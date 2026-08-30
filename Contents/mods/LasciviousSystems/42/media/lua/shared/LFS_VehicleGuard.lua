-- Lascivious Factions System - vehicle protection/lock registry (shared data model).
--
-- Two independent per-faction registries, both keyed by vehicle:getId() (the
-- same identifier vanilla itself uses to address one specific vehicle across
-- the client-server boundary -- see ISVehicleMechanics.lua's sendClientCommand
-- calls and server/Vehicles/VehicleCommands.lua's getVehicleById):
--
-- - vehicles.protected[id] = { requestedAt, protectedAt, name }
--   PROTEGER. requestedAt (getGameTime():getWorldAgeHours()) is set the
--   moment a member clicks the button; protectedAt stays nil until
--   FF.VEHICLE_PROTECT_CONFIRM_HOURS of game time have passed AND the vehicle
--   is re-confirmed still inside this exact faction's territory with no
--   non-member aboard (see LFS_Server.lua's workshopProtectionConfirmTick) --
--   the delay exists specifically so a faction cannot "protect" a stranger's
--   car that merely happened to be driving through when the button was
--   clicked. Only a CONFIRMED entry (protectedAt ~= nil) makes a vehicle
--   eligible for the Oficina upgrade's auto-repair.
--
-- - vehicles.locked[id] = true
--   TRANCAR. Immediate, no delay -- blocks entry and towing by non-members
--   (see LFS_Server.lua's workshopVehicleGuardTick). Independent of
--   protection: a vehicle can be locked, protected, both, or neither.

require "LFS_Shared"
require "LFS_Claims"
require "LFS_Upgrades"

local FF = LasciviousFactionsSystem
local Claims = FF.Claims

-- Oficina level at which TRANCAR stops needing the vehicle to be inside the
-- locking faction's territory -- explicit user request: "apenas no nível 10
-- do aprimoramento de Oficina, ele também tranca o veículo fora do
-- território... antes disso apenas dentro," later clarified to apply to BOTH
-- (a) whether an already-locked vehicle's protection persists once it leaves
-- (this file, FF.vehicleLockBlocksCharacter below) and (b) whether TRANCAR
-- can even be switched ON while the vehicle is currently outside the
-- territory (LFS_Server.lua's Handlers.toggleLockVehicle) -- DESTRANCAR has
-- no such requirement either way, confirmed explicitly ("Destrancar pode ser
-- feito se o veículo está fora do território, sem problemas"). Public (not
-- local) so both files share the exact same threshold instead of two numbers
-- that could drift. Matches the SAME level already used for the Oficina's
-- other top-tier-only effect (the fuel trickle,
-- WORKSHOP_FUEL_PERCENT_PER_DAY_AT_MAX in LFS_Server.lua) -- consistent
-- "level 10 = the capstone effect" precedent, not a new number invented for
-- this feature alone.
FF.LOCK_ANYWHERE_WORKSHOP_LEVEL = 10

-- Game hours a protection request sits pending before being confirmed (or
-- silently dropped if the re-check below fails). See the header comment.
FF.VEHICLE_PROTECT_CONFIRM_HOURS = 1

-- Faction-power threshold per extra protection slot. limit = 1 + floor(power
-- / 500): power 0-499 = 1 slot (the default, even at zero power), 500-999 = 2,
-- 1000-1499 = 3, and so on indefinitely -- same "keep extending forever"
-- spirit as FF.upgradeMilestoneAt rather than a hard cap. Losing power later
-- never strips an already-CONFIRMED protection (see requestProtectVehicle's
-- own comment in LFS_Server.lua) -- this limit only ever gates NEW requests.
local PROTECT_POWER_PER_SLOT = 500

function FF.vehicleProtectionLimit(faction, opts)
    local power = FF.factionScore(faction, opts)
    return 1 + math.floor(power / PROTECT_POWER_PER_SLOT)
end

-- Migration entry point, same idiom as FF.ensureUpgrades/FF.ensureTribute --
-- idempotent, safe to call on every access.
function FF.ensureVehicleGuard(faction)
    if faction and type(faction.vehicles) ~= "table" then
        faction.vehicles = { protected = {}, locked = {} }
    end
    if faction then
        if type(faction.vehicles.protected) ~= "table" then faction.vehicles.protected = {} end
        if type(faction.vehicles.locked) ~= "table" then faction.vehicles.locked = {} end
    end
    return faction
end

-- Confirmed-OR-pending count, for the limit check: a faction cannot queue
-- more protection requests than its current limit even while some are still
-- awaiting confirmation (see LFS_Server.lua's Handlers.requestProtectVehicle).
function FF.vehicleProtectionCount(faction)
    FF.ensureVehicleGuard(faction)
    local n = 0
    for _ in pairs(faction.vehicles.protected) do n = n + 1 end
    return n
end

-- ---------------------------------------------------------------------------
-- Preventative action lock (shared -- used by LFS_VehicleActionGuard.lua's
-- isValid() overrides on ISTakeGasolineFromVehicle/ISUninstallVehiclePart/
-- ISInstallVehiclePart, and by client/LFS_VehicleEnterGuard.lua's override
-- on ISEnterVehicle).
--
-- True if `character` should be blocked from acting on `vehicle` right now:
-- the vehicle is TRANCAR-locked by some faction character isn't a member of,
-- AND the vehicle is CURRENTLY standing inside that same faction's
-- territory. Explicit user requirement -- the block must not follow the
-- vehicle once it leaves the territory ("só pode impedir caso ele esteja
-- dentro do território, não fora"), unlike workshopVehicleGuardTick's
-- occupant-eject/tow-detach check (LFS_Server.lua), which stays
-- territory-agnostic on purpose (it only ever acts on someone already
-- inside/towing the vehicle, a narrower and already-rarer situation).
--
-- Deliberately shared, not server-only: the three TimedActions above are
-- themselves vanilla shared/ classes with their own serverStart()/
-- serverStop() lifecycle, so a shared override here runs both as the acting
-- client's own immediate block AND as the actual server-side gate for that
-- same networked action -- not merely a client-side UI convenience like the
-- TRANCAR button's disabled state.
function FF.vehicleLockBlocksCharacter(vehicle, character)
    if not vehicle or not character then return false end
    local idOk, id = pcall(function() return vehicle:getId() end)
    if not (idOk and id) then return false end
    local nameOk, username = pcall(function() return character:getUsername() end)
    if not (nameOk and username) then return false end
    local posOk, vx, vy = pcall(function() return math.floor(vehicle:getX()), math.floor(vehicle:getY()) end)
    if not posOk then return false end

    local myFaction = FF.getFactionOfPlayer(username)

    -- Debug self-test: FF.debugLockSelfTestActive is a client-only flag,
    -- only ever set locally by LFS_Panel.lua's own toggle handler for the
    -- player running that client -- a no-op everywhere else (server, other
    -- clients), same purpose as LFS_Server.lua's debugIgnoreOwnLock but for
    -- this preventative check specifically, so a solo tester can confirm the
    -- block fires against their own faction's own locked vehicle.
    local treatAsOutsiderOfOwnFaction = FF.debugLockSelfTestActive and myFaction

    for factionName, faction in pairs(FF.getData().factions) do
        local isRelevant = (factionName ~= myFaction) or (factionName == treatAsOutsiderOfOwnFaction)
        if isRelevant then
            FF.ensureVehicleGuard(faction)
            if faction.vehicles.locked[id] then
                local inTerritory = Claims.factionAt(vx, vy) == factionName
                -- Level 10 Oficina: protection follows the vehicle anywhere,
                -- not just inside the claim -- same "upgrade effects pause
                -- without an active claim" rule every other Oficina effect
                -- already follows (FF.upgradesActive), so losing the claim
                -- doesn't leave a level-10 faction protected purely on paper.
                local anywhere = FF.upgradesActive(faction)
                    and FF.upgradeLevel(faction, "workshop") >= FF.LOCK_ANYWHERE_WORKSHOP_LEVEL
                if inTerritory or anywhere then
                    return true
                end
            end
        end
    end
    return false
end

-- Shared halo-note feedback for FF.vehicleLockBlocksCharacter, used by both
-- LFS_VehicleActionGuard.lua (gas/parts) and client/LFS_VehicleEnterGuard.lua
-- (entry) -- one place so both kinds of block read identically to the
-- player. Correction: entry originally showed no message at all (only the
-- gas/parts guard had this) -- confusing on its own ("proteção funciona mas
-- não avisa"), and duplicating the throttle table per-file would have meant
-- two independent 3s windows instead of one. Real-seconds throttle, client-
-- side only (a dedicated server has no player to show a note to), keyed by
-- vehicle id so a still-queued blocked action doesn't spam every frame
-- isValid()/isValidStart() gets re-polled.
local WARN_THROTTLE_SECONDS = 3
local lastWarnedAt = {}

function FF.warnVehicleLockBlocked(vehicle, character)
    if isServer() or not character then return end
    local ok, id = pcall(function() return vehicle:getId() end)
    if not ok or not id then return end
    local now = getTimestamp()
    if lastWarnedAt[id] and (now - lastWarnedAt[id]) < WARN_THROTTLE_SECONDS then return end
    lastWarnedAt[id] = now
    pcall(function()
        character:setHaloNote(
            FF.text("UI_LFS_VehicleMsgActionBlocked", "Veículo trancado por outra facção"),
            255, 60, 60, 200)
    end)
end
