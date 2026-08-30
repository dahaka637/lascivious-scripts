if getActivatedMods():contains("\\nattachments") then return end

AliceWeaponSling = AliceWeaponSling or {}

local BASE_ATTACH_TIME = 30

local function slotUsesSling(slot)
    return slot ~= nil and tostring(slot):find("AliceSling", 1, true) ~= nil
end

local function slotIsBack(slot)
    return slot ~= nil and tostring(slot):find(" Back", 1, true) ~= nil
end

local function slingAttachmentType(item, slot)
    if not item or not item.getAttachmentType then return nil end
    local attachmentType = item:getAttachmentType()
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

local function clearHands(character, item)
    if not character or not item then return end

    if character.removeFromHands then
        character:removeFromHands(item)
    end

    if character:getPrimaryHandItem() == item then
        character:setPrimaryHandItem(nil)
    end

    if character:getSecondaryHandItem() == item then
        character:setSecondaryHandItem(nil)
    end
end

local function anchorItemToMainInventory(character, item)
    if not character or not item or not item.getContainer then return end

    local mainInv = character:getInventory()
    if not mainInv then return end

    local oldContainer = item:getContainer()
    if oldContainer == mainInv then return end

    if oldContainer and oldContainer.Remove then
        oldContainer:Remove(item)
    end

    if item:getContainer() ~= mainInv and mainInv.AddItem then
        mainInv:AddItem(item)
    end
end

local function detachOldSlotItem(hotbar, slotIndex)
    if not hotbar or not hotbar.attachedItems or not slotIndex then return end

    local oldItem = hotbar.attachedItems[slotIndex]
    if not oldItem then return end

    if hotbar.chr then
        hotbar.chr:removeAttachedItem(oldItem)
    end

    if AliceWeaponSling.removeWeightReductionPart and hotbar.chr then
        AliceWeaponSling.removeWeightReductionPart(hotbar.chr, oldItem)
    end

    oldItem:setAttachedSlot(-1)
    oldItem:setAttachedSlotType(nil)
    oldItem:setAttachedToModel(nil)

    hotbar.attachedItems[slotIndex] = nil
end

local function resolveReplacementSlot(hotbar, item, slot)
    local attachmentType = slingAttachmentType(item, slot)

    if hotbar and hotbar.replacements and attachmentType and hotbar.replacements[attachmentType] and slotIsBack(slot) then
        return hotbar.replacements[attachmentType]
    end

    return slot
end

local repairQueue = {}
local repairTickInstalled = false

local function repairAttachedItem(data)
    if not data or not data.item or not data.slotIndex or not data.slotType or not data.model then return end

    local character = data.character
    if not character and data.playerNum then
        character = getSpecificPlayer(data.playerNum)
    end
    if not character then return end

    if itemInHands(character, data.item) then return end

    local hotbar = data.hotbar
    if not hotbar and data.playerNum then
        hotbar = getPlayerHotbar(data.playerNum)
    end
    if not hotbar then return end

    anchorItemToMainInventory(character, data.item)

    if AliceWeaponSling.repairHotbarItem then
        AliceWeaponSling.repairHotbarItem(hotbar, data.item, data.slotIndex, data.slotType, data.model)
    else
        character:setAttachedItem(data.model, data.item)
        data.item:setAttachedSlot(data.slotIndex)
        data.item:setAttachedSlotType(data.slotType)
        data.item:setAttachedToModel(data.model)

        hotbar.attachedItems = hotbar.attachedItems or {}
        hotbar.attachedItems[data.slotIndex] = data.item

        if ISInventoryPage then
            ISInventoryPage.renderDirty = true
        end

        safeSyncItem(character, data.item)
    end
end

local lastRepairErrorAt = 0
local function reportRepairError(err)
    local now = getTimestampMs and getTimestampMs() or math.floor(os.time()*1000)
    if now-lastRepairErrorAt < 5000 then return end
    lastRepairErrorAt = now
    print("[AliceWeaponSling] attach repair failed: " .. tostring(err))
end

local function onRepairTick()
    for i = #repairQueue, 1, -1 do
        local data = repairQueue[i]
        data.ticks = data.ticks - 1

        if data.ticks <= 0 then
            table.remove(repairQueue, i)
            local ok, err = pcall(repairAttachedItem, data)
            if not ok then reportRepairError(err) end
        end
    end

    if #repairQueue == 0 then
        Events.OnTick.Remove(onRepairTick)
        repairTickInstalled = false
    end
end

local function scheduleRepairWindow(action, slot)
    if not action or not action.item or not action.character then return end

    local playerNum = action.character:getPlayerNum()
    local slotType = action.slotDef and action.slotDef.type or nil

    if not slotType or not slot then return end

    local delays = { 1, 2, 5, 10, 15, 30 }

    for _, delay in ipairs(delays) do
        table.insert(repairQueue, {
            ticks = delay,
            character = action.character,
            playerNum = playerNum,
            hotbar = action.hotbar,
            item = action.item,
            slotIndex = action.slotIndex,
            slotType = slotType,
            model = slot,
        })
    end

    if not repairTickInstalled then
        Events.OnTick.Add(onRepairTick)
        repairTickInstalled = true
    end
end

local function commitAttach(action)
    if not action or action.aliceWeaponSlingCommitted then return true end

    local hotbar = action.hotbar
    local character = action.character
    local item = action.item

    if not hotbar or not character or not item then
        action.aliceWeaponSlingCommitted = true
        return true
    end

    local slot = resolveReplacementSlot(hotbar, item, action.slot)
    if slot == "null" then
        if hotbar.removeItem then
            hotbar:removeItem(item)
        end
        action.aliceWeaponSlingCommitted = true
        return true
    end

    clearHands(character, item)
    anchorItemToMainInventory(character, item)
    detachOldSlotItem(hotbar, action.slotIndex)

    character:setAttachedItem(slot, item)
    item:setAttachedSlot(action.slotIndex)
    item:setAttachedSlotType(action.slotDef and action.slotDef.type or nil)
    item:setAttachedToModel(slot)

    hotbar.attachedItems = hotbar.attachedItems or {}
    hotbar.attachedItems[action.slotIndex] = item

    action.slot = slot

    if hotbar.reloadIcons then
        hotbar:reloadIcons()
    end

    if ISInventoryPage then
        ISInventoryPage.renderDirty = true
    end

    safeSyncItem(character, item)
    scheduleRepairWindow(action, slot)
    if AliceWeaponSling.refreshWeightReductionPart then
        AliceWeaponSling.refreshWeightReductionPart(character, item)
    end

    action.aliceWeaponSlingCommitted = true
    return true
end

function ISAttachItemHotbar:new(character, item, slot, slotIndex, slotDef)
    local o = ISBaseTimedAction.new(self, character)

    o.character = character
    o.item = item
    o.slot = slot
    o.slotIndex = slotIndex
    o.slotDef = slotDef

    if not isServer() then
        o.hotbar = getPlayerHotbar(character:getPlayerNum())
    end

    o.stopOnWalk = false
    o.stopOnRun = true
    o.fromHotbar = true
    o.useProgressBar = false
    o.ignoreHandsWounds = true

    o.maxTime = o:getDuration()
    o.animSpeed = 1.0
    o.aliceWeaponSlingCommitted = false

    return o
end

function ISAttachItemHotbar:getDuration()
    if self.character and self.character.isTimedActionInstant and self.character:isTimedActionInstant() then
        return 1
    end
    return self:adjustMaxTime(BASE_ATTACH_TIME)
end

function ISAttachItemHotbar:isValid()
    return self.character ~= nil and self.item ~= nil
end

function ISAttachItemHotbar:complete()
    commitAttach(self)
    return true
end

function ISAttachItemHotbar:perform()
    commitAttach(self)
    ISBaseTimedAction.perform(self)
end

function ISAttachItemHotbar:stop()
    ISBaseTimedAction.stop(self)
end
