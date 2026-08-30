-- Lascivious Scripts - Progressive Zombie Decay
-- Client/single-player zombie simulation and Build 42 root-motion control.

require "LasciviousScripts/ZombieDecay/Core"

local Core = LasciviousScripts.ZombieDecay
local Runtime = {
    state = nil,
    loreRevision = nil,
    loreGeneration = 0,
    zombieCache = setmetatable({}, {__mode = "k"}),
    warnedTierSetter = false,
}

local MOVE_VARIABLE = "LasciviousZombieDecayMoveScale"
local LUNGE_VARIABLE = "LasciviousZombieDecayLungeScale"
local FULL_MOVE_ANIM_SPEED = 0.80
local FULL_LUNGE_ANIM_SPEED = 0.90

print("[LasciviousScripts/ZombieDecay] client module loaded v" .. Core.VERSION)

local function debugLog(message)
    local cfg = Runtime.state and Runtime.state.cfg or Core.getConfig()
    if cfg.DebugLogging then print("[LasciviousScripts/ZombieDecay] " .. tostring(message)) end
end

local function refreshWorldState()
    local cfg = Core.getConfig()

    if not cfg.Enabled then
        Core.restoreOriginalLore()
        Runtime.state = Core.buildState(Core.getWorldAgeDays(), cfg)
        Runtime.loreRevision = nil
        return
    end

    local newState = Core.buildState(Core.getWorldAgeDays(), cfg)
    Core.applyVanillaLore(newState)

    if Runtime.loreRevision ~= newState.loreRevision then
        Runtime.loreRevision = newState.loreRevision
        Runtime.loreGeneration = Runtime.loreGeneration + 1
        debugLog("lore revision changed: " .. Core.describeState(newState))
    end

    Runtime.state = newState
end

local function setZombieTier(zombie, tier)
    local ok = false

    if tier == Core.SPEED_SPRINTER then
        ok = pcall(function() zombie:doSprinter() end)
    elseif tier == Core.SPEED_FAST_SHAMBLER then
        ok = pcall(function() zombie:doFastShambler() end)
    elseif tier == Core.SPEED_SHAMBLER then
        ok = pcall(function() zombie:doShambler() end)
    end

    if not ok and not Runtime.warnedTierSetter then
        print("[LasciviousScripts/ZombieDecay] WARNING: B42 explicit zombie speed setter failed. Exact tier transitions are unavailable on this game build.")
        Runtime.warnedTierSetter = true
    end

    return ok
end

local function refreshZombieStats(zombie)
    local oldHealth = nil
    pcall(function() oldHealth = zombie:getHealth() end)

    local ok = pcall(function() zombie:DoZombieStats() end)
    if not ok then return false end

    if oldHealth and oldHealth > 0 then
        local newHealth = nil
        pcall(function() newHealth = zombie:getHealth() end)
        if newHealth and oldHealth < newHealth then pcall(function() zombie:setHealth(oldHealth) end) end
    end

    return true
end

local function clearRunnerVariables(zombie, cache)
    if not cache.runnerVariablesApplied then return end
    pcall(function() zombie:clearVariable(MOVE_VARIABLE) end)
    pcall(function() zombie:clearVariable(LUNGE_VARIABLE) end)
    cache.runnerVariablesApplied = false
end

local function applyRunnerVariables(zombie, state, cache)
    local percent = state.runnerSpeedPercent
    local moveScale = FULL_MOVE_ANIM_SPEED * percent / 100
    local lungeScale = FULL_LUNGE_ANIM_SPEED * percent / 100

    -- Reapply on every zombie update. B42 animation state can recycle variables.
    zombie:setVariable(MOVE_VARIABLE, moveScale)
    zombie:setVariable(LUNGE_VARIABLE, lungeScale)
    cache.runnerVariablesApplied = true
    cache.lastRunnerPercent = percent
end

local function updateZombie(zombie)
    local state = Runtime.state
    if not state then
        refreshWorldState()
        state = Runtime.state
    end

    if not state or not state.enabled or not zombie or zombie:isDead() then return end

    local cache = Runtime.zombieCache[zombie]
    if not cache then
        cache = {loreGeneration = -1, tierRevision = -1, desiredTier = nil, runnerVariablesApplied = false}
        Runtime.zombieCache[zombie] = cache
    end

    if cache.loreGeneration ~= Runtime.loreGeneration then
        refreshZombieStats(zombie)
        cache.loreGeneration = Runtime.loreGeneration
        cache.tierRevision = -1
    end

    if cache.tierRevision ~= state.tierRevision or cache.desiredTier == nil then
        cache.desiredTier = Core.getDesiredTier(zombie, state)
        cache.tierRevision = state.tierRevision
    end

    local desiredTier = cache.desiredTier
    if desiredTier ~= nil then
        local actualTier = nil
        pcall(function() actualTier = zombie:getSpeedType() end)

        if actualTier ~= desiredTier then
            setZombieTier(zombie, desiredTier)
            pcall(function() actualTier = zombie:getSpeedType() end)
        end

        if desiredTier == Core.SPEED_SPRINTER then
            applyRunnerVariables(zombie, state, cache)
        else
            clearRunnerVariables(zombie, cache)
        end
    end
end

local function onZombieCreate(zombie)
    if not Runtime.state then refreshWorldState() end
    if not Runtime.state or not Runtime.state.enabled or not zombie then return end

    local cache = {loreGeneration = Runtime.loreGeneration, tierRevision = Runtime.state.tierRevision, desiredTier = Core.getDesiredTier(zombie, Runtime.state), runnerVariablesApplied = false}
    Runtime.zombieCache[zombie] = cache

    -- New zombies are already created against the current lore. Only force the
    -- exact movement tier and runner root-motion variables.
    if cache.desiredTier then setZombieTier(zombie, cache.desiredTier) end
    if cache.desiredTier == Core.SPEED_SPRINTER then applyRunnerVariables(zombie, Runtime.state, cache) end
end

Events.OnGameStart.Add(refreshWorldState)
Events.EveryTenMinutes.Add(refreshWorldState)
Events.OnZombieCreate.Add(onZombieCreate)
Events.OnZombieUpdate.Add(updateZombie)
