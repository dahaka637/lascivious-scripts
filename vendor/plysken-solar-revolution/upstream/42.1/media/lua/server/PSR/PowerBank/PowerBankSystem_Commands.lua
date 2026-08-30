-- La garde est CORRECTE ; sa justification ne l'etait pas (corrigee le 2026-08-19).
-- Elle disait "coop host = isClient ET isServer vrais" : notre propre table MP l'a
-- REFUTE le 2026-08-16 — un hote coop lance un processus SERVEUR separe, les deux
-- mondes sont disjoints, donc isClient() et isServer() ne sont JAMAIS vrais ensemble.
-- Ce qui se passe reellement est plus simple : dans le processus serveur de l'hote coop
-- isClient() est deja faux, donc cette ligne n'y declenche pas et le systeme serveur
-- reste vivant. Le seul processus ecarte est un vrai client.
-- Ne PAS "corriger" la condition — seul le raisonnement etait faux.
if isClient() and not isServer() then return end

---@class PowerbankSystem_Server
local PSR = require "PSR/Utilities"
local PBSystem = require "PSR/PowerBank/PowerBankSystem_Server"

-- Register shared TimedAction classes in server's global env so PZ can mirror them in coop
require "PSR/TimedActions/ActivatePowerbank"
require "PSR/TimedActions/ConnectPanel"
require "PSR/TimedActions/DisconnectPanel"
require "PSR/TimedActions/LinkBanks"
require "PSR/TimedActions/UnlinkBanks"
require "PSR/TimedActions/LinkComputer"
require "PSR/TimedActions/UnlinkComputer"
require "PSR/TimedActions/ConnectStructure"

local Commands = {}

local function noise(message) return PBSystem.instance:noise(message) end

---@param args table
---@return PowerBankObject_Server
local function getPowerBank(args)
    return PBSystem.instance:getLuaObjectAt(args.x, args.y, args.z)
end

function Commands.disconnectPanel(player, args)
    local pb = getPowerBank(args.pb)
    if pb == nil then return end
    local x, y, z = args.panel.x, args.panel.y, args.panel.z
    for i, panel in ipairs(pb.panels) do
        if panel.x == x and panel.y == y and panel.z == z then
            table.remove(pb.panels, i)
            pb.npanels = (pb.npanels or 1) - 1
            break
        end
    end
    local sq = getSquare(x, y, z)
    if sq then
        local objects = sq:getSpecialObjects()
        for i = 0, objects:size() - 1 do
            local obj = objects:get(i)
            local md = obj:getModData()
            if md.pbLinked then
                md.pbLinked = nil
                md.connectDelta = nil
                obj:transmitModData()
                break
            end
        end
    end
    pb:saveData(true)
end

-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- ❌ RETIRÉES LE 2026-08-04 (méga audit, vague 4) — CINQ COMMANDES QUE PERSONNE N'ÉMET :
--    `connectPanel` · `activateGenerator` · `activatePowerbank` · `linkBank` · `unlinkBank`
--
-- 🔎 Pourquoi elles étaient mortes : PSR suit le pattern ISA — la `TimedAction` fait le travail
--    ELLE-MÊME dans son `complete()`, en attaquant `PSR.PBSystem_Server` en direct (sur dédié,
--    `complete()` s'exécute côté serveur via `NetTimedAction`). Ces 5 commandes n'étaient donc
--    que des DOUBLONS du corps de la TimedAction correspondante — `LinkBanks:complete()`
--    (`LinkBanks.lua:77`) était mot pour mot `Commands.linkBank`. Aucun client ne les appelait.
--
-- ⚠️ Détecteur validé sur TÉMOINS avant de conclure (2 filtres précédents avaient rendu de faux
--    verdicts) : la recherche remonte bien les 5 commandes RÉELLEMENT émises — `disconnectPanel`
--    (`DisconnectPanel.lua:92`), `moveBattery` (`Patches.lua:71/90`), `countBatteries`,
--    `plugGenerator` et `troubleshoot` (depuis 2026-08-07 : `PSRBankPanel.lua`, page DIAG —
--    l'ancien `PSRStatusWindowDebugView.lua` a été retiré avec la refonte des UI). 📌 Les
--    commandes passent par DEUX transports (`sendClientCommand` ET `PSR.PBSystem_Client:sendCommand`) :
--    c'est ce qu'un filtre trop étroit avait raté. Toute commande ajoutée ici doit être cherchée
--    sur les deux.
--
-- 🔒 Et ce n'est pas QUE du nettoyage : elles écrivaient de l'état autoritaire (charge, liens,
--    on/off, panneaux) SANS revalidation d'autorité — atteignables uniquement par un paquet
--    fabriqué. Les retirer ferme une surface d'attaque MP.
--
-- ✅ Remplacements vivants, pour qui chercherait où c'est fait maintenant :
--    connectPanel      → `ConnectPanel:complete()`      (`shared/PSR/TimedActions/ConnectPanel.lua:115`)
--    activatePowerbank → `ActivatePowerBank:complete()` (`.../ActivatePowerbank.lua:76`)
--    linkBank          → `LinkBanks:complete()`         (`.../LinkBanks.lua:77`)
--    unlinkBank        → `UnlinkBanks:complete()`       (`.../UnlinkBanks.lua:83`)
--    activateGenerator → `PowerBankSystem_Server.lua:355` (`applyDeviceToggle`), et l'état réel
--                        est de toute façon remiroité par `updateConGenerator` (`:1180`).
-- ═══════════════════════════════════════════════════════════════════════════════════════════

function Commands.moveBattery(player,args)
    local pb = getPowerBank(args[1])
    if pb == nil then return end
    noise("Transfering Battery")
    -- Recalcule l'état depuis le CONTENEUR RÉEL (autoritaire serveur), comme countBatteries/activatePowerbank,
    -- au lieu d'appliquer les deltas charge/capacité calculés CÔTÉ CLIENT (args[3]/args[4]) :
    -- supprime le vecteur de triche (client modifié pouvait gonfler la charge) ET la dérive sur transferts répétés.
    -- Sûr : la commande est envoyée APRÈS ISTransferAction.transferItem (l'item a déjà bougé côté serveur).
    local isopb = pb:getIsoObject()
    if isopb then
        pb:calculateBatteryStats(isopb:getContainer())
    end
    pb:updateGenerator()
    pb:updateSprite()
    pb:saveData(true)
end

function Commands.plugGenerator(player,args)
    local square = getSquare(args.gen.x,args.gen.y,args.gen.z)
    local generator = square and square:getGenerator()
    for _,i in ipairs(args.pbList) do
        local pb = getPowerBank(i)
        if pb then
            if args.plug and generator then
                noise("adding backup")
                pb:connectBackupGenerator(generator)
            else
                if pb.conGenerator and pb.conGenerator.x == args.gen.x and pb.conGenerator.y == args.gen.y and pb.conGenerator.z == args.gen.z then
                    noise("removing backup")
                    pb.conGenerator = false
                end
            end
            pb:saveData(true)
        end
    end
end

-- ❌ `activateGenerator` et `activatePowerbank` retirées ici le 2026-08-04 — voir le bloc en tête
--    de fichier (jamais émises, doublons des `complete()` de TimedAction).

function Commands.countBatteries(player,args)
    local pb = getPowerBank(args)
    local isopb = pb and pb:getIsoObject()
    if isopb then
        pb:calculateBatteryStats(isopb:getContainer())
        pb:updateSprite()
        pb:saveData(true)
    end
end

function Commands.troubleshoot(player, args)
    local pb = getPowerBank(args)
    if not pb then return end

    local isoPB = pb:getIsoObject()
    if not isoPB then return end
    local pbSquare = isoPB:getSquare()
    if not pbSquare then return end

    -- remove invalid generators
    local objects = pbSquare:getSpecialObjects()
    for i = objects:size() - 1, 0 , -1 do
        local object = objects:get(i)
        if instanceof(object, "IsoGenerator") and object:getSprite() == nil then
            object:remove()
        end
    end

    -- remove old attached sprites
    local attached = isoPB:getAttachedAnimSprite()
    if attached then
        attached:clear()
    end

    pb:calculateBatteryStats(isoPB:getContainer())
    pb:updateSprite()
    pb:saveData(true)
end

-- ❌ `linkBank` et `unlinkBank` retirées ici le 2026-08-04 — voir le bloc en tête de fichier
--    (jamais émises ; `Commands.linkBank` était mot pour mot `LinkBanks:complete()`).

--- Builds a grouped device list from the bank's building scan.
--- Groups: { dtype, total, activeCount, rate, devices=[{x,y,z,rate,active}] }
--- ⚡ PERF 2026-08-04 : `dl` est un paramètre OPTIONNEL. `updateDrain()` vient souvent de produire
--- exactement cette liste et de la ranger dans `pb.deviceList` — la recalculer était un balayage
--- complet de la structure pour rien.
--- ✅ Et c'est aussi plus JUSTE : sans ça, la conso facturée (scan de `updateDrain`) et la liste
---    affichée (ce scan-ci, un instant plus tard) venaient de DEUX relevés différents et pouvaient
---    se contredire à l'écran. Elles viennent désormais du même.
---@param dl table|nil deviceList déjà résolue (sinon on la calcule comme avant)
local function buildDeviceGroups(pb, dl)
    local sq = pb:getSquare()
    local groups, order = {}, {}
    if not sq then return groups, order end
    if not dl then
        local building = sq:getBuilding()
        local drainUnused
        if building then
            drainUnused, dl = pb:getDrainBuilding(sq, building)
        else
            drainUnused, dl = pb:getDrainVanilla(sq)
        end
    end
    if not dl then return groups, order end
    for _, dev in ipairs(dl) do
        if not groups[dev.dtype] then
            groups[dev.dtype] = { dtype=dev.dtype, total=0, activeCount=0, rate=0, devices={}, seen={} }
            order[#order + 1] = dev.dtype
        end
        local g   = groups[dev.dtype]
        local sqk = dev.x .. "_" .. dev.y .. "_" .. dev.z
        if not g.seen[sqk] then
            g.seen[sqk]             = true
            g.total                 = g.total + 1
            if dev.active then g.activeCount = g.activeCount + 1 end
            g.devices[#g.devices+1] = { x=dev.x, y=dev.y, z=dev.z, rate=dev.rate, active=dev.active, powered=dev.powered }
        else
            for _, e in ipairs(g.devices) do
                if e.x==dev.x and e.y==dev.y and e.z==dev.z then
                    e.rate = e.rate + dev.rate; break
                end
            end
        end
        if dev.active then g.rate = g.rate + dev.rate end
    end
    return groups, order
end

--- Sends the current device list (grouped by type, with active state) to the requesting client.
--- args: { x, y, z } — bank coordinates
---@param freshList table|nil deviceList tout juste produite par `updateDrain()` (évite un re-scan)
function Commands.requestDeviceList(playerObj, args, freshList)
    local pb = getPowerBank(args)
    if not pb then return end
    -- 🏘️ `D-11` (2026-08-21) — LE CHEMIN DÉDIÉ AGRÈGE AUSSI LE RÉSEAU.
    -- 🔑 *Sans cette ligne, la fonctionnalité aurait marché en solo et en hôte coop, et serait
    --    restée INERTE en dédié* — mot pour mot la régression de la v1.67, et le contexte où
    --    vit le signal `peanuts`. La moitié client ne suffit jamais.
    -- ⚡ `freshList` (produite par un `updateDrain` juste avant) reste prioritaire pour la bank
    --    courante ; on ne rebalaie rien, `getNetworkDeviceList` réutilise les listes existantes.
    local netList = PBSystem.instance and PBSystem.instance.getNetworkDeviceList
                and PBSystem.instance:getNetworkDeviceList(pb) or nil
    local groups, order = buildDeviceGroups(pb, netList or freshList)
    local deviceList = {}
    for _, dtype in ipairs(order) do
        local g = groups[dtype]; g.seen = nil
        deviceList[#deviceList + 1] = g
    end
    sendServerCommand(playerObj, "PSR", "deviceList", {
        devices = deviceList,
        bx = pb.x, by = pb.y, bz = pb.z,
        -- ⚡ 2026-08-13 — L'ÉTAT DU RÉSEAU VOYAGE AVEC LA LISTE, et c'est le nœud du lot.
        -- Sur un CLIENT DE DÉDIÉ, `PSR.PBSystem_Server` est nil : le client n'a aucun accès
        -- au registre des banks. Une garde écrite côté UI en lisant `srv` marcherait donc en
        -- solo et en hôte coop, et serait INERTE en dédié — c'est mot pour mot la régression
        -- de la v1.67 (correctif toxique côté serveur, inerte pour `Kirthas`).
        -- ⇒ on fait porter l'état par un message QUI EXISTE DÉJÀ, au lieu d'en inventer un :
        --   · dédié            -> arrive ici, avec la liste
        --   · solo / hôte coop -> lisible en direct via `PSR.PBSystem_Server`
        -- ⚖️ Ajout d'un champ à une table envoyée au client : un client d'une version
        --    antérieure l'ignore simplement. Aucun chemin de régression.
        supplies = PBSystem.instance:networkSupplies(pb),
        -- 🔌 v1.71 — L'ÉTAT DE L'INTERRUPTEUR VOYAGE AVEC LA LISTE, pour la même raison que
        --    `supplies` juste au-dessus : sur un CLIENT DE DÉDIÉ, `PSR.PBSystem_Server` est nil.
        --    Une garde qui ne lirait que `srv` marcherait en solo et en hôte coop et serait
        --    INERTE en dédié — la régression de la v1.67, mot pour mot.
        -- ⚠️ Peut valoir `nil` (« je ne sais pas », maillon lié non résolu). **Ce `nil` doit
        --    survivre au transport** : côté client, `nil` vaut AUTORISÉ. Ne jamais le convertir
        --    en `false` ici « pour faire propre » — ce serait rendre un inconnu en refus.
        netAnyOn = PBSystem.instance:networkAnyBankOn(pb),
    })
end

--- 🔄 REDRAIN DE TOUT LE RÉSEAU APRÈS UNE ACTION (2026-08-21, `D-11`).
--- 💥 **Le défaut qu'il corrige, constaté en jeu** : *« toggle le groupe : ko, et le statut on/off ne
---    se rafraîchit pas »*. Les deux symptômes n'en faisaient qu'un — les appareils basculaient bien
---    physiquement, mais seule la bank du terminal voyait son `deviceList` recalculée ; les banks
---    liées gardaient leur liste **en cache avec l'ancien `active`**, et `getNetworkDeviceList` relit
---    précisément ces caches. ⇒ *l'écran affichait un état périmé, ce qui se lit comme « ça ne marche
---    pas ». Le pire profil : l'action RÉUSSIT et l'interface dit le contraire.*
--- 🔑 **C'est le prix exact du compromis de perf de `getNetworkDeviceList`** : réutiliser les listes
---    évite N balayages **à l'OUVERTURE** du panneau — mais après une **ACTION**, il faut les
---    invalider, sinon on optimise en affichant du faux.
--- ⚖️ **Coût assumé et borné** : N balayages, une fois, sur un clic **volontaire** de l'utilisateur —
---    pas sur un tick, pas sur un rafraîchissement automatique. C'est la frontière que la règle de
---    perf trace : *ce qui est répété doit être borné ; ce que l'utilisateur déclenche peut coûter.*
-- ⚠️ 2026-08-21 : le corps a été REMONTÉ dans `PowerBankSystem_Shared` (`PbSystem:refreshNetworkDrain`)
--    parce que le chemin SOLO/hôte coop (le panneau, en direct) en a besoin AUSSI. Ce wrapper ne
--    garde que la garde de disponibilité. 🔑 *Une correction posée dans un seul des deux chemins
--    marche exactement là où on la teste et reste inerte dans l'autre — c'est ce qui m'a fait
--    croire une heure durant que ce correctif ne servait à rien.*
local function refreshNetworkDrain(pb)
    if PBSystem.instance and PBSystem.instance.refreshNetworkDrain then
        PBSystem.instance:refreshNetworkDrain(pb)
    elseif pb.updateDrain then
        pb:updateDrain()
    end
end

--- Collect coordinates of devices of a given type across the bank's NETWORK (for applyDeviceToggle).
--- 🔴 2026-08-21, `D-11` — ÉTAIT BANK-LOCAL, ET LE TOGGLE DE GROUPE L'ÉTAIT DONC AUSSI.
---    Depuis que le terminal liste le RÉSEAU, un « tout éteindre » n'aurait agi que sur la bank du
---    terminal : le joueur voit 12 lampes, en éteint 5, et les 7 autres restent allumées **sans
---    aucun message**. *Un demi-effet est pire qu'un refus : il n'apprend rien et il se répète.*
--- ⚡ Au passage, ça SUPPRIME un balayage complet par clic : `getNetworkDeviceList` réutilise les
---    `deviceList` déjà rangées par `updateDrain`, là où ce code relançait `getDrain*` à chaque fois.
-- ⚠️ 2026-08-21 : délègue au POINT UNIQUE `PbSystem:getNetworkDeviceCoords` (dédoublonnage compris),
--    partagé avec le chemin solo/hôte coop du panneau. Le repli ci-dessous ne sert que si le
--    système n'expose pas encore le helper.
local function collectDeviceCoords(pb, dtype)
    local sq = pb:getSquare()
    if not sq then return {} end
    if PBSystem.instance and PBSystem.instance.getNetworkDeviceCoords then
        return PBSystem.instance:getNetworkDeviceCoords(pb, dtype)
    end
    local building = sq:getBuilding()
    local drainUnused, dl
    if building then
        drainUnused, dl = pb:getDrainBuilding(sq, building)
    else
        drainUnused, dl = pb:getDrainVanilla(sq)
    end
    if not dl then return {} end
    local coords, seen = {}, {}
    for _, dev in ipairs(dl) do
        if dev.dtype == dtype then
            local key = dev.x .. "_" .. dev.y .. "_" .. dev.z
            if not seen[key] then
                seen[key] = true
                coords[#coords + 1] = { x=dev.x, y=dev.y, z=dev.z }
            end
        end
    end
    return coords
end

--- Physically turns on/off all devices of a type for a bank, then refreshes the client.
--- args: { bank={x,y,z}, dtype="light", on=bool }
function Commands.controlDeviceGroup(playerObj, args)
    local pb = getPowerBank(args.bank)
    if not pb or not args.dtype then return end
    -- Collect coords BEFORE toggling (getDrainBuilding reads live state)
    local coords = collectDeviceCoords(pb, args.dtype)
    -- ⚡ PERF : on PASSE ces coords au lieu de laisser la méthode rebalayer toute la structure
    -- pour retrouver exactement les mêmes cases (2 scans identiques pour un seul clic).
    pb:controlDeviceGroup(args.dtype, args.on, coords)
    -- 🔄 `D-11` : TOUT le réseau se recalcule, pas seulement la bank du terminal — sinon les banks
    --    liées renvoient un `active` périmé et l'écran contredit une action qui a RÉUSSI.
    refreshNetworkDrain(pb)
    pb:saveData(true)
    if #coords > 0 then
        if args.dtype == "fridge" or args.dtype == "freezer" or args.dtype == "fridgeFreezer" then
            -- container:setType does NOT auto-replicate over the network → broadcast to ALL clients
            -- so each one applies the swap. setType is idempotent (skips if already the target type),
            -- so the requester receiving it too is harmless.
            sendServerCommand("PSR", "applyDeviceToggle", { dtype=args.dtype, on=args.on, devices=coords })
        else
            sendServerCommand(playerObj, "PSR", "applyDeviceToggle", { dtype=args.dtype, on=args.on, devices=coords })
        end
    end
    -- ⚡ PERF : `updateDrain()` ci-dessus vient de produire la liste — on la réutilise au lieu
    -- de rebalayer la structure une 2ᵉ fois pour la même information.
    Commands.requestDeviceList(playerObj, { x=pb.x, y=pb.y, z=pb.z }, pb.deviceList)
end

--- 🛡️ REVALIDATION D'AUTORITÉ — AJOUTÉE LE 2026-08-16.
---
--- 🔴 Le problème : `Commands.controlDevice` acceptait `args.x/y/z` **tels quels** et agissait
---    dessus, puis rediffusait le résultat à tous les clients. Aucun test de distance, aucun test
---    d'appartenance, aucun test de lien terminal. Sur un dédié, un paquet fabriqué gravait donc
---    `fridge_off`/`freezer_off` — un état **persisté dans la save** — sur n'importe quelle case
---    de la carte, chez n'importe qui.
--- ⚖️ Et c'est une surface qu'on revendique déjà comme fermée : l'en-tête de ce fichier explique
---    qu'on a supprimé 5 commandes en v1.60 précisément parce qu'elles *« écrivaient de l'état
---    autoritaire sans revalidation »*. Les deux ajoutées depuis l'ont rouverte, sur un état pire.
---
--- ⚠️ POURQUOI CE TEST NE PEUT PAS REFUSER UN CLIC LÉGITIME, et c'est ce qui le rend sûr :
---    la liste affichée par le Solar Computer **est** `pb.deviceList` — elle lui est envoyée par
---    `Commands.requestDeviceList`. Un joueur ne peut donc cliquer que sur un appareil qui y
---    figure déjà. Le refus ne peut frapper qu'une coordonnée que le serveur n'a jamais listée.
--- 📌 `controlDeviceGroup` n'a PAS besoin de ce test : ses coordonnées sont dérivées côté serveur
---    par `collectDeviceCoords`, le client n'y fournit que le `dtype`.
--- 🔴 2026-08-21, `D-11` — CETTE GARDE REPOSAIT SUR UN INVARIANT QUE `D-11` A CASSÉ.
---    Son argument de sûreté (juste au-dessus) était : *« la liste affichée par le Solar Computer
---    EST `pb.deviceList` […] un joueur ne peut donc cliquer que sur un appareil qui y figure »*.
---    **C'était vrai — et ça ne l'est plus** : le terminal affiche désormais le RÉSEAU. Un appareil
---    d'une bank liée était donc **visible mais refusé**, en silence (trace unique).
--- 💥 Constaté en jeu : *« je les vois mais je peux pas les on/off »* (`V-11`).
--- 🔑 **La leçon, et elle vaut au-delà de ce fichier** : *une garde peut être juste, commentée, et
---    devenir fausse parce qu'on a changé la PRÉMISSE qu'elle cite — pas son code. Rien dans le
---    fichier ne se plaint : le commentaire continue d'affirmer un invariant qui n'existe plus.*
--- ⚙️ Le périmètre de la garde doit être **le même que celui de l'affichage**. Un seul appel
---    (`getNetworkDeviceList`) sert les deux ⇒ ils ne peuvent plus diverger.
local function psrDeviceIsListed(pb, x, y, z, dtype)
    if not (x and y and z) then return false end
    local list = PBSystem.instance and PBSystem.instance.getNetworkDeviceList
             and PBSystem.instance:getNetworkDeviceList(pb) or nil
    -- Liste vide = « je ne sais pas », pas « il n'y a rien » : on la reconstruit une fois avant
    -- de refuser. On ne la reconstruit PAS si elle est déjà peuplée — ce serait un 2ᵉ scan de
    -- bâtiment complet par clic, exactement le coût qu'on vient de retirer ailleurs.
    if not list or #list == 0 then
        if pb.updateDrain then pb:updateDrain() end
        list = PBSystem.instance and PBSystem.instance.getNetworkDeviceList
           and PBSystem.instance:getNetworkDeviceList(pb) or pb.deviceList
    end
    for _, dev in ipairs(list or {}) do
        if dev.x == x and dev.y == y and dev.z == z and dev.dtype == dtype then return true end
    end
    return false
end

--- Physically turns on/off a single device (by square + dtype), then refreshes the client.
--- args: { bank={x,y,z}, x, y, z, dtype="light", on=bool }
function Commands.controlDevice(playerObj, args)
    local pb = getPowerBank(args.bank)
    if not pb or not args.dtype then return end
    if not psrDeviceIsListed(pb, args.x, args.y, args.z, args.dtype) then
        -- Trace unique et silencieuse : un refus muet serait indiscernable d'un correctif absent,
        -- mais une trace par paquet offrirait un vecteur d'inondation du log.
        if not Commands.psrWarnedUnlistedDevice then
            Commands.psrWarnedUnlistedDevice = true
            print("PSR: controlDevice refused - target square is not in this bank's device list")
        end
        return
    end
    pb:controlDevice(args.x, args.y, args.z, args.dtype, args.on)
    -- 🔄 `D-11` : même raison que pour le groupe — l'appareil basculé peut appartenir à une bank
    --    LIÉE, et c'est SA liste qui porte l'état lu ensuite par l'affichage.
    refreshNetworkDrain(pb)
    pb:saveData(true)
    if args.dtype == "fridge" or args.dtype == "freezer" or args.dtype == "fridgeFreezer" then
        -- setType does not auto-replicate → broadcast to all clients (idempotent, see controlDeviceGroup).
        sendServerCommand("PSR", "applyDeviceToggle", { dtype=args.dtype, on=args.on, devices={{ x=args.x, y=args.y, z=args.z }} })
    else
        sendServerCommand(playerObj, "PSR", "applyDeviceToggle", { dtype=args.dtype, on=args.on, devices={{ x=args.x, y=args.y, z=args.z }} })
    end
    -- ⚡ PERF : réutilise la liste que `updateDrain()` vient de produire (cf. controlDeviceGroup).
    Commands.requestDeviceList(playerObj, { x=pb.x, y=pb.y, z=pb.z }, pb.deviceList)
end

PBSystem.Commands = Commands

-- Route all client→server commands for the "psr_powerbank" module.
-- PBSystem:OnClientCommand dispatches to Commands[command] by name.
Events.OnClientCommand.Add(function(module, command, player, args)
    if module ~= "psr_powerbank" then return end
    if PBSystem.instance then
        PBSystem.instance:OnClientCommand(command, player, args)
    end
end)
