-- Lascivious Factions System - embedded claim map widget.
--
-- A map you drag on to claim land. Wraps PhunZones' own map panel
-- (require "PhunZones/ui/ui_map" -> an ISPanel hosting an ISMiniMapInner with
-- world<->screen transforms), then layers our own rendering + a drag-to-draw
-- interaction on top. Shows ONLY the player's own faction's claim; the drag
-- rectangle is coloured green when it's claimable and red when it isn't
-- (too large for the faction, too many rects, or overlapping another faction).
--
-- A completed claim is submitted through FF.requestClaim -> "claim"; the server
-- independently canonicalises the union, re-validates it, and applies it. Client-side
-- green/red remains an advisory hint rather than an authority boundary.
--
-- Reused from elsewhere:
--   * PhunZones/ui/ui_map      -> initialised map widget + mapAPI transforms
--   * PhunZones.getIntersectingZones(x1,y1,x2,y2) -> reliable client-side overlap
--     (PhunZones zone data is replicated to clients; the FF registry may not be)
--   * FF.maxClaimTiles / FF.totalArea / FF.normaliseRect / FF.zoneKey (Shared)
--   * FF.requestClaim (TileToolAPI), FF.UI.factionColor + theme tokens

require "LFS_Shared"
require "LFS_TileToolAPI"
require "LFS_UI"
require "LFS_Hunter"

local FF = LasciviousFactionsSystem
local UI = FF.UI

-- Server has no map; nothing to build there.
if isServer() then return end

-- A tiny drag (in pixels) is treated as a click, not a new rectangle.
local MIN_DRAW_PX = 5

local function nonOverlappingArea(rects)
    local total = 0
    for _, r in ipairs(rects or {}) do total = total + FF.rectArea(r) end
    return total
end

-- A rect as the "Make a Public Area" quick-action creates them: public, loot-open.
-- One drag produces a finished public area with no follow-up dialog (see shopMode).
local function makePublicRect(x1, y1, x2, y2)
    return FF.sanitiseArea(FF.normaliseRect({ x1, y1, x2, y2 }), "public", { loot = true })
end

-- Human-readable reason for why a proposed claim is invalid (drawn under the drag
-- preview so the red box explains itself). Keys match FFClaimMap:_validity().
local REASON_TEXT = {
    empty             = "Draw a claim area",
    not_in_faction    = "You're not in a faction",
    faction_too_small = "Faction too small to claim",
    too_many_rects    = "Too many separate areas",
    too_large         = "Claim too large for your faction",
    overlap           = "Overlaps another faction's claim",
    too_scattered     = "Too far from your other claims",
    too_many_public   = "Too many public areas",
    too_close         = "Too close to another faction's claim",
    no_claim_zone     = "Claiming is blocked here",
}

-- ===========================================================================
-- FFClaimMap : ISPanel -- hosts the PhunZones map + our claim overlay/draw tool
-- ===========================================================================
FFClaimMap = ISPanel:derive("FFClaimMap")

function FFClaimMap:new(x, y, width, height)
    local o = ISPanel:new(x, y, width, height)
    setmetatable(o, self)
    self.__index = self
    o.background = false
    o.drawMode = false
    o.eraseMode = false   -- click a rect to remove it (mutually exclusive with drawMode)
    -- Shop mode is drawMode with the result pre-marked public+loot. It exists because
    -- reaching a public area the long way round (draw, find the access badge, open the
    -- dialog, pick Public, tick a grant) was discoverable enough that nobody on a live
    -- server ever found it. One button, one drag, one finished public area.
    o.shopMode = false
    o.rects = {}          -- working claim set: { {x1,y1,x2,y2, new=bool}, ... }
    o.name = nil
    o.faction = nil
    o.factionCol = UI.color.accent
    return o
end

function FFClaimMap:createChildren()
    ISPanel.createChildren(self)

    -- Deferred require: PhunZones (a hard dependency) loads before us, but we
    -- keep it inside createChildren so a missing/renamed module degrades to a
    -- notice instead of aborting this whole file at load time.
    local ok, PZMap = pcall(require, "PhunZones/ui/ui_map")
    if not ok or type(PZMap) ~= "table" then
        self.failed = true
        FF.warn("PhunZones map UI unavailable; claim map disabled.")
        return
    end

    local mapui = PZMap:new(0, 0, self:getWidth(), self:getHeight(), getPlayer(), nil)
    mapui.moveWithMouse = false      -- it's embedded; don't let drags move the panel
    mapui:initialise()
    mapui:instantiate()
    if mapui.setData then mapui:setData({}) end   -- suppress PhunZones' own markers
    self:addChild(mapui)
    self.mapui = mapui

    self:_hookMap()
    self:refresh()
end

-- ---------------------------------------------------------------------------
-- Coordinate helpers
-- ---------------------------------------------------------------------------
function FFClaimMap:_api()
    return self.mapui and self.mapui.map and self.mapui.map.mapAPI
end

function FFClaimMap:_sToW(sx, sy)
    local api = self:_api()
    if not api then return 0, 0 end
    return api:uiToWorldX(sx, sy), api:uiToWorldY(sx, sy)
end

-- World-tile rect {x1,y1,x2,y2} -> floored screen AABB. +1 on the far corner so
-- a single-tile claim still spans a visible box (tiles are unit cells).
function FFClaimMap:_screenRect(r)
    local api = self:_api()
    if not api then return 0, 0, 0, 0 end
    local ax, ay = api:worldToUIX(r[1], r[2]), api:worldToUIY(r[1], r[2])
    local bx, by = api:worldToUIX(r[3] + 1, r[4] + 1), api:worldToUIY(r[3] + 1, r[4] + 1)
    if ax > bx then ax, bx = bx, ax end
    if ay > by then ay, by = by, ay end
    return math.floor(ax), math.floor(ay), math.ceil(bx), math.ceil(by)
end

-- ---------------------------------------------------------------------------
-- Mouse hooks on the inner map widget (draw mode). Mirrors the accumulate-deltas
-- pattern documented in PhunZones' ui_map_overlay: onMouseDown/onMouseUp get
-- absolute widget-relative coords, onMouseMove/onMouseMoveWhileCapture get deltas.
-- We suppress the map's own pan while a claim drag is in progress.
-- ---------------------------------------------------------------------------
function FFClaimMap:_hookMap()
    local inner = self.mapui and self.mapui.map
    if not inner then return end
    -- Mark this as our embedded map so the persistent-map overlay hook skips it
    -- (LFS_MapOverlay) -- we draw our own claims below.
    inner.ffEmbedded = true
    local this = self

    local origRender  = inner.render
    local origDown    = inner.onMouseDown
    local origMove    = inner.onMouseMove
    local origMoveCap = inner.onMouseMoveWhileCapture
    local origUp      = inner.onMouseUp

    inner.render = function(s)
        if origRender then origRender(s) end
        this:_drawOverlay(s)
    end

    inner.onMouseDown = function(s, x, y)
        this._mx, this._my = x, y
        if this.drawMode then
            local wx, wy = this:_sToW(x, y)
            this._dragStart = { wx = wx, wy = wy, sx = x, sy = y }
            this._dragCur   = { wx = wx, wy = wy }
            s:setCapture(true)   -- keep receiving moves even outside the widget
            return
        end
        if this.eraseMode then
            return   -- erase happens on mouse-up; suppress the map's own pan
        end
        if origDown then origDown(s, x, y) end
    end

    inner.onMouseMove = function(s, dx, dy)
        this._mx = (this._mx or 0) + dx
        this._my = (this._my or 0) + dy
        if this.drawMode and this._dragStart then
            local wx, wy = this:_sToW(this._mx, this._my)
            this._dragCur = { wx = wx, wy = wy }
            return
        end
        if origMove then origMove(s, dx, dy) end
    end

    inner.onMouseMoveWhileCapture = function(s, dx, dy)
        this._mx = (this._mx or 0) + dx
        this._my = (this._my or 0) + dy
        if this.drawMode and this._dragStart then
            local wx, wy = this:_sToW(this._mx, this._my)
            this._dragCur = { wx = wx, wy = wy }
            return
        end
        if origMoveCap then origMoveCap(s, dx, dy) end
    end

    inner.onMouseUp = function(s, x, y)
        if this.drawMode then
            s:setCapture(false)
            this:_finishDrag(x, y)
            return true
        end
        if this.eraseMode then
            local wx, wy = this:_sToW(x, y)
            this:_removeAt(math.floor(wx), math.floor(wy))
            return true
        end
        if origUp then return origUp(s, x, y) end
    end
end

-- Build the exact union of the working set plus an optional drag rectangle.  The
-- existing set is kept first deliberately: its access metadata wins on overlap and
-- only tiles outside it become part of the new expansion.
function FFClaimMap:_combinedRects(extra)
    local all = {}
    for _, r in ipairs(self.rects or {}) do all[#all + 1] = r end
    if extra then all[#all + 1] = extra end
    return FF.canonicaliseClaimRects(all)
end

-- A normal drag that starts inside or touches an existing logical area inherits that
-- area's access/grants. This makes the gesture an actual extension even for an
-- allies/public area, rather than silently creating a differently-permissioned strip.
function FFClaimMap:_makeDragRect(x1, y1, x2, y2, startX, startY)
    if self.shopMode then return makePublicRect(x1, y1, x2, y2) end
    local rect = FF.normaliseRect({ x1, y1, x2, y2 })
    for i = #self.rects, 1, -1 do
        local existing = self.rects[i]
        if FF.pointInRect(startX, startY, existing) then
            FF.sanitiseArea(rect, existing.access, existing.grants)
            return rect
        end
    end
    -- Starting outside but reaching an edge is the same expansion gesture.  Inherit
    -- the touched area's policy so an allies/public shape does not gain an accidental
    -- private strip and an internal access divider.
    for i = #self.rects, 1, -1 do
        local existing = self.rects[i]
        if FF.rectsEdgeConnected(rect, existing) then
            FF.sanitiseArea(rect, existing.access, existing.grants)
            break
        end
    end
    return rect
end

-- Finish a claim drag.  A rectangle that crosses/touches an existing area is folded
-- into its exact union (including L shapes), rather than becoming a second rectangle
-- drawn inside it. Invalid expansions are refused immediately, matching the preview.
-- A tiny drag remains a click-to-remove shortcut.
function FFClaimMap:_finishDrag(x, y)
    local ds = self._dragStart
    self._dragStart = nil
    self._dragCur = nil
    if not ds then return end

    if math.abs(x - ds.sx) < MIN_DRAW_PX and math.abs(y - ds.sy) < MIN_DRAW_PX then
        self:_removeAt(math.floor(ds.wx), math.floor(ds.wy))
        return
    end

    local wx2, wy2 = self:_sToW(x, y)
    local x1, y1 = math.floor(ds.wx), math.floor(ds.wy)
    local x2, y2 = math.floor(wx2), math.floor(wy2)
    -- In shop mode the rect arrives already public+loot, which is the whole point of
    -- the mode: one drag produces a finished public area with no follow-up dialog.
    local rect = self:_makeDragRect(x1, y1, x2, y2, x1, y1)
    rect.new = true
    local valid, reason, total = self:_validity(rect)
    local added = total - nonOverlappingArea(self.rects)
    if added <= 0 then
        local p = getPlayer()
        if p and HaloTextHelper then
            HaloTextHelper.addText(p, FF.text("UI_LFS_ClaimAlreadyOwned",
                "This selection is already part of the territory."))
        end
        return
    end
    if not valid then
        local p = getPlayer()
        if p and HaloTextHelper then
            HaloTextHelper.addText(p, FFClaimMap.reasonText(reason) or FF.tr("Invalid claim"))
        end
        return
    end
    self.rects = self:_combinedRects(rect)

    -- A shop claim is a single deliberate gesture, so drop straight back out of the
    -- mode rather than leaving it armed and turning the player's next drag into a
    -- second (probably unwanted) public area.
    if self.shopMode then
        self.shopMode = false
        self.drawMode = false
        return
    end

    -- Keep draw mode armed at the area limit: a drag touching existing territory is
    -- an expansion of that same area and must remain possible. _validity blocks only
    -- a NEW disconnected component above the score-driven allowance.
end

-- Enter/leave shop mode. Shop mode implies drawMode (it is a drawing mode) and is
-- mutually exclusive with erase, matching how the panel toggles the other two.
-- Sets the fields directly rather than calling setDrawMode, which deliberately
-- clears shopMode (see its comment).
function FFClaimMap:setShopMode(on)
    self.shopMode = on and true or false
    self.drawMode = self.shopMode
    if self.shopMode then
        self.eraseMode = false
    else
        self._dragStart = nil
        self._dragCur = nil
    end
end

-- How many public areas the working set already holds, and the server's cap. Drives
-- the "N / max" readout and the disabled state on the shop button.
function FFClaimMap:publicAreaCount()
    return FF.countPublicAreas(self.rects), FF.getOptions().maxPublicClaimAreas
end

function FFClaimMap:_removeAt(wx, wy)
    for i = #self.rects, 1, -1 do
        if FF.pointInRect(wx, wy, self.rects[i]) then
            -- Remove the whole connected area, not one implementation fragment of
            -- an L shape. The player never needs to know how the union is encoded.
            for gi, group in ipairs(self:areaGroups()) do
                for _, index in ipairs(group.indices) do
                    if index == i then self:removeIndex(gi); return end
                end
            end
            return
        end
    end
end

-- ---------------------------------------------------------------------------
-- Validity (green/red)
-- ---------------------------------------------------------------------------

-- Does any of `rects` overlap another faction's claim? Uses PhunZones' synced
-- spatial index (reliable on clients) rather than the FF registry.
function FFClaimMap:_overlapsOther(rects)
    local PZ = _G.PhunZones
    if not (PZ and PZ.getIntersectingZones) then return false end
    local myKey = self.name and FF.zoneKey(self.name) or nil
    local prefix = FF.ZONE_PREFIX
    for _, r in ipairs(rects) do
        local zones = PZ.getIntersectingZones(r[1], r[2], r[3], r[4]) or {}
        for _, z in ipairs(zones) do
            local k = z.key
            if k and k ~= myKey and string.sub(k, 1, #prefix) == prefix then
                return true
            end
        end
    end
    return false
end

-- Does any of `rects` sit within `buffer` tiles of a DIFFERENT, non-allied faction's
-- claim? Same rationale as FF.findClaimBufferConflict (shared) -- stops planting a
-- claim directly against a rival's border -- kept in sync with it deliberately.
-- Uses PhunZones' synced spatial index for the RECT geometry (reliable on clients,
-- same reason _overlapsOther does), widening the query box by `buffer` on every side
-- since getIntersectingZones only returns zones that actually intersect the box.
-- FF.areAllied still reads the FF registry for the ally check -- already relied on
-- client-side elsewhere (Kills, Nameplates, the Factions tab), so that part is fine.
-- A PUBLIC rect is exempt, matching the server; a rect still being dragged (not yet
-- marked public) is treated as private for this live preview, so a trade post drawn
-- right at a rival's edge can flash red while drawing and clear once you mark it
-- Public and it goes green on the next _validity pass -- the server is what actually
-- decides.
function FFClaimMap:_bufferConflict(rects, buffer)
    if not buffer or buffer <= 0 then return false end
    local PZ = _G.PhunZones
    if not (PZ and PZ.getIntersectingZones) then return false end
    local myKey = self.name and FF.zoneKey(self.name) or nil
    local prefix = FF.ZONE_PREFIX
    for _, r in ipairs(rects) do
        if FF.areaAccess(r) ~= "public" then
            local zones = PZ.getIntersectingZones(
                r[1] - buffer, r[2] - buffer, r[3] + buffer, r[4] + buffer) or {}
            for _, z in ipairs(zones) do
                local k = z.key
                if k and k ~= myKey and string.sub(k, 1, #prefix) == prefix and z.points then
                    local otherName = FF.factionNameFromZoneKey(k)
                    if not (self.name and otherName and FF.areAllied(self.name, otherName)) then
                        for _, pr in ipairs(z.points) do
                            if FF.rectGap(r, pr) < buffer then return true end
                        end
                    end
                end
            end
        end
    end
    return false
end

-- Validate the working set (optionally plus one in-progress rect `extra`).
-- Returns valid(bool), reasonKey(string|nil), totalTiles(int), maxTiles(int).
function FFClaimMap:_validity(extra)
    local faction = self.faction
    if not faction then return false, "not_in_faction", 0, 0 end
    local opts = FF.getOptions()
    local mc = FF.memberCount(faction)
    -- Score-driven, so the green/red preview matches the server's own check.
    local maxTiles = FF.maxClaimTiles(FF.factionScore(faction, opts), opts)

    -- Carry access/grants into the copy: FF.claimsClustered exempts public areas from
    -- the separation rule, so stripping them here would make the preview disagree with
    -- the server and show a legal remote trade hub as red.
    local proposed = {}
    for i, r in ipairs(self.rects) do
        proposed[i] = FF.sanitiseArea({ r[1], r[2], r[3], r[4] }, r.access, r.grants)
    end
    -- The in-progress rect carries its access too. Without this a shop drawn near a
    -- rival flashed red for the whole drag and only went green once it was marked
    -- public afterwards -- public areas are exempt from the buffer and separation
    -- rules, so the preview was disagreeing with the server about its own rect.
    if extra then
        proposed[#proposed + 1] =
            FF.sanitiseArea({ extra[1], extra[2], extra[3], extra[4] }, extra.access, extra.grants)
    end

    proposed = FF.canonicaliseClaimRects(proposed)
    local total = nonOverlappingArea(proposed)
    if #proposed == 0 then return false, "empty", 0, maxTiles end
    if mc < opts.minFactionSizeToClaim then return false, "faction_too_small", total, maxTiles end
    local proposedAreas = FF.claimComponentCount(proposed)
    local currentAreas = FF.claimComponentCount(faction.claims)
    local maxAreas = FF.maxClaimAreas(FF.factionScore(faction, opts), opts)
    if proposedAreas > maxAreas and proposedAreas > currentAreas then
        return false, "too_many_rects", total, maxTiles
    end
    -- A death can lower the score below land already owned. Existing territory is
    -- grandfathered: while over cap, the editor permits equal-size rearrangements
    -- and reductions, but no increase. This mirrors FF.validateClaim on the server.
    local currentArea = FF.totalArea(faction.claims)
    if total > maxTiles and total > currentArea then
        return false, "too_large", total, maxTiles
    end
    if self:_overlapsOther(proposed) then return false, "overlap", total, maxTiles end
    -- Unlike the two checks either side of it, this one reads the replicated registry
    -- rather than the PhunZones zone layer. No-claim zones are a GLOBAL (like POIs), and
    -- globals do reach every client reliably; it is only other factions' claim state
    -- that can be stale here, which is why those two go through PhunZones instead.
    if FF.findNoClaimConflict(proposed) then
        return false, "no_claim_zone", total, maxTiles
    end
    if self:_bufferConflict(proposed, opts.claimBufferTiles) then
        return false, "too_close", total, maxTiles
    end
    if not FF.claimsClustered(proposed, opts.maxClaimSeparation) then
        return false, "too_scattered", total, maxTiles
    end
    if FF.countPublicAreas(proposed) > opts.maxPublicClaimAreas then
        return false, "too_many_public", total, maxTiles
    end
    return true, nil, total, maxTiles
end

-- ---------------------------------------------------------------------------
-- Overlay rendering (runs after the map widget's own render)
-- ---------------------------------------------------------------------------
function FFClaimMap:_drawUnionBoundary(widget, rects, col, alpha, thickness)
    local api, jo = self:_api(), widget.javaObject
    if not (api and jo) then return end
    local sig = {}
    for _, r in ipairs(rects or {}) do
        sig[#sig + 1] = table.concat({ r[1], r[2], r[3], r[4] }, ",")
    end
    table.sort(sig)
    sig = table.concat(sig, ";")
    if not self._boundaryCache or self._boundaryCache.sig ~= sig then
        self._boundaryCache = { sig = sig, segments = FF.claimBoundarySegments(rects) }
    end
    for _, s in ipairs(self._boundaryCache.segments) do
        local ax, ay = api:worldToUIX(s[1], s[2]), api:worldToUIY(s[1], s[2])
        local bx, by = api:worldToUIX(s[3], s[4]), api:worldToUIY(s[3], s[4])
        jo:DrawLine(nil, ax, ay, bx, by, thickness or UI.claimStyle.isoThickness,
            col.r, col.g, col.b, alpha or UI.claimStyle.borderAlpha)
    end
end

function FFClaimMap:_drawOverlay(widget)
    if not self:_api() then return end
    widget:setStencilRect(0, 0, widget:getWidth(), widget:getHeight())

    -- Admin no-claim zones, first so everything else paints over them. Red because the
    -- drag preview already uses red for "this is not allowed" and this is the same
    -- message stated ahead of time -- the point is that you can see where not to draw
    -- before you waste a drag on it.
    for _, zone in pairs(FF.getData().noClaim or {}) do
        local labelled = false
        for _, r in ipairs(zone.points or {}) do
            local x1, y1, x2, y2 = self:_screenRect(r)
            local w, h = x2 - x1, y2 - y1
            if w >= 2 and h >= 2 then
                widget:drawRect(x1, y1, w, h, 0.12, 0.85, 0.25, 0.25)
                widget:drawRectBorder(x1, y1, w, h, 0.5, 0.85, 0.25, 0.25)
                if not labelled then
                    labelled = true
                    local t = FF.text("UI_LFS_NoClaimsMarker", "NO CLAIMS -- %s",
                        tostring(zone.name or zone.id))
                    widget:drawText(t, x1 + 5, y1 + 4, 0, 0, 0, 0.7, UI.font.small)
                    widget:drawText(t, x1 + 4, y1 + 3, 0.95, 0.45, 0.45, 1.0, UI.font.small)
                end
            end
        end
    end

    -- Allied factions that share their map: drawn under our own claims, dim and
    -- non-interactive, so you can see allied land while editing.
    for _, ally in ipairs(self.allyRects or {}) do
        for _, r in ipairs(ally.rects) do
            local x1, y1, x2, y2 = self:_screenRect(r)
            local w, h = x2 - x1, y2 - y1
            if w >= 2 and h >= 2 then
                widget:drawRect(x1, y1, w, h, 0.10, ally.col.r, ally.col.g, ally.col.b)
                widget:drawRectBorder(x1, y1, w, h, 0.55, ally.col.r, ally.col.g, ally.col.b)
            end
        end
        if ally.rects[1] then
            local x1, y1 = self:_screenRect(ally.rects[1])
            local t = "[" .. tostring(ally.tag) .. "]"
            widget:drawText(t, x1 + 5, y1 + 4, 0, 0, 0, 0.7, UI.font.small)
            widget:drawText(t, x1 + 4, y1 + 3, ally.col.r, ally.col.g, ally.col.b, 1.0, UI.font.small)
        end
    end

    -- Committed claims (faction colour) + pending additions (accent, brighter).
    local labelled = false
    for _, r in ipairs(self.rects) do
        local x1, y1, x2, y2 = self:_screenRect(r)
        local w, h = x2 - x1, y2 - y1
        if w >= 2 and h >= 2 then
            -- Pending edits win the colour (you need to see what you just drew);
            -- otherwise a public area draws in the shared public teal so the editor
            -- matches what everyone else sees of it on the world map.
            -- A public area keeps the shared teal even while pending: for a shop claim
            -- the colour IS the confirmation that the drag produced a trading post, so
            -- it must not be masked by the generic "pending edit" accent.
            local col = self.factionCol
            if FF.areaAccess(r) == "public" then col = UI.publicClaimColor
            elseif r.new then col = UI.color.accent end
            local fillA = r.new and 0.26 or UI.claimStyle.fillAlpha
            widget:drawRect(x1, y1, w, h, fillA, col.r, col.g, col.b)
            if not labelled and self.name then
                local tag = "[" .. tostring((self.faction and self.faction.tag) or self.name) .. "]"
                widget:drawText(tag, x1 + 5, y1 + 4, 0, 0, 0, 0.7, UI.font.small)
                widget:drawText(tag, x1 + 4, y1 + 3, self.factionCol.r, self.factionCol.g, self.factionCol.b, 1.0, UI.font.small)
                labelled = true
            end
        end
    end

    -- One contour around the union.  Do not draw it while dragging because the live
    -- combined contour below replaces it; otherwise the former border would remain as
    -- a visible divider inside the proposed expansion.
    local dragging = self.drawMode and self._dragStart and self._dragCur
    if not dragging then
        self:_drawUnionBoundary(widget, self.rects, self.factionCol,
            UI.claimStyle.borderAlpha, UI.claimStyle.isoThickness)
    end

    -- Caçador upgrade: approximate detection circles for non-member players
    -- currently in range, above everything static so they read as an
    -- attention-grabbing overlay, but below the interactive drag/erase
    -- previews so those still stay clearly on top while in use.
    self:_drawHunterCircles(widget)
    self:_drawHunterRange(widget)

    -- Live drag preview, tile-snapped, coloured by validity.
    if dragging then
        local dx1, dy1 = math.floor(self._dragStart.wx), math.floor(self._dragStart.wy)
        local dx2, dy2 = math.floor(self._dragCur.wx), math.floor(self._dragCur.wy)
        -- Build the preview exactly as _finishDrag will build the real rect, so what
        -- the player sees while dragging is what they get on release.
        local rect = self:_makeDragRect(dx1, dy1, dx2, dy2, dx1, dy1)
        rect.new, rect.preview = true, true
        local valid, reason, total, maxTiles = self:_validity(rect)
        local col = valid and UI.color.good or UI.color.bad
        local combined = self:_combinedRects(rect)
        local added = math.max(0, total - nonOverlappingArea(self.rects))

        -- Paint only the portion the drag really adds. Existing tiles keep their
        -- normal fill, while the outer contour previews the final unified shape.
        for _, piece in ipairs(combined) do
            if piece.preview then
                local px1, py1, px2, py2 = self:_screenRect(piece)
                local pw, ph = px2 - px1, py2 - py1
                if pw >= 1 and ph >= 1 then
                    widget:drawRect(px1, py1, pw, ph, 0.25, col.r, col.g, col.b)
                end
            end
        end
        self:_drawUnionBoundary(widget, combined, col, 1.0, UI.claimStyle.isoThickness)

        local x1, y1, x2, y2 = self:_screenRect(rect)
        local w, h = x2 - x1, y2 - y1
        if w >= 1 and h >= 1 then
            local ww = rect[3] - rect[1] + 1
            local wh = rect[4] - rect[2] + 1
            -- maxTiles can be fractional because survived hours accumulate as a
            -- decimal. Claims themselves are whole tiles, so expose the effective
            -- whole-tile capacity instead of a long floating-point value.
            local shownSelected = math.floor(ww * wh)
            local shownAdded = math.floor(added)
            local shownTotal = math.floor(total)
            local shownMax = math.floor(maxTiles)
            local s = FF.text("UI_LFS_ClaimDragInfo",
                "Selection: %d | new: %d | total: %d / %d",
                shownSelected, shownAdded, shownTotal, shownMax)
            local sw = UI.tw(UI.font.small, s)
            local tx = x1 + math.floor((w - sw) / 2)
            local ty = y1 + math.floor((h - UI.fh(UI.font.small)) / 2)
            widget:drawText(s, tx + 1, ty + 1, 0, 0, 0, 0.7, UI.font.small)
            widget:drawText(s, tx, ty, col.r, col.g, col.b, 1.0, UI.font.small)
            -- When invalid, spell out why right under the size readout.
            local rt = (not valid) and reason and FF.tr(REASON_TEXT[reason])
            if rt then
                local rw = UI.tw(UI.font.small, rt)
                local rtx = x1 + math.floor((w - rw) / 2)
                local rty = ty + UI.fh(UI.font.small) + 2
                widget:drawText(rt, rtx + 1, rty + 1, 0, 0, 0, 0.7, UI.font.small)
                widget:drawText(rt, rtx, rty, col.r, col.g, col.b, 1.0, UI.font.small)
            end
        end
    end

    -- Erase mode: highlight the rect under the cursor so it's clear what a click removes.
    if self.eraseMode and self._mx and self._my then
        local wx, wy = self:_sToW(self._mx, self._my)
        wx, wy = math.floor(wx), math.floor(wy)
        for i = #self.rects, 1, -1 do
            if FF.pointInRect(wx, wy, self.rects[i]) then
                for _, group in ipairs(self:areaGroups()) do
                    local hit = false
                    for _, index in ipairs(group.indices) do
                        if index == i then hit = true; break end
                    end
                    if hit then
                        local col = UI.color.bad
                        for _, r in ipairs(group.rects) do
                            local x1, y1, x2, y2 = self:_screenRect(r)
                            local w, h = x2 - x1, y2 - y1
                            if w >= 2 and h >= 2 then
                                widget:drawRect(x1, y1, w, h, 0.30, col.r, col.g, col.b)
                            end
                        end
                        self:_drawUnionBoundary(widget, group.rects, col, 1.0,
                            UI.claimStyle.isoThickness)
                        break
                    end
                end
                break
            end
        end
    end

    widget:clearStencilRect()
end

-- Caçador upgrade: draws a well-defined filled circle (the hard-edged
-- ui_circle_fill texture, tinted + moderate alpha, scaled to a real
-- world-space radius instead of hugging a UI rect) for every player
-- LFS_Server.lua's hunterTrackingTick currently has detected for this
-- faction, plus their
-- username at Caçador level 10 (server only ever fills in `name` at that
-- level -- the client trusts that decision rather than re-checking the
-- level itself, same "server decides what's revealed" split used
-- throughout this session).
--
-- self._hunterFaction is refreshed here on its own short real-time throttle,
-- deliberately SEPARATE from self.faction/self.rects (which :refresh()
-- above carefully controls the staleness of for the claim-EDITING flow, via
-- its own savedSig comparison). Piggybacking on that mechanism would mean
-- either waiting for a claims-specific change to trigger a refresh, or
-- risking a mid-drag rebuild -- a tiny independent poll here is simpler and
-- cannot interfere with anything the editing logic manages.
local HUNTER_REFRESH_INTERVAL = 1 -- real seconds

-- Fill-only style: a well-defined solid circle, no border -- matches
-- territory claims' solid drawRect fill rather than the soft "ui_glow"
-- gradient this used originally. A vector DrawLine border (matching
-- _drawUnionBoundary's technique for claim outlines) was tried and then
-- explicitly dropped per the user's own follow-up ask ("no dezenho do
-- círculo, vamos tirar a borda, deixar só o preenchimento").
local HUNTER_FILL_ALPHA = 0.22

function FFClaimMap:_drawHunterCircles(widget)
    local api = self:_api()
    if not api then return end

    local now = getTimestamp()
    if not self._hunterRefreshAt or (now - self._hunterRefreshAt) >= HUNTER_REFRESH_INTERVAL then
        self._hunterRefreshAt = now
        local player = getPlayer()
        local username = player and player:getUsername()
        local faction = nil
        if username then local _, f = FF.getFactionOfPlayer(username); faction = f end
        self._hunterFaction = faction
    end

    local faction = self._hunterFaction
    local detected = faction and faction.hunter and faction.hunter.detected
    if not detected then return end

    -- ui_circle_fill: a hard-edged solid circle (unlike ui_glow's soft radial
    -- falloff), same "white source PNG tinted at draw time" convention as
    -- every other ui_* primitive here.
    local tex = UI.icon("ui_circle_fill")
    if not tex then return end
    local col = UI.color.bad
    for _, entry in pairs(detected) do
        local cx, cy, radius = entry.cx, entry.cy, entry.radius
        if cx and cy and radius and radius > 0 then
            local sx, sy = api:worldToUIX(cx, cy), api:worldToUIY(cx, cy)
            -- Both samples share the same Y so only the X delta reflects the
            -- horizontal tile span at the map's current zoom -- never mix an
            -- X result from one call with a Y result from another, since
            -- each transform needs the full (wx, wy) pair.
            local edgeX = api:worldToUIX(cx + radius, cy)
            local screenRadius = math.max(2, math.abs(edgeX - sx))
            widget:drawTextureScaled(tex, sx - screenRadius, sy - screenRadius,
                screenRadius * 2, screenRadius * 2, HUNTER_FILL_ALPHA, col.r, col.g, col.b)
            -- Always draw a label -- "??" below level 10 instead of nothing, per
            -- explicit ask. The server still never SENDS the real name below
            -- level 10 (entry.name is nil), so this is purely a client-side
            -- placeholder, not a new data exposure.
            local label = entry.name and tostring(entry.name) or "??"
            local lw = UI.tw(UI.font.small, label)
            widget:drawText(label, sx - lw / 2 + 1, sy + 1, 0, 0, 0, 0.7, UI.font.small)
            widget:drawText(label, sx - lw / 2, sy, col.r, col.g, col.b, 1.0, UI.font.small)
        end
    end
end

local HUNTER_RANGE_BORDER_THICKNESS = 2    -- was 4 -- with multiple (often adjacent/overlapping) claim rects each drawing their own full boundary, the stacked lines already read as thicker than a single one this size; a normal claim border uses isoThickness (2)
local HUNTER_RANGE_BORDER_ALPHA = 0.35   -- was 0.85

-- Native, always on when the upgrade has any range to show -- no longer
-- gated by the old "mostrar raio de detecção" Debug > Caçador toggle (that
-- flag/button is gone; maxRange<=0 below is now the only gate, so a level-0
-- faction naturally draws nothing). Draws the boundary of "how far the
-- Caçador upgrade is currently reaching" -- NOT a copy of the production
-- circles, this shows the underlying RANGE the tick actually checks distance
-- against (FF.hunterMaxRange(level)) so a member can see exactly where
-- detection stops.
--
-- Rounded, not a sharp-cornered square: FF.hunterDistanceToClaim (the metric
-- hunterTrackingTick actually checks against, shared/LFS_Hunter.lua) is
-- EUCLIDEAN, not the Chebyshev FF.rectGap other claim rules use -- so "within
-- maxRange of this rect" is truly a rounded shape (circular around a point,
-- rounded-corner around a whole rect), and FF.hunterRoundedRectPoints
-- generates the EXACT same boundary via straight edges + quarter-circle
-- corner arcs. Drawn as connected DrawLine segments (same technique
-- _drawUnionBoundary uses for claim outlines) so it stays a true curve at
-- any zoom, not a texture that would blur or pixelate.
function FFClaimMap:_drawHunterRange(widget)
    local api = self:_api()
    local jo = widget.javaObject
    if not (api and jo) then return end
    local faction = self._hunterFaction
    if not faction then return end
    local level = FF.upgradeLevel(faction, "hunter")
    local maxRange = FF.hunterMaxRange(level)
    if maxRange <= 0 then return end
    -- ONE combined boundary, not one per claim rect -- see
    -- FF.hunterCombinedClaimBounds's own comment (shared/LFS_Hunter.lua) for
    -- why: drawing each rect's boundary separately looked like several
    -- overlapping/duplicate lines ("4 áreas") wherever two claims are
    -- adjacent, which is the common case since claims must stay clustered.
    local x1, y1, x2, y2 = FF.hunterCombinedClaimBounds(faction.claims)
    if not x1 then return end
    local col = UI.color.warn
    local pts = FF.hunterRoundedRectPoints(x1, y1, x2 + 1, y2 + 1, maxRange)
    local prevX, prevY
    for i, p in ipairs(pts) do
        local sx, sy = api:worldToUIX(p[1], p[2]), api:worldToUIY(p[1], p[2])
        if prevX then
            jo:DrawLine(nil, prevX, prevY, sx, sy, HUNTER_RANGE_BORDER_THICKNESS,
                col.r, col.g, col.b, HUNTER_RANGE_BORDER_ALPHA)
        end
        prevX, prevY = sx, sy
    end
    -- Close the loop back to the first point.
    if pts[1] and prevX then
        local sx, sy = api:worldToUIX(pts[1][1], pts[1][2]), api:worldToUIY(pts[1][1], pts[1][2])
        jo:DrawLine(nil, prevX, prevY, sx, sy, HUNTER_RANGE_BORDER_THICKNESS,
            col.r, col.g, col.b, HUNTER_RANGE_BORDER_ALPHA)
    end
end

-- ---------------------------------------------------------------------------
-- Public API (used by the panel's Claims tab)
-- ---------------------------------------------------------------------------
-- Plain Draw always means a PRIVATE rect, so entering it clears shop mode. Without
-- that, arming Shop and then pressing Draw would quietly keep drawing public areas.
function FFClaimMap:setDrawMode(b)
    self.drawMode = b and true or false
    self.shopMode = false
    if self.drawMode then self.eraseMode = false end   -- the two modes are exclusive
    if not self.drawMode then
        self._dragStart = nil
        self._dragCur = nil
    end
end

function FFClaimMap:isDrawMode() return self.drawMode end

function FFClaimMap:setEraseMode(b)
    self.eraseMode = b and true or false
    if self.eraseMode then
        self.drawMode = false
        self.shopMode = false
        self._dragStart = nil
        self._dragCur = nil
    end
end

function FFClaimMap:isEraseMode() return self.eraseMode end
function FFClaimMap:isShopMode() return self.shopMode end

-- Logical areas presented by the editor. A non-rectangular union can be backed by
-- several rectangles, but remains one row/one quota slot/one delete operation.
function FFClaimMap:areaGroups()
    local out = {}
    for _, indices in ipairs(FF.claimComponents(self.rects, true)) do
        local g = { indices = indices, rects = {}, area = 0, new = false }
        for _, index in ipairs(indices) do
            local r = self.rects[index]
            g.rects[#g.rects + 1] = r
            g.area = g.area + FF.rectArea(r)
            g.new = g.new or r.new == true
            g.x1 = g.x1 and math.min(g.x1, r[1]) or r[1]
            g.y1 = g.y1 and math.min(g.y1, r[2]) or r[2]
            g.x2 = g.x2 and math.max(g.x2, r[3]) or r[3]
            g.y2 = g.y2 and math.max(g.y2, r[4]) or r[4]
        end
        g.rect = g.rects[1]
        out[#out + 1] = g
    end
    return out
end

-- Remove one logical connected area by its row index.
function FFClaimMap:removeIndex(i)
    local group = self:areaGroups()[i]
    if not group then return end
    table.sort(group.indices, function(a, b) return a > b end)
    for _, index in ipairs(group.indices) do table.remove(self.rects, index) end
end

-- Zoom/centre the map on one logical area (clicking an area row).
function FFClaimMap:focusRect(i)
    local group = self:areaGroups()[i]
    local mapui = self.mapui
    if not (group and mapui and mapui.zoomAndCentreMapToBounds) then return end
    mapui:zoomAndCentreMapToBounds(group.x1, group.y1, group.x2, group.y2)
end

-- Apply one access policy to every rectangle fragment of a logical area, then fold
-- the set again so adjacent fragments with the new matching policy can merge.
function FFClaimMap:applyAreaAccess(targets, access, grants)
    local live = {}
    for _, r in ipairs(self.rects or {}) do live[r] = true end
    local changed = false
    for _, r in ipairs(targets or {}) do
        if live[r] then FF.sanitiseArea(r, access, grants); changed = true end
    end
    if changed then self.rects = FF.canonicaliseClaimRects(self.rects) end
end

-- The working set as it goes on the wire: geometry plus each area's access level.
-- `new` is deliberately dropped (a client-only "pending" marker).
function FFClaimMap:getProposedRects()
    local out = {}
    for i, r in ipairs(self.rects) do
        out[i] = FF.sanitiseArea({ r[1], r[2], r[3], r[4] }, r.access, r.grants)
    end
    return FF.canonicaliseClaimRects(out)
end

-- total, maxTiles, valid, reason for the current working set (no drag rect).
function FFClaimMap:proposedInfo()
    local valid, reason, total, maxTiles = self:_validity(nil)
    return total, maxTiles, valid, reason
end

-- Plain-English text for a _validity reason key. Exposed so the Claims tab's capacity
-- bar can explain an invalid selection too: some reasons (too many public areas, too
-- scattered) come from an edit made in the area list, not from a drag, so the player
-- would otherwise just see Submit greyed out with no clue why.
function FFClaimMap.reasonText(key)
    return key and FF.tr(REASON_TEXT[key]) or nil
end

-- How many separate logical areas the working set currently has, and the cap.
function FFClaimMap:areaCount()
    local opts = FF.getOptions()
    return FF.claimComponentCount(self.rects),
        FF.maxClaimAreas(FF.factionScore(self.faction, opts), opts)
end

-- Order-independent fingerprint of a claim set. Includes each area's access level and
-- grants, not just its coordinates: changing an area from private to public is a real
-- edit, and if it didn't show up here hasChanges() would leave Submit disabled and
-- refresh() would overwrite the edit on the next registry sync.
-- Grants are walked from FF.AREA_GRANTS rather than listed by hand: a grant missing
-- from this fingerprint is invisible to hasChanges(), so toggling it leaves Submit
-- disabled and the next registry sync silently discards the edit. That is what a
-- hand-written list caused when `trade` was added, so the list is now derived.
local function rectSig(rects)
    local t = {}
    for _, r in ipairs(rects or {}) do
        local g = FF.areaGrants(r)
        local parts = { r[1], r[2], r[3], r[4], FF.areaAccess(r) }
        for _, key in ipairs(FF.AREA_GRANTS) do
            parts[#parts + 1] = tostring(g[key])
        end
        t[#t + 1] = table.concat(parts, ",")
    end
    table.sort(t)
    return table.concat(t, ";")
end

function FFClaimMap:hasChanges()
    return rectSig(self.rects) ~= rectSig(self.faction and self.faction.claims or {})
end

-- Submit the working set as the faction's claim (server re-validates + applies).
function FFClaimMap:submit()
    local p = getPlayer()
    if not self.faction then return end
    local rects = self:getProposedRects()
    if #rects == 0 then return end   -- clearing everything is the Unclaim button's job
    FF.requestClaim(p, rects)
    -- Advisory: the server re-validates and may still reject, but confirm the send
    -- so the click isn't silent (the map itself repaints from the registry sync).
    if p and HaloTextHelper then HaloTextHelper.addText(p, FF.tr("Claim submitted")) end
end

-- Re-read the registry and (re)load the working set from the saved claim.
--
-- The panel re-runs this on every registry sync, so we must NOT blow away a
-- player's in-progress edits on an unrelated update: we only rebuild the working
-- set (and reframe) when the saved claim or the faction actually changed since we
-- last loaded, or when `force` is set (the Clear button). Otherwise we just
-- refresh the faction reference and keep the current pending edits + view.
function FFClaimMap:refresh(force)
    local player = getPlayer()
    local name, faction = nil, nil
    if player then name, faction = FF.getFactionOfPlayer(player:getUsername()) end

    local savedSig = rectSig(faction and faction.claims)
    local sameFaction = (name == self.name)

    self.name = name
    self.faction = faction
    self.factionCol = name and UI.factionColor(name) or UI.color.accent

    -- Rebuild the visible allied claims every refresh (they depend on other
    -- factions + alliance state, not our own claim signature, so this runs even
    -- when the early-return below preserves our pending edits).
    self.allyRects = {}
    if name then
        for fname, f in pairs(FF.getData().factions or {}) do
            if fname ~= name and f.claims and #f.claims > 0 and FF.sharesMapWith(fname, name) then
                local rects = {}
                for _, r in ipairs(f.claims) do rects[#rects + 1] = { r[1], r[2], r[3], r[4] } end
                self.allyRects[#self.allyRects + 1] =
                    { rects = rects, name = fname, tag = f.tag or fname, col = UI.factionColor(fname) }
            end
        end
    end

    if not force and self._loaded and sameFaction and self._savedSig == savedSig then
        return  -- saved claim unchanged; preserve pending edits and the view
    end

    self._loaded = true
    self._savedSig = savedSig
    self.rects = {}
    if faction and faction.claims then
        for _, r in ipairs(faction.claims) do
            -- new = nil (saved); access/grants carried so the area list and the
            -- overlay show the level this area was actually submitted with.
            self.rects[#self.rects + 1] =
                FF.sanitiseArea({ r[1], r[2], r[3], r[4] }, r.access, r.grants)
        end
    end
    self.rects = FF.canonicaliseClaimRects(self.rects)
    self.drawMode = false
    self.eraseMode = false
    self._dragStart = nil
    self._dragCur = nil
    self:frame()
end

-- Resize the map widget (and its embedded PhunZones map) in place, then re-frame.
-- The panel calls this when the faction window is resized; the inner map is created
-- once at its original size, so we must push the new dimensions down into it too.
function FFClaimMap:resizeTo(w, h)
    if w <= 0 or h <= 0 then return end
    if self:getWidth() == w and self:getHeight() == h then return end
    self:setWidth(w)
    self:setHeight(h)
    pcall(function()
        local mapui = self.mapui
        if not mapui then return end
        mapui:setWidth(w); mapui:setHeight(h)
        local inner = mapui.map
        if inner and inner.setWidth then inner:setWidth(w); inner:setHeight(h) end
    end)
    self:frame()
end

-- Zoom/centre to the current claim, or to a neighbourhood around the player when
-- there's nothing claimed yet (reuses PhunZones' proven fit-to-bounds routine).
function FFClaimMap:frame()
    local mapui = self.mapui
    if not (mapui and mapui.zoomAndCentreMapToBounds) then return end
    if #self.rects > 0 then
        local minx, miny, maxx, maxy = 1e9, 1e9, -1e9, -1e9
        for _, r in ipairs(self.rects) do
            minx = math.min(minx, r[1]); miny = math.min(miny, r[2])
            maxx = math.max(maxx, r[3]); maxy = math.max(maxy, r[4])
        end
        mapui:zoomAndCentreMapToBounds(minx, miny, maxx, maxy)
    else
        local p = getPlayer()
        if p then
            local px, py = math.floor(p:getX()), math.floor(p:getY())
            mapui:zoomAndCentreMapToBounds(px - 80, py - 80, px + 80, py + 80)
        end
    end
end
