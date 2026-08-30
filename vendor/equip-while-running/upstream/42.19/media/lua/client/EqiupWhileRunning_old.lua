-- Configuration & Mod Options
local RunningActionsConfig = {
    allowClothingWhileRunning = true,
    allowTransfersWhileRunning = true
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
    options:addTickBox("speedpenalty", "Speed penalty while equipping/unequipping", false, "Toggle if you would receive a speed penalty during equipping, unequipping, and transferring (Does not include clothing).")    
    options:addTickBox("speedpenaltyfortransfer", "Speed penalty while transferring", true, "Toggle if you would receive a speed penalty during transferring (Does not include clothing).")       
    options:addTickBox("speedpenaltyforclothing", "Speed penalty while wearing/unequipping clothes", true, "Toggle if you would receive a speed penalty during wearing and unequipping.")         

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
    if character:isRunning() then return true end
    
    local runKey = getCore():getKey("Run")
    if runKey and isKeyDown(runKey) then
        return true
    end
    
    return false
end

-- Vanilla Override Grouped by Action

-- ISEquipWeaponAction
local ISEquipWeaponAction_New = ISEquipWeaponAction.new
function ISEquipWeaponAction:new(...)
    local o = ISEquipWeaponAction_New(self, ...)
    o.stopOnRun  = false
    o.stopOnWalk = false
    return o
end

local ISEquipWeaponAction_isValid_Orig = ISEquipWeaponAction.isValid
function ISEquipWeaponAction:isValid()
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

local ISEquipWeaponAction_start_Orig = ISEquipWeaponAction.start
function ISEquipWeaponAction:start()
    if self.character:isSprinting() then
        self:forceStop()
        return
    end

    if isTryingToRun(self.character) and not RunningActionsConfig.allowspeedpenalty then
        self.character:setVariable("RunEquip_Enable", true)
    end
    ISEquipWeaponAction_start_Orig(self)
end

local ISEquipWeaponAction_update_Orig = ISEquipWeaponAction.update
function ISEquipWeaponAction:update()
    if self.character:isSprinting() then
        self:forceStop()
        return
    end
    ISEquipWeaponAction_update_Orig(self)
end

local ISEquipWeaponAction_perform_Orig = ISEquipWeaponAction.perform
function ISEquipWeaponAction:perform()
    self.character:setVariable("RunEquip_Enable", false)
    ISEquipWeaponAction_perform_Orig(self)
end

local ISEquipWeaponAction_stop_Orig = ISEquipWeaponAction.stop
function ISEquipWeaponAction:stop()
    self.character:setVariable("RunEquip_Enable", false)
    if ISEquipWeaponAction_stop_Orig then
        ISEquipWeaponAction_stop_Orig(self)
    end
end

-- ISUnequipAction
local ISUnequipAction_New = ISUnequipAction.new
function ISUnequipAction:new(character, item, maxTime)
    local o = ISUnequipAction_New(self, character, item, maxTime)

    if isWearable(item) then
        if RunningActionsConfig.allowClothingWhileRunning then
            o.stopOnRun  = false
            o.stopOnWalk = false
            o.clothingAction  = true
            o.useProgressBar = true
        else
            o.stopOnRun = true
            o.clothingAction = true
        end
    else
        o.stopOnRun  = false
        o.stopOnWalk = false
        o.clothingAction  = false
        o.useProgressBar = false
    end

    return o
end

local ISUnequipAction_start_Orig = ISUnequipAction.start
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
                self.character:setVariable("RunUnequip_Enable", true)
            end
        else
            if not RunningActionsConfig.allowspeedpenalty then
                self.character:setVariable("RunUnequip_Enable", true)
            end
        end
    end
    ISUnequipAction_start_Orig(self)
end

local ISUnequipAction_update_Orig = ISUnequipAction.update
function ISUnequipAction:update()
    if self.character:isSprinting() then
        self:forceStop()
        return
    end
    ISUnequipAction_update_Orig(self)
end

local ISUnequipAction_perform_Orig = ISUnequipAction.perform
function ISUnequipAction:perform()
    self.character:setVariable("RunUnequip_Enable", false)
    self.character:getModData().bIsUnequippingClothing = false
    ISUnequipAction_perform_Orig(self)
end

local ISUnequipAction_stop_Orig = ISUnequipAction.stop
function ISUnequipAction:stop()
    self.character:setVariable("RunUnequip_Enable", false)
    self.character:getModData().bIsUnequippingClothing = false
    if ISUnequipAction_stop_Orig then
        ISUnequipAction_stop_Orig(self)
    end
end

-- ISWearClothing
local ISWearClothing_New = ISWearClothing.new
function ISWearClothing:new(...)
    local o = ISWearClothing_New(self, ...)
    if RunningActionsConfig.allowClothingWhileRunning then
        o.stopOnRun  = false
        o.stopOnWalk = false
    else
        o.stopOnRun = true
    end
    return o
end

local ISWearClothing_isValid_Orig = ISWearClothing.isValid
function ISWearClothing:isValid()
    if not RunningActionsConfig.allowClothingWhileRunning and self.character:isRunning() then
        return false
    end
    return ISWearClothing_isValid_Orig(self)
end

local ISWearClothing_start_Orig = ISWearClothing.start
function ISWearClothing:start()
    if self.character:isSprinting() then
        self:forceStop()
        return
    end
    
    if isTryingToRun(self.character) and not RunningActionsConfig.allowclothingspeedpenalty and RunningActionsConfig.allowClothingWhileRunning then
        self.character:setVariable("RunEquip_Enable", true)
    end
    ISWearClothing_start_Orig(self)
end

local ISWearClothing_update_Orig = ISWearClothing.update
function ISWearClothing:update()
    if self.character:isSprinting() then
        self:forceStop()
        return
    end
    ISWearClothing_update_Orig(self)
end

local ISWearClothing_perform_Orig = ISWearClothing.perform
function ISWearClothing:perform()
    self.character:setVariable("RunEquip_Enable", false)
    ISWearClothing_perform_Orig(self)
end

local ISWearClothing_stop_Orig = ISWearClothing.stop
function ISWearClothing:stop()
    self.character:setVariable("RunEquip_Enable", false)
    if ISWearClothing_stop_Orig then
        ISWearClothing_stop_Orig(self)
    end
end

-- ISInventoryTransferAction
local ISInventoryTransferAction_New = ISInventoryTransferAction.new
function ISInventoryTransferAction:new(...)
    local o = ISInventoryTransferAction_New(self, ...)
    if RunningActionsConfig.allowTransfersWhileRunning then
        o.stopOnRun = false
    else
        o.stopOnRun = true
    end
    return o
end

local ISInventoryTransferAction_start_Orig = ISInventoryTransferAction.start
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

local ISInventoryTransferAction_update_Orig = ISInventoryTransferAction.update
function ISInventoryTransferAction:update()
    if self.character:isSprinting() then
        self:forceStop()
        return
    end
    
    -- Dynamically toggle the custom animation on and off if the penalty is disabled
    if RunningActionsConfig.allowTransfersWhileRunning and not RunningActionsConfig.allowspeedpenaltyfortransfer then
        if isTryingToRun(self.character) then
            self.character:setVariable("RunEquip_Enable", true)
        else
            self.character:setVariable("RunEquip_Enable", false)
        end
    end

    if ISInventoryTransferAction_update_Orig then
        ISInventoryTransferAction_update_Orig(self)
    end
end

local ISInventoryTransferAction_stop_Orig = ISInventoryTransferAction.stop
function ISInventoryTransferAction:stop()
    self.character:setVariable("RunEquip_Enable", false)
    if ISInventoryTransferAction_stop_Orig then
        ISInventoryTransferAction_stop_Orig(self)
    end
end

-- ISAttachItemHotbar
local ISAttachItemHotbar_New = ISAttachItemHotbar.new
function ISAttachItemHotbar:new(...)
    local o = ISAttachItemHotbar_New(self, ...)
    o.stopOnRun = false
    return o
end

local ISAttachItemHotbar_start_Orig = ISAttachItemHotbar.start
function ISAttachItemHotbar:start()
    if isTryingToRun(self.character) and not RunningActionsConfig.allowspeedpenalty then
        self.character:setVariable("RunAttach_Enable", true)
    end
    ISAttachItemHotbar_start_Orig(self)
end

local ISAttachItemHotbar_perform_Orig = ISAttachItemHotbar.perform
function ISAttachItemHotbar:perform()
    self.character:setVariable("RunAttach_Enable", false)
    ISAttachItemHotbar_perform_Orig(self)
end

local ISAttachItemHotbar_stop_Orig = ISAttachItemHotbar.stop
function ISAttachItemHotbar:stop()
    self.character:setVariable("RunAttach_Enable", false)
    if ISAttachItemHotbar_stop_Orig then
        ISAttachItemHotbar_stop_Orig(self)
    end
end

-- ISDetachItemHotbar
local ISDetachItemHotbar_New = ISDetachItemHotbar.new
function ISDetachItemHotbar:new(...)
    local o = ISDetachItemHotbar_New(self, ...)
    o.stopOnRun = false
    return o
end

local ISDetachItemHotbar_start_Orig = ISDetachItemHotbar.start
function ISDetachItemHotbar:start()
    if isTryingToRun(self.character) and not RunningActionsConfig.allowspeedpenalty then
        self.character:setVariable("RunDetach_Enable", true)
    end
    ISDetachItemHotbar_start_Orig(self)
end

local ISDetachItemHotbar_perform_Orig = ISDetachItemHotbar.perform
function ISDetachItemHotbar:perform()
    self.character:setVariable("RunDetach_Enable", false)
    ISDetachItemHotbar_perform_Orig(self)
end

local ISDetachItemHotbar_stop_Orig = ISDetachItemHotbar.stop
function ISDetachItemHotbar:stop()
    self.character:setVariable("RunDetach_Enable", false)
    if ISDetachItemHotbar_stop_Orig then
        ISDetachItemHotbar_stop_Orig(self)
    end
end

-- -----------------------------------------------------------------------------
-- luautils Override
-- -----------------------------------------------------------------------------
local luautils_haveToBeTransfered_Orig = luautils.haveToBeTransfered
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

-- Core Update Loop
local function UpdateAllowRun(player)
    if not player then return end

    -- Skip all this logic while mounted (Horse mod)
    local data = player:getModData()
    if data and data.remountAnimal then
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
        t = t ^ 1.7 
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

    -- AllowRun control
    local blockRun = false

    -- Weapons and hotbar actions
    if hasEquip or hasUnequip or hasAttach or hasDetach then
        blockRun = true
    end

    -- Clothing 
    if hasClothing and RunningActionsConfig.allowClothingWhileRunning then
        blockRun = true
    end

    -- Transfers
    if hasTransfer and RunningActionsConfig.allowTransfersWhileRunning then
        if RunningActionsConfig.allowspeedpenaltyfortransfer then
            blockRun = true
        elseif player:getVariableBoolean("RunEquip_Enable") then
            blockRun = true
        end
    end

    player:setAllowRun(not blockRun)
end

Events.OnPlayerUpdate.Add(UpdateAllowRun)