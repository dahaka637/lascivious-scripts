if isServer() then
    return
end
local Core = PhunZones

local activeMods = getActivatedMods()
local bandits2Active = activeMods:contains("Bandits2")

local function actionValue(value)
    local legacy = { ["1"] = "none", ["2"] = "move", ["3"] = "remove" }
    return legacy[tostring(value)] or value
end

-- Evicts entities for the "move" action (legacy value 2). Removal is handled
-- client-side in client_events and confirmed authoritatively by the server.
Core.evictZeds = function(playerObj, zoneKey)
    if not playerObj or not zoneKey then
        return
    end

    local zone = Core.data and Core.data.lookup and Core.data.lookup[zoneKey] or {}
    local shouldEvictZeds = actionValue(zone.zeds) == "move"
    local shouldEvictBandits = bandits2Active and actionValue(zone.bandits) == "move"

    if not shouldEvictZeds and not shouldEvictBandits then
        return
    end

    local zombies = playerObj:getCell():getZombieList()
    for i = 0, zombies:size() - 1 do
        local zed = zombies:get(i)
        if instanceof(zed, "IsoZombie") then
            local zedZone = Core.getLocation(zed:getX(), zed:getY())
            if zedZone and zedZone.key == zoneKey then
                local isBandit = bandits2Active and zed:getModData().brain ~= nil
                local shouldEvict = (isBandit and shouldEvictBandits) or (not isBandit and shouldEvictZeds)
                if shouldEvict then
                    local ex, ey, ez = Core.findNearestSafePosition(zed:getX(), zed:getY(), zed:getZ(), zoneKey)
                    if ex then
                        zed:setX(ex + ZombRand(-2, 2))
                        zed:setY(ey + ZombRand(-2, 2))
                        zed:setZ(ez)
                    end
                end
            end
        end
    end
end

if bandits2Active then
    -- Prevent bandits mod from spawning bandits in zones with any bandit action set
    local BanditScheduler = BanditScheduler
    if BanditScheduler then
        if not BanditScheduler._phunZonesOriginalGenerateSpawnPoint then
            BanditScheduler._phunZonesOriginalGenerateSpawnPoint = BanditScheduler.GenerateSpawnPoint
        end
        local oldfn = BanditScheduler._phunZonesOriginalGenerateSpawnPoint

        if type(oldfn) == "function" then
            function BanditScheduler.GenerateSpawnPoint(player, d)
                local currentCore = PhunZones
                local zone = player and currentCore and currentCore.getLocation
                    and currentCore.getLocation(player:getX(), player:getY())

                local action = zone and actionValue(zone.bandits) or nil
                if action == "move" or action == "remove" then
                    return false
                end

                return oldfn(player, d)
            end
        end
    end
end
