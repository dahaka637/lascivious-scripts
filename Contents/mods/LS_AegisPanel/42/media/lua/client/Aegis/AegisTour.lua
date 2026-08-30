-- Guided tour: a spotlight walks from stop to stop, the card beside it
-- explains what lives there. Every exit counts as seen, so the tour
-- offers itself exactly once per mode and never asks for a checkbox.
require "Aegis/AegisTheme"
require "Aegis/AegisWidgets"
require "Aegis/AegisHelpContent"
require "Aegis/AegisPlayerCore"

AegisTour = ISPanel:derive("AegisTour")
AegisTour.instance = nil

local CARD_W = 360
local PAD = 16
-- distance between spotlight and card, and the margin the card keeps
-- from the screen border
local GAP = 16
local EDGE = 14
local BTN_H = 30
local BTN_GAP = 8
local BTN_MIN_W = 84
local MAX_LINES = 10
-- header height of both windows, the help stop rides on it
local HEADER_H = 64
local MOVE_RATE = 0.26
local FADE_RATE = 0.11

-- fixed order. dock and help are not pages: the first points at the HUD
-- dock, the second at the button row in the window header
local ORDER = {
    admin = { "dashboard", "powers", "roles", "options", "sandbox", "tools", "dock", "help" },
    player = { "me", "stats", "sos", "kits" },
}

local HOME = { admin = "dashboard", player = "me" }

local function normMode(mode)
    return mode == "player" and "player" or "admin"
end

local function prefKey(mode)
    return mode == "player" and "tourPlayer" or "tourGold"
end

-- windows are looked up lazily, requiring them here would tie the load
-- order of two files that already know this module
local function winFor(mode)
    if mode == "player" then
        return AegisPlayerWindow and AegisPlayerWindow.instance
    end
    return AegisWindow and AegisWindow.instance
end

local function pageDefs(mode)
    if mode == "player" then
        return AegisPlayerWindow and AegisPlayerWindow.pages
    end
    return AegisWindow and AegisWindow.pages
end

local function pageKnown(mode, page)
    local defs = pageDefs(mode)
    if not defs then return false end
    for _, def in ipairs(defs) do
        if def.id == page then return true end
    end
    return false
end

-- a stop only shows when its area is granted. The same gate switchPage
-- uses, so the tour never points at a page that refuses to open
local function stopAllowed(mode, page)
    if page == "dock" then
        local d = AegisHudDock and AegisHudDock.instance
        return d ~= nil and d:isVisible()
    end
    if page == "help" then return true end
    if not pageKnown(mode, page) then return false end
    -- a page the admin hid stays hidden: switchPage would pull it back
    -- into the nav and overwrite an arrangement he chose himself
    local win = winFor(mode)
    if win and win.hiddenSet and win:hiddenSet()[page] then return false end
    if mode == "player" then return true end
    return Aegis.canSee(AegisWindow.pageArea(page))
end

local function entryFor(list, page)
    for _, e in ipairs(list) do
        if e.page == page then return e end
    end
    return nil
end

local function btnWidth(label)
    return math.max(BTN_MIN_W, Aegis.strW(UIFont.Small, label) + 24)
end

local function approach(cur, target, rate)
    local t = rate * Aegis.delta()
    if t > 1 then t = 1 end
    return cur + (target - cur) * t
end

-- the world map and the pause screen cover the whole game, an always on
-- top overlay would sit on their buttons. Same test the icon bar uses
local function covered()
    return (ISWorldMap_instance ~= nil and ISWorldMap_instance:isVisible())
        or (MainScreen ~= nil and MainScreen.instance ~= nil and MainScreen.instance:isVisible())
end

-- a start that waits for the rights reply
local pending = nil

function AegisTour.seen(mode)
    return Aegis.getPref(prefKey(normMode(mode))) == "1"
end

function AegisTour.markSeen(mode)
    Aegis.setPref(prefKey(normMode(mode)), "1")
end

-- true when a tour was actually opened, the caller then holds back
-- whatever it wanted to show instead
-- true also while the tour is still waiting for the rights reply: the
-- caller has handed over and must not show anything else meanwhile
function AegisTour.maybeStart(mode)
    mode = normMode(mode)
    if AegisTour.seen(mode) then return false end
    if AegisTour.start(mode) ~= nil then return true end
    if not isClient() or mode == "player" then return false end
    -- no page was allowed yet, which on a server simply means the rights
    -- have not arrived. Wait for them, then try once more
    if pending then return true end
    pending = { until_ = getTimestampMs() + 12000 }
    return true
end

local function pendingWatch()
    if not pending then return end
    if AegisTour.instance then pending = nil return end
    local ready = Aegis.rightsLoaded == true
    if not ready and getTimestampMs() < pending.until_ then return end
    pending = nil
    if ready and AegisTour.start("admin") ~= nil then return end
    -- giving up hands the notices back, the update window may show
    if AegisTourDone then AegisTourDone("admin") end
end

Events.OnTick.Add(pendingWatch)

-- an invisible panel gets no prerender, so the way back is a tick
Events.OnTick.Add(function()
    local o = AegisTour.instance
    if o and not o.done and not o:isVisible() and not covered() then
        o:setVisible(true)
    end
end)

function AegisTour.start(mode)
    mode = normMode(mode)
    if AegisTour.instance then AegisTour.instance:finish() end
    AegisTour.instance = nil

    local win = winFor(mode)
    if not win or win.minimized or not win:isVisible() then return nil end
    local content = AegisHelpContent.get(mode)
    local list = content and content.tour
    if type(list) ~= "table" then return nil end

    -- order comes from here, texts from the help content; a stop without
    -- text is left out entirely so the counter stays honest
    local stops = {}
    for _, page in ipairs(ORDER[mode]) do
        local e = entryFor(list, page)
        if e and stopAllowed(mode, page) then
            table.insert(stops, { page = page, title = e.title or "", text = e.text or "" })
        end
    end
    -- dock and help alone are not a tour. That is what an unanswered
    -- rights request looks like, and starting there would burn the tour
    local pages = 0
    for _, st in ipairs(stops) do
        if st.page ~= "dock" and st.page ~= "help" then pages = pages + 1 end
    end
    if pages == 0 then return nil end

    local sw, sh = getCore():getScreenWidth(), getCore():getScreenHeight()
    local o = ISPanel:new(0, 0, sw, sh)
    setmetatable(o, AegisTour)
    AegisTour.__index = AegisTour
    o.background = false
    o.borderColor = { r = 0, g = 0, b = 0, a = 0 }
    o.mode = mode
    o.col = mode == "player" and AegisPlayerCol or Aegis.col
    if mode == "player" then
        o.acc, o.accHi = AegisPlayerCol.accent, AegisPlayerCol.accentHi
    else
        o.acc, o.accHi = Aegis.col.gold, Aegis.col.goldHi
    end
    o.sw, o.sh = sw, sh
    o.stops = stops
    o.index = 0
    o.anim = 0
    o.lineH = Aegis.fontH(UIFont.Small)
    o.titleH = Aegis.fontH(UIFont.Medium)
    o.cardW = CARD_W
    o.cardH = 120
    o.lines = {}
    o.title = ""
    o.stepText = ""

    o:initialise()
    o:addToUIManager()
    o:setAlwaysOnTop(true)

    o.skipBtn = AegisButton:new(0, 0, btnWidth(getText("UI_Aegis_TourSkip")), BTN_H,
        getText("UI_Aegis_TourSkip"), nil, o, AegisTour.onSkip)
    o:addChild(o.skipBtn)
    o.backBtn = AegisButton:new(0, 0, btnWidth(getText("UI_Aegis_TourBack")), BTN_H,
        getText("UI_Aegis_TourBack"), nil, o, AegisTour.onBack)
    o:addChild(o.backBtn)
    o.nextBtn = AegisButton:new(0, 0, btnWidth(getText("UI_Aegis_TourNext")), BTN_H,
        getText("UI_Aegis_TourNext"), nil, o, AegisTour.onNext)
    o:addChild(o.nextBtn)

    AegisTour.instance = o
    o:showStop(1)
    if o.done then return nil end
    return o
end

function AegisTour.onNext(self) self:go(1) end
function AegisTour.onBack(self) self:go(-1) end
function AegisTour.onSkip(self) self:finish() end

-- walk in one direction and hand over the first stop still allowed.
-- Running past the last one ends the tour, running past the first one
-- keeps the current stop
function AegisTour:go(dir)
    local i = self.index + dir
    while i >= 1 and i <= #self.stops do
        if stopAllowed(self.mode, self.stops[i].page) then
            self:showStop(i)
            return
        end
        i = i + dir
    end
    if dir > 0 then self:finish() end
end

local function hasStop(self, from, dir)
    local j = from + dir
    while j >= 1 and j <= #self.stops do
        if stopAllowed(self.mode, self.stops[j].page) then return true end
        j = j + dir
    end
    return false
end

-- screen rectangle the spotlight covers. Pages use the content area of
-- the window, converted from window space to screen space. out is
-- filled in place, the rectangle is measured every frame
function AegisTour:rectFor(win, page, out)
    out = out or {}
    local wx, wy = win:getX(), win:getY()
    local dock = page == "dock" and AegisHudDock and AegisHudDock.instance or nil
    if dock then
        out.x, out.y = dock:getX(), dock:getY()
        out.w, out.h = dock:getWidth(), math.max(20, dock:getHeight())
    elseif page == "help" then
        -- the question mark and the manual button, not close and collapse
        out.x, out.y = wx + win:getWidth() - 162, wy + 14
        out.w, out.h = 80, 36
    else
        local cx, cy, cw, ch = win:contentArea()
        out.x, out.y, out.w, out.h = wx + cx, wy + cy, cw, ch
    end
    return out
end

-- card beside the spotlight: below, else right, else above, else left,
-- and clamped onto the screen in every case
function AegisTour:placeCard(r)
    local w, h = self.cardW, self.cardH
    local x = math.floor(r.x + (r.w - w) / 2)
    local y = math.floor(r.y + r.h + GAP)
    if y + h > self.sh - EDGE then
        if r.x + r.w + GAP + w <= self.sw - EDGE then
            x = math.floor(r.x + r.w + GAP)
            y = math.floor(r.y + (r.h - h) / 2)
        elseif r.y - GAP - h >= EDGE then
            y = math.floor(r.y - GAP - h)
        elseif r.x - GAP - w >= EDGE then
            x = math.floor(r.x - GAP - w)
            y = math.floor(r.y + (r.h - h) / 2)
        end
    end
    if x + w > self.sw - EDGE then x = self.sw - EDGE - w end
    if y + h > self.sh - EDGE then y = self.sh - EDGE - h end
    if x < EDGE then x = EDGE end
    if y < EDGE then y = EDGE end
    return x, y
end

function AegisTour:showStop(i)
    local stop = self.stops[i]
    if not stop then self:finish() return end
    local win = winFor(self.mode)
    if not win or win.minimized then self:finish() return end
    self.index = i

    if stop.page ~= "dock" and stop.page ~= "help" then
        win:switchPage(stop.page)
    end

    local last = not hasStop(self, i, 1)
    self.nextBtn.label = last and getText("UI_Aegis_TourDone") or getText("UI_Aegis_TourNext")
    self.nextBtn:setWidth(btnWidth(self.nextBtn.label))
    self.backBtn:setEnabled(hasStop(self, i, -1))

    -- the card grows with its button row before the text is wrapped
    local need = PAD * 2 + self.skipBtn.width + 12 + self.backBtn.width + BTN_GAP + self.nextBtn.width
    self.cardW = math.min(math.max(CARD_W, need), self.sw - EDGE * 2)
    self.stepText = getText("UI_Aegis_TourStep", tostring(i), tostring(#self.stops))
    self.title = stop.title
    self.lines = Aegis.wrapText(stop.text, UIFont.Small, self.cardW - PAD * 2, MAX_LINES)
    self.cardH = PAD + self.lineH + 6 + self.titleH + 8 + #self.lines * self.lineH + 14 + BTN_H + PAD

    local r = self:rectFor(win, stop.page, self.target)
    self.target = r
    if not self.rect then
        self.rect = { x = r.x, y = r.y, w = r.w, h = r.h }
    end
    local cx, cy = self:placeCard(r)
    self.cardTX, self.cardTY = cx, cy
    if not self.cardX then
        self.cardX, self.cardY = cx, cy
    end
end

function AegisTour:finish()
    if self.done then return end
    self.done = true
    AegisTour.markSeen(self.mode)
    -- back to the start page, whichever stop the tour ended on
    local win = winFor(self.mode)
    if win and not win.minimized then
        win:switchPage(HOME[self.mode])
    end
    self:removeFromUIManager()
    if AegisTour.instance == self then AegisTour.instance = nil end
    -- the update window belongs on top of an open panel, not on an empty
    -- screen after the panel was closed mid tour
    if AegisTourDone and win and not win.minimized and win:isVisible() then
        AegisTourDone(self.mode)
    end
end

-- clicks next to the card do nothing, the tour is left through its buttons
function AegisTour:onMouseDown(x, y) end

function AegisTour:onKeyRelease(key)
    if key == Keyboard.KEY_ESCAPE then self:finish() end
end


-- four bars around the target darken the rest of the screen
function AegisTour:dimAround(x, y, w, h, a)
    if y > 0 then self:drawRect(0, 0, self.sw, y, a, 0, 0, 0) end
    local below = self.sh - y - h
    if below > 0 then self:drawRect(0, y + h, self.sw, below, a, 0, 0, 0) end
    if x > 0 then self:drawRect(0, y, x, h, a, 0, 0, 0) end
    local right = self.sw - x - w
    if right > 0 then self:drawRect(x + w, y, right, h, a, 0, 0, 0) end
end

function AegisTour:prerender()
    ISPanel.prerender(self)
    if self.done then return end
    self.sw, self.sh = getCore():getScreenWidth(), getCore():getScreenHeight()
    if self:getWidth() ~= self.sw or self:getHeight() ~= self.sh then
        self:setWidth(self.sw)
        self:setHeight(self.sh)
    end
    if covered() then
        self:setVisible(false)
        return
    end
    local win = winFor(self.mode)
    -- a closed or collapsed panel ends the tour, and that counts as seen
    if not win or win.minimized or not win:isVisible() then
        self:finish()
        return
    end
    local stop = self.stops[self.index]
    if not stop then
        self:finish()
        return
    end

    if self.anim < 1 then
        self.anim = math.min(1, self.anim + Aegis.delta() * FADE_RATE)
    end
    local a = self.anim
    local c = self.col

    -- the target is re-measured every frame, a resized window or a moved
    -- dock keeps the spotlight where it belongs
    self:rectFor(win, stop.page, self.target)
    local cx, cy = self:placeCard(self.target)
    self.cardTX, self.cardTY = cx, cy

    local r, tg = self.rect, self.target
    r.x = approach(r.x, tg.x, MOVE_RATE)
    r.y = approach(r.y, tg.y, MOVE_RATE)
    r.w = approach(r.w, tg.w, MOVE_RATE)
    r.h = approach(r.h, tg.h, MOVE_RATE)
    self.cardX = approach(self.cardX, self.cardTX, MOVE_RATE)
    self.cardY = approach(self.cardY, self.cardTY, MOVE_RATE)

    -- clamped drawing rectangle, a target half off screen would otherwise
    -- turn the dim bars inside out
    local x = math.max(0, math.min(math.floor(r.x), self.sw))
    local y = math.max(0, math.min(math.floor(r.y), self.sh))
    local w = math.max(0, math.min(math.floor(r.w), self.sw - x))
    local h = math.max(0, math.min(math.floor(r.h), self.sh - y))
    self:dimAround(x, y, w, h, 0.62 * a)

    -- lit frame with a slow breath around it
    local pulse = 0.6 + 0.4 * math.sin(getTimestampMs() / 420)
    local acc, accHi = self.acc, self.accHi
    self:drawRect(x - 4, y - 4, w + 8, 2, 0.30 * a * pulse, acc.r, acc.g, acc.b)
    self:drawRect(x - 4, y + h + 2, w + 8, 2, 0.30 * a * pulse, acc.r, acc.g, acc.b)
    self:drawRect(x - 4, y - 2, 2, h + 4, 0.30 * a * pulse, acc.r, acc.g, acc.b)
    self:drawRect(x + w + 2, y - 2, 2, h + 4, 0.30 * a * pulse, acc.r, acc.g, acc.b)
    self:drawRect(x - 2, y - 2, w + 4, 2, a, accHi.r, accHi.g, accHi.b)
    self:drawRect(x - 2, y + h, w + 4, 2, a, accHi.r, accHi.g, accHi.b)
    self:drawRect(x - 2, y, 2, h, a, accHi.r, accHi.g, accHi.b)
    self:drawRect(x + w, y, 2, h, a, accHi.r, accHi.g, accHi.b)

    -- card
    local px, py = math.floor(self.cardX), math.floor(self.cardY)
    Aegis.shadow(self, px, py, self.cardW, self.cardH, 22, 0.65 * a)
    Aegis.roundFrame(self, px, py, self.cardW, self.cardH, 10, a, c.line, c.bg)
    self:drawRect(px + 10, py, self.cardW - 20, 2, a, acc.r, acc.g, acc.b)

    local ty = py + PAD
    Aegis.text(self, self.stepText, px + PAD, ty, UIFont.Small, self.accHi, a)
    ty = ty + self.lineH + 6
    Aegis.text(self, self.title, px + PAD, ty, UIFont.Medium, c.text, a)
    ty = ty + self.titleH + 8
    for _, line in ipairs(self.lines) do
        Aegis.text(self, line, px + PAD, ty, UIFont.Small, c.text, 0.92 * a)
        ty = ty + self.lineH
    end

    local by = py + self.cardH - PAD - BTN_H
    self.skipBtn:setX(px + PAD)
    self.skipBtn:setY(by)
    self.nextBtn:setX(px + self.cardW - PAD - self.nextBtn.width)
    self.nextBtn:setY(by)
    self.backBtn:setX(self.nextBtn.x - BTN_GAP - self.backBtn.width)
    self.backBtn:setY(by)
    -- the way on is the accented one, the button itself stays neutral
    self:drawRect(self.nextBtn.x + 8, by + BTN_H + 3, self.nextBtn.width - 16, 2, a, acc.r, acc.g, acc.b)
end
