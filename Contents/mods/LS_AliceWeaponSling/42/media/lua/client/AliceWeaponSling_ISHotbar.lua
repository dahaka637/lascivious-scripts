if getActivatedMods():contains("\\nattachments") then return end

local activatedMods = getActivatedMods()
local HAS_SWAPIT = activatedMods and activatedMods:contains("SwapIt")

local function isSwapItActive()
    return HAS_SWAPIT
end

AliceWeaponSling = AliceWeaponSling or {}

local function slotUsesSling(slot)
    return slot ~= nil and tostring(slot):find("AliceSling", 1, true) ~= nil
end

local function slotIsBack(slot)
    return slot ~= nil and tostring(slot):find(" Back", 1, true) ~= nil
end

local function slingAttachmentType(attachmentType, slot)
    if not attachmentType then return nil end
    if slotUsesSling(slot) then
        return attachmentType .. "AliceSling"
    end
    return attachmentType
end

local function safeSyncItem(character, item)
    if syncItemFields then
        pcall(syncItemFields, character, item)
    end
end

local function itemInHands(character, item)
    if not character or not item then return false end
    return character:getPrimaryHandItem() == item or character:getSecondaryHandItem() == item
end

local aliceSlingModels = {
    "AliceSlingRifle",
    "AliceSlingRifle2",
    "AliceSlingRifle3",
    "AliceSlingRifle Back",
    "AliceSlingRifleBag",

    "AliceSlingWeapon",
    "AliceSlingWeapon2",
    "AliceSlingWeapon3",
    "AliceSlingWeapon Back",
    "AliceSlingWeaponBag",
    "AliceSlingBladeBag",

    "AliceSlingShovel",
    "AliceSlingShovel2",
    "AliceSlingShovel3",
    "AliceSlingShovel Back",
    "AliceSlingShovelBag",
}

local aliceSlingSlotTypes = {
    AliceSling = true,
    AliceSlingAlt = true,
    AliceSlingAlt2 = true,
    AliceSlingBack = true,
}

local function isAliceSlingSlotType(slotType)
    return slotType ~= nil and aliceSlingSlotTypes[tostring(slotType)] == true
end

local function queueSwapItAttachment(hotbar, item, slotIndex, slotDef, model)
    if not hotbar or not hotbar.chr or not item or not slotIndex or not slotDef or not model then
        return false
    end

    hotbar.AliceWeaponSling_PendingSwapItAttach = {
        item = item,
        slotIndex = slotIndex,
        slotType = slotDef.type,
        model = model,
        equipItem = hotbar.AliceWeaponSling_LastSwapItRemovedItem,
    }

    hotbar.AliceWeaponSling_LastSwapItRemovedItem = nil
    return true
end

local function clearStaleAliceSlingVisuals(character, item, keepModel)
    if not character or not item then return end

    pcall(function()
        character:removeAttachedItem(item)
    end)

    for _, model in ipairs(aliceSlingModels) do
        if model ~= keepModel then
            pcall(function()
                if character:getAttachedItem(model) == item then
                    character:setAttachedItem(model, nil)
                end
            end)
        end
    end
end

local function queueTransferToMainInventory(character, item)
    if not character or not item or not item.getContainer then return false end

    local fromContainer = item:getContainer()
    local toContainer = character:getInventory()

    if not fromContainer or not toContainer or fromContainer == toContainer then
        return false
    end

    if ISTimedActionQueue and ISInventoryTransferAction then
        ISTimedActionQueue.add(ISInventoryTransferAction:new(character, item, fromContainer, toContainer))
        return true
    end

    if ISInventoryPaneContextMenu and ISInventoryPaneContextMenu.transferIfNeeded then
        ISInventoryPaneContextMenu.transferIfNeeded(character, item)
        return true
    end

    return false
end

local function resolveReplacementSlot(hotbar, item, slot)
    local attachmentType = nil
    if item and item.getAttachmentType then
        attachmentType = slingAttachmentType(item:getAttachmentType(), slot)
    end

    if hotbar and hotbar.replacements and attachmentType and hotbar.replacements[attachmentType] and slotIsBack(slot) then
        return hotbar.replacements[attachmentType]
    end

    return slot
end

local function setHotbarAttachment(hotbar, item, slotIndex, slotType, model, allowInHands)
    if not hotbar or not hotbar.chr or not item or not slotIndex or not slotType or not model then return false end
    if not allowInHands and itemInHands(hotbar.chr, item) then return false end

    clearStaleAliceSlingVisuals(hotbar.chr, item, model)

    pcall(function()
        hotbar.chr:setAttachedItem(model, item)
    end)

    item:setAttachedSlot(slotIndex)
    item:setAttachedSlotType(slotType)
    item:setAttachedToModel(model)

    hotbar.attachedItems = hotbar.attachedItems or {}
    hotbar.attachedItems[slotIndex] = item

    if ISInventoryPage then
        ISInventoryPage.renderDirty = true
    end

    safeSyncItem(hotbar.chr, item)
    return true
end

function AliceWeaponSling.repairHotbarItem(hotbar, item, slotIndex, slotType, model)
    return setHotbarAttachment(hotbar, item, slotIndex, slotType, model)
end

local function snapshotHotbar(hotbar)
    local snapshot = {}
    if not hotbar or not hotbar.attachedItems then return snapshot end

    for slotIndex, item in pairs(hotbar.attachedItems) do
        if item and item.getAttachedSlot and item.getAttachedSlotType and item.getAttachedToModel then
            local itemSlotIndex = item:getAttachedSlot()
            local slotType = item:getAttachedSlotType()
            local model = item:getAttachedToModel()

            if itemSlotIndex and itemSlotIndex > 0 and slotType and model and isAliceSlingSlotType(slotType) then
                table.insert(snapshot, {
                    item = item,
                    slotIndex = itemSlotIndex,
                    slotType = slotType,
                    model = model,
                })
            elseif slotIndex and slotIndex > 0 and slotType and model and isAliceSlingSlotType(slotType) then
                table.insert(snapshot, {
                    item = item,
                    slotIndex = slotIndex,
                    slotType = slotType,
                    model = model,
                })
            end
        end
    end

    return snapshot
end

local function restoreHotbarSnapshot(hotbar, snapshot)
    if not hotbar or not snapshot then return end

    for _, data in ipairs(snapshot) do
        local item = data.item
        if item then
            local currentSlot = nil
            local currentType = nil
            local currentModel = nil

            local currentSlot = item:getAttachedSlot()
            local currentType = item:getAttachedSlotType()
            local currentModel = item:getAttachedToModel()

            if currentSlot ~= data.slotIndex or currentType ~= data.slotType or currentModel ~= data.model or hotbar.attachedItems[data.slotIndex] ~= item then
                setHotbarAttachment(hotbar, item, data.slotIndex, data.slotType, data.model)
            end
        end
    end
end

if ISHotbar and not ISHotbar.AliceWeaponSling_ReloadPreserve then
    ISHotbar.AliceWeaponSling_ReloadPreserve = true

    local vanillaReloadIcons = ISHotbar.reloadIcons

    function ISHotbar:reloadIcons(...)
        if not vanillaReloadIcons then return end

        if self.AliceWeaponSling_InReload or self.AliceWeaponSling_SuppressReloadRestore then
            return vanillaReloadIcons(self, ...)
        end

        local snapshot = snapshotHotbar(self)
        self.AliceWeaponSling_InReload = true

        local ok, result = pcall(vanillaReloadIcons, self, ...)

        self.AliceWeaponSling_InReload = false
        restoreHotbarSnapshot(self, snapshot)

        if not ok then
            error(result)
        end

        return result
    end
end

if ISHotbar and not ISHotbar.AliceWeaponSling_RemoveItemSuppress then
    ISHotbar.AliceWeaponSling_RemoveItemSuppress = true

    local vanillaRemoveItem = ISHotbar.removeItem

    function ISHotbar:removeItem(item, doAnim, ...)
        if doAnim == false then
            if isSwapItActive() then
                self.AliceWeaponSling_LastSwapItRemovedItem = item
            end

            self.AliceWeaponSling_SuppressReloadRestore = true

            local ok, result = pcall(vanillaRemoveItem, self, item, doAnim, ...)

            self.AliceWeaponSling_SuppressReloadRestore = false

            if not ok then
                error(result)
            end

            return result
        end

        return vanillaRemoveItem(self, item, doAnim, ...)
    end
end

function ISHotbar:attachItem(item, slot, slotIndex, slotDef, doAnim)
    local finalSlot = resolveReplacementSlot(self, item, slot)

    if doAnim then
        if finalSlot == "null" then
            self:removeItem(item, false)
            return
        end

        if isSwapItActive()
                and self.AliceWeaponSling_LastSwapItRemovedItem
                and itemInHands(self.chr, item)
                and not (self.attachedItems and self.attachedItems[slotIndex]) then
            queueSwapItAttachment(self, item, slotIndex, slotDef, finalSlot)
            return
        end

        self:setAttachAnim(item, slotDef)
        queueTransferToMainInventory(self.chr, item)

        self.AliceWeaponSling_LastSwapItRemovedItem = nil

        if self.attachedItems and self.attachedItems[slotIndex] then
            ISTimedActionQueue.add(ISDetachItemHotbar:new(self.chr, self.attachedItems[slotIndex]))
        end

        ISTimedActionQueue.add(ISAttachItemHotbar:new(self.chr, item, finalSlot, slotIndex, slotDef))
        return
    end

    if finalSlot == "null" then
        self:removeItem(item, false)
        return
    end

    clearStaleAliceSlingVisuals(self.chr, item, finalSlot)

    self.chr:setAttachedItem(finalSlot, item)
    item:setAttachedSlot(slotIndex)
    item:setAttachedSlotType(slotDef and slotDef.type or nil)
    item:setAttachedToModel(finalSlot)

    self.attachedItems = self.attachedItems or {}
    self.attachedItems[slotIndex] = item
    
    if AliceWeaponSling.refreshWeightReductionPart then
        AliceWeaponSling.refreshWeightReductionPart(self.chr, item)
    end

    if not self.AliceWeaponSling_InReload then
        self:reloadIcons()
    elseif ISInventoryPage then
        ISInventoryPage.renderDirty = true
    end
end

local function commitPendingSwapItAttachment(character, equippedItem)
    if not character then return end

    local hotbar = getPlayerHotbar(character:getPlayerNum())
    local pending = hotbar and hotbar.AliceWeaponSling_PendingSwapItAttach or nil
    if not pending then return end

    if pending.equipItem and pending.equipItem ~= equippedItem then
        return
    end

    hotbar.AliceWeaponSling_PendingSwapItAttach = nil

    local attached = setHotbarAttachment(
        hotbar,
        pending.item,
        pending.slotIndex,
        pending.slotType,
        pending.model,
        false
    )

    if attached and AliceWeaponSling.refreshWeightReductionPart then
        AliceWeaponSling.refreshWeightReductionPart(character, pending.item)
    end

    if attached and hotbar.reloadIcons then
        hotbar:reloadIcons()
    end
end

local function clearPendingSwapItAttachment(character, equippedItem)
    if not character then return end

    local hotbar = getPlayerHotbar(character:getPlayerNum())
    local pending = hotbar and hotbar.AliceWeaponSling_PendingSwapItAttach or nil
    if not pending then return end

    if not pending.equipItem or pending.equipItem == equippedItem then
        hotbar.AliceWeaponSling_PendingSwapItAttach = nil
    end
end

if ISEquipWeaponAction and not ISEquipWeaponAction.AliceWeaponSling_SwapItPendingAttach then
    ISEquipWeaponAction.AliceWeaponSling_SwapItPendingAttach = true

    local vanillaComplete = ISEquipWeaponAction.complete
    local vanillaStop = ISEquipWeaponAction.stop

    function ISEquipWeaponAction:complete(...)
        local result = vanillaComplete(self, ...)

        if result ~= false then
            commitPendingSwapItAttachment(self.character, self.item)
        else
            clearPendingSwapItAttachment(self.character, self.item)
        end

        return result
    end

    function ISEquipWeaponAction:stop(...)
        clearPendingSwapItAttachment(self.character, self.item)
        return vanillaStop(self, ...)
    end
end