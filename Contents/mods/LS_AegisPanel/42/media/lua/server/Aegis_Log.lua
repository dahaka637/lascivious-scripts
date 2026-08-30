-- Log engine: one file per operation under
-- Aegis/Log/<area>/<admin>/<date_time_target>.txt, the area's manifest
-- keeps the list. Also session tracking for players and admins.
if isClient() then return end

require "Aegis_Store"
require "Aegis_Roles"
-- deliberately NOT requiring Aegis_Moderation: that file requires this one
-- back and the pair produced a recursive require warning in every server
-- log. AegisModeration is only used inside command handlers, and by then
-- every file is loaded

AegisLog = AegisLog or {}

local validAreas = {}
for _, b in ipairs(AegisShared.LOG_AREAS) do validAreas[b] = true end

local function manifestPath(area)
    return AegisStore.ROOT .. "/Log/" .. area .. "/manifest.txt"
end

-- known paths per area so not every write has to read the manifest
local knownPaths = {}

local function pathKnown(area, path)
    if not knownPaths[area] then
        knownPaths[area] = {}
        for _, e in ipairs(AegisStore.readManifest(manifestPath(area))) do
            knownPaths[area][e.path] = true
        end
    end
    return knownPaths[area][path] == true
end

-- public entry for all suite features: writes one operation.
-- Moderation and session areas get one file per operation;
-- "Actions" collects into one daily file per admin, otherwise
-- high-frequency entries (power toggles, relays) flood the manifest with
-- per-second files and past 50000 manifest lines rotation would stall
function AegisLog.write(area, adminName, targetName, text)
    if not validAreas[area] then return nil end
    local admin = AegisShared.sanitizeName(adminName)
    local target = AegisShared.sanitizeName(targetName)
    local now = AegisShared.realTime()
    local dailyJournal = area == "Actions"
    local path
    if dailyJournal then
        path = AegisStore.ROOT .. "/Log/" .. area .. "/" .. admin .. "/"
            .. AegisShared.dateShort(now) .. ".txt"
    else
        path = AegisStore.ROOT .. "/Log/" .. area .. "/" .. admin .. "/"
            .. AegisShared.timestamp(now) .. "_" .. target .. ".txt"
    end

    if not pathKnown(area, path) then
        AegisStore.write(path, "Time: " .. AegisShared.timestampReadable(now) .. "\n"
            .. "Area: " .. area .. "\n"
            .. "Admin: " .. admin .. "\n"
            .. (dailyJournal and "" or ("Target: " .. target .. "\n")) .. "\n")
        AegisStore.appendManifest(manifestPath(area), {
            status = "aktiv", epoch = now, path = path, admin = admin,
            target = dailyJournal and AegisShared.dateShort(now) or target,
        })
        knownPaths[area][path] = true
    end
    if text and text ~= "" then
        if dailyJournal then
            text = AegisShared.timeShort(now) .. "  [" .. target .. "]  " .. text
        end
        AegisStore.append(path, text)
    end
    return path
end

-- ---------- Sessions ----------
-- The server keeps an online map and writes one session file per player:
-- join when they appear, leave with duration on the diff.
-- The map is mirrored into a status file so a server stop does not
-- leave open sessions dangling forever.
local online = {}

local SESSION_STATUS = AegisStore.ROOT .. "/Status/sessions.txt"
local leftoversChecked = false

local function saveOnline()
    local lines = {}
    for name, info in pairs(online) do
        table.insert(lines, table.concat({
            name:gsub("|", "_"), tostring(info.since or 0), info.file or "", info.adminFile or "",
        }, "|"))
    end
    local content = table.concat(lines, "\n")
    if #lines > 0 then content = content .. "\n" end
    AegisStore.write(SESSION_STATUS, content)
end

-- after a restart, stranded session files get an ending
local function closeLeftovers()
    if leftoversChecked then return end
    leftoversChecked = true
    local lines = AegisStore.readLines(SESSION_STATUS, 2000)
    if not lines or #lines == 0 then return end
    for _, line in ipairs(lines) do
        local _, _, file, adminFile = line:match("^([^|]*)|([^|]*)|([^|]*)|([^|]*)$")
        if file and file ~= "" then
            AegisStore.append(file, "Left: server stop, exact time unknown")
        end
        if adminFile and adminFile ~= "" then
            AegisStore.append(adminFile, "Left: server stop, exact time unknown")
        end
    end
    AegisStore.write(SESSION_STATUS, "")
end

local function sessionStart(p)
    -- close stranded files in solo too, the minute diff does not run
    -- there (flag makes the call idempotent)
    closeLeftovers()
    local name = p:getUsername()
    local now = AegisShared.realTime()
    local isAdmin = AegisRoles.isVanillaAdmin(p) or AegisRoles.hasAccess(p)
    online[name] = { since = now, admin = isAdmin }

    online[name].file = AegisLog.write("PlayerSessions", name, "Session",
        "Joined: " .. AegisShared.timestampReadable(now))
    if isAdmin then
        online[name].adminFile = AegisLog.write("AdminSessions", name, "Session",
            "Joined: " .. AegisShared.timestampReadable(now))
    end
    saveOnline()
    AegisRoles.pushRights(p)
end

local function sessionEnd(name, info)
    local now = AegisShared.realTime()
    local minutes = math.max(0, math.floor((now - (info.since or now)) / 60))
    local line = "Left: " .. AegisShared.timestampReadable(now) .. " (duration " .. minutes .. " min)"
    if info.file then AegisStore.append(info.file, line) end
    if info.adminFile then AegisStore.append(info.adminFile, line) end
end

-- one activity line into the player's OWN session file. Deliberately not a
-- log area of its own: these are player activities and belong with the
-- player, a separate area per activity kind would drown the log page
--. Silently does nothing before the session file exists,
-- an activity without a session is not worth creating a file for
function AegisLog.playerActivity(name, text)
    if type(name) ~= "string" or type(text) ~= "string" or text == "" then return end
    local info = online[name]
    if not info or not info.file then return end
    AegisStore.append(info.file, AegisShared.timeShort(AegisShared.realTime()) .. "  " .. text)
end

local function sessionDiff()
    if not isServer() then return end
    closeLeftovers()
    local players = getOnlinePlayers()
    local present = {}
    if players then
        for i = 0, players:size() - 1 do
            local p = players:get(i)
            if p then
                local name = p:getUsername()
                present[name] = true
                if not online[name] then sessionStart(p) end
            end
        end
    end
    local departed = nil
    for name, info in pairs(online) do
        if not present[name] then
            sessionEnd(name, info)
            departed = departed or {}
            table.insert(departed, name)
        end
    end
    if departed then
        for _, name in ipairs(departed) do online[name] = nil end
        saveOnline()
    end
end

Events.EveryOneMinute.Add(sessionDiff)

-- session data of an online player, for moderation evidence bundles
function AegisLog.sessionInfo(name)
    return online[name]
end

-- ---------- Client commands ----------
local function deny(player, area)
    if isServer() then
        sendServerCommand(player, AegisShared.MODULE, "denied", { area = area })
    end
end

local function reply(player, command, args)
    if isServer() then
        sendServerCommand(player, AegisShared.MODULE, command, args)
    elseif AegisLogClient then
        AegisLogClient.receive(command, args)
    end
end

local MAX_ENTRIES = 200
local MAX_LINES = 300

-- cap read requests per player and kind at 1/s: logList parses the
-- whole area manifest, unthrottled a client can flood the server tick
-- with file IO (the regular page poll sits at 2 s and passes through)
local lastRequest = {}
local function requestThrottled(player, kind)
    local name = player and player:getUsername() or "?"
    local key = name .. "|" .. kind
    local now = AegisShared.realTime()
    if lastRequest[key] and now - lastRequest[key] < 1 then return true end
    lastRequest[key] = now
    return false
end

local Commands = {}

-- panel open and close lands in the admin session file. Only for the
-- entitled, throttled and append-only, else a tampered client floods the disk
Commands.panelSession = function(player, args)
    if not (AegisRoles.isVanillaAdmin(player) or AegisRoles.hasAccess(player)) then return end
    local name = player:getUsername()
    local info = online[name]
    if not info then
        sessionStart(player)
        info = online[name]
    end
    if not info then return end
    local now = AegisShared.realTime()
    -- only throttle identical repeats: a quick open-close pair must write
    -- both lines, otherwise the session file ends on an open panel
    -- without a closing line
    local state = (args and args.open) and "open" or "closed"
    if info.panelState == state and info.panelEpoch and now - info.panelEpoch < 2 then return end
    info.panelEpoch = now
    info.panelState = state
    -- whoever became admin only during the session gets their file now
    if not info.adminFile then
        info.adminFile = AegisLog.write("AdminSessions", name, "Session",
            "Joined: " .. AegisShared.timestampReadable(info.since or now))
    end
    if not info.adminFile then return end
    local line = (args and args.open and "Panel opened: " or "Panel closed: ")
        .. AegisShared.timestampReadable(now)
    AegisStore.append(info.adminFile, line)
end

Commands.logList = function(player, args)
    if not AegisRoles.canArea(player, "logs") then deny(player, "logs") return end
    local area = args and args.area
    if not validAreas[area] then return end
    if requestThrottled(player, "list") then return end
    local entries, incomplete = AegisStore.readManifest(manifestPath(area))
    -- past 50000 manifest lines readLines only reads the file start, the
    -- newest entries sit at the end and are then missing from the sort;
    -- the caller gets the flag instead of a falsely complete list
    if incomplete then
        print("[Aegis] Log manifest " .. area .. " is over 50000 lines, list sorted incompletely")
    end
    table.sort(entries, function(a, b) return a.epoch > b.epoch end)
    local list = {}
    for i = 1, math.min(#entries, MAX_ENTRIES) do
        local e = entries[i]
        table.insert(list, { epoch = e.epoch, path = e.path, admin = e.admin, target = e.target, status = e.status })
    end
    reply(player, "logList", { area = area, entries = list, total = #entries, incomplete = incomplete })
end

Commands.logRead = function(player, args)
    if not AegisRoles.canArea(player, "logs") then deny(player, "logs") return end
    local path = args and args.path
    if type(path) ~= "string" or not AegisStore.pathOk(path) then return end
    if path:sub(1, #AegisStore.ROOT + 5) ~= AegisStore.ROOT .. "/Log/" then return end
    if requestThrottled(player, "file") then return end
    -- the last lines instead of the first: for daily journals and running
    -- sessions the end is the live part
    local lines = AegisStore.readLastLines(path, MAX_LINES) or {}
    reply(player, "logRead", { path = path, lines = lines })
end

local function onClientCommand(module, command, player, args)
    if module ~= AegisShared.MODULE then return end
    -- suspended admins may not use any Aegis area anymore
    if AegisModeration.isSuspended(player) then return end
    -- catch joins event-driven, the minute diff is too coarse otherwise;
    -- in solo this is the only session start (no diff run). Guarded:
    -- an error here must not silently take every log command down with it
    if player and not online[player:getUsername()] then
        local ok, err = pcall(sessionStart, player)
        if not ok then
            print("[Aegis] Session start failed: " .. tostring(err))
            online[player:getUsername()] = { since = AegisShared.realTime() }
        end
    end
    if Commands[command] then Commands[command](player, args) end
end

Events.OnClientCommand.Add(onClientCommand)
