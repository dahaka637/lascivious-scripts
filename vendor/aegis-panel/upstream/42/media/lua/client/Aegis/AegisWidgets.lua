-- Building blocks of the Aegis UI: button, toggle, slider, confirm dialog
require "ISUI/ISPanel"
require "Aegis/AegisTheme"

-- ==================================================================
-- AegisScrollArea: generic scroll container with real pixel clipping
-- (setScrollChildren alone does NOT clip, see ISCollapsableWindow's
-- clearStentil pattern: set stencil in prerender, clear it in render)
-- plus mouse wheel support (default onMouseWheel is a no-op otherwise).
-- ==================================================================
AegisScrollArea = ISPanel:derive("AegisScrollArea")

function AegisScrollArea:new(x, y, w, h)
    local o = ISPanel:new(x, y, w, h)
    setmetatable(o, self)
    self.__index = self
    o.background = false
    o:initialise()
    o:instantiate()
    o:setScrollChildren(true)
    o:addScrollBars()
    o.vscroll.doSetStencil = true
    return o
end

-- lists, combos and rich text clear the stencil once they are done drawing
-- and only repaint the freed area when asked. Inside a scrolling parent
-- that leaves the pixels of scrolled out rows standing (vanilla sets the
-- same flag by hand, e.g. ISModalEditRole), so every child gets it here
function AegisScrollArea:addChild(child)
    ISPanel.addChild(self, child)
    if child then child.doRepaintStencil = true end
    return child
end

function AegisScrollArea:prerender()
    ISPanel.prerender(self)
    self:setStencilRect(0, 0, self.width, self.height)
end

function AegisScrollArea:render()
    self:clearStencilRect()
end

function AegisScrollArea:onMouseWheel(del)
    self:setYScroll(self:getYScroll() - del * 48)
    return true
end

-- ==================================================================
-- AegisButton: flat premium button with icon and hover animation
-- Styles: ghost (default), gold, danger
-- ==================================================================
AegisButton = ISPanel:derive("AegisButton")

function AegisButton:new(x, y, w, h, label, icon, target, onClick)
    local o = ISPanel:new(x, y, w, h)
    setmetatable(o, self)
    self.__index = self
    o.background = false
    o.label = label
    o.icon = icon
    o.target = target
    o.onClick = onClick
    o.style = "ghost"
    o.radius = 8
    o.font = UIFont.Small
    o.iconSize = 16
    o.enabled = true
    o.hoverT = 0
    o.pressed = false
    o.hovered = false
    return o
end

function AegisButton:setEnabled(b)
    self.enabled = b and true or false
    if not self.enabled then self.pressed = false end
end

function AegisButton:prerender()
    Aegis.updateTooltip(self)
end

function AegisButton:render()
    local c = Aegis.col
    local w, h = self.width, self.height
    local r = math.min(self.radius, math.floor(h / 2))
    self.hoverT = Aegis.glide(self.hoverT, (self.enabled and self.hovered) and 1 or 0, 0.35)
    local a = self.enabled and 1 or 0.35
    local textC = c.text
    local iconC = c.muted

    if self.style == "gold" then
        Aegis.roundRect(self, 0, 0, w, h, r, a, c.gold)
        if self.hoverT > 0.01 then
            Aegis.roundRect(self, 0, 0, w, h, r, 0.20 * self.hoverT * a, c.white)
        end
        if self.pressed then
            Aegis.roundRect(self, 0, 0, w, h, r, 0.22, c.dark)
        end
        textC = c.dark
        iconC = c.dark
    elseif self.style == "danger" then
        Aegis.roundRect(self, 0, 0, w, h, r, a, c.danger)
        Aegis.roundRect(self, 1, 1, w - 2, h - 2, math.max(1, r - 1), a * (0.82 - 0.35 * self.hoverT), c.bg)
        if self.pressed then
            Aegis.roundRect(self, 0, 0, w, h, r, 0.25, c.danger)
        end
        textC = c.danger
        iconC = c.danger
    else
        Aegis.roundRect(self, 0, 0, w, h, r, a, c.line)
        Aegis.roundRect(self, 1, 1, w - 2, h - 2, math.max(1, r - 1), a, c.card)
        if self.hoverT > 0.01 then
            Aegis.roundRect(self, 1, 1, w - 2, h - 2, math.max(1, r - 1), 0.6 * self.hoverT * a, c.cardHi)
        end
        if self.pressed then
            Aegis.roundRect(self, 1, 1, w - 2, h - 2, math.max(1, r - 1), 0.35, c.dark)
        end
        if self.hovered and self.enabled then iconC = c.gold end
    end

    local iw = self.icon and self.iconSize or 0
    local gap = (self.icon and self.label) and 7 or 0
    local label = self.label
    if label then
        local availW = w - 12 - iw - gap
        if self._fitSrc ~= label or self._fitW ~= availW then
            self._fitSrc = label
            self._fitW = availW
            self._fitLabel = Aegis.fitText(label, self.font, availW)
            if self._fitLabel ~= label and not self.tooltip then
                self.tooltip = label
            end
        end
        label = self._fitLabel
    end
    local tw = label and Aegis.strW(self.font, label) or 0
    local cx = math.floor((w - tw - iw - gap) / 2)
    if self.icon then
        Aegis.icon(self, self.icon, cx, math.floor((h - iw) / 2), iw, a, iconC)
        cx = cx + iw + gap
    end
    if label then
        Aegis.text(self, label, cx, math.floor((h - Aegis.fontH(self.font)) / 2), self.font, textC, a)
    end
end

function AegisButton:onMouseMove(dx, dy) self.hovered = true end
function AegisButton:onMouseMoveOutside(dx, dy) self.hovered = false end
function AegisButton:onMouseDown(x, y)
    if self.enabled then self.pressed = true end
end
function AegisButton:onMouseUpOutside(x, y) self.pressed = false end

function AegisButton:onMouseUp(x, y)
    if self.pressed and self.enabled then
        self.pressed = false
        Aegis.sound()
        if self.onClick then self.onClick(self.target, self) end
        return
    end
    self.pressed = false
end

-- ==================================================================
-- AegisToggle: switch with sliding knob, label on the left
-- ==================================================================
AegisToggle = ISPanel:derive("AegisToggle")

function AegisToggle:new(x, y, w, h, label, icon, target, onChange)
    local o = ISPanel:new(x, y, w, h)
    setmetatable(o, self)
    self.__index = self
    o.background = false
    o.label = label
    o.icon = icon
    o.target = target
    o.onChange = onChange
    o.checked = false
    o.knobT = 0
    o.hovered = false
    o.enabled = true
    o.font = UIFont.Small
    return o
end

function AegisToggle:setChecked(b)
    self.checked = b and true or false
end

function AegisToggle:setEnabled(b)
    self.enabled = b and true or false
    if not self.enabled then self.pressed = false end
end

function AegisToggle:prerender()
    Aegis.updateTooltip(self)
end

function AegisToggle:render()
    local c = Aegis.col
    local w, h = self.width, self.height
    local a = self.enabled and 1 or 0.35
    self.knobT = Aegis.glide(self.knobT, self.checked and 1 or 0, 0.3)

    local tx = 0
    if self.icon then
        Aegis.icon(self, self.icon, 0, math.floor((h - 16) / 2), 16, a, self.checked and c.gold or c.muted)
        tx = 24
    end
    local availW = w - 38 - 10 - tx
    if self._fitSrc ~= self.label or self._fitW ~= availW then
        self._fitSrc = self.label
        self._fitW = availW
        self._fitLabel = Aegis.fitText(self.label, self.font, availW)
        if self._fitLabel ~= self.label and not self.tooltip then
            self.tooltip = self.label
        end
    end
    Aegis.text(self, self._fitLabel, tx, math.floor((h - Aegis.fontH(self.font)) / 2), self.font,
        self.hovered and c.text or (self.checked and c.text or c.muted), a)

    local tw, th = 38, 20
    local sx = w - tw
    local sy = math.floor((h - th) / 2)
    Aegis.roundRect(self, sx, sy, tw, th, math.floor(th / 2), a, c.line)
    Aegis.roundRect(self, sx + 1, sy + 1, tw - 2, th - 2, math.floor(th / 2) - 1, a, c.panel)
    if self.knobT > 0.01 then
        Aegis.roundRect(self, sx, sy, tw, th, math.floor(th / 2), self.knobT * a, c.gold)
    end
    local kd = th - 6
    local kx = sx + 3 + (tw - 6 - kd) * self.knobT
    local dot = Aegis.tex("dot")
    if dot then
        local kc = self.knobT > 0.5 and c.dark or c.text
        self:drawTextureScaled(dot, kx, sy + 3, kd, kd, a, kc.r, kc.g, kc.b)
    end
end

function AegisToggle:onMouseMove(dx, dy) self.hovered = true end
function AegisToggle:onMouseMoveOutside(dx, dy) self.hovered = false end
function AegisToggle:onMouseDown(x, y)
    if self.enabled then self.pressed = true end
end
function AegisToggle:onMouseUpOutside(x, y) self.pressed = false end

function AegisToggle:onMouseUp(x, y)
    if not self.pressed or not self.enabled then return end
    self.pressed = false
    self.checked = not self.checked
    Aegis.sound()
    if self.onChange then self.onChange(self.target, self.checked, self) end
end

-- ==================================================================
-- AegisSlider: track with gold fill, value readout on the right
-- ==================================================================
AegisSlider = ISPanel:derive("AegisSlider")

function AegisSlider:new(x, y, w, h, target, onChange)
    local o = ISPanel:new(x, y, w, h)
    setmetatable(o, self)
    self.__index = self
    o.background = false
    o.target = target
    o.onChange = onChange
    o.min = 0
    o.max = 100
    o.step = 1
    o.value = 0
    o.suffix = ""
    o.dragging = false
    o.hovered = false
    o.valueW = 46
    return o
end

function AegisSlider:setValues(min, max, step, suffix)
    self.min = min
    self.max = max
    self.step = step or 1
    self.suffix = suffix or ""
    if self.value < min then self.value = min end
    if self.value > max then self.value = max end
end

function AegisSlider:setValue(v, silent)
    if v < self.min then v = self.min end
    if v > self.max then v = self.max end
    v = self.min + math.floor((v - self.min) / self.step + 0.5) * self.step
    if v ~= self.value then
        self.value = v
        if not silent and self.onChange then self.onChange(self.target, v, self) end
    end
end

function AegisSlider:trackW()
    return self.width - self.valueW - 12
end

function AegisSlider:applyMouse(mx)
    local p = (mx - 7) / (self:trackW() - 14)
    if p < 0 then p = 0 end
    if p > 1 then p = 1 end
    self:setValue(self.min + p * (self.max - self.min))
end

function AegisSlider:render()
    local c = Aegis.col
    local h = self.height
    local tw = self:trackW()
    local ty = math.floor(h / 2) - 2
    local p = (self.max > self.min) and (self.value - self.min) / (self.max - self.min) or 0

    Aegis.roundRect(self, 0, ty, tw, 4, 2, 1, c.line)
    if p > 0 then
        Aegis.roundRect(self, 0, ty, math.max(4, tw * p), 4, 2, 1, c.gold)
    end
    local kd = 14
    local kx = 7 + (tw - 14) * p - kd / 2
    local dot = Aegis.tex("dot")
    if dot then
        self:drawTextureScaled(dot, kx - 1, ty + 2 - kd / 2 - 1, kd + 2, kd + 2, 1, c.dark.r, c.dark.g, c.dark.b)
        local kc = (self.dragging or self.hovered) and c.goldHi or c.text
        self:drawTextureScaled(dot, kx, ty + 2 - kd / 2, kd, kd, 1, kc.r, kc.g, kc.b)
    end
    Aegis.textRight(self, tostring(self.value) .. self.suffix, self.width, math.floor((h - Aegis.fontH(UIFont.Small)) / 2), UIFont.Small, c.text)
end

function AegisSlider:onMouseDown(x, y)
    self.dragging = true
    self:applyMouse(x)
end

function AegisSlider:onMouseMove(dx, dy)
    self.hovered = true
    if self.dragging then self:applyMouse(self:getMouseX()) end
end

function AegisSlider:onMouseMoveOutside(dx, dy)
    self.hovered = false
    if self.dragging then self:applyMouse(self:getMouseX()) end
end

function AegisSlider:onMouseUp(x, y) self.dragging = false end
function AegisSlider:onMouseUpOutside(x, y) self.dragging = false end

-- ==================================================================
-- AegisConfirm: dimmed fullscreen confirmation before destructive actions
-- ==================================================================
AegisConfirm = ISPanel:derive("AegisConfirm")

-- widest a dialog card may get before the text wraps instead. Measured over
-- all thirteen languages a single line would need up to 1275 px, which is no
-- card anymore; 700 keeps every existing message at two lines
local DIALOG_MAX_W = 700

local function dialogCap(sw)
    return math.max(240, math.min(DIALOG_MAX_W, sw - 80))
end

function AegisConfirm.show(title, message, confirmLabel, target, onConfirm)
    local sw, sh = getCore():getScreenWidth(), getCore():getScreenHeight()
    local o = ISPanel:new(0, 0, sw, sh)
    setmetatable(o, AegisConfirm)
    AegisConfirm.__index = AegisConfirm
    o.background = true
    o.backgroundColor = { r = 0, g = 0, b = 0, a = 0.55 }
    o.borderColor = { r = 0, g = 0, b = 0, a = 0 }
    o.title = title
    o.message = message or ""

    -- card grows with the message up to the cap, from there it wraps
    local cap = dialogCap(sw)
    local w = Aegis.strW(UIFont.Small, o.message) + 40
    if w < 400 then w = 400 end
    if w > cap then w = cap end
    o.cardW = w
    o.lineH = Aegis.fontH(UIFont.Small)
    o.msgTop = 14 + Aegis.fontH(UIFont.Medium) + 8
    -- everything above and below the message block
    local chromeH = o.msgTop + 20 + 36 + 16
    local maxRows = math.max(1, math.floor((math.max(200, sh - 60) - chromeH) / o.lineH))
    o.lines = Aegis.wrapText(o.message, UIFont.Small, o.cardW - 40, maxRows)
    -- 168 was the old fixed height, keep it as the floor so one and two line
    -- dialogs look exactly as before
    o.cardH = math.max(168, chromeH + #o.lines * o.lineH)
    o:initialise()
    o:addToUIManager()
    o:setAlwaysOnTop(true)

    local cx = math.floor((sw - o.cardW) / 2)
    local cy = math.floor((sh - o.cardH) / 2)
    local bw = math.floor((o.cardW - 48) / 2)
    local cancel = AegisButton:new(cx + 16, cy + o.cardH - 52, bw, 36, getText("UI_Aegis_Cancel"), nil, o, AegisConfirm.onCancel)
    o:addChild(cancel)
    local confirm = AegisButton:new(cx + 32 + bw, cy + o.cardH - 52, bw, 36, confirmLabel, nil, o, function(panel)
        panel:removeFromUIManager()
        if onConfirm then onConfirm(target) end
    end)
    confirm.style = "danger"
    o:addChild(confirm)
    return o
end

function AegisConfirm:onCancel()
    self:removeFromUIManager()
end

function AegisConfirm:prerender()
    ISPanel.prerender(self)
    local c = Aegis.col
    local cx = math.floor((self.width - self.cardW) / 2)
    local cy = math.floor((self.height - self.cardH) / 2)
    Aegis.shadow(self, cx, cy, self.cardW, self.cardH, 26, 0.7)
    Aegis.roundFrame(self, cx, cy, self.cardW, self.cardH, 12, 1, c.line, c.bg)
    Aegis.text(self, self.title, cx + 16, cy + 14, UIFont.Medium, c.text)
    local ty = cy + self.msgTop
    for _, line in ipairs(self.lines) do
        Aegis.text(self, line, cx + 16, ty, UIFont.Small, c.muted)
        ty = ty + self.lineH
    end
end

-- ==================================================================
-- AegisPrompt: confirmation with reason input and optional choice chips
-- (e.g. ban duration). onConfirm(target, reason, choice)
-- ==================================================================
AegisPrompt = ISPanel:derive("AegisPrompt")

-- opts = { title, message, confirmLabel, danger, reasonRequired, chips = {{label, value}}, target, onConfirm }
function AegisPrompt.show(opts)
    local sw, sh = getCore():getScreenWidth(), getCore():getScreenHeight()
    local o = ISPanel:new(0, 0, sw, sh)
    setmetatable(o, AegisPrompt)
    AegisPrompt.__index = AegisPrompt
    o.background = true
    o.backgroundColor = { r = 0, g = 0, b = 0, a = 0.55 }
    o.borderColor = { r = 0, g = 0, b = 0, a = 0 }
    o.opts = opts
    o.choice = opts.chips and opts.chips[1].value or nil

    local message = opts.message or ""
    -- the red hint later replaces the message in place. Reserve for the
    -- wider and taller of the two so the card cannot resize under the user
    local warn = opts.reasonRequired and getText("UI_Aegis_ReasonMissing") or ""

    local cap = dialogCap(sw)
    local w = math.max(Aegis.strW(UIFont.Small, message), Aegis.strW(UIFont.Small, warn)) + 40
    if opts.chips then
        -- a chip row that fits on one line beats a narrow card
        local rowW = -8
        for _, chip in ipairs(opts.chips) do
            rowW = rowW + Aegis.strW(UIFont.Small, chip.label) + 24 + 8
        end
        if rowW + 40 > w then w = rowW + 40 end
    end
    if w < 460 then w = 460 end
    if w > cap then w = cap end
    o.cardW = w

    local innerW = o.cardW - 40
    o.lineH = Aegis.fontH(UIFont.Small)

    -- chip rows come first, the message row budget depends on their height
    local chipPos, chipRows = nil, 1
    if opts.chips then
        chipPos = {}
        local chx, row = 0, 0
        for i, chip in ipairs(opts.chips) do
            local cw = Aegis.strW(UIFont.Small, chip.label) + 24
            if chx > 0 and chx + cw > innerW then
                row = row + 1
                chx = 0
            end
            chipPos[i] = { x = chx, row = row, w = cw }
            chx = chx + cw + 8
        end
        chipRows = row + 1
    end
    local chipExtra = (chipRows - 1) * 36
    -- 250 / 208 are the old fixed heights and already contain one message
    -- row, every further row adds its own height
    local baseH = opts.chips and 250 or 208
    local maxRows = math.max(1, math.floor((math.max(200, sh - 60) - baseH - chipExtra) / o.lineH) + 1)
    o.msgLines = Aegis.wrapText(message, UIFont.Small, innerW, maxRows)
    o.warnLines = Aegis.wrapText(warn, UIFont.Small, innerW, maxRows)
    local rows = math.max(#o.msgLines, #o.warnLines)
    o.cardH = baseH + (rows - 1) * o.lineH + chipExtra

    o:initialise()
    o:addToUIManager()
    o:setAlwaysOnTop(true)

    local cx = math.floor((sw - o.cardW) / 2)
    local cy = math.floor((sh - o.cardH) / 2)
    local innerX = cx + 20
    local ey = cy + 44 + Aegis.fontH(UIFont.Medium) + (rows - 1) * o.lineH

    o.entry = ISTextEntryBox:new("", innerX, ey, innerW, 28)
    o.entry:initialise()
    o.entry:instantiate()
    o.entry.font = UIFont.Small
    o.entry:setPlaceholderText(getText(opts.reasonRequired and "UI_Aegis_ReasonRequired" or "UI_Aegis_ReasonOptional"))
    -- the red "reason missing" hint disappears again once the user types
    o.entry.onTextChange = function() o.warnEmpty = false end
    o:addChild(o.entry)

    o.chipRects = {}
    local chipY = ey + 40
    if opts.chips then
        for i, chip in ipairs(opts.chips) do
            local p = chipPos[i]
            local btn = AegisButton:new(innerX + p.x, chipY + p.row * 36, p.w, 28, chip.label, nil, o, function(panel, b)
                panel.choice = b.chipValue
            end)
            btn.chipValue = chip.value
            btn.radius = 14
            o:addChild(btn)
            table.insert(o.chipRects, btn)
        end
    end

    local by = cy + o.cardH - 52
    local bw = math.floor((o.cardW - 48) / 2)
    local cancel = AegisButton:new(cx + 16, by, bw, 36, getText("UI_Aegis_Cancel"), nil, o, AegisPrompt.onCancel)
    o:addChild(cancel)
    o.okBtn = AegisButton:new(cx + 32 + bw, by, bw, 36, opts.confirmLabel, nil, o, AegisPrompt.onConfirm)
    o.okBtn.style = opts.danger and "danger" or "gold"
    o:addChild(o.okBtn)
    return o
end

function AegisPrompt:onCancel()
    self:removeFromUIManager()
end

function AegisPrompt:onConfirm()
    local reason = self.entry:getInternalText() or ""
    reason = reason:gsub("^%s+", ""):gsub("%s+$", "")
    if self.opts.reasonRequired and reason == "" then
        self.warnEmpty = true
        return
    end
    self:removeFromUIManager()
    if self.opts.onConfirm then self.opts.onConfirm(self.opts.target, reason, self.choice) end
end

function AegisPrompt:prerender()
    ISPanel.prerender(self)
    local c = Aegis.col
    local cx = math.floor((self.width - self.cardW) / 2)
    local cy = math.floor((self.height - self.cardH) / 2)
    Aegis.shadow(self, cx, cy, self.cardW, self.cardH, 26, 0.7)
    Aegis.roundFrame(self, cx, cy, self.cardW, self.cardH, 12, 1, c.line, c.bg)
    Aegis.text(self, self.opts.title, cx + 20, cy + 14, UIFont.Medium, c.text)
    local msgC = self.warnEmpty and c.danger or c.muted
    local ty = cy + 16 + Aegis.fontH(UIFont.Medium)
    for _, line in ipairs(self.warnEmpty and self.warnLines or self.msgLines) do
        Aegis.text(self, line, cx + 20, ty, UIFont.Small, msgC)
        ty = ty + self.lineH
    end

    -- highlight the selected chip
    for _, btn in ipairs(self.chipRects) do
        btn.style = (btn.chipValue == self.choice) and "gold" or "ghost"
    end
end

-- ==================================================================
-- AegisTimePicker: click the time instead of typing it. Hour grid,
-- quarter-hour chips plus a minute slider for odd times.
-- Display follows the player's clock option (24h or AM/PM),
-- onPick(target, hour, minute) always receives 0-23.
-- ==================================================================
AegisTimePicker = ISPanel:derive("AegisTimePicker")

local function clock24()
    return getCore():getOptionClock24Hour()
end

function AegisTimePicker.format(hour, minute)
    if clock24() then
        return string.format("%02d:%02d", hour, minute)
    end
    local h = hour % 12
    if h == 0 then h = 12 end
    return string.format("%d:%02d ", h, minute) .. (hour < 12 and "AM" or "PM")
end

function AegisTimePicker.show(title, target, onPick, initHour, initMinute)
    local sw, sh = getCore():getScreenWidth(), getCore():getScreenHeight()
    local o = ISPanel:new(0, 0, sw, sh)
    setmetatable(o, AegisTimePicker)
    AegisTimePicker.__index = AegisTimePicker
    o.background = true
    o.backgroundColor = { r = 0, g = 0, b = 0, a = 0.55 }
    o.borderColor = { r = 0, g = 0, b = 0, a = 0 }
    o.title = title
    o.target = target
    o.onPick = onPick
    o.h24 = clock24()
    o.hour = initHour or 12
    o.minute = initMinute or 0
    o.cardW = 372
    local hoursH = o.h24 and (4 * 34) or (2 * 34 + 34)
    o.cardH = 48 + hoursH + 12 + 34 + 34 + 14 + 36 + 16
    o:initialise()
    o:addToUIManager()
    o:setAlwaysOnTop(true)

    local cx = math.floor((sw - o.cardW) / 2)
    local cy = math.floor((sh - o.cardH) / 2)
    local innerX = cx + 16
    local innerW = o.cardW - 32
    local gap = 6
    local bw = math.floor((innerW - 5 * gap) / 6)
    local y = cy + 48

    -- hour grid: 24h in four rows, 12h in two plus AM/PM
    o.hourBtns = {}
    local values = o.h24 and { 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23 }
        or { 12, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11 }
    for i, value in ipairs(values) do
        local col = (i - 1) % 6
        local row = math.floor((i - 1) / 6)
        local btn = AegisButton:new(innerX + col * (bw + gap), y + row * 34, bw, 28,
            o.h24 and string.format("%02d", value) or tostring(value), nil, o, function(panel, b)
                if panel.h24 then
                    panel.hour = b.value
                else
                    panel.hour = (b.value % 12) + (panel.hour >= 12 and 12 or 0)
                end
            end)
        btn.value = value
        o:addChild(btn)
        table.insert(o.hourBtns, btn)
    end
    y = y + (o.h24 and 4 or 2) * 34
    if not o.h24 then
        local hw = math.floor((innerW - gap) / 2)
        o.amBtn = AegisButton:new(innerX, y, hw, 28, "AM", nil, o, function(panel)
            panel.hour = panel.hour % 12
        end)
        o:addChild(o.amBtn)
        o.pmBtn = AegisButton:new(innerX + hw + gap, y, hw, 28, "PM", nil, o, function(panel)
            panel.hour = panel.hour % 12 + 12
        end)
        o:addChild(o.pmBtn)
        y = y + 34
    end
    y = y + 12

    -- minutes: quarter hours as quick picks, slider for the rest
    o.minuteBtns = {}
    local mw = math.floor((innerW - 3 * gap) / 4)
    for i, m in ipairs({ 0, 15, 30, 45 }) do
        local btn = AegisButton:new(innerX + (i - 1) * (mw + gap), y, mw, 28, string.format(":%02d", m), nil, o, function(panel, b)
            panel.minute = b.value
            panel.slider:setValue(b.value, true)
        end)
        btn.value = m
        o:addChild(btn)
        table.insert(o.minuteBtns, btn)
    end
    y = y + 34
    o.slider = AegisSlider:new(innerX, y, innerW, 28, o, function(panel, value)
        panel.minute = value
    end)
    o.slider:setValues(0, 59, 1, "")
    o.slider.value = o.minute
    o:addChild(o.slider)
    y = y + 34 + 14

    local hw = math.floor((innerW - gap) / 2)
    local cancel = AegisButton:new(innerX, y, hw, 36, getText("UI_Aegis_Cancel"), nil, o, AegisTimePicker.onCancel)
    o:addChild(cancel)
    local ok = AegisButton:new(innerX + hw + gap, y, hw, 36, getText("UI_Aegis_Apply"), nil, o, AegisTimePicker.onConfirm)
    ok.style = "gold"
    o:addChild(ok)
    return o
end

function AegisTimePicker:onCancel()
    self:removeFromUIManager()
end

function AegisTimePicker:onConfirm()
    self:removeFromUIManager()
    if self.onPick then self.onPick(self.target, self.hour, self.minute) end
end

function AegisTimePicker:prerender()
    ISPanel.prerender(self)
    local c = Aegis.col
    local cx = math.floor((self.width - self.cardW) / 2)
    local cy = math.floor((self.height - self.cardH) / 2)
    Aegis.shadow(self, cx, cy, self.cardW, self.cardH, 26, 0.7)
    Aegis.roundFrame(self, cx, cy, self.cardW, self.cardH, 12, 1, c.line, c.bg)
    Aegis.text(self, self.title, cx + 16, cy + 14, UIFont.Medium, c.text)
    Aegis.textRight(self, AegisTimePicker.format(self.hour, self.minute), cx + self.cardW - 16, cy + 14, UIFont.Medium, c.goldHi)

    for _, btn in ipairs(self.hourBtns) do
        local active
        if self.h24 then
            active = btn.value == self.hour
        else
            active = btn.value % 12 == self.hour % 12
        end
        btn.style = active and "gold" or "ghost"
    end
    if self.amBtn then
        self.amBtn.style = self.hour < 12 and "gold" or "ghost"
        self.pmBtn.style = self.hour >= 12 and "gold" or "ghost"
    end
    for _, btn in ipairs(self.minuteBtns) do
        btn.style = btn.value == self.minute and "gold" or "ghost"
    end
end

-- ==================================================================
-- AegisDatePicker: click a day, today up to maxDays ahead.
-- onPick(target, dayOffset, displayText)
-- ==================================================================
AegisDatePicker = ISPanel:derive("AegisDatePicker")

-- 0 = Sunday, days-since-epoch per Howard Hinnant
local function weekday(t)
    local y, m = t.year, t.month
    if m <= 2 then
        y = y - 1
        m = m + 12
    end
    local era = math.floor(y / 400)
    local yoe = y - era * 400
    local doy = math.floor((153 * (m - 3) + 2) / 5) + t.day - 1
    local doe = yoe * 365 + math.floor(yoe / 4) - math.floor(yoe / 100) + doy
    return (era * 146097 + doe - 719468 + 4) % 7
end

local WEEKDAYS = { "UI_Aegis_Wd0", "UI_Aegis_Wd1", "UI_Aegis_Wd2", "UI_Aegis_Wd3", "UI_Aegis_Wd4", "UI_Aegis_Wd5", "UI_Aegis_Wd6" }

function AegisDatePicker.tagText(offset)
    if offset == 0 then return getText("UI_Aegis_Today") end
    if offset == 1 then return getText("UI_Aegis_Tomorrow") end
    local t = AegisShared.dateParts(AegisShared.realTime() + offset * 86400)
    return getText(WEEKDAYS[weekday(t) + 1]) .. string.format(" %02d.%02d.", t.day, t.month)
end

function AegisDatePicker.show(title, target, onPick, maxDays)
    local sw, sh = getCore():getScreenWidth(), getCore():getScreenHeight()
    local o = ISPanel:new(0, 0, sw, sh)
    setmetatable(o, AegisDatePicker)
    AegisDatePicker.__index = AegisDatePicker
    o.background = true
    o.backgroundColor = { r = 0, g = 0, b = 0, a = 0.55 }
    o.borderColor = { r = 0, g = 0, b = 0, a = 0 }
    o.title = title
    o.cardW = 280
    o.cardH = 48 + (maxDays + 1) * 36 + 8 + 36 + 16
    o:initialise()
    o:addToUIManager()
    o:setAlwaysOnTop(true)

    local cx = math.floor((sw - o.cardW) / 2)
    local cy = math.floor((sh - o.cardH) / 2)
    local innerX = cx + 16
    local innerW = o.cardW - 32
    local y = cy + 48
    for offset = 0, maxDays do
        local label = AegisDatePicker.tagText(offset)
        local btn = AegisButton:new(innerX, y, innerW, 30, label, nil, o, function(panel, b)
            panel:removeFromUIManager()
            if onPick then onPick(target, b.value, b.label) end
        end)
        btn.value = offset
        o:addChild(btn)
        y = y + 36
    end
    y = y + 8
    local cancel = AegisButton:new(innerX, y, innerW, 36, getText("UI_Aegis_Cancel"), nil, o, AegisDatePicker.onCancel)
    o:addChild(cancel)
    return o
end

function AegisDatePicker:onCancel()
    self:removeFromUIManager()
end

function AegisDatePicker:prerender()
    ISPanel.prerender(self)
    local c = Aegis.col
    local cx = math.floor((self.width - self.cardW) / 2)
    local cy = math.floor((self.height - self.cardH) / 2)
    Aegis.shadow(self, cx, cy, self.cardW, self.cardH, 26, 0.7)
    Aegis.roundFrame(self, cx, cy, self.cardW, self.cardH, 12, 1, c.line, c.bg)
    Aegis.text(self, self.title, cx + 16, cy + 14, UIFont.Medium, c.text)
end
