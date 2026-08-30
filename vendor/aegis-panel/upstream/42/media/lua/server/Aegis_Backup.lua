-- Zone backup: snapshots of complete safehouse zones (main plus annexes
-- from the group registry) as pipe lines in the Aegis store, plus the
-- restore of the saved build state. Both run in slices over OnTick:
-- saving only reads (250 columns per tick), restoring is expensive
-- (recalc plus packets per object, hence 32 squares per tick).
-- Once per day the watcher backs up all zones with a group registration.
-- Whatever v1 cannot rebuild (devices, generators, mannequins, corpses,
-- curtains, fluid containers, floor loot, trees) is left standing on
-- restore and only appears in the snapshot as an X line.
if isClient() then return end

require "Aegis_Zones"
require "Aegis_Log"
require "Aegis_Moderation"

local SNAP_BUDGET = 250    -- columns per tick while saving
local REST_BUDGET = 32     -- squares per tick while restoring
local Z_MIN, Z_MAX = -8, 7 -- basement to top floor, no base needs more
local MAX_COLUMNS = 90000
local MAX_LINES = 400000
local MAX_QUEUED = 64
local MAX_REPLY = 60
local STATUS_FILE = AegisStore.ROOT .. "/Status/backup.txt"
local INTERVAL = 20 * 3600

local function toClient(player, command, args)
    if isServer() then
        sendServerCommand(player, AegisShared.MODULE, command, args)
    else
        triggerEvent("OnServerCommand", AegisShared.MODULE, command, args)
    end
end

-- B42 has no ManageSafehouses capability, only the Aegis area
-- permission "zones" counts
local function allowed(player)
    if not AegisRoles.canArea(player, "zones") then
        if isServer() then
            sendServerCommand(player, "AegisAdmin", "denied", { area = "zones" })
        end
        return false
    end
    return true
end

-- manifest key of a zone, deliberately tied only to the anchor of the main
-- safehouse (survives owner and title changes, but not relocation)
local function zoneKey(hx, hy)
    return "Zone_" .. math.floor(hx) .. "_" .. math.floor(hy)
end

local function findSafehouse(x, y)
    local list = SafeHouse.getSafehouseList()
    for i = 0, list:size() - 1 do
        local sh = list:get(i)
        if sh:getX() == x and sh:getY() == y then
            return sh
        end
    end
    return nil
end

local function zoneTitle(hx, hy)
    local sh = findSafehouse(hx, hy)
    if not sh then return nil end
    local title = sh:getTitle() or ""
    if title == "" then title = sh:getOwner() or "" end
    return title ~= "" and title or nil
end

-- ---------- line format ----------
-- pipe separates fields, so pipe, backslash and newline get escaped in
-- free text (names, modData, item types)
local function esc(s)
    s = tostring(s or "")
    s = s:gsub("\\", "\\\\"):gsub("|", "\\p"):gsub("\r", ""):gsub("\n", "\\n")
    return s
end

local function unesc(s)
    s = tostring(s or "")
    if not s:find("\\", 1, true) then return s end
    local parts = {}
    local i = 1
    while i <= #s do
        local c = s:sub(i, i)
        if c == "\\" and i < #s then
            local d = s:sub(i + 1, i + 1)
            if d == "p" then
                table.insert(parts, "|")
            elseif d == "n" then
                table.insert(parts, "\n")
            else
                table.insert(parts, d)
            end
            i = i + 2
        else
            table.insert(parts, c)
            i = i + 1
        end
    end
    return table.concat(parts)
end

local function splitLine(line)
    local tiles = {}
    local start = 1
    while true do
        local p = line:find("|", start, true)
        if not p then
            table.insert(tiles, line:sub(start))
            break
        end
        table.insert(tiles, line:sub(start, p - 1))
        start = p + 1
    end
    return tiles
end

local function b01(v) return v and "1" or "0" end
local function intStr(v) return tostring(math.floor(tonumber(v) or 0)) end
local function floatStr(v) return string.format("%.4f", tonumber(v) or 0) end

-- ---------- skip list ----------
-- the same check decides on save (X line only) and on restore (leave
-- standing), otherwise duplicates appear. Devices would lose their logic
-- as a bare IsoObject, so they stay untouched
local DEVICES = {
    "IsoGenerator", "IsoMannequin", "IsoDeadBody", "IsoCurtain",
    "IsoStove", "IsoFireplace", "IsoBarbecue", "IsoTelevision", "IsoRadio",
    "IsoWaveSignal", "IsoLightSwitch", "IsoCombinationWasherDryer",
    "IsoClothingDryer", "IsoClothingWasher", "IsoCompost", "IsoTree",
}

local function untouchable(obj)
    if instanceof(obj, "IsoWorldInventoryObject") then return "Bodenloot" end
    if instanceof(obj, "IsoBarricade") then return "Barrikade" end
    for _, cls in ipairs(DEVICES) do
        if instanceof(obj, cls) then return cls end
    end
    if obj:hasFluid() then return "FluidContainer" end
    return nil
end

-- ---------- save: object to line ----------
local function spriteOf(obj)
    return obj:getSpriteName() or ""
end

local function northOf(obj)
    -- IsoObject has no getNorth, only doors, windows, window frames and
    -- thumpables do
    local hasNorth = instanceof(obj, "IsoDoor") or instanceof(obj, "IsoWindow")
        or instanceof(obj, "IsoWindowFrame") or instanceof(obj, "IsoThumpable")
    if not hasNorth then return false end
    return obj:getNorth() == true
end

local itemLines
itemLines = function(lines, cont, depth)
    local items = cont:getItems()
    for i = 0, items:size() - 1 do
        local it = items:get(i)
        if it then
            local cond = intStr(it:getCondition())
            local condMax = intStr(it:getConditionMax())
            local uses, floatUses = "", ""
            pcall(function() uses = intStr(it:getCurrentUses()) end)
            if instanceof(it, "DrainableComboItem") then
                pcall(function() floatUses = floatStr(it:getCurrentUsesFloat()) end)
            end
            table.insert(lines, "I|" .. depth .. "|" .. esc(it:getFullType())
                .. "|" .. cond .. "|" .. condMax .. "|" .. uses .. "|" .. floatUses)
            if depth < 3 and instanceof(it, "InventoryContainer") then
                local inner = it:getInventory()
                if inner then itemLines(lines, inner, depth + 1) end
            end
        end
    end
end

local function saveContainers(lines, obj)
    for ci = 0, obj:getContainerCount() - 1 do
        local cont = obj:getContainerByIndex(ci)
        if cont then
            local type = cont:getType() or ""
            local explored = cont:isExplored()
            table.insert(lines, "C|" .. ci .. "|" .. esc(type) .. "||" .. b01(explored))
            itemLines(lines, cont, 0)
        end
    end
end

local function saveModData(lines, obj)
    if not obj:hasModData() then return end
    for k, v in pairs(obj:getModData()) do
        local t = type(v)
        if type(k) == "string" then
            if t == "string" then
                table.insert(lines, "M|" .. esc(k) .. "|s|" .. esc(v))
            elseif t == "number" then
                table.insert(lines, "M|" .. esc(k) .. "|n|" .. floatStr(v))
            elseif t == "boolean" then
                table.insert(lines, "M|" .. esc(k) .. "|b|" .. b01(v))
            end
        end
    end
end

local function saveBarricades(lines, obj)
    local function one(b, side)
        if not b then return end
        local type = "plank"
        if b:isMetal() then
            type = "metal"
        elseif b:isMetalBar() then
            type = "metalbar"
        end
        table.insert(lines, "B|" .. side .. "|" .. type .. "|" .. intStr(b:getNumPlanks()) .. "|" .. intStr(b:getHealth()))
    end
    one(obj:getBarricadeOnSameSquare(), "same")
    one(obj:getBarricadeOnOppositeSquare(), "opp")
end

-- fields exactly as in the vanilla serializer saveThumpableParameters
local function thumpLine(idx, obj)
    local name = obj:getName() or ""
    local hp = obj:getHealth()
    local maxhp = obj:getMaxHealth()
    local sound = obj:getThumpSound() or ""
    local padlock = obj:canBeLockByPadlock()
    local keyId, code = "", ""
    if obj:isLockedByPadlock() and obj:getKeyId() ~= -1 then keyId = intStr(obj:getKeyId()) end
    if obj:getLockedByCode() > 0 then code = intStr(obj:getLockedByCode()) end
    local r, g, b, a = "", "", "", ""
    local color = obj:getCustomColor()
    if color then
        r, g, b, a = floatStr(color:getR()), floatStr(color:getG()), floatStr(color:getB()), floatStr(color:getA())
    end
    local lr, lx, ly, ll, lf = "", "", "", "", ""
    if obj:getLightSourceRadius() > 0 then
        lr = intStr(obj:getLightSourceRadius())
        lx = intStr(obj:getLightSourceXOffset())
        ly = intStr(obj:getLightSourceYOffset())
        ll = floatStr(obj:getLifeLeft())
        lf = esc(obj:getLightSourceFuel() or "")
    end
    return "T|" .. idx .. "|" .. esc(spriteOf(obj)) .. "|" .. b01(northOf(obj)) .. "|" .. esc(name)
        .. "|" .. intStr(hp) .. "|" .. intStr(maxhp) .. "|" .. esc(sound) .. "|" .. b01(padlock)
        .. "|" .. keyId .. "|" .. code .. "|" .. r .. "|" .. g .. "|" .. b .. "|" .. a
        .. "|" .. lr .. "|" .. lx .. "|" .. ly .. "|" .. ll .. "|" .. lf
end

local function doorLine(idx, obj)
    local open = obj:IsOpen()
    local locked = obj:isLocked()
    local byKey = obj:isLockedByKey()
    local keyId = obj:getKeyId()
    local hp = obj:getHealth()
    local maxhp = obj:getMaxHealth()
    return "D|" .. idx .. "|" .. esc(spriteOf(obj)) .. "|" .. b01(northOf(obj)) .. "|" .. b01(open)
        .. "|" .. b01(locked) .. "|" .. b01(byKey) .. "|" .. intStr(keyId) .. "|" .. intStr(hp) .. "|" .. intStr(maxhp)
end

local function windowLine(idx, obj)
    local smashed = obj:isSmashed()
    local glass = obj:isGlassRemoved()
    local perma = obj:isPermaLocked()
    local locked = obj:isLocked()
    local open = obj:IsOpen()
    return "W|" .. idx .. "|" .. esc(spriteOf(obj)) .. "|" .. b01(northOf(obj)) .. "|" .. b01(smashed)
        .. "|" .. b01(glass) .. "|" .. b01(perma) .. "|" .. b01(locked) .. "|" .. b01(open)
end

local function saveSquare(job, sq, x, y, z)
    local objects = sq:getObjects()
    local count = objects:size()
    if count == 0 then return end
    local lines = job.lines
    table.insert(lines, "SQ|" .. x .. "|" .. y .. "|" .. z)
    local floor = sq:getFloor()
    for i = 0, count - 1 do
        local obj = objects:get(i)
        if obj then
            if obj == floor then
                table.insert(lines, "F|" .. esc(spriteOf(obj)))
            else
                local reason = untouchable(obj)
                if reason == "Barrikade" then
                    -- travels as a B line on its owning object
                elseif reason then
                    table.insert(lines, "X|" .. i .. "|" .. esc(reason) .. "|" .. esc(spriteOf(obj)))
                    job.skipped = job.skipped + 1
                elseif instanceof(obj, "IsoDoor") then
                    table.insert(lines, doorLine(i, obj))
                    saveBarricades(lines, obj)
                    saveModData(lines, obj)
                    saveContainers(lines, obj)
                elseif instanceof(obj, "IsoWindow") then
                    table.insert(lines, windowLine(i, obj))
                    saveBarricades(lines, obj)
                    saveModData(lines, obj)
                elseif instanceof(obj, "IsoWindowFrame") then
                    table.insert(lines, "WF|" .. i .. "|" .. esc(spriteOf(obj)) .. "|" .. b01(northOf(obj)))
                    saveModData(lines, obj)
                elseif instanceof(obj, "IsoThumpable") then
                    table.insert(lines, thumpLine(i, obj))
                    saveBarricades(lines, obj)
                    saveModData(lines, obj)
                    saveContainers(lines, obj)
                else
                    local sprite = spriteOf(obj)
                    if sprite == "" then
                        table.insert(lines, "X|" .. i .. "|OhneSprite|")
                        job.skipped = job.skipped + 1
                    else
                        table.insert(lines, "O|" .. i .. "|" .. esc(sprite))
                        saveModData(lines, obj)
                        saveContainers(lines, obj)
                    end
                end
            end
        end
    end
    job.tiles = job.tiles + 1
end

-- ---------- restore: line to object ----------
local function buildObject(cell, sq, e)
    local f = e.tiles
    local idx = tonumber(f[2]) or 0
    local sprite = unesc(f[3] or "")
    if sprite == "" then return nil end
    local north = f[4] == "1"
    local obj = nil
    if e.kind == "T" then
        obj = IsoThumpable.new(cell, sq, sprite, north, {})
        local name = unesc(f[5] or "")
        if name ~= "" then obj:setName(name) end
        pcall(function()
            obj:setMaxHealth(tonumber(f[7]) or 100)
            obj:setHealth(tonumber(f[6]) or 100)
        end)
        local sound = unesc(f[8] or "")
        if sound ~= "" then obj:setThumpSound(sound) end
        if f[9] == "1" then obj:setCanBeLockByPadlock(true) end
        if f[10] ~= "" and tonumber(f[10]) then
            pcall(function()
                obj:setLockedByPadlock(true)
                obj:setKeyId(tonumber(f[10]))
            end)
        end
        if f[11] ~= "" and tonumber(f[11]) then
            pcall(function() obj:setLockedByCode(tonumber(f[11])) end)
        end
        if f[12] ~= "" then
            pcall(function()
                obj:setCustomColor(tonumber(f[12]) or 1, tonumber(f[13]) or 1, tonumber(f[14]) or 1, tonumber(f[15]) or 1)
            end)
        end
        if f[16] ~= "" and tonumber(f[16]) then
            local fuel = unesc(f[20] or "")
            pcall(function()
                obj:createLightSource(tonumber(f[16]), tonumber(f[17]) or 0, tonumber(f[18]) or 0, 0, 0, fuel ~= "" and fuel or nil, nil, nil)
                obj:setLifeLeft(tonumber(f[19]) or 0)
                obj:setHaveFuel((tonumber(f[19]) or 0) > 0)
            end)
        end
    elseif e.kind == "D" then
        obj = IsoDoor.new(cell, sq, sprite, north)
        pcall(function()
            obj:setOpen(f[5] == "1")
            obj:setLocked(f[6] == "1")
            obj:setLockedByKey(f[7] == "1")
        end)
        local keyId = tonumber(f[8])
        if keyId and keyId >= 0 then obj:setKeyId(keyId) end
        local hp = tonumber(f[9])
        if hp then obj:setHealth(hp) end
    elseif e.kind == "W" then
        obj = IsoWindow.new(cell, sq, getSprite(sprite), north)
        pcall(function()
            obj:setSmashed(f[5] == "1")
            obj:setGlassRemoved(f[6] == "1")
            obj:setPermaLocked(f[7] == "1")
            -- IsoWindow has no setOpen, only ToggleWindow(character); the
            -- engine always resets locked to false during it, so call it
            -- before setIsLocked instead of after (bytecode verified,
            -- nil as character is safe per the null checks in bytecode)
            if f[9] == "1" then obj:ToggleWindow(nil) end
            obj:setIsLocked(f[8] == "1")
        end)
    elseif e.kind == "WF" then
        obj = IsoWindowFrame.new(cell, sq, getSprite(sprite), north)
    elseif e.kind == "O" then
        obj = IsoObject.new(cell, sq, sprite)
    end
    if not obj then return nil end
    local insertAt = math.min(idx, sq:getObjects():size())
    if e.kind == "O" then
        -- inserts locally via AddTileObject and broadcasts itself
        sq:transmitAddObjectToSquare(obj, insertAt)
    else
        sq:AddSpecialObject(obj, insertAt)
        if isServer() then pcall(function() obj:transmitCompleteItemToClients() end) end
        if isServer() and (e.kind == "D" or e.kind == "W") then
            pcall(function() obj:syncIsoObject(false, 0, nil, nil) end)
        end
        triggerEvent("OnObjectAdded", obj)
    end
    return obj
end

local function applyModData(obj, mods)
    if #mods == 0 then return end
    pcall(function()
        local md = obj:getModData()
        for _, m in ipairs(mods) do
            if m.t == "s" then
                md[m.k] = unesc(m.v)
            elseif m.t == "n" then
                md[m.k] = tonumber(m.v)
            elseif m.t == "b" then
                md[m.k] = m.v == "1"
            end
        end
        obj:transmitModData()
    end)
end

local function restoreBarricades(obj, list)
    for _, b in ipairs(list) do
        pcall(function()
            -- true picks the opposite side per bytecode, verify in testing
            local barricade = IsoBarricade.AddBarricadeToObject(obj, b.side == "opp")
            if barricade then
                if b.type == "metal" then
                    if not barricade:isMetal() then barricade:addMetal(nil, nil) end
                elseif b.type == "metalbar" then
                    if not barricade:isMetalBar() then barricade:addMetalBar(nil, nil) end
                else
                    local missing = (b.planks or 0) - barricade:getNumPlanks()
                    for _ = 1, math.min(missing, 4) do barricade:addPlank(nil, nil) end
                end
                if b.hp and b.hp > 0 then barricade:setHealth(b.hp) end
                if isServer() then barricade:transmitCompleteItemToClients() end
            end
        end)
    end
end

local function countTree(nodes)
    local n = 0
    for _, def in ipairs(nodes) do
        n = n + 1 + (def.children and countTree(def.children) or 0)
    end
    return n
end

local function buildItem(def)
    local it = nil
    pcall(function() it = instanceItem(def.full) end)
    if not it then return nil end
    -- set max first, otherwise the engine setter caps the current value at
    -- the item type default instead of the saved maximum
    if def.condMax ~= "" then pcall(function() it:setConditionMax(tonumber(def.condMax) or 0) end) end
    if def.cond ~= "" then pcall(function() it:setCondition(tonumber(def.cond) or 0) end) end
    if def.usesFloat ~= "" then
        pcall(function() it:setCurrentUsesFloat(tonumber(def.usesFloat) or 0) end)
    elseif def.uses ~= "" then
        pcall(function() it:setCurrentUses(tonumber(def.uses) or 0) end)
    end
    return it
end

-- fill bags on the inside first, then attach them to the parent as ONE
-- item, so the content travels in wire format with the top-level send
local function fillTree(job, target, nodes)
    for _, def in ipairs(nodes) do
        local it = buildItem(def)
        if it then
            if #def.children > 0 then
                local inner = nil
                if instanceof(it, "InventoryContainer") then
                    pcall(function() inner = it:getInventory() end)
                end
                if inner then
                    fillTree(job, inner, def.children)
                else
                    job.lostItems = job.lostItems + countTree(def.children)
                end
            end
            target:AddItem(it)
            def.item = it
        else
            job.lostItems = job.lostItems + 1 + countTree(def.children)
        end
    end
end

-- exact vanilla server pattern: send BEFORE removeAllItems while the items
-- still sit in the container (ClientCommands.lua), then send item by item
local function restoreContainers(job, obj, list)
    for _, c in ipairs(list) do
        local cont = nil
        pcall(function() cont = obj:getContainerByIndex(c.idx) end)
        if cont then
            pcall(function() sendRemoveItemsFromContainer(cont, cont:getItems()) end)
            pcall(function() cont:removeAllItems() end)
            local roots = {}
            local stack = {}
            for _, def in ipairs(c.items) do
                def.children = {}
                local parent = def.depth > 0 and stack[def.depth - 1] or nil
                if def.depth == 0 then
                    table.insert(roots, def)
                    stack[0] = def
                elseif parent then
                    table.insert(parent.children, def)
                    stack[def.depth] = def
                else
                    job.lostItems = job.lostItems + 1
                end
            end
            fillTree(job, cont, roots)
            for _, def in ipairs(roots) do
                if def.item then
                    pcall(function() sendAddItemToContainer(cont, def.item) end)
                end
            end
            if c.explored then pcall(function() cont:setExplored(true) end) end
        else
            job.lostItems = job.lostItems + #c.items
        end
    end
end

-- collect the block of one SQ line: object entries with their attached
-- M, B, C and I lines up to the next SQ or UNGELADEN line
local function parseBlock(lines, pos)
    local header = splitLine(lines[pos])
    local block = {
        x = tonumber(header[2]), y = tonumber(header[3]), z = tonumber(header[4]),
        floorSprite = nil, entries = {},
    }
    pos = pos + 1
    local current = nil
    local cont = nil
    while pos <= #lines do
        local line = lines[pos]
        if line:sub(1, 3) == "SQ|" or line:sub(1, 10) == "UNGELADEN|" then break end
        local f = splitLine(line)
        local kind = f[1]
        if kind == "F" then
            block.floorSprite = unesc(f[2] or "")
            current = nil
            cont = nil
        elseif kind == "T" or kind == "D" or kind == "W" or kind == "WF" or kind == "O" or kind == "X" then
            current = { kind = kind, tiles = f, mods = {}, barricades = {}, container = {} }
            table.insert(block.entries, current)
            cont = nil
        elseif kind == "M" and current then
            table.insert(current.mods, { k = unesc(f[2] or ""), t = f[3], v = f[4] or "" })
        elseif kind == "B" and current then
            table.insert(current.barricades, {
                side = f[2], type = f[3], planks = tonumber(f[4]) or 0, hp = tonumber(f[5]) or 0,
            })
        elseif kind == "C" and current then
            cont = { idx = tonumber(f[2]) or 0, explored = f[5] == "1", items = {} }
            table.insert(current.container, cont)
        elseif kind == "I" and cont then
            table.insert(cont.items, {
                depth = tonumber(f[2]) or 0, full = unesc(f[3] or ""),
                cond = f[4] or "", condMax = f[5] or "", uses = f[6] or "", usesFloat = f[7] or "",
            })
        end
        pos = pos + 1
    end
    return block, pos
end

-- order per square as researched: remove everything restorable in reverse,
-- set a missing floor, re-add snapshot objects ascending with clamped
-- index, finish with one RecalcProperties (RecalcAllWithNeighbours runs
-- internally on every add and remove)
local function restoreSquare(job, block)
    local sq = getSquare(block.x, block.y, block.z)
    if not sq then
        job.notLoaded = job.notLoaded + 1
        return
    end
    local cell = getCell()
    local objects = sq:getObjects()
    local floor = sq:getFloor()
    for i = objects:size() - 1, 0, -1 do
        local obj = objects:get(i)
        if obj and obj ~= floor and not untouchable(obj) then
            pcall(function() sq:transmitRemoveItemFromSquare(obj, false) end)
        end
    end
    if block.floorSprite and block.floorSprite ~= "" and sq:getFloor() == nil then
        pcall(function()
            local newFloor = IsoObject.new(cell, sq, block.floorSprite)
            sq:transmitAddObjectToSquare(newFloor, 0)
        end)
    end
    for _, e in ipairs(block.entries) do
        if e.kind == "X" then
            job.skipped = job.skipped + 1
        else
            local obj = nil
            local ok, res = pcall(buildObject, cell, sq, e)
            if ok then obj = res end
            if obj then
                applyModData(obj, e.mods)
                restoreBarricades(obj, e.barricades)
                restoreContainers(job, obj, e.container)
            else
                job.skipped = job.skipped + 1
            end
        end
    end
    sq:RecalcProperties()
    job.tiles = job.tiles + 1
end

-- ---------- job management ----------
local queue = {}
local active = nil

local function inQueue(kind, key)
    if active and active.kind == kind and active.jobKey == key then return true end
    for _, j in ipairs(queue) do
        if j.kind == kind and j.jobKey == key then return true end
    end
    return false
end

local function reportStatus(job)
    if not job.player then return end
    local now = AegisShared.realTime()
    if job.lastReport and now - job.lastReport < 1 then return end
    job.lastReport = now
    local total = job.kind == "backup" and #job.columns or #job.lines
    local percent = total > 0 and math.floor((job.pos - 1) * 100 / total) or 100
    pcall(function()
        toClient(job.player, "backupStatus", {
            kind = job.kind, percent = math.min(percent, 100), tiles = job.tiles,
            hx = job.hx, hy = job.hy,
        })
    end)
end

local function reportDone(job, ok)
    local text
    if job.kind == "backup" then
        text = string.format("Zone backed up (%s): %d tiles, %d columns not loaded, %d objects skipped",
            job.zoneName, job.tiles, job.notLoaded, job.skipped)
    else
        text = string.format("Zone restored (%s, snapshot %s): %d tiles, %d not loaded, %d objects skipped, %d items lost",
            job.zoneName, AegisShared.timestampReadable(job.snapshotEpoch or 0),
            job.tiles, job.notLoaded, job.skipped, job.lostItems)
    end
    if not ok then text = text .. " [FAILED]" end
    AegisLog.write("Actions", job.adminName, job.jobKey, text)
    if job.player then
        pcall(function()
            toClient(job.player, "backupDone", {
                ok = ok, kind = job.kind, hx = job.hx, hy = job.hy,
                tiles = job.tiles, notLoaded = job.notLoaded,
                skipped = job.skipped, lostItems = job.lostItems,
            })
        end)
    end
end

local function snapshotStep(job)
    local budget = SNAP_BUDGET
    while job.pos <= #job.columns and budget > 0 do
        local sp = job.columns[job.pos]
        job.pos = job.pos + 1
        budget = budget - 1
        if getSquare(sp.x, sp.y, 0) == nil then
            job.notLoaded = job.notLoaded + 1
            table.insert(job.lines, "UNGELADEN|" .. sp.x .. "|" .. sp.y)
        else
            for z = Z_MIN, Z_MAX do
                local sq = getSquare(sp.x, sp.y, z)
                if sq then
                    pcall(saveSquare, job, sq, sp.x, sp.y, z)
                end
            end
        end
    end
    if job.pos > #job.columns then
        local content = table.concat(job.lines, "\n")
        if #job.lines > 0 then content = content .. "\n" end
        local ok = AegisStore.zoneBackup(job.adminName, job.jobKey, content)
        reportDone(job, ok == true)
        return true
    end
    return false
end

local function restoreStep(job)
    local budget = REST_BUDGET
    local lines = job.lines
    while job.pos <= #lines and budget > 0 do
        if lines[job.pos]:sub(1, 3) == "SQ|" then
            budget = budget - 1
            local block, newPos = parseBlock(lines, job.pos)
            job.pos = newPos
            if block.x and block.y and block.z then
                pcall(restoreSquare, job, block)
            end
        else
            job.pos = job.pos + 1
        end
    end
    if job.pos > #lines then
        reportDone(job, true)
        return true
    end
    return false
end

Events.OnTick.Add(function()
    if not active then
        if #queue == 0 then return end
        active = table.remove(queue, 1)
    end
    local step = active.kind == "backup" and snapshotStep or restoreStep
    local ok, finished = pcall(step, active)
    if not ok then
        print("[Aegis] Backup: step failed: " .. tostring(finished))
        reportDone(active, false)
        active = nil
        return
    end
    if finished then
        active = nil
    else
        reportStatus(active)
    end
end)

-- ---------- job creation ----------
local function buildSnapshotJob(hx, hy, adminName, player)
    local sh = findSafehouse(hx, hy)
    if not sh then return nil, "gone" end
    local rects = { { x = sh:getX(), y = sh:getY(), w = sh:getW(), h = sh:getH() } }
    local g = AegisZones.groupFor(hx, hy)
    if g then
        for _, r in ipairs(g.parts) do table.insert(rects, r) end
    end
    local columns = {}
    local seen = {}
    for _, r in ipairs(rects) do
        for x = r.x, r.x + r.w - 1 do
            for y = r.y, r.y + r.h - 1 do
                local key = x .. "," .. y
                if not seen[key] then
                    seen[key] = true
                    table.insert(columns, { x = x, y = y })
                end
            end
        end
    end
    if #columns == 0 or #columns > MAX_COLUMNS then return nil, "data" end
    local key = zoneKey(hx, hy)
    local job = {
        kind = "backup", jobKey = key, zoneName = zoneTitle(hx, hy) or key,
        adminName = adminName, player = player, hx = hx, hy = hy,
        columns = columns, pos = 1, lines = {},
        tiles = 0, notLoaded = 0, skipped = 0, lostItems = 0,
    }
    table.insert(job.lines, "HDR|1|" .. key .. "|" .. intStr(AegisShared.realTime()) .. "|" .. #rects)
    for _, r in ipairs(rects) do
        table.insert(job.lines, "RECT|" .. r.x .. "|" .. r.y .. "|" .. (r.x + r.w - 1) .. "|" .. (r.y + r.h - 1) .. "|0")
    end
    return job
end

-- ---------- commands ----------
-- backupList parses the full zone manifest, so cap at one request per
-- second and player like in Aegis_Log
local lastRequest = {}
local function throttled(player)
    local name = player and player:getUsername() or "?"
    local now = AegisShared.realTime()
    if lastRequest[name] and now - lastRequest[name] < 1 then return true end
    lastRequest[name] = now
    return false
end

local Commands = {}

Commands.backupList = function(player, args)
    if not allowed(player) then return end
    if not args then return end
    local hx, hy = tonumber(args.hx), tonumber(args.hy)
    if not hx or not hy then return end
    if throttled(player) then return end
    local key = zoneKey(hx, hy)
    local entries = AegisStore.readManifest(AegisStore.ZONES_MANIFEST)
    local matching = {}
    for _, e in ipairs(entries) do
        if e.target == key then table.insert(matching, e) end
    end
    table.sort(matching, function(a, b) return a.epoch > b.epoch end)
    local list = {}
    for i = 1, math.min(#matching, MAX_REPLY) do
        local e = matching[i]
        table.insert(list, { epoch = e.epoch, admin = e.admin, path = e.path, status = e.status })
    end
    toClient(player, "backupList", { hx = math.floor(hx), hy = math.floor(hy), entries = list })
end

Commands.backupNow = function(player, args)
    if not allowed(player) then return end
    if not args then return end
    if throttled(player) then return end
    local hx, hy = tonumber(args.hx), tonumber(args.hy)
    if not hx or not hy then return end
    hx, hy = math.floor(hx), math.floor(hy)
    if inQueue("backup", zoneKey(hx, hy)) then
        toClient(player, "backupStart", { ok = false, reason = "running", hx = hx, hy = hy })
        return
    end
    if #queue >= MAX_QUEUED then
        toClient(player, "backupStart", { ok = false, reason = "full", hx = hx, hy = hy })
        return
    end
    local job, reason = buildSnapshotJob(hx, hy, player:getUsername(), player)
    if not job then
        toClient(player, "backupStart", { ok = false, reason = reason, hx = hx, hy = hy })
        return
    end
    table.insert(queue, job)
    toClient(player, "backupStart", { ok = true, kind = "backup", hx = hx, hy = hy })
end

Commands.backupRestore = function(player, args)
    if not allowed(player) then return end
    if not args then return end
    if throttled(player) then return end
    local hx, hy = tonumber(args.hx), tonumber(args.hy)
    local path = args.path
    if not hx or not hy or type(path) ~= "string" or not AegisStore.pathOk(path) then return end
    hx, hy = math.floor(hx), math.floor(hy)
    local key = zoneKey(hx, hy)
    -- only files the zone manifest really assigns to this zone
    local entry = nil
    for _, e in ipairs(AegisStore.readManifest(AegisStore.ZONES_MANIFEST)) do
        if e.path == path and e.target == key then
            entry = e
            break
        end
    end
    if not entry then
        toClient(player, "backupStart", { ok = false, reason = "gone", hx = hx, hy = hy })
        return
    end
    if inQueue("restore", key) then
        toClient(player, "backupStart", { ok = false, reason = "running", hx = hx, hy = hy })
        return
    end
    if #queue >= MAX_QUEUED then
        toClient(player, "backupStart", { ok = false, reason = "full", hx = hx, hy = hy })
        return
    end
    local lines, truncated = AegisStore.readLines(path, MAX_LINES)
    if not lines or #lines == 0 or truncated then
        toClient(player, "backupStart", { ok = false, reason = "file", hx = hx, hy = hy })
        return
    end
    local admin = player:getUsername()
    local job = {
        kind = "restore", jobKey = key,
        zoneName = zoneTitle(hx, hy) or key, adminName = admin,
        player = player, hx = hx, hy = hy,
        lines = lines, pos = 1, snapshotEpoch = entry.epoch,
        tiles = 0, notLoaded = 0, skipped = 0, lostItems = 0,
    }
    table.insert(queue, job)
    AegisLog.write("Actions", admin, key,
        string.format("Zone restore started (%s, snapshot %s)",
            job.zoneName, AegisShared.timestampReadable(entry.epoch)))
    toClient(player, "backupStart", { ok = true, kind = "restore", hx = hx, hy = hy })
end

-- ---------- watcher: daily automation ----------
-- driven by the real clock like Aegis_Retention, EveryTenMinutes is only the beat
local lastRun = nil

local function loadLastRun()
    if lastRun ~= nil then return lastRun end
    lastRun = 0
    local lines = AegisStore.readLines(STATUS_FILE, 2)
    if lines and lines[1] then
        lastRun = tonumber(lines[1]) or 0
    end
    return lastRun
end

local function recordRun(now)
    lastRun = now
    AegisStore.write(STATUS_FILE, tostring(now) .. "\n")
end

local function checkDaily()
    local now = AegisShared.realTime()
    if now <= 0 then return end
    if now - loadLastRun() < INTERVAL then return end
    recordRun(now)
    for _, g in ipairs(AegisZones.allGroups()) do
        if not inQueue("backup", zoneKey(g.hx, g.hy)) and #queue < MAX_QUEUED then
            local job = buildSnapshotJob(g.hx, g.hy, "Server", nil)
            if job then table.insert(queue, job) end
        end
    end
end

Events.EveryTenMinutes.Add(checkDaily)

local function onClientCommand(module, command, player, args)
    if module ~= AegisShared.MODULE then return end
    -- suspended admins may not use any Aegis area
    if AegisModeration.isSuspended(player) then return end
    if Commands[command] then Commands[command](player, args) end
end

Events.OnClientCommand.Add(onClientCommand)
