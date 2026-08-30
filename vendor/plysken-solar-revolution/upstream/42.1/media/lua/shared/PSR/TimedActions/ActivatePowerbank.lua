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

PSR_ActivatePowerBank = ISBaseTimedAction:derive("PSR_ActivatePowerBank")
local ActivatePowerBank = PSR_ActivatePowerBank

function ActivatePowerBank:new(character, powerbank, activate, pbX, pbY, pbZ)
    local o = {}
    setmetatable(o, self)
    self.__index = self
    o.character  = character
    o.activate   = activate
    o.isoPb      = powerbank
    o.pbX        = pbX
    o.pbY        = pbY
    o.pbZ        = pbZ
    o.stopOnWalk = true
    o.stopOnRun  = true
    o.maxTime    = 40
    if not isServer() then
        if character:isTimedActionInstant() then
            o.maxTime = 1
        else
            o.maxTime = 40 - 3 * character:getPerkLevel(Perks.Electricity)
        end
    end
    return o
end

function ActivatePowerBank:isValid()
    if isServer() then return true end
    return self.isoPb ~= nil and self.isoPb:getObjectIndex() ~= -1
end

function ActivatePowerBank:waitToStart()
    if isServer() then return false end
    return false
end

function ActivatePowerBank:start()
    if isServer() then return end
end

function ActivatePowerBank:update()
    if isServer() then return end
end

function ActivatePowerBank:perform()
    if isServer() then return true end
    ISBaseTimedAction.perform(self)
    return true
end

function ActivatePowerBank:complete()
    if PSR.PBSystem_Server then
        local pb = PSR.PBSystem_Server:getLuaObjectAt(self.pbX, self.pbY, self.pbZ)
        if not pb then return true end
        if self.activate then
            local level = self.character and self.character:getPerkLevel(Perks.Electricity) or 0
            if level < 3 and ZombRand(6 - 2*level) ~= 0 then
                self.activate = false
            end
        end
        -- Sons retirés (2026-06-19) : une battery bank est silencieuse (pas un moteur thermique).
        -- Plus de GeneratorStarting/FailedToStart/Stopping au toggle.
        pb.on = self.activate
        pb.switchchanged = true
        pb:updateDrain()
        pb:updateGenerator()
        pb:saveData(true)
        return true
    end
    -- MP client: server handles state via addGeneratorPos. No client-side activation needed.
    -- B42.19: complete() must return a boolean on dedicated (NetTimedAction protectedCallBoolean).
    return true
end

PSR.ActivatePowerbank = ActivatePowerBank
