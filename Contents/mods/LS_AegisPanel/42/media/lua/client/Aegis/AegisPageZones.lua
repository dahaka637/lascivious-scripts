-- Zones: safehouse overview, rectangle builder, freeform brush and
-- click-through overlay. A zone is one main safehouse plus annex
-- rectangles; the outline of the union is always what gets drawn.
-- The truth of a zone is its tile set, so both editor tools send the
-- whole wanted area (full = true) and the server unites it and picks
-- the main.
require "Aegis/AegisWindow"
require "ISUI/ISScrollingListBox"

AegisPageZones = ISPanel:derive("AegisPageZones")

local LIST_W = 300
local ROW_H = 44
-- annexes per zone; a full-area decomposition may hold one more piece
-- because the biggest rectangle of it becomes the main safehouse
local MAX_PARTS = 96
local MAX_EDGE = 300
-- same cap as the rectangle tool, just as area instead of edge length
local MAX_BRUSH_TILES = MAX_EDGE * MAX_EDGE
local POLL_MS = 3000
local LOCK_HEARTBEAT_MS = 4000

-- ==================================================================
-- Tile sets: nested set set[x][y]=true
-- ==================================================================
local function tileSet(rects)
    local set = {}
    for _, r in ipairs(rects) do
        for tx = r.x, r.x + r.w - 1 do
            local column = set[tx]
            if not column then
                column = {}
                set[tx] = column
            end
            for ty = r.y, r.y + r.h - 1 do
                column[ty] = true
            end
        end
    end
    return set
end

local function hasTile(set, tx, ty)
    local column = set[tx]
    return column ~= nil and column[ty] == true
end

-- outer edges of the union as one segment per tile border
local function unitEdges(set)
    local edges = {}
    for tx, column in pairs(set) do
        for ty in pairs(column) do
            if not hasTile(set, tx, ty - 1) then table.insert(edges, { tx, ty, tx + 1, ty }) end
            if not hasTile(set, tx, ty + 1) then table.insert(edges, { tx, ty + 1, tx + 1, ty + 1 }) end
            if not hasTile(set, tx - 1, ty) then table.insert(edges, { tx, ty, tx, ty + 1 }) end
            if not hasTile(set, tx + 1, ty) then table.insert(edges, { tx + 1, ty, tx + 1, ty + 1 }) end
        end
    end
    return edges
end

-- ==================================================================
-- Outlines: { lines, cx, cy, minX, minY, maxX, maxY }.
-- lines are merged runs of tile borders, so a 10x20 area costs 4 lines
-- instead of 60 segments while covering the exact same pixels. cx/cy is
-- the world mean of the unit segment ends, which is what the label used
-- to be averaged from in screen space (projection is affine, same point).
-- ==================================================================
local function mergeUnitEdges(list)
    local rows, cols = {}, {}
    local sumX, sumY, ends = 0, 0, 0
    local minX, minY, maxX, maxY
    for _, k in pairs(list) do
        sumX = sumX + k[1] + k[3]
        sumY = sumY + k[2] + k[4]
        ends = ends + 2
        if not minX or k[1] < minX then minX = k[1] end
        if not maxX or k[3] > maxX then maxX = k[3] end
        if not minY or k[2] < minY then minY = k[2] end
        if not maxY or k[4] > maxY then maxY = k[4] end
        if k[2] == k[4] then
            local row = rows[k[2]]
            if not row then
                row = {}
                rows[k[2]] = row
            end
            row[#row + 1] = k[1]
        else
            local col = cols[k[1]]
            if not col then
                col = {}
                cols[k[1]] = col
            end
            col[#col + 1] = k[2]
        end
    end
    local lines = {}
    for y, xs in pairs(rows) do
        table.sort(xs)
        local i = 1
        while i <= #xs do
            local j = i
            while j < #xs and xs[j + 1] == xs[j] + 1 do j = j + 1 end
            lines[#lines + 1] = { xs[i], y, xs[j] + 1, y }
            i = j + 1
        end
    end
    for x, ys in pairs(cols) do
        table.sort(ys)
        local i = 1
        while i <= #ys do
            local j = i
            while j < #ys and ys[j + 1] == ys[j] + 1 do j = j + 1 end
            lines[#lines + 1] = { x, ys[i], x, ys[j] + 1 }
            i = j + 1
        end
    end
    if ends == 0 then return { lines = lines } end
    return {
        lines = lines, cx = sumX / ends, cy = sumY / ends,
        minX = minX, minY = minY, maxX = maxX, maxY = maxY,
    }
end

local function setOutline(set)
    return mergeUnitEdges(unitEdges(set))
end

-- the four sides of a single rectangle, without tile expansion
local function rectEdges(r)
    return {
        { r.x, r.y, r.x + r.w, r.y },
        { r.x, r.y + r.h, r.x + r.w, r.y + r.h },
        { r.x, r.y, r.x, r.y + r.h },
        { r.x + r.w, r.y, r.x + r.w, r.y + r.h },
    }
end

-- a rectangle is already merged, its mean of ends is the plain centre
local function rectOutline(r)
    return {
        lines = rectEdges(r),
        cx = r.x + r.w / 2, cy = r.y + r.h / 2,
        minX = r.x, minY = r.y, maxX = r.x + r.w, maxY = r.y + r.h,
    }
end

-- greedily split a tile set into maximal rectangles (strips in x,
-- then extend downward while the full row is present)
local function decompose(set)
    local cells = {}
    for tx, column in pairs(set) do
        for ty in pairs(column) do
            table.insert(cells, { x = tx, y = ty })
        end
    end
    table.sort(cells, function(a, b)
        if a.y ~= b.y then return a.y < b.y end
        return a.x < b.x
    end)
    local used = {}
    local function isFree(tx, ty)
        return hasTile(set, tx, ty) and not hasTile(used, tx, ty)
    end
    local function mark(tx, ty)
        local column = used[tx]
        if not column then
            column = {}
            used[tx] = column
        end
        column[ty] = true
    end
    local rects = {}
    for _, z in ipairs(cells) do
        if isFree(z.x, z.y) then
            -- capped like the server side: an edge above MAX_EDGE is
            -- refused there, and under the full payload that would mean
            -- losing that piece of the zone. Two capped
            -- rectangles still touch, so the protection stays seamless
            local width = 1
            while width < MAX_EDGE and isFree(z.x + width, z.y) do width = width + 1 end
            local height = 1
            local keepGoing = true
            while keepGoing and height < MAX_EDGE do
                for dx = 0, width - 1 do
                    if not isFree(z.x + dx, z.y + height) then
                        keepGoing = false
                        break
                    end
                end
                if keepGoing then height = height + 1 end
            end
            for dy = 0, height - 1 do
                for dx = 0, width - 1 do
                    mark(z.x + dx, z.y + dy)
                end
            end
            table.insert(rects, { x = z.x, y = z.y, w = width, h = height })
        end
    end
    return rects
end

-- ==================================================================
-- World->screen: anchor via isoToScreen, points as XToScreen deltas
-- (vehicle placer pattern). Everything on the player's floor, otherwise
-- pick and drawing drift by 3 tiles per level on upper floors
-- ==================================================================
local function playerLevel()
    local p = getPlayer()
    return p and math.floor(p:getZ()) or 0
end

-- tile under the cursor; called once per tick, not once per draw
local function mouseTile()
    local z = playerLevel()
    local zoom = getCore():getZoom(0)
    local mx, my = getMouseX() * zoom, getMouseY() * zoom
    return math.floor(IsoUtils.XToIso(mx, my, z)), math.floor(IsoUtils.YToIso(mx, my, z))
end

local function screenProjection(wx, wy, z)
    local zoom = getCore():getZoom(0)
    if zoom == 0 then return nil end
    local anchorX, anchorY = isoToScreenX(0, wx, wy, z), isoToScreenY(0, wx, wy, z)
    local baseX, baseY = IsoUtils.XToScreen(wx, wy, z, 0), IsoUtils.YToScreen(wx, wy, z, 0)
    return function(px, py)
        return anchorX + (IsoUtils.XToScreen(px, py, z, 0) - baseX) / zoom,
            anchorY + (IsoUtils.YToScreen(px, py, z, 0) - baseY) / zoom
    end
end

-- same slack as before, in screen pixels
local VIEW_MARGIN = 200
-- probing the visible world box costs 3 projections (6 Java calls), a
-- line costs 2. Below this many lines the filter would cost more than
-- the drawing it can save, so plain rectangles skip it
local PREFILTER_MIN = 8

local function makeView(wx, wy, z)
    local project = screenProjection(wx, wy, z)
    if not project then return nil end
    return { project = project }
end

-- World box the screen covers under exactly this projection. The mapping
-- is affine, so three probes give the basis and the screen corners invert
-- back into world coordinates. Probed at most once per view, and only
-- when there is enough to cull.
local function viewBounds(view)
    if view.probed then return view.minX ~= nil end
    view.probed = true
    local sw, sh = getCore():getScreenWidth(), getCore():getScreenHeight()
    local project = view.project
    local ox, oy = project(0, 0)
    local ax, ay = project(1, 0)
    local bx, by = project(0, 1)
    local dax, day = ax - ox, ay - oy
    local dbx, dby = bx - ox, by - oy
    local det = dax * dby - day * dbx
    if det == 0 then return false end
    local minX, minY, maxX, maxY
    for i = 1, 4 do
        local sx = (i == 1 or i == 3) and -VIEW_MARGIN or (sw + VIEW_MARGIN)
        local sy = (i <= 2) and -VIEW_MARGIN or (sh + VIEW_MARGIN)
        local rx, ry = sx - ox, sy - oy
        local px = (rx * dby - ry * dbx) / det
        local py = (dax * ry - day * rx) / det
        if not minX or px < minX then minX = px end
        if not maxX or px > maxX then maxX = px end
        if not minY or py < minY then minY = py end
        if not maxY or py > maxY then maxY = py end
    end
    view.minX, view.minY, view.maxX, view.maxY = minX, minY, maxX, maxY
    return true
end

local function offView(view, minX, minY, maxX, maxY)
    return maxX < view.minX or minX > view.maxX or maxY < view.minY or minY > view.maxY
end

local function drawOutline(el, view, outline, a, color)
    if not view or not outline then return end
    local lines = outline.lines
    local cull = #lines >= PREFILTER_MIN and outline.minX ~= nil and viewBounds(view)
    if cull and offView(view, outline.minX, outline.minY, outline.maxX, outline.maxY) then return end
    local project = view.project
    for i = 1, #lines do
        local k = lines[i]
        local ax, ay, bx, by = k[1], k[2], k[3], k[4]
        -- lines are axis aligned in world space, so lo/hi is a swap
        local lox, hix = ax, bx
        if lox > hix then lox, hix = hix, lox end
        local loy, hiy = ay, by
        if loy > hiy then loy, hiy = hiy, loy end
        if not cull or not offView(view, lox, loy, hix, hiy) then
            local x1, y1 = project(ax, ay)
            local x2, y2 = project(bx, by)
            el:drawLine2(x1, y1, x2, y2, a, color.r, color.g, color.b)
            el:drawLine2(x1, y1 + 1, x2, y2 + 1, a * 0.5, color.r, color.g, color.b)
        end
    end
end

-- label anchor, one projection instead of one per edge
local function outlineLabel(view, outline)
    if not view or not outline or not outline.cx then return nil end
    local mx, my = view.project(outline.cx, outline.cy)
    if not mx then return nil end
    return math.floor(mx), math.floor(my)
end

-- identity of the drawn shape; equal key means the outline still fits
local function shapeKey(entry)
    local out = { entry.x, entry.y, entry.w, entry.h }
    for _, r in ipairs(entry.parts or {}) do
        out[#out + 1] = r.x
        out[#out + 1] = r.y
        out[#out + 1] = r.w
        out[#out + 1] = r.h
    end
    return table.concat(out, ",")
end

local function formRects(entry)
    local rects = { { x = entry.x, y = entry.y, w = entry.w, h = entry.h } }
    for _, r in ipairs(entry.parts or {}) do
        table.insert(rects, r)
    end
    return rects
end

-- a zone is one area, not a pile of rectangles: total tiles of main plus
-- annexes, piece count only for the rare zone that is not one block.
-- The decomposition is disjoint, so a plain sum is the real area
local function zoneStats(entry)
    local tiles = (tonumber(entry.w) or 0) * (tonumber(entry.h) or 0)
    local pieces = 1
    for _, r in ipairs(entry.parts or {}) do
        tiles = tiles + (tonumber(r.w) or 0) * (tonumber(r.h) or 0)
        pieces = pieces + 1
    end
    return tiles, pieces
end

-- ==================================================================
-- Overlay: all zone outlines in the world, mouse events pass through,
-- lives independently of the Aegis window
-- ==================================================================
AegisZoneOverlay = ISPanel:derive("AegisZoneOverlay")
AegisZoneOverlay.instance = nil
AegisZoneOverlay.data = {}

function AegisZoneOverlay.show(on)
    if on and not AegisZoneOverlay.instance then
        local sw, sh = getCore():getScreenWidth(), getCore():getScreenHeight()
        local o = ISPanel:new(0, 0, sw, sh)
        setmetatable(o, AegisZoneOverlay)
        AegisZoneOverlay.__index = AegisZoneOverlay
        o.background = false
        o:initialise()
        o:addToUIManager()
        o.javaObject:setConsumeMouseEvents(false)
        AegisZoneOverlay.instance = o
    elseif not on and AegisZoneOverlay.instance then
        AegisZoneOverlay.instance:removeFromUIManager()
        AegisZoneOverlay.instance = nil
    end
end

function AegisZoneOverlay:render()
    -- while editing, the editor takes over the drawing
    if AegisZoneEditor and AegisZoneEditor.instance then return end
    local c = Aegis.col
    local z = playerLevel()
    for _, e in ipairs(AegisZoneOverlay.data) do
        local view = makeView(e.x, e.y, z)
        drawOutline(self, view, e.outline, 0.7, c.gold)
        local mx, my = outlineLabel(view, e.outline)
        if mx then
            local name = e.title ~= "" and e.title or e.owner
            Aegis.textCentre(self, name, mx, my - math.floor(Aegis.fontH(UIFont.Small) / 2), UIFont.Small, c.goldHi)
        end
    end
end

-- ==================================================================
-- Editor: fullscreen over the world, two tools on ONE tile set.
-- Rect: every left drag appends a rectangle to the set on release, a
-- right drag carves appended area out again (the original zone stays
-- protected, shrinking is the brush's job); the editor stays open
-- between rectangles. Brush: left click paints single tiles, right
-- click erases anywhere. Both preview the union as one shape, Enter
-- applies the whole set once, ESC cancels.
-- ==================================================================
AegisZoneEditor = ISPanel:derive("AegisZoneEditor")
AegisZoneEditor.instance = nil

-- neighbors: outlines of the owner's other zones, drawn but not paintable.
-- The server merges every zone of that owner whose area touches the new
-- one, so the admin has to see where he can dock
function AegisZoneEditor.start(entry, tool, newMode, neighbors)
    if AegisZoneEditor.instance then return end
    local sw, sh = getCore():getScreenWidth(), getCore():getScreenHeight()
    local o = ISPanel:new(0, 0, sw, sh)
    setmetatable(o, AegisZoneEditor)
    AegisZoneEditor.__index = AegisZoneEditor
    o.background = false
    o.entry = entry
    o.tool = tool
    o.newMode = newMode == true
    o.neighbors = type(neighbors) == "table" and neighbors or {}
    -- both tools work the same set: a new area starts empty, an existing
    -- zone starts fully loaded, main and annexes. Whatever the set holds
    -- on Enter is what the zone becomes
    if o.newMode then
        o.tiles = {}
    else
        o.tiles = tileSet(formRects(entry))
        -- the zone as it stood when the editor opened: the rect tool may
        -- not erase it, and apply checks the admin stands on the property
        o.baseTiles = tileSet(formRects(entry))
    end
    -- unit edges as a set, painting only touches the four affected
    -- ones instead of recomputing everything; the merged outline is
    -- rebuilt from it in update(), and only after a real change
    o.edgeSet = {}
    for _, k in ipairs(unitEdges(o.tiles)) do
        o.edgeSet[k[1] .. "|" .. k[2] .. "|" .. k[3] .. "|" .. k[4]] = k
    end
    o.outline = mergeUnitEdges(o.edgeSet)
    o.outlineDirty = false
    o.count = 0
    for _, column in pairs(o.tiles) do
        for _ in pairs(column) do o.count = o.count + 1 end
    end
    -- piece count for the header, recounted only after a real change and
    -- never in the middle of a stroke or drag
    o.partsCount = o.newMode and 0 or (1 + #(entry.parts or {}))
    o.partsDirty = false
    o.dragging = false
    o.erasing = false
    o.nextLockAt = getTimestampMs() + LOCK_HEARTBEAT_MS
    o:initialise()
    o:addToUIManager()
    o:setAlwaysOnTop(true)
    o:setWantKeyEvents(true)
    AegisZoneEditor.instance = o
    if AegisWindow.instance then
        AegisWindow.instance:setVisible(false)
    end
    return o
end

-- everything that reacts to the mouse happens here, render only draws.
-- The lock was already granted at start (AegisPageZones:startEditor), it
-- just gets renewed while the editor stays open, otherwise it expires
function AegisZoneEditor:update()
    ISPanel.update(self)
    local tx, ty = mouseTile()
    if tx and self.tool == "rect" then
        if self.dragging and self.dragX then
            self:updateDrag(tx, ty)
        end
    elseif tx then
        if tx ~= self.curX or ty ~= self.curY then
            self.curX, self.curY = tx, ty
            self.cursorOutline = rectOutline({ x = tx, y = ty, w = 1, h = 1 })
        end
        -- only the newly crossed tiles, nothing when the cursor stands still
        if self.dragging and (tx ~= self.lastX or ty ~= self.lastY) then
            self:applyBrush(tx, ty)
        end
    end
    if self.outlineDirty then
        self.outline = mergeUnitEdges(self.edgeSet)
        self.outlineDirty = false
    end
    if self.partsDirty and not self.dragging then
        self.partsCount = #decompose(self.tiles)
        self.partsDirty = false
    end
    -- a new area belongs to nobody yet, no lock needed
    if self.newMode then return end
    local now = getTimestampMs()
    if now < self.nextLockAt then return end
    self.nextLockAt = now + LOCK_HEARTBEAT_MS
    local p = getPlayer()
    if p then
        sendClientCommand(p, AegisShared.MODULE, "zoneLock", { x = self.entry.x, y = self.entry.y })
    end
end

function AegisZoneEditor:finish()
    if not self.newMode then
        local p = getPlayer()
        if p then
            sendClientCommand(p, AegisShared.MODULE, "zoneUnlock", { x = self.entry.x, y = self.entry.y })
        end
    end
    self:removeFromUIManager()
    AegisZoneEditor.instance = nil
    if AegisWindow.instance then
        AegisWindow.instance:setVisible(true)
    end
end

-- set/clear a tile and only touch the four affected boundary edges
function AegisZoneEditor:setTile(tx, ty, place)
    local edges = {
        { tx, ty - 1, tx, ty, tx + 1, ty },
        { tx, ty + 1, tx, ty + 1, tx + 1, ty + 1 },
        { tx - 1, ty, tx, ty, tx, ty + 1 },
        { tx + 1, ty, tx + 1, ty, tx + 1, ty + 1 },
    }
    for _, n in ipairs(edges) do
        local key = n[3] .. "|" .. n[4] .. "|" .. n[5] .. "|" .. n[6]
        local neighbor = hasTile(self.tiles, n[1], n[2])
        -- the edge sits between own tile and neighbor: it exists
        -- exactly when only one of the two sides is filled
        if (place and neighbor) or (not place and not neighbor) then
            self.edgeSet[key] = nil
        else
            self.edgeSet[key] = { n[3], n[4], n[5], n[6] }
        end
    end
    if place then
        local column = self.tiles[tx]
        if not column then
            column = {}
            self.tiles[tx] = column
        end
        column[ty] = true
        self.count = self.count + 1
    else
        self.tiles[tx][ty] = nil
        self.count = self.count - 1
    end
    self.outlineDirty = true
    self.partsDirty = true
end

function AegisZoneEditor:toggleTile(tx, ty)
    if self.erasing then
        -- every tile is erasable: the server rebuilds the zone from the
        -- remaining set and keeps the old anchor whenever it still fits
        if hasTile(self.tiles, tx, ty) then
            self:setTile(tx, ty, false)
        end
    else
        if not hasTile(self.tiles, tx, ty) then
            if self.count >= MAX_BRUSH_TILES then
                self:warnBrush()
                return
            end
            self:setTile(tx, ty, true)
        end
    end
end

-- throttle the warning, otherwise a drag at the limit spams a toast every frame
function AegisZoneEditor:warnBrush()
    local now = getTimestampMs()
    if now < (self.warnUntil or 0) then return end
    self.warnUntil = now + 1500
    Aegis.showToast(getText("UI_Aegis_ZoneBrushMax"))
end

-- clamp and store the dragged rectangle, outline only on a real change
function AegisZoneEditor:updateDrag(mx, my)
    local x1, x2 = math.min(self.dragX, mx), math.max(self.dragX, mx)
    local y1, y2 = math.min(self.dragY, my), math.max(self.dragY, my)
    x1, y1 = math.max(0, x1), math.max(0, y1)
    if x2 - x1 + 1 > MAX_EDGE then x2 = x1 + MAX_EDGE - 1 end
    if y2 - y1 + 1 > MAX_EDGE then y2 = y1 + MAX_EDGE - 1 end
    local r = self.dragRect
    if r and r.x == x1 and r.y == y1 and r.w == x2 - x1 + 1 and r.h == y2 - y1 + 1 then return end
    self.dragRect = { x = x1, y = y1, w = x2 - x1 + 1, h = y2 - y1 + 1 }
    self.dragOutline = rectOutline(self.dragRect)
end

-- does the rectangle overlap the set or share an edge with it
-- (diagonal touch does not count, same rule as the server fusion)
function AegisZoneEditor:touchesSet(r)
    for tx = r.x - 1, r.x + r.w do
        for ty = r.y - 1, r.y + r.h do
            local insideX = tx >= r.x and tx < r.x + r.w
            local insideY = ty >= r.y and ty < r.y + r.h
            -- the ring around the rectangle without its corners, plus the
            -- rectangle itself for the overlap case
            if (insideX or insideY) and hasTile(self.tiles, tx, ty) then return true end
        end
    end
    return false
end

-- releasing the mouse commits the dragged rectangle to the set: added
-- on a left drag, carved out again on a right drag. The set changes
-- only here, never per frame
function AegisZoneEditor:commitRect(erase)
    local r = self.dragRect
    self.dragRect, self.dragOutline = nil, nil
    self.dragX, self.dragY = nil, nil
    if not r then return end
    if erase then
        -- the original zone area survives the eraser here, shrinking a
        -- zone is the brush's job
        for tx = r.x, r.x + r.w - 1 do
            for ty = r.y, r.y + r.h - 1 do
                if hasTile(self.tiles, tx, ty)
                    and not (self.baseTiles and hasTile(self.baseTiles, tx, ty)) then
                    self:setTile(tx, ty, false)
                end
            end
        end
        return
    end
    -- everything after the first shape has to dock on; a detached
    -- rectangle flashes red and is dropped right away instead of
    -- bouncing off the server later
    if self.count > 0 and not self:touchesSet(r) then
        self.flashRect = r
        self.flashOutline = rectOutline(r)
        self.flashUntil = getTimestampMs() + 1200
        Aegis.showToast(getText("UI_Aegis_ZoneDock"))
        return
    end
    local missing = 0
    for tx = r.x, r.x + r.w - 1 do
        for ty = r.y, r.y + r.h - 1 do
            if not hasTile(self.tiles, tx, ty) then missing = missing + 1 end
        end
    end
    if missing == 0 then return end
    if self.count + missing > MAX_BRUSH_TILES then
        self:warnBrush()
        return
    end
    for tx = r.x, r.x + r.w - 1 do
        for ty = r.y, r.y + r.h - 1 do
            if not hasTile(self.tiles, tx, ty) then
                self:setTile(tx, ty, true)
            end
        end
    end
end

-- rasterize a line from the last to the current mouse tile, otherwise
-- the stroke tears on fast mouse movement
function AegisZoneEditor:applyBrush(tx, ty)
    local lx, ly = self.lastX or tx, self.lastY or ty
    local steps = math.max(math.abs(tx - lx), math.abs(ty - ly))
    for i = 0, steps do
        local t = steps == 0 and 0 or i / steps
        self:toggleTile(math.floor(lx + (tx - lx) * t + 0.5), math.floor(ly + (ty - ly) * t + 0.5))
    end
    self.lastX, self.lastY = tx, ty
end

function AegisZoneEditor:render()
    local c = Aegis.col
    local z = playerLevel()
    local label
    -- other zones of the same owner: faint gold outline, clearly weaker
    -- than the area being edited, and never part of the tile set
    for _, n in ipairs(self.neighbors or {}) do
        drawOutline(self, makeView(n.x, n.y, z), n.outline, 0.35, c.gold)
    end
    -- the union of the whole set as one shape, for both tools
    drawOutline(self, makeView(self.entry.x, self.entry.y, z), self.outline, 0.95, c.goldHi)
    if self.tool == "rect" then
        -- rubber band while dragging, red while it is set to erase
        if self.dragRect then
            drawOutline(self, makeView(self.dragRect.x, self.dragRect.y, z), self.dragOutline,
                0.9, self.erasing and c.danger or c.gold)
        end
        -- a rectangle refused for not docking flashes red where it was
        if self.flashOutline and getTimestampMs() < (self.flashUntil or 0) then
            drawOutline(self, makeView(self.flashRect.x, self.flashRect.y, z), self.flashOutline, 0.95, c.danger)
        end
    else
        -- mark the cursor tile, red while erasing
        if self.curX then
            drawOutline(self, makeView(self.curX, self.curY, z), self.cursorOutline,
                0.9, self.erasing and c.danger or c.gold)
        end
    end
    label = self.count .. " " .. getText("UI_Aegis_ZoneTiles")
    if (self.partsCount or 0) > 1 then
        label = label .. "  " .. self.partsCount .. " " .. getText("UI_Aegis_ZoneParts")
    end
    if self.tool == "rect" and self.dragRect then
        label = label .. "  " .. self.dragRect.w .. "x" .. self.dragRect.h
    end

    local midX = math.floor(self.width / 2)
    local name = self.entry.title ~= "" and self.entry.title or self.entry.owner
    -- anchor in the header: two zones of one owner often read identically,
    -- the coordinates say which one is actually being edited
    local header = name .. "  " .. label
    if not self.newMode then
        header = name .. "  " .. self.entry.x .. "," .. self.entry.y .. "  " .. label
    end
    local hint
    if self.tool ~= "rect" then
        hint = getText("UI_Aegis_ZoneBrushHint")
    elseif self.newMode then
        hint = getText("UI_Aegis_ZoneHint")
    else
        -- an existing zone: appended rectangles are erasable, the zone
        -- itself is not, say so
        hint = getText("UI_Aegis_ZoneHintKeep")
    end
    -- only worth saying when there is something to dock onto
    local mergeHint = #(self.neighbors or {}) > 0 and getText("UI_Aegis_ZoneMergeHint") or nil
    local w = math.max(Aegis.strW(UIFont.Medium, header), Aegis.strW(UIFont.Small, hint))
    if mergeHint then
        w = math.max(w, Aegis.strW(UIFont.Small, mergeHint))
    end
    w = w + 48
    local lineH = Aegis.fontH(UIFont.Small)
    local boxH = 62 + (mergeHint and (lineH + 4) or 0)
    Aegis.roundFrame(self, midX - math.floor(w / 2), 24, w, boxH, 10, 0.95, c.gold, c.dark)
    Aegis.textCentre(self, header, midX, 32, UIFont.Medium, c.goldHi)
    local hintY = 36 + Aegis.fontH(UIFont.Medium)
    Aegis.textCentre(self, hint, midX, hintY, UIFont.Small, c.muted)
    if mergeHint then
        Aegis.textCentre(self, mergeHint, midX, hintY + lineH + 2, UIFont.Small, c.goldDim)
    end
end

function AegisZoneEditor:onMouseDown(x, y)
    self.erasing = false
    self.lastX, self.lastY = nil, nil
    if self.tool == "rect" then
        local tx, ty = mouseTile()
        if not tx then return end
        self.dragX, self.dragY = tx, ty
        self:updateDrag(tx, ty)
    end
    self.dragging = true
end

function AegisZoneEditor:onMouseUp(x, y)
    if self.tool == "rect" and self.dragging and not self.erasing then
        self:commitRect(false)
    end
    self.dragging = false
    self.lastX, self.lastY = nil, nil
end

-- a release off screen never commits, the drag just ends
function AegisZoneEditor:onMouseUpOutside(x, y)
    self.dragging = false
    self.erasing = false
    self.dragRect, self.dragOutline = nil, nil
    self.dragX, self.dragY = nil, nil
    self.lastX, self.lastY = nil, nil
end

function AegisZoneEditor:onRightMouseDown(x, y)
    self.erasing = true
    self.lastX, self.lastY = nil, nil
    if self.tool == "rect" then
        local tx, ty = mouseTile()
        if not tx then return end
        self.dragX, self.dragY = tx, ty
        self:updateDrag(tx, ty)
    end
    self.dragging = true
end

function AegisZoneEditor:onRightMouseUp(x, y)
    if self.tool == "rect" and self.dragging and self.erasing then
        self:commitRect(true)
    end
    self.dragging = false
    self.erasing = false
    self.lastX, self.lastY = nil, nil
end

-- flood fill over the tile set: the operator rule says a zone is ONE
-- connected shape, and the eraser can cut a previously attached piece off
local function setConnected(set)
    local sx, sy
    local total = 0
    for tx, column in pairs(set) do
        for ty in pairs(column) do
            total = total + 1
            if not sx then sx, sy = tx, ty end
        end
    end
    if total <= 1 then return true end
    local seen = { [sx .. "," .. sy] = true }
    local queue = { { sx, sy } }
    local found = 1
    while #queue > 0 do
        local cell = table.remove(queue)
        local cx, cy = cell[1], cell[2]
        local around = { { cx + 1, cy }, { cx - 1, cy }, { cx, cy + 1 }, { cx, cy - 1 } }
        for _, n in ipairs(around) do
            local key = n[1] .. "," .. n[2]
            if not seen[key] and hasTile(set, n[1], n[2]) then
                seen[key] = true
                found = found + 1
                table.insert(queue, n)
            end
        end
    end
    return found == total
end

function AegisZoneEditor:apply()
    local p = getPlayer()
    if not p then return end
    -- one send per session: while the verdict is pending, Enter is inert
    if self.awaitingApply then return end
    -- the operator rule again at the very end: erasing may have cut an
    -- attached piece loose, a zone is one connected shape or nothing
    if not setConnected(self.tiles) then
        Aegis.showToast(getText("UI_Aegis_ZoneDock"))
        return
    end
    -- the set is the whole wanted zone. Maximal rectangles mean two
    -- touching pieces come out as one, so the server can build a single
    -- united safehouse
    local rects = decompose(self.tiles)
    -- an empty area is never a delete: the server rejects it as bad data
    if #rects == 0 then
        Aegis.showToast(getText("UI_Aegis_ZoneBadData"))
        return
    end
    -- the biggest rectangle becomes the main, the rest are annexes
    if #rects > MAX_PARTS + 1 then
        Aegis.showToast(getText("UI_Aegis_ZoneTooJagged"))
        return
    end
    if self.newMode then
        if #rects == 1 then
            local n = rects[1]
            print("[Aegis] zone send shNew owner=" .. tostring(self.entry.owner)
                .. " rect=" .. n.x .. "," .. n.y .. " " .. n.w .. "x" .. n.h)
            sendClientCommand(p, AegisShared.MODULE, "shNew", {
                owner = self.entry.owner, x = n.x, y = n.y, w = n.w, h = n.h,
            })
        else
            print("[Aegis] zone send shNewShape owner=" .. tostring(self.entry.owner)
                .. " rects=" .. #rects .. " tiles=" .. self.count)
            sendClientCommand(p, AegisShared.MODULE, "shNewShape", {
                owner = self.entry.owner, rects = rects,
            })
        end
        self.awaitingApply = true
        return
    end
    -- the server only applies an edit while the admin stands on the old
    -- zone or the wanted area; caught here so the drawn set survives
    local px, py = math.floor(p:getX()), math.floor(p:getY())
    if px and not hasTile(self.tiles, px, py)
        and not (self.baseTiles and hasTile(self.baseTiles, px, py)) then
        Aegis.showToast(getText("UI_Aegis_ZoneOutside"))
        return
    end
    -- full marks the new protocol: rects is the entire area. Without it an
    -- old server would read the same field as the annex list
    print("[Aegis] zone send shShape anchor=" .. self.entry.x .. "," .. self.entry.y
        .. " rects=" .. #rects .. " tiles=" .. self.count .. " full=true")
    sendClientCommand(p, AegisShared.MODULE, "shShape", {
        mainX = self.entry.x, mainY = self.entry.y,
        rects = rects, full = true,
    })
    -- the server can still refuse (overlap, locked neighbour, registry,
    -- fusion ceilings); the editor closes only on ok so a refusal keeps
    -- the drawn session alive
    self.awaitingApply = true
end

function AegisZoneEditor:onRightMouseUpOutside(x, y)
    -- same as a regular right release: without this the eraser keeps
    -- painting after the button came up outside the game window
    if self.onRightMouseUp then self:onRightMouseUp(x, y) end
end

-- consume the keys ourselves, otherwise ESC also opens the pause menu
function AegisZoneEditor:isKeyConsumed(key)
    return key == Keyboard.KEY_ESCAPE or key == Keyboard.KEY_RETURN
end

function AegisZoneEditor:onKeyPress(key)
    if key == Keyboard.KEY_RETURN then
        self:apply()
        GameKeyboard.eatKeyPress(key)
    elseif key == Keyboard.KEY_ESCAPE then
        self:finish()
        GameKeyboard.eatKeyPress(key)
    end
end

-- ==================================================================
-- Page
-- ==================================================================

function AegisPageZones.create(window, x, y, w, h)
    local o = ISPanel:new(x, y, w, h)
    setmetatable(o, AegisPageZones)
    AegisPageZones.__index = AegisPageZones
    o.background = false
    o.window = window
    o.entries = {}
    o.nextPoll = 0
    AegisPageZones.instance = o
    return o
end

-- the list used to only hold the state from the last page switch/click;
-- if another admin changed something, you only saw it after your own
-- reload. Same polling pattern as the log page (AegisPageLogs)
function AegisPageZones:update()
    ISPanel.update(self)
    self:updateButtons()
    if not self:isVisible() or not AegisWindow.instance then return end
    local now = getTimestampMs()
    if now < self.nextPoll then return end
    self.nextPoll = now + POLL_MS
    self:request()
end

function AegisPageZones:createChildren()
    local pad = 20

    self.refreshBtn = AegisButton:new(pad + LIST_W - 32, pad + 7, 30, 28, nil, "refresh", self, AegisPageZones.request)
    self:addChild(self.refreshBtn)

    self.list = ISScrollingListBox:new(pad + 1, pad + 44, LIST_W - 2, self.height - pad * 2 - 46)
    self.list:initialise()
    self.list:instantiate()
    self.list.itemheight = ROW_H
    self.list.drawBorder = false
    self.list.backgroundColor = { r = 0, g = 0, b = 0, a = 0 }
    self.list.doDrawItem = AegisPageZones.drawRow
    self.list:setOnMouseDownFunction(self, AegisPageZones.onSelectRow)
    self:addChild(self.list)

    local dx = pad + LIST_W + 20
    local dw = self.width - dx - pad
    self.brushBtn = AegisButton:new(dx + 14, pad + 46, dw - 28, 38, getText("UI_Aegis_ZoneBrush"), "wand", self, AegisPageZones.onBrush)
    self.brushBtn.style = "gold"
    self.brushBtn.tooltip = getText("UI_Aegis_ZoneBrushTooltip")
    self:addChild(self.brushBtn)

    self.editBtn = AegisButton:new(dx + 14, pad + 92, dw - 28, 38, getText("UI_Aegis_ZoneEdit"), "pin", self, AegisPageZones.onEdit)
    self.editBtn.tooltip = getText("UI_Aegis_ZoneHintKeep")
    self:addChild(self.editBtn)

    self.overlayToggle = AegisToggle:new(dx + 14, pad + 140, dw - 28, 30, getText("UI_Aegis_ZoneOverlay"), "eye", self, AegisPageZones.onOverlay)
    self.overlayToggle:setChecked(AegisZoneOverlay.instance ~= nil)
    self:addChild(self.overlayToggle)

    self.backupsBtn = AegisButton:new(dx + 14, pad + 184, dw - 28, 38, getText("UI_Aegis_Backups"), "shield", self, AegisPageZones.onBackups)
    self.backupsBtn.tooltip = getText("UI_Aegis_BackupTooltip")
    self:addChild(self.backupsBtn)

    self.newBtn = AegisButton:new(dx + 14, pad + 238, dw - 28, 38, getText("UI_Aegis_ZoneNew"), "home", self, AegisPageZones.onNew)
    self.newBtn.tooltip = getText("UI_Aegis_ZoneNewTooltip")
    self:addChild(self.newBtn)
end

function AegisPageZones.request(self)
    local p = getPlayer()
    if not p then return end
    sendClientCommand(p, AegisShared.MODULE, "shList", {})
end

function AegisPageZones:onShow()
    self:request()
end

-- The vanilla client keeps its own SafeHouse list in step via single
-- packets: SafehouseSync creates any rectangle it cannot match by exact
-- geometry, SafehouseRelease removes by onlineID and is dropped whole
-- when the ID cannot be resolved at arrival (bytecode: SafehouseID
-- isConsistent). Both packets travel RELIABLE without ordering, so a
-- reshuffled or discarded removal leaves a stale rectangle behind that
-- vanilla admin views (debug safehouse fill draws per rectangle) show
-- as an overlapping ghost until reconnect rebuilds the list. The zone
-- list poll carries the authoritative server state every few seconds,
-- so anything local the server does not know gets dropped here. Client
-- side SafeHouse.removeSafeHouse only pulls the list entry and fires
-- OnSafehousesChanged, no packet leaves (bytecode verified). A grace of
-- one poll protects rectangles a running edit created after the reply
-- left the server: they are only removed when two polls in a row miss
-- them, and a fresh poll always reports them again before that
-- pending misses live at module level: the sweep must keep working after
-- the page closed, ghosts show up exactly when the admin looks at the
-- world instead of the panel
local ghostPending = {}

function AegisPageZones.reconcileGhosts(entries, stray, complete)
    if not isClient() then return end
    -- a truncated payload must never drive removals (one bad engine read
    -- server side would otherwise read as a pile of ghosts)
    if complete ~= true then
        ghostPending = {}
        return
    end
    local known = {}
    for _, e in ipairs(entries) do
        known[e.x .. "," .. e.y .. "," .. e.w .. "," .. e.h] = true
        for _, r in ipairs(e.parts) do
            known[r.x .. "," .. r.y .. "," .. r.w .. "," .. r.h] = true
        end
    end
    -- orphan annexes of a main removed outside the panel: alive until the
    -- guard reaps them, the server hands them over separately
    for _, r in ipairs(stray or {}) do
        known[r.x .. "," .. r.y .. "," .. r.w .. "," .. r.h] = true
    end
    local pending = ghostPending
    local nextPending = {}
    local java = nil
    pcall(function() java = SafeHouse.getSafehouseList() end)
    if not java then
        ghostPending = {}
        return
    end
    local count = 0
    pcall(function() count = java:size() end)
    local ghosts = {}
    for i = 0, count - 1 do
        local sh = nil
        pcall(function() sh = java:get(i) end)
        local key = nil
        if sh then
            pcall(function()
                key = sh:getX() .. "," .. sh:getY() .. "," .. sh:getW() .. "," .. sh:getH()
            end)
        end
        if key and not known[key] then
            -- replies travel reliable but unordered: two stale replies in
            -- a row can both miss a freshly built rectangle. Removal needs
            -- three consecutive misses spread over at least 8 seconds
            local seen = pending[key]
            local misses = (seen and seen.misses or 0) + 1
            local firstMiss = seen and seen.firstMiss or getTimestampMs()
            if misses >= 3 and getTimestampMs() - firstMiss >= 8000 then
                table.insert(ghosts, { sh = sh, key = key })
            else
                nextPending[key] = { misses = misses, firstMiss = firstMiss }
            end
        end
    end
    for _, g in ipairs(ghosts) do
        local ok = pcall(function() SafeHouse.removeSafeHouse(g.sh) end)
        print("[Aegis] zone ghost rectangle dropped locally: " .. g.key
            .. (ok and "" or " (removal call failed)"))
    end
    ghostPending = nextPending
end

function AegisPageZones:setList(list, stray, complete)
    -- read network tables defensively: pairs plus type check, ipairs
    -- is unreliable on received tables (muteSync pattern)
    local cleaned = {}
    local kept = self.outlineCache or {}
    local fresh = {}
    if type(list) == "table" then
        for _, e in pairs(list) do
            if type(e) == "table" and tonumber(e.x) then
                local players = {}
                if type(e.players) == "table" then
                    for _, s in pairs(e.players) do
                        if type(s) == "string" then table.insert(players, s) end
                    end
                end
                local parts = {}
                if type(e.parts) == "table" then
                    for _, r in pairs(e.parts) do
                        if type(r) == "table" and tonumber(r.x) then
                            table.insert(parts, {
                                x = math.floor(tonumber(r.x)), y = math.floor(tonumber(r.y) or 0),
                                w = math.floor(tonumber(r.w) or 1), h = math.floor(tonumber(r.h) or 1),
                            })
                        end
                    end
                end
                local entry = {
                    x = math.floor(tonumber(e.x)), y = math.floor(tonumber(e.y) or 0),
                    w = math.floor(tonumber(e.w) or 1), h = math.floor(tonumber(e.h) or 1),
                    owner = tostring(e.owner or ""), title = tostring(e.title or ""),
                    players = players, parts = parts,
                    lockedBy = tostring(e.lockedBy or ""),
                }
                -- outlines survive a poll that changed nothing, so a zone
                -- of a few hundred tiles is walked once, not every 3 s
                local key = shapeKey(entry)
                local outline = fresh[key] or kept[key]
                if not outline then
                    -- plain rectangles need no tile expansion
                    if #parts == 0 then
                        outline = rectOutline(entry)
                    else
                        outline = setOutline(tileSet(formRects(entry)))
                    end
                end
                entry.outline = outline
                fresh[key] = outline
                table.insert(cleaned, entry)
            end
        end
    end
    self.outlineCache = fresh
    self.entries = cleaned
    AegisPageZones.reconcileGhosts(cleaned, stray, complete)
    AegisZoneOverlay.data = self.entries
    -- an open editor holds the neighbour outlines it got when it opened;
    -- refresh them so a zone changed meanwhile is not drawn as it was
    local editor = AegisZoneEditor and AegisZoneEditor.instance
    if editor and editor.entry then
        editor.neighbors = self:neighborsFor(editor.entry, editor.entry.owner)
    end
    self:fillList()
end

-- rebuilt from self.entries alone, so folding an owner open or closed
-- does not need a fresh server answer
function AegisPageZones:fillList()
    local prev = self.list.items[self.list.selected]
    local prevKey = prev and prev.item and not prev.item.groupRow
        and (prev.item.x .. "|" .. prev.item.y) or nil
    self.list:clear()
    self.list.selected = -1
    -- one row per owner, the zones themselves only appear when that owner
    -- is opened. A single owner can hold a dozen separate properties and
    -- used to push everyone else off the list entirely, one name filling
    -- the whole panel. Same shape as the
    -- safehouse list on the factions page
    self.zoneOpen = self.zoneOpen or {}
    local order, byOwner = {}, {}
    for _, e in ipairs(self.entries) do
        local owner = e.owner ~= "" and e.owner or "?"
        if not byOwner[owner] then
            byOwner[owner] = {}
            table.insert(order, owner)
        end
        table.insert(byOwner[owner], e)
    end
    table.sort(order, function(a, b) return a:lower() < b:lower() end)
    for _, owner in ipairs(order) do
        local list = byOwner[owner]
        local tiles, locked = 0, false
        for _, e in ipairs(list) do
            local t = zoneStats(e)
            tiles = tiles + t
            if e.lockedBy ~= "" then locked = true end
        end
        self.list:addItem(owner, { groupRow = true, owner = owner, count = #list,
            tiles = tiles, locked = locked, open = self.zoneOpen[owner] == true })
        if self.zoneOpen[owner] then
            for _, e in ipairs(list) do
                local i = #self.list.items + 1
                self.list:addItem(e.owner, e)
                if prevKey and (e.x .. "|" .. e.y) == prevKey then
                    self.list.selected = i
                end
            end
        end
    end
    self:updateButtons()
end

-- owner rows fold open and closed, they are no zone and no target for
-- the edit buttons
function AegisPageZones.onSelectRow(self, e)
    if e and e.groupRow then
        self.zoneOpen = self.zoneOpen or {}
        self.zoneOpen[e.owner] = not self.zoneOpen[e.owner]
        self.list.selected = -1
        self:fillList()
        return
    end
    self:updateButtons()
end

function AegisPageZones.drawRow(list, y, item, alt)
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
    if e.groupRow then
        Aegis.icon(list, e.open and "minus" or "plus", 12, y + 8, 12, 1, c.gold)
        Aegis.text(list, Aegis.fitText(e.owner, UIFont.Small, list:getWidth() - 130), 32, y + 5, UIFont.Small, c.text)
        local gy = y + 7 + Aegis.fontH(UIFont.Small)
        local zones = e.count .. " " .. getText(e.count == 1 and "UI_Aegis_ZoneOne" or "UI_Aegis_ZoneMany")
        Aegis.text(list, zones, 32, gy, UIFont.Small, c.muted)
        Aegis.textRight(list, e.tiles .. " " .. getText("UI_Aegis_ZoneTiles"),
            list:getWidth() - 12, y + 5, UIFont.Small, c.goldDim)
        if e.locked then
            Aegis.textRight(list, getText("UI_Aegis_ZoneLockedShort"), list:getWidth() - 12, gy, UIFont.Small, c.danger)
        end
        return y + ROW_H
    end
    local locked = e.lockedBy ~= ""
    local name = e.title ~= "" and e.title or e.owner
    -- area first, the piece count is the exception and stays quiet
    local tiles, pieces = zoneStats(e)
    local area = tiles .. " " .. getText("UI_Aegis_ZoneTiles")
    local partsText = pieces > 1 and (pieces .. " " .. getText("UI_Aegis_ZoneParts")) or nil
    local partsW = partsText and (Aegis.strW(UIFont.Small, partsText) + 10) or 0
    local rightW = Aegis.strW(UIFont.Small, area) + partsW
    Aegis.text(list, Aegis.fitText(name, UIFont.Small, list:getWidth() - rightW - 34), 14, y + 5, UIFont.Small, sel and c.text or c.muted)
    local subWidth = locked and (list:getWidth() - 150) or (list:getWidth() - 24)
    Aegis.text(list, Aegis.fitText(e.owner .. "  (" .. #e.players .. ")", UIFont.Small, subWidth),
        14, y + 7 + Aegis.fontH(UIFont.Small), UIFont.Small, c.muted)
    Aegis.textRight(list, area, list:getWidth() - 12 - partsW, y + 5, UIFont.Small, c.goldDim)
    if partsText then
        Aegis.textRight(list, partsText, list:getWidth() - 12, y + 5, UIFont.Small, c.muted, 0.75)
    end
    if locked then
        Aegis.textRight(list, getText("UI_Aegis_ZoneLocked", e.lockedBy), list:getWidth() - 12,
            y + 7 + Aegis.fontH(UIFont.Small), UIFont.Small, c.danger)
    end
    return y + ROW_H
end

function AegisPageZones:selectedZone()
    local item = self.list.items[self.list.selected]
    local e = item and item.item or nil
    -- an owner row is a fold, never a zone
    if e and e.groupRow then return nil end
    return e
end

-- disable buttons while the selected zone is open at another admin, and
-- while nothing but an owner row is selected
function AegisPageZones:updateButtons()
    local e = self:selectedZone()
    local usable = e ~= nil and e.lockedBy == ""
    if self.editBtn then self.editBtn:setEnabled(usable) end
    if self.brushBtn then self.brushBtn:setEnabled(usable) end
end

-- outlines of the owner's other zones for the editor. Compared by anchor,
-- not by table, because polling replaces the entries while an editor runs
function AegisPageZones:neighborsFor(entry, owner)
    local out = {}
    local who = owner or (entry and entry.owner) or ""
    if who == "" then return out end
    for _, e in ipairs(self.entries or {}) do
        local same = entry ~= nil and e.x == entry.x and e.y == entry.y
        if e.owner == who and not same and e.outline then
            table.insert(out, { x = e.x, y = e.y, outline = e.outline })
        end
    end
    return out
end

-- requests the edit lock from the server before the editor opens;
-- the answer arrives asynchronously via the OnServerCommand handler below
function AegisPageZones:startEditor(entry, tool)
    local p = getPlayer()
    if not p then return end
    -- token against stale answers: if the admin clicks another zone
    -- before the server answers, the old request must not hit the
    -- new pendingEntry anymore
    self.lockToken = (self.lockToken or 0) + 1
    local thisToken = self.lockToken
    self.pendingEntry = entry
    self.pendingTool = tool
    self.pendingToken = thisToken
    sendClientCommand(p, AegisShared.MODULE, "zoneLock", { x = entry.x, y = entry.y, token = thisToken })
end

function AegisPageZones.onEdit(self)
    local e = self:selectedZone()
    if not e then return end
    self:startEditor(e, "rect")
end

function AegisPageZones.onBrush(self)
    local e = self:selectedZone()
    if not e then return end
    -- requirement: only someone standing inside the zone may edit; the
    -- server checks this again on apply
    local p = getPlayer()
    if p then
        local px, py = math.floor(p:getX()), math.floor(p:getY())
        if not hasTile(tileSet(formRects(e)), px, py) then
            Aegis.showToast(getText("UI_Aegis_ZoneOutside"))
            return
        end
    end
    self:startEditor(e, "brush")
end

function AegisPageZones.onNew(self)
    AegisZoneNew.show()
end

-- called by the owner picker, starts the editor without an existing zone
-- and without an edit lock; the entry rect only anchors view and header,
-- the area itself starts empty and is drawn or painted from scratch
function AegisPageZones.startNew(owner, tool)
    local p = getPlayer()
    if not p then return end
    local x, y = math.floor(p:getX()) - 2, math.floor(p:getY()) - 2
    local entry = { x = x, y = y, w = 5, h = 5, owner = owner, title = "", players = {}, parts = {} }
    local page = AegisPageZones.instance
    AegisZoneEditor.start(entry, tool, true, page and page:neighborsFor(nil, owner) or {})
end

function AegisPageZones.onOverlay(self, checked)
    AegisZoneOverlay.show(checked)
    if checked then self:request() end
end

function AegisPageZones.onBackups(self)
    local e = self:selectedZone()
    if not e then return end
    AegisBackup.show(e)
end

function AegisPageZones:prerender()
    local c = Aegis.col
    local pad = 20

    Aegis.roundFrame(self, pad, pad, LIST_W, self.height - pad * 2, 10, 1, c.line, c.panel)
    Aegis.icon(self, "home", pad + 14, pad + 12, 15, 1, c.gold)
    Aegis.text(self, getText("UI_Aegis_NavZones"), pad + 36, pad + 10, UIFont.Medium, c.text)

    local dx = pad + LIST_W + 20
    local dw = self.width - dx - pad
    Aegis.roundFrame(self, dx, pad, dw, self.height - pad * 2, 10, 1, c.line, c.panel)
    local e = self:selectedZone()
    if e then
        Aegis.text(self, e.title ~= "" and e.title or e.owner, dx + 14, pad + 10, UIFont.Medium, c.text)
        -- anchor stays, then the area of the whole zone; pieces are a footnote
        local tiles, pieces = zoneStats(e)
        local size = e.x .. "," .. e.y .. "  " .. tiles .. " " .. getText("UI_Aegis_ZoneTiles")
        if pieces > 1 then
            size = size .. "  " .. pieces .. " " .. getText("UI_Aegis_ZoneParts")
        end
        Aegis.textRight(self, size, dx + dw - 14, pad + 14, UIFont.Small, c.goldDim)
        if e.lockedBy ~= "" then
            Aegis.text(self, getText("UI_Aegis_ZoneLockedBy", e.lockedBy), dx + 14, pad + 36, UIFont.Small, c.danger)
        end
        -- below the last button of the column (newBtn ends at pad + 276);
        -- the old fixed 240 went stale when the button column grew and the
        -- members block slid underneath the buttons
        local sy = pad + 290
        Aegis.text(self, getText("UI_Aegis_ZoneMembers"), dx + 14, sy, UIFont.Small, c.muted)
        sy = sy + Aegis.fontH(UIFont.Small) + 6
        local lineH = Aegis.fontH(UIFont.Small) + 4
        for i, name in ipairs(e.players) do
            if sy + lineH > self.height - pad - 20 then
                Aegis.text(self, "+" .. (#e.players - i + 1), dx + 26, sy, UIFont.Small, c.muted)
                break
            end
            Aegis.text(self, name .. (name == e.owner and "  *" or ""), dx + 26, sy, UIFont.Small, c.text)
            sy = sy + lineH
        end
    elseif #self.entries == 0 then
        -- below the button column instead of the panel centre: on a small
        -- window the centre lands right on the "new zone" button
        local emptyY = math.max(math.floor(self.height / 2), pad + 290)
        emptyY = math.min(emptyY, self.height - pad - Aegis.fontH(UIFont.Medium))
        Aegis.textCentre(self, getText("UI_Aegis_ZoneNone"), dx + math.floor(dw / 2), emptyY, UIFont.Medium, c.muted)
    end
end

-- server responses, in solo they arrive over the same event path
Events.OnServerCommand.Add(function(module, command, args)
    if module ~= "AegisAdmin" then return end
    local page = AegisPageZones.instance
    if command == "shList" then
        if page and args then
            page:setList(args.list, args.stray, args.complete)
        elseif args then
            -- page closed: the reply still feeds the ghost sweep, the
            -- world view is exactly where stale rectangles hurt
            local cleaned = {}
            for _, e in pairs(type(args.list) == "table" and args.list or {}) do
                if type(e) == "table" and tonumber(e.x) then
                    local parts = {}
                    for _, r in pairs(type(e.parts) == "table" and e.parts or {}) do
                        if type(r) == "table" and tonumber(r.x) then
                            table.insert(parts, { x = math.floor(tonumber(r.x)), y = math.floor(tonumber(r.y) or 0),
                                w = math.floor(tonumber(r.w) or 1), h = math.floor(tonumber(r.h) or 1) })
                        end
                    end
                    table.insert(cleaned, { x = math.floor(tonumber(e.x)), y = math.floor(tonumber(e.y) or 0),
                        w = math.floor(tonumber(e.w) or 1), h = math.floor(tonumber(e.h) or 1), parts = parts })
                end
            end
            AegisPageZones.reconcileGhosts(cleaned, args.stray, args.complete)
        end
    elseif command == "shShape" or command == "shNew" or command == "shNewShape" then
        if args then
            print("[Aegis] zone reply " .. command .. ": "
                .. (args.ok and "ok" or tostring(args.reason or "failed")))
        end
        -- an editor waiting for its verdict closes on success and stays
        -- open on a refusal, so the drawn session survives the toast
        local editor = AegisZoneEditor.instance
        if editor and editor.awaitingApply then
            editor.awaitingApply = false
            if args and args.ok then editor:finish() end
        end
        if args and args.ok then
            Aegis.showToast(getText("UI_Aegis_ZoneSaved"))
        elseif args and args.reason == "overlap" then
            Aegis.showToast(getText("UI_Aegis_ZoneOverlap"))
        elseif args and args.reason == "outside" then
            Aegis.showToast(getText("UI_Aegis_ZoneOutside"))
        elseif args and args.reason == "jagged" then
            Aegis.showToast(getText("UI_Aegis_ZoneTooJagged"))
        elseif args and args.reason == "data" then
            Aegis.showToast(getText("UI_Aegis_ZoneBadData"))
        elseif args and args.reason == "locked" then
            -- a neighbour zone another admin holds open blocks the merge;
            -- without this branch it read as "zone gone"
            Aegis.showToast(getText("UI_Aegis_ZoneLockedBy", tostring(args.admin or "?")))
        elseif args and args.reason == "registry" then
            Aegis.showToast(getText("UI_Aegis_ZoneRegistryLocked"))
        elseif args then
            Aegis.showToast(getText("UI_Aegis_ZoneGone"))
        end
        if page then page:request() end
    elseif command == "zoneLock" then
        if page and page.pendingEntry then
            -- stale answer to a request already replaced by a newer click:
            -- ignore it, pendingEntry stays put so the actually matching
            -- answer can still apply
            if args and args.token == page.pendingToken then
                local target, tool = page.pendingEntry, page.pendingTool
                page.pendingEntry, page.pendingTool, page.pendingToken = nil, nil, nil
                if args.ok then
                    AegisZoneEditor.start(target, tool, false, page:neighborsFor(target))
                else
                    print("[Aegis] zone lock refused for " .. target.x .. "," .. target.y
                        .. " by " .. tostring(args.admin or "?"))
                    Aegis.showToast(getText("UI_Aegis_ZoneLockedBy", tostring(args.admin or "?")))
                end
            end
        elseif args and not args.ok and AegisZoneEditor.instance then
            -- heartbeat lost: our own lock expired while editing
            print("[Aegis] zone lock lost while editing")
            Aegis.showToast(getText("UI_Aegis_ZoneLockLost"))
        end
    end
end)

-- ==================================================================
-- Backup: sub-card above the page (AegisInventory pattern) with the
-- snapshots of the selected zone, backup runs immediately, restore only
-- after confirmation (overwrites the zone's current build state)
-- ==================================================================
AegisBackup = ISPanel:derive("AegisBackup")
AegisBackup.instance = nil

local BACKUP_W = 560
local BACKUP_H = 470
local BACKUP_ROW = 42

function AegisBackup.show(entry)
    if AegisBackup.instance then
        AegisBackup.instance:closeSelf()
    end
    local sw, sh = getCore():getScreenWidth(), getCore():getScreenHeight()
    local o = ISPanel:new(0, 0, sw, sh)
    setmetatable(o, AegisBackup)
    AegisBackup.__index = AegisBackup
    o.background = true
    o.backgroundColor = { r = 0, g = 0, b = 0, a = 0.55 }
    o.borderColor = { r = 0, g = 0, b = 0, a = 0 }
    o.hx = entry.x
    o.hy = entry.y
    o.zoneName = entry.title ~= "" and entry.title or entry.owner
    o.status = ""
    o.running = false
    o.cardX = math.max(0, math.floor((sw - BACKUP_W) / 2))
    o.cardY = math.max(0, math.floor((sh - BACKUP_H) / 2))
    o:initialise()
    o:addToUIManager()
    o:setAlwaysOnTop(true)
    AegisBackup.instance = o
    o:request()
    return o
end

function AegisBackup:closeSelf()
    self:removeFromUIManager()
    if AegisBackup.instance == self then
        AegisBackup.instance = nil
    end
end

function AegisBackup:createChildren()
    local cx, cy = self.cardX, self.cardY

    self.closeBtn = AegisButton:new(cx + BACKUP_W - 42, cy + 12, 30, 30, nil, "close", self, AegisBackup.closeSelf)
    self.closeBtn.radius = 15
    self:addChild(self.closeBtn)

    self.refreshBtn = AegisButton:new(cx + BACKUP_W - 42 - 38, cy + 12, 30, 30, nil, "refresh", self, AegisBackup.request)
    self.refreshBtn.radius = 15
    self:addChild(self.refreshBtn)

    self.list = ISScrollingListBox:new(cx + 16, cy + 56, BACKUP_W - 32, BACKUP_H - 56 - 100)
    self.list:initialise()
    self.list:instantiate()
    self.list.itemheight = BACKUP_ROW
    self.list.drawBorder = false
    self.list.backgroundColor = { r = 0, g = 0, b = 0, a = 0 }
    self.list.doDrawItem = AegisBackup.drawRow
    self:addChild(self.list)

    local bw = math.floor((BACKUP_W - 44) / 2)
    self.backupBtn = AegisButton:new(cx + 16, cy + BACKUP_H - 52, bw, 36, getText("UI_Aegis_BackupNow"), "shield", self, AegisBackup.onBackup)
    self.backupBtn.style = "gold"
    self:addChild(self.backupBtn)

    self.restoreBtn = AegisButton:new(cx + 28 + bw, cy + BACKUP_H - 52, bw, 36, getText("UI_Aegis_BackupRestore"), "rotl", self, AegisBackup.onRestore)
    self.restoreBtn.style = "danger"
    self:addChild(self.restoreBtn)
end

function AegisBackup.request(self)
    local p = getPlayer()
    if not p then return end
    sendClientCommand(p, AegisShared.MODULE, "backupList", { hx = self.hx, hy = self.hy })
end

function AegisBackup:updateButtons()
    if self.backupBtn then self.backupBtn:setEnabled(not self.running) end
    if self.restoreBtn then self.restoreBtn:setEnabled(not self.running) end
end

function AegisBackup:setList(entries)
    -- read network tables defensively (page setList pattern)
    local cleaned = {}
    if type(entries) == "table" then
        for _, e in pairs(entries) do
            if type(e) == "table" and tonumber(e.epoch) and type(e.path) == "string" then
                table.insert(cleaned, {
                    epoch = tonumber(e.epoch), admin = tostring(e.admin or ""),
                    path = e.path, status = tostring(e.status or ""),
                })
            end
        end
    end
    table.sort(cleaned, function(a, b) return a.epoch > b.epoch end)
    self.list:clear()
    self.list.selected = -1
    for _, e in ipairs(cleaned) do
        self.list:addItem(tostring(e.epoch), e)
    end
    if self.list.items[1] then
        self.list.selected = 1
    end
end

function AegisBackup.drawRow(list, y, item, alt)
    local c = Aegis.col
    local sel = list.selected == item.index
    local hover = list.mouseoverselected == item.index
    if sel then
        Aegis.roundRect(list, 2, y + 2, list:getWidth() - 4, BACKUP_ROW - 4, 8, 1, c.card)
        Aegis.roundRect(list, 2, y + 10, 3, BACKUP_ROW - 20, 1, 1, c.gold)
    elseif hover then
        Aegis.roundRect(list, 2, y + 2, list:getWidth() - 4, BACKUP_ROW - 4, 8, 0.5, c.card)
    end
    local e = item.item
    Aegis.text(list, AegisShared.timestampReadable(e.epoch), 14, y + 5, UIFont.Small, sel and c.text or c.muted)
    Aegis.text(list, getText("UI_Aegis_BackupBy", e.admin), 14, y + 7 + Aegis.fontH(UIFont.Small), UIFont.Small, c.muted)
    if e.status == "archiviert" then
        Aegis.textRight(list, getText("UI_Aegis_BackupArchive"), list:getWidth() - 12, y + 5, UIFont.Small, c.muted)
    end
    return y + BACKUP_ROW
end

function AegisBackup:selectedZone()
    local item = self.list.items[self.list.selected]
    return item and item.item or nil
end

function AegisBackup.onBackup(self)
    if self.running then return end
    sendClientCommand(getPlayer(), AegisShared.MODULE, "backupNow", { hx = self.hx, hy = self.hy })
    self.status = getText("UI_Aegis_BackupQueued")
end

function AegisBackup.onRestore(self)
    if self.running then return end
    local e = self:selectedZone()
    if not e then return end
    AegisConfirm.show(getText("UI_Aegis_BackupRestoreTitle"),
        getText("UI_Aegis_BackupRestoreWarn", AegisShared.timestampReadable(e.epoch)),
        getText("UI_Aegis_BackupRestore"), self, function(panel)
            sendClientCommand(getPlayer(), AegisShared.MODULE, "backupRestore",
                { hx = panel.hx, hy = panel.hy, path = e.path })
            panel.status = getText("UI_Aegis_BackupQueued")
        end)
end

function AegisBackup:prerender()
    ISPanel.prerender(self)
    local c = Aegis.col
    local cx, cy = self.cardX, self.cardY

    Aegis.shadow(self, cx, cy, BACKUP_W, BACKUP_H, 26, 0.7)
    Aegis.roundFrame(self, cx, cy, BACKUP_W, BACKUP_H, 12, 1, c.line, c.bg)
    Aegis.icon(self, "shield", cx + 18, cy + 16, 18, 1, c.gold)
    Aegis.text(self, getText("UI_Aegis_BackupTitle", self.zoneName), cx + 46, cy + 14, UIFont.Medium, c.text)

    Aegis.roundFrame(self, cx + 14, cy + 54, BACKUP_W - 28, BACKUP_H - 54 - 96, 8, 1, c.line, c.panel)
    if #self.list.items == 0 then
        Aegis.textCentre(self, getText("UI_Aegis_BackupNone"), cx + math.floor(BACKUP_W / 2), cy + 200, UIFont.Small, c.muted)
    end
    if self.status ~= "" then
        Aegis.text(self, self.status, cx + 16, cy + BACKUP_H - 86, UIFont.Small, self.running and c.goldHi or c.muted)
    end
end

function AegisBackup:onMouseDown(x, y)
    -- swallow clicks on the dimmed background
end

-- matches the message to the currently open card, instead of lying to a
-- foreign zone (different job in the queue) about its state
local function matchesCard(card, args)
    return card and args and tonumber(args.hx) == card.hx and tonumber(args.hy) == card.hy
end

-- responses of the backup server; toasts also arrive without an open card
Events.OnServerCommand.Add(function(module, command, args)
    if module ~= "AegisAdmin" then return end
    local card = AegisBackup.instance
    if command == "backupList" then
        if matchesCard(card, args) then
            card:setList(args.entries)
        end
    elseif command == "backupStart" then
        if args and args.ok then
            if matchesCard(card, args) then
                card.running = true
                card:updateButtons()
                card.status = getText(args.kind == "restore"
                    and "UI_Aegis_BackupStatusRestore" or "UI_Aegis_BackupStatusRunning", "0")
            end
        elseif args then
            local text = getText("UI_Aegis_BackupError")
            if args.reason == "running" or args.reason == "full" then
                text = getText("UI_Aegis_BackupBusy")
            elseif args.reason == "file" then
                text = getText("UI_Aegis_BackupFileError")
            elseif args.reason == "gone" then
                text = getText("UI_Aegis_ZoneGone")
            end
            Aegis.showToast(text)
            if matchesCard(card, args) then card.status = text end
        end
    elseif command == "backupStatus" then
        if matchesCard(card, args) then
            card.running = true
            card:updateButtons()
            card.status = getText(args.kind == "restore"
                and "UI_Aegis_BackupStatusRestore" or "UI_Aegis_BackupStatusRunning",
                tostring(math.floor(tonumber(args.percent) or 0)))
        end
    elseif command == "backupDone" then
        if args then
            local text
            if args.ok then
                text = getText(args.kind == "restore"
                    and "UI_Aegis_BackupRestoreDone" or "UI_Aegis_BackupDone",
                    tostring(math.floor(tonumber(args.tiles) or 0)))
            else
                text = getText("UI_Aegis_BackupError")
            end
            Aegis.showToast(text)
            if matchesCard(card, args) then
                card.running = false
                card:updateButtons()
                local details = {}
                local notLoaded = math.floor(tonumber(args.notLoaded) or 0)
                local skipped = math.floor(tonumber(args.skipped) or 0)
                local lost = math.floor(tonumber(args.lostItems) or 0)
                if notLoaded > 0 or skipped > 0 then
                    table.insert(details, getText("UI_Aegis_BackupDetails", tostring(notLoaded), tostring(skipped)))
                end
                if lost > 0 then
                    table.insert(details, getText("UI_Aegis_BackupItemsMissing", tostring(lost)))
                end
                card.status = text .. (#details > 0 and ("  (" .. table.concat(details, ", ") .. ")") or "")
                card:request()
            end
        end
    end
end)

-- ==================================================================
-- Owner picker for a new zone: no safehouse needed, the admin only
-- picks the target player, then the same editor starts as usual,
-- just without an existing zone and without an edit lock
-- ==================================================================
AegisZoneNew = ISPanel:derive("AegisZoneNew")
AegisZoneNew.instance = nil

local NEW_W = 360
local NEW_H = 170

function AegisZoneNew.show()
    if AegisZoneNew.instance then
        AegisZoneNew.instance:closeSelf()
    end
    local sw, sh = getCore():getScreenWidth(), getCore():getScreenHeight()
    local o = ISPanel:new(0, 0, sw, sh)
    setmetatable(o, AegisZoneNew)
    AegisZoneNew.__index = AegisZoneNew
    o.background = true
    o.backgroundColor = { r = 0, g = 0, b = 0, a = 0.55 }
    o.borderColor = { r = 0, g = 0, b = 0, a = 0 }
    o.cardX = math.max(0, math.floor((sw - NEW_W) / 2))
    o.cardY = math.max(0, math.floor((sh - NEW_H) / 2))
    o:initialise()
    o:addToUIManager()
    o:setAlwaysOnTop(true)
    AegisZoneNew.instance = o
    return o
end

function AegisZoneNew:closeSelf()
    self:removeFromUIManager()
    if AegisZoneNew.instance == self then
        AegisZoneNew.instance = nil
    end
end

function AegisZoneNew:createChildren()
    local cx, cy = self.cardX, self.cardY

    self.closeBtn = AegisButton:new(cx + NEW_W - 42, cy + 12, 30, 30, nil, "close", self, AegisZoneNew.closeSelf)
    self.closeBtn.radius = 15
    self:addChild(self.closeBtn)

    self.ownerCombo = ISComboBox:new(cx + 16, cy + 56, NEW_W - 32, 26, self, nil)
    self.ownerCombo:initialise()
    self:addChild(self.ownerCombo)
    self.ownerCombo:clear()
    for _, row in ipairs(Aegis.scoreboard or {}) do
        self.ownerCombo:addOption(row.username)
    end
    local me = getPlayer() and getPlayer():getUsername()
    if me then
        local found = false
        for _, opt in ipairs(self.ownerCombo.options) do
            if opt == me then found = true end
        end
        if not found then self.ownerCombo:addOption(me) end
    end
    self.ownerCombo.selected = 1

    local bw = math.floor((NEW_W - 44) / 2)
    self.rectBtn = AegisButton:new(cx + 16, cy + NEW_H - 52, bw, 36, getText("UI_Aegis_ZoneEdit"), "pin", self, AegisZoneNew.onRect)
    self.rectBtn.style = "gold"
    self:addChild(self.rectBtn)

    self.brushBtn = AegisButton:new(cx + 28 + bw, cy + NEW_H - 52, bw, 36, getText("UI_Aegis_ZoneBrush"), "wand", self, AegisZoneNew.onBrush)
    self:addChild(self.brushBtn)
end

function AegisZoneNew:owner()
    return self.ownerCombo.options[self.ownerCombo.selected]
end

function AegisZoneNew:onRect()
    local owner = self:owner()
    if not owner then return end
    self:closeSelf()
    AegisPageZones.startNew(owner, "rect")
end

function AegisZoneNew:onBrush()
    local owner = self:owner()
    if not owner then return end
    self:closeSelf()
    AegisPageZones.startNew(owner, "brush")
end

function AegisZoneNew:prerender()
    ISPanel.prerender(self)
    local c = Aegis.col
    local cx, cy = self.cardX, self.cardY
    Aegis.shadow(self, cx, cy, NEW_W, NEW_H, 26, 0.7)
    Aegis.roundFrame(self, cx, cy, NEW_W, NEW_H, 12, 1, c.line, c.bg)
    Aegis.icon(self, "home", cx + 18, cy + 16, 18, 1, c.gold)
    Aegis.text(self, getText("UI_Aegis_ZoneNewTitle"), cx + 46, cy + 14, UIFont.Medium, c.text)
    Aegis.text(self, getText("UI_Aegis_ZoneNewOwner"), cx + 16, cy + 38, UIFont.Small, c.muted)
    if #self.ownerCombo.options == 0 then
        Aegis.text(self, getText("UI_Aegis_ZoneNewNobody"), cx + 16, cy + NEW_H - 90, UIFont.Small, c.danger)
    end
end

function AegisZoneNew:onMouseDown(x, y)
    -- swallow clicks on the dimmed background
end

-- Vanilla binds the safehouse UI to the rectangle under the cursor. If a
-- member stands in a painted annex, the vanilla anticheat checks their
-- packets against the FIRST member safehouse in the list and punishes on
-- mismatch (default: kick). We rebind the UI to exactly that first
-- rectangle, provided it belongs to the same zone (same owner, player is
-- a member); UI and anticheat then always agree. The patch runs on every
-- player, the mod is mandatory on the server.
local function patchSafehouseUI()
    if ISSafehouseUI.aegisRebind then return end
    ISSafehouseUI.aegisRebind = true
    local original = ISSafehouseUI.new
    function ISSafehouseUI:new(x, y, width, height, safehouse, player, ...)
        pcall(function()
            if not safehouse or not player then return end
            local name = player.getUsername and player:getUsername() or nil
            if not name then return end
            local first = SafeHouse.hasSafehouse(name)
            if first and first ~= safehouse
                and first:getOwner() == safehouse:getOwner()
                and safehouse:playerAllowed(name) then
                safehouse = first
            end
        end)
        return original(self, x, y, width, height, safehouse, player, ...)
    end
end

Events.OnGameStart.Add(patchSafehouseUI)

-- detached ghost sweeper: any client side safehouse add/remove arms a
-- short polling window, so stale rectangles vanish within seconds even
-- with the panel closed. Quiet otherwise, zone admins only
local sweepUntil = 0
local sweepNext = 0
Events.OnSafehousesChanged.Add(function()
    if not isClient() then return end
    sweepUntil = getTimestampMs() + 60000
end)
Events.OnTick.Add(function()
    if sweepUntil == 0 or not isClient() then return end
    local now = getTimestampMs()
    if now >= sweepUntil then
        sweepUntil = 0
        return
    end
    if now < sweepNext then return end
    sweepNext = now + 5000
    if not (Aegis and Aegis.canSee and Aegis.canSee("zones")) then return end
    local p = getPlayer()
    if p then sendClientCommand(p, AegisShared.MODULE, "shList", {}) end
end)

AegisWindow.registerPage({
    id = "zones",
    icon = "home",
    label = "UI_Aegis_NavZones",
    create = AegisPageZones.create,
})
