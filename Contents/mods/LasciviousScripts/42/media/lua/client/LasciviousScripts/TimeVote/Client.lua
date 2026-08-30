--
-- Lascivious Scripts - Multiplayer Time Vote
--
-- The server decides only whether 1x/5x/20x/40x has unanimous permission. A granted
-- multiplier is applied ONCE. It is never reasserted every tick.
--
-- B42.20.x intentionally disables parts of the single-player SpeedControls
-- reset path while GameClient.client is true. This file mirrors only those
-- vanilla reset gates that are disabled in MP (movement, nearby zombie,
-- fall/fire and timed-action completion). Every native path that already drops
-- GameTime back to 1x is detected by observing the multiplier and is propagated
-- to the server as a global cancellation.
--

require "LasciviousScripts/TimeVote/Core"
require "LasciviousScripts/TimeVote/SpeedPanel"
require "TimedActions/ISTimedActionQueue"

local Core = LasciviousScripts.TimeVote
local SpeedPanel = LasciviousScripts.TimeVote.SpeedPanel

local Runtime = { applied = Core.NORMAL, votes = {}, online = {}, revision = -1 }

local versionWarned = false
local panel = nil
local panelRevision = -2
local cancelPending = false
local cancelRequestedRevision = -1
local wasEnabled = false
local actionWasRunning = false
local applyGraceTicks = 0
local APPLY_GRACE_TICKS = 2

local function soloGateBlocked()
    local cfg = Core.getConfig()
    return cfg.SoloOnly == true and #Runtime.online > 1
end

local function setLocalMultiplier(multiplier)
    local time = getGameTime and getGameTime() or nil
    if not time then return false end
    local ok, err = pcall(time.setMultiplier, time, multiplier)
    if not ok then Core.debugLog("GameTime:setMultiplier failed: " .. tostring(err)); return false end
    return true
end

local function applyGrantedSpeed(level)
    if not Core.isValidSpeed(level) then level = Core.NORMAL end
    local ok = setLocalMultiplier(Core.multiplierFor(level))
    if ok then applyGraceTicks = level >= Core.FAST_FORWARD_MIN and APPLY_GRACE_TICKS or 0 end
    return ok
end

local function currentMultiplier()
    local time = getGameTime and getGameTime() or nil
    if not time then return nil end
    local ok, value = pcall(time.getTrueMultiplier, time)
    if ok and type(value) == "number" then return value end
    return nil
end

local function requestCancel(reason)
    if cancelPending or Runtime.applied < Core.FAST_FORWARD_MIN then return end
    local player = getPlayer()
    if not player then return end

    cancelPending = true
    cancelRequestedRevision = Runtime.revision
    setLocalMultiplier(1)
    sendClientCommand(player, Core.MODULE, Core.CMD_CANCEL, { reason = reason or "vanilla", revision = Runtime.revision })
    Core.debugLog("fast-forward interrupted: " .. tostring(reason))
end

local function onVoteClick(level)
    if not Core.isValidSpeed(level) then return end
    local player = getPlayer()
    if not player then return end

    if level == Core.NORMAL and Runtime.applied >= Core.FAST_FORWARD_MIN then
        requestCancel("manual")
        return
    end

    sendClientCommand(player, Core.MODULE, Core.CMD_VOTE, { speed = level })
end

local function ensurePanel()
    if panel then return panel end
    panel = SpeedPanel:new(onVoteClick)
    panel:initialise()
    panel:addToUIManager()
    return panel
end

local function updatePanel()
    local p = ensurePanel()
    if Runtime.revision ~= panelRevision then
        p:setData(Runtime.votes, Runtime.online, Runtime.applied)
        panelRevision = Runtime.revision
    end
end

local function updateVisibility()
    local p = ensurePanel()
    local visible = Core.getConfig().Enabled and not soloGateBlocked()
    p:setVisible(visible)
    if visible then updatePanel() end
    return visible
end

local function checkVersion(theirs)
    if versionWarned then return end
    versionWarned = true
    if theirs and theirs ~= Core.VERSION then Core.log(string.format("VERSION MISMATCH: server=%s client=%s", tostring(theirs), Core.VERSION)) end
end

-- Vanilla-reset mirrors -------------------------------------------------------

local function pcallBool(fn, fallback)
    local ok, value = pcall(fn)
    if ok then return value == true end
    return fallback == true
end

local function movementWouldReset(player)
    if not player then return false end
    local justMoved = pcallBool(function() return player:isJustMoved() end, false)
    if not justMoved then return false end
    local hasPath = pcallBool(function() return player:hasPath() end, false)
    local pathfinding = pcallBool(function() return player:isCurrentActionPathfinding() end, false)
    return not hasPath and not pathfinding
end

local function fireOrFallWouldReset(player)
    if not player then return false end
    if pcallBool(function() return player:isOnFire() end, false) then return true end

    local okState, state = pcall(function() return player:getCurrentState() end)
    if okState and state then
        local okFalling, falling = pcall(instanceof, state, "PlayerFallingState")
        if okFalling and falling then return true end
        local okFallDown, fallDown = pcall(instanceof, state, "PlayerFallDownState")
        if okFallDown and fallDown then return true end
    end
    return false
end

local function nearbyZombieWouldReset(player)
    if not player or pcallBool(function() return player:isGhostMode() end, false) then return false end

    local maxDist = 4
    local okStats, stats = pcall(function() return player:getStats() end)
    if okStats and stats then
        local okVisible, visible = pcall(function() return stats:getNumVisibleZombies() end)
        if okVisible and type(visible) == "number" and visible > 4 then maxDist = 7 end
    end

    local okList, spotted = pcall(function() return player:getSpottedList() end)
    if not okList or not spotted then return false end

    local okSize, size = pcall(function() return spotted:size() end)
    if not okSize or type(size) ~= "number" then return false end

    local px, py, pz = player:getX(), player:getY(), math.floor(player:getZ())
    for i = 0, size - 1 do
        local okObj, obj = pcall(function() return spotted:get(i) end)
        if okObj and obj then
            local okZombie, isZombie = pcall(instanceof, obj, "IsoZombie")
            if okZombie and isZombie and math.floor(obj:getZ()) == pz then
                local dx, dy = obj:getX() - px, obj:getY() - py
                if math.sqrt(dx * dx + dy * dy) < maxDist then return true end
            end
        end
    end
    return false
end

local function isDoingTimedAction(player)
    if not player or not ISTimedActionQueue or not ISTimedActionQueue.isPlayerDoingAction then return false end
    local ok, value = pcall(ISTimedActionQueue.isPlayerDoingAction, player)
    return ok and value == true
end

local function timedActionFinishedWouldReset(player)
    local resetEnabled = true
    local core = getCore and getCore() or nil
    if core and core.getOptionTimedActionGameSpeedReset then
        local ok, value = pcall(function() return core:getOptionTimedActionGameSpeedReset() end)
        if ok then resetEnabled = value == true end
    end

    if not resetEnabled then actionWasRunning = false; return false end

    local doing = isDoingTimedAction(player)
    if doing then actionWasRunning = true; return false end
    if actionWasRunning then actionWasRunning = false; return true end
    return false
end

local function checkVanillaInterruptions()
    local player = getPlayer()

    -- Keep the exact vanilla timed-action transition state even while at 1x, so
    -- completing an action after fast-forward starts behaves like single-player.
    local timedFinished = timedActionFinishedWouldReset(player)

    if Runtime.applied < Core.FAST_FORWARD_MIN or cancelPending then return end

    if movementWouldReset(player) then requestCancel("vanilla_movement"); return end
    if fireOrFallWouldReset(player) then requestCancel("vanilla_fall_or_fire"); return end
    if nearbyZombieWouldReset(player) then requestCancel("vanilla_nearby_zombie"); return end
    if timedFinished then requestCancel("vanilla_timed_action_finished"); return end

    -- Attacks and several other vanilla states still call SetCurrentGameSpeed(1)
    -- directly even in multiplayer. Do not duplicate them: observe the result.
    if applyGraceTicks > 0 then applyGraceTicks = applyGraceTicks - 1; return end
    local actual = currentMultiplier()
    local expected = Core.multiplierFor(Runtime.applied)
    if actual ~= nil and actual < expected - 0.01 then requestCancel("vanilla_multiplier_reset") end
end

-- Event handlers --------------------------------------------------------------

local function onTick()
    local enabled = Core.getConfig().Enabled
    if not enabled then
        if wasEnabled then setLocalMultiplier(1) end
        wasEnabled = false
        if panel then panel:setVisible(false) end
        actionWasRunning = false
        return
    end

    wasEnabled = true
    updateVisibility()
    checkVanillaInterruptions()
end

local function onServerCommand(module, command, args)
    if module ~= Core.MODULE or command ~= Core.CMD_SYNC or type(args) ~= "table" then return end

    local incomingRevision = tonumber(args.revision)
    if incomingRevision == nil then incomingRevision = Runtime.revision + 1 end
    if incomingRevision < Runtime.revision then return end

    local incomingApplied = Core.isValidSpeed(args.applied) and args.applied or Core.NORMAL

    -- A periodic packet from the same revision must never resurrect a speed that
    -- this client has already cancelled because vanilla forced it to 1x.
    if cancelPending and incomingApplied >= Core.FAST_FORWARD_MIN and incomingRevision <= cancelRequestedRevision then return end

    local previousApplied = Runtime.applied
    local previousRevision = Runtime.revision
    Runtime.votes = args.votes or {}
    Runtime.online = args.online or {}
    Runtime.applied = incomingApplied
    Runtime.revision = incomingRevision
    checkVersion(args.version)

    if cancelPending and (incomingApplied == Core.NORMAL or incomingRevision > cancelRequestedRevision) then
        cancelPending = false
        cancelRequestedRevision = -1
    end

    -- Only authoritative state transitions touch GameTime. Same-revision resyncs
    -- update presentation only and can never fight a native interruption.
    if incomingRevision > previousRevision or incomingApplied ~= previousApplied then applyGrantedSpeed(incomingApplied) end
    updateVisibility()
end

local function onGameStart()
    local player = getPlayer()
    if not player then return end

    setLocalMultiplier(1)
    wasEnabled = Core.getConfig().Enabled
    updateVisibility()
    if wasEnabled then sendClientCommand(player, Core.MODULE, Core.CMD_HELLO, {}) end
    Core.log(string.format("client loaded (single-player reset semantics mirrored in MP, version=%s)", Core.VERSION))
end

if isClient() then
    Events.OnServerCommand.Add(onServerCommand)
    Events.OnGameStart.Add(onGameStart)
    Events.OnTick.Add(onTick)
end
