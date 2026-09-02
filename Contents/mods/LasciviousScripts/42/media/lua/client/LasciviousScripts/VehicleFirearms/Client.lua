--
-- Lascivious Scripts - Vehicle Firearms
--
-- Client-side safety layer for firearm handling while driving.
--

require "LasciviousScripts/VehicleFirearms/Core"
require "TimedActions/ISTimedActionQueue"

local Core = LasciviousScripts.VehicleFirearms

local Client = {}
Core.Client = Client

local CANCEL_DEBOUNCE_MS = 250

local Runtime = {
    lastCancelAt = {},
    attackDown = {},
}

local KEY_EVENT_CANCEL_BINDINGS = {
    { key = "CancelAction", reason = "cancel_key", eat = true, brake = false },
    -- Do not eat Rack Firearm. After this module clears the stuck reload, the
    -- vanilla firearm radial/menu handler can still perform the actual rack /
    -- unjam action bound by the player.
    { key = "Rack Firearm", reason = "rack_firearm", eat = false, brake = false },
}

local POLLED_CANCEL_BINDINGS = {
    { key = "CancelAction", reason = "cancel_key", brake = false },
}

local function safeBool(fn)
    local ok, value = pcall(fn)
    return ok and value == true
end

local function playerNumOf(player)
    if not player then return 0 end
    local ok, num = pcall(function() return player:getPlayerNum() end)
    if ok and type(num) == "number" then return num end
    return 0
end

local function isLocalPlayer(player)
    if not player then return false end
    if safeBool(function() return player:isLocalPlayer() end) then return true end

    if getPlayer then
        local ok, localPlayer = pcall(getPlayer)
        if ok and localPlayer == player then return true end
    end

    if getNumActivePlayers and getSpecificPlayer then
        local okCount, count = pcall(getNumActivePlayers)
        if okCount and type(count) == "number" then
            for index = 0, count - 1 do
                local okSpecific, localPlayer = pcall(getSpecificPlayer, index)
                if okSpecific and localPlayer == player then return true end
            end
        end
    end

    return false
end

local function getTimestamp()
    if getTimestampMs then return getTimestampMs() end
    return 0
end

local function isMouseOverAnyUI()
    if not isMouseOverUI then return false end
    return safeBool(function() return isMouseOverUI() end)
end

local function keyPressed(binding)
    if not binding then return false end
    return safeBool(function() return isKeyPressed(binding) end)
end

local function keyDown(binding)
    if not binding then return false end

    if GameKeyboard and GameKeyboard.isKeyDown and safeBool(function() return GameKeyboard.isKeyDown(binding) end) then
        return true
    end

    if safeBool(function() return isKeyDown(binding) end) then return true end

    local core = getCore and getCore() or nil
    if not core then return false end

    local okKey, key = pcall(function() return core:getKey(binding) end)
    if okKey and key and key > 0 and safeBool(function() return isKeyDown(key) end) then return true end

    local okAlt, alt = pcall(function() return core:getAltKey(binding) end)
    if okAlt and alt and alt > 0 and safeBool(function() return isKeyDown(alt) end) then return true end

    return false
end

local function mouseLeftDown()
    return safeBool(function() return isMouseButtonDown(0) end)
end

local function isBindingKey(key, binding)
    local core = getCore and getCore() or nil
    if not core then return false end
    return safeBool(function() return core:isKey(binding, key) end)
end

local function currentActionFor(player)
    if not player or not ISTimedActionQueue or not ISTimedActionQueue.getTimedActionQueue then return nil, nil end

    local ok, queue = pcall(ISTimedActionQueue.getTimedActionQueue, player)
    if not ok or not queue then return nil, nil end

    local action = queue.current
    if not action and queue.queue then action = queue.queue[1] end

    return action, queue
end

local function relaxQueuedFirearmActions(player, queue)
    if not queue or not queue.queue then return end
    for _, action in ipairs(queue.queue) do
        if action and action.character == player then Core.relaxActionForDriver(action) end
    end
end

local function eatKeyPress(key)
    if not key or not GameKeyboard or not GameKeyboard.eatKeyPress then return end
    pcall(GameKeyboard.eatKeyPress, key)
end

local function clearFirearmAction(player, action, reason)
    local playerNum = playerNumOf(player)
    local now = getTimestamp()
    local last = Runtime.lastCancelAt[playerNum] or 0
    if now > 0 and last > 0 and now - last < CANCEL_DEBOUNCE_MS then return false end

    Runtime.lastCancelAt[playerNum] = now

    Core.clearFirearmAnimationState(player, action)

    local cleared = false
    if ISTimedActionQueue and ISTimedActionQueue.clear then
        local ok = pcall(ISTimedActionQueue.clear, player)
        cleared = ok == true
    end

    if not cleared then
        cleared = safeBool(function() player:StopAllActionQueue(); return true end)
    end

    Core.clearFirearmAnimationState(player, action)
    Core.releaseMovementLocks(player)

    return true
end

local function emergencyCancelReason(player)
    local playerNum = playerNumOf(player)

    for _, binding in ipairs(POLLED_CANCEL_BINDINGS) do
        if keyPressed(binding.key) then return binding.reason end
    end

    local attackNow = keyPressed("Attack/Click") or keyDown("Attack/Click") or mouseLeftDown()
    local wasAttackDown = Runtime.attackDown[playerNum] == true
    Runtime.attackDown[playerNum] = attackNow == true

    if attackNow and not wasAttackDown and not isMouseOverAnyUI() then
        return "attack_click"
    end

    return nil
end

local function refreshAttackState(player)
    Runtime.attackDown[playerNumOf(player)] = (keyDown("Attack/Click") or mouseLeftDown()) == true
end

local function handlePlayer(player)
    if not player then return end

    local playerNum = playerNumOf(player)
    if not Core.isDriver(player) then
        Runtime.attackDown[playerNum] = false
        return
    end

    local action, queue = currentActionFor(player)
    Core.preserveDriverControls(player, action, "tick")

    if action and Core.isFirearmAction(action) then
        Core.relaxActionForDriver(action)
        relaxQueuedFirearmActions(player, queue)

        local cfg = Core.getConfig()
        if cfg.Enabled and cfg.EmergencyCancel then
            local reason = emergencyCancelReason(player)
            if reason then clearFirearmAction(player, action, reason) end
        end

        return
    end

    if Core.hasFirearmAnimationState(player) then
        Core.clearFirearmAnimationState(player, nil)
        Core.releaseMovementLocks(player)
    end

    refreshAttackState(player)
end

local function onPlayerUpdate(player)
    if not player then return end

    local cfg = Core.getConfig()
    if not cfg.Enabled or not cfg.PreserveDriverControls then return end
    if not isLocalPlayer(player) then return end
    if not Core.isDriver(player) then return end

    local action = currentActionFor(player)
    if action and Core.isFirearmAction(action) then
        Core.relaxActionForDriver(action)
    end

    Core.preserveDriverControls(player, action, "player_update")
end

local function eachLocalPlayer(callback)
    local count = 1
    if getNumActivePlayers then
        local ok, num = pcall(getNumActivePlayers)
        if ok and type(num) == "number" and num > 0 then count = num end
    end

    local seen = false
    for index = 0, count - 1 do
        local player = nil
        if getSpecificPlayer then
            local ok, value = pcall(getSpecificPlayer, index)
            if ok then player = value end
        end
        if player then
            seen = true
            callback(player)
        end
    end

    if not seen and getPlayer then
        local player = getPlayer()
        if player then callback(player) end
    end
end

local function onTick()
    local cfg = Core.getConfig()
    if not cfg.Enabled then return end

    Core.patchFirearmTimedActions()
    eachLocalPlayer(handlePlayer)
end

local function onGameStart()
    Core.patchFirearmTimedActions(true)
end

local function onKeyStartPressed(key)
    local cfg = Core.getConfig()
    if not cfg.Enabled or not cfg.EmergencyCancel then return end

    local matched = nil
    for _, binding in ipairs(KEY_EVENT_CANCEL_BINDINGS) do
        if isBindingKey(key, binding.key) then
            matched = binding
            break
        end
    end
    if not matched then return end

    local cancelled = false
    eachLocalPlayer(function(player)
        if cancelled or not Core.isDriver(player) then return end
        local action = currentActionFor(player)
        if action and Core.isFirearmAction(action) then
            cancelled = clearFirearmAction(player, action, matched.reason)
        end
    end)

    if cancelled and matched.eat then eatKeyPress(key) end
end

local function addEvent(event, callback, name)
    if event and event.Add then
        event.Add(callback)
    end
end

local eventTable = Events or {}
addEvent(eventTable.OnGameStart, onGameStart, "OnGameStart")
addEvent(eventTable.OnPlayerUpdate, onPlayerUpdate, "OnPlayerUpdate")
addEvent(eventTable.OnTick, onTick, "OnTick")
addEvent(eventTable.OnKeyStartPressed, onKeyStartPressed, "OnKeyStartPressed")

return Client
