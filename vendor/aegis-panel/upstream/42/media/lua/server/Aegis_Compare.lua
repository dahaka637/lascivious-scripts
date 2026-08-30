-- Player compare, server side: ONE command returns both data blocks
-- (core stats, skills, traits, aggregated inventory) in ONE reply,
-- so unlike the vanilla InvMng channel identity is never lost and
-- nothing needs to be sequenced. Offline players are unsupported in
-- v1 (ServerPlayerDB is not exposed to Lua), the block then carries
-- a missing flag.
if isClient() then return end

require "Aegis_Roles"
require "Aegis_Moderation"

local function toClient(player, command, args)
    if isServer() then
        sendServerCommand(player, AegisShared.MODULE, command, args)
    else
        triggerEvent("OnServerCommand", AegisShared.MODULE, command, args)
    end
end

local function allowed(player, area)
    if not AegisRoles.canArea(player, area) then
        if isServer() then
            sendServerCommand(player, "AegisAdmin", "denied", { area = area })
        end
        return false
    end
    return true
end

-- online lookup; in solo getOnlinePlayers returns an empty list,
-- only the own player exists there in the same process
local function findPlayer(name)
    local players = getOnlinePlayers()
    if players then
        for i = 0, players:size() - 1 do
            local p = players:get(i)
            if p and p:getUsername() == name then return p end
        end
    end
    if not isServer() then
        local p = getPlayer()
        if p and p:getUsername() == name then return p end
    end
    return nil
end

-- all perks with level > 0; only the perk id is transferred, the client
-- translates it locally (no getText on the dedicated server)
local function skillList(target)
    local list = {}
    for i = 0, PerkFactory.PerkList:size() - 1 do
        local perk = PerkFactory.PerkList:get(i)
        local level = target:getPerkLevel(perk)
        if level and level > 0 then
            table.insert(list, { id = perk:getId(), level = level })
        end
    end
    return list
end

-- B42 way: getCharacterTraits():getKnownTraits(), getTraits is gone
local function traitList(target)
    local list = {}
    local traits = target:getCharacterTraits():getKnownTraits()
    for i = 0, traits:size() - 1 do
        local t = traits:get(i)
        if t then table.insert(list, t:getName()) end
    end
    return list
end

-- aggregate inventory by full type, bags recursed with a depth cap.
-- deliberately via getItems instead of getItems4Admin: the latter
-- mutates live items (setCount) and is off limits for pure display
local MAX_DEPTH = 3
local MAX_KINDS = 250

local function collect(container, map, rows, state, depth)
    if not container or depth > MAX_DEPTH then return end
    local items = container:getItems()
    for i = 0, items:size() - 1 do
        local it = items:get(i)
        if it then
            local full = it:getFullType()
            local rec = map[full]
            if not rec and #rows >= MAX_KINDS then
                -- known kinds keep counting, only new kinds are dropped
                state.truncated = true
            else
                if not rec then
                    rec = { t = full, n = 0, g = 0 }
                    map[full] = rec
                    table.insert(rows, rec)
                end
                rec.n = rec.n + 1
                pcall(function() rec.g = rec.g + it:getActualWeight() end)
            end
            pcall(function()
                if instanceof(it, "InventoryContainer") then
                    collect(it:getItemContainer(), map, rows, state, depth + 1)
                end
            end)
        end
    end
end

local function inventoryList(target)
    local rows = {}
    local state = {}
    pcall(function()
        collect(target:getInventory(), {}, rows, state, 1)
    end)
    for _, rec in ipairs(rows) do
        rec.g = math.floor(rec.g * 10 + 0.5) / 10
    end
    return rows, state.truncated == true
end

local function buildBlock(name)
    local target = findPlayer(name)
    if not target then
        return { username = name, missing = true }
    end
    local block = { username = target:getUsername(), hours = 0, kills = 0, x = 0, y = 0, z = 0 }
    block.hours = math.floor(target:getHoursSurvived() * 10 + 0.5) / 10
    block.kills = target:getZombieKills()
    block.x = math.floor(target:getX())
    block.y = math.floor(target:getY())
    block.z = math.floor(target:getZ())
    pcall(function()
        local inv = target:getInventory()
        block.last = math.floor(inv:getCapacityWeight() * 10 + 0.5) / 10
        block.maxWeight = inv:getMaxWeight()
    end)
    local weapon = target:getPrimaryHandItem()
    if weapon then block.weapon = weapon:getFullType() end
    block.skills = skillList(target)
    block.traits = traitList(target)
    block.inv, block.invTruncated = inventoryList(target)
    return block
end

-- buildBlock is expensive (perk/trait iteration plus recursive inventory
-- aggregation, up to twice per call), capped like the sibling commands
-- at one request per second and player
local lastRequest = {}
local function throttled(player)
    local name = player and player:getUsername() or "?"
    local now = AegisShared.realTime()
    if lastRequest[name] and now - lastRequest[name] < 1 then return true end
    lastRequest[name] = now
    return false
end

local Commands = {}

Commands.compareData = function(player, args)
    if not allowed(player, "players") then return end
    if throttled(player) then return end
    if not args or type(args.a) ~= "string" or args.a == "" then return end
    local reply = { a = buildBlock(args.a) }
    if type(args.b) == "string" and args.b ~= "" then
        reply.b = buildBlock(args.b)
    end
    -- distance from live positions, euclidean in 2D plus floor delta;
    -- DistTo would be Manhattan and misleading for display
    if reply.b and not reply.a.missing and not reply.b.missing then
        local pa = findPlayer(args.a)
        local pb = findPlayer(args.b)
        if pa and pb then
            local dx = pa:getX() - pb:getX()
            local dy = pa:getY() - pb:getY()
            reply.distance = math.floor(math.sqrt(dx * dx + dy * dy) + 0.5)
            reply.floors = math.abs(math.floor(pa:getZ()) - math.floor(pb:getZ()))
        end
    end
    toClient(player, "compareData", reply)
end

Events.OnClientCommand.Add(function(module, command, player, args)
    if module ~= AegisShared.MODULE then return end
    -- suspended admins may not use any Aegis area
    if AegisModeration.isSuspended(player) then return end
    if Commands[command] then Commands[command](player, args) end
end)
