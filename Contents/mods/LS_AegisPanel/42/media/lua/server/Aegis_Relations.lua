-- Relationship radar: tracks minute by minute who stays near whom.
-- Only usernames and minute counts are stored, never positions.
if isClient() then return end

require "Aegis_Store"
require "Aegis_Roles"
require "Aegis_Moderation"

local FOLDER = AegisStore.ROOT .. "/Relationships/"
-- proximity: under 20 tiles in the plane and at most one floor apart
local NEAR_SQUARED = 20 * 20
local FLOOR_DELTA = 1
-- flush interval and sample cap against lag spikes, both real seconds
local FLUSH_INTERVAL = 600
local DELTA_CAP = 120

-- Project Zomboid has no Lua hook for a clean shutdown. The status file of
-- the restart timer (Aegis_Server) survives server restarts for exactly that
-- reason, here it is only read to force a flush shortly before the deadline
-- instead of waiting up to ten minutes
local RESTART_FILE = AegisStore.ROOT .. "/Status/restart.txt"
local RESTART_LEAD = 90

local function toClient(player, command, args)
    if isServer() then
        sendServerCommand(player, AegisShared.MODULE, command, args)
    else
        triggerEvent("OnServerCommand", AegisShared.MODULE, command, args)
    end
end

-- only the area permission the radar needs, no vanilla capability
local function allowed(player, area)
    if not AegisRoles.canArea(player, area) then
        if isServer() then
            sendServerCommand(player, AegisShared.MODULE, "denied", { area = area })
        end
        return false
    end
    return true
end

-- daily accumulator: pair key "smaller|larger" -> shared seconds.
-- It always holds the full day, the day file is just its snapshot.
local acc = {}
local accDay = nil
local lastSample = 0
local lastFlush = 0
local dirty = false

local function dayPath(date)
    return FOLDER .. date .. ".txt"
end

local function pairKey(nameA, nameB)
    local a = AegisShared.sanitizeName(nameA)
    local b = AegisShared.sanitizeName(nameB)
    if a == b then return nil end
    if a > b then a, b = b, a end
    return a .. "|" .. b
end

-- rewrite the day file entirely from the accumulator; fractions below one
-- minute stay in memory and are only lost when the server stops
local function flush()
    if not accDay then return end
    local lines = {}
    for key, seconds in pairs(acc) do
        local minutes = math.floor(seconds / 60)
        if minutes > 0 then
            table.insert(lines, key .. "|" .. tostring(minutes))
        end
    end
    table.sort(lines)
    local content = table.concat(lines, "\n")
    if #lines > 0 then content = content .. "\n" end
    AegisStore.write(dayPath(accDay), content)
    lastFlush = AegisShared.realTime()
    dirty = false
end

-- align the accumulator to the current day: on startup and after
-- midnight. Today's file is loaded back so a server restart does
-- not discard the day's progress.
local function alignDay()
    local now = AegisShared.realTime()
    if now <= 0 then return end
    local today = AegisShared.dateShort(now)
    if accDay == today then return end
    if accDay and dirty then flush() end
    acc = {}
    accDay = today
    dirty = false
    local lines = AegisStore.readLines(dayPath(today), 20000)
    if lines then
        for _, line in ipairs(lines) do
            local a, b, minutes = line:match("^([^|]+)|([^|]+)|(%d+)$")
            if a and b then
                acc[a .. "|" .. b] = (tonumber(minutes) or 0) * 60
            end
        end
    end
end

-- true when the restart timer's PLAN entry is about due. The rhythm entry
-- arms a PLAN entry in time anyway, so that single look into the file
-- is enough
local function restartDueSoon()
    local lines = AegisStore.readLines(RESTART_FILE, 4)
    if not lines then return false end
    for _, line in ipairs(lines) do
        local endTime = line:match("^PLAN|(%d+)|")
        if endTime then
            return AegisShared.realTime() >= tonumber(endTime) - RESTART_LEAD
        end
    end
    return false
end

-- sampling, dedicated only: each nearby online pair gets the real time
-- since the last sample. EveryOneMinute ticks on GAME time and fires every
-- few real seconds on short sandbox days, so the real-time delta is used
-- for normalization instead of adding a flat minute.
local function radar()
    if not isServer() then return end
    alignDay()
    if not accDay then return end
    local now = AegisShared.realTime()
    local delta = 0
    if lastSample > 0 then
        delta = math.min(now - lastSample, DELTA_CAP)
    end
    lastSample = now
    if delta > 0 then
        local players = getOnlinePlayers()
        local n = players and players:size() or 0
        for i = 0, n - 2 do
            local a = players:get(i)
            if a then
                for j = i + 1, n - 1 do
                    local b = players:get(j)
                    -- euclidean in the plane, DistTo would be Manhattan
                    if b and math.abs(a:getZ() - b:getZ()) <= FLOOR_DELTA then
                        local dx = a:getX() - b:getX()
                        local dy = a:getY() - b:getY()
                        if dx * dx + dy * dy < NEAR_SQUARED then
                            local key = pairKey(a:getUsername(), b:getUsername())
                            if key then
                                acc[key] = (acc[key] or 0) + delta
                                dirty = true
                            end
                        end
                    end
                end
            end
        end
    end
    if dirty and (now - lastFlush >= FLUSH_INTERVAL or restartDueSoon()) then
        flush()
    end
end

Events.EveryOneMinute.Add(radar)
Events.OnServerStarted.Add(alignDay)

-- cap read requests per player at 1/s, relationData reads up to 6 files
local lastRequest = {}
local function throttled(player)
    local name = player and player:getUsername() or "?"
    local now = AegisShared.realTime()
    if lastRequest[name] and now - lastRequest[name] < 1 then return true end
    lastRequest[name] = now
    return false
end

local Commands = {}

-- top partners of a player over the last 7 days: today from the live
-- accumulator (it already contains today's day file completely, reading
-- it too would double count), the six previous days from their day
-- files, missing days are skipped
Commands.relationData = function(player, args)
    if not allowed(player, "players") then return end
    if not args or type(args.username) ~= "string" or args.username == "" then return end
    if throttled(player) then
        -- the abort still needs a reply, otherwise the card (opens two
        -- radars in quick succession) stays stuck on the loading text
        toClient(player, "relationData", { username = args.username, throttled = true })
        return
    end
    alignDay()
    local wanted = AegisShared.sanitizeName(args.username)
    local now = AegisShared.realTime()
    local partners = {}

    local function tally(a, b, minutes, today)
        local other
        if a == wanted then
            other = b
        elseif b == wanted then
            other = a
        else
            return
        end
        if minutes <= 0 then return end
        local e = partners[other]
        if not e then
            e = { name = other, total = 0, today = 0 }
            partners[other] = e
        end
        e.total = e.total + minutes
        if today then e.today = e.today + minutes end
    end

    for key, seconds in pairs(acc) do
        local a, b = key:match("^([^|]+)|([^|]+)$")
        if a then tally(a, b, math.floor(seconds / 60), true) end
    end
    for t = 1, 6 do
        local lines = AegisStore.readLines(dayPath(AegisShared.dateShort(now - t * 86400)), 20000)
        if lines then
            for _, line in ipairs(lines) do
                local a, b, minutes = line:match("^([^|]+)|([^|]+)|(%d+)$")
                if a then tally(a, b, tonumber(minutes) or 0, false) end
            end
        end
    end

    local list = {}
    for _, e in pairs(partners) do table.insert(list, e) end
    table.sort(list, function(x, y)
        if x.total ~= y.total then return x.total > y.total end
        return x.name < y.name
    end)
    while #list > 10 do table.remove(list) end
    toClient(player, "relationData", { username = args.username, partners = list })
end

local function onClientCommand(module, command, player, args)
    if module ~= AegisShared.MODULE then return end
    -- suspended admins may not use any Aegis area
    if AegisModeration.isSuspended(player) then return end
    if Commands[command] then Commands[command](player, args) end
end

Events.OnClientCommand.Add(onClientCommand)
