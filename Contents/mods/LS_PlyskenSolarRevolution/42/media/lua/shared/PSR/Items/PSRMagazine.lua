require "TimedActions/ISReadABook"

-- B42: learnRecipe() uses the recipe name WITHOUT module prefix.
-- "WireCarBattery" not "PSR.WireCarBattery" — confirmed by vanilla XpUpdate.lua format.
local psrBaseRecipes = {
    "WireCarBattery",
    "UnWireCarBattery",
    "Make_Improvised_Battery",
    "Make_DIY_Battery",
    "Recondition_Battery",
    "Create_Battery_Bank",
    "Create_Solar_Failsafe",
    "Dismantle_Solar_Failsafe",
    "Dismantle_Battery_Bank",
    "Make_Solar_Roof_Tile",
    "Make_Wall-Mounted_Solar_Panel",
    "Make_Floor-Mounted_Solar_Panel",
    "Reverse_Solar_Panel",
    "Reverse_Solar_Roof_Tile",
    "Make_Inverter",
}

-- The solar panel recipe is sandbox-selectable (PSR.HardenedPanelRecipe, v1.47):
-- OFF (default) = standard Make_Solar_Panel; ON = harder Make_Solar_Panel_Realistic
-- (glass + aluminium frame). Only the selected one is taught so the other stays hidden.
-- DEV: force the hardened recipe ON without a fresh save (existing test save keeps the
-- sandbox option at its default in map_sand.bin). MUST be false before publishing.
local PSR_DEV_FORCE_HARDENED = false
local function psrPanelRecipe()
    if PSR_DEV_FORCE_HARDENED then return "Make_Solar_Panel_Realistic" end
    local sv = SandboxVars.PSR
    if sv and sv.HardenedPanelRecipe then return "Make_Solar_Panel_Realistic" end
    return "Make_Solar_Panel"
end

local function psrMagRecipesList()
    local t = {}
    for _, r in ipairs(psrBaseRecipes) do t[#t+1] = r end
    t[#t+1] = psrPanelRecipe()
    return t
end

local origComplete = ISReadABook.complete
function ISReadABook.complete(self)
    if self.item and self.item:getType() == "PSRMag1" then
        -- Learn recipes client-side (solo + host coop).
        for _, r in ipairs(psrMagRecipesList()) do
            self.character:learnRecipe(r)
        end
        -- Dedicated server: origComplete calls sendSyncPlayerFields(PF_Recipes) but the server
        -- may not accept the sync for module PSR recipes. Send an explicit server command so
        -- the server calls player:learnRecipe() on its own copy of the player — guaranteed to work.
        if isClient() then
            sendClientCommand(self.character, "PSR", "learnPSRRecipes", {})
        end
    end
    return origComplete(self)
end

-- Self-heal for saves created before v1.33: the legacy `enableExpandedRecipes` sandbox option
-- called recipe:setCanPerform(nil) which broke the learned-state of Make_Solar_Panel + Make_Inverter
-- specifically. Players who already read PSRMag1 had 14/16 recipes known and couldn't re-read the
-- magazine (vanilla blocks re-read on already-fully-processed literature for some flows).
-- Fix: at every game start, if PSRMag1 was already read, re-apply learnRecipe for all 16 recipes.
-- learnRecipe is idempotent on already-known recipes, so this is safe to run every load.
local function PSR_selfHealMagazineRecipes()
    local player = getPlayer()
    if not player then return end
    local readBooks = player:getAlreadyReadBook()
    if not readBooks then return end
    if not readBooks:contains("PSR.PSRMag1") then return end
    for _, r in ipairs(psrMagRecipesList()) do
        player:learnRecipe(r)
    end
    if isClient() then
        sendClientCommand(player, "PSR", "learnPSRRecipes", {})
    end
end
Events.OnGameStart.Add(PSR_selfHealMagazineRecipes)
