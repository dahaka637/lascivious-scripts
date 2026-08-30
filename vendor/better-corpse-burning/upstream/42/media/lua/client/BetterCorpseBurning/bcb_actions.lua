require "TimedActions/ISBaseTimedAction"

local BCBConfig = require("BetterCorpseBurning/config")

local BCB = {}

local function isUsableFire(item)
	if item == nil then return false end
	-- Vanilla method: getCurrentUsesFloat() works on DrainableComboItem
	if instanceof(item, "DrainableComboItem") and item.getCurrentUsesFloat then
		local ok, val = pcall(item.getCurrentUsesFloat, item)
		if ok and val ~= nil then
			return val > 0
		end
	end
	-- Fallback: try getDrainableUsesLeft
	if item.getDrainableUsesLeft then
		local ok1, r1 = pcall(item.getDrainableUsesLeft, item)
		if ok1 and r1 ~= nil then
			return r1 > 0
		end
	end
	-- Fallback: try getUsedDelta
	if item.getUsedDelta then
		local ok2, r2 = pcall(item.getUsedDelta, item)
		if ok2 and r2 ~= nil then
			return r2 > 0
		end
	end
	return true
end

local function isCorpseOnFire(corpse)
	if not corpse then return false end
	local square = corpse:getSquare()
	if square then
		local ok, burning = pcall(square.has, square, IsoFlagType.burning)
		if ok and burning then return true end
	end
	if corpse.isOnFire and corpse:isOnFire() then return true end
	return false
end

function findFireItem(character)
	local inv = character:getInventory()
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

BCB.findFireItem = findFireItem

function BCB.isIndoorSquare(square)
	if not square then return false end
	local ok, room = pcall(square.getRoom, square)
	return ok and room ~= nil
end

local function findPetrolItem(character)
	local inv = character:getInventory()
	local items = inv:getItems()
	local need = BCBConfig.PETROL_PER_BURN or 0.1
	if items then
		for i = 0, items:size() - 1 do
			local item = items:get(i)
			local fc = item.getFluidContainer and item:getFluidContainer()
			if fc and fc:contains(Fluid.Petrol) and fc:getAmount() >= need - 0.001 then
				return item
			end
		end
	end
	return nil
end

BCB.findPetrolItem = findPetrolItem

function BCB.findCorpsesOnSquare(square)
	local found = {}
	if not square then return found end
	local okObjs, objects = pcall(square.getStaticMovingObjects, square)
	if not okObjs or not objects then return found end
	for i = 0, objects:size() - 1 do
		local obj = objects:get(i)
		if instanceof(obj, "IsoDeadBody") and not isCorpseOnFire(obj) then
			found[#found + 1] = obj
		end
	end
	return found
end

------------------------------------------------------------
-- Burn a single corpse (fire spread handled by server).
------------------------------------------------------------
local ISBCBBurnAction = ISBaseTimedAction:derive("BCB_ISBCBBurnAction")

function ISBCBBurnAction:isValid()
	if self.corpse == nil then return false end
	if self.corpse:getStaticMovingObjectIndex() < 0 then return false end
	if isCorpseOnFire(self.corpse) then return false end
	if findFireItem(self.character) == nil then return false end
	if BCBConfig.NEED_PETROL and findPetrolItem(self.character) == nil then return false end
	if not BCBConfig.ALLOW_INDOOR and BCB.isIndoorSquare(self.corpse:getSquare()) then return false end
	return true
end

function ISBCBBurnAction:update()
	self.character:faceThisObject(self.corpse)

	-- Build 42 multiplayer: perform() triggers server validation which rejects
	-- custom actions. Use our own frame counter instead of self.current.
	self.bcbFrame = (self.bcbFrame or 0) + 1

	if not self.bcbDone and self.bcbFrame >= self.maxTime then
		self.bcbDone = true

		-- Consume fire item
		local fire = findFireItem(self.character)
		if fire then
			local uses = math.max(0, tonumber(BCBConfig.FIRE_USES_PER_CORPSE) or 1)
			for _ = 1, uses do
				if not isUsableFire(fire) then
					fire = findFireItem(self.character)
					if not fire then break end
				end
				pcall(fire.UseAndSync, fire)
			end
		end

		-- Consume petrol
		if BCBConfig.NEED_PETROL then
			local petrol = findPetrolItem(self.character)
			if petrol then
				local amount = BCBConfig.PETROL_PER_BURN or 0.1
				local fc = petrol:getFluidContainer()
				fc:adjustAmount(fc:getAmount() - amount)
			end
		end

		-- Client-side burn visual
		pcall(self.character.burnCorpse, self.character, self.corpse)

		-- Send to server for fire spread
		local square = self.corpse:getSquare()
		if square then
			sendClientCommand(self.character, "BCB", "burnCorpse", {
				x = square:getX(),
				y = square:getY(),
				z = square:getZ(),
				spreadRadius = BCBConfig.FIRE_SPREAD_RADIUS,
			})
		end

		-- Force-stop the action (bypasses server validation)
		ISBaseTimedAction.stop(self)
	end
end

function ISBCBBurnAction:start()
	self:setActionAnim(CharacterActionAnims.Pour)
end

function ISBCBBurnAction:stop()
	ISBaseTimedAction.stop(self)
end

-- Fallback for singleplayer where perform/complete still work
function ISBCBBurnAction:perform()
	if self.bcbDone then return end
	self.bcbDone = true
	local fire = findFireItem(self.character)
	if fire then
		local uses = math.max(0, tonumber(BCBConfig.FIRE_USES_PER_CORPSE) or 1)
		for _ = 1, uses do
			if not isUsableFire(fire) then
				fire = findFireItem(self.character)
				if not fire then break end
			end
			pcall(fire.UseAndSync, fire)
		end
	end
	if BCBConfig.NEED_PETROL then
		local petrol = findPetrolItem(self.character)
		if petrol then
			local amount = BCBConfig.PETROL_PER_BURN or 0.1
			local fc = petrol:getFluidContainer()
			fc:adjustAmount(fc:getAmount() - amount)
		end
	end
	ISBaseTimedAction.perform(self)
end

function ISBCBBurnAction:complete()
	if self.bcbDone then return end
	self.bcbDone = true
	pcall(self.character.burnCorpse, self.character, self.corpse)
	local square = self.corpse:getSquare()
	if square then
		sendClientCommand(self.character, "BCB", "burnCorpse", {
			x = square:getX(),
			y = square:getY(),
			z = square:getZ(),
			spreadRadius = BCBConfig.FIRE_SPREAD_RADIUS,
		})
	end
	return true
end

function ISBCBBurnAction:getDuration()
	local duration = BCBConfig.TIME_PER_CORPSE or 110
	if self.character:isTimedActionInstant() then
		duration = 50
	end
	return duration
end

function ISBCBBurnAction:new(character, corpse)
	local o = ISBaseTimedAction.new(self, character)
	o.corpse = corpse
	o.maxTime = o:getDuration()
	return o
end

_G[ISBCBBurnAction.Type] = ISBCBBurnAction

BCB.BurnAction = ISBCBBurnAction

return BCB
