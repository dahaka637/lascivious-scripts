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

local UnlinkBanks = ISBaseTimedAction:derive("PSR_UnlinkBanks")
PSR_UnlinkBanks = UnlinkBanks

---@param character IsoPlayer
---@param bankIso IsoObject
---@param targetIso IsoObject|nil  if provided, unlink only this bank; if nil, unlink all
-- 🔴 CORRIGÉ LE 2026-08-16 — même famille que `LinkComputer` (voir son en-tête).
-- 📌 Détail qui rend l'omission plus nette : `targetIso` était DÉJÀ gardé (`targetIso and …`),
--    pas `bankIso`. La moitié du travail était faite. *Une garde posée sur un seul des deux
--    objets prouve qu'on avait vu le risque et qu'on ne l'a pas balayé.*
function UnlinkBanks:new(character, bankIso, targetIso, bx, by, bz, tx, ty, tz)
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
    o.maxTime    = 30
    return o
end

function UnlinkBanks:isValid()
    if isServer() then return true end
    if self.bankIso:getObjectIndex() == -1 then return false end
    if self.targetIso and self.targetIso:getObjectIndex() == -1 then return false end
    return true
end

function UnlinkBanks:start()
    if isServer() then return end
    self:setActionAnim("Loot")
    self.character:SetVariable("LootPosition", "Low")
    self.character:reportEvent("EventLootItem")
end

function UnlinkBanks:waitToStart()
    if isServer() then return false end
    self.character:faceThisObject(self.bankIso)
    return self.character:shouldBeTurning()
end

function UnlinkBanks:update()
    if isServer() then return end
    self.character:faceThisObject(self.bankIso)
end

function UnlinkBanks:perform()
    if isServer() then return true end
    ISBaseTimedAction.perform(self)
    return true
end

function UnlinkBanks:complete()
    -- B42.19 : complete() must return a boolean on dedicated (protectedCallBoolean).
    if not PSR.PBSystem_Server then return true end
    local pbA = PSR.PBSystem_Server:getLuaObjectAt(self.bx, self.by, self.bz)
    if not pbA then return true end
    if self.tx then
        local pbB = PSR.PBSystem_Server:getLuaObjectAt(self.tx, self.ty, self.tz)
        PSR.WorldUtil.removeLinkEntry(pbA, self.tx, self.ty, self.tz)
        pbA:saveData(true)
        if pbB then
            PSR.WorldUtil.removeLinkEntry(pbB, self.bx, self.by, self.bz)
            pbB:saveData(true)
        end
    else
        for _, link in ipairs(pbA.PSR_linkedBanks or {}) do
            local pbB = PSR.PBSystem_Server:getLuaObjectAt(link.x, link.y, link.z)
            if pbB then
                PSR.WorldUtil.removeLinkEntry(pbB, self.bx, self.by, self.bz)
                pbB:saveData(true)
            end
        end
        pbA.PSR_linkedBanks = {}
        pbA:saveData(true)
    end
    return true
end

PSR.UnlinkBanks = UnlinkBanks
