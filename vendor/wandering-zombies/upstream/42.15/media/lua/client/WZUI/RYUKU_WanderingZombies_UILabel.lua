require("WZUI/RYUKU_WanderingZombies_UIControl")

WZUI_LABEL_FONT = UIFont.Medium

---@class WZUILabel : WZUIControl
---@field private _text string
---@field private _colour table
---@field public searchFound boolean
---@field private _lastSearchState boolean
WZUILabel = WZUIControl:derive("__wzuiLabel")

-----------------
-- Constructor --
-----------------

---@param option zombie.config.ConfigOption
---@return WZUILabel
function WZUILabel:new(option)
    local obj = {}
    setmetatable(obj, self)
    self.__index = self

    ---@cast obj WZUILabel
    obj._text = option:getTranslatedName()
    obj:updateAppearance()

    local textMan = getTextManager()
    obj:setWidth(textMan:MeasureStringX(WZUI_LABEL_FONT, obj._text))
    obj:setHeight(textMan:MeasureStringY(WZUI_LABEL_FONT, obj._text))
    return obj
end

----------------
-- Appearance --
----------------

function WZUILabel:updateAppearance()
    self._colour = self:getStateAppearanceValue("WZUI_TEXT_COLOUR")
end

-------------------
-- Enabled State --
-------------------

---@param state boolean
function WZUILabel:setEnabled(state)
    WZUIControl.setEnabled(self, state)
    self:updateAppearance()
end

-----------
-- Value --
-----------

--- SandboxOptionsScreen:doSearch() compatibility
---@return string
function WZUILabel:getName()
    return self._text
end

---@return string
function WZUILabel:getValue()
    return self._text
end

function WZUILabel:onMouseUp(x, y)
    self._color = { r = 1, g = 0, b = 0, a = 1 }
end

---------------
-- Prerender --
---------------

function WZUILabel:prerender()
    if not WZUIControl.prerender(self) then return end
    self:drawText(WZUI_LABEL_FONT, self._text, self._colour, 0, 0)
end

------------
-- Update --
------------

function WZUILabel:update()
    if self._lastSearchState ~= self.searchFound then
        if self.searchFound then self._colour = self:getStateAppearanceValue("WZUI_SEARCH_COLOUR")
        else self._colour = self:getStateAppearanceValue("WZUI_TEXT_COLOUR") end
    end

    self._lastSearchState = self.searchFound
end
