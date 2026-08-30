local Catalog = require "sbfplus/itemcatalog"

local Diagnostics = {}

local POLL_INTERVAL_MS = 5000
local SUMMARY_INTERVAL_MS = 60000
local LOG_PREFIX = "[SBFPlus:diag]"

local FINGERPRINT_FIELDS = {
    "onlineId",
    "perspective",
    "present",
    "itemId",
    "fullType",
    "attachmentType",
    "slotType",
    "model",
    "activated",
    "uses",
    "canEmitLight",
    "isEmittingLight",
    "torchStrength",
    "lightDistance",
}

local supportedFullTypes = {}
local trackedStates = {}
local lastPollMs = 0

local function addCatalogEntries(entries)
    for _, entry in ipairs(entries or {}) do
        if entry.fullType then supportedFullTypes[entry.fullType] = true end
    end
end

addCatalogEntries(Catalog.vanilla)
addCatalogEntries(Catalog.authenticZ)
addCatalogEntries(Catalog.betterFlashlights)

local function valueText(value)
    if value == nil then return "nil" end
    return tostring(value)
end

local function snapshotValue(snapshot, fieldName)
    if snapshot == nil then return nil end
    return snapshot[fieldName]
end

local function safeCall(target, methodName)
    if not target then return nil end
    local okMethod, method = pcall(function() return target[methodName] end)
    if not okMethod or type(method) ~= "function" then return nil end
    local okValue, value = pcall(method, target)
    if okValue then return value end
    return nil
end

local function safeCallWithArgument(target, methodName, argument)
    if not target then return nil end
    local okMethod, method = pcall(function() return target[methodName] end)
    if not okMethod or type(method) ~= "function" then return nil end
    local okValue, value = pcall(method, target, argument)
    if okValue then return value end
    return nil
end

local function currentTimeMs()
    if type(getTimestampMs) == "function" then
        local ok, value = pcall(getTimestampMs)
        if ok and type(value) == "number" then return value end
    end
    return os.time() * 1000
end

local function clearTrackedStates()
    for key in pairs(trackedStates) do trackedStates[key] = nil end
end

function Diagnostics.isEnabled(sandboxVars)
    return type(sandboxVars) == "table"
        and type(sandboxVars.SBFPlus) == "table"
        and sandboxVars.SBFPlus.DebugLogging == true
end

function Diagnostics.isSupportedIdentity(fullType)
    return type(fullType) == "string" and supportedFullTypes[fullType] == true
end

function Diagnostics.makeFingerprint(snapshot)
    local values = {}
    for index, fieldName in ipairs(FINGERPRINT_FIELDS) do
        values[index] = valueText(snapshotValue(snapshot, fieldName))
    end
    return table.concat(values, "|")
end

function Diagnostics.shouldLog(previousFingerprint, currentFingerprint, lastSummaryMs, nowMs)
    if previousFingerprint ~= currentFingerprint then return true, "change" end
    if nowMs - (lastSummaryMs or 0) >= SUMMARY_INTERVAL_MS then return true, "summary" end
    return false, nil
end

function Diagnostics.formatLine(snapshot, reason)
    local parts = { LOG_PREFIX, "reason=" .. valueText(reason) }
    for _, fieldName in ipairs(FINGERPRINT_FIELDS) do
        parts[#parts + 1] = fieldName .. "=" .. valueText(snapshotValue(snapshot, fieldName))
    end
    return table.concat(parts, " ")
end

local function isSupportedItem(item)
    local fullType = safeCall(item, "getFullType")
    return Diagnostics.isSupportedIdentity(fullType)
end

local function getPerspective(player)
    if safeCall(player, "isLocalPlayer") == true or safeCall(player, "isLocal") == true then
        return "local"
    end
    return "remote"
end

local function makeSnapshot(player, item)
    return {
        onlineId = safeCall(player, "getOnlineID") or -1,
        perspective = getPerspective(player),
        present = true,
        itemId = safeCall(item, "getID") or -1,
        fullType = safeCall(item, "getFullType"),
        attachmentType = safeCall(item, "getAttachmentType"),
        slotType = safeCall(item, "getAttachedSlotType"),
        model = safeCall(item, "getAttachedToModel"),
        activated = safeCall(item, "isActivated"),
        uses = safeCall(item, "getCurrentUses"),
        canEmitLight = safeCall(item, "canEmitLight"),
        isEmittingLight = safeCall(item, "isEmittingLight"),
        torchStrength = safeCall(player, "getTorchStrength"),
        lightDistance = safeCall(player, "getLightDistance"),
    }
end

local function collectPlayerSnapshots(player, snapshots)
    local attachedItems = safeCall(player, "getAttachedItems")
    if not attachedItems then return end

    local size = safeCall(attachedItems, "size")
    if type(size) ~= "number" then return end

    for index = 0, size - 1 do
        local item = safeCallWithArgument(attachedItems, "getItemByIndex", index)
        if item and isSupportedItem(item) then
            snapshots[#snapshots + 1] = makeSnapshot(player, item)
        end
    end
end

local function addPlayer(players, seenPlayers, player)
    if player and not seenPlayers[player] then
        seenPlayers[player] = true
        players[#players + 1] = player
    end
end

local function getTrackedPlayers()
    local players = {}
    local seenPlayers = {}

    if type(getNumActivePlayers) == "function" and type(getSpecificPlayer) == "function" then
        local okCount, count = pcall(getNumActivePlayers)
        if okCount and type(count) == "number" then
            for playerNum = 0, count - 1 do
                local okPlayer, player = pcall(getSpecificPlayer, playerNum)
                if okPlayer then addPlayer(players, seenPlayers, player) end
            end
        end
    end

    if type(getOnlinePlayers) == "function" then
        local okOnline, onlinePlayers = pcall(getOnlinePlayers)
        if okOnline and onlinePlayers then
            local size = safeCall(onlinePlayers, "size")
            if type(size) == "number" then
                for index = 0, size - 1 do
                    addPlayer(players, seenPlayers, safeCallWithArgument(onlinePlayers, "get", index))
                end
            end
        end
    end

    return players
end

local function scan(nowMs)
    local snapshots = {}
    for _, player in ipairs(getTrackedPlayers()) do
        collectPlayerSnapshots(player, snapshots)
    end

    local seenKeys = {}
    for _, snapshot in ipairs(snapshots) do
        local key = valueText(snapshot.onlineId) .. ":" .. valueText(snapshot.itemId)
        local fingerprint = Diagnostics.makeFingerprint(snapshot)
        local previous = trackedStates[key]
        local shouldLog, reason = Diagnostics.shouldLog(
            previous and previous.fingerprint or nil,
            fingerprint,
            previous and previous.lastSummaryMs or 0,
            nowMs
        )

        if shouldLog then print(Diagnostics.formatLine(snapshot, reason)) end
        trackedStates[key] = {
            fingerprint = fingerprint,
            lastSummaryMs = shouldLog and nowMs or previous.lastSummaryMs,
            snapshot = snapshot,
        }
        seenKeys[key] = true
    end

    for key, previous in pairs(trackedStates) do
        if not seenKeys[key] then
            local removed = {}
            for fieldName, value in pairs(previous.snapshot or {}) do removed[fieldName] = value end
            removed.present = false
            print(Diagnostics.formatLine(removed, "removed"))
            trackedStates[key] = nil
        end
    end
end

local function onTick()
    if not Diagnostics.isEnabled(rawget(_G, "SandboxVars")) then
        clearTrackedStates()
        lastPollMs = 0
        return
    end

    local nowMs = currentTimeMs()
    if lastPollMs ~= 0 and nowMs - lastPollMs < POLL_INTERVAL_MS then return end
    lastPollMs = nowMs
    scan(nowMs)
end

local function onGameStart()
    clearTrackedStates()
    lastPollMs = 0
    onTick()
end

if Events then
    if Events.OnGameStart then Events.OnGameStart.Add(onGameStart) end
    if Events.OnTick then Events.OnTick.Add(onTick) end
end

return Diagnostics
