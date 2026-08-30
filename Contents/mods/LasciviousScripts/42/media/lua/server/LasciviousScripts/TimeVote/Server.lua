--
-- Lascivious Scripts - Multiplayer Time Vote
-- Server-authoritative unanimous voting. Clients apply a granted multiplier once.
-- If vanilla (or a mirrored single-player reset gate) returns any client to 1x,
-- that client sends CMD_CANCEL and the server returns everybody to 1x.
--

require "LasciviousScripts/TimeVote/Core"

local Core = LasciviousScripts.TimeVote
Core.Server = Core.Server or {}
local ServerState = Core.Server

local votes = {}
local applied = Core.NORMAL
local revision = 0
local lastOnline = {}
local resyncTicks = 0
local RESYNC_TICKS = 120
local wasEnabled = false

local function playerKey(player)
    if not player then return nil end
    if player.getOnlineID then
        local ok, id = pcall(function() return player:getOnlineID() end)
        if ok and id ~= nil and tonumber(id) and tonumber(id) >= 0 then return tostring(id) end
    end
    local name = player.getUsername and player:getUsername() or nil
    return name and ("name:" .. tostring(name)) or nil
end

local function onlinePlayers()
    local out = {}
    local players = getOnlinePlayers()
    if not players then return out end
    for i = 0, players:size() - 1 do
        local player = players:get(i)
        if player then table.insert(out, player) end
    end
    return out
end

local function onlineRoster()
    local keys, names = {}, {}
    for _, player in ipairs(onlinePlayers()) do
        local key = playerKey(player)
        if key then
            table.insert(keys, key)
            names[key] = player.getUsername and player:getUsername() or key
        end
    end
    table.sort(keys)
    return keys, names
end

local function applyEngine(level)
    if not Core.isValidSpeed(level) then level = Core.NORMAL end
    if setGameSpeed then setGameSpeed(level) end
    local time = getGameTime()
    if time then time:setMultiplier(Core.multiplierFor(level)) end
end

local function bumpRevision()
    revision = revision + 1
end

local function buildPayload(reason, actor)
    local keys, names = onlineRoster()
    return { applied = applied, votes = votes, online = keys, names = names, reason = reason, actor = actor, revision = revision, version = Core.VERSION }
end

local function broadcast(reason, actor)
    sendServerCommand(Core.MODULE, Core.CMD_SYNC, buildPayload(reason, actor))
end

local function resetVotes()
    votes = {}
    local keys = onlineRoster()
    for _, key in ipairs(keys) do votes[key] = Core.NORMAL end
end

local function consensusSpeed()
    local keys = onlineRoster()
    if #keys == 0 then return nil end
    local first = votes[keys[1]]
    if not first or first < Core.FAST_FORWARD_MIN then return nil end
    for _, key in ipairs(keys) do if votes[key] ~= first then return nil end end
    return first
end

local function setApplied(level, reason, actor)
    if not Core.isValidSpeed(level) then level = Core.NORMAL end
    applied = level
    applyEngine(level)
    bumpRevision()
    Core.log(string.format("speed -> %d (x%s), reason=%s actor=%s rev=%d", level, tostring(Core.multiplierFor(level)), tostring(reason), tostring(actor), revision))
    broadcast(reason, actor)
end

local function forceNormal(reason, actor)
    resetVotes()
    applied = Core.NORMAL
    applyEngine(Core.NORMAL)
    bumpRevision()
    Core.log(string.format("speed -> 1 (x1), reason=%s actor=%s rev=%d", tostring(reason), tostring(actor), revision))
    broadcast(reason, actor)
end

local function soloGateActive()
    local keys = onlineRoster()
    return Core.getConfig().SoloOnly == true and #keys > 1
end

local function sameOnlineSet(a, b)
    for key in pairs(a) do if not b[key] then return false end end
    for key in pairs(b) do if not a[key] then return false end end
    return true
end

local function refreshElectorate(reason, actor)
    local keys = onlineRoster()
    local current = {}
    for _, key in ipairs(keys) do current[key] = true end

    if #keys == 0 then
        -- Build 42's server Kahlua environment does not reliably expose the
        -- global `next`. Reuse the set comparator, which has the exact same
        -- meaning here because `current` is empty.
        local changed = not sameOnlineSet(lastOnline, current)
        lastOnline = {}
        votes = {}
        if applied ~= Core.NORMAL or changed then
            applied = Core.NORMAL
            applyEngine(Core.NORMAL)
            bumpRevision()
            Core.log("server empty -> forced 1x")
        end
        return changed
    end

    if sameOnlineSet(lastOnline, current) then return false end
    lastOnline = current

    if applied >= Core.FAST_FORWARD_MIN then
        forceNormal(reason or "players_changed", actor)
    else
        resetVotes()
        bumpRevision()
        broadcast(reason or "players_changed", actor)
    end
    return true
end

local function onHello(player)
    local key = playerKey(player)
    local changed = refreshElectorate("players_changed", key)
    if not changed then sendServerCommand(player, Core.MODULE, Core.CMD_SYNC, buildPayload("hello", key)) end
end

local function onVote(player, args)
    local level = args and tonumber(args.speed) or nil
    if not Core.isValidSpeed(level) then return end
    local key = playerKey(player)
    if not key then return end

    if soloGateActive() then
        if applied ~= Core.NORMAL then forceNormal("solo_only", key) end
        return
    end

    if level == Core.NORMAL then
        forceNormal("manual", key)
        return
    end

    if applied >= Core.FAST_FORWARD_MIN then
        if level == applied then return end

        -- Changing 5x <-> 20x invalidates the old consensus. The new click is a
        -- fresh vote. Crucially, we immediately recalculate consensus so a lone
        -- player switches speed in one click instead of getting stuck pending.
        resetVotes()
        votes[key] = level
        local consensus = consensusSpeed()
        if consensus then
            setApplied(consensus, "consensus", key)
        else
            applied = Core.NORMAL
            applyEngine(Core.NORMAL)
            bumpRevision()
            broadcast("vote_changed", key)
        end
        return
    end

    votes[key] = level
    local consensus = consensusSpeed()
    if consensus then
        setApplied(consensus, "consensus", key)
    else
        bumpRevision()
        broadcast("pending", key)
    end
end

local function onCancel(player, args)
    local key = playerKey(player)
    if not key then return end

    -- Ignore a delayed cancellation from an older consensus after the server has
    -- already advanced to a newer revision.
    local clientRevision = args and tonumber(args.revision) or nil
    if clientRevision and clientRevision < revision then return end

    forceNormal((args and args.reason == "manual") and "manual" or "vanilla_cancel", key)
end

local function onClientCommand(module, command, player, args)
    if not Core.getConfig().Enabled then return end
    if module ~= Core.MODULE or not player then return end
    if command == Core.CMD_HELLO then onHello(player)
    elseif command == Core.CMD_VOTE then onVote(player, args)
    elseif command == Core.CMD_CANCEL then onCancel(player, args) end
end

local function enforceSoloGate()
    if soloGateActive() and applied ~= Core.NORMAL then forceNormal("solo_only", nil) end
end

local function onCharacterDeath(character)
    if not Core.getConfig().Enabled or applied < Core.FAST_FORWARD_MIN then return end
    local okPlayer, isPlayer = pcall(instanceof, character, "IsoPlayer")
    if not okPlayer or not isPlayer then return end
    local key = playerKey(character)
    forceNormal("player_death", key)
end

-- NetTimedAction acceleration -------------------------------------------------
-- B42 multiplayer TimedActions are server-authoritative. We scale the network
-- duration to the granted speed. Unlike the previous implementation, duration
-- is also restored/rebased when speed drops (20x->5x or any fast speed->1x), so
-- an interrupted action cannot keep finishing at the old accelerated rate.

local liveNetActions = {}
local injectedActions = {}
local TICK_MS = 16
local scaleFailLogged = false

if emulateAnimEvent and not ServerState.emulateHooked then
    ServerState.emulateHooked = true
    local originalEmulate = emulateAnimEvent
    emulateAnimEvent = function(netAction, every, event, parameter)
        if netAction and not liveNetActions[netAction] then liveNetActions[netAction] = { mult = 1 } end
        return originalEmulate(netAction, every, event, parameter)
    end
end

local function wantedMultiplier()
    return applied >= Core.FAST_FORWARD_MIN and Core.multiplierFor(applied) or 1
end

local function driveNetRegistry(registry, getNet, label)
    local mult = wantedMultiplier()
    for key, state in pairs(registry) do
        local net = getNet(key)
        if not net then
            state.noNet = (state.noNet or 0) + 1
            if state.noNet > 600 then registry[key] = nil end
        else
            state.noNet = 0
            local okP, progress = pcall(net.getProgress, net)
            if not okP or type(progress) ~= "number" or progress >= 1 then
                registry[key] = nil
            else
                if not state.duration then
                    if state.p0 == nil then
                        state.p0, state.ms = progress, 0
                    else
                        state.ms = (state.ms or 0) + TICK_MS
                        local dp = progress - state.p0
                        if state.ms >= 1000 and dp > 1e-6 then state.duration = state.ms / dp end
                    end
                end

                local previousMult = state.mult or 1
                if state.duration and mult ~= previousMult then
                    local targetDuration = state.duration / mult
                    local ok, err = pcall(net.setDuration, net, targetDuration)
                    if ok then
                        state.mult = mult
                        Core.debugLog(string.format("%s rebased: base=%.0fms target=%.0fms x%s", label, state.duration, targetDuration, tostring(mult)))
                    elseif not scaleFailLogged then
                        scaleFailLogged = true
                        Core.log("NetTimedAction setDuration refused: " .. tostring(err))
                    end
                end
            end
        end
    end
end

local function injectCapture(class, className)
    if not class then Core.log("capture skipped, class missing: " .. className); return end
    local original = rawget(class, "serverStart")
    class.serverStart = function(self)
        if not injectedActions[self] then injectedActions[self] = { mult = 1 } end
        if original then return original(self) end
    end
end

if not ServerState.injectHooked then
    ServerState.injectHooked = true
    require "TimedActions/ISEatFoodAction"
    require "TimedActions/ISDrinkFromBottle"
    require "TimedActions/ISWashClothing"
    require "TimedActions/ISWashYourself"
    require "TimedActions/ISCraftAction"
    require "TimedActions/ISAddItemInRecipe"
    injectCapture(ISEatFoodAction, "ISEatFoodAction")
    injectCapture(ISDrinkFromBottle, "ISDrinkFromBottle")
    injectCapture(ISWashClothing, "ISWashClothing")
    injectCapture(ISWashYourself, "ISWashYourself")
    injectCapture(ISCraftAction, "ISCraftAction")
    injectCapture(ISAddItemInRecipe, "ISAddItemInRecipe")
end

local function driveTimedActions()
    driveNetRegistry(liveNetActions, function(net) return net end, "net action")
    driveNetRegistry(injectedActions, function(action) return action.netAction end, "timed action")
end

local function onTick()
    local cfg = Core.getConfig()
    if not cfg.Enabled then
        if wasEnabled then
            forceNormal("disabled", nil)
            driveTimedActions()
        end
        wasEnabled = false
        return
    end
    wasEnabled = true

    refreshElectorate("players_changed", nil)
    enforceSoloGate()
    driveTimedActions()

    resyncTicks = resyncTicks + 1
    if resyncTicks >= RESYNC_TICKS then resyncTicks = 0; broadcast(nil, nil) end
end

if isServer() then
    applyEngine(Core.NORMAL)
    Events.OnClientCommand.Add(onClientCommand)
    Events.OnTick.Add(onTick)
    Events.OnCharacterDeath.Add(onCharacterDeath)
    Core.log(string.format("server loaded (native-reset-compatible vote, version=%s)", Core.VERSION))
end
