require "Hotbar/ISHotbar"

-- Built-in hotbar reordering for Clean HotBar.
-- This feature stays inactive if the external Reorder The Hotbar mod is loaded,
-- so both mods do not try to control the same behavior at the same time.
-- The visual lock/swap controls are intentionally provided through
-- CleanHotbarSettingsPanel to avoid duplicating UI on the hotbar itself.

CleanHotbarReorder = CleanHotbarReorder or {}

local SORT_KEY_SUFFIX = "RTH_index"
local LOCK_KEY = "RTH_locked"
local MODE_KEY = "RTH_swap" -- true = insert mode, false/nil = swap mode
local DRAG_THRESHOLD = 16

local FONT_HGT_SMALL = getTextManager():getFontHeight(UIFont.Small)
local dragGhostSlotBackgroundTexture = getTexture("media/ui/CleanHotBar/CleanHotbar_Slot_BG.png")
local dragGhostSlotBorderTexture = getTexture("media/ui/CleanHotBar/CleanHotbar_Slot_ItemBorder.png")

CleanHotbarReorder.isExternalModActive = false
CleanHotbarReorder.isInstalled = false

local original = {
    render = nil,
    setSizeAndPosition = nil,
    refresh = nil,
    onMouseDown = nil,
    onMouseMove = nil,
    onMouseUp = nil,
    onMouseUpOutside = nil,
}

local function getCharacter(hotbar)
    return hotbar and (hotbar.character or hotbar.chr) or nil
end

local function getModDataForHotbar(hotbar)
    local chr = getCharacter(hotbar)
    if not chr then return nil end
    local ok, modData = pcall(function() return chr:getModData() end)
    if ok then return modData end
    return nil
end

local function getSlotKey(slot)
    if not slot or not slot.slotType then return nil end
    return tostring(slot.slotType) .. SORT_KEY_SUFFIX
end

local function isLocked(hotbar)
    local modData = getModDataForHotbar(hotbar)
    return modData and modData[LOCK_KEY] == true
end

local function isInsertMode(hotbar)
    local modData = getModDataForHotbar(hotbar)
    return modData and modData[MODE_KEY] == true
end

local function syncAttachedSlotIndexes(hotbar)
    if not hotbar or not hotbar.attachedItems then return end
    for index, item in ipairs(hotbar.attachedItems) do
        if item then
            pcall(function() item:setAttachedSlot(index) end)
        end
    end
end

local function rebuildSlotItemRefs(hotbar)
    if not hotbar or not hotbar.availableSlot then return end
    for i, slot in ipairs(hotbar.availableSlot) do
        if slot then
            slot.item = hotbar.attachedItems and hotbar.attachedItems[i] or nil
        end
    end
end

local function getSlotOrderSignature(hotbar)
    if not hotbar or not hotbar.availableSlot then return "" end

    local parts = {}
    for index, slot in ipairs(hotbar.availableSlot) do
        parts[index] = tostring(slot and slot.slotType or "")
    end
    return table.concat(parts, "|")
end

local vanillaSavePositionSyncsCache = nil
local function vanillaSavePositionSyncsModData()
    if vanillaSavePositionSyncsCache ~= nil then
        return vanillaSavePositionSyncsCache
    end

    local version = nil
    local ok, value = pcall(function()
        return getCore():getVersion()
    end)
    if ok then
        version = value
    end

    local major, minor = tostring(version or ""):match("^(%d+)%.(%d+)")
    major = tonumber(major)
    minor = tonumber(minor)
    vanillaSavePositionSyncsCache = major ~= nil and minor ~= nil
        and (major > 42 or (major == 42 and minor >= 20))
    return vanillaSavePositionSyncsCache
end

local function persistCurrentOrder(hotbar)
    local modData = getModDataForHotbar(hotbar)
    if not modData or not hotbar or not hotbar.availableSlot then return end
    for index, slot in ipairs(hotbar.availableSlot) do
        local key = getSlotKey(slot)
        if key then
            modData[key] = index
        end
    end

    -- B42.20+ transmits player modData inside ISHotbar:savePosition().
    -- Older supported builds need the explicit transmit below.
    if hotbar.savePosition then
        hotbar:savePosition()
    end
    local chr = getCharacter(hotbar)
    if isClient() and chr and not vanillaSavePositionSyncsModData() then
        pcall(function() chr:transmitModData() end)
    end
end

local function applySavedOrder(hotbar)
    local modData = getModDataForHotbar(hotbar)
    if not modData or not hotbar or not hotbar.availableSlot then return end
    if #hotbar.availableSlot <= 1 then return end

    local decorated = {}
    for index, slot in ipairs(hotbar.availableSlot) do
        decorated[#decorated + 1] = {
            slot = slot,
            item = hotbar.attachedItems and hotbar.attachedItems[index] or nil,
            index = index,
            preferred = modData[getSlotKey(slot)] or index,
        }
    end

    table.sort(decorated, function(a, b)
        if a.preferred == b.preferred then
            return a.index < b.index
        end
        return a.preferred < b.preferred
    end)

    for i, entry in ipairs(decorated) do
        hotbar.availableSlot[i] = entry.slot
        hotbar.attachedItems[i] = entry.item
    end

    syncAttachedSlotIndexes(hotbar)
    rebuildSlotItemRefs(hotbar)
    persistCurrentOrder(hotbar)
end

local function swapSlots(hotbar, fromIndex, toIndex)
    if fromIndex == toIndex then return end
    local slotA = hotbar.availableSlot[fromIndex]
    local slotB = hotbar.availableSlot[toIndex]
    if not slotA or not slotB then return end

    hotbar.availableSlot[fromIndex], hotbar.availableSlot[toIndex] = slotB, slotA
    hotbar.attachedItems[fromIndex], hotbar.attachedItems[toIndex] = hotbar.attachedItems[toIndex], hotbar.attachedItems[fromIndex]

    syncAttachedSlotIndexes(hotbar)
    rebuildSlotItemRefs(hotbar)
    hotbar.wornItems = nil
    persistCurrentOrder(hotbar)
    hotbar.needsRefresh = true
end

local function insertSlot(hotbar, fromIndex, toIndex)
    if fromIndex == toIndex then return end
    local movedSlot = hotbar.availableSlot[fromIndex]
    local movedItem = hotbar.attachedItems[fromIndex]
    if not movedSlot then return end

    if toIndex < fromIndex then
        for i = fromIndex - 1, toIndex, -1 do
            hotbar.availableSlot[i + 1] = hotbar.availableSlot[i]
            hotbar.attachedItems[i + 1] = hotbar.attachedItems[i]
        end
    else
        for i = fromIndex + 1, toIndex do
            hotbar.availableSlot[i - 1] = hotbar.availableSlot[i]
            hotbar.attachedItems[i - 1] = hotbar.attachedItems[i]
        end
    end

    hotbar.availableSlot[toIndex] = movedSlot
    hotbar.attachedItems[toIndex] = movedItem

    syncAttachedSlotIndexes(hotbar)
    rebuildSlotItemRefs(hotbar)
    hotbar.wornItems = nil
    persistCurrentOrder(hotbar)
    hotbar.needsRefresh = true
end

local function clearDragState(hotbar)
    hotbar.chbReorderDraggingIndex = nil
    hotbar.chbReorderStartX = nil
    hotbar.chbReorderStartY = nil
    hotbar.chbReorderDragging = false
end

local function drawDragGhost(hotbar)
    if not hotbar.chbReorderDragging or not hotbar.chbReorderDraggingIndex then return end
    local slot = hotbar.availableSlot[hotbar.chbReorderDraggingIndex]
    if not slot then return end
    local item = hotbar.attachedItems[hotbar.chbReorderDraggingIndex]

    local x = hotbar:getMouseX() - hotbar.slotWidth / 2
    local y = hotbar:getMouseY() - hotbar.slotHeight / 2
    local config = (CHBConfig and CHBConfig.getConfig and CHBConfig.getConfig()) or {}
    local scale = config.hotbarScale or 1.0
    local opacity = math.max(0.2, math.min(1.0, tonumber(config.hotbarOpacity) or 0.6))

    hotbar:drawTextureScaled(dragGhostSlotBackgroundTexture, x, y, hotbar.slotWidth, hotbar.slotHeight, opacity, 0.4, 0.4, 0.4)
    hotbar:drawTextureScaled(dragGhostSlotBorderTexture, x, y, hotbar.slotWidth, hotbar.slotHeight, 0.8, 0.8, 0.8, 0.8)

    local slotName = getTextOrNull("IGUI_HotbarAttachment_" .. tostring(slot.slotType)) or slot.name or "Unknown"
    local textWid = getTextManager():MeasureStringX(UIFont.Small, slotName)
    hotbar:drawText(slotName, x + (hotbar.slotWidth - textWid) / 2, y - FONT_HGT_SMALL, hotbar.textColor.r, hotbar.textColor.g, hotbar.textColor.b, hotbar.textColor.a, hotbar.font)

    if item and item.getTexture then
        local tex = item:getTexture()
        if tex then
            local texSize = 32 * scale
            local texX = x + (hotbar.slotWidth - texSize) / 2
            local texY = y + (hotbar.slotHeight - texSize) / 2
            hotbar:drawTextureScaledAspect(tex, texX, texY, texSize, texSize, 1, 1, 1, 1)
        end
    elseif slot.texture then
        local texSize = 32 * scale
        local texX = x + (hotbar.slotWidth - texSize) / 2
        local texY = y + (hotbar.slotHeight - texSize) / 2
        hotbar:drawTextureScaledAspect(slot.texture, texX, texY, texSize, texSize, 0.3, 1.0, 1.0, 1.0)
    end
end


local function restoreInternalReorder()
    if not CleanHotbarReorder.isInstalled then
        return
    end

    if original.render then ISHotbar.render = original.render end
    if original.setSizeAndPosition then ISHotbar.setSizeAndPosition = original.setSizeAndPosition end
    if original.refresh then ISHotbar.refresh = original.refresh end
    if original.onMouseDown then ISHotbar.onMouseDown = original.onMouseDown end
    if original.onMouseMove then ISHotbar.onMouseMove = original.onMouseMove end
    if original.onMouseUp then ISHotbar.onMouseUp = original.onMouseUp end
    if original.onMouseUpOutside then ISHotbar.onMouseUpOutside = original.onMouseUpOutside end

    CleanHotbarReorder.isInstalled = false
end

local function installInternalReorder()
    CleanHotbarReorder.isExternalModActive = ReorderTheHotbar_Mod ~= nil
    if CleanHotbarReorder.isInstalled or CleanHotbarReorder.isExternalModActive then
        return
    end

    original.render = ISHotbar.render
    original.setSizeAndPosition = ISHotbar.setSizeAndPosition
    original.refresh = ISHotbar.refresh
    original.onMouseDown = ISHotbar.onMouseDown
    original.onMouseMove = ISHotbar.onMouseMove
    original.onMouseUp = ISHotbar.onMouseUp
    original.onMouseUpOutside = ISHotbar.onMouseUpOutside

    ISHotbar.render = function(self)
        if ReorderTheHotbar_Mod ~= nil then
            return original.render(self)
        end
        original.render(self)
        drawDragGhost(self)
    end

    ISHotbar.setSizeAndPosition = function(self)
        original.setSizeAndPosition(self)
    end

    ISHotbar.refresh = function(self)
        if ReorderTheHotbar_Mod ~= nil then
            return original.refresh(self)
        end

        local beforeSignature = getSlotOrderSignature(self)
        local needsInitialApply = self.chbSavedOrderApplied ~= true

        original.refresh(self)

        local afterSignature = getSlotOrderSignature(self)
        if not CleanHotbarReorder.isExternalModActive
            and (needsInitialApply or beforeSignature ~= afterSignature) then
            applySavedOrder(self)
            self.chbSavedOrderApplied = true
        end
    end

    ISHotbar.onMouseDown = function(self, x, y)
        if ReorderTheHotbar_Mod ~= nil then
            if original.onMouseDown then
                return original.onMouseDown(self, x, y)
            end
            return
        end
        if original.onMouseDown then
            original.onMouseDown(self, x, y)
        end

        if isLocked(self) or ISMouseDrag.dragging then
            return
        end

        local index = self:getSlotIndexAt(x, y)
        if index and index > -1 then
            self.chbReorderDraggingIndex = index
            self.chbReorderStartX = x
            self.chbReorderStartY = y
            self.chbReorderDragging = false
        end
    end

    ISHotbar.onMouseMove = function(self, x, y)
        if ReorderTheHotbar_Mod ~= nil then
            if original.onMouseMove then
                return original.onMouseMove(self, x, y)
            end
            return
        end
        if original.onMouseMove then
            original.onMouseMove(self, x, y)
        end

        if self.chbReorderDraggingIndex and not self.chbReorderDragging then
            local mx = self:getMouseX()
            local my = self:getMouseY()
            local dx = mx - (self.chbReorderStartX or mx)
            local dy = my - (self.chbReorderStartY or my)
            if math.abs(dx) + math.abs(dy) > DRAG_THRESHOLD then
                self.chbReorderDragging = true
            end
        end
    end

    ISHotbar.onMouseUp = function(self, x, y)
        if ReorderTheHotbar_Mod ~= nil then
            clearDragState(self)
            return original.onMouseUp(self, x, y)
        end
        if self.chbReorderDragging then
            local targetIndex = self:getSlotIndexAt(x, y)
            if targetIndex and targetIndex > -1 and targetIndex ~= self.chbReorderDraggingIndex then
                if isInsertMode(self) then
                    insertSlot(self, self.chbReorderDraggingIndex, targetIndex)
                else
                    swapSlots(self, self.chbReorderDraggingIndex, targetIndex)
                end
            end
            clearDragState(self)
            return true
        end

        clearDragState(self)
        return original.onMouseUp(self, x, y)
    end

    ISHotbar.onMouseUpOutside = function(self, x, y)
        if ReorderTheHotbar_Mod ~= nil then
            clearDragState(self)
            if original.onMouseUpOutside then
                return original.onMouseUpOutside(self, x, y)
            end
            return false
        end
        if self.chbReorderDragging then
            self:onMouseUp(x, y)
            return true
        end
        if original.onMouseUpOutside then
            return original.onMouseUpOutside(self, x, y)
        end
        return false
    end

    CleanHotbarReorder.isInstalled = true
end

local function onLoadApply()
    CleanHotbarReorder.isExternalModActive = ReorderTheHotbar_Mod ~= nil
    if CleanHotbarReorder.isExternalModActive then
        restoreInternalReorder()
    else
        installInternalReorder()
    end
end

Events.OnLoad.Add(onLoadApply)
Events.OnGameStart.Add(onLoadApply)

return CleanHotbarReorder
