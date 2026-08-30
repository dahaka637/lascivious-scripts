-- La garde est CORRECTE ; sa justification ne l'etait pas (corrigee le 2026-08-19).
-- Elle disait "coop host = isClient ET isServer vrais" : notre propre table MP l'a
-- REFUTE le 2026-08-16 — un hote coop lance un processus SERVEUR separe, les deux
-- mondes sont disjoints, donc isClient() et isServer() ne sont JAMAIS vrais ensemble.
-- Ce qui se passe reellement est plus simple : dans le processus serveur de l'hote coop
-- isClient() est deja faux, donc cette ligne n'y declenche pas et le systeme serveur
-- reste vivant. Le seul processus ecarte est un vrai client.
-- Ne PAS "corriger" la condition — seul le raisonnement etait faux.
if isClient() and not isServer() then return end

local PSR = require "PSR/Utilities"
-- NOTE : le module "!_TargetSquare_OnLoad" (spawns à positions fixes hérité d'ISA) n'a JAMAIS été bundlé
-- dans le fork PSR → le require échouait (WARN au boot) et retournait nil. On le met explicitement à nil :
-- comportement STRICTEMENT INCHANGÉ (le code garde déjà `TargetSquare_OnLoad and ...` → InitSpawns sort tôt),
-- mais plus de WARN. Spawns par pièce (OnSeeNewRoom) = actifs ; spawns à positions fixes (doRolls) = inertes depuis le fork.
local TargetSquare_OnLoad = nil
-- ⚠️ 2026-08-04 — `local sandbox = SandboxVars.PSR` RETIRÉ (capture au CHARGEMENT du module,
-- sans aucune garde). 3ᵉ occurrence du même motif dans le mod, corrigée d'un bloc avec les 2 autres
-- (`PowerBankSystem_Shared.lua`, `PowerBankObject_Server.lua`) — *corriger un cas, balayer sa famille*.
-- Ici le risque n'était pas une valeur silencieusement fausse mais une **ERREUR LUA** : sans les
-- SandboxVars peuplées, `sandbox.BatteryBankSpawn > 1` compare un nil à un nombre, et
-- `spawnBatteryBankChance[nil]` rend nil qu'on multiplie ensuite — à chaque nouvelle pièce vue.
-- Défauts repris de `sandbox-options.txt` (vérifiés : BatteryBankSpawn=3, LRM*=1), pas supposés.
local function psrSandbox() return (SandboxVars and SandboxVars.PSR) or {} end
local function psrBankSpawn() return psrSandbox().BatteryBankSpawn or 3 end
-- Caisses : option DEDIEE depuis le 2026-08-08 (signal `makeimpossible` : *« is the default settings
-- for the solar crate spawn supposed to be so low? »* — 4 banks trouvees, zero caisse). Jusqu'ici les
-- caisses n'avaient AUCUN reglage propre : elles empruntaient l'echelle des banks, donc le joueur ne
-- pouvait pas les rendre plus frequentes sans inonder la carte de banks. Repli sur `BatteryBankSpawn`
-- pour que le comportement d'une save existante reste identique tant que l'option n'est pas touchee.
local function psrCrateSpawn() return psrSandbox().SolarCrateSpawn or psrBankSpawn() end

local RandomWorldSpawns = {}
RandomWorldSpawns.spawnBatteryBankRooms = { shed = 12, garagestorage = 12, storageunit = 12, electronicsstorage = 3, farmstorage = 8 }
RandomWorldSpawns.spawnBatteryBankChance = { 999999, 10, 3, 1 }
-- ⚖️ REEQUILIBRAGE 2026-08-08 (signal `makeimpossible`, mesure avant/apres ci-dessous).
-- AVANT : { garagestorage = 33, storageunit = 16 } — DEUX types de piece, contre CINQ pour les banks,
-- et un diviseur 33 contre 12. Au defaut (echelle 3) la caisse sortait a 1/99 par `garagestorage`
-- quand la bank sortait a 1/36 — soit ~3x plus rare, sur 2,5x moins de pieces eligibles. Son
-- « 4 banks trouvees, aucune caisse » etait le resultat ATTENDU, pas une anomalie.
-- APRES : memes 5 pieces que les banks, cible ~1,7x plus rare qu'une bank (la caisse est un LOT de
-- composants, elle doit rester le meilleur trouvaille des deux — mais trouvable).
-- Au defaut : garagestorage 1/60 · storageunit 1/48 · shed 1/60 · electronicsstorage 1/18 · farmstorage 1/42.
RandomWorldSpawns.spawnCrateRooms = { garagestorage = 20, storageunit = 16, shed = 20, electronicsstorage = 6, farmstorage = 14 }
RandomWorldSpawns.spawnCrateChance = { 999999, 10, 3, 1 }

---@param square IsoGridSquare
---@param spriteName string
---@param index? number
function RandomWorldSpawns.addToWorld(square, spriteName, index)
    index = index or -1
    local isoObject
    if PSR.WorldUtil.PSRTypes[spriteName] == "PowerBank" then
        RandomWorldSpawns.placePowerBank(square, spriteName, index)
        return
    end
    isoObject = IsoObject.new(square:getCell(), square, spriteName)
    isoObject:createContainersFromSpriteProperties()
    RandomWorldSpawns.fillContainer(isoObject, spriteName)

    square:AddSpecialObject(isoObject,index)
    if isServer() then
        isoObject:transmitCompleteItemToClients()
    end
    triggerEvent("OnObjectAdded", isoObject)
end

---@param square IsoGridSquare
---@param spriteName string
---@param index number
---@return IsoObject
function RandomWorldSpawns.placePowerBank(square, spriteName, index)
    local sprite = getSprite(spriteName)
    local psrType = PSR.WorldUtil.PSRTypes[spriteName]
    local fullType = (psrType and PSR.WorldUtil.PSRFullTypes[psrType]) or ("Moveables." .. spriteName)

    local object = IsoGenerator.new(square:getCell())
    object:setSprite(sprite)
    object:setSquare(square)
    object:getModData().generatorFullType = fullType
    object:createContainersFromSpriteProperties()
    local container = object:getContainer()
    if container then
        container:setExplored(true)
        -- Remove the PSR.PowerBank stub added by the tiledef CustomItem (not a battery)
        local items = container:getItems()
        for i = items:size() - 1, 0, -1 do container:Remove(items:get(i)) end
    end
    square:AddSpecialObject(object, index)
    object:transmitCompleteItemToClients()
    object:setCondition(100)
    object:setFuel(100)
    object:setConnected(true)
    object:getCell():addToProcessIsoObjectRemove(object)
    triggerEvent("OnObjectAdded", object)

    return object
end

function RandomWorldSpawns.fillContainer(isoObject, sprite)
    local container = isoObject:getContainer()
    if not container then return end
    local fillType, overlayType
    if sprite == "solarmod_tileset_01_36" then fillType = "SolarBox"; overlayType = "solarmod_tileset_01_38"
    end
    if fillType == "SolarBox" then
        local sv = psrSandbox()
        local panelnumber = ZombRand(3, 5) * (sv.LRMSolarPanels or 1)
        local batterynumber = ZombRand(1, 2) * (sv.LRMBatteries or 1)
        panelnumber = panelnumber < 8 and panelnumber or 7
        batterynumber = batterynumber < 4 and batterynumber or 3
        container:AddItems("PSR.SolarPanel",panelnumber)
        container:AddItems("Base.ElectricWire",panelnumber*3)
        container:AddItems("Base.MetalBar",panelnumber*2)
        container:AddItems("PSR.DeepCycleBattery",batterynumber)
        container:AddItem("PSR.PSRInverter")
        container:AddItem("PSR.PSRMag1")
    else
        ItemPickerJava.fillContainer(container,getPlayer())
    end
    if overlayType then
        isoObject:setOverlaySprite(overlayType)
    elseif overlayType == nil then
        ItemPickerJava.updateOverlaySprite(isoObject)
    end
    container:setExplored(true)
end

function RandomWorldSpawns.doRolls(targetSquare)
    -- ⚠️ L'option sandbox `PSR.solarPanelWorldSpawns` a ete RETIREE le 2026-08-04 : elle etait
    -- affichee dans le menu et ne pilotait que ce bloc, lui-meme INATTEIGNABLE (`TargetSquare_OnLoad`
    -- vaut nil en dur plus haut, donc `InitSpawns` sort avant d'appeler `doRolls`). Une option qui
    -- ne fait rien est un mensonge d'interface : on l'a retiree plutot que de la laisser rassurer.
    -- Le repli `or 0` est la pour que ce code degrade au lieu de planter si quelqu'un le reveille
    -- un jour sans reintroduire l'option (`dégrader plutôt que planter`, idiome de la gamme).
    local spawnChance = psrSandbox().solarPanelWorldSpawns or 0
    if spawnChance == 0 then return end
    local ZombRand, ipairs = ZombRand, ipairs
    local Locations = require("PSR/World/RandomWorldSpawns_Locations")

    local loaded = {}
    for _,map in ipairs(tostring(getWorld():getMap() or ""):split(";")) do
        local mapLocations = Locations[map]
        if mapLocations ~= nil then
            for _,location in ipairs(mapLocations) do
                local valid = true
                for _,over in ipairs(location.overwrite) do
                    if loaded[over] then valid = false break end
                end
                if valid and ZombRand(100) < spawnChance then
                    targetSquare.addCommand(location.x,location.y,location.z,{ command = "PSRWorldSpawn", sprite = location.type})
                end
            end
        end
        loaded[map] = true
    end
end

function RandomWorldSpawns.OnSeeNewRoom(room)
    local roomChance, square
    -- random powerbank
    local bankSpawn = psrBankSpawn()
    if bankSpawn > 1 then
        roomChance = RandomWorldSpawns.spawnBatteryBankRooms[room:getName()]
        if roomChance and ZombRand(roomChance * RandomWorldSpawns.spawnBatteryBankChance[bankSpawn]) == 0 then
            square = room:getRandomFreeSquare()
            if square then
                RandomWorldSpawns.addToWorld(square, "solarmod_tileset_01_0")
            end
        end
    end
    roomChance = RandomWorldSpawns.spawnCrateRooms[room:getName()]
    -- ⚠️ Volontairement HORS du `bankSpawn > 1` ci-dessus : les caisses apparaissent même quand les
    -- banks du monde sont désactivées. Comportement d'origine, conservé tel quel.
    -- 🔴 2026-08-08 — CETTE INTENTION ÉTAIT ANNULÉE UN CRAN PLUS HAUT : `InitSpawns` n'abonnait
    -- `OnSeeNewRoom` que si `psrBankSpawn() > 1`, donc mettre les banks du monde sur « Aucune »
    -- supprimait AUSSI les caisses — l'exact contraire de ce que cette ligne promet. La garde était
    -- au mauvais niveau : écrite ici, elle ne pouvait rien garder puisque la fonction entière ne
    -- tournait plus. *Un commentaire qui décrit une intention ne la fait pas respecter.*
    local crateSpawn = psrCrateSpawn()
    if crateSpawn > 1 and roomChance and ZombRand(roomChance * RandomWorldSpawns.spawnCrateChance[crateSpawn]) == 0 then
        square = room:getRandomFreeSquare()
        if square then
            RandomWorldSpawns.addToWorld(square, "solarmod_tileset_01_36")
        end
    end
end

function RandomWorldSpawns.InitSpawns()
    -- 🔴 2026-08-08 — L'ABONNEMENT NE DOIT PAS PORTER LA GARDE DES BANKS. Il valait
    -- `if psrBankSpawn() > 1 then`, alors que `OnSeeNewRoom` est le SEUL chemin qui fait apparaitre
    -- les caisses autant que les banks : mettre les banks sur « Aucune » tuait les deux, en
    -- contradiction directe avec le commentaire de `OnSeeNewRoom` qui promettait l'inverse.
    -- Chaque famille porte desormais sa garde LA OU elle est decidee, et l'abonnement ne saute que
    -- si les DEUX sont eteintes (sinon on abonne un handler qui ne peut rien produire).
    if psrBankSpawn() > 1 or psrCrateSpawn() > 1 then
        Events.OnSeeNewRoom.Add(RandomWorldSpawns.OnSeeNewRoom)
    end

    local instance = TargetSquare_OnLoad and TargetSquare_OnLoad.instance
    if not instance then return end

    instance.OnLoadCommands.PSRWorldSpawn = function(square,command)
        RandomWorldSpawns.addToWorld(square,command.sprite)
    end

    if instance.savedData["PSR_RandomWorldSpawns_initialised"] then return end
    RandomWorldSpawns.doRolls(instance)
    instance.savedData["PSR_RandomWorldSpawns_initialised"] = true
end

Events.OnSGlobalObjectSystemInit.Add(RandomWorldSpawns.InitSpawns)

return RandomWorldSpawns