--[[
    Burris Quality of Life -- "Pry Open" on doors and windows.

    Hooks Events.OnFillWorldObjectContextMenu, which is the supported way to add
    entries (ISWorldObjectContextMenu.lua:213). Note the first argument is a
    player *index*, not the object.
]]

require "BQoL/BQoL_PryLogic"
require "TimedActions/BQoL_PryAction"

local function onPrySelected(worldobjects, playerObj, target, kind, garage)
    -- Re-checked rather than passed through: the player may have dropped the
    -- crowbar between opening the menu and clicking.
    local tool = BQoL.Pry.findTool(playerObj)
    if not tool then
        playerObj:Say(getText("IGUI_BQoL_NoPryTool"))
        return
    end

    local square = target:getSquare()
    if not square then return end

    -- Windows and doors have their own walk-to helper that approaches from a
    -- side you can actually reach the handle from.
    local reached = luautils.walkAdjWindowOrDoor(playerObj, square, target)
    if not reached then return end

    ISTimedActionQueue.add(
        BQoL_PryAction:new(playerObj, target, kind, garage, tool, 0))
end

--- Returns the single best prying target near the click, or nil.
local function findTarget(squares)
    for _, square in ipairs(squares) do
        local objects = square:getObjects()

        for i = 0, objects:size() - 1 do
            local candidate = BQoL.Pry.classify(objects:get(i))

            if candidate and not BQoL.Pry.isBlockedBySafehouse(candidate.object) then
                return candidate
            end
        end
    end

    return nil
end

local function onFillWorldObjectContextMenu(playerNum, context, worldobjects, test)
    if test and ISWorldObjectContextMenu.Test then return true end

    local playerObj = getSpecificPlayer(playerNum)
    if not playerObj or playerObj:getVehicle() then return end

    local tool = BQoL.Pry.findTool(playerObj)
    if not tool then return end

    local target = findTarget(BQoL.gatherSquares(worldobjects))
    if not target then return end

    if test then
        ISWorldObjectContextMenu.setTest()
        return true
    end

    local option = context:addOptionOnTop(
        getText("ContextMenu_BQoL_PryOpen"), worldobjects, onPrySelected,
        playerObj, target.object, target.kind, target.garage)

    -- Reinforced doors are visible but refused until the player is strong
    -- enough, so the option explains itself rather than silently missing.
    if target.kind == "door" and BQoL.Pry.isReinforced(target.object)
        and not BQoL.Pry.canForceReinforced(playerObj) then

        option.notAvailable = true
        BQoL.tooltip(option, getText("Tooltip_BQoL_PryReinforced",
            BQoL.getNumber("PryReinforcedDoorLevel")))
        return
    end

    BQoL.tooltip(option, target.kind == "window"
        and getText("Tooltip_BQoL_PryWindow")
        or getText("Tooltip_BQoL_PryDoor"))
end

--[[
    Options whose resolved values get logged at init under Debug logging.

    Worth the handful of lines: "the sandbox toggle does nothing" is
    unfalsifiable from the outside, because a toggle that is being ignored and
    a toggle whose value never reached us look identical in game. This prints
    what the mod actually read, so one launch tells you which of the two it
    is -- and BQoL.get warns separately when the whole namespace is missing.
]]
local LOGGED_OPTIONS = {
    "PryEnabled", "PryBuildingDoors", "PryGarageDoors",
    "PrySafeDoors", "PryWindows", "PryVehicleDoors",
}

local function logResolvedOptions()
    for _, key in ipairs(LOGGED_OPTIONS) do
        BQoL.log("Pry: %s = %s (raw %s)", key,
            tostring(BQoL.getBool(key)), tostring(BQoL.get(key)))
    end
end

BQoL.feature{
    id = "Pry",
    sandbox = "PryEnabled",
    init = function()
        logResolvedOptions()
        Events.OnFillWorldObjectContextMenu.Add(onFillWorldObjectContextMenu)
    end,
}
