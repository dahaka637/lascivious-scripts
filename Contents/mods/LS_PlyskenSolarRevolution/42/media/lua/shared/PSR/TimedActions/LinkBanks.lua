if isServer() then
    if not ISBaseTimedAction then
        ISBaseTimedAction = {}
        ISBaseTimedAction.__index = ISBaseTimedAction
        function ISBaseTimedAction:derive(name)
            local cls = {}
            cls.__index = cls
            setmetatable(cls, self)
            self.__index = self
            _G[name] = cls
            return cls
        end
        function ISBaseTimedAction:perform() self:complete() return true end
        function ISBaseTimedAction:isValid() return true end
        function ISBaseTimedAction:waitToStart() return false end
        function ISBaseTimedAction:start() end
        function ISBaseTimedAction:update() end
        function ISBaseTimedAction:stop() end
        function ISBaseTimedAction:complete() end
    end
else
    require "TimedActions/ISBaseTimedAction"
end
local PSR = require "PSR/Utilities"

local LinkBanks = ISBaseTimedAction:derive("PSR_LinkBanks")
PSR_LinkBanks = LinkBanks

-- 🔴 CORRIGÉ LE 2026-08-16 — même famille que `LinkComputer` (voir son en-tête pour la mesure au
--    bytecode et la contrainte « nom du paramètre = nom du champ »). Ici DEUX objets étaient
--    déréférencés, dont `targetIso` qui est presque toujours sur une autre case — donc le plus
--    exposé au `null` de `NetObject`.
function LinkBanks:new(character, bankIso, targetIso, bx, by, bz, tx, ty, tz)
    local o = {}
    setmetatable(o, self)
    self.__index = self
    o.character  = character
    o.bankIso    = bankIso
    o.targetIso  = targetIso
    o.bx = bx
    o.by = by
    o.bz = bz
    o.tx = tx
    o.ty = ty
    o.tz = tz
    o.stopOnWalk = true
    o.stopOnRun  = true
    o.stopOnAim  = false
    o.maxTime    = 50
    return o
end

function LinkBanks:isValid()
    return true
end

function LinkBanks:start()
    if isServer() then return end
    self:setActionAnim("Loot")
    self.character:SetVariable("LootPosition", "Low")
    self.character:reportEvent("EventLootItem")
end

function LinkBanks:waitToStart()
    if isServer() then return false end
    self.character:faceThisObject(self.bankIso)
    return self.character:shouldBeTurning()
end

function LinkBanks:update()
    if isServer() then return end
    self.character:faceThisObject(self.bankIso)
end

function LinkBanks:perform()
    if isServer() then return true end
    ISBaseTimedAction.perform(self)
    return true
end

function LinkBanks:complete()
    -- B42.19 : complete() must return a boolean on dedicated (protectedCallBoolean).
    if not PSR.PBSystem_Server then return true end
    local pbA = PSR.PBSystem_Server:getLuaObjectAt(self.bx, self.by, self.bz)
    local pbB = PSR.PBSystem_Server:getLuaObjectAt(self.tx, self.ty, self.tz)
    if not pbA or not pbB then return true end
    pbA.PSR_linkedBanks = pbA.PSR_linkedBanks or {}
    pbB.PSR_linkedBanks = pbB.PSR_linkedBanks or {}
    for _, link in ipairs(pbA.PSR_linkedBanks) do
        if link.x == self.tx and link.y == self.ty and link.z == self.tz then return true end
    end
    table.insert(pbA.PSR_linkedBanks, { x = self.tx, y = self.ty, z = self.tz })
    table.insert(pbB.PSR_linkedBanks, { x = self.bx, y = self.by, z = self.bz })
    pbA:saveData(true)
    pbB:saveData(true)
    return true
end

PSR.LinkBanks = LinkBanks
