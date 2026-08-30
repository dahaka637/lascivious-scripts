require("WZUI/RYUKU_WanderingZombies_UIControl")

WZUI_TOOLTIP_FONT = UIFont.Small
WZUI_TOOLTIP_MAX_WIDTH = 300
WZUI_TOOLTIP_SPACE = 6
WZUI_TOOLTIP_BACKGROUND = { r = 0, g = 0, b = 0, a = 0.85 }
WZUI_TOOLTIP_KEY_COLOUR = { r = 0.4, g = 0.4, b = 0.4, a = 1 }

---@class WZUITooltip: WZUIControl
---@field private _background table
---@field private _border table
---@field private _colour table
---@field private _space number
---@field private _wzuiControl WZUIControl
---@field private _optionKey string
---@field private _tooltip string?
---@field private _textHeight number
---@field private _text { x: number, y: number, text: string, colour: table? }[]
WZUITooltip = WZUIControl:derive("__wzuiTooltip")

---------------
-- Show/Hide --
---------------

---@param wzuiControl WZUIControl
function WZUITooltip:show(wzuiControl)
    self._wzuiControl = wzuiControl
    self._tooltip = wzuiControl:getTooltip()
    if self._tooltip == nil then return end

    if self._uiObject == nil then
        self:init()
        self._background = WZUI_TOOLTIP_BACKGROUND
        self._border = WZUI_BORDER_COLOUR_ENABLED

        self._space = WZUI_TOOLTIP_SPACE / 2
        self._textHeight = getTextManager():MeasureStringY(WZUI_TOOLTIP_FONT, "A")
        self._uiObject:setConsumeMouseEvents(false)
    end

    self._optionKey = "CONFIG: " .. wzuiControl:getOptionKey()
    self:setWidth(0)
    self:process()
    self:setX(wzuiControl._uiObject:getAbsoluteX() - (self:getWidth() - wzuiControl:getWidth()) / 2)
    self:setY(wzuiControl._uiObject:getAbsoluteY() + wzuiControl:getHeight() + 4)
    if self:getY() + self:getHeight() > getCore():getScreenHeight() then
        self:setY(wzuiControl._uiObject:getAbsoluteY() - self:getHeight() - 4)
    end

    self._uiObject:setAlwaysOnTop(true)
    UIManager.AddUI(self._uiObject)
end

function WZUITooltip:hide()
    self._tooltip = nil
    self._wzuiControl = nil
    self._text = nil
    self._uiObject:setAlwaysOnTop(false)
    UIManager.RemoveElement(self._uiObject)
end

-------------
-- Control --
-------------

function WZUITooltip:getControl()
    return self._wzuiControl
end

-------------
-- Process --
-------------

function WZUITooltip:process()
    if self._tooltip == nil or #self._tooltip == 0 then return end

    self._text = {}
    self._tooltip = self._tooltip:gsub("\\n", "\n")
    local textMan = getTextManager()
    local textX, textY = self._space, self._textHeight + self._space
    local posX = 1
    local text = ""
    local char
    local colourMatch, colour
    local width
    local lastSpace
    while posX <= #self._tooltip do
        char = self._tooltip:sub(posX, posX)
        if char == "/" then
            colourMatch = string.sub(self._tooltip, posX, posX + 6)
            if string.match(colourMatch, "/%x%x%x%x%x%x") ~= nil then
                table.insert(self._text, { x = textX, y = textY, text = text, colour = colour })
                self._tooltip = self._tooltip:gsub("/%x%x%x%x%x%x", "", 1)
                colour = {
                    r = tonumber(string.sub(colourMatch, 2, 3), 16) / 255,
                    g = tonumber(string.sub(colourMatch, 4, 5), 16) / 255,
                    b = tonumber(string.sub(colourMatch, 6, 7), 16) / 255,
                    a = 1
                }

                textX = textX + textMan:MeasureStringX(WZUI_TOOLTIP_FONT, text)
                text = ""
                char = ""

                posX = posX - 1
            end
        end

        if posX == #self._tooltip then
            table.insert(self._text, { x = textX, y = textY, text = text .. char, colour = colour })
            textY = textY + self._textHeight
        elseif char == "\n" then
            table.insert(self._text, { x = textX, y = textY, text = text, colour = colour })
            colour = nil
            textY = textY + self._textHeight
            textX = self._space
            text = ""
        elseif char ~= "" then
            width = textMan:MeasureStringX(WZUI_TOOLTIP_FONT, text .. char)
            self:setWidth(math.min(WZUI_TOOLTIP_MAX_WIDTH, math.max(self:getWidth(), textX + width + WZUI_TOOLTIP_SPACE)))
            if textX + width > WZUI_TOOLTIP_MAX_WIDTH - WZUI_TOOLTIP_SPACE then
                lastSpace = string.find(text, " [^ ]*$")
                if lastSpace ~= nil then
                    table.insert(self._text, { x = textX, y = textY, text = text:sub(1, lastSpace), colour = colour })
                    text = text:sub(lastSpace + 1) .. char
                else
                    table.insert(self._text, { x = textX, y = textY, text = text, colour = colour })
                    text = char
                end

                colour = nil
                textY = textY + self._textHeight
                textX = self._space
            else
                if char == " " then lastSpace = posX end
                text = text .. char
            end
        end

        posX = posX + 1
    end

    self._tooltip = nil
    self:setHeight(textY + self._textHeight)
end

------------------------
-- Mouse Move Outside --
------------------------

function WZUITooltip:onMouseMoveOutside(x, y)
    if not self._wzuiControl._uiObject:isMouseOver() then self:hide() end
end

----------------
-- Mouse Move --
----------------

function WZUITooltip:onMouseMove(x, y)
    if self._uiObject:isMouseOver() then self:hide() end
end

---------------
-- Prerender --
---------------

local text
function WZUITooltip:prerender()
    if self._text == nil then return end

    WZUIControl.prerender(self)
    self:drawRect(0, 0, self:getWidth(), self:getHeight(), self._background)
    self:drawBorder(0, 0, self:getWidth(), self:getHeight(), 1, self._border)

    self._colour = WZUI_TEXT_COLOUR_ENABLED
    for i = 1, #self._text do
        text = self._text[i]
        if text.colour ~= nil then self._colour = text.colour end
        self:drawText(WZUI_TOOLTIP_FONT, text.text, self._colour, text.x, text.y)
    end

    self:drawText(
        WZUI_TOOLTIP_FONT, self._optionKey, WZUI_TOOLTIP_KEY_COLOUR,
        self._space, self:getHeight() - self._textHeight - self._space
    )
end
