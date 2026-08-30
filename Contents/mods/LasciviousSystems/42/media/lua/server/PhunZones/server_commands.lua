if isClient() then
    return
end
local Commands = {}
local Core = PhunZones

local MAX_ZONE_CHANGES = 128
local MAX_FIELDS_PER_ZONE = 64
local MAX_POINTS_PER_ZONE = 256
local MAX_TOTAL_CHUNK_CELLS = 100000
local MAX_COORD = 1000000
local CHUNK_SIZE = 300

local STRUCTURAL_FIELDS = {
    points = true, inherits = true, isolated = true, disabled = true, enabled = true,
    order = true, modsRequired = true, modsAllRequired = true, modsExcluded = true
}

local function finiteNumber(value)
    local n = tonumber(value)
    if not n or n ~= n or n == math.huge or n == -math.huge then return nil end
    return n
end

local function validZoneKey(key)
    return type(key) == "string" and key ~= "" and #key <= 128 and not key:find("[%c]")
end

local function canEditZones(player)
    if Core.isLocal then return true end
    if not player then return false end
    local okCoop, coop = pcall(function() return isCoopHost() end)
    if okCoop and coop == true then
        local okLocal, localFlag = pcall(function()
            return player.isLocalPlayer and player:isLocalPlayer()
        end)
        if okLocal and localFlag == true then return true end
        local okPlayer, localPlayer = pcall(function() return getPlayer and getPlayer() end)
        if okPlayer and localPlayer and localPlayer == player then return true end
    end
    local ok, allowed = pcall(function()
        local role = player:getRole()
        local required = Core.getOption("EditorRole", "")
        if type(required) == "string" and required ~= "" then
            local roleName = role and role:getName()
            if type(roleName) ~= "string" or roleName:lower() ~= required:lower() then return false end
        end
        return role and role:hasCapability(Capability.CanSetupNonPVPZone) == true
    end)
    return ok and allowed == true
end

local function sanitizeString(value)
    if type(value) ~= "string" or #value > 2048 or value:find("%z") then return nil end
    return value
end

local function sanitizeChanges(changes)
    if type(changes) ~= "table" then return nil, "changes_not_table" end
    local clean, zoneCount, totalChunkCells = {}, 0, 0
    for key, zoneData in pairs(changes) do
        zoneCount = zoneCount + 1
        if zoneCount > MAX_ZONE_CHANGES then return nil, "too_many_zones" end
        if not validZoneKey(key) or type(zoneData) ~= "table" then return nil, "invalid_zone" end
        local out, fieldCount = {}, 0
        for field, value in pairs(zoneData) do
            fieldCount = fieldCount + 1
            if fieldCount > MAX_FIELDS_PER_ZONE or type(field) ~= "string"
                or (not STRUCTURAL_FIELDS[field] and not Core.fields[field]) then
                return nil, "invalid_field"
            end
            if field == "points" then
                if type(value) ~= "table" then return nil, "invalid_points" end
                local pointCount = 0
                for pointKey in pairs(value) do
                    if type(pointKey) ~= "number" or pointKey < 1 or pointKey ~= math.floor(pointKey) then
                        return nil, "invalid_points"
                    end
                    pointCount = pointCount + 1
                end
                if pointCount ~= #value or pointCount > MAX_POINTS_PER_ZONE then return nil, "invalid_points" end
                local points = {}
                for _, rect in ipairs(value) do
                    if type(rect) ~= "table" or #rect ~= 4 then return nil, "invalid_rect" end
                    local rectFields = 0
                    for rectKey in pairs(rect) do
                        if type(rectKey) ~= "number" or rectKey < 1 or rectKey > 4
                            or rectKey ~= math.floor(rectKey) then return nil, "invalid_rect" end
                        rectFields = rectFields + 1
                    end
                    if rectFields ~= 4 then return nil, "invalid_rect" end
                    local x1, y1 = finiteNumber(rect[1]), finiteNumber(rect[2])
                    local x2, y2 = finiteNumber(rect[3]), finiteNumber(rect[4])
                    if not x1 or not y1 or not x2 or not y2
                        or math.abs(x1) > MAX_COORD or math.abs(y1) > MAX_COORD
                        or math.abs(x2) > MAX_COORD or math.abs(y2) > MAX_COORD then
                        return nil, "invalid_rect"
                    end
                    if x1 > x2 then x1, x2 = x2, x1 end
                    if y1 > y2 then y1, y2 = y2, y1 end
                    x1, y1, x2, y2 = math.floor(x1), math.floor(y1), math.floor(x2), math.floor(y2)
                    local cells = (math.floor(x2 / CHUNK_SIZE) - math.floor(x1 / CHUNK_SIZE) + 1)
                        * (math.floor(y2 / CHUNK_SIZE) - math.floor(y1 / CHUNK_SIZE) + 1)
                    totalChunkCells = totalChunkCells + cells
                    if totalChunkCells > MAX_TOTAL_CHUNK_CELLS then return nil, "zone_area_too_large" end
                    table.insert(points, {x1, y1, x2, y2})
                end
                out.points = points
            elseif field == "isolated" or field == "disabled" or field == "enabled"
                or (Core.fields[field] and Core.fields[field].type == "boolean") then
                if type(value) ~= "boolean" then return nil, "invalid_boolean" end
                out[field] = value
            elseif field == "order" or (Core.fields[field] and Core.fields[field].type == "int") then
                local n = finiteNumber(value)
                if not n or math.abs(n) > MAX_COORD then return nil, "invalid_number" end
                out[field] = math.floor(n)
            elseif field == "inherits" or field == "modsRequired" or field == "modsAllRequired"
                or field == "modsExcluded" or (Core.fields[field] and Core.fields[field].type == "string") then
                local str = sanitizeString(value)
                if not str then return nil, "invalid_string" end
                out[field] = str
            else
                local valueType = type(value)
                if valueType == "number" then
                    value = finiteNumber(value)
                    if not value then return nil, "invalid_number" end
                elseif valueType == "string" then
                    value = sanitizeString(value)
                    if not value then return nil, "invalid_string" end
                elseif valueType ~= "boolean" then
                    return nil, "invalid_value"
                end
                out[field] = value
            end
        end
        clean[key] = out
    end
    return clean
end

Commands[Core.commands.playerSetup] = function(player)
    -- send any exemption/changes to the client
    local p = player
    if not p then return end
    local modData = p:getModData()

    if not modData.PhunZones or not modData.PhunZones.at then
        modData.PhunZones = {
            zone = nil,
            at = {}
        }
    end
    Core.updateModData(player, true, true)
    sendServerCommand(player, Core.name, Core.commands.playerSetup, {
        data = ModData.get(Core.const.modifiedModData) or {}
    })
end

Commands[Core.commands.modifyZone] = function(player, data)
    if type(data) ~= "table" or not canEditZones(player) then return end
    local changes, reason = sanitizeChanges(data.changes)
    if not changes then
        local okName, playerName = pcall(function() return player and player:getUsername() end)
        print("PhunZones: rejected modifyZone payload from " .. tostring(okName and playerName or "?") ..
            " (" .. tostring(reason) .. ")")
        return
    end
    Core.debug("[modifyZone]", changes)
    if not Core.saveChanges(changes) then return end

    Core.debug("[custom]", ModData.get(Core.const.modifiedModData))

    ModData.transmit(Core.const.modifiedModData)

end

Commands[Core.commands.replaceZones] = function(player, data)
    if type(data) ~= "table" or not player then return end
    local requestId = type(data.requestId) == "string" and data.requestId or ""
    if #requestId > 80 then requestId = "" end
    local function reply(ok, reason)
        sendServerCommand(player, Core.name, Core.commands.replaceZonesResult, {
            requestId = requestId,
            ok = ok == true,
            reason = reason
        })
    end
    if not canEditZones(player) then reply(false, "permission_denied"); return end
    local zones, reason = sanitizeChanges(data.zones)
    if not zones then
        local okName, playerName = pcall(function() return player and player:getUsername() end)
        print("PhunZones: rejected replaceZones payload from " .. tostring(okName and playerName or "?") ..
            " (" .. tostring(reason) .. ")")
        reply(false, reason)
        return
    end
    if not Core.replaceZones(zones) then
        print("PhunZones: failed to replace imported zone data")
        reply(false, "persistence_failed")
        return
    end
    reply(true)
end

Commands[Core.commands.deleteZone] = function(player, data)
    if not canEditZones(player) or type(data) ~= "table" or not validZoneKey(data.key) then return end
    if not Core.addDeletion(data.key) then return end
    ModData.transmit(Core.const.modifiedModData)
end

Commands[Core.commands.evictZeds] = function(player, args)
    -- A implementacao de movimento e client-only em B42; nao confie num
    -- comando remoto para teleportar entidades do servidor.
    return
end

local removeZedsLastAt = {}
local removeZedsCalls = 0

local function clockMs()
    local ok, now = pcall(getTimestampMs)
    now = ok and finiteNumber(now) or nil
    return now and now > 0 and now or nil
end

local function zedAction(value)
    local legacy = { ["1"] = "none", ["2"] = "move", ["3"] = "remove" }
    return legacy[tostring(value)] or value
end

Commands[Core.commands.removeZeds] = function(player, args)
    if not player then return end
    local okName, username = pcall(function() return player:getUsername() end)
    if not okName or type(username) ~= "string" then return end
    local now = clockMs()
    if not now then return end
    local previous = finiteNumber(removeZedsLastAt[username])
    if previous and now >= previous and now - previous < 1000 then return end
    removeZedsLastAt[username] = now
    removeZedsCalls = removeZedsCalls + 1
    if removeZedsCalls >= 256 then
        local cutoff = now - 60000
        for name, calledAt in pairs(removeZedsLastAt) do
            local validCalledAt = finiteNumber(calledAt)
            if not validCalledAt or validCalledAt < cutoff or validCalledAt > now then
                removeZedsLastAt[name] = nil
            end
        end
        removeZedsCalls = 0
    end
    Core.debug("Removing zeds in " .. tostring(args and args.zone), args)
    -- Re-derive from server state: only remove zeds that are
    -- (a) in the player's current cell, AND
    -- (b) in a zone that actually has zeds==3 action
    local zone = Core.getLocation(player:getX(), player:getY()) or {}
    if zedAction(zone.zeds) ~= "remove" then
        return -- player isn't even in a remove-zeds zone; ignore
    end

    local removed = {}
    local cell = player:getCell()
    local zombies = cell and cell:getZombieList()
    if not zombies then return end
    for i = zombies:size() - 1, 0, -1 do
        local zombie = zombies:get(i)
        if instanceof(zombie, "IsoZombie") then
            local zZone = Core.getLocation(zombie:getX(), zombie:getY()) or {}
            local id = Core.getZId(zombie)
            if id and zZone.key == zone.key then
                if Core.settings.Debug then
                    Core.debugLn(
                        "Removing zed " .. id .. " at " .. zombie:getX() .. "," .. zombie:getY() .. " in zone " ..
                            tostring(zZone.key))
                end
                table.insert(removed, tostring(id))
                zombie:removeFromWorld()
                zombie:removeFromSquare()
            end

        end
    end
    if #removed > 0 then
        triggerEvent(Core.events.OnZombieRemoved, removed)
    end
end

return Commands
