-- In game help: a standalone window with a manual tab (sections on the
-- left, article on the right) and a changelog tab. Texts come from
-- AegisHelpContent.lua, DE native and EN for every other language.
-- Two modes share the window: "admin" (gold, the admin manual) and
-- "player" (blue, the manual of the blue player panel)
require "Aegis/AegisTheme"
require "Aegis/AegisWidgets"
require "Aegis/AegisPlayerCore"
require "Aegis/AegisHelpContent"

AegisHelp = ISPanel:derive("AegisHelp")
AegisHelp.instance = nil

local DEF_W, DEF_H = 780, 560
local MIN_W, MIN_H = 620, 460
local EDGE = 12
local HEADER = 56
local NAV_W = 224
local GRIP = 22
-- chin below the scroll host so its scrollbar stays clear of the resize
-- corner (same collision the admin window ran into)
local GRIP_CHIN = 26
-- article scrollbar pulled INWARDS: at the old width-16 spot it sat in
-- the rounded window corner and long lines kept ending underneath it. The bar now sits at width-ART_BAR_X and
-- the text panel ends ART_INSET before the pane edge, well clear of it
local ART_BAR_X = 28
local ART_INSET = 34
-- gutter on the right of the section list for its own scrollbar
local NAV_GUTTER = 18
-- search box between the tab row and the section list
local SEARCH_Y = HEADER + 46
local SEARCH_H = 26
local NAV_TOP = SEARCH_Y + SEARCH_H + 8

-- admin palette with the gold family exposed as accent, mirror of
-- AegisPlayerCol so both modes draw through the same keys
local ADMIN_COL = {
    accent    = Aegis.col.gold,
    accentHi  = Aegis.col.goldHi,
    accentDim = Aegis.col.goldDim,
}
for k, v in pairs(Aegis.col) do
    if ADMIN_COL[k] == nil then ADMIN_COL[k] = v end
end

function AegisHelp.toggle(mode)
    mode = mode == "player" and "player" or "admin"
    if AegisHelp.instance then
        local sameMode = AegisHelp.instance.mode == mode
        AegisHelp.instance:close()
        -- same mode toggles off, the other mode rebuilds in its colors
        if sameMode then return end
    end
    local sw, sh = getCore():getScreenWidth(), getCore():getScreenHeight()
    local w = math.max(math.min(MIN_W, sw - 40), math.min(tonumber(Aegis.getPref("helpW")) or DEF_W, sw - EDGE * 2))
    local h = math.max(math.min(MIN_H, sh - 40), math.min(tonumber(Aegis.getPref("helpH")) or DEF_H, sh - EDGE * 2))
    local o = ISPanel:new(math.floor((sw - w) / 2), math.floor((sh - h) / 2), w, h)
    setmetatable(o, AegisHelp)
    AegisHelp.__index = AegisHelp
    o.background = false
    o.mode = mode
    o.col = mode == "player" and AegisPlayerCol or ADMIN_COL
    o.tab = "help"
    o.section = 1
    o.content = AegisHelpContent.get(mode)
    o.minimumWidth = math.min(MIN_W, sw - 40)
    o.minimumHeight = math.min(MIN_H, sh - 40)
    o:initialise()
    o:addToUIManager()
    o:setAlwaysOnTop(true)
    AegisHelp.instance = o
end

function AegisHelp:close()
    self:removeFromUIManager()
    AegisHelp.instance = nil
end

function AegisHelp:createChildren()
    self.closeBtn = AegisButton:new(self.width - 40, 13, 30, 30, nil, "close", self, AegisHelp.close)
    self.closeBtn.radius = 15
    self:addChild(self.closeBtn)

    -- reopens the update notice that only shows itself once per version
    self.newsBtn = AegisButton:new(self.width - 40 - 150, 13, 142, 30, getText("UI_Aegis_WhatsNew"), nil, self, function(panel)
        if AegisWhatsNew then AegisWhatsNew.show(panel.mode) end
    end)
    self:addChild(self.newsBtn)

    -- starts the guided tour, the help window steps aside so the highlights show
    self.tourBtn = AegisButton:new(self.width - 40 - 300, 13, 142, 30, getText("UI_Aegis_TourStart"), nil, self, function(panel)
        local mode = panel.mode
        panel:close()
        if AegisTour then AegisTour.start(mode) end
    end)
    self:addChild(self.tourBtn)

    local half = math.floor((NAV_W - 24) / 2)
    self.helpTabBtn = AegisButton:new(12, HEADER + 10, half, 30, getText("UI_Aegis_HelpTab"), nil, self, function(panel)
        panel:setTab("help")
    end)
    self.helpTabBtn.owner = self
    self.helpTabBtn.render = AegisHelp.renderTab
    self:addChild(self.helpTabBtn)
    self.logTabBtn = AegisButton:new(12 + half + 6, HEADER + 10, half, 30, getText("UI_Aegis_ChangelogTab"), nil, self, function(panel)
        panel:setTab("changelog")
    end)
    self.logTabBtn.owner = self
    self.logTabBtn.render = AegisHelp.renderTab
    self:addChild(self.logTabBtn)

    -- filters the section list, titles and body text both count
    self.searchEntry = ISTextEntryBox:new("", 12, SEARCH_Y, half * 2 + 6, SEARCH_H)
    self.searchEntry:initialise()
    self.searchEntry:instantiate()
    self.searchEntry.font = UIFont.Small
    self.searchEntry:setClearButton(true)
    self.searchEntry.backgroundColor = { r = self.col.dark.r, g = self.col.dark.g, b = self.col.dark.b, a = 1 }
    self.searchEntry.borderColor = { r = self.col.line.r, g = self.col.line.g, b = self.col.line.b, a = 1 }
    self.searchEntry:setPlaceholderText(getText("UI_Aegis_HelpSearch"))
    local win = self
    self.searchEntry.onTextChange = function() win:onSearch() end
    self:addChild(self.searchEntry)

    -- article area scrolls, the text panel inside draws the wrapped lines
    self.scroll = AegisScrollArea:new(NAV_W, HEADER + 1, self.width - NAV_W - 12, self.height - HEADER - GRIP_CHIN)
    self:addChild(self.scroll)
    self.textPanel = ISPanel:new(0, 0, self.scroll.width - ART_INSET, 10)
    self.textPanel.background = false
    self.textPanel.owner = self
    self.textPanel.render = AegisHelp.renderText
    self.textPanel.onMouseDown = function() end
    self.scroll:addChild(self.textPanel)

    -- run the layout pass once right away: the scrollbar otherwise sits at
    -- the vanilla default (flush right) until the first manual resize
    self:placeChrome()
    self:setTab("help")
end

-- AegisButton styles are wired to the gold palette, the two tabs draw
-- their pill themselves so the player mode gets the same shape in blue
function AegisHelp.renderTab(btn)
    local c = btn.owner.col
    local w, h = btn.width, btn.height
    local r = math.min(btn.radius, math.floor(h / 2))
    btn.hoverT = Aegis.glide(btn.hoverT, btn.hovered and 1 or 0, 0.35)
    local textC
    if btn.active then
        Aegis.roundRect(btn, 0, 0, w, h, r, 1, c.accent)
        if btn.hoverT > 0.01 then
            Aegis.roundRect(btn, 0, 0, w, h, r, 0.20 * btn.hoverT, c.white)
        end
        if btn.pressed then
            Aegis.roundRect(btn, 0, 0, w, h, r, 0.22, c.dark)
        end
        textC = c.dark
    else
        Aegis.roundRect(btn, 0, 0, w, h, r, 1, c.line)
        Aegis.roundRect(btn, 1, 1, w - 2, h - 2, math.max(1, r - 1), 1, c.card)
        if btn.hoverT > 0.01 then
            Aegis.roundRect(btn, 1, 1, w - 2, h - 2, math.max(1, r - 1), 0.6 * btn.hoverT, c.cardHi)
        end
        if btn.pressed then
            Aegis.roundRect(btn, 1, 1, w - 2, h - 2, math.max(1, r - 1), 0.35, c.dark)
        end
        textC = c.text
    end
    local label = Aegis.fitText(btn.label or "", btn.font, w - 12)
    Aegis.textCentre(btn, label, math.floor(w / 2), math.floor((h - Aegis.fontH(btn.font)) / 2), btn.font, textC)
end

function AegisHelp:setTab(tab)
    self.tab = tab
    self.section = 1
    if self.searchEntry then self.searchEntry:setVisible(tab == "help") end
    self:applyFilter()
    self:layoutText()
end

-- lowercased text per section, built once, keystrokes only scan strings
function AegisHelp:searchBlobs()
    if not self.blobCache then
        local cache = {}
        for i, sec in ipairs(self.content.help) do
            local parts = { string.lower(sec.title or "") }
            for _, line in ipairs(sec.lines or {}) do
                parts[#parts + 1] = string.lower(line)
            end
            cache[i] = table.concat(parts, "\n")
        end
        self.blobCache = cache
    end
    return self.blobCache
end

-- filtered view over the section list. Nav drawing and hit tests read it,
-- so this runs on keystrokes and tab switches, never per frame
function AegisHelp:applyFilter()
    local needle = string.lower(self.searchEntry and self.searchEntry:getInternalText() or "")
    local vis = {}
    if needle == "" then
        for i = 1, #self.content.help do vis[i] = i end
    else
        local blobs = self:searchBlobs()
        for i = 1, #self.content.help do
            if string.find(blobs[i], needle, 1, true) then
                vis[#vis + 1] = i
            end
        end
    end
    self.visibleSections = vis
    for _, idx in ipairs(vis) do
        if idx == self.section then return end
    end
    -- the selected section fell out of the filter, take the first visible
    self.section = vis[1]
    self.navScroll = 0
end

function AegisHelp:onSearch()
    local before = self.section
    self:applyFilter()
    if self.section ~= before then self:layoutText() end
end

-- ------------------------------------------------------------------
-- text layout: wrap once per tab, section or size change, prerender
-- only draws
-- ------------------------------------------------------------------

local function wrap(text, font, maxW, out, color)
    local line = ""
    for word in tostring(text):gmatch("%S+") do
        local probe = line == "" and word or (line .. " " .. word)
        if Aegis.strW(font, probe) > maxW and line ~= "" then
            table.insert(out, { text = line, font = font, color = color })
            line = word
        else
            line = probe
        end
    end
    if line ~= "" then
        table.insert(out, { text = line, font = font, color = color })
    end
end

function AegisHelp:layoutText()
    local c = self.col
    local maxW = self.textPanel.width - 32
    -- the width this layout was made for; renderText compares against it
    -- every frame and lays out again when they drift apart: shrinking
    -- the window otherwise leaves the old wrap running under the
    -- scrollbar on nearly every page
    self.wrappedFor = self.textPanel.width
    local rows = {}
    if self.tab == "help" then
        local sec = self.content.help[self.section]
        if sec then
            table.insert(rows, { text = Aegis.fitText(sec.title, UIFont.Medium, maxW + 16), font = UIFont.Medium, color = c.accentHi })
            table.insert(rows, { gap = 6 })
            for _, para in ipairs(sec.lines) do
                wrap(para, UIFont.Small, maxW, rows, c.text)
                table.insert(rows, { gap = 8 })
            end
        end
    else
        for _, entry in ipairs(self.content.changelog) do
            table.insert(rows, { text = Aegis.fitText("v" .. entry.version .. "  (" .. entry.date .. ")", UIFont.Medium, maxW + 16), font = UIFont.Medium, color = c.accentHi })
            table.insert(rows, { gap = 6 })
            -- sectioned entries (new/fixed) carry their
            -- headings inside the language block itself; flat points stay
            -- supported for the older versions
            if entry.sections then
                for _, sec in ipairs(entry.sections) do
                    if #(sec.points or {}) > 0 then
                        table.insert(rows, { text = sec.title, font = UIFont.Small, color = c.accentHi })
                        table.insert(rows, { gap = 4 })
                        for _, point in ipairs(sec.points) do
                            wrap("- " .. point, UIFont.Small, maxW, rows, c.text)
                            table.insert(rows, { gap = 4 })
                        end
                        table.insert(rows, { gap = 8 })
                    end
                end
            else
                for _, point in ipairs(entry.points) do
                    wrap("- " .. point, UIFont.Small, maxW, rows, c.text)
                    table.insert(rows, { gap = 4 })
                end
            end
            table.insert(rows, { gap = 14 })
        end
    end
    self.rows = rows
    local y = 12
    for _, row in ipairs(rows) do
        if row.gap then
            y = y + row.gap
        else
            y = y + Aegis.fontH(row.font) + 2
        end
    end
    self.textPanel:setHeight(math.max(y + 12, 10))
    self.scroll:setScrollHeight(self.textPanel.height)
    self.scroll:setYScroll(0)
end

function AegisHelp.renderText(panel)
    local o = panel.owner
    -- self healing: any path that changes the panel width without a fresh
    -- layout is caught here, once per change, before a single stale line
    -- is drawn
    if o.wrappedFor ~= panel.width then o:layoutText() end
    if not o.rows then return end
    -- hard clip at the panel edge. The wrap should keep every line
    -- inside on its own, but on some setups long lines still ended
    -- underneath the article scrollbar. The stencil makes that class
    -- of failure impossible instead of arguing with it
    panel:setStencilRect(0, 0, panel.width + 4, math.max(10, panel.height))
    local y = 12
    for _, row in ipairs(o.rows) do
        if row.gap then
            y = y + row.gap
        else
            Aegis.text(panel, row.text, 16, y, row.font, row.color)
            y = y + Aegis.fontH(row.font) + 2
        end
    end
    panel:clearStencilRect()
end

-- ------------------------------------------------------------------
-- resize: own corner drag, same clamping as the admin window
-- ------------------------------------------------------------------

function AegisHelp:applyResize(w, h)
    local sw, sh = getCore():getScreenWidth(), getCore():getScreenHeight()
    w = math.min(w, sw - EDGE - self.x)
    h = math.min(h, sh - EDGE - self.y)
    w = math.max(w, self.minimumWidth)
    h = math.max(h, self.minimumHeight)
    if w == self.width and h == self.height then return end
    self:setWidth(w)
    self:setHeight(h)
    self:placeChrome()
    -- wrapping depends on the article width
    self:layoutText()
end

-- children do not anchor (ISPanel default), move them by hand. The
-- scrollbar re-anchors its lua side too, setWidth alone leaves it stale
function AegisHelp:placeChrome()
    self.closeBtn:setX(self.width - 40)
    if self.newsBtn then self.newsBtn:setX(self.width - 40 - 150) end
    if self.tourBtn then self.tourBtn:setX(self.width - 40 - 300) end
    self.scroll:setWidth(self.width - NAV_W - 12)
    self.scroll:setHeight(self.height - HEADER - GRIP_CHIN)
    if self.scroll.vscroll then
        self.scroll.vscroll:setX(self.scroll.width - ART_BAR_X)
        self.scroll.vscroll:setHeight(self.scroll.height)
    end
    self.textPanel:setWidth(self.scroll.width - ART_INSET)
end

function AegisHelp:finishResize()
    if not self.resizing then return end
    self.resizing = false
    if self.width ~= self.resizeStartW or self.height ~= self.resizeStartH then
        Aegis.setPref("helpW", math.floor(self.width))
        Aegis.setPref("helpH", math.floor(self.height))
    end
end

-- ------------------------------------------------------------------

function AegisHelp:prerender()
    local c = self.col
    Aegis.shadow(self, 0, 0, self.width, self.height, 26, 0.6)
    Aegis.roundFrame(self, 0, 0, self.width, self.height, 14, 1, c.line, c.bg)
    Aegis.icon(self, "logs", 18, 16, 22, 1, c.accent)
    Aegis.text(self, getText("UI_Aegis_Help"), 50, 16, UIFont.Medium, c.accentHi)
    Aegis.hairline(self, 1, HEADER, self.width - 2)

    self.helpTabBtn.active = self.tab == "help"
    self.logTabBtn.active = self.tab == "changelog"

    -- section list, only on the manual tab. It used to simply BREAK once
    -- the window got low, silently dropping the last topics. Packing the
    -- rows tighter looked cramped, so instead the rows keep their
    -- height and the list carries a real draggable
    -- scrollbar on its right, the same pattern as the tile browser
    self.sectionRects = {}
    if self.tab == "help" then
        local vis = self.visibleSections
        local total = #vis
        local top = NAV_TOP
        local avail = self.height - top - 12
        local lineH = Aegis.fontH(UIFont.Small) + 12
        local visible = math.max(1, math.floor(avail / lineH))
        local maxScroll = math.max(0, total - visible)
        self.navScroll = math.max(0, math.min(self.navScroll or 0, maxScroll))
        -- the titles stay clear of the bar gutter
        local textW = NAV_W - 20 - (maxScroll > 0 and NAV_GUTTER or 8)
        local sy = top
        for i = self.navScroll + 1, math.min(total, self.navScroll + visible) do
            local idx = vis[i]
            local sec = self.content.help[idx]
            local active = idx == self.section
            if active then
                Aegis.roundRect(self, 8, sy, NAV_W - 16, lineH - 2, 8, 1, c.card)
            end
            Aegis.text(self, Aegis.fitText(sec.title, UIFont.Small, textW), 20,
                sy + math.floor((lineH - Aegis.fontH(UIFont.Small)) / 2),
                UIFont.Small, active and c.text or c.muted)
            table.insert(self.sectionRects, { y = sy, h = lineH - 2, idx = idx })
            sy = sy + lineH
        end
        local bar = self:navBar()
        if bar then
            Aegis.roundRect(self, bar.x, bar.y, bar.w, bar.h, 5, 1, c.dark)
            Aegis.roundRect(self, bar.x, bar.thumbY, bar.w, bar.thumbH, 5, 1,
                self.navDrag and c.accentDim or c.line)
        end
    end
    self:drawRect(NAV_W - 1, HEADER + 1, 1, self.height - HEADER - 2, 1, c.line.r, c.line.g, c.line.b)

    -- dot triangle in the resize corner
    local hot = self.resizing or (self:isMouseOver()
        and self:getMouseX() >= self.width - GRIP and self:getMouseY() >= self.height - GRIP)
    local gc = hot and c.accent or c.muted
    local ga = hot and 0.9 or 0.45
    for row = 0, 2 do
        for i = 0, row do
            self:drawRect(self.width - 7 - i * 5, self.height - 7 - (2 - row) * 5, 2, 2, ga, gc.r, gc.g, gc.b)
        end
    end
end

-- geometry of the section list scrollbar, nil while everything fits.
-- Drawing and hit testing share it, the tile browser pattern
function AegisHelp:navBar()
    if self.tab ~= "help" then return nil end
    local total = #self.visibleSections
    local top = NAV_TOP
    local avail = self.height - top - 12
    local lineH = Aegis.fontH(UIFont.Small) + 12
    local visible = math.max(1, math.floor(avail / lineH))
    local maxScroll = math.max(0, total - visible)
    if maxScroll == 0 then return nil end
    local trackH = avail - 4
    local thumbH = math.max(24, math.floor(trackH * visible / total))
    local span = trackH - thumbH
    local thumbY = top + math.floor(span * ((self.navScroll or 0) / maxScroll))
    return { x = NAV_W - 14, y = top, w = 10, h = trackH, thumbY = thumbY,
             thumbH = thumbH, span = span, maxScroll = maxScroll, page = visible - 1 }
end

-- the article pane is a child and handles its own wheel; this only fires
-- with the mouse over the section list on the left
function AegisHelp:onMouseWheel(del)
    if self.tab == "help" and self:getMouseX() < NAV_W and self:getMouseY() > HEADER then
        self.navScroll = (self.navScroll or 0) + (del > 0 and 1 or -1)
        return true
    end
    return false
end

function AegisHelp:onMouseDown(x, y)
    self:bringToTop()
    if x >= self.width - GRIP and y >= self.height - GRIP then
        self.resizing = true
        self.resizeStartW = self.width
        self.resizeStartH = self.height
        return
    end
    if y <= HEADER then
        self.dragging = true
        return
    end
    -- the section list scrollbar owns its gutter: thumb starts a drag, the
    -- track pages, both before the row hit test
    local bar = self:navBar()
    if bar and x >= bar.x - 4 and x <= bar.x + bar.w + 4 and y >= bar.y and y <= bar.y + bar.h then
        if y >= bar.thumbY and y <= bar.thumbY + bar.thumbH then
            self.navDrag = { grab = y - bar.thumbY }
        else
            local dir = (y < bar.thumbY) and -1 or 1
            self.navScroll = math.max(0, math.min(bar.maxScroll,
                (self.navScroll or 0) + dir * math.max(1, bar.page)))
        end
        return
    end
    if self.tab == "help" and x < NAV_W then
        for _, rect in ipairs(self.sectionRects or {}) do
            if y >= rect.y and y <= rect.y + rect.h then
                self.section = rect.idx
                self:layoutText()
                return
            end
        end
    end
end

function AegisHelp:onMouseMove(dx, dy)
    if self.resizing then
        self:applyResize(self.width + dx, self.height + dy)
        return
    end
    if self.navDrag then
        local bar = self:navBar()
        if bar and bar.span > 0 then
            local frac = (self:getMouseY() - bar.y - self.navDrag.grab) / bar.span
            self.navScroll = math.max(0, math.min(bar.maxScroll,
                math.floor(frac * bar.maxScroll + 0.5)))
        end
        return
    end
    if self.dragging then
        self:setX(self.x + dx)
        self:setY(self.y + dy)
    end
end

function AegisHelp:onMouseMoveOutside(dx, dy)
    self:onMouseMove(dx, dy)
end

function AegisHelp:onMouseUp(x, y)
    self:finishResize()
    self.dragging = false
    self.navDrag = nil
end

function AegisHelp:onMouseUpOutside(x, y)
    self:finishResize()
    self.dragging = false
    self.navDrag = nil
end
