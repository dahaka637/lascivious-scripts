-- Lascivious Systems - Identity V2.
--
-- Central resolver for exact Steam identity.  The economic and faction-side
-- modules must never build a canonical steam:<id> key from IsoPlayer:getSteamID():
-- that Java long crosses Lua as a double and may already be rounded.  SteamID64 is
-- a string identifier here, end to end.

require "LasciviousSystems_SteamId"

LasciviousSystemsIdentity = LasciviousSystemsIdentity or {}
local I = LasciviousSystemsIdentity
local SteamId = LasciviousSystemsSteamId

I.DATA_KEY = "LasciviousSystemsIdentityV2"
I.SCHEMA_VERSION = 2
I.SP_IDENTITY = (SteamId and SteamId.SP_IDENTITY) or "sp:local-save"

local function nowSeconds()
    return (getTimestamp and getTimestamp()) or os.time()
end

local function trim(value)
    if type(value) ~= "string" then return nil end
    value = value:gsub("^%s+", ""):gsub("%s+$", "")
    return value ~= "" and value or nil
end

local function log(message)
    print("[LasciviousIdentity] " .. tostring(message))
end

function I.isTrueSoloSP()
    if SteamId and type(SteamId.isTrueSoloSP) == "function" then
        return SteamId.isTrueSoloSP()
    end
    return not isClient() and not isServer()
end

function I.usernameOf(player)
    if not (player and player.getUsername) then return nil end
    local ok, username = pcall(function() return player:getUsername() end)
    if not ok then return nil end
    username = trim(username)
    if username and #username <= 64 then return username end
    return nil
end

function I.normalizeSteamId(value)
    if type(value) ~= "string" then return nil, "steam_id_must_be_string" end
    local sid = trim(value)
    if not sid then return nil, "invalid_steam_id" end
    sid = sid:match("^[sS][tT][eE][aA][mM]:(%d+)$") or sid
    if sid == "" or sid == "0" or not sid:match("^%d+$") or #sid < 15 or #sid > 20 then
        return nil, "invalid_steam_id"
    end
    if isValidSteamID then
        local ok, valid = pcall(isValidSteamID, sid)
        if ok and valid == false then return nil, "invalid_steam_id" end
    end
    return sid
end

function I.accountKeyFromSteamId(value)
    local sid, err = I.normalizeSteamId(value)
    if not sid then return nil, err end
    return "steam:" .. sid
end

function I.steamIdFromAccountKey(key)
    if type(key) ~= "string" then return nil end
    return I.normalizeSteamId(key)
end

function I.isSteamKey(key)
    return I.steamIdFromAccountKey(key) ~= nil
end

function I.data()
    local data = ModData.getOrCreate(I.DATA_KEY)
    data.schemaVersion = I.SCHEMA_VERSION
    data.byUsername = type(data.byUsername) == "table" and data.byUsername or {}
    data.bySteamKey = type(data.bySteamKey) == "table" and data.bySteamKey or {}
    data.conflicts = type(data.conflicts) == "table" and data.conflicts or {}
    return data
end

local function recordConflict(data, username, oldSteamKey, newSteamKey, oldSource, newSource)
    data.conflicts[#data.conflicts + 1] = {
        username = username,
        oldSteamKey = oldSteamKey,
        newSteamKey = newSteamKey,
        oldSource = oldSource,
        newSource = newSource,
        at = nowSeconds(),
    }
    log(string.format("CONFLICT username=%s old=%s new=%s oldSource=%s newSource=%s",
        tostring(username), tostring(oldSteamKey), tostring(newSteamKey),
        tostring(oldSource), tostring(newSource)))
end

function I.verifiedSteamKeyForUsername(username)
    username = trim(username)
    if not username then return nil end
    local rec = I.data().byUsername[username]
    if type(rec) == "table" and rec.verified == true and I.isSteamKey(rec.steamKey) then
        return rec.steamKey, rec
    end
    return nil
end

function I.registerVerifiedBinding(username, steamId, source)
    username = trim(username)
    local sid, err = I.normalizeSteamId(steamId)
    if not sid then return false, err end

    local steamKey = "steam:" .. sid
    local data = I.data()
    local now = nowSeconds()
    source = source or "unknown"

    if username then
        local old = data.byUsername[username]
        if type(old) == "table" and old.verified == true and old.steamKey ~= steamKey then
            recordConflict(data, username, old.steamKey, steamKey, old.source, source)
            return false, "identity_conflict", steamKey
        end
        data.byUsername[username] = {
            username = username,
            steamId = sid,
            steamKey = steamKey,
            verified = true,
            source = source,
            firstSeenAt = type(old) == "table" and old.firstSeenAt or now,
            lastConfirmedAt = now,
        }
    end

    local inv = data.bySteamKey[steamKey]
    if type(inv) ~= "table" then inv = { steamId = sid, steamKey = steamKey, usernames = {} } end
    inv.steamId = sid
    inv.steamKey = steamKey
    inv.source = source
    inv.lastConfirmedAt = now
    inv.verified = true
    inv.usernames = type(inv.usernames) == "table" and inv.usernames or {}
    if username then
        inv.usernames[username] = {
            verified = true,
            source = source,
            lastConfirmedAt = now,
        }
    end
    data.bySteamKey[steamKey] = inv

    return true, nil, steamKey
end

function I.recordSteamKeySeen(steamId, username, source)
    local sid, err = I.normalizeSteamId(steamId)
    if not sid then return false, err end
    local steamKey = "steam:" .. sid
    local data = I.data()
    local now = nowSeconds()
    local inv = data.bySteamKey[steamKey]
    if type(inv) ~= "table" then inv = { steamId = sid, steamKey = steamKey, usernames = {} } end
    inv.steamId = sid
    inv.steamKey = steamKey
    inv.source = inv.source or source or "observed"
    inv.lastSeenAt = now
    inv.usernames = type(inv.usernames) == "table" and inv.usernames or {}
    username = trim(username)
    if username then
        inv.usernames[username] = inv.usernames[username] or {}
        inv.usernames[username].source = inv.usernames[username].source or source or "observed"
        inv.usernames[username].lastSeenAt = now
    end
    data.bySteamKey[steamKey] = inv
    return true, nil, steamKey
end

local function steamIdFromUsername(username)
    if type(username) ~= "string" or username == "" or not getSteamIDFromUsername then return nil end
    local ok, value = pcall(getSteamIDFromUsername, username)
    if not ok then return nil end
    return I.normalizeSteamId(value)
end

-- Returns accountKey, info.  Exact live engine identity wins when available;
-- otherwise a verified username binding wins; otherwise callers may fall back to
-- their old name:<username> compatibility path.
function I.resolvePlayer(player)
    if not player then return nil end
    if I.isTrueSoloSP() then
        return I.SP_IDENTITY, { accountKey = I.SP_IDENTITY, source = "singleplayer" }
    end

    local username = I.usernameOf(player)
    local sid = steamIdFromUsername(username)
    if sid then
        local steamKey = "steam:" .. sid
        local verifiedKey, verifiedRec = I.verifiedSteamKeyForUsername(username)
        if verifiedKey and verifiedKey ~= steamKey then
            recordConflict(I.data(), username, verifiedKey, steamKey,
                verifiedRec and verifiedRec.source or "verified_binding", "pz_getSteamIDFromUsername")
            I.recordSteamKeySeen(sid, username, "pz_getSteamIDFromUsername_conflict")
            return steamKey, {
                accountKey = steamKey,
                steamId = sid,
                username = username,
                source = "pz_getSteamIDFromUsername_conflict",
                conflict = true,
                oldSteamKey = verifiedKey,
            }
        end
        I.registerVerifiedBinding(username, sid, "pz_getSteamIDFromUsername")
        return steamKey, {
            accountKey = steamKey,
            steamId = sid,
            username = username,
            source = "pz_getSteamIDFromUsername",
        }
    end

    local verifiedKey = I.verifiedSteamKeyForUsername(username)
    if verifiedKey then
        local sid2 = I.steamIdFromAccountKey(verifiedKey)
        I.recordSteamKeySeen(sid2, username, "verified_binding")
        return verifiedKey, {
            accountKey = verifiedKey,
            steamId = sid2,
            username = username,
            source = "verified_binding",
        }
    end

    return nil, { username = username, source = "unresolved" }
end

return I
