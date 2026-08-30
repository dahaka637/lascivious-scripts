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
	print("UCWF | UnitedCarryWeightFramework_Client | Detected " .. gameMode .. " environment, skipping the file")
	return
else
	print("UCWF | UnitedCarryWeightFramework_Client | Detected " .. gameMode .. " environment, loading the file")
end

---@param playerIndex number
---@param player IsoPlayer
local function recomputeCarryWeight_delayed_OnCreatePlayer(playerIndex, player)
	if gameMode == "SP" then
		print(
			"UCWF | UnitedCarryWeightFramework_Client | recomputeCarryWeight_OnCreatePlayer | Detected "
				.. gameMode
				.. " environment, recomputing carry weight directly"
		)
		require("UnifiedCarryWeightFramework")
		UnifiedCarryWeightFramework.recomputeAll(player)
	elseif gameMode == "MP_Client" then
		print(
			"UCWF | UnitedCarryWeightFramework_Client | recomputeCarryWeight_OnCreatePlayer | Detected "
				.. gameMode
				.. " environment, sending command to server to recalculate carry weight"
		)
		sendClientCommand(player, "UCWF", "update_weight", {})
	else
		print(
			"UCWF | UnitedCarryWeightFramework_Client | recomputeCarryWeight_OnCreatePlayer | Detected unknown environment, skipping carry weight recalculation"
		)
	end
end

local function delayedCommandAfterPlayerSpawned()
	local player = getPlayer()
	if player then
		recomputeCarryWeight_delayed_OnCreatePlayer(0, player)
		Events.OnTick.Remove(delayedCommandAfterPlayerSpawned)
	end
end

-- OnCreatePlayer are client events so if we're SP or MP client we need to send command to the server
-- Commands are not ready to be received in the same tick when player is created, so we need to delay it by one tick
Events.OnTick.Remove(delayedCommandAfterPlayerSpawned)
Events.OnTick.Add(delayedCommandAfterPlayerSpawned)
