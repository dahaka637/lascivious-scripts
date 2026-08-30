-- Server branding: operators put their own server name into the panel
-- heads. One line under Aegis/Status/branding.txt, synced to every
-- client.
if isClient() then return end

require "Aegis_Store"
require "Aegis_Roles"
require "Aegis_Log"
require "Aegis_Moderation"
require "Aegis_PlayerPanel"

AegisBranding = AegisBranding or {}

local FILE = AegisStore.ROOT .. "/Status/branding.txt"
local MAX_NAME = 24

-- nil = not loaded yet, "" = no custom name (clients fall back to AEGIS)
local brandName = nil

-- strips what the header and the file format cannot carry: the pipe is
-- the store's field separator, control chars would forge log lines
local function clean(v)
    local s = tostring(v or ""):gsub("[%c|]", "")
    s = s:gsub("^%s+", ""):gsub("%s+$", "")
    if #s > MAX_NAME then
        -- kahlua strings are java strings: # and byte() count UTF-16
        -- units, not UTF-8 bytes. The only unit a cut
        -- can break is a surrogate pair, so drop a dangling high half
        s = s:sub(1, MAX_NAME)
        local b = #s > 0 and s:byte(#s) or nil
        if b and b >= 55296 and b <= 56319 then s = s:sub(1, #s - 1) end
    end
    return s
end

-- line "B|<name>"; a bare legacy line without the prefix loads too, so
-- an old or hand edited file never silently drops the name
local function load()
    if brandName ~= nil then return end
    brandName = ""
    local lines = AegisStore.readLines(FILE, 5)
    for _, line in ipairs(lines or {}) do
        local v = clean(line:match("^B|(.*)") or line)
        if v ~= "" then
            brandName = v
            break
        end
    end
end

local function save()
    return AegisStore.write(FILE, brandName == "" and "" or ("B|" .. brandName .. "\n"))
end

-- reply to the sender only: over the network in MP, in solo directly to
-- the OnServerCommand listeners of the same process
local function toClient(player, command, args)
    if isServer() then
        sendServerCommand(player, AegisShared.MODULE, command, args)
    else
        triggerEvent("OnServerCommand", AegisShared.MODULE, command, args)
    end
end

local function push(player)
    load()
    toClient(player, "brandSync", { name = brandName })
end

local function broadcast()
    load()
    if isServer() then
        sendServerCommand(AegisShared.MODULE, "brandSync", { name = brandName })
    else
        triggerEvent("OnServerCommand", AegisShared.MODULE, "brandSync", { name = brandName })
    end
end

local lastReq = {}
local function throttled(name, command, seconds)
    local now = AegisShared.realTime()
    local key = name .. "\n" .. command
    if lastReq[key] and now - lastReq[key] < seconds then return true end
    lastReq[key] = now
    return false
end

local function senderName(player)
    local name = player:getUsername()
    if type(name) == "string" and name ~= "" then return name end
    return nil
end

local Commands = {}

-- readable for everyone, the blue player head shows the brand too
Commands.brandReq = function(player, args)
    local name = senderName(player)
    if not name then return end
    if throttled(name, "brandReq", 2) then return end
    push(player)
end

Commands.brandSet = function(player, args)
    local name = senderName(player)
    if not name then return end
    -- throttle before the rights check, same order as every dispatcher
    if throttled(name, "brandSet", 2) then return end
    if not AegisRoles.canArea(player, "server") then
        toClient(player, "denied", { area = "server" })
        return
    end
    load()
    local value = clean(type(args) == "table" and args.name or "")
    if value ~= brandName then
        brandName = value
        save()
        AegisLog.write("Actions", name, "branding",
            value == "" and "Panel branding reset to AEGIS"
            or ("Panel branding set: " .. value))
    end
    -- always broadcast: an unchanged value still confirms to the setter,
    -- and every open head repaints from the same sync
    broadcast()
end

-- join moment: every client asks for its player panel state at game
-- start (ppReq with retries) and that reply always runs through
-- AegisPlayerPanel.push, so riding on it reaches each joiner without a
-- second round trip or an own join event. Pushes after role edits merely
-- repeat the current name, which is harmless.
local basePush = AegisPlayerPanel.push
AegisPlayerPanel.push = function(player)
    basePush(player)
    pcall(push, player)
end

local function onClientCommand(module, command, player, args)
    if module ~= AegisShared.MODULE then return end
    -- suspended senders keep no authority in any Aegis area
    if AegisModeration.isSuspended(player) then return end
    if Commands[command] then Commands[command](player, args) end
end

Events.OnClientCommand.Add(onClientCommand)
