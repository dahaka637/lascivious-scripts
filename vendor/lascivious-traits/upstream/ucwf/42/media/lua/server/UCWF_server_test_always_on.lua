-- this is just a test file for me to come back to when needed for easy tests.
if true then
	return
end

local function gameMode()
	if not isClient() and not isServer() then
		return "SP"
	elseif isClient() then
		return "MP_Client"
	end
	return "MP_Server"
end

local currentGameMode = gameMode()

if currentGameMode == "MP_Client" then
	print("UCWF_TestAlwaysOn | Detected " .. currentGameMode .. " environment, skipping the file")
	return
else
	print("UCWF_TestAlwaysOn | Detected " .. currentGameMode .. " environment, loading the file")
end

require("UnifiedCarryWeightFramework")

UnifiedCarryWeightFramework.registerBaseModifier({
	id = "UCWF_TestAlwaysOn.BasePlus2",

	resolve = function(ctx)
		return {
			add = 2,
		}
	end,
})

UnifiedCarryWeightFramework.registerMaxModifier({
	id = "UCWF_TestAlwaysOn.MaxPlus5",

	resolve = function(ctx)
		return {
			add = 5,
		}
	end,
})

UnifiedCarryWeightFramework.registerMaxModifier({
	id = "UCWF_TestAlwaysOn.MaxMult1p5",

	resolve = function(ctx)
		return {
			mult = 1.5,
		}
	end,
})

local function recomputeCarryWeight_EveryMinutes()
	UnifiedCarryWeightFramework.recomputeAll()
end

Events.EveryOneMinute.Remove(recomputeCarryWeight_EveryMinutes)
Events.EveryOneMinute.Add(recomputeCarryWeight_EveryMinutes)
