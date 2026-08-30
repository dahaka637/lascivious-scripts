require "ISUI/ISToolTipInv"
require "ISIL_SilencerStats"

local originalRender = ISToolTipInv.render

local function getSuppressor(item)
    if not item then
        return nil
    end

    if instanceof(item, "WeaponPart") and ISILSilencerStats.isOurSuppressor(item) then
        return item
    end

    if instanceof(item, "HandWeapon") then
        local suppressor = item:getWeaponPart("Canon")
        if ISILSilencerStats.isOurSuppressor(suppressor) then
            return suppressor
        end
    end

    return nil
end

local function getSuppressorDetails(item)
    local suppressor = getSuppressor(item)
    if not suppressor then
        return nil, nil, nil, nil
    end

    local reduction = ISILSilencerStats.getNoiseReduction(suppressor:getFullType())
    local remaining, maximum = nil, nil
    if ISILSilencerStats.isDurabilityTracked(suppressor) then
        remaining, maximum = ISILSilencerDurability.peek(suppressor)
    end

    return suppressor, reduction, remaining, maximum
end

local function getDurabilityBarColor(fraction)
    if fraction > 0.50 then
        local hc = getCore():getGoodHighlitedColor()
        return hc:getR(), hc:getG(), hc:getB()
    end
    if fraction > 0.25 then
        return 0.95, 0.75, 0.10
    end
    return 0.90, 0.15, 0.10
end

local function appendDurability(tooltip, remaining, maximum)
    local padLeft = tooltip.padLeft or 5
    local padBottom = tooltip.padBottom or 5
    local currentHeight = tooltip:getHeight()
    local fraction = math.max(0, math.min(1, remaining / maximum))
    local r, g, b = getDurabilityBarColor(fraction)

    local layout = tooltip:beginLayout()
    layout:setMinValueWidth(200)
    local layoutItem = layout:addItem()
    layoutItem:setLabel(getText("Tooltip_SuppressorCondition"), 1, 1, 1, 1)
    layoutItem:setProgress(fraction, r, g, b, 1)

    local endY = layout:render(padLeft, currentHeight - padBottom, tooltip)
    tooltip:endLayout(layout)
    tooltip:setHeight(endY + padBottom)
end

local function appendNoiseReduction(tooltip, reduction)
    local padLeft = tooltip.padLeft or 5
    local padBottom = tooltip.padBottom or 5
    local currentHeight = tooltip:getHeight()

    local layout = tooltip:beginLayout()
    local layoutItem = layout:addItem()
    layoutItem:setLabel(getText("Tooltip_ISIL_NoiseReduction"), 1, 1, 1, 1)
    layoutItem:setValue(tostring(reduction) .. "%", 1, 1, 1, 1)

    local endY = layout:render(padLeft, currentHeight - padBottom, tooltip)
    tooltip:endLayout(layout)
    tooltip:setHeight(endY + padBottom)
end

local function renderItemTooltip(tooltip, item, suppressor, reduction, remaining, maximum)
    local itemIsSuppressor = item == suppressor and instanceof(item, "WeaponPart")
    local originalTooltip = nil

    if itemIsSuppressor then
        originalTooltip = item:getTooltip()
        -- InventoryItem.DoTooltip resolves the stored value through getText()
        -- itself. Store the translation key rather than an already translated
        -- sentence, otherwise a literal percentage sign is parsed a second time.
        item:setTooltip("Tooltip_ISIL_DynamicSuppressor")
    end

    item:DoTooltip(tooltip)

    if itemIsSuppressor then
        item:setTooltip(originalTooltip)
    end

    appendNoiseReduction(tooltip, reduction)

    if remaining ~= nil and maximum ~= nil then
        appendDurability(tooltip, remaining, maximum)
    end
end

-- Durability must participate in both the measurement and draw pass. Drawing
-- after the original renderer is clipped by the already measured UI element.
-- Unrelated items still use whichever renderer was installed before this one.
function ISToolTipInv:render()
    local suppressor, reduction, remaining, maximum = getSuppressorDetails(self.item)
    if not suppressor or reduction == nil then
        return originalRender(self)
    end

    if ISContextMenu.instance and ISContextMenu.instance.visibleCheck then
        return
    end

    local mx = getMouseX() + 24
    local my = getMouseY() + 24
    if not self.followMouse then
        mx = self:getX()
        my = self:getY()
        if self.anchorBottomLeft then
            mx = self.anchorBottomLeft.x
            my = self.anchorBottomLeft.y
        end
    end

    local PADX = 0
    self.tooltip:setX(mx + PADX)
    self.tooltip:setY(my)

    self.tooltip:setWidth(50)
    self.tooltip:setMeasureOnly(true)
    renderItemTooltip(self.tooltip, self.item, suppressor, reduction, remaining, maximum)
    self.tooltip:setMeasureOnly(false)

    local myCore = getCore()
    local maxX = myCore:getScreenWidth()
    local maxY = myCore:getScreenHeight()
    local tw = self.tooltip:getWidth()
    local th = self.tooltip:getHeight()

    self.tooltip:setX(math.max(0, math.min(mx + PADX, maxX - tw - 1)))
    if not self.followMouse and self.anchorBottomLeft then
        self.tooltip:setY(math.max(0, math.min(my - th, maxY - th - 1)))
    else
        self.tooltip:setY(math.max(0, math.min(my, maxY - th - 1)))
    end

    if self.contextMenu and self.contextMenu.joyfocus then
        local playerNum = self.contextMenu.player
        self.tooltip:setX(getPlayerScreenLeft(playerNum) + 60)
        self.tooltip:setY(getPlayerScreenTop(playerNum) + 60)
    elseif self.contextMenu and self.contextMenu.currentOptionRect then
        if self.contextMenu.currentOptionRect.height > 32 then
            self:setY(my + self.contextMenu.currentOptionRect.height)
        end
        self:adjustPositionToAvoidOverlap(self.contextMenu.currentOptionRect)
    end

    self:setX(self.tooltip:getX() - PADX)
    self:setY(self.tooltip:getY())
    self:setWidth(tw + PADX)
    self:setHeight(th)

    if self.followMouse and self.contextMenu == nil then
        self:adjustPositionToAvoidOverlap({
            x = mx - 24 * 2,
            y = my - 24 * 2,
            width = 24 * 2,
            height = 24 * 2,
        })
    end

    self:drawRect(0, 0, self.width, self.height,
        self.backgroundColor.a, self.backgroundColor.r,
        self.backgroundColor.g, self.backgroundColor.b)
    self:drawRectBorder(0, 0, self.width, self.height,
        self.borderColor.a, self.borderColor.r,
        self.borderColor.g, self.borderColor.b)
    renderItemTooltip(self.tooltip, self.item, suppressor, reduction, remaining, maximum)
end
