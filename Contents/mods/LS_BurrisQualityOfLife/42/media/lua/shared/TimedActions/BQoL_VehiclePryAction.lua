--[[
    Burris Quality of Life -- prying a vehicle door.

    Separate from BQoL_PryAction because the target is a VehiclePart rather than
    an IsoObject, and because vehicles have their own transmit path.

    Vanilla's ISUnlockVehicleDoor cannot be reused here: it calls
    vehicle:toggleLockedDoor(), which requires the key and silently refuses
    without it. Forcing a lock means breaking it -- setLockBroken(true) --
    which is what vanilla itself does when a car spawns with a broken lock
    (server/Vehicles/Vehicles.lua:162).
]]

require "TimedActions/ISBaseTimedAction"
require "BQoL/BQoL_PryLogic"

BQoL_VehiclePryAction = ISBaseTimedAction:derive("BQoL_VehiclePryAction")

function BQoL_VehiclePryAction:isValid()
    if not self.part or not self.vehicle then return false end

    local door = self.part:getDoor()
    if not door then return false end

    -- Someone else may have opened it while we were working.
    if door:isOpen() or not door:isLocked() then return false end

    return self.tool ~= nil and not self.tool:isBroken()
end

function BQoL_VehiclePryAction:waitToStart()
    self.character:faceThisObject(self.vehicle)
    return self.character:shouldBeTurning()
end

function BQoL_VehiclePryAction:update()
    self.character:faceThisObject(self.vehicle)
    self.character:setMetabolicTarget(Metabolics.HeavyWork)
end

function BQoL_VehiclePryAction:start()
    self:setActionAnim("RemoveBarricade")
    self:setAnimVariable("RemoveBarricade", "CrowbarMid")
    self:setOverrideHandModels(self.tool, nil)

    self.sound = self.character:playSound("BeginRemoveBarricadePlankCrowbar")
    addSound(self.character, self.character:getX(), self.character:getY(),
        self.character:getZ(), 12, 8)
end

local function stopSound(self)
    if not self.sound then return end
    self.character:getEmitter():stopSound(self.sound)
    self.sound = nil
end

function BQoL_VehiclePryAction:stop()
    stopSound(self)
    ISBaseTimedAction.stop(self)
end

function BQoL_VehiclePryAction:perform()
    stopSound(self)
    ISBaseTimedAction.perform(self)
end

local function transmitDoor(self)
    BQoL.safe("VehiclePry.transmit", function()
        self.vehicle:transmitPartDoor(self.part)
    end)
end

--[[
    Breaks the lock and opens the door.

    setLocked/setLockBroken are called on the door directly and then published
    with transmitPartDoor(), which is the same call ISUnlockVehicleDoor uses --
    so this is multiplayer-correct without a custom server command.

    Opening the door is where the two sides part company. Queueing
    ISOpenVehicleDoor is the nicer path and the one single player takes: it
    plays the door swing, trips the alarm and selects the container in the loot
    window. But this complete() runs on the dedicated server and nowhere else
    in multiplayer (BQoL.hasLocalQueue explains why), and there is no queue
    there -- that is the crash this file shipped with. So without one, do what
    ISOpenVehicleDoor:complete() would have done and open the door outright.
    Skipping it is not an option: the lock would break and the door would stay
    shut, which is exactly how the bug presented to players.
]]
local function forceDoorOpen(self)
    local door = self.part:getDoor()

    door:setLockBroken(true)
    door:setLocked(false)
    transmitDoor(self)

    -- Unconditional, as ISUnlockVehicleDoor:perform() plays it -- vehicle
    -- sounds are cheap and the call is a no-op where nobody can hear it.
    self.vehicle:playPartSound(self.part, self.character, "Unlock")

    if BQoL.hasLocalQueue(self.character) then
        ISTimedActionQueue.add(
            ISOpenVehicleDoor:new(self.character, self.vehicle, self.part))
        return
    end

    BQoL.safe("VehiclePry.openDoor", function() door:setOpen(true) end)
    transmitDoor(self)
end

--[[
    A failed attempt may put a window through instead.

    Same split as forceDoorOpen. window:hit() is what ISSmashVehicleWindow's
    own complete() does, so the direct path is the vanilla one minus the swing
    animation -- which no one is watching on a dedicated server anyway.
]]
local function maybeShatterWindow(self)
    if not BQoL.getBool("PryShatterVehicleWindows") then return end
    if ZombRand(100) >= BQoL.getNumber("PryWindowShatterChance") then return end

    local windowPart = self.vehicle:getClosestWindow(self.character)
    if not windowPart then return end

    local window = windowPart:getWindow()
    if not window or not window:isHittable() then return end

    if BQoL.hasLocalQueue(self.character) then
        ISTimedActionQueue.add(
            ISSmashWindow:new(self.character, window, windowPart))
        return
    end

    BQoL.safe("VehiclePry.smashWindow", function()
        window:hit(self.character)
    end)
end

--- Outcome first, endurance last -- see the note on BQoL_PryAction:complete.
function BQoL_VehiclePryAction:complete()
    local playerObj = self.character

    if BQoL.Pry.roll(playerObj, self.penalty) then
        forceDoorOpen(self)
        addXp(playerObj, Perks.Strength, 10)
    else
        playerObj:Say(getText("IGUI_BQoL_PryFailed"))
        playerObj:playSound("BreakBarricadePlank")
        addSound(playerObj, playerObj:getX(), playerObj:getY(), playerObj:getZ(), 10, 6)

        maybeShatterWindow(self)
    end

    BQoL.Pry.tire(playerObj, 0.1)
    return true
end

function BQoL_VehiclePryAction:getDuration()
    if self.character:isTimedActionInstant() then
        return 1
    end
    return math.max(80, 220 - (BQoL.Pry.getStrength(self.character) * 8))
end

function BQoL_VehiclePryAction:new(character, part, tool, penalty)
    local o = ISBaseTimedAction.new(self, character)

    o.character = character
    o.part = part
    o.vehicle = part and part:getVehicle()
    o.tool = tool
    o.penalty = penalty or 0
    o.maxTime = o:getDuration()

    return o
end
