require "BetterPush_Shared"

---Server-side logic for synchronizing BetterPush in Multiplayer.

-- Server-side domino queue for staggered knockdowns
BetterPush.serverQueue = BetterPush.serverQueue or {}
BetterPush.serverTick = 0
BetterPush.SERVER_DOMINO_DELAY = 20  -- ~0.66 seconds per zombie

-- LS-002: per-player request cooldown (authoritative - unlike the client-side
-- cooldown in BetterPush_Client.lua, a modified client can't bypass this one).
local lastRequest = {}
local REQUEST_COOLDOWN_MS = 350

-- LS-002: how close the reported shoved zombie must be to the requesting player.
-- This is the ONLY distance check needed now - once that first zombie is validated,
-- the rest of the chain is derived from it by BetterPush.getDominoChain(), which is
-- itself already bounded by BetterPushLineDistance/BetterPushLineWidth per link.
local MAX_TARGET_DISTANCE_SQ = 6.25 -- 2.5 tiles: melee shove reach plus a little slack

--- Tick handler for server-side staggered knockdowns
local function onServerTick()
    BetterPush.serverTick = BetterPush.serverTick + 1

    local i = 1
    while i <= #BetterPush.serverQueue do
        local entry = BetterPush.serverQueue[i]
        if BetterPush.serverTick >= entry.knockAtTick then
            if entry.zombie and not entry.zombie:isDead() then
                BetterPush.knockDownZombie(entry.zombie)
            end
            table.remove(BetterPush.serverQueue, i)
        else
            i = i + 1
        end
    end
end

Events.OnTick.Add(onServerTick)


---@param module string The module name
---@param command string The command name
---@param player IsoPlayer The player who sent the command
---@param args table Arguments: the shoved zombie's online ID and position
local function onClientCommand(module, command, player, args)
    if module ~= BetterPush.MODULE or command ~= BetterPush.COMMAND_REQUEST then return end
    if not player or not args then return end

    -- LS-002: authoritative per-player rate limit.
    local playerID = player:getOnlineID()
    local now = getTimestampMs()
    if lastRequest[playerID] and now - lastRequest[playerID] < REQUEST_COOLDOWN_MS then return end
    lastRequest[playerID] = now

    -- LS-001/LS-002: resolve and validate the shoved zombie server-side - the client
    -- only ever reports which zombie it shoved, never a chain to apply.
    local target = BetterPush.findZombie(
        args.x or player:getX(), args.y or player:getY(), args.z or player:getZ(),
        args.zombieID, player:getCell()
    )
    if not target or target:isDead() then return end

    local dx = target:getX() - player:getX()
    local dy = target:getY() - player:getY()
    if dx * dx + dy * dy > MAX_TARGET_DISTANCE_SQ then return end

    local str = player:getPerkLevel(Perks.Strength)
    local chance = BetterPush.getChanceForStrength(str)
    if chance <= 0 then return end
    if ZombRand(100) >= chance then return end

    -- LS-002: the chain itself is now computed entirely server-side, from the
    -- server-authoritative zombie list - never received from the client.
    local maxCount = BetterPush.getMaxZombiesForStrength(str)
    local chain = BetterPush.getDominoChain(player, target, maxCount)

    for idx, zombie in ipairs(chain) do
        local delayTicks = idx * BetterPush.SERVER_DOMINO_DELAY
        table.insert(BetterPush.serverQueue, {
            zombie = zombie,
            knockAtTick = BetterPush.serverTick + delayTicks,
        })

        -- LS-002: explicit broadcast so every client (including the attacker) applies
        -- the knockdown itself, rather than relying on generic zombie-state sync to
        -- carry the server's own setHitReaction/setKnockedDown calls to observers.
        sendServerCommand(BetterPush.MODULE, BetterPush.COMMAND_SYNC, {
            zombieID = zombie:getOnlineID(),
            x = zombie:getX(), y = zombie:getY(), z = zombie:getZ(),
            delayTicks = delayTicks,
        })
    end
end

Events.OnClientCommand.Add(onClientCommand)
