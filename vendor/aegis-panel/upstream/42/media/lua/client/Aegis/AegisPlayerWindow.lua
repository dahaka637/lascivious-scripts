-- Player panel main window: header, sidebar, page host. Same optical
-- language as the admin window but blue, fixed size, no rights machinery
require "ISUI/ISPanel"
require "Aegis/AegisTheme"
require "Aegis/AegisWidgets"
require "Aegis/AegisHelp"
require "Aegis/AegisPageHelp"
require "Aegis/AegisPlayerCore"
require "Aegis/AegisBrand"
-- AegisResizeGrip lives in the admin window file and is shared
require "Aegis/AegisWindow"

AegisPlayerWindow = ISPanel:derive("AegisPlayerWindow")
AegisPlayerWindow.instance = nil
AegisPlayerWindow.pages = {}

local HEADER_H = 64
local SIDEBAR_W = 188
local NAV_H = 40
local WIN_W = 980
local WIN_H = 640
-- resize floor and screen margin, mirrors the admin window
local MIN_W = 820
local MIN_H = 540
local EDGE = 12

-- the player panel counts on its own, separate from the admin panel version
AegisPlayerWindow.version = "1.4"

-- pages register here: { id, icon, label (translation key), create(window) }.
-- Files load alphabetically, so without a fixed order the kits page came
-- first in the sidebar; the id order below decides the
-- default, the user can drag his own order on top (navOrderPlayer pref)
local PAGE_ORDER = { me = 1, stats = 2, health = 3, safehouse = 4, vehicles = 5, claim = 6, kits = 7, sos = 8 }

function AegisPlayerWindow.registerPage(def)
    table.insert(AegisPlayerWindow.pages, def)
    table.sort(AegisPlayerWindow.pages, function(a, b)
        return (PAGE_ORDER[a.id] or 99) < (PAGE_ORDER[b.id] or 99)
    end)
end

-- the kits page follows the server flag, every other page is visible to
-- all; a configured boost key also opens it (redeem strip plus the booster
-- kits, the server scopes the list)
local function pageVisible(id)
    if id == "kits" then
        local s = AegisPlayerClient.state
        return s ~= nil and (s.kits == true or s.boostReady == true)
    end
    return true
end

-- first page after the server flag gate and the view filter; the win
-- argument lets createChildren use itself before the instance field is
-- set
function AegisPlayerWindow.firstVisiblePage(win)
    win = win or AegisPlayerWindow.instance
    local pages = win and win:orderedPages() or AegisPlayerWindow.pages
    for _, def in ipairs(pages) do
        if win and win:navVisible(def) or (not win and pageVisible(def.id)) then
            return def.id
        end
    end
    -- every reachable page is hidden away: fall back to the first
    -- reachable one, switchPage brings it back into the nav with a note
    for _, def in ipairs(pages) do
        if pageVisible(def.id) then return def.id end
    end
    return nil
end

-- Notices when the panel opens: while the tour is unseen it runs first and
-- the update notice waits for its end. A fresh install has no saved setting
-- at all, its changelog is parked so a newcomer never sees a list of changes
-- he did not live through
local function openNotices(mode)
    if AegisTour and AegisTour.instance then return end
    if AegisTour and not AegisTour.seen(mode) then
        -- a first install has nothing to catch up on, so the change
        -- list is parked before the tour can hand over to it
        if AegisWhatsNew and AegisWhatsNew.isFreshInstall() then
            AegisWhatsNew.markSeen(mode)
        end
        if AegisTour.maybeStart(mode) then return end
    end
    if AegisWhatsNew then AegisWhatsNew.maybeShow(mode) end
end

function AegisPlayerWindow.toggle()
    -- no window before the server granted the panel
    if not AegisPlayerClient.enabled() then return end
    if AegisPlayerWindow.instance then
        local o = AegisPlayerWindow.instance
        -- collapsed to the mini bar: bring the full window back
        if AegisPlayerMiniBar.instance then
            AegisPlayerMiniBar.instance:restore()
            return
        end
        local show = not o:isVisible()
        o:setVisible(show)
        if show then
            o:bringToTop()
            openNotices("player")
        else
            o.dragging = false
        end
        return
    end
    local sw, sh = getCore():getScreenWidth(), getCore():getScreenHeight()
    -- restore the persisted size, clamped between the floor and the
    -- screen minus a small edge (admin window pattern)
    local defW = math.min(WIN_W, sw - 24)
    local defH = math.min(WIN_H, sh - 24)
    local w = math.max(math.min(MIN_W, sw - 24), math.min(tonumber(Aegis.getPref("pwinW")) or defW, sw - EDGE * 2))
    local h = math.max(math.min(MIN_H, sh - 24), math.min(tonumber(Aegis.getPref("pwinH")) or defH, sh - EDGE * 2))
    local o = AegisPlayerWindow:new(math.floor((sw - w) / 2), math.floor((sh - h) / 2), w, h)
    o:initialise()
    o:addToUIManager()
    AegisPlayerWindow.instance = o
    openNotices("player")
end

function AegisPlayerWindow:new(x, y, w, h)
    local o = ISPanel:new(x, y, w, h)
    setmetatable(o, self)
    self.__index = self
    o.background = false
    o.anim = 0
    o.baseY = y
    o.activePage = nil
    o.pagePanels = {}
    o.navRects = {}
    o.eyeRects = {}
    o.navHoverT = {}
    o.indicatorY = -1
    o.dragging = false
    o.subtitle = nil
    o.minimumWidth = math.min(MIN_W, getCore():getScreenWidth() - 24)
    o.minimumHeight = math.min(MIN_H, getCore():getScreenHeight() - 24)
    return o
end

function AegisPlayerWindow:createChildren()
    self.closeBtn = AegisButton:new(self.width - 44, 16, 30, 30, nil, "close", self, AegisPlayerWindow.close)
    self.closeBtn.radius = 15
    self:addChild(self.closeBtn)

    -- collapse to a small movable bar, same mechanic as the admin window
    self.minBtn = AegisButton:new(self.width - 44 - 38, 16, 30, 30, nil, "minus", self, AegisPlayerWindow.toggleMinimize)
    self.minBtn.radius = 15
    self:addChild(self.minBtn)

    -- manual and changelog, same header spot as in the admin window
    self.helpBtn = AegisButton:new(self.width - 44 - 38 * 2, 16, 30, 30, nil, "logs", self, function()
        AegisHelp.toggle("player")
    end)
    self.helpBtn.radius = 15
    self.helpBtn.tooltip = getText("UI_Aegis_Help")
    self:addChild(self.helpBtn)

    -- hints for the page currently open, next to the manual button
    self.pageHelpBtn = AegisButton:new(self.width - 44 - 38 * 3, 16, 30, 30, "?", nil, self, function(win)
        AegisPageHelp.toggle(win, "player")
    end)
    self.pageHelpBtn.radius = 15
    self.pageHelpBtn.tooltip = getText("UI_Aegis_PageHelp")
    self:addChild(self.pageHelpBtn)

    -- bottom right resize grip, the shared class from the admin window
    self.grip = AegisResizeGrip:new(self.width - 22, self.height - 22, 22, 22, self)
    self.grip.anchorRight = false
    self.grip.anchorBottom = false
    self.grip.resizeFunction = AegisPlayerWindow.applyResize
    self.grip.accent = AegisPlayerCol.accent
    self.grip:initialise()
    self:addChild(self.grip)

    -- unobtrusive padlock in the sidebar footer: open = nav entries can
    -- be dragged into a new order, closed = order fixed (admin pattern)
    self.navUnlocked = false
    self.lockBtn = AegisButton:new(SIDEBAR_W - 38, self.height - 50, 26, 26, nil, "lock", self, function(win)
        win.navUnlocked = not win.navUnlocked
        win.navDrag = nil
        win.pressNav = nil
        win.pressEye = nil
    end)
    self.lockBtn.radius = 13
    self.lockBtn.iconSize = 14
    self.lockBtn.tooltip = getText("UI_Aegis_NavReorder")
    -- the shared button only knows the gold style, this one instance
    -- renders itself in the blue palette (open = filled accent)
    local win = self
    self.lockBtn.render = function(btn)
        local pc = AegisPlayerCol
        local bw, bh = btn.width, btn.height
        local r = math.min(btn.radius, math.floor(bh / 2))
        btn.hoverT = Aegis.glide(btn.hoverT, btn.hovered and 1 or 0, 0.35)
        local iconC
        if win.navUnlocked then
            Aegis.roundRect(btn, 0, 0, bw, bh, r, 1, pc.accent)
            if btn.hoverT > 0.01 then
                Aegis.roundRect(btn, 0, 0, bw, bh, r, 0.20 * btn.hoverT, pc.white)
            end
            if btn.pressed then
                Aegis.roundRect(btn, 0, 0, bw, bh, r, 0.22, pc.dark)
            end
            iconC = pc.dark
        else
            Aegis.roundRect(btn, 0, 0, bw, bh, r, 1, pc.line)
            Aegis.roundRect(btn, 1, 1, bw - 2, bh - 2, math.max(1, r - 1), 1, pc.card)
            if btn.hoverT > 0.01 then
                Aegis.roundRect(btn, 1, 1, bw - 2, bh - 2, math.max(1, r - 1), 0.6 * btn.hoverT, pc.cardHi)
            end
            if btn.pressed then
                Aegis.roundRect(btn, 1, 1, bw - 2, bh - 2, math.max(1, r - 1), 0.35, pc.dark)
            end
            iconC = btn.hovered and pc.accent or pc.muted
        end
        Aegis.icon(btn, btn.icon, math.floor((bw - btn.iconSize) / 2), math.floor((bh - btn.iconSize) / 2), btn.iconSize, 1, iconC)
    end
    self:addChild(self.lockBtn)

    -- plus in the footer next to the padlock: brings hidden pages back.
    -- Only shown while the nav is unlocked and something is hidden
    -- (prerender drives the visibility), the menu itself opens deferred
    -- in update, outside the mouse dispatch
    self.navPlusBtn = AegisButton:new(SIDEBAR_W - 38 - 32, self.height - 50, 26, 26, nil, "plus", self, function(win)
        win.menuToggleWanted = true
    end)
    self.navPlusBtn.radius = 13
    self.navPlusBtn.iconSize = 14
    self.navPlusBtn.tooltip = getText("UI_Aegis_NavRestore")
    self.navPlusBtn:setVisible(false)
    -- same blue ghost look as the closed padlock above
    self.navPlusBtn.render = function(btn)
        local pc = AegisPlayerCol
        local bw, bh = btn.width, btn.height
        local r = math.min(btn.radius, math.floor(bh / 2))
        btn.hoverT = Aegis.glide(btn.hoverT, btn.hovered and 1 or 0, 0.35)
        Aegis.roundRect(btn, 0, 0, bw, bh, r, 1, pc.line)
        Aegis.roundRect(btn, 1, 1, bw - 2, bh - 2, math.max(1, r - 1), 1, pc.card)
        if btn.hoverT > 0.01 then
            Aegis.roundRect(btn, 1, 1, bw - 2, bh - 2, math.max(1, r - 1), 0.6 * btn.hoverT, pc.cardHi)
        end
        if btn.pressed then
            Aegis.roundRect(btn, 1, 1, bw - 2, bh - 2, math.max(1, r - 1), 0.35, pc.dark)
        end
        Aegis.icon(btn, btn.icon, math.floor((bw - btn.iconSize) / 2), math.floor((bh - btn.iconSize) / 2), btn.iconSize, 1, btn.hovered and pc.accent or pc.muted)
    end
    self:addChild(self.navPlusBtn)

    -- respect the saved order and the view filter already on open (pass
    -- self, the instance field is only set after addToUIManager)
    local first = AegisPlayerWindow.firstVisiblePage(self)
    if first then
        self:switchPage(first)
    end
end

function AegisPlayerWindow:close()
    AegisPlayerMiniBar.hide()
    self:removeFromUIManager()
    if AegisPlayerWindow.instance == self then
        AegisPlayerWindow.instance = nil
    end
end

-- ---------- resize and collapse, mirrors the admin window ----------

-- collapse hides the whole window behind a small standalone bar; a
-- height collapse fought the resize machinery there and kept coming back
function AegisPlayerWindow:toggleMinimize()
    if self.grip and self.grip.resizing then
        self.grip.resizing = false
        self.grip:setCapture(false)
    end
    self.minimized = true
    self.dragging = false
    self:setVisible(false)
    AegisPlayerMiniBar.show(self)
end

function AegisPlayerWindow:restoreFromMini()
    self.minimized = false
    self:setVisible(true)
    self:bringToTop()
end

-- header buttons and grip do not anchor, move them by hand
function AegisPlayerWindow:placeChrome()
    self.closeBtn:setX(self.width - 44)
    if self.minBtn then self.minBtn:setX(self.width - 44 - 38) end
    if self.helpBtn then self.helpBtn:setX(self.width - 44 - 38 * 2) end
    if self.pageHelpBtn then self.pageHelpBtn:setX(self.width - 44 - 38 * 3) end
    if self.lockBtn then self.lockBtn:setY(self.height - 50) end
    if self.navPlusBtn then self.navPlusBtn:setY(self.height - 50) end
    if self.restoreMenu then
        self.restoreMenu:setY(self.height - 58 - self.restoreMenu.height - 4)
    end
    if self.grip then
        self.grip:setX(self.width - self.grip.width)
        self.grip:setY(self.height - self.grip.height)
    end
end

-- live drag: the page keeps its size and is clipped to the frame, the
-- single real reflow happens on release (rebuilding several times a
-- second never looked smooth in the admin window)
function AegisPlayerWindow:applyResize(w, h)
    local sw, sh = getCore():getScreenWidth(), getCore():getScreenHeight()
    w = math.min(w, sw - EDGE - self.x)
    h = math.min(h, sh - EDGE - self.y)
    w = math.max(w, self.minimumWidth)
    h = math.max(h, self.minimumHeight)
    if w == self.width and h == self.height then return end
    self:setWidth(w)
    self:setHeight(h)
    self:placeChrome()
    -- the page follows the drag by stretching, not by rebuilding
    self:stretchActivePage()
    self.rebuildWanted = true
end

function AegisPlayerWindow:onResizeDone()
    if self.minimized then return end
    if self.width == self.resizeStartW and self.height == self.resizeStartH then return end
    Aegis.setPref("pwinW", math.floor(self.width))
    Aegis.setPref("pwinH", math.floor(self.height))
    self.rebuildWanted = true
end

-- tear the built pages down and rebuild the active one at the new size
function AegisPlayerWindow:rebuildPages()
    local keep = self.activePage
    local state = nil
    local old = keep and self:page(keep)
    if old and old.saveState then
        local ok, res = pcall(function() return old:saveState() end)
        if ok then state = res end
    end
    for _, panel in pairs(self.pagePanels) do
        self:removeChild(panel)
    end
    self.pagePanels = {}
    self.activePage = nil
    if keep then
        self:switchPage(keep)
        local fresh = self:page(keep)
        if state and fresh and fresh.restoreState then
            pcall(function() fresh:restoreState(state) end)
        end
    end
end

function AegisPlayerWindow:contentArea()
    return SIDEBAR_W + 1, HEADER_H + 1, self.width - SIDEBAR_W - 2, self.height - HEADER_H - 2
end

function AegisPlayerWindow:page(id)
    return self.pagePanels[id]
end

-- starting point for the live stretch below
local function recordBaseline(panel)
    panel.baseW = panel.width
    local kids = panel:getChildren()
    if not kids then return end
    for _, child in pairs(kids) do
        child.baseX = child.x
        child.baseW = child.width
    end
end

-- live follow while the grip drags, ported 1:1 from the admin window:
-- rebuilding a page several times a second never looked smooth, so the
-- existing widgets are stretched instead and the pixel exact layout
-- arrives with the single rebuild on release
function AegisPlayerWindow:stretchActivePage()
    local id = self.activePage
    if not id then return end
    local cx, cy, cw, ch = self:contentArea()
    local panel = self:page(id)
    if not panel then return end
    panel:setHeight(ch)
    local baseW = panel.baseW
    if not baseW or baseW <= 0 then return end
    panel:setWidth(cw)
    if panel.colW then panel.colW = math.floor((cw - 60) / 2) end
    local ratio = cw / baseW
    local kids = panel:getChildren()
    if not kids then return end
    for _, child in pairs(kids) do
        if child.baseX then
            child:setX(math.floor(child.baseX * ratio))
            -- small icon buttons would turn into rectangles for the
            -- length of the drag
            if child.baseW and child.baseW > 60 then
                child:setWidth(math.floor(child.baseW * ratio))
            end
        end
    end
end

-- ---------- nav order: user sortable, persisted, lockable ----------

-- registration order overlaid with the saved order; unknown saved ids
-- are dropped, pages missing from the saved order (new features) append
-- in registration order
function AegisPlayerWindow:orderedPages()
    if self.pageOrderCache then return self.pageOrderCache end
    local saved = tostring(Aegis.getPref("navOrderPlayer") or "")
    local byId = {}
    for _, def in ipairs(AegisPlayerWindow.pages) do byId[def.id] = def end
    local out, seen = {}, {}
    for id in saved:gmatch("[^,]+") do
        if byId[id] and not seen[id] then
            table.insert(out, byId[id])
            seen[id] = true
        end
    end
    for _, def in ipairs(AegisPlayerWindow.pages) do
        if not seen[def.id] then table.insert(out, def) end
    end
    self.pageOrderCache = out
    return out
end

function AegisPlayerWindow:saveNavOrder(list)
    local ids = {}
    for _, def in ipairs(list) do table.insert(ids, def.id) end
    Aegis.setPref("navOrderPlayer", table.concat(ids, ","))
    self.pageOrderCache = nil
end

-- ---------- hidden pages: view filter on top of the server flag ----------

-- pref navHiddenPlayer, comma separated page ids; unknown ids are
-- dropped on read so removed pages clean themselves up
function AegisPlayerWindow:hiddenSet()
    if self.navHiddenCache then return self.navHiddenCache end
    local known = {}
    for _, def in ipairs(AegisPlayerWindow.pages) do known[def.id] = true end
    local set = {}
    for id in tostring(Aegis.getPref("navHiddenPlayer") or ""):gmatch("[^,]+") do
        if known[id] then set[id] = true end
    end
    self.navHiddenCache = set
    return set
end

function AegisPlayerWindow:saveHidden(set)
    local ids = {}
    for _, def in ipairs(AegisPlayerWindow.pages) do
        if set[def.id] then table.insert(ids, def.id) end
    end
    Aegis.setPref("navHiddenPlayer", table.concat(ids, ","))
    self.navHiddenCache = nil
end

-- server flag gate plus the view filter; hiding is a look, never a gate
function AegisPlayerWindow:navVisible(def)
    return pageVisible(def.id) and not self:hiddenSet()[def.id]
end

-- hidden pages the user could bring back right now, in nav order
function AegisPlayerWindow:restorablePages()
    local set = self:hiddenSet()
    local out = {}
    for _, def in ipairs(self:orderedPages()) do
        if set[def.id] and pageVisible(def.id) then
            table.insert(out, def)
        end
    end
    return out
end

-- next visible entry after id in nav order, wrapping around
function AegisPlayerWindow:nextVisiblePage(id)
    local pages = self:orderedPages()
    local start = 1
    for i, def in ipairs(pages) do
        if def.id == id then
            start = i
            break
        end
    end
    for off = 1, #pages do
        local def = pages[((start - 1 + off) % #pages) + 1]
        if def.id ~= id and self:navVisible(def) then return def.id end
    end
    return nil
end

-- hide or restore one page; the active page moves to the next visible
-- entry first, and the last visible entry can never be hidden
function AegisPlayerWindow:setPageHidden(id, hide)
    local set = self:hiddenSet()
    if hide then
        if set[id] then return end
        local nxt = self:nextVisiblePage(id)
        if not nxt then return end
        if self.activePage == id then self:switchPage(nxt) end
        set[id] = true
    else
        if not set[id] then return end
        set[id] = nil
    end
    self:saveHidden(set)
end

function AegisPlayerWindow:openRestoreMenu()
    self:closeRestoreMenu()
    local rows = self:restorablePages()
    if #rows == 0 then return end
    local pc = AegisPlayerCol
    -- same cap as the admin panel: the popup stays clear of the header
    local menu = AegisNavRestoreMenu:new(10, 0, SIDEBAR_W - 20, rows, pc, pc.accent,
        (self.height - 58 - 4) - (HEADER_H + 8))
    menu:initialise()
    menu:setY(self.height - 58 - menu.height - 4)
    self:addChild(menu)
    self.restoreMenu = menu
end

function AegisPlayerWindow:closeRestoreMenu()
    if self.restoreMenu then
        self:removeChild(self.restoreMenu)
        self.restoreMenu = nil
    end
end

-- insertion slot in navRects space for the given mouse y
function AegisPlayerWindow:navSlotAt(my)
    for i, rect in ipairs(self.navRects or {}) do
        if my < rect.y + rect.h / 2 then return i end
    end
    return #(self.navRects or {}) + 1
end

-- reinsert the dragged entry at the slot under the mouse and persist.
-- Hidden pages (kits flag or the view filter) keep their relative
-- place: the visible list is reordered, then the hidden entries are
-- woven back at their old indexes
function AegisPlayerWindow:dropNavDrag()
    local dragId = self.navDrag.id
    self.navDrag = nil
    self.pressNav = nil
    local slot = self:navSlotAt(self:getMouseY())
    local visible, hidden = {}, {}
    for idx, def in ipairs(self:orderedPages()) do
        if self:navVisible(def) then
            table.insert(visible, def)
        else
            table.insert(hidden, { idx = idx, def = def })
        end
    end
    local from = nil
    for i, d in ipairs(visible) do
        if d.id == dragId then
            from = i
            break
        end
    end
    if not from then return end
    local def = table.remove(visible, from)
    if slot > from then slot = slot - 1 end
    slot = math.max(1, math.min(slot, #visible + 1))
    table.insert(visible, slot, def)
    for _, e in ipairs(hidden) do
        table.insert(visible, math.min(e.idx, #visible + 1), e.def)
    end
    self:saveNavOrder(visible)
    Aegis.sound()
end

function AegisPlayerWindow:switchPage(id)
    if not pageVisible(id) then return end
    -- hidden is view state, not a gate: direct jumps (hotkeys, cross
    -- page buttons) still open the page and bring it back into the nav
    -- with a short note
    if self:hiddenSet()[id] then
        self:setPageHidden(id, false)
        for _, def in ipairs(AegisPlayerWindow.pages) do
            if def.id == id then
                self.toastText = getText("UI_Aegis_NavUnhidden", getText(def.label))
                self.toastUntil = getTimestampMs() + 2200
                break
            end
        end
    end
    if self.activePage == id then return end
    for pid, panel in pairs(self.pagePanels) do
        panel:setVisible(pid == id)
    end
    if not self.pagePanels[id] then
        for _, def in ipairs(AegisPlayerWindow.pages) do
            if def.id == id then
                local cx, cy, cw, ch = self:contentArea()
                local panel = def.create(self, cx, cy, cw, ch)
                panel:initialise()
                self:addChild(panel)
                self.pagePanels[id] = panel
                -- keep the grip last in the child list: the java mouse
                -- dispatch walks children back to front, the page panel
                -- covers the corner and would swallow the grip otherwise
                if self.grip then
                    self:removeChild(self.grip)
                    self:addChild(self.grip)
                end
                break
            end
        end
    end
    local panel = self.pagePanels[id]
    if panel then
        panel:setVisible(true)
        if panel.onShow then panel:onShow() end
    end
    local inner = self:page(id)
    if inner then recordBaseline(inner) end
    self.activePage = id
end

function AegisPlayerWindow:update()
    ISPanel.update(self)
    -- the reflow after a resize, deferred out of the mouse dispatch and
    -- never while the grip still drags
    if self.rebuildWanted and not self.minimized
        and not (self.grip and self.grip.resizing) then
        self.rebuildWanted = false
        self:rebuildPages()
    end
    -- restore menu bookkeeping, kept out of the mouse dispatch like the
    -- resize rebuild above
    if self.menuToggleWanted then
        self.menuToggleWanted = false
        if self.restoreMenu then
            self:closeRestoreMenu()
        elseif self.navUnlocked then
            self:openRestoreMenu()
        end
    end
    if self.restoreMenu then
        local pick = self.restoreMenu.pickedId
        if pick then
            self.restoreMenu.pickedId = nil
            self:setPageHidden(pick, false)
            Aegis.sound()
            self:closeRestoreMenu()
            -- reopen with the remaining entries so several pages can be
            -- brought back in one go
            if self.navUnlocked and #self:restorablePages() > 0 then
                self:openRestoreMenu()
            end
        elseif not self.navUnlocked or #self:restorablePages() == 0 then
            self:closeRestoreMenu()
        end
    end
    -- a fresh ppSync can drop the panel or the kits flag at any time
    if not AegisPlayerClient.enabled() then
        self:close()
        return
    end
    -- also catches activePage == nil: a rebuild while a ppSync just
    -- revoked the shown page leaves no page loaded at all, the window
    -- would stay empty until reopened. switchPage handles first ==
    -- activePage (the fallback when everything is hidden) by unhiding
    if not self.activePage or not pageVisible(self.activePage)
        or self:hiddenSet()[self.activePage] then
        local first = AegisPlayerWindow.firstVisiblePage()
        if first then
            self:switchPage(first)
        else
            self:close()
        end
    end
end

-- MP safe clock, same route as the admin window (see AegisTheme.lua)
local function timeString()
    local h, m = Aegis.hourMinute(getGameTime())
    return string.format("%02d:%02d", h, m)
end

local function dayString()
    return Aegis.dayAndDate(getGameTime())
end

-- survival rule for the header clock, same scan the engine hud clock runs
-- (zombie.ui.Clock, bytecode): a worn AlarmClock or AlarmClockClothing shows
-- the time, and only the DIGITAL item tag adds the date. No watch, no clock.
-- Checked once a second, the worn list does not change more often
local wornClock = { at = 0, time = false, date = false }

local function clockGear()
    local now = getTimestampMs()
    if now < wornClock.at then return wornClock end
    wornClock.at = now + 1000
    wornClock.time, wornClock.date = false, false
    -- every local player, like the engine clock: in splitscreen one worn
    -- watch shows the time for the shared screen (plain
    -- getPlayer() hits whichever player updated last)
    for n = 0, (getNumActivePlayers() or 1) - 1 do
        local p = getSpecificPlayer(n)
        if p and not p:isDead() then
            local worn = p:getWornItems()
            for i = 0, worn:size() - 1 do
                local it = worn:getItemByIndex(i)
                if it and (instanceof(it, "AlarmClock") or instanceof(it, "AlarmClockClothing")) then
                    wornClock.time = true
                    -- hasTag needs the ItemTag OBJECT, a raw string throws
                    if it:hasTag(ItemTag.DIGITAL) then wornClock.date = true end
                end
            end
        end
    end
    return wornClock
end

function AegisPlayerWindow:prerender()
    local c = AegisPlayerCol
    local w, h = self.width, self.height
    -- while the grip drags the page still has its old size, clip every
    -- child to the frame so nothing spills onto the world
    self.clipping = self.grip ~= nil and self.grip.resizing == true

    self.anim = Aegis.glide(self.anim, 1, 0.2)
    if not self.dragging then
        self:setY(self.baseY + (1 - self.anim) * 16)
    end

    Aegis.shadow(self, 0, 0, w, h, 34, 0.55)
    Aegis.roundFrame(self, 0, 0, w, h, 14, 1, c.line, c.bg)

    -- header
    local grad = Aegis.tex("grad_v")
    if grad then
        self:drawTextureScaled(grad, 1, 1, w - 2, 44, 0.05, c.accent.r, c.accent.g, c.accent.b)
    end
    local hud = Aegis.tex("hud_player")
    if hud then
        self:drawTextureScaled(hud, 20, 13, 38, 38, 1, 1, 1, 1)
    end
    -- operator brand instead of the fixed AEGIS; capped so a long name
    -- stays clear of the clock on the right (admin head pattern)
    local title = Aegis.fitText(AegisBrand.title(), UIFont.Large, math.floor(w * 0.4) - 70)
    Aegis.text(self, title, 70, 12, UIFont.Large, c.accentHi)
    if not self.subtitle then
        self.subtitle = getText("UI_AegisPlayer_Subtitle"):gsub("(.)", "%1 "):gsub(" $", "")
    end
    Aegis.text(self, self.subtitle, 71, 12 + Aegis.fontH(UIFont.Large), UIFont.Small, c.muted)

    -- left of the THREE header buttons (help, minimize, close), same
    -- guard the admin window uses (the old two
    -- button offset ran the clock straight into the help button)
    local clockX = w - 44 - 38 * 3 - 14
    local gear = clockGear()
    if gear.time then
        Aegis.textRight(self, timeString(), clockX, 12, UIFont.Large, c.text)
        if gear.date then
            Aegis.textRight(self, dayString(), clockX, 12 + Aegis.fontH(UIFont.Large), UIFont.Small, c.muted)
        end
    end
    Aegis.hairline(self, 1, HEADER_H, w - 2)

    -- sidebar
    self:drawRect(1, HEADER_H + 1, SIDEBAR_W, h - HEADER_H - 14, 1, c.panel.r, c.panel.g, c.panel.b)
    self:drawRect(1, h - 14, SIDEBAR_W, 13, 1, c.panel.r, c.panel.g, c.panel.b)
    Aegis.roundRect(self, 1, h - 15, SIDEBAR_W, 14, 13, 1, c.panel)
    self:drawRect(SIDEBAR_W, HEADER_H + 1, 1, h - HEADER_H - 2, 1, c.line.r, c.line.g, c.line.b)

    local ny = HEADER_H + 16
    local activeY = nil
    self.navRects = {}

    local pages = self:orderedPages()

    -- on tight window height the entries pack closer instead of running into the footer
    local visibleCount = 0
    for _, def in ipairs(pages) do
        if self:navVisible(def) then visibleCount = visibleCount + 1 end
    end
    local navH, navGap = NAV_H, 6
    local space = (h - 58 - 8) - ny
    if visibleCount > 0 and visibleCount * (navH + navGap) > space then
        local perEntry = math.max(26, math.floor(space / visibleCount))
        navGap = math.max(2, math.min(6, perEntry - 30))
        navH = perEntry - navGap
    end

    -- hide eyes only while the padlock is open, never during a drag and
    -- never on the last visible entry
    self.eyeRects = {}
    local showEyes = self.navUnlocked and not self.navDrag and visibleCount > 1

    for i, def in ipairs(pages) do
        if self:navVisible(def) then
            local nx, nw = 10, SIDEBAR_W - 20
            local draggingNav = self.navDrag and self.navDrag.id == def.id
            local hovered = self:isMouseOver() and self:getMouseX() >= nx and self:getMouseX() <= nx + nw
                and self:getMouseY() >= ny and self:getMouseY() <= ny + navH
            self.navHoverT[i] = Aegis.glide(self.navHoverT[i] or 0, hovered and 1 or 0, 0.3)
            local active = self.activePage == def.id
            if active then activeY = ny end

            if active then
                Aegis.roundRect(self, nx, ny, nw, navH, 8, draggingNav and 0.4 or 1, c.card)
            elseif self.navHoverT[i] > 0.01 then
                Aegis.roundRect(self, nx, ny, nw, navH, 8, 0.6 * self.navHoverT[i], c.card)
            end
            local a = draggingNav and 0.35 or 1
            local ic = active and c.accent or c.muted
            local tc = active and c.text or c.muted
            Aegis.icon(self, def.icon, nx + 12, ny + math.floor((navH - 18) / 2), 18, a, ic)
            local label = getText(def.label)
            if showEyes then label = Aegis.fitText(label, UIFont.Medium, nw - 42 - 28) end
            Aegis.text(self, label, nx + 42, ny + math.floor((navH - Aegis.fontH(UIFont.Medium)) / 2), UIFont.Medium, tc, a)

            if showEyes then
                local ex = nx + nw - 24
                local ey = ny + math.floor((navH - 16) / 2)
                local mx, myy = self:getMouseX(), self:getMouseY()
                local overEye = self:isMouseOver() and mx >= ex - 4 and mx <= ex + 20
                    and myy >= ny and myy <= ny + navH
                Aegis.icon(self, "eye", ex, ey, 16, overEye and 1 or 0.55, overEye and c.accent or c.muted)
                table.insert(self.eyeRects, { x = ex - 4, y = ny, w = 24, h = navH, id = def.id })
            end

            table.insert(self.navRects, { x = nx, y = ny, w = nw, h = navH, id = def.id })
            ny = ny + navH + navGap
        end
    end
    self.navH = navH

    -- drag preview: accent insertion line at the slot under the mouse
    -- plus the dragged label riding along with the cursor
    if self.navDrag then
        local slot = self:navSlotAt(self:getMouseY())
        local lineY
        if slot > #self.navRects then
            local last = self.navRects[#self.navRects]
            lineY = last and (last.y + last.h + 2) or ny
        else
            lineY = self.navRects[slot].y - math.floor(navGap / 2) - 1
        end
        self:drawRect(10, lineY, SIDEBAR_W - 20, 2, 1, c.accent.r, c.accent.g, c.accent.b)
        for _, def in ipairs(pages) do
            if def.id == self.navDrag.id then
                local my = self:getMouseY() - math.floor(navH / 2)
                Aegis.roundRect(self, 14, my, SIDEBAR_W - 28, navH, 8, 0.92, c.card)
                Aegis.icon(self, def.icon, 26, my + math.floor((navH - 18) / 2), 18, 1, c.accent)
                Aegis.text(self, getText(def.label), 56, my + math.floor((navH - Aegis.fontH(UIFont.Medium)) / 2), UIFont.Medium, c.text)
                break
            end
        end
    end

    -- gliding accent marker next to the active entry
    if activeY then
        if self.indicatorY < 0 then self.indicatorY = activeY end
        self.indicatorY = Aegis.glide(self.indicatorY, activeY, 0.3)
        Aegis.roundRect(self, 4, self.indicatorY + 9, 3, navH - 18, 1, 1, c.accent)
    end

    -- sidebar footer: assigned role in its color plus version
    local fy = h - 58
    Aegis.hairline(self, 12, fy, SIDEBAR_W - 24, 0.7)
    local s = AegisPlayerClient.state
    local roleC = (s and s.color) or c.accent
    Aegis.icon(self, "players", 14, fy + 12, 14, 1, roleC)
    -- the plus only shows while unlocked and something is hidden
    local showPlus = self.navUnlocked and #self:restorablePages() > 0
    if self.navPlusBtn and self.navPlusBtn:isVisible() ~= showPlus then
        self.navPlusBtn:setVisible(showPlus)
    end
    -- the padlock (and the plus when shown) sit at the right footer
    -- edge, long role names must not run underneath them
    local roleW = SIDEBAR_W - 38 - 36 - 6
    if showPlus then roleW = roleW - 32 end
    -- without an assigned role the default panel shows a neutral label
    local roleText = (s and s.role) or getText("UI_AegisPlayer_RoleDefault")
    Aegis.text(self, Aegis.fitText(roleText, UIFont.Small, roleW), 36, fy + 10, UIFont.Small, (s and s.color) or c.text)
    Aegis.text(self, "v" .. AegisPlayerWindow.version, 36, fy + 12 + Aegis.fontH(UIFont.Small), UIFont.Small, c.muted)

    -- last thing before the children draw: the clip for the drag
    if self.clipping then
        self:setStencilRect(1, HEADER_H + 1, w - 2, h - HEADER_H - 2)
    end
end

-- short blue confirmation in the header, counterpart of Aegis.showToast
-- which is hard wired to the admin window
function AegisPlayerWindow.toast(text)
    local win = AegisPlayerWindow.instance
    if win and win:isVisible() then
        win.toastText = text
        win.toastUntil = getTimestampMs() + 2200
    end
end

function AegisPlayerWindow:render()
    if self.clipping then
        self:clearStencilRect()
        self.clipping = false
        -- the grip sits in the clipped corner, redraw it on top
        if self.grip then
            local c = AegisPlayerCol
            for row = 0, 2 do
                for i = 0, row do
                    self:drawRect(self.width - 7 - i * 5, self.height - 7 - (2 - row) * 5,
                        2, 2, 0.9, c.accent.r, c.accent.g, c.accent.b)
                end
            end
        end
    end
    if self.toastText and getTimestampMs() < (self.toastUntil or 0) then
        local c = AegisPlayerCol
        local remaining = self.toastUntil - getTimestampMs()
        local a = math.min(1, remaining / 400)
        local w = Aegis.strW(UIFont.Medium, self.toastText) + 32
        local x = math.floor((self.width - w) / 2)
        local y = math.floor((HEADER_H - 34) / 2)
        Aegis.roundFrame(self, x, y, w, 34, 17, a, c.accent, c.dark)
        Aegis.textCentre(self, self.toastText, x + math.floor(w / 2), y + 9, UIFont.Medium, c.accentHi, a)
    else
        self.toastText = nil
    end
end

function AegisPlayerWindow:onMouseDown(x, y)
    self:bringToTop()
    -- a click on the window body closes the restore menu (the menu and
    -- the buttons swallow their own clicks before this runs)
    if self.restoreMenu then self.menuToggleWanted = true end
    if y <= HEADER_H then
        self.dragging = true
        return
    end
    -- with the padlock open a press on a nav entry may become a drag,
    -- the decision falls in onMouseMove (a plain click still switches)
    if self.navUnlocked and x < SIDEBAR_W then
        -- the eye boxes sit inside the nav entries, check them first so
        -- a press on an eye never starts a drag or a page switch
        for _, rect in ipairs(self.eyeRects or {}) do
            if x >= rect.x and x <= rect.x + rect.w and y >= rect.y and y <= rect.y + rect.h then
                self.pressEye = rect.id
                return
            end
        end
        for _, rect in ipairs(self.navRects) do
            if x >= rect.x and x <= rect.x + rect.w and y >= rect.y and y <= rect.y + rect.h then
                self.pressNav = { id = rect.id, y = y }
                return
            end
        end
    end
end

function AegisPlayerWindow:onMouseMove(dx, dy)
    if self.dragging then
        self:setX(self.x + dx)
        self:setY(self.y + dy)
        self.baseY = self.y
        return
    end
    if self.pressNav and not self.navDrag
        and math.abs(self:getMouseY() - self.pressNav.y) > 5 then
        self.navDrag = { id = self.pressNav.id }
    end
end

function AegisPlayerWindow:onMouseMoveOutside(dx, dy)
    self:onMouseMove(dx, dy)
end

function AegisPlayerWindow:onMouseUp(x, y)
    if self.dragging then
        self.dragging = false
        return
    end
    if self.navDrag then
        self:dropNavDrag()
        return
    end
    -- eye released over the pressed entry hides the page
    if self.pressEye then
        local id = self.pressEye
        self.pressEye = nil
        for _, rect in ipairs(self.eyeRects or {}) do
            if rect.id == id and x >= rect.x and x <= rect.x + rect.w
                and y >= rect.y and y <= rect.y + rect.h then
                self:setPageHidden(id, true)
                Aegis.sound()
                break
            end
        end
        return
    end
    self.pressNav = nil
    for _, rect in ipairs(self.navRects) do
        if x >= rect.x and x <= rect.x + rect.w and y >= rect.y and y <= rect.y + rect.h then
            Aegis.sound()
            self:switchPage(rect.id)
            return
        end
    end
end

function AegisPlayerWindow:onMouseUpOutside(x, y)
    self.dragging = false
    if self.navDrag then
        self:dropNavDrag()
        return
    end
    self.pressNav = nil
    self.pressEye = nil
end

-- ==================================================================
-- AegisPlayerMiniBar: the collapsed player panel, blue counterpart of
-- the admin mini bar. Draggable, restores where it sits
-- ==================================================================
AegisPlayerMiniBar = ISPanel:derive("AegisPlayerMiniBar")
AegisPlayerMiniBar.instance = nil

local MINI_W, MINI_H = 250, 46

function AegisPlayerMiniBar.show(window)
    AegisPlayerMiniBar.hide()
    local sw, sh = getCore():getScreenWidth(), getCore():getScreenHeight()
    local x = math.max(0, math.min(window.x, sw - MINI_W))
    local y = math.max(0, math.min(window.y, sh - MINI_H))
    local o = ISPanel:new(x, y, MINI_W, MINI_H)
    setmetatable(o, AegisPlayerMiniBar)
    AegisPlayerMiniBar.__index = AegisPlayerMiniBar
    o.background = false
    o.window = window
    o:initialise()
    o:addToUIManager()
    o:setAlwaysOnTop(true)

    o.plusBtn = AegisButton:new(MINI_W - 74, 8, 30, 30, nil, "plus", o, AegisPlayerMiniBar.restore)
    o.plusBtn.radius = 15
    o:addChild(o.plusBtn)
    o.closeBtn = AegisButton:new(MINI_W - 38, 8, 30, 30, nil, "close", o, function(bar)
        local win = bar.window
        AegisPlayerMiniBar.hide()
        if win then win:close() end
    end)
    o.closeBtn.radius = 15
    o:addChild(o.closeBtn)
    AegisPlayerMiniBar.instance = o
    return o
end

function AegisPlayerMiniBar.hide()
    if AegisPlayerMiniBar.instance then
        AegisPlayerMiniBar.instance:removeFromUIManager()
        AegisPlayerMiniBar.instance = nil
    end
end

function AegisPlayerMiniBar:restore()
    local win = self.window
    AegisPlayerMiniBar.hide()
    if win then
        -- the window follows the bar if it was dragged elsewhere
        win:setX(self.x)
        win:setY(self.y)
        win.baseY = self.y
        win:restoreFromMini()
    end
end

function AegisPlayerMiniBar:prerender()
    local c = AegisPlayerCol
    Aegis.shadow(self, 0, 0, self.width, self.height, 18, 0.5)
    Aegis.roundFrame(self, 0, 0, self.width, self.height, 12, 1, c.line, c.bg)
    local hud = Aegis.tex("hud_player")
    if hud then
        self:drawTextureScaled(hud, 10, 9, 28, 28, 1, 1, 1, 1)
    end
    Aegis.text(self, "AEGIS", 46, 12, UIFont.Medium, c.accentHi)
end

function AegisPlayerMiniBar:onMouseDown(x, y)
    self:bringToTop()
    self.dragging = true
end

function AegisPlayerMiniBar:onMouseMove(dx, dy)
    if not self.dragging then return end
    self:setX(self.x + dx)
    self:setY(self.y + dy)
end

function AegisPlayerMiniBar:onMouseMoveOutside(dx, dy)
    self:onMouseMove(dx, dy)
end

function AegisPlayerMiniBar:onMouseUp(x, y)
    self.dragging = false
end

function AegisPlayerMiniBar:onMouseUpOutside(x, y)
    self.dragging = false
end
