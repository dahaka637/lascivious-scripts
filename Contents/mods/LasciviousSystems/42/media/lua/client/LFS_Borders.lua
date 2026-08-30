-- Lascivious Factions System - in-world claim border highlighting (client side).
--
-- Highlights the ground along the edge of nearby claims -- EVERY faction's, each in its
-- own colour -- so you can see whose territory you're standing next to while playing, not
-- just on the map. Visibility is a per-client setting (on / only-when-near / off).
--
-- PhunZones draws zone borders on the MAP only; there is no vanilla template for
-- 3D-world claim borders. Rather than hand-project and line-draw every frame (which
-- is fragile across camera/zoom), we use the engine's own ground-highlight system:
-- getWorldMarkers():addGridSquareMarker(square, r,g,b, overlay, radius) -- the same
-- mechanism the spawn-horde and foraging tools use. The engine renders and unprojects
-- these itself, so they track the camera correctly at any zoom.
--
-- We keep a pool of markers keyed by tile. A gated refresh (a few times a second)
-- recomputes the set of visible BORDER tiles within range and reconciles the pool:
-- add markers for newly-bordering loaded tiles, remove markers no longer on a border
-- (which also handles claim/relation changes and the player moving or changing floor
-- -- the desired set simply shrinks/grows and the pool follows). pcall-guarded and
-- self-disabling like the other client hooks.
--
-- Claim geometry is read from PhunZones' LIVE zone layer (getIntersectingZones),
-- exactly like LasciviousFactionsSystem_MapOverlay -- the reliable channel that reaches
-- joined coop clients, carrying each claim's rects (zone.points) and the ally
-- share set (zone.ffShareWith). NOT the LasciviousFactionsSystem registry.

require "LFS_Shared"
require "LFS_UI"

local FF = LasciviousFactionsSystem
local UI = FF.UI

if isServer() then return end

-- Highlight circle radius (tiles) per bordered square. Small so adjacent border
-- tiles read as a continuous edge rather than big blobs. Tunable in-game.
local BORDER_RADIUS = 0.5
local REFRESH_INTERVAL = 0.4        -- seconds between pool rebuilds
local MAX_MARKERS = 800             -- hard cap on live ground markers (perf guard)

local markers = {}                  -- ["x,y"] = worldMarker
local nextRefresh = 0
local bordersBroken = false

local function markerHandle(record)
    return type(record) == "table" and record.handle or record -- reloads old pool safely
end

-- Remove and forget every marker we placed.
local function clearAll()
    for k, m in pairs(markers) do
        pcall(function() markerHandle(m):remove() end)
        markers[k] = nil
    end
end

-- Is the marker pool non-empty? Uses pairs (not next(), which the PZ B42 Kahlua
-- sandbox does not expose as a global -- calling it throws "tried to call nil").
local function hasMarkers()
    for _ in pairs(markers) do return true end
    return false
end

-- Collect the claim rects near the local player, from PhunZones. EVERY faction's claim
-- is included (not just own + allies) so you can see whose territory you're standing
-- next to -- coloured by that faction. Returns { rect = {x1,y1,x2,y2}, col = {r,g,b} }.
local function visibleRects(minx, miny, maxx, maxy)
    local PZ = _G.PhunZones
    if not (PZ and PZ.getIntersectingZones) then return nil end
    local prefix = FF.ZONE_PREFIX
    local out = {}
    local zones = PZ.getIntersectingZones(minx, miny, maxx, maxy) or {}
    for _, zone in ipairs(zones) do
        local k = zone.key
        if k and string.sub(k, 1, #prefix) == prefix and zone.points then
            local col = UI.factionColor(FF.factionNameFromZoneKey(k))
            -- An area opened to everyone gets the shared public teal instead of the
            -- owner's colour, matching the world map and the claim editor: on the
            -- ground it should read as "you may walk in here", not as their territory.
            local access = zone.ffAreaAccess
            for i, r in ipairs(zone.points) do
                local areaAccess = (access and access[i]) or "private"
                local rectCol = areaAccess == "public" and UI.publicClaimColor or col
                local token = tostring(k) .. "\0" .. tostring(areaAccess)
                out[#out + 1] = {
                    rect = r,
                    col = rectCol,
                    -- Same-owner adjacent rectangles with the same policy merge into
                    -- one visual area, while a different owner/access policy keeps a
                    -- visible seam. Comparing only "occupied" erased borders where
                    -- two factions touched directly.
                    token = token,
                    style = token .. string.format("|%.4f,%.4f,%.4f",
                        rectCol.r, rectCol.g, rectCol.b),
                }
            end
        end
    end
    return out
end

local function refresh()
    if bordersBroken then return end
    local now = getTimestamp()
    if now < nextRefresh then return end
    nextRefresh = now + REFRESH_INTERVAL

    local opts = FF.getOptions()
    -- Per-client visibility: "off" (never) / "near" (only when close) / "on". Also honours
    -- a server hard-disable. Fall back to the sandbox var if the helper isn't loaded yet.
    local borderMode = FF.claimBorderMode and FF.claimBorderMode()
        or (opts.showClaimBordersInWorld and "on" or "off")
    if borderMode == "off" then
        if hasMarkers() then clearAll() end
        return
    end

    local player = getPlayer()
    if not player then
        if hasMarkers() then clearAll() end
        return
    end

    local ok, err = pcall(function()
        local cell = getCell()
        if not cell then return end
        -- "near" uses a tight radius so only claims you're right up against light up.
        local range = opts.claimBorderRange or 24
        if borderMode == "near" then range = math.min(range, 8) end
        local px, py = math.floor(player:getX()), math.floor(player:getY())
        local pz = math.floor(player:getZ())
        local minx, maxx = px - range, px + range
        local miny, maxy = py - range, py + range

        local vis = visibleRects(minx, miny, maxx, maxy)
        if not vis or #vis == 0 then
            if hasMarkers() then clearAll() end
            return
        end

        -- Rasterise each clipped rectangle once into sparse x rows. The previous
        -- implementation scanned every visible rectangle up to five times for every
        -- tile in the range window (area * claims * neighbours) every refresh.
        -- Include a one-tile halo so the range-window edge is not mistaken for a
        -- real claim border when the same rectangle continues just outside it.
        local occupied = {}
        for i = 1, #vis do
            local e, r = vis[i], vis[i].rect
            local x1 = math.max(minx - 1, math.floor(math.min(r[1], r[3])))
            local x2 = math.min(maxx + 1, math.floor(math.max(r[1], r[3])))
            local y1 = math.max(miny - 1, math.floor(math.min(r[2], r[4])))
            local y2 = math.min(maxy + 1, math.floor(math.max(r[2], r[4])))
            for x = x1, x2 do
                local row = occupied[x]
                if not row then row = {}; occupied[x] = row end
                for y = y1, y2 do
                    if not row[y] then row[y] = e end
                end
            end
        end

        local function ownerAt(x, y)
            local row = occupied[x]
            return row and row[y] or nil
        end

        -- Build the desired border-tile set inside the range window. A tile is on a
        -- border when it belongs to a visible claim but at least one 4-neighbour does
        -- not (works cleanly across merged/adjacent rects).
        local desired = {}
        for x, row in pairs(occupied) do
            if x >= minx and x <= maxx then
                for y, e in pairs(row) do
                    if y >= miny and y <= maxy then
                        local left, right = ownerAt(x - 1, y), ownerAt(x + 1, y)
                        local up, down = ownerAt(x, y - 1), ownerAt(x, y + 1)
                        if not (left and left.token == e.token
                            and right and right.token == e.token
                            and up and up.token == e.token
                            and down and down.token == e.token) then
                            desired[x .. "," .. y .. "," .. pz] = {
                                x = x, y = y, col = e.col, token = e.style,
                            }
                        end
                    end
                end
            end
        end

        -- Drop stale/wrong-floor/recoloured markers before counting. Records from
        -- the previous implementation are deliberately treated as stale so a Lua
        -- reload upgrades the pool without leaking the old Java markers.
        local live = 0
        for key, record in pairs(markers) do
            local d = desired[key]
            if not d or type(record) ~= "table" or record.token ~= d.token then
                pcall(function() markerHandle(record):remove() end)
                markers[key] = nil
            else
                live = live + 1
            end
        end

        -- Add markers for newly-bordering, currently-loaded tiles (up to the cap).
        for key, d in pairs(desired) do
            if live >= MAX_MARKERS then break end
            if not markers[key] then
                local sq = cell:getGridSquare(d.x, d.y, pz)
                if sq then
                    local m = getWorldMarkers():addGridSquareMarker(
                        sq, d.col.r, d.col.g, d.col.b, true, BORDER_RADIUS)
                    if m then
                        markers[key] = { handle = m, token = d.token }
                        live = live + 1
                    end
                end
            end
        end
    end)

    if not ok then
        bordersBroken = true
        clearAll()
        FF.warn("in-world borders failed: " .. tostring(err)
            .. " (in-world borders disabled)")
    end
end

if Events.OnTick then
    if FF._borderRefreshHook then Events.OnTick.Remove(FF._borderRefreshHook) end
    if FF._borderClearHook then pcall(FF._borderClearHook) end
    FF._borderRefreshHook = refresh
    FF._borderClearHook = clearAll
    Events.OnTick.Add(refresh)
else
    FF.warn("OnTick unavailable; in-world borders disabled")
end
if Events.OnDisconnect then
    if FF._borderDisconnectHook then Events.OnDisconnect.Remove(FF._borderDisconnectHook) end
    FF._borderDisconnectHook = clearAll
    Events.OnDisconnect.Add(clearAll)
end
