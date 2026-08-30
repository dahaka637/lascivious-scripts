if isServer() then return end
require("RYUKU_WanderingZombies_Vector")
require("RYUKU_WanderingZombies_SandboxVars")
require("RYUKU_WanderingZombies_Utility")

local square

---@class WZZombieBase
---@field private __wzZombieBase boolean
---@field protected _init boolean
---@field protected _ref zombie.characters.IsoZombie
---@field protected _position WZVector
---@field protected _lastPosition WZVector
---@field private _nextUpdate number
---@field private _moveCooldown number
---@field private _isMoving boolean
---@field private _state string?
---@field private _isOutside boolean
---@field private _exploreRef zombie.iso.areas.IsoBuilding?
---@field private _lastExploredRoom zombie.iso.areas.IsoRoom?
---@field protected _exploreCount integer
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
    self._exploreCount = 0

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
    self._state = nil
    self._isOutside = nil
    self._exploreRef = nil
    self._exploreCount = nil
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

    self:updateState()
    if self._ref:isUseless() or self._state == nil then
        return false
    end

    if self:hasTarget() then
        self:updateMoveCooldown(false)
        return false
    end

    self:updatePosition()
    self:updateMoving()
    self:updateOutside()

    -- building exploration
    if WZSandboxVars:get(WZ_SHARED, "RoomExploreLimit") > 0
        and (WZSandboxVars:get(WZ_SHARED, "DumbZombiesExplore") or self:isSmart())
    then
        if self:isOutside() then
            self._exploreRef = nil
            self._lastExploredRoom = nil
            self._exploreCount = 0
        elseif self._exploreRef == nil then
            self._exploreRef = self._ref:getBuilding()
            if self._exploreRef ~= nil then
                if not self:isMoving() or RYRNG:mod(100) < WZSandboxVars:get(WZ_SHARED, "ForcedExploreChance") then
                    self._ref:setVariable("bMoving", false)
                    self._ref:setVariable("bPathfind", false)
                    self._exploreCount = RYRNG:range(1, WZSandboxVars:get(WZ_SHARED, "RoomExploreLimit"))
                    return false
                end
            end
        elseif self:isMoveCooldownExpired() and self:getExplorePosition() then
            self:updateMoveCooldown(false)
            return false
        end
    end

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

-------------------
-- Current State --
-------------------

function WZZombieBase:updateState()
    self._state = self._ref:getCurrentStateName()
end

---@return string?
function WZZombieBase:getState()
    return self._state
end

-------------
-- Outside --
-------------

function WZZombieBase:isOutside()
    return self._isOutside
end

function WZZombieBase:updateOutside()
    self._isOutside = self._ref:isOutside()
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

---@param inHorde boolean
function WZZombieBase:updateMoveCooldown(inHorde)
    self._moveCooldown = getTimeInMillis()
        + WZSandboxVars:getZ("MoveCooldown", inHorde)
        + RYRNG:range(0, WZSandboxVars:getZ("MoveCooldownRandom", inHorde))
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
    if WZSandboxVars:get(WZ_SHARED, "ChebyshevDistance") then return self:chebyshevTo(obj) end

    if obj.__wzZombieBase then return self._position:distanceTo(obj._position) end
    return self._position:distanceTo(obj --[[@as WZVector|zombie.iso.IsoObject|zombie.iso.IsoGridSquare]])
end

---@param obj WZZombieBase|WZVector|zombie.iso.IsoObject|zombie.iso.IsoGridSquare
---@return number
function WZZombieBase:chebyshevTo(obj)
    if obj.__wzZombieBase then return self._position:chebyshevTo(obj._position) end
    return self._position:chebyshevTo(obj --[[@as WZVector|zombie.iso.IsoObject|zombie.iso.IsoGridSquare]])
end

-------------
-- Pathing --
-------------

---@private
function WZZombieBase:updateMoving()
    self._isMoving = self._ref:getVariableBoolean("bMoving") or self._ref:getVariableBoolean("bPathfind")
        or self._ref:isClimbing()

    if not self._isMoving then
        local state = self._state:sub(1, 5)
        self._isMoving = state == "WalkT" or state == "PathF" or state == "Climb"
    end
end

---@return boolean
function WZZombieBase:isMoving()
    return self._isMoving
end

function WZZombieBase:isAlerted()
    return self._state == "ZombieTurnAlerted"
end

---@return WZVector
function WZZombieBase:getPathTarget()
    return WZVector:new({
            x = self._ref:getPathTargetX(),
            y = self._ref:getPathTargetY(),
            z = self._ref:getPathTargetZ()
    })
end

local pathToPos, isDestructive
---@param pos WZVector
---@param moveType string
---@param inHorde boolean
---@param noZScan boolean?
---@param forceOOCP boolean?
---@param forcePathfind boolean?
---@param skipDestruction boolean?
---@return boolean
function WZZombieBase:pathTo(pos, moveType, inHorde, noZScan, forceOOCP, forcePathfind, skipDestruction)
    if pathToPos == nil then pathToPos = pos:copy()
    else pathToPos:update(pos) end
    pathToPos:floor()

    if not noZScan then
        -- find walkable squares across Z height, and pick one at random
        -- NOTE: can and will result in paths further than Max Travel Distance
        -- NOTE: allowing nil squares so zombies can path outside the loaded area
        local cell = getCell()
        local zLevels = {}
        local outOfCell = forceOOCP
            or (WZSandboxVars:get(WZ_SHARED, "OutOfCellPaths")
                and WZSandboxVars:getZombieCount() > WZSandboxVars:get(WZ_SHARED, "OutOfCellThreshold"))

        for i = -1, 1 do
            square = cell:getGridSquare(pathToPos.x, pathToPos.y, pathToPos.z + i)
            if square == nil then
                if outOfCell then table.insert(zLevels, pathToPos.z + i) end
            elseif square:isSolidFloor() then table.insert(zLevels, pathToPos.z + i) end
        end

        if #zLevels == 0 then return false end
        pathToPos.z = zLevels[RYRNG:range(1, #zLevels)]
    end

    -- NOTE: animation disabled due to ZombieTurnAlerted always forcing destruction
    -- NOTE: still forces destruction in B42
    -- TODO: see if playing animations on demand is possible for zombies
    --self._ref:setTurnAlertedValues(pathToPos.x, pathToPos.y)

    -- determine whether to be destructive or not
    isDestructive = false
    if not skipDestruction then
        if moveType ~= "Explore" then
            local destructMode = WZSandboxVars:getZ(moveType .. "DestructiveValue", inHorde)
            local indoorThump = destructMode == 2 and not self:isOutside()
            self._ref:getModData().wzThumpIndoors = indoorThump or nil
            isDestructive = indoorThump or destructMode == 1
        else
            isDestructive = WZSandboxVars:get(WZ_SHARED, "ExploreDestructive")
        end
    end

    if isDestructive then self._ref:pathToSound(pathToPos.x, pathToPos.y, pathToPos.z)
    else self._ref:pathToLocation(pathToPos.x, pathToPos.y, pathToPos.z) end

    local pathFind = WZSandboxVars:get(WZ_SHARED, "ForcePathfind")
    if forcePathfind or pathFind == 3 or (pathFind == 2 and not self:isOutside()) then
        self._ref:setVariable("bPathfind", true)
    end

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

    square = zombie:getSquare()
    if square ~= nil and square:isOutside() then
      local state = zombie:getCurrentStateName():sub(1, 5)
        if state == "WalkT" or state == "PathF" or state == "Climb" then
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
    -- NOTE: this is not a vanilla SPEED_*
    if self._ref:isCrawling() then return 5 end
    return self._ref:getSpeedType()
end

---@return boolean
function WZZombieBase:isSprinter()
    return self:getSpeed() == 1
end

---------------
-- Cognition --
---------------

local cognitionIdx ---@type integer?
local cognitionError = false

---@return boolean
function WZZombieBase:isSmart()
    -- with reflection being disabled in B42.15, need to test for the existence of Reflection Enabler
    -- if it doesn't exist, just assume everything is dumb
    if not WZUtility:isReflectionEnabled() then return false end

    local fieldVal
    cognitionIdx, cognitionError, fieldVal = WZUtility:getClassFieldVal(
        cognitionIdx,
        cognitionError,
        "Wandering Zombies: cognitionIdx == nil",
        0,
        self._ref,
        "public int zombie.characters.IsoZombie.cognition"
    )

    return fieldVal == 1
end

--------------------------
-- Building Exploration --
--------------------------

---@return boolean
function WZZombieBase:getExplorePosition()
    if self._exploreRef == nil then return false end

    -- stop exploring when limit has been reached
    if self._exploreCount == 0 then
        self._lastExploredRoom = nil
        return false
    end

    local targetRoom
    if self._lastExploredRoom ~= nil then
        square = self._ref:getSquare()
        if square ~= nil then
            local room = square:getRoom()
            if room ~= nil and self._lastExploredRoom ~= room then targetRoom = room end
        end
    end

    -- pick a random room
    targetRoom = targetRoom or self._exploreRef:getRandomRoom()
    if targetRoom == nil then
        self._exploreCount = 0
        self._lastExploredRoom = nil
        return false
    end

    square = targetRoom:getRandomSquare()
    if square == nil or not square:isSolidFloor() then
        self._exploreCount = 0
        self._lastExploredRoom = nil
        return false
    end

    self:pathTo(WZVector:new(square), "Explore", false, true)
    self._exploreCount = self._exploreCount - 1
    self._lastExploredRoom = targetRoom
    return true
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
