if isServer() then return end

local rx, ry

---@class WZVector
---@field __wzVector boolean
---@field x number
---@field y number
---@field z number
WZVector = { __wzVector = true }

---@param vec WZVector
---@return self
function WZVector:add(vec)
    self.x = self.x + vec.x
    self.y = self.y + vec.y

    return self
end

---@param start integer
---@param range integer
---@return WZVector
function WZVector:addRand(start, range)
    rx = ZombRand(start, range)
    ry = ZombRand(start, range)

    if ZombRand(2) == 0 then rx = -rx end
    if ZombRand(2) == 0 then ry = -ry end

    self.x = self.x + rx
    self.y = self.y + ry
    return self
end

---@param obj WZVector|table|zombie.iso.IsoMovingObject
---@return WZVector
function WZVector:sub(obj)
    local vec = obj
    if not obj.__wzVector then vec = WZVector:new(obj) end

    self.x = self.x - vec.x
    self.y = self.y - vec.y
    return self
end

---@param amount number
---@return self
function WZVector:mult(amount)
    self.x = self.x * amount
    self.y = self.y * amount
    return self
end

---@return number
function WZVector:mag()
    return math.sqrt((self.x * self.x) + (self.y * self.y))
end

---@return WZVector
function WZVector:normal()
    local wzVec = self:copy()
    local mag = self:mag()

    wzVec.x = wzVec.x / mag
    wzVec.y = wzVec.y / mag
    return wzVec
end

---@return self
function WZVector:normalise()
    local mag = self:mag()
    self.x = self.x / mag
    self.y = self.y / mag

    return self
end

---@return WZVector
function WZVector:reverse()
    self.x = -self.x
    self.y = -self.y
    return self
end

---@return number
function WZVector:dot(vec)
    return (self.x * vec.x) + (self.y * vec.y)
end

---@return number
function WZVector:dotOrigin(origin, vec)
    return self:copy():sub(origin):normalise():dot(vec:copy():sub(origin):normalise())
end

---@param dir WZVector
---@return number
function WZVector:cross2d(dir)
    return self.x * dir.y - self.y * dir.x
end

---@param dir WZVector
---@param otherVec WZVector
---@return boolean
function WZVector:isSameSide(dir, otherVec)
    local aCross = self:cross2d(dir) < 0
    local bCross = otherVec:cross2d(dir) < 0
    return aCross == bCross
end

---@param point WZVector
---@param angle integer
function WZVector:rotateAt(point, angle)
    local rads = math.rad(angle)

    local x = math.cos(rads) * (self.x - point.x) - math.sin(rads) * (self.y - point.y) + point.x
    local y = math.sin(rads) * (self.x - point.x) + math.cos(rads) * (self.y - point.y) + point.y

    self.x = x
    self.y = y
end

---@param obj WZVector|zombie.iso.IsoObject|zombie.iso.IsoGridSquare
---@return number
function WZVector:distanceTo(obj)
    if obj.__wzVector then return self:copy():sub(obj --[[@as WZVector]]):mag() end
    return self:copy():sub(WZVector:new(obj)):mag()
end

---@param normalVec WZVector
---@param dist number
---@return WZVector
function WZVector:moveTo(normalVec, dist)
    return self:add(normalVec:mult(dist))
end

---@return WZVector
function WZVector:floor()
    self.x = math.floor(self.x)
    self.y = math.floor(self.y)
    if self.z ~= nil then self.z = math.floor(self.z) end
    return self
end

---@param obj table|zombie.iso.IsoObject|zombie.iso.IsoGridSquare|zombie.characters.IsoGameCharacter.Location|zombie.iso.Vector2
---@param floor boolean?
---@return WZVector
function WZVector:new(obj, floor)
    local wzVec = {}
    setmetatable(wzVec, self)
    self.__index = self

    if type(obj) == "table" then
        wzVec.x = obj.x
        wzVec.y = obj.y
        wzVec.z = obj.z
    elseif instanceof(obj, "IsoObject") or instanceof(obj, "IsoGridSquare") or instanceof(obj, "IsoGameCharacter$Location") then
        ---@cast obj zombie.iso.IsoObject
        wzVec.x = obj:getX()
        wzVec.y = obj:getY()
        wzVec.z = obj:getZ()
    elseif instanceof(obj, "Vector2") then
        ---@cast obj zombie.iso.Vector2
        wzVec.x = obj:getX()
        wzVec.y = obj:getY()
    end

    if floor then
        wzVec.x = math.floor(wzVec.x)
        wzVec.y = math.floor(wzVec.y)
        if wzVec.z ~= nil then wzVec.z = math.floor(wzVec.z) end
    end

    return wzVec
end

---@return WZVector
function WZVector:blank()
    local wzVec = {}
    setmetatable(wzVec, self)
    self.__index = self
    return wzVec
end

---@param vec WZVector?
---@return WZVector
function WZVector:copy(vec)
    local wzVec = {}
    setmetatable(wzVec, self)
    self.__index = self

    if vec ~= nil then
        wzVec.x = vec.x
        wzVec.y = vec.y
        wzVec.z = vec.z
    else
        wzVec.x = self.x
        wzVec.y = self.y
        wzVec.z = self.z
    end

    return wzVec
end

---@param obj table|zombie.iso.IsoMovingObject|zombie.iso.Vector2
---@return WZVector
function WZVector:update(obj)
    if type(obj) == "table" then
        self.x = obj.x
        self.y = obj.y
        self.z = obj.z
    elseif instanceof(obj, "Vector2") then
        self.x = obj:getX()
        self.y = obj:getY()
        self.z = nil
    else
        ---@cast obj zombie.iso.IsoMovingObject
        self.x = obj:getX()
        self.y = obj:getY()
        self.z = obj:getZ()
    end

    return self
end

---@param vec WZVector
---@return boolean
function WZVector:equals(vec, tolerance)
    if vec == nil then return false end
    if tolerance ~= nil then
        return math.abs(self.x - vec.x) + math.abs(self.y - vec.y) + math.abs(self.z - vec.z) < tolerance
    end

    return self.x == vec.x and self.y == vec.y and self.z == vec.z
end

---@return string
function WZVector:tostring()
    return "x: " .. tostring(self.x) .. ", y: " .. tostring(self.y) .. ", z: " .. tostring(self.z)
end
