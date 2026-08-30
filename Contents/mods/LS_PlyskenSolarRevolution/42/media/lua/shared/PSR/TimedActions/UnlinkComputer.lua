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

local UnlinkComputer = ISBaseTimedAction:derive("PSR_UnlinkComputer")
PSR_UnlinkComputer = UnlinkComputer

---@param character  IsoPlayer
---@param computerIso IsoObject  le Desktop Computer lié (PSR_linkedBank doit être dans son modData)
-- 🔴 CORRIGÉ LE 2026-08-16 — même famille que `LinkComputer` (voir son en-tête pour la mesure au
--    bytecode et la contrainte « nom du paramètre = nom du champ »).
-- ⚠️ La lecture du modData (`computerIso:getModData().PSR_linkedBank`) est remontée au SITE
--    D'APPEL, côté client : côté serveur `computerIso` peut être `null`, et indexer le modData
--    d'un objet nul jetait avant même qu'on atteigne `complete()`.
function UnlinkComputer:new(character, computerIso, cx, cy, cz, cSprite, bx, by, bz)
    local o = {}
    setmetatable(o, self)
    self.__index = self
    o.character   = character
    o.computerIso = computerIso
    o.cx = cx
    o.cy = cy
    o.cz = cz
    o.cSprite = cSprite
    o.bx = bx
    o.by = by
    o.bz = bz
    o.stopOnWalk = true
    o.stopOnRun  = true
    o.stopOnAim  = false
    o.maxTime    = 30
    return o
end

---Variante DEPUIS LA BANK — c'est la porte de sortie qui manquait.
---Jusqu'ici l'unique moyen de delier etait le menu de l'ORDINATEUR, garde par le drapeau que
---l'ordinateur porte : quand il disparait (demontage), le lien cote bank survit et plus rien ne
---peut l'effacer. *Une issue de secours ne doit pas vivre sur l'objet qui peut disparaitre.*
---Demande explicite du joueur Zephyrum (2026-08-04) — et il avait raison de la demander.
---@param character IsoPlayer
---@param bankIso   IsoObject  la Battery Bank (c'est elle qu'on cible et qu'on regarde)
---@param comp      table      { x, y, z } lu dans le modData de la bank
function UnlinkComputer:newFromBank(character, bankIso, comp)
    local o = {}
    setmetatable(o, self)
    self.__index = self
    o.character   = character
    o.computerIso = bankIso          -- cible de l'animation / du regard : la bank
    o.fromBank    = true
    o.bx, o.by, o.bz = bankIso:getX(), bankIso:getY(), bankIso:getZ()
    o.cx, o.cy, o.cz = comp and comp.x, comp and comp.y, comp and comp.z
    o.cSprite     = nil              -- inconnu, et sans importance : on matche la reference en retour
    o.stopOnWalk  = true
    o.stopOnRun   = true
    o.stopOnAim   = false
    o.maxTime     = 30
    return o
end

function UnlinkComputer:isValid()
    if isServer() then return true end
    return self.computerIso:getObjectIndex() ~= -1
end

function UnlinkComputer:start()
    if isServer() then return end
    self:setActionAnim("Loot")
    self.character:SetVariable("LootPosition", "Low")
    self.character:reportEvent("EventLootItem")
end

function UnlinkComputer:waitToStart()
    if isServer() then return false end
    self.character:faceThisObject(self.computerIso)
    return self.character:shouldBeTurning()
end

function UnlinkComputer:update()
    if isServer() then return end
    self.character:faceThisObject(self.computerIso)
end

function UnlinkComputer:perform()
    if isServer() then return true end
    ISBaseTimedAction.perform(self)
    return true
end

function UnlinkComputer:complete()
    -- B42.19 : complete() must return a boolean on dedicated (protectedCallBoolean).
    if not PSR.PBSystem_Server then return true end

    -- ═══════════════════════════════════════════════════════════════════════════════════════
    -- 🔴 CORRECTIF MP 2026-08-07 — LES CHAMPS PERSONNALISÉS NE TRAVERSENT PAS LE RÉSEAU
    -- ═══════════════════════════════════════════════════════════════════════════════════════
    -- **Mesuré**, les deux journaux d'un hôte coop côte à côte, même clic :
    --   client  : fromBank=true   bx,by,bz=10680,10339,0   cx,cy,cz=10680,10340,0
    --   serveur : fromBank=NIL    bx,by,bz=nil,nil,nil     cx,cy,cz=10680,10339,0  ← la BANK
    -- En MP, PZ **reconstruit l'action côté serveur** : seuls les champs standards traversent
    -- (personnage + objet ciblé). `fromBank`, `bx/by/bz` et le `cx` rempli par `newFromBank`
    -- sont perdus, et `cx` redevient les coordonnées de la CIBLE.
    --
    -- 🔑 Or `newFromBank` met LA BANK dans `computerIso` — c'est la cible du regard et de
    --    l'animation, pas l'objet sur lequel on agit. **Dès que ces deux rôles divergent, la
    --    réplication casse.** Le serveur cherchait donc le lien sur la case de la bank.
    --
    -- 🧪 Pourquoi ça passait tous les tests : en SOLO il n'y a pas de réplication ; et en coop
    --    DEPUIS L'ORDINATEUR la cible EST l'ordinateur, donc la redérivation retombe juste — par
    --    coïncidence. *Un chemin correct et un chemin qui marche par coïncidence sont
    --    indiscernables, jusqu'au jour où la coïncidence tombe.*
    --
    -- ✅ Parade : ne rien supposer des champs, **redériver depuis l'objet ciblé** (qui, lui,
    --    traverse) et depuis la modData (qui persiste). Si la cible est une PowerBank, on est
    --    en mode « depuis la bank », quoi qu'en dise un drapeau perdu en route.
    local bx, by, bz = self.bx, self.by, self.bz
    local cx, cy, cz = self.cx, self.cy, self.cz
    local fromBank   = self.fromBank
    local target     = self.computerIso
    if target and PSR.WorldUtil.objectIsType(target, "PowerBank") then
        fromBank   = true
        bx, by, bz = target:getX(), target:getY(), target:getZ()
        local pbT  = PSR.PBSystem_Server:getLuaObjectAt(bx, by, bz)
        local c    = pbT and pbT.PSR_computer
        cx, cy, cz = c and c.x, c and c.y, c and c.z
    end
    -- À partir d'ici on n'utilise QUE les locales ci-dessus : les champs `self.*` ne sont plus
    -- fiables au-delà de l'objet ciblé.
    self.fromBank = fromBank

    -- Nettoyer côté bank
    if bx then
        local pb = PSR.PBSystem_Server:getLuaObjectAt(bx, by, bz)
        if pb then
            pb.PSR_computer = nil
            pb:saveData(true)
        end
    end
    -- Nettoyer côté computer. Deux façons de retrouver l'objet, et elles ne se valent pas :
    --  · depuis l'ORDINATEUR (chemin historique) : on connaît son sprite, on matche dessus.
    --  · depuis la BANK : on ne connaît pas le sprite, et surtout l'ordinateur peut avoir DISPARU
    --    ou avoir été remplacé par un autre desktop. On matche donc la RÉFÉRENCE EN RETOUR, ce qui
    --    ne touche que l'objet réellement lié à CETTE bank — et ne fait rien s'il n'y en a plus.
    -- ⚠️ `cx`/`bx`/`fromBank` sont les LOCALES redérivées ci-dessus, pas `self.*` : en MP les
    --    champs de l'instance serveur ne valent plus rien au-delà de l'objet ciblé.
    if not cx then return true end
    local sq = getSquare(cx, cy, cz)
    if not sq then return true end
    local objs = sq:getObjects()
    for i = 0, objs:size() - 1 do
        local obj = objs:get(i)
        local matches
        if fromBank then
            local lb = obj and obj:getModData().PSR_linkedBank
            matches = lb and lb.x == bx and lb.y == by and lb.z == bz
        else
            -- Chemin historique (cible = l'ordinateur) : `cSprite` traverse mal, mais ici la
            -- CIBLE est déjà le bon objet, donc on peut se rabattre dessus si le sprite manque.
            matches = obj and (obj:getTextureName() == self.cSprite
                               or (self.cSprite == nil and obj == target))
        end
        if matches then
            obj:getModData().PSR_linkedBank = nil
            obj:transmitModData()
            break
        end
    end
    return true
end

PSR.UnlinkComputer = UnlinkComputer
