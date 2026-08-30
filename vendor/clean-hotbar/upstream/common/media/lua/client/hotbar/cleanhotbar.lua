require "Hotbar/ISHotbar"


local FONT_HGT_SMALL = getTextManager():getFontHeight(UIFont.Small)

-- Reject broken items before vanilla treats them as valid hotbar attachments.
-- This prevents an existing slot item from being detached only for the broken
-- replacement to be removed again by the following hotbar update.
if not CleanHotbar_original_canBeAttached then
    CleanHotbar_original_canBeAttached = ISHotbar.canBeAttached
end

ISHotbar.canBeAttached = function(self, slot, item)
    if not item or item:isBroken() then
        return false
    end

    return CleanHotbar_original_canBeAttached(self, slot, item)
end

local numberTextures = {}
for i = 0, 20 do
    numberTextures[i] = getTexture("media/ui/CleanHotBar/numbers/" .. i .. ".png")
end

-- Button Texture
local toggleButtonTex = {
    show = getTexture("media/ui/CleanHotBar/CleanHotbar_Toggle_ShowIcon.png"),
    hide = getTexture("media/ui/CleanHotBar/CleanHotbar_Toggle_HideIcon.png")
}
-- Interface Texture
local tooltipBackground = {
    Left = getTexture("media/ui/CleanHotBar/CleanHotbar_Text_BG_Left.png"),
    Middle = getTexture("media/ui/CleanHotBar/CleanHotbar_Text_BG_Middle.png"),
    Right = getTexture("media/ui/CleanHotBar/CleanHotbar_Text_BG_Right.png")
}

local slotBackgroundTexture = getTexture("media/ui/CleanHotBar/CleanHotbar_Slot_BG.png")
local slotItemBorderTexture = getTexture("media/ui/CleanHotBar/CleanHotbar_Slot_ItemBorder.png")
local slotItemHoverTexture = getTexture("media/ui/CleanHotBar/CleanHotbar_Item_Hover.png")
local numberBackgroundTexture = getTexture("media/ui/CleanHotBar/CleanHotbar_Number_BG.png")

local DEFAULT_HOTBAR_OPACITY = 0.6

local function clamp(value, minValue, maxValue)
    return math.max(minValue, math.min(maxValue, value))
end

local function getHotbarOpacity(config)
    return clamp(tonumber(config.hotbarOpacity) or DEFAULT_HOTBAR_OPACITY, 0.2, 1.0)
end

local function scaleAlpha(alpha, opacityScale)
    return clamp(alpha * opacityScale, 0.0, 1.0)
end

local function getDraggedItems()
    local dragging = ISMouseDrag.dragging
    if not dragging then return nil end

    if type(dragging) ~= "table" and instanceof(dragging, "InventoryItem") then
        return { dragging }
    end

    -- Equipment UI represents a dragged item as a single stack table instead of
    -- vanilla's array of stacks. Normalise both forms before asking vanilla (or
    -- Inventory Tetris' compatible override) for the actual InventoryItem list.
    if dragging.items then
        dragging = { dragging }
    end

    return ISInventoryPane.getActualItems(dragging)
end

local function getCompatibleDraggedItem(hotbar, slot, draggingItems)
    if not slot or not draggingItems then return nil end

    for _, item in ipairs(draggingItems) do
        if hotbar:canBeAttached(slot, item) then
            return item
        end
    end

    return nil
end

local function isDraggedItem(item, draggingItems)
    if not item or not draggingItems then return false end

    for _, draggedItem in ipairs(draggingItems) do
        if draggedItem == item then
            return true
        end
    end

    return false
end

local function getScaledNumberSize(scale)
    local baseHeight = FONT_HGT_SMALL * 0.6
    scale = scale or 1.0
    local effectiveScale = scale
    if scale > 1.0 then
        effectiveScale = 1.0 + (scale - 1.0) *(2/3)
    end
    
    return math.floor(baseHeight * effectiveScale), math.floor(baseHeight * effectiveScale)
end

local function drawNumberTexture(hotbar, num, x, y, alpha, numberHeight, numberWidth)
    alpha = alpha or 1.0
    
    local validNum = math.min(20, math.max(0, num))
    local tex = numberTextures[validNum]
    local height = numberHeight
    local width = numberWidth
    local digitX = x - (width / 2)
    local digitY = y - (height / 2)
    hotbar:drawTextureScaled(tex, digitX, digitY, width, height, alpha, 1, 1, 1)
end

local function calculateStatusDisplayHeight(hotbar, item, config)
    if not item then return 0 end
    
    config = config or CHBConfig.getConfig()
    local statusHeight = 0
    
    if CleanHotbarWeaponState.isRangedWeapon(item) then
        if config.showWeaponAmmo.hotbar then
            local fontHeight = getTextManager():getFontHeight(UIFont.Small)
            local scaledFontHeight = fontHeight * 0.8
            local padding = 2
            statusHeight = scaledFontHeight + padding * 2
        end
    else
        local hasHeadCondition = item:hasHeadCondition() and not item:hasSharpness() and config.showWeaponHeadCondition.hotbar
        local hasSharpness = item:hasSharpness() and config.showWeaponSharpness.hotbar
        
        if hasHeadCondition or hasSharpness then
            local statusBarScale = config.statusBarHeightScale or 1.0

            local minBarHeight = math.floor(hotbar.slotHeight / 6)
            local maxBarHeight = math.floor(hotbar.slotHeight / 2)
            local scaleFactor = (statusBarScale - 1.0) / 2.0 
            local barHeight = math.floor(minBarHeight + (maxBarHeight - minBarHeight) * scaleFactor)
            
            local barPadding = 2
            local barTopMargin = 3
            
            local barCount = 0
            if hasHeadCondition then barCount = barCount + 1 end
            if hasSharpness then barCount = barCount + 1 end
            
            statusHeight = barTopMargin + (barHeight * barCount) + (barPadding * (barCount - 1))
        end
    end
    
    return statusHeight
end

-- ----------------------------------------- --
-- ISHotbar:render override
-- ----------------------------------------- --

ISHotbar.render = function(self)
    self:noBackground()
    local config = CHBConfig.getConfig()
    local scale = config.hotbarScale or 1.0
    local hotbarOpacity = getHotbarOpacity(config)
    local opacityScale = hotbarOpacity / DEFAULT_HOTBAR_OPACITY
    local originalSlotWidth = 60
    local originalSlotHeight = 60

    self.slotWidth = math.floor(originalSlotWidth * scale)
    self.slotHeight = math.floor(originalSlotHeight * scale)

    if (self.playerNum > 0) or JoypadState.players[self.playerNum+1] then
        self:setVisible(false)
    end

    local mouseX = self:getMouseX()
    local mouseY = self:getMouseY()
    local mouseOverSlotIndex = self:getSlotIndexAt(mouseX, mouseY)
    local draggingItems = getDraggedItems()
    local isDragging = draggingItems and #draggingItems > 0

    -- ( Show/Hide Empty Slot ) Button
    local toggleButtonSize = math.floor(self.slotWidth / 3)
    local toggleButtonX = self.margins + 1
    local toggleButtonY = self.margins + 1 + (self.slotHeight - toggleButtonSize) / 2

    local iconTexture = config.showEmptySlots and toggleButtonTex.hide or toggleButtonTex.show
    local alpha = 0.6
    if mouseX >= toggleButtonX and mouseX <= toggleButtonX + toggleButtonSize and
       mouseY >= toggleButtonY and mouseY <= toggleButtonY + toggleButtonSize then
        alpha = 0.8
    end
    self:drawTextureScaled(iconTexture, toggleButtonX, toggleButtonY, toggleButtonSize, toggleButtonSize, alpha, 0.8, 0.8, 0.8)

    local slotY = self.margins + 1
    local texSize = 32 * scale
    local numberHeight, numberWidth = getScaledNumberSize(scale)
    local bgPadding = 4 * scale
    local bgSize = numberHeight + bgPadding

    local slotX = toggleButtonX + toggleButtonSize + self.slotPad
    for i, slot in pairs(self.availableSlot) do
        local item = self.attachedItems[i]
        local isMouseOver = (i == mouseOverSlotIndex)

        if not config.showEmptySlots and not item then
            -- Hidden empty slots remain hidden even while dragging. This preserves the
            -- compact layout selected by the player and keeps slot hitboxes stable.
        else
            local compatibleDraggedItem = isDragging and getCompatibleDraggedItem(self, slot, draggingItems) or nil
            local bgBrightness = isMouseOver and 0.5 or 0.35
            local r, g, b = bgBrightness, bgBrightness, bgBrightness

            self:drawTextureScaled(slotBackgroundTexture, slotX, slotY, self.slotWidth, self.slotHeight, hotbarOpacity, r, g, b)

            if item then
                CleanHotbarItemState.renderItemState(self, item, slotX, slotY, self.slotWidth, self.slotHeight, config, opacityScale)
                CleanHotbarWeaponState.renderWeaponState(self, item, slotX, slotY, self.slotWidth, self.slotHeight, config, opacityScale)
                self:drawTextureScaled(slotItemHoverTexture, slotX, slotY, self.slotWidth, self.slotHeight, scaleAlpha(0.6, opacityScale), 0.98, 0.95, 0.85)
            end

            -- While dragging, show every currently visible compatible slot without
            -- requiring hover. Green means the slot is empty; yellow means attaching
            -- the dragged item would replace the item already occupying that slot.
            -- Keep vanilla/Clean HotBar's red feedback for an incompatible hovered slot.
            if compatibleDraggedItem and compatibleDraggedItem ~= item then
                if item then
                    self:drawRect(slotX + 1, slotY + 1, self.slotWidth - 2, self.slotHeight - 2, 0.34, 0.85, 0.70, 0.20)
                else
                    self:drawRect(slotX + 1, slotY + 1, self.slotWidth - 2, self.slotHeight - 2, 0.32, 0.20, 0.75, 0.25)
                end
            elseif isMouseOver and isDragging and not compatibleDraggedItem then
                self:drawRect(slotX + 1, slotY + 1, self.slotWidth - 2, self.slotHeight - 2, 0.30, 0.75, 0.20, 0.20)
            end

            -- Draw border
            if item then
                if item:isEquipped() then
                    self:drawTextureScaled(slotItemBorderTexture, slotX, slotY, self.slotWidth, self.slotHeight, 1.0, 0.6, 0.9, 0.9)
                else
                    self:drawTextureScaled(slotItemBorderTexture, slotX, slotY, self.slotWidth, self.slotHeight, 0.6, 0.6, 0.6, 0.6)
                end
            end

            -- Draw number
            local slotBottomY = slotY + self.slotHeight
            local slotCenterX = slotX + (self.slotWidth / 2)
            local bgX = slotCenterX - (bgSize / 2)
            local bgY = slotBottomY - (bgSize / 2)

            self:drawTextureScaled(numberBackgroundTexture, bgX, bgY, bgSize, bgSize, 1, 0.8, 0.8, 0.8)
            drawNumberTexture(self, i, slotCenterX, slotBottomY, 1.0, numberHeight, numberWidth)

            local displayItem = item
            if isMouseOver and compatibleDraggedItem then
                displayItem = compatibleDraggedItem
            elseif isDraggedItem(item, draggingItems) then
                displayItem = nil
            end

            -- Draw attachment tooltip
            if isMouseOver then
                local slotName = getTextOrNull("IGUI_HotbarAttachment_" .. slot.slotType) or slot.name
                local textWid = getTextManager():MeasureStringX(UIFont.Small, slotName)

                local tooltipPadding = FONT_HGT_SMALL / 4
                local tooltipWidth = textWid + tooltipPadding * 2
                local tooltipHeight = FONT_HGT_SMALL + tooltipPadding * 2
                local tooltipX = slotX + (self.slotWidth - tooltipWidth) / 2

                local statusDisplayHeight = 0
                if displayItem then
                    statusDisplayHeight = calculateStatusDisplayHeight(self, displayItem, config)
                end

                local tooltipY = 0 - tooltipHeight
                if statusDisplayHeight > 0 then
                    tooltipY = tooltipY - statusDisplayHeight
                end

                CHBCommonUnit.drawThreeSliceBar(self, tooltipX, tooltipY, tooltipWidth, tooltipHeight, tooltipBackground.Left, tooltipBackground.Middle, tooltipBackground.Right, 0.8, 0.2, 0.2, 0.2)

                local textY = tooltipY + tooltipPadding
                self:drawText(slotName, slotX + (self.slotWidth - textWid) / 2, textY, self.textColor.r, self.textColor.g, self.textColor.b, self.textColor.a, self.font)
            end

            -- Draw item icon
            if displayItem then
                local shakeOffset = CleanHotbarItemState.calculateShakeOffset(displayItem)
                local itemX = slotX + (self.slotWidth - texSize) / 2 + shakeOffset
                local itemY = slotY + (self.slotHeight - texSize) / 2
                self:drawTextureScaledAspect(displayItem:getTexture(), itemX, itemY, texSize, texSize, 1, 1, 1, 1)
                CleanHotbarItemState.renderActivationIcon(self, displayItem, slotX, slotY, self.slotWidth, self.slotHeight)
                CleanHotbarItemState.renderActionProgress(self, displayItem, slotX, slotY, self.slotWidth, self.slotHeight)

            -- Draw empty slot attachment
            elseif slot.texture then
                local texX = slotX + (self.slotWidth - texSize) / 2
                local texY = slotY + (self.slotHeight - texSize) / 2
                self:drawTextureScaledAspect(slot.texture, texX, texY, texSize, texSize, 0.3, 1.0, 1.0, 1.0)
            end

            slotX = slotX + self.slotWidth + self.slotPad
        end
    end

    self:updateTooltip(config)
end

-- ----------------------------------------- --
-- Scale the Hotbar
-- ----------------------------------------- --
if not CleanHotbar_original_setSizeAndPosition then
    CleanHotbar_original_setSizeAndPosition = ISHotbar.setSizeAndPosition
end

ISHotbar.setSizeAndPosition = function(self)
    local config = CHBConfig.getConfig()
    local scale = config.hotbarScale or 1.0
    
    local originalSlotWidth = 60
    local originalSlotHeight = 60
    
    self.slotWidth = math.floor(originalSlotWidth * scale)
    self.slotHeight = math.floor(originalSlotHeight * scale)
    self.height = self.slotHeight + (self.margins * 2) + 2
    local toggleButtonSize = math.floor(self.slotWidth / 3)
    local visibleSlotCount = 0
    
    for i, _ in pairs(self.availableSlot) do
        if config.showEmptySlots or self.attachedItems[i] then
            visibleSlotCount = visibleSlotCount + 1
        end
    end
    
    -- Calculate Width
    local width = toggleButtonSize + self.slotPad
    width = width + (visibleSlotCount * self.slotWidth)
    if visibleSlotCount > 0 then
        width = width + ((visibleSlotCount - 1) * self.slotPad)
    end
    self:setWidth(width + self.margins*2 + 2)

    -- Get Screen
    local screenX = getPlayerScreenLeft(self.playerNum)
    local screenY = getPlayerScreenTop(self.playerNum)
    local screenW = getPlayerScreenWidth(self.playerNum)
    local screenH = getPlayerScreenHeight(self.playerNum)

    -- Scale Number
    local fontHeight = getTextManager():getFontHeight(UIFont.Small)
    local defaultBaseHeight = fontHeight * 0.6
    local defaultPadding = 4
    local defaultNumberSize = defaultBaseHeight + defaultPadding

    local currentBaseHeight = fontHeight * 0.6 * scale
    local currentPadding = 4 * scale
    local currentNumberSize = currentBaseHeight + currentPadding

    local defaultOverflow = defaultNumberSize / 2
    local currentOverflow = currentNumberSize / 2
    local upwardOffset = currentOverflow - defaultOverflow
    upwardOffset = (scale > 1.0) and upwardOffset or 0

    self:setX(screenX + (screenW - self.width) / 2)
    self:setY(screenY + screenH - self.height - upwardOffset)
    
    if CleanHotbarSettings and CleanHotbarSettings.settingsButton then
        CleanHotbarSettings.settingsButton:updatePosition(self)
    end
end

if not CleanHotbar_original_onMouseUp then
    CleanHotbar_original_onMouseUp = ISHotbar.onMouseUp
end
ISHotbar.onMouseUp = function(self, x, y)
    local toggleButtonSize = math.floor(self.slotWidth / 3)
    local toggleButtonX = self.margins + 1
    local toggleButtonY = self.margins + 1 + (self.slotHeight - toggleButtonSize) / 2
    
    if x >= toggleButtonX and x <= toggleButtonX + toggleButtonSize and
       y >= toggleButtonY and y <= toggleButtonY + toggleButtonSize then
        local config = CHBConfig.getConfig()
        config.showEmptySlots = not config.showEmptySlots
        CHBConfig.updateConfig("showEmptySlots", config.showEmptySlots)
        getSoundManager():playUISound("UIToggleTickBox")
        self:setSizeAndPosition()
        return true
    end

    return CleanHotbar_original_onMouseUp(self, x, y)
end

if not CleanHotbar_original_getSlotIndexAt then
    CleanHotbar_original_getSlotIndexAt = ISHotbar.getSlotIndexAt
end
ISHotbar.getSlotIndexAt = function(self, x, y)
    local config = CHBConfig.getConfig()
    local toggleButtonSize = math.floor(self.slotWidth / 3)

    local slotStartX = self.margins + 1 + toggleButtonSize + self.slotPad
    
    if x >= slotStartX and x < self.width and y >= 0 and y < self.height then
        local relativeX = x - slotStartX
        local slotWidth = self.slotWidth + self.slotPad
        local slotIndex = math.floor(relativeX / slotWidth) + 1
        if not config.showEmptySlots then
            local visibleIndex = 0
            for i=1, #self.availableSlot do
                if self.attachedItems[i] then
                    visibleIndex = visibleIndex + 1
                    if visibleIndex == slotIndex then
                        return i
                    end
                end
            end
            return -1
        else
            if slotIndex <= #self.availableSlot then
                return slotIndex
            end
        end
    end
    return -1
end

-- ----------------------------------------- --
-- Tooltip Manager
-- ----------------------------------------- --

ISHotbar.updateTooltip = function(self, config)
    config = config or CHBConfig.getConfig()

    local function hideTooltip(tooltip)
        if tooltip and tooltip:isVisible() then
            tooltip:removeFromUIManager()
            tooltip:setVisible(false)
        end
    end

    -- Reuse the hotbar tooltip object used by newer vanilla builds so Clean HotBar
    -- does not create a second tooltip window beside the vanilla one.
    local activeTooltip = self.toolRender or self.tooltipRender

    if not config.showItemTooltip.hotbar then
        hideTooltip(self.toolRender)
        if self.tooltipRender and self.tooltipRender ~= self.toolRender then
            hideTooltip(self.tooltipRender)
        end
        return
    end

    local index = self:getSlotIndexAt(self:getMouseX(), self:getMouseY())
    local item = nil

    if index ~= -1 and self.attachedItems[index] and not getPlayerContextMenu(self.playerNum):isAnyVisible() then
        item = self.attachedItems[index]
    end

    if item then
        if activeTooltip then
            activeTooltip:setItem(item)
            activeTooltip:setVisible(true)
            activeTooltip:addToUIManager()
            activeTooltip:bringToTop()
        else
            activeTooltip = ISToolTipInv:new(item)
            activeTooltip.followMouse = false
            activeTooltip:initialise()
            activeTooltip:addToUIManager()
            activeTooltip:setVisible(true)
            activeTooltip:setOwner(self)
            activeTooltip:setCharacter(self.character)
        end

        -- Keep both references pointing to the same tooltip instance so older hooks and
        -- newer vanilla hotbar code stay in sync and do not display duplicate tooltips.
        self.toolRender = activeTooltip
        self.tooltipRender = activeTooltip

        local physicalIndex = 0
        for i = 1, index do
            if config.showEmptySlots or self.attachedItems[i] then
                if i == index then break end
                physicalIndex = physicalIndex + 1
            end
        end
        local toggleButtonSize = math.floor(self.slotWidth / 3)
        local slotX = self:getAbsoluteX() + self.margins + toggleButtonSize + self.slotPad + (self.slotWidth + self.slotPad) * physicalIndex
        local slotY = self:getAbsoluteY()
        local slotBottomY = slotY + self.slotHeight

        activeTooltip.prerender = function(tooltip)
            ISToolTipInv.prerender(tooltip)

            local tooltipWidth = tooltip:getWidth()
            local tooltipHeight = tooltip:getHeight()

            local tooltipX = slotX - tooltipWidth - 5
            local tooltipY = slotBottomY - tooltipHeight

            tooltip:setX(tooltipX)
            tooltip:setY(tooltipY)
        end
    else
        hideTooltip(self.toolRender)
        if self.tooltipRender and self.tooltipRender ~= self.toolRender then
            hideTooltip(self.tooltipRender)
        end
    end
end
