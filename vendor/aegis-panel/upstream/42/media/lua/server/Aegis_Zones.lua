-- Zones page, server side: safehouse list, rectangle adjustment and
-- freeform zones. A painted tile shape is split into several SafeHouse
-- rectangles (same owner, same members); the engine checks every
-- protection per tile across the WHOLE list, so the union of the
-- rectangles is real protection in tile shape (bytecode verified:
-- findSafeHouse iterates everything, containment half-open).
--
-- A zone's truth is its TILE SET, not the rectangle list. Every edit
-- reads main plus annexes as tiles, applies the change to the tiles and
-- splits the result into maximal rectangles again. Two pieces that touch
-- and together form a rectangle end up as ONE safehouse, so an extension
-- never looks like a second zone. Annexes carry the main's title for the
-- same reason. Nothing can shrink away silently either: the split runs
-- before anything is torn down, and an empty result is refused.
--
-- That rule does not stop at the zone border: two zones of the SAME
-- owner whose areas touch are one property, not two rows in the list.
-- Every shape change therefore swallows each touching zone of that owner
-- first (shared edge, no diagonals, one tile of air is not a touch) and
-- splits the union afterwards. The fusion runs before anything is torn
-- down, so a refusal leaves the world untouched.
--
-- Sync paths, since B42 has no vanilla globals for this:
--  * Create/change -> kickUserFromSafehouse(sh, "") is a no-op kick
--    but sends a SafehouseSync packet; the client side creates
--    unknown rectangles from it.
--  * Remove -> SafehouseSync can NEVER delete; the only server Lua
--    path with broadcast is the hitPoint trick: set HitPoints to
--    WarSafehouseHitPoints-1 and call SafeHouse.hitPoint(), which
--    runs the same removeSafeHouse+SafehouseRelease path as a war
--    destruction.
--  * NEVER move in place: the onlineId (Cantor of anchor x,y) is
--    created only in the constructor, setX/setY leave it alone, and
--    client sync matches by geometry -> ghost rectangles. Every
--    geometry CHANGE is therefore teardown + rebuild, main first
--    (first-match for hasSafehouse/respawn/chat must hit the main).
--    A rectangle whose x,y,w,h survive an edit is left alone entirely,
--    but only while the main survives too: a rebuilt main is appended
--    at the end of the list, so a survivor would sit in front of it.
--
-- Current clients always send the full wanted area (shShape with
-- full = true, shNew/shNewShape for fresh zones). shSet is the legacy
-- border drag of older clients: it only ever GROWS a zone, so its
-- rectangle has to touch the zone (shared edge or overlap, same test
-- as the fusion); a free floating rectangle would add a detached
-- island and split the shape a bit further with every pull.
if isClient() then return end

require "Aegis_Roles"
require "Aegis_Log"
require "Aegis_Moderation"

local MAX_PARTS = 96
local MAX_EDGE = 300
-- ceiling for the tile set an edit builds; a legal main alone is at most
-- MAX_EDGE squared, the rest is headroom for painted area. Only a broken
-- or hostile payload gets close
local MAX_TILES = 200000
-- how many zones of one owner a single edit may swallow. An owner with
-- a whole street of touching zones is not a normal case, and an open
-- count would let one click walk the entire safehouse list
local MAX_FUSE = 32

local function toClient(player, command, args)
    if isServer() then
        sendServerCommand(player, AegisShared.MODULE, command, args)
    else
        triggerEvent("OnServerCommand", AegisShared.MODULE, command, args)
    end
end

-- one-line diagnosis into the DebugLog; its own local timestamps beat the
-- UTC clock of the file logs when correlating with engine events
local function zlog(msg)
    print("[Aegis] zone " .. msg)
end

local function denyPlayer(player)
    toClient(player, "denied", { area = "zones" })
end

local function findSafehouseAt(x, y)
    local list = SafeHouse.getSafehouseList()
    for i = 0, list:size() - 1 do
        local sh = list:get(i)
        if sh:getX() == x and sh:getY() == y then return sh end
    end
    return nil
end

-- ---------- Groups: which main safehouse owns which annexes ----------
-- File Aegis/Zones/groups.txt, one line per zone:
-- G|mainX,mainY|x,y,w,h;x,y,w,h;...
local GROUPS_FILE = AegisStore.ROOT .. "/Zones/groups.txt"
local groups = nil
-- after an incomplete read nobody may write back, otherwise the unread
-- zones vanish along with the registration of their annexes
local groupsIncomplete = false
-- self claims from the player panel: username -> anchor of the one zone
-- a player may hold, kept as P| lines in the same registry file so the
-- write protection above covers them too
local playerClaims = nil

local function groupKey(x, y)
    return x .. "," .. y
end

local function loadGroups()
    if groups then return end
    groups = {}
    playerClaims = {}
    local lines, truncated = AegisStore.readLines(GROUPS_FILE, 5000)
    if lines == nil or truncated then
        groupsIncomplete = true
        print("[Aegis] Zone registry read incompletely, write protection active")
        lines = lines or {}
    end
    for _, line in ipairs(lines) do
        local hx, hy, remaining = line:match("^G|(%d+),(%d+)|(.*)$")
        if hx then
            local parts = {}
            for rx, ry, rw, rh in remaining:gmatch("(%d+),(%d+),(%d+),(%d+)") do
                table.insert(parts, { x = tonumber(rx), y = tonumber(ry), w = tonumber(rw), h = tonumber(rh) })
            end
            groups[groupKey(tonumber(hx), tonumber(hy))] = { hx = tonumber(hx), hy = tonumber(hy), parts = parts }
        else
            local user, px, py = line:match("^P|([^|]+)|(%d+),(%d+)$")
            if user then
                playerClaims[user] = { x = tonumber(px), y = tonumber(py) }
            end
        end
    end
end

local function saveGroups()
    if groupsIncomplete then
        print("[Aegis] Zone registry write-protected, change not saved")
        return
    end
    local lines = {}
    for _, g in pairs(groups) do
        local parts = {}
        for _, r in ipairs(g.parts) do
            table.insert(parts, r.x .. "," .. r.y .. "," .. r.w .. "," .. r.h)
        end
        table.insert(lines, "G|" .. g.hx .. "," .. g.hy .. "|" .. table.concat(parts, ";"))
    end
    for user, pt in pairs(playerClaims or {}) do
        table.insert(lines, "P|" .. user:gsub("|", "_") .. "|" .. pt.x .. "," .. pt.y)
    end
    table.sort(lines)
    local content = table.concat(lines, "\n")
    if #lines > 0 then content = content .. "\n" end
    AegisStore.write(GROUPS_FILE, content)
end

-- ---------- Export for other suite features (zone backup) ----------
AegisZones = AegisZones or {}

-- copy of a zone's group, so nobody bends the registry from outside
function AegisZones.groupFor(hx, hy)
    loadGroups()
    local g = groups[groupKey(math.floor(tonumber(hx) or -1), math.floor(tonumber(hy) or -1))]
    if not g then return nil end
    local parts = {}
    for _, r in ipairs(g.parts) do
        table.insert(parts, { x = r.x, y = r.y, w = r.w, h = r.h })
    end
    return { hx = g.hx, hy = g.hy, parts = parts }
end

function AegisZones.allGroups()
    loadGroups()
    local list = {}
    for _, g in pairs(groups) do
        table.insert(list, AegisZones.groupFor(g.hx, g.hy))
    end
    return list
end

-- all annex anchors across all groups, only for the list filter
local function annexAnchors()
    loadGroups()
    local set = {}
    for _, g in pairs(groups) do
        for _, r in ipairs(g.parts) do
            set[groupKey(r.x, r.y)] = true
        end
    end
    return set
end

-- the client addresses a zone by the anchor it last saw. An edit can
-- move the anchor (the largest rectangle becomes the new main), and the
-- old anchor may survive as an ANNEX corner. Resolving blindly would
-- then treat that annex as a second main and tear the zone in half, so
-- an annex anchor is walked back to its group main
local function mainAnchorFor(x, y)
    loadGroups()
    local key = groupKey(x, y)
    if groups[key] then return x, y end
    for _, g in pairs(groups) do
        for _, r in ipairs(g.parts) do
            if groupKey(r.x, r.y) == key then return g.hx, g.hy end
        end
    end
    return x, y
end

-- exemption set for the overlap check: ONLY the own zone, foreign
-- annexes count like foreign main rectangles
local function ownAnchors(key)
    loadGroups()
    local set = { [key] = true }
    local g = groups[key]
    if g then
        for _, r in ipairs(g.parts) do
            set[groupKey(r.x, r.y)] = true
        end
    end
    return set
end

-- ---------- Safehouse helpers ----------
local function members(sh)
    local names = {}
    local pl = sh:getPlayers()
    for j = 0, pl:size() - 1 do table.insert(names, pl:get(j)) end
    return names
end

local function respawnNames(sh)
    local names = {}
    local pl = sh:getPlayersRespawn()
    for j = 0, pl:size() - 1 do table.insert(names, pl:get(j)) end
    return names
end

local function syncToAll(sh)
    if isServer() then
        pcall(function() SafeHouse.kickUserFromSafehouse(sh, "") end)
    end
end

-- removal with broadcast: hitPoint trick on the server, in solo the
-- direct removal is enough (one world, no sync needed)
local function dropSafehouse(sh)
    if isServer() then
        local ok = pcall(function()
            local warHP = getServerOptions():getInteger("WarSafehouseHitPoints")
            sh:setHitPoints(warHP - 1)
            SafeHouse.hitPoint(sh:getOnlineID())
        end)
        if ok and not findSafehouseAt(sh:getX(), sh:getY()) then return end
        -- fallback without broadcast; clients heal on reconnect via the
        -- MetaData packet, which transfers the complete list. Until then
        -- they keep a ghost copy, which the vanilla safehouse UI happily
        -- shows and lets the owner "release" again
        local at = " at " .. sh:getX() .. "," .. sh:getY()
        print("[Aegis] zone removal" .. at .. ": hitPoint path failed, removing without broadcast (clients keep a ghost until reconnect)")
    end
    pcall(function() SafeHouse.removeSafeHouse(sh) end)
end

-- rebuild with a clone of the zone data; respawn names only for the main
local function buildSafehouse(r, owner, title, names, respawn)
    local created = nil
    pcall(function()
        created = SafeHouse.addSafeHouse(r.x, r.y, r.w, r.h, owner)
    end)
    if not created then return nil end
    created:setTitle(title)
    for _, name in ipairs(names) do
        if name ~= owner then
            created:addPlayer(name)
        end
    end
    if respawn then
        for _, name in ipairs(respawn) do
            created:setRespawnInSafehouse(true, name)
        end
    end
    syncToAll(created)
    return created
end

-- bring a rectangle that stayed standing in line with the zone it now
-- belongs to. Only a real difference costs a sync packet, so an untouched
-- part stays silent. respawn = nil clears the flags, annexes carry none
-- (vanilla respawn takes the first match, which must be the main)
local function alignSafehouse(sh, title, names, respawn, owner)
    local dirty = false
    local haveTitle = sh:getTitle() or ""
    if haveTitle ~= title then
        sh:setTitle(title)
        dirty = true
    end
    local wanted = {}
    for _, name in ipairs(names or {}) do
        if name ~= owner then wanted[name] = true end
    end
    local haveSet, differs = {}, false
    for _, name in ipairs(members(sh)) do
        if name ~= owner then
            haveSet[name] = true
            if not wanted[name] then differs = true end
        end
    end
    for name in pairs(wanted) do
        if not haveSet[name] then differs = true end
    end
    if differs then
        for name in pairs(haveSet) do sh:removePlayer(name) end
        for name in pairs(wanted) do sh:addPlayer(name) end
        dirty = true
    end
    local wantSpawn = {}
    for _, name in ipairs(respawn or {}) do wantSpawn[name] = true end
    -- read the list into Lua first, the loop below mutates the safehouse
    for _, name in ipairs(respawnNames(sh)) do
        if wantSpawn[name] then
            wantSpawn[name] = nil
        else
            sh:setRespawnInSafehouse(false, name)
            dirty = true
        end
    end
    for name in pairs(wantSpawn) do
        sh:setRespawnInSafehouse(true, name)
        dirty = true
    end
    if dirty then syncToAll(sh) end
    return dirty
end

-- FactionFramework compatibility (soft dependency): faction claims
-- count as foreign ground for zone placement, so admin zones and
-- faction territory can never overlap. Rect sampled at corners, edge
-- midpoints and center, claims are large contiguous areas
local function inFactionClaim(x, y, w, h)
    if not (FF and FF.Claims and FF.Claims.factionAt) then return false end
    local hit = false
    pcall(function()
        local xs = { x, x + math.floor(w / 2), x + w - 1 }
        local ys = { y, y + math.floor(h / 2), y + h - 1 }
        for _, px in ipairs(xs) do
            for _, py in ipairs(ys) do
                if FF.Claims.factionAt(px, py) then
                    hit = true
                    return
                end
            end
        end
    end)
    return hit
end

local function overlapsForeign(x, y, w, h, exempt)
    if inFactionClaim(x, y, w, h) then return true end
    local list = SafeHouse.getSafehouseList()
    for i = 0, list:size() - 1 do
        local sh = list:get(i)
        if not exempt[groupKey(sh:getX(), sh:getY())] then
            if x < sh:getX2() and x + w > sh:getX() and y < sh:getY2() and y + h > sh:getY() then
                return true
            end
        end
    end
    return false
end

local function inRect(px, py, r)
    return px >= r.x and px < r.x + r.w and py >= r.y and py < r.y + r.h
end

-- is the player standing in the full shape (main plus annexes)?
local function inZone(player, mainRect, parts)
    local px, py = math.floor(player:getX()), math.floor(player:getY())
    if inRect(px, py, mainRect) then return true end
    for _, r in ipairs(parts or {}) do
        if inRect(px, py, r) then return true end
    end
    return false
end

-- ---------- Tile sets ----------
-- Sets are columns: set[x][y] = true. Everything here works on plain
-- tables, no Java object ever enters a set.

-- geometry of a safehouse as a plain rect, nil when the engine hands
-- back something degenerate
local function rectOf(sh)
    local r = { x = sh:getX(), y = sh:getY(), w = sh:getW(), h = sh:getH() }
    if r.w >= 1 and r.h >= 1 then return r end
    return nil
end

-- one pass over the engine list instead of a findSafehouseAt per
-- rectangle: anchor -> live safehouse, its geometry and its position in
-- the list. Removals only take entries out, so the recorded order still
-- describes everything that survives a teardown
local function safehouseIndex()
    local map = {}
    local java = SafeHouse.getSafehouseList()
    for i = 0, java:size() - 1 do
        local sh = java:get(i)
        local r = rectOf(sh)
        if r then
            local key = groupKey(r.x, r.y)
            if not map[key] then map[key] = { sh = sh, idx = i, rect = r } end
        end
    end
    return map
end

-- cheap upper bound before a set gets built, overlaps count twice
local function rectTiles(rects)
    local sum = 0
    for _, r in ipairs(rects or {}) do
        sum = sum + r.w * r.h
    end
    return sum
end

local function addTile(set, tx, ty)
    local column = set[tx]
    if not column then
        column = {}
        set[tx] = column
    end
    column[ty] = true
end

local function hasTile(set, tx, ty)
    local column = set[tx]
    return column ~= nil and column[ty] == true
end

local function addRect(set, r)
    for dy = 0, r.h - 1 do
        for dx = 0, r.w - 1 do
            addTile(set, r.x + dx, r.y + dy)
        end
    end
end

-- the whole zone as tiles: main rectangle plus every registered annex
local function tilesOfZone(mainRect, parts)
    local set = {}
    if mainRect then addRect(set, mainRect) end
    for _, r in ipairs(parts or {}) do
        addRect(set, r)
    end
    return set
end

-- Brush edit, two client generations:
-- keepRect = nil (current client, sends full = true): the payload IS the
--   complete wanted area, so erasing inside the main really erases
-- keepRect set (older client): the payload only holds the tiles outside
--   the main, everything inside the main survives untouched
local function applyBrush(set, painted, keepRect)
    local out = {}
    if keepRect then
        for tx, column in pairs(set) do
            for ty in pairs(column) do
                if inRect(tx, ty, keepRect) then addTile(out, tx, ty) end
            end
        end
    end
    for _, r in ipairs(painted or {}) do
        addRect(out, r)
    end
    return out
end

-- Boundary edit. The dragged rectangle is ADDED to the zone, nothing the
-- zone already held is dropped: dropping the old main made every edit
-- look like the previous zone had been deleted. Shrinking is the brush's
-- job, it is the only tool that carries a full wanted area
local function applyBounds(set, newMain)
    local out = {}
    for tx, column in pairs(set) do
        for ty in pairs(column) do
            addTile(out, tx, ty)
        end
    end
    addRect(out, newMain)
    return out
end

-- Row greedy split, the historical behaviour: scan rows top down, per
-- free tile take the widest strip, then grow it down while the full row
-- is present. That is what melts a painted extension and the main into
-- one rectangle when they together form one. Rows are kept as number
-- lists instead of one table per tile, a big zone would otherwise cost
-- thousands of tables. Edges stay inside MAX_EDGE, two capped rectangles
-- still touch so the protected area has no seam
local function rectsRowGreedy(set)
    local ys = {}
    local rows = {}
    for tx, column in pairs(set) do
        for ty in pairs(column) do
            local row = rows[ty]
            if not row then
                row = {}
                rows[ty] = row
                table.insert(ys, ty)
            end
            table.insert(row, tx)
        end
    end
    table.sort(ys)
    for _, ty in ipairs(ys) do
        table.sort(rows[ty])
    end

    local used = {}
    local function isFree(tx, ty)
        return hasTile(set, tx, ty) and not hasTile(used, tx, ty)
    end

    local rects = {}
    for _, ty in ipairs(ys) do
        for _, tx in ipairs(rows[ty]) do
            if isFree(tx, ty) then
                local w = 1
                while w < MAX_EDGE and isFree(tx + w, ty) do w = w + 1 end
                local h = 1
                local grow = true
                while grow and h < MAX_EDGE do
                    for dx = 0, w - 1 do
                        if not isFree(tx + dx, ty + h) then
                            grow = false
                            break
                        end
                    end
                    if grow then h = h + 1 end
                end
                for dy = 0, h - 1 do
                    for dx = 0, w - 1 do
                        addTile(used, tx + dx, ty + dy)
                    end
                end
                table.insert(rects, { x = tx, y = ty, w = w, h = h })
            end
        end
    end
    return rects
end

local function copySet(set)
    local out = {}
    for tx, column in pairs(set) do
        local c = {}
        for ty in pairs(column) do c[ty] = true end
        out[tx] = c
    end
    return out
end

local function removeRect(set, r)
    for dx = 0, r.w - 1 do
        local column = set[r.x + dx]
        if column then
            for dy = 0, r.h - 1 do column[r.y + dy] = nil end
        end
    end
end

-- biggest rectangle inside the area, histogram of column heights per
-- row with a monotonic stack. A row gap resets the heights, a column
-- gap acts as a zero bar, both caps of the greedy split (MAX_EDGE on
-- either axis) apply here too. Returns the rectangle and the tile count
local function largestRectOf(set)
    local ys, rows = {}, {}
    local total = 0
    for tx, column in pairs(set) do
        for ty in pairs(column) do
            local row = rows[ty]
            if not row then
                row = {}
                rows[ty] = row
                table.insert(ys, ty)
            end
            table.insert(row, tx)
            total = total + 1
        end
    end
    if total == 0 then return nil, 0 end
    table.sort(ys)
    for _, ty in ipairs(ys) do
        table.sort(rows[ty])
    end
    local best, bestArea = nil, 0
    local heights = {}
    local prevY = nil
    for _, ty in ipairs(ys) do
        if prevY ~= nil and ty ~= prevY + 1 then heights = {} end
        prevY = ty
        local xs = rows[ty]
        local newH = {}
        for _, tx in ipairs(xs) do
            local h = (heights[tx] or 0) + 1
            if h > MAX_EDGE then h = MAX_EDGE end
            newH[tx] = h
        end
        heights = newH
        local stack = {}
        -- pop every bar taller than limit; the widest span each popped
        -- bar covers ends at barrier (exclusive). Returns the leftmost
        -- popped x so the caller can extend the next bar to it
        local function popTo(limit, barrier)
            local leftmost = barrier
            while #stack > 0 and stack[#stack].h > limit do
                local top = table.remove(stack)
                leftmost = top.x
                local w = barrier - top.x
                if w > MAX_EDGE then w = MAX_EDGE end
                local area = w * top.h
                if area > bestArea then
                    bestArea = area
                    best = { x = top.x, y = ty - top.h + 1, w = w, h = top.h }
                end
            end
            return leftmost
        end
        local prevX = nil
        for i = 1, #xs do
            local tx = xs[i]
            if prevX ~= nil and tx ~= prevX + 1 then
                popTo(0, prevX + 1)
                stack = {}
            end
            local h = newH[tx]
            local startX = popTo(h, tx)
            if #stack == 0 or stack[#stack].h < h then
                if startX > tx then startX = tx end
                table.insert(stack, { x = startX, h = h })
            end
            prevX = tx
        end
        if prevX ~= nil then popTo(0, prevX + 1) end
    end
    return best, total
end

-- split by biggest rectangle first: carve the largest rectangle out of
-- the remaining area, repeat on the rest. Gives up as soon as the piece
-- count reaches cap, the caller keeps the greedy result then
local function rectsBiggestFirst(set, cap)
    local left = copySet(set)
    local out = {}
    while true do
        local r = largestRectOf(left)
        if not r then break end
        if #out >= cap then return nil end
        table.insert(out, r)
        removeRect(left, r)
    end
    return out
end

-- both splits, the one with fewer pieces wins. On a tie the greedy
-- result stays: identical output for an unchanged shape keeps parts
-- geometrically stable across edits, which is what lets them stand.
-- Fewer pieces means fewer inner borders in every per rectangle view
-- (vanilla debug fill draws each safehouse on its own)
-- merge pass: two rectangles that share a FULL edge and together form a
-- rectangle become one. Neither greedy nor biggest-first sees this, they
-- only ever cut; without it a painted area keeps slivers like 2x1 and 1x1
-- and every sliver is another safehouse in the vanilla list
local function mergePairs(rects)
    local list = {}
    for _, r in ipairs(rects) do
        table.insert(list, { x = r.x, y = r.y, w = r.w, h = r.h })
    end
    local merged = true
    while merged do
        merged = false
        for i = 1, #list do
            local a = list[i]
            if a then
                for j = i + 1, #list do
                    local b = list[j]
                    if b then
                        local fit = nil
                        -- side by side, same rows
                        if a.y == b.y and a.h == b.h and a.w + b.w <= MAX_EDGE then
                            if a.x + a.w == b.x then
                                fit = { x = a.x, y = a.y, w = a.w + b.w, h = a.h }
                            elseif b.x + b.w == a.x then
                                fit = { x = b.x, y = a.y, w = a.w + b.w, h = a.h }
                            end
                        -- stacked, same columns
                        elseif a.x == b.x and a.w == b.w and a.h + b.h <= MAX_EDGE then
                            if a.y + a.h == b.y then
                                fit = { x = a.x, y = a.y, w = a.w, h = a.h + b.h }
                            elseif b.y + b.h == a.y then
                                fit = { x = a.x, y = b.y, w = a.w, h = a.h + b.h }
                            end
                        end
                        if fit then
                            list[i] = fit
                            list[j] = false
                            a = fit
                            merged = true
                        end
                    end
                end
            end
        end
        if merged then
            local packed = {}
            for _, r in ipairs(list) do
                if r then table.insert(packed, r) end
            end
            list = packed
        end
    end
    local out = {}
    for _, r in ipairs(list) do
        if r then table.insert(out, r) end
    end
    return out
end

local function rectsFromSet(set)
    local greedy = mergePairs(rectsRowGreedy(set))
    if #greedy <= 2 then return greedy end
    local better = rectsBiggestFirst(set, #greedy - 1)
    if better and #better > 0 then
        better = mergePairs(better)
        if #better <= #greedy then return better end
    end
    return greedy
end

-- which rectangle becomes the main safehouse: the biggest one. When the
-- old anchor is its corner it stays the anchor, which keeps the onlineId
-- and with it members, respawn flags and title on the same safehouse.
-- On equal area the anchored rectangle wins for exactly that reason; if
-- the old anchor sits inside a bigger rectangle without being its corner
-- the move is unavoidable, a rectangle has only one anchor
local function pickMain(rects, oldHx, oldHy)
    local best, bestArea = 1, -1
    for i, r in ipairs(rects) do
        local area = r.w * r.h
        local anchored = oldHx ~= nil and r.x == oldHx and r.y == oldHy
        if area > bestArea or (area == bestArea and anchored) then
            best, bestArea = i, area
        end
    end
    return best
end

-- ---------- Exports for the player self claims ----------
-- thin wrappers for server/Aegis_PlayerClaims.lua; only plain tables
-- leave this file, never Java objects

function AegisZones.registryWritable()
    loadGroups()
    return not groupsIncomplete
end

function AegisZones.playerClaimFor(username)
    loadGroups()
    local pt = playerClaims[username]
    if not pt then return nil end
    return { x = pt.x, y = pt.y }
end

-- x = nil removes the entry
function AegisZones.setPlayerClaim(username, x, y)
    loadGroups()
    if groupsIncomplete then return false end
    if type(username) ~= "string" or username == "" or username:find("[%c|]") then return false end
    if x then
        playerClaims[username] = { x = math.floor(x), y = math.floor(y) }
    else
        playerClaims[username] = nil
    end
    saveGroups()
    return true
end

-- copy of the safehouse at an anchor, nil when the spot is free
function AegisZones.safehouseAt(x, y)
    local sh = findSafehouseAt(math.floor(x), math.floor(y))
    if not sh then return nil end
    return { x = sh:getX(), y = sh:getY(), w = sh:getW(), h = sh:getH(),
        owner = sh:getOwner() or "", title = sh:getTitle() or "" }
end

-- main rectangles owned by a user; annex anchors are plumbing and
-- filtered out, their area comes via groupFor
function AegisZones.ownedBy(username)
    local list = {}
    local annexes = annexAnchors()
    local java = SafeHouse.getSafehouseList()
    for i = 0, java:size() - 1 do
        local sh = java:get(i)
        if (sh:getOwner() or "") == username and not annexes[groupKey(sh:getX(), sh:getY())] then
            table.insert(list, { x = sh:getX(), y = sh:getY(), w = sh:getW(), h = sh:getH() })
        end
    end
    return list
end

-- overlap against every safehouse, every Aegis zone and every faction
-- claim; the optional exempt anchor spares the own zone plus annexes
function AegisZones.overlapsAny(x, y, w, h, exemptX, exemptY)
    loadGroups()
    local exempt = {}
    if exemptX then
        exempt = ownAnchors(groupKey(math.floor(exemptX), math.floor(exemptY)))
    end
    return overlapsForeign(math.floor(x), math.floor(y), math.floor(w), math.floor(h), exempt)
end

function AegisZones.buildSafehouseFor(rect, owner, title, memberNames)
    local created = buildSafehouse(rect, owner, title, memberNames or {}, nil)
    if created then return true end
    return false
end

function AegisZones.dropSafehouseAt(x, y)
    local sh = findSafehouseAt(math.floor(x), math.floor(y))
    if not sh then return false end
    dropSafehouse(sh)
    return true
end

-- full teardown of a zone released through the panel: annexes, main and
-- registry entry go in one step, so the guard never reports this as a
-- removal from outside
function AegisZones.releaseZoneAt(x, y)
    loadGroups()
    local ax, ay = mainAnchorFor(math.floor(x), math.floor(y))
    local key = groupKey(ax, ay)
    local g = groups[key]
    if g then
        for _, r in ipairs(g.parts) do
            local sh = findSafehouseAt(r.x, r.y)
            if sh then dropSafehouse(sh) end
        end
    end
    local main = findSafehouseAt(ax, ay)
    if main then dropSafehouse(main) end
    if g then
        zlog("release at " .. key .. " via panel, " .. #g.parts .. " annex parts removed with it")
        groups[key] = nil
        saveGroups()
    end
    return main ~= nil or g ~= nil
end

-- ---------- Edit lock: keeps two admins from changing the same zone at
-- once. The editor renews its lock via heartbeat; if it expires (client
-- gone/crashed) it frees itself ----------
local LOCK_TTL = 12
local locks = {}

local function cleanLocks(now)
    for key, s in pairs(locks) do
        if s.expiresAt <= now then locks[key] = nil end
    end
end

local function lockHolder(key, now)
    local s = locks[key]
    if s and s.expiresAt > now then return s.admin end
    return nil
end

-- ---------- Shared apply path ----------
-- the anchor is a zone's identity: the edit lock and a player's self
-- claim both point at it, so they follow when the main rectangle moves
-- and when a zone is swallowed by another one
local function moveAnchor(oldX, oldY, newRect)
    local oldKey = groupKey(oldX, oldY)
    local newKey = groupKey(newRect.x, newRect.y)
    if oldKey ~= newKey then
        local lock = locks[oldKey]
        if lock then
            locks[oldKey] = nil
            -- the target may already carry the same admin's lock; the
            -- later expiry wins so a live editor never loses its hold
            local have = locks[newKey]
            if not have or have.expiresAt < lock.expiresAt then locks[newKey] = lock end
        end
    end
    for user, pt in pairs(playerClaims or {}) do
        if pt.x == oldX and pt.y == oldY then
            playerClaims[user] = { x = newRect.x, y = newRect.y }
        end
    end
end

local function claimHolderAt(x, y)
    for user, pt in pairs(playerClaims or {}) do
        if pt.x == x and pt.y == y then return user end
    end
    return nil
end

local function adminOf(player)
    local name = player:getUsername()
    if type(name) ~= "string" then return "" end
    return name
end

local function shOwner(sh)
    local owner = sh:getOwner()
    if type(owner) ~= "string" then return "" end
    return owner
end

local function shTitle(sh)
    local title = sh:getTitle()
    if type(title) ~= "string" then return "" end
    return title
end

-- ---------- Fusion of touching zones ----------
-- overlapping or sharing an edge. A bare diagonal corner is not a touch
-- and neither is one tile of air, otherwise zones that merely look close
-- would eat each other
local function rectsTouch(a, b)
    local overX = a.x < b.x + b.w and a.x + a.w > b.x
    local overY = a.y < b.y + b.h and a.y + a.h > b.y
    local nearX = a.x <= b.x + b.w and a.x + a.w >= b.x
    local nearY = a.y <= b.y + b.h and a.y + a.h >= b.y
    return (nearX and overY) or (overX and nearY)
end

local function touchesAny(list, r)
    for _, o in ipairs(list) do
        if rectsTouch(o, r) then return true end
    end
    return false
end

-- bounding box over a rectangle list; a box that does not touch cannot
-- hold a rectangle that does, which keeps the scan below linear for the
-- normal case of a few zones spread over the map
local function boxOf(rects)
    local x1, y1 = rects[1].x, rects[1].y
    local x2, y2 = x1 + rects[1].w, y1 + rects[1].h
    for i = 2, #rects do
        local r = rects[i]
        if r.x < x1 then x1 = r.x end
        if r.y < y1 then y1 = r.y end
        if r.x + r.w > x2 then x2 = r.x + r.w end
        if r.y + r.h > y2 then y2 = r.y + r.h end
    end
    return { x = x1, y = y1, w = x2 - x1, h = y2 - y1 }
end

local function growBox(box, r)
    local x2 = box.x + box.w
    local y2 = box.y + box.h
    if r.x < box.x then box.x = r.x end
    if r.y < box.y then box.y = r.y end
    if r.x + r.w > x2 then x2 = r.x + r.w end
    if r.y + r.h > y2 then y2 = r.y + r.h end
    box.w = x2 - box.x
    box.h = y2 - box.y
end

-- every zone of one owner: main rectangle, its annexes and the live
-- safehouse. Annex anchors are plumbing, they are never a zone of
-- their own
local function zonesOfOwner(owner)
    loadGroups()
    local annexes = annexAnchors()
    local list = {}
    local java = SafeHouse.getSafehouseList()
    for i = 0, java:size() - 1 do
        local sh = java:get(i)
        local main = rectOf(sh)
        if main and shOwner(sh) == owner then
            local key = groupKey(main.x, main.y)
            if not annexes[key] then
                local parts = {}
                local rects = { main }
                local g = groups[key]
                if g then
                    for _, p in ipairs(g.parts) do
                        local copy = { x = p.x, y = p.y, w = p.w, h = p.h }
                        table.insert(parts, copy)
                        table.insert(rects, copy)
                    end
                end
                table.insert(list, { key = key, sh = sh, main = main, parts = parts,
                    rects = rects, box = boxOf(rects) })
            end
        end
    end
    return list
end

-- Collect every zone of the owner the new shape touches, transitively:
-- a swallowed zone can reach a third one. Nothing is changed here, the
-- caller decides. A zone another admin holds open is untouchable, then
-- the whole request is refused instead of half merged
local function collectFusion(owner, rects, skip, admin)
    local taken = {}
    if owner == "" then return taken end
    loadGroups()
    -- a player self claim keeps its own life: it is always edge adjacent
    -- to the owner's house by design, so fusion would swallow it, and a
    -- later claimRelease would then tear down the whole property
    --. Claims neither swallow nor get swallowed
    local claimAnchors = {}
    for _, pt in pairs(playerClaims or {}) do
        claimAnchors[groupKey(pt.x, pt.y)] = true
    end
    for key in pairs(skip) do
        if claimAnchors[key] then return taken end
    end
    local pool = {}
    for _, z in ipairs(zonesOfOwner(owner)) do
        if not skip[z.key] and not claimAnchors[z.key] then table.insert(pool, z) end
    end
    if #pool == 0 then return taken end
    local now = AegisShared.realTime()
    local frontier = {}
    for _, r in ipairs(rects) do table.insert(frontier, r) end
    local box = boxOf(frontier)
    local grew = true
    while grew do
        grew = false
        for i = #pool, 1, -1 do
            local z = pool[i]
            local hit = false
            if rectsTouch(z.box, box) then
                for _, r in ipairs(z.rects) do
                    if touchesAny(frontier, r) then
                        hit = true
                        break
                    end
                end
            end
            if hit then
                local locker = lockHolder(z.key, now)
                if locker and locker ~= admin then return nil, "locked", locker end
                if #taken >= MAX_FUSE then return nil, "jagged" end
                table.remove(pool, i)
                -- snapshot before anything can be torn down, the rollback
                -- needs it as much as the rebuild does
                z.title = shTitle(z.sh)
                z.names = members(z.sh)
                z.respawn = respawnNames(z.sh)
                z.claim = claimHolderAt(z.main.x, z.main.y)
                for _, r in ipairs(z.rects) do
                    table.insert(frontier, r)
                    growBox(box, r)
                end
                table.insert(taken, z)
                grew = true
            end
        end
    end
    return taken
end

-- Everything a shape change needs decided before the world is touched:
-- the split of the wanted tiles, the zones it swallows and the ceilings.
-- exempt is extended in place with the swallowed anchors, the caller
-- runs its overlap checks with it afterwards; without that the neighbour
-- about to be merged would block the merge as foreign ground
local function planShape(owner, set, exempt, admin)
    loadGroups()
    -- a write-locked registry must refuse the edit BEFORE the world is
    -- touched, otherwise the rebuilt shape survives only until the next
    -- boot while the client already saw ok=true
    if groupsIncomplete then return nil, "registry" end
    local rects = rectsFromSet(set)
    if #rects == 0 then return nil, "data" end
    local taken, reason, locker = collectFusion(owner, rects, exempt, admin)
    if not taken then return nil, reason, locker end
    if #taken > 0 then
        local extra = 0
        for _, z in ipairs(taken) do
            for _, r in ipairs(z.rects) do
                exempt[groupKey(r.x, r.y)] = true
                extra = extra + r.w * r.h
            end
        end
        -- cheap ceiling before the merged set is built, overlaps count twice
        if rectTiles(rects) + extra > MAX_TILES then return nil, "jagged" end
        for _, z in ipairs(taken) do
            for _, r in ipairs(z.rects) do addRect(set, r) end
        end
        rects = rectsFromSet(set)
        if #rects == 0 then return nil, "data" end
    end
    -- the merged shape has to fit whole or not at all, half a fusion
    -- would leave the owner with a zone he cannot edit back
    if #rects > MAX_PARTS + 1 then return nil, "jagged" end
    local tiles = 0
    for _, r in ipairs(rects) do tiles = tiles + r.w * r.h end
    if tiles > MAX_TILES then return nil, "jagged" end
    return { set = set, rects = rects, absorbed = taken, tiles = tiles }
end

-- Every geometry change ends here: pick the main, tear the old zone and
-- every swallowed one down, build the new shape, answer the client.
-- main is the live safehouse of the ASKING zone, group its registry
-- entry (may be fresh), plan the result of planShape (tiles already
-- merged, split already done, ceilings already checked).
local function applyZoneShape(player, main, group, plan, command, note)
    local oldRect = rectOf(main)
    if not oldRect then
        zlog(command .. " rejected: main safehouse unreadable")
        toClient(player, command, { ok = false, reason = "gone" })
        return
    end
    local rects = plan.rects
    if #rects == 0 then
        -- an edit never deletes a zone, that is what the release path is for
        zlog(command .. " rejected: empty result shape")
        toClient(player, command, { ok = false, reason = "data" })
        return
    end
    local absorbed = plan.absorbed or {}

    local owner = main:getOwner() or ""
    local title = main:getTitle() or ""
    local label = title ~= "" and title or owner
    local ownNames = members(main)
    local ownRespawn = respawnNames(main)

    -- members and respawn flags are the union of everything that goes in,
    -- the title stays the one of the zone that asked for the change. The
    -- own lists are kept apart, the rollback has to restore them as they
    -- were and not hand out the swallowed zones' members
    local names, seenName = {}, {}
    for _, n in ipairs(ownNames) do
        if not seenName[n] then
            seenName[n] = true
            table.insert(names, n)
        end
    end
    local respawn, seenSpawn = {}, {}
    for _, n in ipairs(ownRespawn) do
        if not seenSpawn[n] then
            seenSpawn[n] = true
            table.insert(respawn, n)
        end
    end
    for _, z in ipairs(absorbed) do
        for _, n in ipairs(z.names or {}) do
            if not seenName[n] then
                seenName[n] = true
                table.insert(names, n)
            end
        end
        for _, n in ipairs(z.respawn or {}) do
            if not seenSpawn[n] then
                seenSpawn[n] = true
                table.insert(respawn, n)
            end
        end
    end

    local oldKey = groupKey(oldRect.x, oldRect.y)
    local oldParts = group.parts or {}
    local before = string.format("%d,%d %dx%d", oldRect.x, oldRect.y, oldRect.w, oldRect.h)
    local mainIndex = pickMain(rects, oldRect.x, oldRect.y)
    local newMain = rects[mainIndex]

    local snap = safehouseIndex()

    -- every rectangle this edit is allowed to leave standing: the zone's
    -- own ones plus those of the zones it swallows. Foreign ground never
    -- enters here, the callers checked it against overlapsForeign
    local ownedRects = {}
    ownedRects[oldKey] = oldRect
    for _, r in ipairs(oldParts) do ownedRects[groupKey(r.x, r.y)] = r end
    for _, z in ipairs(absorbed) do
        for _, r in ipairs(z.rects) do ownedRects[groupKey(r.x, r.y)] = r end
    end

    -- A rectangle stays only when it is geometrically identical AND the
    -- main stays too. Order argument for the first-match contract, from
    -- the bytecode: addSafeHouse ends in ArrayList.add(Object), so a
    -- rebuilt safehouse is APPENDED, and removeSafeHouse (the hitPoint
    -- path too) is ArrayList.remove(Object), which keeps the relative
    -- order of everything else. So a rebuilt main lands behind every
    -- survivor and would lose hasSafehouse/respawn/chat to it; with the
    -- main left in place only entries recorded behind it qualify, and
    -- every rectangle built afterwards is appended behind it as well.
    local standing = {}
    local mainStays = false
    local mainEntry = snap[oldKey]
    if mainEntry and newMain.x == oldRect.x and newMain.y == oldRect.y
        and newMain.w == oldRect.w and newMain.h == oldRect.h then
        mainStays = true
        standing[oldKey] = true
        for i, r in ipairs(rects) do
            if i ~= mainIndex then
                local key = groupKey(r.x, r.y)
                local was = ownedRects[key]
                local live = snap[key]
                if was and live and was.w == r.w and was.h == r.h
                    and live.rect.w == r.w and live.rect.h == r.h
                    and live.idx > mainEntry.idx then
                    standing[key] = true
                end
            end
        end
    end

    -- a miss in the snapshot normally means the anchor is free, but a
    -- failed list read looks the same and would leave the rectangle
    -- standing while the rebuild puts a second one on its anchor. The
    -- direct lookup costs one scan and only runs on a miss
    local function dropUnless(r)
        local key = groupKey(r.x, r.y)
        if standing[key] then return end
        local live = snap[key]
        local sh = live and live.sh or findSafehouseAt(r.x, r.y)
        if sh then dropSafehouse(sh) end
    end

    for _, r in ipairs(oldParts) do dropUnless(r) end
    if not mainStays then dropSafehouse(main) end
    -- the swallowed zones go the same way; their registry lines are cut
    -- further down, in one step with writing the new one
    for _, z in ipairs(absorbed) do
        for _, r in ipairs(z.rects) do dropUnless(r) end
    end

    -- main goes back into the list first (first-match for
    -- hasSafehouse/respawn/chat must hit the main). An unchanged main is
    -- never touched at all: no removal packet, no new onlineId
    local built = main
    if not mainStays then
        built = buildSafehouse(newMain, owner, label, names, respawn)
    end
    -- the rollback below rebuilds the old geometry from scratch. It is
    -- only reachable when the main had to be rebuilt, and that is exactly
    -- the case where standing is empty, so nothing here can collide with
    -- a rectangle that is still in the list
    if not built then
        zlog(command .. " rebuild failed at " .. newMain.x .. "," .. newMain.y .. " " .. newMain.w .. "x" .. newMain.h .. ", rolling back")
        -- rollback to the geometry from before, otherwise the whole zone
        -- would be gone after a failed rebuild
        local restored = buildSafehouse(oldRect, owner, label, ownNames, ownRespawn)
        if restored then
            local restoredParts = {}
            for _, r in ipairs(oldParts) do
                if buildSafehouse(r, owner, label, ownNames, nil) then
                    table.insert(restoredParts, r)
                else
                    zlog(command .. " rollback annex build failed at " .. r.x .. "," .. r.y .. " " .. r.w .. "x" .. r.h .. ", area lost")
                end
            end
            group.hx, group.hy = oldRect.x, oldRect.y
            group.parts = restoredParts
            groups[oldKey] = group
        else
            print("[Aegis] Safehouse rollback failed for " .. owner .. " (" .. before .. "), zone lost")
            groups[oldKey] = nil
        end
        -- the swallowed zones never asked for this, they go back as they
        -- were; their registry entries were left alone until here
        for _, z in ipairs(absorbed) do
            local zLabel = (z.title or "") ~= "" and z.title or owner
            if buildSafehouse(z.main, owner, zLabel, z.names or {}, z.respawn or {}) then
                local back = {}
                for _, r in ipairs(z.parts) do
                    if buildSafehouse(r, owner, zLabel, z.names or {}, nil) then
                        table.insert(back, r)
                    else
                        zlog(command .. " rollback annex build failed at " .. r.x .. "," .. r.y .. " " .. r.w .. "x" .. r.h .. ", area lost")
                    end
                end
                groups[z.key] = { hx = z.main.x, hy = z.main.y, parts = back }
            else
                print("[Aegis] Safehouse rollback failed for " .. owner .. " (" .. z.key .. "), zone lost")
                groups[z.key] = nil
            end
        end
        saveGroups()
        toClient(player, command, { ok = false, reason = "gone" })
        return
    end

    -- annexes carry the SAME title as the main; a suffix used to make
    -- them read like a separate zone in the vanilla safehouse list
    local kept = {}
    local stayed = mainStays and 1 or 0
    local rebuilt = mainStays and 0 or 1
    for i, r in ipairs(rects) do
        if i ~= mainIndex then
            local key = groupKey(r.x, r.y)
            if standing[key] then
                -- untouched geometry, but the zone around it may have
                -- gained members or a swallowed part may still carry the
                -- title and respawn flags of its own former zone
                local live = snap[key]
                if live then alignSafehouse(live.sh, label, names, nil, owner) end
                table.insert(kept, r)
                stayed = stayed + 1
            elseif buildSafehouse(r, owner, label, names, nil) then
                table.insert(kept, r)
                rebuilt = rebuilt + 1
            else
                zlog(command .. " annex build failed at " .. r.x .. "," .. r.y .. " " .. r.w .. "x" .. r.h .. ", area lost")
            end
        end
    end
    if mainStays then alignSafehouse(main, label, names, respawn, owner) end

    -- clear every old key BEFORE the new entry is written: the new main
    -- may sit on the anchor of a swallowed zone, and clearing afterwards
    -- would drop the fresh entry and leave the guard with orphan annexes
    local newKey = groupKey(newMain.x, newMain.y)
    groups[oldKey] = nil
    for _, z in ipairs(absorbed) do groups[z.key] = nil end
    moveAnchor(oldRect.x, oldRect.y, newMain)
    for _, z in ipairs(absorbed) do moveAnchor(z.main.x, z.main.y, newMain) end
    group.hx, group.hy = newMain.x, newMain.y
    group.parts = kept
    groups[newKey] = group
    saveGroups()

    if #absorbed > 0 then
        local merged = {}
        for _, z in ipairs(absorbed) do
            local piece = string.format("%d,%d %dx%d", z.main.x, z.main.y, z.main.w, z.main.h)
            if #z.parts > 0 then piece = piece .. " +" .. #z.parts end
            -- a self claim rides along on the new anchor, worth a name in
            -- the log because the player's budget now reads the whole zone
            if z.claim then piece = piece .. " (claim " .. tostring(z.claim) .. ")" end
            table.insert(merged, piece)
        end
        zlog(command .. " fused " .. #absorbed .. " neighbour zone(s): " .. table.concat(merged, " + "))
        AegisLog.write("Actions", adminOf(player), owner,
            string.format("Zones merged into %s (%s): %s",
                before, tostring(label), table.concat(merged, " + ")))
    end

    local tiles = newMain.w * newMain.h
    for _, r in ipairs(kept) do tiles = tiles + r.w * r.h end
    zlog(string.format("%s applied for %s: %s -> %d,%d %dx%d, %d tiles in %d parts, absorbed=%d, %d parts left standing, %d rebuilt",
        command, tostring(owner), before, newMain.x, newMain.y, newMain.w, newMain.h,
        tiles, 1 + #kept, #absorbed, stayed, rebuilt))
    AegisLog.write("Actions", adminOf(player), owner,
        string.format("%s (%s): %s -> %d,%d %dx%d, %d tiles in %d parts",
            note, tostring(label), before,
            newMain.x, newMain.y, newMain.w, newMain.h, tiles, 1 + #kept))
    toClient(player, command, { ok = true })
end

-- A fresh shape that already touches a zone of the same owner is not a
-- new zone, it is that zone growing. The biggest swallowed zone plays
-- host: the change runs on its safehouse, so its title, members and
-- respawn flags survive instead of being replaced by a blank new zone.
-- The remaining swallowed zones stay in the plan and are folded in there
local function growExisting(player, plan, command, note)
    -- growing reshapes an EXISTING zone, so the same rule as the shape
    -- editors applies: the admin has to stand in the resulting area. The
    -- create commands carry no such gate on their own
    local px, py = math.floor(player:getX()), math.floor(player:getY())
    if not hasTile(plan.set, px, py) then
        zlog(command .. " rejected: admin stands outside the grown area")
        toClient(player, command, { ok = false, reason = "outside" })
        return
    end
    local best, bestArea = 1, -1
    for i, z in ipairs(plan.absorbed) do
        local area = z.main.w * z.main.h
        if area > bestArea or (area == bestArea and z.key < plan.absorbed[best].key) then
            best, bestArea = i, area
        end
    end
    local host = table.remove(plan.absorbed, best)
    zlog(command .. " grows existing zone " .. host.key .. " instead of creating a new one")
    local group = groups[host.key] or { hx = host.main.x, hy = host.main.y, parts = host.parts }
    applyZoneShape(player, host.sh, group, plan, command, note)
end

-- ---------- Commands ----------
local Commands = {}

Commands.shList = function(player, args)
    if not AegisRoles.canArea(player, "zones") then denyPlayer(player) return end
    loadGroups()
    local annexes = annexAnchors()
    local now = AegisShared.realTime()
    cleanLocks(now)
    local list = {}
    -- one pcall per entry: a single unreadable safehouse must cost one
    -- row, not truncate the list. The client reconciles ghosts against
    -- this payload, a silently shortened list would delete living zones
    local complete = true
    local java = nil
    local count = 0
    pcall(function()
        java = SafeHouse.getSafehouseList()
        count = java:size()
    end)
    if not java then complete = false end
    for i = 0, count - 1 do
        local ok = pcall(function()
            local sh = java:get(i)
            if not sh then return end
            local key = groupKey(sh:getX(), sh:getY())
            -- annexes are plumbing, only the main counts in the list
            if not annexes[key] then
                local entry = {
                    x = sh:getX(), y = sh:getY(), w = sh:getW(), h = sh:getH(),
                    owner = sh:getOwner() or "", title = sh:getTitle() or "",
                    players = members(sh),
                    parts = {},
                    lockedBy = lockHolder(key, now) or "",
                }
                local g = groups[key]
                if g then
                    for _, r in ipairs(g.parts) do
                        table.insert(entry.parts, { x = r.x, y = r.y, w = r.w, h = r.h })
                    end
                end
                table.insert(list, entry)
            end
        end)
        if not ok then complete = false end
    end
    -- annexes whose main was removed outside the panel live on until the
    -- guard reaps them; hand their rectangles over so the ghost sweep on
    -- the client does not mistake them for stale
    local stray = {}
    for _, g in pairs(groups) do
        if not findSafehouseAt(g.hx, g.hy) then
            for _, r in ipairs(g.parts) do
                table.insert(stray, { x = r.x, y = r.y, w = r.w, h = r.h })
            end
        end
    end
    toClient(player, "shList", { list = list, stray = stray, complete = complete })
end

-- legacy border drag: current clients send the full shape via shShape,
-- this stays for older clients still in the wild
Commands.shSet = function(player, args)
    if not AegisRoles.canArea(player, "zones") then denyPlayer(player) return end
    if not args then return end
    local oldX, oldY = tonumber(args.oldX), tonumber(args.oldY)
    local x = math.floor(tonumber(args.x) or -1)
    local y = math.floor(tonumber(args.y) or -1)
    local w = math.floor(tonumber(args.w) or 0)
    local h = math.floor(tonumber(args.h) or 0)
    if not oldX or not oldY or x < 0 or y < 0 or w < 1 or h < 1 or w > MAX_EDGE or h > MAX_EDGE then
        zlog("shSet rejected: bad payload")
        toClient(player, "shSet", { ok = false, reason = "data" })
        return
    end
    local admin = adminOf(player)
    zlog(string.format("shSet by %s: anchor %d,%d -> %d,%d %dx%d",
        admin, math.floor(oldX), math.floor(oldY), x, y, w, h))
    loadGroups()
    -- same anchor walk as shShape: a stale anchor may point at an annex
    local ax, ay = mainAnchorFor(math.floor(oldX), math.floor(oldY))
    local sh = findSafehouseAt(ax, ay)
    if not sh then
        zlog("shSet rejected: no safehouse at anchor " .. ax .. "," .. ay)
        toClient(player, "shSet", { ok = false, reason = "gone" })
        return
    end
    local oldRect = rectOf(sh)
    if not oldRect then
        zlog("shSet rejected: safehouse at " .. ax .. "," .. ay .. " unreadable")
        toClient(player, "shSet", { ok = false, reason = "gone" })
        return
    end
    local oldKey = groupKey(oldRect.x, oldRect.y)
    local locker = lockHolder(oldKey, AegisShared.realTime())
    if locker and locker ~= admin then
        zlog("shSet rejected: zone " .. oldKey .. " locked by " .. locker)
        toClient(player, "shSet", { ok = false, reason = "locked", admin = locker })
        return
    end
    local group = groups[oldKey] or { hx = oldRect.x, hy = oldRect.y, parts = {} }

    -- The drag handle moves a BORDER, so the new rectangle has to reach
    -- the zone: overlapping or sharing an edge, a bare diagonal corner or
    -- one tile of air is not a touch (same rule as the zone fusion). A
    -- dragged rectangle that stands free would not grow the zone, it
    -- would add a detached island and split the shape into more and more
    -- parts with every pull. Checked against the OWN rectangles only and
    -- before any fusion runs: a neighbour of the same owner that the free
    -- rectangle happens to touch would bridge nothing, the zone itself
    -- stays disconnected, and whether the pull is legal must not depend
    -- on unrelated zones standing nearby. Painting (shShape) carries a
    -- full wanted area and stays free, creating is free anyway
    local zoneRects = { oldRect }
    for _, r in ipairs(group.parts) do table.insert(zoneRects, r) end
    if not touchesAny(zoneRects, { x = x, y = y, w = w, h = h }) then
        zlog(string.format("shSet rejected: new bounds %d,%d %dx%d do not touch zone %s", x, y, w, h, oldKey))
        toClient(player, "shSet", { ok = false, reason = "detached" })
        return
    end

    if rectTiles(group.parts) + rectTiles({ oldRect }) + w * h > MAX_TILES then
        zlog("shSet rejected: tile ceiling")
        toClient(player, "shSet", { ok = false, reason = "jagged" })
        return
    end

    -- the dragged rectangle joins the zone; the union is split fresh
    -- afterwards, so bounds that form one rectangle together with the
    -- old area end up as ONE safehouse instead of two rows in the list
    local newSet = applyBounds(tilesOfZone(oldRect, group.parts),
        { x = x, y = y, w = w, h = h })
    -- fusion before the ground check: a zone of the same owner the new
    -- bounds now touch is about to become part of this one, so it counts
    -- as own ground instead of blocking the edit as foreign
    local exempt = ownAnchors(oldKey)
    local plan, reason, holder = planShape(shOwner(sh), newSet, exempt, admin)
    if not plan then
        zlog("shSet rejected: " .. tostring(reason) .. (holder and (" (held by " .. holder .. ")") or ""))
        toClient(player, "shSet", { ok = false, reason = reason, admin = holder })
        return
    end
    -- only the new bounds need the overlap check, the annex ground was
    -- checked when it was painted
    if overlapsForeign(x, y, w, h, exempt) then
        zlog("shSet rejected: new bounds overlap foreign ground")
        toClient(player, "shSet", { ok = false, reason = "overlap" })
        return
    end
    applyZoneShape(player, sh, group, plan, "shSet", "Safehouse adjusted")
end

-- apply freeform: the client splits the painted tiles outside the main
-- into rectangles, the server merges them with the zone's own tiles and
-- splits the whole thing again, so a piece that touches the main becomes
-- part of it instead of a second safehouse next door
Commands.shShape = function(player, args)
    if not AegisRoles.canArea(player, "zones") then denyPlayer(player) return end
    if not args then return end
    local hx, hy = tonumber(args.mainX), tonumber(args.mainY)
    if not hx or not hy then
        zlog("shShape rejected: bad payload")
        toClient(player, "shShape", { ok = false, reason = "data" })
        return
    end
    loadGroups()
    local ax, ay = mainAnchorFor(math.floor(hx), math.floor(hy))
    local main = findSafehouseAt(ax, ay)
    if not main then
        zlog("shShape rejected: no safehouse at anchor " .. ax .. "," .. ay)
        toClient(player, "shShape", { ok = false, reason = "gone" })
        return
    end

    -- read the network table defensively, drop duplicate anchors (two
    -- rectangles on the same anchor share the onlineId, the second one
    -- could never be removed cleanly later)
    local newRects = {}
    local anchors = {}
    local bad = false
    if type(args.rects) == "table" then
        for _, r in pairs(args.rects) do
            if type(r) == "table" and tonumber(r.x) and tonumber(r.y) and tonumber(r.w) and tonumber(r.h) then
                local rx, ry = math.floor(tonumber(r.x)), math.floor(tonumber(r.y))
                local rw, rh = math.floor(tonumber(r.w)), math.floor(tonumber(r.h))
                local key = groupKey(rx, ry)
                if rx < 0 or ry < 0 or rw < 1 or rh < 1 or rw > MAX_EDGE or rh > MAX_EDGE then
                    -- under the full payload a dropped rectangle is not a
                    -- missing extension any more, it is a missing PIECE OF
                    -- THE ZONE. Refuse the whole edit instead of silently
                    -- shrinking the zone
                    bad = true
                elseif not anchors[key] then
                    anchors[key] = true
                    table.insert(newRects, { x = rx, y = ry, w = rw, h = rh })
                end
            else
                bad = true
            end
        end
    end
    if bad then
        zlog("shShape rejected: malformed rectangle in payload")
        toClient(player, "shShape", { ok = false, reason = "data" })
        return
    end
    if #newRects > MAX_PARTS + 1 then
        zlog("shShape rejected: " .. #newRects .. " parts exceed limit")
        toClient(player, "shShape", { ok = false, reason = "jagged" })
        return
    end

    local mainRect = rectOf(main)
    if not mainRect then
        zlog("shShape rejected: safehouse at " .. ax .. "," .. ay .. " unreadable")
        toClient(player, "shShape", { ok = false, reason = "gone" })
        return
    end
    local key = groupKey(mainRect.x, mainRect.y)
    local admin = adminOf(player)
    zlog(string.format("shShape by %s: zone %s, %d rects, full=%s",
        admin, key, #newRects, tostring(args.full == true)))
    local locker = lockHolder(key, AegisShared.realTime())
    if locker and locker ~= admin then
        zlog("shShape rejected: zone " .. key .. " locked by " .. locker)
        toClient(player, "shShape", { ok = false, reason = "locked", admin = locker })
        return
    end
    local group = groups[key] or { hx = mainRect.x, hy = mainRect.y, parts = {} }

    if rectTiles(group.parts) + rectTiles(newRects) + rectTiles({ mainRect }) > MAX_TILES then
        zlog("shShape rejected: tile ceiling")
        toClient(player, "shShape", { ok = false, reason = "jagged" })
        return
    end

    -- painting and erasing in one set: what the brush left standing
    -- outside the main comes in, the rest of the old annex area falls
    -- away. Members are cloned in the rebuild, respawn flags stay ONLY
    -- on the main (vanilla respawn takes first-match)
    -- full = true means the payload already carries the whole wanted
    -- area, then nothing is carried over from the old shape
    local keep = args.full ~= true and mainRect or nil
    local newSet = applyBrush(tilesOfZone(mainRect, group.parts), newRects, keep)
    -- requirement: only someone standing on the property may edit. The
    -- wanted area counts as well as the old zone: the rect builder appends
    -- ground the admin may already be standing on, and the brush may erase
    -- the very tile under the admin's feet
    if not inZone(player, mainRect, group.parts) then
        local px, py = math.floor(player:getX()), math.floor(player:getY())
        if not hasTile(newSet, px, py) then
            zlog("shShape rejected: admin stands outside zone " .. key)
            toClient(player, "shShape", { ok = false, reason = "outside" })
            return
        end
    end
    -- fusion first, it decides what still counts as foreign ground below
    local exempt = ownAnchors(key)
    local plan, reason, holder = planShape(shOwner(main), newSet, exempt, admin)
    if not plan then
        zlog("shShape rejected: " .. tostring(reason) .. (holder and (" (held by " .. holder .. ")") or ""))
        toClient(player, "shShape", { ok = false, reason = reason, admin = holder })
        return
    end
    -- overlap check against everything outside the own zone and outside
    -- what it just swallowed. Only the freshly painted rectangles can
    -- bring in new ground, the union never covers a tile the zone did
    -- not already hold or the brush did not just paint
    for _, r in ipairs(newRects) do
        if overlapsForeign(r.x, r.y, r.w, r.h, exempt) then
            zlog(string.format("shShape rejected: rect %d,%d %dx%d overlaps foreign ground", r.x, r.y, r.w, r.h))
            toClient(player, "shShape", { ok = false, reason = "overlap" })
            return
        end
    end
    applyZoneShape(player, main, group, plan, "shShape", "Zone shaped")
end

-- create a new zone on unclaimed ground, no existing safehouse needed.
-- Owner is freely chosen (admin picks the target player), no lock since
-- no zone exists yet, the overlap check is enough
Commands.shNew = function(player, args)
    if not AegisRoles.canArea(player, "zones") then denyPlayer(player) return end
    if not args then return end
    local owner = tostring(args.owner or "")
    local x = math.floor(tonumber(args.x) or -1)
    local y = math.floor(tonumber(args.y) or -1)
    local w = math.floor(tonumber(args.w) or 0)
    local h = math.floor(tonumber(args.h) or 0)
    if owner == "" or x < 0 or y < 0 or w < 1 or h < 1 or w > MAX_EDGE or h > MAX_EDGE then
        zlog("shNew rejected: bad payload")
        toClient(player, "shNew", { ok = false, reason = "data" })
        return
    end
    zlog(string.format("shNew by %s for %s: %d,%d %dx%d", adminOf(player), owner, x, y, w, h))
    loadGroups()
    -- same rule as the brush: a rectangle that touches a zone of the same
    -- owner is that zone growing, not a second entry next door. Without
    -- this the rectangle tool would keep producing exactly the split
    -- zones the fusion is there to prevent
    local rect = { x = x, y = y, w = w, h = h }
    local newSet = {}
    addRect(newSet, rect)
    local exempt = {}
    local plan, reason, holder = planShape(owner, newSet, exempt, adminOf(player))
    if not plan then
        zlog("shNew rejected: " .. tostring(reason) .. (holder and (" (held by " .. holder .. ")") or ""))
        toClient(player, "shNew", { ok = false, reason = reason, admin = holder })
        return
    end
    if overlapsForeign(x, y, w, h, exempt) then
        zlog("shNew rejected: rectangle overlaps foreign ground")
        toClient(player, "shNew", { ok = false, reason = "overlap" })
        return
    end
    if #plan.absorbed > 0 then
        growExisting(player, plan, "shNew", "Zone extended by rectangle")
        return
    end
    local created = buildSafehouse(rect, owner, owner, {}, nil)
    if not created then
        zlog("shNew rejected: engine refused the safehouse build")
        toClient(player, "shNew", { ok = false, reason = "gone" })
        return
    end
    zlog(string.format("shNew applied for %s: %d,%d %dx%d", owner, x, y, w, h))
    AegisLog.write("Actions", adminOf(player), owner,
        string.format("Safehouse newly created: %d,%d %dx%d", x, y, w, h))
    toClient(player, "shNew", { ok = true })
end

-- freeform creation: the client splits the painted area completely into
-- rectangles (no main area is protected beforehand). The server runs the
-- same merge as an edit, the biggest rectangle becomes the main, the
-- rest are annexes under the same title
Commands.shNewShape = function(player, args)
    if not AegisRoles.canArea(player, "zones") then denyPlayer(player) return end
    if not args then return end
    local owner = tostring(args.owner or "")
    if owner == "" or type(args.rects) ~= "table" then
        zlog("shNewShape rejected: bad payload")
        toClient(player, "shNewShape", { ok = false, reason = "data" })
        return
    end
    local rects = {}
    local anchors = {}
    for _, r in pairs(args.rects) do
        if type(r) == "table" and tonumber(r.x) and tonumber(r.y) and tonumber(r.w) and tonumber(r.h) then
            local rx, ry = math.floor(tonumber(r.x)), math.floor(tonumber(r.y))
            local rw, rh = math.floor(tonumber(r.w)), math.floor(tonumber(r.h))
            local key = groupKey(rx, ry)
            if rx >= 0 and ry >= 0 and rw >= 1 and rh >= 1 and rw <= MAX_EDGE and rh <= MAX_EDGE
                and not anchors[key] then
                anchors[key] = true
                table.insert(rects, { x = rx, y = ry, w = rw, h = rh })
            end
        end
    end
    if #rects == 0 then
        zlog("shNewShape rejected: no usable rectangles")
        toClient(player, "shNewShape", { ok = false, reason = "data" })
        return
    end
    if #rects > MAX_PARTS + 1 then
        zlog("shNewShape rejected: " .. #rects .. " parts exceed limit")
        toClient(player, "shNewShape", { ok = false, reason = "jagged" })
        return
    end
    if rectTiles(rects) > MAX_TILES then
        zlog("shNewShape rejected: tile ceiling")
        toClient(player, "shNewShape", { ok = false, reason = "jagged" })
        return
    end
    zlog(string.format("shNewShape by %s for %s: %d rects", adminOf(player), owner, #rects))
    loadGroups()
    -- merge first: touching painted pieces become one rectangle and every
    -- touching zone of the same owner is swallowed, so a fresh zone
    -- starts out as clean as an edited one
    local exempt = {}
    local plan, reason, holder = planShape(owner, tilesOfZone(nil, rects), exempt, adminOf(player))
    if not plan then
        zlog("shNewShape rejected: " .. tostring(reason) .. (holder and (" (held by " .. holder .. ")") or ""))
        toClient(player, "shNewShape", { ok = false, reason = reason, admin = holder })
        return
    end
    for _, r in ipairs(rects) do
        if overlapsForeign(r.x, r.y, r.w, r.h, exempt) then
            zlog(string.format("shNewShape rejected: rect %d,%d %dx%d overlaps foreign ground", r.x, r.y, r.w, r.h))
            toClient(player, "shNewShape", { ok = false, reason = "overlap" })
            return
        end
    end
    if #plan.absorbed > 0 then
        growExisting(player, plan, "shNewShape", "Zone extended by new area")
        return
    end

    local merged = plan.rects
    local mainIndex = pickMain(merged, nil, nil)
    local main = merged[mainIndex]
    local newMain = buildSafehouse(main, owner, owner, {}, nil)
    if not newMain then
        zlog("shNewShape rejected: engine refused the safehouse build")
        toClient(player, "shNewShape", { ok = false, reason = "gone" })
        return
    end
    -- annexes share the main's title, nothing may read as a second zone
    local created = {}
    for i, r in ipairs(merged) do
        if i ~= mainIndex then
            if buildSafehouse(r, owner, owner, {}, nil) then
                table.insert(created, r)
            else
                zlog("shNewShape" .. " annex build failed at " .. r.x .. "," .. r.y .. " " .. r.w .. "x" .. r.h .. ", area lost")
            end
        end
    end
    groups[groupKey(main.x, main.y)] = { hx = main.x, hy = main.y, parts = created }
    saveGroups()

    local tiles = main.w * main.h
    for _, r in ipairs(created) do tiles = tiles + r.w * r.h end
    zlog(string.format("shNewShape applied for %s: %d,%d %dx%d, %d tiles in %d parts",
        owner, main.x, main.y, main.w, main.h, tiles, 1 + #created))
    AegisLog.write("Actions", adminOf(player), owner,
        string.format("Safehouse newly shaped: %d,%d %dx%d, %d tiles in %d parts",
            main.x, main.y, main.w, main.h, tiles, 1 + #created))
    toClient(player, "shNewShape", { ok = true })
end

-- request/renew lock: the editor calls this on start and then in the
-- heartbeat, so a second admin cannot open the same zone in parallel
Commands.zoneLock = function(player, args)
    if not AegisRoles.canArea(player, "zones") then denyPlayer(player) return end
    if not args then return end
    local x = math.floor(tonumber(args.x) or -1)
    local y = math.floor(tonumber(args.y) or -1)
    -- mirror the token back unchanged so the client can detect stale
    -- replies (editor request from an already abandoned zone click)
    local token = args.token
    -- same anchor walk as the editors: locking a stale annex anchor
    -- would guard a dead key while the real zone stays open
    if x >= 0 and y >= 0 then
        x, y = mainAnchorFor(x, y)
    end
    if x < 0 or y < 0 then
        toClient(player, "zoneLock", { ok = false, token = token })
        return
    end
    local key = groupKey(x, y)
    local now = AegisShared.realTime()
    cleanLocks(now)
    local name = player:getUsername()
    local existing = locks[key]
    if existing and existing.admin ~= name and existing.expiresAt > now then
        zlog("lock on " .. key .. " refused for " .. tostring(name) .. ", held by " .. existing.admin)
        toClient(player, "zoneLock", { ok = false, admin = existing.admin, token = token })
        return
    end
    -- fresh grants only, the heartbeat renewals would flood the log
    if not existing or existing.admin ~= name then
        zlog("lock on " .. key .. " granted to " .. tostring(name))
    end
    locks[key] = { admin = name, expiresAt = now + LOCK_TTL }
    toClient(player, "zoneLock", { ok = true, token = token })
end

Commands.zoneUnlock = function(player, args)
    if not AegisRoles.canArea(player, "zones") then denyPlayer(player) return end
    if not args then return end
    local x = math.floor(tonumber(args.x) or -1)
    local y = math.floor(tonumber(args.y) or -1)
    if x < 0 or y < 0 then return end
    local name = player:getUsername()
    -- the client unlocks with the anchor it opened, but a merge may have
    -- moved the lock to the new main. The editor is single-instance per
    -- admin, so releasing every lock this admin holds is exact and spares
    -- other admins the TTL wait
    for key, s in pairs(locks) do
        if s.admin == name then locks[key] = nil end
    end
end

-- ---------- Guard ----------
-- (1) a released main safehouse deletes its zone with it (requirement),
-- (2) decay: align the annexes' lastVisited to the freshest group
--     member, otherwise SafeHouseRemovalTime clears part rectangles
--     one by one,
-- (3) mirror member changes on the main (vanilla UI) onto the annexes;
--     the owner is left out, the constructor puts him into the
--     players list itself,
-- (4) mirror the title as well, a rename in the vanilla safehouse UI
--     would otherwise make the annexes read as a zone of their own
local function guard()
    loadGroups()
    local changed = false
    for key, g in pairs(groups) do
        local main = findSafehouseAt(g.hx, g.hy)
        if not main then
            -- our own edits rewrite the registry in the same call, so a
            -- missing main here means an outside removal: vanilla release
            -- button, admin command, decay or war. Name the owner while
            -- an annex can still tell us
            local owner = ""
            for _, r in ipairs(g.parts) do
                local sh = findSafehouseAt(r.x, r.y)
                if sh then
                    if owner == "" then owner = shOwner(sh) end
                    dropSafehouse(sh)
                end
            end
            -- with no annex left alive the owner can still come from a
            -- registered self claim on the anchor; otherwise say unknown
            -- instead of printing an empty name
            if owner == "" then owner = claimHolderAt(g.hx, g.hy) or "" end
            if owner == "" then owner = "unknown" end
            zlog("guard: main " .. key .. " removed outside the panel (owner " .. tostring(owner)
                .. "), reaping " .. #g.parts .. " annex parts")
            groups[key] = nil
            changed = true
            AegisLog.write("Actions", "Server", key,
                "Safehouse released, zone annexes removed with it (" .. #g.parts .. " parts, owner "
                .. tostring(owner) .. ")")
        elseif #g.parts > 0 then
            local owner = main:getOwner() or ""
            local title = main:getTitle() or ""
            local label = title ~= "" and title or owner
            local freshest = main:getLastVisited()
            local partShs = {}
            for _, r in ipairs(g.parts) do
                local sh = findSafehouseAt(r.x, r.y)
                if sh then
                    table.insert(partShs, sh)
                    if sh:getLastVisited() > freshest then freshest = sh:getLastVisited() end
                end
            end
            if main:getLastVisited() < freshest then main:setLastVisited(freshest) end
            local wanted = {}
            for _, name in ipairs(members(main)) do
                if name ~= owner then wanted[name] = true end
            end
            for _, sh in ipairs(partShs) do
                if sh:getLastVisited() < freshest then sh:setLastVisited(freshest) end
                local dirty = false
                local haveTitle = sh:getTitle() or ""
                if haveTitle ~= label then
                    sh:setTitle(label)
                    dirty = true
                end
                local differs = false
                local haveSet = {}
                for _, name in ipairs(members(sh)) do
                    if name ~= owner then
                        haveSet[name] = true
                        if not wanted[name] then differs = true end
                    end
                end
                for name in pairs(wanted) do
                    if not haveSet[name] then differs = true end
                end
                if differs then
                    for name in pairs(haveSet) do sh:removePlayer(name) end
                    for name in pairs(wanted) do sh:addPlayer(name) end
                    dirty = true
                end
                if dirty then syncToAll(sh) end
            end
        end
    end
    if changed then saveGroups() end
end

Events.EveryOneMinute.Add(guard)

-- release a safehouse from the panel, main plus every annex. There was no
-- admin path for this at all before: shSet/shShape
-- both refuse to shrink a zone to nothing on purpose, and the only release
-- command in the whole mod (claimRelease) is player-only, on their own
-- self claim. This is the missing counterpart for admins.
-- x,y may be the main's own anchor or any annex tile; either way the
-- WHOLE group goes, a zone's identity is the group, not one rectangle
-- (same rule the shape editor itself follows)
-- Hand a release over to Knox Claim when that mod owns the property here.
-- Returns "none" (no Knox claim, nothing to do), "released" (Knox let go of
-- zone and record) or "stuck" (Knox is still holding it, so the zone WILL
-- come back and the admin has to hear about it).
-- Everything is guarded and probed by name: Knox is optional, and none of
-- this may throw on a server that runs without it. The result is VERIFIED by
-- reading the claim table again instead of trusting the call, because Knox
-- refuses for its own reasons, among them a mover who is not a vanilla admin
-- (its doAdminRelease checks that itself, and Aegis grants the zones area on
-- its own roles as well)
local function knoxRelease(player, x, y)
    local state = "none"
    pcall(function()
        if not (KnoxClaim and KnoxClaim.Server and KnoxClaim.Server.doAdminRelease
            and KnoxClaim.Store and KnoxClaim.findClaimAt) then return end
        local claims = KnoxClaim.Store.data().claims
        if not claims then return end
        local claim = KnoxClaim.findClaimAt(claims, x, y, 0)
        if not claim or not claim.id then return end
        local id = tostring(claim.id)
        KnoxClaim.Server.doAdminRelease(player, { id = id })
        local after = KnoxClaim.Store.data().claims
        state = (after and after[id]) and "stuck" or "released"
    end)
    return state
end

Commands.shRelease = function(player, args)
    if not AegisRoles.canArea(player, "zones") then denyPlayer(player) return end
    if not args then return end
    local x = math.floor(tonumber(args.x) or -1)
    local y = math.floor(tonumber(args.y) or -1)
    if x < 0 or y < 0 then return end
    loadGroups()
    local hx, hy = x, y
    for _, g in pairs(groups) do
        if g.hx == x and g.hy == y then
            hx, hy = g.hx, g.hy
            break
        end
        for _, r in ipairs(g.parts) do
            if r.x == x and r.y == y then
                hx, hy = g.hx, g.hy
                break
            end
        end
    end
    local sh = findSafehouseAt(hx, hy)
    if not sh then
        toClient(player, "shRelease", { ok = false, reason = "none" })
        return
    end
    local owner = shOwner(sh)
    -- Knox Claim keeps its OWN record beside the vanilla zone and rebuilds
    -- the zone from it (KC_Safehouse.ensure). Dropping only the vanilla zone
    -- made this button a lie: it reported success, the owner kept the
    -- property and the zone was back moments later. Where
    -- a Knox claim covers this spot its own admin release does the work,
    -- that one takes the zone AND the record
    local knox = knoxRelease(player, hx, hy)
    if knox ~= "released" then dropSafehouse(sh) end
    -- reap annexes and the registry entry right away instead of waiting
    -- for the next EveryOneMinute tick, guard() already does exactly that
    -- for any main it finds missing
    guard()
    zlog(string.format("shRelease by %s: %s at %d,%d (knox: %s)",
        adminOf(player), owner, hx, hy, knox))
    AegisLog.write("Actions", adminOf(player), owner,
        string.format("Safehouse released via panel: %d,%d%s", hx, hy,
            knox == "released" and " (Knox Claim property released too)"
            or (knox == "stuck" and " (WARNING: Knox Claim still holds it)" or "")))
    toClient(player, "shRelease", { ok = true, knox = knox })
end

local function onClientCommand(module, command, player, args)
    if module ~= AegisShared.MODULE then return end
    -- suspended admins may not use any Aegis area anymore, not just
    -- moderation itself (otherwise the suspension only exists on paper)
    if AegisModeration.isSuspended(player) then return end
    if Commands[command] then Commands[command](player, args) end
end

Events.OnClientCommand.Add(onClientCommand)
