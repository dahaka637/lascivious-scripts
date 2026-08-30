-- Persistent per username player statistics for the player panel.
-- One ledger file with full rewrites guarded against incomplete reads,
-- minute samplers feed distance and lifetime zombie kills, a death
-- listener keeps death count and best life, bandit kills arrive as
-- rate limited client reports.
if isClient() then return end

require "Aegis_Store"
require "Aegis_Log"
require "Aegis_Moderation"
require "Aegis_Roles"

AegisPlayerStats = AegisPlayerStats or {}

local MODULE = "AegisPlayer"
local FILE = AegisStore.ROOT .. "/Player/stats.txt"
local SESSION_MANIFEST = AegisStore.ROOT .. "/Log/PlayerSessions/manifest.txt"

-- anything past this many tiles between two samples is a teleport
local JUMP_MAX = 200
-- most kills one sample may credit. The sampler hangs on EveryOneMinute,
-- which counts GAME minutes and fires several times per real minute, so a
-- three digit gain in one step is always a sync artefact, never play
local MAX_KILL_GAIN = 150
local FLUSH_GAP = 60
local FLUSH_EVERY = 600
local DEATH_DEDUPE = 10
local PLAY_CACHE_TTL = 300

local stats = {}
local loaded = false
local incomplete = false
local dirty = false
local lastFlush = 0

local function nameOk(name)
    return type(name) == "string" and name ~= "" and #name <= 48
        and not name:find("[%c|]")
end

local function round1(v)
    return math.floor((tonumber(v) or 0) * 10 + 0.5) / 10
end

-- ledger line: S|user|deaths|zkills|bandits|pvp|distM|bestHours|bestKills
local function load()
    if loaded then return end
    loaded = true
    stats = {}
    local lines, truncated = AegisStore.readLines(FILE, 20000)
    if lines == nil then
        -- read error: continue empty, retry on next access, and never
        -- rewrite the file from this state
        loaded = false
        incomplete = true
        return
    end
    incomplete = truncated == true
    for _, line in ipairs(lines) do
        local parts = {}
        for field in string.gmatch(line .. "|", "([^|]*)|") do
            table.insert(parts, field)
        end
        if parts[1] == "S" and nameOk(parts[2]) then
            stats[parts[2]] = {
                deaths = tonumber(parts[3]) or 0,
                zkills = tonumber(parts[4]) or 0,
                bandits = tonumber(parts[5]) or 0,
                pvp = tonumber(parts[6]) or 0,
                distM = tonumber(parts[7]) or 0,
                bestHours = tonumber(parts[8]) or 0,
                bestKills = tonumber(parts[9]) or 0,
            }
        end
    end
end

local function save()
    if incomplete then
        print("[Aegis] Player stats write-protected, change not saved")
        return
    end
    local lines = {}
    for user, e in pairs(stats) do
        table.insert(lines, table.concat({
            "S", user,
            tostring(math.floor((e.deaths or 0) + 0.5)),
            tostring(math.floor((e.zkills or 0) + 0.5)),
            tostring(math.floor((e.bandits or 0) + 0.5)),
            tostring(math.floor((e.pvp or 0) + 0.5)),
            tostring(math.floor((e.distM or 0) + 0.5)),
            tostring(round1(e.bestHours)),
            tostring(math.floor((e.bestKills or 0) + 0.5)),
        }, "|"))
    end
    table.sort(lines)
    local content = table.concat(lines, "\n")
    if #lines > 0 then content = content .. "\n" end
    if AegisStore.write(FILE, content) then
        dirty = false
        lastFlush = AegisShared.realTime()
    end
end

-- steady trickles (distance) only set the flag and ride the ten minute
-- flush, discrete events flush at most once a minute
local function setDirty()
    dirty = true
end

local function markDirty()
    dirty = true
    if AegisShared.realTime() - lastFlush >= FLUSH_GAP then save() end
end

local function entry(name)
    load()
    local e = stats[name]
    if not e then
        e = { deaths = 0, zkills = 0, bandits = 0, pvp = 0, distM = 0,
            bestHours = 0, bestKills = 0 }
        stats[name] = e
    end
    return e
end

-- true while this character currently holds an admin access level, same
-- yardstick as the rest of Aegis (levelIsAdmin resolves custom ranks
-- through the role registry instead of trusting the raw level string)
local function isAdminChar(c)
    local level = tostring(c:getAccessLevel() or ""):lower()
    return AegisShared.levelIsAdmin(level) == true
end

-- ---------- minute samplers ----------
local lastPos = {}
local lastKills = {}
-- set by the death listener, read and cleared by the sampler: proves a
-- drop in the kill counter really is a new life and not a foreign mod
-- resetting the same counter mid life
local diedSinceSample = {}

local function samplePlayer(p)
    local name = p:getUsername()
    if not nameOk(name) then return end
    -- server request: admin testing (godmode, teleporting around, farming
    -- kills for a demo) should not have to count. Sandbox default is on
    -- (unchanged behaviour), a server turns it off to stop the recording
    if isAdminChar(p) and not AegisShared.featureOn("PlayerStatsForAdmins") then return end
    local x, y = p:getX(), p:getY()
    if type(x) == "number" and type(y) == "number" then
        local last = lastPos[name]
        if last then
            local dx, dy = x - last.x, y - last.y
            local d = math.sqrt(dx * dx + dy * dy)
            if d > 0.1 and d <= JUMP_MAX then
                local e = entry(name)
                e.distM = e.distM + d
                setDirty()
            end
        end
        lastPos[name] = { x = x, y = y }
    end
    local kills = p:getZombieKills()
    if type(kills) == "number" then
        local base = lastKills[name]
        if base == nil then
            -- first sight this session, credit nothing: everything up to
            -- here was either counted before or predates the ledger
            lastKills[name] = kills
        elseif kills > base then
            -- A JUMP of hundreds in one sample is not someone killing
            -- hundreds of zombies, it is the server side character catching
            -- up with its real values. On a fresh login the server object
            -- can still report 0 while the sampler already looks at it, so
            -- the baseline is taken as 0 and the whole lifetime count of
            -- that character is credited as if freshly earned, once per
            -- login. That is where the impossible leaderboard numbers come
            -- from (user: 4167 on a server where a few hundred is the real
            -- scale). The sampler runs on game minutes, several times a
            -- real minute, so nothing legitimate lands anywhere near this
            -- cap. Over it: re-baseline on the new truth, credit nothing
            local gain = kills - base
            if gain > MAX_KILL_GAIN then
                print("[Aegis] stats: implausible jump for " .. tostring(name) .. " ("
                    .. tostring(base) .. " -> " .. tostring(kills)
                    .. "), treated as a sync catch up, nothing credited")
            else
                local e = entry(name)
                e.zkills = e.zkills + gain
                markDirty()
            end
            lastKills[name] = kills
        elseif kills < base then
            -- A DROP is only credited when we actually saw this character
            -- die since the last sample. It used to credit the new value
            -- unconditionally, on the assumption that every drop means a
            -- fresh life starting at zero. That assumption is not ours to
            -- make: any other mod resetting getZombieKills mid life makes
            -- the same drop look like a new life, and its kills get added
            -- a second time on top of what we already counted (user
            -- report: server said 730, panel showed over 2300, a
            -- DailyKillCount mod was running). Without a death on record
            -- the drop is treated as a correction: re-baseline, credit
            -- nothing, so the ledger can only ever grow from increments we
            -- measured ourselves
            if kills > 0 and diedSinceSample[name] then
                local e = entry(name)
                e.zkills = e.zkills + kills
                markDirty()
            end
            diedSinceSample[name] = nil
            lastKills[name] = kills
        end
    end
end

local function minuteTick()
    local players = nil
    pcall(function() players = getOnlinePlayers() end)
    if players then
        local n = players:size()
        for i = 0, n - 1 do
            pcall(function()
                local p = players:get(i)
                if p then samplePlayer(p) end
            end)
        end
    end
    if dirty and AegisShared.realTime() - lastFlush >= FLUSH_EVERY then save() end
end

Events.EveryOneMinute.Add(minuteTick)

-- ---------- deaths and best life ----------
-- OnCharacterDeath fires for every death, zombies and animals included,
-- so the cheap filter comes first. IsoAnimal extends IsoPlayer in B42,
-- the isAnimal check must run before the instanceof check.
local lastDeath = {}

local function onCharacterDeath(c)
    local isPlayer = c ~= nil and not c:isZombie() and not c:isAnimal()
        and instanceof(c, "IsoPlayer")
    if not isPlayer then return end
    local name = c:getUsername()
    if not nameOk(name) then return end
    if isAdminChar(c) and not AegisShared.featureOn("PlayerStatsForAdmins") then return end
    local now = AegisShared.realTime()
    if lastDeath[name] and now - lastDeath[name] < DEATH_DEDUPE then return end
    lastDeath[name] = now
    local e = entry(name)
    e.deaths = e.deaths + 1
    local hours = tonumber(c:getHoursSurvived()) or 0
    local kills = tonumber(c:getZombieKills()) or 0
    -- close out the kill ledger of this life before the counter resets;
    -- with no earlier sample the tail stays uncounted on purpose, an
    -- unknown base could double count a previous session
    local base = lastKills[name]
    if base ~= nil and kills > base then
        e.zkills = e.zkills + (kills - base)
    end
    -- the dead character lingers with its final counter until respawn,
    -- keeping it as base makes those samples no-ops
    lastKills[name] = kills
    -- the sampler may only credit the next drop because of THIS death
    diedSinceSample[name] = true
    -- best life snapshot, kept as a pair keyed on survival time
    if hours > (e.bestHours or 0) then
        e.bestHours = hours
        e.bestKills = kills
    end
    markDirty()
end

Events.OnCharacterDeath.Add(onCharacterDeath)

-- ---------- bandit kills ----------
-- detection via the mod's own globals instead of a getActivatedMods id
-- scan: the workshop id string differs between installs while the
-- globals load with the mod wherever this file runs
local function banditsActive()
    return BanditServer ~= nil or BanditBrain ~= nil
end

local banditBudget = {}
-- second belt on top of the token bucket: the counter is client fed and
-- deliberately open to everyone (the ledger should be complete before a
-- player ever gets panel access), a day cap bounds inflation
local BANDIT_DAY_CAP = 300

local function banditAllowed(name)
    local now = AegisShared.realTime()
    local b = banditBudget[name] or { tokens = 5, lastAt = now, day = "", n = 0 }
    b.tokens = math.min(5, b.tokens + (now - b.lastAt) * (5 / 60))
    b.lastAt = now
    banditBudget[name] = b
    local day = AegisShared.dateShort(now)
    if b.day ~= day then
        b.day = day
        b.n = 0
    end
    if b.tokens < 1 or b.n >= BANDIT_DAY_CAP then return false end
    b.tokens = b.tokens - 1
    b.n = b.n + 1
    return true
end

function AegisPlayerStats.addBandit(username)
    if not nameOk(username) then return end
    local e = entry(username)
    e.bandits = e.bandits + 1
    markDirty()
end

-- ---------- reads ----------
function AegisPlayerStats.get(username)
    load()
    local e = type(username) == "string" and stats[username] or nil
    return {
        deaths = e and e.deaths or 0,
        zkills = math.floor(((e and e.zkills) or 0) + 0.5),
        bandits = e and e.bandits or 0,
        pvp = e and e.pvp or 0,
        distM = math.floor(((e and e.distM) or 0) + 0.5),
        bestHours = round1(e and e.bestHours or 0),
        bestKills = e and e.bestKills or 0,
    }
end

local TOP_FIELD = { kills = "zkills", dist = "distM", deaths = "deaths", best = "bestHours" }

function AegisPlayerStats.top(kind)
    local field = TOP_FIELD[kind]
    if not field then return {} end
    load()
    local list = {}
    for user, e in pairs(stats) do
        table.insert(list, { user = user, value = tonumber(e[field]) or 0 })
    end
    table.sort(list, function(a, b)
        if a.value ~= b.value then return a.value > b.value end
        return a.user < b.user
    end)
    local out = {}
    for i = 1, math.min(#list, 10) do
        local it = list[i]
        local value = it.value
        if kind == "dist" then
            value = math.floor(value + 0.5)
        elseif kind == "best" then
            value = round1(value)
        end
        local row = { user = it.user, value = value }
        if kind == "best" then
            row.kills = stats[it.user].bestKills or 0
        end
        table.insert(out, row)
    end
    return out
end

-- ---------- playtime ----------
-- sums the closed player session files the log engine writes, plus the
-- running session from the live map; summing reads the area manifest and
-- one file per session, so the result is cached per user
local playCache = {}

function AegisPlayerStats.playtimeHours(username)
    if type(username) ~= "string" or username == "" then return 0 end
    local now = AegisShared.realTime()
    local c = playCache[username]
    if c and now - c.epoch < PLAY_CACHE_TTL then return c.hours end
    local minutes = 0
    local key = AegisShared.sanitizeName(username)
    local entries = AegisStore.readManifest(SESSION_MANIFEST)
    for _, e in ipairs(entries) do
        if e.admin == key then
            local lines = AegisStore.readLastLines(e.path, 40)
            if lines then
                for _, line in ipairs(lines) do
                    -- crash leftovers get a Left line without a duration
                    -- and stay uncounted
                    local mins = line:match("^Left: .* %(duration (%d+) min%)$")
                    if mins then minutes = minutes + (tonumber(mins) or 0) end
                end
            end
        end
    end
    pcall(function()
        local info = AegisLog.sessionInfo(username)
        if info and info.since then
            minutes = minutes + math.max(0, math.floor((now - info.since) / 60))
        end
    end)
    local hours = round1(minutes / 60)
    playCache[username] = { epoch = now, hours = hours }
    return hours
end

-- ---------- client commands ----------
-- the report comes from a future client side counter; counting is not
-- gated on the panel unlock so the ledger is already complete when a
-- player gets panel access later
local Commands = {}

Commands.banditKill = function(player, args)
    local name = player:getUsername()
    if not nameOk(name) then return end
    if not banditsActive() then return end
    if not banditAllowed(name) then return end
    AegisPlayerStats.addBandit(name)
end

-- Correcting the ledger. The counting bugs above inflated numbers that
-- cannot be recomputed afterwards (nothing records WHICH kills were real),
-- so the only honest repair is to clear a value and let it grow again.
-- Admin only, and it goes through the same area right as the rest of the
-- player panel administration
Commands.statsReset = function(player, args)
    if not AegisRoles.canArea(player, "players") then return end
    if not args then return end
    local who = args.user and AegisShared.sanitizeName(args.user) or nil
    local FIELDS = { zkills = true, deaths = true, distM = true,
        bestHours = true, bestKills = true, bandits = true, pvp = true }
    load()
    local admin = player:getUsername() or "?"
    local touched = 0
    local what

    if args.wipe == true then
        -- the whole ledger goes, including names that only appear there
        -- and would otherwise survive a reset of every single field
        for _ in pairs(stats) do touched = touched + 1 end
        stats = {}
        for k in pairs(lastKills) do lastKills[k] = nil end
        who = nil
        what = "everything"
        markDirty()
        save()
    else
        -- one field or a picked set, the old single field call still works
        local wanted = {}
        if type(args.fields) == "table" then
            for _, f in ipairs(args.fields) do
                if FIELDS[tostring(f)] then wanted[tostring(f)] = true end
            end
        elseif FIELDS[tostring(args.field or "")] then
            wanted[tostring(args.field)] = true
        end
        local names = {}
        for f in pairs(wanted) do table.insert(names, f) end
        if #names == 0 then return end
        table.sort(names)
        what = table.concat(names, ",")
        for user, e in pairs(stats) do
            if who == nil or user == who then
                for f in pairs(wanted) do
                    if (e[f] or 0) ~= 0 then
                        e[f] = 0
                        touched = touched + 1
                    end
                end
                -- the running baseline has to go with it, otherwise the next
                -- sample credits the whole gap right back
                if wanted.zkills then lastKills[user] = nil end
            end
        end
        if touched > 0 then
            markDirty()
            save()
        end
    end

    print("[Aegis] stats reset by " .. tostring(admin) .. ": " .. what
        .. ", " .. (who or "everyone") .. ", " .. touched .. " entr(y/ies) cleared")
    AegisLog.write("Actions", admin, who or "all",
        string.format("Statistics reset: %s for %s (%d entries)", what, who or "all players", touched))
    if isServer() then
        sendServerCommand(player, MODULE, "statsReset", { ok = true, what = what, touched = touched })
    else
        triggerEvent("OnServerCommand", MODULE, "statsReset", { ok = true, what = what, touched = touched })
    end
end

local function onClientCommand(module, command, player, args)
    if module ~= MODULE then return end
    -- suspended senders keep no authority in any Aegis area
    if AegisModeration.isSuspended(player) then return end
    if Commands[command] then Commands[command](player, args) end
end

Events.OnClientCommand.Add(onClientCommand)
