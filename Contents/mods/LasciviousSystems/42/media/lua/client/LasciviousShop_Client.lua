if isServer() then return end

require "LasciviousShop_Shared"
require "LasciviousShop_Catalog"

local LS = LasciviousShop

LasciviousShopClient = LasciviousShopClient or {}
local Client = LasciviousShopClient

Client.state = nil
Client.stateReceivedAt = 0
Client.awaitingPurchase = false
Client.purchaseSentAt = 0
Client.pendingPurchase = type(Client.pendingPurchase) == "table" and Client.pendingPurchase or nil
Client.purchaseAmbiguous = Client.purchaseAmbiguous == true
Client.lastResult = nil
Client.lastError = nil
Client.listeners = Client.listeners or {}
Client.sequence = Client.sequence or 0
Client.appliedXPRequests = Client.appliedXPRequests or {}
Client.appliedXPOrder = Client.appliedXPOrder or {}

Client.onlinePlayers = Client.onlinePlayers or {}
Client.onlinePlayersReceivedAt = 0
Client.awaitingTransfer = false
Client.transferSentAt = 0
Client.pendingTransfer = type(Client.pendingTransfer) == "table" and Client.pendingTransfer or nil
Client.transferAmbiguous = Client.transferAmbiguous == true
Client.lastTransferResult = nil

local PURCHASE_REPLY_TIMEOUT_MS = 10000
local MAX_AUTOMATIC_PURCHASE_RETRIES = 2
local TRANSFER_REPLY_TIMEOUT_MS = 10000
local MAX_AUTOMATIC_TRANSFER_RETRIES = 2
local PENDING_MODDATA_KEY = "LasciviousShopPendingV1"
local MAX_PERSISTED_CART_LINES = 40
local MAX_PERSISTED_CART_UNITS = 50
local MAX_PERSISTED_LINE_QUANTITY = 50
local MAX_PERSISTED_TRANSFER_AMOUNT = 1000000

local function notify()
    for _, listener in ipairs(Client.listeners) do
        local ok, err = pcall(listener)
        if not ok then LS.log("client listener failed: " .. tostring(err)) end
    end
end

local function send(command, args)
    local player = getPlayer()
    if not player then return false end
    sendClientCommand(player, LS.MODULE, command, args or {})
    return true
end

local function nowMilliseconds()
    return getTimestampMs and getTimestampMs() or ((getTimestamp and getTimestamp() or 0) * 1000)
end

-- Own the payload until the server returns a definitive result.  In
-- particular, a lost reply must never turn the next click into a second order
-- with a fresh request id.  The shallow line copies are deliberate: these are
-- the only scalar fields the purchase protocol accepts.
local function copyPurchaseItems(items)
    local copy = {}
    if type(items) ~= "table" then return copy end
    for index, line in ipairs(items) do
        if type(line) == "table" then
            copy[index] = { id = line.id, qty = line.qty }
        else
            copy[index] = line
        end
    end
    return copy
end

local function finiteInteger(value, minimum, maximum)
    local number = LS.finiteNumber(value, nil)
    if number == nil or number ~= math.floor(number) then return nil end
    if minimum ~= nil and number < minimum then return nil end
    if maximum ~= nil and number > maximum then return nil end
    return number
end

-- Player ModData is client-controlled input after a reconnect, so restoration is
-- deliberately stricter than the ordinary UI path. Only the bounded scalar
-- protocol fields are copied back; metatables, sparse arrays and arbitrary nested
-- values never become a network payload.
local function normalisePendingPurchase(record)
    if type(record) ~= "table" then return nil end
    local payload = type(record.payload) == "table" and record.payload or record
    local requestId = record.requestId or payload.requestId
    if type(requestId) ~= "string" or requestId == "" or #requestId > 80 then return nil end
    if record.requestId ~= nil and payload.requestId ~= nil
        and tostring(record.requestId) ~= tostring(payload.requestId) then return nil end

    local items = payload.items
    if type(items) ~= "table" then return nil end
    local itemCount = 0
    for key in pairs(items) do
        if type(key) ~= "number" or key < 1 or key ~= math.floor(key) then return nil end
        itemCount = itemCount + 1
    end
    if itemCount < 1 or itemCount > MAX_PERSISTED_CART_LINES or itemCount ~= #items then return nil end

    local cleanItems, totalUnits = {}, 0
    for index = 1, itemCount do
        local line = items[index]
        if type(line) ~= "table" or type(line.id) ~= "string"
            or line.id == "" or #line.id > 128 then return nil end
        local qty = finiteInteger(line.qty, 1, MAX_PERSISTED_LINE_QUANTITY)
        if not qty then return nil end
        totalUnits = totalUnits + qty
        if totalUnits > MAX_PERSISTED_CART_UNITS then return nil end
        cleanItems[index] = { id = line.id, qty = qty }
    end

    local quotedTotal = finiteInteger(payload.quotedTotal, 0, nil)
    local offerRevision = finiteInteger(payload.offerRevision, 0, nil)
    if quotedTotal == nil or offerRevision == nil then return nil end
    return {
        requestId = requestId,
        automaticRetries = math.max(0, math.floor(tonumber(record.automaticRetries) or 0)),
        payload = {
            requestId = requestId,
            items = cleanItems,
            quotedTotal = quotedTotal,
            offerRevision = offerRevision,
        },
    }
end

local function normalisePendingTransfer(record)
    if type(record) ~= "table" then return nil end
    local payload = type(record.payload) == "table" and record.payload or record
    local requestId = record.requestId or payload.requestId
    if type(requestId) ~= "string" or requestId == "" or #requestId > 80 then return nil end
    if record.requestId ~= nil and payload.requestId ~= nil
        and tostring(record.requestId) ~= tostring(payload.requestId) then return nil end
    local target = payload.target
    if type(target) ~= "string" or target == "" or #target > 64 then return nil end
    local amount = finiteInteger(payload.amount, 1, MAX_PERSISTED_TRANSFER_AMOUNT)
    if not amount then return nil end
    return {
        requestId = requestId,
        automaticRetries = math.max(0, math.floor(tonumber(record.automaticRetries) or 0)),
        payload = { requestId = requestId, target = target, amount = amount },
    }
end

local function pendingPlayerModData(player)
    player = player or (getPlayer and getPlayer() or nil)
    if not player or not player.getModData then return nil, nil end
    local ok, modData = pcall(function() return player:getModData() end)
    if not ok or type(modData) ~= "table" then return nil, nil end
    return player, modData
end

local function persistPendingOperations(player)
    local modData
    player, modData = pendingPlayerModData(player)
    if not player then return false end
    local okIdentity, identity = pcall(function()
        return player.getUsername and tostring(player:getUsername()) or "local"
    end)
    if okIdentity then Client.pendingOwner = identity end

    local purchase = normalisePendingPurchase(Client.pendingPurchase)
    local transfer = normalisePendingTransfer(Client.pendingTransfer)
    if purchase or transfer then
        modData[PENDING_MODDATA_KEY] = {
            purchase = purchase and purchase.payload or nil,
            transfer = transfer and transfer.payload or nil,
        }
    else
        modData[PENDING_MODDATA_KEY] = nil
    end

    -- In multiplayer this sends the record before the following economy command.
    -- The local ModData assignment still protects single-player and ordinary save
    -- persistence when transmitModData is not part of that environment.
    if player.transmitModData then
        local ok, err = pcall(function() player:transmitModData() end)
        if not ok then LS.log("pending transaction ModData transmit failed: " .. tostring(err)) end
    end
    return true
end

Client._normalisePendingPurchase = normalisePendingPurchase
Client._normalisePendingTransfer = normalisePendingTransfer
Client._persistPendingOperations = persistPendingOperations

local function clearPendingPurchase(requestId)
    local pending = Client.pendingPurchase
    if not pending then return end
    if requestId ~= nil and tostring(requestId) ~= tostring(pending.requestId) then return end
    Client.pendingPurchase = nil
    Client.purchaseAmbiguous = false
    persistPendingOperations()
end

local function sendPendingPurchase(isAutomaticRetry)
    local pending = normalisePendingPurchase(Client.pendingPurchase)
    if not pending then return false end
    Client.pendingPurchase = pending
    if isAutomaticRetry then
        pending.automaticRetries = math.max(0, math.floor(tonumber(pending.automaticRetries) or 0)) + 1
    end
    local stamp = nowMilliseconds()
    Client.awaitingPurchase = true
    Client.purchaseAmbiguous = false
    Client.purchaseSentAt = stamp
    if not send(LS.CMD_PURCHASE, pending.payload) then
        Client.awaitingPurchase = false
        return false
    end
    return true
end

local function applyState(state)
    if type(state) ~= "table" then return end
    Client.state = state
    Client.stateReceivedAt = getTimestampMs and getTimestampMs() or 0
end

-- In multiplayer the server owns the transaction and its persistent XP copy,
-- while the local player also needs the confirmed delta for an immediate skill
-- update. Single-player shares the server object and must not apply it twice.
local function applyConfirmedXP(result)
    if not isClient() or type(result) ~= "table" then return end
    local requestId = tostring(result.requestId or "")
    if requestId == "" or Client.appliedXPRequests[requestId] then return end

    local player = getPlayer and getPlayer() or nil
    if not player then return end
    -- A retry can be the first response the client actually receives.  The
    -- server therefore replays the confirmed XP summary even when `duplicate`
    -- is true; this request-id set, rather than that flag, is what prevents a
    -- second local AddXP call when both replies arrive.
    Client.appliedXPRequests[requestId] = true
    table.insert(Client.appliedXPOrder, requestId)
    while #Client.appliedXPOrder > 100 do
        local old = table.remove(Client.appliedXPOrder, 1)
        Client.appliedXPRequests[old] = nil
    end
    local deliveries = type(result.delivered) == "table" and result.delivered or {}
    for _, delivery in ipairs(deliveries) do
        local product = type(delivery) == "table" and LS.PRODUCT_BY_ID[delivery.id] or nil
        if product and product.kind == "xp" then
            local amount = math.max(0, math.floor(LS.finiteNumber(delivery.amount, 0)))
            local ok, err = pcall(function()
                local perk = Perks.FromString(product.perk)
                if not perk or perk == Perks.None or perk == Perks.MAX then
                    error("unknown perk " .. tostring(product.perk))
                end
                player:getXp():AddXP(perk, amount, false, false, false, false)
            end)
            if not ok then LS.log("client XP synchronization failed: " .. tostring(err)) end
        end
    end
end

function Client.onUpdate(listener)
    if type(listener) ~= "function" then return nil end
    table.insert(Client.listeners, listener)
    return listener
end

function Client.offUpdate(listener)
    if type(listener) ~= "function" then return end
    for index = #Client.listeners, 1, -1 do
        if Client.listeners[index] == listener then table.remove(Client.listeners, index) end
    end
end

function Client.requestState()
    send(LS.CMD_REQUEST_STATE, {})
end

function Client.requestPurchase(items, quotedTotal, offerRevision)
    if Client.awaitingPurchase then return false end

    -- An ambiguous request remains queryable with its original immutable
    -- payload.  Reusing the id lets the server replay the recorded outcome and
    -- prevents an innocent second click from buying everything twice.  A
    -- stale server-side `processing` marker therefore does not spin or freeze
    -- the whole UI: browsing/cart edits remain available and each explicit
    -- click performs only a bounded status retry of that same transaction.
    if Client.pendingPurchase then
        Client.lastResult = nil
        Client.lastError = nil
        if sendPendingPurchase(false) then
            notify()
            return true
        end
        return false
    end

    Client.sequence = Client.sequence + 1
    local stamp = nowMilliseconds()
    local requestId = tostring(stamp) .. ":" .. tostring(Client.sequence)
    Client.pendingPurchase = normalisePendingPurchase({
        requestId = requestId,
        automaticRetries = 0,
        payload = {
            requestId = requestId,
            items = copyPurchaseItems(items),
            quotedTotal = quotedTotal,
            offerRevision = offerRevision,
        },
    })
    if not Client.pendingPurchase or not persistPendingOperations() then
        Client.pendingPurchase = nil
        return false
    end
    Client.lastResult = nil
    Client.lastError = nil
    if not sendPendingPurchase(false) then
        clearPendingPurchase(requestId)
        return false
    end
    notify()
    return true
end

function Client.offerSecondsRemaining()
    local state = Client.state
    if not state or not state.offersEnabled then return 0 end
    return math.max(0, math.floor(LS.finiteNumber(state.offerExpiresAt, 0)
        - (getTimestamp and getTimestamp() or 0)))
end

function Client.clearPurchaseTimeout()
    if not Client.awaitingPurchase then return end
    local now = nowMilliseconds()
    if now <= 0 or now - (Client.purchaseSentAt or 0) <= PURCHASE_REPLY_TIMEOUT_MS then return end

    local pending = Client.pendingPurchase
    local retries = pending and math.max(0, math.floor(tonumber(pending.automaticRetries) or 0)) or 0
    if pending and retries < MAX_AUTOMATIC_PURCHASE_RETRIES and sendPendingPurchase(true) then
        -- Ask for a fresh balance in parallel, but keep the order locked to
        -- its original request id until a conclusive purchase reply arrives.
        Client.requestState()
        return
    end

    Client.awaitingPurchase = false
    Client.purchaseAmbiguous = pending ~= nil
    Client.lastError = {
        reason = pending and "purchase_status_unknown" or "timeout",
        requestId = pending and pending.requestId or nil,
    }
    Client.requestState()
    notify()
end

function Client.requestTransferList()
    send(LS.CMD_TRANSFER_LIST, {})
end

local function clearPendingTransfer(requestId)
    local pending = Client.pendingTransfer
    if not pending then return end
    if requestId ~= nil and tostring(requestId) ~= tostring(pending.requestId) then return end
    Client.pendingTransfer = nil
    Client.transferAmbiguous = false
    persistPendingOperations()
end

local function sendPendingTransfer(isAutomaticRetry)
    local pending = normalisePendingTransfer(Client.pendingTransfer)
    if not pending then return false end
    Client.pendingTransfer = pending
    if isAutomaticRetry then
        pending.automaticRetries = math.max(0,
            math.floor(tonumber(pending.automaticRetries) or 0)) + 1
    end
    local stamp = nowMilliseconds()
    Client.awaitingTransfer = true
    Client.transferAmbiguous = false
    Client.transferSentAt = stamp
    if not send(LS.CMD_TRANSFER, pending.payload) then
        Client.awaitingTransfer = false
        return false
    end
    return true
end

function Client.requestTransfer(target, amount)
    if Client.awaitingTransfer then return false end

    -- As with purchases, losing only the reply must not turn the next click
    -- into a second transfer. Query the exact same immutable request until the
    -- server replays a definitive result.
    if Client.pendingTransfer then
        Client.lastTransferResult = nil
        if sendPendingTransfer(false) then
            notify()
            return true
        end
        return false
    end

    Client.sequence = Client.sequence + 1
    local stamp = nowMilliseconds()
    local requestId = tostring(stamp) .. ":t:" .. tostring(Client.sequence)
    Client.pendingTransfer = normalisePendingTransfer({
        requestId = requestId,
        automaticRetries = 0,
        payload = { requestId = requestId, target = target, amount = amount },
    })
    if not Client.pendingTransfer or not persistPendingOperations() then
        Client.pendingTransfer = nil
        return false
    end
    Client.lastTransferResult = nil
    if not sendPendingTransfer(false) then
        clearPendingTransfer(requestId)
        return false
    end
    notify()
    return true
end

function Client.clearTransferTimeout()
    if not Client.awaitingTransfer then return end
    local now = nowMilliseconds()
    if now <= 0 or now - (Client.transferSentAt or 0) <= TRANSFER_REPLY_TIMEOUT_MS then return end

    local pending = Client.pendingTransfer
    local retries = pending and math.max(0,
        math.floor(tonumber(pending.automaticRetries) or 0)) or 0
    if pending and retries < MAX_AUTOMATIC_TRANSFER_RETRIES and sendPendingTransfer(true) then
        Client.requestState()
        return
    end

    Client.awaitingTransfer = false
    Client.transferAmbiguous = pending ~= nil
    Client.lastTransferResult = {
        ok = false,
        reason = pending and "transfer_status_unknown" or "timeout",
        requestId = pending and pending.requestId or nil,
    }
    Client.requestState()
    notify()
end

-- Restore after the player object exists and query the server with the exact same
-- immutable payload. The server's replay ledger turns this into a status lookup if
-- the original operation completed before the disconnect. OnCreatePlayer and
-- OnGameStart can both fire for one spawn, so the player-object guard keeps the
-- resume pass single-shot.
local function restorePendingOperations(player)
    local modData
    player, modData = pendingPlayerModData(player)
    if not player or Client._pendingRestoredPlayer == player then return false end

    local okIdentity, identity = pcall(function()
        return player.getUsername and tostring(player:getUsername()) or "local"
    end)
    identity = okIdentity and identity or "local"
    if Client.pendingOwner ~= nil and Client.pendingOwner ~= identity then
        Client.pendingPurchase = nil
        Client.pendingTransfer = nil
    end

    local stored = type(modData[PENDING_MODDATA_KEY]) == "table"
        and modData[PENDING_MODDATA_KEY] or {}
    Client.pendingPurchase = normalisePendingPurchase(Client.pendingPurchase)
        or normalisePendingPurchase(stored.purchase)
    Client.pendingTransfer = normalisePendingTransfer(Client.pendingTransfer)
        or normalisePendingTransfer(stored.transfer)
    Client.pendingOwner = identity
    Client._pendingRestoredPlayer = player
    Client.purchaseAmbiguous = Client.pendingPurchase ~= nil
    Client.transferAmbiguous = Client.pendingTransfer ~= nil
    persistPendingOperations(player) -- also removes corrupt/legacy payloads

    local resumed = false
    if Client.pendingPurchase then resumed = sendPendingPurchase(false) or resumed end
    if Client.pendingTransfer then resumed = sendPendingTransfer(false) or resumed end
    if resumed then notify() end
    return resumed
end

Client._restorePendingOperations = restorePendingOperations

-- Purely a presentation trigger for whoever the credits landed on -- must
-- work regardless of whether that player has the shop window open at all,
-- so this lives in the always-loaded command dispatcher below rather than
-- anywhere in LasciviousShop_Window.lua.
local function showCreditsReceivedHalo(args)
    local ok, err = pcall(function()
        local player = getPlayer and getPlayer() or nil
        if not player then return end
        local amount = math.max(0, math.floor(LS.finiteNumber(args and args.amount, 0)))
        if amount <= 0 then return end
        local fromUsername = tostring((args and args.fromUsername) or "?")
        local message = LS.text("CreditsReceivedHalo", "+%1 créditos de %2", LS.formatCredits(amount), fromUsername)
        local color = Color.new(0.659, 0.333, 0.969, 1)
        HaloTextHelper.addText(player, message, "[br/]", color)
    end)
    if not ok then LS.log("halo text failed: " .. tostring(err)) end
end

local function onServerCommand(module, command, args)
    module = tostring(module or "")
    command = tostring(command or "")
    if module ~= LS.MODULE or command == "" then return end
    args = type(args) == "table" and args or {}
    if command == LS.CMD_STATE then
        applyState(args)
        Client.lastResult = nil
        Client.lastError = nil
    elseif command == LS.CMD_PURCHASE_RESULT then
        Client.awaitingPurchase = false
        clearPendingPurchase(args.requestId)
        Client.lastResult = args
        Client.lastError = nil
        applyConfirmedXP(args)
        applyState(args.state)
    elseif command == LS.CMD_ERROR then
        Client.awaitingPurchase = false
        local reason = tostring(args.reason or "")
        local pending = Client.pendingPurchase
        local responseId = args.requestId
        local matchesPending = pending and (responseId == nil
            or tostring(responseId) == tostring(pending.requestId))
        if matchesPending and (reason == "purchase_in_progress" or reason == "too_fast"
            or reason == "server_error") then
            -- These replies do not prove that delivery did not commit.  Keep
            -- the request id so an explicit retry remains idempotent, but stop
            -- automatic retrying and release the UI from its waiting state.
            Client.purchaseAmbiguous = true
        elseif matchesPending then
            clearPendingPurchase(responseId)
        end
        Client.lastError = args
        Client.lastResult = nil
        applyState(args.state)
    elseif command == LS.CMD_TRANSFER_LIST then
        Client.onlinePlayers = type(args.players) == "table" and args.players or {}
        Client.onlinePlayersReceivedAt = getTimestampMs and getTimestampMs() or 0
    elseif command == LS.CMD_TRANSFER_RESULT then
        Client.awaitingTransfer = false
        local reason = tostring(args.reason or "")
        local pending = Client.pendingTransfer
        local responseId = args.requestId
        local matchesPending = pending and (responseId == nil
            or tostring(responseId) == tostring(pending.requestId))
        if matchesPending and args.ok ~= true and (reason == "transfer_in_progress"
            or reason == "transfer_status_unknown" or reason == "server_error") then
            Client.transferAmbiguous = true
        elseif matchesPending then
            clearPendingTransfer(responseId)
        end
        Client.lastTransferResult = args
        applyState(args.state)
    elseif command == LS.CMD_CREDITS_RECEIVED then
        -- Not gated on anything above: this must show up even if the
        -- recipient's shop window is closed, or never opened this session.
        showCreditsReceivedHalo(args)
        return
    else
        return
    end
    notify()
end

-- Avoid stacking dispatchers when Lua is reloaded during development. Besides
-- duplicate toasts this was especially dangerous for confirmed XP, whose
-- client-side synchronization must run exactly once.
if Client._serverCommandHandler and Events.OnServerCommand.Remove then
    Events.OnServerCommand.Remove(Client._serverCommandHandler)
end
Client._serverCommandHandler = onServerCommand
Events.OnServerCommand.Add(onServerCommand)

local function resumePendingOnTick()
    local player = getPlayer and getPlayer() or nil
    if not player then return end
    if Events.OnTick and Events.OnTick.Remove then Events.OnTick.Remove(resumePendingOnTick) end
    restorePendingOperations(player)
end

local function schedulePendingResume()
    if not Events.OnTick then return end
    if Events.OnTick.Remove then Events.OnTick.Remove(resumePendingOnTick) end
    Events.OnTick.Add(resumePendingOnTick)
end

-- Replace every development-reload hook and defer network traffic until the
-- player is fully in-world. Scheduling once at file load also covers late Lua
-- reloads, while the two lifecycle hooks cover normal joins and respawns.
if Client._pendingResumeTick and Events.OnTick and Events.OnTick.Remove then
    Events.OnTick.Remove(Client._pendingResumeTick)
end
if Client._pendingGameStartHook and Events.OnGameStart and Events.OnGameStart.Remove then
    Events.OnGameStart.Remove(Client._pendingGameStartHook)
end
if Client._pendingCreatePlayerHook and Events.OnCreatePlayer and Events.OnCreatePlayer.Remove then
    Events.OnCreatePlayer.Remove(Client._pendingCreatePlayerHook)
end
Client._pendingResumeTick = resumePendingOnTick
Client._pendingGameStartHook = schedulePendingResume
Client._pendingCreatePlayerHook = schedulePendingResume
if Events.OnGameStart then Events.OnGameStart.Add(Client._pendingGameStartHook) end
if Events.OnCreatePlayer then Events.OnCreatePlayer.Add(Client._pendingCreatePlayerHook) end
schedulePendingResume()
