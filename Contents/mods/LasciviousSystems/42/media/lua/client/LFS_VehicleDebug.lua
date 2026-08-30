-- Lascivious Factions System - vehicle auto-maintenance debug view (client side).
--
-- Read-only: the actual maintenance (LFS_Server.lua's workshopMaintTick) is
-- server-authoritative and nothing here ever mutates a vehicle. It only reads
-- the same live, already-networked vehicle fields the vanilla mechanics UI
-- itself reads directly client-side with no special sync of its own (part
-- condition, gas tank content/capacity -- see ISVehicleMechanics.lua), the
-- same assumption the earlier (now removed) generator debug card made.
--
-- Mirrors LFS_Territory.lua's wellbeing snapshot tooling: a live "current
-- state" read (no button needed, see FF.nearestVehicle/FF.workshopLevelAt)
-- plus an opt-in accumulation capture that sums real observed change over a
-- full game hour, for the same reason -- a single poll of a slow gradual rate
-- can round away to nothing and read as "not working" even when the server
-- tick is doing its job.

require "LFS_Shared"
require "LFS_Claims"
require "LFS_Upgrades"
require "LFS_Localization"

local FF = LasciviousFactionsSystem
local Claims = FF.Claims

-- The vehicle nearest the player within `maxDist` tiles, or nil. Scans grid
-- squares (same idiom as the removed generator debug card's GEN_SCAN_RADIUS
-- search) and reads IsoGridSquare:getVehicleContainer() per square --
-- NOT getCell():getVehicles(), which turned out to be a real bug: that
-- getter returns a genuine java.util.HashSet (confirmed via decompiled
-- bytecode: `new HashSet()`), and HashSet has no get(int) -- only
-- ArrayList-returning collections support a :size()/:get(i-1) walk. This
-- crashed on every call in practice (visible in console.txt: "Object tried
-- to call nil in nearestVehicle"). getVehicleContainer() has no such issue --
-- it returns a single vehicle or nil per square, exactly like the generator
-- card's sq:getGenerator().
function FF.nearestVehicle(maxDist)
    maxDist = tonumber(maxDist)
    if not maxDist or maxDist ~= maxDist or maxDist == math.huge or maxDist == -math.huge then
        return nil
    end
    -- This is a square-grid debug scan; cap accidental/external calls before they
    -- turn into tens of thousands of getGridSquare lookups in one UI rebuild.
    maxDist = math.max(0, math.min(128, math.floor(maxDist)))
    local player = getPlayer()
    if not player then return nil end
    local cell = getCell()
    if not cell then return nil end
    local px, py, pz = math.floor(player:getX()), math.floor(player:getY()), math.floor(player:getZ())
    local maxDistSq = maxDist * maxDist
    local nearest, nearestDistSq
    for dx = -maxDist, maxDist do
        for dy = -maxDist, maxDist do
            local distSq = dx * dx + dy * dy
            if distSq <= maxDistSq and (not nearestDistSq or distSq < nearestDistSq) then
                local sq = cell:getGridSquare(px + dx, py + dy, pz)
                local v = sq and sq:getVehicleContainer()
                if v then nearest, nearestDistSq = v, distSq end
            end
        end
    end
    return nearest, nearestDistSq
end

-- The faction name and workshop upgrade level at (x, y) -- the exact same
-- read (Claims.factionAt + FF.upgradeLevel) LFS_Server.lua's workshopMaintTick
-- uses server-side, so this debug view's "elegível" line can never disagree
-- with what actually governs the real tick.
function FF.workshopLevelAt(x, y)
    local factionName = Claims.factionAt(math.floor(x), math.floor(y))
    local faction = factionName and FF.getData().factions[factionName]
    return factionName, (faction and FF.upgradeLevel(faction, "workshop")) or 0
end

-- One flat reading of everything the debug view cares about for `vehicle`:
-- condition per currently-installed part (keyed by part index, matching the
-- server tick's own repair-carry keying), gas tank content/capacity if a
-- GasTank part exists, and battery charge (0.0..1.0, separate from the
-- battery part's own condition, which is already included in `parts`) if a
-- battery is installed. Shared by the live display and the accumulation
-- capture so both read exactly the same fields the same way.
local function readVehicle(vehicle)
    local parts = {}
    for i = 0, vehicle:getPartCount() - 1 do
        local part = vehicle:getPartByIndex(i)
        if part and not part:isInventoryItemUninstalled() then
            parts[#parts + 1] = { index = part:getIndex(), id = part:getId(), condition = part:getCondition() }
        end
    end
    local fuel, fuelCapacity
    local tank = vehicle:getPartById("GasTank")
    if tank then
        fuel = tank:getContainerContentAmount()
        fuelCapacity = tank:getContainerCapacity()
    end
    local batteryCharge
    local battery = vehicle:getBattery()
    if battery and not battery:isInventoryItemUninstalled() then
        local item = battery:getInventoryItem()
        batteryCharge = item and item:getCurrentUsesFloat() or nil
    end
    return { parts = parts, fuel = fuel, fuelCapacity = fuelCapacity, batteryCharge = batteryCharge }
end
FF.readVehicleMaintState = readVehicle

-- ---------------------------------------------------------------------------
-- Debug capture state, for LFS_Panel.lua's Debug > Veículos sub-tab. Only ever
-- populated while DebugToolsEnabled is on -- zero cost on a normal live
-- server. Structure while present:
--   { active, vehicle, vehicleId, ticksTotal, ticksRemaining, startedAt,
--     finishedAt, lostVehicle, baseline = readVehicle() at start, last = most
--     recent readVehicle() }
-- `vehicle` holds the live object reference directly (set once by
-- LFS_Panel.lua's onDebugCaptureVehicle) -- NOT re-found every tick by
-- searching getCell():getVehicles(), which turned out to be a real bug (that
-- getter is a genuine java.util.HashSet with no get(int), see
-- FF.nearestVehicle's own comment above). Holding the reference directly is
-- the same thing vanilla's own vehicle UIs do (ISVehicleMechanics/
-- ISVehicleBloodUI keep `self.vehicle` across frames); staleness is checked
-- via getMovingObjectIndex() < 0, the exact same vanilla-proven check
-- ISVehicleBloodUI.lua uses to detect its cached vehicle left the world.
-- `active` flips to false once ticksRemaining hits 0 OR the tracked vehicle
-- goes stale (drove off far enough to unload, got destroyed) -- the latter
-- sets `lostVehicle = true` so the Debug tab can say why it stopped early
-- instead of just going quiet. Started with a fresh table every time
-- (LFS_Panel.lua's onDebugCaptureVehicle), not toggled/reset, so re-clicking
-- mid-capture restarts cleanly with no leftover totals.
-- ---------------------------------------------------------------------------
FF.vehicleMaintAccumulation = nil

local function vehicleMaintSnapshotTick()
    local accum = FF.vehicleMaintAccumulation
    if not (accum and accum.active) then return end

    accum.ticksRemaining = accum.ticksRemaining - 1

    local ok, alive = pcall(function() return accum.vehicle:getMovingObjectIndex() >= 0 end)
    local found = (ok and alive) and accum.vehicle or nil

    if not found then
        accum.active = false
        accum.lostVehicle = true
        accum.finishedAt = getTimestamp()
        return
    end

    accum.last = readVehicle(found)
    if accum.ticksRemaining <= 0 then
        accum.active = false
        accum.finishedAt = getTimestamp()
    end
end

-- Same game-time clock as territoryEffectTick (LFS_Territory.lua) -- see that
-- file's own comment on why Events.EveryOneMinute over a real-time throttle.
if FF._vehicleMaintSnapshotHook then
    Events.EveryOneMinute.Remove(FF._vehicleMaintSnapshotHook)
end
FF._vehicleMaintSnapshotHook = vehicleMaintSnapshotTick
Events.EveryOneMinute.Add(vehicleMaintSnapshotTick)
