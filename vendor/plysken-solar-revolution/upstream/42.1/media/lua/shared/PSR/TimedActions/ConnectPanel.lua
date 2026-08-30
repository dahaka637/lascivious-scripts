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

local ConnectPanel = ISBaseTimedAction:derive("PSR_ConnectPanel")
PSR_ConnectPanel = ConnectPanel

function ConnectPanel:new(character, panel, luaPb, pbX, pbY, pbZ, panelX, panelY, panelZ, panelSprite)
    local o = {}
    setmetatable(o, self)
    self.__index = self
    o.character = character
    o.panel = panel
    o.powerbank = luaPb
    o.pbX = pbX
    o.pbY = pbY
    o.pbZ = pbZ
    -- MP-safe: panel coords + sprite are passed as PRIMITIVE ARGS by the caller (client-side,
    -- where the panel object is valid). new() must NOT call methods on `panel`: on a dedicated
    -- server the action is reconstructed with panel == nil, so panel:getX() would throw here.
    -- complete() re-resolves the IsoObject from these primitives. See feedback-psr-mp-architecture.
    o.panelX = panelX
    o.panelY = panelY
    o.panelZ = panelZ
    o.panelSprite = panelSprite
    o.stopOnWalk = true
    o.stopOnRun = true
    o.stopOnAim = false
    o.maxTime = o:getDuration()
    return o
end

function ConnectPanel:isValid()
    return true
end

function ConnectPanel:getDuration()
    if isServer() then return 60 end
    if self.character:isTimedActionInstant() then
        return 1
    end
    --base time in minutes at level 3, ~1/3 at level 10
    return ((SandboxVars.PSR and SandboxVars.PSR.ConnectPanelMin) or 30) * (1 - 0.095 * (self.character:getPerkLevel(Perks.Electricity) - 3)) * 2 * getGameTime():getMinutesPerDay()
end

function ConnectPanel:start()
    if isServer() then return end
    self:setActionAnim("Loot")
    self.character:SetVariable("LootPosition", "Low")
    self.character:reportEvent("EventLootItem")
    -- son "GeneratorConnect" retiré (2026-06-19) : bank silencieuse

    local data = self.panel:getModData()
    local prevDelta = math.max(0, math.min(90, data["connectDelta"] or 0))
    self:setCurrentTime(self.maxTime * prevDelta / 100)
    if not isClient() then
        data["connectDelta"] = prevDelta
        PSR.PBSystem_Server:removePanel(self.panel)
        self.panel:transmitModData()
    end
end

function ConnectPanel:waitToStart()
    if isServer() then return false end
    self.character:faceThisObject(self.panel)
    return self.character:shouldBeTurning()
end

function ConnectPanel:update()
    if isServer() then return end
    self.character:faceThisObject(self.panel)
end

function ConnectPanel:stop()
    if isServer() then ISBaseTimedAction.stop(self) return end
    if self.sound then self.character:stopOrTriggerSound(self.sound) end
    local delta = math.floor(self:getJobDelta()*100)
    local data = self.panel:getModData()
    if delta > (data.connectDelta or 0) and self.panel:getObjectIndex() ~= -1 then
        data.connectDelta = delta
    end

    ISBaseTimedAction.stop(self)
end

function ConnectPanel:perform()
    if isServer() then return true end
    if self.sound then self.character:stopOrTriggerSound(self.sound) end
    ISBaseTimedAction.perform(self)
    return true
end

function ConnectPanel:complete()
    -- B42.19 : NetTimedAction calls complete() via protectedCallBoolean and requires a boolean
    -- return on the dedicated server — returning nil throws a NullPointerException. So every
    -- path returns true. See feedback-psr-b42-19-timedaction-complete-boolean.
    if not PSR.PBSystem_Server then return true end
    local panelIso = self.panel
    if not (panelIso and panelIso.getModData) then
        local sq = getSquare(self.panelX, self.panelY, self.panelZ)
        if not sq then return true end
        local objs = sq:getObjects()
        for i = 0, objs:size() - 1 do
            local obj = objs:get(i)
            if obj and obj.getTextureName and obj:getTextureName() == self.panelSprite then
                panelIso = obj
                break
            end
        end
    end
    if not (panelIso and panelIso.getModData) then return true end

    local data = panelIso:getModData()
    data.connectDelta = 100
    -- Unlink from any existing bank before connecting to the new one
    PSR.PBSystem_Server:removePanel(panelIso)
    local pb = PSR.PBSystem_Server:getLuaObjectAt(self.pbX, self.pbY, self.pbZ)
    if pb then
        local psq = panelIso:getSquare()
        local panel, status
        if psq then panel, status = pb:getPanelStatusOnSquare(psq) end
        if status == "not connected" then
            data.pbLinked = { x = pb.x, y = pb.y, z = pb.z }
            table.insert(pb.panels, { x = panelIso:getX(), y = panelIso:getY(), z = panelIso:getZ() })
            pb.npanels = (pb.npanels or 0) + 1
            pb:saveData(true)
        end
    end
    panelIso:transmitModData()
    return true
end

PSR.ConnectPanel = ConnectPanel
