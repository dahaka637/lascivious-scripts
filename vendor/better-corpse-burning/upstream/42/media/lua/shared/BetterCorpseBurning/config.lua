local BCBConfig = {}

local function getVal(optionName, default)
	local ok, result = pcall(function()
		local opt = getSandboxOptions():getOptionByName("BetterCorpseBurning." .. optionName)
		if opt then
			return opt:getValue()
		end
		return nil
	end)
	if ok and result ~= nil then
		return result
	end
	return default
end

setmetatable(BCBConfig, {
	__index = function(t, key)
		if key == "TIME_PER_CORPSE" then return getVal("TimePerCorpse", 110) end
		if key == "FIRE_SPREAD_RADIUS" then return getVal("FireSpreadRadius", 4) end
		if key == "REMOVE_VANILLA_BURN" then return getVal("RemoveVanillaBurn", true) end
		if key == "NEED_PETROL" then return getVal("NeedPetrol", false) end
		if key == "PETROL_PER_BURN" then return getVal("PetrolPerBurn", 0.1) end
		if key == "ALLOW_INDOOR" then return getVal("AllowIndoorBurn", true) end
		if key == "FIRE_USES_PER_CORPSE" then return getVal("FireUsesPerCorpse", 1) end
		if key == "AUTO_EXTINGUISH" then return getVal("AutoExtinguishWhenDone", false) end
		if key == "NO_ASH" then return getVal("NoAshRemains", false) end
		if key == "FIRE_SPREAD_SPEED" then return getVal("FireSpreadSpeed", 150) end
		return rawget(t, key)
	end
})

return BCBConfig
