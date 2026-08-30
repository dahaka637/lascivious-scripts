---@class WZIndexedDictionary
---@field private _index table
---@field private _dict table
WZIndexedDictionary = {}

function WZIndexedDictionary:new()
    local obj = {}
    setmetatable(obj, self)
    self.__index = self

    obj._index = {}
    obj._dict = {}
    return obj
end

---@return integer
function WZIndexedDictionary:size()
    return #self._index
end

---@param key any
---@param value any
function WZIndexedDictionary:add(key, value)
    local entry = { index = #self._index + 1, key = key, value = value }
    table.insert(self._index, entry)
    self._dict[key] = entry
end

---@param key any
function WZIndexedDictionary:remove(key)
    local entry = self._dict[key]
    if entry == nil then return end
   
    local x = entry.index + 1
    while x <= #self._index do
        self._index[x].index = x - 1
        x = x + 1
    end

    table.remove(self._index, entry.index)
    self._dict[key] = nil
end

function WZIndexedDictionary:clear()
    self._index = {}
    self._dict = {}
end

---@param key any
---@return any
function WZIndexedDictionary:get(key)
    local entry = self._dict[key]
    if entry ~= nil then return entry.value end
    return nil
end

---@param idx integer
---@return any
function WZIndexedDictionary:getAt(idx)
    if idx < 1 or idx > #self._index then return nil end
    return self._index[idx].value
end

---@return any
function WZIndexedDictionary:getRand()
    if #self._index == 0 then return nil end
    local idx = ZombRand(0, #self._index) + 1
    return self._index[idx].value
end

---@param key any
---@return any
function WZIndexedDictionary:getNext(key)
    if self:size() == 1 then return nil end

    local entry = self._dict[key]
    if entry == nil then return nil end

    local idx = entry.index + 1
    if idx > self:size() then idx = 1 end
    return self._index[idx].value
end

---@return function
function WZIndexedDictionary:pairs()
    local entry
    local x = 1
    return function()
        if x > #self._index then return nil, nil end

        entry = self._index[x]
        x = x + 1
        return entry.key, entry.value
    end
end
