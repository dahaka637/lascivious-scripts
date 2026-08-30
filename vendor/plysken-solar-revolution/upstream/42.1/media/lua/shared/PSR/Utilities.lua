---@class PSR
---@field PBSystem_Server PowerbankSystem_Server
local PSR = {}

local _gameTime
local _season

-- 🧊 POINT UNIQUE — LES APPAREILS DONT L'ÉTAT « OFF » EST GRAVÉ DANS LA SAVE (2026-08-16).
--
-- ⚠️ Ces types ne s'éteignent pas comme les autres : `container:setType("freezer_off")` et
--    `modData.PFR_on = false` sont **sérialisés** (`ItemContainer.save()` écrit `this.type`),
--    là où `setActivated` est volatile. Un « off » posé ici ne se défait **que** par un geste
--    explicite — d'où la règle : *avant d'automatiser une extinction, demander QUI LA DÉFAIT*.
--
-- 🔴 POURQUOI ELLE VIT ICI. Elle existait en **deux exemplaires divergents** : côté serveur
--    (`PSR_PERSISTENT_OFF`, 4 types) et côté panneau client (`coolingType` en dur, 3 types —
--    **`coldunit` oublié**). Or `coldunit` est le pire des quatre : son « off » est persisté **et**
--    PFR fait CHAUFFER la pièce tant qu'il est bas. *Deux listes qui décrivent la même chose
--    finissent par diverger, et c'est la plus courte qui décide en silence.*
-- 📌 Elle est posée sur `PSR/Utilities` et non sur `PSR.WorldUtil` pour une raison de CHARGEMENT :
--    `WorldUtilities.lua` ne publie `PSR.WorldUtil` qu'à sa **dernière ligne**, et les fichiers
--    serveur ne le `require` pas nommément — une lecture au chargement du module y vaudrait `nil`
--    selon l'ordre de chargement de PZ. Ici, tout le monde fait `require "PSR/Utilities"`.
PSR.PERSISTENT_OFF = {
    fridge        = true,
    freezer       = true,
    fridgeFreezer = true,
    coldunit      = true,
}

PSR.patchClassMetaMethod = function(class, methodName, createPatch)
    local metatable = __classmetatables[class]
    if not metatable then
        error("Unable to find metatable for class "..tostring(class))
    end
    local metatable__index = metatable.__index
    if not metatable__index then
        error("Unable to find __index in metatable for class "..tostring(class))
    end
    local originalMethod = metatable__index[methodName]
    metatable__index[methodName] = createPatch(originalMethod)
end

function PSR.queueFunction(eventName,fn)
    local event = Events[eventName]
    if not event then return print("Tried to queue to invalid event") end
    local function queueFn(...)
        event.Remove(queueFn)
        return fn(...)
    end
    event.Add(queueFn)
end

do
    local delayedProcess = ISBaseObject:derive("PSR delayedProcess")
    local meta = {__index=delayedProcess}

    function delayedProcess:new(obj)
        obj = obj or {}
        obj.event = obj.event or Events.OnTick
        setmetatable(obj,meta)
        return obj
    end

    function delayedProcess:start()
        self.event.Add(self.process)
    end

    function delayedProcess:stop()
        self.data = nil
        return self.event.Remove(self.process)
    end

    function delayedProcess.process() end

    PSR.delayedProcess = delayedProcess
end

---NOTE : compare l'heure courante à l'aube/au crépuscule (saison/heure à jour client+serveur, vérifié OK en usage).
---compares current time to dusk and dawn
---@return boolean
function PSR.isDayTime()
    if not _gameTime or not _season then return true end  -- events not fired yet (early call): assume day
    local time = _gameTime:getTimeOfDay()
    return time > _season:getDawn() and time < _season:getDusk()
end

Events.OnGameTimeLoaded.Add(function ()
    _gameTime = getGameTime()
end)

Events.OnInitSeasons.Add(function (season)
    _season = season
end)

return PSR
