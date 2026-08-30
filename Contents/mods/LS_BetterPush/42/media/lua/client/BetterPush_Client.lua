require "BetterPush_Shared"

-- Domino queue: list of { zombie, knockAtTick }
-- Each entry waits until the game tick reaches knockAtTick before falling
BetterPush.dominoQueue = BetterPush.dominoQueue or {}

-- Current game tick counter
BetterPush.tickCount = 0

-- LS-002: per-zombie cooldown so a duplicate OnWeaponHitCharacter fire for the same
-- shove can't send a second Trigger request for the same target.
local lastShoveReport = {}
local SHOVE_REPORT_COOLDOWN_MS = 500

--- Tick handler: process the domino queue with staggered timing
local function onTick()
    BetterPush.tickCount = BetterPush.tickCount + 1

    -- Process queue entries whose time has come
    local i = 1
    while i <= #BetterPush.dominoQueue do
        local entry = BetterPush.dominoQueue[i]
        if BetterPush.tickCount >= entry.knockAtTick then
            -- Time to knock this one down!
            if entry.zombie and not entry.zombie:isDead() then
                BetterPush.knockDownZombie(entry.zombie)
            end
            table.remove(BetterPush.dominoQueue, i)
            -- don't increment i, the next entry shifted into this slot
        else
            i = i + 1
        end
    end
end

Events.OnTick.Add(onTick)

local function queueLocalKnockdown(zombie, delayTicks)
    table.insert(BetterPush.dominoQueue, {
        zombie = zombie,
        knockAtTick = BetterPush.tickCount + delayTicks,
    })
end

---Handler for when a player hits a character.
---Parameters in PZ are: attacker, target, weapon, damageSplit
local function onWeaponHitCharacter(attacker, target, weapon, damageSplit)
    -- Safety checks to prevent crashes from nil or unexpected types during bumps
    if not attacker or type(attacker) ~= "userdata" then return end
    if not target or type(target) ~= "userdata" then return end

    -- Only process player attacking zombie
    if not instanceof(attacker, "IsoPlayer") then return end
    if not instanceof(target, "IsoZombie") then return end
    if target:isDead() then return end
    if target.isKnockedDown and target:isKnockedDown() then return end

    local player = attacker
    local zombie = target

    -- Only trigger on spacebar shoves, NOT weapon swings.
    -- When shoving (spacebar), PZ passes nil or "BareHands" as the weapon parameter.
    -- When swinging (left click), PZ passes the actual equipped weapon.
    if weapon then
        if type(weapon) ~= "userdata" then return end
        if not weapon.getType or weapon:getType() ~= "BareHands" then
            return
        end
    end

    -- LS-002: OnWeaponHitCharacter fires locally on EVERY connected client whenever
    -- ANY player shoves a zombie, not just the attacker's own client. Without this
    -- guard, every online player's client independently computed a domino chain and
    -- sent its own Trigger command for the SAME shove, multiplying the effect by
    -- player count - the root cause of the desync/duplicate-knockdown reports this
    -- rewrite fixes. Only the attacker's own client may ever act on its own attack.
    if isClient() and player ~= getPlayer() then return end

    if isClient() then
        local id = zombie:getOnlineID()
        local now = getTimestampMs()
        if id and id >= 0 then
            if lastShoveReport[id] and now - lastShoveReport[id] < SHOVE_REPORT_COOLDOWN_MS then
                return
            end
            lastShoveReport[id] = now
        end

        -- LS-002: the client only ever reports WHICH zombie it shoved and WHERE - the
        -- server computes the entire domino chain itself (see BetterPush_Server.lua),
        -- it never trusts a client-submitted target list again.
        sendClientCommand(player, BetterPush.MODULE, BetterPush.COMMAND_REQUEST, {
            zombieID = id,
            x = zombie:getX(), y = zombie:getY(), z = zombie:getZ(),
        })
        return
    end

    -- Singleplayer: resolve locally, no server round trip.
    local str = player:getPerkLevel(Perks.Strength)
    local chance = BetterPush.getChanceForStrength(str)
    if chance <= 0 then return end

    local roll = ZombRand(100)
    if roll >= chance then return end

    local maxCount = BetterPush.getMaxZombiesForStrength(str)
    local chainZombies = BetterPush.getDominoChain(player, zombie, maxCount)

    for idx, sz in ipairs(chainZombies) do
        queueLocalKnockdown(sz, idx * BetterPush.DOMINO_DELAY_TICKS)
    end
end

Events.OnWeaponHitCharacter.Add(onWeaponHitCharacter)

-- LS-002: apply the server's authoritative domino result locally. Every connected
-- client (including the original attacker) receives this and queues the same
-- zombie/delay, so the effect is explicitly broadcast instead of relying on generic
-- zombie-state sync to happen to carry a server-side setHitReaction/setKnockedDown
-- call to observers.
local function onServerCommand(module, command, args)
    if module ~= BetterPush.MODULE or command ~= BetterPush.COMMAND_SYNC then return end
    if not args then return end

    local zombie = BetterPush.findZombie(args.x or 0, args.y or 0, args.z or 0, args.zombieID, getCell())
    if zombie then
        queueLocalKnockdown(zombie, math.max(0, tonumber(args.delayTicks) or 0))
    end
end

Events.OnServerCommand.Add(onServerCommand)
