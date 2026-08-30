if isServer() then return end

require("RYUKU_WanderingZombies_ZombieBase")
require("RYUKU_WanderingZombies_LinkedList")
require("RYUKU_WanderingZombies_IndexedDictionary")


---------------------
-- Horde Variables --
---------------------

---@class WZHordeVars
---@field leader WZHorde
---@field mergeCooldown integer
WZHordeVars = {}

---@param leader WZHorde
---@return WZHordeVars
function WZHordeVars:new(leader)
    local obj = {}
    setmetatable(obj, self)
    self.__index = self

    obj.leader = leader
    obj.mergeCooldown = 0
    return obj
end

-----------
-- Horde --
-----------

---@class WZHorde: WZZombieBase
---@field private _followers WZLinkedList
---@field private _followerLink WZLinkedListLink?
---@field private _followerMoveRoll integer
---@field private _hordeVars WZHordeVars
WZHorde = WZZombieBase:derive()

-----------------
-- Inheritance --
-----------------

---@protected
---@return WZHorde
function WZHorde:derive()
    local obj = {}
    setmetatable(obj, self)
    self.__index = self

    return obj
end

----------------
-- Initialise --
----------------

---@protected
function WZHorde:init()
    WZZombieBase.init(self)

    self._followers = WZLinkedList:new("followers")
    self._followerMoveRoll = 3
end

-----------
-- Reset --
-----------

---@protected
function WZHorde:reset()
    if self:isInHorde() then self:resetHorde() end

    WZZombieBase.reset(self)
end

---@protected
function WZHorde:resetHorde()
    if self:isLeader() then
        local wzHorde = self._followers:next():getRef() --[[@as WZHorde]]
        if self._followers:size() > 1 then wzHorde:changeLeader(self._followers)
        else self:removeFollower(wzHorde) end

        self._followers = WZLinkedList:new("followers")
        self._hordeVars = nil
    elseif self:isFollower() then
        self._hordeVars.leader:removeFollower(self)
    end
end

------------
-- Update --
------------

local movePos = WZVector:blank() -- reused WZVector to combat garbage collection

---@protected
---@return boolean?
function WZHorde:update()
    local result = WZZombieBase.update(self)
    if result ~= true then return result end

    -- don't need to do anything if not in a horde
    -- reset if horde option flipped
    if not self:isInHorde() then return true
    elseif not WZSandboxVars:get(WZ_HORDE, "Hordes") then
        self:resetHorde()
        return false
    end

    -- ensure zombie is allowed to be in a horde
    if not self:isValidHordeZombie() then
        self:resetHorde()
        self:updateMoveCooldown(false)
        return false
    end

    local hordeVars = self._hordeVars
    if self:isFollower() then
        -- speed / distance validation
        if (WZSandboxVars:get(WZ_HORDE, "GroupBySpeed") and hordeVars.leader:getSpeed() ~= self:getSpeed())
            or self:distanceTo(hordeVars.leader) > self:getHordeRadius() + WZSandboxVars:get(WZ_HORDE, "LeaveDistance")
        then
            self:resetHorde()
            self:updateMoveCooldown(false)
            return false
        end

        -- reactive movement / idle wandering
        if self:isMoveCooldownExpired() then
            local leader = hordeVars.leader
            if (not self:isAlerted() and not self:isMoving())
                or (not leader:isMoving() and leader:distanceTo(self:getPathTarget()) > self:getHordeRadius())
            then
                if RYRNG:mod(self._followerMoveRoll) == 0 then
                    movePos:update(leader._position)
                    if leader:isMoving() then movePos = leader:getPathTarget()
                    elseif leader:isAlerted() then
                        self:updateMoveCooldown(true)
                        return false
                    end

                    self._followerMoveRoll = math.min(3, self._followerMoveRoll + 1)
                    movePos:addRand(0, self:getHordeRadius())
                    self:pathTo(movePos, "Wander", true)
                else
                    self._followerMoveRoll = math.max(1, self._followerMoveRoll - 1)
                end
            end

            self:updateMoveCooldown(true)
        end

        return false
    end

    return true
end


------------
-- Leader --
------------

---@private
---@return boolean
function WZHorde:swapLeader()
    if self._hordeVars ~= nil then
        local oldLeader = self._hordeVars.leader
        if oldLeader._followers:size() > 1 then
            local newLeader = oldLeader._followers:first():getRef() --[[@as WZHorde]]
            newLeader._followers = oldLeader._followers
            newLeader._followers:remove(newLeader._followerLink)
            newLeader._followerLink = nil

            oldLeader._followers = WZLinkedList:new("followers")
            self._hordeVars.leader = newLeader
            return true
        elseif oldLeader._followers:size() == 1 then
            oldLeader:removeFollower(oldLeader._followers:first():getRef() --[[@as WZHorde]])
        end
    end

    return false
end

---@private
---@param followers WZLinkedList
function WZHorde:changeLeader(followers)
    followers:remove(self._followerLink)
    self._hordeVars.leader = self
    self._followerLink = nil
    self._followers = followers
end

---@return boolean
function WZHorde:isLeader()
    return self._hordeVars ~= nil and self._hordeVars.leader == self
end

--------------
-- Follower --
--------------

---@return boolean
function WZHorde:isFollower()
    return self._followerLink ~= nil
end

---@param wzHorde WZHorde
function WZHorde:addFollower(wzHorde)
    local leader = self
    local hordeVars
    if self:isFollower() then leader = self._hordeVars.leader end
    if leader._followers:size() == 0 then
        WZSandboxVars:updateHordeCount(1)

        hordeVars = WZHordeVars:new(self)
        leader._hordeVars = hordeVars
    else
        hordeVars = leader._hordeVars
    end

    wzHorde._followerLink = leader._followers:push(wzHorde)
    wzHorde._hordeVars = hordeVars
    wzHorde:updateMoveCooldown(true)
end

---@param wzHorde WZHorde
function WZHorde:removeFollower(wzHorde)
    local leader = self
    if self:isFollower() then leader = self._hordeVars.leader end

    leader._followers:remove(wzHorde._followerLink)
    if leader._followers:size() == 0 then
        leader._hordeVars = nil
        WZSandboxVars:updateHordeCount(-1)
    end

    wzHorde._followerLink = nil
    wzHorde._hordeVars = nil
end

-----------
-- Merge --
-----------

---@param wzHorde WZHorde
function WZHorde:mergeHordeWith(wzHorde)
    local targetLeader = wzHorde
    if not wzHorde:isLeader() then targetLeader = wzHorde._hordeVars.leader end

    -- prevent merge if leader is identical
    local fromLeader = self
    if not self:isLeader() then fromLeader = self._hordeVars.leader end
    if fromLeader == targetLeader then return false end

    -- prevent merging if either horde is on cooldown
    local targetVars = targetLeader._hordeVars
    local fromVars = fromLeader._hordeVars
    local time = getTimeInMillis()
    if time < targetVars.mergeCooldown or time < fromVars.mergeCooldown then return false end
    targetVars.mergeCooldown = time + WZSandboxVars:get(WZ_HORDE, "MergeCooldown") * (targetLeader:getHordeSize())

    -- new possible horde radius
    -- zombies outside this radius won't merge
    local maxDistance = WZHorde:getHordeRadius(targetLeader:getHordeSize() + fromLeader:getHordeSize())
        + WZSandboxVars:get(WZ_HORDE, "LeaveDistance")

    for follower in fromLeader._followers:iterRef() do
        ---@cast follower WZHorde
        if follower:distanceTo(targetLeader) <= maxDistance then
            fromLeader:removeFollower(follower)
            targetLeader:addFollower(follower)
        end
    end

    if fromLeader:distanceTo(targetLeader) <= maxDistance then
        fromLeader:swapLeader()
        targetLeader:addFollower(fromLeader)
    end

    return true
end

------------
-- Status --
------------

---@return boolean
function WZHorde:isInHorde()
    return self._hordeVars ~= nil
end

----------
-- Size --
----------

---@return integer
function WZHorde:getHordeSize()
    if not self:isFollower() then return 1 + self._followers:size() end
    return self._hordeVars.leader:getHordeSize()
end

------------
-- Radius --
------------

---@param size integer?
---@return number
function WZHorde:getHordeRadius(size)
    -- padding of 4 units to give some initial wandering room
    return 4 + math.sqrt(size or self:getHordeSize() / math.pi)
end

-------------
-- Pathing --
-------------

---@protected
---@param inHorde boolean
function WZHorde:updateMoveCooldown(inHorde)
    if self:isFollower() then
        if self._exploreCount == 0 then self._moveCooldown = getTimeInMillis() + 900
        else WZZombieBase.updateMoveCooldown(self, false) end

        return
    end

    WZZombieBase.updateMoveCooldown(self, inHorde)
    if inHorde then
        self._moveCooldown = self._moveCooldown
            + WZSandboxVars:getZ("MoveCooldownHordeSize", inHorde) * self:getHordeSize()
    end
end

------------------------
-- Valid Horde Zombie --
------------------------

---@return boolean
function WZHorde:isValidHordeZombie()
    return self._ref:getThumpTarget() == nil
        and self:isOutside()
        and WZSandboxVars:isSpeedAllowed(self:getSpeed())
end
