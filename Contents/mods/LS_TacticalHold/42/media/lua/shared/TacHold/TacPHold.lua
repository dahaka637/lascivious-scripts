TacPHold = TacPHold or {}
TacPHold.activeMasks = {}
TacPHold.poseMode = {}
TacPHold.clearTimers = {}

TacPHold.getRequiredAiming = function()
    if SandboxVars and SandboxVars.TacHold and SandboxVars.TacHold.PistolAimingRequirement then
        return SandboxVars.TacHold.PistolAimingRequirement
    end
    return 0
end

TacHold.getCycleKey = function()
    local opt = TacHold and TacHold.options and TacHold.options.CycleKey
    if opt and opt.getValue then
        local v = opt:getValue()
        if type(v) == "number" and v >= 0 then
            return v
        end
    end
    return Keyboard.KEY_U
end

TacPHold.getEnabledPoses = function()
    local poses = {}

    if TacPHold.options and TacPHold.options.PoseNormal and TacPHold.options.PoseNormal.value then
        table.insert(poses,{ right = "TacPistolRight", left = "TacPistolLeft" })
    end

    if TacPHold.options and TacPHold.options.PoseHighReady and TacPHold.options.PoseHighReady.value then
        table.insert(poses,{ right = "TacPistolRightHigh", left = "TacPistolLeftHigh" })
    end

    if TacPHold.options and TacPHold.options.PoseLowReady and TacPHold.options.PoseLowReady.value then
        table.insert(poses,{ right = "TacPistolRightLow", left = "TacPistolLeftLow" })
    end

    if TacPHold.options and TacPHold.options.PoseVanilla and TacPHold.options.PoseVanilla.value then
        table.insert(poses,{ right = "TacPistolRightVanilla", left = "TacPistolLeftVanilla" })
    end

    if #poses == 0 then
        table.insert(poses,{ right = "TacPistolRightVanilla", left = "TacPistolLeftVanilla" })
    end

    return poses
end

function TacPHold.TogglePose(player)
    if not player then return end
    local poses = TacPHold.getEnabledPoses()
    TacPHold.poseMode[player] = (TacPHold.poseMode[player] or 1) + 1
    if TacPHold.poseMode[player] > #poses then
        TacPHold.poseMode[player] = 1
    end
    local pose = poses[TacPHold.poseMode[player]]
    if pose then
        print("TacPHold Pose: " .. pose.right)
    end
end

local function clearTacMasks(player)
    if not player then return end

    local pose = TacPHold.activeMasks[player]

    if pose then
        if player:getVariableString("RightHandMask") == pose.right then
            player:clearVariable("RightHandMask")
        end
        if player:getVariableString("LeftHandMask") == pose.left then
            player:clearVariable("LeftHandMask")
        end
    end

    TacPHold.activeMasks[player] = nil
    TacPHold.clearTimers[player] = nil

    player:getModData().TacPHoldPose = nil
    player:transmitModData()
end

local function tacHold(player)
    if player:isDead() or player:isAsleep() then
        if TacPHold.activeMasks[player] then clearTacMasks(player) end
        return
    end

    local maskActive = TacPHold.activeMasks[player]
    local primary = player:getPrimaryHandItem()
    local secondary = player:getSecondaryHandItem()

    if primary and instanceof(primary,"HandWeapon") and primary:isRanged() and not primary:isTwoHandWeapon() then
        
        if player:isAiming() or player:isSneaking() then
            if maskActive then clearTacMasks(player) end
            return
        end
        
        local aiming = player:getPerkLevel(Perks.Aiming)
        local required = TacPHold.getRequiredAiming()

        if aiming < required then
            if maskActive then clearTacMasks(player) end
            return
        end

        local poses = TacPHold.getEnabledPoses()
        local mode = TacPHold.poseMode[player] or 1
        local pose = poses[mode]

        -- TRIGGER ANIMATION
        if player:getVariableString("RightHandMask") ~= pose.right then
            player:setVariable("RightHandMask", pose.right)
            if not secondary then
                player:setVariable("LeftHandMask", pose.left)
            end
            TacPHold.activeMasks[player] = pose
            player:getModData().TacPHoldPose = pose
            player:transmitModData()
        end
        
        return 
    end

    if maskActive then
        clearTacMasks(player)
    end
end

local function tacHoldMP(mPlayer)
    if not mPlayer or mPlayer:isLocalPlayer() then return end

    -- Safety Check: Clear animations if the player is dead or asleep
    if mPlayer:isDead() or mPlayer:isAsleep() then
        if mPlayer:getVariableString("RightHandMask") ~= "" or mPlayer:getVariableString("LeftHandMask") ~= "" then
            mPlayer:clearVariable("RightHandMask")
            mPlayer:clearVariable("LeftHandMask")
            if mPlayer:getModData() then mPlayer:getModData().TacPHoldPose = nil end
        end
        return
    end

    local currentR = mPlayer:getVariableString("RightHandMask")
    local currentL = mPlayer:getVariableString("LeftHandMask")
    local modData = mPlayer:getModData()
    if not modData then return end

    local netPose = modData.TacPHoldPose

    if netPose then
        if currentR ~= netPose.right then
            mPlayer:setVariable("RightHandMask", netPose.right)
        end
        if currentL ~= netPose.left then
            mPlayer:setVariable("LeftHandMask", netPose.left)
        end
    else
        if (currentR ~= "" and currentR ~= nil) or (currentL ~= "" and currentL ~= nil) then
            mPlayer:clearVariable("RightHandMask")
            mPlayer:clearVariable("LeftHandMask")
            modData.TacPHoldPose = nil
        end
    end
end

local function TacPHoldInit()
    if isServer() then return end

    local function onPlayerUpdate(player)
        if player:isLocalPlayer() then
            tacHold(player)
        elseif isClient() then
            tacHoldMP(player)
        end
    end

    local function onKeyPressed(key)
        if key ~= TacHold.getCycleKey() then return end

        local player = getPlayer()
        if not player then return end

        local primary = player:getPrimaryHandItem()

        if primary and instanceof(primary,"HandWeapon") then
            if primary:isRanged() and not primary:isTwoHandWeapon() then
                TacPHold.TogglePose(player)
            end
        end
    end

    Events.OnGameStart.Add(function()
        if TacHold.options and TacHold.options.CycleKey and TacHold.options.CycleKey.apply then
            TacHold.options.CycleKey:apply()
        end

        Events.OnPlayerUpdate.Add(onPlayerUpdate)
        Events.OnKeyPressed.Add(onKeyPressed)
    end)
end

TacPHoldInit()