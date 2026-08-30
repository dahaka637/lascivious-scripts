if isServer() then return end

require "Vehicles/ISUI/ISUI3DScene"
require "LasciviousShop_Shared"
require "LasciviousShop_Theme"

local LS = LasciviousShop
local UI = LasciviousShopUI

-- ==================================================================
-- Non-interactive vehicle preview, embedded directly in the shop card
-- instead of a separate detail popup: no drag-to-rotate, no scroll-to-zoom
-- -- every mouse event is a no-op except a click, which is forwarded to the
-- exact same addToCart the rest of the card already uses, so the model
-- being a real child widget (not just a drawn icon) never changes what
-- clicking a vehicle card does. Belt-and-suspenders with the parent
-- window's own rect-based click handling in LasciviousShop_Window.lua --
-- whichever one the engine actually routes the click to, the outcome is
-- the same, so it doesn't matter which of the two claims it.
-- ==================================================================
LasciviousShopVehicleScene = ISUI3DScene:derive("LasciviousShopVehicleScene")

function LasciviousShopVehicleScene:onMouseDown(x, y)
    if self.shopWindow and self.product then
        self.shopWindow:bringToTop()
        self.shopWindow:addToCart(self.product)
    end
    return true
end

function LasciviousShopVehicleScene:onMouseMove(dx, dy) end
function LasciviousShopVehicleScene:onMouseUp(x, y) return true end
function LasciviousShopVehicleScene:onMouseUpOutside(x, y) end
function LasciviousShopVehicleScene:onMouseWheel(del) return true end

function LasciviousShopVehicleScene:new(x, y, width, height)
    local o = ISUI3DScene.new(self, x, y, width, height)
    -- Every reference this was studied from (vanilla's own vehicle
    -- customisation panel, the admin tool it was cross-checked against)
    -- always sets an explicit background rather than leaving it off, so this
    -- follows that rather than guessing at what the bare 3D viewport looks
    -- like with none.
    o.background = true
    o.backgroundColor = { r = UI.col.bg.r, g = UI.col.bg.g, b = UI.col.bg.b, a = 1 }
    o.borderColor = { r = UI.col.line.r, g = UI.col.line.g, b = UI.col.line.b, a = 1 }
    o.currentFullType = nil
    return o
end

-- One-time scene setup: must run exactly ONCE per pooled widget, right after
-- instantiate(). Calling createVehicle("vehicle") again on a slot that
-- already has a vehicle object is almost certainly what was throwing errors
-- when paging through the vehicle category -- vanilla's own vehicle
-- customisation panel (Vehicles/ISUI/EditVehicleState.lua) and every
-- reference admin tool this was cross-checked against only ever call
-- createVehicle once at setup, then swap models purely via setVehicleScript
-- on subsequent changes (see showVehicle below).
function LasciviousShopVehicleScene:setupOnce()
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

-- Zoom calibration, from actual in-game screenshots (2026-08-17, two
-- rounds): the first version scaled zoom UP with vehicle size, assuming a
-- bigger number meant "further away" -- backwards. Round one showed small
-- trailers looking right at a small zoom value while sedans/pickups/vans
-- (bigger footprint, bigger zoom under the old formula) got progressively
-- more cropped, only consistent with a HIGHER number meaning CLOSER -- so
-- bigger vehicles need a LOWER number, the opposite of the original
-- formula; fixed as a straight line through those two data points (trailer
-- ~1.5 footprint near its old working ~3.75, sedan 2.4 footprint roughly
-- halved from the too-close 6 to ~3). Round two (vans, after the "+"
-- removal freed up card space) landed comfortably inside the frame with
-- room to spare, so the whole line was nudged up a little (+0.8 intercept)
-- for a bit more fill -- proportionally the biggest gain for the
-- smaller-zoom/bigger vehicles that had the least margin. Box trucks are
-- still extrapolated past the last confirmed point.
local ZOOM_INTERCEPT = 5.8
local ZOOM_SLOPE = 0.83
local MIN_ZOOM, MAX_ZOOM = 1.2, 6.5
local DEFAULT_ZOOM = 3.5

local function autoZoomFor(script)
    local ok, footprint = pcall(function()
        local extents = script:getExtents()
        return math.max(extents:x(), extents:z())
    end)
    if not ok or not footprint or footprint <= 0 then return DEFAULT_ZOOM end
    local zoom = ZOOM_INTERCEPT - ZOOM_SLOPE * footprint
    return math.max(MIN_ZOOM, math.min(MAX_ZOOM, zoom))
end

-- Assigns/refreshes this pooled widget to show `product`'s vehicle model.
-- Only touches the Java scene calls when the product actually changed since
-- last frame -- every other frame this is just the cheap
-- setX/setY/setWidth/setHeight reposition in the caller.
function LasciviousShopVehicleScene:showVehicle(product)
    if not product or product.fullType == self.currentFullType then return end
    self.currentFullType = product.fullType
    self.product = product
    pcall(function()
        local jo = self.javaObject
        jo:fromLua2("setVehicleScript", "vehicle", product.fullType)
        local script = jo:fromLua1("getVehicleScript", "vehicle")
        jo:fromLua1("setZoom", script and autoZoomFor(script) or DEFAULT_ZOOM)
    end)
end
