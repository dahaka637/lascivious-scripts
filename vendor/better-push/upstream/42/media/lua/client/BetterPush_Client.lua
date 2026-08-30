require "BetterPush_Shared"

-- Domino queue: list of { zombie, knockAtTick }
-- Each entry waits until the game tick reaches knockAtTick before falling
BetterPush.dominoQueue = BetterPush.dominoQueue or {}

-- Ticks between each domino falling (~10 ticks = ~0.33 seconds at 30fps)
BetterPush.DOMINO_DELAY_TICKS = 20

-- Current game tick counter
BetterPush.tickCount = 0

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


---Handler for when a player hits a character.
---Parameters in PZ are: attacker, target, weapon, damageSplit
local function onWeaponHitCharacter(attacker, target, weapon, damageSplit)
    -- Safety checks to prevent crashes from nil or unexpected types during bumps
    if not attacker or type(attacker) ~= "userdata" then return end
    if not target or type(target) ~= "userdata" then return end

    -- Only process player attacking zombie
    if not instanceof(attacker, "IsoPlayer") then return end
    if not instanceof(target, "IsoZombie") then return end

    local player = attacker
    local zombie = target

    -- 0. Only trigger on spacebar shoves, NOT weapon swings
    -- When shoving (spacebar), PZ passes nil or "BareHands" as the weapon parameter
    -- When swinging (left click), PZ passes the actual equipped weapon
    if weapon then
        if type(weapon) ~= "userdata" then return end
        if not weapon.getType or weapon:getType() ~= "BareHands" then
            return
        end
    end

    -- 1. Get strength-based chance (returns 0 if below min strength)
    local str = player:getPerkLevel(Perks.Strength)
    local chance = BetterPush.getChanceForStrength(str)
    if chance <= 0 then return end

    -- 2. Roll against the interpolated chance
    local roll = ZombRand(100)
    if roll >= chance then return end

    print("[BetterPush] TRIGGERED! Strength=" .. str .. " Chance=" .. chance .. "% Roll=" .. roll)

    -- 3. Find zombies in a domino chain behind the shoved zombie
    local maxCount = BetterPush.getMaxZombiesForStrength(str)
    local chainZombies = BetterPush.getDominoChain(player, zombie, maxCount)

    print("[BetterPush] Found " .. #chainZombies .. " zombies in domino chain")

    if #chainZombies > 0 then
        if isClient() then
            -- Multiplayer: send to server with delay indices
            local args = { targetIDs = {}, delays = {} }
            for idx, sz in ipairs(chainZombies) do
                table.insert(args.targetIDs, sz:getOnlineID())
                table.insert(args.delays, idx)  -- delay index for staggering
            end
            sendClientCommand(player, 'BetterPush', 'Trigger', args)
        else
            -- Singleplayer: queue each zombie with a staggered delay
            for idx, sz in ipairs(chainZombies) do
                local knockAtTick = BetterPush.tickCount + (idx * BetterPush.DOMINO_DELAY_TICKS)
                table.insert(BetterPush.dominoQueue, {
                    zombie = sz,
                    knockAtTick = knockAtTick,
                })
            end
        end
    end
end

Events.OnWeaponHitCharacter.Add(onWeaponHitCharacter)
