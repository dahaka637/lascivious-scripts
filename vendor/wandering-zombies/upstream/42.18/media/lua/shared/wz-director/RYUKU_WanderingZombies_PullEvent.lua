if isServer() then return end
require("RYUKU_WanderingZombies_DirectorEvent")

---@class WZZombieBase
---@field package nearbyLink WZLinkedListLink?

---@class WZPullEvent: WZDirectorEvent
---@field private _radius number
---@field private _minRadius number
---@field private _radiusTime integer
---@field private _unseenTriggerTime integer
WZPullEvent = WZDirectorEvent:derive("WZPullEvent")

----------
-- Init --
----------

function WZPullEvent:init()
    WZDirectorEvent.init(self)
    self._radius = WZSandboxVars:get(WZ_DIRECTOR, "PullMaxRadius")
    self._minRadius = WZSandboxVars:get(WZ_DIRECTOR, "PullMinRadius")
    self._radiusTime = 0
    self._unseenTriggerTime = 0
    self.wantHordeUpdate = true

    Events.OnZombieDead.Add(WZPullEvent.onZombieDead)
    Events.OnZombieUpdate.Add(WZPullEvent.onZombieUpdate)
end

-----------
-- Reset --
-----------

function WZPullEvent:reset()
    WZDirectorEvent.reset(self)
    self._radius = nil
    self._unseenTriggerTime = nil

    Events.OnZombieDead.Remove(WZPullEvent.onZombieDead)
    Events.OnZombieUpdate.Remove(WZPullEvent.onZombieUpdate)
end

-------------
-- Enabled --
-------------

---@return boolean
function WZPullEvent:isEnabled()
    return WZSandboxVars:get(WZ_DIRECTOR, "PullEnabled")
end

------------
-- Unseen --
------------

---@return boolean
function WZPullEvent:isUnseen()
    return WZTime:getTimestamp() >= self._unseenTriggerTime
end

local player ---@type zombie.characters.IsoPlayer?
local modData, timeMs
---@param zombie zombie.characters.IsoZombie
function WZPullEvent.onZombieUpdate(zombie)
    modData = zombie:getModData()
    timeMs = getTimeInMillis()
    if modData.wzUnseen == nil or timeMs > modData.wzUnseen then
        modData.wzUnseen = timeMs + 1000
        if player == nil or player:isDead() then
            player = getPlayer()
            return
        end

        if zombie:getTarget() == player then
            WZPullEvent._unseenTriggerTime = WZTime:getTimestamp() + WZSandboxVars:get(WZ_DIRECTOR, "PullUnseenTime") * 60
            WZPullEvent._radius = WZSandboxVars:get(WZ_DIRECTOR, "PullMaxRadius")
        end
    end
end

---------
-- Run --
---------

---@param zombieCount integer
---@return boolean
function WZPullEvent:canRun(zombieCount)
    return false
end

------------------------
-- Zombie Base Update --
------------------------

local timestamp

---@param wzHorde WZHorde
function WZPullEvent:hordeUpdate(wzHorde)
    timestamp = WZTime:getTimestamp()
    if timestamp < self._unseenTriggerTime then return end
    if wzHorde:isMoving() or not wzHorde:isMoveCooldownExpired() then return end
    if player == nil or player:isDead() then
        player = getPlayer()
        return
    elseif wzHorde:chebyshevTo(player) <= self._radius then return end

    wzHorde:pathTo(
        WZVector:new(getPlayer()):addRand(self._minRadius, self._radius + 1),
        "Wander",
        false,
        false,
        false,
        true,
        true
    )

    if timestamp < self._radiusTime then return end
    self._radius = math.max(self._minRadius, self._radius - WZSandboxVars:get(WZ_DIRECTOR, "PullMaxRadius") * 0.01)
    self._radiusTime = timestamp + 60
end

------------------------
-- WZ_DIRECTOR_EVENTS --
------------------------

table.insert(WZ_DIRECTOR_EVENTS, WZPullEvent)
