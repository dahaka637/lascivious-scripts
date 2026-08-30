-- Main window of the suite: header, sidebar, page host
require "ISUI/ISPanel"
require "ISUI/ISResizeWidget"
require "Aegis/AegisTheme"
require "Aegis/AegisWidgets"
require "Aegis/AegisHelp"
require "Aegis/AegisPageHelp"
require "Aegis/AegisBrand"

AegisWindow = ISPanel:derive("AegisWindow")
AegisWindow.instance = nil
AegisWindow.pages = {}

local HEADER_H = 64
local SIDEBAR_W = 188
local NAV_H = 40
-- screen margin the window may never grow past
local EDGE = 12
-- resize floor, deliberately below the old default size;
-- the nav already packs itself on tight heights
local MIN_W = 860
local MIN_H = 560
-- free corner under a scroll host: its scrollbar used to run into the
-- resize grip, both wanted the same pixels
local GRIP_CHIN = 26
-- Pages report the height their layout really needs via self.designH
-- (only the two with a purely fixed layout do, World and Server). Those
-- get a clipped scroll host when the window is shorter. Every other page
-- either scrolls internally already or lays out from self.height, and
-- wrapping those produced two scrollbars on top of each other

-- if rightsReq or the rightsSync reply gets lost, re-request at most
-- every 3s and at most 5 times instead of leaving the panel empty for
-- the rest of the session
local RIGHTS_RETRY_MS = 3000
local RIGHTS_RETRY_MAX = 5

-- pages register here: { id, icon, label (translation key), create(window) }
-- optional def.area: rights area the page is gated by when it differs from
-- the page id. Lets a page ride on an existing area (the options page uses
-- "server") so existing roles keep working without a new area entry
function AegisWindow.registerPage(def)
    table.insert(AegisWindow.pages, def)
end

-- rights area for a page id, def.area wins over the id itself
function AegisWindow.pageArea(id)
    for _, def in ipairs(AegisWindow.pages) do
        if def.id == id then return def.area or def.id end
    end
    return id
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

function AegisWindow.toggle()
    -- during vehicle placement, zone editor or clearing the window is only hidden
    if AegisVehiclePlacer and AegisVehiclePlacer.instance then
        AegisVehiclePlacer.instance:finish()
        return
    end
    if AegisZoneEditor and AegisZoneEditor.instance then
        AegisZoneEditor.instance:finish()
        return
    end
    if AegisClearingEditor and AegisClearingEditor.instance then
        AegisClearingEditor.instance:finish()
        return
    end
    if AegisWindow.instance then
        -- the key minimizes instead of closing: page, lists and selection
        -- are kept, pressing again shows exactly the same state
        local o = AegisWindow.instance
        -- collapsed to the mini bar: the hotkey brings the full panel back
        if AegisMiniBar.instance then
            AegisMiniBar.instance:restore()
            sendClientCommand(getPlayer(), AegisShared.MODULE, "panelSession", { open = true })
            return
        end
        local show = not o:isVisible()
        o:setVisible(show)
        if show then
            o:bringToTop()
        else
            o.dragging = false
        end
        sendClientCommand(getPlayer(), AegisShared.MODULE, "panelSession", { open = show })
        if show then openNotices("admin") end
        return
    end
    Aegis.ensureSoloRole()
    local sw, sh = getCore():getScreenWidth(), getCore():getScreenHeight()
    -- restore the persisted size, clamped between the floor and the
    -- current screen minus a small edge
    local defW = math.min(1150, sw - 40)
    local defH = math.min(720, sh - 40)
    local w = math.max(math.min(MIN_W, sw - 40), math.min(tonumber(Aegis.getPref("winW")) or defW, sw - EDGE * 2))
    local h = math.max(math.min(MIN_H, sh - 40), math.min(tonumber(Aegis.getPref("winH")) or defH, sh - EDGE * 2))
    local o = AegisWindow:new(math.floor((sw - w) / 2), math.floor((sh - h) / 2), w, h)
    o:initialise()
    o:addToUIManager()
    AegisWindow.instance = o
    if isClient() then
        sendClientCommand(getPlayer(), AegisShared.MODULE, "rightsReq", {})
        o.rightsWaitingSince = getTimestampMs()
        o.rightsRetries = 0
    end
    -- session log also in solo, the loopback fires in-process
    sendClientCommand(getPlayer(), AegisShared.MODULE, "panelSession", { open = true })
    openNotices("admin")
end

function AegisWindow:new(x, y, w, h)
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
    o.minimumWidth = math.min(MIN_W, getCore():getScreenWidth() - 40)
    o.minimumHeight = math.min(MIN_H, getCore():getScreenHeight() - 40)
    return o
end

function AegisWindow:createChildren()
    self.closeBtn = AegisButton:new(self.width - 44, 16, 30, 30, nil, "close", self, AegisWindow.close)
    self.closeBtn.radius = 15
    self:addChild(self.closeBtn)

    -- collapse to the header bar (same behaviour as the vehicle detail
    -- panel): pages are only hidden, never rebuilt, so the active page,
    -- lists and selections come back exactly as left
    self.minBtn = AegisButton:new(self.width - 44 - 38, 16, 30, 30, nil, "minus", self, AegisWindow.toggleMinimize)
    self.minBtn.radius = 15
    self:addChild(self.minBtn)

    -- manual and changelog, reachable any time
    self.helpBtn = AegisButton:new(self.width - 44 - 38 * 2, 16, 30, 30, nil, "logs", self, function()
        AegisHelp.toggle()
    end)
    self.helpBtn.radius = 15
    self.helpBtn.tooltip = getText("UI_Aegis_Help")
    self:addChild(self.helpBtn)

    -- hints for the page currently open, next to the manual button
    self.pageHelpBtn = AegisButton:new(self.width - 44 - 38 * 3, 16, 30, 30, "?", nil, self, function(win)
        AegisPageHelp.toggle(win, "admin")
    end)
    self.pageHelpBtn.radius = 15
    self.pageHelpBtn.tooltip = getText("UI_Aegis_PageHelp")
    self:addChild(self.pageHelpBtn)

    -- unobtrusive padlock in the sidebar footer: open = nav entries can
    -- be dragged into a new order, closed = order fixed
    self.navUnlocked = false
    self.lockBtn = AegisButton:new(SIDEBAR_W - 38, self.height - 50, 26, 26, nil, "lock", self, function(win)
        win.navUnlocked = not win.navUnlocked
        win.lockBtn.style = win.navUnlocked and "gold" or "ghost"
        win.navDrag = nil
        win.pressNav = nil
        win.pressEye = nil
    end)
    self.lockBtn.radius = 13
    self.lockBtn.iconSize = 14
    self.lockBtn.tooltip = getText("UI_Aegis_NavReorder")
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
    self:addChild(self.navPlusBtn)

    -- bottom right resize grip: live setWidth/setHeight while dragging,
    -- full page rebuild on release (onResizeDone)
    self.grip = AegisResizeGrip:new(self.width - 22, self.height - 22, 22, 22, self)
    self.grip.anchorRight = false
    self.grip.anchorBottom = false
    self.grip.resizeFunction = AegisWindow.applyResize
    self.grip:initialise()
    self:addChild(self.grip)

    -- pass self, the instance field is only set after addToUIManager
    local first = AegisWindow.firstVisiblePage(self)
    if first then
        self:switchPage(first)
    end
end

function AegisWindow:close()
    AegisMiniBar.hide()
    self:removeFromUIManager()
    AegisWindow.instance = nil
    sendClientCommand(getPlayer(), AegisShared.MODULE, "panelSession", { open = false })
end

-- collapse = hide the whole window behind a small standalone bar. The
-- old height collapse fought the resize machinery and kept resurfacing
-- a full size empty body; with the window simply
-- hidden there is no height state left that anything could corrupt
function AegisWindow:toggleMinimize()
    if self.grip and self.grip.resizing then
        self.grip.resizing = false
        self.grip:setCapture(false)
    end
    self.minimized = true
    self.dragging = false
    self:setVisible(false)
    AegisMiniBar.show(self)
end

function AegisWindow:restoreFromMini()
    self.minimized = false
    self:setVisible(true)
    self:bringToTop()
end

-- live resize while the grip drags: the window keeps its position, the
-- size clamps between the floor and the screen minus a small edge.
-- The page rebuild itself is only FLAGGED here: mouse handlers must not
-- restructure the child list mid dispatch (a rebuild
-- inside the grip's own mouse path corrupted the minimize behaviour),
-- update() picks the flag up on the next tick
function AegisWindow:applyResize(w, h)
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

-- header buttons and grip do not anchor (ISPanel default), move them by hand
function AegisWindow:placeChrome()
    self.closeBtn:setX(self.width - 44)
    self.minBtn:setX(self.width - 44 - 38)
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

-- grip released: only flag the final rebuild and persist, the actual
-- restructuring runs in update() outside the mouse dispatch
function AegisWindow:onResizeDone()
    if self.minimized then return end
    if self.width == self.resizeStartW and self.height == self.resizeStartH then return end
    Aegis.setPref("winW", math.floor(self.width))
    Aegis.setPref("winH", math.floor(self.height))
    self.rebuildWanted = true
end

-- tear down all built pages and rebuild the active one at the current
-- content size. Safe because each create resets its .instance, server
-- replies route to the fresh panels
function AegisWindow:rebuildPages()
    local keep = self.activePage
    -- EVERY page that carries state hands it over, not only the active
    -- one: pending edits on a background page died in a resize otherwise
    --. switchPage restores lazily when a page comes back
    self.pendingStates = {}
    for id in pairs(self.pagePanels) do
        local inner = self:page(id)
        if inner and inner.saveState then
            local ok, res = pcall(function() return inner:saveState() end)
            if ok and res then self.pendingStates[id] = res end
        end
    end
    for _, panel in pairs(self.pagePanels) do
        self:removeChild(panel)
    end
    self.pagePanels = {}
    self.pageInner = {}
    self.activePage = nil
    if keep then
        self:switchPage(keep)
    end
end

-- ---------- nav order: user sortable, persisted, lockable ----------

-- registration order overlaid with the saved order; unknown saved ids
-- are dropped, pages missing from the saved order (new features) append
-- in registration order
function AegisWindow:orderedPages()
    if self.pageOrderCache then return self.pageOrderCache end
    local saved = tostring(Aegis.getPref("navOrder") or "")
    local byId = {}
    for _, def in ipairs(AegisWindow.pages) do byId[def.id] = def end
    local out, seen = {}, {}
    for id in saved:gmatch("[^,]+") do
        if byId[id] and not seen[id] then
            table.insert(out, byId[id])
            seen[id] = true
        end
    end
    for _, def in ipairs(AegisWindow.pages) do
        if not seen[def.id] then table.insert(out, def) end
    end
    self.pageOrderCache = out
    return out
end

function AegisWindow:saveNavOrder(list)
    local ids = {}
    for _, def in ipairs(list) do table.insert(ids, def.id) end
    Aegis.setPref("navOrder", table.concat(ids, ","))
    self.pageOrderCache = nil
end

-- ---------- hidden pages: per admin view filter on top of rights ----------

-- pref navHidden, comma separated page ids; unknown ids are dropped on
-- read so removed pages clean themselves up
function AegisWindow:hiddenSet()
    if self.navHiddenCache then return self.navHiddenCache end
    local known = {}
    for _, def in ipairs(AegisWindow.pages) do known[def.id] = true end
    local set = {}
    for id in tostring(Aegis.getPref("navHidden") or ""):gmatch("[^,]+") do
        if known[id] then set[id] = true end
    end
    self.navHiddenCache = set
    return set
end

function AegisWindow:saveHidden(set)
    local ids = {}
    for _, def in ipairs(AegisWindow.pages) do
        if set[def.id] then table.insert(ids, def.id) end
    end
    Aegis.setPref("navHidden", table.concat(ids, ","))
    self.navHiddenCache = nil
end

-- rights gate plus the view filter; hiding is a look, never a permission
function AegisWindow:navVisible(def)
    return Aegis.canSee(def.area or def.id) and not self:hiddenSet()[def.id]
end

-- hidden pages the user could bring back right now, in nav order
function AegisWindow:restorablePages()
    local set = self:hiddenSet()
    local out = {}
    for _, def in ipairs(self:orderedPages()) do
        if set[def.id] and Aegis.canSee(def.area or def.id) then
            table.insert(out, def)
        end
    end
    return out
end

-- next visible entry after id in nav order, wrapping around
function AegisWindow:nextVisiblePage(id)
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
function AegisWindow:setPageHidden(id, hide)
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

function AegisWindow:openRestoreMenu()
    self:closeRestoreMenu()
    local rows = self:restorablePages()
    if #rows == 0 then return end
    local c = Aegis.col
    -- the menu may never grow into the header: with a lot of hidden
    -- pages on a short window it used to start above the window edge
    --, so its height is capped and it scrolls instead
    local menu = AegisNavRestoreMenu:new(10, 0, SIDEBAR_W - 20, rows, c, c.gold,
        (self.height - 58 - 4) - (HEADER_H + 8))
    menu:initialise()
    menu:setY(self.height - 58 - menu.height - 4)
    self:addChild(menu)
    self.restoreMenu = menu
end

function AegisWindow:closeRestoreMenu()
    if self.restoreMenu then
        self:removeChild(self.restoreMenu)
        self.restoreMenu = nil
    end
end

-- insertion slot in navRects space for the given mouse y
function AegisWindow:navSlotAt(my)
    for i, rect in ipairs(self.navRects or {}) do
        if my < rect.y + rect.h / 2 then return i end
    end
    return #(self.navRects or {}) + 1
end

-- id of the entry a drop should land in front of, nil means the end.
-- navRects only holds the entries currently inside the strip, so a slot
-- NUMBER would not line up with the full visible list once it scrolls
function AegisWindow:navDropBefore(my)
    for _, rect in ipairs(self.navRects or {}) do
        if my < rect.y + rect.h / 2 then return rect.id end
    end
    return nil
end

-- first page the user may see according to Aegis rights and the view
-- filter; the win argument lets createChildren use itself before the
-- instance field is set
function AegisWindow.firstVisiblePage(win)
    win = win or AegisWindow.instance
    local pages = win and win:orderedPages() or AegisWindow.pages
    for _, def in ipairs(pages) do
        if win and win:navVisible(def) or (not win and Aegis.canSee(def.area or def.id)) then
            return def.id
        end
    end
    -- every allowed page is hidden away: fall back to the first allowed
    -- one, switchPage brings it back into the nav with a note
    for _, def in ipairs(pages) do
        if Aegis.canSee(def.area or def.id) then return def.id end
    end
    return nil
end

function AegisWindow:contentArea()
    return SIDEBAR_W + 1, HEADER_H + 1, self.width - SIDEBAR_W - 1, self.height - HEADER_H - 1
end

-- the actual page panel, unwrapped: pages with a fixed layout sit in a
-- scroll host, then pagePanels holds the host and not the page itself
function AegisWindow:page(id)
    return self.pageInner and self.pageInner[id] or self.pagePanels[id]
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

-- live follow while the grip drags. Rebuilding a page several times a
-- second never looked smooth, so the
-- existing widgets are stretched instead: every Aegis page lays out in
-- two equal columns derived from the page width, so scaling child x and
-- width by the width ratio reproduces that layout closely, and the page
-- draws its own cards from colW which is refreshed here. Costs nothing
-- per frame, no allocation. The pixel exact layout arrives with the
-- single rebuild on release
function AegisWindow:stretchActivePage()
    local id = self.activePage
    if not id then return end
    local cx, cy, cw, ch = self:contentArea()
    local host = self.pagePanels[id]
    local panel = self:page(id)
    if not panel then return end
    local targetW = cw
    if host and host ~= panel then
        host:setWidth(cw)
        host:setHeight(ch - GRIP_CHIN)
        targetW = cw - 16
    else
        panel:setHeight(ch)
    end
    local baseW = panel.baseW
    if not baseW or baseW <= 0 then return end
    panel:setWidth(targetW)
    -- same column formula the pages use in their create
    if panel.colW then panel.colW = math.floor((targetW - 60) / 2) end
    local ratio = targetW / baseW
    local kids = panel:getChildren()
    if not kids then return end
    for _, child in pairs(kids) do
        if child.baseX then
            child:setX(math.floor(child.baseX * ratio))
            -- only stretch real layout elements; small icon buttons would
            -- turn into rectangles for the length of the drag
            if child.baseW and child.baseW > 60 then
                child:setWidth(math.floor(child.baseW * ratio))
            end
        end
    end
end

function AegisWindow:switchPage(id)
    if not Aegis.canSee(AegisWindow.pageArea(id)) then return end
    -- hidden is view state, not a permission: direct jumps (hotkeys,
    -- cross page buttons) still open the page and bring it back into
    -- the nav with a short note
    if self:hiddenSet()[id] then
        self:setPageHidden(id, false)
        for _, def in ipairs(AegisWindow.pages) do
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
        for _, def in ipairs(AegisWindow.pages) do
            if def.id == id then
                local cx, cy, cw, ch = self:contentArea()
                local host = nil
                local panel = nil
                -- the needed height is remembered from the first build, so
                -- resizing does not construct every fixed page twice per
                -- rebuild tick
                local need = tonumber(def.designH)
                if not need or need <= ch then
                    panel = def.create(self, cx, cy, cw, ch)
                    panel:initialise()
                    -- createChildren runs in instantiate, NOT in
                    -- initialise (vanilla ISUIElement); without this the
                    -- page reports its designH only after addChild and
                    -- the check below always came up empty
                    panel:instantiate()
                    need = tonumber(panel.designH)
                    def.designH = need
                end
                if need and need > ch then
                    -- fixed layout taller than the window: build it at its
                    -- own height inside a clipped scroll host so nothing
                    -- draws outside the frame; the chin keeps the resize
                    -- grip corner free of the scrollbar
                    host = AegisScrollArea:new(cx, cy, cw, ch - GRIP_CHIN)
                    panel = def.create(self, 0, 0, cw - 16, need)
                    panel:initialise()
                    host:addChild(panel)
                    host:setScrollHeight(need)
                    host.inner = panel
                    host.onShow = function(hostPanel)
                        if hostPanel.inner and hostPanel.inner.onShow then hostPanel.inner:onShow() end
                    end
                    self:addChild(host)
                else
                    self:addChild(panel)
                end
                self.pagePanels[id] = host or panel
                self.pageInner = self.pageInner or {}
                self.pageInner[id] = panel
                -- state saved by rebuildPages comes back the moment the
                -- page is rebuilt, active or not
                local pending = self.pendingStates and self.pendingStates[id]
                if pending and panel.restoreState then
                    self.pendingStates[id] = nil
                    pcall(function() panel:restoreState(pending) end)
                end
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
    -- a jump from a card or a hotkey may land on an entry the strip has
    -- scrolled away, prerender pulls it back into view once
    self.navRevealWanted = true
end

function AegisWindow:update()
    ISPanel.update(self)
    -- the reflow after a resize: deferred out of the mouse dispatch and
    -- never while the grip still drags (rebuilding mid drag is what made
    -- it look choppy)
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
    if not Aegis.allowed(getPlayer()) then
        if AegisVehiclePlacer and AegisVehiclePlacer.instance then
            AegisVehiclePlacer.instance:finish()
        end
        if AegisZoneEditor and AegisZoneEditor.instance then
            AegisZoneEditor.instance:finish()
        end
        if AegisClearingEditor and AegisClearingEditor.instance then
            AegisClearingEditor.instance:finish()
        end
        self:close()
        return
    end
    -- revoked rights or a freshly hidden entry push the active page back
    -- to the first visible one (switchPage handles the fallback case of
    -- everything hidden by just unhiding the target)
    if self.activePage and (not Aegis.canSee(AegisWindow.pageArea(self.activePage))
        or self:hiddenSet()[self.activePage]) then
        local first = AegisWindow.firstVisiblePage()
        if first then
            self:switchPage(first)
        else
            self:close()
        end
        return
    end
    -- on open the rightsSync reply was not in yet, canSee rejected every
    -- area and no page got loaded (fail-closed, see Aegis.canSee); once
    -- the real rights arrive, catch up here once instead of leaving the
    -- user in front of an empty panel until they reopen it
    if not self.activePage then
        local first = AegisWindow.firstVisiblePage()
        if first then
            self:switchPage(first)
        elseif isClient() and self.rightsWaitingSince and (self.rightsRetries or 0) < RIGHTS_RETRY_MAX
            and getTimestampMs() - self.rightsWaitingSince >= RIGHTS_RETRY_MS then
            -- the original rightsReq or its reply got lost, without a retry
            -- the panel would stay empty for the rest of the session
            sendClientCommand(getPlayer(), AegisShared.MODULE, "rightsReq", {})
            self.rightsWaitingSince = getTimestampMs()
            self.rightsRetries = self.rightsRetries + 1
        end
    end
end

-- MP-safe clock + real calendar date instead of the survived-days counter
-- (see Aegis.hourMinute/Aegis.dateText in AegisTheme.lua for the
-- verified engine reasons)
local function timeString()
    local h, m = Aegis.hourMinute(getGameTime())
    return string.format("%02d:%02d", h, m)
end

local function dayString()
    return Aegis.dayAndDate(getGameTime())
end

function AegisWindow:roleString()
    -- an assigned Aegis role wins over the raw vanilla role, that is
    -- the role that actually applies in the Aegis sense
    if Aegis.role and Aegis.role ~= "" then return Aegis.role end
    if not isClient() then return getText("UI_Aegis_RoleSolo") end
    local ok, str = pcall(function()
        local role = getPlayer():getRole()
        return role and role:getName() or getAccessLevel()
    end)
    if ok and str and str ~= "" then return str end
    return getAccessLevel() or ""
end

function AegisWindow:prerender()
    local c = Aegis.col
    local w, h = self.width, self.height
    -- while the grip drags, the page still has its old size; clip every
    -- child to the frame so nothing spills onto the world and the drag
    -- reads like a blind opening and closing. Cleared in render()
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
        self:drawTextureScaled(grad, 1, 1, w - 2, 44, 0.05, c.gold.r, c.gold.g, c.gold.b)
    end
    local hud = Aegis.tex("hud")
    if hud then
        self:drawTextureScaled(hud, 20, 13, 38, 38, 1, 1, 1, 1)
    end
    -- operator brand instead of the fixed AEGIS; capped so a long name
    -- stays clear of the centered toast pill and the clock on the right
    local title = Aegis.fitText(AegisBrand.title(), UIFont.Large, math.floor(w * 0.4) - 70)
    Aegis.text(self, title, 70, 12, UIFont.Large, c.goldHi)
    if not self.subtitle then
        self.subtitle = getText("UI_Aegis_Subtitle"):gsub("(.)", "%1 "):gsub(" $", "")
    end
    Aegis.text(self, self.subtitle, 71, 12 + Aegis.fontH(UIFont.Large), UIFont.Small, c.muted)

    -- left of the three header buttons (help, minimize, close), the old
    -- fixed offset collided with the help button
    local clockX = w - 44 - 38 * 3 - 14
    Aegis.textRight(self, timeString(), clockX, 12, UIFont.Large, c.text)
    Aegis.textRight(self, dayString(), clockX, 12 + Aegis.fontH(UIFont.Large), UIFont.Small, c.muted)
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
    local navTop = ny
    local navFloor = h - 58 - 8
    local space = navFloor - navTop
    local need = visibleCount * (navH + navGap)
    if visibleCount > 0 and need > space then
        local perEntry = math.max(24, math.floor(space / visibleCount))
        navGap = math.max(2, math.min(6, perEntry - 30))
        navH = perEntry - navGap
        need = visibleCount * (navH + navGap)
    end
    -- Packing alone has a floor, and with many pages on a short window the
    -- list used to run straight through the role line in the footer. Past that floor the strip scrolls with the wheel instead
    self.navMaxScroll = math.max(0, need - space)
    local scroll = math.max(0, math.min(self.navScroll or 0, self.navMaxScroll))
    self.navScroll = scroll
    -- keep the active entry reachable after a jump from somewhere else
    if self.navRevealWanted and self.navMaxScroll > 0 then
        self.navRevealWanted = false
        local idx = 0
        for _, def in ipairs(pages) do
            if self:navVisible(def) then
                if def.id == self.activePage then break end
                idx = idx + 1
            end
        end
        local top = idx * (navH + navGap)
        if top < scroll then
            scroll = top
        elseif top + navH > scroll + space then
            scroll = top + navH - space
        end
        self.navScroll = math.max(0, math.min(scroll, self.navMaxScroll))
        scroll = self.navScroll
    end
    ny = navTop - scroll

    -- hide eyes only while the padlock is open, never during a drag and
    -- never on the last visible entry
    self.eyeRects = {}
    local showEyes = self.navUnlocked and not self.navDrag and visibleCount > 1

    for i, def in ipairs(pages) do
        if self:navVisible(def) then
            -- an entry scrolled out of the strip is neither drawn nor
            -- clickable, but it still takes its slot in the column
            if ny >= navTop - 1 and ny + navH <= navFloor + 1 then
            local nx, nw = 10, SIDEBAR_W - 20
            local dragging = self.navDrag and self.navDrag.id == def.id
            local hovered = self:isMouseOver() and self:getMouseX() >= nx and self:getMouseX() <= nx + nw
                and self:getMouseY() >= ny and self:getMouseY() <= ny + navH
            self.navHoverT[i] = Aegis.glide(self.navHoverT[i] or 0, hovered and 1 or 0, 0.3)
            local active = self.activePage == def.id
            if active then activeY = ny end

            if active then
                Aegis.roundRect(self, nx, ny, nw, navH, 8, dragging and 0.4 or 1, c.card)
            elseif self.navHoverT[i] > 0.01 then
                Aegis.roundRect(self, nx, ny, nw, navH, 8, 0.6 * self.navHoverT[i], c.card)
            end
            local a = dragging and 0.35 or 1
            local ic = active and c.gold or c.muted
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
                Aegis.icon(self, "eye", ex, ey, 16, overEye and 1 or 0.55, overEye and c.gold or c.muted)
                table.insert(self.eyeRects, { x = ex - 4, y = ny, w = 24, h = navH, id = def.id })
            end

            table.insert(self.navRects, { x = nx, y = ny, w = nw, h = navH, id = def.id })
            end
            ny = ny + navH + navGap
        end
    end
    -- thin marker on the sidebar edge whenever the strip scrolls
    if self.navMaxScroll > 0 then
        local barH = math.max(14, math.floor(space * space / (space + self.navMaxScroll)))
        local barY = navTop + math.floor((space - barH) * scroll / self.navMaxScroll)
        Aegis.roundRect(self, SIDEBAR_W - 5, barY, 2, barH, 1, 0.5, c.gold)
    end
    self.navH = navH

    -- drag preview: gold insertion line at the slot under the mouse plus
    -- the dragged label riding along with the cursor
    if self.navDrag then
        local slot = self:navSlotAt(self:getMouseY())
        local lineY
        if slot > #self.navRects then
            local last = self.navRects[#self.navRects]
            lineY = last and (last.y + last.h + 2) or ny
        else
            lineY = self.navRects[slot].y - math.floor(navGap / 2) - 1
        end
        self:drawRect(10, lineY, SIDEBAR_W - 20, 2, 1, c.gold.r, c.gold.g, c.gold.b)
        for _, def in ipairs(pages) do
            if def.id == self.navDrag.id then
                local my = self:getMouseY() - math.floor(navH / 2)
                Aegis.roundRect(self, 14, my, SIDEBAR_W - 28, navH, 8, 0.92, c.card)
                Aegis.icon(self, def.icon, 26, my + math.floor((navH - 18) / 2), 18, 1, c.gold)
                Aegis.text(self, getText(def.label), 56, my + math.floor((navH - Aegis.fontH(UIFont.Medium)) / 2), UIFont.Medium, c.text)
                break
            end
        end
    end

    -- gliding gold marker next to the active entry
    if activeY then
        if self.indicatorY < 0 then self.indicatorY = activeY end
        self.indicatorY = Aegis.glide(self.indicatorY, activeY, 0.3)
        Aegis.roundRect(self, 4, self.indicatorY + 9, 3, navH - 18, 1, 1, c.gold)
    end

    -- sidebar footer: role and version
    local fy = h - 58
    Aegis.hairline(self, 12, fy, SIDEBAR_W - 24, 0.7)
    Aegis.icon(self, "crown", 14, fy + 12, 14, 1, c.gold)
    -- the plus only shows while unlocked and something is hidden
    local showPlus = self.navUnlocked and #self:restorablePages() > 0
    if self.navPlusBtn and self.navPlusBtn:isVisible() ~= showPlus then
        self.navPlusBtn:setVisible(showPlus)
    end
    -- the padlock (and the plus when shown) sit at the right footer
    -- edge, long role names must not run underneath them
    local roleW = SIDEBAR_W - 38 - 36 - 6
    if showPlus then roleW = roleW - 32 end
    Aegis.text(self, Aegis.fitText(self:roleString(), UIFont.Small, roleW), 36, fy + 10, UIFont.Small, c.text)
    Aegis.text(self, "v" .. Aegis.version, 36, fy + 12 + Aegis.fontH(UIFont.Small), UIFont.Small, c.muted)

    -- last thing before the children draw: the clip for the drag
    if self.clipping then
        self:setStencilRect(1, HEADER_H + 1, w - 2, h - HEADER_H - 2)
    end
end

-- short gold confirmation for actions without their own visible result,
-- centered in the header between logo and clock
function AegisWindow:render()
    if self.clipping then
        self:clearStencilRect()
        self.clipping = false
        -- the grip sits in the clipped corner, redraw it on top so the
        -- handle stays visible for the whole drag
        if self.grip then
            local c = Aegis.col
            for row = 0, 2 do
                for i = 0, row do
                    self:drawRect(self.width - 7 - i * 5, self.height - 7 - (2 - row) * 5,
                        2, 2, 0.9, c.gold.r, c.gold.g, c.gold.b)
                end
            end
        end
    end
    if self.toastText and getTimestampMs() < (self.toastUntil or 0) then
        local c = Aegis.col
        local remaining = self.toastUntil - getTimestampMs()
        local a = math.min(1, remaining / 400)
        local w = Aegis.strW(UIFont.Medium, self.toastText) + 32
        local x = math.floor((self.width - w) / 2)
        local y = math.floor((HEADER_H - 34) / 2)
        Aegis.roundFrame(self, x, y, w, 34, 17, a, c.gold, c.dark)
        Aegis.textCentre(self, self.toastText, x + math.floor(w / 2), y + 9, UIFont.Medium, c.goldHi, a)
    else
        self.toastText = nil
    end
end

function AegisWindow:onMouseDown(x, y)
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

function AegisWindow:onMouseMove(dx, dy)
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

function AegisWindow:onMouseMoveOutside(dx, dy)
    self:onMouseMove(dx, dy)
end

-- wheel over the sidebar scrolls the entry strip; everywhere else the
-- page below keeps the wheel for its own lists
function AegisWindow:onMouseWheel(del)
    if self:getMouseX() >= SIDEBAR_W or self:getMouseY() <= HEADER_H then return false end
    if (self.navMaxScroll or 0) <= 0 then return false end
    self.navScroll = math.max(0, math.min((self.navScroll or 0) + del * 30, self.navMaxScroll))
    return true
end

function AegisWindow:onMouseUp(x, y)
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

function AegisWindow:onMouseUpOutside(x, y)
    self.dragging = false
    if self.navDrag then
        self:dropNavDrag()
        return
    end
    self.pressNav = nil
    self.pressEye = nil
end

-- reinsert the dragged entry at the slot under the mouse and persist.
-- Hidden pages (rights or the view filter) keep their relative place:
-- the visible list is reordered, then the hidden entries are woven back
-- at their old indexes
function AegisWindow:dropNavDrag()
    local dragId = self.navDrag.id
    self.navDrag = nil
    self.pressNav = nil
    local beforeId = self:navDropBefore(self:getMouseY())
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
    -- target looked up AFTER the removal, so no index correction is needed
    local slot = #visible + 1
    if beforeId and beforeId ~= dragId then
        for i, d in ipairs(visible) do
            if d.id == beforeId then
                slot = i
                break
            end
        end
    end
    table.insert(visible, slot, def)
    for _, e in ipairs(hidden) do
        table.insert(visible, math.min(e.idx, #visible + 1), e.def)
    end
    self:saveNavOrder(visible)
    Aegis.sound()
end

-- ==================================================================
-- AegisResizeGrip: bottom right resize handle. Reuses the vanilla
-- capture based drag mechanics of ISResizeWidget, adds a rebuild
-- callback on release and a subtle dot triangle as corner glyph
-- ==================================================================
AegisResizeGrip = ISResizeWidget:derive("AegisResizeGrip")

function AegisResizeGrip:onMouseDown(x, y)
    if not self:getIsVisible() then return end
    self.target.resizeStartW = self.target.width
    self.target.resizeStartH = self.target.height
    return ISResizeWidget.onMouseDown(self, x, y)
end

function AegisResizeGrip:onMouseUp(x, y)
    local wasResizing = self.resizing
    ISResizeWidget.onMouseUp(self, x, y)
    if wasResizing then self.target:onResizeDone() end
    return true
end

function AegisResizeGrip:onMouseUpOutside(x, y)
    local wasResizing = self.resizing
    ISResizeWidget.onMouseUpOutside(self, x, y)
    if wasResizing then self.target:onResizeDone() end
    return true
end

function AegisResizeGrip:render()
    local c = Aegis.col
    local hot = self.resizing or self:isMouseOver()
    -- the player window reuses this grip in blue via self.accent
    local col = hot and (self.accent or c.gold) or c.muted
    local a = hot and 0.9 or 0.45
    for row = 0, 2 do
        for i = 0, row do
            self:drawRect(self.width - 7 - i * 5, self.height - 7 - (2 - row) * 5, 2, 2, a, col.r, col.g, col.b)
        end
    end
end

-- ==================================================================
-- AegisMiniBar: the collapsed form of the panel. A tiny standalone bar
-- that replaces the hidden window, draggable, with restore and close
-- ==================================================================
AegisMiniBar = ISPanel:derive("AegisMiniBar")
AegisMiniBar.instance = nil

local MINI_W, MINI_H = 264, 46

function AegisMiniBar.show(window)
    AegisMiniBar.hide()
    local sw, sh = getCore():getScreenWidth(), getCore():getScreenHeight()
    local x = math.max(0, math.min(window.x, sw - MINI_W))
    local y = math.max(0, math.min(window.y, sh - MINI_H))
    local o = ISPanel:new(x, y, MINI_W, MINI_H)
    setmetatable(o, AegisMiniBar)
    AegisMiniBar.__index = AegisMiniBar
    o.background = false
    o.window = window
    o:initialise()
    o:addToUIManager()
    o:setAlwaysOnTop(true)

    o.plusBtn = AegisButton:new(MINI_W - 74, 8, 30, 30, nil, "plus", o, AegisMiniBar.restore)
    o.plusBtn.radius = 15
    o:addChild(o.plusBtn)
    o.closeBtn = AegisButton:new(MINI_W - 38, 8, 30, 30, nil, "close", o, function(bar)
        local win = bar.window
        AegisMiniBar.hide()
        if win then win:close() end
    end)
    o.closeBtn.radius = 15
    o:addChild(o.closeBtn)
    AegisMiniBar.instance = o
    return o
end

function AegisMiniBar.hide()
    if AegisMiniBar.instance then
        AegisMiniBar.instance:removeFromUIManager()
        AegisMiniBar.instance = nil
    end
end

function AegisMiniBar:restore()
    local win = self.window
    AegisMiniBar.hide()
    if win then
        -- the window follows the bar if it was dragged somewhere else
        win:setX(self.x)
        win:setY(self.y)
        win.baseY = self.y
        win:restoreFromMini()
    end
end

function AegisMiniBar:prerender()
    local c = Aegis.col
    Aegis.shadow(self, 0, 0, self.width, self.height, 18, 0.5)
    Aegis.roundFrame(self, 0, 0, self.width, self.height, 12, 1, c.line, c.bg)
    local hud = Aegis.tex("hud")
    if hud then
        self:drawTextureScaled(hud, 10, 9, 28, 28, 1, 1, 1, 1)
    end
    Aegis.text(self, "AEGIS", 46, 12, UIFont.Medium, c.goldHi)
end

function AegisMiniBar:onMouseDown(x, y)
    self:bringToTop()
    self.dragging = true
end

function AegisMiniBar:onMouseMove(dx, dy)
    if self.dragging then
        self:setX(self.x + dx)
        self:setY(self.y + dy)
    end
end

function AegisMiniBar:onMouseMoveOutside(dx, dy)
    self:onMouseMove(dx, dy)
end

function AegisMiniBar:onMouseUp(x, y)
    self.dragging = false
end

function AegisMiniBar:onMouseUpOutside(x, y)
    self.dragging = false
end

-- ==================================================================
-- AegisNavRestoreMenu: small popup above the sidebar footer listing
-- the hidden nav pages. A click only marks the row, the owning window
-- picks it up in update outside the mouse dispatch. The player window
-- reuses the class with its own palette
-- ==================================================================
AegisNavRestoreMenu = ISPanel:derive("AegisNavRestoreMenu")

local MENU_ROW_H = 30

-- maxH caps the popup so it can never reach into the header; anything
-- beyond that scrolls with the wheel
function AegisNavRestoreMenu:new(x, y, w, rows, cols, accent, maxH)
    local fits = #rows
    if maxH then
        fits = math.max(1, math.min(#rows, math.floor((maxH - 12) / MENU_ROW_H)))
    end
    local o = ISPanel:new(x, y, w, fits * MENU_ROW_H + 12)
    setmetatable(o, self)
    self.__index = self
    o.background = false
    o.rows = rows
    o.cols = cols
    o.accent = accent
    o.shown = fits
    o.top = 1
    return o
end

function AegisNavRestoreMenu:clampTop()
    local maxTop = math.max(1, #self.rows - self.shown + 1)
    if self.top > maxTop then self.top = maxTop end
    if self.top < 1 then self.top = 1 end
end

-- display slot under y, 1 = topmost visible row
function AegisNavRestoreMenu:rowAt(y)
    local idx = math.floor((y - 6) / MENU_ROW_H) + 1
    if idx >= 1 and idx <= self.shown and self.rows[self.top + idx - 1] then return idx end
    return nil
end

function AegisNavRestoreMenu:onMouseWheel(del)
    self.top = self.top + (del > 0 and 1 or -1)
    self:clampTop()
    return true
end

function AegisNavRestoreMenu:prerender()
    local c = self.cols
    self:clampTop()
    Aegis.shadow(self, 0, 0, self.width, self.height, 14, 0.5)
    Aegis.roundFrame(self, 0, 0, self.width, self.height, 8, 1, c.line, c.card)
    local hover = self:isMouseOver() and self:rowAt(self:getMouseY()) or nil
    local y = 6
    for i = 1, self.shown do
        local def = self.rows[self.top + i - 1]
        if def then
            local hot = hover == i
            if hot then
                Aegis.roundRect(self, 4, y + 1, self.width - 8, MENU_ROW_H - 2, 6, 0.18, self.accent)
            end
            Aegis.icon(self, def.icon, 10, y + math.floor((MENU_ROW_H - 16) / 2), 16, 1, hot and self.accent or c.muted)
            Aegis.text(self, Aegis.fitText(getText(def.label), UIFont.Small, self.width - 36 - 10), 36,
                y + math.floor((MENU_ROW_H - Aegis.fontH(UIFont.Small)) / 2), UIFont.Small, hot and c.text or c.muted)
            y = y + MENU_ROW_H
        end
    end
    -- more entries than fit: a thin marker on the edge that can scroll
    if #self.rows > self.shown then
        local barH = math.max(12, math.floor(self.height * self.shown / #self.rows))
        local barY = 6 + math.floor((self.height - 12 - barH) * (self.top - 1) / math.max(1, #self.rows - self.shown))
        Aegis.roundRect(self, self.width - 5, barY, 2, barH, 1, 0.6, self.accent)
    end
end

function AegisNavRestoreMenu:onMouseDown(x, y)
    return true
end

function AegisNavRestoreMenu:onMouseUp(x, y)
    local idx = self:rowAt(y)
    if idx then self.pickedId = self.rows[self.top + idx - 1].id end
    return true
end
