local Catalog = require "sbfplus/itemcatalog"

local ItemPatcher = {}

local function getManager(manager)
    if manager then return manager end
    if ScriptManager then return ScriptManager.instance end
    return nil
end

local function getItem(manager, fullType)
    if not manager or not manager.getItem then return nil end
    local ok, item = pcall(manager.getItem, manager, fullType)
    if ok then return item end
    return nil
end

local function patchEntry(manager, entry, attachmentType, result)
    local item = getItem(manager, entry.fullType)
    if not item or not item.DoParam then
        result.skipped = result.skipped + 1
        return
    end

    local ok, err = pcall(item.DoParam, item, "AttachmentType = " .. attachmentType)
    if ok then
        result.patched = result.patched + 1
    else
        result.errors[#result.errors + 1] = entry.fullType .. ": " .. tostring(err)
    end
end

local function buildAttachmentMap(manager)
    local result = {}
    local betterFlashlights = ItemPatcher.hasBetterFlashlights(manager)

    for _, entry in ipairs(Catalog.vanilla) do
        local attachmentType = entry.attachmentType
        if betterFlashlights and entry.betterAttachmentType then
            attachmentType = entry.betterAttachmentType
        end
        result[entry.fullType] = attachmentType
    end

    for _, entry in ipairs(Catalog.authenticZ) do
        result[entry.fullType] = entry.attachmentType
    end

    if betterFlashlights then
        for _, entry in ipairs(Catalog.betterFlashlights) do
            result[entry.fullType] = entry.attachmentType
        end
    end

    return result
end

local function callMethod(target, methodName)
    if not target then return nil end
    local method = target[methodName]
    if not method then return nil end
    local ok, value = pcall(method, target)
    if ok then return value end
    return nil
end

local function patchInventoryItemWithMap(item, attachmentMap)
    if not item or not item.setAttachmentType then return false end

    local fullType = callMethod(item, "getFullType")
    local attachmentType = fullType and attachmentMap[fullType] or nil
    if not attachmentType then return false end

    local currentType = callMethod(item, "getAttachmentType")
    if currentType == attachmentType then return false end

    local ok = pcall(item.setAttachmentType, item, attachmentType)
    return ok
end

local function patchContainerWithMap(container, attachmentMap, visited)
    if not container or visited[container] then return 0 end
    visited[container] = true

    local items = callMethod(container, "getItems")
    if not items or not items.size or not items.get then return 0 end

    local okSize, size = pcall(items.size, items)
    if not okSize or type(size) ~= "number" then return 0 end

    local changed = 0
    for index = 0, size - 1 do
        local okItem, item = pcall(items.get, items, index)
        if okItem and item then
            if patchInventoryItemWithMap(item, attachmentMap) then
                changed = changed + 1
            end
            local nestedContainer = callMethod(item, "getItemContainer")
            if nestedContainer then
                changed = changed + patchContainerWithMap(nestedContainer, attachmentMap, visited)
            end
        end
    end

    return changed
end

function ItemPatcher.hasBetterFlashlights(manager)
    return getItem(getManager(manager), "Base.BF_EgenerexLite") ~= nil
end

function ItemPatcher.getAttachmentType(fullType, manager)
    if not fullType then return nil end
    manager = getManager(manager)
    return buildAttachmentMap(manager)[fullType]
end

function ItemPatcher.patchInventoryItem(item, manager)
    manager = getManager(manager)
    return patchInventoryItemWithMap(item, buildAttachmentMap(manager))
end

function ItemPatcher.patchContainer(container, manager)
    manager = getManager(manager)
    return patchContainerWithMap(container, buildAttachmentMap(manager), {})
end

function ItemPatcher.apply(manager)
    manager = getManager(manager)
    local result = {
        betterFlashlights = false,
        errors = {},
        patched = 0,
        skipped = 0,
    }

    if not manager then
        result.errors[1] = "ScriptManager is unavailable"
        return result
    end

    result.betterFlashlights = ItemPatcher.hasBetterFlashlights(manager)

    for _, entry in ipairs(Catalog.vanilla) do
        local attachmentType = entry.attachmentType
        if result.betterFlashlights and entry.betterAttachmentType then
            attachmentType = entry.betterAttachmentType
        end
        patchEntry(manager, entry, attachmentType, result)
    end

    for _, entry in ipairs(Catalog.authenticZ) do
        patchEntry(manager, entry, entry.attachmentType, result)
    end

    if result.betterFlashlights then
        for _, entry in ipairs(Catalog.betterFlashlights) do
            patchEntry(manager, entry, entry.attachmentType, result)
        end
    end

    return result
end

local function applySafely()
    local ok, result = pcall(ItemPatcher.apply)
    if not ok then
        print("[SBFPlus] item patch error: " .. tostring(result))
        return
    end
    if result and #result.errors > 0 then
        print("[SBFPlus] item patch completed with " .. tostring(#result.errors) .. " error(s)")
    end
end

if Events then
    if Events.OnInitGlobalModData then Events.OnInitGlobalModData.Add(applySafely) end
    if Events.OnInitWorld then Events.OnInitWorld.Add(applySafely) end
end

return ItemPatcher

