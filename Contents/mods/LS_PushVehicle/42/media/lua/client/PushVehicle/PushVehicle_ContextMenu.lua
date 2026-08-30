-- Push Vehicle - controller + side-turn support
-- Project Zomboid Build 42.20 prototype.
--
-- Uses the game's real shove combat animation (the same shove path used by
-- RMB + Space) instead of a generic timed-action animation.
-- A single vehicle impulse is applied shortly after the shove begins.

local PushVehicle = {}

-- User-configurable keyboard shortcut. Leave it unassigned by default so the
-- mod never steals a key from vanilla or another mod. Players can bind it in
-- Options -> Key Bindings.
PushVehicle.HOTKEY_BINDING = "PushVehicle_Hotkey"
PushVehicle.HOTKEY_DEFAULT = 0

local function registerPushVehicleHotkey()
    if not keyBinding then
        return
    end

    -- If Lua is reloaded, remove an existing copy first so the binding can be
    -- placed back into the correct Vehicles section instead of being duplicated.
    for i = #keyBinding, 1, -1 do
        if keyBinding[i].value == PushVehicle.HOTKEY_BINDING then
            table.remove(keyBinding, i)
        end
    end

    -- Put the mod binding next to a vanilla vehicle binding. Key bindings are
    -- grouped in the Options UI based on their position in this global list.
    local insertIndex = nil
    for i, binding in ipairs(keyBinding) do
        if binding.value == "VehicleRadialMenu" then
            insertIndex = i + 1
            break
        end
    end

    -- Fallback for builds where the vehicle radial binding is renamed: insert
    -- directly below the Vehicles category header when it can be found.
    if not insertIndex then
        for i, binding in ipairs(keyBinding) do
            if binding.value == "[Vehicles]" or binding.value == "[Vehicle]" then
                insertIndex = i + 1
                break
            end
        end
    end

    local binding = {
        value = PushVehicle.HOTKEY_BINDING,
        key = PushVehicle.HOTKEY_DEFAULT
    }

    if insertIndex then
        table.insert(keyBinding, insertIndex, binding)
    else
        -- Last-resort fallback keeps the hotkey functional even if vanilla
        -- changes its keybinding section names in a future build.
        table.insert(keyBinding, binding)
    end
end

registerPushVehicleHotkey()

PushVehicle.MAX_START_SPEED_KMH = 1.0
-- Interaction is measured from the vehicle's actual rectangular extents,
-- not from its centre. This matters for vans, trucks and other long vehicles.
PushVehicle.INTERACTION_PADDING = 1.35
PushVehicle.END_ZONE_FRACTION = 0.42

-- Side-turn interaction. The middle portion of each side is intentionally
-- excluded so a side shove always has enough leverage to rotate the vehicle.
PushVehicle.SIDE_ZONE_FRACTION = 0.82
PushVehicle.TURN_MIN_LONGITUDINAL_FRACTION = 0.22
PushVehicle.TURN_MAX_LONGITUDINAL_FRACTION = 0.92
PushVehicle.TURN_IMPULSE_FACTOR = 0.42

-- Base tuning. The actual impulse is modified by Strength and vehicle mass.
-- A Strength 5 character pushing a ~1000 kg vehicle feels close to v0.4.2.
PushVehicle.BASE_IMPULSE_PER_MASS = 7.0
PushVehicle.REFERENCE_MASS = 1200.0
PushVehicle.MIN_WEIGHT_FACTOR = 0.70
PushVehicle.MAX_WEIGHT_FACTOR = 1.25

-- Strength now has a much clearer gameplay effect:
-- Strength 0  = 60% force
-- Strength 5  = 130% force
-- Strength 10 = 200% force
PushVehicle.STRENGTH_BASE = 0.60
PushVehicle.STRENGTH_PER_LEVEL = 0.14

-- Delay lets the visible shove begin before the vehicle reacts.
PushVehicle.IMPULSE_DELAY_MS = 260

-- Endurance cost also scales with weight and inversely with Strength.
PushVehicle.BASE_ENDURANCE_COST = 0.010
PushVehicle.MIN_ENDURANCE = 0.06

-- Existing vanilla sound used by BaseVehicle for a physical vehicle impact.
PushVehicle.PUSH_SOUND = "thumpa2"

local FORWARD = Vector3f.new()
local pendingPushes = {}

local function getVehicleUnderMouse()
    if not IsoObjectPicker or not IsoObjectPicker.Instance then
        return nil
    end
    return IsoObjectPicker.Instance:PickVehicle(getMouseXScaled(), getMouseYScaled())
end

local LOCAL_POS = Vector3f.new()
local WORLD_POS = Vector3f.new()

-- Custom Sandbox option. Keep side pushing enabled when the option is not
-- available (for example, an older save/preset) so updates remain backwards
-- compatible with the mod's existing behaviour.
local function isSidePushingEnabled()
    local vars = SandboxVars and SandboxVars.PushVehicle
    if vars and vars.AllowSidePushing ~= nil then
        return vars.AllowSidePushing == true
    end

    return true
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

    -- Convert the player into vehicle-local coordinates.
    -- In BaseVehicle local X is left/right and local Z is front/rear.
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

    -- First make sure the player is actually close to the vehicle body.
    local outsideX = math.max(0.0, math.abs(localX) - halfWidth)
    local outsideZ = math.max(0.0, math.abs(localZ) - halfLength)
    local distanceFromBodySq = outsideX * outsideX + outsideZ * outsideZ

    if distanceFromBodySq >
        (PushVehicle.INTERACTION_PADDING * PushVehicle.INTERACTION_PADDING)
    then
        return nil
    end

    vehicle:getForwardVector(FORWARD)

    -- BaseVehicle:getForwardVector() is physics-space.
    -- Horizontal movement is X/Z; game-world movement is X/Y.
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

    -- SIDE TURN -----------------------------------------------------------
    -- A shove on the front/rear portion of either side pushes inward at an
    -- off-centre point. That produces natural yaw torque through vehicle
    -- physics instead of directly setting the vehicle's angle.
    local absLocalX = math.abs(localX)
    local absLocalZ = math.abs(localZ)
    local sidePushingEnabled = isSidePushingEnabled()
    local sideZone =
        sidePushingEnabled
        and absLocalX >= halfWidth * PushVehicle.SIDE_ZONE_FRACTION
        and absLocalZ >= halfLength * PushVehicle.TURN_MIN_LONGITUDINAL_FRACTION
        and absLocalZ <= halfLength * PushVehicle.TURN_MAX_LONGITUDINAL_FRACTION

    if sideZone then
        -- Remove the forward/rear component from player->vehicle position to
        -- obtain the actual lateral direction, independent of script axis sign.
        local lateralX = px - longitudinal * fx
        local lateralY = py - longitudinal * fy
        local lateralLenSq = lateralX * lateralX + lateralY * lateralY

        if lateralLenSq >= 0.0001 then
            local lateralLen = math.sqrt(lateralLenSq)

            -- Push from the player's side inward toward the vehicle centreline.
            local pushX = -lateralX / lateralLen
            local pushY = -lateralY / lateralLen

            -- Put the force on the physical side surface and preserve the
            -- player's front/rear offset. This is the lever arm that turns it.
            local sideSign = localX >= 0 and 1 or -1
            local maxTurnZ = halfLength * PushVehicle.TURN_MAX_LONGITUDINAL_FRACTION
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

    -- FRONT / REAR STRAIGHT PUSH -----------------------------------------
    if absLocalZ < halfLength * PushVehicle.END_ZONE_FRACTION then
        return nil
    end

    -- When side pushing is disabled, don't let a player standing along a
    -- vehicle's flank fall through and get treated as a straight end push.
    -- Compare normalized local coordinates so this works for short cars,
    -- vans and long trucks without changing the existing enabled behaviour.
    if not sidePushingEnabled then
        local lateralRatio = absLocalX / halfWidth
        local longitudinalRatio = absLocalZ / halfLength
        if lateralRatio > longitudinalRatio then
            return nil
        end
    end

    -- Standing at the front pushes backward; rear pushes forward.
    local side = longitudinal > 0 and 1 or -1
    local pushX = side == 1 and -fx or fx
    local pushY = side == 1 and -fy or fy

    return {
        pushX = pushX,
        pushY = pushY,
        relX = 0.0,
        relY = 0.0,
        mode = "straight"
    }
end

local function canPushVehicle(playerObj, vehicle)
    if not playerObj or not vehicle then
        return false, "No vehicle."
    end

    if playerObj:getVehicle() then
        return false, "Exit the vehicle first."
    end

    if vehicle:isRemovedFromWorld() then
        return false, "Vehicle is unavailable."
    end

    if math.abs(vehicle:getCurrentAbsoluteSpeedKmHour()) > PushVehicle.MAX_START_SPEED_KMH then
        return false, "The vehicle must be stationary."
    end

    local pushData = getPushData(playerObj, vehicle)
    if not pushData then
        if isSidePushingEnabled() then
            return false, "Stand at the front/rear, or near the front/rear of either side."
        end
        return false, "Stand at the front or rear of the vehicle."
    end

    if playerObj:getStats():get(CharacterStat.ENDURANCE) <= PushVehicle.MIN_ENDURANCE then
        return false, "You are too exhausted to push the vehicle."
    end

    return true, nil, pushData
end

local function clamp(value, minValue, maxValue)
    if value < minValue then return minValue end
    if value > maxValue then return maxValue end
    return value
end

local function getStrengthLevel(playerObj)
    return playerObj:getPerkLevel(Perks.Strength)
end

local function getPushBalance(playerObj, vehicle)
    local strength = getStrengthLevel(playerObj)
    local mass = math.max(1.0, vehicle:getFudgedMass())

    local strengthFactor =
        PushVehicle.STRENGTH_BASE
        + (strength * PushVehicle.STRENGTH_PER_LEVEL)

    -- Heavy vehicles accelerate less; light vehicles are easier to move.
    local weightFactor = math.sqrt(PushVehicle.REFERENCE_MASS / mass)
    weightFactor = clamp(
        weightFactor,
        PushVehicle.MIN_WEIGHT_FACTOR,
        PushVehicle.MAX_WEIGHT_FACTOR
    )

    local impulsePerMass =
        PushVehicle.BASE_IMPULSE_PER_MASS
        * strengthFactor
        * weightFactor

    local enduranceCost =
        PushVehicle.BASE_ENDURANCE_COST
        * math.sqrt(mass / PushVehicle.REFERENCE_MASS)
        / math.max(0.65, strengthFactor)

    return {
        strength = strength,
        mass = mass,
        impulsePerMass = impulsePerMass,
        enduranceCost = enduranceCost,
        strengthFactor = strengthFactor
    }
end

local function getEffortLabel(balance)
    local score =
        balance.strengthFactor
        * PushVehicle.REFERENCE_MASS
        / balance.mass

    if score >= 1.15 then
        return "Easy"
    elseif score >= 0.80 then
        return "Moderate"
    elseif score >= 0.55 then
        return "Hard"
    else
        return "Very Hard"
    end
end

local function addPushTooltip(option, playerObj, vehicle, unavailableReason)
    local balance = getPushBalance(playerObj, vehicle)
    local effort = getEffortLabel(balance)

    local tooltip = ISToolTip:new()
    tooltip:initialise()
    tooltip:setVisible(false)
    tooltip:setName(getText("UI_PushVehicle_Action"))

    local massRounded = math.floor(balance.mass + 0.5)

    local description =
        "Push the vehicle using your Strength." ..
        " <LINE> Strength: " .. tostring(balance.strength) .. "/10" ..
        " <LINE> Vehicle weight: ~" .. tostring(massRounded) .. " kg" ..
        " <LINE> Push effort: " .. effort

    if unavailableReason then
        description =
            description ..
            " <LINE> <RGB:1,0.3,0.3> " ..
            unavailableReason
    end

    tooltip.description = description
    option.toolTip = tooltip
end

local function queueVehicleImpulse(playerObj, vehicle)
    table.insert(pendingPushes, {
        player = playerObj,
        vehicle = vehicle,
        executeAt = getTimestampMs() + PushVehicle.IMPULSE_DELAY_MS
    })
end

local function triggerVanillaShove(playerObj)
    -- These are the same combat fields used by the normal hand-to-hand shove.
    playerObj:setDoShove(true)
    playerObj:setDoGrapple(false)
    playerObj:setAimAtFloor(false)

    -- Let vanilla combat code choose and play its actual shove animation/state.
    playerObj:AttemptAttack(0.0)
end

local function onPushVehicle(playerObj, vehicle)
    local canPush = canPushVehicle(playerObj, vehicle)
    if not canPush then
        return
    end

    playerObj:faceThisObject(vehicle)
    triggerVanillaShove(playerObj)

    if isClient() then
        local vehicleId = vehicle:getId()

        sendClientCommand(
            playerObj,
            "PushVehicle",
            "requestPush",
            { vehicle = vehicleId }
        )
    else
        queueVehicleImpulse(playerObj, vehicle)
    end
end

local function processPendingPushes()
    if #pendingPushes == 0 then
        return
    end

    local now = getTimestampMs()

    for i = #pendingPushes, 1, -1 do
        local push = pendingPushes[i]

        if now >= push.executeAt then
            local playerObj = push.player
            local vehicle = push.vehicle

            if playerObj
            and vehicle
            and not vehicle:isRemovedFromWorld()
            and not playerObj:getVehicle()
            then
                -- Re-check the player's exact interaction zone when the
                -- shove reaches the impulse moment.
                local pushData = getPushData(playerObj, vehicle)

                if pushData then
                    local balance = getPushBalance(playerObj, vehicle)
                    local magnitude = balance.mass * balance.impulsePerMass

                    if pushData.mode == "turn" then
                        magnitude = magnitude * PushVehicle.TURN_IMPULSE_FACTOR
                    end

                    vehicle:setPhysicsActive(true, true)

                    vehicle:applyImpulseGeneric(
                        vehicle:getX() + pushData.relX,
                        vehicle:getY() + pushData.relY,
                        vehicle:getZ(),
                        pushData.pushX,
                        pushData.pushY,
                        0.0,
                        magnitude
                    )

                    -- Sync a small vanilla vehicle-impact sound with movement.
                    local square = vehicle:getSquare()
                    if square then
                        square:playSound(PushVehicle.PUSH_SOUND)
                    end

                    playerObj:getStats():remove(
                        CharacterStat.ENDURANCE,
                        balance.enduranceCost
                    )
                end
            end

            table.remove(pendingPushes, i)
        end
    end
end


local function onServerCommand(module, command, args)
    if module ~= "PushVehicle" then
        return
    end

    if command ~= "applyImpulse" or not args then
        return
    end

    -- Build 42 exposes getVehicleById(int) directly to Lua.
    local vehicle = getVehicleById(args.vehicle)
    if not vehicle or vehicle:isRemovedFromWorld() then
        return
    end

    local playerObj = getPlayer()
    local isRequester =
        playerObj
        and playerObj:getOnlineID() == args.requester

    -- The server assigned authority to the requesting player. Mirror that
    -- immediately on that player's client, as vanilla collision handling does.
    if isRequester then
        vehicle:authorizationClientCollide(playerObj)
    end

    vehicle:setPhysicsActive(true, true)

    if isRequester then
        -- The authoritative client uses the exact same proven physics path as
        -- singleplayer/v0.6.7. applyImpulseGeneric() queues a local hit-object
        -- force; Build 42 later applies it to Bullet with its internal x30
        -- force scale.
        vehicle:applyImpulseGeneric(
            vehicle:getX() + (args.relX or 0.0),
            vehicle:getY() + (args.relY or 0.0),
            vehicle:getZ(),
            args.pushX,
            args.pushY,
            0.0,
            args.magnitude
        )

        playerObj:getStats():remove(
            CharacterStat.ENDURANCE,
            args.enduranceCost
        )
    else
        -- Remote clients aren't vehicle-authoritative, so their
        -- applyImpulseGeneric() path would be discarded. addImpulse() is the
        -- built-in remote/server impulse path and is processed regardless of
        -- local vehicle authority.
        --
        -- Important: applyImpulseGeneric's hit-object path multiplies its
        -- central force by 30 before calling Bullet. addImpulse() does not.
        -- Match that vanilla scale here so observers see approximately the
        -- same physical shove as the authoritative client.
        local remoteForceScale = 30.0
        local impulse = Vector3f.new(
            args.pushX * args.magnitude * remoteForceScale,
            0.0,
            args.pushY * args.magnitude * remoteForceScale
        )
        local relPos = Vector3f.new(
            args.relX or 0.0,
            0.0,
            args.relY or 0.0
        )

        vehicle:addImpulse(impulse, relPos)
    end

    local square = vehicle:getSquare()
    if square then
        square:playSound(PushVehicle.PUSH_SOUND)
    end

end

local function onFillWorldObjectContextMenu(player, context, worldobjects, test)
    local playerObj = getSpecificPlayer(player)
    if not playerObj or playerObj:getVehicle() then
        return
    end

    local vehicle = getVehicleUnderMouse()
    if not vehicle then
        return
    end

    local canPush, reason = canPushVehicle(playerObj, vehicle)

    -- Don't show the option when the player is outside every valid push zone.
    if not canPush
    and (reason == "Stand at the front/rear, or near the front/rear of either side."
        or reason == "Stand at the front or rear of the vehicle.")
    then
        return
    end

    if test then
        return true
    end

    local option = context:addOption(
        getText("UI_PushVehicle_Action"),
        playerObj,
        onPushVehicle,
        vehicle
    )

    if not canPush then
        option.notAvailable = true
    end

    local unavailableReason = nil
    if not canPush then
        unavailableReason = reason or "The vehicle cannot be pushed right now."
    end

    addPushTooltip(
        option,
        playerObj,
        vehicle,
        unavailableReason
    )
end

-- Keyboard hotkey ----------------------------------------------------------
-- Uses the same vehicle selection and validation path as the controller
-- radial menu. The hotkey is only an additional input method; all existing
-- Strength, stamina, stationary-vehicle, side-push and MP server checks still
-- run through onPushVehicle()/requestPush().
local function onPushVehicleHotkey(key)
    local core = getCore()
    if not core then
        return
    end

    local boundKey = core:getKey(PushVehicle.HOTKEY_BINDING)

    -- 0 is the unassigned/None value.
    if not boundKey or boundKey <= 0 or key ~= boundKey then
        return
    end

    local playerObj = getSpecificPlayer(0)
    if not playerObj or playerObj:getVehicle() then
        return
    end

    if not ISVehicleMenu or not ISVehicleMenu.getVehicleToInteractWith then
        return
    end

    local vehicle = ISVehicleMenu.getVehicleToInteractWith(playerObj)
    if not vehicle then
        return
    end

    local canPush = canPushVehicle(playerObj, vehicle)
    if not canPush then
        return
    end

    onPushVehicle(playerObj, vehicle)
end

-- Controller support -------------------------------------------------------
-- Build 42's D-pad Up menu is the dedicated outside-vehicle radial menu.
-- Let vanilla build/display that menu first, then append Push Vehicle when
-- the same nearby vehicle is in a valid straight/turn pushing position.
--
-- This intentionally does not replace or copy vanilla radial-menu code.
-- Keyboard/RMB behavior and all vehicle physics/networking remain unchanged.
if ISVehicleMenu and ISVehicleMenu.showRadialMenuOutside
and not ISVehicleMenu._PushVehicleRadialHookInstalled
then
    ISVehicleMenu._PushVehicleRadialHookInstalled = true

    local vanillaShowRadialMenuOutside =
        ISVehicleMenu.showRadialMenuOutside

    ISVehicleMenu.showRadialMenuOutside = function(playerObj)
        local playerIndex = playerObj:getPlayerNum()
        local menu = getPlayerRadialMenu(playerIndex)

        -- Vanilla uses the same function as a toggle. If it was already open,
        -- let vanilla close it and don't append anything to the hidden menu.
        local wasVisible = menu:isReallyVisible()

        vanillaShowRadialMenuOutside(playerObj)

        if wasVisible then
            return
        end

        if playerObj:getVehicle() then
            return
        end

        local vehicle = ISVehicleMenu.getVehicleToInteractWith(playerObj)
        if not vehicle then
            return
        end

        local canPush = canPushVehicle(playerObj, vehicle)
        if not canPush then
            return
        end

        menu:addSlice(
            getText("UI_PushVehicle_Action"),
            getTexture("media/ui/Furniture_Pickup.png"),
            onPushVehicle,
            playerObj,
            vehicle
        )
    end
end

Events.OnFillWorldObjectContextMenu.Add(onFillWorldObjectContextMenu)
Events.OnKeyPressed.Add(onPushVehicleHotkey)
Events.OnTick.Add(processPendingPushes)
Events.OnServerCommand.Add(onServerCommand)
