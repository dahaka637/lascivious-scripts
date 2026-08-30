--[[
    Burris Quality of Life -- cutting yourself opening a can.

    Decision logic only: which recipes count as opening a can without a proper
    opener, and whether an attempt draws blood. The wiring that watches for a
    finished craft lives in client/BQoL/BQoL_CanInjury.lua.

    Split this way because these two answers are the part worth testing, and
    because everything else in this mod that has both a rule and a hook is
    split the same way (BQoL_TourniquetLogic, BQoL_TreeCanopyLogic,
    BQoL_ZombieCollisionLogic).
]]

require "BQoL/BQoL_Core"

BQoL = BQoL or {}
BQoL.CanInjury = BQoL.CanInjury or {}

local CanInjury = BQoL.CanInjury

--[[
    The B42.20 recipes that open a can with something that is not a can opener.

    Taken from scripts/generated/recipes/recipes_cannedFood.txt. Vanilla pairs
    every can with two recipes -- a clean one needing base:canopener and an
    improvised one needing base:sharpknife or a sharp stone flake -- and it is
    only the second kind that should cost you skin.

    Matched on the recipe name rather than the OnCreate callback for a reason.
    The obvious hook, `OnCreate = RecipeCodeOnCreate.openCan`, is a Java class
    (zombie.scripting.logic.RecipeCodeOnCreate) and cannot be replaced from
    Lua; worse, the callbacks are not one-to-one with the recipes.
    OpenUnlabeledCan and OpenUnlabeledCanWithKnifeOrSharpStoneFlake both use
    openMysteryCan, so hooking it would injure people using a proper opener.
    The recipe name is the only thing that actually distinguishes them.
]]
local VANILLA_RECIPES = {
    OpenCannedFoodWithKnifeOrSharpStoneFlake        = true,
    OpenUnlabeledCanWithKnifeOrSharpStoneFlake      = true,
    OpenDentedUnlabeledCanWithKnifeOrSharpStoneFlake = true,
    OpenWaterRationCanWithKnifeOrSharpStoneFlake    = true,
}

--[[
    True when this craft recipe is opening a can the hard way.

    Held here rather than seeded into the API table so a mod calling
    removeCanInjuryRecipe cannot switch the base game's four off by accident.
]]
function CanInjury.isImprovised(recipeName)
    if type(recipeName) ~= "string" or recipeName == "" then return false end
    if VANILLA_RECIPES[recipeName] then return true end

    return BQoL.API.getCanInjuryRecipes()[recipeName] == true
end

--[[
    Rolls whether this particular can bites back.

    Chance is a straight percentage; 0 never cuts and 100 always does, which
    is what makes the sandbox option testable in game.
]]
function CanInjury.roll()
    local chance = BQoL.getNumber("CanInjuryChance")
    chance = math.max(0, math.min(100, chance))

    if chance <= 0 then return false end
    return ZombRand(100) < chance
end

--[[
    How bad the cut is.

    setScratched itself takes only booleans -- the severity knobs on BodyPart
    are setBleedingTime and setAdditionalPain -- so CanInjurySeverity scales
    those instead. The bases are deliberately mild: opening cans with a knife
    should be a bad habit that accumulates, not a tin of beans that takes you
    out of the game.

    Pain is clamped to the 0..100 the stat uses; bleeding is only floored,
    since a server owner winding severity up is asking for exactly that.
]]
local BASE_BLEED_TIME = 8
local BASE_EXTRA_PAIN = 10

local function severityScale()
    return math.max(0, BQoL.getNumber("CanInjurySeverity"))
end

--- Bleeding time in ticks for one cut, scaled by CanInjurySeverity.
function CanInjury.getBleedingTime()
    return math.max(0, BASE_BLEED_TIME * severityScale())
end

--- Extra pain for one cut, scaled by CanInjurySeverity and clamped to 0..100.
function CanInjury.getExtraPain()
    return math.max(0, math.min(100, BASE_EXTRA_PAIN * severityScale()))
end
