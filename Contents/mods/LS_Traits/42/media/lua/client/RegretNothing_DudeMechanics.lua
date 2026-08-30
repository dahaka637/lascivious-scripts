local RN_TraitObj = nil

-- ============================================================
-- Safe call helper.
--
-- RN_OnPlayerUpdate runs every frame, so ANY call in it that starts throwing (a game
-- update changing an API, Moodle Framework missing or changed, etc.) produces an endless
-- error stream in the console -- PZ logs caught pcall errors too, so a bare pcall does
-- NOT stop the spam. RN_safe runs a call once, and if it fails it logs a single line and
-- permanently disables that one operation for the session. Everything else keeps working.
--
-- LasciviousScripts: originally only RN_OnPlayerUpdate used RN_safe; RN_OnZombieDead and
-- RN_EveryTenMinutes still used a bare pcall (same spam risk on repeated zombie kills /
-- every-ten-minutes ticks), and RN_OnWeaponHitCharacter / RN_OnEquipPrimary had no error
-- protection at all despite firing on frequent combat/equip events. Extended RN_safe to
-- all four so a single bad call anywhere in this file costs one log line, never a stream.
-- ============================================================
local RN_disabled = {}

---@param key string  unique id for this operation
---@param fn function
---@return boolean ok
local function RN_safe(key, fn)
    if RN_disabled[key] then return false end
    local ok, err = pcall(fn)
    if not ok then
        RN_disabled[key] = true
        print("[RegretNothing] disabled '" .. tostring(key) .. "' after error: " .. tostring(err))
    end
    return ok
end

local function getTraitObj()
    if RN_TraitObj then return RN_TraitObj end
    local ok, obj = pcall(function()
        return CharacterTrait.get(ResourceLocation.of("RegretNothing:RegretNothing"))
    end)
    if ok and obj then
        RN_TraitObj = obj
        return RN_TraitObj
    end
    return nil
end

local function hasTrait(player)
    if not player then return false end

    local modData = player:getModData()
    if modData.RN_HasRegretNothingTrait == true then
        return true
    end

    local traitObj = getTraitObj()
    if traitObj then
        local ok, res = pcall(function() return player:hasTrait(traitObj) end)
        if ok and res == true then
            modData.RN_HasRegretNothingTrait = true
            return true
        end
    end

    return false
end

-- ============================================================
-- 1. On Zombie Kill: reduce Boredom/Unhappiness
-- ============================================================
local function RN_OnZombieDead(zombie, attacker)
    local player = attacker
    if not player then player = getPlayer() end
    if not player then return end
    if not hasTrait(player) then return end

    local modData = player:getModData()
    modData.RN_LastKillTime = getGameTime():getWorldAgeHours()

    local stats = player:getStats()
    if stats then
        RN_safe("zombiedead_stats", function()
            local b = stats:get(CharacterStat.BOREDOM)
            local u = stats:get(CharacterStat.UNHAPPINESS)
            stats:set(CharacterStat.BOREDOM, math.max(0, b - 2.5))
            stats:set(CharacterStat.UNHAPPINESS, math.max(0, u - 2.5))
        end)
    end
end

-- ============================================================
-- 2. Every Ten Minutes: increase Boredom/Unhappiness if no kill
-- ============================================================
local function RN_EveryTenMinutes()
    local player = getPlayer()
    if not player then return end
    if not hasTrait(player) then return end

    local modData = player:getModData()
    local currentTime = getGameTime():getWorldAgeHours()

    if not modData.RN_LastKillTime then
        modData.RN_LastKillTime = currentTime
        return
    end

    local hoursSince = currentTime - modData.RN_LastKillTime

    if hoursSince > 2.0 then
        local stats = player:getStats()
        if stats then
            RN_safe("everyten_stats", function()
                local b = stats:get(CharacterStat.BOREDOM)
                local u = stats:get(CharacterStat.UNHAPPINESS)
                stats:set(CharacterStat.BOREDOM, math.min(100, b + 3.0))
                stats:set(CharacterStat.UNHAPPINESS, math.min(100, u + 3.0))
            end)
        end
    end
end

-- ============================================================
-- 3. Every Player Update
-- ============================================================
local function RN_OnPlayerUpdate(player)
    if not hasTrait(player) then return end

    local stats = player:getStats()
    local bd = player:getBodyDamage()

    if stats then
        RN_safe("foodsickness", function() stats:set(CharacterStat.FOOD_SICKNESS, 0) end)
        RN_safe("poison", function() stats:set(CharacterStat.POISON, 0) end)
        -- Bugfix: this used to clear STRESS only, with a comment claiming panic immunity.
        -- PANIC and STRESS are two different CharacterStats, so panic was never suppressed.
        -- base:desensitized in traits.txt is the primary (engine-level) immunity; this is a backstop.
        RN_safe("panic", function() stats:set(CharacterStat.PANIC, 0) end)
        RN_safe("stress", function() stats:set(CharacterStat.STRESS, 0) end)
    end

    local modData = player:getModData()
    local isBuffed = modData.RN_ConsumableBuffEnd and getGameTime():getWorldAgeHours() < modData.RN_ConsumableBuffEnd

    if isBuffed and stats then
        RN_safe("endurance", function()
            local e = stats:get(CharacterStat.ENDURANCE)
            stats:set(CharacterStat.ENDURANCE, math.min(1.0, e + 0.05))
        end)
    end

    local isFrenzied = false
    if bd then
        RN_safe("bittenscan", function()
            local parts = bd:getBodyParts()
            for i = 0, parts:size() - 1 do
                if parts:get(i):bitten() then
                    isFrenzied = true
                    break
                end
            end
        end)
    end

    -- Moodle updates. The state flags are written BEFORE the Moodle Framework call, not
    -- after: previously a throw inside getMoodle/setValue skipped the assignment, so the
    -- same branch re-fired on the very next frame and the error repeated forever. Now a
    -- failure costs one log line and the moodle simply stops updating.
    if MF and MF.getMoodle then
        local pNum = player:getPlayerNum()

        if isFrenzied ~= modData.RN_WasFrenzied then
            modData.RN_WasFrenzied = isFrenzied
            RN_safe("moodle_frenzy", function()
                local m = MF.getMoodle("RNFrenzy", pNum)
                -- MF.ISMoodle only hides itself when the value sits in the neutral
                -- band around 0.5 (default thresholds 0.4/0.6) -- 0.0 is NOT neutral,
                -- it's the far BAD extreme, so "not frenzied" was rendering as a
                -- level-4 bad moodle instead of disappearing. 0.5 is the framework's
                -- own "nothing to report" sentinel (see MF.ISMoodle:getMoodleData's
                -- default Value=0.5).
                if m then m:setValue(isFrenzied and 1.0 or 0.5) end
            end)
        end

        if isBuffed ~= modData.RN_WasBuffed then
            modData.RN_WasBuffed = isBuffed
            RN_safe("moodle_meleebuff", function()
                local m = MF.getMoodle("RNMeleebuff", pNum)
                -- Same fix as RNFrenzy above -- 0.0 is the BAD extreme, not neutral.
                if m then m:setValue(isBuffed and 1.0 or 0.5) end
            end)
        end
    end

    if isFrenzied then
        if stats then
            RN_safe("frenzy_stats", function()
                stats:set(CharacterStat.PAIN, 0)
                stats:set(CharacterStat.ENDURANCE, 1.0)
                stats:set(CharacterStat.FATIGUE, 0)
            end)
        end

        if not modData.RN_FrenzyBoostApplied then
            modData.RN_FrenzyBoostApplied = true
            RN_safe("frenzy_perks", function()
                local boostPerks = {
                    Perks.Strength, Perks.Fitness, Perks.Aiming,
                    Perks.Blunt, Perks.Axe, Perks.Spear,
                    Perks.LongBlade, Perks.SmallBlade, Perks.SmallBlunt
                }
                for _, perk in ipairs(boostPerks) do
                    -- Bounded: if LevelPerk ever stops raising the level (perk renamed,
                    -- capped differently) an unbounded while here would hang the game.
                    local guard = 0
                    while player:getPerkLevel(perk) < 10 and guard < 10 do
                        player:LevelPerk(perk, false)
                        guard = guard + 1
                    end
                end
            end)
        end
    else
        modData.RN_FrenzyBoostApplied = nil
    end
end

-- ============================================================
-- 4. Weapon Hit
-- ============================================================
local function RN_OnWeaponHitCharacter(attacker, target, weapon, damageSplit)
    if not hasTrait(attacker) then return end
    RN_safe("weaponhit_buff", function()
        local modData = attacker:getModData()
        if modData.RN_ConsumableBuffEnd and getGameTime():getWorldAgeHours() < modData.RN_ConsumableBuffEnd then
            if target and target:getHealth() > 0 then
                target:setHealth(target:getHealth() - (damageSplit * 0.1))
            end
        end
    end)
end

-- ============================================================
-- 5. Weapon Equip
-- ============================================================
local function RN_OnEquipPrimary(character, item)
    if not hasTrait(character) then return end
    if not item then return end
    local ok, isWeapon = pcall(function() return item:IsWeapon() end)
    if not (ok and isWeapon) then return end

    RN_safe("equipprimary_conditionbuff", function()
        local wType = item:getType()
        if wType == "Base.Shovel" or wType == "Base.Nightstick" or wType == "Base.Scissors" then
            local md = item:getModData()
            if not md.RN_ConditionBuffed then
                local chance = item:getConditionLowerChance()
                if chance and chance > 0 then
                    item:setConditionLowerChance(chance * 2)
                end
                md.RN_ConditionBuffed = true
            end
        end
    end)
end

-- ============================================================
-- 6. Player Created
-- ============================================================
local function RN_OnCreatePlayer(playerIndex, player)
    local modData = player:getModData()
    local hasIt = false

    local ok, res = pcall(function()
        local traitsList = player:getCharacterTraits():getKnownTraits()
        for i = 0, traitsList:size() - 1 do
            local traitName = tostring(traitsList:get(i))
            if traitName and (string.find(traitName, "RegretNothing") or string.find(traitName, "regretnothing")) then
                return true
            end
        end
        return false
    end)

    if ok and res == true then hasIt = true end

    if hasIt then
        modData.RN_HasRegretNothingTrait = true
        if not modData.RN_LastKillTime then
            modData.RN_LastKillTime = getGameTime():getWorldAgeHours()
        end
    end

    modData.RN_WasFrenzied = nil
    modData.RN_WasBuffed = nil
    modData.RN_FrenzyBoostApplied = nil
end

-- ============================================================
-- 7. Cigarette / Painkiller buff via ISEatFoodAction hook.
-- ============================================================
local function RN_InjectEatHook()
    if ISEatFoodAction and not ISEatFoodAction.RN_Hooked then
        local orig = ISEatFoodAction.perform
        function ISEatFoodAction:perform(...)
            orig(self, ...)
            if self.character and self.item then
                if hasTrait(self.character) then
                    local t = self.item:getFullType()
                    -- B42.15: renamed to CigaretteSingle; keep old name as fallback
                    if t == "Base.CigaretteSingle" or t == "Base.Cigar" or t == "Base.Pills" then
                        self.character:getModData().RN_ConsumableBuffEnd =
                            getGameTime():getWorldAgeHours() + 2.0
                    end
                end
            end
        end
        ISEatFoodAction.RN_Hooked = true
    end
end

-- ============================================================
-- Register events
-- ============================================================
Events.OnGameBoot.Add(RN_InjectEatHook)
Events.OnZombieDead.Add(RN_OnZombieDead)
Events.EveryTenMinutes.Add(RN_EveryTenMinutes)
Events.OnPlayerUpdate.Add(RN_OnPlayerUpdate)
Events.OnWeaponHitCharacter.Add(RN_OnWeaponHitCharacter)
Events.OnEquipPrimary.Add(RN_OnEquipPrimary)
Events.OnCreatePlayer.Add(RN_OnCreatePlayer)
