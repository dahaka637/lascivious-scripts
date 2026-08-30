--[[
    Burris Quality of Life -- public API for other mods.

    Anything here is a supported extension point. Call it from your own mod at
    file scope; the tables are read at menu-build time, so registration order
    against this mod does not matter.

        BQoL.API.addPryTool("MyMod.SuperCrowbar")
        BQoL.API.addReinforcedDoorSprite("mymod_doors_01_4")
        BQoL.API.addDebrisMapping("mymod_debris_1_0", { { "Base.Twigs", 2 } })
        BQoL.API.addCanInjuryRecipe("OpenMyModCanWithShard")
]]

BQoL = BQoL or {}
BQoL.API = BQoL.API or {}

-- ------------------------------------------------------------ prying tools

--[[
    Extra item full types that can pry, beyond the tag-based detection.

    Deliberately empty by default. Prying tools are found by the vanilla item
    tags base:crowbar and base:prybar, which already cover Crowbar,
    CrowbarForged and TireIron -- listing them here as well would just mean a
    second redundant inventory scan on every right-click.

    This table is purely an escape hatch for modded tools that do not carry the
    vanilla tags.
]]
local pryTools = {}

--- Registers an item full type ("Module.ItemName") as a prying tool.
function BQoL.API.addPryTool(fullType)
    if type(fullType) ~= "string" or fullType == "" then
        BQoL.warn("addPryTool: expected an item full type string")
        return false
    end

    pryTools[fullType] = true
    BQoL.log("registered prying tool %s", fullType)
    return true
end

--- Unregisters a prying tool. Returns true if it was registered.
function BQoL.API.removePryTool(fullType)
    if not pryTools[fullType] then return false end

    pryTools[fullType] = nil
    BQoL.log("removed prying tool %s", fullType)
    return true
end

--- Read-only view of the registered prying tools, as a set.
function BQoL.API.getPryTools()
    return pryTools
end

-- ------------------------------------------------- can-opening recipes

--[[
    Extra craft recipes that count as opening a can the improvised way, on top
    of the four B42.20 ships.

    Keyed on the craftRecipe name exactly as it appears in the scripts -- the
    string CraftRecipe:getName() returns. Register a recipe here and opening a
    can through it carries the same injury risk as vanilla's knife and
    sharp-stone variants.

    Empty by default: the base game's four are held in BQoL_CanInjuryLogic,
    not here, so a mod cannot accidentally unregister them.
]]
local canInjuryRecipes = {}

--- Registers a craftRecipe name as an improvised can-opening recipe.
function BQoL.API.addCanInjuryRecipe(recipeName)
    if type(recipeName) ~= "string" or recipeName == "" then
        BQoL.warn("addCanInjuryRecipe: expected a craft recipe name string")
        return false
    end

    canInjuryRecipes[recipeName] = true
    BQoL.log("registered can-injury recipe %s", recipeName)
    return true
end

--- Unregisters a can-opening recipe. Returns true if it was registered.
function BQoL.API.removeCanInjuryRecipe(recipeName)
    if not canInjuryRecipes[recipeName] then return false end

    canInjuryRecipes[recipeName] = nil
    return true
end

--- Read-only view of the registered can-opening recipes, as a set.
function BQoL.API.getCanInjuryRecipes()
    return canInjuryRecipes
end

-- ------------------------------------------------- reinforced door sprites

--[[
    Doors that need a higher Strength level to force. Sprite-keyed because the
    base game exposes no property or tag that distinguishes them, so map mods
    adding their own reinforced doors need to register them here.
]]
local reinforcedDoorSprites = {}

--- Registers a sprite name as a reinforced door.
function BQoL.API.addReinforcedDoorSprite(spriteName)
    if type(spriteName) ~= "string" or spriteName == "" then
        BQoL.warn("addReinforcedDoorSprite: expected a sprite name string")
        return false
    end

    reinforcedDoorSprites[spriteName] = true
    return true
end

--- Read-only view of the reinforced door sprites, as a set.
function BQoL.API.getReinforcedDoorSprites()
    return reinforcedDoorSprites
end

-- ---------------------------------------------------------- debris mapping

--[[
    Maps a world sprite name to the items collecting it yields.

    Each mapping is a list of { fullType, count } pairs. An empty list means the
    sprite is removable but drops nothing.
]]
local debrisMappings = {}

--- Registers what a sprite yields when collected. Overwrites any existing entry.
function BQoL.API.addDebrisMapping(spriteName, items)
    if type(spriteName) ~= "string" or spriteName == "" then
        BQoL.warn("addDebrisMapping: expected a sprite name string")
        return false
    end

    if type(items) ~= "table" then
        BQoL.warn("addDebrisMapping(%s): expected a table of { fullType, count }", spriteName)
        return false
    end

    debrisMappings[spriteName] = items
    return true
end

--- Bulk registration. `mappings` is a table of spriteName -> item list.
function BQoL.API.addDebrisMappings(mappings)
    if type(mappings) ~= "table" then
        BQoL.warn("addDebrisMappings: expected a table")
        return false
    end

    local count = 0
    for spriteName, items in pairs(mappings) do
        if BQoL.API.addDebrisMapping(spriteName, items) then
            count = count + 1
        end
    end

    return count
end

--- Returns the item list for a sprite, or nil when it is not collectable.
function BQoL.API.getDebrisMapping(spriteName)
    return debrisMappings[spriteName]
end

-- -------------------------------------------------------- jumbo tree sprites

--[[
    Extra sprite names the tree canopy fix should treat as jumbo trees.

    Vanilla jumbo trees are detected by their IsoTree size (>= 5) plus the
    trunk/treetop sprite names in IsoTreeJumbo.Jumbos, so nothing needs
    registering for the base game. This table is the escape hatch for map mods
    that ship their own oversized trees with custom sprite names.

    `role` is "canopy" or "trunk": canopy sprites are faded while driving or
    walking past, trunk sprites are left fully visible so what you can hit
    stays in view. Registering a sprite as a trunk only matters indoors,
    where both roles are hidden -- it tells the feature the sprite belongs to
    a jumbo tree at all.
]]
local jumboTreeSprites = {}

--- Registers a sprite name as part of a jumbo tree. role is "canopy" or "trunk".
function BQoL.API.addJumboTreeSprite(spriteName, role)
    if type(spriteName) ~= "string" or spriteName == "" then
        BQoL.warn("addJumboTreeSprite: expected a sprite name string")
        return false
    end

    if role ~= "canopy" and role ~= "trunk" then
        BQoL.warn("addJumboTreeSprite(%s): role must be \"canopy\" or \"trunk\"", spriteName)
        return false
    end

    jumboTreeSprites[spriteName] = role
    BQoL.log("registered jumbo tree sprite %s (%s)", spriteName, role)
    return true
end

--- Unregisters a jumbo tree sprite. Returns true if it was registered.
function BQoL.API.removeJumboTreeSprite(spriteName)
    if not jumboTreeSprites[spriteName] then return false end

    jumboTreeSprites[spriteName] = nil
    return true
end

--- Read-only view of the registered jumbo tree sprites, sprite name -> role.
function BQoL.API.getJumboTreeSprites()
    return jumboTreeSprites
end
