if isServer() then return end

----------------------
-- WZLinkedListLink --
----------------------

---@class WZLinkedListLink
---@field private _ref any
---@field private _list WZLinkedList
---@field private _next WZLinkedListLink
---@field private _prev WZLinkedListLink
WZLinkedListLink = {}

---@param ref any
---@param list WZLinkedList
---@return WZLinkedListLink
function WZLinkedListLink:new(ref, list)
    local obj = {}
    setmetatable(obj, self)
    self.__index = self

    obj._ref = ref
    obj._list = list
    return obj
end

---@return any
function WZLinkedListLink:getRef()
    return self._ref
end

---@return WZLinkedList
function WZLinkedListLink:getList()
    return self._list
end

---@param link WZLinkedListLink
function WZLinkedListLink:setNext(link)
    self._next = link
end

---@return WZLinkedListLink
function WZLinkedListLink:getNext()
    return self._next
end

---@param link WZLinkedListLink
function WZLinkedListLink:setPrev(link)
    self._prev = link
end

---@return WZLinkedListLink
function WZLinkedListLink:getPrev()
    return self._prev
end

------------------
-- WZLinkedList --
------------------

---@class WZLinkedList
---@field private _first WZLinkedListLink
---@field private _last WZLinkedListLink
---@field private _current WZLinkedListLink
---@field private _size integer
WZLinkedList = {}

-----------------
-- Constructor --
-----------------

---@param name string name of WZLinkedList for debug usage
---@return WZLinkedList
function WZLinkedList:new(name)
    local wzList = {}
    setmetatable(wzList, self)
    self.__index = self

    wzList._size = 0
    wzList.name = name
    return wzList
end

----------
-- Size --
----------

---@return number
function WZLinkedList:size()
    return self._size
end

-----------------
-- Next / Prev --
-----------------

---@return WZLinkedListLink
function WZLinkedList:next()
    if self._current == nil then
        self._current = self._first
    else
        self._current = self._current:getNext() or self._current
    end

    return self._current
end

---@return WZLinkedListLink
function WZLinkedList:prev()
    if self._current == nil then
        self._current = self._first
    else
        self._current = self._current:getPrev()
    end

    return self._current
end

-------------------
-- Push / Remove --
-------------------

---@param obj any
---@return WZLinkedListLink
function WZLinkedList:push(obj)
    local link = WZLinkedListLink:new(obj, self)
    if self._first == nil then
        self._first = link
        self._last = link
    end

    link:setNext(self._first)
    link:setPrev(self._last)

    if self._size > 0 then
        self._first:setPrev(link)
        self._last:setNext(link)
        self._last = link
    end

    self._size = self._size + 1
    return self._last
end

---@param link WZLinkedListLink
function WZLinkedList:remove(link)
    if self._size > 1 then
        link:getPrev():setNext(link:getNext())
        link:getNext():setPrev(link:getPrev())

        if self._current == link then self._current = link:getPrev() end

        if self._first == link then
            self._first = link:getNext()
        elseif self._last == link then
            self._last = link:getPrev()
        end
    else
        self._first = nil
        self._last = nil
        self._current = nil
    end

    self._size = self._size - 1
end


--------------
-- Iterator --
--------------

function WZLinkedList:iter()
    local x = 0
    local link = self._last
    return function()
        if x < self:size() then
            x = x + 1
            link = link:getNext()
            return link
        end
    end
end

function WZLinkedList:iterRef()
    local x = 0
    local link = self._last
    return function()
        if x < self:size() then
            x = x + 1
            link = link:getNext()
            return link:getRef()
        end
    end
end
