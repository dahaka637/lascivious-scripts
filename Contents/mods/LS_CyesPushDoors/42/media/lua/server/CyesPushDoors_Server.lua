if isClient() then return end

require "CyesPushDoors/Core"

local CPD = CyesPushDoors
local C = CPD.Config
CPD.mpDebug("SERVER_LOAD", "CyesPushDoors_Server.lua loaded")

local pendingDoors = {}
local doorCooldowns = {}
local interactionIntents = {}
local beginGates = {}
local INTENT_TTL_MS = 3000
local BEGIN_RATE_MS = 150

local function nowMs()
    if getTimestampMs then return getTimestampMs() end
    return math.floor(os.time() * 1000)
end

local function playerKey(player)
    if not player then return "nil" end
    local id = player:getOnlineID()
    if id ~= nil and tonumber(id) and tonumber(id) >= 0 then
        return tostring(id)
    end
    return tostring(player:getUsername() or player)
end

local function isCoolingDown(key, now)
    local last = doorCooldowns[key]
    return last ~= nil and (now - last) < C.SERVER_DOOR_COOLDOWN_MS
end

local function candidateIsBetter(a, b)
    if b == nil then return true end
    if a.interaction ~= b.interaction then
        return a.interaction == true
    end
    if a.distanceSq ~= b.distanceSq then
        return a.distanceSq < b.distanceSq
    end
    return a.receivedAt < b.receivedAt
end




local function validateRequestEnvelope(player, door, transition)
    if not player or not player:isAlive() or not door or not CPD.isSupportedDoor(door) then
        return false
    end

    local garage = CPD.isGarageDoor(door)
    transition = transition or (garage and "close" or "open")
    if garage and transition ~= "close" then return false end
    if not garage and transition ~= "open" then return false end

    local sq = door:getSquare()
    if not sq or sq:getZ() ~= player:getZ() then return false end

    local distSq = CPD.getPlayerDoorDistanceSq(player, door)
    if CPD.isDoubleDoor(door) then
        local parts = CPD.getDoubleDoorParts(door)
        for i = 1, #parts do
            local candidateDistance = CPD.getPlayerDoorDistanceSq(player, parts[i])
            if candidateDistance < distSq then distSq = candidateDistance end
        end
    end

    local maxDist = tonumber(C.MAX_SERVER_VALIDATION_DISTANCE) or 2.25
    return distSq <= (maxDist * maxDist)
end

local function queueDoorReport(player, args, door)
    local now = nowMs()
    local key = CPD.getDoorWorldKey(door)
    if isCoolingDown(key, now) then return nil, nil, "door-cooldown" end

    local recovering, remainingMs, recoveryBand = CPD.isImpactRecoveryActive(player)
    if recovering then
        return nil, nil, "muscle-recovery:" .. tostring(recoveryBand) .. ":" .. tostring(remainingMs)
    end

    local pending = pendingDoors[key]
    if not pending then
        pending = {
            firstAt = now,
            lastAt = now,
            hasInteraction = false,
            candidates = {},
        }
        pendingDoors[key] = pending
    else
        pending.lastAt = now
    end

    local candidate = {
        player = player,
        args = args,
        door = door,
        interaction = args.interaction == true,
        distanceSq = CPD.getPlayerDoorDistanceSq(player, door),
        receivedAt = now,
    }

    if candidate.interaction then pending.hasInteraction = true end

    local pKey = playerKey(player)
    local existing = pending.candidates[pKey]
    if existing == nil or candidateIsBetter(candidate, existing) then
        pending.candidates[pKey] = candidate
    end

    return key, pending, nil
end

local function isAttachedServerDoor(door)
    if not door or not CPD.isSupportedDoor(door) then return false end
    local sq = door:getSquare()
    if not sq then return false end
    local index = door:getObjectIndex()
    return index == nil or tonumber(index) == nil or tonumber(index) >= 0
end

local function serverDoorStateMatches(door, transition)
    if not isAttachedServerDoor(door) then return false end
    local garage = CPD.isGarageDoor(door)
    transition = transition or (garage and "close" or "open")
    if garage and transition ~= "close" then return false end
    if not garage and transition ~= "open" then return false end

    local ok, open = pcall(function() return door:IsOpen() end)
    if not ok then return false end
    if garage then return open == false end
    return open == true
end

local function serverDoorPreStateMatches(door, transition)
    if not isAttachedServerDoor(door) then return false end
    local ok, open = pcall(function() return door:IsOpen() end)
    if not ok then return false end
    if transition == "close" then return open == true end
    if transition == "open" then return open == false end
    return false
end

local function intentKey(player, door)
    return playerKey(player) .. "|" .. tostring(CPD.getDoorWorldKey(door))
end

local function recordInteractionIntent(player, args, door)
    if not validateRequestEnvelope(player, door, args.transition) then return false end
    if not serverDoorPreStateMatches(door, args.transition) then return false end
    if not CPD.findPreferredImpactSquare(args, door) then return false end
    local now = nowMs()
    local pKey = playerKey(player)
    if (beginGates[pKey] or 0) > now then return false end
    beginGates[pKey] = now + BEGIN_RATE_MS
    interactionIntents[intentKey(player, door)] = {
        at = now, transition = args.transition,
    }
    return true
end

local function hasInteractionIntent(player, args, door)
    local intent = interactionIntents[intentKey(player, door)]
    if not intent then return false end
    local age = nowMs()-(intent.at or 0)
    return age >= 0 and age <= INTENT_TTL_MS and intent.transition == args.transition
end

local function consumeInteractionIntent(player, door)
    interactionIntents[intentKey(player, door)] = nil
end

local function resolveCandidateDoor(candidate, key)
    if not candidate then return nil end

    
    
    
    local door = candidate.door
    if isAttachedServerDoor(door) and CPD.getDoorWorldKey(door) == key then
        return door
    end

    door = CPD.findDoor(candidate.args)
    if isAttachedServerDoor(door) and CPD.getDoorWorldKey(door) == key then
        candidate.door = door
        return door
    end
    return nil
end

local function resolvePendingDoor(key, pending)
    if not pending or pendingDoors[key] ~= pending then return false, "missing" end

    local best = nil
    local bestDoor = nil

    for _, candidate in pairs(pending.candidates) do
        local candidateDoor = resolveCandidateDoor(candidate, key)
        if candidate.intentVerified and candidateDoor
            and hasInteractionIntent(candidate.player, candidate.args, candidateDoor)
            and serverDoorStateMatches(candidateDoor, candidate.args.transition) then
            
            
            
            
            if candidateIsBetter(candidate, best) then
                best = candidate
                bestDoor = candidateDoor
            end
        end
    end

    local now = nowMs()
    local age = now - (pending.firstAt or now)
    if not best or not bestDoor then
        if pending.hasInteraction and age < (tonumber(C.SERVER_INTERACTION_STATE_GRACE_MS) or 500) then
            return false, "state-wait"
        end

        pendingDoors[key] = nil
        CPD.mpDebug("SERVER_RESOLVE_DROP",
            "no valid candidate key=" .. tostring(key) ..
            " interaction=" .. tostring(pending.hasInteraction == true) ..
            " ageMs=" .. tostring(age))
        return false, "invalid"
    end

    pendingDoors[key] = nil
    doorCooldowns[key] = now
    consumeInteractionIntent(best.player, bestDoor)

    local preferred = CPD.findPreferredImpactSquare(best.args, bestDoor)
    local transition = best.args.transition or (CPD.isGarageDoor(bestDoor) and "close" or "open")
    CPD.mpDebug("SERVER_RESOLVE_START",
        "player=" .. tostring(best.player and best.player:getUsername()) ..
        " transition=" .. tostring(transition) ..
        " interaction=" .. tostring(best.interaction == true) ..
        " kind=" .. tostring(best.args and best.args.interactionKind or "unknown") ..
        " queueAgeMs=" .. tostring(age) ..
        " doorKey=" .. tostring(key))

    local ok, result = pcall(CPD.resolveDoorImpact, best.player, bestDoor, preferred, transition)
    if not ok then
        print("[Cye's Push Doors!] Server impact error: " .. tostring(result))
        CPD.mpDebug("SERVER_RESOLVE_ERROR", tostring(result))
    else
        CPD.mpDebug("SERVER_RESOLVE_END", "resolveDoorImpact returned=" .. tostring(result))
    end
    return ok == true, "resolved"
end

local function processPendingDoors()
    local now = nowMs()
    for key, pending in pairs(pendingDoors) do
        if pending then
            local age = now - (pending.firstAt or now)
            if pending.hasInteraction then
                local _, status = resolvePendingDoor(key, pending)
                if status == "state-wait" and C.DEBUG == true then
                    
                    
                    CPD.mpDebug("SERVER_STATE_WAIT",
                        "waiting for vanilla door state key=" .. tostring(key) ..
                        " ageMs=" .. tostring(age))
                end
            elseif age >= C.SERVER_REPORT_WINDOW_MS then
                resolvePendingDoor(key, pending)
            end
        end
    end

    for key, last in pairs(doorCooldowns) do
        if (now - last) > 5000 then
            doorCooldowns[key] = nil
        end
    end
    for key, intent in pairs(interactionIntents) do
        if not intent or (now-(intent.at or 0)) > INTENT_TTL_MS then interactionIntents[key] = nil end
    end
    for key, untilAt in pairs(beginGates) do
        if untilAt <= now then beginGates[key] = nil end
    end
end

local function onClientCommand(module, command, player, args)
    if module ~= "CyesPushDoors" then return end

    if command == "zombieImpactAck" then
        CPD.mpDebug("SERVER_ACK",
            "player=" .. tostring(player and player:getUsername()) ..
            " zombieId=" .. tostring(args and args.id) ..
            " hp=" .. tostring(args and args.health) ..
            " token=" .. tostring(args and args.syncToken))
        return
    end

    if command == "doorInteractionBegin" then
        if type(args) ~= "table" then return end
        local door = CPD.findDoor(args)
        recordInteractionIntent(player, args, door)
        return
    end

    if command ~= "doorOpened" or not args then return end

    -- Scanner reports have no server-observed pre-state and therefore cannot
    -- prove causality. Only a tracked interaction may apply authoritative
    -- combat or door-wear effects in multiplayer.
    if args.interaction ~= true then return end

    CPD.mpDebug("SERVER_RECEIVE",
        "doorOpened player=" .. tostring(player and player:getUsername()) ..
        " transition=" .. tostring(args.transition) ..
        " door=" .. tostring(args.x) .. "," .. tostring(args.y) .. "," .. tostring(args.z) ..
        " index=" .. tostring(args.index) ..
        " interaction=" .. tostring(args.interaction == true) ..
        " kind=" .. tostring(args.interactionKind or "unknown"))

    local door = CPD.findDoor(args)
    local envelopeValid = validateRequestEnvelope(player, door, args.transition)
    local preferredImpactSquare = envelopeValid and CPD.findPreferredImpactSquare(args, door) or nil
    local impactSideValid = preferredImpactSquare ~= nil
    local stateValid = envelopeValid and CPD.validateServerRequest(player, door, args.transition) or false

    CPD.mpDebug("SERVER_VALIDATE",
        "doorFound=" .. tostring(door ~= nil) ..
        " envelope=" .. tostring(envelopeValid) ..
        " state=" .. tostring(stateValid) ..
        " impactSide=" .. tostring(impactSideValid) ..
        " worldKey=" .. tostring(door and CPD.getDoorWorldKey(door) or "nil"))

    if not envelopeValid then
        CPD.log("Rejected door transition envelope from " .. tostring(player and player:getUsername()))
        return
    end

    if not impactSideValid then
        CPD.log("Rejected door transition without a valid frozen impact side from " .. tostring(player and player:getUsername()))
        CPD.mpDebug("SERVER_IMPACT_SIDE_REJECT",
            "player=" .. tostring(player and player:getUsername()) ..
            " transition=" .. tostring(args.transition) ..
            " doorKey=" .. tostring(door and CPD.getDoorWorldKey(door) or "nil"))
        return
    end

    if not hasInteractionIntent(player, args, door) then
        CPD.log("Rejected door transition without a server-observed interaction intent from "
            .. tostring(player and player:getUsername()))
        return
    end

    if args.interaction ~= true and not stateValid then
        CPD.log("Rejected scanner door transition with stale server state from " .. tostring(player and player:getUsername()))
        return
    end

    local key, pending, queueReason = queueDoorReport(player, args, door)
    if not key or not pending then
        CPD.mpDebug("SERVER_QUEUE_SKIP",
            "reason=" .. tostring(queueReason or "unknown") ..
            " key=" .. tostring(door and CPD.getDoorWorldKey(door) or "nil") ..
            " interaction=" .. tostring(args.interaction == true))
        return
    end
    local candidate = pending.candidates[playerKey(player)]
    if candidate then candidate.intentVerified = true end

    CPD.mpDebug("SERVER_QUEUE",
        "door report queued interaction=" .. tostring(args.interaction == true) ..
        " kind=" .. tostring(args.interactionKind or
            (CPD.isGarageDoor(door) and "garage") or
            (CPD.isDoubleDoor(door) and "double-door") or "door") ..
        " stateReady=" .. tostring(stateValid))

    if args.interaction == true then
        if stateValid then
            CPD.mpDebug("SERVER_FAST_RESOLVE",
                "interaction state ready; resolving immediately key=" .. tostring(key))
            resolvePendingDoor(key, pending)
        else
            CPD.mpDebug("SERVER_STATE_WAIT",
                "interaction arrived before vanilla door state key=" .. tostring(key) .. " ageMs=0")
        end
    end
end

Events.OnClientCommand.Add(onClientCommand)

local function onTick()
    CPD.updatePendingZombieDamage()
    processPendingDoors()
end

if Events and Events.OnTick then Events.OnTick.Add(onTick) end
