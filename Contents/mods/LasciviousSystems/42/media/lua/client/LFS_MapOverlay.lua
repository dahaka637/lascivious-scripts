-- Lascivious Factions System - claim overlay for the persistent world map + minimap.
--
-- Draws the local player's OWN faction claim rectangles, plus any ALLIED faction
-- that shares its map, onto both the big world map (ISWorldMap) and the always-on
-- minimap (ISMiniMapInner), each in its faction accent colour. Also draws LIVE
-- MEMBER MARKERS (own faction + allies that opted into shareMemberLocations) from
-- the server's periodic "positions" broadcast -- see drawMembers below.
--
-- Data source: PhunZones' LIVE zone layer, NOT the LasciviousFactionsSystem registry. The
-- registry (FF.getData) does not reliably/promptly reach clients for other
-- factions, whereas PhunZones zones are transmitted on every claim/relation/share
-- change (Claims.transmitZones). Each LFSFACTION_<name> zone carries its claim rects
-- as zone.points and an embedded `ffShareWith` set (added in Claims.zoneProps) of
-- the ally factions allowed to see it -- so both geometry AND visibility come from
-- the reliable channel and update the moment anything relevant changes.
--
-- We hook the two map classes' :prerender at CLASS level (the only way to reach the
-- persistent minimap we don't own), mirroring the RoleDisplaySystem/CompanionDogs
-- pattern. PhunZones' embedded ui_map is ALSO an ISMiniMapInner, so our own
-- LFS_ClaimMap marks its inner map `ffEmbedded` and we skip it here.
--
-- Isometric: the maps default to isometric, where a world square projects to a
-- rotated quad. We draw the 4 transformed corners (via worldToUIX/Y): a filled
-- axis-aligned rect when orthographic (getBoolean("Isometric")==false), else the
-- 4-corner quad outline via javaObject:DrawLine (the vanilla ISWorldMap:drawMapRect
-- technique) -- correct in both modes.

require "LFS_Shared"
require "LFS_UI"
require "LFS_Localization"
require "LFS_Upgrades"
require "LFS_Hunter"

local FF = LasciviousFactionsSystem
local UI = FF.UI

if isServer() then return end

local STYLE = UI.claimStyle
local boundaryCache = {}

local function cachedBoundary(rects)
    local parts = {}
    for _, r in ipairs(rects) do
        parts[#parts + 1] = table.concat({ r[1], r[2], r[3], r[4] }, ",")
    end
    table.sort(parts)
    local key = table.concat(parts, ";")
    local found = boundaryCache[key]
    if found then return found end
    found = FF.claimBoundarySegments(rects)
    -- Claim edits are rare; a blunt cap prevents a long-lived client that witnesses
    -- thousands of admin edits from retaining every historical outline forever.
    local count = 0
    for _ in pairs(boundaryCache) do count = count + 1 end
    if count > 128 then boundaryCache = {} end
    boundaryCache[key] = found
    return found
end

-- Draw one claim rect on `widget`, projecting its 4 world corners; iso-aware.
-- `thin` uses the lighter iso line thickness (for the small minimap).
local function drawRectProjected(widget, api, r, col, iso, thin)
    local ax, ay = api:worldToUIX(r[1], r[2]), api:worldToUIY(r[1], r[2])
    local bx, by = api:worldToUIX(r[3] + 1, r[2]), api:worldToUIY(r[3] + 1, r[2])
    local cx, cy = api:worldToUIX(r[3] + 1, r[4] + 1), api:worldToUIY(r[3] + 1, r[4] + 1)
    local dx, dy = api:worldToUIX(r[1], r[4] + 1), api:worldToUIY(r[1], r[4] + 1)
    if iso then
        local jo = widget.javaObject
        if not jo then return end
        local t = thin and STYLE.isoThinness or STYLE.isoThickness
        local a = STYLE.isoAlpha
        jo:DrawLine(nil, ax, ay, bx, by, t, col.r, col.g, col.b, a)
        jo:DrawLine(nil, bx, by, cx, cy, t, col.r, col.g, col.b, a)
        jo:DrawLine(nil, cx, cy, dx, dy, t, col.r, col.g, col.b, a)
        jo:DrawLine(nil, dx, dy, ax, ay, t, col.r, col.g, col.b, a)
    else
        local x1, y1 = math.min(ax, cx), math.min(ay, cy)
        local w, h = math.abs(cx - ax), math.abs(cy - ay)
        if w >= 2 and h >= 2 then
            widget:drawRect(x1, y1, w, h, STYLE.fillAlpha, col.r, col.g, col.b)
            widget:drawRectBorder(x1, y1, w, h, STYLE.borderAlpha, col.r, col.g, col.b)
        end
    end
end

-- Draw a rectangle UNION with only its exterior contour. Server-side claim
-- canonicalisation may encode an L shape as multiple rectangles; drawing each border
-- separately would reveal those implementation seams as fake internal divisions.
local function drawUnionProjected(widget, api, rects, col, iso, thin)
    if #rects == 0 then return end
    if not iso then
        for _, r in ipairs(rects) do
            local ax, ay = api:worldToUIX(r[1], r[2]), api:worldToUIY(r[1], r[2])
            local cx, cy = api:worldToUIX(r[3] + 1, r[4] + 1), api:worldToUIY(r[3] + 1, r[4] + 1)
            local x1, y1 = math.min(ax, cx), math.min(ay, cy)
            local rw, rh = math.abs(cx - ax), math.abs(cy - ay)
            if rw >= 2 and rh >= 2 then
                widget:drawRect(x1, y1, rw, rh, STYLE.fillAlpha, col.r, col.g, col.b)
            end
        end
    end
    local jo = widget.javaObject
    if not jo then
        for _, r in ipairs(rects) do drawRectProjected(widget, api, r, col, iso, thin) end
        return
    end
    local thickness = thin and STYLE.isoThinness or STYLE.isoThickness
    local alpha = iso and STYLE.isoAlpha or STYLE.borderAlpha
    for _, s in ipairs(cachedBoundary(rects)) do
        local ax, ay = api:worldToUIX(s[1], s[2]), api:worldToUIY(s[1], s[2])
        local bx, by = api:worldToUIX(s[3], s[4]), api:worldToUIY(s[3], s[4])
        jo:DrawLine(nil, ax, ay, bx, by, thickness, col.r, col.g, col.b, alpha)
    end
end

-- PhunZones' spatial query is not free, and drawClaims runs on the ALWAYS-ON minimap --
-- so it was doing a full getIntersectingZones every single frame. The in-world border
-- code does the identical query behind a 0.4s throttle (LFS_Borders.lua);
-- this is the map-side equivalent.
--
-- Correctness comes from the PADDING, not the TTL: we query a box larger than the
-- viewport and only reuse the result while the live viewport is still fully inside the
-- box we actually queried. A zone can therefore never scroll into view unnoticed. The
-- TTL bounds the other kind of staleness -- a claim being edited while you watch.
--
-- The cache lives on the WIDGET, not this module: drawClaims serves both the world map
-- and the minimap, which have completely different viewports, and a shared cache would
-- thrash between them every frame and cache nothing.
local ZONE_CACHE_TTL = 0.3
local ZONE_CACHE_PAD = 40   -- tiles of margin queried beyond the viewport

local function cachedZones(widget, minx, miny, maxx, maxy)
    local PZ = _G.PhunZones
    local now = getTimestamp()
    local c = widget.ffZoneCache
    if c and (now - c.at) < ZONE_CACHE_TTL
        and minx >= c.minx and maxx <= c.maxx
        and miny >= c.miny and maxy <= c.maxy then
        return c.zones
    end
    local pminx, pminy = minx - ZONE_CACHE_PAD, miny - ZONE_CACHE_PAD
    local pmaxx, pmaxy = maxx + ZONE_CACHE_PAD, maxy + ZONE_CACHE_PAD
    local zones = PZ.getIntersectingZones(pminx, pminy, pmaxx, pmaxy) or {}
    widget.ffZoneCache = { at = now, zones = zones,
        minx = pminx, miny = pminy, maxx = pmaxx, maxy = pmaxy }
    return zones
end

-- Draw every claim the local player is allowed to see, from PhunZones' live zones.
local function drawClaims(widget, showLabels)
    local api = widget.mapAPI
    if not api then return end
    local PZ = _G.PhunZones
    if not (PZ and PZ.getIntersectingZones) then return end
    local player = getPlayer()
    if not player then return end
    -- May be nil: a player with no faction still sees every PUBLIC area, which is the
    -- whole point of opening one. (This used to return early on nil, so shops were
    -- invisible to exactly the unaffiliated players most likely to be customers.)
    -- The two visibility tests below both degrade safely on a nil name -- indexing a
    -- table with a nil KEY is legal in Lua, only assigning with one is not.
    local myName = FF.getFactionOfPlayer(player:getUsername())

    local w, h = widget:getWidth(), widget:getHeight()
    -- Visible world AABB from the four screen corners (handles isometric rotation).
    local x0, x1c = api:uiToWorldX(0, 0), api:uiToWorldX(w, 0)
    local x2c, x3c = api:uiToWorldX(0, h), api:uiToWorldX(w, h)
    local y0, y1c = api:uiToWorldY(0, 0), api:uiToWorldY(w, 0)
    local y2c, y3c = api:uiToWorldY(0, h), api:uiToWorldY(w, h)
    local minx = math.floor(math.min(x0, x1c, x2c, x3c))
    local maxx = math.ceil(math.max(x0, x1c, x2c, x3c))
    local miny = math.floor(math.min(y0, y1c, y2c, y3c))
    local maxy = math.ceil(math.max(y0, y1c, y2c, y3c))

    local iso = api:getBoolean("Isometric")
    local thin = not showLabels   -- the minimap (no labels) gets the lighter line
    local prefix = FF.ZONE_PREFIX
    -- Admin moderation view: show every faction's territory regardless of the sharing
    -- rules. Resolved ONCE per draw rather than per zone -- it re-checks the access
    -- level, and this loop runs every frame the map is open. Defensive call because
    -- this file loads before the panel that defines it.
    local seeAll = FF.adminSeeAllClaims and FF.adminSeeAllClaims() or false
    -- Resolved once per draw too, same reasoning as seeAll above: a stale
    -- PhunZones zone can outlive the faction it was projected from (see
    -- Claims.factionAt's comment in LFS_Claims.lua for the full story --
    -- singleplayer save deletion doesn't reset PhunZones' own zone file).
    -- Used below to gate only the "public area, visible to everyone"
    -- bypass, so an orphaned zone's public sub-area doesn't keep showing on
    -- every player's map forever. Deliberately does NOT touch the seeAll
    -- admin path: LFS_Admin.lua's own tooling relies on admins being able
    -- to see (and right-click remove) orphaned zones.
    local factions = FF.getData().factions
    widget:setStencilRect(0, 0, w, h)
    local zones = cachedZones(widget, minx, miny, maxx, maxy)
    for _, zone in ipairs(zones) do
        local k = zone.key
        if k and string.sub(k, 1, #prefix) == prefix and zone.points then
            local fname = FF.factionNameFromZoneKey(k)
            local col = UI.factionColor(fname)
            -- Is the whole claim visible to us (ours, or an ally/pact sharing maps)?
            -- An admin with the override on sees every claim, which is the one case
            -- that ignores the owner's sharing choice.
            local zoneVisible = seeAll or (fname == myName)
                or (zone.ffShareWith and zone.ffShareWith[myName])
            -- Public areas are visible to EVERYONE regardless -- a trade hub nobody
            -- can find is pointless -- so visibility is decided per area, not per zone.
            local exists = factions[fname] ~= nil
            local access = zone.ffAreaAccess
            local labelAt = nil
            local normalRects, publicRects = {}, {}
            for i, r in ipairs(zone.points) do
                local isPublic = exists and access and access[i] == "public"
                if zoneVisible or isPublic then
                    if isPublic then publicRects[#publicRects + 1] = r
                    else normalRects[#normalRects + 1] = r end
                    -- Label the first area we actually drew, so an outsider seeing only
                    -- a public area still gets the owner's name on it.
                    if not labelAt then
                        labelAt = { r, isPublic }
                    end
                end
            end
            drawUnionProjected(widget, api, normalRects, col, iso, thin)
            drawUnionProjected(widget, api, publicRects, UI.publicClaimColor, iso, thin)
            if showLabels and labelAt then
                local anchor, pub = labelAt[1], labelAt[2]
                local lx = math.floor(api:worldToUIX(anchor[1], anchor[2])) + 3
                local ly = math.floor(api:worldToUIY(anchor[1], anchor[2])) + 2
                -- Skip labels jammed against the map edge (they'd overflow the
                -- stencil); truncate long names so they don't run off either.
                if lx >= 0 and lx <= w - 8 and ly >= 0 and ly <= h - 8 then
                    local label = tostring(zone.title or fname)
                    if pub then label = label .. " " .. FF.tr("(public)") end
                    if #label > 22 then label = string.sub(label, 1, 21) .. ".." end
                    local lc = pub and UI.publicClaimColor or col
                    widget:drawText(label, lx + 1, ly + 1, 0, 0, 0, 0.7, UIFont.Small)
                    widget:drawText(label, lx, ly, lc.r, lc.g, lc.b, 1.0, UIFont.Small)
                end
            end
        end
    end
    widget:clearStencilRect()
end

-- How long after the last server "positions" payload markers keep drawing. The
-- server broadcasts every ~5s; past this cutoff the data is stale (server gone or
-- reloaded) and we draw nothing rather than freeze markers in place forever.
local POSITIONS_STALE_SECONDS = 15

-- Draw live member markers from the server's periodic "positions" broadcast
-- (stored by LFS_Client into FF.memberPositions). The server already
-- filtered the payload to what this player may see (own faction + allies that
-- opted into shareMemberLocations), so this is draw-only. Positions are points,
-- so no isometric special-case is needed -- worldToUIX/Y projects either mode.
local function drawMembers(widget, showLabels)
    local api = widget.mapAPI
    if not api then return end
    local mp = FF.memberPositions
    if not mp or getTimestamp() - (mp.at or 0) > POSITIONS_STALE_SECONDS then return end
    local player = getPlayer()
    if not player then return end
    local me = player:getUsername()

    local w, h = widget:getWidth(), widget:getHeight()
    widget:setStencilRect(0, 0, w, h)
    for fname, list in pairs(mp.factions or {}) do
        local col = UI.factionColor(fname)
        for _, m in ipairs(list) do
            -- Skip the local player: the map already marks them natively.
            if m.u ~= me and m.x and m.y then
                local ux = api:worldToUIX(m.x, m.y)
                local uy = api:worldToUIY(m.x, m.y)
                if ux >= -8 and ux <= w + 8 and uy >= -8 and uy <= h + 8 then
                    -- Dot: dark backing square + tinted fill (no art needed).
                    widget:drawRect(ux - 4, uy - 4, 8, 8, 0.9, 0, 0, 0)
                    widget:drawRect(ux - 3, uy - 3, 6, 6, 1.0, col.r, col.g, col.b)
                    if showLabels then
                        widget:drawText(m.u, ux + 7, uy - 6, 0, 0, 0, 0.7, UIFont.Small)
                        widget:drawText(m.u, ux + 6, uy - 7, col.r, col.g, col.b, 1.0, UIFont.Small)
                    end
                end
            end
        end
    end
    widget:clearStencilRect()
end

-- Caçador upgrade (level 10 only): the same detection circles LFS_ClaimMap.lua
-- draws on the embedded Território map, ALSO on the real world map/minimap --
-- but ONLY for a player who has explicitly opted in (a personal viewing
-- preference, player:getModData().LFS_hunterShowOnWorldMap, set from the
-- Claims tab's toggle in LFS_Panel.lua -- see that file for why this must
-- stay a client-local, per-character choice with no server involvement).
-- Re-checks the LIVE level every draw, not just at toggle time: if the
-- faction drops below level 10 the overlay stops immediately, matching
-- "só aparece caso esteja no nível 10" as an ongoing condition.
--
-- Shared by drawHunterCircles and drawHunterRange below so the opt-in/level
-- gate is written once. Returns the faction, or nil if the overlay should
-- draw nothing at all right now.
local function hunterMapFaction()
    local player = getPlayer()
    if not player or player:getModData().LFS_hunterShowOnWorldMap ~= true then return nil end
    local _, faction = FF.getFactionOfPlayer(player:getUsername())
    if not faction or FF.upgradeLevel(faction, "hunter") < 10 then return nil end
    return faction
end

local HUNTER_MAP_FILL_ALPHA = 0.22
local HUNTER_MAP_CIRCLE_BORDER_THICKNESS = 2
local HUNTER_MAP_CIRCLE_BORDER_ALPHA = 0.35   -- was 0.9, then 0.55 -- lowered again per explicit ask
local HUNTER_MAP_CIRCLE_SEGMENTS = 24

-- Draws one detection circle. ORTHOGRAPHIC: a world-space circle still
-- projects to a screen-space circle, so the cheap texture-fill approach
-- (sample the centre + one edge point, scale a round texture) is correct.
-- ISOMETRIC: a world-space circle projects to a ROTATED ELLIPSE, not a
-- circle -- the single-X-sample technique silently drew a WRONG, skewed
-- shape here (this mod defaults to isometric, so this was the common case,
-- not an edge case). Fixed the same way drawRectProjected/drawUnionProjected
-- above already handle their own iso case: transform each point of the true
-- world-space boundary individually via worldToUIX/Y and connect them with
-- DrawLine. FF.hunterRoundedRectPoints (shared/LFS_Hunter.lua) generates that
-- boundary for a plain circle too -- a zero-size "rect" (x1==x2, y1==y2)
-- degenerates its 4 quarter-arcs into one continuous full circle.
--
-- Border only, NOT filled, in iso mode -- a ring-stacking fill approximation
-- was tried here and explicitly rejected ("ficou tenebrosamente horrível") --
-- reverted to a single outline, just at a lower alpha. Matches
-- drawRectProjected's own iso case (border only there too, for the same
-- underlying reason: drawTextureScaled has no rotation parameter, so a
-- textured fill can't follow a rotated ellipse without a custom asset).
local function drawHunterCircle(widget, api, iso, jo, tex, col, cx, cy, radius, label)
    if iso then
        if not jo then return end
        local pts = FF.hunterRoundedRectPoints(cx, cy, cx, cy, radius, HUNTER_MAP_CIRCLE_SEGMENTS)
        local prevX, prevY
        for _, p in ipairs(pts) do
            local px, py = api:worldToUIX(p[1], p[2]), api:worldToUIY(p[1], p[2])
            if prevX then
                jo:DrawLine(nil, prevX, prevY, px, py, HUNTER_MAP_CIRCLE_BORDER_THICKNESS,
                    col.r, col.g, col.b, HUNTER_MAP_CIRCLE_BORDER_ALPHA)
            end
            prevX, prevY = px, py
        end
    elseif tex then
        local sx, sy = api:worldToUIX(cx, cy), api:worldToUIY(cx, cy)
        -- Both samples share the same Y so only the X delta reflects the
        -- horizontal tile span at the map's current zoom -- valid ONLY in
        -- orthographic mode, where X and Y scale identically.
        local edgeX = api:worldToUIX(cx + radius, cy)
        local screenRadius = math.max(2, math.abs(edgeX - sx))
        widget:drawTextureScaled(tex, sx - screenRadius, sy - screenRadius,
            screenRadius * 2, screenRadius * 2, HUNTER_MAP_FILL_ALPHA, col.r, col.g, col.b)
    end
    if label then
        local sx, sy = api:worldToUIX(cx, cy), api:worldToUIY(cx, cy)
        local lw = UI.tw(UIFont.Small, label)
        widget:drawText(label, sx - lw / 2 + 1, sy + 1, 0, 0, 0, 0.7, UIFont.Small)
        widget:drawText(label, sx - lw / 2, sy, col.r, col.g, col.b, 1.0, UIFont.Small)
    end
end

local function drawHunterCircles(widget, showLabels)
    local api = widget.mapAPI
    if not api then return end
    local faction = hunterMapFaction()
    if not faction then return end
    local detected = faction.hunter and faction.hunter.detected
    if not detected then return end

    local iso = api:getBoolean("Isometric")
    local jo = iso and widget.javaObject or nil
    local tex = (not iso) and UI.icon("ui_circle_fill") or nil
    if iso and not jo then return end
    if not iso and not tex then return end

    local col = UI.color.bad
    local w, h = widget:getWidth(), widget:getHeight()
    widget:setStencilRect(0, 0, w, h)
    for _, entry in pairs(detected) do
        local cx, cy, radius = entry.cx, entry.cy, entry.radius
        if cx and cy and radius and radius > 0 then
            local label = showLabels and (entry.name and tostring(entry.name) or "??") or nil
            drawHunterCircle(widget, api, iso, jo, tex, col, cx, cy, radius, label)
        end
    end
    widget:clearStencilRect()
end

-- Max-range boundary (the same "how far the Caçador upgrade reaches" outline
-- FFClaimMap:_drawHunterRange draws natively on the embedded Território map),
-- now also on the real map/minimap when the player has opted in. Already
-- iso-correct BY CONSTRUCTION -- FF.hunterRoundedRectPoints is generated in
-- world space and each point is transformed individually below, exactly the
-- technique drawUnionProjected uses for claim borders, so there is no
-- separate isometric branch needed here at all.
local HUNTER_MAP_RANGE_BORDER_THICKNESS = 2
local HUNTER_MAP_RANGE_BORDER_ALPHA = 0.35   -- was 0.85

local function drawHunterRange(widget)
    local api = widget.mapAPI
    local jo = widget.javaObject
    if not (api and jo) then return end
    local faction = hunterMapFaction()
    if not faction then return end
    local level = FF.upgradeLevel(faction, "hunter")
    local maxRange = FF.hunterMaxRange(level)
    if maxRange <= 0 then return end

    -- ONE combined boundary, not one per claim rect -- see
    -- FF.hunterCombinedClaimBounds's own comment (shared/LFS_Hunter.lua) for
    -- why: separate per-rect outlines looked like duplicate/crossing lines
    -- ("4 áreas") wherever two claims are adjacent, the common case.
    local x1, y1, x2, y2 = FF.hunterCombinedClaimBounds(faction.claims)
    if not x1 then return end
    local col = UI.color.warn
    local pts = FF.hunterRoundedRectPoints(x1, y1, x2 + 1, y2 + 1, maxRange)

    -- setStencilRect is NOT optional here -- missed the first time around,
    -- and DrawLine happily draws PAST the widget's own bounds with no clip
    -- of its own, unlike drawRect. On the always-on minimap that meant a
    -- large-radius boundary (up to 1500 tiles at level 10) bled straight
    -- through the minimap's small viewport into the rest of the screen --
    -- every other draw function in this file (drawClaims, drawNoClaim,
    -- drawMembers, drawHunterCircles) already wraps itself in
    -- setStencilRect/clearStencilRect for exactly this reason.
    local w, h = widget:getWidth(), widget:getHeight()
    widget:setStencilRect(0, 0, w, h)
    local prevX, prevY
    for i, p in ipairs(pts) do
        local sx, sy = api:worldToUIX(p[1], p[2]), api:worldToUIY(p[1], p[2])
        if prevX then
            jo:DrawLine(nil, prevX, prevY, sx, sy, HUNTER_MAP_RANGE_BORDER_THICKNESS,
                col.r, col.g, col.b, HUNTER_MAP_RANGE_BORDER_ALPHA)
        end
        prevX, prevY = sx, sy
        if i == #pts then
            local fx, fy = api:worldToUIX(pts[1][1], pts[1][2]), api:worldToUIY(pts[1][1], pts[1][2])
            jo:DrawLine(nil, sx, sy, fx, fy, HUNTER_MAP_RANGE_BORDER_THICKNESS,
                col.r, col.g, col.b, HUNTER_MAP_RANGE_BORDER_ALPHA)
        end
    end
    widget:clearStencilRect()
end

-- Admin no-claim zones: areas where no faction may claim land. Areas rather than points,
-- so this goes through drawRectProjected and needs the isometric case.
-- Reads the replicated registry directly (data.noClaim is a plain global table).
--
-- Drawn for everyone, not just admins: knowing where you cannot claim before you open
-- the Claims editor is the whole point.
local NOCLAIM_COLOR = { r = 0.85, g = 0.25, b = 0.25 }

local function drawNoClaim(widget, showLabels)
    local api = widget.mapAPI
    if not api then return end
    local zones = FF.getData().noClaim
    if not zones then return end
    local w, h = widget:getWidth(), widget:getHeight()
    local iso = api:getBoolean("Isometric")
    local thin = not showLabels
    widget:setStencilRect(0, 0, w, h)
    for _, zone in pairs(zones) do
        local labelled = false
        for _, r in ipairs(zone.points or {}) do
            -- Screen-cull on the rect's centre before projecting all four corners --
            -- this runs on the always-on minimap.
            local mx = math.floor((r[1] + r[3]) / 2)
            local my = math.floor((r[2] + r[4]) / 2)
            local ux, uy = api:worldToUIX(mx, my), api:worldToUIY(mx, my)
            local span = math.max(r[3] - r[1], r[4] - r[2])
            local pad = math.max(16, span)
            if ux >= -pad and ux <= w + pad and uy >= -pad and uy <= h + pad then
                drawRectProjected(widget, api, r, NOCLAIM_COLOR, iso, thin)
                if showLabels and not labelled then
                    labelled = true
                    local label = FF.text("UI_LFS_NoClaimsMarker", "NO CLAIMS -- %s",
                        tostring(zone.name or zone.id))
                    if #label > 34 then label = string.sub(label, 1, 33) .. ".." end
                    widget:drawText(label, ux + 1, uy + 1, 0, 0, 0, 0.7, UIFont.Small)
                    widget:drawText(label, ux, uy, NOCLAIM_COLOR.r, NOCLAIM_COLOR.g,
                        NOCLAIM_COLOR.b, 1.0, UIFont.Small)
                end
            end
        end
    end
    widget:clearStencilRect()
end

-- Fail-streak self-disable per draw kind, mirroring LFS_Nameplates.lua's
-- NP_FAIL_LIMIT pattern: these pcalls previously discarded their result entirely, so a
-- persistent render failure silently dropped a whole feature (e.g. claim borders) off
-- the map with zero trace anywhere. A single bad frame is not disable-worthy (transient
-- state mid-update); a sustained run of failures logs once and stops, rather than
-- calling FF.warn 60x/second forever.
local DRAW_FAIL_LIMIT = 120
local drawFailStreak = { claims = 0, members = 0, hunter = 0, hunterRange = 0 }
local drawDisabled = { claims = false, members = false, hunter = false, hunterRange = false }

local function guardedDraw(kind, fn, ...)
    if drawDisabled[kind] then return end
    local ok, err = pcall(fn, ...)
    if ok then
        drawFailStreak[kind] = 0
        return
    end
    drawFailStreak[kind] = drawFailStreak[kind] + 1
    if drawFailStreak[kind] >= DRAW_FAIL_LIMIT then
        drawDisabled[kind] = true
        FF.warn("map overlay '" .. kind .. "' draw failed on " .. DRAW_FAIL_LIMIT
            .. " consecutive frames: " .. tostring(err) .. " (disabled)")
    end
end

-- Install the class-level prerender hooks once PZ's map classes exist. Returns
-- whether both are installed -- Events.OnGameStart can fire before ISWorldMap/
-- ISMiniMapInner are defined globals (observed after a game update; previously this
-- was a single unconditional call here with no retry, which meant a session that hit
-- that timing never installed the hooks at all -- no exception, no warning, nothing
-- in any log, just claims silently never drawing on the map or minimap for the whole
-- session). Retried below, mirroring LFS_LegacyClient.lua's schedulePatchInstall.
local function installHooks()
    if _G.ISWorldMap and not ISWorldMap.__ffOrigPrerender then
        ISWorldMap.__ffOrigPrerender = ISWorldMap.prerender
        function ISWorldMap:prerender()
            if ISWorldMap.__ffOrigPrerender then ISWorldMap.__ffOrigPrerender(self) end
            guardedDraw("claims", drawClaims, self, true)    -- labels on the big map
            guardedDraw("noclaim", drawNoClaim, self, true)
            guardedDraw("members", drawMembers, self, true)
            guardedDraw("hunter", drawHunterCircles, self, true)
            guardedDraw("hunterRange", drawHunterRange, self)
        end
    end
    if _G.ISMiniMapInner and not ISMiniMapInner.__ffOrigPrerender then
        ISMiniMapInner.__ffOrigPrerender = ISMiniMapInner.prerender
        function ISMiniMapInner:prerender()
            if ISMiniMapInner.__ffOrigPrerender then ISMiniMapInner.__ffOrigPrerender(self) end
            if self.ffEmbedded then return end   -- our embedded Claims map draws its own
            local opts = FF.getOptions()
            -- The admin override bypasses the server's minimap preference too. Without
            -- this, ticking it on a server with ShowClaimsOnMinimap off would light up
            -- the world map but not the minimap -- a half-working toggle reads as a bug.
            local seeAll = FF.adminSeeAllClaims and FF.adminSeeAllClaims() or false
            if opts.showClaimsOnMinimap or seeAll then
                guardedDraw("claims", drawClaims, self, false)
            end
            -- No-claim zones follow the claim toggle: they are claim information, and a
            -- player who turned claim shading off on the minimap does not want them.
            if opts.showClaimsOnMinimap or seeAll then
                guardedDraw("noclaim", drawNoClaim, self, false)
            end
            if opts.showMembersOnMinimap then guardedDraw("members", drawMembers, self, false) end
            -- Hunter overlay is gated purely by the player's own opt-in + live level
            -- (both checked inside drawHunterCircles/drawHunterRange themselves) --
            -- no server sandbox option involved, unlike claims/members above, since
            -- this is a personal preference, not a server-wide display policy.
            guardedDraw("hunter", drawHunterCircles, self, false)
            guardedDraw("hunterRange", drawHunterRange, self)
        end
    end
    local worldMapDone = _G.ISWorldMap ~= nil and ISWorldMap.__ffOrigPrerender ~= nil
    local miniMapDone = _G.ISMiniMapInner ~= nil and ISMiniMapInner.__ffOrigPrerender ~= nil
    return worldMapDone and miniMapDone
end

local mapOverlayInstallAttempts = 0

local function scheduleInstallHooks()
    if installHooks() then return end
    if not Events.OnTick then return end
    if FF._mapOverlayInstallTick then Events.OnTick.Remove(FF._mapOverlayInstallTick) end
    mapOverlayInstallAttempts = 0
    FF._mapOverlayInstallTick = function()
        mapOverlayInstallAttempts = mapOverlayInstallAttempts + 1
        local done = installHooks()
        if not done and mapOverlayInstallAttempts >= 120 then
            FF.warn("map overlay hooks never installed after 120 attempts -- ISWorldMap present="
                .. tostring(_G.ISWorldMap ~= nil) .. " ISMiniMapInner present="
                .. tostring(_G.ISMiniMapInner ~= nil))
        end
        if done or mapOverlayInstallAttempts >= 120 then
            Events.OnTick.Remove(FF._mapOverlayInstallTick)
            FF._mapOverlayInstallTick = nil
        end
    end
    Events.OnTick.Add(FF._mapOverlayInstallTick)
end

if FF._mapOverlayInstallHook then Events.OnGameStart.Remove(FF._mapOverlayInstallHook) end
FF._mapOverlayInstallHook = scheduleInstallHooks
Events.OnGameStart.Add(scheduleInstallHooks)
