require("WZUI/RYUKU_WanderingZombies_UITooltip")

WZUI_TEXTBOX_FONT = UIFont.Medium

---@class WZUITextbox : WZUIControl
---@field private _textOption zombie.SandboxOptions.StringSandboxOption
---@field private _numberOption zombie.SandboxOptions.DoubleSandboxOption
---@field private _integerOption zombie.SandboxOptions.IntegerSandboxOption
---@field private _text string
---@field private _background table
---@field private _border table
---@field private _numbers boolean
---@field private _double boolean
WZUITextbox = WZUIControl:derive("__wzuiTextbox")

-----------------
-- Constructor --
-----------------

---@param option zombie.config.ConfigOption
---@return WZUITextbox?
function WZUITextbox:new(option)
    local obj = {}
    setmetatable(obj, self)
    self.__index = self

    ---@cast obj WZUITextbox
    if option:getType() == "double" then
        ---@cast option zombie.SandboxOptions.DoubleSandboxOption
        obj._numberOption = option
        obj._double = true
    elseif option:getType() == "integer" then
        ---@cast option zombie.SandboxOptions.IntegerSandboxOption
        obj._integerOption = option
        obj._numbers = true
    elseif option:getType() == "string" then
        ---@cast option zombie.SandboxOptions.StringSandboxOption
        obj._textOption = option
    else
        print("WZUITextbox.new - unexpected type - " .. option:getType())
        return nil
    end

    obj._text = option:getValueAsString()
    obj:updateAppearance()
    return obj
end

----------------
-- Initialise --
----------------

---@param panel SandboxOptionsPanel?
function WZUITextbox:init(panel)
    self._uiObject = UITextBox2.new(
        WZUI_TEXTBOX_FONT,
        self:getX(), self:getY(), self:getWidth(), self:getHeight(),
        self._text,
        false
    )

    WZUIControl.init(self, panel)
    self._uiObject:setTable(self)
    self._uiObject:setEditable(true)
    self._uiObject:SetText(self._text)
    self._uiObject:setOnlyNumbers(self._numbers)
    self:setRGBA(WZUI_TEXT_COLOUR_ENABLED)
end

-------------------
-- Enabled State --
-------------------

---@param state boolean
function WZUITextbox:setEnabled(state)
    WZUIControl.setEnabled(self, state)
    self:updateAppearance()
    self._uiObject:setEditable(self._enabled)
end

-----------
-- Value --
-----------

---@return string|number|nil
function WZUITextbox:getValue()
    if self._numbers or self._double then return tonumber(self._text) end
    return self._text
end

---@return number
function WZUITextbox:getNumberValue()
    if self._numbers or self._double then return tonumber(self._text) or 0 end
    return 0
end

function WZUITextbox:clampValue()
    local min, max
    if self._numbers then
        min = self._integerOption:getMin()
        max = self._integerOption:getMax()
    elseif self._double then
        min = self._numberOption:getMin()
        max = self._numberOption:getMax()
    else
        return
    end

    self._text = tostring(math.min(max, math.max(min, tonumber(self._text) or 0)))
    self._uiObject:SetText(self._text)
end

-------------
-- Tooltip --
-------------

---@return string?
function WZUITextbox:getTooltip()
    if self._textOption then return self._textOption:getTooltip()
    elseif self._numberOption then return self._numberOption:getTooltip()
    elseif self._integerOption then return self._integerOption:getTooltip() end
end

----------------
-- Option Key --
----------------

---@return string
function WZUITextbox:getOptionKey()
    if self._textOption then return self._textOption:getName()
    elseif self._numberOption then return self._numberOption:getName()
    elseif self._integerOption then return self._integerOption:getName() end

    return ""
end

----------------
-- Appearance --
----------------

function WZUITextbox:updateAppearance()
    local default
    if self._numberOption then default = self._numberOption:getDefaultValue()
    elseif self._integerOption then default = self._integerOption:getDefaultValue()
    else default = self._textOption:getDefaultValue() end

    self._background = self:getStateAppearanceValue("WZUI_BACKGROUND_COLOUR")
    if tostring(default) ~= self._text then
        self._border = self:getStateAppearanceValue("WZUI_COLOUR_NONDEFAULT")
        self:setRGBA(self._border)
    else
        self:setRGBA(self:getStateAppearanceValue("WZUI_TEXT_COLOUR"))
        self._border = self:getStateAppearanceValue("WZUI_BORDER_COLOUR")
    end
end

---@param colour table
function WZUITextbox:setRGBA(colour)
    if self._uiObject ~= nil then self._uiObject:setTextRGBA(colour.r, colour.g, colour.b, colour.a) end
end

--------------------
-- On Text Change --
--------------------

---@private
function WZUITextbox:onTextChange()
    local text = self._uiObject:getInternalText()
    if self._double then
        if text ~= nil and #text > 0 then
            if text:match("%d+") == nil and text:match("%d+%.%d*") == nil then
                self._uiObject:SetText(self._text)
                return
            end
        end
    end

    self._text = text
    self:updateAppearance()
end

-------------------------
-- On Mouse Up Outside --
-------------------------

function WZUITextbox:onLostFocus()
    self:clampValue()
    self:updateAppearance()

    local option = self._numberOption or self._integerOption
    if option ~= nil then option:setValue(tonumber(self._text) or option:getDefaultValue())
    elseif self._textOption then
        self._textOption:setValue(self._text)
    end
end

---------------
-- Prerender --
---------------

function WZUITextbox:prerender()
    if not WZUIControl.prerender(self) then return end

    self:drawRect(0, 0, self:getWidth(), self:getHeight(), self._background)
    self:drawBorder(0, 0, self:getWidth(), self:getHeight(), 1, self._border)
end

--------------------
-- Update Options --
--------------------

---@param options zombie.SandboxOptions
function WZUITextbox:updateOptions(options)
    local opt
    local optionName
    local value
    if self._numberOption then
        optionName = self._numberOption:getName()
        opt = options:getOptionByName(optionName) --[[@as zombie.config.DoubleConfigOption]]
        value = self._numberOption:getValue()
    elseif self._integerOption then
        optionName = self._integerOption:getName()
        opt = options:getOptionByName(optionName) --[[@as zombie.config.IntegerConfigOption]]
        value = self._integerOption:getValue()
    elseif self._textOption then
        optionName = self._textOption:getName()
        opt = options:getOptionByName(self._textOption:getName()) --[[@as zombie.config.StringConfigOption]]
        value = self._textOption:getValue()
    end

    opt:setValue(value)
    self:setSandboxVar(optionName, value)
end

-------------------------
-- Update From Options --
-------------------------

---@param options zombie.SandboxOptions
function WZUITextbox:updateFromOptions(options)
    local opt
    if self._numberOption then opt = options:getOptionByName(self._numberOption:getName())
    elseif self._integerOption then opt = options:getOptionByName(self._integerOption:getName())
    elseif self._textOption then opt = options:getOptionByName(self._textOption:getName()) end

    if opt ~= nil then
        ---@cast opt zombie.config.ConfigOption
        self._text = opt:getValueAsString()
        self:onLostFocus()
    end
end
