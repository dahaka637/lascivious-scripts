-- Lascivious Factions System - member friendly-fire prevention (client side).
--
-- When two PLAYERS are in the same faction and that faction's friendly-fire is
-- OFF (the default), they can't damage each other -- but they can still damage
-- everyone else (outsiders, raiders) normally. Owners flip this per-faction from
-- the Settings tab (faction.friendlyFire).
--
-- Build 42 has no cancellable player-damage event, so we use the proven pattern
-- (HDX_Stranger): cache the victim's HP in OnWeaponHitXp (which fires first), then
-- in OnWeaponHitCharacter -- if the attacker+victim are a protected same-faction
-- pair -- restore the victim's health, clear the fresh wound, and drop the aggro.
--
-- CAVEAT: like the raid-PVP toggle and the permission hooks, this is client-side
-- and therefore advisory. On a dedicated server health is server-authoritative,
-- so the restore is best-effort there; it works on the coop host. The whole thing
-- is pcall-guarded and self-disables after one failure so a B42 API change
-- degrades gracefully instead of erroring on every hit.

require "LFS_Shared"

local FF = LasciviousFactionsSystem

local ffBroken = false          -- set true after a failure; stop trying
local preHitHP = {}             -- [username] = { health, attacker, at }

-- Are these two players a same-faction pair currently protected from each other?
local function protectedPair(wielder, victim)
    if not (instanceof(wielder, "IsoPlayer") and instanceof(victim, "IsoPlayer")) then
        return false
    end
    local wu = wielder:getUsername()
    local vu = victim:getUsername()
    return FF.isFriendlyFireProtected(wu, vu)
end

-- OnWeaponHitXp(owner, weapon, hitObject, damage, hitCount) fires around the hit;
-- we use it only to sample the victim's pre-hit health.
local function onWeaponHitXp(owner, weapon, hitObject, damage, hitCount)
    if ffBroken then return end
    if not instanceof(hitObject, "IsoPlayer") then return end
    local ok, err = pcall(function()
        local vu = hitObject:getUsername()
        if not vu then return end
        -- Never retain a hostile/ordinary hit snapshot. Previously every player
        -- hit was cached and only a later protected hit consumed it, allowing a
        -- stale high HP value from an enemy hit to heal unrelated damage.
        if not FF.getOptions().enforceFriendlyFire or not protectedPair(owner, hitObject) then
            preHitHP[vu] = nil
            return
        end
        preHitHP[vu] = {
            health = hitObject:getHealth(),
            attacker = owner:getUsername(),
            at = getTimestamp(),
        }
    end)
    if not ok then
        ffBroken = true
        FF.warn("friendly-fire cache failed: " .. tostring(err)
            .. " (friendly-fire prevention disabled)")
    end
end

-- OnWeaponHitCharacter(wielder, victim, weapon, damage) fires after damage is
-- applied. Undo it for a protected same-faction pair.
local function onWeaponHitCharacter(wielder, victim, weapon, damage)
    if ffBroken then return end
    if not FF.getOptions().enforceFriendlyFire then return end
    -- victim is very often a zombie, not a player (this event fires on every
    -- successful hit) -- IsoZombie has no getUsername(), so without this
    -- guard the very first zombie hit of the session throws "call nil" from
    -- inside the pcall below and permanently disables the whole feature via
    -- ffBroken. onWeaponHitXp already had the equivalent check; this one
    -- didn't.
    if not instanceof(victim, "IsoPlayer") then return end

    local ok, err = pcall(function()
        local vu = victim:getUsername()
        local cached = vu and preHitHP[vu] or nil
        -- Consume first on every outcome so an exception/identity mismatch cannot
        -- leave a snapshot available to some later hit.
        if vu then preHitHP[vu] = nil end
        if not protectedPair(wielder, victim) then return end
        if not cached or cached.attacker ~= wielder:getUsername()
            or (getTimestamp() - (cached.at or 0)) > 2 then return end

        -- Revert only the HP loss attributable to this hit. The former full-body
        -- reset cured every pre-existing wound, infection and illness whenever a
        -- faction mate landed even a trivial hit -- a severe healing exploit.
        local target = tonumber(cached.health)
        if victim.setHealth then
            victim:setHealth(math.max(target or victim:getHealth(), victim:getHealth()))
        end
        if victim.setKnockedDown then victim:setKnockedDown(false) end
        if victim.setAttackedBy then victim:setAttackedBy(nil) end
    end)
    if not ok then
        ffBroken = true
        FF.warn("friendly-fire prevention failed: " .. tostring(err)
            .. " (falling back to normal PVP; other features unaffected)")
    end
end

-- Guard the registrations: if a B42 build ever lacks one of these events the
-- feature simply no-ops instead of erroring the whole file at load.
if FF._friendlyFireXpHook and Events.OnWeaponHitXp then
    Events.OnWeaponHitXp.Remove(FF._friendlyFireXpHook)
end
if FF._friendlyFireHitHook and Events.OnWeaponHitCharacter then
    Events.OnWeaponHitCharacter.Remove(FF._friendlyFireHitHook)
end
FF._friendlyFireXpHook = onWeaponHitXp
FF._friendlyFireHitHook = onWeaponHitCharacter
if Events.OnWeaponHitXp then Events.OnWeaponHitXp.Add(onWeaponHitXp) end
if Events.OnWeaponHitCharacter then
    Events.OnWeaponHitCharacter.Add(onWeaponHitCharacter)
else
    FF.warn("OnWeaponHitCharacter unavailable; friendly-fire prevention disabled")
end
