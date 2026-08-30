SP_AlternativeCombat = {}
local SPAC = SP_AlternativeCombat

-- Turning is client-authoritative, so the mod only ever touches LOCAL players.
-- On a dedicated server no player is local, which makes the whole runtime a
-- no-op there; on clients (and listen-server hosts) it runs only for that
-- machine's own character(s). This is what keeps it multiplayer-safe.
local function isLocalPlayerObj(p)
    return p ~= nil and p:isLocalPlayer()
end

-- ===================================================================
-- Configuration (backed by the sandbox options; see sandbox-options.txt).
-- Values here are only the fallback defaults used before the sandbox loads.
--
-- Two independent switches give a 2x2 of behaviours:
--   nimbleSystem = false -> "Original": instant-pivot-while-aiming (PivotSpeed)
--   nimbleSystem = true  -> "Nimble":   turn speed scales with the Nimble skill
--   traitVersion = false -> "Global":   applies to everyone
--   traitVersion = true  -> "Trait":    applies only to trait holders, others vanilla
-- ===================================================================
local enabled = true
local traitVersion = false
local nimbleSystem = false
local pivotPreset = 5        -- PivotSpeed enum, while aiming (1 Vanilla .. 5 Instant)
local movementPreset = 5     -- MovementTurnSpeed enum, walking (not aiming/running)
-- NOTE: there is intentionally no jog/sprint preset. getTurnDelta() reads the
-- protected turnDeltaRunning/turnDeltaSprinting fields while running/sprinting,
-- and those cannot be set from Lua (see setRunSprintTurnDelta removal below), so
-- jog/sprint turning always stays vanilla.

-- Dynamic turn-speed modifiers (master switch + per-modifier toggles, all OFF by
-- default). When the master is on, each enabled modifier multiplies the computed
-- walking/aiming turn speed by a situational factor every tick: heavier load,
-- lower-body injury, fatigue and intoxication slow the turn; panic speeds it up;
-- sneaking turns more deliberately. With the master off this whole system is inert
-- and turning behaves exactly as before.
local dynamicEnabled = false
local dynEncumbrance = false
local dynInjury = false
local dynFatigue = false
local dynDrunk = false
local dynPanic = false
local dynSneak = false

-- Nimble-system tuning (ported from the NATS mod).
local onYourToesMult = 1.3
local podShofeMult = 0.4
local defaultMult = 1.0
local onYourToesInGameMult = 0.15
local podShofeInGameMult = 0.2
local nimbleLvlMult = 1.0

-- Turn delta per speed preset (shared by the aiming-pivot and movement-turn
-- options). Higher = faster turning. The top of the scale (2.5) already feels
-- near-instant, so the scale is filled with smaller steps below it rather than
-- larger numbers above. Values are deliberately capped at 2.5: above ~3 the body
-- snaps a full 45 degrees in one frame, which (while aiming) makes it visibly
-- judder when the cursor sits on a facing boundary - and it does not feel any
-- faster than 2.5 anyway. Staying <= 2.5 keeps every preset smooth.
local PIVOT_SPEED_PRESETS = { 1.0, 1.4, 1.8, 2.2, 2.5 }
-- Vanilla turnDeltaNormal, used whenever the buff should not apply.
local DEFAULT_TURN_DELTA = 1.0
-- Bounds for the dynamic modifiers: never lock turning completely (MIN), and keep
-- the top at the smooth cap so a panic boost can't push past it into judder (MAX).
local MIN_TURN_DELTA = 0.3
local MAX_SMOOTH_TURN_DELTA = PIVOT_SPEED_PRESETS[5]  -- 2.5

-- ===================================================================
-- Trait resolution (B42). Traits are script-defined (see
-- media/scripts/characters/PivotMod_traits.txt) and resolved to CharacterTrait
-- objects via their resource location "pivotmod:<name>".
-- ===================================================================
local traitCache = {}
local function getTrait(path)
    if traitCache[path] ~= nil then
        return traitCache[path] or nil
    end
    local t = nil
    -- Preferred: the trait objects registered in media/registries.lua.
    if PivotMod ~= nil and PivotMod.CharacterTrait ~= nil then
        t = PivotMod.CharacterTrait[string.upper(path)]
    end
    -- Fallback: resolve by resource location (namespace + path are lowercased).
    if t == nil then
        pcall(function() t = CharacterTrait.get(ResourceLocation.of("pivotmod:" .. path)) end)
    end
    traitCache[path] = t or false
    return t
end

local function playerHasTrait(p, path)
    local t = getTrait(path)
    return t ~= nil and p:hasTrait(t)
end

-- ===================================================================
-- Sandbox
-- ===================================================================
local function loadSandboxOptions()
    local sv = SandboxVars.PivotMod
    if sv == nil then return end
    if sv.Enabled ~= nil then enabled = sv.Enabled end
    if sv.TraitVersion ~= nil then traitVersion = sv.TraitVersion end
    if sv.NimbleSystem ~= nil then nimbleSystem = sv.NimbleSystem end
    if sv.PivotSpeed ~= nil and PIVOT_SPEED_PRESETS[sv.PivotSpeed] ~= nil then
        pivotPreset = sv.PivotSpeed
    end
    if sv.MovementTurnSpeed ~= nil and PIVOT_SPEED_PRESETS[sv.MovementTurnSpeed] ~= nil then
        movementPreset = sv.MovementTurnSpeed
    end
    if sv.OnYourToesMultiplier ~= nil then onYourToesMult = sv.OnYourToesMultiplier end
    if sv.PodShofeMultiplier ~= nil then podShofeMult = sv.PodShofeMultiplier end
    if sv.DefaultMultiplier ~= nil then defaultMult = sv.DefaultMultiplier end
    if sv.OnYourToesInGameMultiplier ~= nil then onYourToesInGameMult = sv.OnYourToesInGameMultiplier end
    if sv.PodShofeInGameMultiplier ~= nil then podShofeInGameMult = sv.PodShofeInGameMultiplier end
    if sv.NimbleLvlMultiplier ~= nil then nimbleLvlMult = sv.NimbleLvlMultiplier end
    if sv.DynamicModifiers ~= nil then dynamicEnabled = sv.DynamicModifiers end
    if sv.DynEncumbrance ~= nil then dynEncumbrance = sv.DynEncumbrance end
    if sv.DynInjury ~= nil then dynInjury = sv.DynInjury end
    if sv.DynFatigue ~= nil then dynFatigue = sv.DynFatigue end
    if sv.DynDrunkenness ~= nil then dynDrunk = sv.DynDrunkenness end
    if sv.DynPanic ~= nil then dynPanic = sv.DynPanic end
    if sv.DynSneak ~= nil then dynSneak = sv.DynSneak end
end

-- setTurnDelta() drives ONLY the stationary/walking/aiming turn (turnDeltaNormal,
-- a public method). getTurnDelta() returns turnDeltaSprinting while sprinting and
-- turnDeltaRunning while running; both are PROTECTED fields with no public setter.
--
-- A previous version tried `p.turnDeltaRunning = x` / `p.turnDeltaSprinting = x`.
-- That can never work: PZ's Kahlua exposer registers a __newindex metamethod only
-- on static class tables, never on Java *instances*, so any `instance.field = ...`
-- write throws "attempted index of non-table" inside KahluaThread.tableSet BEFORE
-- it reaches any field-setting code. The pcall caught the Lua error but Kahlua had
-- already logged the RuntimeException, producing the on-spawn error spam - while
-- never actually changing the jog/sprint turn rate. The feature was therefore
-- impossible from Lua and has been removed; jog/sprint turning stays vanilla.

-- ===================================================================
-- Dynamic turn-speed modifiers. Each returns a multiplier applied to the base turn
-- speed; 1.0 = no change, <1 slower, >1 faster. Every engine read is pcall-guarded
-- and falls back to neutral, so a missing API can never throw or spam errors.
-- ===================================================================

-- Lower-body parts whose injuries make turning harder.
local INJURY_PARTS = { "UpperLeg_L", "UpperLeg_R", "LowerLeg_L", "LowerLeg_R", "Foot_L", "Foot_R", "Groin" }

-- A CharacterStat value normalised to 0..1 by its own maximum (B42 stat API).
local function statNorm(p, stat)
    if stat == nil then return 0.0 end
    local n = 0.0
    pcall(function()
        local v = p:getStats():get(stat)
        local mx = stat:getMaximumValue()
        if mx ~= nil and mx > 0 then n = v / mx else n = v end
    end)
    if n < 0.0 then return 0.0 elseif n > 1.0 then return 1.0 end
    return n
end

local function encumbranceMult(p)
    local m = 1.0
    pcall(function()
        local maxw = p:getMaxWeight()
        if maxw ~= nil and maxw > 0 then
            local r = p:getInventoryWeight() / maxw   -- 0 empty .. >1 overloaded
            m = 1.0 - 0.45 * r                        -- full load ~0.55, then floored
        end
    end)
    return m
end

local function injuryMult(p)
    if BodyPartType == nil then return 1.0 end
    local bd = p:getBodyDamage()
    if bd == nil then return 1.0 end
    local worst, fractured = 0.0, false   -- worst: 0 healthy .. 1 destroyed
    for i = 1, #INJURY_PARTS do
        local bpt = BodyPartType[INJURY_PARTS[i]]
        if bpt ~= nil then
            pcall(function()
                local part = bd:getBodyPart(bpt)
                if part ~= nil then
                    local sev = (100.0 - part:getHealth()) / 100.0
                    if sev > worst then worst = sev end
                    if part:getFractureTime() > 0 then fractured = true end
                end
            end)
        end
    end
    local m = 1.0 - 0.5 * worst       -- worst injury dominates
    if fractured then m = m * 0.6 end -- a broken leg/foot hurts a lot more
    return m
end

local function fatigueMult(p)
    if CharacterStat == nil then return 1.0 end
    local fatigue = statNorm(p, CharacterStat.FATIGUE)     -- 0 rested .. 1 exhausted
    local endurance = statNorm(p, CharacterStat.ENDURANCE) -- 0 spent  .. 1 full
    return 1.0 - 0.4 * fatigue - 0.3 * (1.0 - endurance)
end

local function drunkMult(p)
    if CharacterStat == nil then return 1.0 end
    return 1.0 - 0.5 * statNorm(p, CharacterStat.INTOXICATION)
end

local function panicMult(p)
    if CharacterStat == nil then return 1.0 end
    return 1.0 + 0.5 * statNorm(p, CharacterStat.PANIC)    -- panicked = quicker, up to +50%
end

local function sneakMult(p)
    local sneaking = false
    pcall(function() sneaking = p:isSneaking() end)
    if sneaking then return 0.7 end
    return 1.0
end

-- Product of every enabled modifier (1.0 when the master switch is off).
local function dynamicMultiplier(p)
    if not dynamicEnabled then return 1.0 end
    local m = 1.0
    if dynEncumbrance then m = m * encumbranceMult(p) end
    if dynInjury      then m = m * injuryMult(p) end
    if dynFatigue     then m = m * fatigueMult(p) end
    if dynDrunk       then m = m * drunkMult(p) end
    if dynPanic       then m = m * panicMult(p) end
    if dynSneak       then m = m * sneakMult(p) end
    return m
end

-- Apply the dynamic multiplier to a base turn delta and keep it in playable bounds.
local function withDynamic(p, base)
    local v = base * dynamicMultiplier(p)
    if v < MIN_TURN_DELTA then return MIN_TURN_DELTA end
    if v > MAX_SMOOTH_TURN_DELTA then return MAX_SMOOTH_TURN_DELTA end
    return v
end

-- ===================================================================
-- Original system (per tick): separate turn speeds for aiming vs WASD movement.
-- ===================================================================
local function updateOriginalPivot(p)
    local apply
    if traitVersion then
        apply = playerHasTrait(p, "OnYourToes")
    else
        apply = true
    end
    if not apply then
        p:setTurnDelta(DEFAULT_TURN_DELTA)
        return
    end
    -- turnDeltaNormal covers stationary/walking (movement) and aiming. Jogging and
    -- sprinting use turnDeltaRunning/turnDeltaSprinting, which Lua cannot set, so
    -- they are left at vanilla (see the note above setRunSprintTurnDelta's removal).
    local base
    if p:isAiming() then
        base = PIVOT_SPEED_PRESETS[pivotPreset] or DEFAULT_TURN_DELTA
    else
        base = PIVOT_SPEED_PRESETS[movementPreset] or DEFAULT_TURN_DELTA
    end
    p:setTurnDelta(withDynamic(p, base))
end

-- ===================================================================
-- Nimble system (ported from NATS): turn speed scales with the Nimble skill,
-- modified by the traits. Applied once on spawn and on each Nimble level-up.
-- ===================================================================
local function nimbleAffected(p)
    if not traitVersion then return true end
    return playerHasTrait(p, "OnYourToes") or playerHasTrait(p, "PodShofe")
end

local function computeNimbleAffect(p)
    local md = p:getModData()
    if md.NimbleAffect ~= nil then return end  -- one-time init (matches NATS)
    local nimbleLvl = p:getPerkLevel(Perks.Nimble)
    if playerHasTrait(p, "OnYourToes") then
        md.NimbleAffect = onYourToesMult
        md.percentPerLvl5 = 0.05; md.percentPerLvl7 = 0.08; md.percentPerLvl9 = 0.12; md.percentPerLvl10 = 0.2
    elseif playerHasTrait(p, "PodShofe") then
        md.NimbleAffect = podShofeMult
        md.percentPerLvl5 = 0.02; md.percentPerLvl7 = 0.04; md.percentPerLvl9 = 0.06; md.percentPerLvl10 = 0.1
    else
        md.NimbleAffect = defaultMult
        md.percentPerLvl5 = 0.03; md.percentPerLvl7 = 0.06; md.percentPerLvl9 = 0.09; md.percentPerLvl10 = 0.15
    end
    local p5, p7, p9, p10 = md.percentPerLvl5, md.percentPerLvl7, md.percentPerLvl9, md.percentPerLvl10
    if nimbleLvl > 0 then
        if nimbleLvl <= 5 then
            md.NimbleAffect = md.NimbleAffect + p5 * nimbleLvl
        elseif nimbleLvl <= 7 then
            md.NimbleAffect = md.NimbleAffect + p5 * 5 + p7 * (nimbleLvl - 5)
        elseif nimbleLvl <= 9 then
            md.NimbleAffect = md.NimbleAffect + p5 * 5 + p7 * 2 + p9 * (nimbleLvl - 7)
        else
            md.NimbleAffect = md.NimbleAffect + p5 * 5 + p7 * 2 + p9 * 2 + p10
        end
    end
end

local function nimbleBaseValue(p)
    if not nimbleAffected(p) then return DEFAULT_TURN_DELTA end
    return (p:getModData().NimbleAffect or DEFAULT_TURN_DELTA) * nimbleLvlMult
end

local function applyNimble(p)
    computeNimbleAffect(p)
    local v = nimbleBaseValue(p)
    -- Dynamic modifiers (when enabled) scale the Nimble turn speed too. Only a floor
    -- is enforced - the Nimble base is intentionally uncapped, so we must not
    -- retroactively clamp the high-skill turn speeds that worked before.
    if dynamicEnabled then
        v = v * dynamicMultiplier(p)
        if v < MIN_TURN_DELTA then v = MIN_TURN_DELTA end
    end
    p:setTurnDelta(v)  -- drives walking/aiming only; jog/sprint stay vanilla (no setter)
end

-- While running/sprinting the engine uses turnDeltaRunning/turnDeltaSprinting, which
-- setTurnDelta() doesn't drive, so a Nimble buff applied mid-run isn't visible until
-- the player stops. A level-up earned mid-run is therefore deferred until they stop.
local runDefer = { pending = false }

local function nimbleOnLevelPerk(p, perk, perklvl)
    if perk ~= Perks.Nimble then return end
    computeNimbleAffect(p)
    local md = p:getModData()

    if p:IsRunning() or p:isSprinting() then
        if not runDefer.pending then
            runDefer.pending = true
            runDefer.player = p
            runDefer.perk = perk
            runDefer.perklvl = perklvl
            Events.OnTick.Add(SPAC.onRunDefer)
        end
        return
    end

    if perklvl == 6 then
        if not (playerHasTrait(p, "OnYourToes") or playerHasTrait(p, "PodShofe")) then
            local t = getTrait("OnYourToes")
            if t ~= nil then
                p:getCharacterTraits():add(t)
                p:Say(getText("IGUI_Add_OnYourToes"))
            end
            md.NimbleAffect = md.NimbleAffect + onYourToesInGameMult
        elseif playerHasTrait(p, "PodShofe") then
            local t = getTrait("PodShofe")
            if t ~= nil then
                p:getCharacterTraits():remove(t)
                p:Say(getText("IGUI_Remove_PodShofe"))
            end
            md.NimbleAffect = md.NimbleAffect + podShofeInGameMult
        end
    end

    if perklvl > 0 then
        if perklvl <= 5 then
            md.NimbleAffect = md.NimbleAffect + (md.percentPerLvl5 or 0)
        elseif perklvl <= 7 then
            md.NimbleAffect = md.NimbleAffect + (md.percentPerLvl7 or 0)
        elseif perklvl <= 9 then
            md.NimbleAffect = md.NimbleAffect + (md.percentPerLvl9 or 0)
        else
            md.NimbleAffect = md.NimbleAffect + (md.percentPerLvl10 or 0)
        end
    end

    applyNimble(p)
end

SPAC.onRunDefer = function()
    local p = runDefer.player
    if p == nil or not (p:IsRunning() or p:isSprinting()) then
        Events.OnTick.Remove(SPAC.onRunDefer)
        runDefer.pending = false
        local perk, perklvl = runDefer.perk, runDefer.perklvl
        runDefer.player, runDefer.perk, runDefer.perklvl = nil, nil, nil
        if p ~= nil then nimbleOnLevelPerk(p, perk, perklvl) end
    end
end

-- ===================================================================
-- Events
-- ===================================================================
SPAC.OnTick = function()
    if not enabled then return end
    -- The Nimble system normally sets the turn delta on spawn / level-up and lets it
    -- persist, so it needs no per-tick work. The exception is dynamic modifiers: they
    -- track live stats, so when enabled the Nimble value is re-applied every tick too.
    if nimbleSystem and not dynamicEnabled then return end
    -- Iterate the local split-screen slots; remote players are never returned
    -- here and the isLocalPlayerObj guard makes this a no-op on a server.
    for i = 0, 3 do
        local p = getSpecificPlayer(i)
        if isLocalPlayerObj(p) then
            if nimbleSystem then
                applyNimble(p)
            else
                updateOriginalPivot(p)
            end
        end
    end
end

SPAC.OnLevelPerk = function(p, perk, perklvl)
    if not enabled or not nimbleSystem or not isLocalPlayerObj(p) then return end
    nimbleOnLevelPerk(p, perk, perklvl)
end

SPAC.OnCreatePlayer = function(playerIndex, p)
    loadSandboxOptions()
    if enabled and nimbleSystem and isLocalPlayerObj(p) then
        applyNimble(p)
    end
    -- Re-add cleanly so respawns don't stack duplicate handlers.
    Events.OnTick.Remove(SPAC.OnTick)
    Events.OnTick.Add(SPAC.OnTick)
end

SPAC.OnGameStart = function()
    loadSandboxOptions()
    Events.OnTick.Remove(SPAC.OnTick)
    Events.OnTick.Add(SPAC.OnTick)
end

Events.OnGameStart.Add(SPAC.OnGameStart)
Events.OnCreatePlayer.Add(SPAC.OnCreatePlayer)
Events.LevelPerk.Add(SPAC.OnLevelPerk)
