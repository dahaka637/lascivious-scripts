-- Update notice: shown once per new version when the panel gets opened,
-- the checkbox parks it until the next version. Content is the newest
-- changelog entry from AegisHelpContent, so there is only one source.
require "Aegis/AegisTheme"
require "Aegis/AegisWidgets"
require "Aegis/AegisHelpContent"
require "Aegis/AegisPlayerCore"

AegisWhatsNew = ISPanel:derive("AegisWhatsNew")
AegisWhatsNew.instance = nil
-- without the checkbox the notice waits for the NEXT session, not the
-- next panel toggle
AegisWhatsNew.shown = {}

local CARD_W = 520
local PAD = 20
local PULSE_MS = 4200

local function versionFor(mode)
    if mode == "player" then
        return AegisPlayerWindow and AegisPlayerWindow.version or "0"
    end
    return Aegis.version
end

local function prefKey(mode)
    return mode == "player" and "whatsNewPlayer" or "whatsNewGold"
end

-- Verdict is taken ONCE and kept: marking a version as seen writes one
-- of the very keys this looks at, so a second call would answer
-- differently for no good reason
local freshVerdict = nil
local FRESH_KEYS = { "winW", "pwinW", "hudDockX", "whatsNewGold",
    "whatsNewPlayer", "tourGold", "tourPlayer", "tagOff", "helpW", "navOrder" }

function AegisWhatsNew.isFreshInstall()
    if freshVerdict == nil then
        freshVerdict = true
        for _, k in ipairs(FRESH_KEYS) do
            if Aegis.getPref(k) ~= nil then freshVerdict = false break end
        end
    end
    return freshVerdict
end

function AegisWhatsNew.maybeShow(mode)
    mode = mode == "player" and "player" or "admin"
    if AegisWhatsNew.shown[mode] then return end
    -- never on top of a running tour
    if AegisTour and AegisTour.instance then return end
    if Aegis.getPref(prefKey(mode)) == versionFor(mode) then return end
    AegisWhatsNew.shown[mode] = true
    AegisWhatsNew.show(mode)
end

-- parks the running version without opening the notice
function AegisWhatsNew.markSeen(mode)
    mode = mode == "player" and "player" or "admin"
    Aegis.setPref(prefKey(mode), versionFor(mode))
end

-- the tour hands over here when it ends, the update notice follows
function AegisTourDone(mode)
    AegisWhatsNew.maybeShow(mode)
end

function AegisWhatsNew.show(mode)
    if AegisWhatsNew.instance then AegisWhatsNew.instance:removeFromUIManager() end
    local content = AegisHelpContent.get(mode == "player" and "player" or "admin")
    local entry = content and content.changelog and content.changelog[1]
    if not entry then return end
    local seen = Aegis.getPref(prefKey(mode))

    local sw, sh = getCore():getScreenWidth(), getCore():getScreenHeight()
    local o = ISPanel:new(0, 0, sw, sh)
    setmetatable(o, AegisWhatsNew)
    AegisWhatsNew.__index = AegisWhatsNew
    o.background = true
    o.backgroundColor = { r = 0, g = 0, b = 0, a = 0.55 }
    o.borderColor = { r = 0, g = 0, b = 0, a = 0 }
    o.mode = mode == "player" and "player" or "admin"
    o.col = o.mode == "player" and AegisPlayerCol or Aegis.col
    if o.mode == "player" then
        o.acc, o.accHi, o.accDim = AegisPlayerCol.accent, AegisPlayerCol.accentHi, AegisPlayerCol.accentDim
    else
        o.acc, o.accHi, o.accDim = Aegis.col.gold, Aegis.col.goldHi, Aegis.col.goldDim
    end
    o.entry = entry
    -- an empty pref means "shown, not silenced", not a previous version
    if seen and seen ~= "" and seen ~= entry.version then
        o.versionLine = seen .. "  >  " .. entry.version
    else
        o.versionLine = "v" .. entry.version
    end
    -- how many releases sit between the remembered one and now
    o.skipped = 0
    if seen and seen ~= "" then
        for i, e in ipairs(content.changelog) do
            if e.version == seen then o.skipped = i - 2 break end
        end
        if o.skipped < 0 then o.skipped = 0 end
    end

    -- rows: group headers and wrapped points, capped so the card can
    -- never grow into a wall of text
    o.cardW = math.min(CARD_W, sw - 60)
    local textW = o.cardW - PAD * 2 - 18
    o.rows = {}
    for _, sec in ipairs(entry.sections or {}) do
        table.insert(o.rows, { kind = "grp", text = sec.title })
        for _, pt in ipairs(sec.points or {}) do
            table.insert(o.rows, { kind = "pt", lines = Aegis.wrapText(pt, UIFont.Small, textW, 6) })
        end
    end

    o.lineH = Aegis.fontH(UIFont.Small)
    o.grpH = Aegis.fontH(UIFont.Small) + 14
    o.headH = 58
    local body = 0
    for _, r in ipairs(o.rows) do
        body = body + (r.kind == "grp" and o.grpH or (#r.lines * o.lineH + 9))
    end
    o.noteH = o.lineH + (o.skipped > 0 and o.lineH + 4 or 0) + 12
    o.footH = 56
    o.bodyH = body
    o.cardH = math.min(sh - 60, o.headH + body + o.noteH + o.footH + 16)
    -- what the body may occupy inside the card, the rest scrolls
    o.viewH = o.cardH - o.headH - o.noteH - o.footH - 16
    o.maxScroll = math.max(0, body - o.viewH)
    o.scroll = 0
    o.cardX = math.floor((sw - o.cardW) / 2)
    o.cardY = math.floor((sh - o.cardH) / 2)

    o.anim = 0
    o:initialise()
    o:addToUIManager()
    o:setAlwaysOnTop(true)

    o.muteToggle = AegisToggle:new(o.cardX + PAD - 6, o.cardY + o.cardH - 44, o.cardW - PAD * 2 - 130, 28,
        getText("UI_Aegis_WhatsNewMute"), nil, o, function() end)
    -- the window mirrors the remembered choice instead of resetting it
    o.muteToggle:setChecked(seen ~= nil and seen ~= "" and seen == versionFor(o.mode))
    o.muteToggle:setVisible(false)
    o:addChild(o.muteToggle)

    o.closeBtn = AegisButton:new(o.cardX + o.cardW - PAD - 110, o.cardY + o.cardH - 48, 110, 34,
        getText("UI_Aegis_Close"), nil, o, AegisWhatsNew.onClose)
    o.closeBtn:setVisible(false)
    o:addChild(o.closeBtn)

    AegisWhatsNew.instance = o
    return o
end

function AegisWhatsNew.onClose(self)
    -- both directions count: unticking on a reopen un-parks the notice
    if self.muteToggle then
        Aegis.setPref(prefKey(self.mode), self.muteToggle.checked and versionFor(self.mode) or "")
    end
    self:removeFromUIManager()
    if AegisWhatsNew.instance == self then AegisWhatsNew.instance = nil end
end

-- clicks on the dim backdrop close nothing, the card wants a decision
function AegisWhatsNew:onMouseDown(x, y) end

function AegisWhatsNew:onMouseWheel(del)
    if (self.maxScroll or 0) <= 0 then return false end
    self.scroll = math.max(0, math.min(self.maxScroll, (self.scroll or 0) + del * 40))
    return true
end

-- small pixel diamond, rows 1-3-5-3-1
local function diamond(self, x, y, a, col)
    self:drawRect(x + 2, y, 1, 1, a, col.r, col.g, col.b)
    self:drawRect(x + 1, y + 1, 3, 1, a, col.r, col.g, col.b)
    self:drawRect(x, y + 2, 5, 1, a, col.r, col.g, col.b)
    self:drawRect(x + 1, y + 3, 3, 1, a, col.r, col.g, col.b)
    self:drawRect(x + 2, y + 4, 1, 1, a, col.r, col.g, col.b)
end

function AegisWhatsNew:prerender()
    ISPanel.prerender(self)
    local c = self.col
    -- seal opening: the card unfolds, the crest lands first
    if self.anim < 1 then
        self.anim = math.min(1, self.anim + Aegis.delta() * 0.09)
    end
    local a = self.anim
    local ease = 1 - (1 - a) * (1 - a)
    local cardA = math.min(1, a * 1.6)
    local rise = math.floor((1 - ease) * 14)
    local cx, cy = self.cardX, self.cardY + rise

    Aegis.shadow(self, cx, cy, self.cardW, self.cardH, 26, 0.7 * cardA)
    Aegis.roundFrame(self, cx, cy, self.cardW, self.cardH, 12, cardA, c.line, c.bg)
    self:drawRect(cx + 12, cy, self.cardW - 24, 2, cardA, self.acc.r, self.acc.g, self.acc.b)

    -- crest with a light overshoot
    local crestT = math.min(1, a * 1.8)
    local over = 1 + 0.35 * (1 - crestT) * crestT * 4
    local size = math.floor(34 * crestT * over)
    local tex = Aegis.tex(self.mode == "player" and "hud_player" or "hud")
    if tex and size > 2 then
        self:drawTextureScaledAspect(tex, cx + PAD + (34 - size) / 2, cy + 14 + (34 - size) / 2, size, size, crestT, 1, 1, 1)
    end
    Aegis.text(self, getText("UI_Aegis_WhatsNew"), cx + PAD + 46, cy + 18, UIFont.Medium, c.text, cardA)
    local pillW = Aegis.strW(UIFont.Small, self.versionLine) + 18
    Aegis.roundFrame(self, cx + self.cardW - PAD - pillW, cy + 18, pillW, 24, 6, cardA, self.accDim, c.card)
    Aegis.textCentre(self, self.versionLine, cx + self.cardW - PAD - math.floor(pillW / 2), cy + 22, UIFont.Small, self.accHi, cardA)

    -- body fades in after the card stands
    local bodyA = math.max(0, (a - 0.45) / 0.55)
    local y = cy + self.headH - (self.scroll or 0)
    local viewTop, viewBot = cy + self.headH - 2, cy + self.headH + self.viewH
    self:setStencilRect(cx + 2, cy + self.headH - 2, self.cardW - 4, self.viewH + 4)
    local now = getTimestampMs() % PULSE_MS
    local idx = 0
    for _, r in ipairs(self.rows) do
        if r.kind == "grp" then
            Aegis.text(self, string.upper(r.text), cx + PAD, y + 6, UIFont.Small, c.muted, bodyA)
            y = y + self.grpH
        else
            -- the diamonds keep glowing one after another, a soft sweep
            local phase = (now / PULSE_MS) - idx * 0.07
            phase = phase - math.floor(phase)
            local glow = 0
            if phase > 0.62 and phase < 0.86 then
                glow = 1 - math.abs((phase - 0.74) / 0.12)
            end
            local dcol = glow > 0.5 and self.accHi or self.accDim
            local dy = y + math.floor(self.lineH / 2) - 2
            if glow > 0 then
                diamond(self, cx + PAD - 1, dy - 1, bodyA * glow * 0.35, self.accHi)
                diamond(self, cx + PAD + 1, dy + 1, bodyA * glow * 0.35, self.accHi)
            end
            diamond(self, cx + PAD, dy, bodyA, dcol)
            local ty = y
            for _, line in ipairs(r.lines) do
                Aegis.text(self, line, cx + PAD + 14, ty, UIFont.Small, c.text, bodyA)
                ty = ty + self.lineH
            end
            y = ty + 9
            idx = idx + 1
        end
    end

    self:clearStencilRect()

    -- slim bar on the right edge whenever there is more than fits
    if (self.maxScroll or 0) > 0 then
        local trackH = self.viewH
        local thumbH = math.max(24, math.floor(trackH * trackH / (trackH + self.maxScroll)))
        local thumbY = cy + self.headH + math.floor((trackH - thumbH) * (self.scroll / self.maxScroll))
        self:drawRect(cx + self.cardW - 7, cy + self.headH, 3, trackH, 0.25 * bodyA, c.line.r, c.line.g, c.line.b)
        self:drawRect(cx + self.cardW - 7, thumbY, 3, thumbH, 0.9 * bodyA, self.accDim.r, self.accDim.g, self.accDim.b)
    end

    local ny = cy + self.cardH - self.footH - self.noteH + 4
    if self.skipped > 0 then
        Aegis.text(self, getText("UI_Aegis_WhatsNewSkipped", self.skipped), cx + PAD, ny, UIFont.Small, c.muted, bodyA)
        ny = ny + self.lineH + 4
    end
    Aegis.text(self, getText("UI_Aegis_WhatsNewMore"), cx + PAD, ny, UIFont.Small, c.muted, bodyA)
    self:drawRect(cx + PAD, cy + self.cardH - 56, self.cardW - PAD * 2, 1, 0.6 * bodyA, c.line.r, c.line.g, c.line.b)

    if a > 0.6 then
        self.muteToggle:setVisible(true)
        self.closeBtn:setVisible(true)
    end
end
