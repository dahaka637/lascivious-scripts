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
if gameMode == "MP_Client" then
	print("UCWF | UnifiedCarryWeightFramework | Detected " .. gameMode .. " environment, skipping the file")
	return
else
	print("UCWF | UnifiedCarryWeightFramework | Detected " .. gameMode .. " environment, loading the file")
end

UnifiedCarryWeightFramework = UnifiedCarryWeightFramework or {}

UnifiedCarryWeightFramework.baseModifiers = UnifiedCarryWeightFramework.baseModifiers or {}
UnifiedCarryWeightFramework.maxModifiers = UnifiedCarryWeightFramework.maxModifiers or {}

function UnifiedCarryWeightFramework.log(...)
	if SandboxVars.UnifiedCarryWeightFramework.GatherDetailedDebug then
		print("UCWF | UnifiedCarryWeightFramework | " .. ...)
	end
end

local systemShouldRun = false

---Function that applies a list of modifiers to a starting value, returning the final modified value.
---@param startValue number
---@param modifiers table
---@param context table
---@return number
local function applyModifierPipeline(startValue, modifiers, context)
	local totalAdd = 0
	local totalMult = 1.0

	for _, modifier in pairs(modifiers) do
		local result = modifier.resolve(context)

		if result then
			if result.add ~= nil then
				totalAdd = totalAdd + result.add
			end

			if result.mult ~= nil then
				totalMult = totalMult * result.mult
			end
		end
	end

	return (startValue + totalAdd) * totalMult
end

--- Function that registers a modifier to be applied to base carry weight
--- @param def any
function UnifiedCarryWeightFramework.registerBaseModifier(def)
	assert(type(def) == "table", "registerBaseModifier(def): def must be a table")
	assert(def.id ~= nil, "registerBaseModifier(def): def.id is required")
	assert(type(def.resolve) == "function", "registerBaseModifier(def): def.resolve must be a function")

	print("UCWF | UnifiedCarryWeightFramework | Registering base modifier: " .. tostring(def.id))

	UnifiedCarryWeightFramework.baseModifiers[def.id] = def
	systemShouldRun = true
end

--- Function that registers a modifier to be applied to max carry weight after base weight is calculated
--- @param def any
function UnifiedCarryWeightFramework.registerMaxModifier(def)
	assert(type(def) == "table", "registerMaxModifier(def): def must be a table")
	assert(def.id ~= nil, "registerMaxModifier(def): def.id is required")
	assert(type(def.resolve) == "function", "registerMaxModifier(def): def.resolve must be a function")

	print("UCWF | UnifiedCarryWeightFramework | Registering max modifier: " .. tostring(def.id))
	UnifiedCarryWeightFramework.maxModifiers[def.id] = def
	systemShouldRun = true
end

local playersListCache = nil
local pendingMaxRecomputeTicks = 0
local pendingPlayersSet = {}
local pendingAllPlayers = false

local function getFrameworkPlayerData(player)
	local modData = player:getModData()
	modData.UCWF = modData.UCWF or {}
	return modData.UCWF
end

--- Function that returns a list of players to apply modifiers for. If player argument is passed, returns a list with just that player, otherwise returns a list of all players (for server).
--- @param player any
--- @return table<IsoPlayer>
local function getPlayerList(player)
	if player then
		return { player }
	end

	local players = {}
	local onlinePlayers = getOnlinePlayers()

	for i = 0, onlinePlayers:size() - 1 do
		players[#players + 1] = onlinePlayers:get(i)
	end

	if #players == 0 then
		local localPlayer = getPlayer()
		if localPlayer then
			players[#players + 1] = localPlayer
		end
	end

	return players
end

local function queuePlayersForMaxRecompute(player)
	if player == nil then
		pendingAllPlayers = true
		pendingPlayersSet = {}
		return
	end

	if pendingAllPlayers then
		return
	end

	pendingPlayersSet[player] = true
end

local function consumeQueuedPlayersForMaxRecompute()
	if pendingAllPlayers then
		pendingAllPlayers = false
		pendingPlayersSet = {}
		return getPlayerList()
	end

	local players = {}
	for player, _ in pairs(pendingPlayersSet) do
		players[#players + 1] = player
	end
	pendingPlayersSet = {}
	return players
end

local function recomputeTotalCarryWeight()
	for _, player in ipairs(playersListCache) do
		UnifiedCarryWeightFramework.log("Recomputing max carry weight for player " .. tostring(player:getUsername()))
		local frameworkPlayerData = getFrameworkPlayerData(player)
		local lastAppliedDelta = frameworkPlayerData.lastAppliedMaxWeightDelta or 1
		local lastBaseMaxWeight = frameworkPlayerData.lastBaseMaxWeight
		player:setMaxWeightDelta(1)

		local maxContext = {
			player = player,
		}
		local observedMaxWeight = player:getMaxWeight()
		local currentMaxWeight = observedMaxWeight
		if lastAppliedDelta > 0 and lastBaseMaxWeight ~= nil then
			local previousModifiedWeight = lastBaseMaxWeight * lastAppliedDelta
			if math.abs(observedMaxWeight - previousModifiedWeight) < 0.001 then
				currentMaxWeight = lastBaseMaxWeight
			end
		end
		UnifiedCarryWeightFramework.log("Observed max weight before normalization: " .. tostring(observedMaxWeight))
		UnifiedCarryWeightFramework.log("Current max weight before max modifiers: " .. tostring(currentMaxWeight))
		local newMaxWeight =
			applyModifierPipeline(currentMaxWeight, UnifiedCarryWeightFramework.maxModifiers, maxContext)
		if SandboxVars.UnifiedCarryWeightFramework.CapWeight then
			newMaxWeight = math.min(newMaxWeight, 50)
		end
		UnifiedCarryWeightFramework.log("Target max weight: " .. tostring(newMaxWeight))
		local deltaToSet = newMaxWeight / currentMaxWeight
		UnifiedCarryWeightFramework.log("Setting max weight delta to: " .. tostring(deltaToSet))

		player:setMaxWeightDelta(deltaToSet)
		frameworkPlayerData.lastAppliedMaxWeightDelta = deltaToSet
		frameworkPlayerData.lastBaseMaxWeight = currentMaxWeight
	end
end

local function recomputeTotalCarryWeightOnTickHelper()
	if pendingMaxRecomputeTicks > 0 then
		pendingMaxRecomputeTicks = pendingMaxRecomputeTicks - 1
		return
	end
	playersListCache = consumeQueuedPlayersForMaxRecompute()
	if #playersListCache == 0 then
		Events.OnTick.Remove(recomputeTotalCarryWeightOnTickHelper)
		return
	end
	recomputeTotalCarryWeight()
	Events.OnTick.Remove(recomputeTotalCarryWeightOnTickHelper)
end

--- Function that recomputes the carry weight for player (if passed as an argument) or all players, applying all modifiers in the correct ordering
--- @param player IsoPlayer|nil
function UnifiedCarryWeightFramework.recomputeAll(player)
	if not systemShouldRun then
		UnifiedCarryWeightFramework.log(
			"No carry weight modifiers registered, skipping recompute and unregistering events"
		)
		Events.EveryHours.Remove(recomputeCarryWeight_EveryHours)
		Events.EveryHours.Remove(debugDumpCarryWeight_EveryHours)
		return
	end
	queuePlayersForMaxRecompute(player)
	playersListCache = getPlayerList(player)
	for _, player in ipairs(playersListCache) do
		UnifiedCarryWeightFramework.log("Recomputing base carry weight for player " .. tostring(player:getUsername()))
		local originalBaseWeight = 8
		player:setMaxWeightDelta(1)

		local baseContext = {
			player = player,
		}

		local newBaseWeight =
			applyModifierPipeline(originalBaseWeight, UnifiedCarryWeightFramework.baseModifiers, baseContext)
		UnifiedCarryWeightFramework.log("New base weight: " .. tostring(newBaseWeight))
		player:setMaxWeightBase(newBaseWeight)
	end
	Events.OnTick.Remove(recomputeTotalCarryWeightOnTickHelper)
	pendingMaxRecomputeTicks = 1
	Events.OnTick.Add(recomputeTotalCarryWeightOnTickHelper)
end

---Just for SP
---@param playerIndex number
---@param player IsoPlayer
local function recomputeCarryWeight_OnCreatePlayer(playerIndex, player)
	UnifiedCarryWeightFramework.recomputeAll(player)
end

local function recomputeCarryWeight_EveryHours()
	UnifiedCarryWeightFramework.recomputeAll()
end

local function debugDumpCarryWeight_EveryHours()
	for _, player in ipairs(getPlayerList(getPlayer())) do
		UnifiedCarryWeightFramework.log("Dumping carry weight modifiers for player " .. tostring(player:getUsername()))
		for id, modifier in pairs(UnifiedCarryWeightFramework.baseModifiers) do
			local result = modifier.resolve({ player = player }) or {}
			UnifiedCarryWeightFramework.log(
				"Base Modifier: "
					.. tostring(id)
					.. " resolved to: { add="
					.. tostring(result.add)
					.. ", mult="
					.. tostring(result.mult)
					.. "}"
			)
		end
		for id, modifier in pairs(UnifiedCarryWeightFramework.maxModifiers) do
			local result = modifier.resolve({ player = player }) or {}
			UnifiedCarryWeightFramework.log(
				"Max Modifier: "
					.. tostring(id)
					.. " resolved to: { add="
					.. tostring(result.add)
					.. ", mult="
					.. tostring(result.mult)
					.. "}"
			)
		end
	end
end

Events.EveryHours.Remove(recomputeCarryWeight_EveryHours)
Events.EveryHours.Add(recomputeCarryWeight_EveryHours)
Events.EveryHours.Remove(debugDumpCarryWeight_EveryHours)
Events.EveryHours.Add(debugDumpCarryWeight_EveryHours)

-- in case it's SP these 2 will work
Events.OnCreatePlayer.Remove(recomputeCarryWeight_OnCreatePlayer)
Events.OnCreatePlayer.Add(recomputeCarryWeight_OnCreatePlayer)

return UnifiedCarryWeightFramework
