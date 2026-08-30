-- Vehicle detail window: docked panel, opens automatically after every
-- Aegis spawn or via the "Edit" button on the vehicles page. Not modal
-- (no fullscreen scrim like AegisCompare): the vehicle stays visible in
-- the world while changes land live.
require "Aegis/AegisWindow"
require "Aegis/AegisWidgets"
require "Aegis/AegisTheme"
-- deliberately NOT requiring AegisPageVehicles: that file requires this
-- one, and the pair produced a recursive require warning in every client
-- log. The dependency only runs one way, the page opens this window
require "ISUI/ISTextEntryBox"
require "Vehicles/ISUI/ISVehicleMechanics"

AegisVehicleDetail = ISPanel:derive("AegisVehicleDetail")
AegisVehicleDetail.instance = nil

local W = 380
local MARGIN = 24
local HEADER_H = 96
local PREVIEW_H = 150
local TAB_H = 36
local TABS = { "color", "parts", "service", "name" }
local TAB_LABEL_KEY = {
    color = "UI_Aegis_TabColor", parts = "UI_Aegis_TabParts",
    service = "UI_Aegis_TabService", name = "UI_Aegis_TabName",
}
local KNOWN_COMMANDS = {
    vehicleData = true, vehicleColor = true, vehicleSkin = true,
    vehiclePartSwap = true, vehiclePartUndo = true, vehiclePartCondition = true,
    vehicleAllTires = true, vehicleService = true, vehicleName = true, vehicleReset = true,
    vehicleContainerLevel = true, vehicleNewKey = true, vehicleCapacity = true,
}

-- ==================================================================
-- brief world target marker on open, disappears after 1.5s on its own
-- (same self-destruct pattern as AegisBanner in AegisHud.lua); needs a
-- full-screen overlay for the world rendering, does not eat clicks
-- ==================================================================
AegisVehicleGlow = ISPanel:derive("AegisVehicleGlow")
AegisVehicleGlow.instance = nil

function AegisVehicleGlow.show(vehicle)
    if not vehicle then return end
    if AegisVehicleGlow.instance then AegisVehicleGlow.instance:removeFromUIManager() end
    local sw, sh = getCore():getScreenWidth(), getCore():getScreenHeight()
    local o = ISPanel:new(0, 0, sw, sh)
    setmetatable(o, AegisVehicleGlow)
    AegisVehicleGlow.__index = AegisVehicleGlow
    o.background = false
    o.vehicle = vehicle
    o.expiresAt = getTimestampMs() + 1500
    o:initialise()
    o:addToUIManager()
    o.javaObject:setConsumeMouseEvents(false)
    AegisVehicleGlow.instance = o
    return o
end

function AegisVehicleGlow:render()
    local c = Aegis.col
    local remaining = self.expiresAt - getTimestampMs()
    if remaining <= 0 then return end
    local z = math.floor(self.vehicle:getZ())
    local sx = isoToScreenX(0, self.vehicle:getX(), self.vehicle:getY(), z)
    local sy = isoToScreenY(0, self.vehicle:getX(), self.vehicle:getY(), z)
    local a = math.min(1, remaining / 400)
    local r = 30 + (1 - remaining / 1500) * 12
    self:drawRectBorder(sx - r, sy - r, r * 2, r * 2, a, c.goldHi.r, c.goldHi.g, c.goldHi.b)
end

function AegisVehicleGlow:update()
    if getTimestampMs() > self.expiresAt then
        self:removeFromUIManager()
        if AegisVehicleGlow.instance == self then AegisVehicleGlow.instance = nil end
    end
end

local COLOR_THROTTLE = 120

-- standard HSV-to-RGB, h/s/v each 0-1
local function hsvToRgb(h, s, v)
    local i = math.floor(h * 6)
    local f = h * 6 - i
    local p = v * (1 - s)
    local q = v * (1 - f * s)
    local t = v * (1 - (1 - f) * s)
    i = i % 6
    if i == 0 then return v, t, p
    elseif i == 1 then return q, v, p
    elseif i == 2 then return p, v, t
    elseif i == 3 then return p, q, v
    elseif i == 4 then return t, p, v
    else return v, p, q end
end

-- only "tire" is bytecode-confirmed, everything else is
-- a generic fallback - covers mod vehicles/mod categories (e.g. armor
-- plating) without the code needing to know them
local function categoryName(category)
    if category == "tire" then return getText("UI_Aegis_PartsCategoryTires") end
    if not category or category == "" then return getText("UI_Aegis_PartsCategoryOther") end
    return category:sub(1, 1):upper() .. category:sub(2)
end

local UNDO_MS = 5000
local TEMPLATE_THROTTLE = 150

-- ==================================================================
-- vehicle templates: client-local file in the admin's own Zomboid/Lua
-- folder (same pattern as the weather presets in AegisPageWorld.lua),
-- one line per template:
-- T|name|script|h|s|v|skin|nick|part:type:cond;...|part:cap;...
-- names and nicknames are sanitized so the separators stay unambiguous
-- ==================================================================
local TEMPLATE_FILE = "AegisVehicleTemplates.txt"
local templatesCache = nil

local function sanitizeName(s)
    return tostring(s or ""):gsub("[|;:\r\n]", ""):gsub("^%s+", ""):gsub("%s+$", ""):sub(1, 40)
end

local function loadTemplates()
    if templatesCache then return templatesCache end
    templatesCache = {}
    -- append writer first: creates folder and file without touching
    -- content, a bare getFileReader throws on a fresh Lua folder
    pcall(function()
        local w = getFileWriter(TEMPLATE_FILE, true, true)
        if w then w:close() end
    end)
    pcall(function()
        local reader = getFileReader(TEMPLATE_FILE, true)
        if not reader then return end
        local line = reader:readLine()
        while line ~= nil do
            local name, script, h, s, v, skin, nick, parts, containers =
                string.match(line, "^T|([^|]+)|([^|]+)|(%d+)|(%d+)|(%d+)|(%d+)|([^|]*)|([^|]*)|([^|]*)$")
            if name then
                local tpl = {
                    name = name, script = script,
                    h = tonumber(h), s = tonumber(s), v = tonumber(v),
                    skin = tonumber(skin), nick = nick,
                    parts = {}, containers = {},
                }
                for part, itemType, cond in string.gmatch(parts, "([^;:]+):([^;:]*):(%d+)") do
                    table.insert(tpl.parts, { part = part, itemType = itemType ~= "" and itemType or nil, condition = tonumber(cond) })
                end
                for part, cap in string.gmatch(containers, "([^;:]+):(%d+)") do
                    table.insert(tpl.containers, { part = part, capacity = tonumber(cap) })
                end
                table.insert(templatesCache, tpl)
            end
            line = reader:readLine()
        end
        reader:close()
    end)
    return templatesCache
end

local function writeTemplates()
    pcall(function()
        local w = getFileWriter(TEMPLATE_FILE, true, false)
        if not w then return end
        for _, tpl in ipairs(templatesCache or {}) do
            local parts = {}
            for _, tp in ipairs(tpl.parts) do
                table.insert(parts, tp.part .. ":" .. (tp.itemType or "") .. ":" .. tostring(tp.condition or 100))
            end
            local containers = {}
            for _, tc in ipairs(tpl.containers) do
                table.insert(containers, tc.part .. ":" .. tostring(tc.capacity or 0))
            end
            w:write(string.format("T|%s|%s|%d|%d|%d|%d|%s|%s|%s\n",
                tpl.name, tpl.script, tpl.h or 0, tpl.s or 0, tpl.v or 0, tpl.skin or 0,
                tpl.nick or "", table.concat(parts, ";"), table.concat(containers, ";")))
        end
        w:close()
    end)
end

-- ==================================================================
-- template chooser: small floating card left of the detail window,
-- save current / apply / delete; apply is only live when the open
-- vehicle runs the same script as the template
-- ==================================================================
AegisVehicleTemplateChooser = ISPanel:derive("AegisVehicleTemplateChooser")
AegisVehicleTemplateChooser.instance = nil

function AegisVehicleTemplateChooser.toggle(detail)
    if AegisVehicleTemplateChooser.instance then
        AegisVehicleTemplateChooser.instance:close()
        return
    end
    local w = 260
    local o = ISPanel:new(math.max(24, detail:getX() - w - 12), detail:getY() + 40, w, 120)
    setmetatable(o, AegisVehicleTemplateChooser)
    AegisVehicleTemplateChooser.__index = AegisVehicleTemplateChooser
    o.background = false
    o.detail = detail
    o.widgets = {}
    o:initialise()
    o:addToUIManager()
    o:setAlwaysOnTop(true)
    AegisVehicleTemplateChooser.instance = o
    o:rebuild()
    return o
end

function AegisVehicleTemplateChooser:close()
    self:removeFromUIManager()
    if AegisVehicleTemplateChooser.instance == self then AegisVehicleTemplateChooser.instance = nil end
end

function AegisVehicleTemplateChooser:rebuild()
    for _, widget in ipairs(self.widgets) do
        pcall(function() self:removeChild(widget) end)
    end
    self.widgets = {}
    local w = self.width - 24
    local y = 40
    local saveBtn = AegisButton:new(12, y, w, 28, getText("UI_Aegis_VtSave"), "plus", self, AegisVehicleTemplateChooser.onSave)
    saveBtn.style = "gold"
    self:addChild(saveBtn)
    table.insert(self.widgets, saveBtn)
    y = y + 36
    local list = loadTemplates()
    self.empty = #list == 0
    for i, tpl in ipairs(list) do
        local matches = self.detail.data and self.detail.data.script == tpl.script
        local applyBtn = AegisButton:new(12, y, w - 30, 26, tpl.name, nil, self, function(panel)
            if matches then
                panel.detail:applyTemplate(tpl)
                panel:close()
            else
                Aegis.showToast(getText("UI_Aegis_VtWrongScript"))
            end
        end)
        applyBtn.font = UIFont.Small
        applyBtn.style = "ghost"
        applyBtn.tooltip = matches and getText("UI_Aegis_VtApply") or getText("UI_Aegis_VtWrongScript")
        self:addChild(applyBtn)
        table.insert(self.widgets, applyBtn)
        local delBtn = AegisButton:new(12 + w - 26, y, 26, 26, nil, "close", self, function(panel)
            table.remove(loadTemplates(), i)
            writeTemplates()
            panel:rebuild()
        end)
        delBtn.radius = 13
        delBtn.tooltip = getText("UI_Aegis_VtDelete")
        self:addChild(delBtn)
        table.insert(self.widgets, delBtn)
        y = y + 30
    end
    if self.empty then y = y + 24 end
    self:setHeight(y + 12)
end

function AegisVehicleTemplateChooser:onSave()
    local chooser = self
    AegisPrompt.show{
        title = getText("UI_Aegis_VehicleTemplate"),
        message = getText("UI_Aegis_VtName"),
        confirmLabel = getText("UI_Aegis_VtSave"),
        reasonRequired = true,
        target = self,
        onConfirm = function(panel, name)
            name = sanitizeName(name)
            if name == "" or not chooser.detail.data then return end
            local tpl = chooser.detail:templateFromCurrent(name)
            local list = loadTemplates()
            -- same name overwrites in place
            local replaced = false
            for i, old in ipairs(list) do
                if old.name == name then
                    list[i] = tpl
                    replaced = true
                end
            end
            if not replaced then table.insert(list, tpl) end
            writeTemplates()
            Aegis.showToast(getText("UI_Aegis_VtSaved"))
            Aegis.logAction("vehicles", "Vehicle template saved: " .. name)
            if AegisVehicleTemplateChooser.instance == chooser then chooser:rebuild() end
        end,
    }
end

function AegisVehicleTemplateChooser:prerender()
    ISPanel.prerender(self)
    local c = Aegis.col
    Aegis.shadow(self, 0, 0, self.width, self.height, 20, 0.6)
    Aegis.roundFrame(self, 0, 0, self.width, self.height, 10, 1, c.line, c.panel)
    Aegis.text(self, getText("UI_Aegis_VehicleTemplate"), 12, 12, UIFont.Medium, c.goldHi)
    if self.empty then
        Aegis.text(self, getText("UI_Aegis_VtNone"), 12, self.height - 32, UIFont.Small, c.muted)
    end
end

function AegisVehicleTemplateChooser:update()
    ISPanel.update(self)
    -- self-close when the detail window went away
    if AegisVehicleDetail.instance ~= self.detail then self:close() end
end

-- ==================================================================
-- main panel
-- ==================================================================

-- opens for a vehicle ID; vehicleObj optional (the "Edit" button already
-- has the object from getNearVehicle, the spawn path only gets the ID
-- from the server reply and resolves it itself via getVehicleById)
function AegisVehicleDetail.open(vehicleId, vehicleObj)
    if AegisVehicleDetail.instance and AegisVehicleDetail.instance.vehicleId == vehicleId then
        AegisVehicleDetail.instance:bringToTop()
        return AegisVehicleDetail.instance
    end
    if AegisVehicleDetail.instance then AegisVehicleDetail.instance:close() end
    if not vehicleObj then
        pcall(function() vehicleObj = getVehicleById(vehicleId) end)
    end
    local sw, sh = getCore():getScreenWidth(), getCore():getScreenHeight()
    local h = sh - MARGIN * 2
    local o = ISPanel:new(sw - MARGIN - W, MARGIN, W, h)
    setmetatable(o, AegisVehicleDetail)
    AegisVehicleDetail.__index = AegisVehicleDetail
    o.background = false
    o.vehicleId = vehicleId
    o.vehicleObj = vehicleObj
    o.data = nil
    o.anim = 0
    o:initialise()
    o:addToUIManager()
    o:setAlwaysOnTop(true)
    AegisVehicleDetail.instance = o
    if vehicleObj then AegisVehicleGlow.show(vehicleObj) end
    sendClientCommand(getPlayer(), AegisShared.MODULE, "vehicleData", { id = vehicleId })
    return o
end

function AegisVehicleDetail:close()
    if self.colorDirty and self.hueSlider then
        local h, s, v = self.hueSlider.value / 360, self.satSlider.value / 100, self.valSlider.value / 100
        sendClientCommand(getPlayer(), AegisShared.MODULE, "vehicleColor", { id = self.vehicleId, h = h, s = s, v = v })
        self.colorDirty = false
    end
    self:removeFromUIManager()
    if AegisVehicleDetail.instance == self then AegisVehicleDetail.instance = nil end
    if AegisVehicleTemplateChooser.instance then AegisVehicleTemplateChooser.instance:close() end
end

function AegisVehicleDetail:createChildren()
    self.closeBtn = AegisButton:new(self.width - 40, 14, 26, 26, nil, "close", self, AegisVehicleDetail.close)
    self.closeBtn.radius = 13
    self:addChild(self.closeBtn)

    -- collapse to the header bar while working in the world; restoring
    -- brings back the exact previous state (children are only hidden,
    -- never rebuilt - active tab, sliders and drafts survive)
    self.minBtn = AegisButton:new(self.width - 74, 14, 26, 26, nil, "minus", self, AegisVehicleDetail.toggleMinimize)
    self.minBtn.radius = 13
    self:addChild(self.minBtn)

    -- cross-category, sits in the header: touches color+skin+all parts at
    -- once - clearly set apart as a warning action, two-step (first click
    -- asks for confirmation, second click triggers it)
    self.resetBtn = AegisButton:new(self.width - 154, 48, 140, 22, getText("UI_Aegis_FactoryReset"), nil, self, AegisVehicleDetail.onFactoryReset)
    self.resetBtn.font = UIFont.Small
    self:addChild(self.resetBtn)

    -- template chooser toggle, header row left of the factory reset
    -- (reset spans width-154..width-14, this one width-270..width-160)
    self.templateBtn = AegisButton:new(self.width - 270, 48, 110, 22, getText("UI_Aegis_VehicleTemplate"), nil, self, function(panel)
        AegisVehicleTemplateChooser.toggle(panel)
    end)
    self.templateBtn.font = UIFont.Small
    self:addChild(self.templateBtn)

    pcall(function()
        local scene = AegisVehicleScene:new(14, HEADER_H, self.width - 28, PREVIEW_H)
        scene:initialise()
        scene:instantiate()
        scene.backgroundColor = { r = Aegis.col.dark.r, g = Aegis.col.dark.g, b = Aegis.col.dark.b, a = 1 }
        scene.borderColor = { r = Aegis.col.line.r, g = Aegis.col.line.g, b = Aegis.col.line.b, a = 1 }
        self:addChild(scene)
        self.scene = scene
        local jo = scene.javaObject
        jo:fromLua1("setDrawGrid", false)
        jo:fromLua1("setDrawGridAxes", false)
        jo:fromLua1("setMaxZoom", 20)
        jo:fromLua1("createVehicle", "vehicle")
        jo:fromLua1("setView", "UserDefined")
        jo:fromLua3("setViewRotation", 15, 45, 0)
        jo:fromLua1("setZoom", 6)
        if self.vehicleObj and self.vehicleObj:getScript() then
            local full = self.vehicleObj:getScript():getFullName()
            jo:fromLua2("setVehicleScript", "vehicle", full)
            self.sceneScript = full
        end
    end)

    self.tabBtns = {}
    local tabW = math.floor((self.width - 28) / #TABS)
    for i, id in ipairs(TABS) do
        local btn = AegisButton:new(14 + (i - 1) * tabW, HEADER_H + PREVIEW_H, tabW, TAB_H, getText(TAB_LABEL_KEY[id]), nil, self, function(panel)
            panel:switchTab(id)
        end)
        self:addChild(btn)
        self.tabBtns[id] = btn
    end

    local cy = HEADER_H + PREVIEW_H + TAB_H + 8
    local ch = self.height - cy - 8
    self.tabPanels = {}
    for _, id in ipairs(TABS) do
        local p = AegisScrollArea:new(14, cy, self.width - 28, ch)
        p:setVisible(false)
        self:addChild(p)
        self.tabPanels[id] = p
    end
    self.tab = "color"
    self.tabPanels.color:setVisible(true)
    self.tabBtns.color.style = "gold"

    self:buildColorUI()
    self:buildPartsUI()
    self:buildServiceUI()
    self:buildNameUI()
end

function AegisVehicleDetail:switchTab(id)
    if self.tab == id then return end
    self.tabPanels[self.tab]:setVisible(false)
    self.tabBtns[self.tab].style = "ghost"
    self.tab = id
    self.tabPanels[id]:setVisible(true)
    self.tabBtns[id].style = "gold"
end

function AegisVehicleDetail:toggleMinimize()
    self.minimized = not self.minimized
    self.minBtn.icon = self.minimized and "plus" or "minus"
    local show = not self.minimized
    if self.scene then self.scene:setVisible(show) end
    self.resetBtn:setVisible(show)
    self.templateBtn:setVisible(show)
    for _, btn in pairs(self.tabBtns) do btn:setVisible(show) end
    for id, tp in pairs(self.tabPanels) do tp:setVisible(show and id == self.tab) end
    if self.minimized then
        self.fullH = self.height
        self:setHeight(52)
    else
        self:setHeight(self.fullH or (getCore():getScreenHeight() - MARGIN * 2))
    end
end

function AegisVehicleDetail:buildColorUI()
    local p = self.tabPanels.color
    local panel = self
    local w = p:getWidth() - 16
    local y = 8
    local swatchY = y
    y = y + 58

    self.hueSlider = AegisSlider:new(8, y, w, 26, self, AegisVehicleDetail.onColorChanged)
    -- no degree suffix: the game's bitmap font lacks the glyph and renders
    -- it as "?" (same known gap as the middle-dot separator elsewhere)
    self.hueSlider:setValues(0, 360, 1, "")
    p:addChild(self.hueSlider)
    y = y + 32

    self.satSlider = AegisSlider:new(8, y, w, 26, self, AegisVehicleDetail.onColorChanged)
    self.satSlider:setValues(0, 100, 1, "%")
    p:addChild(self.satSlider)
    y = y + 32

    self.valSlider = AegisSlider:new(8, y, w, 26, self, AegisVehicleDetail.onColorChanged)
    self.valSlider:setValues(0, 100, 1, "%")
    p:addChild(self.valSlider)
    y = y + 40

    self.skinY = y
    self.skinBtns = {}

    -- own prerender on the tab panel: colour preview swatch. No colour
    -- push onto the 3D mini preview: UI3DScene has no setColorHSV command
    --: "unhandled setColorHSV" thrown every frame, and
    -- the engine swallows the Java exception internally so pcall reports
    -- success - a failure latch can never arm). The swatch plus the real
    -- vehicle in the world carry the live colour feedback instead.
    p.prerender = function(el)
        AegisScrollArea.prerender(el)
        local c = Aegis.col
        local h = (panel.hueSlider and panel.hueSlider.value or 0) / 360
        local s = (panel.satSlider and panel.satSlider.value or 0) / 100
        local v = (panel.valSlider and panel.valSlider.value or 0) / 100
        local r, g, b = hsvToRgb(h, s, v)
        Aegis.roundFrame(el, 8, swatchY, 48, 48, 8, 1, c.gold, { r = r, g = g, b = b })
        if #panel.skinBtns > 0 then
            Aegis.text(el, getText("UI_Aegis_Skin"), 8, panel.skinY - 20, UIFont.Small, c.muted)
        end
    end
end
function AegisVehicleDetail:buildPartsUI()
    self.partCards = {}
    -- per-category collapse state, survives every refreshParts rebuild
    -- for the lifetime of this panel
    self.collapsedCats = {}
end
function AegisVehicleDetail:buildServiceUI()
    local p = self.tabPanels.service
    local panel = self
    local w = p:getWidth() - 16
    self.serviceBtn = AegisButton:new(8, 8, w, 40, getText("UI_Aegis_ServiceVehicle"), "refresh", self, AegisVehicleDetail.onService)
    self.serviceBtn.style = "gold"
    self.serviceBtn.tooltip = getText("UI_Aegis_ServiceInfo")
    p:addChild(self.serviceBtn)

    -- live level sliders for fuel and battery, throttled like the color
    -- sliders; hidden via refreshService when the vehicle has no such part
    self.fuelSlider = AegisSlider:new(8, 108, w, 24, self, function() panel.fuelDirty = true end)
    self.fuelSlider:setValues(0, 100, 1, "%")
    self.fuelSlider:setVisible(false)
    p:addChild(self.fuelSlider)

    self.batterySlider = AegisSlider:new(8, 158, w, 24, self, function() panel.batteryDirty = true end)
    self.batterySlider:setValues(0, 100, 1, "%")
    self.batterySlider:setVisible(false)
    p:addChild(self.batterySlider)

    -- capacity rows for the item container parts follow below the
    -- sliders, built per vehicle in refreshService
    self.capacityBtns = {}
    self.capacityY = 214

    -- description under the button plus labels above the visible sliders
    p.prerender = function(el)
        AegisScrollArea.prerender(el)
        Aegis.text(el, Aegis.fitText(getText("UI_Aegis_ServiceInfo"), UIFont.Small, el.width - 16), 8, 58, UIFont.Small, Aegis.col.muted)
        if panel.fuelSlider and panel.fuelSlider:isVisible() then
            Aegis.text(el, getText("UI_Aegis_Fuel"), 8, 90, UIFont.Small, Aegis.col.text)
        end
        if panel.batterySlider and panel.batterySlider:isVisible() then
            Aegis.text(el, getText("UI_Aegis_Battery"), 8, 140, UIFont.Small, Aegis.col.text)
        end
        if panel.capacityBtns and #panel.capacityBtns > 0 then
            Aegis.text(el, getText("UI_Aegis_Capacity"), 8, panel.capacityY - 20, UIFont.Small, Aegis.col.text)
        end
    end
end

-- one row per container part: part name left, capacity as button right,
-- click opens the number prompt (carry weight pattern)
function AegisVehicleDetail:refreshCapacity()
    local p = self.tabPanels.service
    if not p then return end
    for _, btn in ipairs(self.capacityBtns or {}) do
        local removedA = pcall(function() p:removeChild(btn) end)
        local removedB = pcall(function() btn:removeFromUIManager() end)
        if not removedA and not removedB then print("[Aegis] failed to remove old capacity button") end
    end
    self.capacityBtns = {}
    local list = self.data and self.data.containers or {}
    local panel = self
    local w = p:getWidth() - 16
    local y = self.capacityY
    for _, entry in ipairs(list) do
        local label = (getTextOrNull("IGUI_VehiclePart" .. entry.part) or entry.part)
            .. ": " .. tostring(entry.capacity)
        local btn = AegisButton:new(8, y, w, 26, label, nil, self, function()
            panel:onCapacityPrompt(entry.part, entry.capacity)
        end)
        p:addChild(btn)
        table.insert(self.capacityBtns, btn)
        y = y + 30
    end
    p:setScrollHeight(y + 8)
end

function AegisVehicleDetail:onCapacityPrompt(partId, current)
    local panel = self
    local prompt = AegisPrompt.show{
        title = getText("UI_Aegis_Capacity"),
        message = getText("UI_Aegis_CapacityPrompt", tostring(current)),
        confirmLabel = getText("UI_Aegis_Apply"),
        reasonRequired = true,
        target = self,
        onConfirm = function(page, textValue)
            local value = tonumber(textValue)
            if not value then return end
            value = math.floor(math.max(1, math.min(1000, value)))
            sendClientCommand(getPlayer(), AegisShared.MODULE, "vehicleCapacity", { id = panel.vehicleId, part = partId, value = value })
        end,
    }
    pcall(function() prompt.entry:setOnlyNumbers(true) end)
end

function AegisVehicleDetail:onService()
    sendClientCommand(getPlayer(), AegisShared.MODULE, "vehicleService", { id = self.vehicleId })
end

function AegisVehicleDetail:buildNameUI()
    local p = self.tabPanels.name
    local w = p:getWidth() - 16
    self.nameEntry = ISTextEntryBox:new("", 8, 8, w, 30)
    self.nameEntry:initialise()
    self.nameEntry:instantiate()
    self.nameEntry.font = UIFont.Small
    self.nameEntry:setPlaceholderText(getText("UI_Aegis_VehicleNamePlaceholder"))
    local panel = self
    self.nameEntry.onTextChange = function() panel.nameDirty = true end
    p:addChild(self.nameEntry)

    self.newKeyBtn = AegisButton:new(8, 88, w, 30, getText("UI_Aegis_NewKey"), nil, self, AegisVehicleDetail.onNewKey)
    self.newKeyBtn:setVisible(false)
    p:addChild(self.newKeyBtn)

    self.nameSaveBtn = AegisButton:new(8, 46, w, 34, getText("UI_Aegis_SaveName"), nil, self, AegisVehicleDetail.onSaveName)
    self.nameSaveBtn.style = "gold"
    p:addChild(self.nameSaveBtn)
end

function AegisVehicleDetail:onSaveName()
    local name = (self.nameEntry:getInternalText() or ""):gsub("^%s+", ""):gsub("%s+$", "")
    sendClientCommand(getPlayer(), AegisShared.MODULE, "vehicleName", { id = self.vehicleId, name = name })
end
function AegisVehicleDetail:refreshColor()
    if not self.hueSlider then return end
    self.hueSlider:setValue(math.floor((self.data.hue or 0) * 360), true)
    self.satSlider:setValue(math.floor((self.data.sat or 0) * 100), true)
    self.valSlider:setValue(math.floor((self.data.val or 0) * 100), true)
    self.colorDirty = false

    -- removing a child widget from its parent is not bytecode-verified
    -- (removeChild is the more common ISUIElement method for children,
    -- removeFromUIManager is more for top-level panels like AegisWindow
    -- itself) - both attempts pcall-wrapped defensively, see the
    -- verification step below
    local colorPanel = self.tabPanels.color
    -- currently a no-op in practice (vehicleData is only fetched once per
    -- open), becomes load-bearing when a factory reset re-fetches
    -- vehicleData to resync this tab
    for _, b in ipairs(self.skinBtns) do
        local removedA = pcall(function() colorPanel:removeChild(b) end)
        local removedB = pcall(function() b:removeFromUIManager() end)
        if not removedA and not removedB then print("[Aegis] failed to remove old skin button") end
    end
    self.skinBtns = {}
    local count = self.data.skinCount or 1
    if count > 1 then
        local p = colorPanel
        local w = p:getWidth() - 16
        local bw = math.floor((w - (count - 1) * 6) / count)
        for i = 0, count - 1 do
            local btn = AegisButton:new(8 + i * (bw + 6), self.skinY, bw, 28, tostring(i + 1), nil, self, function(panel)
                panel:setSkin(i)
            end)
            btn.style = (i == self.data.skinIndex) and "gold" or "ghost"
            p:addChild(btn)
            table.insert(self.skinBtns, btn)
        end
    end
end

function AegisVehicleDetail:setSkin(index)
    self.data.skinIndex = index
    for i, b in ipairs(self.skinBtns) do
        b.style = (i - 1 == index) and "gold" or "ghost"
    end
    sendClientCommand(getPlayer(), AegisShared.MODULE, "vehicleSkin", { id = self.vehicleId, index = index })
end

function AegisVehicleDetail:onColorChanged()
    self.colorDirty = true
end
function AegisVehicleDetail:refreshParts()
    local p = self.tabPanels.parts
    -- see the comment on refreshColor: removeChild+removeFromUIManager
    -- both attempted defensively, no bytecode-verified method for this
    for _, card in ipairs(self.partCards) do
        for _, w in ipairs(card.widgets) do
            local removedA = pcall(function() p:removeChild(w) end)
            local removedB = pcall(function() w:removeFromUIManager() end)
            if not removedA and not removedB then print("[Aegis] failed to remove old part card widget") end
        end
    end
    self.partCards = {}
    if not self.data or not self.data.parts then return end

    local w = p:getWidth() - 16
    local y = 8
    -- bucket parts by category FIRST so every category gets exactly one
    -- header - vehicle scripts interleave their part order (some bodywork,
    -- then engine, then bodywork again), grouping only consecutive runs
    -- produced duplicate headers; categories keep
    -- first-seen order, parts keep script order within their category
    local order, buckets = {}, {}
    for _, part in ipairs(self.data.parts) do
        if not buckets[part.category] then
            buckets[part.category] = {}
            table.insert(order, part.category)
        end
        table.insert(buckets[part.category], part)
    end
    for _, cat in ipairs(order) do
        y = self:buildCategoryHeader(p, cat, #buckets[cat], w, y)
        if not self.collapsedCats[cat] then
            for _, part in ipairs(buckets[cat]) do
                y = self:buildPartCard(p, part, w, y)
            end
        end
    end

    local hasTires = false
    for _, part in ipairs(self.data.parts) do
        if part.part == "TireFrontLeft" then hasTires = true end
    end
    if hasTires then
        local btn = AegisButton:new(8, y, w, 30, getText("UI_Aegis_ApplyToAll4"), nil, self, AegisVehicleDetail.onAllTires)
        p:addChild(btn)
        table.insert(self.partCards, { widgets = { btn } })
        y = y + 36
    end
    -- without an explicit scroll height the scroll area never scrolls,
    -- and the card list far exceeds the visible tab
    p:setScrollHeight(y + 8)

    -- empty state as a flag rather than a text position dragged along with
    -- scrolling (same reasoning as the category text below in
    -- buildPartCard - direct text on the parent scroll panel would not
    -- reliably move with the real child widgets while scrolling)
    p.empty = #self.data.parts == 0
    p.prerender = function(el)
        AegisScrollArea.prerender(el)
        if el.empty then
            Aegis.textCentre(el, getText("UI_Aegis_NoParts"), math.floor(el.width / 2), 40, UIFont.Small, Aegis.col.muted)
        end
    end
end

-- full-width gold section bar, clickable to collapse/expand its category
-- (minus = open, plus = collapsed, part count in the label); registered
-- in partCards so the teardown in refreshParts removes it like any other
-- row widget
function AegisVehicleDetail:buildCategoryHeader(p, category, count, w, y)
    local panel = self
    local collapsed = self.collapsedCats[category] == true
    local label = (getTextOrNull("IGUI_VehiclePartCat" .. (category or "")) or categoryName(category))
        .. " (" .. count .. ")"
    local btn = AegisButton:new(8, y, w, 28, label, collapsed and "plus" or "minus", self, function()
        panel.collapsedCats[category] = not panel.collapsedCats[category]
        panel:refreshParts()
    end)
    btn.style = "gold"
    p:addChild(btn)
    table.insert(self.partCards, { widgets = { btn } })
    return y + 34
end

function AegisVehicleDetail:buildPartCard(p, part, w, y)
    local panel = self
    local showUndo = self.undoState and self.undoState.part == part.part and getTimestampMs() < self.undoState.expiresAt

    -- variants stacked two per row instead of squeezed into one line:
    -- German item names ("Autoreifen (Hochleistung) ...") were truncated
    -- to unreadable stubs at a third of the card width.
    -- Parts without real alternatives (hood, doors, windows, lights, ...)
    -- show no swap row at all - just name and condition slider
    local perRow = 2
    local variantCount = #part.variants > 1 and #part.variants or 0
    local rowCount = variantCount > 0 and math.ceil(variantCount / perRow) or 0
    local btnY = 42
    local rowH = 30
    local sliderY = rowCount > 0 and (btnY + rowCount * rowH + 2) or 40
    local cardH = sliderY + 30 + (showUndo and 28 or 0)

    local bg = ISPanel:new(8, y, w, cardH)
    bg:initialise()
    bg:instantiate()
    bg.background = false
    p:addChild(bg)

    local variantBtns = {}
    if variantCount > 0 then
        local vw = math.floor((w - 16 - (perRow - 1) * 6) / perRow)
        for i, itemType in ipairs(part.variants) do
            local col = (i - 1) % perRow
            local row = math.floor((i - 1) / perRow)
            -- full label: AegisButton fits it itself and auto-sets a tooltip
            -- with the complete name whenever it has to truncate
            local btn = AegisButton:new(8 + col * (vw + 6), btnY + row * rowH, vw, 26, getItemName(itemType) or itemType, nil, self, function()
                panel:onPartSwap(part.part, itemType)
            end)
            btn.value = itemType
            btn.style = (itemType == part.current) and "gold" or "ghost"
            bg:addChild(btn)
            table.insert(variantBtns, btn)
        end
    end

    local slider = AegisSlider:new(8, sliderY, w - 16, 24, self, function()
        panel:onConditionChanged(part.part)
    end)
    slider:setValues(0, 100, 1, "%")
    slider:setValue(part.condition or 0, true)
    bg:addChild(slider)

    local card = { widgets = { bg }, part = part.part, currentType = part.current, variantBtns = variantBtns, slider = slider, conditionNextSend = 0 }

    if showUndo then
        local u = self.undoState
        local undoBtn = AegisButton:new(8, sliderY + 28, w - 16, 22, getText("UI_Aegis_Undo"), nil, self, function()
            panel.undoState = nil
            sendClientCommand(getPlayer(), AegisShared.MODULE, "vehiclePartUndo", { id = panel.vehicleId, part = u.part, itemType = u.itemType, condition = u.condition })
            panel:refreshParts()
        end)
        bg:addChild(undoBtn)
        table.insert(card.widgets, undoBtn)
    end

    -- position+name drawn directly on the card instead of separately on
    -- the parent scroll panel: guaranteed to stay with the right card
    -- while scrolling (bg is a real child widget, its position is moved
    -- by the scroll mechanism, a separate direct draw on the parent's
    -- prerender would not necessarily be)
    -- line 1 is the vanilla per-slot position name ("Vorderer linker
    -- Reifen" etc.) so identical slots (4 tires, front/rear brakes) stay
    -- distinguishable under the shared category header; raw slot id as
    -- fallback for mod parts without a vanilla key
    local position = getTextOrNull("IGUI_VehiclePart" .. part.part) or part.part
    local displayName = part.current and (getItemName(part.current) or part.current) or "-"
    bg.prerender = function(el)
        local c = Aegis.col
        Aegis.roundFrame(el, 0, 0, el.width, el.height, 8, 1, c.line, c.card)
        Aegis.text(el, position, 8, 6, UIFont.Small, c.muted)
        Aegis.text(el, Aegis.fitText(displayName, UIFont.Small, el.width - 70), 8, 6 + Aegis.fontH(UIFont.Small), UIFont.Small, c.text)
        local liveCondition = slider.value
        Aegis.textRight(el, liveCondition .. "%", el.width - 8, 6, UIFont.Small,
            liveCondition >= 66 and c.ok or (liveCondition >= 33 and c.goldDim or c.danger))
    end

    table.insert(self.partCards, card)
    return y + cardH + 8
end

function AegisVehicleDetail:onPartSwap(partId, itemType)
    for _, k in ipairs(self.partCards) do
        if k.part == partId then
            k.currentType = itemType
            for _, b in ipairs(k.variantBtns) do
                b.style = (b.value == itemType) and "gold" or "ghost"
            end
        end
    end
    sendClientCommand(getPlayer(), AegisShared.MODULE, "vehiclePartSwap", { id = self.vehicleId, part = partId, itemType = itemType })
end

function AegisVehicleDetail:onConditionChanged(partId)
    for _, k in ipairs(self.partCards) do
        if k.part == partId then k.conditionDirty = true end
    end
end

function AegisVehicleDetail:partSwapAcked(args)
    if args.previousType then
        self.undoState = { part = args.part, itemType = args.previousType, condition = args.previousCondition, expiresAt = getTimestampMs() + UNDO_MS }
        Aegis.showToast(getText("UI_Aegis_Undo"))
    end
    sendClientCommand(getPlayer(), AegisShared.MODULE, "vehicleData", { id = self.vehicleId })
end

function AegisVehicleDetail:onAllTires()
    local firstType, firstCondition
    for _, k in ipairs(self.partCards) do
        if k.part == "TireFrontLeft" then
            firstType = k.currentType
            firstCondition = k.slider.value
        end
    end
    if not firstType then return end
    sendClientCommand(getPlayer(), AegisShared.MODULE, "vehicleAllTires", { id = self.vehicleId, itemType = firstType, value = firstCondition })
end
function AegisVehicleDetail:refreshService()
    if not self.fuelSlider then return end
    if self.data.fuel then
        self.fuelSlider:setValue(self.data.fuel, true)
        self.fuelSlider:setVisible(true)
    else
        self.fuelSlider:setVisible(false)
    end
    if self.data.battery then
        self.batterySlider:setValue(self.data.battery, true)
        self.batterySlider:setVisible(true)
    else
        self.batterySlider:setVisible(false)
    end
    self.fuelDirty = false
    self.batteryDirty = false
end

function AegisVehicleDetail:refreshName()
    if not self.nameDirty and self.data.name and self.data.name ~= "" then
        self.nameEntry:setText(self.data.name)
    end
    -- vehicles that never carry a key (trailers) hide the key button and
    -- show the hint instead
    self.newKeyBtn:setVisible(self.data.hasKey ~= false)
    local p = self.tabPanels.name
    p.noKey = self.data.hasKey == false
    p.prerender = function(el)
        AegisScrollArea.prerender(el)
        if el.noKey then
            Aegis.text(el, getText("UI_Aegis_NoKey"), 8, 90, UIFont.Small, Aegis.col.muted)
        end
    end
end

function AegisVehicleDetail:onNewKey()
    sendClientCommand(getPlayer(), AegisShared.MODULE, "vehicleNewKey", { id = self.vehicleId })
end

function AegisVehicleDetail:vehicleDisplayName()
    if not self.vehicleObj then return nil end
    return getTextOrNull("IGUI_VehicleName" .. (self.vehicleObj:getScript() and self.vehicleObj:getScript():getName() or ""))
end

-- snapshot of the open vehicle for the template store: live slider values
-- where the UI has fresher state than the last vehicleData reply
function AegisVehicleDetail:templateFromCurrent(name)
    local d = self.data
    local tpl = {
        name = name,
        script = tostring(d.script or ""):gsub("[|;]", ""),
        h = self.hueSlider and self.hueSlider.value or math.floor((d.hue or 0) * 360),
        s = self.satSlider and self.satSlider.value or math.floor((d.sat or 0) * 100),
        v = self.valSlider and self.valSlider.value or math.floor((d.val or 0) * 100),
        skin = d.skinIndex or 0,
        nick = sanitizeName(d.name),
        parts = {},
        containers = {},
    }
    -- live condition per slot from the part cards, fallback to the reply
    local liveCondition = {}
    for _, card in ipairs(self.partCards or {}) do
        if card.part and card.slider then liveCondition[card.part] = card.slider.value end
    end
    for _, part in ipairs(d.parts or {}) do
        table.insert(tpl.parts, {
            part = part.part,
            itemType = part.current,
            condition = liveCondition[part.part] or part.condition or 100,
        })
    end
    for _, entry in ipairs(d.containers or {}) do
        table.insert(tpl.containers, { part = entry.part, capacity = entry.capacity })
    end
    return tpl
end

-- replays a template onto the open vehicle through the existing commands,
-- one send per tick slot (the queue drains throttled in update, the
-- server has per-command gates); ends with a vehicleData refetch
function AegisVehicleDetail:applyTemplate(tpl)
    if not self.data or self.data.script ~= tpl.script then
        Aegis.showToast(getText("UI_Aegis_VtWrongScript"))
        return
    end
    local id = self.vehicleId
    local q = {}
    table.insert(q, { cmd = "vehicleColor", args = { id = id, h = (tpl.h or 0) / 360, s = (tpl.s or 0) / 100, v = (tpl.v or 0) / 100 } })
    if (self.data.skinCount or 1) > 1 then
        table.insert(q, { cmd = "vehicleSkin", args = { id = id, index = tpl.skin or 0 } })
    end
    local current = {}
    for _, part in ipairs(self.data.parts or {}) do current[part.part] = part end
    for _, tp in ipairs(tpl.parts) do
        local cur = current[tp.part]
        if cur then
            if tp.itemType and tp.itemType ~= cur.current then
                -- only swap to variants the open vehicle actually offers
                for _, variant in ipairs(cur.variants or {}) do
                    if variant == tp.itemType then
                        table.insert(q, { cmd = "vehiclePartSwap", args = { id = id, part = tp.part, itemType = tp.itemType } })
                        break
                    end
                end
            end
            table.insert(q, { cmd = "vehiclePartCondition", args = { id = id, part = tp.part, value = tp.condition or 100 } })
        end
    end
    for _, tc in ipairs(tpl.containers) do
        table.insert(q, { cmd = "vehicleCapacity", args = { id = id, part = tc.part, value = tc.capacity } })
    end
    if tpl.nick and tpl.nick ~= "" then
        table.insert(q, { cmd = "vehicleName", args = { id = id, name = tpl.nick } })
    end
    table.insert(q, { done = true })
    self.templateQueue = q
    self.templateNextSend = 0
    Aegis.logAction("vehicles", "Vehicle template applied: " .. tpl.name)
end

function AegisVehicleDetail:onFactoryReset()
    local now = getTimestampMs()
    if self.resetConfirming then
        if now - (self.resetConfirmArmedAt or 0) < 400 then return end
        self.resetConfirming = false
        self.resetBtn.label = getText("UI_Aegis_FactoryReset")
        self.resetBtn.style = "ghost"
        sendClientCommand(getPlayer(), AegisShared.MODULE, "vehicleReset", { id = self.vehicleId })
    else
        self.resetConfirming = true
        self.resetConfirmArmedAt = now
        self.resetConfirmExpires = now + 4000
        self.resetBtn.label = getText("UI_Aegis_FactoryResetConfirm")
        self.resetBtn.style = "danger"
    end
end

function AegisVehicleDetail:update()
    ISPanel.update(self)
    if self.templateQueue then
        local now = getTimestampMs()
        if now >= (self.templateNextSend or 0) then
            self.templateNextSend = now + TEMPLATE_THROTTLE
            local entry = table.remove(self.templateQueue, 1)
            if not entry then
                self.templateQueue = nil
            elseif entry.done then
                self.templateQueue = nil
                sendClientCommand(getPlayer(), AegisShared.MODULE, "vehicleData", { id = self.vehicleId })
                Aegis.showToast(getText("UI_Aegis_VtApplied"))
            else
                sendClientCommand(getPlayer(), AegisShared.MODULE, entry.cmd, entry.args)
            end
        end
    end
    if self.colorDirty then
        local now = getTimestampMs()
        if now >= (self.colorNextSend or 0) then
            self.colorNextSend = now + COLOR_THROTTLE
            self.colorDirty = false
            local h, s, v = self.hueSlider.value / 360, self.satSlider.value / 100, self.valSlider.value / 100
            sendClientCommand(getPlayer(), AegisShared.MODULE, "vehicleColor", { id = self.vehicleId, h = h, s = s, v = v })
        end
    end
    for _, k in ipairs(self.partCards) do
        if k.conditionDirty then
            local now = getTimestampMs()
            if now >= (k.conditionNextSend or 0) then
                k.conditionNextSend = now + COLOR_THROTTLE
                k.conditionDirty = false
                sendClientCommand(getPlayer(), AegisShared.MODULE, "vehiclePartCondition", { id = self.vehicleId, part = k.part, value = k.slider.value })
            end
        end
    end
    if self.undoState and getTimestampMs() > self.undoState.expiresAt then
        self.undoState = nil
        self:refreshParts()
    end
    if self.resetConfirming and getTimestampMs() > (self.resetConfirmExpires or 0) then
        self.resetConfirming = false
        self.resetBtn.label = getText("UI_Aegis_FactoryReset")
        self.resetBtn.style = "ghost"
    end
    if self.fuelDirty then
        local now = getTimestampMs()
        if now >= (self.fuelNextSend or 0) then
            self.fuelNextSend = now + COLOR_THROTTLE
            self.fuelDirty = false
            sendClientCommand(getPlayer(), AegisShared.MODULE, "vehicleContainerLevel", { id = self.vehicleId, part = "GasTank", value = self.fuelSlider.value })
        end
    end
    if self.batteryDirty then
        local now = getTimestampMs()
        if now >= (self.batteryNextSend or 0) then
            self.batteryNextSend = now + COLOR_THROTTLE
            self.batteryDirty = false
            sendClientCommand(getPlayer(), AegisShared.MODULE, "vehicleContainerLevel", { id = self.vehicleId, part = "Battery", value = self.batterySlider.value })
        end
    end
end

function AegisVehicleDetail:prerender()
    ISPanel.prerender(self)
    local c = Aegis.col
    -- soft sideways slide-in instead of a hard pop-open
    self.anim = Aegis.glide(self.anim, 1, 0.25)
    local targetX = getCore():getScreenWidth() - MARGIN - W
    self:setX(math.floor(targetX + (1 - self.anim) * 60))

    Aegis.shadow(self, 0, 0, self.width, self.height, 26, 0.6)
    Aegis.roundFrame(self, 0, 0, self.width, self.height, 12, 1, c.line, c.panel)

    local title = (self.data and self.data.name and self.data.name ~= "") and self.data.name
        or (self.data and self.data.model and getTextOrNull("IGUI_VehicleName" .. self.data.model))
        or self:vehicleDisplayName() or getText("UI_Aegis_Vehicle")
    Aegis.text(self, Aegis.fitText(title, UIFont.Medium, self.width - 90), 14, 14, UIFont.Medium, c.goldHi)
    Aegis.text(self, getText("UI_Aegis_VehicleDetailSubtitle"), 14, 14 + Aegis.fontH(UIFont.Medium), UIFont.Small, c.muted)

    -- overall condition: average of live slider values across all part
    -- cards, colour-coded red to green (reads live UI state rather than
    -- the stale self.data.parts snapshot, same reasoning as the per-card
    -- badge in buildPartCard)
    if self.partCards and #self.partCards > 0 then
        local sum, count = 0, 0
        for _, card in ipairs(self.partCards) do
            if card.slider then
                sum = sum + card.slider.value
                count = count + 1
            end
        end
        if count > 0 then
            local avg = math.floor(sum / count)
            local color = avg >= 66 and c.ok or (avg >= 33 and c.goldDim or c.danger)
            Aegis.textRight(self, avg .. "%", self.width - 82, 16, UIFont.Small, color)
        end
    end

    if not self.minimized then
        Aegis.hairline(self, 14, HEADER_H - 6, self.width - 28)
    end
end

function AegisVehicleDetail:receive(command, args)
    if not args then return end
    if args.id and args.id ~= self.vehicleId then return end
    if args.gone then
        self:close()
        Aegis.showToast(getText("UI_Aegis_VehicleGone"))
        return
    end
    if command == "vehicleData" then
        if not args.ok then return end
        self.data = args
        -- preview model comes from the server reply, not from a client-side
        -- vehicle object (getVehicleById proved unreliable on the spawn
        -- path (the preview showed a default model); only
        -- re-push when it actually changed, setVehicleScript rebuilds the
        -- scene model
        if self.scene and args.script and self.sceneScript ~= args.script then
            local ok = pcall(function()
                self.scene.javaObject:fromLua2("setVehicleScript", "vehicle", args.script)
            end)
            if ok then self.sceneScript = args.script end
        end
        self:refreshColor()
        self:refreshParts()
        self:refreshService()
        self:refreshCapacity()
        self:refreshName()
    elseif command == "vehiclePartSwap" then
        -- during a template replay the acks stay quiet: no undo offer and
        -- no per-swap refetch, the queue refetches once at the end
        if args.ok and not self.templateQueue then self:partSwapAcked(args) end
    elseif command == "vehiclePartUndo" then
        if args.ok then
            Aegis.showToast(getText("UI_Aegis_UndoApplied"))
            sendClientCommand(getPlayer(), AegisShared.MODULE, "vehicleData", { id = self.vehicleId })
        end
    elseif command == "vehicleAllTires" then
        sendClientCommand(getPlayer(), AegisShared.MODULE, "vehicleData", { id = self.vehicleId })
    elseif command == "vehicleService" then
        if args.ok then
            Aegis.showToast(getText("UI_Aegis_VehicleServiced"))
            sendClientCommand(getPlayer(), AegisShared.MODULE, "vehicleData", { id = self.vehicleId })
        end
    elseif command == "vehicleName" then
        if args.ok and self.templateQueue then
            self.data.name = args.name
        elseif args.ok then
            self.data.name = args.name
            self.nameDirty = false
            self.nameEntry:setText(args.name)
            Aegis.showToast(getText("UI_Aegis_NameSaved"))
        end
    elseif command == "vehicleReset" then
        if args.ok then
            self.undoState = nil
            Aegis.showToast(getText("UI_Aegis_FactoryResetDone"))
            sendClientCommand(getPlayer(), AegisShared.MODULE, "vehicleData", { id = self.vehicleId })
        end
    elseif command == "vehicleNewKey" then
        if args.ok then
            Aegis.showToast(getText("UI_Aegis_KeyCreated"))
        end
    elseif command == "vehicleCapacity" then
        -- quiet during a template replay, the queue refetches at the end
        if args.ok and not self.templateQueue then
            Aegis.showToast(getText("UI_Aegis_CapacitySet", tostring(args.value)))
            sendClientCommand(getPlayer(), AegisShared.MODULE, "vehicleData", { id = self.vehicleId })
        end
    end
end

-- the vanilla mechanics window recomputes its title from the static model
-- name every frame, deep inside a large render body - instead of copying
-- that function (breaks on game updates), serve the Aegis nickname for
-- exactly the one translation key the title lookup uses, for the duration
-- of a single render call, whenever the vehicle carries one. ModData is
-- synced to every client, so other players see the nickname too.
local prevMechRender = ISVehicleMechanics.render
function ISVehicleMechanics:render()
    local md = self.vehicle and self.vehicle:getModData()
    local nickname = md and md.AegisName
    if nickname and nickname ~= "" then
        local carName
        pcall(function()
            carName = self.vehicle:getScript():getCarModelName() or self.vehicle:getScript():getName()
        end)
        if carName then
            local key = "IGUI_VehicleName" .. carName
            local origGetText = getText
            getText = function(k, ...)
                if k == key then return nickname end
                return origGetText(k, ...)
            end
            local ok, err = pcall(prevMechRender, self)
            getText = origGetText
            if not ok and not AegisVehicleDetail.mechWarned then
            AegisVehicleDetail.mechWarned = true
            print("[Aegis] mechanics title render failed: " .. tostring(err))
        end
            return
        end
    end
    prevMechRender(self)
end

Events.OnServerCommand.Add(function(module, command, args)
    if module ~= AegisShared.MODULE then return end
    local panel = AegisVehicleDetail.instance
    if not panel then return end
    if KNOWN_COMMANDS[command] then panel:receive(command, args) end
end)

-- right click on (or next to) a vehicle in the world offers opening the
-- detail window directly, gated by the same rights as the vehicles page
Events.OnFillWorldObjectContextMenu.Add(function(playerNum, context, worldobjects, test)
    if test then return end
    if playerNum ~= 0 then return end
    if not (Aegis.allowed(getPlayer()) and Aegis.canSee("vehicles")) then return end
    local square = nil
    for _, obj in ipairs(worldobjects) do
        if obj and obj.getSquare then square = obj:getSquare() end
        if square then break end
    end
    if not square then return end
    -- IsoCell:getVehicles returns a java Set without get(i) in B42
    --, so ask the squares around the click
    -- instead: every occupied square knows its vehicle
    local best, bestDist = nil, 4 * 4 + 1
    pcall(function()
        local cell = getCell()
        local sx, sy, sz = square:getX(), square:getY(), square:getZ()
        for dy = -4, 4 do
            for dx = -4, 4 do
                local sq = cell:getGridSquare(sx + dx, sy + dy, sz)
                local v = sq and sq:getVehicleContainer()
                if v then
                    local d = dx * dx + dy * dy
                    if d < bestDist then best, bestDist = v, d end
                end
            end
        end
    end)
    if not best then return end
    local option = context:addOption(getText("UI_Aegis_EditVehicleContext"), nil, function()
        AegisVehicleDetail.open(best:getId(), best)
    end)
    option.iconTexture = getTexture("media/ui/Aegis/ico_shield.png")
end)

-- right click on a world container (crate, cabinet, shelf, fridge, ...)
-- offers setting its storage capacity, gated like the tools page
Events.OnFillWorldObjectContextMenu.Add(function(playerNum, context, worldobjects, test)
    if test then return end
    if playerNum ~= 0 then return end
    if not (Aegis.allowed(getPlayer()) and Aegis.canSee("tools")) then return end
    -- worldobjects usually carries only the floor: resolve the square and
    -- scan every object on it for a container (same lesson as the vehicle
    -- entry above), topmost container wins
    local target = nil
    pcall(function()
        local square = nil
        for _, obj in ipairs(worldobjects) do
            if obj and obj.getSquare then square = obj:getSquare() end
            if square then break end
        end
        if not square then return end
        local function scan(list)
            for i = 0, list:size() - 1 do
                local obj = list:get(i)
                if obj and obj.getContainerCount and obj:getContainerCount() > 0 then
                    target = obj
                end
            end
        end
        scan(square:getObjects())
        scan(square:getSpecialObjects())
    end)
    if not target then return end
    local current = 0
    pcall(function() current = target:getContainer():getCapacity() end)
    local option = context:addOption(getText("UI_Aegis_Capacity"), nil, function()
        local square = target:getSquare()
        if not square then return end
        local x, y, z = square:getX(), square:getY(), square:getZ()
        local objIndex = -1
        pcall(function() objIndex = target:getObjectIndex() end)
        local prompt = AegisPrompt.show{
            title = getText("UI_Aegis_Capacity"),
            message = getText("UI_Aegis_CapacityPrompt", tostring(current)),
            confirmLabel = getText("UI_Aegis_Apply"),
            reasonRequired = true,
            onConfirm = function(page, textValue)
                local value = tonumber(textValue)
                if not value then return end
                value = math.floor(math.max(1, math.min(1000, value)))
                sendClientCommand(getPlayer(), AegisShared.MODULE, "containerCapacity",
                    { x = x, y = y, z = z, obj = objIndex, value = value })
                Aegis.showToast(getText("UI_Aegis_CapacitySet", tostring(value)))
            end,
        }
        pcall(function() prompt.entry:setOnlyNumbers(true) end)
    end)
    option.iconTexture = getTexture("media/ui/Aegis/ico_shield.png")
end)
