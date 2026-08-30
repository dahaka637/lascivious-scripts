-- Server side of the Aegis commands. Also runs in-process in solo play,
-- where the capability checks are skipped (the player owns himself).
if isClient() then return end

require "Aegis_Roles"
require "Aegis_Log"
require "Aegis_Moderation"
require "Aegis_Capacity"

-- reply to the caller: over the network in MP, in solo directly to the
-- OnServerCommand listeners of the same process (sendServerCommand is a
-- no-op in singleplayer, triggerEvent reaches the same receivers)
local function toClient(player, command, args)
    if isServer() then
        sendServerCommand(player, AegisShared.MODULE, command, args)
    else
        triggerEvent("OnServerCommand", AegisShared.MODULE, command, args)
    end
end

local function allowed(player, capName)
    if not isServer() then return true end
    local ok, res = pcall(function()
        -- capability read on the stable REGISTRY role resolved from the
        -- access level, not on the flaky per player role wrapper,
        -- which misjudges in both directions. Exact vanilla semantics for
        -- custom staff roles like Owner included; the strict
        -- level == "admin" it replaces denied every other staff level
        local levelOk, level = pcall(function()
            return tostring(player:getAccessLevel() or ""):lower()
        end)
        if levelOk then
            local role = AegisShared.roleForLevel(level)
            if role then
                local capOk, has = pcall(function()
                    local cap = Capability[capName]
                    if cap == nil then return role:hasAdminTool() == true end
                    return role:hasCapability(cap) == true
                end)
                if capOk then return has end
            end
            return AegisShared.levelIsAdmin(level)
        end
        local role = player:getRole()
        return role and role:hasCapability(Capability[capName]) or false
    end)
    return ok and res == true
end

-- Aegis area right plus vanilla capability, every denial goes back visibly;
-- missing capabilities mostly hit non-admins holding an Aegis role
local function permitted(player, capName, area)
    if not AegisRoles.canArea(player, area) then
        print("[Aegis] denied area " .. tostring(area) .. " for " .. tostring(player and player:getUsername()))
        if isServer() then
            sendServerCommand(player, "AegisAdmin", "denied", { area = area })
        end
        return false
    end
    -- an explicit Aegis role already carries the grantor's full intent
    -- for its areas; the vanilla capability gate stays only for the
    -- vanilla-admin fallthrough (the role object drops
    -- capabilities in some sessions and blocked the owner himself)
    local rights = nil
    pcall(function() rights = AegisRoles.effectiveRights(player) end)
    if type(rights) == "table" then return true end
    if not allowed(player, capName) then
        print("[Aegis] denied capability " .. tostring(capName) .. " for " .. tostring(player and player:getUsername()))
        if isServer() then
            sendServerCommand(player, "AegisAdmin", "denied", { area = area, reason = "capability" })
        end
        return false
    end
    return true
end

-- active horde lures: location, range, expiry, initiator as sound source
local lures = {}

local function findByUsername(name)
    local players = getOnlinePlayers()
    if not players then return nil end
    for i = 0, players:size() - 1 do
        local p = players:get(i)
        if p and p:getUsername() == name then return p end
    end
    return nil
end

local function resolveTarget(player, args)
    if args and args.id and args.id >= 0 then
        return getPlayerByOnlineID(args.id)
    elseif args and args.username then
        return findByUsername(args.username)
    end
    return player
end

local Commands = {}

-- full heal, target picked via online ID or username, otherwise the sender
-- himself; self actions from the dashboard need no players right
Commands.heal = function(player, args)
    local area = (args and (args.id or args.username)) and "players" or "dashboard"
    if not permitted(player, "UseHealthCheat", area) then return end
    local target = resolveTarget(player, args)
    if not target then return end
    -- heal the SERVER object too: B42 body damage syncs server to client,
    -- a client-only heal flashed and was overwritten right back with the
    -- old wounds
    pcall(function() AegisShared.fullHeal(target) end)
    if isServer() then
        sendServerCommand(target, "AegisAdmin", "heal", {})
    end
    AegisLog.write("Actions", player:getUsername(), target:getUsername(), "Full heal")
end

-- persistent per-player carry weights: the engine recomputes maxWeight
-- from traits on every login, a live-only set was gone after a restart
--. File lines U|username|value; the minute sweep re-applies
-- to whoever is online and drifted
local CARRY_FILE = AegisStore.ROOT .. "/Status/carryweights.txt"
local carryWeights = nil

local function carryLoad()
    if carryWeights then return end
    carryWeights = {}
    local lines = AegisStore.readLines(CARRY_FILE, 2000)
    for _, line in ipairs(lines or {}) do
        local user, value = line:match("^U|([^|]+)|(%d+)$")
        if user then carryWeights[user] = tonumber(value) end
    end
end

local function carrySave()
    local out = {}
    for user, value in pairs(carryWeights or {}) do
        table.insert(out, "U|" .. user .. "|" .. tostring(value))
    end
    AegisStore.write(CARRY_FILE, table.concat(out, "\n") .. "\n")
end

local function carryApply(target, value)
    pcall(function()
        target:setMaxWeightBase(value)
        target:setMaxWeight(value)
    end)
    if isServer() then
        sendServerCommand(target, "AegisAdmin", "carryWeight", { value = value })
    end
end

-- set max carry weight: applied on server AND target client, persisted
Commands.carryWeight = function(player, args)
    if not permitted(player, "ToggleUnlimitedCarry", "players") then return end
    local value = math.floor(tonumber(args and args.value) or -1)
    -- 0 asks for the reset, everything else must sit inside the range
    if value ~= 0 and (value < 5 or value > 1000) then return end
    local target = resolveTarget(player, args)
    if not target then return end
    carryLoad()
    local user = target:getUsername()
    if value <= 8 then
        -- back to the engine default: forget the entry, and apply the
        -- default itself. Applying the typed value here pinned 5 to 7
        -- as a NEW limit while the ledger already said default
        carryWeights[user] = nil
        carrySave()
        carryApply(target, 8)
        AegisLog.write("Actions", player:getUsername(), user, "Carry weight reset to default")
        return
    end
    carryWeights[user] = value
    carrySave()
    carryApply(target, value)
    AegisLog.write("Actions", player:getUsername(), user, "Carry weight set to " .. value)
end

-- enforcement sweep: re-applies stored values after logins and deaths.
-- Fast cadence on purpose: a player logging in with a heavy pack would
-- collapse under the engine default within a minute
local carryNextSweep = 0
Events.OnTick.Add(function()
    local now = getTimestampMs()
    if now < carryNextSweep then return end
    carryNextSweep = now + 3000
    carryLoad()
    -- Kahlua on the dedicated server has no global next, the sweep
    -- threw every 3 seconds with it
    local empty = true
    for _ in pairs(carryWeights) do
        empty = false
        break
    end
    if empty then return end
    local players = getOnlinePlayers()
    if not players then
        -- solo: only the local player exists
        local p = getPlayer()
        if p then
            local value = carryWeights[p:getUsername() or ""]
            if value and p:getMaxWeight() ~= value then carryApply(p, value) end
        end
        return
    end
    for i = 0, players:size() - 1 do
        local p = players:get(i)
        if p then
            local value = carryWeights[p:getUsername() or ""]
            if value and p:getMaxWeight() ~= value then carryApply(p, value) end
        end
    end
end)

-- reset basic needs, stats are server-authoritative
Commands.care = function(player, args)
    local area = (args and (args.id or args.username)) and "players" or "dashboard"
    if not permitted(player, "UseHealthCheat", area) then return end
    local target = resolveTarget(player, args)
    if not target then return end
    local stats = target:getStats()
    stats:set(CharacterStat.HUNGER, 0)
    stats:set(CharacterStat.THIRST, 0)
    stats:set(CharacterStat.FATIGUE, 0)
    stats:set(CharacterStat.STRESS, 0)
    stats:set(CharacterStat.PANIC, 0)
    stats:set(CharacterStat.BOREDOM, 0)
    stats:set(CharacterStat.ENDURANCE, 1)
    AegisLog.write("Actions", player:getUsername(), target:getUsername(), "Basic needs reset")
end

-- spawn horde: at position or approaching from distance with a lure sound
Commands.horde = function(player, args)
    if not permitted(player, "CreateHorde", "horde") then return end
    if not args then return end
    local count = math.min(tonumber(args.count) or 10, 200)
    local radius = math.max(1, tonumber(args.radius) or 8)
    local crawler = args.crawler == true
    local onFire = args.onFire == true
    local sprinter = args.sprinter == true
    local paratrooper = args.paratrooper == true
    -- heightOffset is no floor number, it is added directly to getZ
    -- (bytecode verified), cap kept low on purpose against bad client
    -- input, matching the slider (1 to 8)
    local heightOffset = paratrooper and math.min(8, math.max(1, tonumber(args.height) or 4)) or 0
    local px = math.floor(tonumber(args.x) or player:getX())
    local py = math.floor(tonumber(args.y) or player:getY())
    local pz = math.floor(tonumber(args.z) or player:getZ())
    local dist = tonumber(args.dist)

    local sx, sy = px, py
    if dist and dist > 0 then
        local a = ZombRand(360) * math.pi / 180
        sx = math.max(0, math.floor(px + math.cos(a) * dist))
        sy = math.max(0, math.floor(py + math.sin(a) * dist))
        radius = math.max(radius, 4)
    end

    -- paratroopers spawn ON THE GROUND server side: the engine heightOffset
    -- fall never reaches the clients in B42 MP (zombies hung
    -- invisible until the old watchdog dropped them). The fall is a pure
    -- client visual now: every client lifts its local copy and lets the
    -- engine fall physics land it (paraFx broadcast below)
    local spawned = 0
    local paraIds = {}
    for i = 1, count do
        local x = ZombRand(sx - radius, sx + radius + 1)
        local y = ZombRand(sy - radius, sy + radius + 1)
        local zeds = addZombiesInOutfit(x, y, pz, 1, nil, 50, crawler and not sprinter,
            false, false, false, false, false, 1, false, 0, false, onFire)
        if zeds then
            spawned = spawned + zeds:size()
            if paratrooper then
                for j = 0, zeds:size() - 1 do
                    local zed = zeds:get(j)
                    if isServer() then
                        table.insert(paraIds, zed:getOnlineID())
                    else
                        -- solo runs in-process: lift directly, the engine
                        -- fall physics land it (proven by the debug UI)
                        zed:setZ(pz + heightOffset)
                        zed:setbFalling(true)
                    end
                end
            end
            if sprinter then
                for j = 0, zeds:size() - 1 do
                    local zed = zeds:get(j)
                    zed:setWalkType("sprint" .. tostring(ZombRand(2) + 1))
                    zed:setSpeedTypeFromWalkType()
                end
            end
        end
    end

    -- approach: the horde walks toward the ACTIVATION spot, not the admin.
    -- The lure keeps pulsing there minute by minute (see lureWatch),
    -- otherwise the horde loses its target as soon as it gets distracted
    -- or the admin flees
    local approach = dist and dist > 0
    if approach then
        addSound(player, px, py, pz, math.floor(dist) + 80, 100)
        local minutes = math.max(1, math.min(30, math.floor(tonumber(args.lureMinutes) or 5)))
        table.insert(lures, {
            x = px, y = py, z = pz,
            radius = math.floor(dist) + 80,
            expiresAt = AegisShared.realTime() + minutes * 60,
            players = player,
        })
    end

    -- report the honest number: requested vs actually spawned shows right
    -- away when a spawn point was outside the loaded area
    -- the fall visual runs on EVERY client, not just the initiator
    if isServer() and paratrooper and #paraIds > 0 then
        sendServerCommand(AegisShared.MODULE, "paraFx", { ids = paraIds, ground = pz, height = heightOffset })
    end

    AegisLog.write("Actions", player:getUsername(), player:getUsername(),
        string.format("Horde spawned: %d of %d zombies at %d,%d (radius %d)%s",
            spawned, count, sx, sy, radius, approach and (", approach from " .. math.floor(dist) .. "m") or ""))
    toClient(player, "hordeResult", { spawned = spawned, requested = count })
end

-- spawn vehicle at the chosen position with facing direction
-- A debug spawn hands out a factory fresh car. setGeneralPartCondition
-- is the engine's own way to age one: the first number caps the
-- condition a damaged part may keep, the second raises the chance that
-- a part is damaged at all. Vanilla uses the same call for its beaten
-- up scenario cars.
local WEAR = {
    used  = { 0.85, 25 },
    wreck = { 0.35, 70 },
}

local function applyWear(car, wear)
    local v = WEAR[tostring(wear or "")]
    if not v then return end
    car:setGeneralPartCondition(v[1], v[2])
end

Commands.spawnvehicle = function(player, args)
    local function reply(ok, id, x, y, z)
        toClient(player, "spawnvehicle", { ok = ok, name = args and args.name or nil, id = id, x = x, y = y, z = z })
    end
    if not permitted(player, "AddItem", "vehicles") then reply(false) return end
    if not args or not args.script then reply(false) return end
    local x = math.floor(tonumber(args.x) or player:getX())
    local y = math.floor(tonumber(args.y) or player:getY())
    local z = math.floor(tonumber(args.z) or 0)
    local angle = tonumber(args.angle) or 0
    local spawned = false
    local newId = nil
    pcall(function()
        local square = getCell():getGridSquare(x, y, z)
        if square then
            local car = addVehicleDebug(tostring(args.script), IsoDirections.N, nil, square)
            -- addVehicleDebug returns an object even on a blocked position,
            -- only the assigned ID proves a real world spawn
            if car and car:getId() ~= -1 then
                spawned = true
                newId = car:getId()
                car:setAngles(0, AegisShared.worldAngle(angle), 0)
                AegisShared.vehicleHandover(car, player)
                applyWear(car, args.wear)
            end
        end
    end)
    -- log outside the spawn pcall: a logging error must not swallow the
    -- spawn result and needs to surface on its own
    if spawned then
        local ok, err = pcall(AegisLog.write, "Actions", player:getUsername(), player:getUsername(),
            string.format("Vehicle spawned: %s at %d,%d,%d, angle %d",
                tostring(args.name or args.script), x, y, z, math.floor(angle)))
        if not ok then print("[Aegis] Spawn log failed: " .. tostring(err)) end
    end
    reply(spawned, newId, x, y, z)
end


-- shared access+existence check for all vehicle detail commands: the
-- vehicle ID is fixed client-side once when opening, here we re-check
-- on every single command whether the vehicle still exists - a
-- second admin could have removed it meanwhile
local function vehicleOrDeny(player, args, command)
    if not permitted(player, "AddItem", "vehicles") then return nil end
    local id = args and tonumber(args.id)
    if not id then return nil end
    local car = getVehicleById(id)
    if not car then
        toClient(player, command, { ok = false, id = id, gone = true })
        return nil
    end
    return car
end

-- every part with more than one compatible variant per the vehicle script,
-- generic across all categories, also covers mod vehicles and mod parts
local function partsList(car)
    local list = {}
    local ok, err = pcall(function()
        for i = 0, car:getPartCount() - 1 do
            local part = car:getPartByIndex(i)
            if part then
                -- same visibility rule as the vanilla mechanics window:
                -- everything except "nodisplay" (hood, trunk, doors,
                -- windows, lights and seats included, not only the slots
                -- with swappable variants)
                local category = part:getCategory() or "Other"
                if category ~= "nodisplay" then
                    local variants = {}
                    local types = part:getItemType()
                    if types then
                        for j = 0, types:size() - 1 do
                            table.insert(variants, types:get(j))
                        end
                    end
                    local item = part:getInventoryItem()
                    table.insert(list, {
                        part = part:getId(),
                        category = category,
                        variants = variants,
                        current = item and item:getFullType() or nil,
                        condition = part:getCondition(),
                    })
                end
            end
        end
    end)
    if not ok then print("[Aegis] partsList failed: " .. tostring(err)) end
    return list
end

-- factory snapshot: created once on the very first Aegis touch of this
-- vehicle (spawn already ran through Commands.spawnvehicle->vehicleHandover,
-- the snapshot itself is created on the first vehicleData call after that),
-- persisted in ModData, survives server restarts
local function createSnapshot(car)
    local snap = { hue = car:getColorHue(), sat = car:getColorSaturation(), val = car:getColorValue(), skin = 0 }
    snap.skin = car:getSkinIndex()
    snap.parts = {}
    for _, p in ipairs(partsList(car)) do
        snap.parts[p.part] = (p.current or "") .. "|" .. string.format("%d", p.condition)
    end
    return snap
end

local function writeSnapshot(car, snap)
    pcall(function()
        local md = car:getModData()
        md.AegisSnapshot = snap
        car:transmitModData()
    end)
end

-- every part with a real item container (trunk, glove box, seats,
-- trailers), for the capacity rows on the service tab. GasTank and
-- Battery are fluid holders without an item container and drop out here
local function containersList(car)
    local list = {}
    pcall(function()
        for i = 0, car:getPartCount() - 1 do
            local part = car:getPartByIndex(i)
            if part and part:getItemContainer() then
                table.insert(list, { part = part:getId(), capacity = part:getContainerCapacity() })
            end
        end
    end)
    return list
end

Commands.vehicleData = function(player, args)
    local car = vehicleOrDeny(player, args, "vehicleData")
    if not car then return end
    -- lazy server-side re-apply: a part reinstall or the TrailerTrunk
    -- condition path re-derives capacity from the script, the stamp wins
    AegisCapacity.applyVehicle(car)
    if not car:getModData().AegisSnapshot then
        writeSnapshot(car, createSnapshot(car))
    end
    local name = car:getModData().AegisName or ""
    local hasKey = true
    local script = car:getScript()
    if script and (script:getPassengerCount() == 0 or script:neverSpawnKey()) then hasKey = false end
    local skinCount = car:getSkinCount()
    local skinIndex = car:getSkinIndex()
    -- script identity travels with the reply so the client never has to
    -- resolve the vehicle object itself (getVehicleById proved unreliable
    -- client-side: the preview showed a default model and the
    -- title fell back to the generic label on the spawn path)
    local scriptFull, scriptName = nil, nil
    if script then
        scriptFull = script:getFullName()
        scriptName = script:getName()
    end
    -- fuel and battery charge as percentages (nil when the vehicle has no
    -- such part), for the live level sliders on the service tab
    local fuel, battery = nil, nil
    pcall(function()
        local tank = car:getPartById("GasTank")
        if tank and tank:getContainerCapacity() > 0 then
            fuel = math.floor(tank:getContainerContentAmount() / tank:getContainerCapacity() * 100 + 0.5)
        end
    end)
    pcall(function()
        local bat = car:getPartById("Battery")
        if bat and bat:getContainerCapacity() > 0 then
            battery = math.floor(bat:getContainerContentAmount() / bat:getContainerCapacity() * 100 + 0.5)
        end
    end)
    toClient(player, "vehicleData", {
        ok = true, id = car:getId(),
        hue = car:getColorHue(), sat = car:getColorSaturation(), val = car:getColorValue(),
        skinIndex = skinIndex, skinCount = skinCount,
        parts = partsList(car), name = name, hasKey = hasKey,
        script = scriptFull, model = scriptName,
        fuel = fuel, battery = battery,
        containers = containersList(car),
    })
end

-- set the item capacity of one vehicle container part; the stamp in the
-- part modData survives reinstalls and reloads (re-applied lazily server
-- side and on the clients via broadcast + inventory refresh hook)
Commands.vehicleCapacity = function(player, args)
    local car = vehicleOrDeny(player, args, "vehicleCapacity")
    if not car then return end
    local partId = args.part
    if type(partId) ~= "string" then return end
    local part = car:getPartById(partId)
    if not part or not part:getItemContainer() then return end
    local value = math.floor(tonumber(args.value) or 0)
    if value < 1 or value > 1000 then return end
    local ok, err = pcall(function()
        part:setContainerCapacity(value)
        part:getModData().aegisCapacity = value
        car:transmitPartModData(part)
    end)
    if ok then
        if isServer() then
            sendServerCommand(AegisShared.MODULE, "capacityApply", { kind = "veh", id = car:getId(), part = partId, value = value })
        end
        AegisLog.write("Actions", player:getUsername(), player:getUsername(),
            "Vehicle container capacity set: " .. partId .. " = " .. value)
    else
        print("[Aegis] vehicleCapacity failed: " .. tostring(err))
    end
    toClient(player, "vehicleCapacity", { ok = ok, id = car:getId(), part = partId, value = value })
end

-- set the item capacity of a world container object (crates, cabinets,
-- fridges, ...); obj is the object index on the clicked square, with a
-- fallback scan for the first container object there
Commands.containerCapacity = function(player, args)
    if not permitted(player, "AddItem", "tools") then return end
    if not args then return end
    local value = math.floor(tonumber(args.value) or 0)
    if value < 1 or value > 1000 then return end
    local x = math.floor(tonumber(args.x) or -1)
    local y = math.floor(tonumber(args.y) or -1)
    local z = math.floor(tonumber(args.z) or 0)
    local square = getCell():getGridSquare(x, y, z)
    if not square then
        toClient(player, "containerCapacity", { ok = false })
        return
    end
    local obj = nil
    pcall(function()
        local objects = square:getObjects()
        local index = tonumber(args.obj)
        if index and index >= 0 and index < objects:size() then
            local candidate = objects:get(index)
            if candidate and candidate:getContainerCount() > 0 then obj = candidate end
        end
        if not obj then
            for i = 0, objects:size() - 1 do
                local candidate = objects:get(i)
                if candidate and candidate:getContainerCount() > 0 then
                    obj = candidate
                    break
                end
            end
        end
    end)
    if not obj then
        toClient(player, "containerCapacity", { ok = false })
        return
    end
    local ok, err = pcall(function()
        obj:getModData().aegisCapacity = value
        for i = 0, obj:getContainerCount() - 1 do
            -- through the shared setter: the field is clamped to what the
            -- engine reads back anyway, the stamp above carries the rest
            AegisCapacity.setField(obj:getContainerByIndex(i), value)
        end
        obj:transmitModData()
    end)
    if ok then
        if isServer() then
            sendServerCommand(AegisShared.MODULE, "capacityApply", { kind = "obj", x = x, y = y, z = z, value = value })
        end
        AegisLog.write("Actions", player:getUsername(), player:getUsername(),
            string.format("Container capacity set: %d,%d,%d = %d", x, y, z, value))
    else
        print("[Aegis] containerCapacity failed: " .. tostring(err))
    end
    toClient(player, "containerCapacity", { ok = ok, value = value, x = x, y = y, z = z })
end

-- admin item move: the vanilla MP transaction rejects perfectly fine
-- transfers into modded-capacity containers, so the server moves the
-- item itself with the same sync calls the vehicle teleport uses
-- getItemWithID only scans a container's own item list, never the bags
-- inside it; this walks the tree to find one item by id anywhere on the
-- player, then hands back ITS OWN container (the bag's contents)
-- getInventory exists ONLY on InventoryContainer, not on InventoryItem
-- (bytecode). Calling it on a plain item throws a Java exception that PZ
-- dumps as a FULL stack trace even when pcall catches it, so walking a
-- normal inventory wrote hundreds of log lines per second on a live
-- server. IsInventoryContainer is the cheap test that exists on the base
-- class, and it has to come FIRST
local function bagInventory(it)
    local isBag = false
    pcall(function() isBag = it:IsInventoryContainer() == true end)
    if not isBag then return nil end
    local inv = nil
    pcall(function() inv = it:getInventory() end)
    return inv
end

local function findItemRecursive(container, id)
    local ok, items = pcall(function() return container:getItems() end)
    if not ok or not items then return nil end
    for i = 0, items:size() - 1 do
        local it = items:get(i)
        local okId, itemId = pcall(function() return it:getID() end)
        if okId and itemId == id then return it end
        local inv = bagInventory(it)
        if inv then
            local found = findItemRecursive(inv, id)
            if found then return found end
        end
    end
    return nil
end

local function resolveMoveContainer(player, spec)
    if type(spec) ~= "table" then return nil end
    if spec.kind == "player" then
        return player:getInventory()
    end
    if spec.kind == "bag" then
        local item = nil
        pcall(function() item = findItemRecursive(player:getInventory(), tonumber(spec.itemId)) end)
        return item and item:getInventory()
    end
    if spec.kind == "veh" then
        local car = getVehicleById(tonumber(spec.id) or -1)
        local part = car and car:getPartById(tostring(spec.part))
        return part and part:getItemContainer()
    end
    if spec.kind == "obj" then
        local square = getCell():getGridSquare(tonumber(spec.x) or -1, tonumber(spec.y) or -1, tonumber(spec.z) or 0)
        if not square then return nil end
        local found = nil
        pcall(function()
            local objects = square:getObjects()
            for i = 0, objects:size() - 1 do
                local obj = objects:get(i)
                if obj and obj.getContainerCount and obj:getContainerCount() > 0 then
                    for j = 0, obj:getContainerCount() - 1 do
                        local c = obj:getContainerByIndex(j)
                        if c and (not spec.type or c:getType() == spec.type) then
                            found = c
                            return
                        end
                        if c and not found then found = c end
                    end
                end
            end
        end)
        return found
    end
    return nil
end

-- strict self-validation for movers WITHOUT the tools area: the
-- clients route vehicle transfers of ordinary players
-- through this command too, the pure admin gate locked every player
-- out of their own trunks). Mirrors what the vanilla road would check
-- Returns true, or false plus the exact condition that refused. A bare
-- "denied" only says the gate closed, not which of the five checks
-- closed it, and each one has a completely different cause
local function moveValidated(player, args)
    if not args then return false, "no args" end
    local okAll = false
    local why = "unreadable"
    pcall(function()
        local srcInv = resolveMoveContainer(player, args.src)
        local destInv = resolveMoveContainer(player, args.dest)
        if not srcInv then why = "src container unresolved" return end
        if not destInv then why = "dest container unresolved" return end
        if srcInv == destInv then why = "src == dest" return end
        local function near(spec, side)
            if not spec or spec.kind == "player" or spec.kind == "bag" then return true end
            if spec.kind == "veh" then
                local car = getVehicleById(tonumber(spec.id) or -1)
                if not car then
                    why = side .. " vehicle id " .. tostring(spec.id) .. " unknown on the server"
                    return false
                end
                -- A vehicle is measured by its PART, never by its centre. The
                -- centre is what a plain DistanceTo gives, and on a long truck
                -- the trunk sits several tiles behind it: standing right at the
                -- open trunk of an M923 measures over 4 tiles and gets
                -- refused.
                -- isInArea with the part's own area is exactly the check
                -- vanilla uses to decide whether a character can reach a part
                -- (ISVehicleMechanics.lua:1410)
                local part = car:getPartById(tostring(spec.part))
                local area = part and part:getArea()
                if area and area ~= "" then
                    local inArea = false
                    local okA = pcall(function() inArea = car:isInArea(area, player) == true end)
                    if okA then
                        if inArea then return true end
                        why = string.format("%s outside the '%s' area of the vehicle", side, tostring(area))
                        return false
                    end
                end
                -- no area to go by: fall back to a distance, but to the part's
                -- own centre and with headroom for long vehicles
                local d = nil
                pcall(function() d = car:getAreaDist(area or "TruckBed", player) end)
                if d == nil then
                    d = IsoUtils.DistanceTo(player:getX(), player:getY(), car:getX(), car:getY())
                end
                if d > 8 then
                    why = string.format("%s too far away (%.1f tiles from the vehicle)", side, d)
                    return false
                end
                return true
            end
            local x = (tonumber(spec.x) or 0) + 0.5
            local y = (tonumber(spec.y) or 0) + 0.5
            local d = IsoUtils.DistanceTo(player:getX(), player:getY(), x, y)
            if d > 4 then
                why = string.format("%s too far away (%.1f tiles)", side, d)
                return false
            end
            return true
        end
        if not near(args.src, "src") then return end
        if not near(args.dest, "dest") then return end
        local item = srcInv:getItemWithID(tonumber(args.itemId) or -1)
        if not item then why = "item " .. tostring(args.itemId) .. " not in src" return end
        if not destInv:isItemAllowed(item) then why = "dest refuses this item type" return end
        local cap = nil
        local part = destInv:getVehiclePart()
        if part then cap = tonumber(part:getModData().aegisCapacity) end
        if not cap then
            local parent = destInv:getParent()
            if parent and parent:hasModData() then
                cap = tonumber(parent:getModData().aegisCapacity)
            end
        end
        local stamped = cap ~= nil
        if not cap then cap = destInv:getCapacity() end
        local used = destInv:getCapacityWeight()
        local add = item:getUnequippedWeight()
        if used + add > cap then
            why = string.format("over capacity: %.2f used + %.2f new > %.2f%s",
                used, add, cap, stamped and " (Aegis stamp)" or " (engine value, NO stamp found)")
            return
        end
        okAll = true
    end)
    if okAll then return true end
    return false, why
end

-- tools permission without the denial toast, for the two-lane check below
local function toolsPermittedQuiet(player)
    if not AegisRoles.canArea(player, "tools") then return false end
    local rights = nil
    pcall(function() rights = AegisRoles.effectiveRights(player) end)
    if type(rights) == "table" then return true end
    return allowed(player, "AddItem")
end

Commands.adminMoveItem = function(player, args)
    -- every deny leaves a server log line now. A refusal here used to be
    -- completely silent on BOTH sides, which made "the trunk does not
    -- work" needlessly hard to trace to this command saying no
    local function deny(reason)
        pcall(function()
            print("[Aegis] adminMoveItem denied (" .. reason .. ") for "
                .. tostring(player and player:getUsername() or "?"))
        end)
        toClient(player, "adminMoveItem", { ok = false, reason = reason })
    end
    if not toolsPermittedQuiet(player) then
        local ok, why = moveValidated(player, args)
        if not ok then
            deny("no tools right, and the move check said: " .. tostring(why))
            return
        end
    end
    if not args then return end
    local srcInv = resolveMoveContainer(player, args.src)
    local destInv = resolveMoveContainer(player, args.dest)
    if not srcInv or not destInv or srcInv == destInv then
        deny("container not found")
        return
    end
    local item = nil
    pcall(function() item = srcInv:getItemWithID(tonumber(args.itemId) or -1) end)
    if not item then
        deny("item not found")
        return
    end
    local ok, err = pcall(function()
        srcInv:Remove(item)
        destInv:AddItem(item)
        if isServer() then
            sendAddItemToContainer(destInv, item)
            if args.src and args.src.kind ~= "player" then
                sendRemoveItemFromContainer(srcInv, item)
            end
        end
    end)
    if ok then
        local reply = { ok = true }
        if args.src and args.src.kind == "player" then
            reply.removeId = tonumber(args.itemId)
        end
        toClient(player, "adminMoveItem", reply)
    else
        toClient(player, "adminMoveItem", { ok = false, reason = tostring(err) })
        print("[Aegis] adminMoveItem failed: " .. tostring(err))
    end
end

-- live level slider target parts; whitelisted so the client cannot point
-- this at arbitrary containers (trunk, seats)
local LEVEL_PARTS = { GasTank = true, Battery = true }

-- the throttled slider fires ~8x/s while dragging - the audit log gets
-- one line per part every few seconds with the latest value instead
local levelLogGate = {}

Commands.vehicleContainerLevel = function(player, args)
    local car = vehicleOrDeny(player, args, "vehicleContainerLevel")
    if not car then return end
    local partId = args.part
    if type(partId) ~= "string" or not LEVEL_PARTS[partId] then return end
    local part = car:getPartById(partId)
    if not part then return end
    local value = math.max(0, math.min(100, math.floor(tonumber(args.value) or 0)))
    local ok, err = pcall(function()
        part:setContainerContentAmount(part:getContainerCapacity() * value / 100)
        -- the setter alone only changes server state - the client never
        -- sees it without this sync (slider had no
        -- visible effect). Exactly what the vanilla server handler does
        -- after the same call (VehicleCommands.setContainerContentAmount)
        car:transmitPartModData(part)
    end)
    if ok then
        local key = player:getUsername() .. "|" .. partId
        local now = AegisShared.realTime()
        if (levelLogGate[key] or 0) <= now - 5 then
            levelLogGate[key] = now
            AegisLog.write("Actions", player:getUsername(), player:getUsername(),
                "Vehicle " .. partId .. " level set: " .. value .. "%")
        end
    else
        print("[Aegis] vehicleContainerLevel failed: " .. tostring(err))
    end
end

Commands.vehicleNewKey = function(player, args)
    local car = vehicleOrDeny(player, args, "vehicleNewKey")
    if not car then return end
    local ok, err = pcall(function()
        local key = car:createVehicleKey()
        if not key then error("engine returned no key") end
        -- keep the key label in sync with an existing nickname, same
        -- pattern as Commands.vehicleName
        local name = car:getModData().AegisName
        if name and name ~= "" then
            local base = Translator.getText(key:getScriptItem():getDisplayName())
            key:setName(base .. " - " .. name)
        end
        -- glove box first, admin inventory as fallback (same handover as
        -- AegisShared.vehicleHandover)
        local inv = nil
        local part = car:getPartById("GloveBox")
        if part then inv = part:getItemContainer() end
        if not inv then inv = player:getInventory() end
        inv:AddItem(key)
        sendAddItemToContainer(inv, key)
    end)
    if ok then
        AegisLog.write("Actions", player:getUsername(), player:getUsername(), "Vehicle key created")
    else
        print("[Aegis] vehicleNewKey failed: " .. tostring(err))
    end
    toClient(player, "vehicleNewKey", { ok = ok, id = car:getId() })
end

Commands.vehicleColor = function(player, args)
    local car = vehicleOrDeny(player, args, "vehicleColor")
    if not car then return end
    local h = tonumber(args.h) or 0
    local s = tonumber(args.s) or 0
    local v = tonumber(args.v) or 0
    local ok, err = pcall(function()
        car:setColorHSV(h, s, v)
        car:transmitColorHSV()
    end)
    if ok then
        AegisLog.write("Actions", player:getUsername(), player:getUsername(),
            string.format("Vehicle color set: h=%d s=%d v=%d", math.floor(h), math.floor(s * 100), math.floor(v * 100)))
    else
        print("[Aegis] vehicleColor failed: " .. tostring(err))
    end
end

Commands.vehicleSkin = function(player, args)
    local car = vehicleOrDeny(player, args, "vehicleSkin")
    if not car then return end
    local count = car:getSkinCount()
    local index = math.max(0, math.min(count - 1, math.floor(tonumber(args.index) or 0)))
    local ok, err = pcall(function()
        car:setSkinIndex(index)
        car:transmitSkinIndex()
    end)
    if ok then
        AegisLog.write("Actions", player:getUsername(), player:getUsername(), "Vehicle skin changed")
    else
        print("[Aegis] vehicleSkin failed: " .. tostring(err))
    end
end

-- installs a variant directly (admin cheat: creates the item via
-- instanceItem, same pattern as the bulk item grant in AegisPageItems.lua
-- resp. Aegis_Clearing.lua, no inventory requirement), returns the previous
-- variant+condition (for undo)
local function installPart(car, partId, itemType, condition)
    local part = car:getPartById(partId)
    if not part then return false end
    local oldItem = part:getInventoryItem()
    local previousType = oldItem and oldItem:getFullType() or nil
    local previousCondition = part:getCondition()
    local ok, err = pcall(function()
        local item = instanceItem(itemType)
        if not item then error("Unknown item type: " .. tostring(itemType)) end
        part:setInventoryItem(item)
        car:transmitPartItem(part)
        part:setCondition(math.floor(condition or 100))
        car:transmitPartCondition(part)
        -- a fresh part item re-derives the container capacity from the
        -- item script, an admin stamp has to win again
        AegisCapacity.applyPart(part)
    end)
    return ok, previousType, previousCondition, err
end

-- teleport while seated in a vehicle. Vehicle physics is owned by the
-- driving client, so the vehicle can only be moved once the seat is
-- free: the client teleports the player first (the vanilla teleport
-- dismounts cleanly and hands vehicle authority back to the server),
-- then the watcher below pulls the empty vehicle after him. The target
-- area is usually unloaded server side until the player arrives, so the
-- watcher also waits for the chunk before it moves anything
local pendingVehicleMoves = {}

local function refuseVehicleMove(player, reason)
    print("[Aegis] vehicle teleport refused: " .. tostring(reason))
    toClient(player, "teleportVehicle", { ok = false, phase = "moved", reason = reason })
end

-- teleport by recreation: server side vehicle pose writes never reach
-- connected clients reliably, but a FRESH spawn syncs 100% through the
-- normal creation flow. So the vehicle is rebuilt at the target from a
-- full state capture and the old one is deleted afterwards. Every
-- transfer uses the battle tested surfaces of the detail window
-- commands (installPart, capacity stamps, level setter, color/skin,
-- modData, key creation)

local function copyPlainTable(src)
    local out = {}
    for k, v in pairs(src) do
        out[k] = type(v) == "table" and copyPlainTable(v) or v
    end
    return out
end

-- full state of one vehicle, read while the old one still exists
local function captureVehicle(car)
    local snap = { parts = {} }
    snap.script = car:getScriptName()
    snap.angle = car:getAngleY()
    snap.hue, snap.sat, snap.val = car:getColorHue(), car:getColorSaturation(), car:getColorValue()
    snap.skin = car:getSkinIndex()
    snap.rust = car:getRust()
    snap.engineQuality = car:getEngineQuality()
    snap.engineLoudness = car:getEngineLoudness()
    snap.enginePower = car:getEnginePower()
    snap.hotwired = car:isHotwired()
    snap.hotwireBroken = car:isHotwiredBroken()
    pcall(function() snap.modData = copyPlainTable(car:getModData()) end)
    pcall(function()
        for i = 0, car:getPartCount() - 1 do
            local part = car:getPartByIndex(i)
            if part then
                local entry = { id = part:getId(), condition = part:getCondition() }
                local item = part:getInventoryItem()
                if item then entry.itemType = item:getFullType() end
                pcall(function()
                    local cap = part:getModData().aegisCapacity
                    if cap then entry.capacity = math.floor(tonumber(cap)) end
                end)
                -- fluid holders (GasTank, Battery) carry an amount, real
                -- item containers are moved item by item later
                pcall(function()
                    if not part:getItemContainer() and part:getContainerCapacity() > 0 then
                        entry.amount = part:getContainerContentAmount()
                    end
                end)
                table.insert(snap.parts, entry)
            end
        end
    end)
    return snap
end

-- move the real container items across (trunk, glove box, seats). The
-- old container dies with the old vehicle, so only the add side needs a
-- client sync: sendAddItemToContainer is the same call the key handover
-- and the vanilla server item paths use
local function transferContainers(oldCar, newCar)
    pcall(function()
        for i = 0, oldCar:getPartCount() - 1 do
            local oldPart = oldCar:getPartByIndex(i)
            local oldInv = oldPart and oldPart:getItemContainer()
            if oldInv then
                local newPart = newCar:getPartById(oldPart:getId())
                local newInv = newPart and newPart:getItemContainer()
                if newInv then
                    -- admin capacity stamp moves with the vehicle
                    pcall(function()
                        local stamp = oldPart:getModData().aegisCapacity
                        if stamp then
                            newPart:getModData().aegisCapacity = stamp
                            newPart:setContainerCapacity(tonumber(stamp))
                            newCar:transmitPartModData(newPart)
                        end
                    end)
                    -- fresh spawns roll random loot, drop it before the
                    -- real content moves in (user found ghost items)
                    local stale = {}
                    local fresh = newInv:getItems()
                    for j = 0, fresh:size() - 1 do
                        table.insert(stale, fresh:get(j))
                    end
                    for _, item in ipairs(stale) do
                        pcall(function()
                            newInv:Remove(item)
                            sendRemoveItemFromContainer(newInv, item)
                        end)
                    end
                    pcall(function() newInv:setExplored(true) end)
                    local moving = {}
                    local items = oldInv:getItems()
                    for j = 0, items:size() - 1 do
                        table.insert(moving, items:get(j))
                    end
                    for _, item in ipairs(moving) do
                        pcall(function()
                            oldInv:Remove(item)
                            newInv:AddItem(item)
                            sendAddItemToContainer(newInv, item)
                        end)
                    end
                end
            end
        end
    end)
end

-- rebuild one vehicle at the target square, returns the new vehicle or
-- nil plus reason. The old vehicle stays untouched on failure
local function recreateVehicleAt(oldCar, square, player)
    local snap = captureVehicle(oldCar)
    if not snap.script or snap.script == "" then return nil, "script name unreadable" end
    local newCar = nil
    pcall(function() newCar = addVehicleDebug(snap.script, IsoDirections.N, nil, square) end)
    if not newCar then return nil, "spawn at target failed" end
    if newCar:getId() == -1 then
        pcall(function() newCar:permanentlyRemove() end)
        return nil, "no free spot at target"
    end
    -- getAngleY and setAngles disagree by half a turn on spawned
    -- vehicles (the moved car faced backwards)
    newCar:setAngles(0, ((tonumber(snap.angle) or 0) + 180) % 360, 0)
    pcall(function()
        newCar:setColorHSV(tonumber(snap.hue) or 0, tonumber(snap.sat) or 0, tonumber(snap.val) or 0)
        newCar:transmitColorHSV()
    end)
    pcall(function()
        newCar:setSkinIndex(math.floor(tonumber(snap.skin) or 0))
        newCar:transmitSkinIndex()
    end)
    if snap.rust then
        pcall(function()
            newCar:setRust(tonumber(snap.rust) or 0)
            newCar:transmitRust()
        end)
    end
    if snap.engineQuality then
        pcall(function()
            newCar:setEngineFeature(snap.engineQuality, snap.engineLoudness, snap.enginePower)
            newCar:transmitEngine()
        end)
    end
    if snap.hotwired or snap.hotwireBroken then
        pcall(function() newCar:cheatHotwire(snap.hotwired == true, snap.hotwireBroken == true) end)
    end
    pcall(function()
        local md = newCar:getModData()
        for k, v in pairs(snap.modData or {}) do md[k] = v end
        newCar:transmitModData()
    end)
    -- same script means same part ids; parts with an item go through the
    -- proven installPart surface, bare slots only carry their condition
    for _, p in ipairs(snap.parts) do
        if p.itemType then
            installPart(newCar, p.id, p.itemType, p.condition)
        else
            pcall(function()
                local part = newCar:getPartById(p.id)
                if part then
                    part:setCondition(math.floor(tonumber(p.condition) or 100))
                    newCar:transmitPartCondition(part)
                end
            end)
        end
        local newPart = newCar:getPartById(p.id)
        if newPart then
            if p.capacity then
                pcall(function()
                    newPart:setContainerCapacity(p.capacity)
                    newPart:getModData().aegisCapacity = p.capacity
                    newCar:transmitPartModData(newPart)
                end)
                if isServer() then
                    sendServerCommand(AegisShared.MODULE, "capacityApply",
                        { kind = "veh", id = newCar:getId(), part = p.id, value = p.capacity })
                end
            end
            if p.amount then
                pcall(function()
                    newPart:setContainerContentAmount(tonumber(p.amount) or 0)
                    newCar:transmitPartModData(newPart)
                end)
            end
        end
    end
    transferContainers(oldCar, newCar)
    -- the old key can never match the new vehicle id, a fresh one goes
    -- into the new glove box (admin inventory as fallback), same flow as
    -- Commands.vehicleNewKey
    pcall(function()
        local key = newCar:createVehicleKey()
        if not key then return end
        local name = snap.modData and snap.modData.AegisName
        if name and name ~= "" then
            local base = Translator.getText(key:getScriptItem():getDisplayName())
            key:setName(base .. " - " .. name)
        end
        local inv = nil
        local part = newCar:getPartById("GloveBox")
        if part then inv = part:getItemContainer() end
        if not inv and player then inv = player:getInventory() end
        if inv then
            inv:AddItem(key)
            sendAddItemToContainer(inv, key)
        end
    end)
    return newCar
end

-- spot for the recreated trailer: the hitch position behind the new car,
-- with a plain offset square as fallback
local function trailerSquare(newCar)
    local sq = nil
    pcall(function()
        local pos = newCar:getTowingWorldPos("trailer", Vector3f.new())
        if pos then
            sq = getCell():getGridSquare(math.floor(pos:x()), math.floor(pos:y()), 0)
        end
    end)
    if not sq then
        pcall(function()
            sq = getCell():getGridSquare(math.floor(newCar:getX()), math.floor(newCar:getY()) + 4, 0)
        end)
    end
    return sq
end

Commands.teleportVehicle = function(player, args)
    if not permitted(player, "TeleportToCoordinates", "world") then
        print("[Aegis] vehicle teleport refused: missing capability or area right")
        return
    end
    local car = player:getVehicle()
    if not car then refuseVehicleMove(player, "sender not in a vehicle") return end
    local x, y, z
    if args and args.username then
        local target = findByUsername(tostring(args.username))
        if not target then refuseVehicleMove(player, "target player not found") return end
        x, y, z = target:getX(), target:getY(), target:getZ()
    else
        x = tonumber(args and args.x)
        y = tonumber(args and args.y)
        z = tonumber(args and args.z) or 0
    end
    if not x or not y then refuseVehicleMove(player, "bad target coordinates") return end
    x, y, z = math.floor(x), math.floor(y), math.floor(z)
    -- only the admin himself may be aboard: other seated players hold
    -- client side seat state the move would tear apart
    local occupied = false
    for i = 0, car:getMaxPassengers() - 1 do
        local c = car:getCharacter(i)
        if c and c ~= player then occupied = true end
    end
    if occupied then refuseVehicleMove(player, "another player is aboard") return end
    local okA, hasHitch = pcall(function() return car:attachmentExist("trailer") end)
    if not (okA and hasHitch == true) then
        refuseVehicleMove(player, "vehicle script has no trailer attachment")
        return
    end
    local trailer = car:getVehicleTowing()
    if trailer then
        local okT, resT = pcall(function() return trailer:attachmentExist("trailer") end)
        if not (okT and resT == true) then
            refuseVehicleMove(player, "trailer script has no trailer attachment")
            return
        end
    end
    -- an unloaded target square is normal for long jumps: the player
    -- teleport that follows streams the area in, the watcher waits for it
    if not isServer() then
        -- solo runs in one process: dismount here, the reply handler
        -- teleports the player, the watcher below finishes the move
        pcall(function()
            car:exit(player)
            player:setVehicle(nil)
        end)
    end
    table.insert(pendingVehicleMoves, {
        player = player, carId = car:getId(), hasTrailer = trailer ~= nil,
        x = x, y = y, z = z, deadline = AegisShared.realTime() + 20,
    })
    -- the client answers with the plain player teleport, the dismount it
    -- causes (already done directly in solo) frees the vehicle
    toClient(player, "teleportVehicle", { ok = true, phase = "exit", x = x, y = y, z = z })
end

-- runs both on the dedicated server and in the solo process. A pending
-- move fires once the seat is free AND the target square is loaded,
-- everything else is a timeout with reason
local function vehicleMoveWatch()
    if #pendingVehicleMoves == 0 then return end
    for i = #pendingVehicleMoves, 1, -1 do
        local m = pendingVehicleMoves[i]
        local car = getVehicleById(m.carId)
        local finished, moved, reason = false, false, nil
        local driver = car and car:getDriver()
        local square = getCell():getGridSquare(m.x, m.y, m.z)
        if not car then
            finished = true
            reason = "vehicle disappeared while waiting"
        elseif driver == nil and square then
            finished = true
            local newCar, failReason = recreateVehicleAt(car, square, m.player)
            if newCar then
                moved = true
                m.newId = newCar:getId()
                local oldTrailer = car:getVehicleTowing()
                if oldTrailer then
                    local tSq = trailerSquare(newCar)
                    local newTrailer, tReason = nil, nil
                    if tSq then
                        newTrailer, tReason = recreateVehicleAt(oldTrailer, tSq, m.player)
                    else
                        tReason = "no square for trailer"
                    end
                    if newTrailer then
                        -- vanilla attach surface (server Commands.attachTrailer)
                        local hitched = pcall(function()
                            newCar:addPointConstraint(m.player, newTrailer, "trailer", "trailer")
                        end)
                        if not hitched then
                            print("[Aegis] vehicle teleport: trailer recreated but not hitched")
                        end
                        pcall(function() oldTrailer:permanentlyRemove() end)
                    else
                        -- honest fallback: the old trailer stays where it was
                        print("[Aegis] vehicle teleport: trailer left behind: " .. tostring(tReason))
                        reason = "trailer left behind"
                    end
                end
                pcall(function() car:permanentlyRemove() end)
            else
                reason = failReason or "vehicle recreation failed"
            end
        elseif AegisShared.realTime() > m.deadline then
            finished = true
            reason = square and "timeout waiting for empty seat" or "timeout waiting for target chunk"
        end
        if finished then
            table.remove(pendingVehicleMoves, i)
            if moved then
                local okLog, err = pcall(AegisLog.write, "Actions", m.player:getUsername(), m.player:getUsername(),
                    string.format("Vehicle teleport (recreated) to %d,%d,%d%s", m.x, m.y, m.z, m.hasTrailer and " with trailer" or ""))
                if not okLog then print("[Aegis] Vehicle teleport log failed: " .. tostring(err)) end
            else
                print("[Aegis] vehicle teleport refused: " .. tostring(reason))
            end
            pcall(function()
                toClient(m.player, "teleportVehicle",
                    { ok = moved, phase = "moved", x = m.x, y = m.y, z = m.z,
                      reason = reason, newId = m.newId, oldId = m.carId })
            end)
        end
    end
end

Events.OnTick.Add(vehicleMoveWatch)

Commands.vehiclePartSwap = function(player, args)
    local car = vehicleOrDeny(player, args, "vehiclePartSwap")
    if not car then return end
    local partId, itemType = args.part, args.itemType
    if type(partId) ~= "string" or type(itemType) ~= "string" then return end
    local ok, previousType, previousCondition, err = installPart(car, partId, itemType, 100)
    if ok then
        AegisLog.write("Actions", player:getUsername(), player:getUsername(),
            "Vehicle part changed: " .. partId .. " -> " .. itemType)
    else
        print("[Aegis] vehiclePartSwap failed: " .. tostring(err))
    end
    toClient(player, "vehiclePartSwap", { ok = ok, part = partId, itemType = itemType, previousType = previousType, previousCondition = previousCondition, id = car:getId() })
end

Commands.vehiclePartUndo = function(player, args)
    local car = vehicleOrDeny(player, args, "vehiclePartUndo")
    if not car then return end
    local partId, itemType = args.part, args.itemType
    if type(partId) ~= "string" or type(itemType) ~= "string" then return end
    local condition = math.max(0, math.min(100, tonumber(args.condition) or 100))
    local ok, _, _, err = installPart(car, partId, itemType, condition)
    if ok then
        AegisLog.write("Actions", player:getUsername(), player:getUsername(), "Vehicle part change undone: " .. partId)
    else
        print("[Aegis] vehiclePartUndo failed: " .. tostring(err))
    end
    toClient(player, "vehiclePartUndo", { ok = ok, part = partId, id = car:getId() })
end

Commands.vehiclePartCondition = function(player, args)
    local car = vehicleOrDeny(player, args, "vehiclePartCondition")
    if not car then return end
    local partId = args.part
    if type(partId) ~= "string" then return end
    local part = car:getPartById(partId)
    if not part then return end
    local value = math.max(0, math.min(100, math.floor(tonumber(args.value) or 0)))
    local ok, err = pcall(function()
        part:setCondition(value)
        car:transmitPartCondition(part)
    end)
    if ok then
        AegisLog.write("Actions", player:getUsername(), player:getUsername(),
            "Vehicle part condition set: " .. partId .. " = " .. value)
    else
        print("[Aegis] vehiclePartCondition failed: " .. tostring(err))
    end
end

local TIRE_SLOTS = { "TireFrontLeft", "TireFrontRight", "TireRearLeft", "TireRearRight" }

Commands.vehicleAllTires = function(player, args)
    local car = vehicleOrDeny(player, args, "vehicleAllTires")
    if not car then return end
    local itemType = args.itemType
    if type(itemType) ~= "string" then return end
    local value = math.max(0, math.min(100, math.floor(tonumber(args.value) or 100)))
    local succeeded = 0
    for _, slot in ipairs(TIRE_SLOTS) do
        local ok = installPart(car, slot, itemType, value)
        if ok then succeeded = succeeded + 1 end
    end
    local allOk = succeeded == #TIRE_SLOTS
    AegisLog.write("Actions", player:getUsername(), player:getUsername(),
        string.format("Tires changed: %d/%d -> %s (%d%%)", succeeded, #TIRE_SLOTS, itemType, value))
    if not allOk then
        print(string.format("[Aegis] vehicleAllTires: only %d/%d tires installed", succeeded, #TIRE_SLOTS))
    end
    toClient(player, "vehicleAllTires", { ok = allOk, id = car:getId() })
end

Commands.vehicleService = function(player, args)
    local car = vehicleOrDeny(player, args, "vehicleService")
    if not car then return end
    local ok, err = pcall(function()
        car:repair()
        local tank = car:getPartById("GasTank")
        if tank then
            tank:setContainerContentAmount(tank:getContainerCapacity())
            -- same sync gap as the level slider: without this the client
            -- never sees the refill (vanilla handler pattern)
            car:transmitPartModData(tank)
        end
    end)
    if ok then
        AegisLog.write("Actions", player:getUsername(), player:getUsername(), "Vehicle serviced (detail window)")
    else
        print("[Aegis] vehicleService failed: " .. tostring(err))
    end
    toClient(player, "vehicleService", { ok = ok, id = car:getId() })
end

-- escape free text name (same pattern as the free text spots ahead of
-- SendCommandToServer):
-- strip pipe/newline, hard length cap
Commands.vehicleName = function(player, args)
    local car = vehicleOrDeny(player, args, "vehicleName")
    if not car then return end
    local name = tostring(args.name or ""):sub(1, 40)
    name = name:gsub("[|\r\n]", "")
    local ok, err = pcall(function()
        car:getModData().AegisName = name
        car:transmitModData()
    end)
    if ok then
        AegisLog.write("Actions", player:getUsername(), player:getUsername(), "Vehicle renamed")
    else
        print("[Aegis] vehicleName failed: " .. tostring(err))
    end
    -- key rename is best-effort enrichment, not the primary outcome: a
    -- vehicle legitimately having no key (script:neverSpawnKey/0
    -- passengers) is a valid state, not a failure, so this never flips
    -- the overall ok flag - it only gets its own diagnostic on a genuine
    -- unexpected throw
    local keyOk, keyErr = pcall(function()
        local key = car:getCurrentKey()
        if key and name ~= "" then
            -- always rebuilt from the key item's own base name, never
            -- stacked onto an already-renamed string (exact pattern from
            -- BaseVehicle.keyNamerVehicle, just with the nickname instead
            -- of the static model name)
            local base = Translator.getText(key:getScriptItem():getDisplayName())
            key:setName(base .. " - " .. name)
        end
    end)
    if not keyOk then print("[Aegis] vehicleName key rename failed: " .. tostring(keyErr)) end
    toClient(player, "vehicleName", { ok = ok, name = name, id = car:getId() })
end

Commands.vehicleReset = function(player, args)
    local car = vehicleOrDeny(player, args, "vehicleReset")
    if not car then return end
    local snap = car:getModData().AegisSnapshot
    if not snap then return end
    local colorOk, colorErr = pcall(function()
        car:setColorHSV(tonumber(snap.hue) or 0, tonumber(snap.sat) or 0, tonumber(snap.val) or 0)
        car:transmitColorHSV()
        car:setSkinIndex(math.floor(tonumber(snap.skin) or 0))
        car:transmitSkinIndex()
    end)
    if not colorOk then print("[Aegis] vehicleReset color/skin failed: " .. tostring(colorErr)) end
    local restored, total = 0, 0
    if snap.parts then
        for part, encoded in pairs(snap.parts) do
            total = total + 1
            local itemType, condition = tostring(encoded):match("^(.-)|(%-?%d+)$")
            if itemType and itemType ~= "" then
                local partOk = pcall(function()
                    local ok = installPart(car, part, itemType, tonumber(condition))
                    if ok then restored = restored + 1 end
                end)
                if not partOk then print("[Aegis] vehicleReset part restore failed: " .. part) end
            else
                -- empty slot at snapshot time is itself the valid factory
                -- state (no item was installed) - nothing to restore, counts
                -- as a trivial success
                restored = restored + 1
            end
        end
    end
    AegisLog.write("Actions", player:getUsername(), player:getUsername(),
        string.format("Vehicle reset to factory state (%d/%d parts restored)", restored, total))
    toClient(player, "vehicleReset", { ok = colorOk and restored == total, id = car:getId() })
end

-- 8 IsoDirections in ordinal order, angle mapping derived like in
-- AegisShared.worldAngle (N=0,NW=45,W=90,SW=135,S=180,SE=225,
-- E=270,NE=315, bytecode verified via addVehicleDebug). Animals are
-- characters without setAngles; faceDirection(IsoDirections) is the
-- regular path (IsoGameCharacter, IsoAnimal inherits it via IsoPlayer)
local ANIMAL_DIRECTIONS = {
    IsoDirections.N, IsoDirections.NW, IsoDirections.W, IsoDirections.SW,
    IsoDirections.S, IsoDirections.SE, IsoDirections.E, IsoDirections.NE,
}
local function animalDirection(uiAngle)
    local world = AegisShared.worldAngle(uiAngle)
    local ordinal = math.floor(world / 45 + 0.5) % 8
    return ANIMAL_DIRECTIONS[ordinal + 1]
end

Commands.spawnanimal = function(player, args)
    local function reply(ok)
        toClient(player, "spawnanimal", { ok = ok, name = args and args.name or nil })
    end
    if not permitted(player, "AnimalCheats", "animals") then reply(false) return end
    if not args or type(args.type) ~= "string" or type(args.breed) ~= "string" then reply(false) return end
    local x = math.floor(tonumber(args.x) or player:getX())
    local y = math.floor(tonumber(args.y) or player:getY())
    local z = math.floor(tonumber(args.z) or 0)
    local angle = tonumber(args.angle) or 0
    local spawned = false
    pcall(function()
        local def = AnimalDefinitions.getDef(args.type)
        local breed = def and def:getBreedByName(args.breed)
        if not breed then return end
        local animal = addAnimal(getCell(), x, y, z, args.type, breed, false)
        if animal then
            animal:addToWorld()
            animal:faceDirection(animalDirection(angle))
            spawned = true
        end
    end)
    if spawned then
        local ok, err = pcall(AegisLog.write, "Actions", player:getUsername(), player:getUsername(),
            string.format("Animal spawned: %s at %d,%d,%d", tostring(args.name or args.type), x, y, z))
        if not ok then print("[Aegis] Spawn log failed: " .. tostring(err)) end
    end
    reply(spawned)
end

-- broadcast the absolute in-game date to all clients: the engine distributes
-- nothing by itself after setDay/setMonth/setYear, and a clock moved
-- backwards over midnight otherwise makes the clients' wrap detection
-- falsely jump a day ahead
local function broadcastDate()
    if not isServer() then return end
    local gt = getGameTime()
    -- tod lets every client snap its smoothed local clock: after an admin
    -- jump the world lighting otherwise eases toward the new time for
    -- minutes (getHour reads the smoothed value, not serverTimeOfDay)
    sendServerCommand(AegisShared.MODULE, "timeSync", {
        day = gt:getDay(),
        month = gt:getMonth(),
        year = gt:getYear(),
        tod = gt:getTimeOfDay(),
    })
end

Commands.settime = function(player, args)
    if not permitted(player, "ClimateManager", "world") then return end
    local hour = args and tonumber(args.hour)
    if not hour then return end
    hour = math.floor(hour) % 24
    if hour < 0 then hour = hour + 24 end
    local minute = math.floor(tonumber(args and args.minute) or 0)
    if minute < 0 then minute = 0 end
    if minute > 59 then minute = 59 end
    getGameTime():setTimeOfDay(hour + minute / 60)
    -- rebuild day infos right away instead of waiting for the climate tick
    getClimateManager():forceDayInfoUpdate()
    broadcastDate()
    AegisLog.write("Actions", player:getUsername(), player:getUsername(),
        string.format("Time set to %02d:%02d", hour, minute))
end

-- set in-game date and time: without a date only the clock is set, the
-- day is clamped to the real month length (leap years included). Climate
-- and season catch up via the ClimateManager itself, erosion and spoilage
-- do not depend on the calendar
Commands.setWorldTime = function(player, args)
    if not permitted(player, "ClimateManager", "world") then return end
    if not args then return end
    local gt = getGameTime()
    local parts = {}
    local year = tonumber(args.year)
    local month = tonumber(args.month)
    local day = tonumber(args.day)
    if year and month and day then
        year, month, day = math.floor(year), math.floor(month), math.floor(day)
        if year < 1993 or year > 2100 or month < 1 or month > 12 or day < 1 then return end
        local maxDay = gt:daysInMonth(year, month - 1)
        if day > maxDay then day = maxDay end
        gt:setYear(year)
        gt:setMonth(month - 1)
        gt:setDay(day - 1)
        table.insert(parts, string.format("Date %02d.%02d.%d", day, month, year))
    end
    local hour = tonumber(args.hour)
    if hour then
        hour = math.floor(hour) % 24
        if hour < 0 then hour = hour + 24 end
        local minute = math.floor(tonumber(args.minute) or 0)
        if minute < 0 then minute = 0 end
        if minute > 59 then minute = 59 end
        gt:setTimeOfDay(hour + minute / 60)
        table.insert(parts, string.format("Time %02d:%02d", hour, minute))
    end
    if #parts == 0 then return end
    -- rebuild day infos right away instead of waiting for the next climate tick
    getClimateManager():forceDayInfoUpdate()
    broadcastDate()
    AegisLog.write("Actions", player:getUsername(), player:getUsername(),
        "In-game time set: " .. table.concat(parts, ", "))
end

-- generic log relay for purely client-side actions (Java cheat setters,
-- vanilla slash commands, solo direct paths): without this detour there
-- would be no server-side "Actions" entry for them.
-- throttle as a token bucket instead of a hard one-second lock: a burst of
-- quickly toggled powers lands in the log completely, only a client on
-- rapid fire gets slowed down
local logBudget = {}
Commands.logAction = function(player, args)
    if not args or type(args.text) ~= "string" or args.text == "" then return end
    local area = args.area
    local valid = false
    for _, b in ipairs(AegisShared.AREAS) do
        if b == area then valid = true break end
    end
    if not valid or not AegisRoles.canArea(player, area) then return end
    local name = player:getUsername()
    local now = AegisShared.realTime()
    local b = logBudget[name] or { tokens = 8, lastAt = now }
    b.tokens = math.min(8, b.tokens + (now - b.lastAt))
    b.lastAt = now
    logBudget[name] = b
    if b.tokens < 1 then return end
    b.tokens = b.tokens - 1
    AegisLog.write("Actions", name, name, args.text:sub(1, 300))
end

-- ---------- restart timer ----------
-- The server counts down in real time and broadcasts announcements as
-- banners to all clients; at the end it sends the triggering admin a
-- quitRelay, whose client runs /quit resp. /restart (the hoster's panel
-- handles the rest). The plan survives server restarts: it sits as a
-- status file on disk and is cleared again after firing, on cancel or
-- when the deadline has passed
local restartPlan = nil
-- recurring cycle: { hours, nextAt (epoch) }
local interval = nil
local RESTART_FILE = AegisStore.ROOT .. "/Status/restart.txt"
-- OnServerStarted and OnGameStart both fire on boot, without this guard
-- loadRestartPlan loads the plan twice and the banners go out twice
-- (same pattern as leftoversChecked in Aegis_Log.lua)
local restartLoaded = false

local function saveRestartPlan()
    local lines = {}
    if restartPlan then
        table.insert(lines, "PLAN|" .. tostring(restartPlan.endsAt) .. "|" .. (restartPlan.by or ""))
    end
    if interval then
        table.insert(lines, "INT|" .. tostring(interval.hours) .. "|" .. tostring(interval.nextAt))
    end
    local content = table.concat(lines, "\n")
    if #lines > 0 then content = content .. "\n" end
    AegisStore.write(RESTART_FILE, content)
end

-- key + parameter instead of finished text: the dedicated server has no
-- UI translations loaded, the client translates on receipt
local function broadcast(key, param)
    local args = { key = key, par = param }
    if isServer() then
        sendServerCommand(AegisShared.MODULE, "banner", args)
    else
        triggerEvent("OnServerCommand", AegisShared.MODULE, "banner", args)
    end
end

local function sendRestartStatus(player)
    local remaining = -1
    if restartPlan then
        remaining = math.max(0, restartPlan.endsAt - AegisShared.realTime())
    end
    toClient(player, "restartStatus", {
        remaining = remaining,
        intHours = interval and interval.hours or 0,
        intNext = interval and interval.nextAt or 0,
    })
end

Commands.restart = function(player, args)
    if not AegisRoles.canArea(player, "server") then
        toClient(player, "denied", { area = "server" })
        return
    end
    if args and args.cancel then
        if restartPlan then
            -- a cancelled automatic round jumps to the next cycle slot,
            -- otherwise the watcher rearms it immediately
            if restartPlan.by == "Server" and interval then
                interval.nextAt = interval.nextAt + interval.hours * 3600
            end
            restartPlan = nil
            saveRestartPlan()
            broadcast("UI_Aegis_RestartCancelled")
            AegisLog.write("Actions", player:getUsername(), player:getUsername(), "Server restart cancelled")
        end
        sendRestartStatus(player)
        return
    end
    local minutes = math.floor(tonumber(args and args.minutes) or 0)
    if minutes < 1 or minutes > 10080 then return end
    restartPlan = {
        endsAt = AegisShared.realTime() + minutes * 60,
        by = player:getUsername(),
        marks = {},
    }
    -- tick off marks above the start time right away, otherwise the
    -- watcher repeats the start announcement on the first tick
    for _, m in ipairs({ 30, 15, 10, 5, 2, 1 }) do
        if minutes <= m then restartPlan.marks[m] = true end
    end
    saveRestartPlan()
    if minutes >= 180 then
        broadcast("UI_Aegis_RestartAnnounceHours", math.floor(minutes / 60 + 0.5))
    else
        broadcast("UI_Aegis_RestartAnnounce", minutes)
    end
    AegisLog.write("Actions", player:getUsername(), player:getUsername(),
        "Server restart announced in " .. minutes .. " minutes")
    sendRestartStatus(player)
end

-- free-text announcement as the golden banner for every player (the
-- chat alert goes through the vanilla /servermsg relay client-side)
Commands.announce = function(player, args)
    if not AegisRoles.canArea(player, "server") then
        toClient(player, "denied", { area = "server" })
        return
    end
    local text = tostring(args and args.text or ""):sub(1, 200)
    if text == "" then return end
    if isServer() then
        sendServerCommand(AegisShared.MODULE, "banner", { text = text })
    else
        triggerEvent("OnServerCommand", AegisShared.MODULE, "banner", { text = text })
    end
    AegisLog.write("Actions", player:getUsername(), player:getUsername(), "Announcement banner: " .. text)
end

Commands.restartStatus = function(player, args)
    if not AegisRoles.canArea(player, "server") then
        toClient(player, "denied", { area = "server" })
        return
    end
    sendRestartStatus(player)
end

-- execution trace of the quit relay: without it nobody could tell from
-- the logs whether any client ever picked the relay up, which made
-- "alerts ran, restart never came" unanswerable
Commands.relayRan = function(player, args)
    if not AegisRoles.isVanillaAdmin(player) then return end
    local name = player:getUsername() or "?"
    AegisLog.write("Actions", name, name,
        "Restart relay executed: /restart sent, /quit follows if the server survives")
end

-- recurring restart cycle, 0 turns it off
Commands.restartInterval = function(player, args)
    if not AegisRoles.canArea(player, "server") then
        toClient(player, "denied", { area = "server" })
        return
    end
    local hours = math.floor(tonumber(args and args.hours) or 0)
    if hours <= 0 then
        interval = nil
        -- a countdown already armed by the cycle (restartPlan.by == "Server")
        -- must be cancelled along with it, otherwise it keeps firing at the
        -- originally planned time despite the automation being off
        if restartPlan and restartPlan.by == "Server" then
            restartPlan = nil
            broadcast("UI_Aegis_RestartCancelled")
        end
        AegisLog.write("Actions", player:getUsername(), player:getUsername(), "Automatic restart turned off")
    elseif hours <= 48 then
        -- startIn: minutes until the first slot (anchor time the client
        -- sends as a difference, so time zones play no role)
        local startIn = math.floor(tonumber(args and args.startIn) or 0)
        if startIn < 1 or startIn > 1440 then startIn = hours * 60 end
        interval = { hours = hours, nextAt = AegisShared.realTime() + startIn * 60 }
        AegisLog.write("Actions", player:getUsername(), player:getUsername(),
            "Automatic restart: every " .. hours .. " hours, first in " .. startIn .. " minutes")
    else
        return
    end
    saveRestartPlan()
    sendRestartStatus(player)
end

local MARKS = { 30, 15, 10, 5, 2, 1 }

local function restartWatch()
    -- the cycle arms a normal countdown half an hour before the slot,
    -- which then runs through the usual warning cascade
    if interval and not restartPlan then
        local untilNext = interval.nextAt - AegisShared.realTime()
        if untilNext <= 1800 then
            restartPlan = { endsAt = interval.nextAt, by = "Server", marks = {} }
            local minutes = math.max(1, math.ceil(untilNext / 60))
            for _, m in ipairs(MARKS) do
                if minutes <= m then restartPlan.marks[m] = true end
            end
            saveRestartPlan()
            broadcast("UI_Aegis_RestartAnnounce", minutes)
        end
    end
    if not restartPlan then return end
    local now = AegisShared.realTime()
    local remaining = restartPlan.endsAt - now
    if remaining <= 0 then
        -- EveryOneMinute counts GAME minutes: on a three hour day it fires
        -- every seven and a half real seconds, and the relay went out at
        -- that rate. The client resent /restart faster than its own eight
        -- second /quit fallback could ever run, so the server never went
        -- down. Attempts are spaced in REAL seconds now, the tick rate only
        -- decides how precisely we hit the mark
        if restartPlan.lastTry and (now - restartPlan.lastTry) < 60 then return end
        restartPlan.lastTry = now
        restartPlan.tries = (restartPlan.tries or 0) + 1
        if restartPlan.tries == 1 then
            broadcast("UI_Aegis_RestartNow")
            AegisLog.write("Actions", restartPlan.by, restartPlan.by, "Server restart triggered")
        end
        if isServer() then
            -- the server queues its own quit first, the same call /quit
            -- makes. Whether it really takes the server down cannot be
            -- observed from here, so the relay still goes out and the
            -- retry loop below stays in charge. A server that is already
            -- shutting down simply never runs the next attempt
            if ServerMap ~= nil then
                pcall(function() ServerMap.instance:QueueQuit() end)
            end
            -- ANY online client with QuitWorld answers, always, not just the
            -- planner. It used to gate on "by" whenever the planner was
            -- still online, which sounds like the safer default but was
            -- backwards: while the planner was present, every OTHER admin
            -- with full quit rights was refused, so the restart depended on
            -- one specific person still being logged in. The planner is just another
            -- QuitWorld holder, no reason to single him out
            local relay = { anyone = true }
            sendServerCommand(AegisShared.MODULE, "quitRelay", relay)
            -- count who could even execute: /quit needs QuitWorld on the
            -- connection role. Zero on this line answers the next report
            -- ("alerts ran, nothing happened") straight from the console
            local able = 0
            pcall(function()
                local players = getOnlinePlayers()
                for i = 0, players:size() - 1 do
                    local pl = players:get(i)
                    local level = tostring(pl:getAccessLevel() or ""):lower()
                    local role = AegisShared.roleForLevel(level)
                    if role and role:hasCapability(Capability.QuitWorld) then able = able + 1 end
                end
            end)
            print("[Aegis] restart relay sent, attempt " .. restartPlan.tries
                .. " (anyone with QuitWorld), " .. able .. " client(s) able to quit")
            -- The relay needs a LIVING authorized client in exactly that
            -- moment. It used to fire once and clear the plan, executed or
            -- not: one loading screen at the wrong second and the alerts
            -- ran for nothing. A
            -- server that still lives one minute later proves the quit did
            -- not happen, so keep knocking; a successful quit ends this
            -- loop by taking the server down
            if restartPlan.tries < 10 then return end
            AegisLog.write("Actions", restartPlan.by, restartPlan.by,
                "Server restart NOT executed: no authorized client ran the relay within 10 minutes")
        end
        -- only a cycle round pushes the next slot forward, a manual
        -- restart leaves the cadence untouched
        if restartPlan.by == "Server" and interval then
            interval.nextAt = interval.nextAt + interval.hours * 3600
        end
        restartPlan = nil
        saveRestartPlan()
        return
    end
    local minutes = math.ceil(remaining / 60)
    for _, m in ipairs(MARKS) do
        if minutes <= m and not restartPlan.marks[m] then
            restartPlan.marks[m] = true
            broadcast("UI_Aegis_RestartAnnounce", minutes)
            break
        end
    end
end

Events.EveryOneMinute.Add(restartWatch)

-- resume a planned restart after a server start; a passed deadline (the
-- restart did happen) only clears the file
local function loadRestartPlan()
    if restartLoaded then return end
    restartLoaded = true
    local lines = AegisStore.readLines(RESTART_FILE, 4)
    if not lines or #lines == 0 then return end
    local now = AegisShared.realTime()
    for _, entry in ipairs(lines) do
        local endsAt, by = entry:match("^PLAN|(%d+)|(.*)$")
        if endsAt then
            endsAt = tonumber(endsAt)
            -- a passed plan has happened and only gets cleared
            if endsAt and endsAt - now >= 60 then
                restartPlan = { endsAt = endsAt, by = by ~= "" and by or "Server", marks = {} }
            end
        end
        local hours, nextAt = entry:match("^INT|(%d+)|(%d+)$")
        if hours then
            hours, nextAt = tonumber(hours), tonumber(nextAt)
            if hours and hours > 0 and nextAt then
                -- skip slots missed during a downtime
                while nextAt <= now + 60 do
                    nextAt = nextAt + hours * 3600
                end
                interval = { hours = hours, nextAt = nextAt }
            end
        end
    end
    saveRestartPlan()
    if restartPlan then
        local minutes = math.ceil((restartPlan.endsAt - now) / 60)
        for _, m in ipairs(MARKS) do
            if minutes <= m then restartPlan.marks[m] = true end
        end
        if minutes >= 180 then
            broadcast("UI_Aegis_RestartAnnounceHours", math.floor(minutes / 60 + 0.5))
        else
            broadcast("UI_Aegis_RestartAnnounce", minutes)
        end
        print("[Aegis] Scheduled restart resumed, " .. minutes .. " minutes left")
    end
    if interval then
        print("[Aegis] Automatic restart active: every " .. interval.hours .. " hours")
    end
end

Events.OnServerStarted.Add(loadRestartPlan)
-- says once per boot which way a scheduled restart will take
Events.OnServerStarted.Add(function()
    print("[Aegis] restart: server-side quit "
        .. (ServerMap ~= nil and "available" or "unavailable, falling back to the client relay"))
end)
Events.OnGameStart.Add(loadRestartPlan)

-- keep lures alive: a fresh noise pulse at the fixed spot every minute
-- until the runtime is over (if the initiator logs out the lure ends)
local function lureWatch()
    if #lures == 0 then return end
    local now = AegisShared.realTime()
    for i = #lures, 1, -1 do
        local k = lures[i]
        if now >= k.expiresAt then
            table.remove(lures, i)
        else
            local ok = pcall(function()
                addSound(k.players, k.x, k.y, k.z, k.radius, 100)
            end)
            if not ok then
                table.remove(lures, i)
            end
        end
    end
end

Events.EveryOneMinute.Add(lureWatch)

-- ---------- head tag visibility ----------
-- the engine derives the sent tag bit from active admin powers alone,
-- so a plain tag role never shows and a hidden tag only vanishes on the
-- own screen. This ledger makes both choices global, every client
-- re-applies it to its local copies (see AegisRoleTag). One name per
-- line, a listed name wants its tag hidden
local hideTags = nil
local HIDE_FILE = AegisStore.ROOT .. "/Roles/hidetags.txt"

local function loadHideTags()
    if hideTags then return end
    hideTags = {}
    local lines = AegisStore.readLines(HIDE_FILE, 2000)
    for _, n in ipairs(lines or {}) do
        if n ~= "" then hideTags[n] = true end
    end
end

local function hideNames()
    local out = {}
    for n in pairs(hideTags) do table.insert(out, n) end
    table.sort(out)
    return out
end

Commands.tagHide = function(player, args)
    if not AegisRoles.canArea(player, "powers") then return end
    loadHideTags()
    local name = player:getUsername()
    if not name then return end
    local on = args and args.on == true
    if (hideTags[name] == true) == on then return end
    hideTags[name] = on and true or nil
    local names = hideNames()
    AegisStore.write(HIDE_FILE, #names > 0 and (table.concat(names, "\n") .. "\n") or "")
    AegisLog.write("Actions", name, name, on and "Head tag hidden" or "Head tag shown")
    sendServerCommand(AegisShared.MODULE, "tagHide", { names = names })
end

Commands.tagHideReq = function(player, args)
    loadHideTags()
    sendServerCommand(player, AegisShared.MODULE, "tagHide", { names = hideNames() })
end

local function onClientCommand(module, command, player, args)
    if module ~= "AegisAdmin" then return end
    -- suspended admins may not operate any Aegis area anymore
    if AegisModeration.isSuspended(player) then return end
    if Commands[command] then
        Commands[command](player, args)
    end
end

Events.OnClientCommand.Add(onClientCommand)
