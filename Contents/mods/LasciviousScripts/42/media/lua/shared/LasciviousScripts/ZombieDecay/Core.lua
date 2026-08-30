-- Lascivious Scripts - Progressive Zombie Decay
-- Shared deterministic model for Project Zomboid Build 42.
-- This file is a module of LasciviousScripts, not a standalone mod.

LasciviousScripts = LasciviousScripts or {}
LasciviousScripts.ZombieDecay = LasciviousScripts.ZombieDecay or {}

local Core = LasciviousScripts.ZombieDecay

Core.VERSION = "1.0.0"
Core.OPTION_TABLE = "LasciviousScriptsZombieDecay"

Core.SPEED_SPRINTER = 1
Core.SPEED_FAST_SHAMBLER = 2
Core.SPEED_SHAMBLER = 3
Core.SPEED_RANDOM = 4

Core.DEFAULTS = {
    Enabled = true,
    TimelineScalePercent = 100,
    MinimumRunnerSpeedPercent = 50,
    FinalShamblerCollapseEnabled = true,
    DebugLogging = false,
}

Core.BASE_DAYS = {
    BrutalEnd = 7,
    RunnerSlowdownStart = 30,
    RunnerSpeedFloor = 180,
    RunnersGone = 365,
    FinalDecay = 730,
    FinalCollapse = 1460,
}

Core._originalLore = Core._originalLore or nil
Core._warned = Core._warned or {}
Core.LORE_OPTIONS = {
    "ZombieLore.Speed", "ZombieLore.SprinterPercentage", "ZombieLore.Strength",
    "ZombieLore.Toughness", "ZombieLore.Cognition", "ZombieLore.Memory",
    "ZombieLore.Sight", "ZombieLore.Hearing",
}

local function clamp(value, minimum, maximum)
    value = tonumber(value) or minimum
    if value < minimum then return minimum end
    if value > maximum then return maximum end
    return value
end

local function round(value)
    return math.floor((tonumber(value) or 0) + 0.5)
end

local function lerp(a, b, t)
    if t <= 0 then return a end
    if t >= 1 then return b end
    return a + (b - a) * t
end

local function progress(value, startValue, endValue)
    if endValue <= startValue then return value >= endValue and 1 or 0 end
    return clamp((value - startValue) / (endValue - startValue), 0, 1)
end

local function getLiveOption(name, fallback)
    local fullName = Core.OPTION_TABLE .. "." .. name
    local options = getSandboxOptions and getSandboxOptions() or nil

    if options then
        local option = options:getOptionByName(fullName)
        if option then
            local value = option:getValue()
            if value ~= nil then return value end
        end
    end

    local tableVars = SandboxVars and SandboxVars[Core.OPTION_TABLE] or nil
    if tableVars and tableVars[name] ~= nil then return tableVars[name] end
    return fallback
end

function Core.getConfig()
    local cfg = {}
    cfg.Enabled = getLiveOption("Enabled", Core.DEFAULTS.Enabled) == true
    cfg.TimelineScalePercent = round(clamp(getLiveOption("TimelineScalePercent", Core.DEFAULTS.TimelineScalePercent), 25, 400))
    cfg.MinimumRunnerSpeedPercent = round(clamp(getLiveOption("MinimumRunnerSpeedPercent", Core.DEFAULTS.MinimumRunnerSpeedPercent), 25, 100))
    cfg.FinalShamblerCollapseEnabled = getLiveOption("FinalShamblerCollapseEnabled", Core.DEFAULTS.FinalShamblerCollapseEnabled) == true
    cfg.DebugLogging = getLiveOption("DebugLogging", Core.DEFAULTS.DebugLogging) == true

    local scale = cfg.TimelineScalePercent / 100
    cfg.BrutalEnd = Core.BASE_DAYS.BrutalEnd * scale
    cfg.RunnerSlowdownStart = Core.BASE_DAYS.RunnerSlowdownStart * scale
    cfg.RunnerSpeedFloor = Core.BASE_DAYS.RunnerSpeedFloor * scale
    cfg.RunnersGone = Core.BASE_DAYS.RunnersGone * scale
    cfg.FinalDecay = Core.BASE_DAYS.FinalDecay * scale
    cfg.FinalCollapse = Core.BASE_DAYS.FinalCollapse * scale
    return cfg
end

function Core.getWorldAgeDays()
    if IsoWorld and IsoWorld.instance then
        local ok, value = pcall(function() return IsoWorld.instance:getWorldAgeDays() end)
        if ok and value then return math.max(0, tonumber(value) or 0) end
    end

    if getGameTime then
        local gameTime = getGameTime()
        if gameTime then
            local ok, hours = pcall(function() return gameTime:getWorldAgeHours() end)
            if ok and hours then return math.max(0, (tonumber(hours) or 0) / 24) end
        end
    end

    return 0
end

function Core.buildState(worldAgeDays, cfg)
    cfg = cfg or Core.getConfig()
    local day = math.max(0, tonumber(worldAgeDays) or 0)
    local state = {enabled = cfg.Enabled, day = day, cfg = cfg}

    if not cfg.Enabled then
        state.phase = 0
        state.loreRevision = 0
        state.runnerSpeedPercent = 100
        state.runnerChance = 0
        state.shamblerChance = 0
        state.tierRevision = -1
        return state
    end

    if day < cfg.BrutalEnd then
        state.phase = 1
        state.phaseName = "SURTO_RECENTE"
        state.loreRevision = 1
        state.strength = 1
        state.toughness = 1
        -- cognition=1 is "Navigate and Use Doors", the highest AI tier. This module
        -- never touches ZombieLore.DoorOpeningPercentage (see applyVanillaLore/
        -- captureOriginalLore below), so the actual share of zombies that act on the
        -- door-opening capability stays fully controlled by whatever the server has
        -- configured natively for that option -- explicit request, server always runs
        -- DoorOpeningPercentage at 0.
        state.cognition = 1
        state.memory = 1
        state.sight = 1
        state.hearing = 1
    elseif day < cfg.RunnerSpeedFloor then
        state.phase = 2
        state.phaseName = day < cfg.RunnerSlowdownStart and "DEGRADACAO_NEUROLOGICA" or "DEGRADACAO_MUSCULAR"
        state.loreRevision = 2
        state.strength = 2
        state.toughness = 2
        state.cognition = 4
        state.memory = 2
        state.sight = 2
        state.hearing = 2
    elseif day < cfg.RunnersGone then
        state.phase = 3
        state.phaseName = "COLAPSO_DA_CORRIDA"
        state.loreRevision = 3
        state.strength = 2
        state.toughness = 2
        state.cognition = 3
        state.memory = 2
        state.sight = 5
        state.hearing = 5
    else
        if day < cfg.FinalDecay then
            state.phase = 4
            state.phaseName = "DECOMPOSICAO_AVANCADA"
        elseif cfg.FinalShamblerCollapseEnabled and day < cfg.FinalCollapse then
            state.phase = 5
            state.phaseName = "COLAPSO_FINAL_SHAMBLER"
        else
            state.phase = cfg.FinalShamblerCollapseEnabled and 6 or 5
            state.phaseName = "ESTADO_FINAL"
        end
        state.loreRevision = 4
        state.strength = 3
        state.toughness = 3
        state.cognition = 3
        state.memory = 2
        state.sight = 5
        state.hearing = 5
    end

    if day < cfg.RunnerSlowdownStart then
        state.runnerSpeedPercent = 100
    elseif day < cfg.RunnerSpeedFloor then
        local t = progress(day, cfg.RunnerSlowdownStart, cfg.RunnerSpeedFloor)
        state.runnerSpeedPercent = round(lerp(100, cfg.MinimumRunnerSpeedPercent, t))
    else
        state.runnerSpeedPercent = cfg.MinimumRunnerSpeedPercent
    end

    if day < cfg.RunnerSpeedFloor then
        state.runnerChance = 100
    elseif day < cfg.RunnersGone then
        local t = progress(day, cfg.RunnerSpeedFloor, cfg.RunnersGone)
        state.runnerChance = round(lerp(100, 0, t))
    else
        state.runnerChance = 0
    end

    -- No percentage mix: once Runners are gone (day 365) the population is 100% Fast
    -- Shambler, period. With FinalShamblerCollapseEnabled, a second stage starting at
    -- the day-730 milestone gradually turns Fast Shamblers into plain Shamblers over
    -- another FinalDecay-length window, reaching 100% Shambler by day 1460.
    if not cfg.FinalShamblerCollapseEnabled or day < cfg.FinalDecay then
        state.shamblerChance = 0
    elseif day < cfg.FinalCollapse then
        local t = progress(day, cfg.FinalDecay, cfg.FinalCollapse)
        state.shamblerChance = round(lerp(0, 100, t))
    else
        state.shamblerChance = 100
    end

    state.runnerChance = round(clamp(state.runnerChance, 0, 100))
    state.shamblerChance = round(clamp(state.shamblerChance, 0, 100))
    state.runnerSpeedPercent = round(clamp(state.runnerSpeedPercent, cfg.MinimumRunnerSpeedPercent, 100))
    state.tierRevision = math.floor(day)
    return state
end

function Core.getStableSeed(zombie)
    if not zombie then return nil end

    local okId, onlineId = pcall(function() return zombie:getOnlineID() end)
    if okId and onlineId and tonumber(onlineId) and tonumber(onlineId) >= 0 then
        return math.abs(tonumber(onlineId))
    end

    if isClient and isClient() then
        return nil
    end

    local okHash, hash = pcall(function() return zombie:hashCode() end)
    if okHash and hash then return math.abs(tonumber(hash) or 0) end

    local okPos, x, y, z = pcall(function() return zombie:getX(), zombie:getY(), zombie:getZ() end)
    if okPos then
        return math.abs(round((x or 0) * 31 + (y or 0) * 131 + (z or 0) * 8191))
    end

    return nil
end

function Core.rollPercent(seed, salt)
    if seed == nil then return nil end
    salt = tonumber(salt) or 0
    local mixed = (math.abs(seed) * 7919 + 104729 + salt * 15485863) % 1000003
    return (mixed % 10000) / 100
end

function Core.getDesiredTier(zombie, state)
    if not state or not state.enabled then return nil end
    local seed = Core.getStableSeed(zombie)
    if seed == nil then return nil end

    if state.day < state.cfg.RunnerSpeedFloor then return Core.SPEED_SPRINTER end

    if state.day < state.cfg.RunnersGone then
        local runnerRoll = Core.rollPercent(seed, 1)
        return runnerRoll < state.runnerChance and Core.SPEED_SPRINTER or Core.SPEED_FAST_SHAMBLER
    end

    local shamblerRoll = Core.rollPercent(seed, 2)
    return shamblerRoll < state.shamblerChance and Core.SPEED_SHAMBLER or Core.SPEED_FAST_SHAMBLER
end

local function sameValue(a, b)
    if type(a) == "number" or type(b) == "number" then
        return math.abs((tonumber(a) or 0) - (tonumber(b) or 0)) < 0.0001
    end
    return a == b
end

local function getVanillaValue(name)
    local options = getSandboxOptions and getSandboxOptions() or nil
    if not options then return nil end
    local option = options:getOptionByName(name)
    if not option then return nil end
    return option:getValue()
end

local function setVanillaValue(name, value)
    local options = getSandboxOptions and getSandboxOptions() or nil
    if not options then return false end

    local option = options:getOptionByName(name)
    if not option then
        if not Core._warned[name] then
            print("[LasciviousScripts/ZombieDecay] WARNING: sandbox option not found: " .. tostring(name))
            Core._warned[name] = true
        end
        return false
    end

    local current = option:getValue()
    if sameValue(current, value) then return false end
    options:set(name, value)
    return true
end

-- Deliberately excluded: ZombieLore.DoorOpeningPercentage, ZombiesDragDown and
-- ZombiesFenceLunge. This module never reads or writes any of these, so they always
-- stay whatever the server has configured natively -- explicit request, those three
-- are the admin's call, not the decay system's.
function Core.captureOriginalLore()
    if Core._originalLore then return Core._originalLore end
    Core._originalLore = {}
    for _, name in ipairs(Core.LORE_OPTIONS) do
        Core._originalLore[name] = getVanillaValue(name)
    end
    return Core._originalLore
end

function Core.setOriginalLore(snapshot)
    if type(snapshot) ~= "table" then return false end
    local copy, count = {}, 0
    for _, name in ipairs(Core.LORE_OPTIONS) do
        local value = snapshot[name]
        if value ~= nil then copy[name], count = value, count+1 end
    end
    if count ~= #Core.LORE_OPTIONS then return false end
    Core._originalLore = copy
    return true
end

function Core.copyOriginalLore()
    if not Core._originalLore then return nil end
    local copy = {}
    for _, name in ipairs(Core.LORE_OPTIONS) do copy[name] = Core._originalLore[name] end
    return copy
end

function Core.applyVanillaLore(state)
    if not state or not state.enabled then return false end
    Core.captureOriginalLore()

    local changed = false
    local speedValue = state.day < state.cfg.RunnerSpeedFloor and Core.SPEED_SPRINTER or Core.SPEED_RANDOM
    local sprinterValue = state.day < state.cfg.RunnerSpeedFloor and 100 or state.runnerChance

    changed = setVanillaValue("ZombieLore.Speed", speedValue) or changed
    changed = setVanillaValue("ZombieLore.SprinterPercentage", sprinterValue) or changed
    changed = setVanillaValue("ZombieLore.Strength", state.strength) or changed
    changed = setVanillaValue("ZombieLore.Toughness", state.toughness) or changed
    changed = setVanillaValue("ZombieLore.Cognition", state.cognition) or changed
    changed = setVanillaValue("ZombieLore.Memory", state.memory) or changed
    changed = setVanillaValue("ZombieLore.Sight", state.sight) or changed
    changed = setVanillaValue("ZombieLore.Hearing", state.hearing) or changed

    if changed then
        local options = getSandboxOptions and getSandboxOptions() or nil
        if options then pcall(function() options:toLua() end) end
    end

    return changed
end

function Core.restoreOriginalLore()
    if not Core._originalLore then return false end
    local changed = false

    for name, value in pairs(Core._originalLore) do
        if value ~= nil then changed = setVanillaValue(name, value) or changed end
    end

    if changed then
        local options = getSandboxOptions and getSandboxOptions() or nil
        if options then pcall(function() options:toLua() end) end
    end

    return changed
end

function Core.describeState(state)
    if not state or not state.enabled then return "disabled" end
    return string.format("day=%.2f phase=%s runnerChance=%d%% runnerSpeed=%d%% shamblerChance=%d%%", state.day, tostring(state.phaseName), state.runnerChance, state.runnerSpeedPercent, state.shamblerChance)
end

return Core
