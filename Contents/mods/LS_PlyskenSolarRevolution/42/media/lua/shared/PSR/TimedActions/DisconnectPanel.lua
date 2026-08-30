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
---@class PSR
local PSR = require "PSR/Utilities"

local DisconnectPanel = ISBaseTimedAction:derive("PSR_DisconnectPanel")
PSR_DisconnectPanel = DisconnectPanel

function DisconnectPanel:new(character, panel, luaPb)
    local o = {}
    setmetatable(o, self)
    self.__index = self
    o.character = character
    o.panel = panel
    o.powerbank = luaPb
    o.stopOnWalk = true
    o.stopOnRun = true
    o.stopOnAim = false
    o.maxTime = o:getDuration()
    return o
end

function DisconnectPanel:getDuration()
    if isServer() then return 30 end
    if self.character:isTimedActionInstant() then return 1 end
    -- Half the connect time
    return ((SandboxVars.PSR and SandboxVars.PSR.ConnectPanelMin) or 30) * (1 - 0.095 * (self.character:getPerkLevel(Perks.Electricity) - 3)) * getGameTime():getMinutesPerDay()
end

function DisconnectPanel:isValid()
    if isServer() then return true end
    return self.panel:getObjectIndex() ~= -1
end

function DisconnectPanel:start()
    if isServer() then return end
    self:setActionAnim("Loot")
    self.character:SetVariable("LootPosition", "Low")
    self.character:reportEvent("EventLootItem")
    -- son "GeneratorConnect" retiré (2026-06-19) : bank silencieuse
end

function DisconnectPanel:waitToStart()
    if isServer() then return false end
    self.character:faceThisObject(self.panel)
    return self.character:shouldBeTurning()
end

function DisconnectPanel:update()
    if isServer() then return end
    self.character:faceThisObject(self.panel)
end

function DisconnectPanel:stop()
    if isServer() then ISBaseTimedAction.stop(self) return end
    if self.sound then self.character:stopOrTriggerSound(self.sound) end
    ISBaseTimedAction.stop(self)
end

function DisconnectPanel:perform()
    if isServer() then return true end
    if self.sound then self.character:stopOrTriggerSound(self.sound) end
    ISBaseTimedAction.perform(self)
    return true
end

function DisconnectPanel:complete()
    -- B42.19 : complete() must return a boolean on dedicated (NetTimedAction protectedCallBoolean).
    if not PSR.PBSystem_Server then
        if PSR.PBSystem_Client then
            PSR.PBSystem_Client:sendCommand(self.character, "disconnectPanel", {
                pb = { x = self.powerbank.x, y = self.powerbank.y, z = self.powerbank.z },
                panel = { x = self.panel:getX(), y = self.panel:getY(), z = self.panel:getZ() }
            })
        end
        return true
    end
    -- On a dedicated server the action is reconstructed with self.panel == nil (IsoObject
    -- args aren't serialized; see ConnectPanel). The client branch above already sends the
    -- disconnectPanel command which does the real work from coords, so the server-replication
    -- path must NOT call removePanel(nil) (NPE logged every disconnect). On host self.panel is
    -- valid and PBSystem_Server is set, so removePanel runs here directly (no command sent).
    if self.panel and self.panel.getModData then
        PSR.PBSystem_Server:removePanel(self.panel)
    end
    return true
end

PSR.DisconnectPanel = DisconnectPanel
