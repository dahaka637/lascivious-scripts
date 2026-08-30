--[[
    Burris Quality of Life -- cutting yourself opening a can.

    Watches for a finished craft and, when it was one of the improvised
    can-opening recipes, rolls for a cut hand. The rules live in
    shared/BQoL/BQoL_CanInjuryLogic.lua.

    Client-only on purpose. ISHandcraftAction:complete runs performRecipe()
    under `if isServer()`, so the same wrapper placed in shared/ would fire on
    both halves of a multiplayer session and injure the player twice for one
    can. A dedicated server never loads client/, so this side alone rolls.
]]

require "BQoL/BQoL_CanInjuryLogic"

--[[
    Hands, and nothing else. Every plausible way to slice yourself on a can
    lid goes through the hand holding it, and vanilla's own equivalent -- the
    cut you take picking up broken glass, ISMoveableSpriteProps.lua:1372 --
    targets a hand too.
]]
local HANDS = { "Hand_L", "Hand_R" }

--[[
    Which hand takes it -- a coin flip.

    Deliberately not derived from the primary hand item. The knife is in one
    hand and the can in the other, and nothing in the API says which of the
    two the lid catches, so weighting it either way would be invented
    precision.
]]
local function pickHand()
    return HANDS[ZombRand(2) + 1]
end

--- Applies the cut. Every Java call guarded; an injury is never worth a crash.
local function injure(playerObj)
    local partName = pickHand()

    BQoL.safe("CanInjury.apply", function()
        local partType = BodyPartType[partName]
        if not partType then return end

        local bodyPart = playerObj:getBodyDamage():getBodyPart(partType)
        if not bodyPart then return end

        -- The pair vanilla uses; the second argument is what makes it a
        -- real wound rather than a cosmetic mark.
        bodyPart:setScratched(true, true)

        --[[
            Severity rides on these rather than on setScratched, which takes
            only booleans. Added to whatever is already there so a second cut
            on an already-bleeding hand makes things worse, not better.
        ]]
        local bleed = BQoL.CanInjury.getBleedingTime()
        if bleed > 0 then
            bodyPart:setBleedingTime(bodyPart:getBleedingTime() + bleed)
        end

        local pain = BQoL.CanInjury.getExtraPain()
        if pain > 0 then
            bodyPart:setAdditionalPain(
                math.min(100, bodyPart:getAdditionalPain() + pain))
        end
    end)

    playerObj:Say(getText("IGUI_BQoL_CanCut"))
    BQoL.log("CanInjury: cut %s opening a can", partName)
end

--[[
    Runs after a craft completes.

    Only the local player is considered: in multiplayer every client runs its
    own action queue, and injuring on someone else's completion would cut the
    wrong character.
]]
local function onCraftComplete(action)
    if not action or not action.character then return end
    if action.character ~= getPlayer() then return end

    local ok, name = BQoL.safe("CanInjury.recipeName", function()
        return action.craftRecipe and action.craftRecipe:getName()
    end)

    if not ok or not name then return end
    if not BQoL.CanInjury.isImprovised(name) then return end
    if not BQoL.CanInjury.roll() then
        BQoL.log("CanInjury: %s opened cleanly", name)
        return
    end

    injure(action.character)
end

BQoL.feature{
    id = "CanInjury",
    sandbox = "CanInjuryEnabled",
    init = function()
        --[[
            ISHandcraftAction is what ISEntityUI.HandcraftStartMultiple builds
            every hand-craft from, and it carries both the recipe
            (craftRecipe:getName(), which vanilla itself reads at line 87) and
            the crafter. Wrapping it beats the recipes' own
            OnCreate = RecipeCodeOnCreate.* hook, which is a Java class and
            cannot be replaced from Lua.
        ]]
        local original = ISHandcraftAction and ISHandcraftAction.complete

        if type(original) ~= "function" then
            BQoL.warn("CanInjury: ISHandcraftAction.complete is missing")
            return
        end

        ISHandcraftAction.complete = function(self, ...)
            local result = original(self, ...)

            -- Never let the injury take the craft down with it.
            BQoL.safe("CanInjury.onCraftComplete", onCraftComplete, self)

            return result
        end
    end,
}
