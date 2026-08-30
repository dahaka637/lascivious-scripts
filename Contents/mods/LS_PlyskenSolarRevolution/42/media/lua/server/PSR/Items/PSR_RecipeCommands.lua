--[[
    PSR_RecipeCommands.lua — server only
    Handles "learnPSRRecipes" client command sent by PSRMagazine.lua when a player reads PSRMag1.

    Problem: In dedicated server MP, ISReadABook.complete() runs client-side. sendSyncPlayerFields
    (called by origComplete) syncs PF_Recipes to the server, but for module PSR recipes the server
    may not reconcile the sync correctly. We bypass this by having the server call learnRecipe()
    directly on its own copy of the player.

    We call learnRecipe() with both the short name ("WireCarBattery") and the full name
    ("PSR.WireCarBattery") because B42's internal key format for custom modules is uncertain.
    One of the two will match what canPerformCurrentRecipe() checks — the other is a silent no-op.
--]]

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

-- Solar panel recipe is sandbox-selectable (PSR.HardenedPanelRecipe). The server reads the
-- same synced SandboxVars as the client (PSRMagazine.lua) so both teach the same recipe.
local function psrPanelRecipe()
    local sv = SandboxVars.PSR
    if sv and sv.HardenedPanelRecipe then return "Make_Solar_Panel_Realistic" end
    return "Make_Solar_Panel"
end

Events.OnClientCommand.Add(function(module, command, player, args)
    if module ~= "PSR" or command ~= "learnPSRRecipes" then return end
    local recipes = {}
    for _, r in ipairs(psrBaseRecipes) do recipes[#recipes+1] = r end
    recipes[#recipes+1] = psrPanelRecipe()
    for _, r in ipairs(recipes) do
        player:learnRecipe(r)           -- short name: "WireCarBattery"
        player:learnRecipe("PSR." .. r) -- full name: "PSR.WireCarBattery"
    end
end)
