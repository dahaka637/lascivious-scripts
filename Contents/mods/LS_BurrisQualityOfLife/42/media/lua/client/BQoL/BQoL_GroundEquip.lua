--[[
    Burris Quality of Life -- equip weapons, clothing and bags off the ground.

    Vanilla only offers Grab / Grab one / Grab half / Grab all on a ground item,
    all of which drop it into your inventory unequipped. There is no equip or
    wear option on the world menu at all -- ContextMenu_Equip_Primary and
    ContextMenu_Wear are added only from ISInventoryPaneContextMenu.

    This chains walk -> pick up -> equip into one click.
]]

require "BQoL/BQoL_Core"
require "TimedActions/ISInventoryTransferUtil"

--[[
    Queues the pickup.

    The client/singleplayer split is not optional -- it is exactly what vanilla's
    own ISWorldObjectContextMenu.onGrabWItem does (ISWorldObjectContextMenu.lua:1449).
    ISGrabItemAction manipulates the world object directly, which a multiplayer
    client may not do, so clients go through the transfer utility instead.
]]
local function queuePickup(playerObj, witem)
    if isClient() then
        local item = witem:getItem()
        ISTimedActionQueue.add(ISInventoryTransferUtil.newInventoryTransferAction(
            playerObj, item, item:getContainer(), playerObj:getInventory()))
    else
        local time = ISWorldObjectContextMenu.grabItemTime(playerObj, witem)
        ISTimedActionQueue.add(ISGrabItemAction:new(playerObj, witem, time))
    end
end

local function onEquipSelected(worldobjects, playerObj, witem)
    local square = witem:getSquare()
    if not square then return end

    -- The item may have been taken since the menu was built.
    local item = witem:getItem()
    if not item then return end

    if not luautils.walkAdj(playerObj, square) then return end

    queuePickup(playerObj, witem)

    if item:IsWeapon() then
        ISTimedActionQueue.add(ISEquipWeaponAction:new(
            playerObj, item, 50, true, item:isTwoHandWeapon()))
    else
        -- Clothing and bags both go through ISWearClothing, which takes
        -- exactly two arguments (ISWearClothing.lua:164) -- vanilla passes a
        -- third in one place and it is silently ignored.
        ISTimedActionQueue.add(ISWearClothing:new(playerObj, item))
    end
end

--- True for things worth offering an equip shortcut for.
local function isEquippable(item)
    if not item then return false end
    return item:IsWeapon() or item:IsClothing() or item:IsInventoryContainer()
end

--[[
    Collects equippable items lying on nearby squares.

    Note `worldobjects` is the fetched object set (tiles, walls, furniture), not
    ground items -- ground items come from square:getWorldObjects(), which
    returns IsoWorldInventoryObject wrappers.
]]
local function findGroundItems(worldobjects)
    local found, seen = {}, {}

    for _, square in ipairs(BQoL.gatherSquares(worldobjects)) do
        local objects = square:getWorldObjects()

        if objects then
            for i = 0, objects:size() - 1 do
                local witem = objects:get(i)
                local item = witem and witem:getItem()

                if item and not seen[item] and isEquippable(item) then
                    seen[item] = true
                    table.insert(found, { witem = witem, item = item })
                end
            end
        end
    end

    return found
end

local function onFillWorldObjectContextMenu(playerNum, context, worldobjects, test)
    if test and ISWorldObjectContextMenu.Test then return true end

    local playerObj = getSpecificPlayer(playerNum)
    if not playerObj or playerObj:getVehicle() then return end

    local items = findGroundItems(worldobjects)
    if #items == 0 then return end

    if test then
        ISWorldObjectContextMenu.setTest()
        return true
    end

    local parent = context:addOption(getText("ContextMenu_BQoL_Equip"), worldobjects, nil)
    local submenu = ISContextMenu:getNew(context)
    context:addSubMenu(parent, submenu)

    for _, entry in ipairs(items) do
        submenu:addOption(
            entry.item:getName(), worldobjects, onEquipSelected,
            playerObj, entry.witem)
    end
end

BQoL.feature{
    id = "GroundEquip",
    sandbox = "EquipFromGroundEnabled",
    init = function()
        Events.OnFillWorldObjectContextMenu.Add(onFillWorldObjectContextMenu)
    end,
}
