if isServer() then return end
require("RYUKU_WanderingZombies_Zombie")

---@class WZZombieBase
---@field public eventMoved boolean?

WZ_DIRECTOR_EVENTS = {} ---@type WZDirectorEvent[]
local RESET_LINK_KEYS = { "activeLink", "zombieResetLink", "baseUpdateLink", "hordeUpdateLink", "zombieUpdateLink" }

---@class WZDirectorEvent
---@field private _name string
---@field public activeLink WZLinkedListLink?
---@field public wantZombieReset boolean
---@field public wantBaseUpdate boolean
---@field public wantHordeUpdate boolean
---@field public wantZombieUpdate boolean
---@field public zombieResetLink WZLinkedListLink?
---@field public baseUpdateLink WZLinkedListLink?
---@field public hordeUpdateLink WZLinkedListLink?
---@field public zombieUpdateLink WZLinkedListLink?
---@field protected _cooldown integer
WZDirectorEvent = {}

---@param name string
---@return WZDirectorEvent
function WZDirectorEvent:derive(name)
    local obj = {}
    setmetatable(obj, self)
    self.__index = self

    obj._name = name
    return obj
end

----------
-- Init --
----------

function WZDirectorEvent:init()
    self:updateCooldown()
end

-----------
-- Reset --
-----------

function WZDirectorEvent:reset()
    self._cooldown = nil

    local link
    for _, v in pairs(RESET_LINK_KEYS) do
        link = self[v] --[[@as WZLinkedListLink?]]
        if link ~= nil then
            link:getList():remove(link)
            self[v] = nil
        end
    end
end

--------------
--- Enabled --
--------------

---@return boolean
function WZDirectorEvent:isEnabled()
    print("WZDirectorEvent " .. tostring(self._name) .. " did not override isEnabled")
    return false
end

---@param zombieCount integer
---@return boolean
function WZDirectorEvent:canRun(zombieCount)
    if WZTime:getTimestamp() < self._cooldown then return false end
    return true
end

function WZDirectorEvent:run()
    self:updateCooldown()
end

---@param wzZombie WZZombie
function WZDirectorEvent:zombieReset(wzZombie)
    print("WZDirectorEvent " .. tostring(self._name) .. "did not override zombieReset")
end

---@param wzZombieBase WZZombieBase
function WZDirectorEvent:zombieBaseUpdate(wzZombieBase)
    print("WZDirectorEvent " .. tostring(self._name) .. " did not override zombieBaseUpdate")
end

---@param wzHorde WZHorde
function WZDirectorEvent:hordeUpdate(wzHorde)
    print("WZDirectorEvent " .. tostring(self._name) .. " did not override hordeUpdate")
end

---@param wzZombie WZZombie
function WZDirectorEvent:zombieUpdate(wzZombie)
    print("WZDirectorEvent " .. tostring(self._name) .. " did not override zombieUpdate")
end

function WZDirectorEvent:updateCooldown()
    print("WZDirectorEvent " .. tostring(self._name) .. " did not override updateCooldown")
end
