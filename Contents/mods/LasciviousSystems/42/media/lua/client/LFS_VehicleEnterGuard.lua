-- Lascivious Factions System - preventative TRANCAR enforcement on vehicle
-- entry (client side).
--
-- ISEnterVehicle is a client-only vanilla TimedAction (client/Vehicles/
-- TimedActions/ISEnterVehicle.lua) with no server-side counterpart to patch
-- the way LFS_VehicleActionGuard.lua does for the shared fuel/parts
-- actions -- so this override is honest-client UX only: it stops a legit
-- client from ever starting to climb into a locked vehicle it shouldn't be
-- in. The REAL security boundary against a modified client remains
-- LFS_Server.lua's workshopVehicleGuardTick, which still ejects (and always
-- has) any non-member it finds already seated, every GUARD_TICK_INTERVAL.
-- This is a complementary, not a replacement, layer -- explicit user request
-- ("bloquear a ação em si, tipo a ação de entrar") plus it directly closes
-- the entry-to-eject window an earlier round of testing flagged as long
-- enough to start the engine.
--
-- Patches both isValid() AND isValidStart() -- same reasoning as
-- LFS_VehicleActionGuard.lua's own correction: ISTimedActionQueue.lua only
-- consults isValidStart() at the moment the action is dequeued/started,
-- isValid() separately while it's already running. ISEnterVehicle has no
-- instant-completion branch the way the mechanics actions do, so isValid()
-- alone already worked here in the first live test -- isValidStart() is
-- added anyway for the same "block before it even starts" guarantee and to
-- stay structurally consistent with the other three guarded actions rather
-- than relying on a timing detail specific to this one class.
-- Also now shares FF.warnVehicleLockBlocked's halo note (LFS_VehicleGuard.lua)
-- -- round-7 live testing showed entry was silently blocked with NO message
-- at all (only the gas/parts guard had one), which read as broken/inconsistent.

require "LFS_Shared"
require "LFS_VehicleGuard"
require "Vehicles/TimedActions/ISEnterVehicle"

local FF = LasciviousFactionsSystem
if FF._vehicleEnterGuardInstalled then return end

local function blocked(self)
    if self.vehicle and FF.vehicleLockBlocksCharacter(self.vehicle, self.character) then
        FF.warnVehicleLockBlocked(self.vehicle, self.character)
        return true
    end
    return false
end

local originalIsValid = ISEnterVehicle.isValid
if type(originalIsValid) == "function" then
    function ISEnterVehicle:isValid()
        if blocked(self) then return false end
        return originalIsValid(self)
    end
end

local originalIsValidStart = ISEnterVehicle.isValidStart
if type(originalIsValidStart) == "function" then
    function ISEnterVehicle:isValidStart()
        if blocked(self) then return false end
        return originalIsValidStart(self)
    end
end
FF._vehicleEnterGuardInstalled = true
