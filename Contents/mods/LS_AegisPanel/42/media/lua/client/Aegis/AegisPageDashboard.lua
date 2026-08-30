-- Overview: card grid built from the old fixed dashboard blocks. The
-- layout is stored per admin (pref dashCards) and edited via the pencil
-- button: drag reorders, the cross removes, the plus tile opens the
-- catalog of unplaced cards. Without a saved pref the grid reproduces
-- the old two column page pixel for pixel.
require "Aegis/AegisWindow"

AegisPageDashboard = ISPanel:derive("AegisPageDashboard")
AegisDashCanvas = ISPanel:derive("AegisDashCanvas")
AegisDashCatalog = ISPanel:derive("AegisDashCatalog")

-- quick access, the full list (23 vanilla powers) lives on the powers page
local POWERS = {
    { key = "GodMod",    label = "UI_Aegis_PowerGod",       icon = "shield", cap = "ToggleGodModHimself",
      get = function(p) return p:isGodMod() end,              set = function(p, v) p:setGodMod(v) end },
    { key = "Invisible", label = "UI_Aegis_PowerInvisible", icon = "eye", cap = "ToggleInvisibleHimself",
      get = function(p) return p:isInvisible() end,           set = function(p, v) p:setInvisible(v) end },
    { key = "NoClip",    label = "UI_Aegis_PowerNoClip",    icon = "noclip", cap = "ToggleNoclipHimself",
      get = function(p) return p:isNoClip() end,              set = function(p, v) p:setNoClip(v) end },
    { key = "UnlimitedAmmo", label = "UI_Aegis_PowerAmmo",  icon = "plus", cap = "ToggleUnlimitedAmmo",
      get = function(p) return p:isUnlimitedAmmo() end,       set = function(p, v) p:setUnlimitedAmmo(v) end },
}

-- player facing feature switches, same defs and sandbox channel as the
-- server page uses
local FEATURES = {
    { opt = "PlayerPanel",  label = "UI_Aegis_FeatPanel",  icon = "players", tip = "Sandbox_AegisPlayerPanel_tooltip" },
    { opt = "PlayerClaims", label = "UI_Aegis_FeatClaims", icon = "home",    tip = "Sandbox_AegisPlayerClaims_tooltip" },
    { opt = "PlayerKits",   label = "UI_Aegis_FeatKits",   icon = "plus",    tip = "Sandbox_AegisPlayerKits_tooltip" },
}

local FEED_POLL_MS = 6000
local PULSE_POLL_MS = 10000
local SCORE_POLL_MS = 10000

local PAD = 20
local GAP_X = 20
local GAP_Y = 12
local FEED_MIN = 140
local PLUS_H = 56
-- below this page width the grid falls back to a single column. The
-- smallest page the window can produce is 671 px wide (window floor 860
-- minus the sidebar), so a threshold under that would never fire
local NARROW_W = 700
-- own strip above the grid for the title and the edit buttons. Without
-- it the edit button sat on top of the first card in the right column
-- and swallowed the clicks meant for that card's remove cross
local HEAD_H = 44
-- the grid is the only page area that reaches the bottom right corner of
-- the window, and that corner belongs to the resize grip. Same chin the
-- window itself leaves for wrapped pages (AegisWindow.GRIP_CHIN), else
-- the scroll bar of the grid lies on top of the grip once the window is
-- small enough to scroll at all
local GRIP_CHIN = 26

-- ------------------------------------------------------------------
-- Drawing helpers (unchanged looks from the fixed page)
-- ------------------------------------------------------------------

local function sectionCard(el, x, y, w, h, titleKey, icon)
    local c = Aegis.col
    Aegis.roundFrame(el, x, y, w, h, 10, 1, c.line, c.panel)
    Aegis.icon(el, icon, x + 14, y + 12, 15, 1, c.gold)
    Aegis.text(el, getText(titleKey), x + 36, y + 10, UIFont.Medium, c.text)
end

local function statHeader(el, x, y, labelKey, icon)
    local c = Aegis.col
    Aegis.icon(el, icon, x + 16, y + 14, 16, 1, c.gold)
    Aegis.text(el, getText(labelKey), x + 40, y + 12, UIFont.Small, c.muted)
end

local function formatUptime(ms)
    local s = math.floor(ms / 1000)
    local h = math.floor(s / 3600)
    local m = math.floor((s % 3600) / 60)
    return string.format("%d:%02d h", h, m)
end

local function formatCountdown(sec)
    if sec >= 3600 then
        return string.format("%d:%02d:%02d", math.floor(sec / 3600), math.floor((sec % 3600) / 60), sec % 60)
    end
    return string.format("%d:%02d", math.floor(sec / 60), sec % 60)
end

-- ------------------------------------------------------------------
-- Card faces: draw(page, el, x, y, w, h), widgets draw themselves
-- ------------------------------------------------------------------

local function drawPowers(page, el, x, y, w, h)
    sectionCard(el, x, y, w, h, "UI_Aegis_Powers", "wand")
end

local function drawActions(page, el, x, y, w, h)
    sectionCard(el, x, y, w, h, "UI_Aegis_Actions", "bolt")
end

local function drawFeed(page, el, x, y, w, h)
    local c = Aegis.col
    sectionCard(el, x, y, w, h, "UI_Aegis_DashActivity", "logs")
    if h <= 60 then return end
    local rowY = y + 40
    local rowH = 22
    local maxRows = math.floor((h - 48) / rowH)
    if #page.feed == 0 then
        Aegis.textCentre(el, getText("UI_Aegis_DashActivityEmpty"), x + math.floor(w / 2),
            y + math.floor(h / 2) - 8, UIFont.Small, c.muted)
        return
    end
    local timeW = Aegis.strW(UIFont.Small, "00:00") + 10
    for i = 1, math.min(#page.feed, maxRows) do
        local row = page.feed[i]
        Aegis.roundRect(el, x + 16, rowY + 8, 4, 4, 2, 1, c.gold)
        local textW = w - 28 - 16 - timeW - 12
        Aegis.text(el, Aegis.fitText(row.text, UIFont.Small, textW), x + 28, rowY, UIFont.Small, c.text)
        Aegis.textRight(el, row.time, x + w - 16, rowY, UIFont.Small, c.muted)
        rowY = rowY + rowH
    end
end

-- time card with a day progress bar (night segments tinted darker)
local function drawTime(page, el, x, y, w, h)
    local c = Aegis.col
    Aegis.roundFrame(el, x, y, w, h, 10, 1, c.line, c.panel)
    statHeader(el, x, y, "UI_Aegis_StatTime", "clock")
    local hh, mm = Aegis.hourMinute(getGameTime())
    Aegis.text(el, string.format("%02d:%02d", hh, mm), x + 16, y + 32, UIFont.Large, c.text)
    local dayText = Aegis.dayAndDate(getGameTime())
    if dayText ~= "" then
        Aegis.textRight(el, Aegis.fitText(dayText, UIFont.Small, w - 120), x + w - 16, y + 42, UIFont.Small, c.muted)
    end
    local barX, barW = x + 16, w - 32
    local barY = y + h - 20
    Aegis.roundRect(el, barX, barY, barW, 5, 2, 1, c.line)
    local dayStart, dayEnd = 6, 22
    Aegis.roundRect(el, barX + barW * (dayStart / 24), barY, barW * ((dayEnd - dayStart) / 24), 5, 2, 0.35, c.gold)
    local frac = math.min((hh + mm / 60) / 24, 1)
    Aegis.roundRect(el, barX + math.max(0, barW * frac - 2), barY - 2, 4, 9, 2, 1, c.goldHi)
end

local function drawPulse(page, el, x, y, w, h)
    local c = Aegis.col
    Aegis.roundFrame(el, x, y, w, h, 10, 1, c.line, c.panel)
    statHeader(el, x, y, "UI_Aegis_DashPulse", "players")
    local count = 1
    if isClient() and Aegis.scoreboard then
        count = #Aegis.scoreboard
    end
    local colW = math.floor((w - 32) / 3)
    local baseY = y + 32
    Aegis.text(el, tostring(count), x + 16, baseY, UIFont.Large, c.text)
    Aegis.text(el, getText("UI_Aegis_StatPlayers"), x + 16, baseY + 28, UIFont.Small, c.muted)
    Aegis.text(el, tostring(page.zombieCount), x + 16 + colW, baseY, UIFont.Large, c.text)
    Aegis.text(el, getText("UI_Aegis_DashZombies"), x + 16 + colW, baseY + 28, UIFont.Small, c.muted)
    Aegis.text(el, formatUptime(getTimestampMs() - page.sessionStart), x + 16 + colW * 2, baseY, UIFont.Large, c.text)
    Aegis.text(el, getText("UI_Aegis_DashUptime"), x + 16 + colW * 2, baseY + 28, UIFont.Small, c.muted)
end

-- gold countdown line; in the view layout the card only takes height
-- while a restart is planned, edit mode shows a muted placeholder
local function drawRestart(page, el, x, y, w, h)
    local c = Aegis.col
    local left = page:restartLeft()
    if left then
        Aegis.roundFrame(el, x, y, w, h, 8, 1, c.gold, c.dark)
        Aegis.icon(el, "clock", x + 12, y + 7, 14, 1, c.goldHi)
        Aegis.text(el, getText("UI_Aegis_DashNextRestart"), x + 34, y + 6, UIFont.Small, c.goldHi)
        Aegis.textRight(el, formatCountdown(left), x + w - 12, y + 6, UIFont.Small, c.goldHi)
    else
        Aegis.roundFrame(el, x, y, w, h, 8, 1, c.line, c.dark)
        Aegis.icon(el, "clock", x + 12, y + 7, 14, 1, c.muted)
        Aegis.text(el, getText("UI_Aegis_DashNextRestart"), x + 34, y + 6, UIFont.Small, c.muted)
        Aegis.textRight(el, "--:--", x + w - 12, y + 6, UIFont.Small, c.muted)
    end
end

local function drawWeather(page, el, x, y, w, h)
    local c = Aegis.col
    Aegis.roundFrame(el, x, y, w, h, 10, 1, c.line, c.panel)
    local okw, running, progress = pcall(function()
        local wp = getClimateManager():getWeatherPeriod()
        if wp and wp:isRunning() then
            return true, wp:getTotalProgress()
        end
        return false, 0
    end)
    statHeader(el, x, y, "UI_Aegis_StatWeather", (okw and running) and "storm" or "rain")
    if okw and running then
        Aegis.text(el, getText("UI_Aegis_WeatherActive"), x + 16, y + 34, UIFont.Medium, c.text)
        local barW = w - 32
        Aegis.roundRect(el, x + 16, y + h - 20, barW, 5, 2, 1, c.line)
        Aegis.roundRect(el, x + 16, y + h - 20, math.max(5, barW * math.min(progress or 0, 1)), 5, 2, 1, c.gold)
    else
        Aegis.text(el, getText("UI_Aegis_WeatherCalm"), x + 16, y + 34, UIFont.Medium, c.muted)
    end
end

local function drawRole(page, el, x, y, w, h)
    local c = Aegis.col
    Aegis.roundFrame(el, x, y, w, h, 10, 1, c.line, c.panel)
    statHeader(el, x, y, "UI_Aegis_StatRole", "crown")
    Aegis.text(el, page.window:roleString(), x + 16, y + 32, UIFont.Large, c.goldHi)
    local visible, total = 0, 0
    for _, area in ipairs(AegisShared.AREAS) do
        total = total + 1
        if Aegis.canSee(area) then visible = visible + 1 end
    end
    Aegis.textRight(el, getText("UI_Aegis_DashAreas", visible, total), x + w - 16, y + h - 26, UIFont.Small, c.muted)
end

local function drawFeatures(page, el, x, y, w, h)
    sectionCard(el, x, y, w, h, "UI_Aegis_DashFeatures", "gear")
end

local function drawPlayers(page, el, x, y, w, h)
    local c = Aegis.col
    sectionCard(el, x, y, w, h, "UI_Aegis_DashPlayers", "players")
    local rows = {}
    if isClient() then
        for _, row in ipairs(Aegis.scoreboard or {}) do
            table.insert(rows, row.displayName or row.username or "?")
        end
    else
        local p = getPlayer()
        if p then
            local name = p:getDescriptor():getForename() .. " " .. p:getDescriptor():getSurname()
            table.insert(rows, name)
        end
    end
    Aegis.textRight(el, tostring(#rows), x + w - 16, y + 12, UIFont.Small, c.muted)
    if #rows == 0 then
        Aegis.textCentre(el, getText("UI_Aegis_DashPlayersEmpty"), x + math.floor(w / 2),
            y + math.floor(h / 2) - 8, UIFont.Small, c.muted)
        return
    end
    local rowY = y + 40
    local rowH = 22
    local maxRows = math.floor((h - 48) / rowH)
    local shown = math.min(#rows, maxRows)
    for i = 1, shown do
        Aegis.roundRect(el, x + 16, rowY + 8, 4, 4, 2, 1, c.gold)
        Aegis.text(el, Aegis.fitText(rows[i], UIFont.Small, w - 28 - 16 - 40), x + 28, rowY, UIFont.Small, c.text)
        rowY = rowY + rowH
    end
    if #rows > shown then
        Aegis.textRight(el, "+" .. tostring(#rows - shown), x + w - 16, rowY - rowH, UIFont.Small, c.muted)
    end
end

-- shortcut tile for any panel page: whole card is the button, so a page
-- the admin needs often is one click away from the overview
local function drawJump(page, el, x, y, w, h, def)
    local c = Aegis.col
    local hot = (not page.editMode) and el:isMouseOver()
        and el:getMouseX() >= x and el:getMouseX() <= x + w
        and el:getMouseY() >= y and el:getMouseY() <= y + h
    Aegis.roundFrame(el, x, y, w, h, 10, 1, hot and c.gold or c.line, c.panel)
    Aegis.icon(el, (def and def.icon) or "dash", x + 14, y + math.floor((h - 18) / 2), 18, 1, c.gold)
    Aegis.text(el, Aegis.fitText(getText(def and def.title or ""), UIFont.Medium, w - 80),
        x + 44, y + math.floor((h - Aegis.fontH(UIFont.Medium)) / 2), UIFont.Medium,
        hot and c.text or c.muted)
    Aegis.icon(el, "chevron", x + w - 26, y + math.floor((h - 14) / 2), 14, hot and 1 or 0.5, c.muted)
end

-- the four presets and the stop button of the world page, pulled onto the
-- overview
local QUICK_TIMES = {
    { hour = 7,  label = "UI_Aegis_Morning" },
    { hour = 12, label = "UI_Aegis_Noon" },
    { hour = 18, label = "UI_Aegis_Evening" },
    { hour = 0,  label = "UI_Aegis_Midnight" },
}

local function drawWorldQuick(page, el, x, y, w, h)
    sectionCard(el, x, y, w, h, "UI_Aegis_DashWorldQuick", "clock")
end

-- ------------------------------------------------------------------
-- Card catalog: every card checks the rights of its home area itself,
-- without that right it neither lays out nor shows in the plus catalog
-- ------------------------------------------------------------------

local CARDS = {
    { id = "powers",   title = "UI_Aegis_Powers",          icon = "wand",    desc = "UI_Aegis_DashCardPowers",
      h = 40 + #POWERS * 36 + 6 + 34 + 8, draw = drawPowers },
    { id = "actions",  title = "UI_Aegis_Actions",         icon = "bolt",    desc = "UI_Aegis_DashCardActions",
      h = 102, draw = drawActions },
    { id = "feed",     title = "UI_Aegis_DashActivity",    icon = "logs",    desc = "UI_Aegis_DashCardFeed",
      area = "logs", flex = true, draw = drawFeed },
    { id = "time",     title = "UI_Aegis_StatTime",        icon = "clock",   desc = "UI_Aegis_DashCardTime",
      h = 104, draw = drawTime },
    { id = "pulse",    title = "UI_Aegis_DashPulse",       icon = "players", desc = "UI_Aegis_DashCardPulse",
      h = 104, draw = drawPulse },
    { id = "restart",  title = "UI_Aegis_DashNextRestart", icon = "clock",   desc = "UI_Aegis_DashCardRestart",
      area = "server", h = 30, draw = drawRestart },
    { id = "weather",  title = "UI_Aegis_StatWeather",     icon = "rain",    desc = "UI_Aegis_DashCardWeather",
      h = 88, draw = drawWeather },
    { id = "role",     title = "UI_Aegis_StatRole",        icon = "crown",   desc = "UI_Aegis_DashCardRole",
      h = 88, draw = drawRole },
    { id = "features", title = "UI_Aegis_DashFeatures",    icon = "gear",    desc = "UI_Aegis_DashCardFeatures",
      area = "server", h = 40 + #FEATURES * 34 + 12, draw = drawFeatures },
    { id = "players",  title = "UI_Aegis_DashPlayers",     icon = "players", desc = "UI_Aegis_DashCardPlayers",
      area = "players", h = 188, draw = drawPlayers },
    { id = "worldquick", title = "UI_Aegis_DashWorldQuick", icon = "clock", desc = "UI_Aegis_DashCardWorldQuick",
      area = "world", h = 40 + 34 + 34 + 12, draw = drawWorldQuick },
}

-- Shortcut tiles are derived from the registered pages, not hard coded:
-- at file load time the other page files are not registered yet (they
-- load alphabetically), so the full catalog is built on first use. That
-- also means every future page shows up in the catalog by itself
local ALL_CARDS = nil
local CARD_BY_ID = nil

local function allCards()
    if ALL_CARDS then return ALL_CARDS end
    ALL_CARDS = {}
    CARD_BY_ID = {}
    for _, def in ipairs(CARDS) do table.insert(ALL_CARDS, def) end
    for _, page in ipairs(AegisWindow.pages) do
        if page.id ~= "dashboard" then
            table.insert(ALL_CARDS, {
                id = "go:" .. page.id, jumpTo = page.id, title = page.label,
                icon = page.icon, desc = "UI_Aegis_DashCardJump",
                area = page.area or page.id, h = 56, draw = drawJump,
            })
        end
    end
    for _, def in ipairs(ALL_CARDS) do CARD_BY_ID[def.id] = def end
    return ALL_CARDS
end

local function cardById(id)
    allCards()
    return CARD_BY_ID[id]
end

-- exactly the old fixed page: left column powers, actions, feed as the
-- flex block, right column the live stat cards
local DEFAULT_LAYOUT = "powers,actions,feed,time,pulse,restart,weather,role"

local function cardAllowed(def)
    return def.area == nil or Aegis.canSee(def.area)
end

-- pref semantics differ from navOrder on purpose: unknown ids are
-- dropped, but missing cards are NOT appended, a removed card stays
-- removed. Only a never written pref (nil) yields the default layout
local function loadLayout()
    local saved = Aegis.getPref("dashCards")
    if saved == nil then saved = DEFAULT_LAYOUT end
    local out, seen = {}, {}
    for id in tostring(saved):gmatch("[^,]+") do
        if cardById(id) and not seen[id] then
            table.insert(out, id)
            seen[id] = true
        end
    end
    return out
end

local function inRect(r, x, y)
    return x >= r.x and x <= r.x + r.w and y >= r.y and y <= r.y + r.h
end

-- ------------------------------------------------------------------
-- Page
-- ------------------------------------------------------------------

function AegisPageDashboard.create(window, x, y, w, h)
    local o = ISPanel:new(x, y, w, h)
    setmetatable(o, AegisPageDashboard)
    AegisPageDashboard.__index = AegisPageDashboard
    o.background = false
    o.window = window
    o.toggles = {}
    o.widgets = {}
    o.refreshTick = 0
    o.sessionStart = getTimestampMs()
    o.feed = {}
    o.feedPath = nil
    o.feedNextAt = 0
    o.zombieCount = 0
    o.zombieNextAt = 0
    o.restartRemaining = -1
    o.restartReceivedAt = 0
    o.pulseNextAt = 0
    o.scoreNextAt = 0
    o.featHold = 0
    o.editMode = false
    o.layout = loadLayout()
    o.cardRects = {}
    AegisPageDashboard.instance = o
    return o
end

function AegisPageDashboard:createChildren()
    -- the grid starts below the head strip; the strip carries the edit
    -- buttons so they never sit on top of a card
    local gridH = math.max(80, self.height - HEAD_H - GRIP_CHIN)
    self.scroll = AegisScrollArea:new(0, HEAD_H, self.width, gridH)
    self:addChild(self.scroll)
    self.canvas = AegisDashCanvas:new(0, 0, self.width, gridH, self)
    self.scroll:addChild(self.canvas)
    -- the canvas spans the full width, so lift the scrollbar back on
    -- top of it to keep the thumb draggable (it draws nothing while
    -- the content fits)
    if self.scroll.vscroll then
        self.scroll:removeChild(self.scroll.vscroll)
        self.scroll:addChild(self.scroll.vscroll)
    end
    self.scroll:setScrollHeight(gridH)

    -- pencil: toggles the layout edit mode, same button ends it
    self.editBtn = AegisButton:new(self.width - 50, 7, 30, 30, nil, "gear", self, AegisPageDashboard.onToggleEdit)
    self.editBtn.radius = 15
    self.editBtn.iconSize = 14
    self.editBtn.tooltip = getText("UI_Aegis_DashEdit")
    self:addChild(self.editBtn)

    -- back to the layout everyone starts with, only offered while editing
    self.resetBtn = AegisButton:new(self.width - 50 - 8 - 150, 7, 150, 30,
        getText("UI_Aegis_DashReset"), "refresh", self, AegisPageDashboard.onReset)
    self.resetBtn.radius = 15
    self.resetBtn.iconSize = 14
    self.resetBtn:setVisible(false)
    self:addChild(self.resetBtn)

    for _, id in ipairs(self.layout) do
        self:ensureWidgets(id)
    end
end

-- head strip: page title on the left, edit buttons on the right
function AegisPageDashboard:prerender()
    local c = Aegis.col
    Aegis.icon(self, "dash", PAD, 14, 16, 1, c.gold)
    Aegis.text(self, getText("UI_Aegis_NavDashboard"), PAD + 24, 12, UIFont.Medium, c.text)
    if self.editMode then
        local hx = PAD + 24 + Aegis.strW(UIFont.Medium, getText("UI_Aegis_NavDashboard")) + 16
        local hw = (self.resetBtn and self.resetBtn.x or self.width - 50) - 12 - hx
        if hw > 60 then
            Aegis.text(self, Aegis.fitText(getText("UI_Aegis_DashEditHint"), UIFont.Small, hw),
                hx, 14, UIFont.Small, c.muted)
        end
    end
    Aegis.hairline(self, PAD, HEAD_H - 4, self.width - PAD * 2, 0.6)
end

-- ------------------------------------------------------------------
-- Widgets per card, created lazily and repositioned by the layout
-- ------------------------------------------------------------------

function AegisPageDashboard:ensureWidgets(id)
    if self.widgets[id] then return end
    local canvas = self.canvas
    if not canvas then return end
    if id == "powers" then
        local list = {}
        for _, def in ipairs(POWERS) do
            local t = AegisToggle:new(0, 0, 100, 30, getText(def.label), def.icon, self, AegisPageDashboard.onPower)
            t.powerDef = def
            canvas:addChild(t)
            table.insert(list, t)
            self.toggles[def.key] = t
        end
        self.allPowersBtn = AegisButton:new(0, 0, 100, 34, getText("UI_Aegis_SeeAllPowers"), "wand", self, AegisPageDashboard.onSeeAllPowers)
        canvas:addChild(self.allPowersBtn)
        table.insert(list, self.allPowersBtn)
        self.widgets[id] = list
        self:refreshToggles()
    elseif id == "actions" then
        self.healBtn = AegisButton:new(0, 0, 100, 38, getText("UI_Aegis_HealSelf"), "heal", self, AegisPageDashboard.onHealSelf)
        self.healBtn.style = "gold"
        self.healBtn.tooltip = getText("UI_Aegis_HealTooltip")
        canvas:addChild(self.healBtn)
        self.careBtn = AegisButton:new(0, 0, 100, 38, getText("UI_Aegis_Care"), "check", self, AegisPageDashboard.onCareSelf)
        self.careBtn.tooltip = getText("UI_Aegis_CareTooltip")
        canvas:addChild(self.careBtn)
        self.widgets[id] = { self.healBtn, self.careBtn }
    elseif id == "features" then
        local list = {}
        for _, def in ipairs(FEATURES) do
            local t = AegisToggle:new(0, 0, 100, 28, getText(def.label), def.icon, self, function(page, checked)
                page:setFeature(def.opt, checked)
            end)
            t.featureOpt = def.opt
            t.tooltip = getTextOrNull(def.tip)
            t:setChecked(AegisShared.featureOn(def.opt))
            canvas:addChild(t)
            table.insert(list, t)
        end
        self.widgets[id] = list
    elseif id == "worldquick" then
        local list = {}
        for _, def in ipairs(QUICK_TIMES) do
            local b = AegisButton:new(0, 0, 60, 30, getText(def.label), nil, self, function(page)
                page:setQuickTime(def.hour)
            end)
            b.font = UIFont.Small
            canvas:addChild(b)
            table.insert(list, b)
        end
        local stop = AegisButton:new(0, 0, 100, 30, getText("UI_Aegis_StopWeather"), "ban", self,
            AegisPageDashboard.onStopWeather)
        canvas:addChild(stop)
        table.insert(list, stop)
        self.widgets[id] = list
    end
end

local function placeCardWidgets(page, id, x, y, w, h)
    local list = page.widgets[id]
    if not list then return end
    if id == "powers" then
        local wy = y + 40
        for i = 1, #POWERS do
            local t = list[i]
            t:setX(x + 14)
            t:setY(wy)
            t:setWidth(w - 28)
            wy = wy + 36
        end
        local btn = list[#POWERS + 1]
        btn:setX(x + 14)
        btn:setY(wy + 6)
        btn:setWidth(w - 28)
    elseif id == "actions" then
        local bw = math.floor((w - 28 - 12) / 2)
        list[1]:setX(x + 14)
        list[1]:setY(y + 42)
        list[1]:setWidth(bw)
        list[2]:setX(x + 14 + bw + 12)
        list[2]:setY(y + 42)
        list[2]:setWidth(bw)
    elseif id == "features" then
        local fy = y + 40
        for i = 1, #FEATURES do
            list[i]:setX(x + 14)
            list[i]:setY(fy)
            list[i]:setWidth(w - 28)
            fy = fy + 34
        end
    elseif id == "worldquick" then
        local n = #QUICK_TIMES
        local bw = math.floor((w - 28 - (n - 1) * 8) / n)
        for i = 1, n do
            list[i]:setX(x + 14 + (i - 1) * (bw + 8))
            list[i]:setY(y + 40)
            list[i]:setWidth(bw)
        end
        list[n + 1]:setX(x + 14)
        list[n + 1]:setY(y + 74)
        list[n + 1]:setWidth(w - 28)
    end
end

-- ------------------------------------------------------------------
-- Layout: order preserving two column fill. A card moves to the right
-- column when the left one is full, the flex feed absorbs the rest of
-- its column, exactly how the fixed page used to stack
-- ------------------------------------------------------------------

function AegisPageDashboard:cardHeight(def)
    if def.id == "restart" then
        if self.editMode then return def.h end
        return (self:restartLeft() and def.h) or 0
    end
    return def.h
end

function AegisPageDashboard:restartLeft()
    if not self.restartRemaining or self.restartRemaining < 0 then return nil end
    local left = self.restartRemaining - math.floor((getTimestampMs() - self.restartReceivedAt) / 1000)
    if left < 0 then return nil end
    return left
end

function AegisPageDashboard:layoutCards()
    local w = self.width
    -- the visible height is the scroll viewport, not the page: the head
    -- strip sits above it and the column break must not count it in
    local vh = self.scroll and self.scroll.height or (self.height - HEAD_H - GRIP_CHIN)
    local twoCol = w >= NARROW_W
    local leftW = twoCol and math.floor((w - 60) * 0.52) or (w - PAD * 2)
    local colX = { PAD, PAD + leftW + GAP_X }
    local colW = { leftW, twoCol and (w - 60 - leftW) or leftW }
    local colY = { PAD, PAD }
    local bottom = vh - PAD
    local maxCol = twoCol and 2 or 1
    local col = 1
    local rects = {}

    local function place(id, def, h, flex)
        local need = flex and FEED_MIN or h
        if col < maxCol and colY[col] > PAD and colY[col] + need > bottom then
            col = col + 1
        end
        if flex then
            h = math.max(FEED_MIN, bottom - colY[col])
        end
        table.insert(rects, { id = id, def = def, x = colX[col], y = colY[col], w = colW[col], h = h })
        colY[col] = colY[col] + h + GAP_Y
        if flex and col < maxCol then
            col = col + 1
        end
    end

    for _, id in ipairs(self.layout) do
        local def = cardById(id)
        if def and cardAllowed(def) then
            if def.flex then
                place(id, def, 0, true)
            else
                local h = self:cardHeight(def)
                if h > 0 then place(id, def, h, false) end
            end
        end
    end
    if self.editMode then
        place("__plus", nil, PLUS_H, false)
    end
    self.cardRects = rects

    -- widgets follow their card, cards outside the layout or without
    -- rights keep theirs hidden; rights can flip at runtime, so this
    -- runs every frame like the old per frame gates did
    local placed = {}
    for _, r in ipairs(rects) do
        placed[r.id] = true
        placeCardWidgets(self, r.id, r.x, r.y, r.w, r.h)
    end
    for id, list in pairs(self.widgets) do
        local show = (not self.editMode) and placed[id] == true
        for _, widget in ipairs(list) do
            if widget:isVisible() ~= show then widget:setVisible(show) end
        end
    end

    if self.canvas.width ~= w then self.canvas:setWidth(w) end
    local totalH = math.max(colY[1], colY[2]) - GAP_Y + PAD
    if totalH < vh then totalH = vh end
    if self.canvas.height ~= totalH then
        self.canvas:setHeight(totalH)
        self.scroll:setScrollHeight(totalH)
        local maxScroll = math.max(0, totalH - self.scroll.height)
        if -self.scroll:getYScroll() > maxScroll then
            self.scroll:setYScroll(-maxScroll)
        end
    end
end

function AegisPageDashboard:hasCard(id)
    local def = cardById(id)
    if not def or not cardAllowed(def) then return false end
    for _, cid in ipairs(self.layout) do
        if cid == id then return true end
    end
    return false
end

-- ------------------------------------------------------------------
-- Layout mutations, each one persists right away
-- ------------------------------------------------------------------

function AegisPageDashboard:saveLayout()
    Aegis.setPref("dashCards", table.concat(self.layout, ","))
end

function AegisPageDashboard:moveCard(dragId, beforeId)
    local from = nil
    for i, id in ipairs(self.layout) do
        if id == dragId then
            from = i
            break
        end
    end
    if not from then return end
    table.remove(self.layout, from)
    local at = #self.layout + 1
    if beforeId then
        for i, id in ipairs(self.layout) do
            if id == beforeId then
                at = i
                break
            end
        end
    end
    table.insert(self.layout, at, dragId)
    self:saveLayout()
end

function AegisPageDashboard:removeCard(id)
    for i, cid in ipairs(self.layout) do
        if cid == id then
            table.remove(self.layout, i)
            break
        end
    end
    self:saveLayout()
end

function AegisPageDashboard:addCard(id)
    local def = cardById(id)
    if not def or not cardAllowed(def) then return end
    for _, cid in ipairs(self.layout) do
        if cid == id then return end
    end
    table.insert(self.layout, id)
    self:saveLayout()
    self:ensureWidgets(id)
end

-- insertion target for a drop at mx, my: card id to insert before (nil
-- appends) plus the gold indicator line
function AegisPageDashboard:dropTargetAt(mx, my, dragId)
    local cards = {}
    for _, r in ipairs(self.cardRects) do
        if r.id ~= "__plus" and r.id ~= dragId then
            table.insert(cards, r)
        end
    end
    for i, r in ipairs(cards) do
        if inRect(r, mx, my) then
            if my < r.y + r.h / 2 then
                return r.id, { x = r.x, y = r.y - math.floor(GAP_Y / 2) - 1, w = r.w }
            end
            local nxt = cards[i + 1]
            if nxt then
                return nxt.id, { x = nxt.x, y = nxt.y - math.floor(GAP_Y / 2) - 1, w = nxt.w }
            end
            return nil, { x = r.x, y = r.y + r.h + math.floor(GAP_Y / 2), w = r.w }
        end
    end
    local last = cards[#cards]
    if last then
        return nil, { x = last.x, y = last.y + last.h + math.floor(GAP_Y / 2), w = last.w }
    end
    return nil, nil
end

function AegisPageDashboard.onToggleEdit(self)
    self.editMode = not self.editMode
    self.editBtn.style = self.editMode and "gold" or "ghost"
    if self.resetBtn then self.resetBtn:setVisible(self.editMode) end
    if self.canvas then self.canvas:resetPress() end
    -- no save here: every mutation persists on its own, an untouched
    -- visit must not stamp the pref (missing pref = follow the default)
    if not self.editMode and self.catalog then
        self.catalog:removeFromUIManager()
        self.catalog = nil
    end
end

function AegisPageDashboard:openCatalog()
    if self.catalog then return end
    Aegis.sound()
    self.catalog = AegisDashCatalog.show(self)
end

-- ------------------------------------------------------------------
-- Actions (unchanged behaviour from the fixed page)
-- ------------------------------------------------------------------

function AegisPageDashboard:refreshToggles()
    local p = getPlayer()
    if not p then return end
    for _, t in pairs(self.toggles) do
        t:setChecked(t.powerDef.get(p))
        -- without the capability the Java setter silently refuses, the toggle
        -- would be a dummy and the log entry a lie (same pattern as powers page)
        t:setEnabled(Aegis.hasCap(t.powerDef.cap))
    end
end

function AegisPageDashboard:refreshFeatures()
    local list = self.widgets["features"]
    if not list then return end
    -- hold the frame sync off until the server echoes the new value,
    -- otherwise the toggle snaps back for the round trip
    if getTimestampMs() < self.featHold then return end
    for _, t in ipairs(list) do
        if t.featureOpt then t:setChecked(AegisShared.featureOn(t.featureOpt)) end
    end
end

function AegisPageDashboard.onPower(self, checked, toggle)
    local p = getPlayer()
    if not p then return end
    Aegis.ensureSoloRole()
    toggle.powerDef.set(p, checked)
    Aegis.syncPowers(p)
    -- same log line as the powers page, godmode via dashboard
    -- was previously invisible in every mode
    Aegis.logAction("dashboard", (checked and "Power enabled: " or "Power disabled: ") .. getText(toggle.powerDef.label))
end

function AegisPageDashboard.onHealSelf(self)
    local p = getPlayer()
    if not p then return end
    -- fires in-process in solo, the handler heals and logs
    sendClientCommand(p, "AegisAdmin", "heal", {})
    Aegis.showToast(getText("UI_Aegis_HealSelf"))
end

function AegisPageDashboard.onCareSelf(self)
    local p = getPlayer()
    if not p then return end
    -- fires in-process in solo, in MP the server sets the stats
    sendClientCommand(p, "AegisAdmin", "care", {})
    Aegis.showToast(getText("UI_Aegis_Care"))
end

function AegisPageDashboard.onSeeAllPowers(self)
    self.window:switchPage("powers")
end

-- same client command the world page uses, the handler sets the clock
-- and writes the log entry
function AegisPageDashboard:setQuickTime(hour)
    local p = getPlayer()
    if not p then return end
    sendClientCommand(p, AegisShared.MODULE, "settime", { hour = hour })
    Aegis.showToast(getText("UI_Aegis_Time") .. " " .. string.format("%02d:00", hour))
end

-- same stop path as the world page, including its two designer resets
function AegisPageDashboard.onStopWeather(self)
    pcall(function()
        if AegisPageWorld then
            if AegisPageWorld.weatherKickStop then AegisPageWorld.weatherKickStop() end
            if AegisPageWorld.designerStop then AegisPageWorld.designerStop() end
        end
        local cm = getClimateManager()
        if isClient() then
            cm:transmitStopWeather()
        else
            cm:stopWeatherAndThunder()
        end
    end)
    Aegis.logAction("world", "Weather stopped")
    Aegis.showToast(getText("UI_Aegis_StopWeather"))
end

-- back to the layout a fresh install shows
function AegisPageDashboard.onReset(self)
    AegisConfirm.show(getText("UI_Aegis_DashReset"), getText("UI_Aegis_DashResetAsk"),
        getText("UI_Aegis_DashReset"), self, function(page)
        page.layout = {}
        for id in DEFAULT_LAYOUT:gmatch("[^,]+") do table.insert(page.layout, id) end
        page:saveLayout()
        for _, id in ipairs(page.layout) do page:ensureWidgets(id) end
        if page.canvas then page.canvas:resetPress() end
        Aegis.sound()
    end)
end

-- feature switch through the same vanilla sandbox channel the server
-- page uses: the server persists and distributes, every client follows
function AegisPageDashboard:setFeature(option, on)
    local ok = pcall(function()
        if isClient() then
            local copy = SandboxOptions.new()
            copy:copyValuesFrom(getSandboxOptions())
            copy:set("AegisEvents." .. option, on == true)
            copy:sendToServer()
        else
            getSandboxOptions():set("AegisEvents." .. option, on == true)
            getSandboxOptions():toLua()
        end
    end)
    if ok then
        self.featHold = getTimestampMs() + 3000
        Aegis.logAction("server", "Feature " .. option .. (on and " turned on" or " turned off"))
    end
end

function AegisPageDashboard:onShow()
    self:refreshToggles()
    self:refreshFeatures()
    -- poll right away on entering the page
    self.feedNextAt = 0
    self.pulseNextAt = 0
    self.scoreNextAt = 0
end

-- ------------------------------------------------------------------
-- Data polling (all throttled, all rights gated)
-- ------------------------------------------------------------------

-- the feed reuses the existing logList/logRead pair: pick the requester's
-- own newest Actions journal, then read its tail. Gated on the logs area,
-- otherwise every poll would come back as a denied toast
function AegisPageDashboard:pollFeed(now)
    if now < self.feedNextAt then return end
    self.feedNextAt = now + FEED_POLL_MS
    if not Aegis.canSee("logs") then return end
    local p = getPlayer()
    if not p then return end
    sendClientCommand(p, AegisShared.MODULE, "logList", { area = "Actions" })
end

function AegisPageDashboard:pollPulse(now)
    if now < self.pulseNextAt then return end
    self.pulseNextAt = now + PULSE_POLL_MS
    if not Aegis.canSee("server") then return end
    local p = getPlayer()
    if not p then return end
    sendClientCommand(p, AegisShared.MODULE, "restartStatus", {})
end

-- lines look like "12:36:42  [Target]  text"
local function parseFeedLines(lines)
    local rows = {}
    for i = #lines, 1, -1 do
        local time, target, text = tostring(lines[i]):match("^(%d+:%d+:%d+)%s+%[([^%]]*)%]%s+(.*)$")
        if time then
            table.insert(rows, { time = time:sub(1, 5), target = target, text = text })
        end
        if #rows >= 12 then break end
    end
    return rows
end

function AegisPageDashboard.receiveLog(command, args)
    local page = AegisPageDashboard.instance
    if not page or not args then return end
    if command == "logList" then
        if args.area ~= "Actions" or type(args.entries) ~= "table" then return end
        local me = getPlayer() and getPlayer():getUsername() or ""
        for _, e in ipairs(args.entries) do
            if e.admin == me and e.path then
                page.feedPath = e.path
                local p = getPlayer()
                if p then sendClientCommand(p, AegisShared.MODULE, "logRead", { path = e.path }) end
                break
            end
        end
    elseif command == "logRead" then
        if args.path == page.feedPath and type(args.lines) == "table" then
            page.feed = parseFeedLines(args.lines)
        end
    end
end

Events.OnServerCommand.Add(function(module, command, args)
    if module ~= "AegisAdmin" then return end
    if command == "logList" or command == "logRead" then
        AegisPageDashboard.receiveLog(command, args)
    elseif command == "restartStatus" then
        local page = AegisPageDashboard.instance
        if page and args then
            page.restartRemaining = tonumber(args.remaining) or -1
            page.restartReceivedAt = getTimestampMs()
        end
    end
end)

function AegisPageDashboard:update()
    ISPanel.update(self)
    self.refreshTick = self.refreshTick + 1
    if self.refreshTick >= 30 then
        self.refreshTick = 0
        self:refreshToggles()
        self:refreshFeatures()
    end
    if not self:isVisible() then return end
    local now = getTimestampMs()
    -- every poll only runs while its card is actually on the grid
    if self:hasCard("feed") then
        self:pollFeed(now)
    end
    if self:hasCard("restart") then
        self:pollPulse(now)
    end
    if self:hasCard("pulse") and now >= self.zombieNextAt then
        self.zombieNextAt = now + 2000
        pcall(function() self.zombieCount = getCell():getZombieList():size() end)
    end
    if self:hasCard("players") and isClient() and now >= self.scoreNextAt then
        self.scoreNextAt = now + SCORE_POLL_MS
        scoreboardUpdate()
    end
end

-- ------------------------------------------------------------------
-- Canvas: draws the cards below its widget children and handles the
-- edit mode mouse work (drag, cross, plus)
-- ------------------------------------------------------------------

function AegisDashCanvas:new(x, y, w, h, page)
    local o = ISPanel:new(x, y, w, h)
    setmetatable(o, self)
    self.__index = self
    o.background = false
    o.page = page
    o.crossRects = {}
    return o
end

function AegisDashCanvas:resetPress()
    self.pressCard = nil
    self.pressCross = nil
    self.pressPlus = nil
    self.dragId = nil
end

-- backgrounds and cards must be drawn before the child widgets
function AegisDashCanvas:prerender()
    local page = self.page
    page:layoutCards()
    local c = Aegis.col

    if not page.editMode then
        -- hint only with truly no allowed card, a resting restart
        -- countdown still counts as placed
        local any = false
        for _, id in ipairs(page.layout) do
            local def = cardById(id)
            if def and cardAllowed(def) then
                any = true
                break
            end
        end
        if not any then
            Aegis.textCentre(self, getText("UI_Aegis_DashEmpty"), math.floor(self.width / 2),
                math.floor((page.scroll and page.scroll.height or self.height) / 2) - 8, UIFont.Small, c.muted)
            return
        end
        for _, r in ipairs(page.cardRects) do
            if r.def and r.def.draw then
                r.def.draw(page, self, r.x, r.y, r.w, r.h, r.def)
            end
        end
        return
    end

    -- edit mode: simplified tiles, live widgets stay hidden so every
    -- card can be grabbed anywhere
    self.crossRects = {}
    local mx, my = self:getMouseX(), self:getMouseY()
    local over = self:isMouseOver()
    for _, r in ipairs(page.cardRects) do
        if r.id == "__plus" then
            local hot = over and inRect(r, mx, my)
            Aegis.roundFrame(self, r.x, r.y, r.w, r.h, 10, 1, hot and c.gold or c.goldDim, c.panel)
            local label = Aegis.fitText(getText("UI_Aegis_DashAddCard"), UIFont.Medium, r.w - 52)
            local tw = Aegis.strW(UIFont.Medium, label)
            local cx = math.max(r.x + 12, r.x + math.floor((r.w - tw - 24) / 2))
            Aegis.icon(self, "plus", cx, r.y + math.floor((r.h - 16) / 2), 16, 1, hot and c.goldHi or c.gold)
            Aegis.text(self, label, cx + 24, r.y + math.floor((r.h - Aegis.fontH(UIFont.Medium)) / 2),
                UIFont.Medium, hot and c.text or c.muted)
        else
            local a = (self.dragId == r.id) and 0.35 or 1
            Aegis.roundFrame(self, r.x, r.y, r.w, r.h, 10, a, c.line, c.panel)
            Aegis.icon(self, r.def.icon, r.x + 14, r.y + 8, 15, a, c.gold)
            Aegis.text(self, Aegis.fitText(getText(r.def.title), UIFont.Medium, r.w - 36 - 32),
                r.x + 36, r.y + 6, UIFont.Medium, c.text, a)
            local cross = { x = r.x + r.w - 26, y = r.y + 7, w = 16, h = 16, id = r.id }
            table.insert(self.crossRects, cross)
            local hot = over and inRect(cross, mx, my)
            Aegis.icon(self, "close", cross.x + 2, cross.y + 2, 12, hot and 1 or 0.55, hot and c.danger or c.muted)
        end
    end
end

-- drag preview above everything the canvas drew
function AegisDashCanvas:render()
    local page = self.page
    if not page.editMode or not self.dragId then return end
    local c = Aegis.col
    local def = cardById(self.dragId)
    local mx, my = self:getMouseX(), self:getMouseY()
    local beforeId, line = page:dropTargetAt(mx, my, self.dragId)
    if line then
        self:drawRect(line.x, line.y, line.w, 2, 1, c.gold.r, c.gold.g, c.gold.b)
    end
    if def then
        local gx, gy = mx - 20, my - 16
        Aegis.roundRect(self, gx, gy, 220, 32, 8, 0.92, c.card)
        Aegis.icon(self, def.icon, gx + 10, gy + 8, 15, 1, c.gold)
        Aegis.text(self, getText(def.title), gx + 32, gy + 7, UIFont.Medium, c.text)
    end
end

function AegisDashCanvas:onMouseDown(x, y)
    local page = self.page
    if not page.editMode then return end
    for _, r in ipairs(self.crossRects) do
        if inRect(r, x, y) then
            self.pressCross = r.id
            return
        end
    end
    for _, r in ipairs(page.cardRects) do
        if inRect(r, x, y) then
            if r.id == "__plus" then
                self.pressPlus = true
            else
                self.pressCard = { id = r.id, x = x, y = y }
            end
            return
        end
    end
end

function AegisDashCanvas:onMouseMove(dx, dy)
    if self.pressCard and not self.dragId then
        local mx, my = self:getMouseX(), self:getMouseY()
        if math.abs(mx - self.pressCard.x) > 5 or math.abs(my - self.pressCard.y) > 5 then
            self.dragId = self.pressCard.id
        end
    end
end

function AegisDashCanvas:onMouseMoveOutside(dx, dy)
    self:onMouseMove(dx, dy)
end

function AegisDashCanvas:onMouseUp(x, y)
    local page = self.page
    if not page.editMode then
        self:resetPress()
        -- the compact player card and every shortcut tile open their page
        for _, r in ipairs(page.cardRects) do
            if inRect(r, x, y) then
                local target = (r.id == "players" and "players") or (r.def and r.def.jumpTo)
                if target then
                    Aegis.sound()
                    page.window:switchPage(target)
                end
                return
            end
        end
        return
    end
    if self.dragId then
        local dragId = self.dragId
        local beforeId = page:dropTargetAt(x, y, dragId)
        self:resetPress()
        page:moveCard(dragId, beforeId)
        Aegis.sound()
        return
    end
    if self.pressCross then
        local id = self.pressCross
        self:resetPress()
        for _, r in ipairs(self.crossRects) do
            if r.id == id and inRect(r, x, y) then
                Aegis.sound()
                page:removeCard(id)
                return
            end
        end
        return
    end
    if self.pressPlus then
        self:resetPress()
        for _, r in ipairs(page.cardRects) do
            if r.id == "__plus" and inRect(r, x, y) then
                page:openCatalog()
                return
            end
        end
        return
    end
    self:resetPress()
end

function AegisDashCanvas:onMouseUpOutside(x, y)
    self:resetPress()
end

-- ------------------------------------------------------------------
-- Catalog: the plus tile lists every allowed card that is not placed
-- ------------------------------------------------------------------

function AegisDashCatalog.show(page)
    local sw, sh = getCore():getScreenWidth(), getCore():getScreenHeight()
    local o = ISPanel:new(0, 0, sw, sh)
    setmetatable(o, AegisDashCatalog)
    AegisDashCatalog.__index = AegisDashCatalog
    o.background = true
    o.backgroundColor = { r = 0, g = 0, b = 0, a = 0.55 }
    o.borderColor = { r = 0, g = 0, b = 0, a = 0 }
    o.page = page

    local placed = {}
    for _, id in ipairs(page.layout) do placed[id] = true end
    o.rows = {}
    for _, def in ipairs(allCards()) do
        if not placed[def.id] and cardAllowed(def) then
            table.insert(o.rows, def)
        end
    end

    o.rowH = 54
    o.cardW = 460
    o.top = 1
    -- with a shortcut tile per page the list outgrows the screen, so it
    -- shows a window of rows and scrolls with the wheel
    local chrome = 48 + 12 + 36 + 16
    o.maxRows = math.max(3, math.floor((sh - 80 - chrome) / o.rowH))
    o.shown = math.min(math.max(#o.rows, 1), o.maxRows)
    o.cardH = 48 + o.shown * o.rowH + 12 + 36 + 16
    o.cx = math.floor((sw - o.cardW) / 2)
    o.cy = math.floor((sh - o.cardH) / 2)
    o:initialise()
    o:addToUIManager()
    o:setAlwaysOnTop(true)

    o.cancelBtn = AegisButton:new(o.cx + 16, o.cy + o.cardH - 52, o.cardW - 32, 36,
        getText("UI_Aegis_Cancel"), nil, o, AegisDashCatalog.onCancel)
    o:addChild(o.cancelBtn)
    return o
end

function AegisDashCatalog:onCancel()
    self:removeFromUIManager()
    if self.page.catalog == self then self.page.catalog = nil end
end

function AegisDashCatalog:update()
    ISPanel.update(self)
    -- the page can be rebuilt under the dialog (window resize) or the
    -- edit mode can end. The panel itself can also be closed or folded
    -- into the mini bar while this is open, and then a full screen
    -- overlay would stay behind on the game
    if AegisPageDashboard.instance ~= self.page or not self.page.editMode or not self.page:isVisible()
        or not AegisWindow.instance or not AegisWindow.instance:isVisible()
        or (AegisMiniBar and AegisMiniBar.instance) then
        self:onCancel()
    end
end

-- rect of the list row at display slot i (1 = topmost visible row)
function AegisDashCatalog:rowRect(i)
    return { x = self.cx + 16, y = self.cy + 44 + (i - 1) * self.rowH, w = self.cardW - 32, h = self.rowH - 6 }
end

function AegisDashCatalog:clampTop()
    local maxTop = math.max(1, #self.rows - self.shown + 1)
    if self.top > maxTop then self.top = maxTop end
    if self.top < 1 then self.top = 1 end
end

function AegisDashCatalog:prerender()
    ISPanel.prerender(self)
    local c = Aegis.col
    Aegis.shadow(self, self.cx, self.cy, self.cardW, self.cardH, 26, 0.7)
    Aegis.roundFrame(self, self.cx, self.cy, self.cardW, self.cardH, 12, 1, c.line, c.bg)
    Aegis.text(self, getText("UI_Aegis_DashCatalog"), self.cx + 16, self.cy + 14, UIFont.Medium, c.text)
    if #self.rows == 0 then
        Aegis.textCentre(self, getText("UI_Aegis_DashCatalogEmpty"), self.cx + math.floor(self.cardW / 2),
            self.cy + 48 + math.floor(self.rowH / 2) - 8, UIFont.Small, c.muted)
        return
    end
    self:clampTop()
    if #self.rows > self.shown then
        Aegis.textRight(self, getText("UI_Aegis_DashCatalogMore", self.top, self.top + self.shown - 1, #self.rows),
            self.cx + self.cardW - 16, self.cy + 17, UIFont.Small, c.muted)
    end
    local mx, my = self:getMouseX(), self:getMouseY()
    for i = 1, self.shown do
        local def = self.rows[self.top + i - 1]
        if def then
            local r = self:rowRect(i)
            local hot = inRect(r, mx, my)
            Aegis.roundFrame(self, r.x, r.y, r.w, r.h, 8, 1, hot and c.gold or c.line, hot and c.cardHi or c.card)
            Aegis.icon(self, def.icon, r.x + 14, r.y + math.floor((r.h - 16) / 2), 16, 1, c.gold)
            Aegis.text(self, Aegis.fitText(getText(def.title), UIFont.Medium, r.w - 56), r.x + 42, r.y + 6, UIFont.Medium, c.text)
            Aegis.text(self, Aegis.fitText(getText(def.desc), UIFont.Small, r.w - 56), r.x + 42,
                r.y + 8 + Aegis.fontH(UIFont.Medium), UIFont.Small, c.muted)
        end
    end
end

function AegisDashCatalog:onMouseWheel(del)
    self.top = self.top + (del > 0 and 1 or -1)
    self:clampTop()
    return true
end

function AegisDashCatalog:onMouseUp(x, y)
    for i = 1, self.shown do
        local def = self.rows[self.top + i - 1]
        if def and inRect(self:rowRect(i), x, y) then
            Aegis.sound()
            self.page:addCard(def.id)
            self:onCancel()
            return
        end
    end
end

AegisWindow.registerPage({
    id = "dashboard",
    icon = "dash",
    label = "UI_Aegis_NavDashboard",
    create = AegisPageDashboard.create,
})
