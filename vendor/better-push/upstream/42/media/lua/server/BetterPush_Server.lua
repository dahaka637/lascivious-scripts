require "BetterPush_Shared"

---Server-side logic for synchronizing BetterPush in Multiplayer.

-- Server-side domino queue for staggered knockdowns
BetterPush.serverQueue = BetterPush.serverQueue or {}
BetterPush.serverTick = 0
BetterPush.SERVER_DOMINO_DELAY = 20  -- ~0.66 seconds per zombie

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
---@param args table Arguments containing zombie IDs and delay indices
local function onClientCommand(module, command, player, args)
    if module == 'BetterPush' and command == 'Trigger' then
        if not args or not args.targetIDs then return end

        for idx, id in ipairs(args.targetIDs) do
            local zombie = getZombieByOnlineID(id)
            if zombie and not zombie:isDead() then
                -- Stagger each knockdown by its position in the chain
                local delay = idx * BetterPush.SERVER_DOMINO_DELAY
                local knockAtTick = BetterPush.serverTick + delay
                table.insert(BetterPush.serverQueue, {
                    zombie = zombie,
                    knockAtTick = knockAtTick,
                })
            end
        end
    end
end

Events.OnClientCommand.Add(onClientCommand)
