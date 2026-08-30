if not isServer() then
    return
end
local Core = PhunZones

PhunZonesEventRegistry = PhunZonesEventRegistry or {}
local registry = PhunZonesEventRegistry.rv or {}
PhunZonesEventRegistry.rv = registry
Core._rvEventHandlers = registry

local function removeHandler(event, fn)
    if event and fn and event.Remove then pcall(event.Remove, fn) end
end
removeHandler(Events[Core.events.OnPhunZoneReady], registry.ready)
removeHandler(Events.OnTick, registry.tick)
registry.ready, registry.tick, registry.tickInstalled = nil, nil, false

-- Desembrulha somente se a funcao global ainda for exatamente nossa. Se um
-- terceiro mod instalou um wrapper por cima, nao o sobrescreva nem acrescente
-- outra camada PhunZones na cadeia.
local getInCanWrap = true
if registry.getInWrapper then
    if GetInToRV == registry.getInWrapper then
        GetInToRV = registry.getInBase
        registry.getInWrapper, registry.getInBase = nil, nil
    else
        getInCanWrap = false
    end
end
local getOutCanWrap = true
if registry.getOutWrapper and RVServer and RVServer.GetOutFromRV then
    if RVServer.GetOutFromRV == registry.getOutWrapper then
        RVServer.GetOutFromRV = registry.getOutBase
        registry.getOutWrapper, registry.getOutBase = nil, nil
    else
        getOutCanWrap = false
    end
end

local activeMods = getActivatedMods()
if not activeMods:contains("PROJECTRVInterior42") then
    print("[PhunZones]PROJECTRVInterior42 not active, skipping integration")
    return
else
    print("[PhunZones] PROJECTRVInterior42 active, loading integration")
end

require "RVServerMP_V3"

if GetInToRV and getInCanWrap then
    local oldGetInToRV = GetInToRV
    local function wrappedGetInToRV(player, vehicle)

        local result = oldGetInToRV(player, vehicle)

        if not player then return result end

        local rvPlayerId = player:getModData().projectRV_playerId
        local modData = ModData.getOrCreate("modPROJECTRVInterior")

        local md = ModData.getOrCreate("PhunZonesRVInfo")

        if type(md.players) ~= "table" then md.players = {} end
        md.players[player:getUsername()] = {}

        local p = modData.Players and modData.Players[rvPlayerId]
        if not p then
            return result
        end
        local v = modData.Vehicles and modData.Vehicles[p.VehicleId]

        if v and v.x then
            md.players[player:getUsername()] = {
                vid = p.VehicleId,
                zone = (PhunZones.getLocation(v.x, v.y) or {}).key
            }
        end

        return result
    end
    registry.getInBase = oldGetInToRV
    registry.getInWrapper = wrappedGetInToRV
    GetInToRV = wrappedGetInToRV
end

if RVServer and RVServer.GetOutFromRV and getOutCanWrap then
    local oldRVServerGetOutFromRV = RVServer.GetOutFromRV
    local function wrappedGetOutFromRV(player, vehicle)
        local result = oldRVServerGetOutFromRV(player, vehicle)
        if not player then return result end
        local md = ModData.getOrCreate("PhunZonesRVInfo")
        if type(md.players) ~= "table" then md.players = {} end
        md.players[player:getUsername()] = nil
        return result
    end
    registry.getOutBase = oldRVServerGetOutFromRV
    registry.getOutWrapper = wrappedGetOutFromRV
    RVServer.GetOutFromRV = wrappedGetOutFromRV
end

local function processVehicleZoneChanges()
    local md = ModData.getOrCreate("PhunZonesRVInfo")
    local rvData = ModData.getOrCreate("modPROJECTRVInterior")

    if type(md.players) ~= "table" then md.players = {} end
    local vehicles = type(rvData.Vehicles) == "table" and rvData.Vehicles or {}
    for k, v in pairs(md.players) do
        local player = Core.tools.getPlayerByUsername(k)
        if not player or type(v) ~= "table" then
            -- Crash/desconexao dentro do RV nao passa necessariamente por
            -- GetOutFromRV; remova registros mortos do loop permanente.
            md.players[k] = nil
        else
        local vehicleData = vehicles[v.vid]
        if vehicleData and vehicleData.x and vehicleData.y then
            local loc = Core.getLocation(vehicleData.x, vehicleData.y)
            if loc and loc.key and loc.key ~= v.zone then
                Core.debugLn(k .. "'s vehicle zone changed from " .. tostring(v.zone) .. " to " .. tostring(loc.key))
                sendServerCommand(player, Core.name, Core.commands.updateEffectiveZone, {
                    player = k,
                    zone = loc.key
                })
                v.zone = loc.key
            end
        end
        end
    end
end

local nextCheck = 0
local function onRVTick()
    local now = getTimestamp()
    if type(now) ~= "number" or now ~= now or now == math.huge or now == -math.huge then return end
    if now >= nextCheck then
        local interval = tonumber(Core.settings.updateInterval) or 2
        if interval ~= interval or interval < 0.1 or interval == math.huge then interval = 2 end
        nextCheck = now + interval
        processVehicleZoneChanges()
    end
end
registry.tick = onRVTick

local function onReady()
    if registry.tickInstalled then return end
    registry.tickInstalled = true
    Events.OnTick.Add(onRVTick)
end
registry.ready = onReady
Events[Core.events.OnPhunZoneReady].Add(onReady)

