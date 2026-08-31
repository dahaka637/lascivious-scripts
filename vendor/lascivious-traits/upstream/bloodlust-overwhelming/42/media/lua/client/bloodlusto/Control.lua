local Utils = require('bloodlusto/Utils')


local SB = require('bloodlusto/ControlSandbox')
local MO = require('bloodlusto/Options')



---@class Control
---@field b Bloodlust
---@field outburst string | nil
---@field now number
---@field player_last_active_at number
---@field tracking_ends_at number | nil
---@field tracking_movement_lock_ends_at number | nil
---@field following_ends_at number | nil
---@field following_active_ends_at number | nil
---@field go_to_action ISWalkToTimedAction | nil
---@field go_to_square IsoGridSquare | nil
local Control = BloodlustO_Uncontrollable or {}
BloodlustO_Uncontrollable = Control
Control.__index = Control

Control.last_paused = getTimeInMillis()
Control.last_movement_input_at = getTimeInMillis()

--- @param bloodlust Bloodlust
function Control:new(bloodlust)
    local instance = {
        b = bloodlust,
        now = getTimeInMillis(),
        outburst = nil,
        player_last_active_at = getTimeInMillis(),
    }
    setmetatable(instance, Control)
    return instance
end



function Control:canControl()
    return not (self.b.player:isAsleep()
        or self.b.player:isDriving()
        or self.b.player:getVehicle()
    )
end


--region Tracking

--- @return string | nil - reason why it can't happen
function Control:testTracking()
    if self.outburst then return "outburst-active" end
    if not SB.TrackingOutburst then return "disabled" end
    if self.b.data.bloodlust <= SB.TrackingMinBloodlust then return "below min bloodlust" end
    if not self:canControl() then return "cannot control" end

    if not self.b.closest_zombie then return "no closest zombie" end
    if self.b.can_see_closest_zombie then
        if self.b.data.distance_to_zombie < SB.TrackingMinVisibleZombieTiles then return "visible zombie too close" end
    else
        if self.b.data.distance_to_zombie < SB.TrackingMinHiddenZombieTiles then return "hidden zombie too close" end
    end
    if self.now - math.max(self.player_last_active_at, Control.last_paused) < SB.TrackingRequiredIdleTime * 1000 then return "player active" end

    local chance
    if self.b.data.bloodlust < SB.TrackingMaxBloodlust then
        chance = SB.TrackingMaxChance * ((SB.TrackingMinBloodlust - self.b.data.bloodlust) / (SB.TrackingMaxBloodlust - SB.TrackingMinBloodlust))
    else
        chance = SB.TrackingMaxChance
    end
    if ZombRandFloat(0, 100) > chance then return "chance" end
end

function Control:startTracking()
    self.outburst = 'tracking'
    self.tracking_ends_at = getGametimeTimestamp() + ZombRand((SB.TrackingMaxMinutes - SB.TrackingMinMinutes) * 60) + 1
    self.tracking_movement_lock_ends_at = self.now + SB.TrackingMovementLockSeconds*1000

    self.b:shout(1, MO.tracking_outburst_phrase and Utils.getVariant('outburst:tracking', '...'))

    -- Only if can move-lock
    if not self.b.data.distance_to_zombie or self.b.data.distance_to_zombie > SB.TrackingMovementLockMinTilesFromZombie then
        self.b:emitEvent("tracking")
    end
end

function Control:stopTracking()
    if self.tracking_movement_lock_ends_at then
        self.b.player:setBlockMovement(false)
        self.b.player:setIgnoreMovement(false)
    end
    self.tracking_ends_at = nil
    self.tracking_movement_lock_ends_at = nil
    self.outburst = nil
end

function Control:track()
    if self.outburst ~= 'tracking' then return end
    if getGametimeTimestamp() > self.tracking_ends_at or self.b.data.bloodlust < SB.TrackingMinBloodlust then
        self:stopTracking()
        return
    end
    if self.tracking_movement_lock_ends_at and self.now > self.tracking_movement_lock_ends_at then
        self.b.player:setBlockMovement(false)
        self.b.player:setIgnoreMovement(false)
        self.tracking_movement_lock_ends_at = nil
    end

    if not self.b.closest_zombie then return end
    if not self:canControl() then return end

    if self.tracking_movement_lock_ends_at then
        local safe_to_lock = self.b.data.distance_to_zombie > SB.TrackingMovementLockMinTilesFromZombie
        self.b.player:setBlockMovement(safe_to_lock)
        self.b.player:setIgnoreMovement(safe_to_lock)
    end

    if self.b.can_see_closest_zombie and self.b.data.distance_to_zombie < SB.TrackingStopIfZombieWithinTiles then return end

    self:turnTowards(self.b.closest_zombie, self.tracking_movement_lock_ends_at)
end

--endregion

--region Following

--- @return string | nil - reason why it can't happen
function Control:testFollowing()
    if not SB.FollowingOutburst then return "disabled" end
    if self.outburst ~= "tracking" then return "not tracking" end
    if self.b.data.bloodlust <= SB.FollowingMinBloodlust then return "below min bloodlust" end
    if not self:canControl() then return "cannot control" end

    if not self.b.closest_zombie then return "no closest zombie" end
    if self.b.can_see_closest_zombie then
        if self.b.data.distance_to_zombie < SB.TrackingToFollowingMinTilesFromVisibleZombie then return "visible zombie too close" end
    else
        if self.b.data.distance_to_zombie < SB.TrackingToFollowingMinTilesFromHiddenZombie then return "hidden zombie too close" end
    end
    if not self.b.player:isPlayerMoving() then return "not moving" end
    if self.b.player:isAiming() then return "aiming" end

    local chance
    if self.b.data.bloodlust < SB.FollowingMaxBloodlust then
        chance = SB.TrackingToFollowingMaxChance * ((SB.FollowingMinBloodlust - self.b.data.bloodlust) / (SB.FollowingMaxBloodlust - SB.FollowingMinBloodlust))
    else
        chance = SB.TrackingToFollowingMaxChance
    end
    if ZombRandFloat(0, 100) > chance then return "chance" end
end

function Control:startFollowing()
    if self.outburst == 'tracking' then
        self:stopTracking()
    end
    self.outburst = 'following'
    self.following_ends_at = getGametimeTimestamp() + ZombRand((SB.FollowingMaxIngameMinutes - SB.FollowingMinIngameMinutes) * 60) + 1
    self.following_active_ends_at = self.now + ZombRandFloat(SB.FollowingActiveMinRealSeconds, SB.FollowingActiveMaxRealSeconds) * 1000

    self.b:emitEvent("following")
end

function Control:stopFollowing()
    if self.following_active_ends_at then
        self.b.player:setBlockMovement(false)
    end
    self.following_ends_at = nil
    self.following_active_ends_at = nil
    self:stopGoingTo()
    self.outburst = nil

    if ZombRand(100)+1 < SB.FollowingEndToTrackingChance then
        self:startTracking()
    end
end

function Control:follow()
    if self.outburst ~= 'following' then return end
    if getGametimeTimestamp() > self.following_ends_at or self.b.data.bloodlust < SB.FollowingMinBloodlust then
        self:stopFollowing()
        return
    end
    if self.following_active_ends_at and self.now > self.following_active_ends_at then
        self.b.player:setBlockMovement(false)
        self.following_active_ends_at = nil
    end

    if not self.b.closest_zombie then return end
    if not self:canControl() then return end

    -- Active
    if self.following_active_ends_at then
        local safe = self.b.data.distance_to_zombie > SB.FollowingActiveMinTilesFromZombie

        if safe and self.now - Control.last_movement_input_at <= SB.FollowingMovementAttemptMovesForSeconds * 1000 then
            self.b.player:setBlockMovement(true)
            self:goTo(self.b.closest_zombie)
        else
            self.b.player:setBlockMovement(false)
            self:stopGoingTo()
        end

        return
    end

    -- Idle
    local safe_to_go = self.b.data.distance_to_zombie > SB.FollowingIdleMinTilesFromZombie
    local safe_to_look = self.b.data.distance_to_zombie > SB.TrackingStopIfZombieWithinTiles

    if not self.following_random_idle then
        self.following_random_idle = ZombRandFloat(SB.FollowingAfterInactivityMin, SB.FollowingAfterInactivityMax) * 1000
    end

    local inactive_for = self.now - math.max(Control.last_movement_input_at, Control.last_paused)
    local progress = inactive_for / self.following_random_idle
    if progress >= 1 and safe_to_go then
        self:goTo(self.b.closest_zombie)
        self.following_reroll_random_idle = true
    elseif progress >= SB.StartTrackingAfterInactivityWhenFollowing * 0.01 then
        self:stopGoingTo()
        if safe_to_look then
            self:turnTowards(self.b.closest_zombie)
        end
        self.following_reroll_random_idle = true
    else
        self:stopGoingTo()
        if self.following_reroll_random_idle then
            self.following_random_idle = ZombRandFloat(SB.FollowingAfterInactivityMin, SB.FollowingAfterInactivityMax) * 1000
        end
    end
end

--endregion


function Control:checkPlayerActivity()
    local is_active = self.b.player:isPlayerMoving()
        or self.b.player:isAiming()
        or self.b.player:isDriving()
        or self.b.player:getVehicle()
        or self.b.player:isAsleep()
    if is_active then
        self.player_last_active_at = self.now
    end
end



--- @param zombie IsoZombie
--- @param force boolean
function Control:turnTowards(zombie, force)
    -- Note: This is only called when idle because it messes up interaction direction
    if force or self.now - math.max(self.player_last_active_at, Control.last_paused) > 300 then
        self.b.player:faceThisObject(zombie)
    end
end

--- @param zombie IsoZombie
function Control:goTo(zombie)
    local queue = ISTimedActionQueue.getTimedActionQueue(self.b.player)
    if self.go_to_action then
        if self.go_to_square == zombie:getSquare() then
            if queue:indexOf(self.go_to_action) ~= -1 then return end
        end
        ISTimedActionQueue.clear(self.b.player)
    end
    self.go_to_square = zombie:getSquare()
    self.go_to_action = ISWalkToTimedAction:new(self.b.player, self.go_to_square)
    queue:addToQueue(self.go_to_action)
end
function Control:stopGoingTo()
    if self.go_to_action then
        ISTimedActionQueue.clear(self.b.player)
    end
    self.go_to_action = nil
    self.go_to_square = nil
end



---region Events

function Control:tick()
    self.now = getTimeInMillis()
    self:checkPlayerActivity()
    self:track()
    self:follow()
end

function Control:onEveryMinute()
    self.now = getTimeInMillis()
    if not self:testTracking() then
        self:startTracking()
    end
    if not self:testFollowing() then
        self:startFollowing()
    end
end

---endregion



--region Controlling code WIP

--- @param player IsoPlayer
function Control.attack(player)
    if not player:CanAttack() or player:isAttacking() then return end
    player:setBlockMovement(true)
    player:pressedAttack()
    if not player:isAttacking() then
        player:setBlockMovement(false) -- FIXME Remember if blocked and unblock the next tick as well
    end
end

-- TODO Cooldown changing between zombies with nearly identical distance for a second
local last_go_target

--- @param player IsoPlayer
--- @param square IsoGridSquare
function Control.goToOLD(player, square)
    if last_go_target ~= square then
        ISTimedActionQueue.clear(player)
    end
    ISTimedActionQueue.add(ISWalkToTimedAction:new(player, square))
    last_go_target = square
end

--- From Java's IsoPlayer.isMeleeAttackRange
--- @param player IsoPlayer
--- @param zombie IsoZombie
function Control.distanceUntilReach(player, zombie)
    local deltaZ = math.abs(zombie:getZ() - player:getZ())
    if deltaZ >= 0.5 then return end

    --- @type HandWeapon
    local weapon = player:getPrimaryHandItem()
    local range = weapon:getModData().BloodlustO_OriginalMaxRange or weapon:getMaxRange()
    range = range * weapon:getRangeMod(player)

    local distSq = ((player:getX() - zombie:getX()) ^ 2) + ((player:getY() - zombie:getY()) ^ 2)
    if distSq < 4.0 and zombie.target == player and zombie.isCurrentState(LungeState.instance()) then
        range = range + 0.2;
    end

    -- TODO Time perfect max-ranged hits
    -- There's player/zombie getMovementLastFrame() and player:calculateCombatSpeed(),
    -- but I haven't found how to get swing duration

    return distSq - range * range
end

function Control.canHit(player, zombie)
    local pX = player:getXi()
    local pY = player:getYi()
    local pZ = player:getZi()

    local zX = zombie:getXi()
    local zY = zombie:getYi()
    local zZ = zombie:getZi()

    if pX == zX and pY == zY and pZ == zZ then return true end
    return not LosUtil.lineClearCollide(pX, pY, pZ, zX, zY, zZ, false)
end

--- @class Target
--- @field zombie IsoZombie
--- @field distance number
--- @field until_reach number

--- @param player IsoPlayer
--- @return table<number, Target>
function Control.getTargets(player)
    local targets = {}
    local zombies = getCell():getZombieList()
    for i = 0, zombies:size() - 1 do
        --- @type IsoZombie
        local zombie = zombies:get(i)
        if zombie:isDead() or zombie:getHealth() <= 0 then
            local data = zombie:getModData()
            data.bo_dying_outline_alpha = data.bo_dying_outline_alpha or 1
            if data.bo_dying_outline_alpha > 0 then
                data.bo_dying_outline_alpha = data.bo_dying_outline_alpha - (0.008 * GameTime.getInstance():getThirtyFPSMultiplier())
                zombie:setOutlineHighlight(true)
                zombie:setOutlineHighlightCol(player:getPlayerNum(), 150/255, 6/255, 6/255, data.bo_dying_outline_alpha)
            else
                zombie:setOutlineHighlight(false)
            end
        end
        if not zombie:isDead() and not zombie:isKnockedDown() then
            local distance = player:getDistanceSq(zombie)
            local until_reach = Control.distanceUntilReach(player, zombie)
            table.insert(targets, { zombie = zombie, distance = distance, until_reach = until_reach })
        end
    end

    local function comp(a, b)
        return a.distance < b.distance
    end
    table.sort(targets, comp)
    return targets
end

--- @param player IsoPlayer
--- @param targets table<number, Target>
--- @return Target | nil
function Control.pickTarget(player, targets)
    local within_reach = {}
    for _, item in ipairs(targets) do
        if item.until_reach and item.until_reach <= 0.5
                and (item.zombie:isAttacking() or Control.canHit(player, item.zombie)) then
            table.insert(within_reach, item)
        end
    end
    return #within_reach > 0 and within_reach[ZombRand(#within_reach) + 1]
end

function Control.clearMind(player)
    player:setIgnoreMovement(false)
    player:setBlockMovement(false)
    --- TODO These require resetting to original
    player:setTurnDelta(1)
    getCore():setOptionPanCameraWhileAiming(true)


    local weapon = player:getPrimaryHandItem()
    if weapon and instanceof(weapon, 'HandWeapon') then
        local weapon_data = weapon:getModData()
        if weapon_data.BloodlustO_OriginalMaxRange then
            local original = weapon_data.BloodlustO_OriginalMaxRange
            local max_range = weapon:getMaxRange()
            weapon:setMaxRange(original)
            Utils.log('Returned weapon reach to '..tostring(original)..' (From '..tostring(max_range)..')')
            weapon_data.BloodlustO_OriginalMaxRange = nil
        end
    end
end

--- @param player IsoPlayer
--- @return boolean true if equipped
function Control.equipBestWeapon(player)
    local best_weapon = player:getInventory():getBestWeapon()
    if not best_weapon then return false end
    player:setPrimaryHandItem(best_weapon)
    if best_weapon:isTwoHandWeapon() then
        player:setSecondaryHandItem(best_weapon)
    end
    return true
end

--- @param player IsoPlayer
function Control.control(player)
    --- @type HandWeapon
    local weapon = player:getPrimaryHandItem()
    if not instanceof(weapon, 'HandWeapon') or weapon:isRanged() or not weapon:isMelee() then
        Control.clearMind(player)
        Control.equipBestWeapon(player)
        return
    end

    local targets = Control.getTargets(player)
    if #targets == 0 then
        Control.clearMind(player)
        return
    end

    -- Note: Applying this only while aiming results in flickering
    getCore():setOptionPanCameraWhileAiming(false)

    local closest = targets[1]
    local hit_target = Control.pickTarget(player, targets)

    if hit_target then
        local weapon_data = weapon:getModData()
        if not weapon_data.BloodlustO_OriginalMaxRange then
            local max_range = weapon:getMaxRange()
            weapon_data.BloodlustO_OriginalMaxRange = max_range
            weapon:setMaxRange(max_range + 1)
            Utils.log('Temporarily increased weapon reach from '..tostring(max_range)..' to '..tostring(max_range+1))
        end
        player:setTurnDelta(8)
        player:faceThisObject(hit_target.zombie)
        if player:CanAttack() and not player:isAttacking() then
            player:setBlockMovement(true)
            if hit_target.zombie:isAttacking() then
                player:setDoShove(false)
            end
            player:pressedAttack()
        end
        for _, item in ipairs(targets) do
            if item.zombie ~= hit_target.zombie and (item.distance <= 2 or item.zombie:isAttacking()) then
                item.zombie:setHitReaction("Uppercut")
                item.zombie:setOutlineHighlight(false)
            end
        end
    else
        for _, item in ipairs(targets) do
            if closest.zombie == item.zombie then
                item.zombie:setOutlineHighlight(true)
                item.zombie:setOutlineHighlightCol(player:getPlayerNum(), 150/255, 6/255, 6/255, 1)
            else
                item.zombie:setOutlineHighlight(false)
            end
        end
        Control.goTo(player, closest.zombie:getSquare())
        player:setTurnDelta(1)
        player:setIsAiming(false)
    end

    -- Don't let the player mess up killing!
    if closest.distance <= 32 then
        player:setBlockMovement(true)
    else
        player:setBlockMovement(false)
    end
    -- Even with movement block, you can still rotate character if it's already aiming... which is why this is required
    if player:isAiming() then
        player:setIgnoreMovement(true)
    else
        player:setIgnoreMovement(false)
    end
end

--endregion



--region Events

local function onTickEvenPaused(tick)
    if tick == 0 then
        Control.last_paused = getTimeInMillis()
    end
end
Events.OnTickEvenPaused.Add(onTickEvenPaused)

local function onKeyKeepPressed(key)
    local core = getCore()
    if key == core:getKey('Forward')
        or key == core:getKey('Backward')
        or key == core:getKey('Left')
        or key == core:getKey('Right') then
        Control.last_movement_input_at = getTimeInMillis()
    end
end
Events.OnKeyKeepPressed.Add(onKeyKeepPressed)

--endregion


return Control
