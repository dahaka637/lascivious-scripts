-- Vehicles page of the player panel: registered cars with distance and
-- heading, a rotatable 3D preview and a screen navi that points the way
-- back to a lost vehicle. All rules live in Aegis_PlayerVehicles.lua,
-- this side only renders and asks.
require "ISUI/ISPanel"
require "Vehicles/ISUI/ISUI3DScene"
require "Aegis/AegisTheme"
require "Aegis/AegisWidgets"
require "Aegis/AegisPlayerCore"
require "Aegis/AegisPlayerWindow"

AegisPlayerPageVehicles = ISPanel:derive("AegisPlayerPageVehicles")
AegisPlayerPageVehicles.instance = nil

local MODULE = "AegisPlayer"
local TRY_MAX = 5
-- above the 5s server throttle for vehList, shorter retries only burn
-- requests the server drops
local RETRY_MS = 6000
local ROW_H = 56
-- upper bounds, applyLayout shrinks both on small panels
local LIST_W = 300
local PREVIEW_H = 250
-- display only, the server decides. Same sandbox option and the same
-- fallback as Aegis_PlayerVehicles.maxVehicles, sandbox values are
-- readable on both sides
local function maxVehicles()
    local n = nil
    local v = SandboxVars and SandboxVars.AegisEvents
        and SandboxVars.AegisEvents.PlayerVehicles
    if v ~= nil then n = math.floor(tonumber(v) or 0) end
    if not n or n < 0 then n = 5 end
    return math.min(n, 20)
end
local ARRIVE_TILES = 10
local POLL_MS = 30000

-- ---------- shared helpers ----------
local COMPASS_KEYS = {
    "UI_AegisPlayer_CompassN", "UI_AegisPlayer_CompassNE",
    "UI_AegisPlayer_CompassE", "UI_AegisPlayer_CompassSE",
    "UI_AegisPlayer_CompassS", "UI_AegisPlayer_CompassSW",
    "UI_AegisPlayer_CompassW", "UI_AegisPlayer_CompassNW",
}

local function playerPos()
    local x, y = nil, nil
    local p = getPlayer()
    if p then
        x, y = p:getX(), p:getY()
    end
    return x, y
end

-- distance in tiles plus the compass sector towards the target; world
-- north is negative y, so the bearing comes from atan2(dx, -dy)
local function distanceAndHeading(tx, ty)
    local px, py = playerPos()
    if not px then return nil end
    local dx, dy = tx - px, ty - py
    local dist = math.sqrt(dx * dx + dy * dy)
    local bearing = math.deg(math.atan2(dx, -dy))
    if bearing < 0 then bearing = bearing + 360 end
    local sector = math.floor((bearing + 22.5) / 45) % 8 + 1
    return dist, getText(COMPASS_KEYS[sector])
end

-- admin nicknames are literal text, script names translate like the
-- vanilla vehicle list does
local function displayName(e)
    local raw = tostring(e.name or "")
    if raw == "" then return "?" end
    return getTextOrNull("IGUI_VehicleName" .. raw) or raw
end

local function distLine(e)
    -- Knox entries only have a position while the car is loaded nearby
    if not e.x or not e.y then return "--" end
    local dist, heading = distanceAndHeading(e.x, e.y)
    if not dist then return "--" end
    return string.format("%d m %s", math.floor(dist + 0.5), heading)
end

-- amber middle band for the state bars, same tone as the health page
local AMBER = { r = 0.83, g = 0.62, b = 0.25 }

local function stateColor(v)
    local c = AegisPlayerCol
    if v < 30 then return c.danger end
    if v < 60 then return AMBER end
    return c.accent
end

-- ==================================================================
-- Vehicle state, measured here and pushed to the ledger.
-- The server sees the parts without their installed items and reported
-- condition 15 and engine 0 for a mint van, so the numbers come from the
-- machine that also feeds the vanilla mechanics window. Only vehicles
-- the player has loaded around him can be measured, everything else
-- keeps the stored snapshot and goes stale.
-- ==================================================================
local STATE_RANGE = 40
local STATE_MS = 30000
local nextPush = {}

-- mod vehicles and mod parts may report outside the band
local function clampPct(v)
    if not v or v ~= v then return nil end
    if v < 0 then return 0 end
    if v > 100 then return 100 end
    return math.floor(v + 0.5)
end

-- vanilla general condition (ISVehicleMechanics.recalculGeneralCondition):
-- every part counts, no category filter, and a part that offers item
-- variants but has none installed counts as zero
local function generalCondition(car)
    local out = nil
    local sum, n = 0, 0
    for i = 0, car:getPartCount() - 1 do
        local part = car:getPartByIndex(i)
        if part then
            local cond = part:getCondition()
            local types = part:getItemType()
            if types and not types:isEmpty() and not part:getInventoryItem() then
                cond = 0
            end
            sum = sum + cond
            n = n + 1
        end
    end
    if n > 0 then out = math.floor(sum / n + 0.5) end
    return out
end

local function readState(car)
    local st = {}
    st.cond = generalCondition(car)
    -- the tank script carries no capacity, the engine takes it from the
    -- installed tank item: without that item capacity is 0 and the fill
    -- is unknown, not empty
    pcall(function()
        local tank = car:getPartById("GasTank")
        if tank and tank:getInventoryItem() then
            local cap = tank:getContainerCapacity()
            if cap and cap > 0 then
                st.fuel = math.floor(tank:getContainerContentAmount() / cap * 100 + 0.5)
            end
        end
    end)
    -- the battery part has no container at all, its charge is the
    -- remaining uses of the battery item (getBatteryCharge is 0..1)
    local bat = car:getPartById("Battery")
    if bat and bat:getInventoryItem() then
        st.batt = math.floor(car:getBatteryCharge() * 100 + 0.5)
    end
    -- engine condition, the percentage the mechanics window prints next
    -- to the engine part. getEngineQuality is a fixed spawn attribute
    -- that never moves with wear and would be a dead bar
    local eng = car:getPartById("Engine")
    if eng then st.engine = eng:getCondition() end
    -- clamped field by field, never by clearing keys inside pairs: a
    -- Kahlua table does not like losing entries mid traversal
    st.cond, st.fuel = clampPct(st.cond), clampPct(st.fuel)
    st.batt, st.engine = clampPct(st.batt), clampPct(st.engine)
    return st
end

-- the vehicle object only exists while its cell is loaded; the distance
-- check keeps a stale object from a far corner out
local function reachable(id)
    -- number first: Knox rows carry a string key as id, the engine call
    -- takes only the net number, and the kahlua bridge answers a wrong
    -- argument type with a java exception that NO pcall catches (the
    -- documented trap, and it still bit: one error per tick, live report)
    id = tonumber(id)
    if not id then return nil end
    local car = nil
    pcall(function() car = getVehicleById(id) end)
    if not car then return nil end
    local near = false
    pcall(function()
        local p = getPlayer()
        if p and car:getSquare() then
            local dx, dy = car:getX() - p:getX(), car:getY() - p:getY()
            near = (dx * dx + dy * dy) <= STATE_RANGE * STATE_RANGE
        end
    end)
    if not near then return nil end
    return car
end

-- ==================================================================
-- Finding a Knox vehicle in the world.
-- NEVER by the stored net number: the engine hands out fresh ids after
-- every restart, so after a relog that number points at nothing or at a
-- stranger, and distance, bars and the part list stayed blank (user
-- report). The claim key in the vehicle's modData is the only stable
-- link, so the world is searched for it and the hit is cached.
-- Defined ABOVE carFor on purpose: a local declared further down is
-- still nil when the function above it runs, and kahlua answers that
-- with "tried to call nil", once per tick
-- ==================================================================
local KNOX_SCAN = 30
local KNOX_SCAN_MS = 3000
local knoxCar = {}
local knoxScanAt = 0

-- both registries stamp their vehicles: Knox Claim with KnoxClaimKey,
-- the own ledger with aegisVehKey (same cure, same reason). A vehicle
-- can carry both, so the match is against the asked key, never against
-- "whatever stamp comes first"
local function hasStamp(car, key)
    local hit = false
    pcall(function()
        local md = car:getModData()
        hit = tostring(md.KnoxClaimKey) == key or tostring(md.aegisVehKey) == key
    end)
    return hit
end

-- one sweep for ALL stamped vehicles instead of one per row. Step 2 on
-- purpose: the smallest vehicle still covers two tiles, so nothing slips
-- through while the lookups drop to a quarter
local function knoxScan()
    local now = getTimestampMs()
    if now < knoxScanAt then return end
    knoxScanAt = now + KNOX_SCAN_MS
    local p = getPlayer()
    if not p then return end
    local cell = getCell()
    local px, py, pz = math.floor(p:getX()), math.floor(p:getY()), math.floor(p:getZ())
    for dy = -KNOX_SCAN, KNOX_SCAN, 2 do
        for dx = -KNOX_SCAN, KNOX_SCAN, 2 do
            local sq = cell:getGridSquare(px + dx, py + dy, pz)
            local v = sq and sq:getVehicleContainer()
            if v then
                local md = v:getModData()
                if md.KnoxClaimKey then knoxCar[tostring(md.KnoxClaimKey)] = v end
                if md.aegisVehKey then knoxCar[tostring(md.aegisVehKey)] = v end
            end
        end
    end
end

local function knoxVehicleFor(key, net)
    if not key then return nil end
    key = tostring(key)
    -- cached hit, verified every time: kahlua wrappers go stale and the
    -- stamp is the only thing that proves identity
    local car = knoxCar[key]
    if car then
        if hasStamp(car, key) then return car end
        knoxCar[key] = nil
    end
    -- the stored number is correct within one session, so try it first
    -- and skip the sweep in the common case
    if net then
        local hit = nil
        pcall(function()
            local c = getVehicleById(tonumber(net) or -1)
            if c and hasStamp(c, key) then hit = c end
        end)
        if hit then
            knoxCar[key] = hit
            return hit
        end
    end
    knoxScan()
    return knoxCar[key]
end

-- the vehicle behind a row, whichever list it came from, with the same
-- reach rule for both. Knox rows carry a text key as id, which is why
-- reachable() alone can never serve them
local function carFor(e)
    if not e then return nil end
    if not e.knox then
        -- stamped ledger rows heal like Knox rows; only the stampless
        -- relics from before the key column keep the bare id path
        if not e.key then return reachable(e.id) end
        local car = knoxVehicleFor(e.key, e.id)
        if not car then return nil end
        local near = false
        local p = getPlayer()
        if p then
            local dx, dy = car:getX() - p:getX(), car:getY() - p:getY()
            near = (dx * dx + dy * dy) <= STATE_RANGE * STATE_RANGE
        end
        return near and car or nil
    end
    local car = knoxVehicleFor(e.knoxKey, e.net)
    if not car then return nil end
    -- distance from the coordinates alone. getSquare() as a condition was
    -- one link too many: it can be nil on a loaded vehicle, and then the
    -- part list stayed on "too far away" while the bars right above it
    -- were happily updating from the very same vehicle
    local near = false
    local p = getPlayer()
    if p then
        local dx, dy = car:getX() - p:getX(), car:getY() - p:getY()
        near = (dx * dx + dy * dy) <= STATE_RANGE * STATE_RANGE
    end
    return near and car or nil
end

-- measure everything in reach and hand it over, at most once per vehicle
-- and half minute. The entry keeps the fresh numbers right away so the
-- page does not wait for the next list
local function pushStates(entries)
    local p = getPlayer()
    if not p then return end
    local now = getTimestampMs()
    for _, e in ipairs(entries) do
        -- Knox entries belong to the Knox registry, the Aegis ledger has
        -- no row for them and must not be written
        if not e.knox and now >= (nextPush[e.id] or 0) then
            local car = carFor(e)
            if not car then
                -- out of reach, look again in a moment instead of every
                -- frame the page is up
                nextPush[e.id] = now + 3000
            else
                nextPush[e.id] = now + STATE_MS
                local st = readState(car)
                e.cond, e.fuel = st.cond, st.fuel
                e.batt, e.engine = st.batt, st.engine
                e.fresh = true
                sendClientCommand(p, MODULE, "vehState", {
                    id = e.id, cond = st.cond, fuel = st.fuel,
                    batt = st.batt, engine = st.engine,
                })
            end
        end
    end
end

-- Knox Claim mode: the vehicles live in that mod's registry, and every
-- client holds it in full (KnoxClaim.Client.vehicles, sent with each
-- claims push). Read directly instead of keeping an own ledger: a second
-- list that only knows its half was the reason the remember button left.
-- The record's name is the script name, same convention as the ledger,
-- so translation and the 3D preview work unchanged
local function knoxEntries()
    local out = {}
    pcall(function()
        local me = getPlayer():getUsername()
        local faction = nil
        local f = Faction.getPlayerFaction(getPlayer())
        if f then faction = f:getName() end
        for key, rec in pairs(KnoxClaim.Client.vehicles or {}) do
            local mine = (rec.ownerType == "faction") and (rec.owner == faction)
                or (rec.ownerType ~= "faction") and (rec.owner == me)
            if mine then
                -- the record carries the FULL script name (Base.SmallCar).
                -- The preview wants exactly that, but the translation keys
                -- run IGUI_VehicleName<short>, so the display name needs
                -- the module stripped, same split the ledger keeps
                local full = tostring(rec.name or "")
                local e = { id = "kc-" .. tostring(key), knox = true,
                            knoxKey = tostring(key), net = rec.net,
                            name = full:match("[^%.]+$") or full,
                            script = full }
                -- position and bars need the real vehicle, found by claim
                -- key and cached, never by the stored number alone
                local car = knoxVehicleFor(key, rec.net)
                if car then
                    e.x, e.y = car:getX(), car:getY()
                    local st = readState(car)
                    e.cond, e.fuel = st.cond, st.fuel
                    e.batt, e.engine = st.batt, st.engine
                    e.fresh = true
                end
                out[#out + 1] = e
            end
        end
        table.sort(out, function(a, b) return displayName(a) < displayName(b) end)
    end)
    return out
end

-- ==================================================================
-- Part breakdown of the selected vehicle, also measured client side.
-- One sweep per second at most, everything drawn from the cache.
-- ==================================================================
local PARTS_MS = 1000
-- reserved strip for the breakdown. It has to clear the show threshold
-- below (headline + gaps + PARTS_ROWS_MIN), otherwise the card shrinks to
-- exactly the reserve and the list can never appear
-- line under the 3D stage that explains turning and zooming; the stage
-- gives up exactly this much height so the text is not drawn underneath
local STAGE_HINT_H = 18
local PARTS_ROWS_MIN = 46
local PARTS_MIN = 110

-- display order of the groups
local PART_CATS = {
    { id = "Engine", key = "UI_AegisPlayer_VehCatEngine" },
    { id = "Body", key = "UI_AegisPlayer_VehCatBody" },
    { id = "Doors", key = "UI_AegisPlayer_VehCatDoors" },
    { id = "Glass", key = "UI_AegisPlayer_VehCatGlass" },
    { id = "Wheels", key = "UI_AegisPlayer_VehCatWheels" },
    { id = "Chassis", key = "UI_AegisPlayer_VehCatChassis" },
    { id = "Interior", key = "UI_AegisPlayer_VehCatInterior" },
    { id = "Lights", key = "UI_AegisPlayer_VehCatLights" },
    { id = "Accessory", key = "UI_AegisPlayer_VehCatAccessory" },
    { id = "Other", key = "UI_AegisPlayer_VehCatOther" },
}

-- order matters: lights first, glass before body (vanilla files the
-- windshields under category bodywork), body before doors (hood and
-- trunk lid carry a door object), engine after body so EngineDoor is
-- already taken. Runs on plain data, the java reads happened in the
-- sweep below
local function classify(d)
    local id = d.id
    local lid = string.lower(id)
    local cat = d.cat or ""
    if lid:find("light") or lid:find("lamp") or lid:find("siren") or cat == "lights" then
        return "Lights"
    end
    if d.win or id:find("^Window") or id:find("^Windshield") or lid:find("windscreen") then
        return "Glass"
    end
    if id == "EngineDoor" or id:find("^TrunkDoor") or id:find("^TruckBed") or id:find("^Trailer")
        or d.trunk or lid:find("hood") or lid:find("bumper") or lid:find("fender")
        or lid:find("roof") or lid:find("grille") or lid:find("armor") or lid:find("armour")
        or lid:find("plate") or cat == "bodywork" then
        return "Body"
    end
    if id:find("^Door") or d.door then return "Doors" end
    if id:find("^Tire") or id:find("^Wheel") or d.wheel or cat == "tire" then return "Wheels" end
    if id:find("^Brake") or id:find("^Suspension") or id:find("^Axle") or id:find("^Shock")
        or cat == "brakes" or cat == "suspension" then
        return "Chassis"
    end
    if id:find("^Seat") or d.seat or lid:find("glovebox") or lid:find("dashboard")
        or lid:find("steering") or cat == "seat" then
        return "Interior"
    end
    if id == "Engine" or id:find("^Battery") or id:find("^Muffler") or id:find("^GasTank")
        or id:find("^FuelTank") or id:find("^Heater") or lid:find("alternator")
        or lid:find("radiator") or lid:find("transmission") or lid:find("exhaust")
        or lid:find("carburet") or lid:find("sparkplug") or lid:find("turbo")
        or cat == "engine" or cat == "gastank" then
        return "Engine"
    end
    if lid:find("radio") or lid:find("antenna") or lid:find("winch") or lid:find("plow")
        or lid:find("hitch") or lid:find("cooler") or lid:find("toolbox") or d.device then
        return "Accessory"
    end
    return "Other"
end

-- one pass over every part of a loaded vehicle. Category nodisplay is
-- dropped the way the vanilla mechanics window does it, a part that
-- offers item variants without one installed reads as missing
local function measureParts(car)
    local count = car:getPartCount() or 0
    if count <= 0 then return nil end
    local byCat = {}
    for i = 0, count - 1 do
        local d = nil
        -- one guard per part: a part that throws is skipped, the rest of
        -- the sweep survives
        pcall(function()
            local part = car:getPartByIndex(i)
            if not part then return end
            local cat = part:getCategory()
            if cat == "nodisplay" then return end
            local id = part:getId()
            if not id or id == "" then return end
            local e = { id = id, cat = cat, cond = part:getCondition() or 0 }
            local types = part:getItemType()
            e.hasTypes = types ~= nil and not types:isEmpty()
            e.hasItem = part:getInventoryItem() ~= nil
            local win = part:getWindow()
            if win then
                e.win = true
                e.dead = win:isDestroyed() == true
                e.open = win:isOpenable() == true and win:isOpen() == true
            end
            local door = part:getDoor()
            if door then
                e.door = true
                if door:isOpen() == true then e.open = true end
                e.locked = door:isLocked() == true
                e.lockBroken = door:isLockBroken() == true
            end
            e.wheel = (part:getWheelIndex() or -1) >= 0
            -- tire pressure hangs on the part container and is independent
            -- of the condition, a flat tire otherwise reads as healthy
            if part:isContainer() == true and part:getContainerContentType() == "Air" then
                local cap = part:getContainerCapacity() or 0
                if cap > 0 then
                    e.air = math.floor(((part:getContainerContentAmount() or 0) / cap) * 100 + 0.5)
                end
            end
            e.seat = part:isSeat() == true
            e.trunk = part:isVehicleTrunk() == true
            e.device = part:getDeviceData() ~= nil
            d = e
        end)
        if d then
            local miss = d.hasTypes == true and d.hasItem ~= true
            local cond = miss and 0 or (d.cond or 0)
            if cond < 0 then cond = 0 elseif cond > 100 then cond = 100 end
            cond = math.floor(cond + 0.5)
            local mark = nil
            if d.air ~= nil and d.air <= 0 then
                mark = "UI_AegisPlayer_VehPartFlat"
            elseif d.air ~= nil and d.air < 50 then
                mark = "UI_AegisPlayer_VehPartSoft"
            elseif d.open then
                mark = "UI_AegisPlayer_VehPartOpen"
            elseif d.lockBroken then
                mark = "UI_AegisPlayer_VehPartLockBroken"
            elseif d.locked then
                mark = "UI_AegisPlayer_VehPartLocked"
            end
            local cid = classify(d)
            local g = byCat[cid]
            if not g then
                g = { sum = 0, parts = {} }
                byCat[cid] = g
            end
            table.insert(g.parts, {
                name = getTextOrNull("IGUI_VehiclePart" .. d.id) or d.id,
                cond = cond,
                missing = miss,
                broken = (not miss) and (cond <= 0 or d.dead == true),
                mark = mark,
                air = d.air,
            })
            g.sum = g.sum + cond
        end
    end
    local out = {}
    for _, def in ipairs(PART_CATS) do
        local g = byCat[def.id]
        if g and #g.parts > 0 then
            table.insert(out, {
                key = def.key,
                parts = g.parts,
                avg = math.floor(g.sum / #g.parts + 0.5),
            })
        end
    end
    if #out == 0 then return nil end
    return out
end

-- ==================================================================
-- Navi: click-through fullscreen overlay in the blue panel style.
-- On screen the target gets a pulsing marker, off screen an arrow at
-- the screen edge points along the projected direction, the distance
-- rides in a small chip. Position refreshes every 30s over vehList,
-- arrival inside 10 tiles shows a short found note and shuts it off.
-- ==================================================================
AegisPlayerVehNavi = ISPanel:derive("AegisPlayerVehNavi")
AegisPlayerVehNavi.instance = nil
AegisPlayerVehNavi.target = nil

function AegisPlayerVehNavi.start(entry)
    AegisPlayerVehNavi.target = {
        id = entry.id, x = entry.x, y = entry.y, name = displayName(entry),
    }
    if not AegisPlayerVehNavi.instance then
        -- a 1x1 element instead of a fullscreen layer: UI drawing is not
        -- clipped to the element bounds, but a fullscreen panel counts as
        -- "UI under the mouse" every frame and starves the world right
        -- click even with mouse events off (same trap the
        -- construction radar hit with UIManager.lastPicked)
        local o = ISPanel:new(0, 0, 1, 1)
        setmetatable(o, AegisPlayerVehNavi)
        AegisPlayerVehNavi.__index = AegisPlayerVehNavi
        o.background = false
        o:initialise()
        o:addToUIManager()
        o.javaObject:setConsumeMouseEvents(false)
        AegisPlayerVehNavi.instance = o
    end
    local o = AegisPlayerVehNavi.instance
    o.nextPoll = getTimestampMs() + POLL_MS
    o.foundUntil = nil
end

function AegisPlayerVehNavi.stop()
    AegisPlayerVehNavi.target = nil
    if AegisPlayerVehNavi.instance then
        AegisPlayerVehNavi.instance:removeFromUIManager()
        AegisPlayerVehNavi.instance = nil
    end
end

-- fresh list from the server: track the target, a target that vanished
-- from the list was forgotten and takes the navi down with it. The home
-- target of the safehouse page is no vehicle and never in this list,
-- the sweep must not kill it
function AegisPlayerVehNavi.sync(entries)
    local t = AegisPlayerVehNavi.target
    if not t or t.home then return end
    for _, e in ipairs(entries) do
        if e.id == t.id then
            t.x, t.y = e.x, e.y
            t.name = displayName(e)
            return
        end
    end
    AegisPlayerVehNavi.stop()
end

function AegisPlayerVehNavi:update()
    if not AegisPlayerVehNavi.target then return end
    -- the navi dies with the session and with a revoked panel
    if not AegisPlayerClient.enabled() then
        AegisPlayerVehNavi.stop()
        return
    end
    local now = getTimestampMs()
    if self.foundUntil and now >= self.foundUntil then
        AegisPlayerVehNavi.stop()
        return
    end
    if now >= (self.nextPoll or 0) then
        self.nextPoll = now + POLL_MS
        -- walking towards the car counts as a trigger too: the state
        -- goes out first so the answering list already carries it
        pushStates({ AegisPlayerVehNavi.target })
        local p = getPlayer()
        if p then sendClientCommand(p, MODULE, "vehList", {}) end
    end
end

local function naviChip(el, cx, cy, text)
    local c = AegisPlayerCol
    local w = Aegis.strW(UIFont.Small, text) + 22
    local h = Aegis.fontH(UIFont.Small) + 8
    -- clamp against the real screen, the element is 1x1 (otherwise:
    -- el.width pushed every chip off screen after the overlay shrink)
    local sw, sh = getCore():getScreenWidth(), getCore():getScreenHeight()
    if cx - w / 2 < 8 then cx = 8 + w / 2 end
    if cx + w / 2 > sw - 8 then cx = sw - 8 - w / 2 end
    if cy < 8 then cy = 8 end
    if cy + h > sh - 8 then cy = sh - 8 - h end
    local x = math.floor(cx - w / 2)
    local y = math.floor(cy)
    Aegis.roundFrame(el, x, y, w, h, math.floor(h / 2), 0.92, c.accentDim, c.dark)
    Aegis.textCentre(el, text, math.floor(cx), y + 4, UIFont.Small, c.accentHi)
end

function AegisPlayerVehNavi:render()
    local t = AegisPlayerVehNavi.target
    if not t then return end
    local c = AegisPlayerCol
    local now = getTimestampMs()
    local dist = distanceAndHeading(t.x, t.y)
    if not dist then return end
    if not self.foundUntil and dist <= ARRIVE_TILES then
        self.foundUntil = now + 2500
    end
    -- the element is 1x1 (see start), everything positions against the
    -- real screen
    local sw, sh = getCore():getScreenWidth(), getCore():getScreenHeight()
    if self.foundUntil then
        -- the home target celebrates as home, not as a found vehicle
        local text = t.home and getText("UI_AegisPlayer_HomeFound")
            or getText("UI_AegisPlayer_VehFound")
        local w = Aegis.strW(UIFont.Medium, text) + 36
        local bx = math.floor((sw - w) / 2)
        Aegis.roundFrame(self, bx, 96, w, 36, 18, 0.95, c.accent, c.dark)
        Aegis.textCentre(self, text, math.floor(sw / 2), 105, UIFont.Medium, c.accentHi)
        return
    end
    local sx = isoToScreenX(0, t.x, t.y, 0)
    local sy = isoToScreenY(0, t.x, t.y, 0)
    if not sx or not sy then return end
    local pulse = 0.5 + 0.5 * math.sin(now / 260)
    local label = Aegis.fitText(t.name, UIFont.Small, 170)
        .. "  " .. string.format("%d m", math.floor(dist + 0.5))
    local M = 56

    if sx >= M and sx <= sw - M and sy >= M and sy <= sh - M then
        -- target in view: pulsing marker over the position
        local r = 16 + pulse * 8
        local a = 0.5 + 0.45 * pulse
        self:drawRectBorder(sx - r, sy - r, r * 2, r * 2, a, c.accentHi.r, c.accentHi.g, c.accentHi.b)
        self:drawRectBorder(sx - r - 5, sy - r - 5, r * 2 + 10, r * 2 + 10, 0.3 * a, c.accent.r, c.accent.g, c.accent.b)
        naviChip(self, sx, sy + r + 12, label)
        return
    end

    -- target outside: arrow clamped to the screen edge, its direction is
    -- the projected world delta (screen center towards the raw projection)
    local cx, cy = sw / 2, sh / 2
    local dxs, dys = sx - cx, sy - cy
    local len = math.sqrt(dxs * dxs + dys * dys)
    if len < 1 then return end
    local ux, uy = dxs / len, dys / len
    local tEdge = math.huge
    if ux > 1e-6 then
        tEdge = math.min(tEdge, (sw - M - cx) / ux)
    elseif ux < -1e-6 then
        tEdge = math.min(tEdge, (M - cx) / ux)
    end
    if uy > 1e-6 then
        tEdge = math.min(tEdge, (sh - M - cy) / uy)
    elseif uy < -1e-6 then
        tEdge = math.min(tEdge, (M - cy) / uy)
    end
    if tEdge == math.huge then return end
    local ax, ay = cx + ux * tEdge, cy + uy * tEdge
    local a = 0.55 + 0.4 * pulse
    local bx, by = ax - ux * 26, ay - uy * 26
    self:drawLine2(bx, by, ax, ay, a, c.accentHi.r, c.accentHi.g, c.accentHi.b)
    self:drawLine2(bx, by + 1, ax, ay + 1, a * 0.5, c.accentHi.r, c.accentHi.g, c.accentHi.b)
    local ang = math.atan2(uy, ux)
    for s = -1, 1, 2 do
        local ha = ang + s * math.rad(150)
        local hx, hy = ax + math.cos(ha) * 14, ay + math.sin(ha) * 14
        self:drawLine2(ax, ay, hx, hy, a, c.accentHi.r, c.accentHi.g, c.accentHi.b)
        self:drawLine2(ax, ay + 1, hx, hy + 1, a * 0.5, c.accentHi.r, c.accentHi.g, c.accentHi.b)
    end
    naviChip(self, ax - ux * 60, ay - uy * 60 - 10, label)
end

-- a stale overlay must never leak into the next session
Events.OnGameStart.Add(function()
    AegisPlayerVehNavi.target = nil
    AegisPlayerVehNavi.instance = nil
    nextPush = {}
end)

-- ==================================================================
-- the stage magnifies by 160 * e^(0.2 * zoom) / 1.82 pixels per metre
-- (bytecode UI3DScene.zoomMult), so a fixed zoom made the car overflow
-- as soon as the preview got smaller. Solve the formula for the stage
-- we actually have: a car is about 6 m long and 3 m tall with the tilt.
-- An extents based variant was tried and REVERTED: the script extents
-- are not the metres this formula needs (an M923 filled
-- the whole frame), and the camera looks at the model origin anyway,
-- which no exposed call can re-target (recalculateBoxCenter works on
-- editor boxes, not the view). Long rigs zoom out by wheel, off origin
-- models move by shift, both survive within one selection
local function fitZoom(w, h, script)
    if not w or not h or w < 20 or h < 20 then return 3 end
    local pxPerMetre = math.min(w / 6.5, h / 3.2)
    local mult = pxPerMetre * 1366 / w
    local z = math.log(math.max(0.01, mult * 1.82 / 160)) / 0.2
    return math.max(1, math.min(12, math.floor(z + 0.5)))
end

-- 3D stage with drag rotation (pattern AegisVehicleScene)
-- ==================================================================
AegisPlayerVehScene = ISUI3DScene:derive("AegisPlayerVehScene")

function AegisPlayerVehScene:onMouseDown(x, y)
    ISUI3DScene.onMouseDown(self, x, y)
    -- shift drags the view, plain drag rotates. The pan HAS to stay: mod
    -- vehicles with a shifted model origin sit off centre from the start
    -- and the pan is the only way to see them at all (a
    -- roofed rig hung outside the frame). Centring is guaranteed anyway,
    -- the page rebuilds the whole stage on every vehicle switch
    self.rotating = not (isKeyDown(Keyboard.KEY_LSHIFT) or isKeyDown(Keyboard.KEY_RSHIFT))
end

function AegisPlayerVehScene:onMouseMove(dx, dy)
    if self.mouseDown and self.rotating then
        local current = self.javaObject:fromLua0("getViewRotation")
        local rx = math.max(-20, math.min(70, current:x() + dy / 4))
        local ry = current:y() + dx / 2
        self.javaObject:fromLua3("setViewRotation", rx, ry, current:z())
        return
    end
    ISUI3DScene.onMouseMove(self, dx, dy)
end

function AegisPlayerVehScene:onMouseUp(x, y)
    ISUI3DScene.onMouseUp(self, x, y)
    self.rotating = false
end

function AegisPlayerVehScene:onMouseUpOutside(x, y)
    ISUI3DScene.onMouseUpOutside(self, x, y)
    self.rotating = false
end

-- once the player turned the wheel the automatic fit steps aside, it
-- would otherwise fight the manual choice on every layout pass
function AegisPlayerVehScene:onMouseWheel(del)
    if self.page then self.page.sceneZoomed = true end
    return ISUI3DScene.onMouseWheel(self, del)
end

-- ==================================================================
-- Page
-- ==================================================================
function AegisPlayerPageVehicles.create(window, x, y, w, h)
    local o = ISPanel:new(x, y, w, h)
    setmetatable(o, AegisPlayerPageVehicles)
    AegisPlayerPageVehicles.__index = AegisPlayerPageVehicles
    o.background = false
    o.window = window
    o.entries = {}
    o.gotList = false
    o.tries = 0
    o.requestedAt = nil
    o.selectedId = nil
    o.statusKey = nil
    o.nearVeh = nil
    o.nearNext = 0
    o.stateNext = 0
    o.sceneScript = nil
    o.parts = nil
    o.partsId = nil
    o.partsState = nil
    o.partsNext = 0
    AegisPlayerPageVehicles.instance = o
    return o
end

-- every position derives from the real panel size; runs once at build
-- and again whenever the window stretches the page live, so the card
-- never draws against sizes from a previous rebuild
function AegisPlayerPageVehicles:applyLayout()
    self.layoutW, self.layoutH = self.width, self.height
    local pad = 20
    self.pad = pad
    local smallH = Aegis.fontH(UIFont.Small)
    local largeH = Aegis.fontH(UIFont.Large)
    local avail = self.width - pad * 2 - 16
    local listW = math.min(LIST_W, math.max(120, avail - 260))
    self.listW = listW
    local rx = pad + listW + 16
    local rw = math.max(80, self.width - rx - pad)
    self.rightX, self.rightW = rx, rw
    self.buttonY = self.height - pad - 34
    self.statusY = self.buttonY - 26
    self.barRowH = smallH + 22
    self.barCols = rw >= 300 and 2 or 1
    local barRows = self.barCols == 2 and 2 or 4
    -- card needs title + distance + seen line + bar block, plus a strip
    -- for the part breakdown underneath
    self.headH = 12 + largeH + 6 + smallH + 4 + smallH + 10
    local cardMin = self.headH + barRows * self.barRowH + PARTS_MIN
    local previewH = PREVIEW_H
    local cardTop = pad + previewH + 12
    local cardH = self.statusY - 8 - cardTop
    if cardH < cardMin then
        previewH = math.max(90, previewH - (cardMin - cardH))
        cardTop = pad + previewH + 12
        cardH = self.statusY - 8 - cardTop
    end
    self.previewH = previewH
    self.infoY = cardTop
    self.infoH = math.max(50, cardH)

    -- part breakdown sits under the bars, headline first, scroller below
    local pTop = self.infoY + self.headH + barRows * self.barRowH + 4
    self.partsTop = pTop
    local pY = pTop + smallH + 10
    local pH = self.infoY + self.infoH - 10 - pY
    self.partsShow = pH >= PARTS_ROWS_MIN and rw >= 200
    if self.partsScroll then
        self.partsScroll:setX(rx + 14)
        self.partsScroll:setY(pY)
        self.partsScroll:setWidth(math.max(40, rw - 28))
        self.partsScroll:setHeight(math.max(40, pH))
        if self.partsRows then
            self.partsRows:setWidth(math.max(20, self.partsScroll.width - 16))
            self:layoutParts()
        end
    end

    if self.scroll then
        self.scroll:setX(pad + 8)
        self.scroll:setY(pad + 40)
        self.scroll:setWidth(math.max(40, listW - 16))
        self.scroll:setHeight(math.max(40, self.height - pad * 2 - 48))
        if self.rows then
            local rowsW = self.scroll.width - 16
            local need = #self.entries * (ROW_H + 8) + 8
            local rowsH = math.max(need, self.scroll.height)
            self.rows:setWidth(rowsW)
            self.rows:setHeight(rowsH)
            self.scroll:setScrollHeight(rowsH)
        end
    end
    if self.scene then
        pcall(function()
            self.scene:setX(rx + 14)
            self.scene:setY(pad + 40)
            self.scene:setWidth(math.max(10, rw - 28))
            self.scene:setHeight(math.max(10, previewH - 54 - STAGE_HINT_H))
            -- the stage changed size, the magnification has to follow or
            -- the car spills out of its frame
            if not self.sceneZoomed then
                self.scene.javaObject:fromLua1("setZoom", fitZoom(self.scene.width, self.scene.height, self.sceneScript))
            end
        end)
    end
    if self.saveBtn then
        local bw = math.max(40, math.floor((rw - 28 - 12) / 2))
        self.saveBtn:setX(rx + 14)
        self.saveBtn:setY(self.buttonY)
        self.saveBtn:setWidth(bw)
        self.forgetBtn:setX(rx + 14 + bw + 12)
        self.forgetBtn:setY(self.buttonY)
        self.forgetBtn:setWidth(bw)
        -- this layout knows nothing of Knox Claim and has just put both
        -- buttons back on their default halves, so the row has to be
        -- decided again from scratch
        self.knoxApplied = nil
        self:applyKnox()
    end
end

-- the stage is DISPOSABLE on purpose: the pan (viewX/viewY) has no
-- exposed reset, so the only way to a guaranteed centre is a fresh
-- build. applyPreview tears the stage down and rebuilds it on every
-- vehicle switch; within one vehicle the pan stays available, mod
-- vehicles with a shifted model origin need it to be seen at all
function AegisPlayerPageVehicles:buildScene()
    -- the OLD stage keeps drawing until the new one is anchored and
    -- revealed from update(); removing it first left a dark frame on
    -- every switch, and the eye caught even that (user: the blend has
    -- to be invisible, full stop)
    if self.oldScene then
        pcall(function() self:removeChild(self.oldScene) end)
        self.oldScene = nil
    end
    self.oldScene = self.scene
    self.scene = nil
    local pad = self.pad
    local rx, rw = self.rightX, self.rightW
    pcall(function()
        local scene = AegisPlayerVehScene:new(rx + 14, pad + 40, math.max(10, rw - 28),
            math.max(10, self.previewH - 54 - STAGE_HINT_H))
        scene:initialise()
        scene:instantiate()
        scene.backgroundColor = { r = AegisPlayerCol.dark.r, g = AegisPlayerCol.dark.g, b = AegisPlayerCol.dark.b, a = 1 }
        scene.borderColor = { r = AegisPlayerCol.line.r, g = AegisPlayerCol.line.g, b = AegisPlayerCol.line.b, a = 1 }
        self:addChild(scene)
        scene.page = self
        self.scene = scene
        local jo = scene.javaObject
        jo:fromLua1("setDrawGrid", false)
        jo:fromLua1("setDrawGridAxes", false)
        jo:fromLua1("setMaxZoom", 20)
        jo:fromLua1("createVehicle", "vehicle")
        jo:fromLua1("setView", "UserDefined")
        jo:fromLua3("setViewRotation", 15, 45, 0)
        jo:fromLua1("setZoom", fitZoom(scene.width, scene.height, self.sceneScript))
        scene:setVisible(false)
    end)
end

function AegisPlayerPageVehicles:createChildren()
    self:applyLayout()
    local pad = self.pad
    self.scroll = AegisScrollArea:new(pad + 8, pad + 40, math.max(40, self.listW - 16), math.max(40, self.height - pad * 2 - 48))
    self:addChild(self.scroll)

    local rx, rw = self.rightX, self.rightW
    self.sceneScript = nil
    self:buildScene()

    -- breakdown scroller; its inner panel stays for good and only gets
    -- resized, a rebuild per measurement would drop the scroll position
    self.partsScroll = AegisScrollArea:new(rx + 14, self.partsTop + Aegis.fontH(UIFont.Small) + 10,
        math.max(40, rw - 28), 40)
    -- height comes from applyLayout, which ran before this element existed
    self:addChild(self.partsScroll)
    local prows = ISPanel:new(0, 0, math.max(20, self.partsScroll.width - 16), 10)
    prows:initialise()
    prows.background = false
    prows.page = self
    prows.prerender = AegisPlayerPageVehicles.drawParts
    self.partsScroll:addChild(prows)
    self.partsRows = prows
    self.partsScroll:setVisible(false)
    self:applyLayout()

    local by = self.buttonY
    local bw = math.max(40, math.floor((rw - 28 - 12) / 2))
    self.saveBtn = AegisButton:new(rx + 14, by, bw, 34, getText("UI_AegisPlayer_VehSave"), "car", self, AegisPlayerPageVehicles.onSave)
    self:addChild(self.saveBtn)
    self.forgetBtn = AegisButton:new(rx + 14 + bw + 12, by, bw, 34, getText("UI_AegisPlayer_VehForget"), "trash", self, AegisPlayerPageVehicles.onForget)
    self.forgetBtn.style = "danger"
    self:addChild(self.forgetBtn)
    self:applyKnox()

    self:rebuildRows()
end

-- Knox Claim owns the vehicles on this server (server flag from ppSync).
-- Then remembering here would build a second, blind list next to its one,
-- so the button goes. Forget stays: entries from before the switch have to
-- be removable, and the list itself keeps working
function AegisPlayerPageVehicles.knoxOwns()
    local s = AegisPlayerClient and AegisPlayerClient.state
    return type(s) == "table" and s.knoxVehicles == true
end

-- runs on every frame, so it has to be cheap: nothing moves unless the
-- flag really changed. applyLayout clears the marker before it calls in,
-- because it has just put both buttons back on their default halves
function AegisPlayerPageVehicles:applyKnox()
    if not self.saveBtn or not self.forgetBtn then return end
    local knox = AegisPlayerPageVehicles.knoxOwns()
    local rx, rw = self.rightX, self.rightW
    if self.knoxApplied == knox then return end
    self.knoxApplied = knox
    local bw = math.max(40, math.floor((rw - 28 - 12) / 2))
    self.saveBtn:setVisible(not knox)
    if knox then
        -- forget takes the whole row, a lone half wide button next to a
        -- gap reads like something failed to load
        self.forgetBtn:setX(rx + 14)
        self.forgetBtn:setWidth(math.max(40, rw - 28))
    else
        self.forgetBtn:setX(rx + 14 + bw + 12)
        self.forgetBtn:setWidth(bw)
    end
end

-- ---------- data ----------
function AegisPlayerPageVehicles:requestList()
    local p = getPlayer()
    if not p then return end
    self.requestedAt = getTimestampMs()
    self.tries = self.tries + 1
    sendClientCommand(p, MODULE, "vehList", {})
end

function AegisPlayerPageVehicles:selected()
    for _, e in ipairs(self.entries) do
        if e.id == self.selectedId then return e end
    end
    return nil
end

function AegisPlayerPageVehicles:setEntries(entries)
    -- a locally measured state beats the ledger numbers riding in the list:
    -- without this every vehList reply rolled fresh bars back for a moment
    for _, old in ipairs(self.entries or {}) do
        if old.fresh == true then
            for _, e in ipairs(entries) do
                if e.id == old.id and e.fresh ~= true then
                    e.cond, e.fuel = old.cond, old.fuel
                    e.batt, e.engine = old.batt, old.engine
                    e.fresh = true
                    break
                end
            end
        end
    end
    -- only ledger rows are stored: a restored page state may carry Knox
    -- rows from before a resize, and compose adds those fresh anyway
    local ledger = {}
    for _, e in ipairs(entries) do
        if not e.knox then table.insert(ledger, e) end
    end
    self.ledger = ledger
    self.gotList = true
    self:composeEntries()
end

-- the visible list: the own ledger plus, where Knox Claim runs, the Knox
-- vehicles of this player straight from that mod's client cache
function AegisPlayerPageVehicles:composeEntries()
    local all = {}
    for _, e in ipairs(self.ledger or {}) do table.insert(all, e) end
    if AegisPlayerPageVehicles.knoxOwns() then
        for _, e in ipairs(knoxEntries()) do table.insert(all, e) end
    end
    self.entries = all
    if not self:selected() then
        self.selectedId = all[1] and all[1].id or nil
    end
    self:rebuildRows()
    self:applyPreview()
end

function AegisPlayerPageVehicles:applyPreview()
    if not self.scene then return end
    local e = self:selected()
    if not e or e.script == "" then
        self.scene:setVisible(false)
        return
    end
    if self.sceneScript == e.script then
        self.scene:setVisible(true)
        return
    end
    -- fresh stage per vehicle: the ONLY reliable way back to a centred
    -- view, the pan of the old stage has no exposed reset
    self.sceneScript = e.script
    self.sceneZoomed = false
    self:buildScene()
    pcall(function()
        self.scene.javaObject:fromLua2("setVehicleScript", "vehicle", e.script)
        self.scene.javaObject:fromLua1("setZoom", fitZoom(self.scene.width, self.scene.height, e.script))
        -- start nudge downwards: the default camera carries the vehicle
        -- too high in the frame. dragView takes raw mouse
        -- deltas (vanilla ISUIVehicleModel feeds it exactly that), and on
        -- a FRESH stage the pan provably sits at zero, so a fixed nudge
        -- is deterministic instead of drifting
        self.scene.javaObject:fromLua2("dragView", 0, math.floor(self.scene.height * 0.12))
    end)
    -- revealed from the NEXT update pass, once the anchor sat; the old
    -- stage keeps drawing until then, so no frame is ever dark
    self.sceneShowAt = getTimestampMs() + 1
end

-- ---------- list rows ----------
-- rows live on an inner panel inside the scroll area (kits pattern), a
-- rebuild replaces one child and leaves the scrollbar alone
function AegisPlayerPageVehicles:rebuildRows()
    if not self.scroll then return end
    if self.rows then self.scroll:removeChild(self.rows) end
    local w = self.scroll.width - 16
    local need = #self.entries * (ROW_H + 8) + 8
    local h = math.max(need, self.scroll.height)
    local panel = ISPanel:new(0, 0, w, h)
    panel:initialise()
    panel.background = false
    panel.page = self
    panel.prerender = AegisPlayerPageVehicles.drawRows
    panel.onMouseUp = AegisPlayerPageVehicles.onRowsMouseUp
    self.scroll:addChild(panel)
    self.scroll:setScrollHeight(h)
    self.rows = panel
end

function AegisPlayerPageVehicles.drawRows(panel)
    local page = panel.page
    local c = AegisPlayerCol
    local w = panel.width
    local y = 8
    local naviId = AegisPlayerVehNavi.target and AegisPlayerVehNavi.target.id or nil
    for _, e in ipairs(page.entries) do
        local active = page.selectedId == e.id
        Aegis.roundFrame(panel, 0, y, w, ROW_H, 8, 1, c.line, active and c.card or c.panel)
        if active then
            Aegis.roundRect(panel, 0, y + 8, 3, ROW_H - 16, 1, 1, c.accent)
        end
        Aegis.text(panel, Aegis.fitText(displayName(e), UIFont.Medium, w - 74), 12, y + 8, UIFont.Medium, c.text)
        Aegis.text(panel, distLine(e), 12, y + ROW_H - 10 - Aegis.fontH(UIFont.Small), UIFont.Small, c.muted)
        local on = naviId == e.id
        Aegis.icon(panel, "pin", w - 36, y + 9, 18, 1, on and c.accentHi or c.muted)
        Aegis.textCentre(panel, getText("UI_AegisPlayer_VehNavi"), w - 27, y + 31, UIFont.Small, on and c.accentHi or c.muted)
        y = y + ROW_H + 8
    end
    if page.gotList and #page.entries == 0 then
        local hint = AegisPlayerPageVehicles.knoxOwns()
            and "UI_AegisPlayer_VehKnoxHint" or "UI_AegisPlayer_VehEmptyHint"
        -- fitted: centred text wider than the column ran out on BOTH
        -- sides and the clip cut its first letters
        Aegis.textCentre(panel, Aegis.fitText(getText("UI_AegisPlayer_VehEmpty"), UIFont.Small, w - 12),
            math.floor(w / 2), 28, UIFont.Small, c.muted)
        Aegis.textCentre(panel, Aegis.fitText(getText(hint), UIFont.Small, w - 12),
            math.floor(w / 2), 28 + Aegis.fontH(UIFont.Small) + 6, UIFont.Small, c.muted)
    end
end

function AegisPlayerPageVehicles.onRowsMouseUp(panel, x, y)
    local page = panel.page
    local idx = math.floor((y - 8) / (ROW_H + 8)) + 1
    local rowY = 8 + (idx - 1) * (ROW_H + 8)
    if y < rowY or y > rowY + ROW_H then return end
    local e = page.entries[idx]
    if not e then return end
    Aegis.sound()
    if x >= panel.width - 52 then
        page:toggleNavi(e)
        return
    end
    page.selectedId = e.id
    page:applyPreview()
end

function AegisPlayerPageVehicles:toggleNavi(e)
    -- no position, no navi: a Knox car that is not loaded nearby has
    -- no coordinates to point at
    if not e.x or not e.y then return end
    local t = AegisPlayerVehNavi.target
    if t and t.id == e.id then
        AegisPlayerVehNavi.stop()
    else
        AegisPlayerVehNavi.start(e)
    end
end

-- ---------- part breakdown ----------
-- flow the groups into columns once per measurement instead of per
-- frame; a group goes into the currently shortest column so a wide card
-- fills evenly
function AegisPlayerPageVehicles:layoutParts()
    self.partsLayout = nil
    local rows, sc = self.partsRows, self.partsScroll
    if not rows or not sc then return end
    local groups = self.parts
    local w = rows.width
    if not groups or w < 60 then
        rows:setHeight(math.max(10, sc.height))
        sc:setScrollHeight(math.max(10, sc.height))
        sc:setYScroll(0)
        return
    end
    local smallH = Aegis.fontH(UIFont.Small)
    local rowH = smallH + 10
    local headH = smallH + 12
    local cols = 1
    if w >= 640 then cols = 3 elseif w >= 400 then cols = 2 end
    local gap = 16
    local colW = math.floor((w - gap * (cols - 1)) / cols)
    local colY = {}
    for i = 1, cols do colY[i] = 4 end
    local items = {}
    for _, g in ipairs(groups) do
        local best = 1
        for i = 2, cols do
            if colY[i] < colY[best] then best = i end
        end
        local x = (best - 1) * (colW + gap)
        local y = colY[best]
        table.insert(items, { head = true, x = x, y = y, w = colW, key = g.key, avg = g.avg })
        y = y + headH
        for _, p in ipairs(g.parts) do
            table.insert(items, { x = x, y = y, w = colW, p = p })
            y = y + rowH
        end
        colY[best] = y + 10
    end
    local h = 4
    for i = 1, cols do
        if colY[i] > h then h = colY[i] end
    end
    self.partsLayout = { items = items, rowH = rowH }
    local total = math.max(h, sc.height)
    rows:setHeight(total)
    sc:setScrollHeight(total)
    local off = sc:getYScroll() or 0
    if -off > total - sc.height then sc:setYScroll(0) end
end

function AegisPlayerPageVehicles.drawParts(panel)
    local page = panel.page
    local lay = page.partsLayout
    if not lay then return end
    local c = AegisPlayerCol
    local smallH = Aegis.fontH(UIFont.Small)
    -- only draw the visible band, the list runs well past the viewport
    local top, bot = nil, nil
    local sc = page.partsScroll
    if sc then
        local off = sc:getYScroll() or 0
        top = -off - 24
        bot = top + sc.height + 48
    end
    for _, it in ipairs(lay.items) do
        if not top or (it.y + lay.rowH >= top and it.y <= bot) then
            if it.head then
                local val = tostring(it.avg) .. "%"
                local valW = Aegis.strW(UIFont.Small, val)
                Aegis.text(panel, Aegis.fitText(getText(it.key), UIFont.Small, math.max(20, it.w - valW - 10)),
                    it.x, it.y, UIFont.Small, c.text)
                Aegis.textRight(panel, val, it.x + it.w, it.y, UIFont.Small, stateColor(it.avg))
                Aegis.hairline(panel, it.x, it.y + smallH + 4, it.w, 0.45)
            else
                local p = it.p
                local val, col
                if p.missing then
                    val, col = getText("UI_AegisPlayer_VehPartMissing"), c.danger
                elseif p.broken then
                    val, col = getText("UI_AegisPlayer_VehPartBroken"), c.danger
                else
                    val, col = tostring(p.cond) .. "%", stateColor(p.cond)
                end
                local valW = Aegis.strW(UIFont.Small, val)
                local nameW = it.w - valW - 10
                if p.mark then
                    local mk = getText(p.mark)
                    local mkW = Aegis.strW(UIFont.Small, mk) + 10
                    if nameW - mkW >= 44 then
                        Aegis.textRight(panel, mk, it.x + it.w - valW - 8, it.y, UIFont.Small, c.muted)
                        nameW = nameW - mkW
                    end
                end
                Aegis.text(panel, Aegis.fitText(p.name, UIFont.Small, math.max(20, nameW)),
                    it.x, it.y, UIFont.Small, c.muted)
                Aegis.textRight(panel, val, it.x + it.w, it.y, UIFont.Small, col)
                local ty = it.y + smallH + 2
                Aegis.roundRect(panel, it.x, ty, it.w, 3, 1, 0.5, c.dark)
                if p.cond > 0 then
                    Aegis.roundRect(panel, it.x, ty, math.max(3, math.floor(it.w * p.cond / 100)), 3, 1, 1, col)
                end
            end
        end
    end
end

-- ---------- actions ----------
function AegisPlayerPageVehicles.onSave(self)
    -- the button is gone where Knox Claim owns the vehicles, but a hotkey
    -- or a stale layout must not slip past it
    if AegisPlayerPageVehicles.knoxOwns() then return end
    local veh = self.nearVeh
    if not veh then return end
    local id = veh:getId()
    if not id then return end
    self.statusKey = nil
    -- the car is right here, so its state travels with the entry and the
    -- first list already shows real numbers
    local st = readState(veh)
    nextPush[id] = getTimestampMs() + STATE_MS
    sendClientCommand(getPlayer(), MODULE, "vehSave", {
        id = id, cond = st.cond, fuel = st.fuel,
        batt = st.batt, engine = st.engine,
    })
end

-- one button, called release everywhere: a ledger row is
-- removed from the ledger, a Knox row is truly released through the
-- Knox Claim registry, the confirm text covers both
function AegisPlayerPageVehicles.onForget(self)
    local e = self:selected()
    if not e then return end
    self.statusKey = nil
    AegisConfirm.show(getText("UI_AegisPlayer_VehForget"),
        getText("UI_AegisPlayer_VehForgetConfirm"),
        getText("UI_AegisPlayer_VehForget"), self, function()
            if e.knox then
                pcall(function()
                    KnoxClaim.Client.send("vehrelease", { id = e.knoxKey })
                end)
            else
                sendClientCommand(getPlayer(), MODULE, "vehForget", { id = e.id })
            end
        end)
end

-- a resize rebuilds the page from scratch; without carrying the list
-- over, the preview stays empty until the next server reply, and the
-- throttled vehList can push that out by several seconds
function AegisPlayerPageVehicles:saveState()
    return { entries = self.entries, selectedId = self.selectedId, gotList = self.gotList }
end

function AegisPlayerPageVehicles:restoreState(state)
    if type(state) ~= "table" or type(state.entries) ~= "table" then return end
    if #state.entries == 0 then return end
    self.selectedId = state.selectedId
    self:setEntries(state.entries)
    self.gotList = state.gotList == true
end

-- ---------- frame ----------
function AegisPlayerPageVehicles:onShow()
    self.tries = 0
    self:requestList()
    self.nearNext = 0
    self.stateNext = 0
    self.partsNext = 0
end

function AegisPlayerPageVehicles:update()
    ISPanel.update(self)
    if not self:isVisible() then return end
    local now = getTimestampMs()
    -- lost request self healing, same rhythm as the other panel pages
    if not self.gotList and self.requestedAt and self.tries < TRY_MAX
        and now - self.requestedAt >= RETRY_MS then
        self:requestList()
    end
    -- deferred reveal of a rebuilt stage, see applyPreview: show the new
    -- one, THEN retire the old one, the order is the whole trick
    if self.sceneShowAt and now >= self.sceneShowAt then
        self.sceneShowAt = nil
        if self.scene and self.sceneScript then self.scene:setVisible(true) end
        if self.oldScene then
            pcall(function() self:removeChild(self.oldScene) end)
            self.oldScene = nil
        end
    end
    -- Knox rows follow that mod's client cache, which never pushes into
    -- this page: recompose when its stand counter moves, plus a slow
    -- timer so positions of nearby cars stay current
    if AegisPlayerPageVehicles.knoxOwns() then
        local rev = (KnoxClaim and KnoxClaim.Client and KnoxClaim.Client.rev) or 0
        if rev ~= self.knoxRev or now >= (self.knoxNext or 0) then
            self.knoxRev = rev
            self.knoxNext = now + 5000
            self:composeEntries()
        end
    end
    -- an open page keeps measuring what is in reach, the per vehicle gate
    -- inside pushStates decides what actually goes out
    if now >= (self.stateNext or 0) then
        self.stateNext = now + 2000
        pushStates(self.entries)
    end
    -- vehicles in reach get their four bars refreshed locally once a second:
    -- refuelling or repairing next to the car has to show up right away.
    -- The 30s STATE_MS throttle stays untouched, it only paces the network
    -- push; before this, every vehList reply also rolled the bars back to
    -- the stale ledger numbers until that throttle expired
    if now >= (self.liveNext or 0) then
        self.liveNext = now + 1000
        for _, e in ipairs(self.entries or {}) do
            local car = carFor(e)
            if car then
                local st = readState(car)
                e.cond, e.fuel = st.cond, st.fuel
                e.batt, e.engine = st.batt, st.engine
                e.fresh = true
                -- the live position beats the stored one; without this a
                -- healed entry kept pointing at the old parking spot
                e.x, e.y = car:getX(), car:getY()
            end
        end
    end
    -- part breakdown of the selected vehicle: a fresh sweep right after a
    -- selection change, otherwise once a second, never per frame
    local sel = self:selected()
    local selId = sel and sel.id or nil
    if selId ~= self.partsId then
        self.partsId = selId
        self.parts, self.partsState = nil, nil
        self.partsNext = 0
        self:layoutParts()
    end
    -- no sweep while the card is too short to show the list at all
    if self.partsShow and now >= (self.partsNext or 0) then
        self.partsNext = now + PARTS_MS
        local car = sel and carFor(sel) or nil
        self.parts = car and measureParts(car) or nil
        self.partsState = self.parts and "ok" or "far"
        if not selId then self.partsState = nil end
        -- "too far away" is the collecting answer for three different
        -- causes; one line per change says which one it was instead of
        -- leaving the next report to guesswork
        local why = self.parts and "ok" or (car and "vehicle found, no parts" or "no vehicle in reach")
        if why ~= self.partsWhy and getTimestampMs() >= (self.partsWhyAt or 0) then
            self.partsWhy = why
        self.partsWhyAt = getTimestampMs() + 30000
            print("[Aegis] vehicle parts (" .. tostring(selId) .. "): " .. why)
        end
        self:layoutParts()
    end
    -- vehicle at hand, sampled at half speed for the save button
    if now >= (self.nearNext or 0) then
        self.nearNext = now + 500
        local veh = nil
        local p = getPlayer()
        if p then
            veh = p:getVehicle()
            if not veh then veh = p:getNearVehicle() end
        end
        self.nearVeh = veh
    end
    if self.saveBtn then
        -- a cap of zero turns remembering off entirely, the server answers
        -- every save with "limit". An enabled button that can only fail
        -- reads as a broken panel, so it stays grey
        self.saveBtn:setEnabled(self.nearVeh ~= nil and maxVehicles() > 0)
        -- the release button serves both lists now, see onForget
        self.forgetBtn:setEnabled(self:selected() ~= nil)
    end
end

-- one slim state bar: label left, percent right, track underneath. The
-- fill tips to red under 30, amber under 60, accent blue above
function AegisPlayerPageVehicles:drawStateBar(x, y, w, labelKey, v)
    local c = AegisPlayerCol
    if v then
        if v < 0 then v = 0 elseif v > 100 then v = 100 end
        v = math.floor(v + 0.5)
    end
    Aegis.text(self, getText(labelKey), x, y, UIFont.Small, c.muted)
    Aegis.textRight(self, v and (tostring(v) .. "%") or "--", x + w, y,
        UIFont.Small, v and stateColor(v) or c.muted)
    local ty = y + Aegis.fontH(UIFont.Small) + 4
    Aegis.roundRect(self, x, ty, w, 8, 4, 1, c.dark)
    if v and v > 0 then
        Aegis.roundRect(self, x, ty, math.max(6, math.floor(w * v / 100)), 8, 4, 1, stateColor(v))
    end
end

function AegisPlayerPageVehicles:prerender()
    -- the window stretches the page live while the grip drags
    if self.layoutW ~= self.width or self.layoutH ~= self.height then
        self:applyLayout()
    end
    -- the server flag can land after this page was built, so the row is
    -- checked here instead of only once; applyKnox is a no-op unless the
    -- state actually changed
    self:applyKnox()
    local c = AegisPlayerCol
    local pad = self.pad
    local listW = self.listW
    local smallH = Aegis.fontH(UIFont.Small)

    -- left: the list
    Aegis.roundFrame(self, pad, pad, listW, self.height - pad * 2, 10, 1, c.line, c.panel)
    Aegis.icon(self, "car", pad + 14, pad + 12, 15, 1, c.accent)
    -- in Knox mode the cap is that mod's sandbox limit, not our ledger's
    local cap = maxVehicles()
    if AegisPlayerPageVehicles.knoxOwns() then
        pcall(function() cap = KnoxClaim.limits().vehicles or cap end)
    end
    local count = tostring(#self.entries) .. " / " .. tostring(cap)
    local countW = Aegis.strW(UIFont.Small, count)
    Aegis.text(self, Aegis.fitText(getText("UI_AegisPlayer_NavVehicles"), UIFont.Medium, listW - 58 - countW),
        pad + 36, pad + 10, UIFont.Medium, c.text)
    Aegis.textRight(self, count, pad + listW - 14, pad + 12, UIFont.Small, c.muted)

    -- right: preview stage plus details
    local rx, rw = self.rightX, self.rightW
    Aegis.roundFrame(self, rx, pad, rw, self.previewH, 10, 1, c.line, c.panel)
    local e = self:selected()
    if not e then
        Aegis.textCentre(self, getText("UI_AegisPlayer_VehSelectHint"),
            rx + math.floor(rw / 2), pad + math.floor(self.previewH / 2) - 8, UIFont.Small, c.muted)
    else
        -- nothing told the player the stage can be turned at all
        local hint = getText("UI_AegisPlayer_VehStageHint")
        local hy = pad + self.previewH - 14 - math.floor((STAGE_HINT_H + Aegis.fontH(UIFont.Small)) / 2) + 2
        Aegis.textCentre(self, Aegis.fitText(hint, UIFont.Small, rw - 24),
            rx + math.floor(rw / 2), hy, UIFont.Small, c.muted)
    end

    -- detail card: header lines flow from the top, each with its own
    -- slot, the bars follow underneath; a bar row without room is
    -- dropped instead of drawn into the text
    local iy, ih = self.infoY, self.infoH
    Aegis.roundFrame(self, rx, iy, rw, ih, 10, 1, c.line, c.panel)
    if e then
        local bottom = iy + ih - 8
        local ty = iy + 12
        Aegis.text(self, Aegis.fitText(displayName(e), UIFont.Large, rw - 32), rx + 16, ty, UIFont.Large, c.accentHi)
        ty = ty + Aegis.fontH(UIFont.Large) + 6
        local dl = distLine(e)
        Aegis.text(self, dl, rx + 16, ty, UIFont.Small, c.text)
        if e.fresh ~= true and (e.cond or e.fuel or e.batt or e.engine) then
            local stale = getText("UI_AegisPlayer_VehStale")
            if Aegis.strW(UIFont.Small, dl) + Aegis.strW(UIFont.Small, stale) + 40 <= rw - 32 then
                Aegis.textRight(self, stale, rx + rw - 16, ty, UIFont.Small, c.muted)
            end
        end
        ty = ty + smallH + 4
        local seen = ""
        if e.epoch and e.epoch > 0 then
            seen = AegisShared.timestampReadable(e.epoch)
        end
        if seen ~= "" and ty + smallH <= bottom then
            Aegis.text(self, Aegis.fitText(getText("UI_AegisPlayer_VehSeen", seen), UIFont.Small, rw - 32),
                rx + 16, ty, UIFont.Small, c.muted)
        end
        ty = ty + smallH + 10
        local rowH = self.barRowH
        local cols = self.barCols
        local colW = cols == 2 and math.floor((rw - 32 - 16) / 2) or rw - 32
        local bars = {
            { key = "UI_AegisPlayer_VehCond", v = e.cond },
            { key = "UI_AegisPlayer_VehFuel", v = e.fuel },
            { key = "UI_AegisPlayer_VehBattery", v = e.batt },
            { key = "UI_AegisPlayer_VehEngine", v = e.engine },
        }
        for i, b in ipairs(bars) do
            local bx = rx + 16 + ((i - 1) % cols) * (colW + 16)
            local by = ty + math.floor((i - 1) / cols) * rowH
            if by + smallH + 12 <= bottom then
                self:drawStateBar(bx, by, colW, b.key, b.v)
            end
        end
        -- breakdown headline; the list itself is the scroller underneath
        local pTop = self.partsTop or bottom
        if self.partsShow and pTop + smallH <= bottom then
            Aegis.text(self, getText("UI_AegisPlayer_VehParts"), rx + 16, pTop, UIFont.Small, c.accentHi)
            Aegis.hairline(self, rx + 16, pTop + smallH + 4, rw - 32, 0.5)
            if self.partsState ~= "ok" then
                Aegis.text(self, Aegis.fitText(getText("UI_AegisPlayer_VehPartsFar"), UIFont.Small, rw - 32),
                    rx + 16, pTop + smallH + 12, UIFont.Small, c.muted)
            end
        end
    end
    if self.partsScroll then
        self.partsScroll:setVisible(e ~= nil and self.partsShow == true
            and self.partsState == "ok" and self.partsLayout ~= nil)
    end
    if self.statusKey then
        Aegis.text(self, Aegis.fitText(getText(self.statusKey), UIFont.Small, rw - 28),
            rx + 14, self.statusY, UIFont.Small, c.danger)
    end
end

-- ---------- server replies ----------
local REASON_KEYS = {
    far = "UI_AegisPlayer_VehErrFar",
    key = "UI_AegisPlayer_VehErrKey",
    limit = "UI_AegisPlayer_VehErrLimit",
}

-- the net layer does not guarantee array keys, rebuild the order
local function normalizeEntries(raw)
    local tmp = {}
    if type(raw) == "table" then
        for k, e in pairs(raw) do
            local idx = tonumber(k)
            local id = type(e) == "table" and tonumber(e.id) or nil
            if idx and id then
                table.insert(tmp, {
                    idx = idx,
                    id = math.floor(id),
                    script = tostring(e.script or ""),
                    name = tostring(e.name or ""),
                    x = tonumber(e.x) or 0,
                    y = tonumber(e.y) or 0,
                    epoch = tonumber(e.epoch) or 0,
                    cond = tonumber(e.cond),
                    fuel = tonumber(e.fuel),
                    batt = tonumber(e.batt),
                    engine = tonumber(e.engine),
                    fresh = e.fresh == true,
                })
            end
        end
    end
    table.sort(tmp, function(a, b) return a.idx < b.idx end)
    for _, e in ipairs(tmp) do e.idx = nil end
    return tmp
end

Events.OnServerCommand.Add(function(module, command, args)
    if module ~= MODULE then return end
    if command == "vehList" then
        local entries = normalizeEntries(args and args.entries)
        local page = AegisPlayerPageVehicles.instance
        -- measure before the page takes the list: whatever is in reach
        -- overwrites the stored snapshot right in place
        local live = AegisPlayerVehNavi.target ~= nil
        if not live and page then
            live = page:isVisible() == true
        end
        if live then pushStates(entries) end
        -- the navi keeps listening even with the window closed
        AegisPlayerVehNavi.sync(entries)
        if page then page:setEntries(entries) end
    elseif command == "vehSave" then
        local page = AegisPlayerPageVehicles.instance
        if not page or type(args) ~= "table" then return end
        if args.ok == true then
            page.statusKey = nil
            AegisPlayerWindow.toast(getText("UI_AegisPlayer_VehSaved"))
        else
            page.statusKey = REASON_KEYS[args.reason] or "UI_AegisPlayer_VehErrFailed"
        end
    elseif command == "vehForget" then
        if type(args) ~= "table" or args.ok ~= true then return end
        local t = AegisPlayerVehNavi.target
        if t and t.id == tonumber(args.id) then
            AegisPlayerVehNavi.stop()
        end
        AegisPlayerWindow.toast(getText("UI_AegisPlayer_VehForgotten"))
    end
end)

AegisPlayerWindow.registerPage({
    id = "vehicles",
    icon = "car",
    label = "UI_AegisPlayer_NavVehicles",
    create = AegisPlayerPageVehicles.create,
})
