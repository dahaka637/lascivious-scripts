--[[
    Burris Quality of Life -- "Pick Up" on ground debris vanilla doesn't cover.

    See BQoL_Debris.lua for exactly which sprites this applies to and why:
    in short, the d_generic_1 tileset (twigs/grass/rocks on grass) has 80
    sprites, 20 of which vanilla already handles via a CustomName property on
    the tiledef and its own ISPickUpGroundCoverItem action. This covers the
    other 60, which currently do nothing when right-clicked.
]]

require "BQoL/BQoL_Core"
require "BQoL/BQoL_API"
require "TimedActions/BQoL_CollectAction"

--- Finds the first mapped debris object among the given squares, at most one per square scan.
local function findDebris(squares)
    for _, square in ipairs(squares) do
        local objects = square:getObjects()

        for i = 0, objects:size() - 1 do
            local object = objects:get(i)
            local sprite = object.getSprite and object:getSprite()
            local spriteName = sprite and sprite:getName()

            if spriteName then
                local items = BQoL.API.getDebrisMapping(spriteName)
                if items then
                    return object, square, items
                end
            end
        end
    end

    return nil
end

local function onCollectSelected(worldobjects, playerObj, object, square, items)
    if not luautils.walkAdj(playerObj, square) then return end
    ISTimedActionQueue.add(BQoL_CollectAction:new(playerObj, square, object, items))
end

local function onFillWorldObjectContextMenu(playerNum, context, worldobjects, test)
    if test and ISWorldObjectContextMenu.Test then return true end

    local playerObj = getSpecificPlayer(playerNum)
    if not playerObj or playerObj:getVehicle() then return end

    local object, square, items = findDebris(BQoL.gatherSquares(worldobjects))
    if not object then return end

    if test then
        ISWorldObjectContextMenu.setTest()
        return true
    end

    context:addOptionOnTop(getText("ContextMenu_BQoL_PickUp"), worldobjects,
        onCollectSelected, playerObj, object, square, items)
end

BQoL.feature{
    id = "Collect",
    sandbox = "CollectEnabled",
    init = function()
        Events.OnFillWorldObjectContextMenu.Add(onFillWorldObjectContextMenu)
    end,
}
