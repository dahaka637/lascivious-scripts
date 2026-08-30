SP_AlternativeCombat = {}
local SPAC = SP_AlternativeCombat

-- B41 build. Feature parity with the B42 variant, but using B41 APIs:
--   * traits via TraitFactory.addTrait (not B42 script-defined traits)
--   * player:HasTrait("name") string checks, getTraits():add/remove("name")
--   * .txt translations (not JSON)
-- Turning is client-authoritative, so the mod only ever touches LOCAL players:
-- no-op on a dedicated server, keeping it multiplayer-safe.
local function isLocalPlayerObj(p)
    return p ~= nil and p:isLocalPlayer()
end

-- ==== Configuration (backed by media/sandbox-options.txt) ====
local enabled = true
local traitVersion = false   -- false: applies globally; true: only trait holders
local nimbleSystem = false   -- false: fixed speeds; true: Nimble-scaled turning
local pivotPreset = 5        -- aiming           (1 Vanilla .. 5 Instant)
local movementPreset = 2     -- walking
-- No jog/sprint preset: getTurnDelta() reads the protected turnDeltaRunning/
-- turnDeltaSprinting fields while running/sprinting, and Lua cannot set them
-- (see setRunSprintTurnDelta removal below), so jog/sprint turning stays vanilla.

-- Dynamic turn-speed modifiers (master switch + per-modifier toggles, all OFF by
-- default). When the master is on, each enabled modifier multiplies the computed
-- walking/aiming turn speed by a situational factor every tick: heavier load,
-- lower-body injury, fatigue and drunkenness slow the turn; panic speeds it up;
-- sneaking turns more deliberately. With the master off the system is inert.
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

-- Turn delta per speed preset, used while AIMING (stationary). 2.5 is the original
-- mod's smooth "instant" value; the steps below it give gentler turns. Capped at 2.5
-- because above ~3 the body snaps a full 45 degrees in one frame, which judders
-- visibly while the cursor sits on a facing boundary.
local PIVOT_SPEED_PRESETS = { 1.0, 1.4, 1.8, 2.2, 2.5 }

-- Turn delta per speed preset while MOVING (walking, not aiming). B41 attenuates the
-- turn rate by movement speed: in IsoGameCharacter.postUpdate the engine computes
--   angleStepDelta = max(1 - moveDelta/2, 0) * turnDelta
-- so a walking character's turn is scaled down (and zeroed once moveDelta >= 2),
-- which makes the 2.5-capped aiming scale nearly imperceptible on foot. These larger
-- values counteract that attenuation so MovementTurnSpeed is actually felt while
-- walking. The aiming judder cap does not apply here - snapping the body toward the
-- movement-aligned facing while already moving looks fine. (Jogging/sprinting use the
-- protected turnDeltaRunning/turnDeltaSprinting fields, which Lua cannot set, so they
-- always stay vanilla regardless of this preset - see the note below.)
local MOVEMENT_TURN_PRESETS = { 1.0, 3.0, 6.0, 12.0, 30.0 }
local DEFAULT_TURN_DELTA = 1.0
-- Bounds for the dynamic modifiers: never lock turning completely (MIN), and keep the
-- AIMING top at the smooth cap so a panic boost can't push past it into judder (MAX).
local MIN_TURN_DELTA = 0.3
local MAX_SMOOTH_TURN_DELTA = PIVOT_SPEED_PRESETS[5]  -- 2.5

-- ==== Traits (B41 TraitFactory API), registered at boot ====
local function registerTraits()
    local oyt = TraitFactory.addTrait("OnYourToes", getText("UI_trait_OnYourToes"), 4, getText("UI_trait_OnYourToesdesc"), false)
    oyt:addXPBoost(Perks.Nimble, 1)
    local pod = TraitFactory.addTrait("PodShofe", getText("UI_trait_PodShofe"), -3, getText("UI_trait_PodShofedesc"), false)
    pod:addXPBoost(Perks.Nimble, -1)
    TraitFactory.setMutualExclusive("OnYourToes", "PodShofe")
    if BaseGameCharacterDetails ~= nil then
        BaseGameCharacterDetails.SetTraitDescription(oyt)
        BaseGameCharacterDetails.SetTraitDescription(pod)
    end
end

local function playerHasTrait(p, name)
    return p:HasTrait(name)
end

-- ==== Sandbox ====
local function loadSandboxOptions()
    local sv = SandboxVars.PivotMod
    if sv == nil then return end
    if sv.Enabled ~= nil then enabled = sv.Enabled end
    if sv.TraitVersion ~= nil then traitVersion = sv.TraitVersion end
    if sv.NimbleSystem ~= nil then nimbleSystem = sv.NimbleSystem end
    if sv.PivotSpeed ~= nil and PIVOT_SPEED_PRESETS[sv.PivotSpeed] ~= nil then pivotPreset = sv.PivotSpeed end
    if sv.MovementTurnSpeed ~= nil and MOVEMENT_TURN_PRESETS[sv.MovementTurnSpeed] ~= nil then movementPreset = sv.MovementTurnSpeed end
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

-- setTurnDelta() drives ONLY the walking/aiming turn (turnDeltaNormal, a public
-- method). getTurnDelta() returns the protected turnDeltaRunning/turnDeltaSprinting
-- fields while running/sprinting, and those have no setter.
--
-- A previous version tried `p.turnDeltaRunning = x`. That can never work: PZ's
-- Kahlua exposer adds a __newindex metamethod only to static class tables, never to
-- Java *instances*, so any `instance.field = ...` write throws "attempted index of
-- non-table" before reaching any field code. pcall swallowed the Lua error but
-- Kahlua still logged the RuntimeException every tick, and the jog/sprint turn rate
-- never actually changed. The feature was impossible from Lua and has been removed;
-- jog/sprint turning stays vanilla.

-- ==== Dynamic turn-speed modifiers ====
-- Each returns a multiplier applied to the base turn speed; 1.0 = no change, <1
-- slower, >1 faster. Every engine read is pcall-guarded and falls back to neutral,
-- so a missing API can never throw or spam errors.

-- Lower-body parts whose injuries make turning harder.
local INJURY_PARTS = { "UpperLeg_L", "UpperLeg_R", "LowerLeg_L", "LowerLeg_R", "Foot_L", "Foot_R", "Groin" }

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
    local fatigue, endurance = 0.0, 1.0
    pcall(function()
        local st = p:getStats()
        fatigue = st:getFatigue()      -- 0 rested .. 1 exhausted
        endurance = st:getEndurance()  -- 0 spent  .. 1 full
    end)
    if fatigue < 0 then fatigue = 0 elseif fatigue > 1 then fatigue = 1 end
    if endurance < 0 then endurance = 0 elseif endurance > 1 then endurance = 1 end
    return 1.0 - 0.4 * fatigue - 0.3 * (1.0 - endurance)
end

local function drunkMult(p)
    local d = 0.0
    pcall(function() d = p:getStats():getDrunkenness() / 100.0 end)
    if d < 0 then d = 0 elseif d > 1 then d = 1 end
    return 1.0 - 0.5 * d
end

local function panicMult(p)
    local pa = 0.0
    pcall(function() pa = p:getStats():getPanic() / 100.0 end)
    if pa < 0 then pa = 0 elseif pa > 1 then pa = 1 end
    return 1.0 + 0.5 * pa              -- panicked = quicker, up to +50%
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
-- Used for AIMING: clamped to the smooth cap to avoid judder.
local function withDynamic(p, base)
    local v = base * dynamicMultiplier(p)
    if v < MIN_TURN_DELTA then return MIN_TURN_DELTA end
    if v > MAX_SMOOTH_TURN_DELTA then return MAX_SMOOTH_TURN_DELTA end
    return v
end

-- Movement variant: floor only, NO upper cap. The movement presets are intentionally
-- large to overcome B41's moveDelta attenuation (see MOVEMENT_TURN_PRESETS), so
-- clamping them to 2.5 here would undo the fix; judder isn't a concern while moving.
local function withDynamicMovement(p, base)
    local v = base * dynamicMultiplier(p)
    if v < MIN_TURN_DELTA then return MIN_TURN_DELTA end
    return v
end

-- ==== Original system (per tick): separate aiming / walking turn speeds ====
local function updateOriginalPivot(p)
    local apply = (not traitVersion) or playerHasTrait(p, "OnYourToes")
    if not apply then
        p:setTurnDelta(DEFAULT_TURN_DELTA)
        return
    end
    -- setTurnDelta drives turnDeltaNormal, which the engine uses while AIMING and while
    -- WALKING (the Run key is up). Jog/sprint use turnDeltaRunning/turnDeltaSprinting
    -- (unsettable from Lua), so those always stay vanilla. Aiming and walking use
    -- different preset scales: walking needs the larger MOVEMENT_TURN_PRESETS to beat
    -- B41's moveDelta attenuation, and skips the aiming judder cap.
    if p:isAiming() then
        local base = PIVOT_SPEED_PRESETS[pivotPreset] or DEFAULT_TURN_DELTA
        p:setTurnDelta(withDynamic(p, base))
    else
        local base = MOVEMENT_TURN_PRESETS[movementPreset] or DEFAULT_TURN_DELTA
        p:setTurnDelta(withDynamicMovement(p, base))
    end
end

-- ==== Nimble system (ported from NATS) ====
local function nimbleAffected(p)
    if not traitVersion then return true end
    return playerHasTrait(p, "OnYourToes") or playerHasTrait(p, "PodShofe")
end

local function computeNimbleAffect(p)
    local md = p:getModData()
    if md.NimbleAffect ~= nil then return end
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
            p:getTraits():add("OnYourToes")
            p:Say(getText("IGUI_Add_OnYourToes"))
            md.NimbleAffect = md.NimbleAffect + onYourToesInGameMult
        elseif playerHasTrait(p, "PodShofe") then
            p:getTraits():remove("PodShofe")
            p:Say(getText("IGUI_Remove_PodShofe"))
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

-- ==== Events ====
SPAC.OnTick = function()
    if not enabled then return end
    -- The Nimble system normally persists its value (set on spawn / level-up), so it
    -- needs no per-tick work. The exception is dynamic modifiers: they track live
    -- stats, so when enabled the Nimble value is re-applied every tick too.
    if nimbleSystem and not dynamicEnabled then return end
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
    Events.OnTick.Remove(SPAC.OnTick)
    Events.OnTick.Add(SPAC.OnTick)
end

SPAC.OnGameStart = function()
    loadSandboxOptions()
    Events.OnTick.Remove(SPAC.OnTick)
    Events.OnTick.Add(SPAC.OnTick)
end

Events.OnGameBoot.Add(registerTraits)
Events.OnGameStart.Add(SPAC.OnGameStart)
Events.OnCreatePlayer.Add(SPAC.OnCreatePlayer)
Events.LevelPerk.Add(SPAC.OnLevelPerk)
