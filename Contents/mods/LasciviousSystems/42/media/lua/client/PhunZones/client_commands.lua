if isServer() then
    return
end

local Core = PhunZones

local Commands = {}

local function hasEntries(value)
    if type(value) ~= "table" then return false end
    for _ in pairs(value) do return true end
    return false
end

Commands[Core.commands.playerSetup] = function(data)
    data = type(data) == "table" and data or {}
    ModData.add(Core.const.modifiedModData, type(data.data) == "table" and data.data or {})
    Core.updateZoneData()

    local players = Core.tools.onlinePlayers()
    for i = 0, players:size() - 1 do
        local p = players:get(i)
        Core.updateModData(p, true, true)
    end
end

Commands[Core.commands.zoneUpdated] = function(data)
    data = type(data) == "table" and data or {}
    -- data.data is only set by playerSetup; zoneUpdated sends data.changes.
    -- Calling ModData.add with an empty table can wipe the client's zone data,
    -- so only update ModData when the server actually provides a full dataset.
    -- OnReceiveGlobalModData (triggered by ModData.transmit on the server) handles
    -- the authoritative full-data sync for all clients.
    if data.replace == true and type(data.data) == "table" then
        -- Full import may intentionally be empty; unlike the incremental path,
        -- an empty table here means "clear all customisations", not "no data".
        ModData.add(Core.const.modifiedModData, data.data)
    elseif hasEntries(data.data) then
        ModData.add(Core.const.modifiedModData, data.data)
    end
    Core.updateZoneData()
    local players = Core.tools.onlinePlayers()
    for i = 0, players:size() - 1 do
        local p = players:get(i)
        Core.updateModData(p, true, true)
    end
end

Commands[Core.commands.updateEffectiveZone] = function(data)
    if type(data) ~= "table" then return end
    local player = Core.tools.getPlayerByUsername(data.player)
    if player then
        Core.setEffectiveZone(player, data.zone)
    end
end

Commands[Core.commands.playerTeleport] = function(data)
    if type(data) ~= "table" then return end
    local player = Core.tools.getPlayerByUsername(data.username)
    if player then Core.portPlayer(player, data.x, data.y, data.z) end
end

Commands[Core.commands.replaceZonesResult] = function(data)
    data = type(data) == "table" and data or {}
    local editor = Core.ui and Core.ui.configEditor
    if editor and type(editor.onReplaceZonesResult) == "function" then
        editor.onReplaceZonesResult(data)
    end
end

Commands[Core.commands.teleportVehicle] = function(data)
    if type(data) ~= "table" then return end
    local vehicle = getVehicleById(data.id)
    local player = Core.tools.getPlayerByUsername(data.username)
    if player and vehicle then
        Core.teleportVehicleToCoords(player, vehicle, data.x, data.y, data.z)
    end
end

return Commands
