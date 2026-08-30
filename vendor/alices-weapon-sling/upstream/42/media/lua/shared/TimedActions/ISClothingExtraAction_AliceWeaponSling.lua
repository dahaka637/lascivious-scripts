if getActivatedMods():contains("\\nattachments") then return end
if not ISClothingExtraAction or ISClothingExtraAction.AliceWeaponSling then return end

ISClothingExtraAction.AliceWeaponSling = true

local vanillaComplete = ISClothingExtraAction.complete
local repairQueue = {}
local repairTickInstalled = false

local slingSlotByFullType = {
    AliceWeaponSling = "AliceSling",
    AliceWeaponSlingAlt = "AliceSlingAlt",
    AliceWeaponSlingAlt2 = "AliceSlingAlt2",
    AliceWeaponSlingBack = "AliceSlingBack",

    AliceWeaponSling_Hidden = "AliceSling",
    AliceWeaponSlingAlt_Hidden = "AliceSlingAlt",
    AliceWeaponSlingAlt2_Hidden = "AliceSlingAlt2",
    AliceWeaponSlingBack_Hidden = "AliceSlingBack",

    ["Base.AliceWeaponSling"] = "AliceSling",
    ["Base.AliceWeaponSlingAlt"] = "AliceSlingAlt",
    ["Base.AliceWeaponSlingAlt2"] = "AliceSlingAlt2",
    ["Base.AliceWeaponSlingBack"] = "AliceSlingBack",

    ["Base.AliceWeaponSling_Hidden"] = "AliceSling",
    ["Base.AliceWeaponSlingAlt_Hidden"] = "AliceSlingAlt",
    ["Base.AliceWeaponSlingAlt2_Hidden"] = "AliceSlingAlt2",
    ["Base.AliceWeaponSlingBack_Hidden"] = "AliceSlingBack",
}

local slingGroupBySlotType = {
    AliceSling = "front",
    AliceSlingAlt = "front",
    AliceSlingAlt2 = "front",
    AliceSlingBack = "back",
}

local function getFullType(item)
    if item and item.getFullType then
        return item:getFullType()
    end
    return nil
end

local function getSlingSlotType(itemOrType)
    if type(itemOrType) == "string" then
        return slingSlotByFullType[itemOrType]
    end
    return slingSlotByFullType[getFullType(itemOrType)]
end

local function isAliceSlingItem(item)
    return getSlingSlotType(item) ~= nil
end

local function getSlotDef(slotType)
    if not ISHotbarAttachDefinition or not slotType then return nil end

    for _, def in ipairs(ISHotbarAttachDefinition) do
        if def and def.type == slotType then
            return def
        end
    end

    return nil
end

local function getCurrentSlotIndex(hotbar, slotType)
    if not hotbar or not slotType then return nil end

    if hotbar.getThisSlotIndex then
        local slotIndex = hotbar:getThisSlotIndex(slotType)
        if slotIndex then return slotIndex end
    end

    if hotbar.availableSlot then
        for slotIndex, slot in pairs(hotbar.availableSlot) do
            if slot and slot.slotType == slotType then
                return slotIndex
            end
        end
    end

    return nil
end

local function getSlingAttachmentKey(item)
    if not item or not item.getAttachmentType then return nil end

    local attachmentType = item:getAttachmentType()
    if not attachmentType then return nil end

    return attachmentType .. "AliceSling"
end

local function resolveReplacementSlot(hotbar, item, model)
    if not hotbar or not hotbar.replacements or not model then return model end
    if tostring(model):find(" Back", 1, true) == nil then return model end

    local attachmentKey = getSlingAttachmentKey(item)
    if attachmentKey and hotbar.replacements[attachmentKey] then
        return hotbar.replacements[attachmentKey]
    end

    return model
end

local function findAttachedWeapon(hotbar, slotType)
    if not hotbar or not hotbar.attachedItems or not slotType then return nil end

    for slotIndex, item in pairs(hotbar.attachedItems) do
        if item and item.getAttachedSlotType and item:getAttachedSlotType() == slotType then
            return {
                item = item,
                slotIndex = slotIndex,
                slotType = slotType,
            }
        end
    end

    return nil
end

local function findWornAliceSlingInGroup(character, group, exceptItem)
    if not character or not group or not character.getWornItems then return nil end

    local wornItems = character:getWornItems()
    if not wornItems then return nil end

    for i = 0, wornItems:size() - 1 do
        local item = wornItems:getItemByIndex(i)
        if item and item ~= exceptItem and isAliceSlingItem(item) then
            local slotType = getSlingSlotType(item)
            if slingGroupBySlotType[slotType] == group then
                return item
            end
        end
    end

    return nil
end

local function itemInHands(character, item)
    if not character or not item then return false end
    return character:getPrimaryHandItem() == item or character:getSecondaryHandItem() == item
end

local function preserveHotbarSlot(data, model)
    if not data or not data.hotbar or not data.item or not model then return end

    local slotIndex = getCurrentSlotIndex(data.hotbar, data.newSlotType) or data.slotIndex
    if not slotIndex then return end

    item:setAttachedSlot(slotIndex)
    item:setAttachedSlotType(slotType)
    item:setAttachedToModel(model)

    data.hotbar.attachedItems = data.hotbar.attachedItems or {}
    data.hotbar.attachedItems[slotIndex] = data.item

    if ISInventoryPage then
        ISInventoryPage.renderDirty = true
    end
end

local function detachAttachedWeapon(data)
    if not data or not data.hotbar or not data.item then return end

    if data.hotbar.removeItem then
        data.hotbar:removeItem(data.item, false)
    else
        if data.character then
            data.character:removeAttachedItem(data.item)
        end

        data.item:setAttachedSlot(-1)
        data.item:setAttachedSlotType(nil)
        data.item:setAttachedToModel(nil)

        if data.hotbar.attachedItems then
            data.hotbar.attachedItems[data.slotIndex] = nil
        end
    end
end

local function snapshotAction(action)
    if not action or not action.character or isServer() then return nil end
    if not isAliceSlingItem(action.item) then return nil end

    if not action.character.isEquippedClothing or not action.character:isEquippedClothing(action.item) then
        return nil
    end

    local oldSlotType = getSlingSlotType(action.item)
    local newSlotType = getSlingSlotType(action.extra)
    if not oldSlotType or not newSlotType then return nil end

    local hotbar = getPlayerHotbar(action.character:getPlayerNum())
    if not hotbar then return nil end

    local oldGroup = slingGroupBySlotType[oldSlotType]
    local newGroup = slingGroupBySlotType[newSlotType]

    local snapshot = {
        hotbar = hotbar,
        character = action.character,
        attached = findAttachedWeapon(hotbar, oldSlotType),
        displaced = nil,
    }

    if snapshot.attached then
        snapshot.attached.hotbar = hotbar
        snapshot.attached.character = action.character
        snapshot.attached.newSlotType = newSlotType
    end

    if oldGroup and newGroup and oldGroup ~= newGroup then
        local displacedSling = findWornAliceSlingInGroup(action.character, newGroup, action.item)
        if displacedSling then
            snapshot.displaced = findAttachedWeapon(hotbar, newSlotType)
            if snapshot.displaced then
                snapshot.displaced.hotbar = hotbar
                snapshot.displaced.character = action.character
            end
        end
    end

    return snapshot
end

local function restoreAttachedWeapon(data)
    if not data or not data.hotbar or not data.character or not data.item or not data.newSlotType then return end

    local slotDef = getSlotDef(data.newSlotType)
    if not slotDef or not slotDef.attachments or not data.item.getAttachmentType then return end

    local slotIndex = getCurrentSlotIndex(data.hotbar, data.newSlotType)
    if not slotIndex then return end

    local model = slotDef.attachments[data.item:getAttachmentType()]
    model = resolveReplacementSlot(data.hotbar, data.item, model)
    if not model or model == "null" then return end

    local existing = data.hotbar.attachedItems and data.hotbar.attachedItems[slotIndex]
    if existing and existing ~= data.item then
        detachAttachedWeapon({
            hotbar = data.hotbar,
            character = data.character,
            item = existing,
            slotIndex = slotIndex,
            slotType = data.newSlotType,
        })
    end

    data.slotIndex = slotIndex

    if itemInHands(data.character, data.item) then
        preserveHotbarSlot(data, model)
        return
    end

    data.character:removeAttachedItem(data.item)

    if AliceWeaponSling and AliceWeaponSling.repairHotbarItem then
        AliceWeaponSling.repairHotbarItem(data.hotbar, data.item, slotIndex, data.newSlotType, model)
    else
        data.character:setAttachedItem(model, data.item)
        data.item:setAttachedSlot(slotIndex)
        data.item:setAttachedSlotType(data.newSlotType)
        data.item:setAttachedToModel(model)

        data.hotbar.attachedItems = data.hotbar.attachedItems or {}
        data.hotbar.attachedItems[slotIndex] = data.item

        if ISInventoryPage then
            ISInventoryPage.renderDirty = true
        end
    end

    if data.hotbar.reloadIcons then
        data.hotbar:reloadIcons()
    end
end

local function onRepairTick()
    for index = #repairQueue, 1, -1 do
        local data = repairQueue[index]
        data.ticks = data.ticks - 1

        if data.ticks <= 0 then
            if data.displaced and (not data.attached or data.displaced.item ~= data.attached.item) then
                detachAttachedWeapon(data.displaced)
            end
            restoreAttachedWeapon(data.attached)
            table.remove(repairQueue, index)
        end
    end

    if #repairQueue == 0 then
        Events.OnTick.Remove(onRepairTick)
        repairTickInstalled = false
    end
end

local function scheduleRestoreWindow(snapshot)
    if not snapshot or not Events or not Events.OnTick then return end

    local delays = { 1, 2, 5, 10, 15, 30 }

    for _, delay in ipairs(delays) do
        table.insert(repairQueue, {
            ticks = delay,
            attached = snapshot.attached,
            displaced = snapshot.displaced,
        })
    end

    if not repairTickInstalled then
        Events.OnTick.Add(onRepairTick)
        repairTickInstalled = true
    end
end

function ISClothingExtraAction:complete()
    local snapshot = snapshotAction(self)
    local result = vanillaComplete(self)

    if snapshot then
        if snapshot.displaced and (not snapshot.attached or snapshot.displaced.item ~= snapshot.attached.item) then
            detachAttachedWeapon(snapshot.displaced)
        end
        restoreAttachedWeapon(snapshot.attached)
        scheduleRestoreWindow(snapshot)
    end

    return result
end