-- fixme SandboxVars are sometimes the default values at this stage - MP server values are loaded OnPreDistributionMerge???, SP are loaded when creating a character

require 'Items/Distributions'
require 'Items/ProceduralDistributions'
---@class PSR
local PSR = require "PSR/Utilities"

----------------------------------------------------------------------------------------------------------------------
local subDist = SuburbsDistributions
local pdList = ProceduralDistributions.list
local vehDist = VehicleDistributions

----------------------------------------------------------------------------------------------------------------------
---

PSR.Distributions = {}

local function insertRecursive(insertKey,insertInto,insertFrom,default)
    for key,value in pairs(insertFrom) do
        local _insertInto = insertInto[key]
        if not _insertInto and default then
            _insertInto = copyTable(default)
            insertInto[key] = _insertInto
        end
        if type(_insertInto) == "table" then
            if key == insertKey then
                for _,i in ipairs(value) do
                    table.insert(_insertInto,i)
                end
            else
                insertRecursive(insertKey,_insertInto,value,default)
            end
        end
    end
end

----------------------------------------------------------------------------------------------------------------------
--- add custom tables to ProceduralDistributions

pdList.PSRBatteries = {
    rolls = 4,
    items = {
        "PSR.DeepCycleBattery", 36,
        "PSR.SuperBattery", 8,
        "PSR.DIYBattery", 8,
        "PSR.WiredCarBattery", 8,
    }
}
pdList.PSRBatteriesCache = {
    rolls = 4,
    items = {
        "PSR.DeepCycleBattery", 64,
        "PSR.SuperBattery", 32,
        "PSR.DIYBattery", 32,
        "PSR.WiredCarBattery", 32,
    }
}
pdList.PSRSolarBox = {
    rolls = 4,
    items = {
        "PSR.SolarPanel", 48,
        "PSR.DeepCycleBattery", 48,
        "PSR.SuperBattery", 24,
    },
    junk = {
        rolls = 1,
        items = {
            "PSR.PSRMag1", 64,
            "PSR.PSRInverter", 64,
            "PSR.SolarPanel", 16,
            "PSR.DeepCycleBattery", 16,
            "PSR.SuperBattery", 16,
            "PSR.SolarFailsafe", 0.1,
            "Base.ElectronicsScrap", 20,
            "Base.MetalBar", 10,
            "Base.SmallSheetMetal", 10,
            "Base.Screws", 5,
            "Base.ElectricWire", 20,
            "Base.RemoteCraftedV3", 0.1,
        }
    }
}

----------------------------------------------------------------------------------------------------------------------
---edit procList tables for room / cache house types

subDist.all.BatteryBank = {
    procedural = true,
    procList = {
        {name="PSRBatteries", min=0, max=99},
    },
}
subDist.all.SolarBox = {
    procedural = true,
    procList = {
        { name = "PSRSolarBox", min = 0, max = 99, weightChance = 80 },
        { name = "PSRBatteries", min = 0, max = 99, weightChance = 20 },
        { name = "PSRBatteriesCache", min = 0, max = 99, weightChance = 10 },
    },
}

subDist.PSRSolarBoxCache = copyTable(subDist.electronicsstorage or {})   -- garde : table vanilla potentiellement retirée par un mod tiers
subDist.PSRSolarBoxCache.isStore = nil
subDist.PSRSolarBoxCache.SolarBox = copyTable(pdList.PSRSolarBox)
subDist.PSRSolarBoxCache.SolarBox.rolls = 32

insertRecursive("procList", subDist, {
    electronicsstorage = {
        metal_shelves = {
            procList = {
                { name = "PSRSolarBox", min = 0, max = 1, weightChance = 10 },
            },
        },
        crate = {
            procList = {
                { name = "PSRSolarBox", min = 0, max = 1, weightChance = 20 },
                { name = "PSRBatteries", min = 0, max = 1, weightChance = 5 },
                { name = "PSRBatteriesCache", min = 0, max = 1, weightChance = 5 },
            },
        },
    },
    garagestorage = {
        crate = {
            procList = {
                { name = "PSRSolarBox", min = 0, max = 1, weightChance = 3 },
            },
        },
    },
    storageunit = {
        crate = {
            procList = {
                { name = "PSRSolarBox", min = 0, max = 1, weightChance = 5 },
            },
        },
        metal_shelves = {
            procList = {
                { name = "PSRSolarBox", min = 0, max = 1, weightChance = 3 },
            }
        }
    },
    warehouse = {
        crate = {
            procList = {
                { name = "PSRSolarBox", min = 0, max = 1, weightChance = 5 },
                { name = "PSRBatteries", min = 0, max = 1, weightChance = 5 },
            },
        },
    },
    --Cache
    SafehouseLoot = {
        metal_shelves = {
            procList = {
                { name = "PSRSolarBox", min = 0, max = 1, weightChance = 5 },
            },
        },
    },
    PSRSolarBoxCache = {
        crate = {
            procList = {
                { name = "PSRSolarBox", min = 0, max = 3, weightChance = 25 },
                { name = "PSRBatteries", min = 0, max = 1, weightChance = 10 },
            },
        },
        metal_shelves = {
            procList = {
                { name = "PSRSolarBox", min = 0, max = 3, weightChance = 20 },
            },
        },
    }
})

----------------------------------------------------------------------------------------------------------------------
--- Insert items to item lists

-- ROBUSTESSE (durcissement PSR) : résolution SÛRE de la liste `.items` d'une table de distribution
-- vanilla. Un mod tiers (overhaul de loot, pack véhicule…) peut SUPPRIMER ou restructurer une de ces
-- tables ; l'accès direct `pdList["X"].items` plantait alors TOUTE la génération de monde
-- (« attempted index: items of non-table: null » -> crash mid-loading sur partie NEUVE uniquement).
-- On résout par nom avec garde : table absente/malformée -> on LOG laquelle (diagnostic du conflit) et
-- on SAUTE cet insert (l'objet ne spawn juste pas dans cette table-là), au lieu de crasher le monde.
-- Hérité du fork ISA. À calquer sur tout mod qui insère dans les distributions vanilla (cf. PFR).
local function safeItems(root, key, subkey)
    local t = root and root[key]
    if t and subkey then t = t[subkey] end
    if not (t and t.items) then
        print("[PSR] Distributions: loot table '" .. tostring(key) ..
              (subkey and ("." .. subkey) or "") ..
              "' missing or malformed (another mod may have removed it) -> skipping PSR insert there.")
        return nil
    end
    return t.items
end

function PSR.Distributions.distributeItem(info)
    local multiplier = (SandboxVars.PSR and SandboxVars.PSR[info.LRM]) or 1   -- garde : 0 reste 0 (truthy en Lua), seul nil -> 1
    for i = 1, #info.entries do
        local entry = info.entries[i]
        local list = entry[2]
        if list then                                   -- nil = table vanilla absente (déjà loggée par safeItems) -> skip
            table.insert(list, info.fullType)
            table.insert(list, entry[1] * multiplier)
        end
    end
end

function PSR.Distributions.insertDistributions()

    PSR.Distributions.distributeItem({
        fullType = "PSR.PSRMag1",
        LRM = "LRMMisc",
        entries = {
            { 1.0, safeItems(pdList, "BookstoreBooks") },
            { 0.5, safeItems(pdList, "BookstoreMisc") },
            { 1.0, safeItems(pdList, "CrateMagazines") },
            { 2.0, safeItems(pdList, "ElectronicStoreMagazines") },
            { 0.2, safeItems(pdList, "EngineerTools") },
            { 0.8, safeItems(pdList, "LibraryBooks") },
            { 0.5, safeItems(pdList, "LivingRoomShelf") },
            { 0.5, safeItems(pdList, "LivingRoomShelfNoTapes") },
            { 0.6, safeItems(pdList, "MagazineRackMixed") },
            { 0.5, safeItems(pdList, "PostOfficeBooks") },
            { 0.8, safeItems(pdList, "PostOfficeMagazines") },
            { 0.2, safeItems(pdList, "ShelfGeneric") },
            { 1.0, safeItems(vehDist, "ElectricianTruckBed") }
        },
    })

    PSR.Distributions.distributeItem({
        fullType = "PSR.SolarPanel",
        LRM = "LRMSolarPanels",
        entries = {
            { 0.05, safeItems(pdList, "ArmyHangarTools") },
            { 0.10, safeItems(pdList, "ArmyStorageElectronics") },
            { 0.05, safeItems(pdList, "CrateCarpentry") },
            { 0.10, safeItems(pdList, "CrateElectronics") },
            { 0.05, safeItems(pdList, "CrateFarming") },
            { 0.10, safeItems(pdList, "CrateMechanics") },
            { 0.05, safeItems(pdList, "CrateMetalwork") },
            { 0.10, safeItems(pdList, "CrateRandomJunk") },
            { 0.05, safeItems(pdList, "CrateTools") },
            { 0.10, safeItems(pdList, "ElectronicStoreAppliances") },
            { 0.15, safeItems(pdList, "ElectronicStoreMisc") },
            { 0.10, safeItems(pdList, "EngineerTools") },
            { 0.10, safeItems(pdList, "GarageMechanics") },
            { 0.05, safeItems(pdList, "GarageMetalwork") },
            { 0.05, safeItems(pdList, "GarageTools") },
            { 0.10, safeItems(pdList, "GigamartHouseElectronics") },
            { 0.05, safeItems(pdList, "GigamartFarming") },
            { 0.05, safeItems(pdList, "LoggingFactoryTools") },
            { 0.05, safeItems(pdList, "MechanicShelfElectric") },
            { 0.05, safeItems(pdList, "MechanicShelfMisc") },
            { 0.05, safeItems(pdList, "MetalShopTools") },
            { 0.20, safeItems(pdList, "StoreShelfElectronics") },
            { 0.10, safeItems(pdList, "ToolStoreFarming") },
            { 0.10, safeItems(pdList, "ToolStoreMetalwork") },
            { 0.15, safeItems(pdList, "ToolStoreMisc") },
            { 0.10, safeItems(pdList, "ToolStoreTools") },
            { 0.10, safeItems(pdList, "OtherGeneric") },
            { 0.01, safeItems(subDist.all, "metal_shelves") },
            { 1.00, safeItems(vehDist, "ElectricianTruckBed") }
        },
    })

    PSR.Distributions.distributeItem({
        fullType = "PSR.DeepCycleBattery",
        LRM = "LRMBatteries",
        entries = {
            { 0.15, safeItems(pdList, "JanitorMisc") },
            { 0.15, safeItems(pdList, "StoreShelfElectronics") },
            { 0.15, safeItems(pdList, "MechanicShelfElectric") },
            { 0.20, safeItems(pdList, "StoreShelfMechanics") },
            { 0.15, safeItems(pdList, "CrateElectronics") },
            { 0.15, safeItems(pdList, "CrateMechanics") },
            { 0.15, safeItems(pdList, "ToolStoreTools") },
            { 0.20, safeItems(pdList, "ToolStoreMisc") },
            { 0.15, safeItems(pdList, "ArmyStorageElectronics") },
            { 0.15, safeItems(pdList, "ElectronicStoreMisc") },
            { 0.15, safeItems(pdList, "CrateRandomJunk") },
            { 0.15, safeItems(pdList, "CrateTools") },
            { 0.15, safeItems(pdList, "OtherGeneric") },
            { 0.15, safeItems(pdList, "GarageMechanics") },
            { 0.15, safeItems(pdList, "ToolStoreFarming") },
            { 0.03, safeItems(pdList, "CrateFarming") },
            { 0.03, safeItems(pdList, "CrateMetalwork") },
            { 0.01, safeItems(subDist.all, "metal_shelves") },
            { 1.00, safeItems(vehDist, "ElectricianTruckBed") }
        },
    })

    PSR.Distributions.distributeItem({
        fullType = "PSR.SuperBattery",
        LRM = "LRMBatteries",
        entries = {
            { 0.05, safeItems(pdList, "JanitorMisc") },
            { 0.05, safeItems(pdList, "StoreShelfElectronics") },
            { 0.05, safeItems(pdList, "MechanicShelfElectric") },
            { 0.10, safeItems(pdList, "StoreShelfMechanics") },
            { 0.05, safeItems(pdList, "CrateElectronics") },
            { 0.05, safeItems(pdList, "CrateMechanics") },
            { 0.05, safeItems(pdList, "ToolStoreTools") },
            { 0.10, safeItems(pdList, "ToolStoreMisc") },
            { 0.20, safeItems(pdList, "ArmyStorageElectronics") },
            { 0.05, safeItems(pdList, "ElectronicStoreMisc") },
            { 0.05, safeItems(pdList, "CrateRandomJunk") },
            { 0.05, safeItems(pdList, "CrateTools") },
            { 0.05, safeItems(pdList, "OtherGeneric") },
            { 0.05, safeItems(pdList, "GarageMechanics") },
            { 0.05, safeItems(pdList, "ToolStoreFarming") },
            { 0.05, safeItems(pdList, "CrateFarming") },
            { 0.05, safeItems(pdList, "CrateMetalwork") },
            { 0.01, safeItems(subDist.all, "metal_shelves") },
            { 0.40, safeItems(vehDist, "ElectricianTruckBed") }
        },
    })

    PSR.Distributions.distributeItem({
        fullType = "PSR.PSRInverter",
        LRM = "LRMMisc",
        entries = {
            { 0.10, safeItems(pdList, "StoreShelfElectronics") },
            { 0.10, safeItems(pdList, "StoreShelfMechanics") },
            { 0.10, safeItems(pdList, "CrateElectronics") },
            { 0.10, safeItems(pdList, "CrateMechanics") },
            { 0.10, safeItems(pdList, "MechanicShelfMisc") },
            { 0.10, safeItems(pdList, "MechanicShelfElectric") },
            { 0.10, safeItems(pdList, "ToolStoreMisc") },
            { 0.10, safeItems(pdList, "ToolStoreTools") },
            { 0.10, safeItems(pdList, "GigamartHouseElectronics") },
            { 0.10, safeItems(pdList, "ArmyStorageElectronics") },
            { 0.10, safeItems(pdList, "ElectronicStoreMisc") },
            { 0.10, safeItems(pdList, "CrateRandomJunk") },
            { 0.10, safeItems(pdList, "CrateTools") },
            { 0.10, safeItems(pdList, "OtherGeneric") },
            { 0.10, safeItems(pdList, "GarageMechanics") },
            { 0.10, safeItems(pdList, "ElectronicStoreAppliances") },
            { 0.10, safeItems(pdList, "ToolStoreFarming") },
            { 0.03, safeItems(pdList, "CrateFarming") },
            { 0.03, safeItems(pdList, "CrateMetalwork") },
            { 0.01, safeItems(subDist.all, "metal_shelves") },
            { 0.60, safeItems(vehDist, "ElectricianTruckBed") }
        },
    })

    PSR.Distributions.distributeItem({
        fullType = "PSR.SolarFailsafe",
        LRM = "LRMMisc",
        entries = {
            { 0.01, safeItems(pdList, "CrateElectronics", "junk") },
            { 0.01, safeItems(pdList, "GigamartHouseElectronics", "junk") },
            { 0.01, safeItems(pdList, "ArmyStorageElectronics", "junk") },
            { 0.01, safeItems(pdList, "ElectronicStoreMisc", "junk") },
            { 0.01, safeItems(vehDist, "ElectricianTruckBed") }
        },
    })
end

local function OnLoadedMapZones()
    if ItemPickerJava.doParse then
        ItemPickerJava.doParse = nil
        ItemPickerJava.Parse()
    end
    PSR.Distributions = nil
end

-- =============================================================================
-- 🔴 CORRIGÉ 2026-08-05 — les options `LRM*` n'ont JAMAIS rien fait EN SOLO.
-- =============================================================================
-- Signalé par 3 joueurs Steam (drag0fek0, Adam, Imkiddz) : *« I've upped the loot rarity
-- multiplier from 1.0 to 5.0 […] searching through the entirety of Rosewood only netted me one
-- single solar panel part »*.
--
-- L'ANCIEN CODE insérait les distributions à DEUX endroits selon le contexte :
--   · `if not isServer() then insertDistributions() end`  ← exécuté AU CHARGEMENT DU FICHIER
--   · le handler `OnPreDistributionMerge`, gardé par `isServer()`
-- Or le multiplicateur est lu DANS `insertDistributions` (`SandboxVars.PSR[info.LRM] or 1`).
--
-- ⏱️ POURQUOI LE CHEMIN « AU CHARGEMENT » NE PEUT PAS MARCHER — prouvé dans le jar, pas déduit :
--    `zombie/iso/IsoWorld` déclenche les 3 événements de distribution ET porte
--    `SandboxOptions.load()`, `InitSandboxLootSettings`, `parseDistributions` : les SandboxVars du
--    MONDE sont chargés dans `IsoWorld.init()`. Les fichiers Lua d'un mod, eux, sont exécutés bien
--    avant, au boot du LuaManager, quand AUCUN monde n'existe. ⇒ une valeur lue à ce moment-là ne
--    peut pas refléter le sandbox de la partie : `SandboxVars.PSR` est absent, le garde `or 1`
--    s'applique, et **l'option est inerte quelle que soit sa valeur**.
--
-- 🎯 PORTÉE EXACTE (recroisée garde par garde, pas supposée) :
--    · SOLO          : `isServer()` faux ⇒ insertion au load (multiplicateur 1) ET handler sauté ⇒ 🔴 CASSÉ
--    · HÔTE COOP     : `isServer()` vrai ⇒ pas d'insert au load, handler joué ⇒ ✅ correct
--    · DÉDIÉ         : idem hôte coop ⇒ ✅ correct
--    · client dédié  : insérait au load, mais le loot est autoritaire côté serveur ⇒ sans effet
--    ⇒ **le défaut est SOLO-ONLY**, ce qui explique qu'il ait survécu à toutes nos campagnes MP.
--
-- 🔑 C'est encore le motif du jumeau : le correctif « double-insert sur dédié » a été appliqué
--    correctement, et a laissé le solo sur le chemin qui lit le sandbox trop tôt. Le commentaire
--    d'origine le disait même à voix haute — *« OnPreDistributionMerge fait foi (SandboxVars
--    chargés, multiplicateur correct) »* — sans que personne ne se demande ce que valait l'autre.
--
-- ✅ MAINTENANT : un seul point d'insertion, dans TOUS les contextes, au moment où les SandboxVars
--    du monde existent. Le drapeau rend l'appel idempotent si l'événement venait à partir deux fois.
-- ⚖️ Le risque de régression est borné : le défaut `LRM*` vaut **1**, donc un joueur qui n'a jamais
--    touché l'option voit **exactement** le même loot qu'avant. Seuls ceux qui ont changé le
--    réglage voient un changement — c'est-à-dire précisément ceux qui se plaignent.
local psrInserted = false
local function OnPreDistributionMerge()
    if psrInserted then return end
    -- `OnLoadedMapZones` met `PSR.Distributions` à nil : garde pour ne jamais indexer un nil si
    -- l'ordre des événements changeait dans une build future.
    if not (PSR.Distributions and PSR.Distributions.insertDistributions) then return end
    psrInserted = true
    PSR.Distributions.insertDistributions()
end

Events.OnLoadedMapZones.Add(OnLoadedMapZones)
Events.OnPreDistributionMerge.Add(OnPreDistributionMerge)
