--[[
    Burris Quality of Life -- corpses into vehicle trunks and trailers.

    Build 42.20 already ships corpse storage: shared/BodyDragging/
    corpseStorageCheck.lua adds "Drop Corpse Into <container>" to the world
    context menu while you are dragging a body, and ItemContainer.
    canHumanCorpseFit accepts *any* vehicle container -- seat, trunk, truck
    bed, trailer bed -- gated only on `capacity - contents >= 20`. So none of
    that is reimplemented here; doing so would put two "Drop Corpse Into"
    entries in the same menu.

    What vanilla gets wrong is the vehicle door, and it gets it wrong in
    exactly the case players ask for. Two defects, both patched below.
]]

require "BQoL/BQoL_Core"

--[[
    Defect 1: the trunk door is never opened.

    corpseStorageCheck decides whether a door is in the way with
    ItemContainer:doesVehicleDoorNeedOpening(), which resolves the part via
    getVehicleDoorPart() -- and that handles trunks properly, routing through
    VehiclePart.isVehicleTrunk() to VehiclePartOwner.getTrunkDoorPart().

    But when it comes to actually opening that door it calls
    getVehicleSeatDoorPart() instead, whose first line is
    `if (!isVehicleSeat()) return null`. For a trunk or truck bed that is
    always nil, so openContainerVehicleDoor returns early having done nothing.
    The menu offers the option, correctly works out the door needs opening,
    silently fails to open it, and queues ISDropCorpseIntoContainer against a
    shut trunk.

    The fix is to keep the seat-specific lookup first -- it is the more
    precise one, mapping a seat's container to that seat's passenger door --
    and fall back to the general accessor for everything else.
]]
local function resolveDoorPart(container)
    local ok, part = BQoL.safe("CorpseTrunk.seatDoorPart", function()
        return container:getVehicleSeatDoorPart()
    end)

    if ok and part then return part end

    local ok2, general = BQoL.safe("CorpseTrunk.doorPart", function()
        return container:getVehicleDoorPart()
    end)

    if ok2 then return general end
    return nil
end

local function openDoor(playerNum, container)
    local playerObj = getSpecificPlayer(playerNum)
    if not playerObj or not container then return false end

    local part = resolveDoorPart(container)
    if not part then return false end

    BQoL.safe("CorpseTrunk.openDoor", function()
        ISVehicleMenu.onOpenDoor(playerObj, part)
    end)
    return true
end

local function closeDoor(playerNum, container)
    local playerObj = getSpecificPlayer(playerNum)
    if not playerObj or not container then return false end

    local part = resolveDoorPart(container)
    if not part then return false end

    BQoL.safe("CorpseTrunk.closeDoor", function()
        ISVehicleMenu.onCloseDoor(playerObj, part)
    end)
    return true
end

--[[
    Defect 2: onGrabCorpseFrom passes a nil character.

    Vanilla's copy never declares playerObj in that function, yet calls
    targetContainer:canCharacterUnlockVehicleDoor(playerObj) -- it is reading
    an undefined global, so BaseVehicle.canUnlockDoor gets a null character
    and taking a corpse back out of any closed vehicle container fails.
    (onDropCorpseInto does declare it; only the grab path is affected.)

    Replaced rather than wrapped, because the bug is mid-function and there is
    no way to correct it from the outside. Otherwise this follows vanilla step
    for step: find the corpse, walk to the container, open the door if it is
    shut, transfer, close the door behind you.
]]
local function onGrabCorpseFrom(playerNum, targetContainer)
    local playerObj = getSpecificPlayer(playerNum)
    if not playerObj or not targetContainer then return end

    local corpseItem = targetContainer:findHumanCorpseItem()
    if not corpseItem then return end

    if not luautils.walkToContainer(targetContainer, playerNum) then return end

    local doorNeedsOpening = targetContainer:doesVehicleDoorNeedOpening()
    if doorNeedsOpening then
        if not targetContainer:canCharacterUnlockVehicleDoor(playerObj) then
            BQoL.log("CorpseTrunk: cannot unlock the door to grab from it")
            return
        end
        openDoor(playerNum, targetContainer)
    end

    ISInventoryPaneContextMenu.transferItemToPlayer(corpseItem, playerNum)

    if doorNeedsOpening then
        closeDoor(playerNum, targetContainer)
    end
end

BQoL.feature{
    id = "CorpseTrunk",
    sandbox = "CorpseTrunkEnabled",
    init = function()
        --[[
            Resolved rather than referenced directly: corpseStorageCheck is a
            plain global declared in shared/BodyDragging/, and a later build
            that renames or drops it should leave us degrading to vanilla
            behaviour instead of throwing at init.
        ]]
        local vanilla = BQoL.resolve("corpseStorageCheck")

        if not vanilla then
            BQoL.warn("CorpseTrunk: corpseStorageCheck is missing; " ..
                "vehicle corpse storage is left as the base game has it")
            return
        end

        vanilla.openContainerVehicleDoor = openDoor
        vanilla.closeContainerVehicleDoor = closeDoor
        vanilla.onGrabCorpseFrom = onGrabCorpseFrom
    end,
}
