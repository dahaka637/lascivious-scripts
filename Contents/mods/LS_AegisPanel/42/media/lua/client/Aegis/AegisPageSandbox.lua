-- Sandbox editor: real vanilla categories, every option editable inline
require "Aegis/AegisWindow"
require "ISUI/ISComboBox"
require "ISUI/ISTextEntryBox"
require "ISUI/ISLabel"
require "OptionScreens/ServerSettingsScreen"

AegisPageSandbox = ISPanel:derive("AegisPageSandbox")

local NAV_W = 200
local ROW_H = 34
local NAV_ROW_H = 32
-- the vanilla vertical scroll bar is 17 wide and sits flush on the right
-- edge of its scroll area (ISScrollBar.lua:276). Controls have to end
-- BEFORE it, otherwise a long value runs underneath it, the spawn zone
-- names field for example
local SCROLLBAR_W = 17

-- ------------------------------------------------------------------
-- Category nav list, child of the left AegisScrollArea
-- ------------------------------------------------------------------
local NavList = ISPanel:derive("AegisSandboxNavList")

function NavList:new(x, y, w, categories)
    local o = ISPanel:new(x, y, w, math.max(1, #categories) * NAV_ROW_H)
    setmetatable(o, self)
    self.__index = self
    o.background = false
    o.categories = categories
    o.active = 1
    o.hoverT = {}
    return o
end

function NavList:prerender()
    local c = Aegis.col
    for i, cat in ipairs(self.categories) do
        local y = (i - 1) * NAV_ROW_H
        local hovered = self:isMouseOver() and self:getMouseY() >= y and self:getMouseY() < y + NAV_ROW_H
        self.hoverT[i] = Aegis.glide(self.hoverT[i] or 0, hovered and 1 or 0, 0.35)
        local active = self.active == i
        if active then
            Aegis.roundRect(self, 0, y + 2, self.width, NAV_ROW_H - 4, 8, 1, c.card)
            Aegis.roundRect(self, 0, y + 7, 3, NAV_ROW_H - 14, 1, 1, c.gold)
        elseif self.hoverT[i] > 0.01 then
            Aegis.roundRect(self, 0, y + 2, self.width, NAV_ROW_H - 4, 8, 0.5 * self.hoverT[i], c.card)
        end
        Aegis.text(self, Aegis.fitText(cat.name, UIFont.Small, self.width - 24), 14,
            y + math.floor((NAV_ROW_H - Aegis.fontH(UIFont.Small)) / 2), UIFont.Small,
            active and c.text or c.muted)
    end
end

function NavList:onMouseUp(x, y)
    local i = math.floor(y / NAV_ROW_H) + 1
    local cat = self.categories[i]
    if cat then
        Aegis.sound()
        self.active = i
        if self.onSelect then self.onSelect(self.owner, cat.pageIndex) end
    end
end

-- ------------------------------------------------------------------
-- Page
-- ------------------------------------------------------------------

function AegisPageSandbox.create(window, x, y, w, h)
    local o = ISPanel:new(x, y, w, h)
    setmetatable(o, AegisPageSandbox)
    AegisPageSandbox.__index = AegisPageSandbox
    o.background = false
    o.window = window
    o.pages = nil
    o.touched = {}
    o.categoryPanels = {}
    o.activeIndex = 1
    return o
end

-- Take vanilla categories + translations + tooltips as-is, just link them
-- to our own options copy (name is the shared key)
function AegisPageSandbox:buildData()
    if self.pages then return end
    self.options = SandboxOptions.new()
    self.options:copyValuesFrom(getSandboxOptions())
    local byName = {}
    for i = 1, self.options:getNumOptions() do
        local opt = self.options:getOptionByIndex(i - 1)
        byName[opt:getName()] = opt
    end
    local raw = ServerSettingsScreen.getSandboxSettingsTable()
    self.pages = {}
    for _, page in ipairs(raw) do
        local settings = {}
        for _, setting in ipairs(page.settings) do
            local opt = byName[setting.name]
            if opt then
                setting.opt = opt
                table.insert(settings, setting)
            end
        end
        if #settings > 0 then
            table.insert(self.pages, { name = page.name, settings = settings })
        end
    end
end

function AegisPageSandbox:createChildren()
    local pad = 20
    local innerX = pad + 14
    local innerW = self.width - innerX * 2
    self:buildData()

    self.fullBtn = AegisButton:new(innerX + innerW - 150, pad + 4, 150, 30, getText("UI_Aegis_FullEditor"), "gear", self, AegisPageSandbox.onFullEditor)
    self:addChild(self.fullBtn)
    self.applyBtn = AegisButton:new(innerX + innerW - 150 - 12 - 170, pad + 4, 170, 30, getText("UI_Aegis_Apply"), "check", self, AegisPageSandbox.onApply)
    self.applyBtn.style = "gold"
    self:addChild(self.applyBtn)

    -- search belongs above the category list, not in the title row
    local navY = pad + 46
    self.search = ISTextEntryBox:new("", innerX, navY, NAV_W, 28)
    self.search:initialise()
    self.search:instantiate()
    self.search.font = UIFont.Small
    self.search:setClearButton(true)
    self.search:setPlaceholderText(getText("UI_Aegis_SearchCategory"))
    local page = self
    self.search.onTextChange = function() page:rebuildNav() end
    self:addChild(self.search)

    local listY = navY + 38
    local navH = self.height - listY - pad
    self.navArea = AegisScrollArea:new(innerX, listY, NAV_W, navH)
    self:addChild(self.navArea)

    self.contentX = innerX + NAV_W + 16
    self.contentW = innerW - NAV_W - 16
    self.contentY = navY
    self.contentH = self.height - navY - pad

    self:rebuildNav()
    self:selectCategory(self.pages[1] and 1 or nil)
    self:updateApply()
end

function AegisPageSandbox:rebuildNav()
    local needle = string.lower(self.search:getInternalText() or "")
    local cats = {}
    for i, p in ipairs(self.pages) do
        if needle == "" or string.find(string.lower(p.name), needle, 1, true) then
            table.insert(cats, { name = p.name, pageIndex = i })
        end
    end
    if self.navList then
        self.navArea:removeChild(self.navList)
    end
    self.navList = NavList:new(0, 0, NAV_W - 14, cats)
    self.navList.owner = self
    self.navList.onSelect = AegisPageSandbox.selectCategory
    -- if the active category drops out of the filter, switch to the first visible one
    local stillActive = false
    for _, cat in ipairs(cats) do
        if cat.pageIndex == self.activeIndex then
            stillActive = true
            break
        end
    end
    if not stillActive and cats[1] then
        self:selectCategory(cats[1].pageIndex)
    end
    for i, cat in ipairs(cats) do
        if cat.pageIndex == self.activeIndex then self.navList.active = i end
    end
    self.navArea:addChild(self.navList)
    self.navArea:setScrollHeight(self.navList.height)
end

function AegisPageSandbox:selectCategory(pageIndex)
    if not pageIndex then return end
    if self.activePanel then self.activePanel:setVisible(false) end
    self.activeIndex = pageIndex
    self.activePanel = self:buildCategoryPanel(pageIndex)
    self.activePanel:setVisible(true)
end

-- ------------------------------------------------------------------
-- Category panel: per row a label + matching live control,
-- built once and reused afterwards
-- ------------------------------------------------------------------

local function enumOptionLabel(setting, idx)
    if setting.values and setting.values[idx] then return setting.values[idx] end
    return tostring(idx)
end

function AegisPageSandbox:buildCategoryPanel(idx)
    if self.categoryPanels[idx] then return self.categoryPanels[idx] end
    local cat = self.pages[idx]
    local w = self.contentW
    local panel = AegisScrollArea:new(self.contentX, self.contentY, w, self.contentH)
    panel:setVisible(false)
    self:addChild(panel)

    -- everything stays left of the scroll bar
    local usableW = w - SCROLLBAR_W
    local labelW = math.floor((usableW - 24) * 0.5)
    local ctrlX = 14 + labelW + 14
    local ctrlW = usableW - ctrlX - 14
    local y = 6
    local page = self

    for _, setting in ipairs(cat.settings) do
        local opt = setting.opt
        local otype = opt:getType()
        local label = setting.translatedName or setting.name
        local tooltip = setting.tooltip

        if otype == "boolean" then
            local t = AegisToggle:new(14, y, usableW - 28, ROW_H, label, nil, page, AegisPageSandbox.onRowToggle)
            t.settingRef = setting
            t:setChecked(opt:getValue() == true)
            t.tooltip = tooltip
            panel:addChild(t)
        else
            -- trim long mod names, full name goes into the control tooltip
            local shown = Aegis.fitText(label, UIFont.Small, labelW - 6)
            if shown ~= label then
                tooltip = tooltip and (label .. "\n" .. tooltip) or label
            end
            local lbl = ISLabel:new(14, y + math.floor((ROW_H - 16) / 2), 16, shown,
                Aegis.col.text.r, Aegis.col.text.g, Aegis.col.text.b, 1, UIFont.Small, true)
            panel:addChild(lbl)

            if otype == "enum" then
                local combo = ISComboBox:new(ctrlX, y + math.floor((ROW_H - 24) / 2), ctrlW, 24, page, AegisPageSandbox.onRowCombo)
                combo:initialise()
                combo.settingRef = setting
                local num = opt:getNumValues()
                for i = 1, num do
                    combo:addOption(enumOptionLabel(setting, i))
                end
                combo.selected = opt:getValue()
                if tooltip then combo.tooltip = { defaultTooltip = tooltip } end
                panel:addChild(combo)
            else
                local entry = ISTextEntryBox:new("", ctrlX, y + math.floor((ROW_H - 24) / 2), ctrlW, 24)
                entry:initialise()
                entry:instantiate()
                entry.font = UIFont.Small
                entry.settingRef = setting
                entry:setOnlyNumbers(otype == "double" or otype == "integer")
                local v
                if otype == "double" or otype == "integer" then
                    v = opt:getValueAsString()
                else
                    v = tostring(opt:getValue())
                end
                entry:setText(v)
                entry.tooltip = tooltip
                entry.onTextChange = function() AegisPageSandbox.onRowEntry(page, entry) end
                panel:addChild(entry)
            end
        end
        y = y + ROW_H + 6
    end
    panel:setScrollHeight(y)
    self.categoryPanels[idx] = panel
    return panel
end

-- ------------------------------------------------------------------
-- Editing
-- ------------------------------------------------------------------

function AegisPageSandbox:markTouched(setting)
    self.touched[setting.name] = true
    self:updateApply()
end

function AegisPageSandbox.onRowToggle(self, checked, toggle)
    toggle.settingRef.opt:setValue(checked == true)
    self:markTouched(toggle.settingRef)
end

function AegisPageSandbox.onRowCombo(self, combo)
    combo.settingRef.opt:setValue(combo.selected)
    self:markTouched(combo.settingRef)
end

function AegisPageSandbox.onRowEntry(self, entry)
    local setting = entry.settingRef
    local otype = setting.opt:getType()
    local ok = pcall(function()
        if otype == "double" or otype == "integer" then
            setting.opt:parse(entry:getInternalText())
        else
            setting.opt:setValue(entry:getInternalText())
        end
    end)
    entry:setValid(ok)
    if ok then self:markTouched(setting) end
end

function AegisPageSandbox:updateApply()
    local n = 0
    for _ in pairs(self.touched) do n = n + 1 end
    self.applyBtn:setEnabled(n > 0 and Aegis.hasCap("SandboxOptions"))
    self.applyBtn.label = getText("UI_Aegis_Apply") .. (n > 0 and (" (" .. n .. ")") or "")
end

function AegisPageSandbox.onApply(self)
    if isClient() then
        self.options:sendToServer()
    else
        for i = 1, self.options:getNumOptions() do
            local opt = self.options:getOptionByIndex(i - 1)
            getSandboxOptions():set(opt:getName(), opt:getValue())
        end
    end
    -- reparse loot distributions and clutter, like the vanilla editor
    IsoWorld.parseDistributions()
    pcall(function() StoryClutter.Init() end)
    -- sendToServer is a pure vanilla channel, the log entry goes through the relay
    local names = {}
    for name in pairs(self.touched) do table.insert(names, name) end
    table.sort(names)
    if #names > 0 then
        Aegis.logAction("sandbox", "Sandbox changed (" .. #names .. "): " .. table.concat(names, ", "))
    end
    self.touched = {}
    self:updateApply()
    Aegis.showToast(getText("UI_Aegis_SandboxApplied"))
end

-- A resize tears the page down and builds it again. Without this the
-- editor came back on the first category every time, and any pending edit
-- was gone with it: the options copy lives on the page object, so it died
-- with the old instance while the admin was only dragging the window edge
--. Category, search text and unapplied changes all travel
function AegisPageSandbox:saveState()
    local names = {}
    for name in pairs(self.touched) do table.insert(names, name) end
    return {
        activeIndex = self.activeIndex,
        search = self.search and self.search:getInternalText() or "",
        options = self.options,
        touched = names,
    }
end

function AegisPageSandbox:restoreState(state)
    if type(state) ~= "table" then return end
    -- the edited copy comes back as a whole, so unapplied values survive.
    -- buildData already ran in createChildren, its settings still point at
    -- the OLD copy, so the option references have to be rewired
    if state.options then
        self.options = state.options
        local byName = {}
        for i = 1, self.options:getNumOptions() do
            local opt = self.options:getOptionByIndex(i - 1)
            byName[opt:getName()] = opt
        end
        for _, page in ipairs(self.pages or {}) do
            for _, setting in ipairs(page.settings) do
                if byName[setting.name] then setting.opt = byName[setting.name] end
            end
        end
    end
    if type(state.touched) == "table" then
        self.touched = {}
        for _, name in ipairs(state.touched) do self.touched[name] = true end
    end
    if self.search and type(state.search) == "string" and state.search ~= "" then
        self.search:setText(state.search)
    end
    self:rebuildNav()
    local idx = tonumber(state.activeIndex)
    if idx and self.pages[idx] then
        -- the panels were built with the old width, drop them so the
        -- restored category is laid out for the new size. DROP means
        -- remove as children too: clearing only the cache left the old
        -- panels attached and the visible one kept drawing underneath
        -- the rebuilt category, two option sets interleaved on screen
        for _, panel in pairs(self.categoryPanels or {}) do
            panel:setVisible(false)
            self:removeChild(panel)
        end
        self.categoryPanels = {}
        self.activePanel = nil
        self:selectCategory(idx)
        for i, cat in ipairs(self.navList.categories or {}) do
            if cat.pageIndex == idx then self.navList.active = i end
        end
    end
    self:updateApply()
end

function AegisPageSandbox.onFullEditor(self)
    -- treat as singleton like the vanilla call sites do
    if ISServerSandboxOptionsUI.instance then
        ISServerSandboxOptionsUI.instance:close()
    end
    local ui = ISServerSandboxOptionsUI:new(150, 150, 800, 600)
    ui:initialise()
    ui:addToUIManager()
end

-- ------------------------------------------------------------------
-- Frame
-- ------------------------------------------------------------------

function AegisPageSandbox:prerender()
    if not self.navArea then return end
    local c = Aegis.col
    local pad = 20
    Aegis.roundFrame(self, pad, pad, self.width - pad * 2, self.height - pad * 2, 10, 1, c.line, c.panel)
    Aegis.icon(self, "gear", pad + 14, pad + 12, 15, 1, c.gold)
    Aegis.text(self, getText("UI_Aegis_NavSandbox"), pad + 36, pad + 10, UIFont.Medium, c.text)

    Aegis.roundFrame(self, self.navArea.x, self.navArea.y, NAV_W, self.navArea.height, 10, 1, c.line, c.card)
    if not self.pages[1] then
        Aegis.textCentre(self, getText("UI_Aegis_NoOptionSelected"), self.contentX + math.floor(self.contentW / 2),
            math.floor(self.height / 2), UIFont.Medium, c.muted)
    end
end

AegisWindow.registerPage({
    id = "sandbox",
    icon = "gear",
    label = "UI_Aegis_NavSandbox",
    create = AegisPageSandbox.create,
})
