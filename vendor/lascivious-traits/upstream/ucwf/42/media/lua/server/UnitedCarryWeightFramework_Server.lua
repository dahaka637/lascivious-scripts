local function gameMode()
	if not isClient() and not isServer() then
		return "SP"
	elseif isClient() then
		return "MP_Client"
	end
	return "MP_Server"
end

local gameMode = gameMode()

-- This should be ran only if it's SP or if it's a server process
if gameMode ~= "MP_Server" then
	print("UCWF | UnifiedCarryWeightFramework_Server | Detected " .. gameMode .. " environment, skipping the file")
	return
else
	print("UCWF | UnifiedCarryWeightFramework_Server | Detected " .. gameMode .. " environment, loading the file")
end

local Commands = {}

require("UnifiedCarryWeightFramework")

function Commands.update_weight(player, args)
	UnifiedCarryWeightFramework.recomputeAll(player)
end

Commands.OnClientCommand = function(module, command, player, args)
	if module == "UCWF" and Commands[command] then
		local argStr = ""
		args = args or {}
		for k, v in pairs(args) do
			argStr = argStr .. " " .. k .. "=" .. tostring(v)
		end
		if SandboxVars.UnifiedCarryWeightFramework.GatherDetailedDebug then
			print(
				"UCWF | UnifiedCarryWeightFramework_Server | Received command: " .. command .. " with args:" .. argStr
			)
		end
		Commands[command](player, args)
	end
end

Events.OnClientCommand.Add(Commands.OnClientCommand)
