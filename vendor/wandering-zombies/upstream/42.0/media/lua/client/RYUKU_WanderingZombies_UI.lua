-- this is hacky as fuck

if isServer() then return end
require("OptionScreens/SandboxOptions")
require("OptionScreens/ServerSettingsScreen")
require("ISUI/AdminPanel/ISServerSandboxOptionsUI")

----------------------
-- WZComboBox (lsp) --
----------------------
---@class WZComboBox: ISComboBox
---@field wzName string
---@field wzLabel ISLabel
---@field wzMinLabel ISLabel
---@field wzMaxLabel ISLabel
---@field wzMinControl ISTextEntryBox
---@field wzMaxControl ISTextEntryBox
---@field wzChildren WZComboBox[]
---@field wzOthers ISUIElement[]
---@field wzEditable boolean?
---@field wzOld_onChange function?
WZComboBox = {}
function WZComboBox:wzOld_prerender() end


---------------------
-- Line Separators --
---------------------

local CONTROL_GAP
local LINE_HEIGHT = 2
local TITLE_FONT = UIFont.Cred1

local function separatorRender(self)
    local startX = -(self.x - self:getParent().wzLineX) -- where the label text would start
    local y = self.height + LINE_HEIGHT
    local endX = self:getParent().wzLineWidth - self:getParent().wzLineX

    self:drawRect(
        startX, y,
        endX, LINE_HEIGHT,
        1.0, 0.2, 0.2, 0.2
    )

    if self.wzTitle ~= nil then
        self:drawText(self.wzTitle,
            startX + (endX / 2) - self.wzTextLength / 2,
            y - self.wzTextHeight + LINE_HEIGHT,
            0.2, 0.5, 1, 1, TITLE_FONT
        )
    end
end

local function doSeparatorPatch(panel, k, v)
    if string.find(k, "GroupTitle") == nil then return false end

    v:setVisible(false)

    local checkbox = panel.controls[k]
    checkbox.render = separatorRender
    checkbox.wzTitle = v.name
    checkbox.wzTextHeight = getTextManager():MeasureStringY(TITLE_FONT, v.name)
    checkbox.wzTextLength = getTextManager():MeasureStringX(TITLE_FONT, v.name)
    return true
end

-----------------------------------
-- Wander/Homing/Flee Visibility --
-----------------------------------

---@param label ISLabel
---@param editable boolean
local function setLabelColour(label, editable)
    if editable then label.a = 1
    else label.a = 0.2 end
end

---@param control ISBaseObject
---@param editable boolean
local function setEditable(control, editable)
    if control.Type == "ISComboBox" then
        ---@cast control WZComboBox
        control.disabled = not editable
    elseif control.Type == "ISTextEntryBox" then
        ---@cast control ISTextEntryBox
        control:setEditable(editable)
    else
        ---@cast control ISTickBox
        control.enable = editable
    end
end

---@param isComboBox WZComboBox
---@param editable boolean
---@param toggleSelf boolean?
local function dropdownToggleEdit(isComboBox, editable, toggleSelf)
    if toggleSelf then
        setEditable(isComboBox, editable)
        setEditable(isComboBox.wzMinControl, editable)
        setLabelColour(isComboBox.wzLabel, editable)
        setLabelColour(isComboBox.wzMinLabel, editable)

        if isComboBox.selected > 1 then
            setEditable(isComboBox.wzMaxControl, editable)
            setLabelColour(isComboBox.wzMaxLabel, editable)
        end

        return
    end

    for _, v in pairs(isComboBox.wzChildren) do
        setEditable(v, editable)
        setEditable(v.wzMinControl, editable)
        setLabelColour(v.wzLabel, editable)
        setLabelColour(v.wzMinLabel, editable)

        if v.selected > 1 then
            setEditable(v.wzMaxControl, editable)
            setLabelColour(v.wzMaxLabel, editable)
        end
    end

    for _, v in pairs(isComboBox.wzOthers) do
        if v.Type == "ISLabel" then setLabelColour(v --[[@as ISLabel]], editable)
        else setEditable(v, editable) end
    end
end

---@param target table
---@param combo WZComboBox
---@param args_a any
---@param args_b any
local function dropdownOnChange(target, combo, args_a, args_b)
    if combo.wzOld_onChange ~= nil then combo:wzOld_onChange(target, combo, args_a, args_b) end
    if combo.wzMaxControl:isEditable() == (combo.selected > 1) then return end

    setEditable(combo.wzMaxControl, combo.selected > 1)
    setLabelColour(combo.wzMaxLabel, combo.selected > 1)
end

local groupVisible, controlText

---@param self WZComboBox
local function dropdownPrerender(self)
    self:wzOld_prerender()
    if self.wzEditable == nil then
        self.wzEditable = true

        -- set Max controls to the correct initial state
        dropdownOnChange(self.target, self, self.onChangeArgs[1], self.onChangeArgs[2])
        for _, v in pairs(self.wzChildren) do
            dropdownOnChange(v.target, v, v.onChangeArgs[1], v.onChangeArgs[2])
        end
    end

    groupVisible = self.wzMinControl:isEditable()
    if groupVisible then
        -- group should only be considered visible if the value is valid (>0)
        controlText = self.wzMinControl:getText()
        groupVisible = controlText ~= "0" and controlText ~= ""
        if not groupVisible and self.selected > 1 then
            controlText = self.wzMaxControl:getText()
            groupVisible = controlText ~= "0" and controlText ~= ""
        end
    end

    -- prevent unnecessary calls to editable toggle
    if self.wzEditable == groupVisible then return end
    self.wzEditable = groupVisible

    dropdownToggleEdit(self, groupVisible)
end

local function doGroupVisibilityPatch(panel, name)
    -- grab the page key
    -- ignore WZUI
    local pageKey
    for k, _ in pairs(panel.labels) do
        if string.find(k, "WZUI") == nil then
            pageKey = k:match("(.+)%..+")
            break
        end
    end

    -- group together Dropdowns with Min/Max values
    -- hook the Dropdown's onChange to toggle Max visibility
    -- if the Dropdown is "Chance", hook the prerender to toggle group visibility
    local parentDropdown, dropdown, key
    for _, v in pairs({ "Wander", "Homing", "Flee" }) do
        parentDropdown = nil
        for _, vv in pairs({ "Chance", "StartHour", "TotalHours", "CooldownHours", "Radius" }) do
            dropdown = nil

            if v ~= "Wander" or vv ~= "Radius" then
                for _, vvv in pairs({ "Dropdown", "Min", "Max" }) do
                    key = pageKey .. "." .. v .. vv .. vvv
                    if dropdown == nil then
                        dropdown = panel.controls[key]
                        if dropdown.wzLabel ~= nil then break end

                        dropdown.wzLabel = panel.labels[key]
                        dropdown.wzName = pageKey
                        dropdown.wzPanel = panel
                        dropdown.wzOld_onChange = dropdown.onChange
                        dropdown.onChange = dropdownOnChange

                        if parentDropdown == nil then
                            parentDropdown = dropdown
                            dropdown.wzOld_prerender = dropdown.prerender
                            dropdown.prerender = dropdownPrerender
                            dropdown.wzChildren = {}
                        else
                            table.insert(parentDropdown.wzChildren, dropdown)
                        end
                    else
                        dropdown["wz" .. vvv .. "Label"] = panel.labels[key]
                        dropdown["wz" .. vvv .. "Control"] = panel.controls[key]
                    end
                end
            end
        end

        if parentDropdown ~= nil then
            parentDropdown.wzOthers = {}
            for _, vv in pairs({ "RadiusInterrupt", "Destructive" }) do
                if vv ~= "RadiusInterrupt" or v ~= "Wander" then
                    key = pageKey .. "." .. v .. vv
                    table.insert(parentDropdown.wzOthers, panel.labels[key])
                    table.insert(parentDropdown.wzOthers, panel.controls[key])
                end
            end
        end
    end
end

----------------------
-- Horde Visibility --
----------------------

local function checkboxChangeOption(target, option, selected, args_a, args_b, checkbox)
    if checkbox.wzOld_changeOption ~= nil then
        checkbox.wzOld_changeOption(target, option, selected, args_a, args_b, checkbox)
    end

    local toggleVis
    for k, v in pairs(checkbox.wzPanel.controls) do
        if v ~= checkbox then
            -- dropdown/min/max/destructive/interrupt needs to be handled differently
            toggleVis = true
            for _, vv in pairs({ "Dropdown", "Min", "Max", "Destructive", "RadiusInterrupt" }) do
                toggleVis = k:match(".+%..+" .. vv) == nil
                if not toggleVis then
                    if vv == "Dropdown" and v.wzChildren ~= nil then dropdownToggleEdit(v, selected, true) end
                    break
                end
            end

            if toggleVis then
                setEditable(v, selected)
                if string.find(k, "GroupTitle") == nil then setLabelColour(checkbox.wzPanel.labels[k], selected) end
            end
        end
    end
end

local function doHordeVisibilityPatch(panel)
    local pageKey = "WZHordeZombie" .. "."
    local checkbox = panel.controls[pageKey .. "Hordes"]
    if checkbox.wzPanel ~= nil then return end

    checkbox.wzPanel = panel
    checkbox.wzOld_changeOption = checkbox.changeOptionMethod
    checkbox.changeOptionMethod = checkboxChangeOption

    checkbox.changeOptionMethod(
        checkbox.changeOptionTarget,
        checkbox.mouseOverOption,
        checkbox.selected[1],
        checkbox.changeOptionArgs[1],
        checkbox.changeOptionArgs[2],
        checkbox
    )
end

--------------
-- UI Setup --
--------------

local function isInTable(v, t)
    for _, tv in pairs(t) do
        if v == tv then return true end
    end

    return false
end

---@param page table
---@param panel ISPanel
local function uiSetup(page, panel)
    -- remove transparency, it looks bad
    panel.backgroundColor = { r = 0, g = 0, b = 0, a = 1 }

    -- find out if CONTROL_GAP needs to be initialised
    -- CONTROL_GAP is used for fixing the admin panel Y bug
    local initGap = panel.labels == nil and page.name == getText("Sandbox_WZLoneZombie")
    if initGap then CONTROL_GAP = nil end

    -- wzLineWidth = x pos + width (right edge) of the control with the greatest length
    -- used for group title/headers
    panel.wzLineWidth = nil
    local controlEndX
    for _, v in pairs(panel.controls) do
        if initGap then
            if CONTROL_GAP == nil then CONTROL_GAP = v.y
            else
                CONTROL_GAP = (v.y - CONTROL_GAP) - v.height
                initGap = false
            end
        end

        controlEndX = v.x + v.width
        if panel.wzLineWidth == nil or controlEndX > panel.wzLineWidth then panel.wzLineWidth = controlEndX end
    end

    if panel.labels == nil then
        -- admin panel panel.labels patch
        local usedKeys = {}
        panel.labels = {}
        for _, v in pairs(panel.children) do
            if v.Type == "ISLabel" then
                for k, _ in pairs(panel.controls) do
                    if not isInTable(k, usedKeys) then
                        panel.labels[k] = v
                        table.insert(usedKeys, k)
                        break
                    end
                end
            end
        end

        -- admin panel Y patch
        local lastY, label
        for k, control in pairs(panel.controls) do
            if lastY ~= nil then
                control:setY(lastY + control.height + CONTROL_GAP)
                label = panel.labels[k]
                label:setY(lastY + control.height + CONTROL_GAP)
            end

            lastY = control:getY()
            panel:setScrollHeight(lastY + CONTROL_GAP + control.height)
        end
    end

    -- setup WZUI checkboxes to be titles/headers for the grouped settings
    -- wzLineX = the x position of the label with the greatest length (furthest left)
    panel.wzLineX = nil
    for k, v in pairs(panel.labels) do
        if panel.wzLineX == nil or v.x < panel.wzLineX then panel.wzLineX = v.x end
        doSeparatorPatch(panel, k, v)
    end

    if page.name == getText("Sandbox_WZLoneZombie") or page.name == getText("Sandbox_WZHordeZombie") then
        doGroupVisibilityPatch(panel, page.name)
        if page.name == getText("Sandbox_WZHordeZombie") then doHordeVisibilityPatch(panel) end
    end
end

---------------
-- Solo Hook --
---------------

local old_soloCreatePanel = SandboxOptionsScreen.createPanel
local function soloCreatePanel(self, page)
    local panel = old_soloCreatePanel(self, page)
    if string.find(page.name, getText("Sandbox_WanderingZombies")) == nil then return panel end

    uiSetup(page, panel)
    return panel
end

SandboxOptionsScreen.createPanel = soloCreatePanel

----------------
-- Admin Hook --
----------------

local old_adminCreateChildren = ISServerSandboxOptionsUI.createChildren
local function adminCreateChildren(self)
    old_adminCreateChildren(self)

    local item
    for _, lbitem in pairs(self.listbox.items) do
        item = lbitem.item
        if string.find(item.page.name, getText("Sandbox_WanderingZombies")) then
            uiSetup(item.page, item.panel)
        end
    end
end

ISServerSandboxOptionsUI.createChildren = adminCreateChildren

---------------
-- Host Hook --
---------------

local old_aboutToShow = ServerSettingsScreen.aboutToShow
local function aboutToShow(self)
    old_aboutToShow(self)

    for _, v in pairs(self.pageEdit.listbox.items) do
        if string.find(v.text, getText("Sandbox_WanderingZombies")) ~= nil then
            uiSetup(v.item.page, v.item.panel)
        end
    end
end

ServerSettingsScreen.aboutToShow = aboutToShow

