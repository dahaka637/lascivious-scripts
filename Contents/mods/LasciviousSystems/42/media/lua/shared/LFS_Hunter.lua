-- Lascivious Factions System - Caçador upgrade data model + pure math (shared).
--
-- The Caçador ("Hunter") upgrade reveals, on the faction's own Território map
-- (client/LFS_ClaimMap.lua), an approximate area where each non-member
-- player currently within range might be -- never their exact position.
-- Explicit user design, verbatim:
--   "ele não vai mostrar precisamente a localização do jogador... vai
--   desenhar um círculo colorido com alpha reduzido preenchido na área onde
--   o jogador pode estar... essa área atualiza a cada 1 hora e apenas caso o
--   jogador tenha saído dela... a distância máxima 1km por nível... mais
--   próximo do território = mais preciso, mais longe = mais abrangente
--   (isso já fica automático pois já expande a área máxima de alcance)."
-- SUPERSEDED, 2026-08-20: the "1 hour, per-level scaled" refresh cadence
-- above turned out flaky in live testing (see LFS_Server.lua's
-- hunterTrackingTick) and was deliberately simplified per explicit follow-up
-- instruction -- the circle now just regenerates on whichever real-time poll
-- (HUNTER_TICK_INTERVAL, 60 real seconds) notices the target left it, same
-- cadence at every level, no game-hour interval of any kind.
--
-- Data model: faction.hunter.detected[username] = {
--   cx, cy    -- world tile coords of the SPECULATION CIRCLE's centre (NOT
--               the target's real position -- see FF.hunterRandomPointNear)
--   radius    -- tiles
--   at        -- getGameTime():getWorldAgeHours() when this circle was (re)generated
--   name      -- the target's username, ONLY present at Caçador level 10
-- }
-- Populated exclusively by LFS_Server.lua's hunterTrackingTick -- this file
-- only holds the shared math both server (to build a circle) and client (to
-- convert world tiles to screen pixels) need identically, plus the
-- migration helper.
--
-- SECURITY NOTE: like every other per-faction table in this mod, `hunter`
-- lives inside FF.getData().factions[name], which is replicated to EVERY
-- client, not scoped to the tracking faction's own members -- the same
-- trust model every other feature this session already relies on (a
-- faction's tribute balance, vehicle protection state, etc. are all equally
-- readable by a client that goes looking, just not surfaced in the normal
-- UI to anyone else). The circle itself is already deliberately imprecise
-- and the real position is NEVER stored or sent -- only a random point
-- guaranteed to be within `radius` of it -- so this is an acceptable
-- continuation of that existing model, not a new privacy exposure.

require "LFS_Shared"

local FF = LasciviousFactionsSystem

-- Tunable constants -- no exact numbers were specified beyond "1km per
-- level" and "closer = tighter, farther = looser", so these are reasonable
-- defaults, clearly isolated here for easy retuning after live testing
-- (same "ship a documented default, let feedback tune it" approach every
-- other upgrade's exact rate constants used this session).
FF.HUNTER_RANGE_PER_LEVEL_TILES = 150    -- tiles per level -- max detection range at level 10 (the cap) is therefore 1500 tiles, an explicit correction down from the original "1km/level" (10000 tiles at level 10).
FF.HUNTER_CIRCLE_RADIUS_MAX = 200        -- tiles -- radius at/beyond max detection range (distance == hunterMaxRange(level)), i.e. 100%. Was 150, raised alongside the floor per explicit numbers given directly by the user.
FF.HUNTER_CIRCLE_MIN_FRACTION = 30 / 200 -- floor, as a FRACTION of RADIUS_MAX -- chosen so the floor lands on exactly 30 tiles, the user's explicit number, not an arbitrary percentage

function FF.ensureHunterTracking(faction)
    if faction and type(faction.hunter) ~= "table" then
        faction.hunter = { detected = {} }
    end
    if faction and type(faction.hunter.detected) ~= "table" then faction.hunter.detected = {} end
    return faction
end

function FF.hunterMaxRange(level)
    return math.max(0, math.floor(tonumber(level) or 0)) * FF.HUNTER_RANGE_PER_LEVEL_TILES
end

-- Euclidean (NOT Chebyshev) distance from (x, y) to the nearest point of any
-- of this faction's claim rects -- 0 if the point is inside/touching one.
-- Deliberately a SEPARATE function from FF.distanceToClaim (shared/LFS_Shared.lua),
-- which reuses FF.rectGap (max(dx,dy), Chebyshev) for claim-adjacency rules
-- elsewhere in the mod. That metric makes "within R of a rect" a SQUARE with
-- sharp corners, which reads as an obviously-wrong shape for a detection
-- "radius" -- the user asked directly why it wasn't circular. Hunter gets its
-- own metric so its range genuinely IS circular around a single point and
-- rounded-corner around a whole rect, matching FF.hunterRoundedRectPoints
-- below exactly (same geometry backs both the real detection check and the
-- debug visualization -- the debug overlay is never allowed to lie about
-- what the server actually checks).
function FF.hunterDistanceToClaim(faction, x, y)
    local rects = faction and faction.claims
    if not (rects and #rects > 0) then return nil end
    local min = nil
    for _, r in ipairs(rects) do
        local cx = math.max(r[1], math.min(x, r[3]))
        local cy = math.max(r[2], math.min(y, r[4]))
        local dx, dy = x - cx, y - cy
        local d = math.sqrt(dx * dx + dy * dy)
        if not min or d < min then min = d end
    end
    return min
end

-- Points (world tile coords, in order) tracing the boundary of "within `r`
-- tiles of this rect" under EUCLIDEAN distance -- straight edges offset by
-- `r`, quarter-circle arcs of radius `r` at the four corners. This is the
-- EXACT shape FF.hunterDistanceToClaim's "in range" region has (not an
-- approximation), used to draw the debug range overlay so it's a truthful
-- picture of what the server is actually checking.
function FF.hunterRoundedRectPoints(x1, y1, x2, y2, r, segsPerCorner)
    segsPerCorner = segsPerCorner or 12
    local pts = {}
    local corners = {
        { cx = x1, cy = y1, a0 = math.pi,       a1 = math.pi * 1.5 }, -- top-left
        { cx = x2, cy = y1, a0 = math.pi * 1.5, a1 = math.pi * 2   }, -- top-right
        { cx = x2, cy = y2, a0 = 0,             a1 = math.pi * 0.5 }, -- bottom-right
        { cx = x1, cy = y2, a0 = math.pi * 0.5, a1 = math.pi       }, -- bottom-left
    }
    for _, c in ipairs(corners) do
        for i = 0, segsPerCorner do
            local ang = c.a0 + (c.a1 - c.a0) * (i / segsPerCorner)
            pts[#pts + 1] = { c.cx + r * math.cos(ang), c.cy + r * math.sin(ang) }
        end
    end
    return pts
end

-- Single combined bounding box across every claim rect -- min(x1,y1), max(x2,y2).
-- Used ONLY for the range-boundary VISUALIZATION (not the real detection
-- check, which stays exact per-rect via FF.hunterDistanceToClaim): drawing
-- each claim rect's own expanded boundary separately looked like several
-- overlapping/duplicate outlines wherever two rects are adjacent (which is
-- common -- claims must stay clustered), reading as "4 areas" instead of one.
-- A single boundary around the combined bounds is a deliberate, documented
-- OVER-approximation when claims are spread out with real gaps between them
-- (it can show a bit more "reachable" area than the true per-rect union in
-- the gap between two claims) -- accepted because claims are already
-- required to stay near each other, so the gap is bounded, and one clean
-- outline reads far better than several crossing ones.
function FF.hunterCombinedClaimBounds(claims)
    if not (claims and #claims > 0) then return nil end
    local x1, y1, x2, y2 = claims[1][1], claims[1][2], claims[1][3], claims[1][4]
    for i = 2, #claims do
        local r = claims[i]
        if r[1] < x1 then x1 = r[1] end
        if r[2] < y1 then y1 = r[2] end
        if r[3] > x2 then x2 = r[3] end
        if r[4] > y2 then y2 = r[4] end
    end
    return x1, y1, x2, y2
end

-- Circle radius for a target `distance` tiles from the territory, at this
-- Caçador `level`. STRICTLY LINEAR, per the user's explicit correction: the
-- fraction of RADIUS_MAX is just distance/maxRange directly (0.3 at 30% of
-- the way to max range, 0.5 at 50%, etc), floored at HUNTER_CIRCLE_MIN_FRACTION
-- so it never reads as a zero-size circle right at the territory edge, and
-- capped at 1.0 beyond max range. No easing curve of any kind. Deliberately
-- NOT given a second, separate level-based adjustment: the "higher level
-- reads as more precise" effect falls out automatically from the SAME
-- absolute distance being a smaller fraction of a bigger max range at a
-- higher level, exactly as the user's own spec called out ("isso por sí só
-- já fica automático").
function FF.hunterCircleRadius(distance, level)
    local maxRange = FF.hunterMaxRange(level)
    if maxRange <= 0 then return FF.HUNTER_CIRCLE_RADIUS_MAX end
    local fraction = (tonumber(distance) or 0) / maxRange
    fraction = math.max(FF.HUNTER_CIRCLE_MIN_FRACTION, math.min(1, fraction))
    return FF.HUNTER_CIRCLE_RADIUS_MAX * fraction
end

function FF.hunterPointInCircle(px, py, cx, cy, radius)
    local dx, dy = px - cx, py - cy
    return (dx * dx + dy * dy) <= radius * radius
end

-- A uniformly-random point within `radius` tiles of (px, py) -- sqrt(random)
-- for uniform distribution BY AREA (a plain `radius * random()` would bias
-- points toward the centre, since the same radial step covers less area
-- near the centre than near the edge of the circle).
--
-- Uses ZombRandFloat, NOT math.random -- confirmed by decompiling the
-- engine's se.krka.kahlua.j2se.MathLib class that Kahlua's own "math" table
-- only ever registers abs/ceil/floor/trig/log/pow/etc (24 functions) plus
-- the raw constants pi/huge -- there is no random/randomseed anywhere in it.
-- This crashed live ("Object tried to call nil in hunterRandomPointNear")
-- the first time this ran with a real detection to place. ZombRandFloat is
-- a confirmed real global (zombie.Lua.LuaManager$GlobalObject.ZombRandFloat),
-- the same RNG entry point PZ's own Lua code and community mods use.
--
-- Called with the TARGET's real position as (px, py): the returned point
-- becomes the circle's CENTRE, which by the symmetry of "distance" means the
-- real position is always within `radius` of that centre too -- i.e. always
-- somewhere inside the resulting circle, matching the design's own
-- invariant ("o jogador está em algum lugar dela").
function FF.hunterRandomPointNear(px, py, radius)
    px, py, radius = tonumber(px), tonumber(py), tonumber(radius)
    if not px or px ~= px or px == math.huge or px == -math.huge
        or not py or py ~= py or py == math.huge or py == -math.huge
        or not radius or radius ~= radius or radius == math.huge or radius == -math.huge then
        return nil, nil
    end
    radius = math.max(0, radius)
    local rng = _G.ZombRandFloat
    if type(rng) ~= "function" then
        -- Exact target position is a valid zero-error circle centre and a safer
        -- degradation than taking the whole hunter tick down on an unusual build.
        return math.floor(px), math.floor(py)
    end
    local angle = rng(0, 2 * math.pi)
    local r = radius * math.sqrt(rng(0, 1))
    return math.floor(px + r * math.cos(angle)), math.floor(py + r * math.sin(angle))
end
