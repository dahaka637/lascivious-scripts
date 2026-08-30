--[[
    Burris Quality of Life -- "Pry Open" slice on the vehicle radial menu.

    Wraps ISVehicleMenu.showRadialMenuOutside (client/Vehicles/ISUI/ISVehicleMenu.lua:277).
    The wrapper always calls through to vanilla first; the mod this is modelled
    on inserted an early return that suppressed vanilla's entire radial menu
    whenever the player was in a vehicle.

    Vanilla already bails on `playerObj:getVehicle()` itself, so there is no
    need to repeat that check before delegating.
]]

require "BQoL/BQoL_PryLogic"
require "TimedActions/BQoL_VehiclePryAction"

--- Vehicle doors are harder to lever than building doors.
local VEHICLE_PENALTY = 20

local function onPryVehicleSelected(playerObj, part)
    local tool = BQoL.Pry.findTool(playerObj)
    if not tool then
        playerObj:Say(getText("IGUI_BQoL_NoPryTool"))
        return
    end

    ISTimedActionQueue.add(
        BQoL_VehiclePryAction:new(playerObj, part, tool, VEHICLE_PENALTY))
end

--[[
    Finds a locked door worth prying.

    getUseablePart() is the same call vanilla uses to decide which door the
    player is standing next to, so the slice targets exactly the door vanilla
    would have offered to unlock. The hood is excluded: levering a bonnet open
    is not a lock-defeating action.
]]
local function findLockedDoor(vehicle, playerObj)
    local part = vehicle:getUseablePart(playerObj)
    if not part then return nil end

    local door = part:getDoor()
    if not door then return nil end
    if part:getId() == "EngineDoor" then return nil end

    if door:isOpen() or not door:isLocked() then return nil end

    return part
end

local function addPrySlice(playerObj)
    if not BQoL.getBool("PryEnabled") or not BQoL.getBool("PryVehicleDoors") then return end
    if playerObj:getVehicle() then return end

    if not BQoL.Pry.findTool(playerObj) then return end

    local vehicle = ISVehicleMenu.getVehicleToInteractWith(playerObj)
    if not vehicle then return end

    local part = findLockedDoor(vehicle, playerObj)
    if not part then return end

    local menu = getPlayerRadialMenu(playerObj:getPlayerNum())
    if not menu then return end

    menu:addSlice(
        getText("ContextMenu_BQoL_PryOpen"),
        getTexture("media/ui/vehicles/vehicle_lockdoors.png"),
        onPryVehicleSelected, playerObj, part)
end

BQoL.feature{
    id = "PryVehicle",
    sandbox = "PryVehicleDoors",
    init = function()
        local original = ISVehicleMenu.showRadialMenuOutside

        if type(original) ~= "function" then
            BQoL.warn("PryVehicle: ISVehicleMenu.showRadialMenuOutside is missing")
            return
        end

        ISVehicleMenu.showRadialMenuOutside = function(playerObj)
            original(playerObj)

            -- Never let our slice break the vanilla menu.
            BQoL.safe("PryVehicle.addSlice", addPrySlice, playerObj)
        end
    end,
}
