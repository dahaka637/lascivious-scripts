-- Lascivious Factions System - preventative TRANCAR enforcement on vehicle
-- mechanics/fuel actions (shared: client AND server).
--
-- The existing workshopVehicleGuardTick (LFS_Server.lua) only reacts to a
-- non-member already sitting in a locked vehicle's seat or towing it -- it
-- has no idea about someone standing outside the vehicle siphoning gas or
-- popping the hood to pull a part, since neither of those ever puts the
-- character "in" the vehicle. Direct user request: block those actions
-- themselves, immediately, not after the fact ("de cara já bloqueasse...
-- bloquear a ação em si, tipo a ação de entrar ou ação de tirar gasolina, ou
-- ação de abrir capô etc.").
--
-- Vanilla research this session found NO existing permission hook at all for
-- siphoning gas (ISTakeGasolineFromVehicle:isValid() only checks inventory
-- space) and an opaque NATIVE hook for parts (vehicle:canUninstallPart /
-- canInstallPart -- can't be inspected or reimplemented from Lua, only
-- consumed as a black box). Either way, the actual extension point vanilla
-- itself uses for "can this action even run" is each TimedAction's own
-- plain-Lua isValid()/isValidStart() methods -- so this file monkey-patches
-- BOTH on the three vanilla classes that matter, adding
-- FF.vehicleLockBlocksCharacter's check (LFS_VehicleGuard.lua) BEFORE
-- falling through to the original.
--
-- BOTH methods, not just isValid() -- correction after first live test.
-- isValid() alone blocked gas siphoning (confirmed working) but NOT
-- uninstalling/installing a part, even though the wrapper code is identical
-- for all three. Root cause: ISTimedActionQueue.lua only ever consults
-- isValidStart() at the moment an action is dequeued/started (isValid() is
-- polled separately, only WHILE an action is already running) -- and
-- ISUninstallVehiclePart/ISInstallVehiclePart's own getDuration() collapses
-- to 1 tick under self.character:isMechanicsCheat() or :isTimedActionInstant()
-- (ISTakeGasolineFromVehicle has no such instant branch at all, which is
-- exactly why gas was never affected by this gap). An action that completes
-- in ~1 tick leaves isValid() little to no meaningful "while running" window
-- to catch it in, so the fix is to also gate at isValidStart() -- the same
-- earlier, proven gate ISTimedActionQueue.lua itself checks before an action
-- is ever allowed to begin, regardless of how long it then takes to finish.
--
-- All three patched classes live in shared/Vehicles/TimedActions -- meaning
-- they already run their own logic on both sides of the network (see e.g.
-- ISTakeGasolineFromVehicle's serverStart/serverStop). Patching here
-- therefore isn't just a client-side UI nicety like the TRANCAR button's
-- disabled state -- it also runs as the real server-side gate for these
-- specific networked actions, the same way the vanilla class itself does.
-- ISEnterVehicle is handled separately (client/LFS_VehicleEnterGuard.lua)
-- because that TimedAction is client-only in vanilla, with no server
-- counterpart to patch.

require "LFS_Shared"
require "LFS_VehicleGuard"
require "Vehicles/TimedActions/ISTakeGasolineFromVehicle"
require "Vehicles/TimedActions/ISUninstallVehiclePart"
require "Vehicles/TimedActions/ISInstallVehiclePart"

local FF = LasciviousFactionsSystem

-- Shared files can be reloaded by development tools without clearing class
-- tables. Do not stack another pair of wrappers around the same methods.
if FF._vehicleActionGuardInstalled then return end

-- Diagnostic detail is useful during an explicit debug session, but these
-- methods are polled continuously while an action is queued. Never route the
-- normal hot path through FF.warn/durable logging in a release session.
local lastDiagAt = {}
local function diagLog(self, vehicle, result)
    if not FF.debugEnabled() then return end
    local ty = tostring(self.Type)
    local now = getTimestamp()
    if lastDiagAt[ty] and (now - lastDiagAt[ty]) < 5 then return end
    lastDiagAt[ty] = now
    FF.log(string.format(
        "vehicle action guard: type=%s isServer=%s vehicleId=%s blocks=%s",
        ty, tostring(isServer()), tostring(vehicle and select(2, pcall(function() return vehicle:getId() end))),
        tostring(result)))
end

-- Shared check + halo-note feedback (FF.warnVehicleLockBlocked -- also used
-- by client/LFS_VehicleEnterGuard.lua, one throttle table for both).
local function blocked(self, vehicleField)
    local vehicle = self[vehicleField]
    local result = vehicle and FF.vehicleLockBlocksCharacter(vehicle, self.character)
    diagLog(self, vehicle, result)
    if result then
        FF.warnVehicleLockBlocked(vehicle, self.character)
        return true
    end
    return false
end

-- Wraps both `original` methods (vanilla isValid/isValidStart) so the
-- faction-lock check runs first on each; `vehicleField` is always "vehicle"
-- for these three classes (all three set self.vehicle = part:getVehicle()
-- in their own constructors -- verified directly against each class's own
-- :new(), not assumed).
local function guardAction(class, vehicleField)
    if type(class) ~= "table" then return false end
    local originalIsValid = class.isValid
    if type(originalIsValid) == "function" then
        class.isValid = function(self, ...)
            if blocked(self, vehicleField) then return false end
            return originalIsValid(self, ...)
        end
    end

    local originalIsValidStart = class.isValidStart
    if type(originalIsValidStart) == "function" then
        class.isValidStart = function(self, ...)
            if blocked(self, vehicleField) then return false end
            return originalIsValidStart(self, ...)
        end
    end
    return type(originalIsValid) == "function" or type(originalIsValidStart) == "function"
end

guardAction(ISTakeGasolineFromVehicle, "vehicle")
guardAction(ISUninstallVehiclePart, "vehicle")
guardAction(ISInstallVehiclePart, "vehicle")
FF._vehicleActionGuardInstalled = true

FF.checkpoint("vehicle action guard installed (gas/uninstall/install), isServer=" .. tostring(isServer()))
