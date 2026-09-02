--
-- Lascivious Scripts - Vehicle Firearms
--
-- Gameplay QoL for B42 firearm handling while seated in the driver's seat.
-- The module keeps the change scoped to firearm timed actions created while the
-- character is driving, avoiding the broader exploit of reloading while running
-- on foot.
--

LasciviousScripts = LasciviousScripts or {}
LasciviousScripts.VehicleFirearms = LasciviousScripts.VehicleFirearms or {}

local Core = LasciviousScripts.VehicleFirearms

Core.VERSION = "1.0.7"
Core.OPTION_TABLE = "LasciviousScriptsVehicleFirearms"

Core.DEFAULTS = {
    Enabled = true,
    RelaxDriverFirearmActions = true,
    PreserveDriverControls = true,
    EmergencyCancel = true,
}

Core.FIREARM_ACTION_TYPES = {
    ISReloadWeaponAction = true,
    ISRackFirearm = true,
    ISInsertMagazine = true,
    ISEjectMagazine = true,
    ISLoadBulletsInMagazine = true,
    ISUnloadBulletsFromMagazine = true,
    ISUnloadBulletsFromFirearm = true,
}

Core.PATCH_TARGETS = {
    { name = "ISReloadWeaponAction", path = "TimedActions/ISReloadWeaponAction" },
    { name = "ISRackFirearm", path = "TimedActions/ISRackFirearm" },
    { name = "ISEjectMagazine", path = "TimedActions/ISEjectMagazine" },
    { name = "ISInsertMagazine", path = "TimedActions/ISInsertMagazine" },
    { name = "ISLoadBulletsInMagazine", path = "TimedActions/ISLoadBulletsInMagazine" },
    { name = "ISUnloadBulletsFromMagazine", path = "TimedActions/ISUnloadBulletsFromMagazine" },
    { name = "ISUnloadBulletsFromFirearm", path = "TimedActions/ISUnloadBulletsFromFirearm" },
}

Core._methodPatches = Core._methodPatches or {}
Core._wrappedMethods = Core._wrappedMethods or {}
Core._patchComplete = Core._patchComplete or false
Core._patchCount = Core._patchCount or 0
Core._vehicleUpdateControlsCallable = Core._vehicleUpdateControlsCallable

local function getLiveOption(name, fallback)
    local fullName = Core.OPTION_TABLE .. "." .. name
    local options = getSandboxOptions and getSandboxOptions() or nil
    if options then
        local option = options:getOptionByName(fullName)
        if option then
            local value = option:getValue()
            if value ~= nil then return value end
        end
    end

    local tableVars = SandboxVars and SandboxVars[Core.OPTION_TABLE] or nil
    if tableVars and tableVars[name] ~= nil then return tableVars[name] end
    return fallback
end

function Core.getConfig()
    return {
        Enabled = getLiveOption("Enabled", Core.DEFAULTS.Enabled) == true,
        RelaxDriverFirearmActions = getLiveOption("RelaxDriverFirearmActions", Core.DEFAULTS.RelaxDriverFirearmActions) == true,
        PreserveDriverControls = getLiveOption("PreserveDriverControls", Core.DEFAULTS.PreserveDriverControls) == true,
        EmergencyCancel = getLiveOption("EmergencyCancel", Core.DEFAULTS.EmergencyCancel) == true,
    }
end

local function safeBool(fn)
    local ok, value = pcall(fn)
    return ok and value == true
end

local function safeCall(fn)
    local ok, value = pcall(fn)
    return ok, value
end

local function getGlobalTable()
    if _G then return _G end
    return nil
end

function Core.getDriverVehicle(character)
    if not character then return nil end

    local okVehicle, vehicle = pcall(function() return character:getVehicle() end)
    if not okVehicle or not vehicle then return nil end

    local okIsDriver, isDriver = pcall(function()
        if vehicle.isDriver then return vehicle:isDriver(character) end
        if vehicle.getDriver then return vehicle:getDriver() == character end
        return false
    end)
    if okIsDriver and isDriver == true then return vehicle end

    local okSeat, seat = pcall(function() return vehicle:getSeat(character) end)
    if okSeat and seat == 0 then return vehicle end

    return nil
end

function Core.isDriver(character)
    return Core.getDriverVehicle(character) ~= nil
end

function Core.isRangedWeapon(item)
    if not item then return false end
    return safeBool(function() return item:isRanged() end)
end

function Core.getPrimaryHandItem(character)
    if not character then return nil end
    local ok, item = pcall(function() return character:getPrimaryHandItem() end)
    if ok then return item end
    return nil
end

function Core.hasRangedWeaponEquipped(character)
    return Core.isRangedWeapon(Core.getPrimaryHandItem(character))
end

function Core.hasFirearmAnimationState(character)
    if not character then return false end
    if safeBool(function() return character:getVariableBoolean("isLoading") end) then return true end
    if safeBool(function() return character:getVariableBoolean("isRacking") end) then return true end
    if safeBool(function() return character:getVariableBoolean("isUnloading") end) then return true end
    return false
end

function Core.isAimingOrLookingFromVehicle(character)
    if not character then return false end
    if safeBool(function() return character:isAiming() end) then return true end
    if safeBool(function() return character:isLookingWhileInVehicle() end) then return true end
    return false
end

function Core.isFirearmAction(action)
    if type(action) ~= "table" then return false end

    local actionType = action.Type
    if actionType and Core.FIREARM_ACTION_TYPES[actionType] then return true end
    if action.reloading == true then return true end
    if action.gun and Core.isRangedWeapon(action.gun) then return true end

    if action.magazine and type(actionType) == "string" then
        if string.find(actionType, "Magazine", 1, true) or string.find(actionType, "Bullets", 1, true) then
            return true
        end
    end

    return false
end

function Core.clearFirearmAnimationState(character, action)
    if action then
        if action.gun then safeCall(function() action.gun:setJobDelta(0.0) end) end
        if action.magazine then safeCall(function() action.magazine:setJobDelta(0.0) end) end
    end

    if not character then return end
    safeCall(function() character:clearVariable("isLoading") end)
    safeCall(function() character:clearVariable("isRacking") end)
    safeCall(function() character:clearVariable("isUnloading") end)
    safeCall(function() character:clearVariable("WeaponReloadType") end)
    safeCall(function() character:clearVariable("RackAiming") end)
end

function Core.releaseMovementLocks(character)
    if not character then return end
    safeCall(function() character:setIgnoreMovement(false) end)
    safeCall(function() character:setBlockMovement(false) end)
end

function Core.refreshDriverVehicleControls(character)
    if isServer and isServer() then return false end
    if Core._vehicleUpdateControlsCallable == false then return false end

    local vehicle = Core.getDriverVehicle(character)
    if not vehicle then return false end

    local ok, err = pcall(function() vehicle:updateControls() end)
    if ok then
        Core._vehicleUpdateControlsCallable = true
        return true
    end

    Core._vehicleUpdateControlsCallable = false
    return false
end

function Core.shouldPreserveDriverControls(character, action)
    local cfg = Core.getConfig()
    if not cfg.Enabled or not cfg.PreserveDriverControls then return false end
    if not Core.isDriver(character) then return false end

    if action and Core.isFirearmAction(action) then return true end
    if Core.hasFirearmAnimationState(character) then return true end

    return Core.hasRangedWeaponEquipped(character) and Core.isAimingOrLookingFromVehicle(character)
end

function Core.preserveDriverControls(character, action, reason)
    if not Core.shouldPreserveDriverControls(character, action) then return false end

    -- B42's BaseVehicle.updateControls() returns immediately when the driver
    -- has blockMovement=true. Aiming/reloading firearms can set that flag, so
    -- we clear only that movement gate while the character is the driver and is
    -- actively handling a firearm.
    Core.releaseMovementLocks(character)
    Core.refreshDriverVehicleControls(character)

    return true
end

function Core.relaxActionForDriver(action)
    if not Core.isFirearmAction(action) then return false end

    local cfg = Core.getConfig()
    if not cfg.Enabled or not cfg.RelaxDriverFirearmActions then return false end
    if not Core.isDriver(action.character) then return false end

    local changed = false

    if action.stopOnAim ~= false then action.stopOnAim = false; changed = true end
    if action.stopOnWalk ~= false then action.stopOnWalk = false; changed = true end
    if action.stopOnRun ~= false then action.stopOnRun = false; changed = true end

    Core.releaseMovementLocks(action.character)
    Core.refreshDriverVehicleControls(action.character)

    return changed
end

function Core.patchActionMethod(globalName, methodName)
    local globals = getGlobalTable()
    local actionClass = globals and globals[globalName] or nil
    if not actionClass or type(actionClass[methodName]) ~= "function" then return false end

    local patchKey = globalName .. "." .. methodName
    if Core._wrappedMethods[patchKey] and actionClass[methodName] == Core._wrappedMethods[patchKey] then
        return true
    end

    local original = actionClass[methodName]
    Core._methodPatches[patchKey] = Core._methodPatches[patchKey] or original

    local wrapped = function(self, ...)
        if methodName == "start" then
            Core.relaxActionForDriver(self)
            Core.preserveDriverControls(self and self.character or nil, self, methodName)
        end

        local result1, result2, result3, result4 = original(self, ...)

        Core.relaxActionForDriver(self)
        Core.preserveDriverControls(self and self.character or nil, self, methodName)

        return result1, result2, result3, result4
    end

    Core._wrappedMethods[patchKey] = wrapped
    actionClass[methodName] = wrapped
    return true
end

-- BUG (found 2026-09-01, decompiled zombie.core.NetTimedAction to root-cause):
-- this used to also wrap `<Class>.new` the same way it wraps `start`/`update`
-- below, calling Core.relaxActionForDriver(action) right after construction.
-- That broke reload/rack/unload EVEN OUTSIDE VEHICLES, for every player.
--
-- NetTimedAction.set(player, action) reads `action:getMetatable():rawget("new")`
-- -- the CLASS's OWN constructor closure -- casts it to a LuaClosure and reads
-- its *compiled bytecode prototype* (numParams + the local-variable NAMES the
-- Lua compiler recorded for each parameter) to decide which named fields of
-- the instance to copy into actionArgs for network (re)construction. This is
-- Java reflecting on the constructor's own parameter list, not calling it --
-- it has no way to know our replacement function is "the same constructor
-- with extra behaviour tacked on". Our `function(self, ...) ... end` wrapper
-- has exactly ONE compiled parameter (`self`; `...` is not a named local), so
-- that loop found zero real parameter names, actionArgs came back with
-- `character`/`weapon`/etc. entirely missing, and the reconstructed action
-- had a nil self.character server-side -- exactly the
-- "getPerkLevel/getSpentRoundCount of non-table: null" crashes in vanilla
-- ISReloadWeaponAction/ISRackFirearm.
--
-- Fixed by never touching `.new` at all. `Core.relaxActionForDriver` already
-- runs from the `start` method wrap below (both before AND after the real
-- start()), which fires once the action is fully constructed with a real
-- self.character/self.gun -- functionally equivalent, and `start`/`update` are
-- called directly by Lua (self:start()), never introspected by Java for named
-- parameters, so wrapping them is safe.
function Core.patchFirearmTimedActions(force)
    if not force and Core._patchComplete then return Core._patchCount end

    local patched = 0

    for _, target in ipairs(Core.PATCH_TARGETS) do
        if target.path then
            pcall(require, target.path)
        end
    end

    for _, target in ipairs(Core.PATCH_TARGETS) do
        if Core.patchActionMethod(target.name, "start") then patched = patched + 1 end
        Core.patchActionMethod(target.name, "update")
    end

    Core._patchComplete = patched > 0
    Core._patchCount = patched
    return patched
end

Core.patchFirearmTimedActions()

return Core
