require("WZUI/RYUKU_WanderingZombies_UITextbox")
require("WZUI/RYUKU_WanderingZombies_UIDropdown")
require("WZUI/RYUKU_WanderingZombies_UICheckbox")


WZUI_GROUP_FONT = UIFont.Cred1
WZUI_GROUP_COLOUR = { r = 0.2, g = 0.5, b = 1, a = 1 }
WZUI_GROUP_SEPARATOR_COLOUR = { r = 0.2, g = 0.2, b = 0.2, a = 1 }
WZUI_GROUP_SEPARATOR_THICKNESS = 2
WZUI_GROUP_SEPARATOR_TRAIL_SPACE = 5
WZUI_GROUP_LABEL_WIDTH = 0
WZUI_GROUP_LABEL_SPACE = 5
WZUI_GROUP_CONTROL_WIDTH = 150
WZUI_GROUP_CONTROL_SPACE = 4

---@class WZUIGroup : WZUIControl
---@field private _screen SandboxOptionsScreen|ISServerSandboxOptionsUI|ServerSettingsScreen.Page3
---@field private _settingsFromUI function
---@field private _settingsToUI function
---@field private _title string
---@field private _titleHeight number
---@field private _titleWidth number
---@field private _titleX number
---@field private _separatorWidth number
---@field private _separatorX number
---@field private _children WZUIControl[]
---@field private _childY number
---@field private _childHeight number
---@field private _panelWidth number
WZUIGroup = WZUIControl:derive("__wzuiGroup")

-----------------
-- Constructor --
-----------------

---@param screen SandboxOptionsScreen|ISServerSandboxOptionsUI|ServerSettingsScreen.Page3
---@param panel SandboxOptionsScreenPanel
---@param title string
---@return WZUIGroup
function WZUIGroup:new(screen, panel, title)
    local obj = WZUIControl:new()
    setmetatable(obj, self)
    self.__index = self

    ---@cast obj WZUIGroup
    obj._screen = screen
    obj._panel = panel
    obj._title = getText(title)
    obj._children = {}

    local textMan = getTextManager()
    obj._titleWidth = textMan:MeasureStringX(WZUI_GROUP_FONT, obj._title)
    obj._titleHeight = textMan:MeasureStringY(WZUI_GROUP_FONT, obj._title)
    obj._titleX = -obj._titleWidth / 2
    obj._childY = obj._titleHeight + WZUI_GROUP_SEPARATOR_THICKNESS + WZUI_GROUP_SEPARATOR_TRAIL_SPACE
    obj._childHeight = 0
    obj._panelWidth = obj._panel:getWidth()
    obj:setX(obj._panelWidth / 2)
    return obj
end

----------------
-- Initialise --
----------------

function WZUIGroup:init()
    WZUIControl.init(self, self._panel)
    self._separatorWidth = WZUI_GROUP_LABEL_WIDTH + WZUI_GROUP_CONTROL_WIDTH + WZUI_GROUP_LABEL_SPACE
    self._separatorX = -(self._separatorWidth / 2)

    local wzuiLabel
    for idx, wzuiControl in pairs(self._children) do
        wzuiControl:setX(self:getX() + self._separatorX + WZUI_GROUP_LABEL_WIDTH + WZUI_GROUP_LABEL_SPACE)
        wzuiControl:setY(self:getY() + self._childY + (idx - 1) * (self._childHeight + WZUI_GROUP_CONTROL_SPACE))
        wzuiControl:setWidth(WZUI_GROUP_CONTROL_WIDTH)
        wzuiControl:init(self._panel)

        wzuiLabel = wzuiControl:getLabel()
        if wzuiLabel ~= nil then
            wzuiLabel:setX(self:getX() + self._separatorX)
        end
    end

    local screen = self._screen
    if screen.settingsFromUIAux then
        ---@cast screen ServerSettingsScreen.Page3
        self:settingsFromUIAuxHook(screen)
        self:settingsToUIAuxHook(screen)
    else
        ---@cast screen SandboxOptionsScreen|ISServerSandboxOptionsUI
        self:settingsFromUIHook(screen)
        self:settingsToUIHook(screen)
    end
end

----------------
-- Reposition --
----------------

---@param delta number
function WZUIGroup:reposition(delta)
    self:setX(self:getX() + delta)
    local wzuiLabel
    for _, wzuiControl in pairs(self._children) do
        wzuiControl:setX(wzuiControl:getX() + delta)
        wzuiLabel = wzuiControl:getLabel()
        if wzuiLabel ~= nil then wzuiLabel:setX(wzuiLabel:getX() + delta) end
    end
end

------------------
-- Group Height --
------------------

function WZUIGroup:getGroupHeight()
    local textMan = getTextManager()
    return self._titleHeight + WZUI_GROUP_SEPARATOR_THICKNESS + WZUI_GROUP_SEPARATOR_TRAIL_SPACE +
        #self._children * (textMan:MeasureStringY(WZUI_LABEL_FONT, "A") + WZUI_GROUP_CONTROL_SPACE)
end

-------------------
-- Enabled State --
-------------------

---@param state boolean
function WZUIGroup:setEnabled(state)
    WZUIControl.setEnabled(self, state)
    for _, wzuiControl in pairs(self._children) do
        if wzuiControl._groupToggle then wzuiControl:setEnabled(state) end
    end
end

--------------
-- Children --
--------------

local typeToControl = {
    double = WZUITextbox,
    integer = WZUITextbox,
    string = WZUITextbox,
    enum = WZUIDropdown,
    boolean = WZUICheckbox,
}

---@param option zombie.config.ConfigOption
---@return WZUIControl?
function WZUIGroup:createChild(option)
    if option == nil then
        print("WZUIGroup.createChild - missing option")
        return nil
    end

    local controlType = typeToControl[option:getType()]
    if controlType == nil then
        print("WZUIGroup.createChild - unknown type - " .. option:getType())
        return nil
    end

    local key = option:getName()
    local wzuiControl = controlType:new(option)
    if wzuiControl == nil then return nil end

    local wzuiLabel = WZUILabel:new(option)
    wzuiControl:setLabel(wzuiLabel)

    -- panel requires 'controls' and 'labels' tables
    self._panel.controls[key] = wzuiControl --[[@as ISUIElement]]
    self._panel.labels[key] = wzuiLabel --[[@as ISLabel]]

    -- Remove old controls from screen
    if self._screen.settingsFromUIAux then self._screen.controls["Sandbox"][key] = nil
    else self._screen.controls[key] = nil end

    self._childHeight = math.max(self._childHeight, wzuiLabel:getHeight())
    WZUI_GROUP_LABEL_WIDTH = math.max(WZUI_GROUP_LABEL_WIDTH, wzuiLabel:getWidth())

    table.insert(self._children, wzuiControl)
    return wzuiControl
end

---@param aIdx integer
---@param bIdx integer
function WZUIGroup:swapChildren(aIdx, bIdx)
    local a = self._children[aIdx]
    local b = self._children[bIdx]
    if a == nil or b == nil then return end

    self._children[bIdx] = a
    self._children[aIdx] = b
end

---@return WZUIControl[]
function WZUIGroup:getChildren()
    return self._children
end

------------------------
-- settingsToUI hooks --
------------------------

---@param screen SandboxOptionsScreen|ISServerSandboxOptionsUI
function WZUIGroup:settingsToUIHook(screen)
    self._settingsToUI = screen.settingsToUI
    screen.settingsToUI = function(obj, options)
        for _, wzuiControl in pairs(self._children) do
            wzuiControl:updateFromOptions(options)
        end

        self._settingsToUI(obj, options)
    end
end

---@param screen ServerSettingsScreen.Page3
function WZUIGroup:settingsToUIAuxHook(screen)
    self._settingsToUI = screen.settingsToUIAux
    screen.settingsToUIAux = function(obj, category, options)
        if category == "Sandbox" then
            for _, wzuiControl in pairs(self._children) do
                wzuiControl:updateFromOptions(options)
            end
        end

        self._settingsToUI(obj, category, options)
    end
end

--------------------------
-- settingsFromUI hooks --
--------------------------

---@param screen SandboxOptionsScreen|ISServerSandboxOptionsUI
function WZUIGroup:settingsFromUIHook(screen)
    self._settingsFromUI = screen.settingsFromUI
    screen.settingsFromUI = function(obj, options)
        if options ~= obj.nonDefaultOptions then
            for _, wzuiControl in pairs(self._children) do
                wzuiControl:updateOptions(options)
            end
        end

        self._settingsFromUI(obj, options)
    end
end

---@param screen ServerSettingsScreen.Page3
function WZUIGroup:settingsFromUIAuxHook(screen)
    self._settingsFromUI = screen.settingsFromUIAux
    screen.settingsFromUIAux = function(obj, category, options)
        if category == "Sandbox" and options ~= obj.nonDefaultOptions.Sandbox then
            for _, wzuiControl in pairs(self._children) do
                wzuiControl:updateOptions(options)
            end
        end

        self._settingsFromUI(obj, category, options)
    end
end

---------------
-- Prerender --
---------------

function WZUIGroup:prerender()
    -- admin panel adjusts the panel width at some point ...
    if self._panel:getWidth() ~= self._panelWidth then
        self:reposition((self._panel:getWidth() / 2) - (self._panelWidth /2))
        self._panelWidth = self._panel:getWidth()
    end

    WZUIControl.prerender(self)
    self:drawText(WZUI_GROUP_FONT, self._title, WZUI_GROUP_COLOUR, self._titleX, 0)
    self:drawRect(
        self._separatorX, self._titleHeight,
        self._separatorWidth, WZUI_GROUP_SEPARATOR_THICKNESS,
        WZUI_GROUP_SEPARATOR_COLOUR
    )
end
