-- Discord booster status and code redemption. The bot signs a short code
-- with a secret both sides hold, the player redeems it in the panel. The
-- secret lives in Aegis/Player/boostkey.txt and never leaves the server;
-- without it redemption is switched off, not broken. Status is append only
-- and the newest line of a user wins, so a revoke can lower an earlier
-- grant. Kits gate on it through the @booster pseudo role.
if isClient() then return end

require "Aegis_Store"
require "Aegis_Roles"
require "Aegis_Log"
require "Aegis_Moderation"

AegisBoost = AegisBoost or {}

local PLAYER_MODULE = "AegisPlayer"

local BOOST_FILE = AegisStore.ROOT .. "/Player/boost.txt"
local KEY_FILE = AegisStore.ROOT .. "/Player/boostkey.txt"

local READ_CAP = 20000
local COMPACT_AT = 8000
local LIST_CAP = 300
local MAX_USER = 48
-- 2^64 needs 13 base36 digits, a discord id never needs more
local MAX_DISCORD = 13
-- a plain number field: 36^8 stays far below 2^52, so every step is exact
local MAX_NUM_FIELD = 8
local MAX_CODE = 96
local MIN_SECRET = 8
local MAX_SECRET = 128
local MAX_GRANT_DAYS = 3650
-- guards against a bot bug handing out a century of booster status
local MAX_AHEAD = 157680000
local REDEEM_GAP = 3
local FAIL_MAX = 5
local FAIL_WINDOW = 600
local LOCK_SECONDS = 900

-- username -> { discordId, untilEpoch, grantedEpoch, source }
-- field is untilEpoch, "until" is a Lua keyword
local recs = nil
local recsIncomplete = false
-- nil = not read yet, false = no usable key on disk
local secret = nil

local B36 = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ"
local NUL = string.char(0)

-- ---------- validation ----------

local function nameOk(name)
    return type(name) == "string" and name ~= "" and #name <= MAX_USER
        and not name:find("[%c|]")
end

-- canonical base36, no leading zero beyond a single "0"
local function discordOk(id)
    if type(id) ~= "string" or id == "" or #id > MAX_DISCORD then return false end
    if id:find("[^0-9A-Z]") then return false end
    if #id > 1 and id:sub(1, 1) == "0" then return false end
    return true
end

-- only the tail of a discord id may reach logs or admin lists, the full
-- value stays in boost.txt
local function idTail(id)
    if type(id) ~= "string" or id == "" then return "" end
    return "..." .. id:sub(-4)
end

-- printable ascii only, the bytes go into the signature and must match the
-- bot side exactly
local function secretOk(s)
    if type(s) ~= "string" then return false end
    if #s < MIN_SECRET or #s > MAX_SECRET then return false end
    for i = 1, #s do
        local b = string.byte(s, i)
        if not b or b < 32 or b > 126 then return false end
    end
    return true
end

-- ---------- base36 ----------

local function b36(n)
    n = math.floor(tonumber(n) or 0)
    if n <= 0 then return "0" end
    local out = ""
    while n > 0 do
        local d = n % 36
        out = B36:sub(d + 1, d + 1) .. out
        n = math.floor(n / 36)
    end
    return out
end

local function fromB36(s)
    if type(s) ~= "string" or s == "" or #s > MAX_NUM_FIELD then return nil end
    local n = 0
    for i = 1, #s do
        local d = B36:find(s:sub(i, i), 1, true)
        if not d then return nil end
        n = n * 36 + (d - 1)
    end
    return n
end

-- ---------- signature ----------
-- two accumulators over the bytes of secret+NUL+payload+NUL+secret. Peak
-- intermediate is 2147483646*131, far below 2^52, so the double arithmetic
-- is exact and matches the bot bit for bit. Result is two 6 digit base36
-- blocks, zero padded on the left.

local function mac(payload)
    if type(secret) ~= "string" then return nil end
    local message = secret .. NUL .. payload .. NUL .. secret
    local h1 = 2166136261 % 2147483647
    local h2 = 5381
    for i = 1, #message do
        local b = string.byte(message, i)
        h1 = (h1 * 131 + b) % 2147483647
        h2 = (h2 * 8191 + b) % 1000000007
    end
    local a, c = b36(h1), b36(h2)
    while #a < 6 do a = "0" .. a end
    while #c < 6 do c = "0" .. c end
    return a .. c
end

-- ---------- key file ----------

local function loadKey()
    if secret ~= nil then return end
    secret = false
    local lines = AegisStore.readLines(KEY_FILE, 4)
    for _, l in ipairs(lines or {}) do
        local s = tostring(l or ""):gsub("^%s+", ""):gsub("%s+$", "")
        if secretOk(s) then
            secret = s
            break
        end
    end
end

function AegisBoost.keySet()
    loadKey()
    return type(secret) == "string"
end

function AegisBoost.setKey(raw)
    local s = type(raw) == "string" and (raw:gsub("^%s+", ""):gsub("%s+$", "")) or ""
    if not secretOk(s) then return false end
    if not AegisStore.write(KEY_FILE, s .. "\n") then return false end
    secret = s
    return true
end

-- ---------- status file ----------
-- append only, line: B|user|discordId|untilEpoch|grantedEpoch|source|maxUntil
-- shorter legacy lines stay readable and fall back to safe defaults

local function lineFor(user, r)
    return "B|" .. user .. "|" .. (r.discordId or "") .. "|" .. tostring(math.floor(r.untilEpoch or 0))
        .. "|" .. tostring(math.floor(r.grantedEpoch or 0)) .. "|" .. (r.source == "code" and "code" or "admin")
        .. "|" .. tostring(math.floor(math.max(r.maxUntil or 0, r.untilEpoch or 0)))
end

-- id tombstones: D|discordId|blockedUntil. Written when an id is unlinked
-- while its revocation block still runs, so the block sticks to the ID and
-- cannot be shaken off by redeeming on a second player name
local tombs = nil

local function tombLine(id, untilEpoch)
    return "D|" .. id .. "|" .. tostring(math.floor(untilEpoch or 0))
end

local function parseTomb(line)
    local id, u = tostring(line):match("^D|([A-Z0-9]+)|(%d+)$")
    if not id or not discordOk(id) then return nil end
    local untilEpoch = math.floor(tonumber(u) or 0)
    if untilEpoch <= 0 or untilEpoch > 4102444800 then return nil end
    return id, untilEpoch
end

local function parseLine(line)
    local parts = {}
    for field in string.gmatch(tostring(line) .. "|", "([^|]*)|") do
        table.insert(parts, field)
    end
    if parts[1] ~= "B" then return nil end
    local user = parts[2]
    if not nameOk(user) then return nil end
    local id = parts[3] or ""
    if id ~= "" and not discordOk(id) then id = "" end
    local untilEpoch = math.floor(tonumber(parts[4]) or 0)
    if untilEpoch < 0 or untilEpoch > 4102444800 then untilEpoch = 0 end
    local granted = math.floor(tonumber(parts[5]) or 0)
    if granted < 0 or granted > 4102444800 then granted = 0 end
    local source = parts[6]
    if source ~= "code" then source = "admin" end
    -- high water mark of every expiry ever held: a redeem may only push
    -- past it, so a revoke cannot be undone by replaying the month code.
    -- Missing on legacy lines, then it equals untilEpoch
    local maxUntil = math.floor(tonumber(parts[7]) or 0)
    if maxUntil < 0 or maxUntil > 4102444800 then maxUntil = 0 end
    if maxUntil < untilEpoch then maxUntil = untilEpoch end
    return user, {
        discordId = id, untilEpoch = untilEpoch, grantedEpoch = granted,
        source = source, maxUntil = maxUntil,
    }
end

local function loadRecs()
    if recs then return end
    recs = {}
    tombs = {}
    recsIncomplete = false
    local lines, truncated = AegisStore.readLines(BOOST_FILE, READ_CAP)
    if lines == nil or truncated then
        recsIncomplete = true
        -- once per load, not per tick: the kit side reports "unavailable"
        -- instead of silently treating every booster as expired
        print("[Aegis] boost.txt incomplete or unreadable, booster kits locked until it loads clean")
    end
    -- in file order, the newest line of a user wins so a revoke can lower
    -- an earlier grant
    for _, line in ipairs(lines or {}) do
        local user, rec = parseLine(line)
        if user then
            recs[user] = rec
        else
            local id, blockedUntil = parseTomb(line)
            if id and blockedUntil > (tombs[id] or 0) then tombs[id] = blockedUntil end
        end
    end
    -- monthly renewals append forever; near the read cap the file collapses
    -- to one line per user (the map holds exactly that). Only after a
    -- complete read, a truncated read must never shrink the file
    if not recsIncomplete and lines and #lines > COMPACT_AT then
        local out = {}
        for user, r in pairs(recs) do
            table.insert(out, lineFor(user, r))
        end
        -- expired tombstones may go, live ones must survive the collapse
        local tnow = AegisShared.realTime()
        for id, blockedUntil in pairs(tombs) do
            if blockedUntil > tnow then table.insert(out, tombLine(id, blockedUntil)) end
        end
        table.sort(out)
        local content = table.concat(out, "\n")
        if #out > 0 then content = content .. "\n" end
        AegisStore.write(BOOST_FILE, content)
        print("[Aegis] boost lines compacted: " .. tostring(#lines) .. " -> " .. tostring(#out))
    end
end

-- refused after an incomplete read: appending on top of a partial map would
-- resurrect revoked status on the next compaction (zone registry pattern)
local function store(user, rec)
    if recsIncomplete then
        print("[Aegis] Boost store incomplete, change not saved")
        return false
    end
    if not nameOk(user) then return false end
    if not AegisStore.append(BOOST_FILE, lineFor(user, rec)) then return false end
    recs[user] = rec
    return true
end

-- ---------- exports ----------

function AegisBoost.expiry(name)
    if type(name) ~= "string" or name == "" then return 0 end
    loadRecs()
    local r = recs[name]
    return r and r.untilEpoch or 0
end

-- false while the status file could not be read completely; the kit side
-- shows booster kits as locked instead of dropping them
function AegisBoost.available()
    loadRecs()
    return not recsIncomplete
end

function AegisBoost.isBooster(name)
    if type(name) ~= "string" or name == "" then return false end
    loadRecs()
    local r = recs[name]
    if not r then return false end
    return (r.untilEpoch or 0) > AegisShared.realTime()
end

function AegisBoost.linked(name)
    if type(name) ~= "string" or name == "" then return false end
    loadRecs()
    local r = recs[name]
    return r ~= nil and (r.discordId or "") ~= ""
end

function AegisBoost.list()
    loadRecs()
    local out = {}
    for user, r in pairs(recs) do
        table.insert(out, {
            -- tail only, the admin list is no place for the full id
            user = user, discordId = idTail(r.discordId),
            untilEpoch = r.untilEpoch or 0, grantedEpoch = r.grantedEpoch or 0,
            source = r.source or "admin",
        })
    end
    table.sort(out, function(a, b) return a.user < b.user end)
    while #out > LIST_CAP do table.remove(out) end
    return out
end

-- admin grant, extends from the current expiry so a manual top up on top of
-- a running month is not a downgrade
function AegisBoost.grant(name, days)
    if not nameOk(name) then return false end
    loadRecs()
    local d = math.max(1, math.min(MAX_GRANT_DAYS, math.floor(tonumber(days) or 30)))
    local now = AegisShared.realTime()
    local old = recs[name]
    local base = math.max(now, old and old.untilEpoch or 0)
    return store(name, {
        discordId = old and old.discordId or "",
        untilEpoch = base + d * 86400,
        grantedEpoch = now, source = "admin",
        maxUntil = math.max(old and old.maxUntil or 0, base + d * 86400),
    })
end

-- the link survives a revoke on purpose: the same discord id must not be
-- able to walk over to a second player name afterwards
function AegisBoost.revoke(name)
    if not nameOk(name) then return false end
    loadRecs()
    local old = recs[name]
    if not old then return false end
    -- the high water mark stays: the code of the running month sits below
    -- it and can no longer undo the revoke
    return store(name, {
        discordId = old.discordId or "", untilEpoch = 0,
        grantedEpoch = AegisShared.realTime(), source = "admin",
        maxUntil = math.max(old.maxUntil or 0, old.untilEpoch or 0),
    })
end

function AegisBoost.unlink(name)
    if not nameOk(name) then return false end
    loadRecs()
    local old = recs[name]
    if not old or (old.discordId or "") == "" then return false end
    local now = AegisShared.realTime()
    local block = math.max(old.maxUntil or 0, old.untilEpoch or 0)
    -- unlinking a REVOKED record frees the id for a new name; without a
    -- tombstone the month code would simply be redeemed again over there.
    -- A plain unlink of an active record (hijack repair) writes none, the
    -- rightful owner must be able to redeem right away
    local revoked = (old.untilEpoch or 0) <= now and block > now
    if not store(name, {
        discordId = "", untilEpoch = old.untilEpoch or 0,
        grantedEpoch = old.grantedEpoch or 0, source = old.source or "admin",
        maxUntil = block,
    }) then return false end
    if revoked then
        if AegisStore.append(BOOST_FILE, tombLine(old.discordId, block)) then
            tombs[old.discordId] = math.max(tombs[old.discordId] or 0, block)
        end
    end
    return true
end

-- ---------- redemption ----------

-- per user: a minimum gap plus a lockout after repeated failures, so a code
-- cannot be brute forced through the panel
local attempts = {}

local function gate(name)
    local now = AegisShared.realTime()
    local a = attempts[name]
    if not a then
        a = { at = 0, fails = 0, firstFail = 0, lockedUntil = 0 }
        attempts[name] = a
    end
    if a.lockedUntil > now then return false, "locked" end
    if now - a.at < REDEEM_GAP then return false, "throttle" end
    a.at = now
    return true
end

local function noteFail(name)
    local a = attempts[name]
    if not a then return end
    local now = AegisShared.realTime()
    if a.firstFail == 0 or now - a.firstFail > FAIL_WINDOW then
        a.firstFail = now
        a.fails = 0
    end
    a.fails = a.fails + 1
    if a.fails >= FAIL_MAX then
        a.lockedUntil = now + LOCK_SECONDS
        a.fails = 0
        a.firstFail = 0
    end
end

-- AEG1.<discordId>.<codeExpiryMinutes>.<boostUntilHours>.<mac12>, all base36
-- uppercase. The payload is rebuilt from the parsed fields and both number
-- fields must be canonical, so what gets signed is byte identical to what
-- the bot signed.
local function parseCode(code)
    if type(code) ~= "string" then return nil, "format" end
    local s = code:gsub("%s+", "")
    if s == "" or #s > MAX_CODE then return nil, "format" end
    s = s:upper()
    if s:find("[^0-9A-Z%.]") then return nil, "format" end
    local id, expF, untilF, sig = s:match("^AEG1%.([0-9A-Z]+)%.([0-9A-Z]+)%.([0-9A-Z]+)%.([0-9A-Z]+)$")
    if not id then return nil, "format" end
    if not discordOk(id) then return nil, "format" end
    if #sig ~= 12 then return nil, "format" end
    local expMin = fromB36(expF)
    local untilH = fromB36(untilF)
    if not expMin or not untilH then return nil, "format" end
    if b36(expMin) ~= expF or b36(untilH) ~= untilF then return nil, "format" end
    return {
        discordId = id,
        expiryEpoch = expMin * 60,
        untilEpoch = untilH * 3600,
        payload = "AEG1." .. id .. "." .. expF .. "." .. untilF,
        sig = sig,
    }
end

-- true on success plus the new expiry, otherwise false plus a reason:
-- throttle|locked|nokey|format|sig|expired|idtaken|playerbound|used|error
function AegisBoost.redeem(player, code)
    -- the sender is always the player object, never anything from args
    local name = player and player:getUsername()
    if not nameOk(name) then return false, "error" end
    local pass, why = gate(name)
    if not pass then return false, why end
    loadKey()
    if type(secret) ~= "string" then return false, "nokey" end
    loadRecs()
    if recsIncomplete then return false, "error" end

    local parsed, reason = parseCode(code)
    if not parsed then
        noteFail(name)
        return false, reason
    end
    if mac(parsed.payload) ~= parsed.sig then
        noteFail(name)
        return false, "sig"
    end
    local now = AegisShared.realTime()
    if parsed.expiryEpoch <= now then
        noteFail(name)
        return false, "expired"
    end
    if parsed.untilEpoch > now + MAX_AHEAD then
        noteFail(name)
        return false, "format"
    end
    -- one discord id belongs to exactly one player name
    for user, r in pairs(recs) do
        if user ~= name and (r.discordId or "") == parsed.discordId then
            noteFail(name)
            -- visible trail for the admin: boostUnlink on the holder frees
            -- a hijacked id again
            AegisLog.write("Actions", "Kits", name, "Boost code rejected for " .. name
                .. ": discord id " .. idTail(parsed.discordId) .. " is linked to " .. user)
            return false, "idtaken"
        end
    end
    local old = recs[name]
    local bound = old and old.discordId or ""
    if bound ~= "" and bound ~= parsed.discordId then
        noteFail(name)
        return false, "playerbound"
    end
    -- a revocation block that stuck to the id itself (unlink after revoke)
    if (tombs[parsed.discordId] or 0) >= parsed.untilEpoch then
        noteFail(name)
        return false, "used"
    end
    -- a code that does not push past the high water mark has been used or
    -- was revoked for this month; this replaces a nonce list
    local highWater = old and math.max(old.untilEpoch or 0, old.maxUntil or 0) or 0
    if parsed.untilEpoch <= highWater then
        noteFail(name)
        return false, "used"
    end
    if not store(name, {
        discordId = parsed.discordId, untilEpoch = parsed.untilEpoch,
        grantedEpoch = now, source = "code", maxUntil = parsed.untilEpoch,
    }) then
        return false, "error"
    end
    attempts[name] = nil
    AegisLog.write("Actions", "Kits", name, "Boost redeemed by " .. name
        .. " (discord " .. idTail(parsed.discordId) .. ", until "
        .. AegisShared.timestampReadable(parsed.untilEpoch) .. ")")
    return true, nil, parsed.untilEpoch
end

-- ---------- network ----------

local function toClient(player, module, command, args)
    if isServer() then
        sendServerCommand(player, module, command, args)
    else
        triggerEvent("OnServerCommand", module, command, args)
    end
end

local function senderName(player)
    local name = player and player:getUsername()
    if nameOk(name) then return name end
    return nil
end

local lastReq = {}
local function throttled(name, command, seconds)
    local now = AegisShared.realTime()
    local key = name .. "\n" .. command
    if lastReq[key] and now - lastReq[key] < seconds then return true end
    lastReq[key] = now
    return false
end

local function findOnline(name)
    if not isServer() then
        -- solo runs both sides in one process, the workshop player is the
        -- only possible target
        local p = getPlayer()
        local u = p and p:getUsername()
        if u == name then return p end
        return nil
    end
    local players = getOnlinePlayers()
    if not players then return nil end
    for i = 0, players:size() - 1 do
        local p = players:get(i)
        local u = p and p:getUsername()
        if u == name then return p end
    end
    return nil
end

-- the secret itself never goes out, only whether one is configured
local function pushInfo(player, name)
    if not player or not name then return end
    toClient(player, PLAYER_MODULE, "boostInfo", {
        keySet = AegisBoost.keySet(),
        booster = AegisBoost.isBooster(name),
        untilEpoch = AegisBoost.expiry(name),
        linked = AegisBoost.linked(name),
    })
end

-- status change of a user: refresh his panel strip and his kit list, the
-- @booster gate may have opened or closed a kit for him
local function refreshUser(name)
    local p = findOnline(name)
    if not p then return end
    pushInfo(p, name)
    if AegisKits and AegisKits.pushPlayerList then
        pcall(AegisKits.pushPlayerList, p)
    end
end

AegisBoost.refreshUser = refreshUser

-- ---------- admin commands (area "kits") ----------

local AdminCommands = {}

local function deny(player)
    toClient(player, AegisShared.MODULE, "denied", { area = "kits" })
end

local function pushBoostList(player)
    toClient(player, AegisShared.MODULE, "boostList", {
        entries = AegisBoost.list(), keySet = AegisBoost.keySet(),
    })
end

AdminCommands.boostList = function(player, args)
    if not AegisRoles.canArea(player, "kits") then deny(player) return end
    local name = senderName(player)
    if not name then return end
    if throttled(name, "boostList", 1) then return end
    pushBoostList(player)
end

AdminCommands.boostKey = function(player, args)
    if not AegisRoles.canArea(player, "kits") then deny(player) return end
    local name = senderName(player)
    if not name then return end
    if throttled(name, "boostKey", 2) then return end
    local ok = type(args) == "table" and AegisBoost.setKey(args.key) == true
    if ok then
        -- never log the key itself
        AegisLog.write("Actions", name, name, "Boost key set by " .. name)
    end
    toClient(player, AegisShared.MODULE, "boostKey", { ok = ok, keySet = AegisBoost.keySet() })
    if ok then
        pushBoostList(player)
        -- a fresh key can open the kits page for boosters without the
        -- kits flag; their panels only learn that through a new sync
        pcall(function()
            local players = getOnlinePlayers()
            if not players then return end
            for i = 0, players:size() - 1 do
                local p = players:get(i)
                if p then
                    if AegisPlayerPanel and AegisPlayerPanel.push then
                        pcall(AegisPlayerPanel.push, p)
                    end
                    if AegisKits and AegisKits.pushPlayerList then
                        pcall(AegisKits.pushPlayerList, p)
                    end
                end
            end
        end)
    end
end

AdminCommands.boostGrant = function(player, args)
    if not AegisRoles.canArea(player, "kits") then deny(player) return end
    local name = senderName(player)
    if not name then return end
    if throttled(name, "boostGrant", 1) then return end
    local target = type(args) == "table" and args.user or nil
    local ok = nameOk(target) and AegisBoost.grant(target, args.days) == true
    if ok then
        AegisLog.write("Actions", name, target, "Boost granted by " .. name .. ": " .. target
            .. " until " .. AegisShared.timestampReadable(AegisBoost.expiry(target)))
        refreshUser(target)
    end
    toClient(player, AegisShared.MODULE, "boostGrant", { ok = ok, user = target })
    if ok then pushBoostList(player) end
end

AdminCommands.boostRevoke = function(player, args)
    if not AegisRoles.canArea(player, "kits") then deny(player) return end
    local name = senderName(player)
    if not name then return end
    if throttled(name, "boostRevoke", 1) then return end
    local target = type(args) == "table" and args.user or nil
    local ok = nameOk(target) and AegisBoost.revoke(target) == true
    if ok then
        AegisLog.write("Actions", name, target, "Boost revoked by " .. name .. ": " .. target)
        refreshUser(target)
    end
    toClient(player, AegisShared.MODULE, "boostRevoke", { ok = ok, user = target })
    if ok then pushBoostList(player) end
end

AdminCommands.boostUnlink = function(player, args)
    if not AegisRoles.canArea(player, "kits") then deny(player) return end
    local name = senderName(player)
    if not name then return end
    if throttled(name, "boostUnlink", 1) then return end
    local target = type(args) == "table" and args.user or nil
    local ok = nameOk(target) and AegisBoost.unlink(target) == true
    if ok then
        AegisLog.write("Actions", name, target, "Boost link released by " .. name .. ": " .. target)
        refreshUser(target)
    end
    toClient(player, AegisShared.MODULE, "boostUnlink", { ok = ok, user = target })
    if ok then pushBoostList(player) end
end

-- ---------- player commands ----------

local PlayerCommands = {}

-- solo has no role file, the workshop player always counts as unlocked
local function panelUnlocked(name)
    if not isServer() then return true end
    if not (AegisRoles and AegisRoles.playerPanelFor) then return false end
    local ok, pp = pcall(AegisRoles.playerPanelFor, name)
    return ok and type(pp) == "table"
end

PlayerCommands.boostInfo = function(player, args)
    local name = senderName(player)
    if not name or not panelUnlocked(name) then return end
    if throttled(name, "boostInfo", 2) then return end
    pushInfo(player, name)
end

PlayerCommands.boostRedeem = function(player, args)
    local name = senderName(player)
    if not name or not panelUnlocked(name) then return end
    local code = type(args) == "table" and args.code or nil
    if type(code) ~= "string" then code = "" end
    if #code > MAX_CODE then code = code:sub(1, MAX_CODE) end
    local ok, reason, untilEpoch = AegisBoost.redeem(player, code)
    toClient(player, PLAYER_MODULE, "boostRedeem", {
        ok = ok == true, reason = reason, untilEpoch = untilEpoch or AegisBoost.expiry(name),
    })
    if ok then
        pushInfo(player, name)
        -- a freshly unlocked @booster kit must show up without a reconnect
        if AegisKits and AegisKits.pushPlayerList then
            pcall(AegisKits.pushPlayerList, player)
        end
    end
end

local function onClientCommand(module, command, player, args)
    if module ~= AegisShared.MODULE and module ~= PLAYER_MODULE then return end
    -- suspended senders keep no authority in any Aegis area
    if AegisModeration.isSuspended(player) then return end
    if module == AegisShared.MODULE then
        if AdminCommands[command] then AdminCommands[command](player, args) end
    else
        if PlayerCommands[command] then PlayerCommands[command](player, args) end
    end
end

Events.OnClientCommand.Add(onClientCommand)
