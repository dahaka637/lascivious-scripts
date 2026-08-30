require "Hotbar/ISHotbar"
require "ISUI/ISButton"


CleanHotbarSettings = {}
CleanHotbarSettings.original_hotbar_render = nil
CleanHotbarSettings.original_reorderhotbar_render = nil
CleanHotbarSettings.original_hotbar_setSizeAndPosition = nil
CleanHotbarSettings.original_external_hotbar_setSizeAndPosition = nil
CleanHotbarSettings.original_external_getSlotIndexAt = nil
CleanHotbarSettings.settingsButton = nil

local slotBackgroundTexture = getTexture("media/ui/CleanHotBar/CleanHotbar_Slot_BG.png")
local slotItemBorderTexture = getTexture("media/ui/CleanHotBar/CleanHotbar_Slot_ItemBorder.png")

local function isReorderTheHotbarActive()
    if ReorderTheHotbar_Mod ~= nil then
        return true
    end
    if CleanHotbarReorder ~= nil and not CleanHotbarReorder.isExternalModActive then
        return true
    end
    return false
end

-- ----------------------------------------- --
-- initialise
-- ----------------------------------------- --

CleanHotbarSettingsButton = ISButton:derive("CleanHotbarSettingsButton")

function CleanHotbarSettingsButton:initialise()
    ISButton.initialise(self)
end

function CleanHotbarSettingsButton:new()
    local o = ISButton:new(0, 0, 0, 0)
    setmetatable(o, self)
    self.__index = self
    
    o.displayBackground = false
    o.buttonIcon = getTexture("media/ui/CleanHotBar/CleanHotbar_Settings_Icon.png")
    o.backgroundTex = getTexture("media/ui/CleanHotBar/CleanHotbar_Settings_BG.png")
    
    o.mouseOverHotbar = false
    o.mouseLeaveTime = 0
    o.hideDelay = 3000
    o.lastUpdateTime = 0
    o.updateIntervalMs = 100
    
    return o
end

function CleanHotbarSettingsButton:createChildren()
    ISButton.createChildren(self)
end

function CleanHotbarSettingsButton:render()
    local alpha = self:isMouseOver() and 1.0 or 0.4
    self:drawTextureScaled(self.backgroundTex, 0, 0, self.width, self.height, alpha, 0.6, 0.6, 0.6)
    
    self:drawTextureScaled(self.buttonIcon, 0, 0, self.width, self.height, 1.0, 0.6, 0.6, 0.6)
end

function CleanHotbarSettingsButton:updatePosition(hotbar)
    if not hotbar then return end
    
    local playerObj = hotbar.chr
    if not playerObj then return end

    if (playerObj:getPlayerNum() > 0) or JoypadState.players[playerObj:getPlayerNum()+1] then
        self:setVisible(false)
        return
    end
    
    if playerObj:getVehicle() and playerObj:getVehicle():isDriver(playerObj) then
        self:setVisible(false)
        return
    end
    
    local buttonSize = math.floor(hotbar.slotWidth / 2)
    local buttonX = hotbar:getX() + hotbar:getWidth()

    local slotY = hotbar:getY() + hotbar.margins + 1
    local slotCenterY = slotY + (hotbar.slotHeight / 2)

    local buttonY = slotCenterY - (buttonSize / 2)
    
    self:setX(buttonX)
    self:setY(buttonY)
    self:setWidth(buttonSize)
    self:setHeight(buttonSize)

    local mouseX, mouseY = getMouseX(), getMouseY()
    local hotbarX = hotbar:getX()
    local hotbarY = hotbar:getY()
    local hotbarWidth = hotbar:getWidth()
    local hotbarHeight = hotbar:getHeight()

    local isMouseOverHotbar = (mouseX >= hotbarX and mouseX <= hotbarX + hotbarWidth and
                              mouseY >= hotbarY and mouseY <= hotbarY + hotbarHeight)

    local isMouseOverButtonArea = (mouseX >= buttonX and mouseX <= buttonX + self:getWidth() and
                                 mouseY >= buttonY and mouseY <= buttonY + self:getHeight())

    local isMouseOver = isMouseOverHotbar or isMouseOverButtonArea
    
    if isMouseOver ~= self.mouseOverHotbar then
        self.mouseOverHotbar = isMouseOver
        if not isMouseOver then
            self.mouseLeaveTime = getTimestampMs()
        end
    end
    
    local shouldBeVisible = (self.mouseOverHotbar or (getTimestampMs() - self.mouseLeaveTime < self.hideDelay))
    
    self:setVisible(shouldBeVisible)
end

function CleanHotbarSettingsButton:onMouseUp(x, y)
    if self:isMouseOver() then
        CleanHotbarSettingsPanel.open()
        return true
    end
    return false
end

function CleanHotbarSettingsButton:requestImmediateUpdate()
    -- Force the next update pass to reposition immediately after UI changes.
    self.lastUpdateTime = 0
end

function CleanHotbarSettingsButton:update()
    -- Throttle the floating settings button refresh; layout changes still force an immediate update.
    local now = getTimestampMs()
    if self.lastUpdateTime > 0 and (now - self.lastUpdateTime) < self.updateIntervalMs then
        return
    end
    self.lastUpdateTime = now

    local hotbar = getPlayerHotbar(0)
    if not hotbar then
        self:setVisible(false)
        return
    end
    
    local isHotbarVisible = hotbar:isVisible()
    
    if not isHotbarVisible then
        self:setVisible(false)
        return
    end
    
    self:updatePosition(hotbar)
end

-- ----------------------------------------- --
-- Override
-- ----------------------------------------- --

function CleanHotbarSettings.setSizeAndPosition(self)
    CleanHotbarSettings.original_hotbar_setSizeAndPosition(self)
    
    if CleanHotbarSettings.settingsButton then
        CleanHotbarSettings.settingsButton:requestImmediateUpdate()
        CleanHotbarSettings.settingsButton:updatePosition(self)
    end
end

function CleanHotbarSettings.external_getSlotIndexAt_override(self, x, y)
    -- When Reorder The Hotbar is active, keep its reorder logic but use
    -- Clean HotBar's slot geometry so hover / drag matches the visible slots.
    local config = CHBConfig.getConfig()
    local toggleButtonSize = math.floor(self.slotWidth / 3)
    local slotStartX = self.margins + 1 + toggleButtonSize + self.slotPad

    if x >= slotStartX and x < self.width and y >= 0 and y < self.height then
        local relativeX = x - slotStartX
        local slotWidth = self.slotWidth + self.slotPad
        local slotIndex = math.floor(relativeX / slotWidth) + 1

        if not config.showEmptySlots then
            local visibleIndex = 0
            for i = 1, #self.availableSlot do
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

function CleanHotbarSettings.external_setSizeAndPosition_override(self)
    CleanHotbarSettings.original_external_hotbar_setSizeAndPosition(self)

    -- The external mod adds extra width for its own inline lock/swap buttons.
    -- Clean HotBar already exposes those controls in its settings panel, so
    -- remove that extra width to keep slot hitboxes aligned with the visuals.
    local newWidth = math.max(0, self:getWidth() - 18)
    self:setWidth(newWidth)

    if CleanHotbarSettings.settingsButton then
        CleanHotbarSettings.settingsButton:requestImmediateUpdate()
        CleanHotbarSettings.settingsButton:updatePosition(self)
    end
end

function CleanHotbarSettings.reorder_render_override(self)
    -- Intentionally unused in the external reorder path.
    -- Clean HotBar no longer wraps ISHotbar.reorder_render when
    -- Reorder The Hotbar is active, to avoid render recursion.
end

-- ----------------------------------------- --
-- initializeOverrides
-- ----------------------------------------- --

local function initializeOverrides()
    if not CleanHotbarSettings.settingsButton then
        CleanHotbarSettings.settingsButton = CleanHotbarSettingsButton:new()
        CleanHotbarSettings.settingsButton:addToUIManager()
        CleanHotbarSettings.settingsButton:requestImmediateUpdate()
    end

    if ReorderTheHotbar_Mod ~= nil then
        if not CleanHotbarSettings.original_external_hotbar_setSizeAndPosition then
            CleanHotbarSettings.original_external_hotbar_setSizeAndPosition = ISHotbar.setSizeAndPosition
            ISHotbar.setSizeAndPosition = CleanHotbarSettings.external_setSizeAndPosition_override
        end

        if not CleanHotbarSettings.original_external_getSlotIndexAt then
            CleanHotbarSettings.original_external_getSlotIndexAt = ISHotbar.getSlotIndexAt
            ISHotbar.getSlotIndexAt = CleanHotbarSettings.external_getSlotIndexAt_override
        end

        -- Do not wrap ISHotbar.reorder_render here.
        -- Reorder The Hotbar keeps full control of its own render path to avoid
        -- recursive chaining with Clean HotBar on some load orders.
    end
end

Events.OnGameStart.Add(initializeOverrides)

return CleanHotbarSettings