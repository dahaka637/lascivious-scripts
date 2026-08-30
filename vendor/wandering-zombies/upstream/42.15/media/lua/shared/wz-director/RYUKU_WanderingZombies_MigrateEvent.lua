if isServer() then return end
require("RYUKU_WanderingZombies_DirectorEvent")

------------------
-- WZPulseEvent --
------------------

---@class WZMigrateEvent: WZDirectorEvent
---@field private _pulsePos WZVector
WZMigrateEvent = WZDirectorEvent:derive("WZPulseEvent")

-------------
-- Enabled --
-------------

---@return boolean
function WZMigrateEvent:isEnabled()
    return WZSandboxVars:get(WZ_DIRECTOR, "MigrateEnabled") and not isClient()
end

--------------
-- Cooldown --
--------------

function WZMigrateEvent:updateCooldown()
    self._cooldown = WZTime:getTimestamp() + WZSandboxVars:get(WZ_DIRECTOR, "MigrateCooldown") * 60
end

---------
-- Run --
---------

---@param zombieCount integer
---@return boolean
function WZMigrateEvent:canRun(zombieCount)
    if zombieCount < WZSandboxVars:get(WZ_DIRECTOR, "MigrateZombieThreshold") then
        return WZDirectorEvent.canRun(self, zombieCount)
    end

    self:updateCooldown()
    return false
end

local soundMan
function WZMigrateEvent:run()
    WZDirectorEvent.run(self)
    if not soundMan then soundMan = getWorldSoundManager() end

    local player = getPlayer()
    soundMan:addSound(
        nil,
        math.floor(player:getX()) + ZombRand(-80, 81), math.floor(player:getY()) + ZombRand(-80, 81), 0,
        WZSandboxVars:get(WZ_DIRECTOR, "MigrateDistance"), 300,
        false,
        120,
        0, false, isClient(), false, false, false
    )
end

----------
-- Init --
----------

function WZMigrateEvent:init()
    WZDirectorEvent.init(self)
    self._pulsePos = WZVector:blank()
end

-----------
-- Reset --
-----------

function WZMigrateEvent:reset()
    WZDirectorEvent.reset(self)
    self._pulsePos = nil
end

------------------------
-- WZ_DIRECTOR_EVENTS --
------------------------

table.insert(WZ_DIRECTOR_EVENTS, WZMigrateEvent)
