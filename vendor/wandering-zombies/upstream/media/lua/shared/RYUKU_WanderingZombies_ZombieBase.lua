if isServer() then return end

require("RYUKU_WanderingZombies_Vector")
require("RYUKU_WanderingZombies_SandboxVars")
require("RYUKU_WanderingZombies_Utility")

---@class WZZombieBase
---@field private __wzZombieBase boolean
---@field protected _init boolean
---@field protected _ref zombie.characters.IsoZombie
---@field protected _position WZVector
---@field protected _lastPosition WZVector
---@field private _nextUpdate number
---@field private _moveCooldown number
WZZombieBase =
{
    __wzZombieBase = true,
    _init = false
}

-----------------
-- Inheritance --
-----------------

---@protected
---@return WZZombieBase
function WZZombieBase:derive()
    local obj = {}
    setmetatable(obj, self)
    self.__index = self

    return obj
end

-----------------
-- Constructor --
-----------------

---@protected
---@param isoZombie zombie.characters.IsoZombie
---@return WZZombieBase
function WZZombieBase:new(isoZombie)
    local obj = {}
    setmetatable(obj, self)
    self.__index = self

    obj._ref = isoZombie

    isoZombie:getModData().wz = true
    return obj
end

----------------
-- Initialise --
----------------

---@protected
function WZZombieBase:init()
    self._init = true
    self._position = WZVector:new(self._ref)
    self._lastPosition = WZVector:new(self._ref)
    self._nextUpdate = 0
    self._moveCooldown = 0

    if WZSandboxVars:get(WZ_SHARED, "MoveCooldownInitial") then self:updateMoveCooldown(false) end
end

---@return boolean
function WZZombieBase:isInit()
    return self._init
end

-----------
-- Reset --
-----------

---@protected
function WZZombieBase:reset()
    local modData = self._ref:getModData()
    modData.wz = nil
    modData.wzThumpIndoors = nil

    self._init = nil
    self._ref = nil
    self._position = nil
    self._lastPosition = nil
    self._nextUpdate = nil
    self._moveCooldown = nil
end

------------
-- Update --
------------

---@protected
---@return boolean?
function WZZombieBase:update()
    -- perform init if necessary
    -- return false to signal that update should not continue
    if self._init ~= true then
        self:init()
        return false
    end

    -- validate zombie
    -- return nil to signal that the zombie is not valid
    if not self:isValid() then
        self:reset()
        return nil
    end

    -- prevent updates from occuring too frequently
    if getTimeInMillis() < self._nextUpdate then return false
    else self._nextUpdate = getTimeInMillis() + 250 end

    self:updatePosition()
    return true
end

----------------
-- Validation --
----------------

---@return boolean
function WZZombieBase:isValid()
    return (not isClient() or not self._ref:isRemoteZombie())   -- zombie must be under player's control
        and not self._ref:isDead()                              -- zombie must not be dead
        and self._ref:isExistInTheWorld()                       -- zombie must exist in the world
        and not self._ref:getVariableBoolean("Bandit")          -- Bandits mod compatibility
end

-------------
-- Vanilla --
-------------

function WZZombieBase:isOutside()
    return self._ref:isOutside()
end

-------------
-- Targets --
-------------

---@return boolean
function WZZombieBase:hasTarget()
    return self._ref:getTarget() ~= nil
        or self._ref:getThumpTarget() ~= nil
        or self._ref:getEatBodyTarget() ~= nil
end

---@return zombie.iso.IsoObject?
function WZZombieBase:getTarget()
    return self._ref:getTarget()
        or self._ref:getThumpTarget()
        or self._ref:getEatBodyTarget()
end

-----------------------
-- Movement Cooldown --
-----------------------

---@protected
---@param inHorde boolean
function WZZombieBase:updateMoveCooldown(inHorde)
    self._moveCooldown = getTimeInMillis()
        + WZSandboxVars:getZ("MoveCooldown", inHorde)
        + ZombRand(0, WZSandboxVars:getZ("MoveCooldownRandom", inHorde) + 1)
end

---@return boolean
function WZZombieBase:isMoveCooldownExpired()
    return getTimeInMillis() >= self._moveCooldown
end

--------------
-- Position --
--------------

---@private
function WZZombieBase:updatePosition()
    self._lastPosition:update(self._position)
    self._position:update(self._ref)
end

---@return WZVector copy
function WZZombieBase:getPosition()
    return self._position:copy()
end

---@param obj WZZombieBase|WZVector|zombie.iso.IsoObject|zombie.iso.IsoGridSquare
---@return number
function WZZombieBase:distanceTo(obj)
    if obj.__wzZombieBase then return self._position:distanceTo(obj._position) end
    return self._position:distanceTo(obj --[[@as WZVector|zombie.iso.IsoObject|zombie.iso.IsoGridSquare]])
end

-------------
-- Pathing --
-------------

---@return boolean
function WZZombieBase:isMoving()
    if self._ref:isMoving() or self._ref:hasPath() or self._ref:isClimbing() then return true end

    local state = self._ref:getCurrentStateName()
    return state == "WalkTowardState"
        or state == "PathFindState2"
        or state == "ClimbOverFenceState"
        or state == "ClimbThroughWindowState"
end

function WZZombieBase:isAlerted()
    return self._ref:getCurrentStateName() == "ZombieTurnAlerted"
end

---@return WZVector
function WZZombieBase:getPathTarget()
    return WZVector:new({
            x = self._ref:getPathTargetX(),
            y = self._ref:getPathTargetY(),
            z = self._ref:getPathTargetZ()
    })
end

local pathToPos
---@param pos WZVector
---@param moveKey string
---@param inHorde boolean
---@return boolean
function WZZombieBase:pathTo(pos, moveKey, inHorde)
    if pathToPos == nil then pathToPos = pos:copy()
    else pathToPos:update(pos) end
    pathToPos:floor()

    -- find walkable squares across Z height, and pick one at random
    -- NOTE: can and will result in paths further than Max Travel Distance
    local square
    local cell = getCell()
    local squares = {}
    for i = -1, 1 do
        square = cell:getGridSquare(pathToPos.x, pathToPos.y, pathToPos.z + i)
        if square ~= nil and square:isSolidFloor() then
            table.insert(squares, square)
        end
    end

    if #squares == 0 then return false end
    pathToPos.z = squares[ZombRand(#squares) + 1]:getZ()

    -- NOTE: animation disabled due to ZombieTurnAlerted always forcing destruction
    -- TODO: revisit in B42
    --self._ref:setTurnAlertedValues(pathToPos.x, pathToPos.y)

    -- determine whether to be destructive or not
    local destructMode = WZSandboxVars:getZ(moveKey .. "Destructive", inHorde)
    local indoorThump = destructMode == 2 and not self._ref:isOutside()
    self._ref:getModData().wzThumpIndoors = indoorThump or nil

    if indoorThump or destructMode == 1 then self._ref:pathToSound(pathToPos.x, pathToPos.y, pathToPos.z)
    else self._ref:pathToLocation(pathToPos.x, pathToPos.y, pathToPos.z) end
    return true
end

---@param zombie zombie.characters.IsoZombie
local function monitorIndoorThump(zombie)
    local modData = zombie:getModData()
    if not modData.wzThumpIndoors then return end

    if zombie:getTarget() ~= nil
        or zombie:getThumpTarget() ~= nil
        or zombie:getEatBodyTarget() ~= nil
        or zombie:getLastHeardSound():getX() ~= -1
    then
        modData.wzThumpIndoors = nil
        return
    end

    local square = zombie:getSquare()
    if square ~= nil and square:isOutside() then
        local state = zombie:getCurrentStateName()
        if state == "PathFindState2"
            or state == "WalkTowardState"
            or state == "ClimbThroughWindowState"
            or string.find(state, "ClimbOver")
        then
            zombie:pathToLocation(zombie:getPathTargetX(), zombie:getPathTargetY(), zombie:getPathTargetZ())
        end

        modData.wzThumpIndoors = nil
    end
end

Events.OnZombieUpdate.Add(monitorIndoorThump)

-----------
-- Speed --
-----------

-- SPEED_SPRINTER = 1
-- SPEED_FAST_SHAMBLER = 2
-- SPEED_SHAMBLER = 3
-- SPEED_RANDOM = 4

local speedIdx ---@type integer?
local speedError = false

---@return integer
function WZZombieBase:getSpeed()
    if speedIdx == nil then
        if not speedError then
            speedIdx = WZUtility:getClassFieldIdx(self._ref, "public int zombie.characters.IsoZombie.speedType")
            if speedIdx == nil then
                getPlayer():addLineChatElement("Wandering Zombies: speedIdx == nil")
                speedError = true

                return 2
            end
        else
            return 2
        end
    end

    -- NOTE: returns crawlers as 5, this is not a vanilla SPEED_*
    return (self._ref:isCrawling() and 5) or (WZUtility:getClassFieldVal(self._ref, speedIdx) or 2)
end

---@return boolean
function WZZombieBase:isSprinter()
    return self:getSpeed() == 1
end

--------------------
-- Debug: History --
--------------------

local debugHistory = false
local historyChat = false
local historyLimit = 50

function WZZombieBase:addHistory(msg)
    if not debugHistory then return end
    if historyChat then
        self._ref:addLineChatElement(msg)
        return
    end
   
    if not self._history then self._history = {} end
    table.insert(self._history, msg)
    if #self._history > historyLimit then table.remove(self._history, 1) end
end
