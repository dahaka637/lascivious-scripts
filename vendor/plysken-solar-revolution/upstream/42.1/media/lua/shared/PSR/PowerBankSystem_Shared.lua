--[[
    "psr_powerbank" shared functions between client and server systems
--]]

local PSR = require "PSR/Utilities"

-- ⚠️ 2026-08-04 — `local sandbox = SandboxVars.PSR` RETIRÉ (capture au CHARGEMENT du module).
-- Deux façons de tomber, aucune rattrapée : si `SandboxVars.PSR` n'est pas encore peuplé quand ce
-- fichier est requis, `sandbox` vaut `nil` ⇒ indexation d'un nil ; et si l'option manque (une option
-- ajoutée APRÈS la création d'une save, cf. `map_sand.bin` binaire), la valeur vaut `nil` ⇒
-- **arithmétique sur nil**. Dans les deux cas une erreur Lua, pas une valeur dégradée.
-- 📌 Et c'est surtout un DOUBLE POINT DE VÉRITÉ : `PSRComputerPanel.lua:perPanelOutput()` lit la
--    MÊME option, mais **en direct et avec un repli `or 25`**. Le point protégé était l'affichage,
--    le point nu était celui qui calcule la CHARGE RÉELLE. Les deux lisent désormais pareil.
--    ⚖️ Défaut `25` = celui de `sandbox-options.txt` (vérifié, pas supposé) — s'il change là-bas,
--    il doit changer ICI et dans `perPanelOutput()`.
local PSR_SOLAR_EFF_DEFAULT = 25

---@class PowerbankSystem
---@field getLuaObjectAt fun(self, x: number, y: number, z: number): PowerBankObject_Server
---@field getLuaObjectOnSquare fun(self, square: IsoGridSquare): PowerBankObject_Server
local PbSystem = {}

--also adds this function
function PbSystem:new(obj)
    for key,value in pairs(self) do
        obj[key] = value
    end
    return obj
end

---@param isoObject IsoObject
---@return boolean
function PbSystem:isValidIsoObject(isoObject)
    return instanceof(isoObject, "IsoGenerator") and PSR.WorldUtil.getType(isoObject) == "PowerBank"
end

function PbSystem:getIsoObjectOnSquare(square)
    if not square then return end
    local objects = square:getSpecialObjects()
    for i=0,objects:size()-1 do
        local isoObject = objects:get(i)
        if self:isValidIsoObject(isoObject) then
            return isoObject
        end
    end
end

function PbSystem:getMaxSolarOutput(SolarInput)
    -- Lecture EN DIRECT + repli (cf. la note en tête de fichier) : ce calcul alimente la charge
    -- réelle des banks, il ne doit jamais dépendre de l'instant où le module a été chargé.
    local eff = (SandboxVars and SandboxVars.PSR and SandboxVars.PSR.solarPanelEfficiency)
                or PSR_SOLAR_EFF_DEFAULT
    return SolarInput * (83 * ((eff * 1.25) / 100)) --changed to more realistic 1993 levels
end

local climateManager
function PbSystem:getModifiedSolarOutput(SolarInput)
    climateManager = climateManager or getClimateManager()
    local cloudiness = climateManager:getCloudIntensity()
    local light = climateManager:getDayLightStrength()
    local fogginess = climateManager:getFogIntensity()
    local CloudinessFogginessMean = 1 - (((cloudiness + fogginess) / 2) * 0.25) --make it so that clouds and fog can only reduce output by 25%
    local temperature = climateManager:getTemperature()
    local temperaturefactor = temperature * -0.0035 + 1.1 --based on linear single crystal sp efficiency
    local output = self:getMaxSolarOutput(SolarInput)
    output = output * CloudinessFogginessMean
    output = output * temperaturefactor
    output = output * light
    return output
end

---BFS from startPb — returns all PowerBankObjects in the linked network.
---@param startPb table
---@return table[]
function PbSystem:getNetwork(startPb)
    local visited = {}
    local queue   = { startPb }
    local result  = {}
    local function key(p) return p.x .. "," .. p.y .. "," .. p.z end
    visited[key(startPb)] = true
    while #queue > 0 do
        local pb = table.remove(queue, 1)
        table.insert(result, pb)
        for _, link in ipairs(pb.PSR_linkedBanks or {}) do
            local k = link.x .. "," .. link.y .. "," .. link.z
            if not visited[k] then
                visited[k] = true
                local linked = self:getLuaObjectAt(link.x, link.y, link.z)
                if linked then table.insert(queue, linked) end
            end
        end
    end
    return result
end

--- Une bank du réseau de `pb` est-elle ALLUMÉE ? — critère de la garde du terminal (v1.71).
---
--- 🎯 **Pourquoi ce prédicat et pas `networkSupplies`** (directive Commandeur, 2026-08-14) :
---    *« la bank est éteinte »* est un **fait POSITIF décidé par le joueur** ; *« rien ne fournit »*
---    était une **inférence tirée d'une absence**. Les quatre régressions de la v1.68 venaient
---    toutes de l'inférence — jamais de la règle. On ne teste donc **ni** `maxcapacity`,
---    **ni** `getIsoObject()` : uniquement l'interrupteur.
---
--- 🔗 **Le réseau, pas la bank seule** — question du Commandeur : *« et dans le cas où il y a une
---    bank liée ? »*. Un terminal collé à une bank éteinte dont un **jumeau lié** tourne doit rester
---    utilisable : le réseau alimente. Regarder la seule bank du terminal griserait un terminal qui
---    marche. ⇒ BFS sur `PSR_linkedBanks`, exactement comme `getNetwork`.
---
--- 🕳️ **TROIS états, et le troisième est le sujet.** `getNetwork` **laisse silencieusement tomber**
---    un maillon que `getLuaObjectAt` ne résout pas (`if linked then ...`). Si ce maillon était le
---    seul allumé, un prédicat binaire répondrait « tout est éteint » — c'est **mot pour mot** le
---    défaut qui a coûté la v1.68. On rend donc `nil` = *« je ne sais pas »*, et l'appelant
---    **n'a pas le droit de bloquer sur un `nil`**. → cookbook §56 · [[feedback-cleanup-default-preserve]]
---
--- ⚖️ **Lecture ADDITIVE de l'état** : le champ `activated` **ou** l'objet du monde. Mesuré le
---    13/08 : le champ du registre a divergé de l'objet (`active=0` pendant que le capteur lisait
---    `allume=true`). Lire le seul champ griserait un terminal parfaitement fonctionnel.
---@param startPb table|nil
---@return boolean|nil true = au moins une allumée · false = toutes éteintes, PROUVÉ · nil = inconnu
function PbSystem:networkAnyBankOn(startPb)
    if not startPb then return nil end
    local visited, queue = {}, { startPb }
    local unresolved = false
    local function key(p) return p.x .. "," .. p.y .. "," .. p.z end
    visited[key(startPb)] = true
    while #queue > 0 do
        local pb  = table.remove(queue, 1)
        local iso = pb.getIsoObject and pb:getIsoObject() or nil
        if pb.activated or (iso and iso.isActivated and iso:isActivated()) then
            return true
        end
        for _, link in ipairs(pb.PSR_linkedBanks or {}) do
            local k = link.x .. "," .. link.y .. "," .. link.z
            if not visited[k] then
                visited[k] = true
                local linked = self:getLuaObjectAt(link.x, link.y, link.z)
                -- ⚠️ Le `else` est TOUTE la valeur de cette fonction : `getNetwork` n'a pas cette
                --    branche et perd le maillon en silence.
                if linked then table.insert(queue, linked) else unresolved = true end
            end
        end
    end
    if unresolved then return nil end
    return false
end

---Sums charge and capacity across a network.
---@param network table[]
---@return number totalCharge
---@return number totalCapacity
--- 🏘️ LISTE D'APPAREILS DE TOUT LE RÉSEAU (2026-08-21, `D-11`, idée du Commandeur).
--- 💥 **Le défaut qu'elle supprime** : le terminal listait les appareils d'**UNE SEULE** bank, alors
---    que `Connect this area` rattache une structure à la bank la **plus proche**. Avec deux banks,
---    le joueur connectait une pièce, voyait « connecté » en vert, et regardait un terminal qui ne
---    la montrerait jamais. *Ce n'est pas un défaut d'affichage : c'était une INCOHÉRENCE.*
--- 🔑 Tout le reste du mod raisonne déjà en RÉSEAU — la charge est mise en commun
---    (`distributeCharge`), la coupure d'urgence agit sur le réseau (`cutNetworkDevices`), et même
---    les permissions du terminal (`networkSupplies`, `networkAnyBankOn`). **Seule la liste ne
---    suivait pas.** ⇒ on ne devine plus « la bonne bank », la question devient sans objet.
---
--- ⚡ **PERF — LA CONTRAINTE QUI DÉCIDE DE L'IMPLÉMENTATION.** `getDrain*` est un balayage
---    **linéaire en surface de bâtiment** ; le refaire pour N banks à chaque ouverture du panneau
---    multiplierait par N un coût déjà lourd. 💥 Précédent : fps ÷1,4 chez un admin, 1103
---    rebalayages en 2 h 30. ⇒ **on RÉUTILISE la `deviceList` que `updateDrain` a déjà rangée**, et
---    on ne recalcule que pour une bank qui n'en a jamais eu. → [[feedback-mesurer-le-cout-pas-le-deduire]]
--- 🔴 **`R-29` (2026-08-23) — CE COMMENTAIRE DISAIT L'INVERSE DE LA VÉRITÉ, ET C'EST LUI QUI A
---    PRODUIT LE DÉFAUT.** Il affirmait : *« le dédoublonnage est déjà fait en aval, un appareil
---    couvert par deux banks liées ne compte qu'une fois »*. ⚠️ Vrai du **COMPTE**, faux du **TAUX** :
---    `buildGroupsFromPB` / `buildDeviceGroups` dédupliquent `g.seen[x_y_z]` pour le compte, mais
---    **somment `e.rate` et `g.rate` sur CHAQUE entrée, doublons compris**. ⇒ avec N banks liées,
---    les Ah affichés étaient multipliés par N.
---    📏 Mesuré chez `TheFlawedKnight` (4 banks, 4 frigos, dédié) : ligne détaillée 312 Ah = 4×r,
---    groupe 1 248 = 16×r, drain réel 312 — les trois lignes rendent le même r = 78.
---    ⚖️ **Affichage seul** : la simulation ne comptait qu'une bank (`totalDrain = member.drain`
---    sous garde `drainCounted`), aucune batterie ne s'est vidée plus vite.
--- 🔑 *Le défaut n'était pas dans la ligne écrite en 1.75 : c'est un consommateur PERMISSIF resté
---    identique pendant que sa SOURCE changeait de contrat.* En 1.74 le panneau appelait
---    `buildGroupsFromPB(pb)` **sans liste** — une seule bank, donc aucun doublon possible.
---    → [[feedback-repli-change-de-source-change-de-contrat]] · [[feedback-option-qui-ment-tester-le-texte]]
--- ⛔ **ON NE TOUCHE PAS AUX RÉDUCTEURS** : leur sommation est **légitime**. `scanCellDevices`
---    (`PowerBankObject_Server.lua:837`) pousse **une entrée par OBJET** de la case ⇒ deux
---    plafonniers sur une même case sont **deux entrées justes**, de même `dtype` et même `(x,y,z)`,
---    et leur taux DOIT s'additionner. Supprimer le `else` sous-facturerait toutes ces cases.
--- ⚙️ **La correction vit donc ICI, au point d'agrégation, en DEUX TEMPS** : une case déjà apportée
---    par une bank PRÉCÉDENTE est ignorée ; les entrées multiples d'une **même** bank sur cette case
---    sont toutes gardées. C'est pour ça que `claimed` est alimenté **après** la boucle d'une bank et
---    non pendant — sinon on jetterait le 2ᵉ plafonnier de la bank courante.
--- 🔍 Le moteur fait pareil pour le même travail : `IsoChunk.addGeneratorPos(x,y,z)` **refuse un
---    doublon** (cookbook l.1919). Le vanilla, lui, n'agrège **jamais** plusieurs générateurs
---    (`ISGeneratorInfoWindow.lua:60-65` liste `getItemsPowered()` d'UN objet) ⇒ aucun précédent à
---    copier, l'agrégation est à nous et son dédoublonnage aussi.
--- 🧪 Témoins écrits À L'AVANCE : **une seule bank ⇒ aucun chiffre ne bouge** (le `claimed` est
---    vide au 1er tour) · **N banks liées ⇒ la ligne détaillée passe de N×r à r** · **le COMPTE
---    d'appareils est inchangé dans les deux cas** (l'ensemble des cases distinctes est le même).
--- ⚠️ Sur un CLIENT DE DÉDIÉ, l'objet bank n'a ni `getDrainBuilding` ni `getDrainVanilla` : les
---    gardes `b.getDrainBuilding` le couvrent, et de toute façon ce chemin-là fabrique sa liste
---    côté serveur puis l'envoie.
---@param startPb table bank de départ (celle du terminal)
---@return table liste plate d'entrées { x, y, z, dtype, rate, active }
function PbSystem:getNetworkDeviceList(startPb)
    local out = {}
    if not startPb then return out end
    -- `R-29` : cases déjà apportées par une bank PRÉCÉDENTE du réseau (voir l'en-tête).
    local claimed = {}
    for _, b in ipairs(self:getNetwork(startPb)) do
        local dl = b.deviceList
        if not dl and b.getSquare and b.getDrainBuilding and b.getDrainVanilla then
            local sq = b:getSquare()
            if sq then
                local _
                local bld = sq:getBuilding()
                if bld then _, dl = b:getDrainBuilding(sq, bld) else _, dl = b:getDrainVanilla(sq) end
                b.deviceList = dl   -- mémorisée : la prochaine ouverture ne rebalaiera pas
            end
        end
        -- Deux temps : on lit `claimed` (état des banks PRÉCÉDENTES) et on remplit `mine` ; la fusion
        -- n'a lieu qu'après la boucle, sinon la 2ᵉ entrée d'une MÊME bank sur une même case serait
        -- jetée (deux plafonniers sur une case = deux entrées légitimes, cf. `scanCellDevices`).
        local mine = nil
        for i = 1, #(dl or {}) do
            local dev = dl[i]
            local k   = dev.x .. "_" .. dev.y .. "_" .. dev.z
            if not claimed[k] then
                mine = mine or {}
                mine[k] = true
                out[#out + 1] = dev
            end
        end
        if mine then for k in pairs(mine) do claimed[k] = true end end
    end
    return out
end

--- 🔢 `R-32` (2026-08-23) — LE DRAIN FACTURÉ D'UN RÉSEAU, calculé sur l'UNION DÉDOUBLONNÉE.
--- 💥 **Le défaut qu'elle corrige, mesuré sur deux terminaux du même réseau** : `updateNetwork`
---    prenait `member.drain` du **PREMIER** membre qui draine (garde `drainCounted`). Or deux banks
---    liées à UNE CASE l'une de l'autre annonçaient **156,8 Ah** et **332,8 Ah** — chacune ne facture
---    que ce que **son propre balayage** atteint. ⇒ le drain du réseau dépendait de **l'ordre
---    d'itération**, pas de la consommation, et le réseau pouvait être facturé **de moitié**.
--- 🔑 *La seule vue qui connaît le vrai ensemble d'appareils est la liste dédoublonnée* — c'est
---    donc elle qui doit produire le drain, pas un membre choisi au hasard.
--- ⚖️ **Ce n'est PAS de l'affichage** : cette valeur décide de la vitesse de décharge. Un réseau
---    multi-banks couvrant plusieurs zones se videra plus vite qu'avant — c'est la fin d'un courant
---    gratuit, à dire au joueur dans le changelog.
--- ⚠️ On somme `rate` seulement quand `active` **ET** `powered` — exactement la règle de
---    `scanCellDevices` (`if active and powered then totalRate = totalRate + rate`). `powered` a dû
---    y être AJOUTÉ le même jour : la liste disait ce qui est allumé, jamais ce qui est alimenté.
---@param members table[] les banks à compter (typiquement celles dont `shouldDrain` est vrai)
---@return number drain en Ah
function PbSystem:getNetworkBilledDrain(members)
    if not members or #members == 0 then return 0 end
    -- ⚠️ Repli NOMMÉ, pas muet : `fuelToSolarRate` est une constante de CLASSE (800) côté serveur ;
    --    un objet client peut ne pas la porter. On la lit sur le 1er membre, sinon 800.
    local toAh = members[1].fuelToSolarRate or 800
    local seen, total = {}, 0
    for _, b in ipairs(members) do
        local dl = b.deviceList
        if dl then
            -- Même dédoublonnage EN DEUX TEMPS que `getNetworkDeviceList`, et pour la même raison :
            -- deux objets sur une MÊME case d'une MÊME bank sont deux entrées légitimes qui doivent
            -- s'additionner ; c'est la répétition ENTRE banks qu'il faut jeter.
            local mine = nil
            for i = 1, #dl do
                local dev = dl[i]
                local k = dev.x .. "_" .. dev.y .. "_" .. dev.z
                if not seen[k] then
                    mine = mine or {}
                    mine[k] = true
                    if dev.active and dev.powered then total = total + (dev.rate or 0) end
                end
            end
            if mine then for k in pairs(mine) do seen[k] = true end end
        end
    end
    return total * toAh
end

--- 🔗 Coordonnées dédoublonnées de tous les appareils d'un TYPE, sur tout le réseau (`D-11`).
--- 💥 **Le défaut qu'elle corrige** : le panneau appelait `pb:controlDeviceGroup(dtype, on)` **sans
---    coordonnées**, ce qui faisait retomber la méthode sur son repli — un balayage de **sa seule
---    bank**. Le joueur voyait 4 TV, en éteignait 1, et les 3 autres (portées par la bank LIÉE) ne
---    bougeaient pas. *Un demi-effet sans message : rien n'échoue, donc rien n'alerte.*
--- ⚖️ Dédoublonnage **obligatoire ici** : un appareil dans l'emprise de deux banks liées figure dans
---    les DEUX `deviceList` (mesuré : `getNetworkDeviceList` rend 73 = 36+37, `tv=5` pour 4 TV réelles).
---    Sans lui on basculerait deux fois la même case — inoffensif pour un interrupteur, **pas** pour
---    un `setType` de frigo rediffusé à tous les clients.
---@param startPb table bank de départ · @param dtype string type d'appareil
---@return table liste de { x, y, z }
function PbSystem:getNetworkDeviceCoords(startPb, dtype)
    local out, seen = {}, {}
    for _, dev in ipairs(self:getNetworkDeviceList(startPb)) do
        if dev.dtype == dtype then
            local k = dev.x .. "_" .. dev.y .. "_" .. dev.z
            if not seen[k] then
                seen[k] = true
                out[#out + 1] = { x = dev.x, y = dev.y, z = dev.z }
            end
        end
    end
    return out
end

--- 🔄 Recalcule la `deviceList` de TOUTES les banks du réseau, après une action (`D-11`).
--- 💥 Sans ça, seule la bank du terminal se rafraîchissait : les banks liées renvoyaient un `active`
---    périmé, et **l'écran contredisait une action qui avait RÉUSSI**. *Le pire profil : l'action
---    marche, l'interface dit le contraire, et le joueur conclut que c'est cassé.*
--- ⚖️ **Coût assumé et borné** : N balayages, une fois, sur un clic **volontaire** — jamais sur un
---    tick ni sur un rafraîchissement automatique. C'est là que passe la frontière : *ce qui se
---    répète doit être borné ; ce que l'utilisateur déclenche peut coûter.*
--- 🔑 **Vit ICI et pas dans un des deux appelants** : le chemin SOLO/hôte coop (le panneau, en
---    direct) et le chemin DÉDIÉ (`Commands`) ont besoin du même geste. *Une correction posée dans
---    un seul des deux marche là où on teste et reste inerte dans l'autre — c'est exactement
---    l'erreur qui a fait croire que ce correctif ne servait à rien.*
function PbSystem:refreshNetworkDrain(startPb)
    for _, b in ipairs(self:getNetwork(startPb)) do
        if b.updateDrain then b:updateDrain() end
    end
end

function PbSystem:getNetworkStats(network)
    local totalCharge, totalCapacity = 0, 0
    for _, pb in ipairs(network) do
        totalCharge    = totalCharge    + (pb.charge       or 0)
        totalCapacity  = totalCapacity  + (pb.maxcapacity  or 0)
    end
    return totalCharge, totalCapacity
end

---Distributes newCharge proportionally by each bank's maxcapacity.
---@param network table[]
---@param newCharge number
---@param totalCapacity number
function PbSystem:distributeCharge(network, newCharge, totalCapacity)
    for _, pb in ipairs(network) do
        pb.charge = totalCapacity > 0 and newCharge * ((pb.maxcapacity or 0) / totalCapacity) or 0
    end
end

function PbSystem:getValidBackupOnSquare(square)
    local generator = square:getGenerator()
    if generator and generator:isConnected() and not PSR.WorldUtil.findTypeOnSquare(square, "PowerBank") then
        return generator
    end
end

return PbSystem
