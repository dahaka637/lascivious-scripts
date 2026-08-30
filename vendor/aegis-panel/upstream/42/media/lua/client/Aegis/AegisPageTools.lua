-- Tools: photo mode, power rings, construction radar and area clearing in one place
require "Aegis/AegisWindow"
require "Aegis/AegisPhotoMode"
require "Aegis/AegisPower"
require "Aegis/AegisConstruction"
require "Aegis/AegisClearing"
require "Aegis/AegisInspector"
require "Aegis/AegisBuilder"

AegisPageTools = ISPanel:derive("AegisPageTools")

function AegisPageTools.create(window, x, y, w, h)
    local o = ISPanel:new(x, y, w, h)
    setmetatable(o, AegisPageTools)
    AegisPageTools.__index = AegisPageTools
    o.background = false
    o.window = window
    o.colW = math.floor((w - 60) / 2)
    o.clDayOffset = 0
    o.clDate = AegisShared.dateShort(AegisShared.realTime())
    o.clRows = {}
    o.clMore = false
    AegisPageTools.instance = o
    return o
end

function AegisPageTools:createChildren()
    local pad = 20
    local x = pad + 14
    local w = self.colW - 28

    local y = pad + 46
    self.photoToggle = AegisToggle:new(x, y, w, 28, getText("UI_Aegis_PhotoMode"), "eye", self, function(page, checked)
        AegisPhotoMode.setOn(checked, page.weatherToggle and page.weatherToggle.checked)
    end)
    self.photoToggle.tooltip = getText("UI_Aegis_PhotoModeTooltip")
    self:addChild(self.photoToggle)
    y = y + 34
    -- sub toggle: whether photo mode also calms the weather
    self.weatherToggle = AegisToggle:new(x + 24, y, w - 24, 28, getText("UI_Aegis_PhotoWeather"), "rain", self, nil)
    self.weatherToggle:setChecked(true)
    self:addChild(self.weatherToggle)
    y = y + 34 + 14

    self.energyToggle = AegisToggle:new(x, y, w, 28, getText("UI_Aegis_PowerRange"), "bolt", self, function(page, checked)
        AegisPower.setOn(checked)
    end)
    self.energyToggle.tooltip = getText("UI_Aegis_PowerRangeTip")
    self:addChild(self.energyToggle)
    y = y + 34

    self.radarToggle = AegisToggle:new(x, y, w, 28, getText("UI_Aegis_BuildRadar"), "search", self, function(page, checked)
        AegisConstruction.setOn(checked)
    end)
    self.radarToggle.tooltip = getText("UI_Aegis_BuildRadarTooltip")
    self:addChild(self.radarToggle)
    y = y + 34

    self.inspectorToggle = AegisToggle:new(x, y, w, 28, getText("UI_Aegis_Inspector"), "search", self, function(page, checked)
        AegisInspector.setOn(checked)
    end)
    self.inspectorToggle.tooltip = getText("UI_Aegis_InspectorTooltip")
    self:addChild(self.inspectorToggle)
    y = y + 34 + 14

    self.clearAreaBtn = AegisButton:new(x, y, w, 30, getText("UI_Aegis_ClearArea"), "trash", self, function(page)
        AegisClearing.start()
    end)
    self.clearAreaBtn.style = "danger"
    self.clearAreaBtn.tooltip = getText("UI_Aegis_ClearAreaTooltip")
    self:addChild(self.clearAreaBtn)
    y = y + 30 + 8

    self.clearAreaUndoBtn = AegisButton:new(x, y, w, 28, getText("UI_Aegis_ClearAreaUndo"), "refresh", self, function(page)
        AegisClearing.undo()
    end)
    self.clearAreaUndoBtn.tooltip = getText("UI_Aegis_ClearAreaUndoTooltip")
    self:addChild(self.clearAreaUndoBtn)
    y = y + 28 + 14

    self.builderBtn = AegisButton:new(x, y, w, 30, getText("UI_Aegis_Builder"), "home", self, function(page)
        AegisBuilder.start()
    end)
    self.builderBtn.style = "gold"
    self.builderBtn.tooltip = getText("UI_Aegis_BuilderTooltip")
    self:addChild(self.builderBtn)
    self.bottom = y + 30 + 18

    -- right column: construction journal viewer
    local cx = pad + self.colW + 20
    local ix = cx + 14
    local iw = self.colW - 28
    local cy = pad + 44

    self.clPrevBtn = AegisButton:new(ix, cy, 28, 26, "<", nil, self, function(page)
        page:clShiftDay(-1)
    end)
    self:addChild(self.clPrevBtn)
    self.clNextBtn = AegisButton:new(ix + 34 + 96 + 6, cy, 28, 26, ">", nil, self, function(page)
        page:clShiftDay(1)
    end)
    self:addChild(self.clNextBtn)
    self.clTodayBtn = AegisButton:new(ix + 34 + 96 + 6 + 34, cy, 64, 26, getText("UI_Aegis_ClToday"), nil, self, function(page)
        if page.clDayOffset ~= 0 then
            page.clDayOffset = 0
            page:clSetDate()
        end
    end)
    self:addChild(self.clTodayBtn)
    self.clRefreshBtn = AegisButton:new(ix + iw - 30, cy, 30, 26, nil, "refresh", self, function(page)
        page:clRequest()
    end)
    self:addChild(self.clRefreshBtn)

    local listY = cy + 34
    local listH = self.height - pad - 26 - listY
    self.clScroll = AegisScrollArea:new(ix, listY, iw, listH)
    self:addChild(self.clScroll)
    self.clRowsPanel = ISPanel:new(0, 0, iw - 14, 10)
    self.clRowsPanel.background = false
    self.clRowsPanel.owner = self
    self.clRowsPanel.render = AegisPageTools.clRenderRows
    self.clRowsPanel.onMouseUp = AegisPageTools.clRowsMouseUp
    self.clRowsPanel.onMouseDown = function() end
    self.clScroll:addChild(self.clRowsPanel)

    -- reply hook: the stub in AegisConstruction stores the list and calls here
    AegisConstruction.onList = function(args)
        local page = AegisPageTools.instance
        if page then page:clReceive(args) end
    end
end

function AegisPageTools:onShow()
    self:clRequest()
end

-- ---------- construction log ----------
local function clRowH()
    return Aegis.fontH(UIFont.Small) * 2 + 10
end

function AegisPageTools:clShiftDay(delta)
    local offset = self.clDayOffset + delta
    if offset > 0 then offset = 0 end
    if offset == self.clDayOffset then return end
    self.clDayOffset = offset
    self:clSetDate()
end

function AegisPageTools:clSetDate()
    self.clDate = AegisShared.dateShort(AegisShared.realTime() + self.clDayOffset * 86400)
    self.clRows = {}
    self.clMore = false
    self:clLayout()
    self.clScroll:setYScroll(0)
    self:clRequest()
end

function AegisPageTools:clRequest()
    AegisConstruction.requestList(self.clDate, 200)
end

-- line format: time|user|action|x,y,z|sprite|kind|north|parts (see
-- server Aegis_Construction.lua); trailing fields are optional, older
-- lines without them still parse fine (kind falls back to "object").
-- parts carries multi-tile structures as "x,y,z,sprite,north,floor;..."
local function clParseParts(text)
    if type(text) ~= "string" or text == "" then return nil end
    local parts = {}
    for entry in text:gmatch("[^;]+") do
        local px, py, pz, sprite, north, floor =
            entry:match("^(-?%d+),(-?%d+),(-?%d+),([^,]+),([01]),([01])$")
        if px then
            table.insert(parts, {
                x = tonumber(px), y = tonumber(py), z = tonumber(pz),
                sprite = sprite, north = north == "1", floor = floor == "1",
            })
        end
    end
    if #parts == 0 then return nil end
    return parts
end

local function clParse(line)
    if type(line) ~= "string" then return nil end
    local time, user, action, coords, rest = line:match("^([^|]*)|([^|]*)|([^|]*)|([^|]*)|(.*)$")
    if not time then return nil end
    local x, y, z = coords:match("^(-?%d+),(-?%d+),(-?%d+)$")
    local sprite, kind, north, partsText = rest:match("^(.-)|([^|]*)|([^|]*)|([^|]*)$")
    if not sprite then
        sprite, kind, north = rest:match("^(.-)|([^|]*)|([^|]*)$")
    end
    if not sprite then sprite, kind, north = rest, "object", "" end
    return {
        time = time, user = user, action = action, sprite = sprite,
        kind = kind ~= "" and kind or "object", north = north == "1",
        parts = clParseParts(partsText),
        x = tonumber(x), y = tonumber(y), z = tonumber(z),
    }
end

function AegisPageTools:clReceive(args)
    if not args or args.date ~= self.clDate then return end
    local rows = {}
    -- newest first: the file is chronological, walk it backwards
    local lines = args.lines or {}
    for i = #lines, 1, -1 do
        local row = clParse(lines[i])
        if row then table.insert(rows, row) end
    end
    self.clRows = rows
    self.clMore = args.more == true
    self:clLayout()
end

function AegisPageTools:clLayout()
    if not self.clRowsPanel then return end
    self.clRowsPanel:setHeight(math.max(10, #self.clRows * clRowH() + 8))
    self.clScroll:setScrollHeight(self.clRowsPanel.height)
end

local function clActionText(action)
    if action == "bau" then return getText("UI_Aegis_ClBuilt") end
    if action == "abriss" then return getText("UI_Aegis_ClRemoved") end
    return tostring(action)
end

function AegisPageTools.clRenderRows(panel)
    local page = panel.owner
    local c = Aegis.col
    local f = UIFont.Small
    local lineH = Aegis.fontH(f)
    local rowH = clRowH()
    local w = panel.width
    local hoverIdx = nil
    if panel:isMouseOver() then
        hoverIdx = math.floor((panel:getMouseY() - 4) / rowH) + 1
    end
    local y = 4
    for i, row in ipairs(page.clRows) do
        if i == hoverIdx then
            Aegis.roundRect(panel, 0, y, w, rowH - 2, 6, 0.5, c.card)
        end
        local built = row.action == "bau"
        local markC = built and c.gold or c.danger
        Aegis.text(panel, row.time, 8, y + 4, f, c.muted)
        local tx = 8 + Aegis.strW(f, "00:00:00") + 10
        Aegis.roundRect(panel, tx, y + 4 + math.floor(lineH / 2) - 3, 6, 6, 3, 1, markC)
        tx = tx + 12
        local actionText = clActionText(row.action)
        Aegis.text(panel, actionText, tx, y + 4, f, markC)
        tx = tx + Aegis.strW(f, actionText) + 8
        local coords = (row.x and row.y) and (tostring(row.x) .. "," .. tostring(row.y)) or ""
        local coordsW = Aegis.strW(f, coords)
        -- restore icon: only on demolish rows, sits left of the coordinates
        local restoreW = 0
        if row.action == "abriss" then
            restoreW = lineH + 6
            local ix = w - 8 - coordsW - restoreW
            Aegis.icon(panel, "refresh", ix, y + 3, lineH, 1, c.gold)
        end
        Aegis.text(panel, Aegis.fitText(row.user, f, w - tx - coordsW - restoreW - 16), tx, y + 4, f, c.text)
        Aegis.textRight(panel, coords, w - 8, y + 4, f, c.goldDim)
        Aegis.text(panel, Aegis.fitText(row.sprite or "?", f, w - 16), 8, y + 4 + lineH + 2, f, c.muted)
        y = y + rowH
    end
end

function AegisPageTools.clRowsMouseUp(panel, x, y)
    local page = panel.owner
    local idx = math.floor((y - 4) / clRowH()) + 1
    local row = page.clRows[idx]
    if not row or not row.x then return end

    -- restore icon hit test: same geometry as clRenderRows, only present
    -- on demolish rows
    if row.action == "abriss" and Aegis.canSee("tools") then
        local f = UIFont.Small
        local lineH = Aegis.fontH(f)
        local w = panel.width
        local coords = tostring(row.x) .. "," .. tostring(row.y)
        local coordsW = Aegis.strW(f, coords)
        local restoreW = lineH + 6
        local ix = w - 8 - coordsW - restoreW
        local rowY = 4 + (idx - 1) * clRowH()
        if x >= ix - 4 and x <= ix + restoreW and y >= rowY and y <= rowY + lineH + 8 then
            -- ghost preview in the world replaces the text confirm: the card it brings along carries the actual
            -- restore button
            AegisRestorePreview.start(row)
            return
        end
    end

    if not Aegis.canSee("world") then return end
    AegisConfirm.show(getText("UI_Aegis_ConstructionLog"),
        getText("UI_Aegis_ClTeleport") .. "  (" .. row.x .. "," .. row.y .. "," .. row.z .. ")",
        getText("UI_Aegis_MapTeleport"), page, function()
            -- same mechanic as the world map patch in AegisHud.lua
            Aegis.teleportSmart(row.x, row.y, row.z)
            Aegis.logAction("world", string.format("Construction log teleport to %d,%d,%d", row.x, row.y, row.z))
            Aegis.showToast(getText("UI_Aegis_MapTeleport") .. ": " .. row.x .. "," .. row.y)
        end)
end

function AegisPageTools:prerender()
    if not self.bottom then return end
    local c = Aegis.col
    local pad = 20
    Aegis.roundFrame(self, pad, pad, self.colW, self.bottom - pad, 10, 1, c.line, c.panel)
    Aegis.icon(self, "wand", pad + 14, pad + 12, 15, 1, c.gold)
    Aegis.text(self, getText("UI_Aegis_NavTools"), pad + 36, pad + 10, UIFont.Medium, c.text)

    -- toggles mirror the real state, photo mode can also end via hotkey
    if self.photoToggle then self.photoToggle:setChecked(AegisPhotoMode.isOn()) end
    if self.energyToggle then self.energyToggle:setChecked(AegisPower.isOn()) end
    if self.radarToggle then self.radarToggle:setChecked(AegisConstruction.isOn()) end
    if self.inspectorToggle then self.inspectorToggle:setChecked(AegisInspector.isOn()) end

    -- right card: construction journal
    local cx = pad + self.colW + 20
    Aegis.roundFrame(self, cx, pad, self.colW, self.height - pad * 2, 10, 1, c.line, c.panel)
    Aegis.icon(self, "clock", cx + 14, pad + 12, 15, 1, c.gold)
    Aegis.text(self, getText("UI_Aegis_ConstructionLog"), cx + 36, pad + 10, UIFont.Medium, c.text)

    if self.clPrevBtn then
        -- date label centered between the arrow buttons
        local lx = cx + 14 + 34
        local lw = 96
        local dw = Aegis.strW(UIFont.Small, self.clDate)
        Aegis.text(self, self.clDate, lx + math.floor((lw - dw) / 2),
            pad + 44 + math.floor((26 - Aegis.fontH(UIFont.Small)) / 2), UIFont.Small,
            self.clDayOffset == 0 and c.goldHi or c.text)
        self.clNextBtn:setEnabled(self.clDayOffset < 0)
        self.clTodayBtn:setEnabled(self.clDayOffset < 0)

        if #self.clRows == 0 then
            local hint = getText("UI_Aegis_ClEmpty")
            local hw = Aegis.strW(UIFont.Small, hint)
            Aegis.text(self, hint, cx + math.floor((self.colW - hw) / 2),
                self.clScroll.y + math.floor(self.clScroll.height / 2) - 8, UIFont.Small, c.muted)
        elseif self.clMore then
            local hint = getText("UI_Aegis_ClMore")
            local hw = Aegis.strW(UIFont.Small, hint)
            Aegis.text(self, hint, cx + math.floor((self.colW - hw) / 2),
                self.height - pad - 20, UIFont.Small, c.muted)
        end
    end
end

AegisWindow.registerPage({
    id = "tools",
    icon = "wand",
    label = "UI_Aegis_NavTools",
    create = AegisPageTools.create,
})
