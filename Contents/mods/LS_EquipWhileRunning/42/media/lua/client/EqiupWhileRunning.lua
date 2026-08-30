-- Configuration & Mod Options
local RunningActionsConfig = {
    allowClothingWhileRunning = true,
    allowTransfersWhileRunning = true,
    allowspeedpenalty = false,
    allowclothingspeedpenalty = true,
    allowspeedpenaltyfortransfer = true
}

local function ApplyRunningActionsOptions()
    local options = PZAPI.ModOptions:getOptions("RunningActionsMod")
    if not options then return end

    RunningActionsConfig.allowClothingWhileRunning = options:getOption("clothingRun"):getValue()
    RunningActionsConfig.allowTransfersWhileRunning = options:getOption("transferRun"):getValue()
    RunningActionsConfig.allowspeedpenalty = options:getOption("speedpenalty"):getValue()
    RunningActionsConfig.allowclothingspeedpenalty = options:getOption("speedpenaltyforclothing"):getValue()
    RunningActionsConfig.allowspeedpenaltyfortransfer = options:getOption("speedpenaltyfortransfer"):getValue()
end

local function InitRunningActionsOptions()
    local options = PZAPI.ModOptions:create("RunningActionsMod", "Equip While Running")

    options:addTickBox("clothingRun", "Allow Clothing To Be Equipped/Unequipped", true, "Toggle whether clothing can be worn or removed while running.")
    options:addTickBox("transferRun", "Allow Transferring Between Containers", true, "Toggle whether transferring between containers and actions that depend on them can be done while running.")
    options:addTickBox("speedpenalty", "Speed penalty while equipping/unequipping", false, "Toggle if you would receive a speed penalty during equipping and unequipping (Does not include clothing).")    
    options:addTickBox("speedpenaltyfortransfer", "Speed penalty while transferring", true, "Toggle if you would receive a speed penalty during transferring (Does not include clothing).")       
    options:addTickBox("speedpenaltyforclothing", "Speed penalty while wearing/unequipping clothes", true, "Toggle if you would receive a speed penalty during wearing and unequipping clothes.")         

    options.apply = function()
        ApplyRunningActionsOptions()
    end

    Events.OnMainMenuEnter.Add(function()
        options:apply()
    end)

    ApplyRunningActionsOptions()
end

InitRunningActionsOptions()

-- Utilities & Constants
local MIN_RUN  = 0.200
local BASE_RUN = 0.650
local MAX_RUN  = 1.000

local function clamp(v, a, b)
    if v < a then return a end
    if v > b then return b end
    return v
end

local function isWearable(item)
    return item and (
        (item.IsClothing and item:IsClothing()) or
        (item.getBodyLocation and item:getBodyLocation() ~= nil)
    )
end

local function isTryingToRun(character)
    if character:isRunning() then 
        return true 
    end
    
    if character:isLocalPlayer() then
        local runKey = getCore():getKey("Run")
        if runKey and isKeyDown(runKey) then
            return true
        end
    end
    
    return false
end

-- Networking Utilities
local function setSyncedVariable(character, varName, value)
    if not character then return end
    
    character:setVariable(varName, value)

    -- Broadcast variable state to other clients in MP
    if isClient() and character:isLocalPlayer() then
        sendClientCommand(character, "RunningActionsMod", "SyncAnimVar", {
            id = character:getOnlineID(),
            var = varName,
            val = value
        })
    end
end

local function OnServerCommand(module, command, args)
    if module == "RunningActionsMod" and command == "SyncAnimVar" then
        if not args or not args.id then return end

        local localPlayer = getPlayer()
        if localPlayer and localPlayer:getOnlineID() == args.id then
            return -- Ignore self-echoes
        end

        local onlinePlayers = getOnlinePlayers()
        if onlinePlayers then
            for i = 0, onlinePlayers:size() - 1 do
                local remotePlayer = onlinePlayers:get(i)
                if remotePlayer and remotePlayer:getOnlineID() == args.id then
                    remotePlayer:setVariable(args.var, args.val)
                    break
                end
            end
        end
    end
end

Events.OnServerCommand.Add(OnServerCommand)

-- Overrides

-- Equipping
local ISEquipWeaponAction_start_Orig = ISEquipWeaponAction.start
local ISEquipWeaponAction_isValid_Orig = ISEquipWeaponAction.isValid
local ISEquipWeaponAction_update_Orig = ISEquipWeaponAction.update
local ISEquipWeaponAction_perform_Orig = ISEquipWeaponAction.perform
local ISEquipWeaponAction_stop_Orig = ISEquipWeaponAction.stop

-- TOFIX: Find out why not reusing vanilla code causes not equipping bug
function ISEquipWeaponAction:new(character, item, maxTimeInit, primary, twoHands, alwaysTurnOn)
	local o = ISBaseTimedAction.new(self, character);
	o.item = item;
	o.stopOnAim = false;
	o.stopOnWalk = false;
	o.stopOnRun = false; 
	o.maxTimeInit = maxTimeInit
	o.maxTime = maxTimeInit
	o.primary = primary;
	o.twoHands = twoHands;
	o.ignoreHandsWounds = true;
	o.alwaysTurnOn = alwaysTurnOn

	if isServer() then
		o.hotbar = nil
	else
		o.hotbar = getPlayerHotbar(character:getPlayerNum());
	end

    if item ~= nil then
        o.fromHotbar = o.hotbar and o.hotbar:isItemAttached(item);
        o.useProgressBar = not o.fromHotbar;

        if instanceof(item, "HandWeapon") and not item:isTwoHandWeapon() then
            o.twoHands = false;
            if character:getSecondaryHandItem() and instanceof(item, "HandWeapon") then
            end
        end
        if item:isRequiresEquippedBothHands() then
            o.twoHands = true;
        end
        if o.twoHands then
            o.jobType = getText("ContextMenu_Equip_Two_Hands") .. " " .. item:getName()
        elseif o.primary then
            o.jobType = getText("ContextMenu_Equip_Primary") .. " " .. item:getName()
        else
            o.jobType = getText("ContextMenu_Equip_Secondary") .. " " .. item:getName()
        end
        if o.maxTime > 1 and o.fromHotbar then
            o.animSpeed = o.maxTime / o:adjustMaxTime(o.maxTime)
        else
            o.animSpeed = 1.0
        end
    end
	return o
end

function ISEquipWeaponAction:start()
    if self.character:isSprinting() then
        self:forceStop()
        return
    end

    if isTryingToRun(self.character) and not RunningActionsConfig.allowspeedpenalty then
        setSyncedVariable(self.character, "RunEquip_Enable", true)
    end
    ISEquipWeaponAction_start_Orig(self)
end

-- Keeps track of items getting equipped from a container
-- It should always return true unless a mod or a server issue cause it to return false
function ISEquipWeaponAction:isValid()
    if not self.item then
        return false
    end

    local invItem = self.character:getInventory():getItemWithID(self.item:getID())
    
    if invItem then
        self.item = invItem
        return true
    end

    local clothingItems = self.character:getClothingItems()
    for i = 0, clothingItems:size() - 1 do
        local clothingItem = clothingItems:get(i)
        if clothingItem and clothingItem:getContainer() then
            local containerItem = clothingItem:getContainer():getItemWithID(self.item:getID())
            if containerItem then
                self.item = containerItem
                return true
            end
        end
    end

    local attachedItems = self.character:getAttachedItems()
    for i = 0, attachedItems:size() - 1 do
        local attached = attachedItems:get(i)
        if attached and attached:getContainer() then
            local containerItem = attached:getContainer():getItemWithID(self.item:getID())
            if containerItem then
                self.item = containerItem
                return true
            end
        end
    end

    return false
end

-- This is merely here to make sure the player doesn't start spirinting mid running which would break the equipping animation
function ISEquipWeaponAction:update()
    if self.character:isSprinting() then
        self:forceStop()
        return
    end
    ISEquipWeaponAction_update_Orig(self)
end

-- Stops the equipping animtaion (naturally)
function ISEquipWeaponAction:perform()
    setSyncedVariable(self.character, "RunEquip_Enable", false)
    ISEquipWeaponAction_perform_Orig(self)
end

-- Stops the equipping animtaion (forcibly)
function ISEquipWeaponAction:stop()
    setSyncedVariable(self.character, "RunEquip_Enable", false)
    if ISEquipWeaponAction_stop_Orig then
        ISEquipWeaponAction_stop_Orig(self)
    end
end

-- Unequipping
local ISUnequipAction_start_Orig = ISUnequipAction.start
local ISUnequipAction_update_Orig = ISUnequipAction.update
local ISUnequipAction_perform_Orig = ISUnequipAction.perform
local ISUnequipAction_stop_Orig = ISUnequipAction.stop

-- TOFIX: Find out why not reusing vanilla code causes not unequipping bug
function ISUnequipAction:new(character, item, maxTimeInit, reason)
	local o = ISBaseTimedAction.new(self, character);
	o.item = item;
	o.stopOnAim = false;
	o.maxTimeInit = maxTimeInit;
	o.maxTime = maxTimeInit;
	o.reason = reason;
	o.ignoreHandsWounds = true;

	-- Unequipping clothes
	if isWearable(item) then
		if RunningActionsConfig.allowClothingWhileRunning then
			o.stopOnRun  = false
			o.stopOnWalk = false
			o.clothingAction  = true
			o.useProgressBar = true
		else
			o.stopOnRun = true
			o.stopOnWalk = ISWearClothing.isStopOnWalk(item); -- Restores vanilla walk limit if config is off
			o.clothingAction = true
		end
	else
		-- Unequipping weapon/item
		o.stopOnRun  = false
		o.stopOnWalk = false
		o.clothingAction  = false
		o.useProgressBar = false
	end

	if isServer() then
		o.hotbar = nil
	else
		o.hotbar = getPlayerHotbar(character:getPlayerNum());
	end

	o.fromHotbar = o.hotbar and o.hotbar:isItemAttached(item);

	if o.maxTime > 1 and o.fromHotbar then
		o.animSpeed = o.maxTime / o:adjustMaxTime(o.maxTime)
	else
		o.animSpeed = 1.0
	end

	return o;
end

function ISUnequipAction:start()
    if self.character:isSprinting() then
        self:forceStop()
        return
    end

    local item = self.item
    local wearable = isWearable(item) 
    
    -- Safely flag if this is a clothing unequip so UpdateAllowRun can differentiate it
    if wearable then
        self.character:getModData().bIsUnequippingClothing = true
    else
        self.character:getModData().bIsUnequippingClothing = false
    end

    if isTryingToRun(self.character) then
        if wearable then
            if not RunningActionsConfig.allowclothingspeedpenalty then
                setSyncedVariable(self.character, "RunUnequip_Enable", true)
            end
        else
            if not RunningActionsConfig.allowspeedpenalty then
                setSyncedVariable(self.character, "RunUnequip_Enable", true)
            end
        end
    end
    ISUnequipAction_start_Orig(self)
end
-- This is merely here to make sure the player doesn't start spirinting mid running which would break the unequipping animation
function ISUnequipAction:update()
    if self.character:isSprinting() then
        self:forceStop()
        return
    end
    ISUnequipAction_update_Orig(self)
end

-- Stops the unequipping animtaion (naturally)
function ISUnequipAction:perform()
    setSyncedVariable(self.character, "RunUnequip_Enable", false)
    self.character:getModData().bIsUnequippingClothing = false
    ISUnequipAction_perform_Orig(self)
end

-- Stops the unequipping animtaion (forcibly)
function ISUnequipAction:stop()
    setSyncedVariable(self.character, "RunUnequip_Enable", false)
    self.character:getModData().bIsUnequippingClothing = false
    if ISUnequipAction_stop_Orig then
        ISUnequipAction_stop_Orig(self)
    end
end

-- Wearing clothes (Slightly different than Equipping items)
local ISWearClothing_isValid_Orig = ISWearClothing.isValid
local ISWearClothing_start_Orig = ISWearClothing.start
local ISWearClothing_update_Orig = ISWearClothing.update
local ISWearClothing_perform_Orig = ISWearClothing.perform
local ISWearClothing_stop_Orig = ISWearClothing.stop

-- TOFIX: Find out why not reusing vanilla code causes not wearing bug
function ISWearClothing:new(character, item)
	local o = ISBaseTimedAction.new(self, character);
	o.item = item;
	o.maxTime = o:getDuration();
	o.fromHotbar = true; -- just to disable hotbar:update() during the wearing
	o.clothingAction = true;
    
    if RunningActionsConfig.allowClothingWhileRunning then
        o.stopOnRun  = false
        o.stopOnWalk = false
    else
        o.stopOnWalk = ISWearClothing.isStopOnWalk(item);
        o.stopOnRun = true;
    end
    
	return o;
end

-- Useless, condition moved to ISWearClothing:new()
--[[ function ISWearClothing:isValid()
    if not RunningActionsConfig.allowClothingWhileRunning and self.character:isRunning() then
        return false
    end
    return ISWearClothing_isValid_Orig(self)
end ]]

function ISWearClothing:start()
    if self.character:isSprinting() then
        self:forceStop()
        return
    end
    
    if isTryingToRun(self.character) and not RunningActionsConfig.allowclothingspeedpenalty and RunningActionsConfig.allowClothingWhileRunning then
        setSyncedVariable(self.character, "RunEquip_Enable", true)
    end
    ISWearClothing_start_Orig(self)
end

-- This is merely here to make sure the player doesn't start spirinting mid running which would break the wearing animation
function ISWearClothing:update()
    if self.character:isSprinting() then
        self:forceStop()
        return
    end
    ISWearClothing_update_Orig(self)
end

-- Stops the wearing animtaion (naturally)
function ISWearClothing:perform()
    setSyncedVariable(self.character, "RunEquip_Enable", false)
    ISWearClothing_perform_Orig(self)
end

-- Stops the wearing animtaion (forcibly)
function ISWearClothing:stop()
    setSyncedVariable(self.character, "RunEquip_Enable", false)
    if ISWearClothing_stop_Orig then
        ISWearClothing_stop_Orig(self)
    end
end

-- Transferring
local luautils_haveToBeTransfered_Orig = luautils.haveToBeTransfered
local ISInventoryTransferAction_start_Orig = ISInventoryTransferAction.start
local ISInventoryTransferAction_update_Orig = ISInventoryTransferAction.update
local ISInventoryTransferAction_perform_Orig = ISInventoryTransferAction.perform
local ISInventoryTransferAction_stop_Orig = ISInventoryTransferAction.stop

-- TOFIX: Find out why not reusing vanilla code causes not transferring bug
function ISInventoryTransferAction:new(character, item, srcContainer, destContainer, time)
	local o = {}
	setmetatable(o, self)
	self.__index = self
	o.character = character;
	o.item = item;
	o.dontAdd = false;
	o.started = false;
	o.transactionId = 0;
	o.srcContainer = srcContainer;
	o.destContainer = destContainer;
	o.startTime = getTimestampMs()

	-- handle people right click the same item while eating it
	if not srcContainer or not destContainer then
		o.maxTime = 0;
		return o;
	end

	o.stopOnWalk = not o.destContainer:isInCharacterInventory(o.character) or (not o.srcContainer:isInCharacterInventory(o.character))
	if (o.srcContainer == character:getInventory()) and (o.destContainer:getType() == "floor") then
		o.stopOnWalk = false
	end

    if RunningActionsConfig.allowTransfersWhileRunning then
        o.stopOnRun = false
    else
        o.stopOnRun = true
    end

    if destContainer:getType() ~= "TradeUI" and srcContainer:getType() ~= "TradeUI" then
        o.maxTime = 120;
        -- increase time for bigger objects or when backpack is more full.
        local destCapacityDelta = 1.0;

        if o.srcContainer == o.character:getInventory() then
            if o.destContainer:isInCharacterInventory(o.character) then
                destCapacityDelta = o.destContainer:getCapacityWeight() / o.destContainer:getMaxWeight();
            else
                o.maxTime = 50;
            end

        elseif not o.srcContainer:isInCharacterInventory(o.character) then
            if o.destContainer:isInCharacterInventory(o.character) then
                o.maxTime = 50;
            end
        end

        if destCapacityDelta < 0.4 then
            destCapacityDelta = 0.4;
        end

		if item then -- kludge to fix error when filling gas bottles out of backpack
			local w = item:getActualWeight();
			if w > 3 then w = 3; end;
			o.maxTime = o.maxTime * (w) * destCapacityDelta;
		end

        if getCore():getGameMode()=="LastStand" then
            o.maxTime = o.maxTime * 0.3;
        end

        if o.destContainer:getType()=="floor" then
			if o.srcContainer == o.character:getInventory() then
				o.maxTime = o.maxTime * 0.1;
			elseif o.srcContainer:isInCharacterInventory(o.character) then
				-- Unpack -> drop
			else
				o.maxTime = o.maxTime * 0.2;
			end
		end

		if character:hasTrait(CharacterTrait.DEXTROUS) then
			o.maxTime = o.maxTime * 0.5
		end
		if character:hasTrait(CharacterTrait.ALL_THUMBS) or character:isWearingAwkwardGloves() then
			o.maxTime = o.maxTime * 2.0
		end
    else
        o.maxTime = 0;
    end

    if time then
        o.maxTime = time;
    end

	if character:isTimedActionInstant() then
		o.maxTime = 1;
	end
	
	if item then -- kludge to fix error when filling gas bottles out of backpack
		if item:isFavorite() and not o.destContainer:isInCharacterInventory(o.character) then o.maxTime = 0; end
	end

    if item then
            if isClient() then 
                -- If we are running and allowing running transfers, 
                -- keep a real maxTime so the progress bar actually fills up visually!
                if RunningActionsConfig.allowTransfersWhileRunning and character:isRunning() then
                    -- Keep the calculated maxTime instead of setting it to -1
                else
                    o.maxTime = -1
                end
            end
		o.queueList = {};
		local queuedItem = {items = {o.item}, time = o.maxTime, type = o.item:getFullType()};
		table.insert(o.queueList, queuedItem);
		o.loopedAction = true
	end

    o.isTransferIntoVehicleSeatFromOutside = not o.srcContainer:isVehicleSeat() and o.destContainer:isVehicleSeat()

	return o
end

-- Helper function to allow interacting with items in other containers transfer over to main inventory while running
function luautils.haveToBeTransfered(player, item, dontWalk)
    local isRunning = player:isRunning() or player:isSprinting()

    if item and item:getContainer() and item:getContainer() ~= player:getInventory() then
        if isRunning and RunningActionsConfig.allowTransfersWhileRunning then
            return true
        end
        return luautils_haveToBeTransfered_Orig(player, item, dontWalk)
    end

    return false
end    

function ISInventoryTransferAction:start()
    if self.character:isSprinting() then
        self:forceStop()
        return
    end
    if not RunningActionsConfig.allowTransfersWhileRunning then
        if self.character:isRunning() then
            self:forceStop()
            return
        end
    end
    ISInventoryTransferAction_start_Orig(self)
end

function ISInventoryTransferAction:update()
    if self.character:isSprinting() then
        self:forceStop()
        return
    end
    
    -- Dynamically toggle the custom animation on and off if the penalty is disabled
    if RunningActionsConfig.allowTransfersWhileRunning and not RunningActionsConfig.allowspeedpenaltyfortransfer then
        if isTryingToRun(self.character) then
            setSyncedVariable(self.character, "RunEquip_Enable", true)
        else
            setSyncedVariable(self.character, "RunEquip_Enable", false)
        end
    end

    if ISInventoryTransferAction_update_Orig then
        ISInventoryTransferAction_update_Orig(self)
    end
end

-- Stops the transferring animtaion (naturally)
function ISInventoryTransferAction:perform()
    setSyncedVariable(self.character, "RunEquip_Enable", false)
    if ISInventoryTransferAction_perform_Orig then
        ISInventoryTransferAction_perform_Orig(self)
    end
end

-- Stops the transferring animtaion (forcibly)
function ISInventoryTransferAction:stop()
    setSyncedVariable(self.character, "RunEquip_Enable", false)
    if ISInventoryTransferAction_stop_Orig then
        ISInventoryTransferAction_stop_Orig(self)
    end
end

-- Attatching To Hotbar
local ISAttachItemHotbar_start_Orig = ISAttachItemHotbar.start
--TOFIX: Override update for attaching too
local ISAttachItemHotbar_perform_Orig = ISAttachItemHotbar.perform
local ISAttachItemHotbar_stop_Orig = ISAttachItemHotbar.stop

-- TOFIX: Find out why not reusing vanilla code causes not attaching bug
function ISAttachItemHotbar:new(character, item, slot, slotIndex, slotDef)
    local o = ISBaseTimedAction.new(self, character)
    o.character = character;
    o.item = item;
    o.stopOnWalk = false;
    o.stopOnRun = false;
    o.slotIndex = slotIndex;
    o.slot = slot;
    o.slotDef = slotDef;
    o.fromHotbar = true;
    o.maxTime = 30;

    if not isServer() then
        o.hotbar = getPlayerHotbar(character:getPlayerNum());
    end

    o.useProgressBar = false;
    o.ignoreHandsWounds = true;
    if o.character:isTimedActionInstant() then
        o.maxTime = 1
    end
    if o.maxTime > 1 then
        o.animSpeed = o.maxTime / o:adjustMaxTime(o.maxTime)
        o.maxTime = -1
    else
        o.animSpeed = 1.0
    end

    return o;
end

function ISAttachItemHotbar:start()
    if isTryingToRun(self.character) and not RunningActionsConfig.allowspeedpenalty then
        setSyncedVariable(self.character, "RunAttach_Enable", true)
    end
    ISAttachItemHotbar_start_Orig(self)
end

-- Stops the attaching animtaion (naturally)
function ISAttachItemHotbar:perform()
    setSyncedVariable(self.character, "RunAttach_Enable", false)
    ISAttachItemHotbar_perform_Orig(self)
end

-- Stops the attaching animtaion (forcibly)
function ISAttachItemHotbar:stop()
    setSyncedVariable(self.character, "RunAttach_Enable", false)
    if ISAttachItemHotbar_stop_Orig then
        ISAttachItemHotbar_stop_Orig(self)
    end
end

-- Detatching From Hotbar
local ISDetachItemHotbar_start_Orig = ISDetachItemHotbar.start
local ISDetachItemHotbar_perform_Orig = ISDetachItemHotbar.perform
local ISDetachItemHotbar_stop_Orig = ISDetachItemHotbar.stop

-- TOFIX: Find out why not reusing vanilla code causes not detaching bug
function ISDetachItemHotbar:new(character, item)
    local o = {}
    setmetatable(o, self)
    self.__index = self
    o.character = character;
    o.item = item;
    o.stopOnWalk = false;
    o.stopOnRun = false;
    o.equipped = character:isEquipped(item);
    o.hotbar = getPlayerHotbar(o.character:getPlayerNum());
    o.fromHotbar = true;
    o.useProgressBar = false;
    o.ignoreHandsWounds = true;
    o.maxTime = 25;
    if o.equipped then
        o.maxTime = 1;
    end
    if o.character:isTimedActionInstant() then
        o.maxTime = 1
    end
    if o.maxTime > 1 then
        o.animSpeed = o.maxTime / o:adjustMaxTime(o.maxTime)
        o.maxTime = -1
    else
        o.animSpeed = 1.0
    end
    return o;
end

function ISDetachItemHotbar:start()
    if isTryingToRun(self.character) and not RunningActionsConfig.allowspeedpenalty then
        setSyncedVariable(self.character, "RunDetach_Enable", true)
    end
    ISDetachItemHotbar_start_Orig(self)
end

-- Stops the attaching animtaion (naturally)
function ISDetachItemHotbar:perform()
    setSyncedVariable(self.character, "RunDetach_Enable", false)
    ISDetachItemHotbar_perform_Orig(self)
end

-- Stops the attaching animtaion (forcibly)
function ISDetachItemHotbar:stop()
    setSyncedVariable(self.character, "RunDetach_Enable", false)
    if ISDetachItemHotbar_stop_Orig then
        ISDetachItemHotbar_stop_Orig(self)
    end
end

-- Core Update Loop
-- Keep ownership of AllowRun narrow: remember the value that existed before this
-- mod applied a speed penalty and restore exactly that value when the penalty ends.
-- Weak keys avoid retaining player objects after disconnect/reload.
local previousAllowRunByPlayer = setmetatable({}, { __mode = "k" })

local function applyRunPenalty(player, shouldBlockRun)
    local previousAllowRun = previousAllowRunByPlayer[player]

    if shouldBlockRun then
        if previousAllowRun == nil then
            previousAllowRunByPlayer[player] = player:isAllowRun()
        end
        player:setAllowRun(false)
    elseif previousAllowRun ~= nil then
        player:setAllowRun(previousAllowRun)
        previousAllowRunByPlayer[player] = nil
    end
end

local function UpdateAllowRun(player)
    if not player then return end

    -- Skip all this logic while mounted (Horse mod)
    local data = player:getModData()
    if data and data.remountAnimal then
        applyRunPenalty(player, false)
        return
    end

    local speed = player:getVariableFloat("WalkSpeed", 0.0)

    -- Map to animation speed range
    local MIN_ANIM = 0.55   -- slowest run animation for endurance/limping
    local BASE_ANIM = 1.00  -- normal running speed
    local MAX_ANIM = 1.15   -- slightly faster for top running

    local animSpeed
    if speed <= BASE_RUN then
        -- Standard endurance/light injury penalty
        local t = (speed - MIN_RUN) / (BASE_RUN - MIN_RUN)
        t = t ^ 1.6
        animSpeed = MIN_ANIM + (BASE_ANIM - MIN_ANIM) * t
    else
        -- High running skill
        local t = (speed - BASE_RUN) / (MAX_RUN - BASE_RUN)
        t = 1.0 + t
        t = t ^ 0.65 
        animSpeed = BASE_ANIM + (MAX_ANIM - BASE_ANIM) * (t - 1.0)
    end

    -- Clamp to our standard limits
    animSpeed = clamp(animSpeed, MIN_ANIM, MAX_ANIM)

    -- Detect active actions
    local actions = player:getCharacterActions()
    local hasEquip = false
    local hasUnequip = false
    local hasAttach = false
    local hasDetach = false
    local hasTransfer = false
    local hasClothing = false

    -- Pull the tracker we set during ISUnequipAction:start
    local isClothingUnequip = data.bIsUnequippingClothing

    for i = 0, actions:size() - 1 do
        local name = actions:get(i):getMetaType()

        if name == "ISEquipWeaponAction" then
            hasEquip = true
        elseif name == "ISUnequipAction" then
            if isClothingUnequip then
                hasClothing = true
            else
                hasUnequip = true
            end
        elseif name == "ISAttachItemHotbar" then
            hasAttach = true
        elseif name == "ISDetachItemHotbar" then
            hasDetach = true
        elseif name == "ISInventoryTransferAction" then
            hasTransfer = true
        elseif name == "ISWearClothing" then
            hasClothing = true
        end
    end

    -- Decide WHICH penalty applies
    local useEquipCustom = (hasEquip or hasAttach or hasDetach) and not RunningActionsConfig.allowspeedpenalty
    local useUnequipCustom = hasUnequip and not RunningActionsConfig.allowspeedpenalty
    local useClothingCustom = hasClothing and not RunningActionsConfig.allowclothingspeedpenalty

    -- Apply animation variables safely
    if speed <= MIN_RUN then
        player:setVariable("RunEquip_Enable", false)
        player:setVariable("RunUnequip_Enable", false)
        player:setVariable("RunAttach_Enable", false)
        player:setVariable("RunDetach_Enable", false)
    else
        -- Normal execution for when the character is capable of running
        if useEquipCustom and player:getVariableBoolean("RunEquip_Enable") then
            player:setVariable("RunEquip_AnimSpeed", animSpeed)
        end

        if useUnequipCustom and player:getVariableBoolean("RunUnequip_Enable") then
            player:setVariable("RunUnequip_AnimSpeed", animSpeed)
        end

        if useClothingCustom then
            if player:getVariableBoolean("RunEquip_Enable") then
                player:setVariable("RunEquip_AnimSpeed", animSpeed)
            end
            if player:getVariableBoolean("RunUnequip_Enable") then
                player:setVariable("RunUnequip_AnimSpeed", animSpeed)
            end
        end
        
        if hasAttach and not RunningActionsConfig.allowspeedpenalty and player:getVariableBoolean("RunAttach_Enable") then
            player:setVariable("RunAttach_AnimSpeed", animSpeed)
        end
        
        if hasDetach and not RunningActionsConfig.allowspeedpenalty and player:getVariableBoolean("RunDetach_Enable") then
            player:setVariable("RunDetach_AnimSpeed", animSpeed)
        end
    end

    -- Apply only the speed penalties explicitly enabled by the player. Previously
    -- every equip/hotbar/clothing action blocked running even with its penalty off,
    -- defeating stopOnRun=false and the purpose of this mod.
    local blockRun =
        ((hasEquip or hasUnequip or hasAttach or hasDetach) and RunningActionsConfig.allowspeedpenalty)
        or (hasClothing
            and RunningActionsConfig.allowClothingWhileRunning
            and RunningActionsConfig.allowclothingspeedpenalty)
        or (hasTransfer
            and RunningActionsConfig.allowTransfersWhileRunning
            and RunningActionsConfig.allowspeedpenaltyfortransfer)

    applyRunPenalty(player, blockRun)
end

Events.OnPlayerUpdate.Add(UpdateAllowRun)
