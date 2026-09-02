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

local function hardcoreKitsPendingActive()
    if not (HardcoreKits and HardcoreKitsPersistence and HardcoreKitsPersistence.getPendingTx) then return false end
    local found = false
    for _, player in ipairs(onlinePlayers()) do
        if found then break end
        local ok, tx = pcall(HardcoreKitsPersistence.getPendingTx, player)
        local status = ok and type(tx) == "table" and tx.status or nil
        local terminal = status == HardcoreKits.STATUS_COMPLETED
            or status == HardcoreKits.STATUS_CANCELLED
            or status == HardcoreKits.STATUS_ABANDONED_DEAD
            or status == "completed"
            or status == "cancelled"
            or status == "abandoned_dead"
        if status and not terminal then
            found = true
        end
    end
    return found
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

    if level >= Core.FAST_FORWARD_MIN and hardcoreKitsPendingActive() then
        if applied ~= Core.NORMAL then
            forceNormal("hardcore_kits_pending", key)
        else
            resetVotes()
            bumpRevision()
            broadcast("hardcore_kits_pending", key)
        end
        Core.log("fast-forward denied: Hardcore Kits claim pending")
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

local function enforceHardcoreKitsGate()
    if applied >= Core.FAST_FORWARD_MIN and hardcoreKitsPendingActive() then
        forceNormal("hardcore_kits_pending", nil)
    end
end

local function onCharacterDeath(character)
    if not Core.getConfig().Enabled or applied < Core.FAST_FORWARD_MIN then return end
    local okPlayer, isPlayer = pcall(instanceof, character, "IsoPlayer")
    if not okPlayer or not isPlayer then return end
    local key = playerKey(character)
    forceNormal("player_death", key)
end

-- TimedAction duration acceleration --------------------------------------------
-- BUG (found 2026-09-01, root-caused by decompiling zombie.core.Action/
-- NetTimedAction and zombie.characters.CharacterTimedActions.*): the previous
-- approach (below, removed) hooked 6 hardcoded classes' `serverStart` and tried
-- to read a NetTimedAction reference off `action.netAction` to rescale its
-- duration. That field is never assigned anywhere -- not by any vanilla Lua
-- file, not by any Java bytecode in this build (grepped both exhaustively) --
-- so `net` was always nil, the 600-tick "noNet" counter always expired the
-- registration, and setDuration() was NEVER actually called. This was
-- completely invisible from the client: the progress bar and animation you see
-- come from the vanilla per-character update() loop, which already runs
-- getGameSpeed() times per rendered frame and therefore speeds up correctly on
-- its own, no mod involvement needed or possible to break. What never sped up
-- is the SEPARATE, real, server-authoritative completion timer
-- (zombie.core.Action: startTime/endTime, using GameTime.getServerTimeMills(),
-- which on the server is literally System.nanoTime() -- true wall-clock,
-- completely unaffected by setGameSpeed()) that actually gates when :perform()
-- fires and the task's real effect (hunger reduction, item consumed, etc.)
-- applies.
--
-- The correct, universal hook is ISBaseTimedAction:adjustMaxTime (shared by
-- EVERY TimedAction that derives from it, not just 6 hardcoded classes):
-- ISBaseTimedAction:create() calls `self.maxTime = self:adjustMaxTime(self.maxTime)`
-- once, server-side, before constructing the actual LuaTimedActionNew action
-- object that drives real completion -- this is the one point server and
-- client both compute maxTime independently but only the server's copy is
-- authoritative. Scaling it down by our speed multiplier here, gated to
-- isServer() only, accelerates real completion time to match the granted
-- speed without touching the client's own already-correct local calculation
-- (which the sprint/moodle/pain/temperature adjustments inside the original
-- adjustMaxTime still apply to, unchanged, on both sides).
require "TimedActions/ISBaseTimedAction"

local function wantedMultiplier()
    return applied >= Core.FAST_FORWARD_MIN and Core.multiplierFor(applied) or 1
end

if not ServerState.adjustMaxTimeHooked then
    ServerState.adjustMaxTimeHooked = true
    local originalAdjustMaxTime = ISBaseTimedAction.adjustMaxTime
    function ISBaseTimedAction:adjustMaxTime(maxTime)
        maxTime = originalAdjustMaxTime(self, maxTime)
        if isServer() then
            local mult = wantedMultiplier()
            if mult ~= 1 then
                maxTime = maxTime / mult
                Core.debugLog(string.format("adjustMaxTime scaled: base=%.2f target=%.2f x%s",
                    maxTime * mult, maxTime, tostring(mult)))
            end
        end
        return maxTime
    end
end

local function onTick()
    local cfg = Core.getConfig()
    if not cfg.Enabled then
        if wasEnabled then forceNormal("disabled", nil) end
        wasEnabled = false
        return
    end
    wasEnabled = true

    refreshElectorate("players_changed", nil)
    enforceSoloGate()
    enforceHardcoreKitsGate()

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
