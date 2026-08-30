--[[
	global and recipe functions
	In shared/ so Recipe.OnCreate callbacks and AcceptItemFunction are available on all processes.

	B42 dedicated server execution model for craftRecipe:
	  - Server: ISHandcraftAction.perform() → performCurrentRecipe() → onCreate (server-side only)
	  - Client: ISHandcraftAction.complete() does NOT call performCurrentRecipe() in dedicated MP
	  Therefore onCreate runs ONCE, on the server. No double-execution risk.
	  The old guard "if isServer() and not isClient() then return end" was incorrect:
	  it blocked the server-side execution, preventing addOrDrop and modData from running.

	B42 dedicated server item sync rule:
	  - Items created via instanceItem() + inv:AddItem/AddItems() do NOT sync to the client.
	    (Client only sees them after reconnect — the server has them, but the client is not notified.)
	  - ONLY items defined in outputs {} in Recipes.txt are synced by the craft system.
	  - Items from getAllCreatedItems() (recipe outputs) CAN be modified in onCreate and will sync.
	  - Items that are mode:keep inputs are modified in-place — they stay in inventory and sync.
	  Therefore: never use instanceItem() + addOrDrop() in server-side onCreate.
	  Use outputs {} in Recipes.txt + getAllCreatedItems(), or mode:keep + modify in-place.
--]]

-- AcceptItemFunction is a client/ vanilla global — may not be defined yet when shared/ loads.
-- Use additive pattern: create the table if nil, preserve it if already defined.
AcceptItemFunction = AcceptItemFunction or {}

Recipe = Recipe or {}
Recipe.OnCreate = Recipe.OnCreate or {}

local PSR = require("PSR/Utilities")
-- ❌ RETIRÉ 2026-08-05 : `local Sandbox = SandboxVars.PSR` vivait ici, au NIVEAU DU FICHIER.
-- Il était **défini une fois et jamais utilisé** (le seul point de lecture réel est ligne ~172,
-- qui relit `SandboxVars.PSR` en direct et le garde correctement).
-- 🔴 Pourquoi une variable morte n'était PAS inoffensive : c'est un accès NU à `SandboxVars` joué
-- à l'INSTANT DU CHARGEMENT du fichier. Si `SandboxVars` n'est pas encore peuplé quand `shared/`
-- charge — ordre de chargement différent sur un serveur dédié — la ligne lève « attempt to index
-- nil » et **TOUT LE FICHIER échoue à charger**. Conséquences en cascade, toutes SILENCIEUSES pour
-- le joueur : `Recipe.OnCreate.PSR_createDiyBattery` n'est jamais défini ⇒ le `onCreate` de
-- `Make_DIY_Battery` ne fait rien ⇒ la batterie garde le `PSR_maxCapacity = 200` de `Items.txt`
-- ⇒ **`DIYBatteryMultiplier` paraît sans effet quelle que soit sa valeur** ; et
-- `AcceptItemFunction.PSR_Batteries` n'est jamais enregistrée non plus.
-- 📌 Les 2 autres lectures de `SandboxVars.PSR` du mod (`PSRMagazine.lua`, `PSR_RecipeCommands.lua`)
--    sont DANS des fonctions ⇒ jouées au runtime, sans danger. Celle-ci était la seule au niveau
--    fichier — vérifié par grep sur tout le mod avant de conclure.
-- ⚖️ Suppression plutôt que garde `SandboxVars and …` : on ne durcit pas une variable inutilisée,
--    on l'enlève. Zéro changement de comportement.
local RecipeDef = {}

-- Default stats for PSR battery types — used as fallback when PSR_maxCapacity is not in modData.
-- This covers: world-spawned items (DeepCycle, Super), ImprovisedBattery before v1.25,
-- and DIYBattery made from ImprovisedBattery before v1.25.
local PSR_BATTERY_TYPES = {
    WiredCarBattery   = { ah = 50,  degrade = 8     },
    ImprovisedBattery = { ah = 100, degrade = 8     },
    DIYBattery        = { ah = 200, degrade = 0.125 },
    DeepCycleBattery  = { ah = 200, degrade = 4     },
    SuperBattery      = { ah = 400, degrade = 2     },
}

local function roundToNumber(x, n)
	return math.ceil(x / n - 0.5) * n
end

-- AcceptItemFunction.PSR_Batteries: accept any PSR battery type, or items with PSR_maxCapacity in modData.
-- Registered immediately (client) and via OnInitGlobalModData (server).
-- On dedicated server, vanilla server/Items/AcceptItemFunction.lua does AcceptItemFunction = {}
-- which erases any entry defined at file-load time. OnInitGlobalModData fires after ALL Lua files
-- are loaded (vanilla + mods) and re-adds our entry safely.
local function PSR_registerAcceptItem()
	AcceptItemFunction = AcceptItemFunction or {}
	AcceptItemFunction.PSR_Batteries = function(container, item)
		-- Check by type first (robust: works even if PSR_maxCapacity not yet in modData)
		if PSR_BATTERY_TYPES[item:getType()] then return true end
		if item:getModData().PSR_maxCapacity ~= nil then return true end
		return false
	end
end
PSR_registerAcceptItem()
Events.OnInitGlobalModData.Add(PSR_registerAcceptItem)

-- Keyed by getType() (no module prefix) for robustness against B42 casing changes
RecipeDef.carBatteries = { CarBattery1 = { ah = 50, degrade = 10 }, CarBattery2 = { ah = 100, degrade = 6 }, CarBattery3 = { ah = 75, degrade = 8 } }

-- B42: craftRecipe onCreate receives (CraftRecipeData, IsoPlayer), not (items, result, player)
-- Guard: ISCraftAction runs client-side in MP. Dedicated server process loads shared/ too but must not
-- execute these handlers again (double-execution, different ZombRand results, duplicate addOrDrop).
-- isServer() and not isClient() == true only on a dedicated server process.

-- PSR_makeImprovisedBattery: disabled — no onCreate on this recipe.
-- The fallback in PSR_BATTERY_TYPES handles missing PSR_maxCapacity for Recondition/DIY Battery.

function Recipe.OnCreate.PSR_wireCarBattery(craftData, chr)
	local consumed = craftData:getAllConsumedItems()
	local created  = craftData:getAllCreatedItems()
	for i=0, consumed:size()-1 do
		local carBattery = consumed:get(i)
		local batteryInfo = RecipeDef.carBatteries[carBattery:getType()]
		if batteryInfo then
			local result = nil
			for j=0, created:size()-1 do
				local out = created:get(j)
				if out:getType() == "WiredCarBattery" then result = out; break end
			end
			if not result then return end

			local resultData = result:getModData()
			resultData.unwiredType = carBattery:getFullType()
			if carBattery:hasModData() then
				resultData.unwiredData = carBattery:getModData()
			end

			local skillMod = math.min(10, ZombRand(1 + chr:getPerkLevel(Perks.Electricity)))
			local qualityMod = math.min(11, ZombRand(9,11) + skillMod / 4) / 10

			resultData.PSR_maxCapacity = roundToNumber(batteryInfo.ah * qualityMod, 5)
			resultData.PSR_BatteryDegrade = batteryInfo.degrade / qualityMod
			result:setCurrentUsesFloat(carBattery:getCurrentUsesFloat())
			result:setCondition(carBattery:getCondition() - ZombRand(1,12 - skillMod))
			return
		end
	end
end

function Recipe.OnCreate.PSR_unwireCarBattery(craftData, chr)
	-- The recipe outputs a static Base.CarBattery1 (synced by the craft system).
	-- We copy condition/charge from the consumed WiredCarBattery onto that output item.
	-- Note: the original battery type (CarBattery2/3) is not preserved — it always returns
	-- CarBattery1. The WiredCarBattery modData.unwiredData (original battery modData) is copied.
	local consumed = craftData:getAllConsumedItems()
	local created  = craftData:getAllCreatedItems()

	local wiredBattery = nil
	for i = 0, consumed:size()-1 do
		if consumed:get(i):getType() == "WiredCarBattery" then
			wiredBattery = consumed:get(i); break
		end
	end
	if not wiredBattery then return end

	-- Find the output CarBattery created by the recipe (Base.CarBattery1/2/3)
	local result = nil
	for j = 0, created:size()-1 do
		if RecipeDef.carBatteries[created:get(j):getType()] then
			result = created:get(j); break
		end
	end
	if not result then return end

	local skillMod = math.min(10, ZombRand(1 + chr:getPerkLevel(Perks.Electricity)))
	result:setCurrentUsesFloat(wiredBattery:getCurrentUsesFloat())
	result:setCondition(wiredBattery:getCondition() - ZombRand(1, 12 - skillMod))

	-- Restore any original modData stored when the battery was wired
	local oldData = wiredBattery:getModData()
	if oldData.unwiredData then
		local newData = result:getModData()
		for k, v in pairs(oldData.unwiredData) do newData[k] = v end
	end
end

function Recipe.OnCreate.PSR_createDiyBattery(craftData, chr)
	local consumed = craftData:getAllConsumedItems()
	local created  = craftData:getAllCreatedItems()
	local sourceItems, sumCondition, sumCapacity = 0, 0, 0
	for i=0, consumed:size()-1 do
		local item = consumed:get(i)
		-- Fallback to default if PSR_maxCapacity not in modData (e.g. ImprovisedBattery before v1.25)
		local maxCapacity = item:getModData().PSR_maxCapacity
		if maxCapacity == nil then
			local defaults = PSR_BATTERY_TYPES[item:getType()]
			if defaults then maxCapacity = defaults.ah end
		end
		if maxCapacity then
			sourceItems = sourceItems + 1
			sumCapacity = sumCapacity + maxCapacity
			sumCondition = sumCondition + item:getCondition()
		end
	end

	if sourceItems == 0 then return end

	local result = nil
	for j=0, created:size()-1 do
		local out = created:get(j)
		if out:getType() == "DIYBattery" then result = out; break end
	end
	if not result then return end

	local resultData = result:getModData()
	resultData.PSR_maxCapacity = roundToNumber(sumCapacity * ((SandboxVars.PSR and SandboxVars.PSR.DIYBatteryMultiplier) or 100) / 100, 5)

	result:setCurrentUsesFloat(0)
	result:setCondition(math.floor(sumCondition / sourceItems))
end

function Recipe.OnCreate.PSR_reconditionBattery(craftData, chr)
	-- The battery input uses mode:keep — it stays in the player's inventory.
	-- We modify it in-place (condition +20, PSR_maxCapacity fallback).
	-- No instanceItem + addOrDrop needed: the kept item syncs as part of the craft result.
	--
	-- 🔴🔴 CORRIGE LE 2026-08-20 — SIGNAL `Sleaker` : « Recondition on a DIY battery with 'worn'
	--    status doesn't work, and just eats the components. » Il avait raison, et la cause etait ici.
	--
	-- 📚 MESURE AU BYTECODE (42.20, `zombie.entity.components.crafting.recipe.CraftRecipeData`) —
	--    `getAllConsumedItems()` **N'INCLUT JAMAIS** un input `mode:keep`. Chaine des surcharges :
	--      getAllConsumedItems()            -> getAllConsumedItems(list)
	--      getAllConsumedItems(list)        -> (list, includeKeep=FALSE)      [iconst_0]
	--      getAllConsumedItems(list, bool)  -> (list, bool, recordOnly=FALSE) [iconst_0]
	--      corps : `if inputScript.isKeep() && !includeKeep -> skip`
	--    Notre batterie est declaree `mode:keep` (Recipes.txt:94) ⇒ la 1re boucle ne pouvait
	--    STRUCTURELLEMENT rien trouver, et le repli tournait **a chaque craft**.
	--
	-- 🔑 Le repli prenait « la premiere batterie PSR de l'inventaire », pas celle que le joueur a
	--    choisie ⇒ il reconditionnait une AUTRE batterie (souvent deja pleine = aucun effet visible)
	--    pendant que les 3 ElectronicsScrap partaient quand meme. `outputs{}` est vide, donc rien
	--    ne le signalait. Un refus qui a deja coute au joueur. (Jumeau du defaut PAR C-01 du 18/08.)
	--
	-- 🔍 VANILLA : `getAllKeepInputItems` a **0 occurrence** dans le Lua vanilla (seul le Java
	--    l'appelle) — un grep ne pouvait pas la trouver ; c'est la liste EXHAUSTIVE des membres de
	--    la classe qui l'a rendue. Le repli etait l'aveu qu'on n'avait pas lu cette liste.
	-- ⚠️ Le tournevis est LUI AUSSI `mode:keep` ⇒ le filtre par type reste indispensable.
	local sourceBattery = nil

	-- 1. LA bonne liste : les inputs `mode:keep` reellement fournis par le joueur.
	--    Garde d'existence a la Kahlua (`if not obj.method`) : un renommage moteur ne doit pas
	--    tuer la recette, il doit retomber sur les chemins ci-dessous.
	if craftData.getAllKeepInputItems then
		local kept = craftData:getAllKeepInputItems()
		if kept then
			for i = 0, kept:size()-1 do
				local item = kept:get(i)
				if item and PSR_BATTERY_TYPES[item:getType()] then
					sourceBattery = item; break
				end
			end
		end
	end

	-- 2. Filet : si une build future faisait passer les `mode:keep` par la liste consommee.
	if not sourceBattery then
		local consumed = craftData:getAllConsumedItems()
		for i = 0, consumed:size()-1 do
			local item = consumed:get(i)
			if PSR_BATTERY_TYPES[item:getType()] then
				sourceBattery = item; break
			end
		end
	end

	-- 3. DERNIER recours seulement. ⚠️ Il ne connait PAS le choix du joueur : il prend la premiere
	--    batterie de l'inventaire. Conserve pour ne jamais rendre la recette inerte, mais il ne doit
	--    plus etre le chemin nominal — c'etait tout le defaut.
	if not sourceBattery then
		local allItems = chr:getInventory():getItems()
		for i = 0, allItems:size()-1 do
			local item = allItems:get(i)
			if PSR_BATTERY_TYPES[item:getType()] then
				sourceBattery = item; break
			end
		end
	end
	if not sourceBattery then return end

	-- Ensure PSR_maxCapacity is set (fallback for world-spawned / pre-v1.25 batteries)
	local data = sourceBattery:getModData()
	if not data.PSR_maxCapacity then
		local defaults = PSR_BATTERY_TYPES[sourceBattery:getType()]
		if defaults then
			data.PSR_maxCapacity = defaults.ah
			data.PSR_BatteryDegrade = defaults.degrade
		end
	end
	-- Recondition: restore up to 20 points of condition (battery stays in inventory, mode:keep)
	sourceBattery:setCondition(math.min(100, sourceBattery:getCondition() + 20))
end

-- PSR_ReverseSolarPanel: removed in v1.28.
-- Was using inventory:AddItems() which does NOT sync to client in B42 dedicated server.
-- Fix: split into two separate recipes ("Reverse Solar Roof Tile" + "Reverse Solar Panel")
-- with all outputs defined in Recipes.txt outputs {} — synced automatically by the craft system.
-- Recipe.OnCreate.PSR_ReverseSolarPanel is no longer referenced from Recipes.txt.

return RecipeDef
