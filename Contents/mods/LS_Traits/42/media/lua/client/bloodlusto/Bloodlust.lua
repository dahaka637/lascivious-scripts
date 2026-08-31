local BloodlustTrait = require("bloodlusto/Registries").traits.Bloodlust
local Bloodiness = require('bloodlusto/Bloodiness')
local Control = require('bloodlusto/Control')
local Utils = require('bloodlusto/Utils')
local ZombieImpact = require("LS_Traits_ZombieImpact")



local SB = require('bloodlusto/Sandbox')
local MO = require('bloodlusto/Options')

local STRAIN_PARTS = {
    BodyPartType.Foot_L,
    BodyPartType.Foot_R,
    BodyPartType.ForeArm_L,
    BodyPartType.ForeArm_R,
    BodyPartType.Hand_L,
    BodyPartType.Hand_R,
    BodyPartType.LowerLeg_L,
    BodyPartType.LowerLeg_R,
    BodyPartType.Torso_Lower,
    BodyPartType.Torso_Upper,
    BodyPartType.UpperArm_L,
    BodyPartType.UpperArm_R,
    BodyPartType.UpperLeg_L,
    BodyPartType.UpperLeg_R
}


---@class BloodlustModData
---@field bloodlust number
---@field frenzy_progress number
---@field buffered_exertion number
---@field last_kill_at number
---@field last_hit_at number
---@field last_got_hit_at number | nil
---@field combat_start_at number | nil
---@field last_in_combat number | nil
---@field nimble_xp_added number | nil
---@field distance_to_zombie number | nil
---@field frenzy_instakills number | nil
---@field frenzy_instakills_decayed_in_sleep number | nil


---@class Bloodlust
---@field player IsoPlayer
---@field data BloodlustModData
---@field bloodiness BloodinessValues
---@field in_combat boolean
---@field control Control
---@field at boolean
---@field closest_zombie IsoZombie | nil
---@field can_see_closest_zombie boolean
---@field sees_any_zombie boolean
---@field is_rear_danger boolean
local Bloodlust = BloodlustO or {}
BloodlustO = Bloodlust
Bloodlust.__index = Bloodlust

local FRENZY_INSTAKILL_CHAIN_DURATION_SECONDS = 12

local function isLocalPlayer(player)
    if player == nil then
        return false
    end

    local ok, result = pcall(function()
        return player:isLocalPlayer()
    end)

    if ok then
        return result == true
    end

    return player == getPlayer()
end

function Bloodlust:new()
    local instance = {}
    instance.control = Control:new(instance)
    setmetatable(instance, Bloodlust)
    return instance
end

local instances = {}
--- @param player IsoPlayer
--- @return Bloodlust
function Bloodlust.getInstance(player)
    local id = player:getID()
    if not instances[id] then
        instances[id] = Bloodlust:new()
    end
    return instances[id]
end


--- @param player IsoPlayer
--- @param type string
function Bloodlust:preUpdate(player, type)
    self.player = player
    self.data = Utils.getModData(player)
    self.at = getGametimeTimestamp()

    if (type ~= "tick" and type ~= "move") or self.bloodiness == nil then
        self.bloodiness = Bloodiness.get(player)
        self:updateBloodinessMoodle()
    end

    self:updateCombat(type)
end

function Bloodlust:updateCombat(type)
    if (type ~= "tick" and type ~= "move") or not self._zombies_scan_tick or self._zombies_scan_tick >= SB.ZombiesScanEveryTicks then
        --- @type { distance: number, zombie: IsoZombie } | nil
        local closest
        local zombies = getCell():getZombieList()
        local sees_any_zombie = false
        for i = 0, zombies:size() - 1 do
            --- @type IsoZombie
            local zombie = zombies:get(i)
            if not sees_any_zombie then
                sees_any_zombie = zombie:getAlpha() > 0.5
            end
            if math.abs(self.player:getZ() - zombie:getZ()) < SB.IgnoreZombiesWithFloorsDifference then
                local distance = Utils.getDistanceSq(self.player, zombie)
                if not closest or closest.distance > distance then
                    closest = { zombie = zombie, distance = distance }
                end
            end
        end
        self.sees_any_zombie = sees_any_zombie
        if closest then
            self.closest_zombie = closest.zombie
            self.data.distance_to_zombie = math.sqrt(closest.distance)
            self.can_see_closest_zombie = self.player:CanSee(self.closest_zombie)
        else
            self.closest_zombie = nil
            self.data.distance_to_zombie = nil
            self.can_see_closest_zombie = false
        end
        self:checkRearDanger()
        self._zombies_scan_tick = 0
    else
        if type == "tick" then
            self._zombies_scan_tick = self._zombies_scan_tick + 1
        end
    end

    local close_distance
    if self.can_see_closest_zombie then
        close_distance = SB.TilesUntilSeenZombieForInCombat
    else
        close_distance = SB.TilesUntilZombieForInCombat
    end
    local is_zombie_close = self.data.distance_to_zombie and self.data.distance_to_zombie <= close_distance
    local is_targeted = self.closest_zombie and self.closest_zombie:getTarget() == self.player
    self.in_combat = is_zombie_close or is_targeted

    if self.in_combat then
        self.data.last_in_combat = self.at
        if not self.data.combat_start_at then
            self.data.combat_start_at = self.at
        end
    else
        self.data.combat_start_at = nil
    end
end


--region Any Update

function Bloodlust:checkRearDanger()
    if not self.closest_zombie then
        self.is_rear_danger = false
        return
    end

    local is_visible = self.closest_zombie:getAlpha() > 0.5 -- 0 alpha = player doesn't see it

    local zdata = self.closest_zombie:getModData()
    if is_visible then
        zdata.BloodlustO_LastSeenAt = getGametimeTimestamp()
    end
    local last_seen_at = zdata.BloodlustO_LastSeenAt or 0

    self.is_rear_danger = self.closest_zombie
            and not is_visible
            and self.can_see_closest_zombie
            and self.closest_zombie:getTarget() == self.player -- zombie is going for player
            and (self.data.distance_to_zombie or 0) <= SB.RearDangerMaxTiles
            and ((self.data.distance_to_zombie or 0) <= SB.RearDangerIfWithinTiles
                 or (getGametimeTimestamp() - last_seen_at)/60 >= SB.RearDangerIfNotSeenMinutes)
end

function Bloodlust:addNewBloodinessBloodlust()
    local bloodiness_change = Bloodiness.getChange(self.player)
    if bloodiness_change <= 0 then return end

    local bloodlust_change = bloodiness_change * SB.GettingBloodyBloodlustChange
    self.data.bloodlust = math.clamp(self.data.bloodlust + bloodlust_change, 0, 100)

    local stats = self.player:getStats()
    stats:remove(CharacterStat.BOREDOM, 100)
    stats:add(CharacterStat.STRESS, bloodiness_change * SB.GettingBloodyStressChange * 0.01)
    stats:add(CharacterStat.NICOTINE_WITHDRAWAL, bloodiness_change * SB.GettingBloodyStressChange * 0.01)
    stats:add(CharacterStat.UNHAPPINESS, bloodiness_change * SB.GettingBloodyUnhappinessChange)
end

--- @param progress number
function Bloodlust:addFrenzyProgress(progress)
    if progress <= 0 then return end -- Can be called with < 0

    local freshness_bloodiness_multiplier = 1 + (self.bloodiness.overall_freshness * SB.BloodinessFreshnessMultiplierForFrenzy)
    local enough_bloodiness = self.bloodiness.overall * freshness_bloodiness_multiplier >= SB.BloodinessForFrenzy / 100
    local already_started = self.data.frenzy_progress > 0

    if enough_bloodiness or already_started then
        local freshness_progress_multiplier = SB.BloodinessFreshnessFrenzyProgressExponent ^ self.bloodiness.overall_freshness
        self.data.frenzy_progress = self.data.frenzy_progress + (progress * freshness_progress_multiplier)
    end
end

--- @param bloodlust_change number
function Bloodlust:addFightSatisfaction(bloodlust_change)
    local stats = self.player:getStats()
    stats:remove(CharacterStat.BOREDOM, 100)
    stats:remove(CharacterStat.STRESS, bloodlust_change * SB.BloodlustChangeDestress * 0.01)
    stats:remove(CharacterStat.NICOTINE_WITHDRAWAL, bloodlust_change * SB.BloodlustChangeDestress * 0.01)
    stats:remove(CharacterStat.UNHAPPINESS, bloodlust_change * SB.BloodlustChangeHappiness)
end

function Bloodlust:setWeaponSpeedIncrease()
    --- @type HandWeapon
    local weapon = self.player:getPrimaryHandItem()
    if not weapon or not instanceof(weapon, "HandWeapon") then return end
    local data = weapon:getModData()

    if self:inFrenzy() then
        if not data.BloodlustO_OriginalBaseSpeed then
            Utils.log("Saved original weapon base speed: "..tostring(weapon:getBaseSpeed()))
            data.BloodlustO_OriginalBaseSpeed = weapon:getBaseSpeed()
        end
        local modifier = 1 + ((self.data.bloodlust * 0.01) * SB.MaxBloodlustFrenzyWeaponSpeedIncrease)

        weapon:setBaseSpeed(data.BloodlustO_OriginalBaseSpeed * modifier)
    else
        if data.BloodlustO_OriginalBaseSpeed then
            Utils.log("Returned original weapon base speed: "..tostring(data.BloodlustO_OriginalBaseSpeed)
                    .." (From "..tostring(weapon:getBaseSpeed())..")")
            weapon:setBaseSpeed(data.BloodlustO_OriginalBaseSpeed)
            data.BloodlustO_OriginalBaseSpeed = nil
        end
    end
end

--endregion



--region Per Minute

function Bloodlust:onEveryMinute()
    if not self.player:isAlive() then return end

    self:addNewBloodinessBloodlust()
    self:addBloodlustInFightlessCombat()

    self:updateKillCraving()
    self:decayFrenzy()

    self:backlashFrenzyInstakills()
    self:updateExertionBuffering()

    self.control:onEveryMinute()

    -- Phrases
    self:sayPreFrenzy()

    -- Moodles
    self:updateBloodlustMoodle()
    self:updateBufferedExertionMoodle()
    self:updateFrenzyInstakillsBacklashMoodle()
    self:updateFightlessCombatMoodle()
end


function Bloodlust:isFightlessCombat()
    if self.player:isAsleep() then return false end
    if not self.in_combat then return false end
    if self:inFrenzy() then return false end
    if not self.sees_any_zombie then return false end
    if self.player:getVehicle() and not SB.FightlessCombatBloodlustWhileDriving then return false end

    local since_action = self.at - math.max(self.data.last_hit_at, self.data.combat_start_at or 0)
    return since_action/60 >= SB.FightlessCombatAfterMinutes
end
function Bloodlust:addBloodlustInFightlessCombat()
    if not self:isFightlessCombat() then return end
    self.data.bloodlust = math.clamp(self.data.bloodlust + SB.FightlessCombatBloodlustPerMinute, 0, 100)
end

function Bloodlust:decayFrenzy()
    local decay_rate
    if self.in_combat then
        decay_rate = SB.FrenzyPerMinuteDecayInCombat
    else
        decay_rate = SB.FrenzyPerMinuteDecayOutOfCombat
    end

    if self.data.frenzy_progress >= SB.BloodlustOverreducedForFrenzy then
        local bloodlust_overdecay = decay_rate - self.data.bloodlust
        if bloodlust_overdecay > 0 then
            self.data.frenzy_progress = math.max(0, self.data.frenzy_progress - bloodlust_overdecay)
        end
        self.data.bloodlust = math.clamp(self.data.bloodlust - decay_rate, 0, 100)
    else
        self.data.frenzy_progress = math.max(0, self.data.frenzy_progress - decay_rate)
    end
end

function Bloodlust:updateKillCraving()
    if self.player:isAsleep() then return end
    if self:inFrenzy() then return end

    -- Bloodlust Increase
    local bloodiness_factor = (1 + (self.bloodiness.overall * SB.KillCravingBloodinessFactor))
        * (1 + ((1 - self.bloodiness.overall_freshness) * SB.KillCravingStaleBloodinessMultiplier))

    local remaining_health = (self.player:getBodyDamage():getOverallBodyHealth() / 100)
    local health_factor = remaining_health ^ SB.KillCravingHealthExponent

    local since_kill = self.at - self.data.last_kill_at
    local raw_increase = Utils.getMinuteValueIncrease(
        since_kill / 60,
        SB.KillCravingMaxHours * 60,
        SB.KillCravingMaxHoursExponent
    ) * 100

    local increase = raw_increase * bloodiness_factor * health_factor
    self.data.bloodlust = math.min(100, self.data.bloodlust + increase)

    -- Mood
    if self.data.bloodlust < SB.BloodlustLevelForMoodDebuffs then return end

    local bloodlust_factor = ((self.data.bloodlust - SB.BloodlustLevelForMoodDebuffs)
            / (100 - SB.BloodlustLevelForMoodDebuffs)) ^ SB.MoodDebuffBloodlustExponent
    local bloodiness_modifier = 1 + (self.bloodiness.overall * SB.BloodinessImpactOnMoodDebuffs)

    local stats = self.player:getStats()

    local boredom_per_minute = (100 / (SB.MaxBloodlustFullBoredomAfterHours * 60)) * bloodlust_factor
    stats:add(CharacterStat.BOREDOM, boredom_per_minute * bloodiness_modifier)

    local stress_per_minute = (1 / (SB.MaxBloodlustFullStressAfterHours * 60)) * bloodlust_factor
    local idle_stress_reduction = 0.0018
    stats:add(CharacterStat.STRESS, idle_stress_reduction + (stress_per_minute * bloodiness_modifier))

    local unhappiness_per_minute = (100 / (SB.MaxBloodlustDepressionAfterHours * 60)) * bloodlust_factor
    stats:add(CharacterStat.UNHAPPINESS, unhappiness_per_minute * bloodiness_modifier)
end

function Bloodlust:backlashFrenzyInstakills()
    if self.data.frenzy_progress and self.data.frenzy_progress > 0 then return end
    if not self.data.frenzy_instakills and not self.data.frenzy_instakills_decayed_in_sleep then return end
    local stats = self.player:getStats()

    if not self.player:isAsleep() and self.data.frenzy_instakills_decayed_in_sleep then
        local postsleep_rate = math.min(
            (100 - stats:get(CharacterStat.HUNGER)*100) / SB.FrenzyInstakillBacklashHunger,
            (100 - stats:get(CharacterStat.THIRST)*100) / SB.FrenzyInstakillBacklashThirst,
            self.data.frenzy_instakills_decayed_in_sleep
        )
        stats:add(CharacterStat.HUNGER, postsleep_rate * SB.FrenzyInstakillBacklashHunger * 0.01)
        stats:add(CharacterStat.THIRST, postsleep_rate * SB.FrenzyInstakillBacklashThirst * 0.01)
        self.data.frenzy_instakills_decayed_in_sleep = self.data.frenzy_instakills_decayed_in_sleep - postsleep_rate
        if self.data.frenzy_instakills_decayed_in_sleep <= 0 then
            self.data.frenzy_instakills_decayed_in_sleep = nil
        end
    end

    local rate = math.max(0, math.min(
        SB.FrenzyBacklashPerMinute,
        (100 - stats:get(CharacterStat.HUNGER)*100) / SB.FrenzyInstakillBacklashHunger,
        (100 - stats:get(CharacterStat.THIRST)*100) / SB.FrenzyInstakillBacklashThirst,
        self.data.frenzy_instakills or 0
    ))
    if not self.player:isAsleep() then
        rate = math.max(0, math.min(
            rate,
            (100 - stats:get(CharacterStat.FATIGUE)*100) / SB.FrenzyInstakillBacklashFatigue
        ))
        stats:add(CharacterStat.FATIGUE, rate * SB.FrenzyInstakillBacklashFatigue * 0.01)
        stats:add(CharacterStat.HUNGER, rate * SB.FrenzyInstakillBacklashHunger * 0.01)
        stats:add(CharacterStat.THIRST, rate * SB.FrenzyInstakillBacklashThirst * 0.01)
        self:addStrain(rate * SB.FrenzyInstakillBacklashStrain)
    else
        self:addStrain(rate * SB.FrenzyInstakillBacklashStrain)
        self.data.frenzy_instakills_decayed_in_sleep = (self.data.frenzy_instakills_decayed_in_sleep or 0) + rate
    end

    self.data.frenzy_instakills = (self.data.frenzy_instakills or 0) - rate
    if self.data.frenzy_instakills <= 0 then
        self.data.frenzy_instakills = nil
    end
end

--region Exertion Buffering

function Bloodlust:canBufferExertion()
    if self:inFrenzy() then return true end
    if not self.in_combat then return false end
    return self.data.bloodlust >= SB.BloodlustForExertionBuffering
end

function Bloodlust:canUnbufferExertion()
    if self:inFrenzy() then return false end
    if self.in_combat then return false end
    if not self.data.last_in_combat then return true end
    return (self.at - self.data.last_in_combat) / 60 >= SB.MinutesSinceCombatForUnbuffering
end

function Bloodlust:updateExertionBuffering()
    if self:canBufferExertion() then
        self:bufferExertion()
    elseif self:canUnbufferExertion() then
        self:unbufferExertion()
    end
end

function Bloodlust:bufferExertion()
    local stats = self.player:getStats()
    local exertion = (1 - stats:get(CharacterStat.ENDURANCE)) * 100
    if exertion < SB.BufferExertionAfter then return end

    local to_buffer = math.min(
        SB.ExertionBufferedPerMinute, -- max to buffer
        exertion, -- exertion left
        SB.MaxBufferedExertion - self.data.buffered_exertion -- buffer space left
    )
    if to_buffer <= 0 then return end

    self.data.buffered_exertion = self.data.buffered_exertion + (to_buffer * SB.ExertionBufferingMultiplier)
    stats:add(CharacterStat.ENDURANCE, to_buffer * 0.01)
end

function Bloodlust:unbufferExertion()
    local stats = self.player:getStats()
    local endurance = stats:get(CharacterStat.ENDURANCE) * 100

    local to_unbuffer = math.min(
        SB.ExertionUnbufferedPerMinute, -- max to unbuffer
        endurance, -- endurance left
        self.data.buffered_exertion -- buffer left
    )
    if to_unbuffer <= 0 then return end

    self.data.buffered_exertion = self.data.buffered_exertion - to_unbuffer

    stats:remove(CharacterStat.ENDURANCE, to_unbuffer * 0.01)
    stats:add(CharacterStat.HUNGER, to_unbuffer * SB.ExertionUnbufferingHunger * 0.01)
    stats:add(CharacterStat.THIRST, to_unbuffer * SB.ExertionUnbufferingThirst * 0.01)

    self:addStrain(to_unbuffer * SB.ExertionUnbufferingStrain)
end

--endregion

--endregion


--region Per Tick

function Bloodlust:onPlayerUpdate()
    self:setWeaponSpeedIncrease()

    if self.data.frenzy_progress >= SB.BloodlustOverreducedForFrenzy
            and self.data.bloodlust >= SB.InstakillAtBloodlust then
        Utils.wiggleMoodle(self.player, "BloodyFrenzy")
    end

    if self.attacker_to_kill and getTimeInMillis() >= self.attacker_to_kill.at then
        self.attacker_to_kill.attacker:setHealth(self.attacker_to_kill.attacker:getHealth() - SB.FrenzyHurtRevengeDamage)
        self.attacker_to_kill.attacker:update()
        self.attacker_to_kill = nil
    end

    self.control:tick()
end

--endregion


--region Per Event

function Bloodlust:onPlayerMove()
    self:addMoveSpeed()
end

function Bloodlust:addMoveSpeed()
    if not self:inFrenzy() then return end
    if not self.player:isPlayerMoving() then return end

    if not self._move_vector then
        self._move_vector = Vector2.new(0, 0)
    end

    local boost = (self.data.bloodlust * 0.01) * SB.MaxBloodlustFrenzyMoveSpeedIncrease

    self.player:getDeferredMovement(self._move_vector)

    local boost_x = self._move_vector:getX() * boost
    local boost_y = self._move_vector:getY() * boost

    -- unmodded my ass. each dir is multiplied by (1.0 - self.getSlowFactor())
    local slow_modifier = 1.0 - self.player:getSlowFactor()

    self.player:moveUnmodded(boost_x / slow_modifier, boost_y / slow_modifier)
end


function Bloodlust:onPlayerHit()
    self.data.last_got_hit_at = self.at

    if self:inFrenzy() then
        local attacker = self.player:getAttackedBy()
        if attacker and instanceof(attacker, "IsoZombie") then
            attacker:getModData().BloodlustO_IgnoreKill = true

            if self.data.bloodlust >= SB.FrenzyHurtRevengeAtBloodlust then
                -- Prevent drag down
                if self.player:isDeathDragDown() then
                    self.player:setPlayingDeathSound(false)
                    self.player:setDeathDragDown(false)
                    self.player:setHitReaction("EvasiveBlocked")
                end

                -- Push others back
                self:pushZombies(attacker)

                -- Execute queued kill
                if self.attacker_to_kill then
                    self.attacker_to_kill.attacker:setHealth(self.attacker_to_kill.attacker:getHealth() - SB.FrenzyHurtRevengeDamage)
                    self.attacker_to_kill.attacker:update()
                end
                -- Queue kill to perfectly match hit push back animation
                self.attacker_to_kill = { attacker = attacker, at = getTimeInMillis() + 600 }

                -- Phrase
                self:shout(SB.FrenzyHurtSoundRadius, MO.frenzy_hurt_phrase and Utils.getVariant('frenzy:got-hit', 'GET OFF ME'))
            end

            local overreduce = self.data.bloodlust + SB.FrenzyHurtBloodlustChange
            if overreduce < 0 then
                self.data.frenzy_progress = self.data.frenzy_progress + overreduce
            end
            self.data.bloodlust = math.clamp(self.data.bloodlust + SB.FrenzyHurtBloodlustChange, 0, 100)
        end
    else
        self.data.bloodlust = math.clamp( self.data.bloodlust + SB.HurtBloodlustChange, 0, 100)
    end
    self:emitEvent("hurt")
end


--- @param zombie IsoZombie
function Bloodlust:onZombieKill(zombie)
    if zombie:getModData().BloodlustO_IgnoreKill then return end

    if SB.ConsiderCarDriveOverAsCombat and self.player:isDriving() then
        self.data.last_hit_at = self.at
    end

    self.data.last_kill_at = self.at

    local bloodlust_change = self:getWeaponModifiers(self.player:getPrimaryHandItem()).kill
    if self:inFrenzy() then
        self.data.bloodlust = math.clamp(self.data.bloodlust + bloodlust_change, 0, 100)
    else
        self.data.bloodlust = math.clamp(self.data.bloodlust - bloodlust_change, 0, 100)
        self:addFrenzyProgress(bloodlust_change - self.data.bloodlust)
    end
    self:addFightSatisfaction(bloodlust_change)

    self:addNewBloodinessBloodlust()

    self:updateBloodlustMoodle()
    self:updateFightlessCombatMoodle()
    self:updateBloodinessMoodle()
    self:emitEvent("kill")
end


--- @param weapon HandWeapon
--- @param target IsoZombie
function Bloodlust:onZombieHit(weapon, target)
    local target_data = target:getModData()
    if target_data.BloodlustO_IgnoreKill then
        target_data.BloodlustO_IgnoreKill = nil
    end

    if SB.ConsiderShovesAndStompsAsHits or not weapon:isBareHands() then
        self.data.last_hit_at = getGametimeTimestamp()
    end

    if not SB.AdditionalDamageWithBareHands and weapon:isBareHands() then return end

    self:applyBonusDamage(weapon, target)

    local bloodlust_change = self:getWeaponModifiers(weapon).hit
    if self:inFrenzy() then
        self.data.bloodlust = math.clamp(self.data.bloodlust + bloodlust_change, 0, 100)
    else
        self.data.bloodlust = math.clamp(self.data.bloodlust - bloodlust_change, 0, 100)
        self:addFrenzyProgress(bloodlust_change - self.data.bloodlust)
    end
    self:addFightSatisfaction(bloodlust_change)

    self:addNewBloodinessBloodlust()

    self:updateBloodlustMoodle()
    self:updateFightlessCombatMoodle()
    self:updateBloodinessMoodle()
end

--- @param weapon HandWeapon
--- @param target IsoZombie
function Bloodlust:applyBonusDamage(weapon, target)
	local is_ranged = weapon and weapon.isRanged and weapon:isRanged()
	self.data.BloodlustO_InstakillChainUntil = nil
	local nowMs = getTimeInMillis()
	local in_frenzy_instakill_chain = self:inFrenzy()
		and self.data.BloodlustO_InstakillChainUntilMs
		and nowMs <= self.data.BloodlustO_InstakillChainUntilMs
	local can_instakill = (self.data.bloodlust >= SB.InstakillAtBloodlust or in_frenzy_instakill_chain)
		and (SB.InstakillWorksForRanged or not is_ranged)

	local damage = 0
    if self:inFrenzy() then
        damage = math.min(
            SB.BloodlustAdditionalDamageInFrenzy,
            SB.BloodlustAdditionalDamageInFrenzy * (self.data.bloodlust / SB.InstakillAtBloodlust)
        )
    else
        damage = math.min(
            SB.BloodlustAdditionalDamage,
            SB.BloodlustAdditionalDamage * (self.data.bloodlust / SB.InstakillAtBloodlust)
        )
    end

    if not SB.AdditionalDamageWorksForRanged and is_ranged then
        damage = 0
    end

	if can_instakill then
		damage = damage + SB.InstakillDamage
		local reduction
		if self:inFrenzy() then
            reduction = SB.InstakillBloodlustReductionInFrenzy
        else
            reduction = SB.InstakillBloodlustReduction
        end
		if self:inFrenzy() then
			self.data.bloodlust = math.clamp(self.data.bloodlust - reduction, SB.InstakillAtBloodlust, 100)
			self.data.BloodlustO_InstakillChainUntilMs = nowMs + FRENZY_INSTAKILL_CHAIN_DURATION_SECONDS * 1000
		else
			self.data.bloodlust = math.clamp(self.data.bloodlust - reduction, 0, 100)
		end
		self:addFightSatisfaction(reduction)

        if self:inFrenzy() then
            self.data.frenzy_instakills = (self.data.frenzy_instakills or 0) + 1
            self:applyFrenzyAreaDamage(weapon, target)
        else
            self:addStrain(SB.InstakillDueToCravingStrain)
        end

        local variant
        local radius
        if self.data.last_got_hit_at and self.data.last_got_hit_at > self.data.last_kill_at then
            variant = MO.revenge_instakill_phrase and Utils.getVariant("revenge", "EAT THIS!")
            radius = SB.RevengeInstakillSoundRadius
        elseif self:inFrenzy() then
            variant = MO.frenzy_instakill_phrase and Utils.getVariant("frenzy:instakill", "HAHAHAHAHA")
            radius = SB.InstakillSoundRadiusInFrenzy
        else
            variant = MO.craving_instakill_phrase and Utils.getVariant("instakill", "FINALLY!")
            radius = SB.InstakillSoundRadius
        end
        self:shout(radius, variant)
        self:emitEvent("instakill")
    else
        self:emitEvent("hit")
    end

    if damage > 0 then
        target:setHealth(target:getHealth() - damage)
        target:update()
    end
end

--- @param weapon HandWeapon
--- @param target IsoZombie
function Bloodlust:applyFrenzyAreaDamage(weapon, target)
    local max_distance = SB.FrenzyInstakillAreaRadius ^ 2
    --- @type table<number, {zombie: IsoZombie, distance: number}>
    local to_damage = {}
    local zombies = getCell():getZombieList()
    for i = 0, zombies:size() - 1 do
        local zombie = zombies:get(i)
        if zombie ~= target then
            local distance = Utils.getDistanceSq(target, zombie)
            if distance <= max_distance then
                table.insert(to_damage, { zombie = zombie, distance = distance })
            end
        end
    end
    if #to_damage == 0 then return end

    local function comp(a, b)
        return a.distance < b.distance
    end
    table.sort(to_damage, comp)

    local damage_per_zombie = SB.FrenzyInstakillAreaDamage / #to_damage
    local damaged = 0
    for _, item in ipairs(to_damage) do
        if damaged < SB.FrenzyInstakillZombiesLimit then
            item.zombie:hitConsequences(weapon, self.player, false, damage_per_zombie, false)
            item.zombie:update()
            damaged = damaged + 1
        end
    end
end

--- @param except IsoZombie
function Bloodlust:pushZombies(except)
    local max_distance = SB.FrenzyHurtRevengePushTiles ^ 2
    --- @type table<number, {zombie: IsoZombie, distance: number}>
    local to_damage = {}
    local zombies = getCell():getZombieList()
    for i = 0, zombies:size() - 1 do
        local zombie = zombies:get(i)
        if zombie ~= except then
            local distance = Utils.getDistanceSq(self.player, zombie)
            if distance <= max_distance then
                table.insert(to_damage, { zombie = zombie, distance = distance })
            end
        end
    end

    local function comp(a, b)
        return a.distance < b.distance
    end
    table.sort(to_damage, comp)

    local pushed = 0
    for _, item in ipairs(to_damage) do
        if pushed < SB.FrenzyHurtRevengeZombiesPushed then
            ZombieImpact.apply(item.zombie, {
                stagger = true,
                knockDown = ZombRandFloat(0, 100) <= SB.FrenzyHurtRevengeKnockDownChance,
                update = true,
            })
            pushed = pushed + 1
        end
    end
end

--endregion


--region Phrases

Bloodlust.said_pre_frenzy_at = nil
Bloodlust.prev_frenzy_progress = nil

function Bloodlust:sayPreFrenzy()
    local should_say = self.prev_frenzy_progress
        and self.prev_frenzy_progress < SB.BloodlustOverreducedForFrenzy
        and self.data.frenzy_progress >= SB.BloodlustOverreducedForFrenzy
    self.prev_frenzy_progress = self.data.frenzy_progress
    if not should_say then return end

    if self.said_pre_frenzy_at and (getGametimeTimestamp() - self.said_pre_frenzy_at) / 60 < SB.PreFrenzyPhraseCooldown then return end

    if MO.pre_frenzy_phrase then
        self.player:addLineChatElement(Utils.getVariant('pre-frenzy', 'There is no stopping now'), 120/255, 6/255, 6/255)
        self.said_pre_frenzy_at = getGametimeTimestamp()
    end
end

--endregion


--region Moodles

function Bloodlust:updateBloodlustMoodle()
    if self.data.frenzy_progress >= SB.BloodlustOverreducedForFrenzy then
        Utils.updateMoodle(self.player, "KillCraving", 0)
        Utils.updateMoodle(self.player, "Bloodlust", 0)
        if self.data.bloodlust >= SB.FrenzyHurtRevengeAtBloodlust then
            Utils.updateMoodle(self.player, "PreFrenzy", 0)

            if self.data.bloodlust >= SB.InstakillAtBloodlust then
                Utils.updateMoodle(self.player, "BloodyFrenzy", 4)
            else
                Utils.updateMoodle(self.player, "BloodyFrenzy", 2)
            end
        else
            Utils.updateMoodle(self.player, "BloodyFrenzy", 0)

            Utils.updateMoodle(self.player, "PreFrenzy", 1)
        end
    elseif self.data.bloodlust >= SB.InstakillAtBloodlust then
        Utils.updateMoodle(self.player, "KillCraving", 0)
        Utils.updateMoodle(self.player, "PreFrenzy", 0)
        Utils.updateMoodle(self.player, "BloodyFrenzy", 0)

        Utils.updateMoodle(self.player, "Bloodlust", -3)
    elseif self.data.bloodlust >= SB.BloodlustLevelForMoodDebuffs then
        Utils.updateMoodle(self.player, "Bloodlust", 0)
        Utils.updateMoodle(self.player, "PreFrenzy", 0)
        Utils.updateMoodle(self.player, "BloodyFrenzy", 0)

        Utils.updateMoodle(self.player, "KillCraving", -1)
    else
        Utils.updateMoodle(self.player, "KillCraving", 0)
        Utils.updateMoodle(self.player, "Bloodlust", 0)
        Utils.updateMoodle(self.player, "PreFrenzy", 0)
        Utils.updateMoodle(self.player, "BloodyFrenzy", 0)
    end
end

function Bloodlust:updateBufferedExertionMoodle()
    if self:canBufferExertion() then
        local fullness = self.data.buffered_exertion / SB.MaxBufferedExertion
        local level
        if fullness >= 0.90 then
            level = 4
        elseif fullness >= 0.75 then
            level = 3
        elseif fullness >= 0.50 then
            level = 2
        elseif fullness > 0.25 then
            level = 1
        else
            level = 0
        end
        Utils.updateMoodle(self.player, 'BufferedExertion', level)
    else
        local fullness = self.data.buffered_exertion / SB.MaxBufferedExertion
        local level
        if fullness >= 0.90 then
            level = -4
        elseif fullness >= 0.60 then
            level = -3
        elseif fullness >= 0.30 then
            level = -2
        elseif fullness > 0 then
            level = -1
        else
            level = 0
        end
        Utils.updateMoodle(self.player, 'BufferedExertion', level, { wiggle = self:canUnbufferExertion() })
    end
end

function Bloodlust:updateFrenzyInstakillsBacklashMoodle()
    if self.data.frenzy_progress and self.data.frenzy_progress > 0 then
        Utils.updateMoodle(self.player, 'FrenzyBacklash', 0)
        return
    end

    local remaining = math.max(self.data.frenzy_instakills or 0, self.data.frenzy_instakills_decayed_in_sleep or 0)
    local fullness = 0
    if remaining > 0 then
        fullness = math.max(
            SB.FrenzyInstakillBacklashFatigue * remaining,
            SB.FrenzyInstakillBacklashHunger * remaining,
            SB.FrenzyInstakillBacklashThirst * remaining
        )
    end

    local level
    if fullness >= 90 then
        level = -4
    elseif fullness >= 60 then
        level = -3
    elseif fullness >= 30 then
        level = -2
    elseif fullness > 0 then
        level = -1
    else
        level = 0
    end
    Utils.updateMoodle(self.player, 'FrenzyBacklash', level, { wiggle = true })
end

function Bloodlust:updateFightlessCombatMoodle()
    if self:isFightlessCombat() then
        Utils.updateMoodle(self.player, 'FightlessCombat', -2, {wiggle = true})
    else
        Utils.updateMoodle(self.player, 'FightlessCombat', 0)
    end
end

function Bloodlust:updateBloodinessMoodle()
    if self.bloodiness.overall < MO.bloodiness_moodle_at/100 then
        Utils.updateMoodle(self.player, 'Bloodiness', 0)
        return
    end

    local blood_level
    if self.bloodiness.overall >= 0.90 then
        blood_level = 90
    elseif self.bloodiness.overall >= 0.60 then
        blood_level = 60
    elseif self.bloodiness.overall >= 0.30 then
        blood_level = 30
    elseif self.bloodiness.overall > 0.05 then
        blood_level = 5
    else
        blood_level = 0
    end
    local tooltip = getText('Moodles_BloodlustO_Bloodiness_'..tostring(blood_level))

    local level
    if self.bloodiness.overall_freshness >= 0.80 then
        level = 3
    elseif self.bloodiness.overall_freshness >= 0.40 then
        level = 2
    elseif self.bloodiness.overall_freshness >= 0.20 then
        level = 1
    else
        level = -1
    end

    if MO.bloodiness_exact then
        tooltip = tooltip..'\n\n'
            ..tostring(math.floor(self.bloodiness.overall*100))..'% bloody ('
            ..tostring(math.floor(self.bloodiness.overall_freshness*100))..'% fresh)'
    end

    Utils.updateMoodle(self.player, 'Bloodiness', level, {add_to_tooltip = tooltip})
end

--endregion



--region Utils

function Bloodlust:inFrenzy()
    return self.data.frenzy_progress >= SB.BloodlustOverreducedForFrenzy
end

--- @param weapon HandWeapon | InventoryItem | nil
function Bloodlust:getWeaponModifiers(weapon)
    if weapon and instanceof(weapon, 'HandWeapon') and WeaponType.getWeaponType(weapon) == WeaponType.KNIFE then
        if self:inFrenzy() then
            return { hit = SB.FrenzyKnifeHitBloodlustIncrease, kill = SB.FrenzyKnifeKillBloodlustIncrease }
        else
            return { hit = SB.KnifeHitBloodlustReduction, kill = SB.KnifeKillBloodlustReduction }
        end
    elseif weapon and weapon.isRanged and weapon:isRanged() then
        if self:inFrenzy() then
            return { hit = SB.FrenzyRangedHitBloodlustIncrease, kill = SB.FrenzyRangedKillBloodlustIncrease }
        else
            return { hit = SB.RangedHitBloodlustReduction, kill = SB.RangedKillBloodlustReduction }
        end
    elseif weapon and weapon.isOfWeaponCategory and
            (weapon:isOfWeaponCategory(WeaponCategory.SPEAR)
            or weapon:isOfWeaponCategory(WeaponCategory.AXE)
            or weapon:isOfWeaponCategory(WeaponCategory.LONG_BLADE)
            or weapon:isOfWeaponCategory(WeaponCategory.SMALL_BLADE)) then
        if self:inFrenzy() then
            return { hit = SB.FrenzySharpHitBloodlustIncrease, kill = SB.FrenzySharpKillBloodlustIncrease }
        else
            return { hit = SB.SharpHitBloodlustReduction, kill = SB.SharpKillBloodlustReduction }
        end
    else
        if self:inFrenzy() then
            return { hit = SB.FrenzyHitBloodlustIncrease, kill = SB.FrenzyKillBloodlustIncrease }
        else
            return { hit = SB.HitBloodlustReduction, kill = SB.KillBloodlustReduction }
        end
    end
end


function Bloodlust:shout(radius, text)
    -- Same as shouting
    WorldSoundManager.instance:addSound(
        self.player,
        self.player:getX(), self.player:getY(), self.player:getZ(),
        radius, radius,
        false,
        0.0,
        1.0,
        false,
        true,
        false,
        false,
        true
    )

    if text then
        self.player:addLineChatElement(text, 1, 0, 0)
    end
end

--- @param value number 0-100
function Bloodlust:addStrain(value)
    local body_damage = self.player:getBodyDamage()

    local available_parts = {}
    for _, part in ipairs(STRAIN_PARTS) do
        table.insert(available_parts, part)
    end

    local remaining = value
    while remaining > 0 and #available_parts > 0 do
        local index = ZombRand(#available_parts) + 1
        local part = available_parts[index]

        local capacity = 100 - body_damage:getBodyPart(part):getStiffness()
        if capacity > 0 then
            local chunk = math.min(
                ZombRand(math.ceil(remaining)) + 1,
                remaining,
                capacity
            )

            body_damage:addStiffness(part, chunk)
            remaining = remaining - chunk
        else
            table.remove(available_parts, index)
        end
    end
end

Bloodlust.event_listeners = {}
function Bloodlust.registerEventListener(listener)
    table.insert(Bloodlust.event_listeners, listener)
end

--- @param type string
function Bloodlust:emitEvent(type)
    for _, listener in ipairs(Bloodlust.event_listeners) do
        listener(self.player, type)
    end
end

--endregion



--region Events

local function onEveryMinute()
    local players = IsoPlayer.getPlayers()
    for i=0, players:size()-1 do
        local player = players:get(i)
        if (player and isLocalPlayer(player) and player:hasTrait(BloodlustTrait)) then
            local instance = Bloodlust.getInstance(player)
            instance:preUpdate(player, 'minute')
            instance:onEveryMinute()
        end
    end
end
Events.EveryOneMinute.Add(onEveryMinute)

--- @param zombie IsoZombie
local function onZombieKill(zombie)
    local player = zombie:getAttackedBy()
    if not instanceof(player, "IsoPlayer") then return end
    if not isLocalPlayer(player) then return end
    if not player:hasTrait(BloodlustTrait) then return end

    local instance = Bloodlust.getInstance(player)
    instance:preUpdate(player, 'kill')
    instance:onZombieKill(zombie)
end
Events.OnZombieDead.Add(onZombieKill)

--- @param player IsoPlayer
--- @param target IsoLivingCharacter
--- @param weapon HandWeapon
--- @param damage number
local function onWeaponHit(player, target, weapon, damage)
    if not instanceof(player, "IsoPlayer") then return end
    if not isLocalPlayer(player) then return end
    if not instanceof(target, "IsoZombie") then return end
    if not player:hasTrait(BloodlustTrait) then return end

    local instance = Bloodlust.getInstance(player)
    instance:preUpdate(player, 'hit')
    instance:onZombieHit(weapon, target)
end
Events.OnWeaponHitCharacter.Add(onWeaponHit)


local last_hit_list = {}

--- @param player IsoPlayer
local function onPlayerUpdate(player)
    if not isLocalPlayer(player) then return end
    if not player:hasTrait(BloodlustTrait) then return end

    local instance = Bloodlust.getInstance(player)
    instance:preUpdate(player, 'tick')
    instance:onPlayerUpdate()

    -- Detect when player gets hit
    local hit_reaction = player:getHitReaction()
    local attacked_by = player:getAttackedBy()
    if attacked_by then attacked_by = attacked_by:customHashCode() end
    local last_hit = last_hit_list[player:getID()] or {}
    if hit_reaction == last_hit.hit_reaction and attacked_by == last_hit.attacked_by then return end
    last_hit_list[player:getID()] = { hit_reaction = hit_reaction, attacked_by = attacked_by }

    -- Bite, Bite Defended, Crawler Bite, Crawler Bite LEFT ...
    if hit_reaction:find('Bite', 1, true)
            and not hit_reaction:find('Defend', 1, true) then
        instance:onPlayerHit()
    end
end
Events.OnPlayerUpdate.Add(onPlayerUpdate)


--- @param player IsoPlayer
local function onPlayerMove(player)
    if not isLocalPlayer(player) then return end
    if not player:hasTrait(BloodlustTrait) then return end

    local instance = Bloodlust.getInstance(player)
    instance:preUpdate(player, 'move')
    instance:onPlayerMove()
end
Events.OnPlayerMove.Add(onPlayerMove)

--endregion


return Bloodlust
