-- Push Vehicle v1.0 - multiplayer
-- Project Zomboid Build 42.20

local PushVehicleServer = {}

PushVehicleServer.MAX_START_SPEED_KMH = 1.0
PushVehicleServer.MAX_REQUEST_DISTANCE_SQ = 25.0
PushVehicleServer.INTERACTION_PADDING = 1.35
PushVehicleServer.END_ZONE_FRACTION = 0.42
PushVehicleServer.SIDE_ZONE_FRACTION = 0.82
PushVehicleServer.TURN_MIN_LONGITUDINAL_FRACTION = 0.22
PushVehicleServer.TURN_MAX_LONGITUDINAL_FRACTION = 0.92
PushVehicleServer.TURN_IMPULSE_FACTOR = 0.42

PushVehicleServer.BASE_IMPULSE_PER_MASS = 7.0
PushVehicleServer.REFERENCE_MASS = 1200.0
PushVehicleServer.MIN_WEIGHT_FACTOR = 0.70
PushVehicleServer.MAX_WEIGHT_FACTOR = 1.25
PushVehicleServer.STRENGTH_BASE = 0.60
PushVehicleServer.STRENGTH_PER_LEVEL = 0.14
PushVehicleServer.BASE_ENDURANCE_COST = 0.010
PushVehicleServer.MIN_ENDURANCE = 0.06

local FORWARD = Vector3f.new()
local LOCAL_POS = Vector3f.new()
local WORLD_POS = Vector3f.new()

local function isSidePushingEnabled()
    local vars = SandboxVars and SandboxVars.PushVehicle
    if vars and vars.AllowSidePushing ~= nil then
        return vars.AllowSidePushing == true
    end

    return true
end

local function clamp(value, minValue, maxValue)
    if value < minValue then return minValue end
    if value > maxValue then return maxValue end
    return value
end

local function getPushBalance(playerObj, vehicle)
    local strength = playerObj:getPerkLevel(Perks.Strength)
    local mass = math.max(1.0, vehicle:getFudgedMass())

    local strengthFactor =
        PushVehicleServer.STRENGTH_BASE
        + (strength * PushVehicleServer.STRENGTH_PER_LEVEL)

    local weightFactor = math.sqrt(
        PushVehicleServer.REFERENCE_MASS / mass
    )
    weightFactor = clamp(
        weightFactor,
        PushVehicleServer.MIN_WEIGHT_FACTOR,
        PushVehicleServer.MAX_WEIGHT_FACTOR
    )

    local impulsePerMass =
        PushVehicleServer.BASE_IMPULSE_PER_MASS
        * strengthFactor
        * weightFactor

    local enduranceCost =
        PushVehicleServer.BASE_ENDURANCE_COST
        * math.sqrt(mass / PushVehicleServer.REFERENCE_MASS)
        / math.max(0.65, strengthFactor)

    return mass * impulsePerMass, enduranceCost
end

local function getPushData(playerObj, vehicle)
    local script = vehicle:getScript()
    if not script then
        return nil
    end

    local extents = script:getExtents()
    local com = script:getCenterOfMassOffset()
    if not extents or not com then
        return nil
    end

    vehicle:getLocalPos(
        playerObj:getX(),
        playerObj:getY(),
        playerObj:getZ(),
        LOCAL_POS
    )

    local localX = LOCAL_POS:x() - com:x()
    local localZ = LOCAL_POS:z() - com:z()
    local halfWidth = math.max(0.5, extents:x() * 0.5)
    local halfLength = math.max(0.75, extents:z() * 0.5)

    local outsideX = math.max(0.0, math.abs(localX) - halfWidth)
    local outsideZ = math.max(0.0, math.abs(localZ) - halfLength)
    local distanceFromBodySq = outsideX * outsideX + outsideZ * outsideZ

    if distanceFromBodySq >
        (PushVehicleServer.INTERACTION_PADDING * PushVehicleServer.INTERACTION_PADDING)
    then
        return nil
    end

    vehicle:getForwardVector(FORWARD)

    local fx = FORWARD:x()
    local fy = FORWARD:z()
    local lenSq = fx * fx + fy * fy
    if lenSq < 0.0001 then
        return nil
    end

    local len = math.sqrt(lenSq)
    fx = fx / len
    fy = fy / len

    local px = playerObj:getX() - vehicle:getX()
    local py = playerObj:getY() - vehicle:getY()
    local longitudinal = px * fx + py * fy

    local absLocalX = math.abs(localX)
    local absLocalZ = math.abs(localZ)
    local sidePushingEnabled = isSidePushingEnabled()
    local sideZone =
        sidePushingEnabled
        and absLocalX >= halfWidth * PushVehicleServer.SIDE_ZONE_FRACTION
        and absLocalZ >= halfLength * PushVehicleServer.TURN_MIN_LONGITUDINAL_FRACTION
        and absLocalZ <= halfLength * PushVehicleServer.TURN_MAX_LONGITUDINAL_FRACTION

    if sideZone then
        local lateralX = px - longitudinal * fx
        local lateralY = py - longitudinal * fy
        local lateralLenSq = lateralX * lateralX + lateralY * lateralY

        if lateralLenSq >= 0.0001 then
            local lateralLen = math.sqrt(lateralLenSq)
            local pushX = -lateralX / lateralLen
            local pushY = -lateralY / lateralLen

            local sideSign = localX >= 0 and 1 or -1
            local maxTurnZ = halfLength * PushVehicleServer.TURN_MAX_LONGITUDINAL_FRACTION
            local impactLocalZ = math.max(-maxTurnZ, math.min(maxTurnZ, localZ))
            local impactLocalX = com:x() + sideSign * halfWidth

            vehicle:getWorldPos(
                impactLocalX,
                com:y(),
                com:z() + impactLocalZ,
                WORLD_POS
            )

            return {
                pushX = pushX,
                pushY = pushY,
                relX = WORLD_POS:x() - vehicle:getX(),
                relY = WORLD_POS:y() - vehicle:getY(),
                mode = "turn"
            }
        end
    end

    if absLocalZ < halfLength * PushVehicleServer.END_ZONE_FRACTION then
        return nil
    end

    if not sidePushingEnabled then
        local lateralRatio = absLocalX / halfWidth
        local longitudinalRatio = absLocalZ / halfLength
        if lateralRatio > longitudinalRatio then
            return nil
        end
    end

    local side = longitudinal > 0 and 1 or -1
    return {
        pushX = side == 1 and -fx or fx,
        pushY = side == 1 and -fy or fy,
        relX = 0.0,
        relY = 0.0,
        mode = "straight"
    }
end

local function validateRequest(playerObj, vehicle)
    if not playerObj or not vehicle then
        return false
    end

    if playerObj:getVehicle() then
        return false
    end

    if vehicle:isRemovedFromWorld() then
        return false
    end

    if math.abs(vehicle:getCurrentAbsoluteSpeedKmHour()) >
        PushVehicleServer.MAX_START_SPEED_KMH
    then
        return false
    end

    local dx = playerObj:getX() - vehicle:getX()
    local dy = playerObj:getY() - vehicle:getY()
    if dx * dx + dy * dy > PushVehicleServer.MAX_REQUEST_DISTANCE_SQ then
        return false
    end

    if playerObj:getStats():get(CharacterStat.ENDURANCE) <=
        PushVehicleServer.MIN_ENDURANCE
    then
        return false
    end

    return true
end

local function requestPush(playerObj, args)
    if not args or not args.vehicle then
        return
    end

    local vehicle = getVehicleById(args.vehicle)
    if not vehicle then
        return
    end

    if not validateRequest(playerObj, vehicle) then
        return
    end

    local pushData = getPushData(playerObj, vehicle)
    if not pushData then
        return
    end

    -- Server-side enforcement: never trust the client to decide whether
    -- side turning is enabled. This also blocks stale/modified clients.
    if pushData.mode == "turn" and not isSidePushingEnabled() then
        return
    end

    local magnitude, enduranceCost = getPushBalance(playerObj, vehicle)
    if pushData.mode == "turn" then
        magnitude = magnitude * PushVehicleServer.TURN_IMPULSE_FACTOR
    end

    -- Keep one authoritative vehicle simulation, but allow the authority
    -- to move from one pusher to another.
    --
    -- authorizationServerOnSeat(player, true) only assigns authority when the
    -- vehicle currently has no net player (-1). That means without explicitly
    -- releasing the previous pusher, the first player to push a vehicle would
    -- effectively "own" it for all later pushes.
    local requesterId = playerObj:getOnlineID()
    local currentOwnerId = vehicle:getNetPlayerId()

    if currentOwnerId ~= -1 and currentOwnerId ~= requesterId then
        local previousOwner = getPlayerByOnlineID(currentOwnerId)

        if previousOwner then
            vehicle:authorizationServerOnSeat(previousOwner, false)
        else
            return
        end
    end

    vehicle:authorizationServerOnSeat(playerObj, true)

    if vehicle:getNetPlayerId() ~= requesterId then
        return
    end

    -- No player argument = broadcast to all connected clients.
    -- Every client receives the exact same impulse. The requesting client is
    -- also told who requested it, so only that player loses endurance and
    -- mirrors the Local authority immediately.
    sendServerCommand(
        "PushVehicle",
        "applyImpulse",
        {
            vehicle = vehicle:getId(),
            requester = playerObj:getOnlineID(),
            pushX = pushData.pushX,
            pushY = pushData.pushY,
            relX = pushData.relX,
            relY = pushData.relY,
            mode = pushData.mode,
            magnitude = magnitude,
            enduranceCost = enduranceCost
        }
    )

end

local function onClientCommand(module, command, playerObj, args)
    if module ~= "PushVehicle" then
        return
    end

    if command == "requestPush" then
        requestPush(playerObj, args)
    end
end

Events.OnClientCommand.Add(onClientCommand)
