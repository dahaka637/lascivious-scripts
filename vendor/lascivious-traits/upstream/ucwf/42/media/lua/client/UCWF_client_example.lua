-- this is just to prevent this example file from ever running in-game.
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

local gameMode = gameMode()

if gameMode == "MP_Server" then
	print("YourMod_UCWF | Detected " .. gameMode .. " environment, skipping the file")
	return
else
	print("YourMod_UCWF | Detected " .. gameMode .. " environment, loading the file")
end

--- Example of how to fire weight recalculation from your mod when some CLIENT event happens.
--- Remember that you're SUPPOSED to name ur event recomputeCarryWeight_EVENTNAME so later when you register and unregister it, you don't overlap code framework twice
--- More details in server example
local function recomputeCarryWeight_SomeClientSideEvent(character, perk, level, increased)
	if gameMode == "SP" then
		print(
			"YourMod_UCWF | recomputeCarryWeight_SomeClientSideEvent | Detected "
				.. gameMode
				.. " environment, recomputing carry weight directly"
		)
		require("UnifiedCarryWeightFramework")
		UnifiedCarryWeightFramework.recomputeAll()
	elseif gameMode == "MP_Client" then
		print(
			"YourMod_UCWF | recomputeCarryWeight_SomeClientSideEvent | Detected "
				.. gameMode
				.. " environment, sending command to server to recalculate carry weight"
		)
		--- this is the exact syntax for sending command to server to recalculate carry weight
		sendClientCommand(player, "UCWF", "update_weight", {})
	end
end

Events.SomeClientSideEvent.Remove(recomputeCarryWeight_SomeClientSideEvent)
Events.SomeClientSideEvent.Add(recomputeCarryWeight_SomeClientSideEvent)
