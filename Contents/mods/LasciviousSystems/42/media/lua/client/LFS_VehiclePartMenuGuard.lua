-- Lascivious Factions System - preventative TRANCAR enforcement on vehicle
-- part install/uninstall, at the CONTEXT-MENU CLICK itself (client side).
--
-- LFS_VehicleActionGuard.lua already patches ISUninstallVehiclePart/
-- ISInstallVehiclePart's isValid()/isValidStart() -- but a second live test
-- showed that alone still isn't enough: the user could still open the hood
-- and pull a part with no impediment. Root cause found by reading
-- ISVehicleMechanics.lua directly: there is a debug "mechanics cheat" toggle
-- (ISVehicleMechanics.cheat, driven by getPlayer():isMechanicsCheat() --
-- exposed both via the admin panel and a "DBG:" context menu option) that,
-- when on, makes ISUninstallVehiclePart/ISInstallVehiclePart:getDuration()
-- collapse to A SINGLE TICK (see each class's own getDuration(), both
-- explicitly check self.character:isMechanicsCheat()). An action that
-- completes in ~1 tick leaves isValid()/isValidStart() -- both fundamentally
-- POLLING mechanisms -- little to no real window to ever catch it in.
-- ISTakeGasolineFromVehicle has no such instant branch at all, which is
-- exactly why gas siphoning was never affected by this gap and blocked
-- correctly from the very first attempt.
--
-- Rather than chase tick-timing further, this guards the one place that is
-- GUARANTEED to run exactly once, synchronously, at the moment the player
-- actually clicks "Instalar"/"Desinstalar" in the mechanics window or radial
-- menu -- ISVehiclePartMenu.onInstallPart/onUninstallPart (client/Vehicles/
-- ISUI/ISVehiclePartMenu.lua, the single shared entry point both the
-- mechanics window AND the right-click menu route through) -- completely
-- independent of how long the resulting TimedAction's duration ends up
-- being. The isValid()/isValidStart() patches in LFS_VehicleActionGuard.lua
-- are left in place as a second, redundant layer (harmless, still correct
-- for the normal-duration case a real thief -- without mechanics cheat --
-- would hit).

require "LFS_Shared"
require "LFS_VehicleGuard"
require "Vehicles/ISUI/ISVehiclePartMenu"

local FF = LasciviousFactionsSystem
if FF._vehiclePartMenuGuardInstalled then return end

local function blockedByLock(part, character)
    local vehicle = part and part:getVehicle()
    if vehicle and FF.vehicleLockBlocksCharacter(vehicle, character) then
        FF.warnVehicleLockBlocked(vehicle, character)
        return true
    end
    return false
end

local originalOnUninstallPart = ISVehiclePartMenu.onUninstallPart
if type(originalOnUninstallPart) == "function" then
    function ISVehiclePartMenu.onUninstallPart(playerObj, part)
        if blockedByLock(part, playerObj) then return end
        return originalOnUninstallPart(playerObj, part)
    end
end

local originalOnInstallPart = ISVehiclePartMenu.onInstallPart
if type(originalOnInstallPart) == "function" then
    function ISVehiclePartMenu.onInstallPart(playerObj, part, item)
        if blockedByLock(part, playerObj) then return end
        return originalOnInstallPart(playerObj, part, item)
    end
end
FF._vehiclePartMenuGuardInstalled = true

FF.checkpoint("vehicle part-menu guard installed (uninstall/install click gate)")
