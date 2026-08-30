if isServer() then return end
require("RYUKU_WanderingZombies_DirectorEvent")

---@class WZDirector
---@field private _init boolean
---@field private _nextEventScan integer
---@field private _activeEvents WZLinkedList
---@field private _zombieResets WZLinkedList
---@field private _baseUpdates WZLinkedList
---@field private _hordeUpdates WZLinkedList
---@field private _zombieUpdates WZLinkedList
WZDirector = {}

----------
-- Init --
----------

function WZDirector:init()
    self._nextEventScan = 0
    self._activeEvents = WZLinkedList:new("ActiveEvents")
    self._zombieResets = WZLinkedList:new("ZombieResets")
    self._baseUpdates = WZLinkedList:new("BaseUpdates")
    self._hordeUpdates = WZLinkedList:new("HordeUpdates")
    self._zombieUpdates = WZLinkedList:new("ZombieUpdates")
    self._init = true
end

------------
-- Update --
------------

local time
local eventLink, event
---@param zombieCount integer
function WZDirector:update(zombieCount)
    if not self._init then self:init() end

    time = getTimeInMillis()
    if time >= self._nextEventScan then
        self._nextEventScan = time + 5000

        for _, ev in pairs(WZ_DIRECTOR_EVENTS) do
            if ev.activeLink then
                if not ev:isEnabled() then ev:reset() end
            elseif ev:isEnabled() then
                ev.activeLink = self._activeEvents:push(ev)
                ev:init()

                if ev.wantZombieReset then ev.zombieResetLink = self._zombieResets:push(ev) end
                if ev.wantBaseUpdate then ev.baseUpdateLink = self._baseUpdates:push(ev) end
                if ev.wantHordeUpdate then ev.hordeUpdateLink = self._hordeUpdates:push(ev) end
                if ev.wantZombieUpdate then ev.zombieUpdateLink = self._zombieUpdates:push(ev) end
            end
        end
    else
        eventLink = self._activeEvents:next()
        if eventLink == nil then return end

        event = eventLink:getRef() --[[@as WZDirectorEvent]]
        if event:canRun(zombieCount) then event:run() end
    end
end

----------------
-- Reset Hook --
----------------

---@param wzZombie WZZombie
function WZDirector:zombieReset(wzZombie)
    if not self._init then return end
    for ev in self._zombieResets:iterRef() do
        ev:zombieReset(wzZombie)
    end
end

local wzZombie_reset = WZZombie.reset
function WZZombie:reset()
    if self.eventMoved then self.eventMoved = nil end
    WZDirector:zombieReset(self)
    return wzZombie_reset(self)
end

----------------------
-- Base Update Hook --
----------------------

---@param wzZombieBase WZZombieBase
function WZDirector:zombieBaseUpdate(wzZombieBase)
    if not self._init then return end
    for ev in self._baseUpdates:iterRef() do
        ev:zombieBaseUpdate(wzZombieBase)
    end
end

local wzZombieBase_update = WZZombieBase.update

---@return boolean
function WZZombieBase:update()
    if self.eventMoved and not self:isMoving() then self._eventMoved = nil end

    local result = wzZombieBase_update(self)
    if result ~= true then return result end

    WZDirector:zombieBaseUpdate(self)
    return true
end

-----------------------
-- Horde Update Hook --
-----------------------

---@param wzHorde WZHorde
function WZDirector:hordeUpdate(wzHorde)
    if not self._init then return end
    for ev in self._hordeUpdates:iterRef() do
        ev:hordeUpdate(wzHorde)
    end
end

local wzHorde_update = WZHorde.update

---@return boolean
function WZHorde:update()
    local result = wzHorde_update(self)
    if result ~= true then return result end

    WZDirector:hordeUpdate(self)
    return true
end

------------------------
-- Zombie Update Hook --
------------------------

---@param wzZombie WZZombie
function WZDirector:zombieUpdate(wzZombie)
    if not self._init then return end
    for ev in self._zombieUpdates:iterRef() do
        ev:zombieUpdate(wzZombie)
    end
end

local wzZombie_update = WZZombie.update

---@return boolean
function WZZombie:update()
    local result = wzZombie_update(self)
    if result ~= true then return result end

    WZDirector:zombieUpdate(self)
    return true
end
