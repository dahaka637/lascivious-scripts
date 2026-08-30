RYRNG = { m = math.floor(2 ^ 31 - 1), a = 16807 }

---@param value integer?
function RYRNG:stir(value)
    value = math.floor(value or 0) % self.m
    self.s = math.floor(((self.s or os.time()) + value) % self.m)
    if self.s <= 0 then self.s = math.floor(self.s + (self.m - 1)) end
end

---@return integer
function RYRNG:next31()
    if not self.init then
        self:stir()
        self.init = true
    end

    self.s = math.floor((self.a * self.s) % self.m)
    return self.s
end

---@return number
function RYRNG:double()
    return self:next31() / self.m
end

---@param min integer
---@param max integer
---@return integer
function RYRNG:range(min, max)
    min = math.floor(min)
    max = math.floor(max)
    return min + self:next31() % (max + 1 - min)
end

---@param value integer
---@return integer
function RYRNG:mod(value)
    return self:next31() % math.floor(value)
end
