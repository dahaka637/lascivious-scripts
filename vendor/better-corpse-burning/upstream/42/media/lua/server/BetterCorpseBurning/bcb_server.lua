-- Server-side handler for Better Corpse Burning
-- Sequential fire spread with chain reaction using IsoFireManager

local BCBConfig = require("BetterCorpseBurning/config")

local spreadQueue = {}
local spreadFrameCount = 0
local spreadActive = false
local function getFramesPerTile()
	return BCBConfig.FIRE_SPREAD_SPEED or 150
end
local EXTINGUISH_DELAY_FRAMES = 600

local extinguishSquares = {}
local extinguishAtFrame = nil
local ashWatchList = {}
local ASH_CHECK_INTERVAL = 30

local function ensureTickActive()
	if not spreadActive then
		spreadActive = true
		Events.OnTick.Add(onSpreadTick)
	end
end

local function trackExtinguish(square)
	if not BCBConfig.AUTO_EXTINGUISH then return end
	if not square then return end
	extinguishSquares[#extinguishSquares + 1] = square
	extinguishAtFrame = nil
	ensureTickActive()
end

--- Ateşi söndür (vanilla ISPutOutFire ile doğrulanmış API)
local function stopFireOnSquare(square)
	-- Server-side: stopFire() global fonksiyonu (Java tarafından expose edilmiş)
	local ok, err = pcall(stopFire, square)
	if ok then
		print("[BCB] stopFire success")
	else
		print("[BCB] stopFire failed: " .. tostring(err))
	end
end

--- Yanık zemin tile'larını kaldır (vanilla ISClearAshes ile doğrulanmış API)
--- Kalan burnt tile sayısını döndürür (0 = temizlendi)
local function removeBurntTiles(square)
	local okObjs, objects = pcall(square.getObjects, square)
	if not okObjs or not objects then return 0 end
	local removed = 0
	for i = objects:size() - 1, 0, -1 do
		local obj = objects:get(i)
		local okSpr, spr = pcall(obj.getSprite, obj)
		if okSpr and spr then
			local okName, nm = pcall(spr.getName, spr)
			if okName and nm and tostring(nm):find("floors_burnt_01_", 1, true) then
				-- Vanilla ISClearAshes: transmitRemoveItemFromSquare + getObjects():remove()
				pcall(square.transmitRemoveItemFromSquare, square, obj)
				pcall(objects.remove, objects, obj)
				removed = removed + 1
				print("[BCB] NoAsh removed: " .. tostring(nm))
			end
		end
	end
	if removed > 0 then
		print("[BCB] NoAsh: removed " .. tostring(removed) .. " burnt tiles")
	end
	-- Hâlâ kalan burnt tile sayısını say
	local remaining = 0
	local okObjs2, objects2 = pcall(square.getObjects, square)
	if okObjs2 and objects2 then
		for i = 0, objects2:size() - 1 do
			local obj = objects2:get(i)
			local okSpr, spr = pcall(obj.getSprite, obj)
			if okSpr and spr then
				local okName, nm = pcall(spr.getName, spr)
				if okName and nm and tostring(nm):find("floors_burnt_01_", 1, true) then
					remaining = remaining + 1
				end
			end
		end
	end
	if remaining > 0 then
		-- Debug: kalan tüm objelerin sprite isimlerini logla
		if okObjs2 and objects2 then
			for i = 0, objects2:size() - 1 do
				local obj = objects2:get(i)
				local okSpr, spr = pcall(obj.getSprite, obj)
				if okSpr and spr then
					local okName, nm = pcall(spr.getName, spr)
					print("[BCB] NoAsh remaining object: " .. tostring(nm))
				end
			end
		end
	end
	return remaining
end

local function checkAshWatchList()
	for i = #ashWatchList, 1, -1 do
		local w = ashWatchList[i]
		local sq = getCell():getGridSquare(w.x, w.y, w.z)
		if not sq then
			table.remove(ashWatchList, i)
		else
		-- Ateş hâlâ yanıyor mu? (vanilla ISPutOutFire: square:has(IsoFlagType.burning))
		local hasFire = false
		local ok, burning = pcall(sq.has, sq, IsoFlagType.burning)
		if ok then hasFire = burning end
			if not hasFire then
				-- Ateş söndü, kül ve yanık zemin temizliği
				local remaining = removeBurntTiles(sq)
				if remaining > 0 then
					-- Hâlâ burnt tile var, bir sonraki kontrole kadar bekle
					print("[BCB] NoAsh: " .. tostring(remaining) .. " tiles still remaining, will retry")
				else
					-- Temizlendi, listeden çıkar
					table.remove(ashWatchList, i)
				end
			end
		end
	end
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
				local ok, sq = pcall(cell.getGridSquare, cell, bx + dx, by + dy, z)
				if ok and sq and not seen[sq] then
					seen[sq] = true
					local okObjs, objects = pcall(sq.getStaticMovingObjects, sq)
					if okObjs and objects then
						for i = 0, objects:size() - 1 do
							local obj = objects:get(i)
							if instanceof(obj, "IsoDeadBody") then
								local dist = math.abs(dx) + math.abs(dy)
								found[#found + 1] = {square = sq, dist = dist}
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
	if not square then return end
	spreadQueue[#spreadQueue + 1] = {
		square = square,
		fireAtFrame = spreadFrameCount + frameDelay,
		spread = spread,
	}
	if not spreadActive then
		spreadActive = true
		Events.OnTick.Add(onSpreadTick)
	end
end

function onSpreadTick()
	spreadFrameCount = spreadFrameCount + 1
	if not spreadActive then return end

	if #ashWatchList > 0 and spreadFrameCount % ASH_CHECK_INTERVAL == 0 then
		checkAshWatchList()
	end

	local toRemove = {}
	for i, entry in ipairs(spreadQueue) do
		if spreadFrameCount >= entry.fireAtFrame then
			local cell = getCell()
			IsoFireManager.StartFire(cell, entry.square, true, 100, 500)

			-- Söndürme için takip et (zincirleme yaysa bile)
			trackExtinguish(entry.square)

			if BCBConfig.NO_ASH then
				ashWatchList[#ashWatchList + 1] = {
					x = math.floor(entry.square:getX()),
					y = math.floor(entry.square:getY()),
					z = entry.square:getZ(),
				}
			end

		if entry.spread then
			local nearby = findCorpseSquaresNearby(entry.square, 1)
			for _, n in ipairs(nearby) do
				local okFire, hasFire = pcall(n.square.has, n.square, IsoFlagType.burning)
				if not (okFire and hasFire) then
					queueSpread(n.square, getFramesPerTile(), true)
				end
			end
		end

			toRemove[#toRemove + 1] = i
		end
	end

	for i = #toRemove, 1, -1 do
		table.remove(spreadQueue, toRemove[i])
	end

	-- Söndürme zamanlayıcısını başlat (tüm yayılım bitince)
	if #spreadQueue == 0 and BCBConfig.AUTO_EXTINGUISH and #extinguishSquares > 0 and not extinguishAtFrame then
		extinguishAtFrame = spreadFrameCount + EXTINGUISH_DELAY_FRAMES
		print("[BCB] Extinguish scheduled in " .. tostring(EXTINGUISH_DELAY_FRAMES) .. " frames, tracking " .. tostring(#extinguishSquares) .. " squares")
	end

	-- Söndürme zamanı geldi
	if extinguishAtFrame and spreadFrameCount >= extinguishAtFrame then
		print("[BCB] Extinguish firing on " .. tostring(#extinguishSquares) .. " squares")
		for _, sq in ipairs(extinguishSquares) do
			local hasFire = false
			local ok, burning = pcall(sq.has, sq, IsoFlagType.burning)
			if ok then hasFire = burning end
			if hasFire then
				stopFireOnSquare(sq)
			end
		end
		extinguishSquares = {}
		extinguishAtFrame = nil
	end

	-- Tick'i kapat (tüm işler bitince)
	if #spreadQueue == 0 and not extinguishAtFrame and #ashWatchList == 0 then
		spreadActive = false
		Events.OnTick.Remove(onSpreadTick)
		print("[BCB] Tick deactivated")
	end
end

Events.OnClientCommand.Add(function(module, command, player, args)
	if module ~= "BCB" then return end
	print("[BCB Server] OnClientCommand: module=" .. tostring(module) .. ", command=" .. tostring(command) .. ", player=" .. tostring(player))
	local cell = getCell()

	if command == "burnCorpse" then
		print("[BCB Server] burnCorpse args: x=" .. tostring(args.x) .. ", y=" .. tostring(args.y) .. ", z=" .. tostring(args.z) .. ", spread=" .. tostring(args.spreadRadius))
		local square = cell:getGridSquare(args.x, args.y, args.z)
		if not square then print("[BCB Server] square not found!") return end

		local okRoom, room = pcall(square.getRoom, square)
		if not BCBConfig.ALLOW_INDOOR and okRoom and room then
			print("[BCB Server] indoor burn not allowed, skipping")
			return
		end

		print("[BCB Server] starting fire on square (" .. square:getX() .. "," .. square:getY() .. "," .. square:getZ() .. ")")
		local okFire, errFire = pcall(IsoFireManager.StartFire, cell, square, true, 100, 500)
		if not okFire then
			print("[BCB Server] StartFire FAILED: " .. tostring(errFire))
		else
			print("[BCB Server] StartFire OK")
		end
		trackExtinguish(square)

		if BCBConfig.NO_ASH then
			ashWatchList[#ashWatchList + 1] = {
				x = math.floor(square:getX()),
				y = math.floor(square:getY()),
				z = square:getZ(),
			}
			ensureTickActive()
		end

		if args.spreadRadius and args.spreadRadius > 0 then
			local nearby = findCorpseSquaresNearby(square, args.spreadRadius)
			print("[BCB Server] fire spread: " .. tostring(#nearby) .. " nearby corpses")
			for _, entry in ipairs(nearby) do
				trackExtinguish(entry.square)
				queueSpread(entry.square, entry.dist * getFramesPerTile(), true)
			end
		end
	else
		print("[BCB Server] unknown command: " .. tostring(command))
	end
end)

-- Register action type on server so it's recognized in multiplayer
-- (client registers via _G[ISBCBBurnAction.Type] = ISBCBBurnAction)
local ISBCBBurnAction = ISBaseTimedAction:derive("BCB_ISBCBBurnAction")
_G[ISBCBBurnAction.Type] = ISBCBBurnAction

print("[BCB] Server-side loaded")
