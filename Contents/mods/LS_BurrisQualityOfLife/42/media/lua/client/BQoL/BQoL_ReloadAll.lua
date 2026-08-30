--[[
    Burris Quality of Life -- reload every selected magazine in one click.

    Vanilla only offers "Insert Bullets" per single magazine. Most of the setup
    work is left to it: ISInventoryPaneContextMenu.transferIfNeeded already
    pulls the magazine and the bullets out of any bags, so magazines in a
    backpack and ammunition in another one just work. Ammo is pooled from the
    player's own inventory plus every container currently open in the loot
    window (ISInventoryPaneContextMenu.getContainers), not just what's already
    on the player, so a chest rig, a bandolier, or a nearby crate all count.

    Since every move above goes through transferIfNeeded, which always queues
    a real ISInventoryTransferAction rather than moving items instantly, Tidy
    Up Meister (if installed) sees these transfers through its own
    ISTimedActionQueue.add hook and restores items to their original
    containers on its own -- no BQoL-side integration needed.

    Vanilla's own ISLoadBulletsInMagazine, though, does NOT actually respect
    the ammoCount it's constructed with -- see BQoL_LoadBulletsCapped in
    shared/TimedActions/, the subclass this queues, which adds the missing cap
    so a shared ammo pool gets split as computed.
]]

require "BQoL/BQoL_Core"
require "TimedActions/BQoL_LoadBulletsCapped"

-- The same magazine test vanilla's own reload menu uses
-- (ISInventoryPaneContextMenu.lua:1820).
local function isLoadableMagazine(item)
    return item:getAmmoType() ~= nil
        and not instanceof(item, "HandWeapon")
        and item:getCurrentAmmoCount() < item:getMaxAmmo()
end

--[[
    The event's `items` argument mixes InventoryItem entries with
    { items = {...} } stacks and duplicates the clicked item
    (ISInventoryPaneContextMenu.lua:940's own comment says so). Normalise to a
    deduplicated list of loadable magazines.
]]
local function collectMagazines(items)
    local magazines, seen = {}, {}

    local function consider(item)
        if item and not seen[item] and isLoadableMagazine(item) then
            seen[item] = true
            table.insert(magazines, item)
        end
    end

    for _, entry in ipairs(items) do
        if type(entry) == "table" and entry.items then
            for _, item in ipairs(entry.items) do
                consider(item)
            end
        else
            consider(entry)
        end
    end

    return magazines
end

--[[
    ISInventoryPaneContextMenu.getContainers (:2424) lists every container tab
    shown in the player's own inventory window plus every tab shown in the
    currently open loot window (skipping ones locked to the character) --
    vanilla's own scope for multi-container actions like crafting. It returns
    an ArrayList, not a Lua table, hence the size()/get() walk rather than
    ipairs below. BQoL.safe guards the call itself: getContainers reaches into
    getPlayerLoot(n).inventoryPane.inventoryPage.backpacks, and if any link in
    that chain is nil this degrades to pooling from the player's own inventory
    only, rather than losing the whole feature the way an unguarded crash did.

    Its first loop already includes the player's base inventory and everything
    worn/carried on the player, which inventory:getItemCountRecurse below
    already walks, so drop anything reachable from the player's own inventory
    tree to avoid double-counting. Same containingItem/containsRecursive
    reachability check Tidy Up Meister uses in its own destinationIsAvailable.

    That same check is also applied BETWEEN candidates, not just against the
    player: a bag sitting in a vehicle seat or trunk gets its own loot-window
    tab (ISInventoryPage:refreshBackpacks, the item:getCategory() == "Container"
    branches) while its contents are also walked by the seat/trunk container's
    own getItemCountRecurse. Counting both would inflate the pool and loosen
    the very per-magazine cap BQoL_LoadBulletsCapped exists to enforce.
    Nesting is a tree, so "drop a container whose containing item lives inside
    another candidate" is enough: bag-in-bag-in-trunk collapses to just the
    trunk, and the trunk itself has no containing item, so it survives.
]]
local function collectExternalContainers(playerObj, inventory)
    local ok, containerList =
        BQoL.safe("ReloadAll: getContainers",
                  ISInventoryPaneContextMenu.getContainers, playerObj)
    if not ok or not containerList then return {} end

    local candidates, seen = {}, {}
    for i = 0, containerList:size() - 1 do
        local container = containerList:get(i)
        if container and container ~= inventory and not seen[container] then
            seen[container] = true
            table.insert(candidates, container)
        end
    end

    local externalContainers = {}
    for _, container in ipairs(candidates) do
        local containingItem = container:getContainingItem()
        local counted = containingItem ~= nil
            and inventory:containsRecursive(containingItem)

        if containingItem and not counted then
            for _, other in ipairs(candidates) do
                if other ~= container and other:containsRecursive(containingItem) then
                    counted = true
                    break
                end
            end
        end

        if not counted then
            table.insert(externalContainers, container)
        end
    end

    return externalContainers
end

local function onReloadAllSelected(playerObj, magazines)
    local inventory = playerObj:getInventory()
    local externalContainers = collectExternalContainers(playerObj, inventory)
    local ammoPool = {}

    for _, magazine in ipairs(magazines) do
        local itemKey = magazine:getAmmoType():getItemKey()

        if ammoPool[itemKey] == nil then
            local total = inventory:getItemCountRecurse(itemKey)
            for _, container in ipairs(externalContainers) do
                total = total + container:getItemCountRecurse(itemKey)
            end
            ammoPool[itemKey] = total
        end

        local needed = magazine:getMaxAmmo() - magazine:getCurrentAmmoCount()
        local count = math.min(ammoPool[itemKey], needed)

        if count > 0 then
            ammoPool[itemKey] = ammoPool[itemKey] - count

            --[[
                Same setup as ISInventoryPaneContextMenu.onLoadBulletsInMagazine
                (:1993), but queues our capped subclass so this magazine can't
                eat bullets earmarked for the next one in the loop.

                Inside the count > 0 branch rather than hoisted above it: every
                transferIfNeeded queues a real ISInventoryTransferAction rather
                than moving anything instantly, so pulling in all the selected
                magazines up front sent the character off to fetch ones the
                loop had already decided to skip. Ten empty magazines and
                fifteen rounds is one reload and nine pointless transfers, with
                the nine left sitting in the main inventory afterwards.
            ]]
            ISInventoryPaneContextMenu.transferIfNeeded(playerObj, magazine)

            -- The ammo comes from wherever it physically is: the player's own
            -- inventory first, then the external containers, through
            -- getSomeTypeRecurse's append form.
            local ammoItems = ArrayList.new()
            inventory:getSomeTypeRecurse(itemKey, count, ammoItems)
            for _, container in ipairs(externalContainers) do
                if ammoItems:size() >= count then break end
                container:getSomeTypeRecurse(itemKey, count - ammoItems:size(), ammoItems)
            end

            ISInventoryPaneContextMenu.transferIfNeeded(playerObj, ammoItems)
            ISTimedActionQueue.add(BQoL_LoadBulletsCapped:new(playerObj, magazine, count))
        end
    end
end

local function onFillInventoryObjectContextMenu(playerNum, context, items)
    local playerObj = getSpecificPlayer(playerNum)
    if not playerObj then return end

    local magazines = collectMagazines(items)
    -- One magazine is already covered by vanilla's own option.
    if #magazines < 2 then return end

    -- Vanilla's own reload entries ("Insert Bullets in Magazine (N)", "Insert
    -- Magazine", "Unload Magazine") carry a dynamic count/weapon name in the
    -- label, so there's no fixed string to anchor after. Top of the menu at
    -- least keeps it out of the unrelated clutter further down.
    context:addOptionOnTop(getText("ContextMenu_BQoL_ReloadAllMagazines"),
        playerObj, onReloadAllSelected, magazines)
end

BQoL.feature{
    id = "ReloadAllMagazines",
    sandbox = "ReloadAllMagazinesEnabled",
    init = function()
        Events.OnFillInventoryObjectContextMenu.Add(onFillInventoryObjectContextMenu)
    end,
}
