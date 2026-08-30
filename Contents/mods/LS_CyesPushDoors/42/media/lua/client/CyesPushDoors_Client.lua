if isServer() then return end

require "CyesPushDoors/Core"
require "CyesPushDoors/Settings"
require "CyesPushDoors/Hook"

local CPD = CyesPushDoors
local C = CPD.Config
local S = CPD.Settings
CPD.mpDebug("CLIENT_LOAD", "CyesPushDoors_Client.lua loaded")

local function findZombie(args)
    if not args or args.x == nil or args.y == nil or args.z == nil then return nil end
    local id = tonumber(args.id)
    if id == nil or id < 0 then return nil end
    local cx, cy, cz = tonumber(args.x), tonumber(args.y), tonumber(args.z)
    if not cx or not cy or not cz then return nil end

    for radius = 0, 2 do
        for x = cx - radius, cx + radius do
            for y = cy - radius, cy + radius do
                if radius == 0 or x == cx - radius or x == cx + radius or y == cy - radius or y == cy + radius then
                    local sq = getCell():getGridSquare(x, y, cz)
                    local moving = sq and sq:getMovingObjects() or nil
                    if moving then
                        for i = 0, moving:size() - 1 do
                            local object = moving:get(i)
                            if object and instanceof(object, "IsoZombie") then
                                local onlineId = tonumber(object:getOnlineID())
                                if onlineId == id then
                                    return object
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    return nil
end

local function findLocalPlayer(args)
    local wantedId = args and tonumber(args.playerId) or nil

    if wantedId ~= nil and getNumActivePlayers and getSpecificPlayer then
        local count = getNumActivePlayers()
        for i = 0, count - 1 do
            local player = getSpecificPlayer(i)
            if player and tonumber(player:getOnlineID()) == wantedId then
                return player
            end
        end
    end

    return getPlayer and getPlayer() or nil
end

local function combatTextAvailable()
    return CombatText ~= nil
        and CombatText.Fn ~= nil
        and type(CombatText.Fn.getEntityId) == "function"
        and CombatTextCache ~= nil
        and CombatTextCache.TrackingList ~= nil
        and CombatTextCache.HealthBarManagers ~= nil
end

local function getCombatTextTimestamp()
    local ok, value = pcall(function()
        return getGameTime():getCalender():getTimeInMillis()
    end)
    if ok and value then return value end
    return getTimestampMs and getTimestampMs() or 0
end

function CPD.onCombatTextDoorHit(zombie, oldHealth, newHealth)
    if not zombie or not combatTextAvailable() then return false end

    oldHealth = tonumber(oldHealth)
    newHealth = tonumber(newHealth)
    if not oldHealth or not newHealth or newHealth >= oldHealth then return false end

    local okUid, uid = pcall(CombatText.Fn.getEntityId, zombie)
    if not okUid or uid == nil then return false end

    local oldHp = oldHealth * 100.0
    local tick = getCombatTextTimestamp()
    local tracking = CombatTextCache.TrackingList[uid]

    if tracking == nil then
        tracking = {
            fullHp = oldHp,
            hp = oldHp,
            isDead = false,
            entity = zombie,
            isOnFire = false,
            isBleeding = false,
            weapon = nil,
            isCrit = false,
            tick = tick,
        }
        CombatTextCache.TrackingList[uid] = tracking
        CombatTextCache.TrackingListCount = (tonumber(CombatTextCache.TrackingListCount) or 0) + 1
    else
        tracking.entity = zombie
        tracking.hp = oldHp
        if tracking.fullHp == nil or tonumber(tracking.fullHp) == nil or tonumber(tracking.fullHp) < oldHp then
            tracking.fullHp = oldHp
        end
        tracking.isDead = false
        tracking.isOnFire = zombie:isOnFire()
        tracking.isBleeding = false
        tracking.weapon = nil
        tracking.isCrit = false
        tracking.tick = tick
    end

    for _, manager in pairs(CombatTextCache.HealthBarManagers) do
        if manager then
            pcall(function() manager:onHit(uid, nil, false, tracking) end)
            local bar = manager.barList and manager.barList[uid] or nil
            if bar then
                bar.entity = zombie
                bar.weapon = nil
                bar.isCrit = false
                bar.isDead = false
                bar.currentHp = oldHp
                if not bar.maxHp or bar.maxHp < oldHp then bar.maxHp = oldHp end
                bar.hpChange = 0
                bar.isChangingHp = false
                bar.hpChangeStart = nil
            end
        end
    end

    CPD.log("Combat Text tracked door hit uid=" .. tostring(uid) ..
        " hp=" .. string.format("%.2f", oldHp) .. "->" .. string.format("%.2f", newHealth * 100.0))
    return true
end

local function onServerCommand(module, command, args)
    if module ~= "CyesPushDoors" then return end

    if command == "impactSound" then
        local player = findLocalPlayer(args)
        if S.impactFeedbackEnabled() and player and args and args.sound then
            pcall(function() player:playSoundLocal(tostring(args.sound)) end)
        end
        return
    end

    if command == "doorHealth" then
        local door = CPD.findDoor(args)
        if door and args.health ~= nil then
            door:setHealth(tonumber(args.health) or door:getHealth())
        end
        return
    end

    if command == "armStrainSync" then
        local player = findLocalPlayer(args)
        if player then CPD.setArmStrainAbsolute(player, args) end
        return
    end

    if command == "combatTextHit" then
        local zombie = findZombie(args)
        if zombie and args.oldHealth ~= nil and args.newHealth ~= nil then
            CPD.onCombatTextDoorHit(zombie, tonumber(args.oldHealth), tonumber(args.newHealth))
        end
        return
    end

    if command == "playerImpact" then
        if args and args.knockedDown == true then
            local player = findLocalPlayer(args)
            if player and player:isAlive() then
                player:setKnockedDown(true)
            end
        end
        return
    end

    if command == "zombieImpact" then
        CPD.mpDebug("CLIENT_RECEIVE",
            "zombieImpact id=" .. tostring(args and args.id) ..
            " hp=" .. tostring(args and args.health) ..
            " knock=" .. tostring(args and args.knockedDown) ..
            " stagger=" .. tostring(args and args.staggered) ..
            " staggerAnim=" .. tostring(args and args.staggerAnimation) ..
            " pos=" .. tostring(args and args.x) .. "," .. tostring(args and args.y) .. "," .. tostring(args and args.z))
        local zombie = findZombie(args)
        if not zombie then
            CPD.mpDebug("CLIENT_FIND_FAIL", "Could not find zombie for server payload id=" .. tostring(args and args.id))
            return
        end
        CPD.mpDebug("CLIENT_FIND_OK",
            "found zombie id=" .. tostring(zombie:getOnlineID()) ..
            " currentHp=" .. tostring(zombie:getHealth()))
        if args.health ~= nil then
            local expected = tonumber(args.health) or zombie:getHealth()
            local before = zombie:getHealth()
            zombie:setHealth(expected)
            CPD.mpDebug("CLIENT_HEALTH_APPLY",
                "zombieId=" .. tostring(zombie:getOnlineID()) ..
                " hp=" .. tostring(before) .. "->" .. tostring(zombie:getHealth()) ..
                " expected=" .. tostring(expected))
            CPD.queueZombieDamageVerification(nil, zombie, expected, expected <= 0)
        end

        if args.slidingAnimated == true then
            if S.impactFeedbackEnabled() and args.hitAnimation ~= nil and CPD and CPD.playSlidingDoorAnimation then
                CPD.playSlidingDoorAnimation(zombie, tostring(args.hitAnimation))
            end
        elseif args.crawlerStunned == true then
            pcall(function() zombie:setHitLegsWhileOnFloor(true) end)
            pcall(function() zombie:setHitTime(C.CRAWLER_STUN_HIT_TIME) end)
        elseif args.knockedDown == true then
            local okKnock = pcall(function() zombie:knockDown(false) end)
            if not okKnock then zombie:setKnockedDown(true) end
        elseif args.staggered == true then
            if S.impactFeedbackEnabled() and args.staggerAnimation ~= nil and CPD and CPD.playDoorStaggerAnimation then
                CPD.playDoorStaggerAnimation(zombie, tostring(args.staggerAnimation))
            end
        end
        CPD.mpDebug("CLIENT_REACTION_APPLY",
            "zombieId=" .. tostring(zombie:getOnlineID()) ..
            " knock=" .. tostring(args.knockedDown == true) ..
            " stagger=" .. tostring(args.staggered == true) ..
            " staggerAnim=" .. tostring(args.staggerAnimation) ..
            " crawler=" .. tostring(args.crawlerStunned == true) ..
            " sliding=" .. tostring(args.slidingAnimated == true))

        if sendClientCommand then
            local ack = {
                id = tonumber(zombie:getOnlineID()),
                health = tonumber(zombie:getHealth()),
                syncToken = args and args.syncToken or nil,
            }
            local okAck, errAck = pcall(function()
                sendClientCommand("CyesPushDoors", "zombieImpactAck", ack)
            end)
            if okAck then
                CPD.mpDebug("CLIENT_ACK",
                    "zombieId=" .. tostring(ack.id) ..
                    " hp=" .. tostring(ack.health) ..
                    " token=" .. tostring(ack.syncToken))
            else
                CPD.mpDebug("CLIENT_ACK_FAIL", tostring(errAck))
            end
        end
    end
end

Events.OnServerCommand.Add(onServerCommand)
