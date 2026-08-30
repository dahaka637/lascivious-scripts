-- =============================================================================
-- ConnectStructure.lua — connecte/déconnecte (toggle) une extension player-built
-- au réseau PSR le plus proche, pour que ses appareils soient COMPTABILISÉS
-- (drain batterie + liste/gestion Solar Computer). N'alimente rien : l'extension
-- est déjà alimentée par le rayon vanilla de la bank ; on comble juste le trou de
-- facturation « powered but not billed ».
-- Server-authoritative (écriture modData dans complete(), côté serveur/hôte/SP).
-- =============================================================================

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
require "PSR/PSRStructures"

local SEARCH_R = 20   -- rayon horizontal (~rayon générateur vanilla)
local SEARCH_Z = 8    -- rayon vertical : la bank peut être au sous-sol / à un autre étage

local ConnectStructure = ISBaseTimedAction:derive("PSR_ConnectStructure")
PSR_ConnectStructure = ConnectStructure

function ConnectStructure:new(character, ax, ay, az)
    local o = {}
    setmetatable(o, self)
    self.__index = self
    o.character  = character
    o.ax, o.ay, o.az = ax, ay, az
    o.stopOnWalk = true
    o.stopOnRun  = true
    o.stopOnAim  = false
    o.maxTime    = 40
    return o
end

function ConnectStructure:isValid() return true end

function ConnectStructure:start()
    if isServer() then return end
    self:setActionAnim("Loot")
    self.character:SetVariable("LootPosition", "Low")
    self.character:reportEvent("EventLootItem")
end

function ConnectStructure:waitToStart() return false end
function ConnectStructure:update() end

function ConnectStructure:perform()
    if isServer() then return true end
    ISBaseTimedAction.perform(self)
    return true
end

-- Halo au JOUEUR AGISSANT (character). ⚠️ B42 : HaloTextHelper.addText(char,text,ColorInfo) n'existe
-- plus → addText(char,text) / addGoodText / addBadText (2 args), gardés. Routage 3-contextes :
-- si on tourne côté serveur (dédié OU hôte coop) et que l'acteur n'est PAS le joueur local → commande
-- vers son client ; sinon halo local SUR l'acteur (corrige aussi le split-screen : pas getSpecificPlayer(0)).
local function notify(character, key, kind)
    if not character then return end
    if isServer() and character ~= getSpecificPlayer(0) then
        sendServerCommand(character, "PSR", "notification", { key = key, kind = kind })
        return
    end
    if not HaloTextHelper then return end
    local txt = getText(key)
    if kind == "bad" and HaloTextHelper.addBadText then HaloTextHelper.addBadText(character, txt)
    elseif kind == "good" and HaloTextHelper.addGoodText then HaloTextHelper.addGoodText(character, txt)
    elseif HaloTextHelper.addText then HaloTextHelper.addText(character, txt) end
end

-- Objet-support d'une case = ancrage de la back-ref (état "connectée" lu à moindre coût par le
-- menu + nettoyage). Historiquement un `IsoThumpable`, c'est-à-dire du PLAYER-BUILT.
--
-- 🔴 ÉLARGI le 2026-08-21 — sans ça, tout le correctif « structure vanilla » est décoratif :
--    l'entrée de menu s'afficherait, l'action s'exécuterait, et **rien ne serait taguable**
--    ⇒ le menu resterait bloqué sur « Connect » et `pruneDeadStructures` prendrait la
--    structure pour démolie au tick suivant.
-- 📚 Mesuré au BYTECODE avant d'écrire (`javap zombie.iso.IsoObject`) : `getModData`,
--    `hasModData`, `setModData` et `transmitModData` vivent sur **`IsoObject`**, la classe de
--    base — ce ne sont pas des méthodes d'`IsoThumpable`.
-- 🔍 Vanilla : le jeu les appelle bien sur des `IsoObject` nus
--    (`SCampfireGlobalObject.lua:263`, `ClientCommands.lua:79` et `:290`).
-- ⚖️ On garde la PRIORITÉ au thumpable : sur une case mixte (mur construit contre mur de
--    carte), l'ancre reste celle d'avant ⇒ **aucune connexion existante ne change d'ancre**,
--    donc aucune save déjà taguée n'est perturbée.
local function anchorObj(sq)
    local objs = sq and sq:getObjects()
    if not objs then return nil end
    local fallback = nil
    for i = 0, objs:size() - 1 do
        local o = objs:get(i)
        if o and instanceof(o, "IsoThumpable") then return o end
        -- ⚠️ Repli VANILLA : mur ou sol réel uniquement, via LE POINT UNIQUE
        --    `WorldUtil.isAnchorable` — surtout pas une copie locale du critère : le menu et
        --    l'élagage lisent le même, et deux copies qui divergent poseraient une connexion
        --    que l'élagage retirerait ensuite tout seul.
        if not fallback and o and PSR.WorldUtil and PSR.WorldUtil.isAnchorable
           and PSR.WorldUtil.isAnchorable(o) then
            fallback = o
        end
    end
    return fallback
end

-- Tague TOUTES les cases de la pièce (pas juste l'ancre) → n'importe quelle case affiche le bon
-- label "Disconnect" dans le menu, et re-cliquer n'importe où dans la pièce déconnecte proprement.
local function tagSquares(squares, bx, by, bz, ax, ay, az)
    for _, s in ipairs(squares) do
        local sq = getSquare(s.x, s.y, s.z)
        local o = sq and anchorObj(sq)
        if o then
            -- Stocke la bank propriétaire (x,y,z) ET l'ancre (ax,ay,az) → toggle fiable même avec 2 banks à portée.
            o:getModData().PSR_structBank = { x = bx, y = by, z = bz, ax = ax, ay = ay, az = az }
            o:transmitModData()
        end
    end
end

local function untagSquares(squares, bx, by, bz)
    for _, s in ipairs(squares) do
        local sq = getSquare(s.x, s.y, s.z)
        local o = sq and anchorObj(sq)
        if o then
            local md = o:getModData()
            if md.PSR_structBank and md.PSR_structBank.x == bx
               and md.PSR_structBank.y == by and md.PSR_structBank.z == bz then
                md.PSR_structBank = nil
                o:transmitModData()
            end
        end
    end
end

function ConnectStructure:complete()
    -- B42.19 : complete() doit retourner un booléen sur dédié (protectedCallBoolean).
    if not PSR.PBSystem_Server then return true end
    local sq = getSquare(self.ax, self.ay, self.az)
    if not sq then return true end

    -- Fix 8 — RE-VALIDATION SERVEUR. Le menu client l'a déjà vérifié, mais un client modifié
    -- pourrait envoyer des coords arbitraires : **le serveur reste l'autorité**.
    -- 🔴 ÉLARGIE le 2026-08-21 (chantier `peanuts`) — et c'était la DERNIÈRE porte fermée de la
    --    chaîne. Sans ce changement, tout le reste du correctif était décoratif : le joueur
    --    marchait jusqu'au mur, l'action se jouait, et on ressortait ici **en silence** — pas de
    --    connexion, pas de message, rien à déboguer côté joueur.
    -- ⚖️ LA GARDE N'EST PAS RETIRÉE, ELLE EST MISE EN CORRESPONDANCE avec celle du menu :
    --    un bâtiment de carte n'est accepté que si l'option sandbox `AllowVanillaConnect` est
    --    active. 🔑 *C'est le serveur qui lit l'option, donc un client modifié ne gagne rien —
    --    la propriété anti-grief est intacte, seul son périmètre a changé.*
    -- ⚠️ `SandboxVars` lu ICI, à l'exécution — jamais au chargement du fichier.
    -- 🔴 REFONTE 2026-08-21 (2ᵉ passe) — **`getBuilding()` EST LE SEUL PRÉDICAT ICI, ET C'EST VOULU.**
    --    `mapBaked` (`mg:getBuildingAt`) a été RETIRÉ : mesuré en jeu, il a rendu **deux valeurs
    --    opposées sur la MÊME case** entre deux sessions. Un garde-fou de sécurité ne se bâtit pas
    --    sur un prédicat qui vacille — surtout quand le sens de son erreur ouvre la garde.
    -- ✅ `getBuilding()` évalué **dans ce processus**, qui est l'autorité, a été mesuré **stable**
    --    sur notre dédié : pièce vanilla ⇒ `OUI` · plancher player-built ⇒ `nil`.
    -- 🔑 *La vue du CLIENT sur ce même champ dépend du contexte (un client d'hôte coop voit un
    --    `IsoBuilding` là où le serveur n'en voit pas). C'est précisément pour ça que la décision
    --    vit ICI et nulle part ailleurs* — un client modifié ne gagne toujours rien.
    if sq:getBuilding() ~= nil then
        local sv = SandboxVars and SandboxVars.PSR
        if (sv and sv.AllowVanillaConnect) ~= true then return true end
    end

    -- Footprint de la région player-built cliquée.
    local foot = PSR.Structures.resolveSquares(self.ax, self.ay, self.az)
    local footSet = {}
    for _, s in ipairs(foot) do footSet[s.x .. "_" .. s.y .. "_" .. s.z] = true end

    -- Fix 3 — déjà connectée ? Le TAG des cases est la source de vérité de la bank PROPRIÉTAIRE
    -- (et NON "la bank la plus proche" : 2 banks à portée provoquaient double-facturation + orphelin).
    local owner
    for _, s in ipairs(foot) do
        local o = anchorObj(getSquare(s.x, s.y, s.z))
        if o then
            local t = o:getModData().PSR_structBank
            if t then owner = t; break end
        end
    end

    if owner then
        -- DÉCONNEXION de la bank propriétaire (peu importe laquelle est la plus proche).
        local pb = PSR.PBSystem_Server:getLuaObjectAt(owner.x, owner.y, owner.z)
        if pb and pb.PSR_manualStructures then
            for i = #pb.PSR_manualStructures, 1, -1 do
                local a = pb.PSR_manualStructures[i]
                if (owner.ax and a.x == owner.ax and a.y == owner.ay and a.z == owner.az)
                   or footSet[a.x .. "_" .. a.y .. "_" .. a.z] then
                    table.remove(pb.PSR_manualStructures, i)
                end
            end
            untagSquares(foot, owner.x, owner.y, owner.z)
            pb:updateDrain()
            pb:saveData(true)
        else
            untagSquares(foot, owner.x, owner.y, owner.z)  -- bank propriétaire disparue → juste nettoyer
        end
        notify(self.character, "IGUI_PSR_Struct_Disconnected")
        return true
    end

    -- CONNEXION : bank PSR la plus proche dans le rayon (±20 h / ±8 v, z pondéré).
    local bx, by, bz, bestD
    for dz = -SEARCH_Z, SEARCH_Z do
        for dx = -SEARCH_R, SEARCH_R do
            for dy = -SEARCH_R, SEARCH_R do
                local s = getSquare(self.ax + dx, self.ay + dy, self.az + dz)
                local bank = s and PSR.WorldUtil.findTypeOnSquare(s, "PowerBank")
                if bank then
                    local d = dx * dx + dy * dy + (dz * 4) * (dz * 4)  -- z pondéré → préfère le même étage
                    if not bestD or d < bestD then
                        bestD = d
                        bx, by, bz = s:getX(), s:getY(), s:getZ()
                    end
                end
            end
        end
    end
    if not bx then notify(self.character, "IGUI_PSR_Struct_NoBank", "bad"); return true end

    local pb = PSR.PBSystem_Server:getLuaObjectAt(bx, by, bz)
    if not pb then notify(self.character, "IGUI_PSR_Struct_NoBank", "bad"); return true end
    pb.PSR_manualStructures = pb.PSR_manualStructures or {}
    table.insert(pb.PSR_manualStructures, { x = self.ax, y = self.ay, z = self.az })
    tagSquares(foot, bx, by, bz, self.ax, self.ay, self.az)
    pb:updateDrain()
    pb:saveData(true)
    notify(self.character, "IGUI_PSR_Struct_Connected", "good")
    return true
end

PSR.ConnectStructure = ConnectStructure
