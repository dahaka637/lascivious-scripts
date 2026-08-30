TacHold = TacHold or {}
TacHold.activeMasks = {}
TacHold.poseMode = {}
TacHold.clearTimers = {}

TacHold.getRequiredAiming = function()
    if SandboxVars and SandboxVars.TacHold and SandboxVars.TacHold.AimingRequirement then
        return SandboxVars.TacHold.AimingRequirement
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

TacHold.getEnabledPoses = function()
    local poses = {}
    if TacHold.options and TacHold.options.PoseNormal and TacHold.options.PoseNormal.value then
        table.insert(poses, "TacGunPose")
    end
    if TacHold.options and TacHold.options.PoseHighReady and TacHold.options.PoseHighReady.value then
        table.insert(poses, "TacGunPoseHighReady")
    end
    if TacHold.options and TacHold.options.PoseLowReady and TacHold.options.PoseLowReady.value then
        table.insert(poses, "TacGunPoseLowready")
    end
    if TacHold.options and TacHold.options.PoseGunResting and TacHold.options.PoseGunResting.value then
        table.insert(poses, "TacGunResting")
    end
    if TacHold.options and TacHold.options.PoseVanilla and TacHold.options.PoseVanilla.value then
        table.insert(poses, "Vanilla")
    end
    if #poses == 0 then
        table.insert(poses, "Vanilla")
    end
    return poses
end

function TacHold.TogglePose(player)
    if not player then return end
    local poses = TacHold.getEnabledPoses()
    TacHold.poseMode[player] = (TacHold.poseMode[player] or 1) + 1
    if TacHold.poseMode[player] > #poses then
        TacHold.poseMode[player] = 1
    end
    print("TacHold Pose: " .. poses[TacHold.poseMode[player]])
end

local function clearTacMask(player)
    if not player then return end
    local pose = TacHold.activeMasks[player]
    if pose and player:getVariableString("RightHandMask") == pose then
        player:clearVariable("RightHandMask")
    end
    TacHold.activeMasks[player] = nil
    TacHold.clearTimers[player] = nil
    player:getModData().TacHoldPose = nil
    player:transmitModData()
end

local function tacHold(player)
    -- Death/Sleep check
    if player:isDead() or player:isAsleep() then
        if TacHold.activeMasks[player] then clearTacMask(player) end
        return
    end

    local maskActive = TacHold.activeMasks[player]
    local primary = player:getPrimaryHandItem()
    local secondary = player:getSecondaryHandItem()

    -- Valid Weapon Check
    if primary and primary == secondary and instanceof(primary, "HandWeapon") and primary:isRanged() then
        
        if player:isAiming() or player:isSneaking() then
            if maskActive then clearTacMask(player) end
            return
        end
        
        local aiming = player:getPerkLevel(Perks.Aiming)
        local required = TacHold.getRequiredAiming()
        
        if aiming < required then
            if maskActive then clearTacMask(player) end
            return
        end

        local poses = TacHold.getEnabledPoses()
        local mode = TacHold.poseMode[player] or 1
        local pose = poses[mode]

        -- Animation trigger
        if player:getVariableString("RightHandMask") ~= pose then
            player:setVariable("RightHandMask", pose)
            TacHold.activeMasks[player] = pose
            player:getModData().TacHoldPose = pose
            player:transmitModData()
        end
        
        return
    end

    -- Fallthrough (If no gun, clear)
    if maskActive then
        clearTacMask(player)
    end
end

local function tacHoldMP(mPlayer)
    if not mPlayer or mPlayer:isLocalPlayer() then return end

    -- Safety Check: Clear animation if the player is dead or asleep
    if mPlayer:isDead() or mPlayer:isAsleep() then
        if mPlayer:getVariableString("RightHandMask") ~= "" then
            mPlayer:clearVariable("RightHandMask")
            if mPlayer:getModData() then mPlayer:getModData().TacHoldPose = nil end
        end
        return
    end

    local current = mPlayer:getVariableString("RightHandMask")
    local modData = mPlayer:getModData()
    if not modData then return end
    
    local netPose = modData.TacHoldPose

    if netPose then
        if current ~= netPose then
            mPlayer:setVariable("RightHandMask", netPose)
        end
    else
        if current ~= "" and current ~= nil then
            mPlayer:clearVariable("RightHandMask")
            modData.TacHoldPose = nil
        end
    end
end

local function TacHoldInit()
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
        local secondary = player:getSecondaryHandItem()

        if primary and primary == secondary then
            if instanceof(primary, "HandWeapon") and primary:isRanged() then
                TacHold.TogglePose(player)
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

TacHoldInit()