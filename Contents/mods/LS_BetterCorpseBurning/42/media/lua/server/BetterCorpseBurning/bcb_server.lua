require "TimedActions/ISBaseTimedAction"

local BCBConfig = require("BetterCorpseBurning/config")

local MAX_BURN_DISTANCE_SQ = 1.8 * 1.8
local MAX_SPREAD_RADIUS = 5
local EXTINGUISH_DELAY_FRAMES = 600
local ASH_CHECK_INTERVAL = 30

local spreadQueue = {}
local queuedSpreadSquares = {}
local spreadFrameCount = 0
local spreadActive = false
local extinguishSquares = {}
local extinguishAtFrame = nil
local ashWatchList = {}
local onSpreadTick

local function squareKey(square)
	return tostring(math.floor(square:getX())) .. ":" .. tostring(math.floor(square:getY())) .. ":" .. tostring(square:getZ())
end

local function getFramesPerTile()
	return math.max(1, math.floor(tonumber(BCBConfig.FIRE_SPREAD_SPEED) or 150))
end

local function ensureTickActive()
	if not spreadActive then
		spreadActive = true
		Events.OnTick.Add(onSpreadTick)
	end
end

local function trackExtinguish(square)
	if not BCBConfig.AUTO_EXTINGUISH or not square then return end
	extinguishSquares[#extinguishSquares + 1] = square
	extinguishAtFrame = nil
	ensureTickActive()
end

local function stopFireOnSquare(square)
	local ok, err = pcall(stopFire, square)
	if not ok then print("[BCB] stopFire failed: " .. tostring(err)) end
end

local function removeBurntTiles(square)
	local okObjs, objects = pcall(square.getObjects, square)
	if not okObjs or not objects then return 0 end
	for i = objects:size() - 1, 0, -1 do
		local obj = objects:get(i)
		local okSpr, sprite = pcall(obj.getSprite, obj)
		local okName, name = false, nil
		if okSpr and sprite then okName, name = pcall(sprite.getName, sprite) end
		if okName and name and tostring(name):find("floors_burnt_01_", 1, true) then
			pcall(square.transmitRemoveItemFromSquare, square, obj)
			pcall(objects.remove, objects, obj)
		end
	end

	local remaining = 0
	local okAfter, objectsAfter = pcall(square.getObjects, square)
	if okAfter and objectsAfter then
		for i = 0, objectsAfter:size() - 1 do
			local obj = objectsAfter:get(i)
			local okSpr, sprite = pcall(obj.getSprite, obj)
			local okName, name = false, nil
			if okSpr and sprite then okName, name = pcall(sprite.getName, sprite) end
			if okName and name and tostring(name):find("floors_burnt_01_", 1, true) then
				remaining = remaining + 1
			end
		end
	end
	return remaining
end

local function checkAshWatchList()
	for i = #ashWatchList, 1, -1 do
		local watch = ashWatchList[i]
		local square = getCell():getGridSquare(watch.x, watch.y, watch.z)
		if not square then
			table.remove(ashWatchList, i)
		else
			local ok, burning = pcall(square.has, square, IsoFlagType.burning)
			if ok and not burning and removeBurntTiles(square) == 0 then
				table.remove(ashWatchList, i)
			end
		end
	end
end

local function serverDisablesFire()
	if not getServerOptions then return false end
	local ok, disabled = pcall(function() return getServerOptions():getBoolean("NoFire") end)
	return ok and disabled == true
end

local function safehouseDisablesFire(square)
	if not getServerOptions or not SafeHouse then return false end
	local okOption, allowed = pcall(function() return getServerOptions():getBoolean("SafehouseAllowFire") end)
	if not okOption or allowed ~= false then return false end
	local okHouse, house = pcall(SafeHouse.getSafeHouse, square)
	return okHouse and house ~= nil
end

local function zoneDisablesFire(square)
	local zones = rawget(_G, "PhunZones")
	if not zones or not zones.getLocation then return false end
	local ok, zone = pcall(zones.getLocation, square)
	return ok and zone and zone.nofire == true
end

local function fireIsForbidden(square)
	return serverDisablesFire() or safehouseDisablesFire(square) or zoneDisablesFire(square)
end

local function findCorpseSquaresNearby(originSquare, radius)
	local found = {}
	if not originSquare then return found end
	local cell = getCell()
	local z = originSquare:getZ()
	local bx = originSquare:getX()
	local by = originSquare:getY()
	local seen = {}
	for dx = -radius, radius do
		for dy = -radius, radius do
			if dx ~= 0 or dy ~= 0 then
				local ok, square = pcall(cell.getGridSquare, cell, bx + dx, by + dy, z)
				if ok and square and not seen[square] and not fireIsForbidden(square) then
					seen[square] = true
					local okObjs, objects = pcall(square.getStaticMovingObjects, square)
					if okObjs and objects then
						for i = 0, objects:size() - 1 do
							if instanceof(objects:get(i), "IsoDeadBody") then
								found[#found + 1] = {square = square, dist = math.abs(dx) + math.abs(dy)}
								break
							end
						end
					end
				end
			end
		end
	end
	table.sort(found, function(a, b) return a.dist < b.dist end)
	return found
end

local function queueSpread(square, frameDelay, spread)
	if not square or fireIsForbidden(square) then return end
	local key = squareKey(square)
	if queuedSpreadSquares[key] then return end
	queuedSpreadSquares[key] = true
	spreadQueue[#spreadQueue + 1] = {
		square = square,
		key = key,
		fireAtFrame = spreadFrameCount + frameDelay,
		spread = spread,
	}
	ensureTickActive()
end

onSpreadTick = function()
	spreadFrameCount = spreadFrameCount + 1
	if not spreadActive then return end

	if #ashWatchList > 0 and spreadFrameCount % ASH_CHECK_INTERVAL == 0 then checkAshWatchList() end

	local toRemove = {}
	for i, entry in ipairs(spreadQueue) do
		if spreadFrameCount >= entry.fireAtFrame then
			queuedSpreadSquares[entry.key] = nil
			if not fireIsForbidden(entry.square) then
				local okFire = pcall(IsoFireManager.StartFire, getCell(), entry.square, true, 100, 500)
				if okFire then
					trackExtinguish(entry.square)
					if BCBConfig.NO_ASH then
						ashWatchList[#ashWatchList + 1] = {
							x = math.floor(entry.square:getX()),
							y = math.floor(entry.square:getY()),
							z = entry.square:getZ(),
						}
					end
					if entry.spread then
						for _, nearby in ipairs(findCorpseSquaresNearby(entry.square, 1)) do
							local okBurning, burning = pcall(nearby.square.has, nearby.square, IsoFlagType.burning)
							if not (okBurning and burning) then
								queueSpread(nearby.square, getFramesPerTile(), true)
							end
						end
					end
				end
			end
			toRemove[#toRemove + 1] = i
		end
	end

	for i = #toRemove, 1, -1 do table.remove(spreadQueue, toRemove[i]) end

	if #spreadQueue == 0 and BCBConfig.AUTO_EXTINGUISH and #extinguishSquares > 0 and not extinguishAtFrame then
		extinguishAtFrame = spreadFrameCount + EXTINGUISH_DELAY_FRAMES
	end
	if extinguishAtFrame and spreadFrameCount >= extinguishAtFrame then
		for _, square in ipairs(extinguishSquares) do
			local ok, burning = pcall(square.has, square, IsoFlagType.burning)
			if ok and burning then stopFireOnSquare(square) end
		end
		extinguishSquares = {}
		extinguishAtFrame = nil
	end
	if #spreadQueue == 0 and not extinguishAtFrame and #ashWatchList == 0 then
		spreadActive = false
		Events.OnTick.Remove(onSpreadTick)
	end
end

local function isUsableFire(item)
	if item == nil then return false end
	if instanceof(item, "DrainableComboItem") and item.getCurrentUsesFloat then
		local ok, val = pcall(item.getCurrentUsesFloat, item)
		if ok and val ~= nil then return val > 0 end
	end
	if item.getDrainableUsesLeft then
		local ok, val = pcall(item.getDrainableUsesLeft, item)
		if ok and val ~= nil then return val > 0 end
	end
	if item.getUsedDelta then
		local ok, val = pcall(item.getUsedDelta, item)
		if ok and val ~= nil then return val > 0 end
	end
	return true
end

local function findFireItem(player)
	local inv = player:getInventory()
	local ok, tagged = pcall(inv.getAllTagRecurse, inv, ItemTag.START_FIRE, ArrayList.new())
	if ok and tagged then
		for i = 0, tagged:size() - 1 do
			local item = tagged:get(i)
			if isUsableFire(item) then return item end
		end
	end
	for _, typeName in ipairs({"Lighter", "LighterBBQ", "Lighter_Battery", "LighterDisposable", "Matches", "Matchbox"}) do
		local items = inv:getAllTypeRecurse(typeName, ArrayList.new())
		if items then
			for i = 0, items:size() - 1 do
				local item = items:get(i)
				if isUsableFire(item) then return item end
			end
		end
	end
	return nil
end

local function findPetrolInContainer(container, need)
	if not container then return nil end
	local items = container:getItems()
	if not items then return nil end
	for i = 0, items:size() - 1 do
		local item = items:get(i)
		local fc = item.getFluidContainer and item:getFluidContainer()
		if fc and fc:contains(Fluid.Petrol) and fc:getAmount() >= need - 0.001 then return item end
		if item.getInventory then
			local found = findPetrolInContainer(item:getInventory(), need)
			if found then return found end
		end
	end
	return nil
end

local function findPetrolItem(player)
	local need = math.max(0, tonumber(BCBConfig.PETROL_PER_BURN) or 0.1)
	return findPetrolInContainer(player:getInventory(), need)
end

local function corpseIsOnFire(corpse)
	local square = corpse and corpse:getSquare()
	if not square then return false end
	local ok, burning = pcall(square.has, square, IsoFlagType.burning)
	if ok and burning then return true end
	return corpse.isOnFire and corpse:isOnFire() or false
end

local function findBurnableCorpse(square)
	local objects = square and square:getStaticMovingObjects()
	if not objects then return nil end
	for i = 0, objects:size() - 1 do
		local obj = objects:get(i)
		if instanceof(obj, "IsoDeadBody") and obj:getStaticMovingObjectIndex() >= 0 and not corpseIsOnFire(obj) then
			return obj
		end
	end
	return nil
end

local function validInteger(value)
	local number = tonumber(value)
	if not number or number ~= number or number == math.huge or number == -math.huge then return nil end
	if number ~= math.floor(number) or math.abs(number) > 1000000 then return nil end
	return number
end

local function resolveRequest(player, args)
	if not player or player:isDead() or type(args) ~= "table" then return nil end
	local x, y, z = validInteger(args.x), validInteger(args.y), validInteger(args.z)
	if not x or not y or not z then return nil end
	if math.abs(player:getZ() - z) > 0.01 then return nil end
	if player:DistToSquared(x + 0.5, y + 0.5) > MAX_BURN_DISTANCE_SQ then return nil end

	local square = getCell():getGridSquare(x, y, z)
	if not square or fireIsForbidden(square) then return nil end
	if not BCBConfig.ALLOW_INDOOR then
		local okRoom, room = pcall(square.getRoom, square)
		if okRoom and room then return nil end
	end

	local corpse = findBurnableCorpse(square)
	local fire = findFireItem(player)
	if not corpse or not fire then return nil end

	local petrol
	if BCBConfig.NEED_PETROL then
		petrol = findPetrolItem(player)
		if not petrol then return nil end
	end
	return square, corpse, fire, petrol
end

local function consumeResources(player, fire, petrol)
	local uses = math.max(0, math.floor(tonumber(BCBConfig.FIRE_USES_PER_CORPSE) or 1))
	for _ = 1, uses do
		if not isUsableFire(fire) then
			fire = findFireItem(player)
			if not fire then break end
		end
		pcall(fire.UseAndSync, fire)
	end
	if petrol then
		local amount = math.max(0, tonumber(BCBConfig.PETROL_PER_BURN) or 0.1)
		local fc = petrol:getFluidContainer()
		fc:adjustAmount(math.max(0, fc:getAmount() - amount))
		if sendItemStats then sendItemStats(petrol) end
	end
end

local function handleBurnCorpse(player, args)
	local square, corpse, fire, petrol = resolveRequest(player, args)
	if not square then return end

	consumeResources(player, fire, petrol)
	local okFire, err = pcall(player.burnCorpse, player, corpse)
	if not okFire then
		print("[BCB] burnCorpse failed: " .. tostring(err))
		return
	end

	trackExtinguish(square)
	if BCBConfig.NO_ASH then
		ashWatchList[#ashWatchList + 1] = {x = square:getX(), y = square:getY(), z = square:getZ()}
		ensureTickActive()
	end

	local radius = math.max(0, math.min(MAX_SPREAD_RADIUS, math.floor(tonumber(BCBConfig.FIRE_SPREAD_RADIUS) or 0)))
	if radius > 0 then
		for _, entry in ipairs(findCorpseSquaresNearby(square, radius)) do
			queueSpread(entry.square, entry.dist * getFramesPerTile(), true)
		end
	end
end

Events.OnClientCommand.Add(function(module, command, player, args)
	if module == "BCB" and command == "burnCorpse" then handleBurnCorpse(player, args) end
end)

local ISBCBBurnAction = ISBaseTimedAction:derive("BCB_ISBCBBurnAction")
_G[ISBCBBurnAction.Type] = ISBCBBurnAction

print("[BCB] Server-side loaded")
