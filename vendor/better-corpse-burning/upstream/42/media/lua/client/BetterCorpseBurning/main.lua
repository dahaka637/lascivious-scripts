local BCBConfig = require("BetterCorpseBurning/config")
local BCBActions = require("BetterCorpseBurning/bcb_actions")

local TEXT_QUICK = getText("IGUI_BCB_QuickBurnCorpse")

local function onQuickBurn(worldobjects, playerIdx, corpse)
	local playerObj = getSpecificPlayer(playerIdx)
	if not (corpse and corpse:getSquare()) then return end
	if luautils.walkAdj(playerObj, corpse:getSquare()) then
		ISTimedActionQueue.add(BCBActions.BurnAction:new(playerObj, corpse))
	end
end

Events.OnFillWorldObjectContextMenu.Add(function(playerIdx, context, worldobjects, test)
	if test then return end
	local playerObj = getSpecificPlayer(playerIdx)
	if not playerObj then return end

	if BCBConfig.REMOVE_VANILLA_BURN then
		context:removeOptionByName(getText("ContextMenu_Burn_Corpse"))
	end

	local fire = BCBActions.findFireItem(playerObj)
	if not fire then return end

	if BCBConfig.NEED_PETROL then
		local petrol = BCBActions.findPetrolItem(playerObj)
		if not petrol then return end
	end

	local seenSquares = {}
	for _, obj in ipairs(worldobjects) do
		local square = obj and obj.getSquare and obj:getSquare()
		if square and not seenSquares[square] then
			seenSquares[square] = true
			local corpses = BCBActions.findCorpsesOnSquare(square)
			if #corpses > 0 and (BCBConfig.ALLOW_INDOOR or not BCBActions.isIndoorSquare(square)) then
				local fireIcon = fire:getTex():splitIcon()
				local optQuick = context:addOption(TEXT_QUICK, worldobjects, onQuickBurn, playerIdx, corpses[1])
				optQuick.iconTexture = fireIcon
			end
		end
	end
end)

print("[BetterCorpseBurning] loaded")
