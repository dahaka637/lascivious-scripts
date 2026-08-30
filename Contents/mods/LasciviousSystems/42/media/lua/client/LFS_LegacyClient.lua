if isServer() and not isClient() then
    return
end

require "LFS_Shared"
require "LFS_Upgrades"
require "LFS_Localization"

pcall(require, "OptionScreens/CharacterCreationProfession")
pcall(require, "OptionScreens/CoopCharacterCreation")

local FF = LasciviousFactionsSystem

FF.LegacyClient = type(FF.LegacyClient) == "table" and FF.LegacyClient or {}
local Client = FF.LegacyClient

local RECEIPT_KEY = "LFS_LegacyReceiptV1"
local STATUS_REQUEST_COOLDOWN_MS = 1000
local READY_SEND_COOLDOWN_MS = 2500
local READY_OBSERVATION_TTL_MS = 120000

Client.state = type(Client.state) == "table" and Client.state or { pending = false }

local function finiteNumber(value, fallback)
    value = tonumber(value)
    if not value or value ~= value or value == math.huge or value == -math.huge then
        return fallback
    end
    return value
end

local function nowMs()
    if getTimestampMs then return math.max(0, math.floor(finiteNumber(getTimestampMs(), 0))) end
    return math.max(0, math.floor(finiteNumber(getTimestamp and getTimestamp() or 0, 0) * 1000))
end

local function currentPlayer()
    return getPlayer and getPlayer() or nil
end

local function playerIsAlive(player)
    if not player then return false end
    if player.isDead then
        local ok, dead = pcall(function() return player:isDead() end)
        if ok and dead == true then return false end
    end
    return true
end

local function playerIdentity(player)
    if not player then return "no-player" end
    return tostring(player)
end

local function showHalo(key, fallback, r, g, b, ...)
    local message = FF.text(key, fallback, ...)
    local player = currentPlayer()
    if player and player.setHaloNote then
        pcall(function() player:setHaloNote(message, r or 255, g or 255, b or 255, 300) end)
    end
    if addChat then pcall(addChat, message) end
    print("[LFS/Legacy] " .. tostring(message))
end

local function sanitizeStatus(args)
    if type(args) ~= "table" then return { pending = false } end
    local state = tostring(args.state or "none")
    if state ~= "pending" and state ~= "applying" then return { pending = false } end
    local legacyId = args.legacyId
    if type(legacyId) ~= "string" or legacyId == "" or #legacyId > 240 then
        return { pending = false }
    end
    local level = FF.legacyLevel(args.legacyLevelAtDeath)
    local creationPoints = math.max(0, math.min(20,
        math.floor(finiteNumber(args.creationPoints, FF.legacyCreationPoints(level)))))
    local xpRetention = math.max(0, math.min(1,
        finiteNumber(args.xpRetention, FF.legacyXpRetention(level))))
    return {
        pending = true,
        state = state,
        legacyId = legacyId,
        legacyLevelAtDeath = level,
        creationPoints = creationPoints,
        creationPointsTotal = math.max(0, math.min(20,
            math.floor(finiteNumber(args.creationPointsTotal, creationPoints)))),
        creationPointsConsumed = args.creationPointsConsumed == true,
        xpRetention = xpRetention,
        xpPercent = math.max(0, math.min(100,
            math.floor(finiteNumber(args.xpPercent, xpRetention * 100) + 0.5))),
        xpCount = math.max(0, math.floor(finiteNumber(args.xpCount, 0))),
        receivedAt = nowMs(),
    }
end

function Client.creationBonus()
    local state = Client.state
    if type(state) ~= "table" or not state.pending or state.creationPointsConsumed then return 0 end
    return math.max(0, math.min(20, math.floor(finiteNumber(state.creationPoints, 0))))
end

local function persistReceipt(player)
    player = player or currentPlayer()
    if not (player and player.getModData) then return end
    local ok, modData = pcall(function() return player:getModData() end)
    if not ok or type(modData) ~= "table" then return end

    local state = Client.state
    if type(state) == "table" and state.pending then
        modData[RECEIPT_KEY] = {
            state = state.state,
            legacyId = state.legacyId,
            legacyLevelAtDeath = state.legacyLevelAtDeath,
            creationPoints = state.creationPoints,
            creationPointsTotal = state.creationPointsTotal,
            creationPointsConsumed = state.creationPointsConsumed,
            xpRetention = state.xpRetention,
            xpPercent = state.xpPercent,
            xpCount = state.xpCount,
            receivedAt = state.receivedAt,
        }
    else
        modData[RECEIPT_KEY] = nil
    end
    if player.transmitModData then pcall(function() player:transmitModData() end) end
end

local function restoreReceipt(player)
    if type(Client.state) == "table" and Client.state.pending then return true end
    player = player or currentPlayer()
    if not (player and player.getModData) then return false end
    local ok, modData = pcall(function() return player:getModData() end)
    if not ok or type(modData) ~= "table" then return false end
    local restored = sanitizeStatus(modData[RECEIPT_KEY])
    if restored.pending then
        Client.state = restored
        return true
    end
    if modData[RECEIPT_KEY] ~= nil then
        modData[RECEIPT_KEY] = nil
        if player.transmitModData then pcall(function() player:transmitModData() end) end
    end
    return false
end

function Client.requestStatus()
    local player = currentPlayer()
    if not player or not sendClientCommand then return false end
    local now = nowMs()
    if now - (tonumber(Client.lastStatusRequestAt) or 0) < STATUS_REQUEST_COOLDOWN_MS then
        return true
    end
    Client.lastStatusRequestAt = now
    sendClientCommand(player, FF.MODULE, "requestLegacyStatus", {})
    return true
end

local function removeTickHook(key)
    if Client[key] and Events.OnTick and Events.OnTick.Remove then
        Events.OnTick.Remove(Client[key])
    end
    Client[key] = nil
end

function Client.scheduleStatusRequest()
    if Client.requestStatus() then return true end
    if not Events.OnTick then return false end
    removeTickHook("_statusRequestTick")
    Client._statusRequestAttempts = 0
    Client._statusRequestTick = function()
        Client._statusRequestAttempts = math.max(0,
            math.floor(finiteNumber(Client._statusRequestAttempts, 0))) + 1
        if Client.requestStatus() or Client._statusRequestAttempts >= 120 then
            removeTickHook("_statusRequestTick")
        end
    end
    Events.OnTick.Add(Client._statusRequestTick)
    return true
end

local function readyKey(player, legacyId)
    return playerIdentity(player) .. "\0" .. tostring(legacyId or "")
end

local function characterReadyObserved()
    local now = nowMs()
    local deathAt = tonumber(Client.lastDeathAt) or 0
    local createAt = tonumber(Client.lastCreatePlayerAt) or 0
    if createAt > 0 and createAt >= deathAt and now - createAt <= READY_OBSERVATION_TTL_MS then
        return true
    end
    local gameStartAt = tonumber(Client.lastGameStartAt) or 0
    if gameStartAt > 0 and gameStartAt >= deathAt and now - gameStartAt <= READY_OBSERVATION_TTL_MS then
        return true
    end
    return false
end

function Client.sendCharacterReady()
    local state = Client.state
    if type(state) ~= "table" or not state.pending then return false end
    if not characterReadyObserved() then return false end
    local player = currentPlayer()
    if not playerIsAlive(player) then return false end

    local now = nowMs()
    local key = readyKey(player, state.legacyId)
    if Client.lastReadyKey == key and now - (tonumber(Client.lastReadyAt) or 0) < READY_SEND_COOLDOWN_MS then
        return true
    end

    Client.lastReadyKey = key
    Client.lastReadyAt = now
    sendClientCommand(player, FF.MODULE, "legacyCharacterReady", { legacyId = state.legacyId })
    return true
end

function Client.scheduleCharacterReady()
    if Client.sendCharacterReady() then return true end
    if not Events.OnTick then return false end
    removeTickHook("_readyTick")
    Client._readyAttempts = 0
    Client._readyTick = function()
        Client._readyAttempts = math.max(0,
            math.floor(finiteNumber(Client._readyAttempts, 0))) + 1
        if Client.sendCharacterReady() or Client._readyAttempts >= 120 then
            removeTickHook("_readyTick")
        end
    end
    Events.OnTick.Add(Client._readyTick)
    return true
end

local function clearState(player)
    Client.state = { pending = false }
    persistReceipt(player)
end

local function handleStatus(args)
    local quiet = type(args) == "table" and args.quiet == true
    local state = sanitizeStatus(args)
    if not state.pending then
        clearState()
        if not quiet then
            showHalo("UI_LFS_LegacyNoPending", "Nenhum legado pendente encontrado.", 230, 230, 230)
        end
        return
    end

    Client.state = state
    persistReceipt()

    if state.creationPoints > 0 and not quiet then
        showHalo("UI_LFS_LegacyPrepared",
            "Legado preparado: +%s pontos de criação e %s%% de XP para o próximo personagem.",
            180, 230, 255, tostring(state.creationPoints), tostring(state.xpPercent))
    end

    if state.creationPoints > 0 then
        showHalo("UI_LFS_LegacyCreationBonus",
            "Legado da facção: +%s pontos disponíveis na criação.",
            180, 255, 180, tostring(state.creationPoints))
    end

    Client.scheduleCharacterReady()
end

local function handleConsumed(args)
    local restored = math.max(0, math.floor(finiteNumber(args and args.restored, 0)))
    clearState()
    showHalo("UI_LFS_LegacyRestored",
        "Legado aplicado: criação consumida e %s habilidade(s) receberam XP herdado.",
        180, 255, 180, tostring(restored))
end

local function handleFailed(args)
    local failed = math.max(0, math.floor(finiteNumber(args and args.failed, 0)))
    clearState()
    showHalo("UI_LFS_LegacyRestoreFailed",
        "Legado consumido, mas %s habilidade(s) não puderam ser confirmadas. Avise um administrador.",
        255, 170, 120, tostring(failed))
end

local function onServerCommand(module, command, args)
    if module ~= FF.MODULE then return end
    if command == "legacyStatus" then
        handleStatus(args or {})
    elseif command == "legacyConsumed" then
        handleConsumed(args or {})
    elseif command == "legacyFailed" then
        handleFailed(args or {})
    end
end

local function installCreationPatch()
    pcall(require, "OptionScreens/CharacterCreationProfession")
    local cls = CharacterCreationProfession
    if type(cls) ~= "table" or type(cls.PointToSpend) ~= "function" then return false end

    if not cls._lfsLegacyPointToSpendOriginal then
        cls._lfsLegacyPointToSpendOriginal = cls.PointToSpend
        cls.PointToSpend = function(self, ...)
            local value = finiteNumber(cls._lfsLegacyPointToSpendOriginal(self, ...), 0)
            local client = LasciviousFactionsSystem and LasciviousFactionsSystem.LegacyClient
            local bonus = client and client.creationBonus and client.creationBonus() or 0
            return value + finiteNumber(bonus, 0)
        end
    end

    if type(cls.new) == "function" and not cls._lfsLegacyNewOriginal then
        cls._lfsLegacyNewOriginal = cls.new
        cls.new = function(self, ...)
            local obj = cls._lfsLegacyNewOriginal(self, ...)
            local client = LasciviousFactionsSystem and LasciviousFactionsSystem.LegacyClient
            if client and client.scheduleStatusRequest then client.scheduleStatusRequest() end
            return obj
        end
    end

    return true
end

local function installCoopCreationPatch()
    pcall(require, "OptionScreens/CoopCharacterCreation")
    local cls = CoopCharacterCreation
    if type(cls) ~= "table" or type(cls.new) ~= "function" then return false end
    if cls._lfsLegacyNewOriginal then return true end
    cls._lfsLegacyNewOriginal = cls.new
    cls.new = function(self, ...)
        local obj = cls._lfsLegacyNewOriginal(self, ...)
        local client = LasciviousFactionsSystem and LasciviousFactionsSystem.LegacyClient
        if client and client.scheduleStatusRequest then client.scheduleStatusRequest() end
        return obj
    end
    return true
end

local function installPatches()
    local professionPatched = installCreationPatch()
    installCoopCreationPatch()
    return professionPatched
end

local function schedulePatchInstall()
    if installPatches() then return end
    if not Events.OnTick then return end
    removeTickHook("_patchInstallTick")
    Client._patchInstallAttempts = 0
    Client._patchInstallTick = function()
        Client._patchInstallAttempts = math.max(0,
            math.floor(finiteNumber(Client._patchInstallAttempts, 0))) + 1
        if installPatches() or Client._patchInstallAttempts >= 120 then
            removeTickHook("_patchInstallTick")
        end
    end
    Events.OnTick.Add(Client._patchInstallTick)
end

local function onCreatePlayer(playerIndex, playerObj)
    Client.lastCreatePlayerAt = nowMs()
    Client.lastDeathAt = nil
    local player = playerObj or (getSpecificPlayer and getSpecificPlayer(playerIndex) or currentPlayer())
    restoreReceipt(player)
    Client.scheduleStatusRequest()
    Client.scheduleCharacterReady()
end

local function onGameStart()
    Client.lastGameStartAt = nowMs()
    restoreReceipt()
    Client.scheduleStatusRequest()
    Client.scheduleCharacterReady()
    schedulePatchInstall()
end

local function onPlayerDeath(playerObj)
    Client.lastDeathAt = nowMs()
    restoreReceipt(playerObj)
    Client.scheduleStatusRequest()
end

local function replaceHook(event, key, callback)
    if not event then return end
    if FF[key] and event.Remove then event.Remove(FF[key]) end
    FF[key] = callback
    event.Add(callback)
end

removeTickHook("_statusRequestTick")
removeTickHook("_readyTick")
removeTickHook("_patchInstallTick")

replaceHook(Events.OnServerCommand, "_legacyClientServerCommandHook", onServerCommand)
replaceHook(Events.OnCreatePlayer, "_legacyClientCreatePlayerHook", onCreatePlayer)
replaceHook(Events.OnGameStart, "_legacyClientGameStartHook", onGameStart)
replaceHook(Events.OnPlayerDeath, "_legacyClientPlayerDeathHook", onPlayerDeath)

schedulePatchInstall()
Client.scheduleStatusRequest()

print("[LFS/Legacy] client ready")
