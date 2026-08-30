-- Construction radar, server side: stamps every built object with
-- builder and time (modData.aegisBuild = "name|epoch", legacy key aegisBau
-- still read) and keeps a
-- daily journal of all build and demolish events under Aegis/Construction/.
-- All three hooks run on the dedi AND in solo at the same place:
-- buildUtil.setInfo is called by the server build path (Actions.build) or in solo
-- by ISBuildAction:perform, and timed actions with complete()
-- are executed by the MP server itself (NetTimedAction rebuilds the action
-- with a real IsoPlayer), MP clients never call Lua complete.
if isClient() then return end

require "BuildingObjects/ISBuildUtil"
require "BuildingObjects/ISBuildIsoEntity"
require "Moveables/ISMoveablesAction"
require "TimedActions/ISDestroyStuffAction"
require "TimedActions/ISSmashWindow"
require "Vehicles/TimedActions/ISHotwireVehicle"
require "Aegis_Store"
require "Aegis_Roles"
require "Aegis_Moderation"
require "Aegis_Log"

local function toClient(player, command, args)
    if isServer() then
        sendServerCommand(player, AegisShared.MODULE, command, args)
    else
        triggerEvent("OnServerCommand", AegisShared.MODULE, command, args)
    end
end

local function deny(player)
    toClient(player, "denied", { area = "tools" })
end

-- ---------- Stamp and journal ----------
local function playerName(chr)
    if not chr or not instanceof(chr, "IsoPlayer") then return nil end
    local name = chr:getUsername()
    if type(name) == "string" and name ~= "" then return name end
    return nil
end

local function timestamp(obj, name)
    obj:getModData().aegisBuild = tostring(name):gsub("|", "_") .. "|" .. tostring(AegisShared.realTime())
end

local function spriteName(obj)
    local spr = obj:getSprite()
    if spr then return spr:getName() end
    return nil
end

-- Line format: time|user|action|x,y,z|sprite|kind|north|parts
-- kind/north are only meaningful for "abriss" entries (what to rebuild
-- with on restore); trailing fields are optional so old lines still
-- parse. parts carries multi-tile structures (stairs, garage doors,
-- double doors) as "x,y,z,sprite,north,floor;..." so one restore click
-- rebuilds the whole thing
local function journal(name, action, x, y, z, sprite, kind, north, parts)
    local now = AegisShared.realTime()
    local path = AegisStore.ROOT .. "/Construction/" .. AegisShared.dateShort(now) .. ".txt"
    AegisStore.append(path, table.concat({
        AegisShared.timeShort(now),
        tostring(name):gsub("|", "_"),
        action,
        tostring(x) .. "," .. tostring(y) .. "," .. tostring(z),
        tostring(sprite or "?"):gsub("|", "_"),
        tostring(kind or ""),
        north and "1" or "",
        tostring(parts or ""),
    }, "|"))
end

local function serializeParts(list)
    local out = {}
    for _, p in ipairs(list) do
        table.insert(out, table.concat({
            tostring(p.x), tostring(p.y), tostring(p.z),
            tostring(p.sprite):gsub("[|;,]", "_"),
            p.north and "1" or "0",
            p.floor and "1" or "0",
        }, ","))
    end
    return table.concat(out, ";")
end

local function objectKind(obj)
    -- stairs are a scripted multi-tile structure (server/BuildingObjects/
    -- ISWoodenStairs.lua), not a single sprite on one square; restoring
    -- one as a plain object stacked one fake tile on top of the real
    -- remaining steps.
    -- Flag it so restore can refuse cleanly instead of faking a result
    if obj:isStairsObject() then return "stairs" end
    -- garage doors are a LINKED CHAIN of IsoDoor pieces (engine statics
    -- getGarageDoorNext/Prev, destroyGarageDoor tears down the whole
    -- chain in one action); same problem as stairs, one tile came back
    -- while the rest of the door stayed missing
    if instanceof(obj, "IsoDoor") then
        local isGarage = false
        -- static helper, it wants a real door; guarded for the same
        -- reason as objectNorth below
        pcall(function()
            if instanceof(obj, "IsoDoor") then
                isGarage = IsoDoor.getGarageDoorIndex(obj) >= 0
            end
        end)
        if isGarage then return "garage" end
        return "door"
    end
    if instanceof(obj, "IsoWindow") then return "window" end
    if instanceof(obj, "IsoWindowFrame") then return "windowframe" end
    if instanceof(obj, "IsoThumpable") then return "wall" end
    return "object"
end

-- only doors, windows, window frames and thumpables declare getNorth
-- (bytecode: IsoObject itself does not). Calling it on a plain object
-- throws a Java exception that travels THROUGH pcall and kills the whole
-- action handler, so the type is checked first (live crash on a server)
local function objectNorth(obj)
    local hasNorth = instanceof(obj, "IsoDoor") or instanceof(obj, "IsoWindow")
        or instanceof(obj, "IsoWindowFrame") or instanceof(obj, "IsoThumpable")
    if not hasNorth then return false end
    local north = false
    pcall(function() north = obj:getNorth() == true end)
    return north
end

local function journalObject(name, action, obj, sprite, kind)
    local sq = obj:getSquare()
    if not sq then return end
    journal(name, action, sq:getX(), sq:getY(), sq:getZ(), sprite or spriteName(obj),
        kind or objectKind(obj), objectNorth(obj))
end

-- multi-tile structures: the vanilla destroy removes the WHOLE thing in
-- one action via these buildUtil helpers (shared/TimedActions/
-- ISDestroyStuffAction.lua:238-241), so the journal must capture every
-- piece the same way, otherwise the restore can only fake the anchor
-- tile
local function structureParts(obj)
    local result = nil
    pcall(function()
        local list = buildUtil.getStairObjects(obj)
        local kind = "stairs"
        if #list == 0 then
            list = buildUtil.getDoubleDoorObjects(obj)
            kind = "multi"
        end
        if #list == 0 then
            list = buildUtil.getGarageDoorObjects(obj)
            kind = "garage"
        end
        if #list == 0 then return end
        local parts = {}
        for _, o in ipairs(list) do
            local sq = o:getSquare()
            local spr = spriteName(o)
            if sq and spr then
                local isFloor = false
                pcall(function()
                    isFloor = o:getSprite():getProperties():has(IsoFlagType.solidfloor) == true
                end)
                table.insert(parts, {
                    x = sq:getX(), y = sq:getY(), z = sq:getZ(),
                    sprite = spr, north = objectNorth(o), floor = isFloor,
                })
            end
        end
        if #parts > 0 then
            result = { kind = kind, parts = parts }
        end
    end)
    return result
end

-- ---------- Hook 1: building (IsoThumpable) ----------
-- Original first: setInfo overwrites modData via setModData(copyTable),
-- an earlier stamp would be gone. Set afterwards, the stamp travels to all
-- clients automatically in the complete-item packet (setInfo runs before
-- AddSpecialObject and transmitCompleteItemToClients).
if not buildUtil.aegisBuild then
    buildUtil.aegisBuild = true

    local origSetInfo = buildUtil.setInfo
    buildUtil.setInfo = function(javaObject, item)
        origSetInfo(javaObject, item)
        local name = playerName(item and item.character)
        if name then
            timestamp(javaObject, name)
            journalObject(name, "bau", javaObject, nil)
        end
    end

    -- Auto corners skip setInfo: find the fresh corner thumpable on the
    -- target square after the original and stamp it. The packet is already
    -- out by then, hence transmitModData. No journal entry, the corner is
    -- a technical byproduct of the wall build.
    local origAddCorner = buildUtil.addCorner
    buildUtil.addCorner = function(x, y, z, thumpable, item)
        origAddCorner(x, y, z, thumpable, item)
        local name = playerName(item and item.character)
        if not name or not (item and item.corner) then return end
        pcall(function()
            local sq = getCell():getGridSquare(x, y, z)
            if not sq then return end
            local objects = sq:getSpecialObjects()
            for i = 0, objects:size() - 1 do
                local obj = objects:get(i)
                if instanceof(obj, "IsoThumpable") and spriteName(obj) == item.corner
                    and (not obj:hasModData()
                        or not (obj:getModData().aegisBuild or obj:getModData().aegisBau)) then
                    timestamp(obj, name)
                    obj:transmitModData()
                    break
                end
            end
        end)
    end
end

-- ---------- Build cheat: material consumption on the dedicated server ----------
-- Vanilla bug (source verified, server/BuildingObjects/ISBuildUtil.lua
-- consumeMaterial): the consumption bypass reads "if not isServer() and
-- ISBuildMenu.cheat then return {} end". isServer() is ALWAYS true on a
-- real dedicated server, so the condition is structurally unreachable there,
-- no matter how ISBuildMenu.cheat is set. haveMaterial() (the check that
-- enables the build button) respects isBuildCheat() correctly, but the
-- actual consumption on finished builds does not, so the build cheat on the
-- powers page only half worked.
-- Wrap adds the same bypass keyed on the character cheat flag, independent
-- of isServer().
if not buildUtil.aegisMaterial then
    buildUtil.aegisMaterial = true

    local origConsume = buildUtil.consumeMaterial
    buildUtil.consumeMaterial = function(isItem)
        local cheat = false
        pcall(function()
            if not isItem or not isItem.player then return end
            -- exact same resolution as the original: isItem.player is
            -- already a live object on the server, otherwise an ID
            local players = isItem.player
            if not isServer() then
                players = getSpecificPlayer(isItem.player)
            end
            cheat = players ~= nil and players:isBuildCheat() == true
        end)
        if cheat then return {} end
        return origConsume(isItem)
    end
end

-- shared helper for hook 1b and hook 2: placeMoveableInternal fires
-- OnObjectAdded synchronously per part, only objects near the target square
-- count so no unrelated object falls into the trap
local function matchesTarget(obj, target)
    if not target then return false end
    local sq = obj:getSquare()
    if not sq then return false end
    return sq:getZ() == target:getZ()
        and math.abs(sq:getX() - target:getX()) <= 4
        and math.abs(sq:getY() - target:getY()) <= 4
end

-- ---------- Hook 1b: build objects with script isProp() ----------
-- ISBuildIsoEntity:setInfo bails out for prop objects BEFORE buildUtil.setInfo
-- and builds directly via ISMoveableSpriteProps:placeMoveableInternal instead
-- (vanilla evidence ISBuildIsoEntity.lua:591-598), hook 1 never sees this path.
-- placeMoveableInternal fires the same OnObjectAdded events as the furniture
-- placement in hook 2, so the same capture technique applies.
if not ISBuildIsoEntity.aegisBuildProp then
    ISBuildIsoEntity.aegisBuildProp = true

    local origSetInfoEntity = ISBuildIsoEntity.setInfo
    function ISBuildIsoEntity:setInfo(square, north, sprite, openSprite)
        local isProp = false
        pcall(function() isProp = self.objectInfo:getScript():isProp() end)
        local name = isProp and playerName(self.character) or nil
        if not name then
            return origSetInfoEntity(self, square, north, sprite, openSprite)
        end
        local caught = {}
        local catcher = function(obj) table.insert(caught, obj) end
        Events.OnObjectAdded.Add(catcher)
        local ok, result = pcall(function() return origSetInfoEntity(self, square, north, sprite, openSprite) end)
        Events.OnObjectAdded.Remove(catcher)
        for _, obj in ipairs(caught) do
            if matchesTarget(obj, square) then
                timestamp(obj, name)
                pcall(function() obj:transmitModData() end)
            end
        end
        if not ok then error(result) end
        if #caught > 0 and square then
            journal(name, "bau", square:getX(), square:getY(), square:getZ(), sprite)
        end
        return result
    end
end

-- ---------- Hook 2: furniture (place, pick up, scrap) ----------
if not ISMoveablesAction.aegisBuild then
    ISMoveablesAction.aegisBuild = true

    local origComplete = ISMoveablesAction.complete
    function ISMoveablesAction:complete()
        local name = playerName(self.character)
        if not name then return origComplete(self) end

        if (self.mode == "pickup" or self.mode == "scrap") and self.object then
            -- before the original: the object is still in the world
            journalObject(name, "abriss", self.object, self.origSpriteName)
            return origComplete(self)
        end

        if self.mode == "place" then
            local caught = {}
            local catcher = function(obj) table.insert(caught, obj) end
            Events.OnObjectAdded.Add(catcher)
            local ok, result = pcall(function() return origComplete(self) end)
            Events.OnObjectAdded.Remove(catcher)
            for _, obj in ipairs(caught) do
                if matchesTarget(obj, self.square) then
                    timestamp(obj, name)
                    -- the object packet is already out on return,
                    -- the stamp must travel on its own
                    pcall(function() obj:transmitModData() end)
                end
            end
            if not ok then error(result) end
            -- journal only if something was actually caught, otherwise the
            -- journal would show a build entry for a failed placement
            -- (e.g. item already gone or target square occupied)
            if self.square and #caught > 0 then
                journal(name, "bau", self.square:getX(), self.square:getY(),
                    self.square:getZ(), self.origSpriteName)
            end
            return result
        end

        return origComplete(self)
    end
end

-- ---------- Hook 3: demolition (sledgehammer) ----------
if not ISDestroyStuffAction.aegisBuild then
    ISDestroyStuffAction.aegisBuild = true

    local origDestroy = ISDestroyStuffAction.complete
    function ISDestroyStuffAction:complete()
        local name = playerName(self.character)
        if name and self.item then
            -- before the original: square and sprite of the victim still
            -- readable, and for multi-tile structures the whole set of
            -- pieces is still standing to be captured
            local group = structureParts(self.item)
            if group then
                local sq = self.item:getSquare()
                if sq then
                    journal(name, "abriss", sq:getX(), sq:getY(), sq:getZ(),
                        spriteName(self.item), group.kind, objectNorth(self.item),
                        serializeParts(group.parts))
                end
            else
                journalObject(name, "abriss", self.item, nil)
            end
        end
        return origDestroy(self)
    end
end

-- ---------- Hook 4: window smashing and hotwiring ----------
-- Community request for an activity trail beyond building. These two are
-- the only ones of the four asked for that have a single clean hook:
-- setting buildings on fire has no scripted player action in B42 at all,
-- and loot cycling only surfaces as OnFillContainer, which carries no
-- player reference. Both measured, neither guessed.
-- These write into the player's own session file, NOT a new log area
--.
local function activity(chr, text)
    local name = playerName(chr)
    if not name then return end
    local sq = chr:getSquare()
    if sq then
        text = text .. " at " .. sq:getX() .. "," .. sq:getY() .. "," .. sq:getZ()
    end
    AegisLog.playerActivity(name, text)
end

-- readable name of a vehicle for a log line. The translated name is what
-- the admin sees everywhere else in the panel, the script name is the
-- fallback so a modded vehicle without a translation still says something
local function vehicleLabel(veh)
    local script = veh and veh:getScript()
    if not script then return "vehicle" end
    local key = script:getName()
    return getTextOrNull("IGUI_VehicleName" .. key) or key
end

if ISSmashWindow and not ISSmashWindow.aegisActivity then
    ISSmashWindow.aegisActivity = true
    local origSmash = ISSmashWindow.complete
    function ISSmashWindow:complete()
        -- vehiclePart tells the two apart, vanilla branches on the same
        -- field (shared/TimedActions/ISSmashWindow.lua)
        pcall(function()
            if self.vehiclePart == nil then
                activity(self.character, "Smashed a window")
                return
            end
            -- name the car and the window, a bare coordinate did not say
            -- whose vehicle it was
            local veh = self.vehiclePart:getVehicle()
            local part = self.vehiclePart:getId()
            local text = "Smashed the window of a " .. vehicleLabel(veh)
            if part and part ~= "" then text = text .. " (" .. tostring(part) .. ")" end
            activity(self.character, text)
        end)
        return origSmash(self)
    end
end

if ISHotwireVehicle and not ISHotwireVehicle.aegisActivity then
    ISHotwireVehicle.aegisActivity = true
    local origHotwire = ISHotwireVehicle.complete
    function ISHotwireVehicle:complete()
        local result = origHotwire(self)
        -- after the original: tryHotwire returns nothing, the engine state
        -- afterwards is the only readable outcome
        pcall(function()
            local veh = self.character:getVehicle()
            local ok = veh and veh:isHotwired() == true
            activity(self.character, (ok and "Hotwired a " or "Tried to hotwire a ") .. vehicleLabel(veh))
        end)
        return result
    end
end

-- ---------- Restore (rebuild a demolished piece from its log entry) ----------
-- Same primitives as the build brush (Aegis_Builder.lua): floors replace
-- whatever is on the square, walls/fences are a fresh IsoThumpable, any
-- other sprite (furniture, props) goes back as a plain IsoObject on top
-- of the stack. No undo tracking: a restored piece is a normal built
-- object afterwards, removable again like any other.
local function restoreFloor(cell, sq, sprite)
    local floor = sq:getFloor()
    if floor then
        pcall(function() sq:transmitRemoveItemFromSquare(floor, false) end)
    end
    local obj = IsoObject.new(cell, sq, sprite)
    sq:transmitAddObjectToSquare(obj, 0)
    return obj
end

local function restoreObject(cell, sq, sprite)
    local obj = IsoObject.new(cell, sq, sprite)
    sq:transmitAddObjectToSquare(obj, sq:getObjects():size())
    return obj
end

local function restoreWall(cell, sq, sprite, north, name)
    local obj = IsoThumpable.new(cell, sq, sprite, north, {})
    obj:setMaxHealth(400)
    obj:setHealth(400)
    timestamp(obj, name)
    sq:AddSpecialObject(obj)
    if isServer() then pcall(function() obj:transmitCompleteItemToClients() end) end
    triggerEvent("OnObjectAdded", obj)
    return obj
end

-- doors and windows are NOT IsoThumpable (vanilla evidence,
-- ISMoveableSpriteProps.lua:2186-2196: the build system reads the
-- sprite's own tile properties to pick IsoDoor/IsoWindow/IsoWindowFrame
-- vs a plain wall thumpable). Restoring every demolished piece as a
-- generic object or thumpable produced doors with no collision at all
--. Ask the sprite itself,
-- exactly like the vanilla placer does, instead of guessing from the
-- coarse wall/object split stored in the log
local function restoreDoor(cell, sq, sprite, north, name)
    local obj = IsoDoor.new(cell, sq, sprite, north, {})
    timestamp(obj, name)
    sq:AddSpecialObject(obj)
    if isServer() then pcall(function() obj:transmitCompleteItemToClients() end) end
    triggerEvent("OnObjectAdded", obj)
    return obj
end

local function restoreWindow(cell, sq, sprite, north, name)
    local obj = IsoWindow.new(cell, sq, getSprite(sprite), north)
    obj:setIsLocked(false)
    timestamp(obj, name)
    sq:AddSpecialObject(obj)
    if isServer() then pcall(function() obj:transmitCompleteItemToClients() end) end
    triggerEvent("OnObjectAdded", obj)
    return obj
end

local function restoreWindowFrame(cell, sq, sprite, north, name)
    local obj = IsoWindowFrame.new(cell, sq, getSprite(sprite), north)
    timestamp(obj, name)
    sq:AddSpecialObject(obj)
    if isServer() then pcall(function() obj:transmitCompleteItemToClients() end) end
    triggerEvent("OnObjectAdded", obj)
    return obj
end

-- the ground truth for "what kind of piece is this sprite" always sits
-- on the sprite's own tile properties, not in whatever the log happened
-- to record; this overrides a stale/coarse stored kind whenever it can
local function kindFromSprite(spriteName)
    local ok, kind, north = pcall(function()
        local spr = getSprite(spriteName)
        local props = spr and spr:getProperties()
        if not props then return nil, nil end
        if props:has(IsoFlagType.doorN) or props:has(IsoFlagType.doorW) then
            return "door", props:has(IsoFlagType.doorN)
        elseif props:has(IsoFlagType.WallN) or props:has(IsoFlagType.WallW) then
            return "wall", props:has(IsoFlagType.WallN)
        elseif props:has(IsoFlagType.windowN) or props:has(IsoFlagType.windowW) then
            return "window", props:has(IsoFlagType.windowN)
        elseif props:has(IsoFlagType.WindowN) or props:has(IsoFlagType.WindowW) then
            return "windowframe", props:has(IsoFlagType.WindowN)
        end
        return nil, nil
    end)
    if not ok then return nil, nil end
    return kind, north
end

-- ---------- Commands ----------
local MAX_LINES = 200

-- cap file reads per player at 1/s, same as the protocol fetch
local lastRequest = {}
local function throttled(player)
    local name = player and player:getUsername() or "?"
    local now = AegisShared.realTime()
    if lastRequest[name] and now - lastRequest[name] < 1 then return true end
    lastRequest[name] = now
    return false
end

local Commands = {}

-- last entries of a day, date optional (defaults to today)
Commands.constructionList = function(player, args)
    if not AegisRoles.canArea(player, "tools") then deny(player) return end
    if throttled(player) then return end
    local date = args and type(args.date) == "string"
        and args.date:match("^%d%d%d%d%-%d%d%-%d%d$") or nil
    if not date then date = AegisShared.dateShort(AegisShared.realTime()) end
    local n = math.floor(tonumber(args and args.n) or 100)
    if n < 1 then n = 1 end
    if n > MAX_LINES then n = MAX_LINES end
    local path = AegisStore.ROOT .. "/Construction/" .. date .. ".txt"
    local lines, more = AegisStore.readLastLines(path, n)
    toClient(player, "constructionList", { date = date, lines = lines or {}, more = more == true })
end

-- rebuild a demolished piece at its logged position; same permission bar
-- as the build brush (tools area plus the brush tool capability)
Commands.constructionRestore = function(player, args)
    -- the tools area right is the whole gate, same
    -- as the build brush. The former extra bar demanded access level
    -- exactly "admin" and refused everyone else without a visible reason
    if not AegisRoles.canArea(player, "tools") then deny(player) return end
    if not args or type(args.sprite) ~= "string" or args.sprite == "" then
        toClient(player, "constructionRestore", { ok = false })
        return
    end
    local x = math.floor(tonumber(args.x) or 0)
    local y = math.floor(tonumber(args.y) or 0)
    local z = math.floor(tonumber(args.z) or 0)
    local sq = getCell():getGridSquare(x, y, z)
    if not sq then
        toClient(player, "constructionRestore", { ok = false })
        return
    end
    local cell = getCell()
    local name = player:getUsername()

    -- one piece, dispatched by the sprite's own tile properties (the
    -- ground truth for door/wall/window/window frame); returns the
    -- object or nil. Shared by the single path and the multi-tile loop
    local function rebuildPiece(psq, sprite, storedKind, storedNorth, isFloorPiece)
        local kind = storedKind
        local north = storedNorth == true
        local spriteKind, spriteNorth = kindFromSprite(sprite)
        if spriteKind then
            kind = spriteKind
            if spriteNorth ~= nil then north = spriteNorth end
        end
        if isFloorPiece then kind = "floor" end
        local okBuild, obj = pcall(function()
            if kind == "door" then
                return restoreDoor(cell, psq, sprite, north, name)
            elseif kind == "window" then
                return restoreWindow(cell, psq, sprite, north, name)
            elseif kind == "windowframe" then
                return restoreWindowFrame(cell, psq, sprite, north, name)
            elseif kind == "wall" then
                return restoreWall(cell, psq, sprite, north, name)
            elseif kind == "floor" then
                return restoreFloor(cell, psq, sprite)
            end
            return restoreObject(cell, psq, sprite)
        end)
        if not okBuild or not obj then return nil end
        if kind ~= "wall" and kind ~= "door" and kind ~= "window" and kind ~= "windowframe" then
            timestamp(obj, name)
            pcall(function() obj:transmitModData() end)
        end
        psq:RecalcProperties()
        return obj
    end

    -- multi-tile structure (stairs, garage door, double door): rebuild
    -- every captured piece, one click restores the whole thing
    local parts = args.parts
    if type(parts) == "table" and #parts > 0 then
        if #parts > 16 then
            toClient(player, "constructionRestore", { ok = false })
            return
        end
        local builtCount, failedCount = 0, 0
        for _, p in ipairs(parts) do
            local px = math.floor(tonumber(p.x) or 0)
            local py = math.floor(tonumber(p.y) or 0)
            local pz = math.floor(tonumber(p.z) or 0)
            local psq = getCell():getGridSquare(px, py, pz)
            local sprite = type(p.sprite) == "string" and p.sprite or ""
            if psq and sprite ~= "" then
                if rebuildPiece(psq, sprite, nil, p.north == true, p.floor == true) then
                    builtCount = builtCount + 1
                else
                    failedCount = failedCount + 1
                end
            else
                failedCount = failedCount + 1
            end
        end
        if builtCount == 0 then
            toClient(player, "constructionRestore", { ok = false })
            return
        end
        journal(name, "bau", x, y, z, args.sprite, args.kind, args.north == true)
        AegisLog.write("Actions", name, name, string.format(
            "Restored structure %s at %d,%d,%d (%d pieces, %d failed)",
            tostring(args.sprite), x, y, z, builtCount, failedCount))
        toClient(player, "constructionRestore", { ok = true, x = x, y = y, z = z })
        return
    end

    -- legacy multi-tile log lines from before the parts capture carry no
    -- piece list, those still get the honest refusal
    if args.kind == "stairs" or args.kind == "garage" or args.kind == "multi" then
        toClient(player, "constructionRestore", { ok = false, reason = "stairs" })
        return
    end

    local obj = rebuildPiece(sq, args.sprite, args.kind, args.north == true, args.kind == "floor")
    if not obj then
        toClient(player, "constructionRestore", { ok = false })
        return
    end
    journal(name, "bau", x, y, z, args.sprite, args.kind, args.north == true)
    AegisLog.write("Actions", name, name, string.format("Restored %s at %d,%d,%d", tostring(args.sprite), x, y, z))
    toClient(player, "constructionRestore", { ok = true, x = x, y = y, z = z })
end

Events.OnClientCommand.Add(function(module, command, player, args)
    if module ~= AegisShared.MODULE then return end
    -- suspended admins may not use any Aegis area
    if AegisModeration.isSuspended(player) then return end
    if Commands[command] then Commands[command](player, args) end
end)
