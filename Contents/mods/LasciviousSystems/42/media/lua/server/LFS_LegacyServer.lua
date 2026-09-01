if isClient() and not isCoopHost() then
    return
end

require "LFS_Shared"
require "LFS_Upgrades"
require "LasciviousSystems_SteamId"
require "LasciviousSystems_Identity"

local FF = LasciviousFactionsSystem

FF.Legacy = type(FF.Legacy) == "table" and FF.Legacy or {}
local Legacy = FF.Legacy

Legacy.STORE_KEY = "LasciviousFactionsSystem_LegacyV1"

local XP_CACHE_INTERVAL_MS = 7000
local XP_CACHE_TTL_MS = 60000
local XP_RETRY_INTERVAL_MS = 1500
local XP_RETRY_LIMIT = 5
local MAX_XP_PER_PERK = 1000000000

Legacy._xpCache = type(Legacy._xpCache) == "table" and Legacy._xpCache or {}
Legacy._retryQueue = type(Legacy._retryQueue) == "table" and Legacy._retryQueue or {}

local function finiteNumber(value, fallback)
    value = tonumber(value)
    if not value or value ~= value or value == math.huge or value == -math.huge then
        return fallback
    end
    return value
end

local function nowMs()
    if Calendar and Calendar.getInstance then
        local ok, value = pcall(function() return Calendar.getInstance():getTimeInMillis() end)
        if ok then return math.max(0, math.floor(finiteNumber(value, 0))) end
    end
    if getTimestampMs then return math.max(0, math.floor(finiteNumber(getTimestampMs(), 0))) end
    return math.max(0, math.floor(finiteNumber(getTimestamp and getTimestamp() or 0, 0) * 1000))
end

local function usernameOf(player)
    if not (player and player.getUsername) then return nil end
    local ok, username = pcall(function() return player:getUsername() end)
    if ok and type(username) == "string" and username ~= "" and #username <= 64 then
        return username
    end
    return nil
end

local function characterNameOf(player)
    if not player then return "?" end
    if player.getFullName then
        local ok, name = pcall(function() return player:getFullName() end)
        if ok and type(name) == "string" and name ~= "" then return name end
    end
    return usernameOf(player) or "?"
end

local function accountKey(player)
    if not player then return nil end
    local okIdentity, identityKey = pcall(function()
        return LasciviousSystemsIdentity and LasciviousSystemsIdentity.resolvePlayer(player) or nil
    end)
    if okIdentity and type(identityKey) == "string" and identityKey ~= "" then return identityKey end
    local ok, key = pcall(function() return LasciviousSystemsSteamId.accountKey(player) end)
    if ok and type(key) == "string" and key ~= "" then return key end
    local username = usernameOf(player)
    return username and ("name:" .. username) or nil
end

local function accountIdFragment(accountId)
    local text = tostring(accountId or "unknown")
    text = string.gsub(text, "[^%w%-%_%.%:]", "_")
    if #text > 96 then text = string.sub(text, 1, 96) end
    return text
end

local function dataStore()
    local data = ModData.getOrCreate(Legacy.STORE_KEY)
    if type(data) ~= "table" then
        data = {}
        ModData.add(Legacy.STORE_KEY, data)
    end
    data.schemaVersion = 1
    if type(data.accounts) ~= "table" then data.accounts = {} end
    data.sequence = math.max(0, math.floor(finiteNumber(data.sequence, 0)))
    return data
end

local function ensureAccountRecord(accountId, create)
    if type(accountId) ~= "string" or accountId == "" then return nil, nil end
    local data = dataStore()
    local rec = data.accounts[accountId]
    if type(rec) ~= "table" then
        if not create then return nil, data end
        rec = {}
        data.accounts[accountId] = rec
    end
    if type(rec.pending) ~= "table" then rec.pending = nil end
    return rec, data
end

local function sanitizeXP(value)
    value = finiteNumber(value, 0)
    value = math.max(0, math.min(MAX_XP_PER_PERK, value))
    return value
end

local function sanitizeTargets(targets)
    if type(targets) ~= "table" then return nil end
    local out = {}
    local any = false
    for perkId, target in pairs(targets) do
        if type(perkId) == "string" and perkId ~= "" and #perkId <= 128 then
            target = sanitizeXP(target)
            if target > 0 then
                out[perkId] = target
                any = true
            end
        end
    end
    return any and out or nil
end

local function sanitizePending(pending)
    if type(pending) ~= "table" then return nil end
    if type(pending.legacyId) ~= "string" or pending.legacyId == "" or #pending.legacyId > 240 then
        return nil
    end
    local level = FF.legacyLevel(pending.legacyLevelAtDeath)
    local creationPoints = math.max(0, math.min(20,
        math.floor(finiteNumber(pending.creationPoints, FF.legacyCreationPoints(level)))))
    local xpRetention = math.max(0, math.min(1,
        finiteNumber(pending.xpRetention, FF.legacyXpRetention(level))))
    local xpByPerk = {}
    local xpCount, xpTotal = 0, 0
    if type(pending.xpByPerk) == "table" then
        for perkId, xp in pairs(pending.xpByPerk) do
            if type(perkId) == "string" and perkId ~= "" and #perkId <= 128 then
                xp = sanitizeXP(xp)
                if xp > 0 then
                    xpByPerk[perkId] = xp
                    xpCount = xpCount + 1
                    xpTotal = xpTotal + xp
                end
            end
        end
    end
    pending.legacyLevelAtDeath = level
    pending.creationPoints = creationPoints
    pending.xpRetention = xpRetention
    pending.xpByPerk = xpByPerk
    pending.xpCount = xpCount
    pending.xpTotal = xpTotal
    if pending.state ~= "applying" then pending.state = "pending" end
    pending.creationPointsConsumed = pending.creationPointsConsumed == true
    pending.xpConsumed = pending.xpConsumed == true
    pending.applyTargets = sanitizeTargets(pending.applyTargets)
    return pending
end

local function pendingFor(accountId)
    local rec = ensureAccountRecord(accountId, false)
    if not rec then return nil, nil end
    local pending = sanitizePending(rec.pending)
    rec.pending = pending
    return pending, rec
end

local function newLegacyId(data, accountId)
    data.sequence = math.max(0, math.floor(finiteNumber(data.sequence, 0))) + 1
    return "legacy:" .. accountIdFragment(accountId) .. ":" .. tostring(nowMs())
        .. ":" .. tostring(data.sequence)
end

local function sendLegacyCommand(player, command, payload)
    if not player then return end
    pcall(function()
        sendServerCommand(player, FF.MODULE, command, type(payload) == "table" and payload or {})
    end)
end

local function sendStatusForPending(player, pending, quiet)
    if not player then return end
    if pending then
        sendLegacyCommand(player, "legacyStatus", {
            state = pending.state or "pending",
            legacyId = pending.legacyId,
            legacyLevelAtDeath = pending.legacyLevelAtDeath,
            creationPoints = pending.creationPointsConsumed and 0 or pending.creationPoints,
            creationPointsTotal = pending.creationPoints,
            creationPointsConsumed = pending.creationPointsConsumed == true,
            xpRetention = pending.xpRetention,
            xpPercent = math.floor((pending.xpRetention or 0) * 100 + 0.5),
            xpCount = pending.xpCount or 0,
            quiet = quiet == true,
        })
    else
        sendLegacyCommand(player, "legacyStatus", { state = "none", quiet = quiet ~= false })
    end
end

function Legacy.sendStatus(player, quiet)
    local accountId = accountKey(player)
    if not accountId then return sendStatusForPending(player, nil, quiet) end
    local pending = pendingFor(accountId)
    sendStatusForPending(player, pending, quiet)
end

local function isIsoPlayer(character)
    if not character then return false end
    if instanceof then
        local ok, value = pcall(instanceof, character, "IsoPlayer")
        if ok then return value == true end
    end
    return character.getUsername ~= nil and character.getXp ~= nil
end

local function isDead(player)
    if not (player and player.isDead) then return false end
    local ok, dead = pcall(function() return player:isDead() end)
    return ok and dead == true
end

local function isAnimalPlayer(player)
    if not (player and player.isAnimal) then return false end
    local ok, animal = pcall(function() return player:isAnimal() end)
    return ok and animal == true
end

local function validPerk(perk)
    if not perk then return false end
    if Perks and (perk == Perks.None or perk == Perks.MAX) then return false end
    if not perk.getParent then return false end
    local ok, parent = pcall(function() return perk:getParent() end)
    return ok and parent ~= nil and (not Perks or parent ~= Perks.None)
end

local function perkStableId(perk)
    if not (perk and perk.getId) then return nil end
    local ok, id = pcall(function() return perk:getId() end)
    if not ok or id == nil then return nil end
    id = tostring(id)
    if id == "" or id == "nil" or #id > 128 then return nil end
    return id
end

local function forEachPerk(fn)
    local list = PerkFactory and PerkFactory.PerkList
    if not (list and list.size and list.get) then return end
    for i = 0, list:size() - 1 do
        local perk = list:get(i)
        if validPerk(perk) then
            local id = perkStableId(perk)
            if id then fn(perk, id) end
        end
    end
end

local function buildPerkIndex()
    local byId = {}
    forEachPerk(function(perk, id)
        byId[id] = perk
    end)
    return byId
end

local function snapshotXP(player)
    local out, total, count = {}, 0, 0
    if not (player and player.getXp) then return out, total, count end
    local okXp, xpManager = pcall(function() return player:getXp() end)
    if not okXp or not xpManager then return out, total, count end
    forEachPerk(function(perk, id)
        local ok, value = pcall(function() return xpManager:getXP(perk) end)
        if ok then
            local xp = sanitizeXP(value)
            if xp > 0 then
                out[id] = xp
                total = total + xp
                count = count + 1
            end
        end
    end)
    return out, total, count
end

local function copyXpTable(source)
    local out, total, count = {}, 0, 0
    if type(source) ~= "table" then return out, total, count end
    for perkId, xp in pairs(source) do
        if type(perkId) == "string" and perkId ~= "" and #perkId <= 128 then
            xp = sanitizeXP(xp)
            if xp > 0 then
                out[perkId] = xp
                total = total + xp
                count = count + 1
            end
        end
    end
    return out, total, count
end

local function onlinePlayers()
    local out = {}
    local found = false
    local players = getOnlinePlayers and getOnlinePlayers()
    if players and players.size and players.get then
        for i = 0, players:size() - 1 do
            local player = players:get(i)
            if player then
                found = true
                out[#out + 1] = player
            end
        end
    end
    if not found and getSpecificPlayer then
        for i = 0, 3 do
            local player = getSpecificPlayer(i)
            if player then out[#out + 1] = player end
        end
    end
    return out
end

local function findOnlinePlayer(username)
    if type(username) ~= "string" or username == "" then return nil end
    local players = onlinePlayers()
    for i = 1, #players do
        local player = players[i]
        if usernameOf(player) == username then return player end
    end
    return nil
end

local function cacheLiveXP()
    local now = nowMs()
    if now < (Legacy._nextXpCacheAt or 0) then return end
    Legacy._nextXpCacheAt = now + XP_CACHE_INTERVAL_MS
    local players = onlinePlayers()
    for i = 1, #players do
        local player = players[i]
        if isIsoPlayer(player) and not isAnimalPlayer(player) and not isDead(player) then
            local id = accountKey(player)
            if id then
                local xpByPerk, total, count = snapshotXP(player)
                Legacy._xpCache[id] = {
                    updatedAt = now,
                    xpByPerk = xpByPerk,
                    xpTotal = total,
                    xpCount = count,
                }
            end
        end
    end
end

local function playerFingerprint(player, username)
    local parts = { tostring(username or usernameOf(player) or "?"), characterNameOf(player) }
    if player then
        local readers = {
            function() return player:getX() end,
            function() return player:getY() end,
            function() return player:getZ() end,
            function() return player:getHoursSurvived() end,
            function() return player:getZombieKills() end,
        }
        for i = 1, #readers do
            local ok, value = pcall(readers[i])
            value = ok and finiteNumber(value, 0) or 0
            parts[#parts + 1] = tostring(math.floor(value * 10 + 0.5))
        end
    end
    return table.concat(parts, "|")
end

local function prepareLegacyOnDeath(character)
    if not isIsoPlayer(character) or isAnimalPlayer(character) then return end

    local username = usernameOf(character)
    if not username then return end

    local accountId = accountKey(character)
    if not accountId then
        FF.warn("legacy skipped for '" .. tostring(username) .. "': account key unavailable")
        return
    end

    local factionName, faction = FF.getFactionOfPlayer(username)
    if not faction then return end

    FF.ensureUpgrades(faction)
    local level = FF.legacyLevel(FF.upgradeLevel(faction, "legacy"))
    if level <= 0 then return end
    if not FF.upgradesActive(faction) then return end

    local creationPoints = FF.legacyCreationPoints(level)
    local xpRetention = FF.legacyXpRetention(level)
    local xpByPerk, xpTotal, xpCount = snapshotXP(character)
    local snapshotSource = "death"
    local cache = Legacy._xpCache[accountId]
    if xpTotal <= 0 and type(cache) == "table"
        and nowMs() - (tonumber(cache.updatedAt) or 0) <= XP_CACHE_TTL_MS then
        xpByPerk, xpTotal, xpCount = copyXpTable(cache.xpByPerk)
        snapshotSource = "live_cache"
    end

    local rec, data = ensureAccountRecord(accountId, true)
    if not rec then return end

    local now = nowMs()
    local fingerprint = playerFingerprint(character, username)
    if rec.lastDeathFingerprint == fingerprint and now - (tonumber(rec.lastDeathAt) or 0) < 15000 then
        return
    end

    local pending = {
        legacyId = newLegacyId(data, accountId),
        state = "pending",
        accountId = accountId,
        username = username,
        factionName = factionName,
        legacyLevelAtDeath = level,
        creationPoints = creationPoints,
        xpRetention = xpRetention,
        xpByPerk = xpByPerk,
        xpCount = xpCount,
        xpTotal = xpTotal,
        snapshotSource = snapshotSource,
        createdAt = now,
        deathFingerprint = fingerprint,
        deadCharacterName = characterNameOf(character),
        creationPointsConsumed = false,
        xpConsumed = false,
        lastConsumedId = nil,
    }
    rec.pending = pending
    rec.lastDeathFingerprint = fingerprint
    rec.lastDeathAt = now

    sendStatusForPending(character, pending, false)
    FF.log(string.format("legacy prepared for %s (%s): level=%d points=%d xp=%d skills source=%s",
        username, tostring(factionName), level, creationPoints, xpCount, snapshotSource))
end

local function currentXP(player, perk)
    if not (player and player.getXp and perk) then return nil end
    local ok, value = pcall(function() return player:getXp():getXP(perk) end)
    if not ok then return nil end
    return sanitizeXP(value)
end

local function addXP(player, perk, amount)
    amount = finiteNumber(amount, 0)
    if amount <= 0 then return true, 0 end
    amount = math.max(0, math.min(MAX_XP_PER_PERK, amount))
    local ok, err = pcall(function()
        player:getXp():AddXP(perk, amount, false, false, false, false)
    end)
    return ok, ok and amount or 0, err
end

local function buildTargets(player, pending)
    local targets = {}
    local any = false
    local perkIndex = buildPerkIndex()
    local rate = math.max(0, math.min(1, finiteNumber(pending.xpRetention, 0)))
    for perkId, deadXP in pairs(type(pending.xpByPerk) == "table" and pending.xpByPerk or {}) do
        local perk = perkIndex[perkId]
        if perk then
            local current = currentXP(player, perk)
            if current then
                local inherited = sanitizeXP(deadXP) * rate
                local target = math.max(current, sanitizeXP(inherited))
                if target > current + 0.01 then
                    targets[perkId] = target
                    any = true
                end
            end
        end
    end
    return any and targets or nil
end

local function applyTargets(player, targets)
    local perkIndex = buildPerkIndex()
    local restored, added, failed, remaining = 0, 0, 0, 0
    for perkId, target in pairs(type(targets) == "table" and targets or {}) do
        local perk = perkIndex[perkId]
        if not perk then
            failed = failed + 1
        else
            target = sanitizeXP(target)
            local current = currentXP(player, perk)
            if current == nil then
                failed = failed + 1
            elseif current + 0.01 < target then
                local ok, amount = addXP(player, perk, target - current)
                if ok then
                    added = added + amount
                    restored = restored + 1
                    local after = currentXP(player, perk)
                    if after and after + 0.01 < target then remaining = remaining + 1 end
                else
                    failed = failed + 1
                    remaining = remaining + 1
                end
            end
        end
    end
    return restored, added, failed, remaining
end

local function remainingTargets(player, targets)
    local perkIndex = buildPerkIndex()
    local remaining = {}
    local count = 0
    for perkId, target in pairs(type(targets) == "table" and targets or {}) do
        local perk = perkIndex[perkId]
        local current = perk and currentXP(player, perk) or nil
        if not current or current + 0.01 < sanitizeXP(target) then
            remaining[perkId] = sanitizeXP(target)
            count = count + 1
        end
    end
    return remaining, count
end

local function consumePending(accountId, player, ok, restored, added, failed)
    local rec = ensureAccountRecord(accountId, false)
    if not rec then return end
    local pending = sanitizePending(rec.pending)
    if not pending then return end
    rec.lastConsumedId = pending.legacyId
    rec.lastConsumedAt = nowMs()
    rec.lastConsumedCharacter = characterNameOf(player)
    rec.lastConsumedSummary = {
        ok = ok == true,
        restored = math.max(0, math.floor(finiteNumber(restored, 0))),
        added = math.max(0, finiteNumber(added, 0)),
        failed = math.max(0, math.floor(finiteNumber(failed, 0))),
    }
    pending.xpConsumed = ok == true
    pending.state = "consumed"
    rec.pending = nil
    Legacy._retryQueue[accountId] = nil

    if player then
        if ok then
            sendLegacyCommand(player, "legacyConsumed", {
                legacyId = rec.lastConsumedId,
                restored = rec.lastConsumedSummary.restored,
                addedXp = math.floor(rec.lastConsumedSummary.added + 0.5),
            })
        else
            sendLegacyCommand(player, "legacyFailed", {
                legacyId = rec.lastConsumedId,
                restored = rec.lastConsumedSummary.restored,
                addedXp = math.floor(rec.lastConsumedSummary.added + 0.5),
                failed = rec.lastConsumedSummary.failed,
            })
        end
    end

    FF.log(string.format("legacy consumed for %s: ok=%s restored=%d added=%.2f failed=%d",
        tostring(accountId), tostring(ok == true), rec.lastConsumedSummary.restored,
        rec.lastConsumedSummary.added, rec.lastConsumedSummary.failed))
end

local function scheduleRetry(accountId, username, legacyId, targets, restored, added)
    targets = sanitizeTargets(targets)
    if not targets then return false end
    Legacy._retryQueue[accountId] = {
        username = username,
        legacyId = legacyId,
        targets = targets,
        attempts = 0,
        nextAt = nowMs() + XP_RETRY_INTERVAL_MS,
        restored = math.max(0, math.floor(finiteNumber(restored, 0))),
        added = math.max(0, finiteNumber(added, 0)),
    }
    return true
end

local function processRetry(accountId, job)
    local player = findOnlinePlayer(job.username)
    if not player or isDead(player) then
        local rec = ensureAccountRecord(accountId, false)
        if rec and type(rec.pending) == "table" and rec.pending.legacyId == job.legacyId then
            rec.pending.state = "pending"
        end
        Legacy._retryQueue[accountId] = nil
        return
    end

    local rec = ensureAccountRecord(accountId, false)
    local pending = rec and sanitizePending(rec.pending) or nil
    if not pending or pending.legacyId ~= job.legacyId then
        Legacy._retryQueue[accountId] = nil
        return
    end

    job.attempts = math.max(0, math.floor(finiteNumber(job.attempts, 0))) + 1
    local restored, added = applyTargets(player, job.targets)
    job.restored = math.max(0, math.floor(finiteNumber(job.restored, 0))) + restored
    job.added = math.max(0, finiteNumber(job.added, 0)) + added

    local stillRemaining, remainingCount = remainingTargets(player, job.targets)
    if remainingCount <= 0 then
        return consumePending(accountId, player, true, job.restored, job.added, 0)
    end
    job.targets = stillRemaining
    if job.attempts >= XP_RETRY_LIMIT then
        return consumePending(accountId, player, false, job.restored, job.added, remainingCount)
    end
    job.nextAt = nowMs() + XP_RETRY_INTERVAL_MS
end

local function retryTick()
    cacheLiveXP()
    local now = nowMs()
    for accountId, job in pairs(Legacy._retryQueue) do
        if type(job) ~= "table" then
            Legacy._retryQueue[accountId] = nil
        elseif now >= (tonumber(job.nextAt) or 0) then
            local ok, err = pcall(processRetry, accountId, job)
            if not ok then
                Legacy._retryQueue[accountId] = nil
                FF.warn("legacy retry failed for " .. tostring(accountId) .. ": " .. tostring(err))
            end
        end
    end
end

function Legacy.onCharacterReady(player, clientLegacyId)
    if not player or isDead(player) then return end
    local accountId = accountKey(player)
    if not accountId then return end
    local pending, rec = pendingFor(accountId)
    if not pending or not rec then return end

    if type(clientLegacyId) == "string" and clientLegacyId ~= "" and clientLegacyId ~= pending.legacyId then
        FF.warn("legacy ready ignored for " .. tostring(usernameOf(player))
            .. ": client legacyId mismatch")
        return sendStatusForPending(player, pending, true)
    end

    if pending.creationPointsConsumed and pending.xpConsumed then
        return consumePending(accountId, player, true, 0, 0, 0)
    end

    pending.state = "applying"
    pending.creationPointsConsumed = true
    pending.lastConsumedId = pending.legacyId
    pending.consumeStartedAt = pending.consumeStartedAt or nowMs()
    pending.username = usernameOf(player) or pending.username

    local targets = sanitizeTargets(pending.applyTargets) or buildTargets(player, pending)
    pending.applyTargets = targets

    if not targets then
        return consumePending(accountId, player, true, 0, 0, 0)
    end

    local restored, added = applyTargets(player, targets)
    local stillRemaining, remainingCount = remainingTargets(player, targets)
    if remainingCount <= 0 then
        return consumePending(accountId, player, true, restored, added, 0)
    end

    pending.applyTargets = stillRemaining
    scheduleRetry(accountId, pending.username, pending.legacyId, stillRemaining, restored, added)
    sendStatusForPending(player, pending, true)
end

local function onCharacterDeath(character)
    local ok, err = pcall(prepareLegacyOnDeath, character)
    if not ok then FF.warn("legacy death hook failed: " .. tostring(err)) end
end

local function replaceHook(event, key, callback)
    if not event then return end
    if FF._replaceServerHook then
        return FF._replaceServerHook(event, key, callback)
    end
    if FF[key] and event.Remove then event.Remove(FF[key]) end
    FF[key] = callback
    event.Add(callback)
end

-- Self-heal: mesmo motivo do FF.migrateSoloSPIdentity em LFS_Server.lua --
-- accountKey() acima agora usa LasciviousSystemsSteamId.accountKey(), que em
-- SP puro devolve uma chave fixa (SP_IDENTITY) em vez do fallback antigo
-- "name:"..username, que ficava orfao a cada personagem novo (a engine
-- reescreve username com o nome do personagem em SP -- ver IsoPlayer.
-- updateUsername(), decompilado). Se sobrar exatamente UM account com um
-- pending gravado sob uma chave "name:..." antiga, migra pra chave fixa --
-- senao aquele legado (pontos de criacao + XP herdado) fica perdido pra
-- sempre, pois nenhum personagem futuro vai bater com a chave antiga. Mais de
-- um e ambiguo (varias mortes de teste geraram pendings diferentes) -- nao
-- adivinha qual e o certo, so avisa no log.
local function migrateSoloSPLegacyAccounts()
    if not LasciviousSystemsSteamId.isTrueSoloSP() then return end
    local data = dataStore()
    local newKey = LasciviousSystemsSteamId.SP_IDENTITY
    local newRec = data.accounts[newKey]
    if newRec and type(newRec.pending) == "table" then return end -- already has a live pending; do not clobber

    local staleKeys = {}
    for accountId, rec in pairs(data.accounts) do
        if accountId ~= newKey and type(rec) == "table" and type(rec.pending) == "table" then
            staleKeys[#staleKeys + 1] = accountId
        end
    end
    if #staleKeys == 0 then return end
    if #staleKeys > 1 then
        FF.warn("legacy SP identity migration skipped: " .. #staleKeys
            .. " accounts with a pending legacy record found (ambiguous), expected at most 1.")
        return
    end

    local oldKey = staleKeys[1]
    local oldRec = data.accounts[oldKey]
    data.accounts[oldKey] = nil
    newRec = data.accounts[newKey]
    if type(newRec) ~= "table" then
        newRec = {}
        data.accounts[newKey] = newRec
    end
    newRec.pending = oldRec.pending
    newRec.pending.accountId = newKey
    FF.log("legacy SP identity migrated: '" .. tostring(oldKey) .. "' -> '" .. newKey .. "'")
end

replaceHook(Events.OnCharacterDeath, "_legacyDeathHook", onCharacterDeath)
replaceHook(Events.OnTick, "_legacyRetryTickHook", retryTick)
replaceHook(Events.OnServerStarted, "_legacySPIdentityMigrateStart", migrateSoloSPLegacyAccounts)
local function migrateSoloSPLegacyAccountsForLocalAuthority()
    if isClient() and not isCoopHost() then return end
    migrateSoloSPLegacyAccounts()
end
replaceHook(Events.OnGameStart, "_legacySPIdentityMigrateGameStart", migrateSoloSPLegacyAccountsForLocalAuthority)

FF.log("legacy server ready")
