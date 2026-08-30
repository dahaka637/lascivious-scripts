pcall(require, "Hotbar/ISHotbarAttachDefinition")
pcall(require, "Hotbar/ISHotbar")

local ItemPatcher = require "sbfplus/itempatcher"
local HotbarCompatibility = require "sbfplus/hotbarcompatibility"
local AttachedItemMigration = require "sbfplus/attacheditemmigration"
local unpackValues = unpack or table.unpack

if not ISHotbarAttachDefinition then return end

local LEFT_BELT = {
    SBFPlus_VanillaSmall = "SBFPlus_VanillaSmallLeft",
    SBFPlus_Angled = "SBFPlus_AngledLeft",
    SBFPlus_AZMilitary = "SBFPlus_AZMilitaryLeft",
    SBFPlus_BFNative = "SBFPlus_BFNativeLeft",
    SBFPlus_BF_Torch1 = "SBFPlus_BF_Torch1Left",
    SBFPlus_BF_Torch2 = "SBFPlus_BF_Torch2Left",
    SBFPlus_BF_Torch3 = "SBFPlus_BF_Torch3Left",
    SBFPlus_BF_Torch5 = "SBFPlus_BF_Torch5Left",
    SBFPlus_BF_EgenerexLite = "SBFPlus_BF_EgenerexLiteLeft",
    SBFPlus_BF_SpiffoLite = "SBFPlus_BF_SpiffoLiteLeft",
}

local RIGHT_BELT = {
    SBFPlus_VanillaSmall = "SBFPlus_VanillaSmallRight",
    SBFPlus_Angled = "SBFPlus_AngledRight",
    SBFPlus_AZMilitary = "SBFPlus_AZMilitaryRight",
    SBFPlus_BFNative = "SBFPlus_BFNativeRight",
    SBFPlus_BF_Torch1 = "SBFPlus_BF_Torch1Right",
    SBFPlus_BF_Torch2 = "SBFPlus_BF_Torch2Right",
    SBFPlus_BF_Torch3 = "SBFPlus_BF_Torch3Right",
    SBFPlus_BF_Torch5 = "SBFPlus_BF_Torch5Right",
    SBFPlus_BF_EgenerexLite = "SBFPlus_BF_EgenerexLiteRight",
    SBFPlus_BF_SpiffoLite = "SBFPlus_BF_SpiffoLiteRight",
}

local LEFT_WEBBING = {
    SBFPlus_Angled = "SBFPlus_AngledWebbingLeft",
    SBFPlus_AZMilitary = "SBFPlus_AngledWebbingLeft",
}

local RIGHT_WEBBING = {
    SBFPlus_Angled = "SBFPlus_AngledWebbingRight",
    SBFPlus_AZMilitary = "SBFPlus_AngledWebbingRight",
}

local SLOT_MAPS = {
    SmallBeltLeft = LEFT_BELT,
    FrontBeltL = LEFT_BELT,
    SmallBeltRight = RIGHT_BELT,
    FrontBeltR = RIGHT_BELT,
    WebbingLeft = LEFT_WEBBING,
    AZWebbingLeft = LEFT_WEBBING,
    WebbingRight = RIGHT_WEBBING,
    AZWebbingRight = RIGHT_WEBBING,
}

local function ensureDefinitions()
    for _, definition in ipairs(ISHotbarAttachDefinition) do
        local additions = definition and SLOT_MAPS[definition.type] or nil
        if additions then
            definition.attachments = definition.attachments or {}
            for attachmentType, location in pairs(additions) do
                definition.attachments[attachmentType] = location
            end
        end
    end

    HotbarCompatibility.patchPARDefinitions(ISHotbarAttachDefinition, rawget(_G, "PARSlotsName"))
end

local function ensureDefinitionsSafely()
    local okDefinitions, definitionError = pcall(ensureDefinitions)
    if not okDefinitions then
        print("[SBFPlus] hotbar definition error: " .. tostring(definitionError))
    end
    return okDefinitions
end

local function getInventory(character)
    if not character or not character.getInventory then return nil end
    local ok, inventory = pcall(character.getInventory, character)
    if ok then return inventory end
    return nil
end

local function patchCharacterInventory(character)
    local inventory = getInventory(character)
    if not inventory then return 0 end
    local ok, changed = pcall(ItemPatcher.patchContainer, inventory)
    if ok then return changed or 0 end
    print("[SBFPlus] inventory migration error: " .. tostring(changed))
    return 0
end

local function syncMigratedItem(character, item)
    if type(isClient) ~= "function" or type(syncItemFields) ~= "function" then return end
    local okClient, client = pcall(isClient)
    if okClient and client then
        local okSync, syncError = pcall(syncItemFields, character, item)
        if not okSync then error(syncError) end
    end
end

local function patchAttachedItems(hotbar)
    local attachedItems = hotbar and hotbar.attachedItems or nil
    if type(attachedItems) ~= "table" then return 0 end

    local changed = 0
    for _, item in pairs(attachedItems) do
        local okPatch, patched = pcall(ItemPatcher.patchInventoryItem, item)
        if okPatch and patched then
            changed = changed + 1
        elseif not okPatch then
            print("[SBFPlus] attached item migration error: " .. tostring(patched))
        end
    end
    return changed
end

local function migrateAttachedItems(hotbar)
    local character = hotbar and hotbar.chr or nil
    local attachedItems = hotbar and hotbar.attachedItems or nil
    if not character or type(attachedItems) ~= "table" then return 0 end

    local changed = 0
    for _, item in pairs(attachedItems) do
        if item and item.getFullType and item.getAttachedSlot and item.getAttachmentType then
            local okFullType, fullType = pcall(item.getFullType, item)
            local okSlot, slotIndex = pcall(item.getAttachedSlot, item)
            local slot = okSlot and slotIndex and slotIndex > -1 and hotbar.availableSlot and hotbar.availableSlot[slotIndex] or nil
            local slotDef = slot and slot.def or nil
            local okType, attachmentType = pcall(item.getAttachmentType, item)
            local okExpected, expectedType = pcall(ItemPatcher.getAttachmentType, okFullType and fullType or nil)
            local ownedSlotMap = okExpected and expectedType == attachmentType and slotDef and SLOT_MAPS[slotDef.type] or nil
            local target = okType and ownedSlotMap and ownedSlotMap[attachmentType] or nil
            if target and item.getAttachedToModel and item.setAttachedToModel and character.setAttachedItem then
                local status, migrationError = AttachedItemMigration.move(character, item, target, syncMigratedItem)
                if migrationError then
                    print("[SBFPlus] attached model migration error: " .. tostring(migrationError))
                end
                if status == "moved" then changed = changed + 1 end
            end
        end
    end

    return changed
end

local function refreshCompatibility()
    local okPatch, patchError = pcall(ItemPatcher.apply)
    if not okPatch then print("[SBFPlus] item definition patch error: " .. tostring(patchError)) end
    ensureDefinitionsSafely()
end

refreshCompatibility()

if ISHotbar and type(ISHotbar.refresh) == "function" and not ISHotbar.SBFPlus_RefreshWrapped then
    local previousRefresh = ISHotbar.refresh
    function ISHotbar:refresh(...)
        ensureDefinitionsSafely()
        patchAttachedItems(self)
        local results = { n = 0 }
        local function capture(...)
            results.n = select("#", ...)
            for index = 1, results.n do results[index] = select(index, ...) end
        end
        capture(previousRefresh(self, ...))
        migrateAttachedItems(self)
        return unpackValues(results, 1, results.n)
    end
    ISHotbar.SBFPlus_RefreshWrapped = true
end

if ISHotbar and type(ISHotbar.doMenuFromInventory) == "function" and not ISHotbar.SBFPlus_MenuWrapped then
    local previousMenu = ISHotbar.doMenuFromInventory
    function ISHotbar.doMenuFromInventory(playerNum, item, context, ...)
        local okPatch, patchError = pcall(ItemPatcher.patchInventoryItem, item)
        if not okPatch then print("[SBFPlus] context item migration error: " .. tostring(patchError)) end
        return previousMenu(playerNum, item, context, ...)
    end
    ISHotbar.SBFPlus_MenuWrapped = true
end

local function patchPlayer(playerNum, player)
    if not player and type(getSpecificPlayer) == "function" then
        local okPlayer, result = pcall(getSpecificPlayer, playerNum or 0)
        if okPlayer then player = result end
    end
    if not player then return end

    patchCharacterInventory(player)
    if type(getPlayerHotbar) == "function" then
        local okHotbar, hotbar = pcall(getPlayerHotbar, playerNum or 0)
        if okHotbar and hotbar then migrateAttachedItems(hotbar) end
    end
end

local function onGameStart()
    refreshCompatibility()
    if type(getNumActivePlayers) ~= "function" then
        patchPlayer(0)
        return
    end
    local okCount, count = pcall(getNumActivePlayers)
    if not okCount or type(count) ~= "number" then return end
    for playerNum = 0, count - 1 do patchPlayer(playerNum) end
end

if Events then
    if Events.OnCreatePlayer then Events.OnCreatePlayer.Add(patchPlayer) end
    if Events.OnGameStart then Events.OnGameStart.Add(onGameStart) end
end
