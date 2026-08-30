-- Log browser: area and entries from the server manifest on the left,
-- content of the clicked file on the right
require "Aegis/AegisWindow"
require "ISUI/ISScrollingListBox"
require "ISUI/ISComboBox"

AegisPageLogs = ISPanel:derive("AegisPageLogs")
AegisLogClient = AegisLogClient or {}

local LIST_W = 320
local ROW_H = 46

function AegisPageLogs.create(window, x, y, w, h)
    local o = ISPanel:new(x, y, w, h)
    setmetatable(o, AegisPageLogs)
    AegisPageLogs.__index = AegisPageLogs
    o.background = false
    o.window = window
    o.area = AegisShared.LOG_AREAS[1]
    o.entries = {}
    o.allEntries = {}
    o.days = {}
    o.day = ""
    o.total = 0
    o.lines = nil
    o.selectedEntry = nil
    o.nextPoll = 0
    AegisPageLogs.instance = o
    return o
end

-- The list used to refresh only on page switch or click; leaving the page
-- open while doing things showed stale data. The opened file follows along,
-- otherwise appended lines stayed invisible; hidden (other tab) is not
-- polled, the engine keeps calling update() for hidden children too.
-- Clock-based interval instead of frames, otherwise a 144 FPS client
-- polls the server every second
function AegisPageLogs:update()
    ISPanel.update(self)
    if not self:getIsVisible() then return end
    local now = getTimestampMs()
    if now < (self.nextPoll or 0) then return end
    self.nextPoll = now + 2000
    self:requestList()
    if self.selectedEntry and self.selectedEntry.path then
        local p = getPlayer()
        if p then
            sendClientCommand(p, AegisShared.MODULE, "logRead", { path = self.selectedEntry.path })
        end
    end
end

function AegisPageLogs:createChildren()
    local pad = 20

    -- area on the left, day on the right: a busy area piles up hundreds of
    -- entries and scrolling to a specific day was the only way through
    local comboW = math.floor((LIST_W - 48) / 2)
    self.areaCombo = ISComboBox:new(pad + 1, pad + 6, comboW, 26, self, AegisPageLogs.onArea)
    self.areaCombo:initialise()
    for _, b in ipairs(AegisShared.LOG_AREAS) do
        self.areaCombo:addOption(getText("UI_Aegis_Log" .. b))
    end
    self.areaCombo.selected = 1
    self:addChild(self.areaCombo)

    self.dayCombo = ISComboBox:new(pad + 9 + comboW, pad + 6, comboW, 26, self, AegisPageLogs.onDay)
    self.dayCombo:initialise()
    self.dayCombo:addOption(getText("UI_Aegis_LogAllDays"))
    self.dayCombo.selected = 1
    self:addChild(self.dayCombo)

    self.refreshBtn = AegisButton:new(pad + LIST_W - 32, pad + 5, 30, 28, nil, "refresh", self, AegisPageLogs.requestList)
    self:addChild(self.refreshBtn)

    self.list = ISScrollingListBox:new(pad + 1, pad + 44, LIST_W - 2, self.height - pad * 2 - 66)
    self.list:initialise()
    self.list:instantiate()
    self.list.itemheight = ROW_H
    self.list.font = UIFont.Medium
    self.list.drawBorder = false
    self.list.backgroundColor = { r = 0, g = 0, b = 0, a = 0 }
    self.list.doDrawItem = AegisPageLogs.drawRow
    self.list:setOnMouseDownFunction(self, AegisPageLogs.onSelect)
    self:addChild(self.list)

    -- content on the right as scrollable text
    local dx = pad + LIST_W + 20
    local dw = self.width - dx - pad
    self.scroll = AegisScrollArea:new(dx + 12, pad + 44, dw - 24, self.height - pad * 2 - 58)
    self:addChild(self.scroll)

    self.textPanel = ISPanel:new(0, 0, self.scroll.width - 16, 10)
    self.textPanel.background = false
    self.textPanel.owner = self
    self.textPanel.render = AegisPageLogs.renderText
    self.scroll:addChild(self.textPanel)
end

function AegisPageLogs:onShow()
    self:requestList()
end

function AegisPageLogs.onArea(self)
    local idx = self.areaCombo.selected or 1
    self.area = AegisShared.LOG_AREAS[idx] or AegisShared.LOG_AREAS[1]
    -- a day of one area says nothing about the next, start wide again
    self.day = ""
    self:requestList()
end

function AegisPageLogs.onDay(self)
    local idx = self.dayCombo.selected or 1
    self.day = (idx > 1 and self.days and self.days[idx - 1]) or ""
    self:fillList()
end

function AegisPageLogs.requestList(self)
    local p = getPlayer()
    if not p then return end
    sendClientCommand(p, AegisShared.MODULE, "logList", { area = self.area })
end

function AegisPageLogs:setEntries(entries, total)
    self.allEntries = entries or {}
    self.total = total or #self.allEntries
    -- day options from what actually arrived, newest first. Rebuilt on
    -- every poll, so the picked day is restored by its NAME and not by an
    -- index that shifts as soon as a new day appears
    local seen, days = {}, {}
    for _, e in ipairs(self.allEntries) do
        local d = AegisShared.dateShort(e.epoch or 0)
        if not seen[d] then
            seen[d] = true
            table.insert(days, d)
        end
    end
    table.sort(days, function(a, b) return a > b end)
    self.days = days
    if self.day and self.day ~= "" and not seen[self.day] then
        -- the chosen day fell out of the window, do not silently show
        -- another one
        self.day = ""
    end
    self.dayCombo:clear()
    self.dayCombo:addOption(getText("UI_Aegis_LogAllDays"))
    local pick = 1
    for i, d in ipairs(days) do
        self.dayCombo:addOption(d)
        if d == self.day then pick = i + 1 end
    end
    self.dayCombo.selected = pick
    self:fillList()
end

-- list from allEntries through the day filter; separate from setEntries so
-- switching the day needs no server round trip
function AegisPageLogs:fillList()
    -- keep the selection across auto refresh: otherwise the log being read
    -- would collapse on its own every few seconds
    local previousPath = self.selectedEntry and self.selectedEntry.path
    local out = {}
    for _, e in ipairs(self.allEntries or {}) do
        if self.day == nil or self.day == ""
            or AegisShared.dateShort(e.epoch or 0) == self.day then
            table.insert(out, e)
        end
    end
    self.entries = out
    self.list:clear()
    self.list.selected = -1
    local found = false
    for i, e in ipairs(self.entries) do
        self.list:addItem(e.target or "", e)
        if previousPath and e.path == previousPath then
            self.list.selected = i
            found = true
        end
    end
    if not found then
        self.selectedEntry = nil
        self.lines = nil
    end
    self:layoutText()
end

function AegisPageLogs:setRows(lines)
    self.lines = lines or {}
    self:layoutText()
end

-- deliberately does not reset the scroll: auto refresh would throw the
-- reading position back to the top every couple of seconds; only clicking
-- another entry resets it (onSelect)
function AegisPageLogs:layoutText()
    local lineH = Aegis.fontH(UIFont.Small) + 4
    local n = self.lines and #self.lines or 0
    self.textPanel:setHeight(math.max(10, n * lineH + 8))
    self.scroll:setScrollHeight(self.textPanel.height)
end

function AegisPageLogs.drawRow(list, y, item, alt)
    local c = Aegis.col
    local sel = list.selected == item.index
    local hover = list.mouseoverselected == item.index

    if sel then
        Aegis.roundRect(list, 2, y + 2, list:getWidth() - 4, ROW_H - 4, 8, 1, c.card)
        Aegis.roundRect(list, 2, y + 10, 3, ROW_H - 20, 1, 1, c.gold)
    elseif hover then
        Aegis.roundRect(list, 2, y + 2, list:getWidth() - 4, ROW_H - 4, 8, 0.5, c.card)
    end

    local e = item.item
    local tc = sel and c.text or c.muted
    Aegis.text(list, AegisShared.timestampReadable(e.epoch or 0), 14, y + 5, UIFont.Small, tc)
    local bottomLine = tostring(e.admin or "") .. " / " .. tostring(e.target or "")
    Aegis.text(list, Aegis.fitText(bottomLine, UIFont.Small, list:getWidth() - 90), 14, y + 7 + Aegis.fontH(UIFont.Small), UIFont.Small, c.muted)
    if e.status == "archiviert" then
        Aegis.textRight(list, getText("UI_Aegis_LogArchive"), list:getWidth() - 12, y + 5, UIFont.Small, c.goldDim)
    end
    return y + ROW_H
end

function AegisPageLogs.onSelect(self, item)
    self.selectedEntry = item
    self.lines = nil
    self:layoutText()
    self.scroll:setYScroll(0)
    if not item or not item.path then return end
    local p = getPlayer()
    if not p then return end
    sendClientCommand(p, AegisShared.MODULE, "logRead", { path = item.path })
end

function AegisPageLogs.renderText(panel)
    local page = panel.owner
    if not page.lines then return end
    local c = Aegis.col
    local lineH = Aegis.fontH(UIFont.Small) + 4
    local y = 4
    for _, line in ipairs(page.lines) do
        Aegis.text(panel, line, 4, y, UIFont.Small, c.text)
        y = y + lineH
    end
end

function AegisPageLogs:prerender()
    local c = Aegis.col
    local pad = 20

    -- left card: list
    Aegis.roundFrame(self, pad, pad + 38, LIST_W, self.height - pad * 2 - 54, 10, 1, c.line, c.panel)
    local count = #self.entries
    local info = count .. " " .. getText("UI_Aegis_LogEntries")
    -- with a day picked the honest reference is what the day hid, not the
    -- server's archive note
    if self.day and self.day ~= "" then
        info = info .. " / " .. #(self.allEntries or {})
    elseif self.total > count then
        info = info .. " (" .. getText("UI_Aegis_LogOlder") .. ")"
    end
    Aegis.text(self, info, pad + 4, self.height - pad - 12, UIFont.Small, c.muted)

    -- right card: content
    local dx = pad + LIST_W + 20
    local dw = self.width - dx - pad
    Aegis.roundFrame(self, dx, pad, dw, self.height - pad * 2, 10, 1, c.line, c.panel)
    Aegis.icon(self, "logs", dx + 14, pad + 12, 15, 1, c.gold)
    if self.selectedEntry then
        local title = tostring(self.selectedEntry.target or "") .. "  " .. AegisShared.timestampReadable(self.selectedEntry.epoch or 0)
        Aegis.text(self, Aegis.fitText(title, UIFont.Medium, dw - 60), dx + 36, pad + 10, UIFont.Medium, c.text)
    else
        Aegis.text(self, getText("UI_Aegis_LogPick"), dx + 36, pad + 10, UIFont.Medium, c.muted)
    end
end

-- server responses, in solo the server side calls in here directly
function AegisLogClient.receive(command, args)
    local page = AegisPageLogs.instance
    if not page or not args then return end
    if command == "logList" then
        if args.area == page.area then
            page:setEntries(args.entries, args.total)
        end
    elseif command == "logRead" then
        if page.selectedEntry and args.path == page.selectedEntry.path then
            page:setRows(args.lines)
        end
    end
end

Events.OnServerCommand.Add(function(module, command, args)
    if module ~= "AegisAdmin" then return end
    if command == "logList" or command == "logRead" then
        AegisLogClient.receive(command, args)
    end
end)

AegisWindow.registerPage({
    id = "logs",
    icon = "logs",
    label = "UI_Aegis_NavLogs",
    create = AegisPageLogs.create,
})
