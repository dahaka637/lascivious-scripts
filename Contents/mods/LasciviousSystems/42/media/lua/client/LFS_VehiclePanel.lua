-- Lascivious Factions System - "Veículos" faction panel tab (client side).
--
-- Lists every vehicle currently detected inside the player's own faction's
-- territory, each as a row with a small non-interactive 3D preview, its
-- name, and the PROTEGER/TRANCAR controls -- see LFS_Panel.lua's
-- populateVehicles for the actual row layout, and LFS_VehicleGuard.lua
-- (shared) for what protection/locking actually mean server-side.

require "Vehicles/ISUI/ISUI3DScene"
require "LFS_Shared"
require "LFS_Claims"
require "LFS_UI"
require "LFS_Localization"

local FF = LasciviousFactionsSystem
local Claims = FF.Claims
local UI = FF.UI

-- ---------------------------------------------------------------------------
-- Vehicle discovery
-- ---------------------------------------------------------------------------
-- Every currently-loaded vehicle, regardless of territory -- walked via the
-- Java Iterator protocol, same reasoning and same caveat as LFS_Server.lua's
-- workshopMaintTick (getCell():getVehicles() is a java.util.HashSet -- no
-- get(int) -- see that function's own comment for the full story). This is
-- the primitive a PROTECTED row's live preview is resolved from -- protected
-- status has nothing to do with the vehicle's current territory (it may
-- have been driven right outside the claim edge, or simply be sitting there
-- loaded), only with whether the vehicle is loaded at all right now. Using
-- the territory-filtered FF.factionVehicles for this (an earlier version
-- did) meant a protected vehicle sitting in plain sight, loaded, one tile
-- outside the claim line showed as "out of range" -- wrong, and confusing,
-- per direct feedback ("não entendi o motivo de não mostrar o 3D... isso é
-- ridículo").
function FF.allLoadedVehicles()
    local cell = getCell()
    local vehicles = cell and cell:getVehicles()
    if not vehicles then return {} end

    local out = {}
    local ok = pcall(function()
        local it = vehicles:iterator()
        while it:hasNext() do
            local v = it:next()
            if v then out[#out + 1] = v end
        end
    end)
    if not ok then return {} end
    return out
end

-- Loaded vehicles currently standing inside `factionName`'s own territory --
-- used ONLY to find NEW, not-yet-protected candidates worth showing in the
-- "DETECTADOS NO TERRITÓRIO" section. Protected rows use FF.allLoadedVehicles
-- above instead (see its own comment for why).
function FF.factionVehicles(factionName)
    local out = {}
    for _, v in ipairs(FF.allLoadedVehicles()) do
        local owner = Claims.factionAt(math.floor(v:getX()), math.floor(v:getY()))
        if owner == factionName then out[#out + 1] = v end
    end
    return out
end

-- ---------------------------------------------------------------------------
-- Non-interactive 3D preview, one per vehicle row. Adapted from the shop's
-- own LasciviousShopVehicleScene (client/LasciviousShop_VehicleScene.lua) --
-- same setup/zoom-calibration approach, since that is the proven, tuned
-- reference for embedding a small vehicle viewport in a card. Click is a
-- no-op here (no cart to add to); showVehicleType takes a plain fullType
-- string ("Base.PickupTruck" style, from vehicle:getScript():getFullName())
-- instead of a shop product table.
-- ---------------------------------------------------------------------------
FF_VehicleScene = ISUI3DScene:derive("FF_VehicleScene")

function FF_VehicleScene:onMouseDown(x, y) return true end
function FF_VehicleScene:onMouseMove(dx, dy) end
function FF_VehicleScene:onMouseUp(x, y) return true end
function FF_VehicleScene:onMouseUpOutside(x, y) end
function FF_VehicleScene:onMouseWheel(del) return true end

function FF_VehicleScene:new(x, y, width, height)
    local o = ISUI3DScene.new(self, x, y, width, height)
    local c = UI.color
    o.background = true
    o.backgroundColor = { r = c.panel2.r, g = c.panel2.g, b = c.panel2.b, a = 1 }
    o.borderColor = { r = c.border.r, g = c.border.g, b = c.border.b, a = 1 }
    o.currentFullType = nil
    return o
end

-- Must run exactly once per widget, right after instantiate() -- calling
-- createVehicle("vehicle") again on a slot that already has one is what the
-- shop's own version of this comment warns broke paging; same rule applies.
function FF_VehicleScene:setupOnce()
    pcall(function()
        local jo = self.javaObject
        jo:fromLua1("setDrawGrid", false)
        jo:fromLua1("setDrawGridAxes", false)
        jo:fromLua1("setMaxZoom", 20)
        jo:fromLua1("createVehicle", "vehicle")
        jo:fromLua1("setView", "UserDefined")
        jo:fromLua3("setViewRotation", 18, 35, 0)
    end)
end

-- Identical calibration to LasciviousShopVehicleScene's autoZoomFor -- same
-- viewport-fitting goal, no reason to re-derive it for this context.
local ZOOM_INTERCEPT = 5.8
local ZOOM_SLOPE = 0.83
local MIN_ZOOM, MAX_ZOOM = 1.2, 6.5
local DEFAULT_ZOOM = 3.5

-- LFS-specific, applied ON TOP of the shop's own formula above (that formula
-- is left untouched -- it's proven/tuned there for the shop's own, much
-- bigger grid-tile viewport). This tab's rows are visibly smaller than a
-- shop card, and per direct feedback the vehicle read as "lost" in a mostly-
-- empty box at the shop's own zoom level -- the 3D camera's field of view is
-- NOT auto-scaled to viewport pixel size, so making the box itself bigger
-- (an earlier, wrong attempt at this fix) only showed more empty space
-- around the same small model instead of a bigger one. Pulling the camera
-- closer (higher zoom = closer, per the shop's own calibration notes) is the
-- actual fix. Re-clamped to a higher ceiling than the shop's own MAX_ZOOM so
-- the boost can't be capped away for small vehicles already near it.
local ZOOM_BOOST = 1.6
local BOOSTED_MAX_ZOOM = 9.5

local function autoZoomFor(script)
    local ok, footprint = pcall(function()
        local extents = script:getExtents()
        return math.max(extents:x(), extents:z())
    end)
    if not ok or not footprint or footprint <= 0 then return DEFAULT_ZOOM * ZOOM_BOOST end
    local zoom = ZOOM_INTERCEPT - ZOOM_SLOPE * footprint
    zoom = math.max(MIN_ZOOM, math.min(MAX_ZOOM, zoom))
    return math.min(BOOSTED_MAX_ZOOM, zoom * ZOOM_BOOST)
end

-- Assigns/refreshes this widget to show `fullType`'s vehicle model. Only
-- touches the Java scene calls when the type actually changed.
function FF_VehicleScene:showVehicleType(fullType)
    if not fullType or fullType == self.currentFullType then return end
    self.currentFullType = fullType
    pcall(function()
        local jo = self.javaObject
        jo:fromLua2("setVehicleScript", "vehicle", fullType)
        local script = jo:fromLua1("getVehicleScript", "vehicle")
        jo:fromLua1("setZoom", script and autoZoomFor(script) or (DEFAULT_ZOOM * ZOOM_BOOST))
    end)
end
