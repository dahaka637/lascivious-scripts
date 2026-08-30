--[[
    Burris Quality of Life -- wash only equipped or only unequipped items.

    Vanilla's Wash submenu is built in Java
    (zombie.iso.ISWorldObjectContextMenuLogic.doWashClothingMenu) and cannot be
    hooked from Lua, so this adds a second, deliberately narrow entry beside it.
    Vanilla already covers everything else -- All Clothing, All Containers, All
    Weapons, All Bandages, per-item entries and soap/water tooltips -- so the
    only thing here is the equipped/unequipped filter it lacks.

    Nothing is reimplemented: the filtered list is handed to vanilla's own
    ISWorldObjectContextMenu.onWashClothing, which does the walking, the soap
    accounting and the clothing-vs-weapon blood split
    (ISWorldObjectContextMenu.lua:1792).
]]

require "BQoL/BQoL_Core"

--[[
    Mirrors what the Java wash menu itself considers washable -- its constant
    pool references hasBlood/hasDirt and nothing fancier. Weapons carry blood
    but not dirt; clothing and bags carry both, per body part.
]]
local function isWashable(item)
    if instanceof(item, "Clothing") or instanceof(item, "InventoryContainer") then
        return item:hasBlood() or item:hasDirt()
    end
    return item:IsWeapon() and item:getBloodLevel() > 0
end

--[[
    IsoObject has no isWaterSource() -- that method only exists on
    InventoryItem. hasWater() is what the Java wash menu references and what
    ISCleanBandage:isValid() and Tutorial1 use to spot water fixtures.

    The guard mirrors BQoL.gatherSquares' own idiom; BQoL.has() only accepts
    tables and world objects are userdata in Kahlua.

    worldobjects is checked first because clicking a sink directly puts it
    there, but B42 does not guarantee it -- the object under the cursor is
    often the floor or a wall on the same tile -- so the surrounding squares
    are scanned as a fallback, the same way the prying menu does.
]]
local function findSink(worldobjects)
    for _, object in ipairs(worldobjects) do
        if object and object.hasWater and object:hasWater() then
            return object
        end
    end

    for _, square in ipairs(BQoL.gatherSquares(worldobjects)) do
        local objects = square:getObjects()
        for i = 0, objects:size() - 1 do
            local object = objects:get(i)
            if object and object.hasWater and object:hasWater() then
                return object
            end
        end
    end

    return nil
end

--[[
    Partitions everything washable the player carries -- including inside
    bags -- by whether it is currently equipped.

    The results are plain Lua tables, not the ArrayList getAllEvalRecurse
    returns, because vanilla's calculateSoapAndWaterRequired and
    onWashClothing iterate the list with ipairs.
]]
local function buildWashLists(playerObj)
    local equipped, unequipped = {}, {}
    local items = playerObj:getInventory():getAllEvalRecurse(isWashable)

    for i = 0, items:size() - 1 do
        local item = items:get(i)
        if playerObj:isEquipped(item) then
            table.insert(equipped, item)
        else
            table.insert(unequipped, item)
        end
    end

    return equipped, unequipped
end

local function onWashSelected(worldobjects, playerObj, sink, soapList, washList)
    ISWorldObjectContextMenu.onWashClothing(playerObj, sink, soapList, washList)
end

local function addWashOption(submenu, worldobjects, labelKey,
        playerObj, sink, soapList, washList)

    local option = submenu:addOption(getText(labelKey), worldobjects,
        onWashSelected, playerObj, sink, soapList, washList)

    local soapRequired, waterRequired =
        ISWorldObjectContextMenu.calculateSoapAndWaterRequired(washList)
    local soapAvailable = ISWashClothing.GetSoapRemaining(soapList)

    BQoL.tooltip(option, getText("Tooltip_BQoL_WashRequirements",
        soapRequired, soapAvailable, waterRequired, sink:getFluidAmount()))

    if sink:getFluidAmount() <= 0 then
        option.notAvailable = true
    end
end

local function onFillWorldObjectContextMenu(playerNum, context, worldobjects, test)
    if test and ISWorldObjectContextMenu.Test then return true end

    local playerObj = getSpecificPlayer(playerNum)
    if not playerObj or playerObj:getVehicle() then return end

    local sink = findSink(worldobjects)
    if not sink then return end

    local equipped, unequipped = buildWashLists(playerObj)
    if #equipped == 0 and #unequipped == 0 then return end

    if test then
        ISWorldObjectContextMenu.setTest()
        return true
    end

    local parent = context:addOption(getText("ContextMenu_BQoL_Wash"), worldobjects, nil)
    local submenu = ISContextMenu:getNew(context)
    context:addSubMenu(parent, submenu)

    local soapList = playerObj:getInventory():getSoapList(nil, true)

    if #equipped > 0 then
        addWashOption(submenu, worldobjects, "ContextMenu_BQoL_WashEquipped",
            playerObj, sink, soapList, equipped)
    end
    if #unequipped > 0 then
        addWashOption(submenu, worldobjects, "ContextMenu_BQoL_WashUnequipped",
            playerObj, sink, soapList, unequipped)
    end
end

BQoL.feature{
    id = "Wash",
    sandbox = "WashEnabled",
    init = function()
        Events.OnFillWorldObjectContextMenu.Add(onFillWorldObjectContextMenu)
    end,
}
