-- this is just to prevent this example file from ever running in-game.
if true then
	return
end

--- Example of how to register modifiers for the Unified Carry Weight Framework.
--- There's extra guard just in case and for debug purposes.

local function gameMode()
	if not isClient() and not isServer() then
		return "SP"
	elseif isClient() then
		return "MP_Client"
	end
	return "MP_Server"
end

local gameMode = gameMode()

if gameMode == "MP_Client" then
	print("YourMod_UCWF | Detected " .. gameMode .. " environment, skipping the file")
	return
else
	print("YourMod_UCWF | Detected " .. gameMode .. " environment, loading the file")
end

require("UnifiedCarryWeightFramework")

--- You register your modifiers by calling the registration functions and passing in a definition table. The definition table must have an id field and a resolve function. The resolve function will be called with a context table that contains the player object and any other relevant information you may need to determine the modifier's effect (at current moment it just has a player). The resolve function should return a table with add and/or mult fields to indicate how much to add or multiply the carry weight by, or return {} if the modifier should not apply.

--- Example of a base modifier that adds to the base carry weight based on a sandbox setting
UnifiedCarryWeightFramework.registerBaseModifier({
	id = "SomeMod.SandboxSettingForBaseWeight", -- id is required. Try making it unique, for example YourMod.ModifierName, to avoid conflicts with other mods.

	resolve = function(ctx)
		--- 8 is default game base weight
		if SandboxVars.SomeMod.SandboxSettingForBaseWeight ~= 8 then
			return {
				add = SandboxVars.SomeMod.SandboxSettingForBaseWeight - 8,
			}
		end

		return {}
	end,
})

UnifiedCarryWeightFramework.registerMaxModifier({
	id = "SomeMod.AthleticGivesCarryWeight",

	resolve = function(ctx)
		local player = ctx.player -- context will always have player object so you should access it from there.

		if player:hasTrait(CharacterTrait.ATHLETIC) then
			return {
				mult = 1.5,
			}
		end
		return {}
	end,
})

-- Framework by default calculates carry weight on character load and every hour afterwards. But what happens if you need to recalculate carry weight from your side? You can just call the recomputeAll function and pass in the player object, and it will recalculate carry weight applying all modifiers in the correct order.

-- Example on how to register weight recalc on server event (such as EveryDays, for example)
UnifiedCarryWeightFramework.registerBaseModifier({
	id = "SomeMod.ExtraCarryWeightSomething",

	resolve = function(ctx)
		local player = ctx.player
		local strengthLevel = player:getPerkLevel(Perks.Strength)
		return {
			add = strengthLevel * 0.25,
		}
	end,
})

local function recomputeCarryWeight_EveryDays()
	-- DO NOT put your logic here, all you have to do is call recomputeAll in here. The logic deciding how much to add or multiply should be in the resolve function of the modifier, and the framework will take care of calling it and applying the modifiers in the correct order.
	UnifiedCarryWeightFramework.recomputeAll()
end

Events.EveryDays.Remove(recomputeCarryWeight_EveryDays)
Events.EveryDays.Add(recomputeCarryWeight_EveryDays)

-- That's all you have to do.
-- !!!!!!!! VERY IMPORTANT !!!!!!!!!
-- You NEED to follow the convention of calling the function that fires on event recomputeCarryWeight_EVENTNAME. So if you want to recalculate carry weight for example on clothes change, it'd be called recomputeCarryWeight_OnClothingUpdated
-- Why? Because if some other mod also wants to do it, we don't want to run framework code twice, so thats why you also have to do this:

Events.OnClothingUpdated.Remove(recomputeCarryWeight_OnClothingUpdated)
Events.OnClothingUpdated.Add(recomputeCarryWeight_OnClothingUpdated)

-- First you unregister the event that might or might not be there. If it is there, you remove it so the framework code is not ran twice, and then you add your own function that calls recomputeAll, which will run the framework code once and apply all modifiers in the correct order. If you don't follow this convention, you might end up with carry weight being recalculated multiple times on the same event, which is inefficient. This is also why you don't put your logic for calculating how much to add or multiply in the event function, but rather in the resolve function of the modifier. Because it's meant to be unregistered by other mod and registered again. You don't have to touch OnCreatePlayer and EveryHours as framework itself already has code for those events.

-- Last example: say you have a mod that has a trait that gives player extra carry weight and they can get the trait midgame. Waiting 1h is not great, and increasing the frequency of recalculations is not needed. In this case you can just add modifier and call recomputeAll when the trait is added to the player.

UnifiedCarryWeightFramework.registerMaxModifier({
	id = "SomeMod.YourTraitModifier",

	resolve = function(ctx)
		local player = ctx.player -- context will always have getPlayer() object so you should access it from there.

		if player:hasTrait(YourRegistry.YourTrait) then
			return {
				add = 1,
				mult = 1.5,
			}
		end
		return {}
	end,
})

local function yourFunctionThatAddsTrait(player)
	if some_condition then
		player:getCharacterTraits():add(YourRegistry.YourTrait)
		UnifiedCarryWeightFramework.recomputeAll(player)
	end
end
