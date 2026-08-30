-- Position feed for the client side spectator follow (AegisFollow.lua)
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

local function findByUsername(name)
    local players = getOnlinePlayers()
    if not players then return nil end
    for i = 0, players:size() - 1 do
        local p = players:get(i)
        if p and p:getUsername() == name then return p end
    end
    return nil
end

local Commands = {}

-- getTimestamp only resolves whole seconds: at most one granted request
-- per started second is the 1/s budget (the client polls every 1s, so
-- back to back requests land in different seconds and none is wasted)
local lastReq = {}

Commands.followPos = function(player, args)
    if not args or type(args.username) ~= "string" or args.username == "" or #args.username > 64 then return end
    -- throttle FIRST: a client that lost the right mid follow keeps polling,
    -- the deny answer must not fire more often than the budget either
    local name = player:getUsername()
    local now = AegisShared.realTime()
    if lastReq[name] == now then return end
    lastReq[name] = now
    if not AegisRoles.canArea(player, "players") then
        toClient(player, "denied", { area = "players" })
        return
    end
    local target = findByUsername(args.username)
    if not target then
        toClient(player, "followPos", { username = args.username, gone = true })
        return
    end
    local x, y, z
    local ok = pcall(function() x, y, z = target:getX(), target:getY(), target:getZ() end)
    -- momentarily unreadable is not gone, the client just polls again
    if not ok or not x then return end
    toClient(player, "followPos", { username = args.username, x = x, y = y, z = z })
end

local function onClientCommand(module, command, player, args)
    if module ~= AegisShared.MODULE then return end
    if AegisModeration.isSuspended(player) then return end
    if Commands[command] then Commands[command](player, args) end
end

Events.OnClientCommand.Add(onClientCommand)
