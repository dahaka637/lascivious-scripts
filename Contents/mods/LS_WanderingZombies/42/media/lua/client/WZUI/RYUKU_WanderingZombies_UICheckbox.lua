require("WZUI/RYUKU_WanderingZombies_UIControl")

WZUI_CHECKBOX_TEXTURE = getTexture("media/ui/inventoryPanes/Tickbox_Tick.png")
WZUI_CHECKBOX_COLOUR_ENABLED = { r = 0, g = 1, b = 0, a = 1 }
WZUI_CHECKBOX_COLOUR_DISABLED = { r = 0, g = 0.4, b = 0, a = 1 }

---@class WZUICheckbox : WZUIControl
---@field private _option zombie.SandboxOptions.BooleanSandboxOption
---@field private _checked boolean
---@field private _background table
---@field private _border table
---@field private _colour table
WZUICheckbox = WZUIControl:derive("__wzuiCheckbox")

-----------------
-- Constructor --
-----------------

---@param option zombie.config.ConfigOption
---@return WZUICheckbox?
function WZUICheckbox:new(option)
    local obj = {}
    setmetatable(obj, self)
    self.__index = self

    if option:getType() ~= "boolean" then
        print("WZUICheckbox.new - unexpected type - " .. option:getType())
        return nil
    end

    ---@cast option zombie.SandboxOptions.BooleanSandboxOption
    ---@cast obj WZUICheckbox
    obj._option = option
    obj._checked = option:getValue()
    obj:updateAppearance()
    return obj
end

----------------
-- Initialise --
----------------

---@param panel SandboxOptionsScreenPanel?
function WZUICheckbox:init(panel)
    WZUIControl.init(self, panel)
    self:setWidth(self:getHeight())
end

----------------
-- Appearance --
----------------

---@private
function WZUICheckbox:updateAppearance()
    self._background = self:getStateAppearanceValue("WZUI_BACKGROUND_COLOUR")
    if self._option:getDefaultValue() ~= self._checked then
        self._colour = self:getStateAppearanceValue("WZUI_COLOUR_NONDEFAULT")
        self._border = self._colour
    else
        self._colour = self:getStateAppearanceValue("WZUI_CHECKBOX_COLOUR")
        self._border = self:getStateAppearanceValue("WZUI_BORDER_COLOUR")
    end
end

-------------------
-- Enabled State --
-------------------

---@param state boolean
function WZUICheckbox:setEnabled(state)
    WZUIControl.setEnabled(self, state)
    self:updateAppearance()
end

--------------
-- Mouse Up --
--------------

function WZUICheckbox:onMouseUp(x, y)
    if self._enabled and self._uiObject:isMouseOver() then
        self._checked = not self._checked
        self:updateAppearance()
        self._option:setValue(self._checked)
    end
end

-----------
-- Value --
-----------

---@param enabled boolean
function WZUICheckbox:setValue(enabled)
    self._checked = enabled
end

---@return boolean
function WZUICheckbox:getValue()
    return self._checked
end

-------------
-- Tooltip --
-------------

function WZUICheckbox:getTooltip()
    return self._option:getTooltip()
end

----------------
-- Option Key --
----------------

function WZUICheckbox:getOptionKey()
    return self._option:getName()
end

---------------
-- Prerender --
---------------

function WZUICheckbox:prerender()
    if not WZUIControl.prerender(self) then return end

    self:drawRect(0, 0, self:getWidth(), self:getHeight(), self._background)
    self:drawBorder(0, 0, self:getWidth(), self:getHeight(), 1, self._border)
    if self._checked then
        self:drawTexture(WZUI_CHECKBOX_TEXTURE, 0, 0, self:getWidth(), self:getHeight(), self._colour)
    end
end

--------------------
-- Update Options --
--------------------

---@param options zombie.SandboxOptions
function WZUICheckbox:updateOptions(options)
    local optionName = self._option:getName()
    local value = self:getValue()
    local opt = options:getOptionByName(optionName) --[[@as zombie.config.BooleanConfigOption]]
    opt:setValue(value)
    self:setSandboxVar(optionName, value)
end

-------------------------
-- Update From Options --
-------------------------

---@param options zombie.SandboxOptions
function WZUICheckbox:updateFromOptions(options)
    local opt = options:getOptionByName(self._option:getName()) --[[@as zombie.config.BooleanConfigOption]]
    self._checked = opt:getValue()
    self:updateAppearance()
    self._option:setValue(self._checked)
end
