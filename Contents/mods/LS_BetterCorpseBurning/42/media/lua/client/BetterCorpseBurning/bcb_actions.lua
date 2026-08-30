require "TimedActions/ISBaseTimedAction"

local BCBConfig = require("BetterCorpseBurning/config")
local BCB = {}

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

local function findFireItem(character)
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

local function findPetrolInContainer(container, need)
	if not container then return nil end
	local items = container:getItems()
	if not items then return nil end
	for i = 0, items:size() - 1 do
		local item = items:get(i)
		local fc = item.getFluidContainer and item:getFluidContainer()
		if fc and fc:contains(Fluid.Petrol) and fc:getAmount() >= need - 0.001 then
			return item
		end
		if item.getInventory then
			local found = findPetrolInContainer(item:getInventory(), need)
			if found then return found end
		end
	end
	return nil
end

local function findPetrolItem(character)
	local need = math.max(0, tonumber(BCBConfig.PETROL_PER_BURN) or 0.1)
	return findPetrolInContainer(character:getInventory(), need)
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

local function consumeResources(character)
	local fire = findFireItem(character)
	if not fire then return false end

	local petrol
	if BCBConfig.NEED_PETROL then
		petrol = findPetrolItem(character)
		if not petrol then return false end
	end

	local uses = math.max(0, math.floor(tonumber(BCBConfig.FIRE_USES_PER_CORPSE) or 1))
	for _ = 1, uses do
		if not isUsableFire(fire) then
			fire = findFireItem(character)
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
	return true
end

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

local function finishBurn(action)
	if action.bcbDone then return true end
	local square = action.corpse and action.corpse:getSquare()
	if not square then return false end

	action.bcbDone = true
	if isClient() then
		-- The server resolves the corpse, validates distance and consumes resources.
		sendClientCommand(action.character, "BCB", "burnCorpse", {
			x = square:getX(),
			y = square:getY(),
			z = square:getZ(),
		})
	else
		-- Single-player has no server command handler.
		if not consumeResources(action.character) then return false end
		pcall(action.character.burnCorpse, action.character, action.corpse)
	end
	return true
end

function ISBCBBurnAction:update()
	self.character:faceThisObject(self.corpse)

	-- Build 42 rejects this custom action during normal NetTimedAction completion,
	-- so its result is revalidated authoritatively by our server command handler.
	self.bcbFrame = (self.bcbFrame or 0) + 1
	if not self.bcbDone and self.bcbFrame >= self.maxTime then
		finishBurn(self)
		ISBaseTimedAction.stop(self)
	end
end

function ISBCBBurnAction:start()
	self:setActionAnim(CharacterActionAnims.Pour)
end

function ISBCBBurnAction:stop()
	ISBaseTimedAction.stop(self)
end

function ISBCBBurnAction:perform()
	if not self.bcbDone then finishBurn(self) end
	ISBaseTimedAction.perform(self)
end

function ISBCBBurnAction:complete()
	return finishBurn(self)
end

function ISBCBBurnAction:getDuration()
	local duration = BCBConfig.TIME_PER_CORPSE or 110
	if self.character:isTimedActionInstant() then duration = 50 end
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
