if getActivatedMods():contains("\\nattachments") then return end

require "TimedActions/ISClothingExtraAction"

AliceWeaponSling = AliceWeaponSling or {}
AliceWeaponSling.TextureToggle = AliceWeaponSling.TextureToggle or {}

local PREF_KEY = "AliceWeaponSling_ShowTexture"

local function getTranslatedText(key, fallback)
    return getTextOrNull(key) or fallback
end

local visibleToHidden = {
    ["Base.AliceWeaponSling"] = "Base.AliceWeaponSling_Hidden",
    ["Base.AliceWeaponSlingAlt"] = "Base.AliceWeaponSlingAlt_Hidden",
    ["Base.AliceWeaponSlingAlt2"] = "Base.AliceWeaponSlingAlt2_Hidden",
    ["Base.AliceWeaponSlingBack"] = "Base.AliceWeaponSlingBack_Hidden",
}

local hiddenToVisible = {
    ["Base.AliceWeaponSling_Hidden"] = "Base.AliceWeaponSling",
    ["Base.AliceWeaponSlingAlt_Hidden"] = "Base.AliceWeaponSlingAlt",
    ["Base.AliceWeaponSlingAlt2_Hidden"] = "Base.AliceWeaponSlingAlt2",
    ["Base.AliceWeaponSlingBack_Hidden"] = "Base.AliceWeaponSlingBack",
}

local function getFullType(item)
    return item and item.getFullType and item:getFullType() or nil
end

local function isVisibleSling(item)
    return visibleToHidden[getFullType(item)] ~= nil
end

local function isHiddenSling(item)
    return hiddenToVisible[getFullType(item)] ~= nil
end

local function isSling(item)
    return isVisibleSling(item) or isHiddenSling(item)
end

local function getPreference(playerObj)
    local modData = playerObj:getModData()
    if modData[PREF_KEY] == nil then
        modData[PREF_KEY] = true
    end
    return modData[PREF_KEY] == true
end

local function setPreference(playerObj, showTexture)
    playerObj:getModData()[PREF_KEY] = showTexture == true
end

local function copyBasicState(oldItem, newItem)
    if not oldItem or not newItem then return end

    newItem:setCondition(oldItem:getCondition())
    newItem:setFavorite(oldItem:isFavorite())
    newItem:setColor(oldItem:getColor())

    if oldItem:hasModData() then
        newItem:copyModData(oldItem:getModData())
    end
end

local function replaceUnwornItem(playerObj, item, newFullType)
    local container = item:getContainer() or playerObj:getInventory()
    if not container then return nil end

    local newItem = instanceItem(newFullType)
    if not newItem then return nil end

    copyBasicState(item, newItem)

    container:Remove(item)
    if sendRemoveItemFromContainer then
        sendRemoveItemFromContainer(container, item)
    end

    container:AddItem(newItem)
    if sendAddItemToContainer then
        sendAddItemToContainer(container, newItem)
    end

    return newItem
end

local function swapSlingTexture(playerObj, item, showTexture)
    if not playerObj or not item or not isSling(item) then return end

    local newFullType
    if showTexture then
        newFullType = hiddenToVisible[getFullType(item)]
    else
        newFullType = visibleToHidden[getFullType(item)]
    end

    if not newFullType then return end

    setPreference(playerObj, showTexture)

    if playerObj:isEquippedClothing(item) then
        ISTimedActionQueue.add(ISClothingExtraAction:new(playerObj, item, newFullType))
    else
        replaceUnwornItem(playerObj, item, newFullType)
    end
end

local function normalizeContextItems(items)
    local result = {}

    for _, entry in ipairs(items) do
        local item = entry
        if type(entry) == "table" then
            item = entry.items and entry.items[1] or entry.item or entry[1]
        end

        if item and item.getFullType and isSling(item) then
            table.insert(result, item)
        end
    end

    return result
end

local function onFillInventoryObjectContextMenu(playerNum, context, items)
    local playerObj = getSpecificPlayer(playerNum)
    if not playerObj then return end

    local slings = normalizeContextItems(items)
    if #slings == 0 then return end

    local item = slings[1]
    local currentlyVisible = isVisibleSling(item)

    if currentlyVisible then
        context:addOption(getTranslatedText("ContextMenu_AliceWeaponSling_HideTexture", "Hide Sling Texture"), playerObj, swapSlingTexture, item, false)
    else
        context:addOption(getTranslatedText("ContextMenu_AliceWeaponSling_ShowTexture", "Show Sling Texture"), playerObj, swapSlingTexture, item, true)
    end
end

local function applyPreferenceToWornSlings(playerObj)
    if not playerObj or not playerObj.getWornItems then return end

    local showTexture = getPreference(playerObj)
    local wornItems = playerObj:getWornItems()
    if not wornItems then return end

    for i = 0, wornItems:size() - 1 do
        local item = wornItems:getItemByIndex(i)
        if isSling(item) then
            if showTexture and isHiddenSling(item) then
                swapSlingTexture(playerObj, item, true)
                return
            elseif not showTexture and isVisibleSling(item) then
                swapSlingTexture(playerObj, item, false)
                return
            end
        end
    end
end

local function onClothingUpdated(playerObj)
    if not playerObj or playerObj ~= getSpecificPlayer(0) then return end
    applyPreferenceToWornSlings(playerObj)
end

Events.OnFillInventoryObjectContextMenu.Add(onFillInventoryObjectContextMenu)
Events.OnClothingUpdated.Add(onClothingUpdated)