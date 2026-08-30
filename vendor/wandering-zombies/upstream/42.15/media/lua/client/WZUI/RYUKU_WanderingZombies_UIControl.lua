WZUI_PAIRED_LABEL_SPACE = 10
WZUI_COLOUR_NONDEFAULT_ENABLED = { r = 1, g = 1, b = 0, a = 1 }
WZUI_COLOUR_NONDEFAULT_DISABLED = { r = 0.4, g = 0.4, b = 0, a = 1 }
WZUI_TEXT_COLOUR_ENABLED = { r = 1, g = 1, b = 1, a = 1 }
WZUI_TEXT_COLOUR_DISABLED = { r = 0.4, g = 0.4, b = 0.4, a = 1 }
WZUI_BORDER_COLOUR_ENABLED = { r = 0.4, g = 0.4, b = 0.4, a = 1 }
WZUI_BORDER_COLOUR_DISABLED = { r = 0.2, g = 0.2, b = 0.2, a = 1 }
WZUI_BACKGROUND_COLOUR_ENABLED = { r = 0, g = 0, b = 0, a = 1 }
WZUI_BACKGROUND_COLOUR_DISABLED = { r = 0, g = 0, b = 0, a = 1 }
WZUI_SEARCH_COLOUR_ENABLED = { r = 0, g = 1, b = 0, a = 1 }
WZUI_SEARCH_COLOUR_DISABLED = { r = 0, g = 0.4, b = 0, a = 1 }

---@class SandboxOptionsScreenPanel : ISPanel
---@field public wzYScroll number?

---@class WZUIControl
---@field protected _uiObject table?
---@field private _x integer
---@field private _y integer
---@field private _width integer
---@field private _height integer
---@field private _canToggle boolean
---@field protected _groupToggle boolean
---@field private _condition function
---@field protected _toggleFn function?
---@field protected _enabled boolean
---@field protected _label WZUILabel?
---@field protected _panel SandboxOptionsScreenPanel?
WZUIControl = {}

-----------------
-- Inheritance --
-----------------

---@return WZUIControl
function WZUIControl:derive(newType)
    local obj = {}
    setmetatable(obj, self)
    self.__index = self

    ---@cast obj WZUIControl
    obj._x = 0
    obj._y = 0
    obj._width = 0
    obj._height = 0
    obj._canToggle = true
    obj._groupToggle = true
    obj._enabled = true
    obj[newType] = true
    return obj
end

-----------------
-- Constructor --
-----------------

---@return WZUIControl
function WZUIControl:new()
    local obj = {}
    setmetatable(obj, self)
    self.__index = self

    ---@cast obj WZUIControl
    obj._groupToggle = true
    obj._enabled = true
    return obj
end

----------------
-- Initialise --
----------------

---@param panel SandboxOptionsScreenPanel?
function WZUIControl:init(panel)
    if self._uiObject == nil then self._uiObject = UIElement.new(self) end

    if self._label ~= nil then
        self._height = self._label._height
        self._label._x = self._x - self._label._width
        self._label._y = self._y
        self._label:init(panel)
        if panel == nil then self._uiObject:AddChild(self._label._uiObject) end
    end

    self._uiObject:setX(self._x)
    self._uiObject:setY(self._y)
    self._uiObject:setWidth(self._width)
    self._uiObject:setHeight(self._height)
    if panel ~= nil then panel.javaObject:AddChild(self._uiObject) end

    self._panel = panel
end

--------------
-- Position --
--------------

---@param x integer
function WZUIControl:setX(x)
    self._x = x
    if self._uiObject ~= nil then self._uiObject:setX(self._x) end
end

---@param y integer
function WZUIControl:setY(y)
    self._y = y
    if self._uiObject ~= nil then self._uiObject:setY(self._y) end
end

function WZUIControl:setPos(x, y)
    self:setX(x)
    self:setY(y)
end

---@return integer
function WZUIControl:getX()
    return self._x
end

---@return integer
function WZUIControl:getY()
    return self._y
end

--------------------
-- Width / Height --
--------------------

---@param w integer
function WZUIControl:setWidth(w)
    self._width = w
    if self._uiObject ~= nil then self._uiObject:setWidth(self._width) end
end

---@param h integer
function WZUIControl:setHeight(h)
    self._height = h
    if self._uiObject ~= nil then self._uiObject:setHeight(self._height) end
end

---@return integer
function WZUIControl:getWidth()
    return self._width
end

---@return integer
function WZUIControl:getHeight()
    return self._height
end

-------------------
-- Enabled State --
-------------------

---@return boolean
function WZUIControl:isEnabled()
    return self._enabled
end

---@param state boolean
function WZUIControl:canToggle(state)
    self._canToggle = state
end

---@param state boolean
function WZUIControl:toggleWithGroup(state)
    self._groupToggle = state
end

---@param fn function
function WZUIControl:setEnabledCondition(fn)
    self._condition = fn
end

---@return boolean
function WZUIControl:hasCondition()
    return self._condition ~= nil
end

---@param state boolean
function WZUIControl:setEnabled(state)
    if not self._canToggle then return end
    self._enabled = state
    if self._label ~= nil then self._label:setEnabled(state) end
end

---@param globalKey string
---@return any
function WZUIControl:getStateAppearanceValue(globalKey)
    return (self._enabled and _G[globalKey .. "_ENABLED"]) or _G[globalKey .. "_DISABLED"]
end

--------------------
-- Draw Functions --
--------------------

local r, g, b, a
local function extractColour(colour)
    r = colour.r
    g = colour.g
    b = colour.b
    a = colour.a
end

function WZUIControl:drawRect(x, y, w, h, colour)
    extractColour(colour)
    self._uiObject:DrawTextureScaledColor(nil, x, y, w, h, r, g, b, a)
end

function WZUIControl:drawBorder(x, y, w, h, t, colour)
    extractColour(colour)
    self._uiObject:DrawTextureScaledColor(nil, x, y, w, t, r, g, b, a)
    self._uiObject:DrawTextureScaledColor(nil, x, y + h, w, t, r, g, b, a)
    self._uiObject:DrawTextureScaledColor(nil, x, y + t, t, h - t, r, g, b, a)
    self._uiObject:DrawTextureScaledColor(nil, x + w - t, y + t, t, h - t, r, g, b, a)
end

function WZUIControl:drawText(font, text, colour, x, y)
    extractColour(colour)
    self._uiObject:DrawText(font, text, x, y, r, g, b, a)
end

function WZUIControl:drawTexture(texture, x, y, w, h, colour)
    extractColour(colour)
    self._uiObject:DrawTextureScaledColor(texture, x, y, w, h, r, g, b, a)
end

------------------
-- Paired Label --
------------------

---@param wzuiLabel WZUILabel
function WZUIControl:setLabel(wzuiLabel)
    self._label = wzuiLabel
end

---@return WZUILabel?
function WZUIControl:getLabel()
    return self._label
end

-------------
-- Tooltip --
-------------

---@return string?
function WZUIControl:getTooltip()
    return nil
end

----------------
-- Option Key --
----------------

---@return string
function WZUIControl:getOptionKey()
    return ""
end

----------------------------------------
-- SandboxOptionScreen.settingsFromUI --
----------------------------------------

---@param options zombie.SandboxOptions
function WZUIControl:updateOptions(options)

end

---@param optionName string
---@param value any
function WZUIControl:setSandboxVar(optionName, value)
    if not isClient() and GameWindow.isIngameState() then
        local optKey = optionName:match("(%w+)%.")
        local optValue = optionName:match("%w+%.(%w+)")
        SandboxVars[optKey][optValue] = value
    end
end

---------------------------------------
-- SandboxOptionsScreen.settingsToUI --
---------------------------------------

---@param options zombie.SandboxOptions
function WZUIControl:updateFromOptions(options)

end

---------------
-- Prerender --
---------------

local state, forceToggle, condition, yScroll
---@return boolean
function WZUIControl:prerender()
    if self._condition ~= nil then
        state = self:_condition()
        if state ~= self._enabled then self:setEnabled(state) end
    end

    if self._panel ~= nil then
        yScroll = self._panel.wzYScroll or 0
        if yScroll + self._panel.height < self._y or yScroll > self._y + self._height then
            return false
        end
    end

    if self:getTooltip() ~= nil and WZUITooltip:getControl() ~= self and self._uiObject:isMouseOver() then
        WZUITooltip:show(self)
    end

    return true
end
