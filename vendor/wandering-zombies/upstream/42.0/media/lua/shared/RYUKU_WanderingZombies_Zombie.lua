if isServer() then return end
require("RYUKU_WanderingZombies_Horde")

local inHorde
local reusedVector = WZVector:blank()

------------------
-- WZMoveTarget --
------------------

---@class WZMoveTarget
---@field private _ref WZZombie
---@field private _target zombie.characters.IsoGameCharacter
---@field private _active boolean
---@field private _interrupt function
---@field private _distance function
WZMoveTarget = {}

---@param ref WZZombie
---@return WZMoveTarget
function WZMoveTarget:new(ref)
    local obj = {}
    setmetatable(obj, self)
    self.__index = self

    obj._ref = ref
    return obj
end

---@param isoGameCharacter zombie.characters.IsoGameCharacter
---@param moveType string
function WZMoveTarget:set(isoGameCharacter, moveType)
    self._target = isoGameCharacter
    self._active = true
    if moveType == "Flee" then
        self._interrupt = self.fleeInterrupt
        self._distance = self.fleeDistance
    else
        self._interrupt = self.homingInterrupt
        self._distance = self.homingDistance
    end
end

---@return boolean
function WZMoveTarget:isActive()
    return self._active
end

function WZMoveTarget:setInactive()
    self._active = false
end

---@return boolean
function WZMoveTarget:shouldInterrupt()
    return self:_interrupt(inHorde) and self:_distance(inHorde)
end

---@return boolean
function WZMoveTarget:fleeInterrupt()
    return WZSandboxVars:getZ("FleeRadiusInterrupt", inHorde)
end

---@return boolean
function WZMoveTarget:homingInterrupt()
    return WZSandboxVars:getZ("HomingRadiusInterrupt", inHorde)
end

---@return boolean
function WZMoveTarget:fleeDistance()
    return self._ref:distanceTo(self._target) > WZSandboxVars:getZ("FleeRadius", inHorde)
end

---@return boolean
function WZMoveTarget:homingDistance()
    return self._ref:distanceTo(self._target) < WZSandboxVars:getZ("HomingRadius", inHorde)
end

--------------
-- WZZombie --
--------------

---@class WZZombie: WZHorde
---@field private _closestPlayer zombie.characters.IsoPlayer?
---@field private _closestPlayerIdx integer?
---@field private _closestAgedPlayer zombie.characters.IsoPlayer?
---@field private _closestAgedPlayerIdx integer?
---@field private _nextPlayerIdx integer
---@field private _moveTarget WZMoveTarget
---@field private _soundTarget WZVector|nil
WZZombie = WZHorde:derive()

-----------------
-- Constructor --
-----------------

---@param isoZombie zombie.characters.IsoZombie
---@return WZZombie
function WZZombie:new(isoZombie)
    local obj = WZHorde:new(isoZombie)
    setmetatable(obj, self)
    self.__index = self

    ---@cast obj WZZombie
    obj._nextPlayerIdx = 0
    obj._moveTarget = WZMoveTarget:new(obj)
    return obj
end

-----------
-- Reset --
-----------

---@return boolean
function WZZombie:reset()
    WZHorde.reset(self)

    self._playerCacheTime = nil
    self._closestPlayer = nil
    self._closestAgedPlayer = nil
    self._moveTarget = nil
    self._soundTarget = nil
    return false
end

------------
-- Update --
------------

local player
local movePos = WZVector:blank() -- reused WZVector to combat garbage collection
local moveType = "Wander"
local pathTarget
local wzMoveTarget

---@return boolean?
function WZZombie:update()
    local result = WZHorde.update(self)
    if result ~= true then return result end

    inHorde = self:isInHorde()
    wzMoveTarget = self._moveTarget
    self:updatePlayers()
    if self:hasTarget() or self:hasSoundTarget() then
        wzMoveTarget:setInactive()
        self:updateMoveCooldown(inHorde)
        return true
    end

    -- NOTE: zombies and walking around fences... don't like it
    -- TODO: (maybe, big task) find a way to implement my own pathfinding algorithm (HPA* would be most suitable)
    if self:isMoving() then
        if WZSandboxVars:get(WZ_SHARED, "TryStopVirtual") then
            -- NOTE:
            -- tsv ignores sprinters due to the possibility of them keeping up with the player
            -- this only checks the IsoZombie.speedType which is not a perfect solution
            -- mods may alter the speed of animations and not apply the IsoZombie.speedType to match
            player = getPlayer()
            if not player:isDead() and not self:isSprinter() then
                -- TODO: find a way to scale this based on the size of the cell, which changes with resolution
                local maxDist = 85
                movePos:update(self._position)
                reusedVector:update(player)

                -- check min/max x/y to see if zombie falls outside the box
                if movePos.x < reusedVector.x - maxDist
                    or movePos.x > reusedVector.x + maxDist
                    or movePos.y < reusedVector.y - maxDist
                    or movePos.y > reusedVector.y + maxDist
                then
                    -- if path is towards the player, do nothing
                    -- otherwise tell the zombie to move a short distance in a random direction towards the player
                    pathTarget = self:getPathTarget()
                    if pathTarget:dotOrigin(movePos, reusedVector) < 0.5 then
                        wzMoveTarget:setInactive()
                        movePos:moveTo(reusedVector:sub(movePos):normalise(), 7)
                        movePos:rotateAt(self._position, ZombRand(-40, 41))
                        self:pathTo(movePos, "Wander", inHorde)
                    end
                end
            end
        end

        -- WZ will not update the move cooldown when:
        --      the current state is WalkTowardState
        --      the distance to pathTarget is within the expected distance for vanilla wandering (Rand.Next(8) - 4)
        -- this is due to the way the game does vanilla wandering, and the way the zombie pathfinding works
        if self._ref:getCurrentStateName() == "WalkTowardState"
            and self:distanceTo(self:getPathTarget()) < 6
        then
            return true
        end

        -- if zombie is homing/fleeing, interrupt movement if necessary
        if wzMoveTarget:isActive() and wzMoveTarget:shouldInterrupt() then
            wzMoveTarget:setInactive()
            self._ref:setVariable("bPathfind", false)
            self._ref:setVariable("bMoving", false)
            self:updateMoveCooldown(inHorde)
            return true
        end

        self:updateMoveCooldown(inHorde)
        return true
    elseif self:isAlerted() then
        -- avoid interrupting pathfinding in progress
        self:updateMoveCooldown(inHorde)
        return true
    end

    -- clear homing/flee targets
    wzMoveTarget:setInactive()

    -- do not continue if zombie is not ready to be moved
    if not self:isMoveCooldownExpired() then return true end
    self:updateMoveCooldown(inHorde)

    if self:getMovePosition() then self:pathTo(movePos, moveType, inHorde) end
    return true
end

---------------------
-- Closest Players --
---------------------

function WZZombie:updatePlayers()
    if not isClient() and not isCoopHost() then return end

    -- NOTE: this is less accurate then the previous solution, but, should be significantly more performance friendly
    -- verify current players are still valid
    local players = IsoPlayer:getPlayers()
    local playerCount = players:size()
    local closestPlayer = self._closestPlayerIdx ~= nil
        and self._closestPlayerIdx < playerCount
        and players:get(self._closestPlayerIdx) --[[@as false|zombie.characters.IsoPlayer?]]

     local closestAgedPlayer = self._closestAgedPlayerIdx ~= nil
        and self._closestAgedPlayerIdx < playerCount
        and players:get(self._closestAgedPlayerIdx) --[[@as false|zombie.characters.IsoPlayer?]]

    if not closestPlayer or closestPlayer ~= self._closestPlayer or closestPlayer:isDead() then
        self._closestPlayer = nil
        self._closestPlayerIdx = nil
        closestPlayer = nil
    end

    if not closestAgedPlayer or closestAgedPlayer ~= self._closestAgedPlayer or closestAgedPlayer:isDead() then
        self._closestAgedPlayer = nil
        self._closestAgedPlayerIdx = nil
        closestAgedPlayer = nil
    end

    if playerCount == 0 then return end

    -- check next player
    local idx = self._nextPlayerIdx
    if idx >= playerCount then idx = 0 end

    player = players:get(idx) --[[@as zombie.characters.IsoPlayer?]]
    if player ~= nil and not player:isDead() then
        local dist = self:distanceTo(player)
        if dist < 300 then
            if closestPlayer == nil or self:distanceTo(closestPlayer) > dist then
                self._closestPlayer = player
                self._closestPlayerIdx = idx
            end

            if player:getHoursSurvived() >= WZSandboxVars:get(WZ_SHARED, "HoursSurvived")
                and (closestAgedPlayer == nil or self:distanceTo(closestAgedPlayer) > dist)
            then
                self._closestAgedPlayer = player
                self._closestAgedPlayerIdx = idx
            end
        end
    end

    self._nextPlayerIdx = idx + 1
end

---@return zombie.characters.IsoPlayer?
function WZZombie:getClosestPlayer()
    if isClient() or isCoopHost() then return self._closestPlayer end
    return getPlayer()
end

---@return zombie.characters.IsoPlayer?
function WZZombie:getClosestAgedPlayer()
    if isClient() or isCoopHost() then return self._closestAgedPlayer end
    return (getPlayer():getHoursSurvived() >= WZSandboxVars:get(WZ_SHARED, "HoursSurvived") and getPlayer()) or nil
end

-----------
-- Sound --
-----------

local bigSoundIdx ---@type integer|nil
local bigSoundError = false

---@param isoZombie zombie.characters.IsoZombie
---@return zombie.WorldSoundManager.WorldSound?
local function getBigSound(isoZombie)
    local sound = getWorldSoundManager():getBiggestSoundZomb(
        isoZombie:getX(), isoZombie:getY(), isoZombie:getZ(), true, isoZombie
    )

    if bigSoundIdx == nil then
        if not bigSoundError then
            bigSoundIdx = WZUtility:getClassFieldIdx(sound,
                "public zombie.WorldSoundManager$WorldSound zombie.WorldSoundManager$ResultBiggestSound.sound"
            )

            if bigSoundIdx == nil then
                getPlayer():addLineChatElement("Wandering Zombies: bigSoundIdx == nil")
                bigSoundError = true
                return nil
            end
        else
            return nil
        end
    end

    return WZUtility:getClassFieldVal(sound, bigSoundIdx)
end

local soundXIdx --@type integer?
local soundYIdx --@type integer?
local soundZIdx --@type integer?
local soundError = false

---@param worldSound zombie.WorldSoundManager.WorldSound?
---@return WZVector?
local function getSoundVec(worldSound)
    if worldSound == nil then return nil end
    if soundXIdx == nil then
        if not soundError then
            soundXIdx = WZUtility:getClassFieldIdx(worldSound, "public int zombie.WorldSoundManager$WorldSound.x")
            soundYIdx = WZUtility:getClassFieldIdx(worldSound, "public int zombie.WorldSoundManager$WorldSound.y")
            soundZIdx = WZUtility:getClassFieldIdx(worldSound, "public int zombie.WorldSoundManager$WorldSound.z")
            if soundXIdx == nil or soundYIdx == nil or soundZIdx == nil then
                getPlayer():addLineChatElement("Wandering Zombies: (soundXIdx || soundYIdx || soundZIdx) == nil")
                soundError = true
                return nil
            end
        else
            return nil
        end
    end

    return WZVector:new({
        x = WZUtility:getClassFieldVal(worldSound, soundXIdx --[[@as integer]]),
        y = WZUtility:getClassFieldVal(worldSound, soundYIdx --[[@as integer]]),
        z = WZUtility:getClassFieldVal(worldSound, soundZIdx --[[@as integer]])
    })
end

---@private
---@return boolean
function WZZombie:hasSoundTarget()
    -- TODO:
    -- attract?
    -- randomise the end of the path? would require finding out what the source of sound is
    local soundPos = getSoundVec(getWorldSoundManager():getSoundZomb(self._ref))
        or getSoundVec(getBigSound(self._ref))
        or (self._ref:getLastHeardSound():getX() > -1 and WZVector:new(self._ref:getLastHeardSound()))
        or self._soundTarget

    if soundPos == nil then return false end

    -- verify zombie path is near soundPos
    pathTarget = self:getPathTarget()
    if self:distanceTo(pathTarget) > 1 then
        if soundPos:dotOrigin(self._position, pathTarget) >= 0.6 then
            if not pathTarget:equals(self._soundTarget) then self._soundTarget = pathTarget end
            return true
        end
    elseif soundPos:equals(self._soundTarget) then
        self._soundTarget = nil
        return false
    end

    if self._soundTarget == nil then self._ref:setTurnAlertedValues(soundPos.x, soundPos.y) end

    self._soundTarget = soundPos
    self._ref:setLastHeardSound(soundPos.x, soundPos.y, soundPos.z)
    self:pathTo(soundPos, "Wander", self:isInHorde())
    return true
end

-------------
-- Pathing --
-------------

---@param isoPlayer zombie.characters.IsoPlayer
---@param dist number
---@return boolean
function WZZombie:pathToPlayer(isoPlayer, dist)
    movePos:update(self._position)
    return self:pathTo(movePos:moveTo(
            reusedVector:update(isoPlayer):sub(movePos):normalise(), dist
        ), "Homing", self:isInHorde()
    )
end

-------------
-- Chances --
-------------

---@return number
function WZZombie:getFleeChance()
    if not WZSandboxVars:isTimeNow("Flee", self:isInHorde()) then return 0 end

    player = self:getClosestPlayer()
    if player == nil or self:distanceTo(player) > WZSandboxVars:getZ("FleeRadius", self:isInHorde()) then
        return 0
    end

    return WZSandboxVars:getZ("FleeChance", self:isInHorde())
end

---@return number
function WZZombie:getHomingChance()
    if self:getClosestAgedPlayer() == nil then return 0 end
    if not WZSandboxVars:isTimeNow("Homing", self:isInHorde()) then return 0 end

    player = self:getClosestAgedPlayer()
    if player == nil or self:distanceTo(player) < WZSandboxVars:getZ("HomingRadius", self:isInHorde()) then
        return 0
    end

    return WZSandboxVars:getZ("HomingChance", self:isInHorde())
end

---@return number
function WZZombie:getWanderChance()
    if not WZSandboxVars:isTimeNow("Wander", self:isInHorde()) then return 0 end
    return WZSandboxVars:getZ("WanderChance", self:isInHorde())
end

-------------------
-- Move Position --
-------------------

---@return boolean
function WZZombie:getMovePosition()
    local maxDist = WZSandboxVars:getZ("MaxTravel", self:isInHorde()) + 1
    local moveDist = ZombRand(7, maxDist)

    if ZombRand(100) < self:getFleeChance() then
        moveType = "Flee"
        movePos:update(self._position)
        movePos:moveTo(reusedVector:update(self._position):sub(player):normalise(), moveDist)
        self._moveTarget:set(player, "Flee")
        return true
    elseif ZombRand(100) < self:getHomingChance() then
        moveType = "Homing"
        moveDist = math.min(moveDist,
            1 + (self:distanceTo(player) - WZSandboxVars:getZ("HomingRadius", self:isInHorde()))
        )

        self._moveTarget:set(player, "Homing")
        self:pathToPlayer(player, moveDist)
    elseif ZombRand(100) < self:getWanderChance() then
        moveType = "Wander"
        movePos:update(self._position)
        if WZSandboxVars:get(WZ_SHARED, "WanderForwards") then
            -- selects a random location within +/- 45 degress of the zombie's facing direction
            reusedVector:update(self._ref:getForwardDirection()):normalise()
            movePos:add(reusedVector:mult(moveDist))
            movePos:rotateAt(self._position, ZombRand(-45, 46))
        else
            movePos:addRand(7, maxDist)
        end

        return true
    end

    return false
end
