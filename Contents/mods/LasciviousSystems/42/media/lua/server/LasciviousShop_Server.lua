if isClient() then return end

require "LasciviousShop_Shared"
require "LasciviousShop_Catalog"
require "GoMCompat"
require "LasciviousSystems_SteamId"

local LS = LasciviousShop
local Commands = {}
local validProducts = {}
local invalidProductsForClient = {}
local invalidProductsHash = ""
local catalogValidated = false
local lastTickAt = 0
local lastRuntimeConfigHash = nil
local TICK_SECONDS = 5
local MAX_CART_LINES = 40
local MAX_CART_UNITS = 50
local MAX_LINE_QUANTITY = 50
local MAX_RECENT_REQUESTS = 20
local MAX_RECENT_TRANSFERS = 20
local MAX_API_CREDIT_AMOUNT = 10000000
local MAX_VEHICLE_LINES = LS.MAX_VEHICLES_PER_PURCHASE or 4
local DEBUG_STARTING_CREDITS = 10000
local REQUEST_STATE_COOLDOWN_SECONDS = 1
local PURCHASE_COOLDOWN_SECONDS = 1
local DEDUP_REPLAY_COOLDOWN_SECONDS = 1
local TRANSFER_LIST_COOLDOWN_SECONDS = 1
local lastStateRequestAt = {}
local lastPurchaseAttemptAt = {}
local lastPurchaseReplayAt = {}
local lastTransferListRequestAt = {}

local function nowSeconds()
    return (getTimestamp and getTimestamp()) or os.time()
end

local function randomInt(minValue, maxValue)
    minValue, maxValue = math.floor(minValue), math.floor(maxValue)
    if maxValue <= minValue then return minValue end
    if ZombRand then return minValue + ZombRand(maxValue - minValue + 1) end
    return math.random(minValue, maxValue)
end

local function finiteNumber(value, fallback)
    return LS.finiteNumber(value, fallback)
end

local function integerOrNil(value)
    value = finiteNumber(value, nil)
    return value ~= nil and math.floor(value) or nil
end

local function tooSoon(bucket, key, interval)
    if not key then return false end
    local now = nowSeconds()
    local previous = bucket[key]
    bucket[key] = now
    -- A wall-clock correction backwards must not freeze this identity behind a
    -- future timestamp until the clock catches up.
    return previous ~= nil and now >= previous and now - previous < interval
end

local function toClient(player, command, args)
    if isServer() then
        sendServerCommand(player, LS.MODULE, command, args or {})
    else
        triggerEvent("OnServerCommand", LS.MODULE, command, args or {})
    end
end

local function eachOnlinePlayer(fn)
    if isServer() and getOnlinePlayers then
        local players = getOnlinePlayers()
        if not players then return end
        for i = 0, players:size() - 1 do
            local player = players:get(i)
            if player then fn(player) end
        end
        return
    end
    local player = getPlayer and getPlayer() or nil
    if player then fn(player) end
end

local function dataStore()
    local data = ModData.getOrCreate(LS.DATA_KEY)
    data.schema = 1
    data.accounts = type(data.accounts) == "table" and data.accounts or {}
    data.usernameIndex = type(data.usernameIndex) == "table" and data.usernameIndex or {}
    data.offers = type(data.offers) == "table" and data.offers or {}
    data.offerIds = type(data.offerIds) == "table" and data.offerIds or {}
    data.offerExpiresAt = math.max(0, finiteNumber(data.offerExpiresAt, 0))
    data.offerRevision = math.max(0, integerOrNil(data.offerRevision) or 0)
    -- Credits API pending-grant queue (see "Public credits API" section
    -- below): { [accountKey] = { {amount=, reason=, queuedAt=}, ... } }.
    data.pendingCredits = type(data.pendingCredits) == "table" and data.pendingCredits or {}
    -- Persistent receipts for one-shot external rewards, e.g. Discord
    -- verification. Keyed by rewardType .. ":" .. canonical account key.
    data.externalRewards = type(data.externalRewards) == "table" and data.externalRewards or {}
    return data
end

-- Canonical shape for a brand-new account record. Pulled out once so
-- ensureAccount, ensureAccountByUsername and the credits API's own
-- key-based creation path (applyCreditsToKey) can never quietly drift out
-- of sync with each other on what a "new" account looks like.
local function newAccountRecord()
    return {
        initialized = false,
        balance = 0,
        lastKills = 0,
        lastHours = 0,
        lifetimeEarned = 0,
        lifetimeSpent = 0,
        recentResults = {},
        recentOrder = {},
        recentTransfers = {},
        recentTransferOrder = {},
        debugCreditsGranted = false,
    }
end

-- Keep ambiguous cross-world side effects forever (or until an administrator
-- reconciles them).  A normal bounded replay cache may forget old completed
-- requests, but evicting a `processing` marker would make the same requestId
-- executable again even though its item/vehicle/credit side effect may already
-- exist.  The guarded pass also terminates on corrupt histories containing only
-- protected markers instead of spinning forever.
local function trimHistoryPreservingProcessing(map, order, limit)
    if type(map) ~= "table" or type(order) ~= "table" then return end
    local protectedSeen = 0
    while #order > limit and protectedSeen < #order do
        local old = table.remove(order, 1)
        local value = map[old]
        if type(value) == "table" and value.status == "processing" then
            table.insert(order, old)
            protectedSeen = protectedSeen + 1
        else
            if type(old) == "string" then map[old] = nil end
            protectedSeen = 0
        end
    end
end

local function normalizeAccountRecord(rec)
    if type(rec) ~= "table" then rec = newAccountRecord() end
    rec.initialized = rec.initialized == true
    rec.balance = LS.roundCredits(rec.balance)
    rec.lastKills = math.max(0, integerOrNil(rec.lastKills) or 0)
    rec.lastHours = math.max(0, integerOrNil(rec.lastHours) or 0)
    rec.lifetimeEarned = LS.roundCredits(rec.lifetimeEarned)
    rec.lifetimeSpent = LS.roundCredits(rec.lifetimeSpent)
    rec.recentResults = type(rec.recentResults) == "table" and rec.recentResults or {}
    rec.recentOrder = type(rec.recentOrder) == "table" and rec.recentOrder or {}
    rec.recentTransfers = type(rec.recentTransfers) == "table" and rec.recentTransfers or {}
    rec.recentTransferOrder = type(rec.recentTransferOrder) == "table" and rec.recentTransferOrder or {}
    rec.debugCreditsGranted = rec.debugCreditsGranted == true
    trimHistoryPreservingProcessing(rec.recentResults, rec.recentOrder, MAX_RECENT_REQUESTS)
    trimHistoryPreservingProcessing(rec.recentTransfers, rec.recentTransferOrder, MAX_RECENT_TRANSFERS)
    return rec
end

local function mergeHistory(target, source, mapField, orderField, limit)
    local targetMap, targetOrder = target[mapField], target[orderField]
    local sourceMap, sourceOrder = source[mapField], source[orderField]
    for _, requestId in ipairs(sourceOrder) do
        local value = sourceMap[requestId]
        if type(requestId) == "string" and type(value) == "table" and targetMap[requestId] == nil then
            targetMap[requestId] = value
            targetOrder[#targetOrder + 1] = requestId
        end
    end
    trimHistoryPreservingProcessing(targetMap, targetOrder, limit)
end

-- A username-only API grant may create name:<username> before that player has
-- ever connected. Once Steam identity becomes available, move/merge that exact
-- fallback record instead of silently orphaning its balance. We intentionally
-- never merge one steam:* key into another: a reused username must not transfer
-- the previous Steam user's wallet to a different account.
local function mergeFallbackAccount(target, fallback)
    target = normalizeAccountRecord(target)
    fallback = normalizeAccountRecord(fallback)
    target.balance = LS.roundCredits(target.balance + fallback.balance)
    target.lifetimeEarned = LS.roundCredits(target.lifetimeEarned + fallback.lifetimeEarned)
    target.lifetimeSpent = LS.roundCredits(target.lifetimeSpent + fallback.lifetimeSpent)
    target.lastKills = math.max(target.lastKills, fallback.lastKills)
    target.lastHours = math.max(target.lastHours, fallback.lastHours)
    target.initialized = target.initialized or fallback.initialized
    target.debugCreditsGranted = target.debugCreditsGranted or fallback.debugCreditsGranted
    target.updatedAt = math.max(finiteNumber(target.updatedAt, 0), finiteNumber(fallback.updatedAt, 0))
    mergeHistory(target, fallback, "recentResults", "recentOrder", MAX_RECENT_REQUESTS)
    mergeHistory(target, fallback, "recentTransfers", "recentTransferOrder", MAX_RECENT_TRANSFERS)
    return target
end

-- Applies (and clears) any pending grants queued under `key` itself, plus
-- any of `extraKeys` -- a grant queued back when only a username was known
-- (LS.queueCredits resolving a never-seen username to a "name:" key) must
-- still reach the player once they log in for real and end up keyed by
-- Steam ID instead, which is a DIFFERENT key.
--
-- Deliberately safe to call repeatedly, not just on first account creation:
-- the Discord/HTTP bridge can enqueue under steam:<id> while the shop still
-- has a live name:<username>/legacy account from an older resolution path.
-- Draining on every ensureAccount() makes that failure mode self-healing
-- instead of leaving credits stuck in pendingCredits forever.
local function flushPendingCredits(rec, key, extraKeys)
    local data = dataStore()
    local keys = { key }
    if extraKeys then
        for _, k in ipairs(extraKeys) do
            if k ~= key then table.insert(keys, k) end
        end
    end
    for _, k in ipairs(keys) do
        local list = data.pendingCredits[k]
        if type(list) == "table" and #list > 0 then
            local total = 0
            for _, entry in ipairs(list) do
                local amount = type(entry) == "table" and finiteNumber(entry.amount, 0) or 0
                if amount > 0 and amount <= MAX_API_CREDIT_AMOUNT then
                    rec.balance = LS.roundCredits(rec.balance + amount)
                    rec.lifetimeEarned = LS.roundCredits(rec.lifetimeEarned + amount)
                    total = total + amount
                end
            end
            rec.updatedAt = nowSeconds()
            rec.source = "api_queued_grant_flush"
            LS.log(string.format("applied %d queued grant(s) totalling %s credits queued for '%s' (account '%s')",
                #list, LS.formatCredits(total), k, key))
            data.pendingCredits[k] = nil
        end
    end
end

local function usernameOf(player)
    if not player or not player.getUsername then return nil end
    local ok, username = pcall(function() return player:getUsername() end)
    if ok and type(username) == "string" and username ~= "" and #username <= 64 then return username end
    return nil
end

local function exactSteamKeyFromUsername(username)
    if type(username) ~= "string" or username == "" or not getSteamIDFromUsername then return nil end
    local ok, value = pcall(getSteamIDFromUsername, username)
    if not ok then return nil end
    local sid = LasciviousSystemsSteamId.isValid(value)
    return sid and ("steam:" .. sid) or nil
end

local function accountId(player)
    if not player then return nil end
    local username = usernameOf(player)
    local exactKey = exactSteamKeyFromUsername(username)
    if exactKey then return exactKey end
    local key = LasciviousSystemsSteamId.accountKey(player)
    if key then return key end
    return username and ("name:" .. username) or nil
end

local function ensureAccount(player)
    local key = accountId(player)
    local username = usernameOf(player)
    local legacyKey = player and LasciviousSystemsSteamId.legacyAccountKey(player, key) or nil
    local data = dataStore()
    if not key and username and type(data.usernameIndex[username]) == "string" then
        key = data.usernameIndex[username]
    end
    if not key then return nil, nil end
    local rec = data.accounts[key]
    local createdOrMigrated = false
    local migratedFrom = {}

    -- Old-precision-bug key (steam:<rounded>, written by tostring(long)
    -- before this fix existed) for the SAME player as `key`. Safe to merge
    -- steam:*->steam:* here specifically -- see LasciviousSystems_SteamId.lua's
    -- legacyAccountKey() comment for why this doesn't reopen the
    -- username-reuse concern the fallbackKey merge below has to avoid.
    if legacyKey and legacyKey ~= key and type(data.accounts[legacyKey]) == "table" then
        if rec == data.accounts[legacyKey] then
            rec = normalizeAccountRecord(rec)
        elseif type(rec) == "table" then
            rec = mergeFallbackAccount(rec, data.accounts[legacyKey])
        else
            rec = normalizeAccountRecord(data.accounts[legacyKey])
        end
        data.accounts[key] = rec
        data.accounts[legacyKey] = nil
        createdOrMigrated = true
        table.insert(migratedFrom, legacyKey)
        LS.log(string.format("migrated legacy-precision account '%s' to '%s'", legacyKey, key))
    end

    local fallbackKey = username and ("name:" .. username) or nil
    if fallbackKey and fallbackKey ~= key and type(data.accounts[fallbackKey]) == "table" then
        if rec == data.accounts[fallbackKey] then
            rec = normalizeAccountRecord(rec)
        elseif type(rec) == "table" then
            rec = mergeFallbackAccount(rec, data.accounts[fallbackKey])
        else
            rec = normalizeAccountRecord(data.accounts[fallbackKey])
        end
        data.accounts[key] = rec
        data.accounts[fallbackKey] = nil
        createdOrMigrated = true
        table.insert(migratedFrom, fallbackKey)
        LS.log(string.format("migrated fallback account '%s' to '%s'", fallbackKey, key))
    end

    if not rec then
        rec = newAccountRecord()
        data.accounts[key] = rec
        createdOrMigrated = true
    end
    rec = normalizeAccountRecord(rec)
    data.accounts[key] = rec
    if username then data.usernameIndex[username] = key end
    if legacyKey and legacyKey ~= key then table.insert(migratedFrom, legacyKey) end
    if fallbackKey and fallbackKey ~= key then table.insert(migratedFrom, fallbackKey) end
    flushPendingCredits(rec, key, #migratedFrom > 0 and migratedFrom or nil)
    return rec, key
end

-- Resolve/create an account purely by username, for contexts with no live player
-- object (crediting an offline faction owner on auto-disband, or the faction
-- tribute treasury deposit/withdraw flow, which only ever has a username). Reuses
-- the account a real login already created via usernameIndex when one exists;
-- falls back to synthesizing "name:"..username exactly like accountId() does when
-- no Steam-linked account exists yet. ensureAccount() migrates that exact
-- name:<username> fallback into the Steam-keyed record on first login.
local function ensureAccountByUsername(username)
    if type(username) ~= "string" or username == "" or #username > 64 then return nil, nil end
    local data = dataStore()
    local key = type(data.usernameIndex[username]) == "string" and data.usernameIndex[username] or nil
    local usingFallback = false
    if not key then
        key = "name:" .. username
        usingFallback = true
    end
    data.usernameIndex[username] = key
    local rec = data.accounts[key]
    if not rec then
        rec = newAccountRecord()
        data.accounts[key] = rec
        if usingFallback then
            LS.log("WARNING: created fallback account for offline user '" .. username
                .. "' (no prior shop account; it will migrate on Steam-authenticated login)")
        end
        flushPendingCredits(rec, key, { "name:" .. username })
    end
    rec = normalizeAccountRecord(rec)
    data.accounts[key] = rec
    flushPendingCredits(rec, key, { "name:" .. username })
    return rec, key
end

-- Cross-mod boundary for the faction tribute feature (LasciviousFactionsSystem):
-- grant/spend a Shop balance purely by username. Both are plain synchronous
-- mutations -- callers on the other side of the boundary must not yield between
-- calling these and their own faction-side mutation, or the two ledgers can drift.
function LS.grantCredits(username, amount, reason)
    amount = finiteNumber(amount, nil)
    if not amount or amount <= 0 or amount > MAX_API_CREDIT_AMOUNT then return false end
    local rec = ensureAccountByUsername(username)
    if not rec then return false end
    if rec.balance + amount > LS.MAX_CREDITS then return false end
    rec.balance = LS.roundCredits(rec.balance + amount)
    rec.lifetimeEarned = LS.roundCredits(rec.lifetimeEarned + amount)
    rec.updatedAt = nowSeconds()
    rec.source = reason or "external_grant"
    LS.pushStateToUsername(username)
    LS.log(string.format("grant: +%s credits to '%s' (%s)", LS.formatCredits(amount), username,
        tostring(reason or "external_grant")))
    return true
end

-- Hard-fails on insufficient balance; never applies a partial spend.
function LS.spendCredits(username, amount, reason)
    amount = finiteNumber(amount, nil)
    if not amount or amount <= 0 or amount > MAX_API_CREDIT_AMOUNT then return false, "invalid_amount" end
    local rec = ensureAccountByUsername(username)
    if not rec then return false, "invalid_player" end
    if rec.balance + 0.0001 < amount then return false, "insufficient_credits" end
    rec.balance = LS.roundCredits(rec.balance - amount)
    rec.lifetimeSpent = LS.roundCredits(rec.lifetimeSpent + amount)
    rec.updatedAt = nowSeconds()
    rec.source = reason or "external_spend"
    LS.pushStateToUsername(username)
    LS.log(string.format("spend: -%s credits from '%s' (%s)", LS.formatCredits(amount), username,
        tostring(reason or "external_spend")))
    return true
end

-- ===================================================================
-- Public credits API, richer-identity layer. LS.grantCredits/LS.spendCredits
-- above stay exactly as they were (username-only, unchanged signatures and
-- behaviour) because LasciviousFactionsSystem's tribute feature already
-- depends on them in production -- this section is additive, not a
-- replacement. Everything here is meant to be a stable boundary other
-- server-side mods (and anything built later on top of a chat/admin
-- command, for genuinely external triggers) can call directly.
--
-- IDENTITY accepted by every function below is any of:
--   - a plain username string          (same resolution LS.grantCredits uses)
--   - a live IsoPlayer object
--   - { steamId = "765611..." }        (works even if that person has never logged in)
--   - { username = "SomeUser" }
--
-- Every mutating function returns (ok, reason, extra):
--   ok      boolean
--   reason  nil on success; short machine-readable string on failure:
--           invalid_identity, invalid_amount, unknown_identity,
--           insufficient_credits, self_target, queue_full,
--           recipient_balance_limit
--   extra   table, currently only { queued = true/false } where relevant
--
-- Grants can be QUEUED (no existing account yet, e.g. a Steam ID that has
-- never logged in) -- applied automatically the moment that identity's
-- account is actually created (see flushPendingCredits above). Deducting
-- and reading a balance never queue: you cannot take from, or meaningfully
-- ask the balance of, an account that doesn't exist yet.
-- ===================================================================

-- Direct mutation on an ALREADY-RESOLVED account key, bypassing username
-- resolution entirely. Only for code in this section that already knows
-- the canonical key -- everything else should go through
-- ensureAccount/ensureAccountByUsername/LS.grantCredits instead.
local function applyCreditsToKey(key, delta, reason)
    local data = dataStore()
    local rec = data.accounts[key]
    if not rec then
        rec = newAccountRecord()
    end
    rec = normalizeAccountRecord(rec)
    data.accounts[key] = rec
    rec.balance = LS.roundCredits(rec.balance + delta)
    if delta > 0 then
        rec.lifetimeEarned = LS.roundCredits(rec.lifetimeEarned + delta)
    else
        rec.lifetimeSpent = LS.roundCredits(rec.lifetimeSpent - delta)
    end
    rec.updatedAt = nowSeconds()
    rec.source = reason
    return rec
end

-- Normalizes any accepted identity shape into this mod's canonical account
-- key ("steam:<id>" / "name:<username>"), consulting usernameIndex so a
-- plain username that already resolved to a Steam-based key on a real
-- login keeps using that same key. Pure lookup -- never creates anything,
-- and safe to call with garbage input (a live player object is duck-typed
-- and probed inside a pcall, same convention as usernameOf/accountId).
local function resolveIdentityKey(identity)
    if identity == nil then return nil end
    if type(identity) == "string" then
        if identity == "" or #identity > 64 then return nil end
        local indexed = dataStore().usernameIndex[identity]
        return type(indexed) == "string" and indexed or ("name:" .. identity)
    end
    local ok, result = pcall(function()
        if identity.getUsername then
            local key = accountId(identity)
            if key then return key end
            local username = usernameOf(identity)
            return username and resolveIdentityKey(username) or nil
        end
        if identity.steamId ~= nil then
            local sid = LasciviousSystemsSteamId.isValid(identity.steamId)
            if sid then return "steam:" .. sid end
        end
        if type(identity.username) == "string" and identity.username ~= "" and #identity.username <= 64 then
            return resolveIdentityKey(identity.username)
        end
        return nil
    end)
    return ok and result or nil
end

local function steamKeyFromIdentity(identity)
    if type(identity) ~= "table" or identity.steamId == nil then return nil end
    local sid = LasciviousSystemsSteamId.isValid(identity.steamId)
    return sid and ("steam:" .. sid) or nil
end

local function isSteamKey(key)
    return type(key) == "string" and string.sub(key, 1, 6) == "steam:"
end

local function addUniqueKey(list, seen, key)
    if type(key) == "string" and key ~= "" and not seen[key] then
        seen[key] = true
        list[#list + 1] = key
    end
end

local identityUsernameHint

local function identityPendingKeys(identity, primaryKey, username)
    local keys, seen = {}, {}
    addUniqueKey(keys, seen, primaryKey)
    addUniqueKey(keys, seen, steamKeyFromIdentity(identity))
    if not username then username = identityUsernameHint(identity) end
    if username then
        addUniqueKey(keys, seen, dataStore().usernameIndex[username])
        addUniqueKey(keys, seen, "name:" .. username)
    end
    return keys
end

-- Best-effort USERNAME (not account key) for the sole purpose of pushing an
-- immediate state refresh to whoever's online right now -- LS.pushStateToUsername
-- already no-ops harmlessly on nil, so it's fine for this to come back empty
-- for a pure Steam-ID identity with no known username yet.
identityUsernameHint = function(identity)
    if type(identity) == "string" then return identity end
    local ok, result = pcall(function()
        if identity.getUsername then return usernameOf(identity) end
        if type(identity.username) == "string" and identity.username ~= "" then return identity.username end
        return nil
    end)
    return ok and result or nil
end

local function findOnlinePlayerForIdentity(identity)
    local username = identityUsernameHint(identity)
    local steamKey = steamKeyFromIdentity(identity)
    local found = nil
    eachOnlinePlayer(function(player)
        if found then return end
        local playerUsername = usernameOf(player)
        if username and playerUsername == username then
            local exactKey = exactSteamKeyFromUsername(playerUsername)
            if steamKey and exactKey and exactKey ~= steamKey then
                LS.log(string.format(
                    "WARNING: bridge username '%s' maps to '%s' but command targets '%s'; refusing username-only online match",
                    tostring(username), exactKey, steamKey))
                return
            end
            found = player
            return
        end
        if steamKey then
            local key = accountId(player)
            if key == steamKey then found = player end
        end
    end)
    return found
end

local function rawSteamIdForDebug(player)
    if not player or not player.getSteamID then return nil end
    local ok, value = pcall(function() return player:getSteamID() end)
    if not ok or value == nil then return nil end
    return tostring(value)
end

local function logOnlineIdentitySnapshot(context, expectedSteamKey, expectedUsername)
    LS.log(string.format(
        "%s: no exact online player match for expected steamKey='%s' username='%s'; listing all online identities",
        tostring(context), tostring(expectedSteamKey), tostring(expectedUsername)))
    local count = 0
    eachOnlinePlayer(function(player)
        count = count + 1
        local username = usernameOf(player)
        local exactKey = exactSteamKeyFromUsername(username)
        local resolvedKey = accountId(player)
        LS.log(string.format(
            "%s: online[%d] username='%s' exactSteamKey='%s' rawGetSteamID='%s' resolvedAccountKey='%s'",
            tostring(context), count, tostring(username), tostring(exactKey), tostring(rawSteamIdForDebug(player)),
            tostring(resolvedKey)))
    end)
    if count == 0 then
        LS.log(tostring(context) .. ": no online players visible to the server")
    end
end

-- Bridge/admin identities often arrive as {steamId=..., username=...}.  When a
-- matching player is online, force account discovery before deciding to queue.
-- When only an older name:<username> record exists, promote it into the exact
-- steam:<id> account supplied by the bridge unless the live engine already
-- resolved a DIFFERENT steam key (then the live engine wins and we log).
local function ensureAccountForIdentity(identity)
    local primaryKey = resolveIdentityKey(identity)
    if not primaryKey then return nil, nil, nil end
    local username = identityUsernameHint(identity)
    local steamKey = steamKeyFromIdentity(identity)
    local player = findOnlinePlayerForIdentity(identity)

    if player then
        local rec, liveKey = ensureAccount(player)
        username = username or usernameOf(player)
        if rec and liveKey then
            local targetKey = liveKey
            if steamKey and liveKey ~= steamKey then
                local exactKey = exactSteamKeyFromUsername(username)
                if exactKey and exactKey ~= steamKey then
                    LS.log(string.format(
                        "WARNING: bridge steam key '%s' disagrees with exact engine key '%s' for '%s'; using exact engine key",
                        steamKey, exactKey, tostring(username)))
                    targetKey = exactKey
                else
                    targetKey = steamKey
                end
            end

            if targetKey ~= liveKey then
                local data = dataStore()
                local targetRec = data.accounts[targetKey]
                if type(targetRec) == "table" and targetRec ~= rec then
                    rec = mergeFallbackAccount(targetRec, rec)
                else
                    rec = normalizeAccountRecord(rec)
                end
                data.accounts[targetKey] = rec
                data.accounts[liveKey] = nil
                if username then data.usernameIndex[username] = targetKey end
                LS.log(string.format("promoted live shop account '%s' to bridge identity '%s'", liveKey, targetKey))
            end

            local pendingKeys = identityPendingKeys(identity, targetKey, username)
            flushPendingCredits(rec, targetKey, pendingKeys)
            return rec, targetKey, username
        end
    end

    if steamKey and username then
        local data = dataStore()
        local fallbackKey = "name:" .. username
        local indexedKey = data.usernameIndex[username]
        local sourceKey = nil
        if type(data.accounts[fallbackKey]) == "table" then
            sourceKey = fallbackKey
        elseif type(indexedKey) == "string" and not isSteamKey(indexedKey)
            and type(data.accounts[indexedKey]) == "table" then
            sourceKey = indexedKey
        end

        if sourceKey and sourceKey ~= steamKey then
            local rec = data.accounts[sourceKey]
            if type(data.accounts[steamKey]) == "table" and data.accounts[steamKey] ~= rec then
                rec = mergeFallbackAccount(data.accounts[steamKey], rec)
            else
                rec = normalizeAccountRecord(rec)
            end
            data.accounts[steamKey] = rec
            data.accounts[sourceKey] = nil
            data.usernameIndex[username] = steamKey
            flushPendingCredits(rec, steamKey, identityPendingKeys(identity, sourceKey, username))
            LS.log(string.format("promoted fallback shop account '%s' to bridge identity '%s'", sourceKey, steamKey))
            return rec, steamKey, username
        end

        if type(data.accounts[steamKey]) == "table" then
            local rec = normalizeAccountRecord(data.accounts[steamKey])
            data.accounts[steamKey] = rec
            data.usernameIndex[username] = steamKey
            flushPendingCredits(rec, steamKey, identityPendingKeys(identity, primaryKey, username))
            return rec, steamKey, username
        end
    end

    return nil, primaryKey, username
end


-- Peek-only: current balance for `identity`, or 0 if no account exists yet.
-- Never creates a record -- a mod polling balances must not silently spawn
-- ghost accounts for names it merely checked.
function LS.getBalance(identity)
    local key = resolveIdentityKey(identity)
    if not key then return 0 end
    local rec = dataStore().accounts[key]
    return rec and LS.roundCredits(rec.balance) or 0
end

-- True only if `identity` already has a real account (created by a real
-- login, grant, or spend) -- lets a caller distinguish "0 balance" from
-- "never seen" before deciding whether a grant will apply immediately.
function LS.hasAccount(identity)
    local key = resolveIdentityKey(identity)
    return key ~= nil and dataStore().accounts[key] ~= nil
end

local PENDING_MAX_PER_IDENTITY = 25

-- Shared by LS.queueCredits and the recipient side of LS.transferCredits:
-- applies the grant immediately if `key` already has an account, otherwise
-- queues it. Returns ok, queued -- ok is only false when that identity's
-- queue is already full (a strong signal the caller has a typo'd identity
-- it keeps retrying, not a one-off).
local function applyOrQueueGrant(key, amount, reason)
    local data = dataStore()
    if data.accounts[key] then
        local rec = normalizeAccountRecord(data.accounts[key])
        data.accounts[key] = rec
        if rec.balance + amount > LS.MAX_CREDITS then
            return false, false, "recipient_balance_limit"
        end
        applyCreditsToKey(key, amount, reason)
        return true, false
    end
    local list = data.pendingCredits[key]
    if type(list) ~= "table" then
        list = {}
        data.pendingCredits[key] = list
    end
    if #list >= PENDING_MAX_PER_IDENTITY then return false, false, "queue_full" end
    table.insert(list, { amount = amount, reason = reason, queuedAt = nowSeconds() })
    LS.log(string.format("queued %s credits for '%s' (%s) -- no account yet, applies on first login",
        LS.formatCredits(amount), key, tostring(reason)))
    return true, true
end

-- Richer-identity counterpart to LS.spendCredits. No queueing: deducting
-- from a balance that doesn't exist yet has no sensible meaning.
function LS.deductCredits(identity, amount, reason)
    amount = finiteNumber(amount, nil)
    if not amount or amount <= 0 or amount > MAX_API_CREDIT_AMOUNT then
        return false, "invalid_amount"
    end
    local key = resolveIdentityKey(identity)
    if not key then return false, "invalid_identity" end
    local data = dataStore()
    local rec = data.accounts[key]
    if not rec then return false, "unknown_identity" end
    rec = normalizeAccountRecord(rec)
    data.accounts[key] = rec
    if rec.balance + 0.0001 < amount then return false, "insufficient_credits" end
    applyCreditsToKey(key, -amount, reason or "api_deduct")
    LS.pushStateToUsername(identityUsernameHint(identity))
    return true
end

-- Richer-identity counterpart to LS.grantCredits: applies now if the
-- identity already has an account, otherwise queues it for the moment that
-- account gets created (see flushPendingCredits above). This is the
-- direct answer to "give credits to a player who might be offline, dead,
-- or someone the server has never even seen yet" -- it always succeeds
-- unless the identity itself can't be resolved at all, or its queue is full.
function LS.queueCredits(identity, amount, reason)
    amount = finiteNumber(amount, nil)
    if not amount or amount <= 0 or amount > MAX_API_CREDIT_AMOUNT then
        return false, "invalid_amount"
    end
    local rec, key, username = ensureAccountForIdentity(identity)
    if not key then return false, "invalid_identity" end
    local steamKey = steamKeyFromIdentity(identity)
    if rec then
        rec = normalizeAccountRecord(rec)
        dataStore().accounts[key] = rec
        if rec.balance + amount > LS.MAX_CREDITS then
            return false, "recipient_balance_limit"
        end
        applyCreditsToKey(key, amount, reason or "api_queued_grant")
        LS.pushStateToUsername(username or identityUsernameHint(identity))
        LS.log(string.format("grant: +%s credits to '%s' via identity '%s' (%s)",
            LS.formatCredits(amount), tostring(username or key), tostring(key), tostring(reason or "api_queued_grant")))
        return true, nil, { queued = false, accountKey = key, username = username, matchedAccount = true }
    end
    if steamKey then
        local data = dataStore()
        rec = normalizeAccountRecord(data.accounts[steamKey])
        data.accounts[steamKey] = rec
        if username then
            local indexed = data.usernameIndex[username]
            if not indexed or indexed == steamKey or not isSteamKey(indexed) then
                data.usernameIndex[username] = steamKey
            elseif indexed ~= steamKey then
                LS.log(string.format(
                    "WARNING: not overwriting usernameIndex for '%s' from '%s' to bridge key '%s'",
                    tostring(username), tostring(indexed), steamKey))
            end
        end
        flushPendingCredits(rec, steamKey, identityPendingKeys(identity, key, username))
        rec = normalizeAccountRecord(data.accounts[steamKey])
        data.accounts[steamKey] = rec
        if rec.balance + amount > LS.MAX_CREDITS then
            return false, "recipient_balance_limit"
        end
        applyCreditsToKey(steamKey, amount, reason or "api_steam_grant")
        LS.pushStateToUsername(username)
        LS.log(string.format("grant: +%s credits to exact SteamID account '%s' (%s; username=%s)",
            LS.formatCredits(amount), steamKey, tostring(reason or "api_steam_grant"), tostring(username)))
        return true, nil, { queued = false, accountKey = steamKey, username = username, createdAccount = true }
    end
    local ok, queued, failure = applyOrQueueGrant(key, amount, reason or "api_queued_grant")
    if not ok then return false, failure or "queue_full" end
    if not queued then LS.pushStateToUsername(identityUsernameHint(identity)) end
    return true, nil, { queued = queued, accountKey = key, username = username }
end

local function externalRewardReceiptKey(rewardType, steamKey)
    if type(rewardType) ~= "string" or rewardType == "" then return nil end
    if not isSteamKey(steamKey) then return nil end
    return rewardType .. ":" .. steamKey
end

local function removePendingRewardEntries(data, keys, reason)
    local removed, removedTotal = 0, 0
    local seen = {}
    for _, key in ipairs(keys or {}) do
        if type(key) == "string" and not seen[key] then
            seen[key] = true
            local list = data.pendingCredits[key]
            if type(list) == "table" then
                local kept = {}
                for _, entry in ipairs(list) do
                    if type(entry) == "table" and entry.reason == reason then
                        removed = removed + 1
                        removedTotal = removedTotal + math.max(0, finiteNumber(entry.amount, 0))
                    else
                        kept[#kept + 1] = entry
                    end
                end
                data.pendingCredits[key] = #kept > 0 and kept or nil
            end
        end
    end
    return removed, removedTotal
end

function LS.grantExternalRewardOnce(identity, rewardType, amount, externalId)
    amount = finiteNumber(amount, nil)
    if not amount or amount <= 0 or amount > MAX_API_CREDIT_AMOUNT then
        return false, "invalid_amount"
    end

    local steamKey = steamKeyFromIdentity(identity)
    if not steamKey then
        return false, "invalid_steam_identity"
    end

    local receiptKey = externalRewardReceiptKey(rewardType, steamKey)
    if not receiptKey then
        return false, "invalid_reward_type"
    end

    local username = identityUsernameHint(identity)
    local onlinePlayer = findOnlinePlayerForIdentity(identity)
    if onlinePlayer then
        username = username or usernameOf(onlinePlayer)
    else
        logOnlineIdentitySnapshot("external reward '" .. tostring(rewardType) .. "'", steamKey, username)
    end
    local data = dataStore()
    local existing = data.externalRewards[receiptKey]
    if type(existing) == "table" and (existing.status == "applied" or existing.status == "processing") then
        local removedPending, removedPendingTotal = removePendingRewardEntries(data,
            identityPendingKeys(identity, steamKey, username), rewardType)
        if removedPending > 0 then
            LS.log(string.format("external reward '%s' for '%s' already recorded; removed %d duplicate pending grant(s) totalling %s",
                tostring(rewardType), steamKey, removedPending, LS.formatCredits(removedPendingTotal)))
        end
        LS.log(string.format("external reward '%s' for '%s' already recorded as %s; not granting again",
            tostring(rewardType), steamKey, tostring(existing.status)))
        return true, nil, {
            queued = false,
            alreadyApplied = true,
            accountKey = steamKey,
            username = username,
            receiptKey = receiptKey,
        }
    end

    local rec = normalizeAccountRecord(data.accounts[steamKey])
    data.accounts[steamKey] = rec
    if username then
        local indexed = data.usernameIndex[username]
        if not indexed or indexed == steamKey or not isSteamKey(indexed) then
            data.usernameIndex[username] = steamKey
        end
    end

    if rec.balance + amount > LS.MAX_CREDITS then
        return false, "recipient_balance_limit"
    end

    data.externalRewards[receiptKey] = {
        status = "processing",
        rewardType = rewardType,
        accountKey = steamKey,
        amount = amount,
        externalId = externalId,
        startedAt = nowSeconds(),
    }

    local pendingKeys = identityPendingKeys(identity, steamKey, username)
    local removedPending, removedPendingTotal = removePendingRewardEntries(data, pendingKeys, rewardType)
    applyCreditsToKey(steamKey, amount, rewardType)

    data.externalRewards[receiptKey] = {
        status = "applied",
        rewardType = rewardType,
        accountKey = steamKey,
        amount = amount,
        externalId = externalId,
        appliedAt = nowSeconds(),
        removedDuplicatePending = removedPending,
        removedDuplicatePendingTotal = removedPendingTotal,
    }

    LS.pushStateToUsername(username)
    LS.log(string.format("external reward '%s': +%s credits to '%s'%s%s",
        tostring(rewardType), LS.formatCredits(amount), steamKey,
        username and (" (username=" .. tostring(username) .. ")") or "",
        removedPending > 0 and string.format("; removed %d duplicate pending grant(s) totalling %s",
            removedPending, LS.formatCredits(removedPendingTotal)) or ""))

    return true, nil, {
        queued = false,
        alreadyApplied = false,
        accountKey = steamKey,
        username = username,
        receiptKey = receiptKey,
        removedDuplicatePending = removedPending,
    }
end

-- Generic transfer between two identities -- what Commands[LS.CMD_TRANSFER]
-- itself calls, after its own player-facing checks (alive, not self,
-- cooldown, request dedup), none of which belong at this level. The
-- SENDER must already have a real, sufficiently-funded account (you cannot
-- spend from nothing); the RECIPIENT does not -- an offline or entirely
-- unknown-but-identifiable recipient gets queued via the same mechanism as
-- LS.queueCredits, so a transfer to someone who isn't online still
-- succeeds instead of failing outright.
function LS.transferCredits(fromIdentity, toIdentity, amount, reason)
    amount = finiteNumber(amount, nil)
    if not amount or amount <= 0 or amount > MAX_API_CREDIT_AMOUNT then
        return false, "invalid_amount"
    end
    local fromKey = resolveIdentityKey(fromIdentity)
    if not fromKey then return false, "invalid_identity" end
    local toKey = resolveIdentityKey(toIdentity)
    if not toKey then return false, "invalid_identity" end
    if fromKey == toKey then return false, "self_target" end

    local data = dataStore()
    local fromRec = data.accounts[fromKey]
    if not fromRec then return false, "unknown_identity" end
    fromRec = normalizeAccountRecord(fromRec)
    data.accounts[fromKey] = fromRec
    if fromRec.balance + 0.0001 < amount then return false, "insufficient_credits" end

    -- Preflight the only recipient-side failure before touching either ledger.
    -- The old deduct-then-refund path restored the balance but recorded the
    -- failed attempt as both lifetimeSpent and lifetimeEarned.
    if data.accounts[toKey] then
        local toRec = normalizeAccountRecord(data.accounts[toKey])
        data.accounts[toKey] = toRec
        if toRec.balance + amount > LS.MAX_CREDITS then
            return false, "recipient_balance_limit"
        end
    else
        local pending = data.pendingCredits[toKey]
        if type(pending) == "table" and #pending >= PENDING_MAX_PER_IDENTITY then
            return false, "queue_full"
        end
    end

    local balanceBefore = fromRec.balance
    local earnedBefore = fromRec.lifetimeEarned
    local spentBefore = fromRec.lifetimeSpent
    applyCreditsToKey(fromKey, -amount, reason or ("transfer_to:" .. toKey))

    local ok, queued, failure = applyOrQueueGrant(toKey, amount, reason or ("transfer_from:" .. fromKey))
    if not ok then
        -- Defensive rollback in case a future recipient path gains another
        -- failure mode after the preflight. Restore the exact snapshots so a
        -- failed transfer is neutral to every ledger counter, not just balance.
        fromRec.balance = balanceBefore
        fromRec.lifetimeEarned = earnedBefore
        fromRec.lifetimeSpent = spentBefore
        fromRec.updatedAt = nowSeconds()
        fromRec.source = "transfer_rollback:" .. tostring(failure or "recipient_failure")
        return false, failure or "queue_full"
    end

    LS.pushStateToUsername(identityUsernameHint(fromIdentity))
    if not queued then LS.pushStateToUsername(identityUsernameHint(toIdentity)) end
    LS.log(string.format("api transfer: %s -> %s, %s credits%s (%s)",
        fromKey, toKey, LS.formatCredits(amount), queued and " [queued]" or "", tostring(reason or "api_transfer")))
    return true, nil, { queued = queued }
end

local function isDead(player)
    if not player or not player.isDead then return false end
    local ok, dead = pcall(function() return player:isDead() end)
    return ok and dead == true
end

local function nativeStats(player)
    if not player or isDead(player) then return nil, nil end
    local kills, hours
    if player.getZombieKills then
        local ok, value = pcall(function() return player:getZombieKills() end)
        value = ok and finiteNumber(value, nil) or nil
        if value then kills = math.max(0, math.floor(value)) end
    end
    if player.getHoursSurvived then
        local ok, value = pcall(function() return player:getHoursSurvived() end)
        value = ok and finiteNumber(value, nil) or nil
        if value then hours = math.max(0, math.floor(value + 0.000001)) end
    end
    return kills, hours
end

local function consumeDebugStartingGrant(rec, opts)
    if opts.debugAddCredits and rec.debugCreditsGranted ~= true then
        rec.debugCreditsGranted = true
        return DEBUG_STARTING_CREDITS
    end
    return 0
end

-- Optional cross-mod read (same defensive pattern as commerceDiscountFor
-- further down): this player's faction's current Recompensa por Combate
-- (combatBounty) upgrade level, 0-10. 0 if not in a faction,
-- LasciviousFactionsSystem isn't loaded, or the faction has no active claim
-- -- upgrade effects pause without one, the same rule every other LFS
-- upgrade effect follows. Declared before refreshCredits (its earliest
-- caller), not just before buildState (its other one) -- same
-- forward-reference lesson as commerceDiscountFor's own placement.
local function combatBountyLevelFor(player)
    if not (LasciviousFactionsSystem and LasciviousFactionsSystem.getFactionOfPlayer
        and LasciviousFactionsSystem.upgradeLevel and LasciviousFactionsSystem.upgradesActive) then
        return 0
    end
    local username = usernameOf(player)
    if not username then return 0 end
    local ok, name, faction = pcall(LasciviousFactionsSystem.getFactionOfPlayer, username)
    if not (ok and faction) then return 0 end
    local activeOk, active = pcall(LasciviousFactionsSystem.upgradesActive, faction)
    if not (activeOk and active) then return 0 end
    local levelOk, level = pcall(LasciviousFactionsSystem.upgradeLevel, faction, "combatBounty")
    if not levelOk then return 0 end
    return math.max(0, math.min(10, finiteNumber(level, 0)))
end

-- Two independent linear curves off the SAME level -- explicit user request
-- to extend this upgrade beyond kills to hour-survived credits too, but with
-- a smaller max boost on that side (1.5x vs 2.5x for kills).
local function combatBountyKillMultiplier(level)
    return 1.0 + level * 0.15
end
local function combatBountyHourMultiplier(level)
    return 1.0 + level * 0.05
end

-- Balance is a ledger, not a formula over the current raw totals: purchases must
-- remain spent, and changing a Sandbox rate must only affect future gains. The
-- first observation is deliberately retroactive for the character's current life.
local function refreshCredits(player, suppliedOptions)
    local rec = ensureAccount(player)
    if not rec then return false end
    local kills, hours = nativeStats(player)
    if kills == nil and hours == nil then return false end
    kills = kills ~= nil and kills or rec.lastKills
    hours = hours ~= nil and hours or rec.lastHours
    local opts = suppliedOptions or LS.getOptions()
    local debugGrant = consumeDebugStartingGrant(rec, opts)

    if rec.initialized ~= true then
        local combatBountyLevel = combatBountyLevelFor(player)
        local killMultiplier = combatBountyKillMultiplier(combatBountyLevel)
        local hourMultiplier = combatBountyHourMultiplier(combatBountyLevel)
        local retroactive = kills * opts.creditsPerZombieKill * killMultiplier
            + hours * opts.creditsPerHourSurvived * hourMultiplier + debugGrant
        -- Preserve API/offline grants already sitting on this not-yet-observed
        -- account. Assigning `retroactive` outright used to erase queued grants
        -- the moment their recipient logged in for the first time.
        rec.balance = LS.roundCredits(rec.balance + retroactive)
        rec.lifetimeEarned = LS.roundCredits((tonumber(rec.lifetimeEarned) or 0) + retroactive)
        rec.lastKills, rec.lastHours = kills, hours
        rec.initialized = true
        rec.updatedAt = nowSeconds()
        rec.source = "retroactive_first_seen"
        return true
    end

    -- If either native counter moves backwards, the server missed a death event
    -- (crash/reconnect edge case). Treat it as a new life. By default this keeps
    -- legacy behaviour and clears the old ledger; the sandbox preservation toggle
    -- only resets the raw baselines so future gains continue from the new life.
    if kills < rec.lastKills or hours < rec.lastHours then
        local preserveBalance = opts.preserveCreditsOnDeath == true
        if preserveBalance then
            rec.balance = LS.roundCredits(math.max(0, finiteNumber(rec.balance, 0)))
        else
            rec.balance = 0
        end
        rec.debugCreditsGranted = false
        if opts.debugAddCredits then
            if preserveBalance then
                rec.balance = LS.roundCredits(rec.balance + DEBUG_STARTING_CREDITS)
            else
                rec.balance = DEBUG_STARTING_CREDITS
            end
            rec.debugCreditsGranted = true
        end
        rec.lastKills, rec.lastHours = kills, hours
        -- The replay ledger belongs to the account, not to one character life.
        -- In particular, never discard an ambiguous processing tombstone here:
        -- the old client can still retry its request after reconnect/death.
        rec.updatedAt = nowSeconds()
        rec.source = preserveBalance and "native_counter_reset_preserved" or "native_counter_reset"
        return true
    end

    local deltaKills = kills - rec.lastKills
    local deltaHours = hours - rec.lastHours
    if deltaKills <= 0 and deltaHours <= 0 and debugGrant <= 0 then return false end

    -- Faction lookups are unnecessary for the overwhelmingly common idle tick.
    -- Resolve the upgrade only after a real native-stat/debug delta survives the
    -- early return above (and once in the first-observation branch separately).
    local combatBountyLevel = combatBountyLevelFor(player)
    local killMultiplier = combatBountyKillMultiplier(combatBountyLevel)
    local hourMultiplier = combatBountyHourMultiplier(combatBountyLevel)

    -- Faction tribute (LasciviousFactionsSystem) taxes only the kill/hour-derived
    -- portion of this tick's earnings -- never the debug grant, and never the
    -- one-time retroactive grant above (that branch returns before reaching here).
    -- Optional cross-mod call, guarded and pcall-wrapped: if the faction mod isn't
    -- present or its call fails for any reason, the player simply keeps the full
    -- untaxed amount rather than earning breaking.
    local killHourEarned = deltaKills * opts.creditsPerZombieKill * killMultiplier
        + deltaHours * opts.creditsPerHourSurvived * hourMultiplier
    local netEarned = killHourEarned
    if killHourEarned > 0 and LasciviousFactionsSystem and LasciviousFactionsSystem.creditTributeFromEarnings then
        local username = usernameOf(player)
        if username then
            local ok, net = pcall(LasciviousFactionsSystem.creditTributeFromEarnings, username, killHourEarned)
            local safeNet = ok and finiteNumber(net, nil) or nil
            if safeNet then netEarned = math.max(0, math.min(killHourEarned, safeNet)) end
        end
    end

    local earned = netEarned + debugGrant
    rec.balance = LS.roundCredits(rec.balance + earned)
    rec.lifetimeEarned = LS.roundCredits(rec.lifetimeEarned + earned)
    rec.lastKills, rec.lastHours = kills, hours
    rec.updatedAt = nowSeconds()
    rec.source = "native_delta"
    return true
end

local validVehicleScripts = nil
local function vehicleScriptExists(fullType)
    if not validVehicleScripts then
        validVehicleScripts = {}
        pcall(function()
            local scripts = getScriptManager():getAllVehicleScripts()
            for i = 1, scripts:size() do
                validVehicleScripts[scripts:get(i - 1):getFullName()] = true
            end
        end)
    end
    return validVehicleScripts[fullType] == true
end

local function validateCatalog()
    validProducts = {}
    invalidProductsForClient = {}
    local validCount = 0
    local invalidIds = {}
    local seenIds, duplicateIds = {}, {}
    for _, product in ipairs(LS.PRODUCTS) do
        local id = product and product.id
        if type(id) == "string" and seenIds[id] then duplicateIds[id] = true end
        if type(id) == "string" then seenIds[id] = true end
    end

    -- Which mods (by the id their catalog entries were tagged with via
    -- LS.addModdedItems in LasciviousShop_Catalog.lua) fail their own
    -- OPTIONAL presence probe this pass -- purely to make the warning below
    -- readable ("this item is gone because ModX isn't installed" instead of
    -- a bare product id). Never used to decide validProducts itself: that
    -- stays owned entirely by the real per-item checks below, the same ones
    -- every vanilla item already goes through. A missing, wrong or buggy
    -- probe can only make a log line less helpful -- it can never make an
    -- item wrongly available or wrongly unavailable.
    local missingMods = {}
    for modId, isPresent in pairs(LS.MOD_PRESENCE_CHECKS or {}) do
        local ok, present = pcall(isPresent)
        if not ok or present ~= true then missingMods[modId] = true end
    end

    -- Guns of Marz (GoM) active on the server: vanilla firearms and ammo
    -- (rounds/boxes/cartons/magazines) are hidden from the shop entirely --
    -- explicit server design choice (GoM does not remove them itself, see
    -- GoMCompat.lua), so players only ever see the GoM equivalents added at
    -- the bottom of LasciviousShop_Catalog.lua. Computed once per validation
    -- pass, not per product. Only ever hides VANILLA entries (sourceMod ==
    -- nil) -- any other mod's own "firearm"/"ammo" additions are untouched.
    local hideVanillaFirearmsAndAmmo = GoMCompat.isActive()

    for productIndex, product in ipairs(LS.PRODUCTS) do
        local productId = type(product) == "table" and type(product.id) == "string" and product.id
            or ("__invalid_product_" .. tostring(productIndex))
        local kind = type(product) == "table" and product.kind or nil
        local valid = type(product) == "table" and type(product.id) == "string"
            and product.id ~= "" and #product.id <= 64
            and not duplicateIds[product.id]
        if valid and kind ~= "xp" and kind ~= "cure" then
            local price = finiteNumber(product.price, nil)
            valid = price ~= nil and price > 0
        end
        if kind == "item" then
            local ok, scriptItem = pcall(function() return getScriptManager():FindItem(product.fullType) end)
            valid = valid and ok and scriptItem ~= nil
        elseif kind == "xp" then
            local ok, perk = pcall(function() return Perks.FromString(product.perk) end)
            valid = valid and ok and perk ~= nil and perk ~= Perks.None and perk ~= Perks.MAX
        elseif kind == "cure" then
            valid = valid
        elseif kind == "vehicle" then
            valid = valid and vehicleScriptExists(product.fullType)
        else
            valid = false
        end
        local hiddenForGoM = valid and hideVanillaFirearmsAndAmmo
            and not (type(product) == "table" and product.sourceMod)
            and type(product) == "table" and (product.category == "firearm" or product.category == "ammo")
        if hiddenForGoM then valid = false end
        validProducts[productId] = valid
        if valid then
            validCount = validCount + 1
        else
            invalidIds[#invalidIds + 1] = productId
            invalidProductsForClient[productId] = true
            if hiddenForGoM then
                -- Not a broken/missing item -- deliberately hidden because Guns
                -- of Marz is active on this server. Quieter than the WARNING
                -- lines below on purpose, this is expected, not a problem.
            elseif type(product) == "table" and product.sourceMod then
                LS.log(string.format("WARNING: disabled invalid catalog product '%s' (from mod '%s'%s)",
                    tostring(productId), tostring(product.sourceMod),
                    missingMods[product.sourceMod] and ", which appears to not be installed/active" or ""))
            else
                LS.log("WARNING: disabled invalid catalog product " .. tostring(productId))
            end
        end
    end
    table.sort(invalidIds)
    invalidProductsHash = table.concat(invalidIds, ";")
    catalogValidated = true
    LS.log(string.format("catalog validated: %d/%d products available", validCount, #LS.PRODUCTS))
end

local function offerConfigHash(opts)
    return table.concat({
        tostring(opts.offersEnabled), opts.offerRotationRealMinutes,
        opts.offerProductCountMin, opts.offerProductCountMax,
        opts.offerDiscountMinPercent, opts.offerDiscountMaxPercent,
    }, "|")
end

local function runtimeConfigHash(opts)
    return table.concat({
        offerConfigHash(opts), opts.creditsPerZombieKill, opts.creditsPerHourSurvived,
        LS.priceConfigurationHash(opts), tostring(opts.offerBadgeEnabled), tostring(opts.offerHighlightEnabled),
        tostring(opts.debugAddCredits),
        opts.offerHighlightRed, opts.offerHighlightGreen, opts.offerHighlightBlue,
    }, "|")
end

local function rerollOffers(opts, reason)
    local data = dataStore()
    data.offers, data.offerIds = {}, {}
    data.offerRevision = data.offerRevision + 1
    data.offerConfigHash = offerConfigHash(opts)

    if opts.offersEnabled then
        local pool = {}
        for _, product in ipairs(LS.PRODUCTS) do
            if validProducts[product.id] ~= false then table.insert(pool, product.id) end
        end
        local maxCount = math.min(opts.offerProductCountMax, #pool)
        local minCount = math.min(opts.offerProductCountMin, maxCount)
        local count = maxCount > 0 and randomInt(minCount, maxCount) or 0
        for _ = 1, count do
            local index = randomInt(1, #pool)
            local productId = table.remove(pool, index)
            local discount = randomInt(opts.offerDiscountMinPercent, opts.offerDiscountMaxPercent)
            data.offers[productId] = discount
            table.insert(data.offerIds, productId)
        end
        data.offerExpiresAt = nowSeconds() + opts.offerRotationRealMinutes * 60
    else
        data.offerExpiresAt = 0
    end
    LS.log(string.format("offers rotated (%s): %d product(s), revision %d",
        tostring(reason or "timer"), #data.offerIds, data.offerRevision))
end

local function ensureOffers(suppliedOptions)
    if not catalogValidated then validateCatalog() end
    local data = dataStore()
    local opts = suppliedOptions or LS.getOptions()
    local hash = offerConfigHash(opts)
    local changed = false
    local invalidSelection = false
    local seenOfferIds = {}
    for _, productId in ipairs(data.offerIds or {}) do
        local discount = finiteNumber(data.offers[productId], nil)
        if not LS.PRODUCT_BY_ID[productId] or validProducts[productId] == false
            or seenOfferIds[productId] or not discount or discount <= 0 or discount >= 100 then
            invalidSelection = true
            break
        end
        seenOfferIds[productId] = true
    end
    if data.offerConfigHash ~= hash then
        rerollOffers(opts, "configuration")
        changed = true
    elseif opts.offersEnabled and invalidSelection then
        rerollOffers(opts, "catalog_changed")
        changed = true
    elseif opts.offersEnabled and (data.offerExpiresAt <= nowSeconds() or #data.offerIds == 0) then
        rerollOffers(opts, "real_time_timer")
        changed = true
    elseif not opts.offersEnabled and (#data.offerIds > 0 or data.offerExpiresAt ~= 0) then
        rerollOffers(opts, "disabled")
        changed = true
    end
    return changed
end

local function copyOffers(source, ids)
    local out = {}
    for _, id in ipairs(ids or {}) do
        local discount = finiteNumber(source and source[id], nil)
        if type(id) == "string" and discount and discount > 0 and discount < 100 then
            out[id] = math.floor(discount)
        end
    end
    return out
end

local function perkAndLevel(player, product)
    if not player or not product or product.kind ~= "xp" then return nil, 0 end
    local ok, perk, level = pcall(function()
        local resolved = Perks.FromString(product.perk)
        if not resolved or resolved == Perks.None or resolved == Perks.MAX then
            error("unknown perk " .. tostring(product.perk))
        end
        return resolved, player:getPerkLevel(resolved)
    end)
    if not ok then return nil, 0 end
    return perk, math.max(0, math.min(10, math.floor(finiteNumber(level, 0))))
end

local function perkProgress(player, product, quantity)
    local perk, level = perkAndLevel(player, product)
    if not perk then return nil, level, 0 end
    local ok, currentXP = pcall(function() return player:getXp():getXP(perk) end)
    if not ok then return nil, level, 0, 0 end
    local amount = LS.xpRequiredForLevelsFromXP(perk, level, currentXP, quantity or 1)
    return perk, level, amount, finiteNumber(currentXP, 0)
end

local function buildPerkProgress(player)
    local levels, xpToNext, bundles, hash = {}, {}, {}, {}
    for _, product in ipairs(LS.XP_PRODUCTS or LS.PRODUCTS) do
        if product.kind == "xp" then
            local perk, level, remaining, currentXP = perkProgress(player, product, 1)
            levels[product.perk] = level
            xpToNext[product.perk] = remaining
            local skillBundles, hashParts = {}, { product.perk, "=", tostring(level) }
            if perk then
                for quantity = 1, 10 - level do
                    local amount = LS.xpRequiredForLevelsFromXP(perk, level, currentXP, quantity)
                    skillBundles[quantity] = amount
                    hashParts[#hashParts + 1] = ":"
                    hashParts[#hashParts + 1] = tostring(amount)
                end
            end
            bundles[product.perk] = skillBundles
            table.insert(hash, table.concat(hashParts))
        end
    end
    return levels, xpToNext, bundles, table.concat(hash, ";")
end

-- Optional cross-mod read (same defensive pattern as buildState's own
-- factionName/tributeRatePercent lookup just below): this player's faction's
-- current Comércio upgrade discount, 0..50 (custom curve, level 0-10). 0 if
-- not in a faction, LasciviousFactionsSystem isn't loaded, or the faction has
-- no active claim -- upgrade effects pause without one, the same rule every
-- other LFS upgrade effect already follows. Never mutates
-- LasciviousFactionsSystem's data from here. Declared before buildState (not
-- just before currentPrice, its other caller) since buildState needs it too
-- and Lua locals aren't visible to a function defined earlier in the file.
local COMMERCE_DISCOUNT_BY_LEVEL = {
    [0] = 0,
    [1] = 3,
    [2] = 6,
    [3] = 10,
    [4] = 14,
    [5] = 19,
    [6] = 24,
    [7] = 30,
    [8] = 36,
    [9] = 43,
    [10] = 50,
}

local function commerceDiscountFor(player)
    if not (LasciviousFactionsSystem and LasciviousFactionsSystem.getFactionOfPlayer
        and LasciviousFactionsSystem.upgradeLevel and LasciviousFactionsSystem.upgradesActive) then
        return 0
    end
    local username = usernameOf(player)
    if not username then return 0 end
    local ok, name, faction = pcall(LasciviousFactionsSystem.getFactionOfPlayer, username)
    if not (ok and faction) then return 0 end
    local activeOk, active = pcall(LasciviousFactionsSystem.upgradesActive, faction)
    if not (activeOk and active) then return 0 end
    local levelOk, level = pcall(LasciviousFactionsSystem.upgradeLevel, faction, "commerce")
    if not levelOk then return 0 end
    level = math.max(0, math.min(10, math.floor(finiteNumber(level, 0))))
    return COMMERCE_DISCOUNT_BY_LEVEL[level] or 0
end

local function buildState(player, suppliedOptions)
    local rec = ensureAccount(player)
    local data = dataStore()
    local opts = suppliedOptions or LS.getOptions()
    local perkLevels, perkXPToNext, perkXPBundles, perkProgressHash = buildPerkProgress(player)
    local bountyLevel = combatBountyLevelFor(player)

    -- Optional cross-mod read: which faction (if any) this player belongs to, and
    -- its current tribute rate, purely for the "your faction charges X%" hint in
    -- the client UI. Never mutates LasciviousFactionsSystem's data from here.
    local factionName, tributeRatePercent = nil, nil
    if LasciviousFactionsSystem and LasciviousFactionsSystem.getFactionOfPlayer then
        local username = usernameOf(player)
        if username then
            local ok, name, faction = pcall(LasciviousFactionsSystem.getFactionOfPlayer, username)
            if ok and faction then
                factionName = name
                tributeRatePercent = math.max(0, math.min(100,
                    finiteNumber(faction.tribute and faction.tribute.ratePercent, 0)))
            end
        end
    end

    return {
        balance = rec and rec.balance or 0,
        factionName = factionName,
        tributeRatePercent = tributeRatePercent,
        commerceDiscountPercent = commerceDiscountFor(player),
        -- Real, currently-effective kill/hour rates including the faction's
        -- Recompensa por Combate multipliers -- equal the plain
        -- creditsPerZombieKill/creditsPerHourSurvived when there's no boost,
        -- so the client can always just show/color THESE values without
        -- needing to know the multiplier formulas itself (same "server
        -- computes, client only displays" split as commerceDiscountPercent).
        creditsPerZombieKillBoosted = LS.roundCredits(opts.creditsPerZombieKill * combatBountyKillMultiplier(bountyLevel)),
        creditsPerHourSurvivedBoosted = LS.roundCredits(opts.creditsPerHourSurvived * combatBountyHourMultiplier(bountyLevel)),
        zombieKills = rec and rec.lastKills or 0,
        survivedHours = rec and rec.lastHours or 0,
        creditsPerZombieKill = opts.creditsPerZombieKill,
        creditsPerHourSurvived = opts.creditsPerHourSurvived,
        priceMultiplier = opts.priceMultiplier,
        useCategoryPriceMultipliers = opts.useCategoryPriceMultipliers,
        categoryPriceMultipliers = LS.copyCategoryPriceMultipliers(opts.categoryPriceMultipliers),
        perkLevels = perkLevels,
        perkXPToNext = perkXPToNext,
        perkXPBundles = perkXPBundles,
        perkProgressHash = perkProgressHash,
        offersEnabled = opts.offersEnabled,
        offers = copyOffers(data.offers, data.offerIds),
        offerIds = data.offerIds,
        offerExpiresAt = data.offerExpiresAt,
        offerRevision = data.offerRevision,
        offerBadgeEnabled = opts.offerBadgeEnabled,
        offerHighlightEnabled = opts.offerHighlightEnabled,
        offerColor = {
            r = opts.offerHighlightRed / 255,
            g = opts.offerHighlightGreen / 255,
            b = opts.offerHighlightBlue / 255,
        },
        -- Immutable between catalog validation passes; sharing it here avoids
        -- scanning all ~2,400 products and allocating an identical map for
        -- every 15-second state response to every connected player.
        invalidProducts = invalidProductsForClient,
        invalidProductsHash = invalidProductsHash,
        serverNow = nowSeconds(),
    }
end

local function sendState(player, refresh, suppliedOptions)
    local opts = suppliedOptions or LS.getOptions()
    ensureOffers(opts)
    if refresh ~= false then refreshCredits(player, opts) end
    toClient(player, LS.CMD_STATE, buildState(player, opts))
end

-- Cross-mod boundary: push a fresh CMD_STATE to `username` right now, if online,
-- instead of waiting for the shop window's own ~15s poll or the next periodicTick
-- cycle. LS.grantCredits/LS.spendCredits call this after mutating a balance from
-- OUTSIDE refreshCredits's own native-stat-delta logic (a tribute deposit,
-- withdraw, donate, or the disband refund) -- periodicTick's `creditsChanged`
-- check never catches those, since nothing about the player's kills/hours
-- changed. Passive per-tick tribute tax does NOT need this: it only ever runs
-- alongside a real kill/hour delta, which periodicTick already detects and
-- pushes for on its own within TICK_SECONDS.
function LS.pushStateToUsername(username)
    if type(username) ~= "string" or username == "" then return end
    eachOnlinePlayer(function(player)
        local ok, playerUsername = pcall(function() return player:getUsername() end)
        if ok and playerUsername == username then
            sendState(player, false)
        end
    end)
end

local function sendError(player, reason, extra, includeState)
    local args = extra or {}
    args.reason = reason
    if includeState ~= false then args.state = buildState(player) end
    toClient(player, LS.CMD_ERROR, args)
end

local function currentPrice(player, product, quantity, pricing)
    local data = pricing and pricing.data or dataStore()
    local opts = pricing and pricing.options or LS.getOptions()
    local offerDiscount = tonumber(data.offers[product.id]) or 0
    local commerceDiscount = pricing and pricing.commerceDiscount or commerceDiscountFor(player)
    local discount = LS.combineDiscounts(offerDiscount, commerceDiscount)
    local multiplier = LS.priceMultiplierForCategory(opts, product.category)
    local xpAmount, perkLevel, xpBasePrice
    if product.kind == "xp" then
        local perk, level, remaining, currentXP = perkProgress(player, product, quantity or 1)
        perkLevel = level
        xpAmount = remaining
        xpBasePrice = perk and LS.xpLevelUpBasePriceFromXP(perk, level, currentXP, quantity or 1) or 0
    end
    local severity = product.kind == "cure" and LS.cureSeverity(player) or nil
    local price, original = LS.priceFor(product, discount, multiplier, xpBasePrice, severity)
    return price, original, xpAmount, perkLevel
end

local function normalizeCart(rawItems)
    if type(rawItems) ~= "table" or #rawItems == 0 or #rawItems > MAX_CART_LINES then return nil end
    local combined, order = {}, {}
    local totalUnits = 0
    for i = 1, #rawItems do
        local entry = rawItems[i]
        if type(entry) ~= "table" or type(entry.id) ~= "string" or #entry.id > 64 then return nil end
        local qty = finiteNumber(entry.qty, nil)
        if not qty or qty ~= math.floor(qty) or qty < 1 or qty > MAX_LINE_QUANTITY then return nil end
        local product = LS.PRODUCT_BY_ID[entry.id]
        if not product or validProducts[entry.id] == false then return nil end
        if not combined[entry.id] then
            combined[entry.id] = { product = product, qty = 0 }
            table.insert(order, entry.id)
        end
        combined[entry.id].qty = combined[entry.id].qty + qty
        if combined[entry.id].qty > MAX_LINE_QUANTITY then return nil end
        totalUnits = totalUnits + qty
        if totalUnits > MAX_CART_UNITS then return nil end
    end
    local lines = {}
    for _, id in ipairs(order) do table.insert(lines, combined[id]) end
    return lines
end

local function callIfExists(object, methodName, ...)
    if not object or type(methodName) ~= "string" then return false end
    local args = { ... }
    local ok, result = pcall(function()
        local method = object[methodName]
        if type(method) ~= "function" then return nil end
        return method(object, unpack(args))
    end)
    return ok, result
end

local function numericGetter(object, methodName)
    local ok, value = callIfExists(object, methodName)
    value = ok and tonumber(value) or nil
    if value and value == value and value ~= math.huge and value ~= -math.huge then return value end
    return nil
end

local function setMaxConditionIfPossible(item)
    local ok, maxCondition = pcall(function() return item:getConditionMax() end)
    maxCondition = ok and tonumber(maxCondition) or numericGetter(item, "getConditionMax")
    if maxCondition and maxCondition > 0 then
        pcall(function() item:setCondition(math.floor(maxCondition)) end)
        callIfExists(item, "setCondition", math.floor(maxCondition))
    end
end

local function setMaxNumericPart(item, setterName, maxGetterName, fallbackMax)
    local maximum = numericGetter(item, maxGetterName) or fallbackMax
    if maximum and maximum > 0 then
        callIfExists(item, setterName, maximum)
    end
end

local function freshenPurchasedWeaponItem(item)
    if not item then return end
    setMaxConditionIfPossible(item)

    -- Build 42/modded melee can expose extra durability/sharpness fields for
    -- weapon heads, blades, handles or attached weapon parts. Method names vary
    -- between vanilla, experimental branches and mods, so every attempt is
    -- optional. Missing methods simply no-op; existing ones are forced to max.
    local maxCondition = numericGetter(item, "getConditionMax")
    setMaxNumericPart(item, "setConditionLowerChance", "getConditionLowerChanceMax", numericGetter(item, "getConditionLowerChance"))
    setMaxNumericPart(item, "setHeadCondition", "getHeadConditionMax", maxCondition)
    setMaxNumericPart(item, "setBladeCondition", "getBladeConditionMax", maxCondition)
    setMaxNumericPart(item, "setHandleCondition", "getHandleConditionMax", maxCondition)
    setMaxNumericPart(item, "setSharpness", "getSharpnessMax", 1.0)
    setMaxNumericPart(item, "setCurrentSharpness", "getSharpnessMax", 1.0)
    setMaxNumericPart(item, "setSharpnessLevel", "getMaxSharpnessLevel", 1.0)

    callIfExists(item, "setHaveBeenRepaired", 0)
    callIfExists(item, "setBloodLevel", 0)
    callIfExists(item, "setDirtyness", 0)
    callIfExists(item, "setWet", false)

    local okParts, parts = callIfExists(item, "getAllWeaponParts")
    if okParts and parts then
        local okSize, size = pcall(function() return parts:size() end)
        size = okSize and tonumber(size) or 0
        for i = 0, size - 1 do
            local okPart, part = pcall(function() return parts:get(i) end)
            if okPart and part then setMaxConditionIfPossible(part) end
        end
    end
end

local function freshenPurchasedItems(product, items)
    if not product or (product.category ~= "melee" and product.category ~= "firearm" and product.category ~= "ammo") then
        return
    end
    local okSize, size = pcall(function() return items:size() end)
    size = okSize and tonumber(size) or 0
    for i = 0, size - 1 do
        local okItem, item = pcall(function() return items:get(i) end)
        if okItem and item then freshenPurchasedWeaponItem(item) end
    end
end

local function deliverItem(player, product, cartQty)
    local okInventory, inventory = pcall(function() return player:getInventory() end)
    if not okInventory or not inventory then return false, 0, 0 end
    local amount = math.max(1, math.floor(tonumber(product.quantity) or 1)) * cartQty
    local ok, items = pcall(function() return inventory:AddItems(product.fullType, amount) end)
    if not ok or not items then return false, 0, amount end
    freshenPurchasedItems(product, items)
    pcall(function() sendAddItemsToContainer(inventory, items) end)
    local okSize, size = pcall(function() return items:size() end)
    size = okSize and tonumber(size) or 0
    return size == amount, size, amount
end

local function deliverXP(player, product, totalXP)
    local amount = math.max(1, math.floor(tonumber(totalXP) or tonumber(product.xp) or 100))
    local ok = pcall(function()
        local perk = Perks.FromString(product.perk)
        if not perk or perk == Perks.None or perk == Perks.MAX then
            error("unknown perk " .. tostring(product.perk))
        end
        player:getXp():AddXP(perk, amount, false, false, false, false)
    end)
    return ok, ok and amount or 0
end

-- Emergency "kind=cure" delivery: no inventory footprint, applies directly to
-- the connected player's own IsoPlayer/BodyDamage on the server, the same way
-- vanilla's own admin health-cheat commands do (ClientCommands.lua
-- Commands.player.onHealthCheatCurrentPlayer / onHealthCheat both mutate
-- otherPlayer:getBodyDamage() from the server and rely on normal player-state
-- sync to reach the client -- not a client-authoritative trick). Each step is
-- individually pcall-wrapped so one missing/renamed API in a future game
-- update degrades gracefully instead of failing the whole cure (and refunding
-- a purchase the player actually needed).
local function clearBodyPart(player, bp)
    bp:RestoreToFullHealth()
    if bp:getStiffness() > 0 then
        bp:setStiffness(0)
        if player.getFitness then
            player:getFitness():removeStiffnessValue(BodyPartType.ToString(bp:getType()))
        end
    end
    if bp:bitten() then
        bp:SetBitten(false)
        bp:SetInfected(false)
        bp:SetFakeInfected(false)
    end
    if bp:scratched() then bp:setScratched(false, true) end
    bp:setScratchTime(0)
    if bp:isCut() then bp:setCut(false) end
    bp:setCutTime(0)
    bp:setBleedingTime(0)
    bp:setDeepWoundTime(0)
    bp:setDeepWounded(false)
    bp:setFractureTime(0)
    bp:setBurnTime(0)
    if bp:haveBullet() then bp:setHaveBullet(false, 0) end
    if bp:isInfectedWound() then bp:setWoundInfectionLevel(-1) end
end

function LS.applyFullCure(player)
    if not player then return end

    local body = player.getBodyDamage and player:getBodyDamage()
    if body then
        pcall(function() body:setOverallBodyHealth(100) end)
        pcall(function() body:setInfected(false) end)
        pcall(function() body:setIsFakeInfected(false) end)
        pcall(function() body:setIsOnFire(false) end)

        local parts = body.getBodyParts and body:getBodyParts()
        if parts then
            for i = 0, parts:size() - 1 do
                local bp = parts:get(i)
                if bp then pcall(clearBodyPart, player, bp) end
            end
        end
    end

    local stats = player.getStats and player:getStats()
    if stats then
        pcall(function() stats:set(CharacterStat.ZOMBIE_INFECTION, 0) end)
        pcall(function() stats:set(CharacterStat.ZOMBIE_FEVER, 0) end)
        pcall(function() stats:set(CharacterStat.SICKNESS, 0) end)
        pcall(function() stats:set(CharacterStat.FOOD_SICKNESS, 0) end)
        pcall(function() stats:set(CharacterStat.PAIN, 0) end)
        pcall(function() stats:set(CharacterStat.POISON, 0) end)
        pcall(function() stats:set(CharacterStat.PANIC, 0) end)
        pcall(function() stats:set(CharacterStat.FATIGUE, 0) end)
        pcall(function() stats:set(CharacterStat.ENDURANCE, 1) end)
        pcall(function() stats:set(CharacterStat.HUNGER, 0) end)
        pcall(function() stats:set(CharacterStat.THIRST, 0) end)
        -- Mood, added alongside the price going dynamic: a purchase this
        -- expensive should leave the character in a genuinely good state
        -- across the board, not just physically patched up.
        pcall(function() stats:set(CharacterStat.BOREDOM, 0) end)
        pcall(function() stats:set(CharacterStat.UNHAPPINESS, 0) end)
        pcall(function() stats:set(CharacterStat.STRESS, 0) end)
        pcall(function() stats:set(CharacterStat.ANGER, 0) end)
    end
end

local function deliverCure(player)
    local ok = pcall(LS.applyFullCure, player)
    return ok, ok and 1 or 0
end

-- Vehicle placement: a purchased vehicle must land on open, solid, dry, flat
-- ground with nothing already parked there -- never inside a building (the
-- reference admin tool this was studied from spawns wherever the admin
-- manually clicks, no safety check at all, which is exactly the "not
-- perfect" gap this closes). Checked as a square clearance box around each
-- candidate anchor tile rather than the vehicle's real (rotated) footprint:
-- simpler, and safely oversized for every vanilla vehicle including buses
-- and fire trucks, at the cost of occasionally skipping a technically-valid
-- but tight gap -- an acceptable trade for a purchase that must never clip
-- into geometry.
local VEHICLE_CLEARANCE_RADIUS = 3 -- 7x7 tiles around the anchor
local VEHICLE_SEARCH_MAX_RADIUS = 60

-- `reserved` (optional) is a set of "x:y" footprint tiles already claimed by an
-- earlier vehicle line in the SAME purchase (see the CMD_PURCHASE pre-check
-- below): those haven't actually spawned yet, so isVehicleIntersecting()
-- alone can't see them, and without this a cart with two+ vehicles could
-- have every line "find" the exact same empty spot. Marking the chosen
-- clearance footprint means any later candidate whose
-- own clearance box reaches any claimed tile fails via the footprint loop
-- below, keeping the conservative clearance boxes disjoint.
local function squareClearForVehicle(cell, x, y, z, reserved, clearanceCache)
    local coordinateKey = x .. ":" .. y
    if reserved and reserved[coordinateKey] then return false end
    local cached = clearanceCache and clearanceCache[coordinateKey]
    if cached ~= nil then return cached end
    local sq = cell:getGridSquare(x, y, z)
    local clear = sq ~= nil
        and sq:getFloor() ~= nil
        and sq:isOutside()
        and not sq:has(IsoFlagType.water)
        and not sq:has(IsoFlagType.solid)
        and not sq:has(IsoFlagType.solidtrans)
        and not sq:isVehicleIntersecting()
    if clearanceCache then clearanceCache[coordinateKey] = clear end
    return clear
end

local function footprintClearForVehicle(cell, cx, cy, z, reserved, clearanceCache)
    for dx = -VEHICLE_CLEARANCE_RADIUS, VEHICLE_CLEARANCE_RADIUS do
        for dy = -VEHICLE_CLEARANCE_RADIUS, VEHICLE_CLEARANCE_RADIUS do
            if not squareClearForVehicle(cell, cx + dx, cy + dy, z, reserved, clearanceCache) then
                return false
            end
        end
    end
    return true
end

local function reserveVehicleFootprint(reserved, cx, cy)
    for dx = -VEHICLE_CLEARANCE_RADIUS, VEHICLE_CLEARANCE_RADIUS do
        for dy = -VEHICLE_CLEARANCE_RADIUS, VEHICLE_CLEARANCE_RADIUS do
            reserved[(cx + dx) .. ":" .. (cy + dy)] = true
        end
    end
end

-- First clear anchor found while walking the perimeter of the given ring
-- (Chebyshev distance == radius) around (px, py), or nil. Perimeter-only
-- keeps this O(radius) per ring instead of rescanning the whole square every
-- time, since findVehicleSpawnSquare below calls it once per growing radius.
local function firstClearInRing(cell, px, py, radius, z, reserved, clearanceCache)
    if radius == 0 then
        if footprintClearForVehicle(cell, px, py, z, reserved, clearanceCache) then return px, py end
        return nil
    end
    local x0, x1 = px - radius, px + radius
    local y0, y1 = py - radius, py + radius
    for x = x0, x1 do
        if footprintClearForVehicle(cell, x, y0, z, reserved, clearanceCache) then return x, y0 end
        if footprintClearForVehicle(cell, x, y1, z, reserved, clearanceCache) then return x, y1 end
    end
    for y = y0 + 1, y1 - 1 do
        if footprintClearForVehicle(cell, x0, y, z, reserved, clearanceCache) then return x0, y end
        if footprintClearForVehicle(cell, x1, y, z, reserved, clearanceCache) then return x1, y end
    end
    return nil
end

-- Vehicles only ever exist at ground level (z=0), regardless of which floor
-- the player is currently standing on -- searching outward from the
-- player's own (x,y) at z=0 still finds the street/yard below or beside a
-- multi-storey building correctly. Returns the square plus its x/y (the
-- caller needs the coordinates to add them to `reserved` for the next line
-- in the same cart, the square object alone doesn't expose them cheaply).
local function findVehicleSpawnSquare(player, reserved, clearanceCache)
    local cell = getCell()
    if not cell then return nil end
    local ok, px, py = pcall(function() return math.floor(player:getX()), math.floor(player:getY()) end)
    if not ok then return nil end
    local z = 0
    for radius = 0, VEHICLE_SEARCH_MAX_RADIUS do
        local ringOk, x, y = pcall(firstClearInRing,
            cell, px, py, radius, z, reserved, clearanceCache)
        if ringOk and x then
            local sq = cell:getGridSquare(x, y, z)
            if sq then return sq, x, y end
        end
    end
    return nil
end

-- Factory-fresh delivery: empty every container part (no random loot from
-- glovebox/seats/trunk), unlock doors and trunk (LockedCar sandbox settings
-- otherwise lock even a fresh delivery), full repair, full tank, and a key
-- straight into the buyer's own inventory -- not the glove box, per explicit
-- request ("da a chave... para o jogador"). Each step is isolated in its own
-- pcall so a failure in one (say, a vehicle with no GasTank part) never
-- costs the rest of the handover.
-- `square` is already resolved by the CMD_PURCHASE pre-check below, before
-- the player was ever charged -- this never searches on its own, so it can
-- only fail here if the spawn call itself rejects a square that passed
-- every one of those checks a moment earlier (should be rare).
local function deliverVehicle(player, product, square)
    if not square then return false, 0 end

    local car = nil
    pcall(function()
        local c = addVehicleDebug(product.fullType, IsoDirections.N, nil, square)
        if c and c:getId() ~= -1 then car = c end
    end)
    if not car then return false, 0 end

    pcall(function() car:setAngles(0, ZombRand(360), 0) end)
    pcall(function() car:repair() end)
    pcall(function()
        local tank = car:getPartById("GasTank")
        if tank then
            tank:setContainerContentAmount(tank:getContainerCapacity())
            car:transmitPartModData(tank)
        end
    end)
    pcall(function()
        for i = 0, car:getPartCount() - 1 do
            local part = car:getPartByIndex(i)
            local inv = part and part:getItemContainer()
            if inv then inv:removeAllItems() end
        end
    end)
    pcall(function()
        for i = 0, car:getPartCount() - 1 do
            local part = car:getPartByIndex(i)
            local door = part and part:getDoor()
            if door then
                door:setLocked(false)
                door:setLockBroken(false)
            end
        end
    end)
    pcall(function() car:setTrunkLocked(false) end)

    local skipKey = false
    pcall(function()
        local script = car:getScript()
        if script and (script:getPassengerCount() == 0 or script:neverSpawnKey()) then skipKey = true end
    end)
    if not skipKey then
        pcall(function()
            local key = car:createVehicleKey()
            if not key then return end
            pcall(function() key:setName(LS.text("VehicleKeyName", "Chave — %1", LS.productName(product))) end)
            player:getInventory():AddItem(key)
            sendAddItemToContainer(player:getInventory(), key)
        end)
    end

    return true, 1
end

local function confirmedXPDeliveries(result)
    local confirmed = {}
    local deliveries = type(result.delivered) == "table" and result.delivered or {}
    for _, delivery in ipairs(deliveries) do
        if #confirmed >= MAX_CART_LINES then break end
        local product = type(delivery) == "table" and LS.PRODUCT_BY_ID[delivery.id] or nil
        local amount = type(delivery) == "table" and finiteNumber(delivery.amount, nil) or nil
        if product and product.kind == "xp" and amount and amount > 0 then
            confirmed[#confirmed + 1] = { id = product.id, amount = amount }
        end
    end
    return #confirmed > 0 and confirmed or nil
end

local function rememberResult(rec, requestId, result)
    local isNew = rec.recentResults[requestId] == nil
    rec.recentResults[requestId] = {
        status = result.status,
        charged = result.charged,
        refunded = result.refunded,
        failedCount = result.failedCount,
        -- Small authoritative summary needed when the original multiplayer
        -- reply is lost: the idempotent replay then lets the client apply its
        -- local XP mirror once. Inventory/vehicle deliveries are intentionally
        -- not persisted here; only XP needs a client-side confirmation.
        xpDelivered = confirmedXPDeliveries(result),
        -- Retained only while status=processing. If the VM/server is torn down
        -- between the debit and the final marker, these fields leave enough
        -- evidence for an administrator to reconcile the ambiguous delivery.
        -- Automatic refunds would be unsafe: an item/vehicle may already have
        -- spawned even though the final marker never reached ModData.
        startedAt = result.status == "processing" and result.startedAt or nil,
        reservedTotal = result.status == "processing" and result.reservedTotal or nil,
        balanceBefore = result.status == "processing" and result.balanceBefore or nil,
    }
    if isNew then table.insert(rec.recentOrder, requestId) end
    trimHistoryPreservingProcessing(rec.recentResults, rec.recentOrder, MAX_RECENT_REQUESTS)
end

Commands[LS.CMD_REQUEST_STATE] = function(player, args)
    local key = accountId(player) or usernameOf(player)
    if tooSoon(lastStateRequestAt, key, REQUEST_STATE_COOLDOWN_SECONDS) then return end
    sendState(player, true)
end

Commands[LS.CMD_PURCHASE] = function(player, args)
    local rec, key = ensureAccount(player)
    if not rec then return sendError(player, "invalid_player", nil, false) end

    local requestId = args and args.requestId
    if type(requestId) ~= "string" or requestId == "" or #requestId > 80 then
        if tooSoon(lastPurchaseAttemptAt, key, PURCHASE_COOLDOWN_SECONDS) then return end
        return sendError(player, "invalid_cart", nil, false)
    end
    local previous = rec.recentResults[requestId]
    if type(previous) == "table" then
        -- Idempotent retries still get a deterministic answer, but one cached
        -- requestId cannot be spammed to force the expensive perk/state build
        -- without limit (dedup intentionally runs before new-attempt cooldowns).
        if tooSoon(lastPurchaseReplayAt, key, DEDUP_REPLAY_COOLDOWN_SECONDS) then return end
        if previous.status == "failed" then
            return sendError(player, "delivery_failed", { requestId = requestId, duplicate = true })
        elseif previous.status == "processing" then
            return sendError(player, "purchase_in_progress",
                { requestId = requestId, duplicate = true }, false)
        end
        local replay = {
            requestId = requestId,
            status = previous.status,
            charged = previous.charged,
            refunded = previous.refunded,
            failedCount = previous.failedCount,
            -- Revalidate persisted data before putting it on the wire. This is
            -- normally our own tiny summary, but old/corrupt ModData must not
            -- be able to turn a replay into an unbounded client payload.
            delivered = confirmedXPDeliveries({ delivered = previous.xpDelivered }) or {},
            duplicate = true,
            state = buildState(player),
        }
        return toClient(player, LS.CMD_PURCHASE_RESULT, replay)
    elseif previous ~= nil then
        rec.recentResults[requestId] = nil
    end
    if tooSoon(lastPurchaseAttemptAt, key, PURCHASE_COOLDOWN_SECONDS) then
        return sendError(player, "too_fast", { requestId = requestId }, false)
    end
    if isDead(player) then return sendError(player, "dead") end

    local options = LS.getOptions()
    ensureOffers(options)
    refreshCredits(player, options)
    local data = dataStore()
    local quotedRevision = integerOrNil(args and args.offerRevision)
    if quotedRevision == nil or quotedRevision ~= data.offerRevision then
        return sendError(player, "prices_changed")
    end

    local lines = normalizeCart(args and args.items)
    if not lines then return sendError(player, "invalid_cart") end

    local total = 0
    local vehicleCount = 0
    local pricing = {
        data = data,
        options = options,
        commerceDiscount = commerceDiscountFor(player),
    }
    for _, line in ipairs(lines) do
        line.unitPrice, line.originalPrice, line.xpAmount, line.perkLevel =
            currentPrice(player, line.product, line.qty, pricing)
        if line.product.kind == "xp" and (line.perkLevel >= 10 or line.xpAmount <= 0) then
            return sendError(player, "skill_maxed", { perk = line.product.perk })
        end
        if line.product.kind == "xp" and line.qty > 10 - line.perkLevel then
            return sendError(player, "xp_level_limit", {
                perk = line.product.perk,
                maxQuantity = 10 - line.perkLevel,
            })
        end
        if line.product.kind == "cure" and line.qty > 1 then
            return sendError(player, "cure_single_only", { maxQuantity = 1 })
        end
        if line.product.kind == "vehicle" and line.qty > 1 then
            return sendError(player, "vehicle_single_only", { maxQuantity = 1 })
        end
        if line.product.kind == "vehicle" then
            vehicleCount = vehicleCount + 1
            if vehicleCount > MAX_VEHICLE_LINES then
                return sendError(player, "vehicle_cart_limit", { maxQuantity = MAX_VEHICLE_LINES })
            end
        end
        line.linePrice = line.product.kind == "xp" and line.unitPrice or line.unitPrice * line.qty
        total = total + line.linePrice
    end
    local quotedTotal = integerOrNil(args and args.quotedTotal)
    if quotedTotal == nil or quotedTotal ~= total then
        return sendError(player, "prices_changed", { expectedTotal = total })
    end
    if rec.balance + 0.0001 < total then
        return sendError(player, "insufficient_credits", { required = total })
    end

    -- Placement is the expensive preflight, so it deliberately happens only
    -- after revision, price and balance checks. Reserve each full 7x7 clearance
    -- footprint (not merely its anchor) so multiple vehicles in one cart cannot
    -- be assigned overlapping spawn zones before any of them exists in-world.
    local vehicleReserved = {}
    -- Neighbouring candidate footprints overlap heavily. Cache the physical
    -- result for each grid square across every vehicle in this one request;
    -- the worst-case radius-60 search then asks the engine about ~16k unique
    -- squares instead of re-reading up to ~700k overlapping square checks per
    -- vehicle. Same-request reservations remain a separate live check above.
    local vehicleClearanceCache = {}
    if vehicleCount > 0 then
        for _, line in ipairs(lines) do
            if line.product.kind == "vehicle" then
                local square, sx, sy = findVehicleSpawnSquare(player,
                    vehicleReserved, vehicleClearanceCache)
                if not square then return sendError(player, "vehicle_no_space") end
                line.vehicleSquare = square
                reserveVehicleFootprint(vehicleReserved, sx, sy)
            end
        end
    end

    -- Reserve the full amount before item creation. Lua command handlers execute
    -- sequentially, so another request cannot spend the same balance in between.
    -- Persisting a processing marker first also makes a retry fail closed if an
    -- unexpected exception/restart interrupts the delivery after side effects.
    -- This blocks only a retry of this requestId, never the account or later
    -- purchases. We deliberately do not auto-refund a stale marker because its
    -- delivery side effects may have committed immediately before interruption.
    local balanceBefore = rec.balance
    rememberResult(rec, requestId, {
        status = "processing", charged = 0, refunded = 0, failedCount = 0,
        startedAt = nowSeconds(), reservedTotal = total, balanceBefore = balanceBefore,
    })
    rec.balance = LS.roundCredits(rec.balance - total)
    local charged, failedCount, delivered = 0, 0, {}
    for _, line in ipairs(lines) do
        local ok, amount, expectedAmount
        local callOk, callErr = pcall(function()
            if line.product.kind == "item" then
                ok, amount, expectedAmount = deliverItem(player, line.product, line.qty)
            elseif line.product.kind == "xp" then
                ok, amount = deliverXP(player, line.product, line.xpAmount)
            elseif line.product.kind == "vehicle" then
                ok, amount = deliverVehicle(player, line.product, line.vehicleSquare)
            else
                ok, amount = deliverCure(player)
            end
        end)
        if not callOk then
            ok, amount = false, 0
            LS.log("ERROR delivering " .. tostring(line.product.id) .. ": " .. tostring(callErr))
        end
        if ok then
            charged = charged + line.linePrice
            table.insert(delivered, {
                id = line.product.id, qty = line.qty, amount = amount,
                xpAmount = line.xpAmount, perk = line.product.perk,
            })
        else
            failedCount = failedCount + 1
            -- AddItems can theoretically return fewer objects than requested
            -- (modded container/item edge cases). Those objects already exist
            -- and cannot be treated as a failed/refunded line: charge only the
            -- delivered fraction and report the purchase as partial.
            if line.product.kind == "item" and amount and amount > 0
                and expectedAmount and expectedAmount > 0 then
                local deliveredFraction = math.min(1, amount / expectedAmount)
                charged = charged + LS.roundCredits(line.linePrice * deliveredFraction)
                table.insert(delivered, {
                    id = line.product.id, qty = line.qty, amount = amount,
                })
            end
            LS.log(string.format("WARNING: delivery failed for %s x%d (%s)",
                tostring(line.product.id), line.qty, tostring(usernameOf(player))))
        end
    end

    charged = LS.roundCredits(charged)
    local refunded = LS.roundCredits(total - charged)
    if refunded > 0 then rec.balance = LS.roundCredits(rec.balance + refunded) end
    rec.lifetimeSpent = LS.roundCredits(rec.lifetimeSpent + charged)
    rec.updatedAt = nowSeconds()
    local status = failedCount == 0 and "completed" or (charged > 0 and "partial" or "failed")
    local result = {
        requestId = requestId,
        status = status,
        charged = charged,
        refunded = refunded,
        failedCount = failedCount,
        delivered = delivered,
    }
    rememberResult(rec, requestId, result)
    LS.log(string.format("purchase %s: user=%s charged=%s lines=%d failed=%d balance=%s",
        requestId, tostring(usernameOf(player)), LS.formatCredits(charged), #lines,
        failedCount, LS.formatCredits(rec.balance)))

    if status == "failed" then
        return sendError(player, "delivery_failed", { requestId = requestId })
    end
    result.state = buildState(player)
    toClient(player, LS.CMD_PURCHASE_RESULT, result)
end

-- ===================================================================
-- Player-to-player credit transfer. Server-authoritative end to end: the
-- client only ever supplies a target username and an amount, every other
-- fact (sender alive, sender's real balance, target genuinely online right
-- now) is re-derived here rather than trusted from the request. Reuses
-- LS.spendCredits/LS.grantCredits -- the same hardened primitives the
-- faction tribute cross-mod boundary already relies on -- instead of
-- hand-rolling a second balance-mutation path.
-- ===================================================================

local TRANSFER_MIN_AMOUNT = 1
local TRANSFER_MAX_AMOUNT = 1000000
local TRANSFER_COOLDOWN_SECONDS = 3

-- In-memory only, keyed by account key (not username): a server restart
-- resetting everyone's cooldown is harmless, so this doesn't need to be
-- persisted the way the request-id dedup ledger below does.
local lastTransferAttemptAt = {}
local lastTransferReplayAt = {}

local function onlinePlayerList(excludeUsername)
    local list = {}
    eachOnlinePlayer(function(other)
        local name = usernameOf(other)
        if name and name ~= excludeUsername then table.insert(list, name) end
    end)
    table.sort(list, function(a, b) return string.lower(a) < string.lower(b) end)
    return list
end

Commands[LS.CMD_TRANSFER_LIST] = function(player, args)
    local key = accountId(player) or usernameOf(player)
    if tooSoon(lastTransferListRequestAt, key, TRANSFER_LIST_COOLDOWN_SECONDS) then return end
    toClient(player, LS.CMD_TRANSFER_LIST, { players = onlinePlayerList(usernameOf(player)) })
end

local function sendTransferResult(player, ok, reason, extra, includeState)
    local args = extra or {}
    args.ok = ok
    if reason then args.reason = reason end
    if includeState ~= false then args.state = buildState(player) end
    toClient(player, LS.CMD_TRANSFER_RESULT, args)
end

-- Records the final outcome (persisted, for replay on a retried requestId --
-- same reasoning as rememberResult for purchases) and replies to the
-- sender. The rate-limit rejection path deliberately does NOT go through
-- here: it's transient in-memory state, not a business outcome worth
-- remembering forever.
local function finishTransfer(rec, requestId, player, ok, reason, amount, target)
    local isNew = rec.recentTransfers[requestId] == nil
    rec.recentTransfers[requestId] = {
        status = "completed", ok = ok, reason = reason, amount = amount,
        target = target, completedAt = nowSeconds(),
    }
    if isNew then table.insert(rec.recentTransferOrder, requestId) end
    trimHistoryPreservingProcessing(rec.recentTransfers, rec.recentTransferOrder, MAX_RECENT_TRANSFERS)
    sendTransferResult(player, ok, reason,
        { requestId = requestId, amount = amount, target = target })
end

local function beginTransfer(rec, requestId, amount, target)
    local isNew = rec.recentTransfers[requestId] == nil
    rec.recentTransfers[requestId] = {
        status = "processing", ok = false, reason = "transfer_in_progress",
        amount = amount, target = target, startedAt = nowSeconds(),
    }
    if isNew then table.insert(rec.recentTransferOrder, requestId) end
    trimHistoryPreservingProcessing(rec.recentTransfers, rec.recentTransferOrder, MAX_RECENT_TRANSFERS)
end

Commands[LS.CMD_TRANSFER] = function(player, args)
    local senderName = usernameOf(player)
    if not senderName then return sendTransferResult(player, false, "invalid_player", nil, false) end
    local rec, key = ensureAccount(player)
    if not rec then return sendTransferResult(player, false, "invalid_player", nil, false) end

    local requestId = args and args.requestId
    if type(requestId) ~= "string" or requestId == "" or #requestId > 80 then
        if tooSoon(lastTransferAttemptAt, key, TRANSFER_COOLDOWN_SECONDS) then return end
        return sendTransferResult(player, false, "invalid_request", nil, false)
    end
    local previous = rec.recentTransfers[requestId]
    if type(previous) == "table" then
        if tooSoon(lastTransferReplayAt, key, DEDUP_REPLAY_COOLDOWN_SECONDS) then return end
        if previous.status == "processing" then
            return sendTransferResult(player, false, "transfer_in_progress", {
                requestId = requestId, amount = previous.amount,
                target = previous.target, duplicate = true,
            }, false)
        end
        return sendTransferResult(player, previous.ok, previous.reason,
            { requestId = requestId, amount = previous.amount,
                target = previous.target, duplicate = true })
    elseif previous ~= nil then
        rec.recentTransfers[requestId] = nil
    end

    -- Independent of the dedup above: a genuinely NEW request arriving too
    -- soon after the last one. Checked (and only armed) after the dedup
    -- replay so retries of an already-answered request never eat into it.
    if tooSoon(lastTransferAttemptAt, key, TRANSFER_COOLDOWN_SECONDS) then
        return sendTransferResult(player, false, "too_fast", { requestId = requestId }, false)
    end
    if isDead(player) then
        return sendTransferResult(player, false, "dead", { requestId = requestId })
    end

    local targetName = args and args.target
    if type(targetName) ~= "string" or targetName == "" or #targetName > 64 then
        return finishTransfer(rec, requestId, player, false, "invalid_target")
    end
    if targetName == senderName then
        return finishTransfer(rec, requestId, player, false, "self_target")
    end

    local amount = integerOrNil(args and args.amount)
    if not amount or amount < TRANSFER_MIN_AMOUNT or amount > TRANSFER_MAX_AMOUNT then
        return finishTransfer(rec, requestId, player, false, "invalid_amount")
    end

    -- Re-validated against the live player list right now -- never trust the
    -- client's own (possibly several-seconds-stale) copy of who's online.
    local targetPlayer = nil
    eachOnlinePlayer(function(other)
        if not targetPlayer and usernameOf(other) == targetName then targetPlayer = other end
    end)
    if not targetPlayer then
        return finishTransfer(rec, requestId, player, false, "target_offline")
    end

    -- Reuses the generic API primitive (see "Public credits API" section
    -- above) instead of hand-rolling a second spend+grant pair -- the
    -- target-online check above ensures the identity is genuine; if their shop
    -- account has not been initialised during this login yet, the API may still
    -- use its normal short-lived queue and flush it on the next refresh.
    -- Persist the request before crossing into the two-account mutation. If the
    -- call throws after either ledger changed, a retry remains fail-closed instead
    -- of moving the same credits twice.
    beginTransfer(rec, requestId, amount, targetName)
    local callOk, transferOk, transferReason = pcall(
        LS.transferCredits, senderName, targetName, amount)
    if not callOk then
        LS.log(string.format("ERROR: transfer %s became ambiguous: %s",
            requestId, tostring(transferOk)))
        return sendTransferResult(player, false, "transfer_status_unknown", {
            requestId = requestId, amount = amount, target = targetName,
        }, false)
    end
    if not transferOk then
        return finishTransfer(rec, requestId, player, false, transferReason or "insufficient_credits", amount, targetName)
    end

    LS.log(string.format("transfer %s: %s -> %s, %s credits",
        requestId, senderName, targetName, LS.formatCredits(amount)))
    -- Finalize before the cosmetic recipient notification. Even if that packet
    -- throws/is lost, the sender can replay the persisted definitive result.
    finishTransfer(rec, requestId, player, true, nil, amount, targetName)
    local haloOk, haloErr = pcall(toClient, targetPlayer, LS.CMD_CREDITS_RECEIVED,
        { amount = amount, fromUsername = senderName })
    if not haloOk then LS.log("recipient transfer notification failed: " .. tostring(haloErr)) end
end

-- ===================================================================
-- Kill credit steal: killing another player pays out a sandbox-configured
-- percentage of the VICTIM's balance (0 = off, 100 = the whole thing),
-- right before resetOnDeath either wipes the remaining balance or preserves it
-- according to the sandbox option.
--
-- Deliberately does NOT read character:getAttackedBy() at death time --
-- that field has no built-in expiry (LFS_FriendlyFire.lua already has to
-- clear it by hand after reverting a friendly-fire hit, which wouldn't be
-- necessary if it faded on its own), so a single graze from days ago would
-- still be sitting there and misattribute an unrelated later death (hunger,
-- thirst, a zombie...) to whoever threw that graze. Instead this tracks
-- real player-on-player weapon hits itself, in memory, with a short shelf
-- life -- only a hit inside that window counts toward the kill.
--
-- Cost-conscious by construction: OnWeaponHitCharacter fires on every
-- single weapon swing server-wide (including the constant stream of
-- players hitting zombies), so the handler bails on one cheap boolean
-- check whenever the feature is off, and otherwise still fails fast for
-- any hit that isn't player-vs-player before touching anything else.
-- ---------------------------------------------------------------------

-- Both refreshed every periodicTick (every TICK_SECONDS) instead of
-- re-reading LS.getOptions() on every single hit -- that hot path needs to
-- stay a plain number comparison. killCreditStealWindowSeconds (sandbox,
-- default 900s/15min) is how long a recorded hit still counts toward a
-- kill: generous enough to cover a real firefight or someone bleeding out
-- from the wound that actually killed them, short enough that "wounded,
-- wandered off, died of something unrelated hours/days later" never
-- qualifies.
local cachedKillStealPercent = 0
local cachedKillStealWindowSeconds = 900

-- [victimUsername] = { attacker = attackerUsername, at = epochSeconds }.
-- In-memory only and intentionally not persisted -- a server restart losing a
-- few seconds of "who hit whom" is harmless. periodicTick also expires entries,
-- so the table is bounded by recently-hit victims rather than every username
-- the server has ever seen.
local recentPlayerHitBy = {}

-- A hit that the faction system immediately reverses must not remain eligible
-- to claim an unrelated death minutes later. Prefer LFS's shared read-only
-- policy helper so both systems have one definition; the fallback preserves
-- compatibility with older/partially-loaded LFS builds. All calls are guarded
-- so Shop remains standalone if the faction subsystem failed to load.
local function factionPairIsProtected(attackerName, victimName)
    local factions = rawget(_G, "LasciviousFactionsSystem")
    if factions and type(factions.isFriendlyFireProtected) == "function" then
        local ok, protected = pcall(factions.isFriendlyFireProtected, attackerName, victimName)
        return ok and protected == true
    end
    if not (factions and factions.getOptions and factions.getFactionOfPlayer) then return false end
    local ok, protected = pcall(function()
        local options = factions.getOptions()
        if not options or options.enforceFriendlyFire == false then return false end
        local attackerFactionName, attackerFaction = factions.getFactionOfPlayer(attackerName)
        if not attackerFactionName then return false end
        local victimFactionName = factions.getFactionOfPlayer(victimName)
        if victimFactionName ~= attackerFactionName then return false end
        local faction = attackerFaction
        if not faction and factions.getFaction then faction = factions.getFaction(attackerFactionName) end
        return faction ~= nil and faction.friendlyFire ~= true
    end)
    return ok and protected == true
end

local function onWeaponHitCharacter(attacker, victim, weapon, damage)
    if cachedKillStealPercent <= 0 then return end
    if not attacker or not victim then return end
    if damage ~= nil then
        local safeDamage = finiteNumber(damage, nil)
        if not safeDamage or safeDamage <= 0 then return end
    end
    pcall(function()
        -- IsoAnimal extends IsoPlayer in B42 -- isAnimal() must be checked
        -- before trusting instanceof(..., "IsoPlayer") on either side.
        if not instanceof(victim, "IsoPlayer") or victim:isAnimal() then return end
        if not instanceof(attacker, "IsoPlayer") or attacker:isAnimal() then return end
        local victimName = usernameOf(victim)
        local attackerName = usernameOf(attacker)
        if not victimName or not attackerName or victimName == attackerName then return end
        if factionPairIsProtected(attackerName, victimName) then return end
        recentPlayerHitBy[victimName] = { attacker = attackerName, at = nowSeconds() }
    end)
end

-- Pays out the killer's cut (if any), debits the victim, and clears the tracked
-- hit either way -- called from resetOnDeath below before it applies the normal
-- death reset/preserve rule.
local function payKillCreditSteal(character, rec, key)
    local victimName = usernameOf(character)
    if not victimName then return end
    local hit = recentPlayerHitBy[victimName]
    recentPlayerHitBy[victimName] = nil
    if not hit then return end
    if nowSeconds() - hit.at > cachedKillStealWindowSeconds then return end
    local percent = cachedKillStealPercent
    local victimBalance = LS.roundCredits(math.max(0, finiteNumber(rec.balance, 0)))
    if percent <= 0 or victimBalance <= 0 then return end
    local cut = LS.roundCredits(victimBalance * percent / 100)
    if cut <= 0 then return end
    -- Taxed by the KILLER's own faction tribute rate, same as any other
    -- credit they earn -- this originally paid the full `cut` straight to
    -- the attacker with no tribute deduction at all, unlike refreshCredits'
    -- own killHourEarned handling above (which already routes through
    -- LasciviousFactionsSystem.creditTributeFromEarnings). Same defensive,
    -- optional cross-mod call: if LFS isn't loaded or the killer isn't in a
    -- taxed faction, netCut just stays the full cut.
    local netCut = cut
    if LasciviousFactionsSystem and LasciviousFactionsSystem.creditTributeFromEarnings then
        local ok, net = pcall(LasciviousFactionsSystem.creditTributeFromEarnings, hit.attacker, cut)
        local safeNet = ok and finiteNumber(net, nil) or nil
        if safeNet then netCut = math.max(0, math.min(cut, safeNet)) end
    end
    rec.balance = LS.roundCredits(math.max(0, victimBalance - cut))
    -- Queued rather than granted directly: the killer is almost always
    -- online (they just landed the fatal hit a moment ago), but this stays
    -- correct even in the freak case they disconnect in the same instant.
    if netCut > 0 then
        LS.queueCredits(hit.attacker, netCut, "kill_credit_steal_from:" .. tostring(key))
    end
    LS.log(string.format("kill credit steal: %s killed %s, victim -%s credits, attacker +%s credits (%s%% of %s, tribute-adjusted from %s)",
        hit.attacker, victimName, LS.formatCredits(cut), LS.formatCredits(netCut),
        LS.formatCredits(percent), LS.formatCredits(victimBalance), LS.formatCredits(cut)))
end

local function resetOnDeath(character)
    if not character or not instanceof(character, "IsoPlayer") then return end
    -- B42 IsoAnimal may satisfy the IsoPlayer inheritance check.  Keep this
    -- defensive so an older runtime without isAnimal() still behaves normally.
    local animalCheckOk, animal = pcall(function() return character:isAnimal() end)
    if animalCheckOk and animal == true then return end
    local ok, err = pcall(function()
        local rec, key = ensureAccount(character)
        if not rec then
            local username = usernameOf(character)
            key = username and dataStore().usernameIndex[username] or nil
            rec = key and dataStore().accounts[key] or nil
        end
        if not rec then return end
        -- Isolated in its own pcall: a failure here must never be able to
        -- skip the balance reset below, which is the one thing this whole
        -- function absolutely must still do.
        local stealOk, stealErr = pcall(payKillCreditSteal, character, rec, key)
        if not stealOk then LS.log("ERROR in kill credit steal: " .. tostring(stealErr)) end
        local preserveBalance = LS.getOptions().preserveCreditsOnDeath == true
        rec.initialized = true
        if preserveBalance then
            rec.balance = LS.roundCredits(math.max(0, finiteNumber(rec.balance, 0)))
        else
            rec.balance = 0
        end
        rec.lastKills = 0
        rec.lastHours = 0
        rec.debugCreditsGranted = false
        -- Preserve account-level request replay/tombstone history across death.
        -- Clearing it here allowed a delayed packet for an already delivered
        -- purchase to execute again in the next character life.
        rec.updatedAt = nowSeconds()
        rec.source = preserveBalance and "character_death_preserved" or "character_death"
        if preserveBalance then
            LS.log("credits preserved on death for " .. tostring(usernameOf(character) or key))
        else
            LS.log("credits reset on death for " .. tostring(usernameOf(character) or key))
        end
    end)
    if not ok then LS.log("ERROR resetting death credits: " .. tostring(err)) end
end

-- A pending grant nobody ever claims almost always means the calling mod
-- queued it against a typo'd or long-abandoned identity, not a player who's
-- simply taking their time to log back in. Dropped (not silently, so a
-- server owner grepping logs can catch a systematically wrong identity
-- before it happens a hundred more times) after this long with no matching
-- account. Checked at its own slow cadence, independent of TICK_SECONDS --
-- this never needs to be prompt.
local PENDING_EXPIRY_SECONDS = 90 * 24 * 3600
local PENDING_SWEEP_INTERVAL_SECONDS = 6 * 3600
local lastPendingSweepAt = 0

local function sweepPendingCredits()
    local now = nowSeconds()
    if now - lastPendingSweepAt < PENDING_SWEEP_INTERVAL_SECONDS then return end
    lastPendingSweepAt = now
    local data = dataStore()
    for key, list in pairs(data.pendingCredits) do
        local kept = {}
        if type(list) == "table" then
            for _, entry in ipairs(list) do
                local queuedAt = type(entry) == "table" and finiteNumber(entry.queuedAt, nil) or nil
                local amount = type(entry) == "table" and finiteNumber(entry.amount, nil) or nil
                if queuedAt and amount and amount > 0 and amount <= MAX_API_CREDIT_AMOUNT
                    and now - queuedAt < PENDING_EXPIRY_SECONDS then
                    table.insert(kept, entry)
                else
                    local queuedLabel = queuedAt and os.date("%Y-%m-%d", queuedAt) or "invalid"
                    LS.log(string.format(
                        "WARNING: dropped expired/invalid queued grant of %s credits for '%s' (queued %s, reason '%s')",
                        LS.formatCredits(amount), tostring(key), queuedLabel,
                        tostring(type(entry) == "table" and entry.reason or "invalid_entry")))
                end
            end
        end
        data.pendingCredits[key] = #kept > 0 and kept or nil
    end
end

local function validSteamAccountKey(key)
    if type(key) ~= "string" then return nil end
    local sid = string.match(key, "^steam:(%d+)$")
    if not sid then return nil end
    sid = LasciviousSystemsSteamId.isValid(sid)
    return sid and ("steam:" .. sid) or nil, sid
end

local function reconcileSteamPendingCredits()
    local data = dataStore()
    local keys = {}
    for key in pairs(data.pendingCredits) do
        if validSteamAccountKey(key) then keys[#keys + 1] = key end
    end

    for _, key in ipairs(keys) do
        local canonicalKey, sid = validSteamAccountKey(key)
        local list = data.pendingCredits[key]
        if canonicalKey and type(list) == "table" and #list > 0 then
            local discordAmount = nil
            for _, entry in ipairs(list) do
                if type(entry) == "table" and entry.reason == "discord_verification" then
                    local amount = finiteNumber(entry.amount, nil)
                    if amount and amount > 0 and amount <= MAX_API_CREDIT_AMOUNT then
                        discordAmount = amount
                        break
                    end
                end
            end

            if discordAmount then
                LS.grantExternalRewardOnce({ steamId = sid }, "discord_verification", discordAmount, "startup_pending_reconcile")
                list = data.pendingCredits[key]
            end

            if type(list) == "table" and #list > 0 then
                local rec = normalizeAccountRecord(data.accounts[canonicalKey])
                data.accounts[canonicalKey] = rec
                flushPendingCredits(rec, canonicalKey)
                LS.log("reconciled generic pending credits into exact Steam account '" .. canonicalKey .. "' at startup")
            end

            if key ~= canonicalKey and data.pendingCredits[key] then
                data.pendingCredits[key] = nil
            end
        end
    end
end

local TRANSIENT_SWEEP_INTERVAL_SECONDS = 10 * 60
local TRANSIENT_RETENTION_SECONDS = 60 * 60
local lastTransientSweepAt = 0

local function pruneTimestampBucket(bucket, cutoff)
    for key, timestamp in pairs(bucket) do
        if finiteNumber(timestamp, 0) < cutoff then bucket[key] = nil end
    end
end

local function sweepTransientState(now)
    if now - lastTransientSweepAt < TRANSIENT_SWEEP_INTERVAL_SECONDS then return end
    lastTransientSweepAt = now
    local cutoff = now - TRANSIENT_RETENTION_SECONDS
    pruneTimestampBucket(lastStateRequestAt, cutoff)
    pruneTimestampBucket(lastPurchaseAttemptAt, cutoff)
    pruneTimestampBucket(lastPurchaseReplayAt, cutoff)
    pruneTimestampBucket(lastTransferListRequestAt, cutoff)
    pruneTimestampBucket(lastTransferAttemptAt, cutoff)
    pruneTimestampBucket(lastTransferReplayAt, cutoff)
    for victimName, hit in pairs(recentPlayerHitBy) do
        local hitAt = type(hit) == "table" and finiteNumber(hit.at, 0) or 0
        if now - hitAt > cachedKillStealWindowSeconds then recentPlayerHitBy[victimName] = nil end
    end
end

local function periodicTick()
    local now = nowSeconds()
    if now - lastTickAt < TICK_SECONDS then return end
    lastTickAt = now
    local opts = LS.getOptions()
    local offersChanged = ensureOffers(opts)
    local hash = runtimeConfigHash(opts)
    local configChanged = lastRuntimeConfigHash ~= nil and lastRuntimeConfigHash ~= hash
    lastRuntimeConfigHash = hash
    cachedKillStealPercent = opts.killCreditStealPercent
    cachedKillStealWindowSeconds = opts.killCreditStealWindowSeconds
    eachOnlinePlayer(function(player)
        local creditsChanged = refreshCredits(player, opts)
        if offersChanged or configChanged or creditsChanged then sendState(player, false, opts) end
    end)
    sweepPendingCredits()
    sweepTransientState(now)
end

local processingMarkersAudited = false
local PROCESSING_AUDIT_DETAIL_LIMIT = 20

local function auditInterruptedPurchases()
    if processingMarkersAudited then return end
    processingMarkersAudited = true
    local data = dataStore()
    local count = 0
    for accountKey, rec in pairs(data.accounts) do
        if type(rec) == "table" and type(rec.recentResults) == "table" then
            for requestId, result in pairs(rec.recentResults) do
                if type(result) == "table" and result.status == "processing" then
                    count = count + 1
                    if count <= PROCESSING_AUDIT_DETAIL_LIMIT then
                        local startedAt = finiteNumber(result.startedAt, nil)
                        local age = startedAt and math.max(0, nowSeconds() - startedAt) or nil
                        local reserved = finiteNumber(result.reservedTotal, nil)
                        local balanceBefore = finiteNumber(result.balanceBefore, nil)
                        LS.log(string.format(
                            "WARNING: unresolved fail-closed purchase marker: account=%s request=%s age=%s reserved=%s balanceBefore=%s currentBalance=%s; delivery outcome is ambiguous, no automatic refund applied",
                            tostring(accountKey), tostring(requestId), age and tostring(age) .. "s" or "unknown",
                            reserved and LS.formatCredits(reserved) or "unknown",
                            balanceBefore and LS.formatCredits(balanceBefore) or "unknown",
                            LS.formatCredits(rec.balance)))
                    end
                end
            end
        end
    end
    if count > PROCESSING_AUDIT_DETAIL_LIMIT then
        LS.log(string.format("WARNING: %d additional unresolved purchase marker(s) omitted from startup detail log",
            count - PROCESSING_AUDIT_DETAIL_LIMIT))
    end

    local transferCount = 0
    for accountKey, rec in pairs(data.accounts) do
        if type(rec) == "table" and type(rec.recentTransfers) == "table" then
            for requestId, result in pairs(rec.recentTransfers) do
                if type(result) == "table" and result.status == "processing" then
                    transferCount = transferCount + 1
                    if transferCount <= PROCESSING_AUDIT_DETAIL_LIMIT then
                        local startedAt = finiteNumber(result.startedAt, nil)
                        local age = startedAt and math.max(0, nowSeconds() - startedAt) or nil
                        LS.log(string.format(
                            "WARNING: unresolved fail-closed transfer marker: account=%s request=%s age=%s target=%s amount=%s; outcome is ambiguous, no automatic retry/refund applied",
                            tostring(accountKey), tostring(requestId),
                            age and tostring(age) .. "s" or "unknown",
                            tostring(result.target), LS.formatCredits(result.amount)))
                    end
                end
            end
        end
    end
    if transferCount > PROCESSING_AUDIT_DETAIL_LIMIT then
        LS.log(string.format("WARNING: %d additional unresolved transfer marker(s) omitted from startup detail log",
            transferCount - PROCESSING_AUDIT_DETAIL_LIMIT))
    end
end

local function initialise()
    validateCatalog()
    local opts = LS.getOptions()
    ensureOffers(opts)
    reconcileSteamPendingCredits()
    lastRuntimeConfigHash = runtimeConfigHash(opts)
    cachedKillStealPercent = opts.killCreditStealPercent
    cachedKillStealWindowSeconds = opts.killCreditStealWindowSeconds
    auditInterruptedPurchases()
    LS.log("server ready")
end

local function onClientCommand(module, command, player, args)
    if module ~= LS.MODULE or not player then return end
    local handler = Commands[command]
    if not handler then return end
    -- Network payloads are untrusted. Coercing a non-table to an empty request
    -- lets the command's normal validation/rate limit handle it instead of
    -- throwing before those protections and becoming a log-spam primitive.
    local safeArgs = type(args) == "table" and args or {}
    local ok, err = pcall(handler, player, safeArgs)
    if not ok then
        LS.log("ERROR handling command " .. tostring(command) .. ": " .. tostring(err))
        if command == LS.CMD_TRANSFER then
            pcall(function()
                sendTransferResult(player, false, "server_error",
                    { requestId = safeArgs.requestId }, false)
            end)
        elseif command == LS.CMD_TRANSFER_LIST then
            pcall(function() toClient(player, LS.CMD_TRANSFER_LIST, { players = {} }) end)
        else
            pcall(function() sendError(player, "server_error") end)
        end
    end
end

-- Development reloads must replace hooks, not stack parallel economy handlers.
-- Duplicate OnClientCommand/OnCharacterDeath callbacks would be economically
-- observable even with request dedup (earn/reset paths are not all commands).
local oldHooks = LS._serverHooks
if oldHooks then
    if oldHooks.clientCommand and Events.OnClientCommand.Remove then Events.OnClientCommand.Remove(oldHooks.clientCommand) end
    if oldHooks.characterDeath and Events.OnCharacterDeath.Remove then Events.OnCharacterDeath.Remove(oldHooks.characterDeath) end
    if oldHooks.tick and Events.OnTick.Remove then Events.OnTick.Remove(oldHooks.tick) end
    if oldHooks.serverStarted and Events.OnServerStarted and Events.OnServerStarted.Remove then
        Events.OnServerStarted.Remove(oldHooks.serverStarted)
    end
    if oldHooks.gameStart and Events.OnGameStart and Events.OnGameStart.Remove then
        Events.OnGameStart.Remove(oldHooks.gameStart)
    end
    if oldHooks.weaponHit and Events.OnWeaponHitCharacter and Events.OnWeaponHitCharacter.Remove then
        Events.OnWeaponHitCharacter.Remove(oldHooks.weaponHit)
    end
end
LS._serverHooks = {
    clientCommand = onClientCommand,
    characterDeath = resetOnDeath,
    tick = periodicTick,
    serverStarted = initialise,
    gameStart = initialise,
    weaponHit = Events.OnWeaponHitCharacter and onWeaponHitCharacter or nil,
}
Events.OnClientCommand.Add(onClientCommand)
Events.OnCharacterDeath.Add(resetOnDeath)
Events.OnTick.Add(periodicTick)
if Events.OnServerStarted then Events.OnServerStarted.Add(initialise) end
if Events.OnGameStart then Events.OnGameStart.Add(initialise) end
if Events.OnWeaponHitCharacter then
    Events.OnWeaponHitCharacter.Add(onWeaponHitCharacter)
else
    LS.log("WARNING: OnWeaponHitCharacter unavailable; kill credit steal disabled")
end
