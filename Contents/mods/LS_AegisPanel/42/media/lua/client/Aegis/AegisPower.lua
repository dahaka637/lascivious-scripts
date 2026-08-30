-- Power range overlay: dark tile fills for every loaded, running generator
-- show exactly the tiles it actually powers (2D euclidean radius
-- SandboxVars.GeneratorTileRange, floor band GeneratorVerticalPowerRange,
-- the same formula IsoGenerator uses internally in isPoweringSquare).
-- Display only, no server part.
--
-- A previous version drew a circle outline via renderIsoCircle from
-- Events.OnPreUIDraw. Bytecode research showed renderIsoCircle itself is
-- render pass independent (pure world to screen projection through the
-- camera, always identical), so that was NOT the cause. The real reason
-- for "the circle follows me" was the carry/placement
-- preview, which deliberately followed the player/cursor. That is now
-- fully removed, only the real supply tiles of actually placed, running
-- generators remain. Drawing works like AegisZoneOverlay as a fullscreen
-- panel with isoToScreen projection (screenProjection/AegisPageZones
-- pattern) plus drawTextureAllPoint for filled tile diamonds, no circle.
require "Aegis/AegisTheme"

AegisPower = AegisPower or {}

local enabled = false
local permitted = false
local generators = {}
local nextScan = 0

function AegisPower.isOn()
    return enabled
end

-- rescan the generator list every 2 seconds, not per frame.
-- getProcessIsoObjects keeps every placed IsoGenerator permanently
local function refresh()
    local now = getTimestampMs()
    if now < nextScan then return end
    nextScan = now + 2000
    permitted = Aegis.allowed(getPlayer()) and Aegis.canSee("tools")
    generators = {}
    if not (enabled and permitted) then return end
    local cell = getCell()
    local objects = cell and cell:getProcessIsoObjects()
    if not objects then return end
    for i = 0, objects:size() - 1 do
        local o = objects:get(i)
        if o and instanceof(o, "IsoGenerator") then
            table.insert(generators, o)
        end
    end
    local where = {}
    for _, g in ipairs(generators) do
        pcall(function()
            table.insert(where, math.floor(g:getX()) .. "," .. math.floor(g:getY())
                .. "," .. math.floor(g:getZ()) .. (g:isActivated() and " an" or " aus"))
        end)
    end
    print("[Aegis] power scan: " .. tostring(#generators) .. " generator(s) of "
        .. tostring(objects:size()) .. " process objects, permitted "
        .. tostring(permitted) .. (#where > 0 and (": " .. table.concat(where, " | ")) or ""))
end

-- ==================================================================
-- World to screen, exactly the pattern from AegisPageZones.lua
-- ==================================================================
local function currentLevel()
    local p = getPlayer()
    return p and math.floor(p:getZ()) or 0
end

local function screenProjection(wx, wy, z)
    local ok, anchorX, anchorY = pcall(function()
        return isoToScreenX(0, wx, wy, z), isoToScreenY(0, wx, wy, z)
    end)
    if not ok then return nil end
    local zoom = getCore():getZoom(0)
    local baseX = IsoUtils.XToScreen(wx, wy, z, 0)
    local baseY = IsoUtils.YToScreen(wx, wy, z, 0)
    return function(px, py)
        return anchorX + (IsoUtils.XToScreen(px, py, z, 0) - baseX) / zoom,
            anchorY + (IsoUtils.YToScreen(px, py, z, 0) - baseY) / zoom
    end
end

-- filled tile (diamond) over the four projected corners; nil as texture
-- draws a plain color fill (same approach ISUIElement:drawLine2 uses
-- internally for lines)
local function fillTile(el, projection, dx, dy, r, g, b, a)
    local x1, y1 = projection(dx, dy)
    local x2, y2 = projection(dx + 1, dy)
    local x3, y3 = projection(dx + 1, dy + 1)
    local x4, y4 = projection(dx, dy + 1)
    el:drawTextureAllPoint(nil, x1, y1, x2, y2, x3, y3, x4, y4, r, g, b, a)
end

-- ring of edge tiles for a radius, computed once and cached: the full
-- disc fill was over 1250 textured draw calls per generator per FRAME
--, the boundary ring carries the same
-- information with about a tenth of the draws
local edgeCache = {}
local function edgeOffsets(radius)
    local cached = edgeCache[radius]
    if cached then return cached end
    local list = {}
    local r2 = radius * radius
    for dx = -radius, radius do
        for dy = -radius, radius do
            if dx * dx + dy * dy <= r2 then
                local outside = (dx + 1) * (dx + 1) + dy * dy > r2
                    or (dx - 1) * (dx - 1) + dy * dy > r2
                    or dx * dx + (dy + 1) * (dy + 1) > r2
                    or dx * dx + (dy - 1) * (dy - 1) > r2
                if outside then table.insert(list, { dx, dy }) end
            end
        end
    end
    edgeCache[radius] = list
    return list
end

-- ==================================================================
-- Overlay: fullscreen, click-through, lives independent of the Aegis window
-- ==================================================================
AegisPowerOverlay = ISPanel:derive("AegisPowerOverlay")
AegisPowerOverlay.instance = nil

local function setOverlay(show)
    if show and not AegisPowerOverlay.instance then
        local sw, sh = getCore():getScreenWidth(), getCore():getScreenHeight()
        local o = ISPanel:new(0, 0, sw, sh)
        setmetatable(o, AegisPowerOverlay)
        AegisPowerOverlay.__index = AegisPowerOverlay
        o.background = false
        o:initialise()
        o:addToUIManager()
        pcall(function() o.javaObject:setConsumeMouseEvents(false) end)
        AegisPowerOverlay.instance = o
    elseif not show and AegisPowerOverlay.instance then
        AegisPowerOverlay.instance:removeFromUIManager()
        AegisPowerOverlay.instance = nil
    end
end

function AegisPower.setOn(value)
    enabled = value == true
    -- rescan immediately instead of drawing empty for up to 2 seconds
    nextScan = 0
    if not enabled then generators = {} end
    setOverlay(enabled)
end

function AegisPower.toggle()
    AegisPower.setOn(not enabled)
    return enabled
end

function AegisPowerOverlay:render()
    refresh()
    if not permitted or #generators == 0 then return end
    local z = currentLevel()

    local sv = SandboxVars or {}
    local radius = math.floor(tonumber(sv.GeneratorTileRange) or 20)
    local vertical = tonumber(sv.GeneratorVerticalPowerRange) or 3
    if radius < 1 then return end
    local r2 = radius * radius

    local sw, sh = getCore():getScreenWidth(), getCore():getScreenHeight()
    local margin = 64

    for _, gen in ipairs(generators) do
        -- show switched-off/empty generators too, just dimmed. A generator
        -- WITHOUT fuel supplies no power right now, but the area still
        -- reliably shows "this is where it would supply" (otherwise
        -- with a currently stopped generator the active-only filter drew
        -- nothing at all and looked like a bug)
        local active = gen:isActivated()
        local distance = math.abs(z - gen:getZ())
        if distance <= vertical then
            local base = active and 0.55 or 0.30
            local a = distance < 0.5 and base or base * 0.35
            local gx, gy = math.floor(gen:getX()), math.floor(gen:getY())
            local projection = screenProjection(gx, gy, z)
            if projection then
                for _, o in ipairs(edgeOffsets(radius)) do
                    -- rough screen clip before drawing
                    local mx, my = projection(gx + o[1] + 0.5, gy + o[2] + 0.5)
                    if mx > -margin and mx < sw + margin and my > -margin and my < sh + margin then
                        if active then
                            fillTile(self, projection, gx + o[1], gy + o[2], 0.06, 0.5, 0.7, a)
                        else
                            fillTile(self, projection, gx + o[1], gy + o[2], 0.4, 0.4, 0.4, a)
                        end
                    end
                end
                -- generator tile itself marked so the source is obvious
                fillTile(self, projection, gx, gy, 0.9, 0.75, 0.2, 0.5)
            end
        end
    end
end
