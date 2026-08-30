require("WZUI/RYUKU_WanderingZombies_UIControl")

WZUI_DROPDOWN_FONT = UIFont.Small
WZUI_DROPDOWN_SPACE = 3
WZUI_DROPDOWN_FOCUS = { r = 0.4, g = 0.4, b = 0.4, a = 1 }

-----------------------
-- WZUIDropdownPopup --
-----------------------

---@class WZUIDropdownPopup : WZUIControl
---@field private _background table
---@field private _border table
---@field private _colour table
---@field private _focus table
---@field private _dropdown WZUIDropdown
---@field private _options string[]
---@field private _textHeight number
---@field private _yOffset number
---@field private _focusedIndex integer
WZUIDropdownPopup = WZUIControl:derive("__wzuiDropdownPopup")

---------------------
-- Show/Hide Popup --
---------------------

---@param wzuiDropdown WZUIDropdown
function WZUIDropdownPopup:show(wzuiDropdown)
    self._dropdown = wzuiDropdown
    wzuiDropdown:setExpanded(true)

    self._options = wzuiDropdown:getOptions()
    self._textHeight = wzuiDropdown:getOptionsHeight() / #self._options
    self._yOffset = wzuiDropdown:getOptionYOffset()
    self._focusedIndex = 0
    self:setX(wzuiDropdown._uiObject:getAbsoluteX())
    self:setY(wzuiDropdown._uiObject:getAbsoluteY() + wzuiDropdown:getHeight())
    self:setHeight(wzuiDropdown:getOptionsHeight())
    if self._uiObject == nil then
        self:setWidth(wzuiDropdown:getWidth())
        self:init()
        self._background = WZUI_BACKGROUND_COLOUR_ENABLED
        self._border = WZUI_BORDER_COLOUR_ENABLED
        self._colour = WZUI_TEXT_COLOUR_ENABLED
        self._focus = WZUI_DROPDOWN_FOCUS
    end

    self._uiObject:setAlwaysOnTop(true)
    self._uiObject:setCapture(true)
    UIManager.AddUI(self._uiObject)
end

function WZUIDropdownPopup:hide()
    self._dropdown:setExpanded(false)
    self._dropdown = nil
    self._options = nil
    self._uiObject:setAlwaysOnTop(false)
    self._uiObject:setCapture(false)
    UIManager.RemoveElement(self._uiObject)
end

-----------------
-- On Mouse Up --
-----------------

function WZUIDropdownPopup:onMouseUp(x, y)
    if x <= 0 or y <= 0 or x > self:getWidth() or y > self:getHeight() then return self:hide() end
    self._dropdown:setSelected(math.ceil(y / self._textHeight))
    self:hide()
end

-------------------
-- On Mouse Move --
-------------------

local absX, absY
function WZUIDropdownPopup:onMouseMove(x, y)
    x = getMouseX()
    y = getMouseY()
    absX = self._uiObject:getAbsoluteX()
    absY = self._uiObject:getAbsoluteY()
    if x <= absX or y <= absY or x > absX + self:getWidth() or y > absY + self:getHeight() then
        self._focusedIndex = 0
        return
    end

    self._focusedIndex = math.ceil((y - absY) / self._textHeight)
end

--------------------
-- On Mouse Wheel --
--------------------

function WZUIDropdownPopup:onMouseWheel()
    if not self._uiObject:isMouseOver() then self:hide() end
end

---------------
-- Prerender --
---------------

local optionY
function WZUIDropdownPopup:prerender()
    if self._options == nil then return end
    self:drawRect(0, 0, self:getWidth(), self:getHeight(), self._background)
    self:drawBorder(0, 0, self:getWidth(), self:getHeight(), 1, self._border)

    for i = 1, #self._options do
        optionY = (i - 1) * self._textHeight + self._yOffset
        if i == self._focusedIndex then
            self:drawRect(0, optionY, self:getWidth(), self._textHeight, self._focus)
        end

        self:drawText(WZUI_DROPDOWN_FONT, self._options[i], self._colour, WZUI_DROPDOWN_SPACE, optionY)
    end
end

------------------
-- WZUIDropdown --
------------------

---@class WZUIDropdown : WZUIControl
---@field private _sandboxOption zombie.SandboxOptions.EnumSandboxOption
---@field private _background table
---@field private _border table
---@field private _colour table
---@field private _selectedIndex integer
---@field private _options string[]
---@field private _optionsHeight number
---@field private _optionYOffset number
---@field private _expanded boolean
WZUIDropdown = WZUIControl:derive("__wzuiDropdown")

-----------------
-- Constructor --
-----------------

---@param option zombie.config.ConfigOption
---@return WZUIDropdown?
function WZUIDropdown:new(option)
    local obj = {}
    setmetatable(obj, self)
    self.__index = self

    if option:getType() ~= "enum" then
        print("WZUIDropdown.new - unexpected type - " .. option:getType())
        return nil
    end

    ---@cast option zombie.SandboxOptions.EnumSandboxOption
    ---@cast obj WZUIDropdown
    obj._sandboxOption = option
    obj._selectedIndex = option:getValue()
    obj:updateAppearance()

    local key = option:getName()
    obj._options = {}
    for i = 1, option:getNumValues() do
        table.insert(obj._options, option:getValueTranslationByIndex(i))
    end

    return obj
end

----------------
-- Initialise --
----------------

---@param panel SandboxOptionsPanel?
function WZUIDropdown:init(panel)
    WZUIControl.init(self, panel)

    self._optionsHeight = #self._options * self:getHeight()
    self._optionYOffset = (self:getHeight() - getTextManager():MeasureStringY(WZUI_DROPDOWN_FONT, "A")) / 2
end

--------------
-- Mouse Up --
--------------

function WZUIDropdown:onMouseUp(x, y)
    if self._expanded then WZUIDropdownPopup:hide()
    elseif self._enabled then WZUIDropdownPopup:show(self) end
end

-------------------
-- Enabled State --
-------------------

---@param state boolean
function WZUIDropdown:setEnabled(state)
    WZUIControl.setEnabled(self, state)
    self._background = self:getStateAppearanceValue("WZUI_DROPDOWN_BACKGROUND")
    self:updateAppearance()
end

-----------
-- Value --
-----------

---@return integer
function WZUIDropdown:getValue()
    return self._selectedIndex
end

-------------
-- Tooltip --
-------------

---@return string?
function WZUIDropdown:getTooltip()
    return self._sandboxOption:getTooltip()
end

----------------
-- Option Key --
----------------

function WZUIDropdown:getOptionKey()
    return self._sandboxOption:getName()
end

----------------
-- Appearance --
----------------

function WZUIDropdown:updateAppearance()
    self._background = self:getStateAppearanceValue("WZUI_BACKGROUND_COLOUR")
    if self._sandboxOption:getDefaultValue() ~= self._selectedIndex then
        self._colour = self:getStateAppearanceValue("WZUI_COLOUR_NONDEFAULT")
        self._border = self._colour
    else
        self._colour = self:getStateAppearanceValue("WZUI_TEXT_COLOUR")
        self._border = self:getStateAppearanceValue("WZUI_BORDER_COLOUR")
    end
end

-------------
-- Options --
-------------

---@return string[]
function WZUIDropdown:getOptions()
    return self._options
end

---@return number
function WZUIDropdown:getOptionsHeight()
    return self._optionsHeight
end

---@return number
function WZUIDropdown:getOptionYOffset()
    return self._optionYOffset
end

---@param idx integer
function WZUIDropdown:setSelected(idx)
    self._selectedIndex = idx
    self:updateAppearance()
    self._sandboxOption:setValue(self._selectedIndex)
end

---@param state boolean
function WZUIDropdown:setExpanded(state)
    self._expanded = state
end

---------------
-- Prerender --
---------------

function WZUIDropdown:prerender()
    if not WZUIControl.prerender(self) then return end

    self:drawRect(0, 0, self:getWidth(), self:getHeight(), self._background)
    self:drawBorder(0, 0, self:getWidth(), self:getHeight(), 1, self._border)
    self:drawText(
        WZUI_DROPDOWN_FONT,
        self._options[self._selectedIndex],
        self._colour,
        WZUI_DROPDOWN_SPACE, self._optionYOffset
    )
end

--------------------
-- Update Options --
--------------------

---@param options zombie.SandboxOptions
function WZUIDropdown:updateOptions(options)
    local optionName = self._sandboxOption:getName()
    local value = self:getValue()
    local opt = options:getOptionByName(optionName) --[[@as zombie.config.EnumConfigOption]]
    opt:setValue(value)
    self:setSandboxVar(optionName, value)
end

-------------------------
-- Update From Options --
-------------------------

---@param options zombie.SandboxOptions
function WZUIDropdown:updateFromOptions(options)
    local opt = options:getOptionByName(self._sandboxOption:getName()) --[[@as zombie.config.EnumConfigOption]]
    self:setSelected(opt:getValue())
end
