-- Lascivious Factions System - own-territory wellbeing effects (client side).
--
-- Character stats are client-authoritative in Build 42 (there is no clean way to
-- have the server verify or apply moodle/stat changes the way it does for, say,
-- credits), so these effects are applied to the local player only, client-side.
-- A modified client could in principle force this permanently; this is a soft
-- quality-of-life buff, not an economy, so that trade-off is accepted rather than
-- built around -- same call the original version of this file made.
--
-- Gated by the faction's Bem-estar upgrade level (FF.UPGRADE_TYPES key
-- "wellbeing", see LFS_Upgrades.lua): level 0 applies nothing at all, level 10
-- applies the full rates below. Every rate is expressed as a PERCENT OF THE
-- STAT'S OWN REAL RANGE per game-minute at level 10 -- not a bare absolute
-- constant -- specifically so "how much is enough to matter" is a computed
-- answer (percent x range) instead of a fresh guess per stat. See STATS below.
--
-- Four independent categories, each with its own sandbox toggle and its own
-- failure isolation (a broken category logs once and keeps retrying every
-- game-minute; it does NOT permanently disable itself or the other three the
-- way the old single pcall used to). TerritoryWellbeingPower remains a global
-- multiplier on top of the level fraction, and a global kill switch at 0.

require "LFS_Shared"
require "LFS_Claims"
require "LFS_Upgrades"
require "LFS_Localization"

local FF = LasciviousFactionsSystem
local Claims = FF.Claims

-- ---------------------------------------------------------------------------
-- Stat catalog: min/max are each CharacterStat's real native range (verified
-- against Build 42's own debug stat panel -- see the per-stat notes below),
-- `pct` is the percent OF THAT RANGE removed (dir=-1) or added (dir=1) per
-- game-minute at full intensity (Bem-estar level 10, TerritoryWellbeingPower 1).
-- A stat's own scale is baked into the formula this way: 1% of a 0..100 stat is
-- always 1.0, 1% of a 0..1 stat is always 0.01 -- nobody has to separately
-- remember which stats are which scale when tuning `pct`.
--
-- The `pct` figures themselves did not start as a fresh guess: they began as the
-- ORIGINAL absolute rates this file shipped with, each divided by its stat's own
-- range, then went through two live-tested recalibration passes after direct
-- feedback that several categories were imperceptible in real play (pain, general
-- health, zombie infection, wound timers) -- see the per-entry notes below for
-- what changed and why.
--
-- labelKey/labelFallback (not a bare `label`) because a raw PT-BR string literal
-- with accents, defined here and read by the Debug tab's snapshot tool, rendered
-- as "T?dio", "Sa?de", "Resist?ncia" etc. in testing -- every accented character
-- broke, in a font that renders those same accents correctly for FF.text/getText-
-- sourced strings (confirmed: the snapshot's own summary line, which is
-- FF.text-driven, always rendered fine). Cause not fully pinned down (tried
-- routing through string.format vs plain concatenation first -- neither mattered,
-- so the corruption is not there), but FF.text/getText is proven correct on every
-- test, so labels resolve through it now instead of guessing further.
local STATS = {
    mood = {
        { key = "boredom",     labelKey = "UI_LFS_WellbeingStatBoredom",     labelFallback = "Tédio",        stat = CharacterStat.BOREDOM,     min = 0, max = 100, pct = 0.9,  dir = -1 },
        { key = "unhappiness", labelKey = "UI_LFS_WellbeingStatUnhappiness", labelFallback = "Infelicidade", stat = CharacterStat.UNHAPPINESS, min = 0, max = 100, pct = 1.0,  dir = -1 },
        { key = "stress",      labelKey = "UI_LFS_WellbeingStatStress",      labelFallback = "Estresse",     stat = CharacterStat.STRESS,      min = 0, max = 1,   pct = 3.0,  dir = -1 },
        { key = "panic",       labelKey = "UI_LFS_WellbeingStatPanic",       labelFallback = "Pânico",       stat = CharacterStat.PANIC,       min = 0, max = 100, pct = 12.0, dir = -1 },
        { key = "anger",       labelKey = "UI_LFS_WellbeingStatAnger",       labelFallback = "Raiva",        stat = CharacterStat.ANGER,       min = 0, max = 1,   pct = 3.0,  dir = -1 },
    },
    health = {
        { key = "sickness", labelKey = "UI_LFS_WellbeingStatSickness", labelFallback = "Doença",
          stat = CharacterStat.SICKNESS, min = 0, max = 1, pct = 8.0, dir = -1 },
        -- Bumped three times on direct feedback after live testing: 0.4 -> 4.0
        -- (still "far too slow to notice" at level 8) -> 10.0 -> 12.0 ("um
        -- pouquinho mais", already close to right). At level 10/power 1 that is
        -- 12 pain/minute -- clears 50 pain in a little over 4 minutes of standing
        -- in fully-upgraded territory.
        { key = "pain", labelKey = "UI_LFS_WellbeingStatPain", labelFallback = "Dor",
          stat = CharacterStat.PAIN, min = 0, max = 100, pct = 12.0, dir = -1 },
        { key = "poison", labelKey = "UI_LFS_WellbeingStatPoison", labelFallback = "Veneno",
          stat = CharacterStat.POISON, min = 0, max = 100, pct = 0.4, dir = -1 },
        { key = "foodSickness", labelKey = "UI_LFS_WellbeingStatFoodSickness", labelFallback = "Intoxicação alimentar",
          stat = CharacterStat.FOOD_SICKNESS, min = 0, max = 100, pct = 0.4, dir = -1 },
    },
    -- Only applied while actually bitten/infected (see applyHealth). Bumped
    -- 0.05 -> 0.3 -> 0.6 (zombieInfection) on feedback that it stays barely
    -- perceptible. Worth knowing why it stays subtle regardless of this number:
    -- decompiled BodyDamage's own update FORCIBLY sets CharacterStat.ZOMBIE_INFECTION
    -- to (elapsed / infectionMortalityDuration * 100) every update while genuinely
    -- infected and progressing toward death -- vanilla overwrites whatever this
    -- removes, far more often than this tick runs. This category was always going
    -- to look weak while a real infection is actively progressing; it is not a
    -- rate-tuning problem. A real counter would mean touching infectionTime/
    -- infectionMortalityDuration directly (both have real Lua setters -- verified
    -- via decompile) instead of the CharacterStat -- deliberately NOT done here,
    -- kept simple per explicit request; worth a dedicated pass later if wanted.
    -- zombieFever, separately reported as "always reads 0% while infected", was
    -- NOT found tied to that same progress calculation anywhere in BodyDamage's
    -- update -- left untouched rather than guessing at a rate for a stat that
    -- may not be driven by anything this system can currently see.
    infection = {
        { key = "zombieInfection", labelKey = "UI_LFS_WellbeingStatZombieInfection", labelFallback = "Infecção zumbi",
          stat = CharacterStat.ZOMBIE_INFECTION, min = 0, max = 100, pct = 0.6, dir = -1 },
        { key = "zombieFever", labelKey = "UI_LFS_WellbeingStatZombieFever", labelFallback = "Febre zumbi",
          stat = CharacterStat.ZOMBIE_FEVER, min = 0, max = 100, pct = 0.72, dir = -1 },
    },
    fatigue = {
        { key = "fatigue", labelKey = "UI_LFS_WellbeingStatFatigue", labelFallback = "Fadiga",
          stat = CharacterStat.FATIGUE, min = 0, max = 1, pct = 1.4, dir = -1 },
        { key = "endurance", labelKey = "UI_LFS_WellbeingStatEndurance", labelFallback = "Resistência",
          stat = CharacterStat.ENDURANCE, min = 0, max = 1, pct = 4.0, dir = 1 },
    },
    -- Still capped light per design (hunger/thirst relief must stay "a little
    -- more", never strong and never elimination, EVEN AT LEVEL 10) -- bumped 2x
    -- (0.015 -> 0.03) on feedback asking for "um pouquinho mais, mas pouca coisa".
    needs = {
        { key = "hunger", labelKey = "UI_LFS_WellbeingStatHunger", labelFallback = "Fome",
          stat = CharacterStat.HUNGER, min = 0, max = 1, pct = 0.03, dir = -1 },
        { key = "thirst", labelKey = "UI_LFS_WellbeingStatThirst", labelFallback = "Sede",
          stat = CharacterStat.THIRST, min = 0, max = 1, pct = 0.03, dir = -1 },
        { key = "wetness", labelKey = "UI_LFS_WellbeingStatWetness", labelFallback = "Umidade",
          stat = CharacterStat.WETNESS, min = 0, max = 100, pct = 0.6, dir = -1 },
    },
}

-- Not a CharacterStat -- BodyDamage:AddGeneralHealth/getOverallBodyHealth is its
-- own small API -- so it is handled by its own branch in applyHealth rather than
-- forced into the generic list above, but still driven by the same min/max/pct
-- shape for consistency. Bumped twice on feedback: 0.09 -> 0.6 (the original rate
-- looked like it was doing nothing, but that was a SEPARATE display bug, see
-- applyHealth) -> 3.0, after 0.6 still read as insignificant at level 8.
-- AddGeneralHealth divides its amount across only the body parts below 100
-- health, so a raw call amount of `pct * intensity` (3.0 at level 10) lands
-- concentrated on whichever parts are actually hurt, not spread thin -- e.g. one
-- injured arm gets the full 3.0/minute, not a fraction of it.
local GENERAL_HEALTH = { labelKey = "UI_LFS_WellbeingStatGeneralHealth", labelFallback = "Saúde geral",
    min = 0, max = 100, pct = 3.0, dir = 1 }

-- Wound timers (BodyPart bleeding/deepWound/fracture/scratch/bite/burn/infection)
-- have no fixed universal range -- a fresh fracture and a fresh scratch do not
-- start at the same countdown value -- so these stay absolute-rate-based rather
-- than percent-of-range, same as before, just now also scaled by `intensity`.
-- Units/real vanilla healing speed were NOT independently measured (no equivalent
-- "how fast does a fresh fracture naturally count down" data exists), and the
-- first-pass values were confirmed too slow to notice in a live snapshot test (a
-- laceration + a bite moved a combined 0.01 in one minute) -- bumped ~10x across
-- the board, keeping the same relative ordering (bite slowest/most serious,
-- scratch fastest/least serious, woundInfection deliberately still tiny -- see its
-- own note).
--
-- `bite` was MISSING from the original pass entirely (a real gap, not a design
-- choice -- getBiteTime()/setBiteTime() is its own field on BodyPart, separate
-- from scratchTime, confirmed via decompile). A bite in this claim never got
-- healed OR counted in totalWoundTime, which is exactly the symptom first
-- reported: a character with an active bite showed no visible effect from this
-- category at all. Same as ZOMBIE_INFECTION/ZOMBIE_FEVER above, this only heals
-- the physical wound-mark countdown, never touches IsInfected/SetInfected: it
-- cannot cure a bite, only close the mark faster.
local WOUND_RATES = {
    bleeding        = 0.5,  -- BodyPart bleedingTime countdown
    deepWound       = 0.3,  -- BodyPart deepWoundTime countdown
    fracture        = 0.2,  -- BodyPart fractureTime countdown -- most serious of the non-bite timers
    scratch         = 0.8,  -- BodyPart scratchTime countdown -- minor, heals fastest
    bite            = 0.15, -- BodyPart biteTime countdown -- slowest of all; most serious wound type
    burn            = 0.5,  -- BodyPart burnTime countdown
    -- Deliberately NOT bumped with the rest: this is the "cannot cure" boundary
    -- for a wound that has already turned septic, same spirit as
    -- ZOMBIE_INFECTION/ZOMBIE_FEVER staying the weakest category. Left as-is
    -- unless feedback says otherwise.
    woundInfection  = 0.01, -- BodyPart woundInfectionLevel -- deliberately tiny, never forced to the "cured" -1 value
}

-- Per-category "already logged" flags -- a category that throws warns once and
-- keeps being retried every game-minute afterwards (recovers on its own if the
-- failure was transient), instead of the old version's single pcall that
-- permanently disabled the ENTIRE feature, silently, for the rest of the
-- session on any single error in any one of these stats.
local warnedCategory = {}

local function insideOwnTerritory(player)
    local factionName = FF.getFactionOfPlayer(player:getUsername())
    return factionName ~= nil
        and Claims.factionAt(math.floor(player:getX()), math.floor(player:getY())) == factionName
end

local function runCategory(key, fn)
    local ok, err = pcall(fn)
    if not ok and not warnedCategory[key] then
        warnedCategory[key] = true
        FF.warn("territory wellbeing: '" .. key .. "' category failed: " .. tostring(err)
            .. " (will keep retrying every game-minute; this message will not repeat)")
    end
end

-- Adds (after-before) to the running total for `key` inside an active
-- accumulation capture (FF.wellbeingAccumulation, started by the Debug tab's
-- "Capturar snapshot" button -- see territoryEffectTick). Creates the entry,
-- remembering the value it started at, the first time this key is touched during
-- the current capture window. A no-op when `accum` is nil (not currently
-- capturing), same guard style as `snapshot` throughout this file.
-- accum.order records each key's first-seen position: accum.entries itself is a
-- dict (needs O(1) lookup-by-key every tick to keep accumulating into the same
-- row), and Lua's pairs() over a dict has no defined/stable order -- without this,
-- the Debug tab's accumulated list would reshuffle on every rebuild.
local function recordAccum(accum, key, label, max, before, after)
    if not accum then return end
    local e = accum.entries[key]
    if not e then
        e = { label = label, startValue = before, sum = 0, max = max }
        accum.entries[key] = e
        accum.order[#accum.order + 1] = key
    end
    e.sum = e.sum + (after - before)
end

-- Applies every stat in `list` (see STATS above) toward its buffed direction by a
-- fixed PERCENT OF ITS OWN REAL RANGE per game-minute, scaled by `intensity`
-- (0..1: Bem-estar level / 10, times the sandbox power dial). `snapshot`, when
-- not nil, records a before/after entry per stat for the Debug tab's "last tick"
-- view; `accum`, when not nil, adds this tick's contribution to the running
-- 1-hour capture instead -- see LFS_Panel.lua:populateDebug for both.
local function applyCategory(stats, list, intensity, snapshot, accum)
    for _, def in ipairs(list) do
        local needsRead = snapshot or accum
        local before = needsRead and stats:get(def.stat) or nil
        local delta = (def.pct / 100) * (def.max - def.min) * intensity
        if def.dir > 0 then stats:add(def.stat, delta) else stats:remove(def.stat, delta) end
        if needsRead then
            local after = stats:get(def.stat)
            local label = FF.text(def.labelKey, def.labelFallback)
            if snapshot then
                snapshot.entries[#snapshot.entries + 1] = { label = label, before = before, after = after, max = def.max }
            end
            recordAccum(accum, def.key, label, def.max, before, after)
        end
    end
end

-- Average health across every body part, 0..100. NOT the same number as
-- body:getOverallBodyHealth() -- see applyHealth below for why that getter is the
-- wrong thing to read here.
local function averageBodyPartHealth(body)
    local parts = body:getBodyParts()
    if not parts or parts:size() == 0 then return 100 end
    local total = 0
    for i = 0, parts:size() - 1 do
        local bp = parts:get(i)
        total = total + (bp and bp:getHealth() or 100)
    end
    return total / parts:size()
end

-- AddGeneralHealth does NOT touch the value getOverallBodyHealth() returns --
-- decompiled: it distributes the given amount across every body part currently
-- below 100 health via BodyPart:AddHealth(amount/count), and getOverallBodyHealth
-- is a plain getter for a SEPARATE `overallBodyHealth` field that only some other,
-- unrelated vanilla process recalculates. Reading getOverallBodyHealth() right
-- before/after this call is why the debug snapshot always showed "68.06 -> 68.06
-- (+0.0%)" even though AddGeneralHealth was genuinely running -- averageBodyPartHealth
-- above reads the value this call ACTUALLY changes. Also drop the old
-- `before > 0 and before < 100` gate: AddGeneralHealth already no-ops internally
-- when every body part is already at 100 (same decompile), so the extra guard here
-- was redundant and, worse, was gating on the wrong (disconnected) value.
local function applyHealth(player, stats, intensity, snapshot, accum)
    local body = player:getBodyDamage()
    if body then
        local needsRead = snapshot or accum
        local before = needsRead and averageBodyPartHealth(body) or nil
        local delta = (GENERAL_HEALTH.pct / 100) * (GENERAL_HEALTH.max - GENERAL_HEALTH.min) * intensity
        body:AddGeneralHealth(delta)
        if needsRead then
            local after = averageBodyPartHealth(body)
            local label = FF.text(GENERAL_HEALTH.labelKey, GENERAL_HEALTH.labelFallback)
            if snapshot then
                snapshot.entries[#snapshot.entries + 1] = { label = label, before = before, after = after, max = GENERAL_HEALTH.max }
            end
            recordAccum(accum, "generalHealth", label, GENERAL_HEALTH.max, before, after)
        end
    end
    applyCategory(stats, STATS.health, intensity, snapshot, accum)
    if body and body:IsInfected() then
        applyCategory(stats, STATS.infection, intensity, snapshot, accum)
    end
end

-- Sum of every active wound-timer's remaining time, across every body part.
-- Only used to give the debug snapshot ONE legible before/after row instead of
-- up to 8 body parts x 6 timers of noise.
local function totalWoundTime(body)
    local parts = body:getBodyParts()
    if not parts then return 0 end
    local total = 0
    for i = 0, parts:size() - 1 do
        local bp = parts:get(i)
        if bp then
            total = total + math.max(0, bp:getBleedingTime()) + math.max(0, bp:getDeepWoundTime())
                + math.max(0, bp:getFractureTime()) + math.max(0, bp:getScratchTime())
                + math.max(0, bp:getBiteTime()) + math.max(0, bp:getBurnTime())
        end
    end
    return total
end

-- Gradual per-body-part wound healing. getBodyParts() is a real Java list
-- (confirmed via vanilla's own LastStand/AReallyCDDAy.lua using the same
-- :size()/:get(i) pattern), so every part -- head, torso, both arms, both
-- hands, both legs, both feet -- gets checked, not just a hardcoded subset.
-- Each timer is only touched while active (> 0), and only ever moved toward
-- 0 by a small amount, never set directly. Deep wounds get the same explicit
-- setDeepWounded(false) vanilla's own admin cheat pairs with clearing the
-- timer, since other vanilla code treats that boolean as a separate flag from
-- the countdown itself; fractures don't need an equivalent call, since
-- vanilla code elsewhere already treats getFractureTime() == 0 alone as
-- "not fractured". setScratched()'s second argument isn't clearly documented
-- anywhere reachable from Lua, so scratchTime is counted down without also
-- touching that flag, to avoid guessing at an under-documented call -- same
-- reasoning for biteTime, which has no equivalent boolean flag exposed at all.
local function applyWounds(player, intensity, snapshot, accum)
    local body = player:getBodyDamage()
    if not body then return end
    local parts = body:getBodyParts()
    if not parts then return end
    local needsRead = snapshot or accum
    local before = needsRead and totalWoundTime(body) or nil
    local r = WOUND_RATES
    for i = 0, parts:size() - 1 do
        local bp = parts:get(i)
        if bp then
            if bp:getBleedingTime() > 0 then
                bp:setBleedingTime(math.max(0, bp:getBleedingTime() - r.bleeding * intensity))
            end
            if bp:getDeepWoundTime() > 0 then
                local newTime = math.max(0, bp:getDeepWoundTime() - r.deepWound * intensity)
                bp:setDeepWoundTime(newTime)
                if newTime <= 0 then bp:setDeepWounded(false) end
            end
            if bp:getFractureTime() > 0 then
                bp:setFractureTime(math.max(0, bp:getFractureTime() - r.fracture * intensity))
            end
            if bp:getScratchTime() > 0 then
                bp:setScratchTime(math.max(0, bp:getScratchTime() - r.scratch * intensity))
            end
            if bp:getBiteTime() > 0 then
                bp:setBiteTime(math.max(0, bp:getBiteTime() - r.bite * intensity))
            end
            if bp:getBurnTime() > 0 then
                bp:setBurnTime(math.max(0, bp:getBurnTime() - r.burn * intensity))
            end
            if bp:isInfectedWound() then
                local lvl = bp:getWoundInfectionLevel()
                if lvl and lvl > 0 then
                    bp:setWoundInfectionLevel(math.max(0, lvl - r.woundInfection * intensity))
                end
            end
        end
    end
    if needsRead then
        local after = totalWoundTime(body)
        local label = FF.text("UI_LFS_WellbeingStatWoundHealing", "Cicatrização (soma dos timers)")
        if snapshot then
            -- "0.00 -> 0.00" reads as "this isn't doing anything" -- it usually just
            -- means the character has no active wound timer at all right now (nothing
            -- for this category to heal), not that healing is broken. Say so explicitly
            -- instead of leaving that ambiguous, per the exact confusion reported.
            local note = (before == 0 and after == 0)
                and FF.text("UI_LFS_WellbeingStatNoWounds", "sem feridas ativas") or nil
            snapshot.entries[#snapshot.entries + 1] = { label = label, before = before, after = after, note = note }
        end
        recordAccum(accum, "woundHealing", label, nil, before, after)
    end
end

local function applyMood(stats, intensity, snapshot, accum)
    applyCategory(stats, STATS.mood, intensity, snapshot, accum)
end

local function applyFatigue(stats, intensity, snapshot, accum)
    applyCategory(stats, STATS.fatigue, intensity, snapshot, accum)
end

local function applyNeeds(stats, intensity, snapshot, accum)
    applyCategory(stats, STATS.needs, intensity, snapshot, accum)
end

-- ---------------------------------------------------------------------------
-- Debug capture state, for LFS_Panel.lua's Debug tab. Both only ever populated
-- while DebugToolsEnabled is on -- zero cost on a normal live server.
--
-- FF.lastWellbeingSnapshot: what every touched stat was before/after the last
-- time this tick actually applied (inside territory, level > 0) -- one tick's
-- worth, refreshed every game-minute. Good for "is this doing SOMETHING right
-- now"; a small-but-real move here can round away to "0.0%" for a slow stat.
--
-- FF.wellbeingAccumulation: an opt-in, explicitly-started capture that instead
-- SUMS every tick's contribution per stat over a full game hour (60 firings of
-- this tick), so a slow-moving stat's real size shows clearly instead of
-- looking like nothing happened. Structure while present:
--   { active, ticksTotal, ticksRemaining, activeTicks, finishedAt,
--     entries = { [statKey] = { label, startValue, sum, max } },
--     order = { statKey, ... } }   -- first-seen order; entries itself is a dict
-- `active` flips to false once ticksRemaining hits 0; the accumulated entries
-- stay in place after that so the Debug tab can show the finished result until
-- a new capture is started. Started with a fresh table entirely (not toggled)
-- by LFS_Panel.lua's onDebugCaptureAccumulation, so re-clicking mid-capture
-- restarts cleanly with no leftover totals from the previous window.
-- ---------------------------------------------------------------------------
FF.lastWellbeingSnapshot = nil
FF.wellbeingAccumulation = nil

local function territoryEffectTick()
    -- The accumulation clock always advances on this event while capturing,
    -- independent of whether the buff itself applies this specific minute --
    -- leaving territory or the level dropping mid-capture just means less
    -- accumulates, it does not pause the 1-hour window. Read BEFORE decrementing
    -- so this tick's own contribution (below, if any) still counts toward the
    -- window that may be about to close.
    local accumState = FF.wellbeingAccumulation
    local capturingThisTick = accumState ~= nil and accumState.active
    if capturingThisTick then
        accumState.ticksRemaining = accumState.ticksRemaining - 1
        if accumState.ticksRemaining <= 0 then
            accumState.active = false
            accumState.finishedAt = getTimestamp()
        end
    end

    local opts = FF.getOptions()
    local globalPower = math.max(0, tonumber(opts.territoryWellbeingPower) or 1)
    if globalPower <= 0 then return end

    local player = getPlayer()
    if not player or player:isDead() then return end

    local username = player:getUsername()
    local factionName, faction = FF.getFactionOfPlayer(username)
    if not faction then return end
    -- Level 0: the upgrade simply does not apply yet, by design.
    local level = FF.upgradeLevel(faction, "wellbeing")
    if level <= 0 then return end

    local ok, inside = pcall(insideOwnTerritory, player)
    if not ok or not inside then
        if FF.debugEnabled() then
            FF.log("territory wellbeing: minute skipped (ok=" .. tostring(ok)
                .. ", inside=" .. tostring(inside) .. ")")
        end
        return
    end

    local stats = player:getStats()
    if not stats then return end

    -- 0..1 at level 10 with the default power=1 sandbox value; scales down
    -- linearly with fewer levels, up or down further with the sandbox dial.
    local intensity = (level / 10) * globalPower

    local snapshot = opts.debugToolsEnabled
        and { at = getTimestamp(), level = level, intensity = intensity, entries = {} }
        or nil
    local accum = (opts.debugToolsEnabled and capturingThisTick) and accumState or nil
    if accum then accum.activeTicks = (accum.activeTicks or 0) + 1 end

    if opts.territoryMoodBuffEnabled then
        runCategory("mood", function() applyMood(stats, intensity, snapshot, accum) end)
    end
    if opts.territoryHealthBuffEnabled then
        runCategory("health", function() applyHealth(player, stats, intensity, snapshot, accum) end)
        runCategory("wounds", function() applyWounds(player, intensity, snapshot, accum) end)
    end
    if opts.territoryFatigueBuffEnabled then
        runCategory("fatigue", function() applyFatigue(stats, intensity, snapshot, accum) end)
    end
    if opts.territoryNeedsBuffEnabled then
        runCategory("needs", function() applyNeeds(stats, intensity, snapshot, accum) end)
    end

    if snapshot then FF.lastWellbeingSnapshot = snapshot end
end

-- Fires on Events.EveryOneMinute -- a GAME-time clock event, not a real-time one.
-- At normal 1x speed one game-minute takes one real second, so this reads as
-- "about once a second" exactly like the original request; the important part is
-- that it fires proportionally MORE OFTEN in real time whenever the player runs
-- time forward, automatically keeping pace with vanilla's own moodle/stat changes
-- (boredom while idle, panic near zombies, etc), which are themselves driven by
-- the same game clock. An earlier version tried to approximate this by throttling
-- on real time (getTimestamp()) and multiplying by getGameTime():getMultiplier()
-- each firing -- that reading turned out to be noisy/unstable per-frame (observed
-- swinging between ~0.2 and ~10 within the same accelerated session in testing),
-- so it under- or over-corrected instead of tracking game speed reliably. Driving
-- straight off a game-time event sidesteps that instability entirely.
if FF._territoryEffectHook then Events.EveryOneMinute.Remove(FF._territoryEffectHook) end
FF._territoryEffectHook = territoryEffectTick
Events.EveryOneMinute.Add(territoryEffectTick)
