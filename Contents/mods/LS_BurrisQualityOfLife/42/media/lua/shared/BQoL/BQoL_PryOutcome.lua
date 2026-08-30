--[[
    Burris Quality of Life -- applying the result of a prying attempt.

    Kept separate from BQoL_PryLogic so there is exactly one implementation of
    "the door is now open", called either directly (singleplayer, where the
    client is the authority) or from the server command handler (multiplayer).
]]

require "BQoL/BQoL_PryLogic"

BQoL = BQoL or {}
BQoL.Pry = BQoL.Pry or {}

local Pry = BQoL.Pry

--[[
    Unlocks a door and every object that moves with it.

    Doubles and garage doors are made of several IsoObjects that each carry
    their own lock state; unlocking only the clicked one leaves the other half
    locked. Modelled on vanilla's own DebugContextMenu.OnDoorLock
    (client/DebugUIs/DebugContextMenu.lua:755).
]]
local function unlockDoor(door)
    door:setIsLocked(false)

    --[[
        Cleared unconditionally, as the sibling loops below already do.

        This used to be gated on the door having a key id, which left a door
        that reports isLockedByKey() but carries no key id still locked after
        a successful pry. That gate was harmless only because Pry.classify
        refused key-locked doors outright, so this branch never ran on one;
        now that classify accepts them, the gate would be a live failure.
        Clearing the flag on a door that was not key-locked is a no-op.
    ]]
    if door.setLockedByKey then
        door:setLockedByKey(false)
    end

    for _, sibling in ipairs(buildUtil.getDoubleDoorObjects(door)) do
        sibling:setLockedByKey(false)
        if sibling.setIsLocked then sibling:setIsLocked(false) end
    end

    for _, sibling in ipairs(buildUtil.getGarageDoorObjects(door)) do
        sibling:setLockedByKey(false)
        if sibling.setIsLocked then sibling:setIsLocked(false) end
    end
end

--[[
    Clears a window's lock so ToggleWindow will actually open it.

    Exactly the trap the setLockedByKey gate above was: a step that looks
    optional only while classify refuses the case that needs it. classify used
    to offer Pry Open on any closed window regardless of its lock, so the
    windows that reached here were almost always unlocked and ToggleWindow
    opened them unaided. Now that a window has to be locked to be offered at
    all, skipping this would mean every successful window pry played its
    animation, awarded XP and left the window shut.

    setIsLocked is the setter that pairs with IsoWindow:isLocked() -- vanilla
    uses both in client/DebugUIs/DebugContextMenu.lua:853.
]]
local function unlockWindow(window)
    BQoL.safe("Pry.unlockWindow", function()
        if window.setIsLocked then window:setIsLocked(false) end
    end)
end

--- Pushes the new state to other players. No-op in singleplayer.
local function transmit(object)
    if not (isClient() or isServer()) then return end

    BQoL.safe("Pry.transmit", function()
        object:sendObjectChange(IsoObjectChange.STATE)
    end)
end

--[[
    Applies a successful attempt.

    `playerObj` may be nil when this runs on a dedicated server without a local
    character; the world change still happens, only the XP award is skipped.
]]
function Pry.applySuccess(object, playerObj, kind)
    if not object then return false end

    if kind == "window" then
        unlockWindow(object)
        BQoL.safe("Pry.openWindow", function() object:ToggleWindow(playerObj) end)
    else
        unlockDoor(object)
        BQoL.safe("Pry.openDoor", function() object:ToggleDoor(playerObj) end)
    end

    transmit(object)

    if playerObj then
        addXp(playerObj, Perks.Strength, 10)

        --[[
            setKnownBlockedDoor only has an implementation for IsoDoor --
            calling it with an IsoWindow throws "No implementation found for
            function" (a Java reflection failure, not something BQoL.safe's
            pcall can head off cleanly beforehand), so this must be skipped
            for windows rather than merely wrapped.
        ]]
        if kind ~= "window" then
            BQoL.safe("Pry.mapKnowledge", function()
                playerObj:getMapKnowledge():setKnownBlockedDoor(object, false)
            end)
        end
    end

    BQoL.log("Pry: forced %s open", tostring(kind))
    return true
end

--[[
    Applies a failed attempt. Windows may shatter; doors just hold.
    Returns true when the window broke.
]]
function Pry.applyFailure(object, playerObj, kind)
    if not object then return false end
    if kind ~= "window" then return false end

    local chance = BQoL.getNumber("PryWindowShatterChance")
    if ZombRand(100) >= chance then return false end

    local smashed = BQoL.safe("Pry.smashWindow", function()
        object:smashWindow(playerObj)
    end)

    if not smashed then
        -- Older/renamed API: fall back to destroying the pane.
        BQoL.safe("Pry.destroyWindow", function() object:destroy() end)
    end

    transmit(object)
    BQoL.log("Pry: window shattered")
    return true
end
