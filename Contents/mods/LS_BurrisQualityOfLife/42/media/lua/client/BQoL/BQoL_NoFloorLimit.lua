--[[
    Burris Quality of Life -- removes the vanilla 50-weight ground limit.

    Two separate mechanisms enforce the limit in 42.20 (verified by
    disassembling ItemContainer):

      1. Direct floor drops are gated in pure Lua:
         ISInventoryTransferAction:floorHasRoomFor() compares the square's
         total weight against the floor proxy container's capacity (default
         50). Both are reachable from Lua.

      2. Bags lying on the ground are gated by a hardcoded 50.0 constant
         inside Java ItemContainer.hasRoomFor(character, F, F): when the
         destination has a world item, floorTotal + addedWeight > 50 fails.
         That constant cannot be changed from Lua, so the Java call is
         replaced at each Lua call site with a mirror that drops ONLY the
         floor term. The mirror keeps the checks the same disassembly shows
         around it: MaxItemSize and real bag capacity
         (getCapacityWeight + weight <= getEffectiveCapacity). isItemAllowed
         is enforced separately by every caller's own code path.

    Caveats: everything here is client-side, so a multiplayer server may
    still refuse some over-50 transfers; and the Ground button's capacity
    label reads x / 100, the most the Java clamp in getCapacity() allows.
]]

require "BQoL/BQoL_Core"

--[[
    Floor-free mirror of Java hasRoomFor for bags lying on the ground.
    `totalWeight` is the accumulated weight being added (a single item's
    weight at action time, the running drag total at UI time), matching how
    Java applies its own MaxItemSize and capacity comparisons.
]]
local function groundBagHasRoom(character, container, totalWeight)
    local bag = container:getContainingItem()
    if bag and instanceof(bag, "InventoryContainer") then
        local maxItemSize = bag:getMaxItemSize()
        if maxItemSize > 0 and totalWeight > maxItemSize then
            return false
        end
    end

    local current = ItemContainer.floatingPointCorrection(container:getCapacityWeight())
    return current + totalWeight <= container:getEffectiveCapacity(character)
end

--- True when the container is a bag (or any item container) lying on a square.
local function isGroundContainer(container)
    return container
        and container.getType and container:getType() ~= "floor"
        and container.hasWorldItem and container:hasWorldItem()
end

local function install()
    -- (1) Direct floor drops: the action-time gate simply disappears.
    -- canDropOnFloor (walls, stairs, solidity) is a separate method and is
    -- not touched.
    ISInventoryTransferAction.floorHasRoomFor = function(self, square, item)
        return true
    end

    -- (2) The loot window's floor proxy: 100 is the most the Java clamp in
    -- getCapacity() allows for an item-less container, and setCapacity only
    -- warns above that. Covers the button label and any unpatched read.
    local originalGetFloorContainer = ISInventoryPage.GetFloorContainer
    function ISInventoryPage.GetFloorContainer(playerNum)
        local container = originalGetFloorContainer(playerNum)
        if container:getCapacity() < 100 then
            container:setCapacity(100)
        end
        return container
    end

    -- (3) Action-time for bags on the ground. The fallback replicates every
    -- other guard in vanilla isValid (42.20), so the only check lifted is the
    -- 50.0 floor rule inside Java hasRoomFor.
    local originalIsValid = ISInventoryTransferAction.isValid
    function ISInventoryTransferAction:isValid()
        if originalIsValid(self) then return true end

        local dest, src, item = self.destContainer, self.srcContainer, self.item
        if not isGroundContainer(dest) then return false end
        if not src or not item then return false end

        -- The remaining vanilla guards the fallback must NOT lift
        -- (ISInventoryTransferAction.lua:32-86): crafting-consumed items
        -- vanish rather than transfer, mid-sync containers reject moves, and
        -- the corpse-pickup duplication exploit stays plugged.
        if item:getIsCraftingConsumed() then return false end
        if not dest:isExistYet() or not src:isExistYet() then return false end
        local parent = src:getParent()
        if instanceof(parent, "IsoDeadBody") and parent:getStaticMovingObjectIndex() == -1 then
            return false
        end

        if not src:contains(item) then return false end
        if src == dest then return false end
        if not dest:isItemAllowed(item) then return false end
        if not src:isRemoveItemAllowed(item) then return false end
        if item:getContainer() ~= src or dest:isInside(item) then return false end
        if isClient() and src:getSourceGrid()
            and SafeHouse.isSafeHouse(src:getSourceGrid(), self.character:getUsername(), true) then
            return false
        end

        return groundBagHasRoom(self.character, dest, item:getUnequippedWeight())
    end

    -- (4) Drag-and-drop UI: DraggedItems:update() marks items not-OK when the
    -- Java 50.0 rule fails. After the original runs, re-evaluate the rejected
    -- items with the mirror -- re-applying the cheap guards first, so items
    -- rejected for other reasons (favourite, wrong container, item rules)
    -- stay rejected. Vanilla sorts by type and weight and fails items
    -- progressively, so the running total is kept the same way.
    --
    -- Vanilla rebuilds itemNotOK only when the drop target actually changed
    -- (ISInventoryPane.lua:1365), so this rescan is skipped otherwise --
    -- without that it would repeat the same work on every frame of a drag.
    --
    -- The item count has to be part of the comparison: vanilla also forces a
    -- rebuild when the destination's contents change underneath the cursor
    -- (:1360 nils mouseOverContainer, then :1368 restores the same value), so
    -- comparing the container alone would miss that and leave items wrongly
    -- flagged.
    local originalUpdate = ISInventoryPaneDraggedItems.update
    function ISInventoryPaneDraggedItems:update()
        local previousContainer = self.mouseOverContainer
        local previousWhat = self.mouseOverWhat
        local previousCount = self.mouseOverItemCount

        originalUpdate(self)

        local container = self.mouseOverContainer
        if container == previousContainer
            and self.mouseOverWhat == previousWhat
            and self.mouseOverItemCount == previousCount then
            return
        end

        if not isGroundContainer(container) then return end

        local playerObj = getSpecificPlayer(self.playerNum)
        if not playerObj then return end

        local total = 0
        for _, item in ipairs(self.items or {}) do
            if not self.itemNotOK[item] then
                total = total + item:getUnequippedWeight()
            end
        end

        for _, item in ipairs(self.items or {}) do
            if self.itemNotOK[item]
                and not item:isFavorite()
                and item:getContainer() ~= container
                and not container:isInside(item)
                and container:isItemAllowed(item) then

                local candidate = total + item:getUnequippedWeight()
                if groundBagHasRoom(playerObj, container, candidate) then
                    self.itemNotOK[item] = nil
                    total = candidate
                end
            end
        end
    end

    -- (5) Right-click "Move to" availability.
    local originalHasRoomForAny = ISInventoryPaneContextMenu.hasRoomForAny
    ISInventoryPaneContextMenu.hasRoomForAny = function(playerObj, container, items)
        if originalHasRoomForAny(playerObj, container, items) then return true end

        if instanceof(container, "InventoryContainer") then
            container = container:getInventory()
        end
        if not isGroundContainer(container) then return false end

        local minWeight = math.huge
        for _, item in ipairs(items) do
            minWeight = math.min(minWeight, item:getUnequippedWeight())
        end
        if minWeight == math.huge then return false end

        return groundBagHasRoom(playerObj, container, minWeight)
    end
end

BQoL.feature{
    id = "NoFloorLimit",
    sandbox = "NoFloorLimitEnabled",
    init = install,
}
