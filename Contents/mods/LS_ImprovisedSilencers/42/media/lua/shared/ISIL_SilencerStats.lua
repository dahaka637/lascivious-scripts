require "TimedActions/ISUpgradeWeapon"
require "TimedActions/ISRemoveWeaponUpgrade"

if not isServer() or isClient() then
    pcall(require, "TimedActions/ISInventoryTransferAction")
end

ISILSilencerStats = ISILSilencerStats or {}
ISILDeferredWeaponStates = ISILDeferredWeaponStates or {}
ISILPendingNetworkWeaponStates = ISILPendingNetworkWeaponStates or {}
ISILObservedSuppressors = ISILObservedSuppressors or {}

local effects = {
    ["Base.Silencer"] = {
        soundRadius = 0.20,
        soundVolume = 0.30,
        extendedReductionKey = "ProfessionalNoiseReduction",
        extendedReductionDefault = 60,
        durabilityKey = "ProfessionalDurability",
        durabilityDefault = 500,
        sounds = {
            pistol = "ISILProfessionalPistol",
            rifle = "ISILProfessionalRifle",
            shotgun = "ISILProfessionalShotgun",
        },
    },
    ["Base.MetalPipeSilencer"] = {
        soundRadius = 0.40,
        soundVolume = 0.50,
        extendedReductionKey = "MetalPipeNoiseReduction",
        extendedReductionDefault = 40,
        durabilityKey = "MetalPipeDurability",
        durabilityDefault = 100,
        sounds = {
            pistol = "ISILMetalPipePistol",
            rifle = "ISILMetalPipeRifle",
            shotgun = "ISILMetalPipeShotgun",
        },
    },
    ["Base.TorchSilencer"] = {
        soundRadius = 0.60,
        soundVolume = 0.70,
        extendedReductionKey = "HandTorchNoiseReduction",
        extendedReductionDefault = 30,
        durabilityKey = "HandTorchDurability",
        durabilityDefault = 20,
        sounds = {
            pistol = "ISILHandTorchPistol",
            rifle = "ISILHandTorchRifle",
        },
    },
    ["Base.WaterBottleSilencer"] = {
        soundRadius = 0.80,
        soundVolume = 0.80,
        extendedReductionKey = "WaterBottleNoiseReduction",
        extendedReductionDefault = 20,
        durabilityKey = "WaterBottleDurability",
        durabilityDefault = 5,
        sounds = {
            pistol = "ISILWaterBottlePistol",
            rifle = "ISILWaterBottleRifle",
        },
    },
    ["Base.PotatoSilencer"] = {
        soundRadius = 0.90,
        soundVolume = 0.90,
        extendedReductionKey = "WaterBottleNoiseReduction",
        extendedReductionDefault = 20,
        extendedReductionScale = 0.5,
        durabilityDefault = 1,
        alwaysOneShot = true,
        sounds = {
            pistol = "ISILPotatoShot",
            rifle = "ISILPotatoShot",
        },
    },
}

local function clampNumber(value, fallback, minimum, maximum)
    local number = tonumber(value)
    if number == nil then
        number = fallback
    end
    return math.max(minimum, math.min(maximum, number))
end

local function getExtendedOptions()
    return SandboxVars and SandboxVars.ISIL or nil
end

local function getExtendedOption(name)
    if getSandboxOptions then
        local options = getSandboxOptions()
        local option = options and options:getOptionByName("ISIL." .. name)
        if option then
            return option:getValue()
        end
    end

    local options = getExtendedOptions()
    return options and options[name] or nil
end

function ISILSilencerStats.isExtendedModeEnabled()
    return getExtendedOption("ExtendedMode") == true
end

function ISILSilencerStats.isDurabilityEnabled()
    return ISILSilencerStats.isExtendedModeEnabled()
        and getExtendedOption("EnableDurability") ~= false
end

function ISILSilencerStats.isCaliberBasedWearEnabled()
    return ISILSilencerStats.isDurabilityEnabled()
        and getExtendedOption("CaliberBasedWear") ~= false
end

local function containsAmmoToken(ammoId, tokens)
    for _, token in ipairs(tokens) do
        if string.find(ammoId, token, 1, true) then
            return true
        end
    end
    return false
end

-- Durability settings represent 9mm-equivalent base shots. Keep this mapping
-- based on ammunition identifiers instead of weapon names so vanilla, VFE and
-- Guns of Marz weapons share the same rules. Unknown mod ammunition safely
-- falls back to the standard one-point wear rate.
function ISILSilencerStats.getCaliberWearMultiplier(weapon)
    if not ISILSilencerStats.isCaliberBasedWearEnabled() or not weapon then
        return 1.0
    end

    local ammoId = string.lower(tostring(weapon:getAmmoType() or ""))
    if ammoId == "" then
        return 1.0
    end

    -- Check longer and potentially overlapping identifiers first.
    if containsAmmoToken(ammoId, { "round_40mm", "40mm_round", ":40mm" }) then
        return 3.0
    end
    if containsAmmoToken(ammoId, { "shell_12g", "shotgun_shells", "12gauge" }) then
        return 2.5
    end
    if containsAmmoToken(ammoId, { "bullet_4570", "bullets_4570", "45-70", "4570" }) then
        return 2.5
    end
    if containsAmmoToken(ammoId, { "bullet_50", "bullets_50", "50ae", "50bmg" }) then
        return 2.5
    end
    if containsAmmoToken(ammoId, {
        "bullet_762x54", "bullets_762x54", "762x54",
        "bullet_762x51", "bullets_762x51", "762x51",
        "bullets_308", "bullet_308", "308_linked",
        "bullet_3006", "bullets_3006", "3006", "30-06",
    }) then
        return 2.0
    end
    if containsAmmoToken(ammoId, { "bullet_3030", "bullets_3030", "3030", "30-30" }) then
        return 1.75
    end
    if containsAmmoToken(ammoId, {
        "bullet_762x39", "bullets_762x39", "762x39", "vfe:bullets_762",
        "bullet_545x39", "bullets_545x39", "545x39",
        "bullet_556x45", "bullets_556x45",
        "bullets_556", "bullet_556", "556x45",
        "bullets_223", "bullet_223",
        "bullet_9x39", "bullets_9x39", "9x39",
    }) then
        return 1.5
    end
    if containsAmmoToken(ammoId, {
        "bullets_357", "bullet_357", "357mag",
        "bullets_44", "bullet_44", "44mag",
        "bullets_45", "bullet_45", "45acp",
    }) then
        return 1.25
    end
    if containsAmmoToken(ammoId, { "bullet_57x28", "bullets_57x28", "57x28" }) then
        return 0.75
    end
    if containsAmmoToken(ammoId, { "bullets_22", "bullet_22", "22lr" }) then
        return 0.5
    end
    if containsAmmoToken(ammoId, { "cap_gun_cap" }) then
        return 0.25
    end

    -- 9x19, 9mm, .38 Special and unknown ammunition are the baseline.
    return 1.0
end

local function getEffectValues(fullType)
    local effect = effects[fullType]
    if not effect then
        return nil
    end

    if not ISILSilencerStats.isExtendedModeEnabled() then
        return effect, effect.soundRadius, effect.soundVolume
    end

    local reduction = clampNumber(
        getExtendedOption(effect.extendedReductionKey),
        effect.extendedReductionDefault,
        0,
        100)
    reduction = reduction * (effect.extendedReductionScale or 1.0)
    local multiplier = 1.0 - (reduction / 100.0)
    return effect, multiplier, multiplier
end

function ISILSilencerStats.getNoiseReduction(fullType)
    local effect, radiusMultiplier = getEffectValues(fullType)
    if not effect then
        return nil
    end
    return math.floor(((1.0 - radiusMultiplier) * 100.0) + 0.5)
end

function ISILSilencerStats.getConfiguredDurability(fullType)
    local effect = effects[fullType]
    if not effect then
        return nil
    end
    if effect.alwaysOneShot then
        return 1
    end
    return math.floor(clampNumber(
        getExtendedOption(effect.durabilityKey),
        effect.durabilityDefault,
        1,
        10000))
end

function ISILSilencerStats.isOurSuppressor(part)
    return part and effects[part:getFullType()] ~= nil
end

function ISILSilencerStats.isDurabilityTracked(part)
    local effect = part and effects[part:getFullType()] or nil
    return effect ~= nil and (effect.alwaysOneShot or ISILSilencerStats.isDurabilityEnabled())
end

local appliedStateKey = "ISILSuppressorStatsApplied"

local function getWeaponFamily(weapon)
    local fullType = weapon:getFullType()
    local registeredFamily = ISILWeaponSoundFamilies and ISILWeaponSoundFamilies[fullType]

    if registeredFamily then
        return registeredFamily
    end

    local modelFamily = ISILModelTable and ISILModelTable[fullType]
    if modelFamily == 0 then
        return "pistol"
    elseif modelFamily == 1 then
        return "shotgun"
    elseif modelFamily == 2 then
        return "rifle"
    end

    local reloadType = string.lower(tostring(weapon:getWeaponReloadType() or ""))
    local ammoType = string.lower(tostring(weapon:getAmmoType() or ""))

    if reloadType == "handgun" or reloadType == "revolver" then
        return "pistol"
    end

    if string.find(reloadType, "shotgun", 1, true)
        or string.find(ammoType, "shell_12g", 1, true)
        or string.find(ammoType, "shotgun_shells", 1, true) then
        return "shotgun"
    end

    return weapon:isTwoHandWeapon() and "rifle" or "pistol"
end

local function enforceSuppressedSound(weapon)
    if not weapon or not instanceof(weapon, "HandWeapon") or not weapon:isRanged() then
        return
    end

    local canon = weapon:getWeaponPart("Canon")
    local effect = canon and effects[canon:getFullType()] or nil
    if not effect then
        return
    end

    local family = getWeaponFamily(weapon)
    local suppressedSound = effect.sounds[family] or effect.sounds.rifle or effect.sounds.pistol
    if suppressedSound and weapon:getSwingSound() ~= suppressedSound then
        weapon:setSwingSound(suppressedSound)
    end
end

local function makeUnsuppressedCopy(weapon)
    local copy = instanceItem(weapon:getFullType())
    if not copy or not instanceof(copy, "HandWeapon") then
        return nil
    end

    local parts = weapon:getAllWeaponParts()
    if parts then
        for i = 0, parts:size() - 1 do
            local part = parts:get(i)
            if part and not effects[part:getFullType()] then
                local partCopy = instanceItem(part:getFullType())
                if partCopy and instanceof(partCopy, "WeaponPart") then
                    if copy.canAttachWeaponPart == nil or copy:canAttachWeaponPart(partCopy) then
                        copy:attachWeaponPart(partCopy)
                    end
                end
            end
        end
    end

    return copy
end

function ISILSilencerStats.apply(weapon, forceRestore)
    if not weapon or not instanceof(weapon, "HandWeapon") or not weapon:isRanged() then
        return
    end

    local canon = weapon:getWeaponPart("Canon")
    local effect, soundRadiusMultiplier, soundVolumeMultiplier
    if canon then
        effect, soundRadiusMultiplier, soundVolumeMultiplier = getEffectValues(canon:getFullType())
    end
    local modData = weapon:getModData()
    local wasApplied = modData and modData[appliedStateKey] == true

    -- Other mods may use the Canon slot and apply their own custom statistics.
    -- Never overwrite those values. This is especially important for native
    -- Guns of Marz suppressors, whose effects are managed by Gunworks.
    if canon and not effect then
        if modData then
            modData[appliedStateKey] = nil
        end
        return
    end

    -- Do not rebuild unrelated ranged weapons on equip. Only restore a weapon
    -- that was previously modified by this mod, or when one of our suppressors
    -- has just been removed.
    if not effect and not wasApplied and not forceRestore then
        return
    end

    local baseWeapon = makeUnsuppressedCopy(weapon)
    if not baseWeapon then
        return
    end

    weapon:setSoundRadius(baseWeapon:getSoundRadius())
    weapon:setSoundVolume(baseWeapon:getSoundVolume())
    weapon:setSwingSound(baseWeapon:getSwingSound())
    weapon:setMuzzleFlashModelKey(baseWeapon:getMuzzleFlashModelKey())

    if effect then
        weapon:setSoundRadius(baseWeapon:getSoundRadius() * soundRadiusMultiplier)
        weapon:setSoundVolume(baseWeapon:getSoundVolume() * soundVolumeMultiplier)
        enforceSuppressedSound(weapon)
        weapon:setMuzzleFlashModelKey(nil)
        if modData then
            modData[appliedStateKey] = true
        end
    elseif modData then
        modData[appliedStateKey] = nil
    end
end

local networkModule = "ISIL"
local networkCommand = "syncSuppressorState"
local networkRevisionKey = "ISILSuppressorNetworkRevision"
local appliedNetworkRevisions = {}

local function findNetworkWeapon(player, itemId)
    if not player or not itemId then
        return nil
    end

    local primary = player:getPrimaryHandItem()
    if primary and primary:getID() == itemId and instanceof(primary, "HandWeapon") then
        return primary
    end

    local secondary = player:getSecondaryHandItem()
    if secondary and secondary:getID() == itemId and instanceof(secondary, "HandWeapon") then
        return secondary
    end

    local inventory = player:getInventory()
    local item = inventory and inventory:getItemWithIDRecursiv(itemId) or nil
    return item and instanceof(item, "HandWeapon") and item or nil
end

local function findNetworkPlayer(onlineId)
    local player = getPlayerByOnlineID and getPlayerByOnlineID(onlineId) or nil
    if player then
        return player
    end

    if getNumActivePlayers and getSpecificPlayer then
        for playerIndex = 0, getNumActivePlayers() - 1 do
            local localPlayer = getSpecificPlayer(playerIndex)
            if localPlayer and localPlayer:getOnlineID() == onlineId then
                return localPlayer
            end
        end
    end

    return nil
end

local function applyNetworkWeaponState(state)
    local player = findNetworkPlayer(state.onlineId)
    local weapon = findNetworkWeapon(player, state.itemId)
    if not player or not weapon then
        return false
    end

    local key = tostring(state.onlineId) .. ":" .. tostring(state.itemId)
    local revision = tonumber(state.revision) or 0
    if revision < (appliedNetworkRevisions[key] or 0) then
        return true
    end

    local canon = weapon:getWeaponPart("Canon")
    local canonIsOurs = ISILSilencerStats.isOurSuppressor(canon)

    if state.attached == true then
        -- Never replace a newer foreign muzzle attachment with a delayed packet.
        if canon and not canonIsOurs then
            return true
        end
        if not canon and state.suppressorType then
            local visualPart = instanceItem(state.suppressorType)
            if visualPart and instanceof(visualPart, "WeaponPart") then
                weapon:attachWeaponPart(player, visualPart, false)
            end
        end
        weapon:getModData()[appliedStateKey] = true
    else
        -- The native hand-weapon packet does not consistently remove the part
        -- from observer copies. Detach only one of our parts and leave every
        -- foreign Canon attachment untouched.
        if canonIsOurs then
            weapon:detachWeaponPart(player, canon, false)
        elseif canon then
            return true
        end
        weapon:getModData()[appliedStateKey] = nil
    end

    -- Rebuild client-only fields that SyncHandWeaponFieldsPacket does not
    -- serialize at all (SoundRadius, SoundVolume, SwingSound and muzzle flash).
    -- The numeric/string values below remain authoritative for sound, while
    -- apply() also restores the locally typed muzzle-flash ModelKey safely.
    ISILSilencerStats.apply(weapon, state.attached ~= true)

    if state.soundRadius ~= nil then
        weapon:setSoundRadius(state.soundRadius)
    end
    if state.soundVolume ~= nil then
        weapon:setSoundVolume(state.soundVolume)
    end
    if state.swingSound ~= nil then
        weapon:setSwingSound(state.swingSound)
    end

    player:resetEquippedHandsModels()
    appliedNetworkRevisions[key] = revision
    return true
end

local function broadcastNetworkWeaponState(character, weapon, attached, suppressorType)
    if not isServer() or not character or not weapon then
        return
    end

    local modData = weapon:getModData()
    local revision = (tonumber(modData[networkRevisionKey]) or 0) + 1
    modData[networkRevisionKey] = revision

    local args = {
        onlineId = character:getOnlineID(),
        itemId = weapon:getID(),
        revision = revision,
        attached = attached == true,
        suppressorType = suppressorType,
        soundRadius = weapon:getSoundRadius(),
        soundVolume = weapon:getSoundVolume(),
        swingSound = weapon:getSwingSound(),
    }

    local players = getOnlinePlayers()
    for playerIndex = 0, players:size() - 1 do
        sendServerCommand(players:get(playerIndex), networkModule, networkCommand, args)
    end
end

local function onSuppressorServerCommand(module, command, args)
    if module ~= networkModule or command ~= networkCommand or not args then
        return
    end

    -- Apply immediately and retry briefly. Native hand-weapon packets and Lua
    -- server commands use separate network paths, so under latency the native
    -- packet can arrive later and temporarily restore the stale part/sound.
    -- A newer revision replaces this retry state instead of allowing an old
    -- remove packet to win over a subsequent attachment (or vice versa).
    applyNetworkWeaponState(args)
    local key = tostring(args.onlineId) .. ":" .. tostring(args.itemId)
    ISILPendingNetworkWeaponStates[key] = {
        state = args,
        retryTicks = { 2, 10, 30 },
        retryIndex = 1,
        age = 0,
    }
end

local function processPendingNetworkWeaponStates()
    for key, pending in pairs(ISILPendingNetworkWeaponStates) do
        pending.age = pending.age + 1
        local retryAt = pending.retryTicks[pending.retryIndex]
        if retryAt and pending.age >= retryAt then
            applyNetworkWeaponState(pending.state)
            pending.retryIndex = pending.retryIndex + 1
        end
        if not pending.retryTicks[pending.retryIndex] then
            ISILPendingNetworkWeaponStates[key] = nil
        end
    end
end

ISILSilencerDurability = ISILSilencerDurability or {}

local durabilityRemainingKey = "ISILDurabilityRemaining"
local durabilityMaximumKey = "ISILDurabilityMaximum"

local function updatePartCondition(part, remaining, maximum)
    if not part or maximum <= 0 then
        return
    end
    local conditionMaximum = math.max(1, part:getConditionMax())
    local condition = math.ceil(conditionMaximum * (remaining / maximum))
    part:setCondition(math.max(0, math.min(conditionMaximum, condition)))
end

function ISILSilencerDurability.initialize(part)
    if not ISILSilencerStats.isDurabilityTracked(part) then
        return nil, nil
    end

    local maximum = ISILSilencerStats.getConfiguredDurability(part:getFullType())
    local modData = part:getModData()
    local oldMaximum = tonumber(modData[durabilityMaximumKey])
    local remaining = tonumber(modData[durabilityRemainingKey])

    if remaining == nil or oldMaximum == nil or oldMaximum <= 0 then
        remaining = maximum
    elseif oldMaximum ~= maximum then
        -- Preserve the used percentage when a server changes its setting.
        remaining = math.ceil(math.max(0, math.min(1, remaining / oldMaximum)) * maximum)
    end

    remaining = math.max(0, math.min(maximum, remaining))
    modData[durabilityMaximumKey] = maximum
    modData[durabilityRemainingKey] = remaining
    updatePartCondition(part, remaining, maximum)
    return remaining, maximum
end

function ISILSilencerDurability.getRemaining(part)
    local remaining, maximum = ISILSilencerDurability.initialize(part)
    return remaining, maximum
end

-- Read the current durability without changing item state. This is used by
-- client-side UI code so merely hovering a weapon never initializes or
-- rewrites nested weapon-part modData, especially on multiplayer clients.
function ISILSilencerDurability.peek(part)
    if not ISILSilencerStats.isDurabilityTracked(part) then
        return nil, nil
    end

    local maximum = ISILSilencerStats.getConfiguredDurability(part:getFullType())
    local modData = part:getModData()
    local oldMaximum = tonumber(modData[durabilityMaximumKey])
    local remaining = tonumber(modData[durabilityRemainingKey])

    if remaining == nil or oldMaximum == nil or oldMaximum <= 0 then
        remaining = maximum
    elseif oldMaximum ~= maximum then
        remaining = math.ceil(math.max(0, math.min(1, remaining / oldMaximum)) * maximum)
    end

    return math.max(0, math.min(maximum, remaining)), maximum
end

local function onWeaponFired(character, weapon)
    -- In multiplayer, only the server changes durability. The client receives
    -- the resulting nested weapon-part state through syncHandWeaponFields.
    if isClient() and not isServer() then
        return
    end
    if not character or not weapon or not instanceof(weapon, "HandWeapon")
        or not weapon:isRanged() then
        return
    end

    local part = weapon:getWeaponPart("Canon")
    if not ISILSilencerStats.isOurSuppressor(part) then
        return
    end

    local effect = effects[part:getFullType()]
    if not effect.alwaysOneShot and not ISILSilencerStats.isDurabilityEnabled() then
        return
    end

    local remaining, maximum = ISILSilencerDurability.initialize(part)
    if remaining == nil then
        return
    end

    local wear = effect.alwaysOneShot and 1 or ISILSilencerStats.getCaliberWearMultiplier(weapon)
    remaining = math.max(0, remaining - wear)
    local modData = part:getModData()
    modData[durabilityRemainingKey] = remaining
    updatePartCondition(part, remaining, maximum)

    local destroyedSuppressorType = nil
    if remaining <= 0 then
        -- A failed suppressor is destroyed instead of being returned as a
        -- broken inventory item. Restore the weapon before synchronizing it.
        destroyedSuppressorType = part:getFullType()
        weapon:detachWeaponPart(character, part)
        local partContainer = part:getContainer()
        if partContainer then
            partContainer:Remove(part)
        end
        ISILSilencerStats.apply(weapon, true)
    end

    syncHandWeaponFields(character, weapon)
    if destroyedSuppressorType then
        -- The native hand-weapon packet does not reliably remove nested weapon
        -- parts from observer copies. Send the same explicit state transition
        -- used by manual removal so remote visuals and sound update at once.
        broadcastNetworkWeaponState(
            character,
            weapon,
            false,
            destroyedSuppressorType)
    end
end

local function captureWeaponState(character, weapon)
    if not character or not weapon then
        return nil
    end

    local primary = character:getPrimaryHandItem()
    local secondary = character:getSecondaryHandItem()

    return {
        primary = primary,
        secondary = secondary,
        container = weapon:getContainer(),
        wasEquipped = primary == weapon or secondary == weapon,
    }
end

local function takePendingWeaponState(weapon)
    if not weapon or not ISILPendingWeaponStates then
        return nil
    end

    local itemId = weapon:getID()
    local state = ISILPendingWeaponStates[itemId]
    ISILPendingWeaponStates[itemId] = nil
    return state
end

local function queueWeaponStateRestore(action)
    local character = action and action.character
    local weapon = action and action.weapon
    local state = action and action.ISILOriginalWeaponState

    if not character or not weapon or not state then
        return
    end

    -- Gunworks/GoM may run another completion hook after ours and equip the
    -- modified weapon. Restore on the next update after every hook has finished.
    ISILDeferredWeaponStates[weapon:getID()] = {
        character = character,
        weapon = weapon,
        state = state,
        ticks = 1,
    }
end

local originalUpgradeNew = ISUpgradeWeapon.new
function ISUpgradeWeapon:new(character, weapon, part, ...)
    local action = originalUpgradeNew(self, character, weapon, part, ...)
    if part and effects[part:getFullType()] then
        action.ISILOriginalWeaponState = takePendingWeaponState(weapon)
            or captureWeaponState(character, weapon)
    end
    return action
end

local originalRemoveNew = ISRemoveWeaponUpgrade.new
function ISRemoveWeaponUpgrade:new(character, weapon, partType, ...)
    local action = originalRemoveNew(self, character, weapon, partType, ...)
    local part = weapon and partType and weapon:getWeaponPart(partType) or nil
    if part and effects[part:getFullType()] then
        action.ISILOriginalWeaponState = takePendingWeaponState(weapon)
            or captureWeaponState(character, weapon)
    end
    return action
end

local originalUpgradeComplete = ISUpgradeWeapon.complete
function ISUpgradeWeapon:complete()
    local isOurSuppressor = self.part and effects[self.part:getFullType()] ~= nil

    -- Foreign weapon parts must remain entirely inside their owning framework's
    -- completion chain. In particular, Gunworks converts a generic Picatinny
    -- rail into a directional outcome part during this call.
    if not isOurSuppressor then
        return originalUpgradeComplete(self)
    end

    local result = originalUpgradeComplete(self)
    -- Gunworks synchronizes the weapon from its registered attachment stats.
    -- Apply our family-specific sound after that synchronization so it is not
    -- replaced with the weapon's original firing sound.
    ISILSilencerStats.apply(self.weapon)
    if isOurSuppressor then
        ISILSilencerDurability.initialize(self.part)
        -- In multiplayer the final custom values must be synchronized after
        -- they have been applied. Synchronizing first leaves remote copies
        -- with the weapon's previous state.
        if self.character and self.weapon then
            syncHandWeaponFields(self.character, self.weapon)
        end
        broadcastNetworkWeaponState(
            self.character,
            self.weapon,
            true,
            self.part:getFullType())
        queueWeaponStateRestore(self)
    end
    return result
end

local originalRemoveComplete = ISRemoveWeaponUpgrade.complete
function ISRemoveWeaponUpgrade:complete()
    local removedPart = self.weapon and self.partType and self.weapon:getWeaponPart(self.partType) or nil
    local isOurSuppressor = removedPart and effects[removedPart:getFullType()] ~= nil

    if not isOurSuppressor then
        return originalRemoveComplete(self)
    end

    local result = originalRemoveComplete(self)
    ISILSilencerStats.apply(self.weapon, isOurSuppressor)
    if isOurSuppressor then
        -- Restore first, then synchronize the unsuppressed values. The old
        -- order sent the still-suppressed state to multiplayer clients.
        if self.character and self.weapon then
            syncHandWeaponFields(self.character, self.weapon)
        end
        broadcastNetworkWeaponState(
            self.character,
            self.weapon,
            false,
            removedPart:getFullType())
        queueWeaponStateRestore(self)
    end
    return result
end

local function onEquipPrimary(character, item)
    ISILSilencerStats.apply(item)
    local part = item and instanceof(item, "HandWeapon") and item:getWeaponPart("Canon") or nil
    ISILSilencerDurability.initialize(part)
    if item and instanceof(item, "HandWeapon") then
        ISILObservedSuppressors[item:getID()] = ISILSilencerStats.isOurSuppressor(part)
            and part:getFullType() or nil
    end
end

local function onWeaponSwing(character, weapon)
    if not weapon or not instanceof(weapon, "HandWeapon") or not weapon:isRanged() then
        return
    end

    local canon = weapon:getWeaponPart("Canon")
    if not ISILSilencerStats.isOurSuppressor(canon) then
        return
    end

    -- Some weapon frameworks rebuild an equipped weapon from its script when
    -- it is drawn from a holster. If the player fires immediately afterwards,
    -- the first shot can otherwise use those restored unsuppressed values.
    -- Reassert only our suppressor state at swing start, immediately before the
    -- firing event consumes the weapon's current sound and noise statistics.
    ISILSilencerStats.apply(weapon)
end

local function onPlayerUpdate(character)
    if not character then
        return
    end

    for itemId, pending in pairs(ISILDeferredWeaponStates) do
        if pending.character == character then
            pending.ticks = pending.ticks - 1
            if pending.ticks <= 0 then
                local weapon = pending.weapon
                local state = pending.state

                character:setPrimaryHandItem(state.primary)
                character:setSecondaryHandItem(state.secondary)
                character:resetEquippedHandsModels()

                -- Hand changes do not dirty the inventory pane automatically.
                -- Mark only the affected containers so Build 42 rebuilds the
                -- equipped grouping and sorting on its next normal render.
                if not isServer() then
                    local playerInventory = character:getInventory()
                    if playerInventory then
                        playerInventory:setDrawDirty(true)
                    end
                    if state.container and state.container ~= playerInventory then
                        state.container:setDrawDirty(true)
                    end
                end

                -- Vanilla first transfers a weapon to the main inventory.
                -- Return an originally unequipped weapon to its prior container.
                local currentContainer = weapon and weapon:getContainer() or nil
                if weapon and not state.wasEquipped and state.container
                    and currentContainer and state.container ~= currentContainer
                    and ISTimedActionQueue and ISInventoryTransferAction then
                    ISTimedActionQueue.add(ISInventoryTransferAction:new(
                        character, weapon, currentContainer, state.container))
                end

                ISILDeferredWeaponStates[itemId] = nil
            end
        end
    end

    local primary = character:getPrimaryHandItem()
    if primary and instanceof(primary, "HandWeapon") and primary:isRanged() then
        local canon = primary:getWeaponPart("Canon")
        local currentSuppressor = ISILSilencerStats.isOurSuppressor(canon)
            and canon:getFullType() or nil
        local previousSuppressor = ISILObservedSuppressors[primary:getID()]

        if currentSuppressor then
            if currentSuppressor ~= previousSuppressor then
                ISILSilencerStats.apply(primary)
            end
            -- VFE may refresh SwingSound from its weapon script while equipped.
            enforceSuppressedSound(primary)
        elseif previousSuppressor then
            -- Local fallback for multiplayer: the native packet can remove the
            -- part without rerunning our Lua completion hook on the client.
            ISILSilencerStats.apply(primary, true)
        end

        ISILObservedSuppressors[primary:getID()] = currentSuppressor
    end
end

local function onGameStart()
    local player = getPlayer()
    if player then
        ISILSilencerStats.apply(player:getPrimaryHandItem())
        local weapon = player:getPrimaryHandItem()
        local part = weapon and instanceof(weapon, "HandWeapon") and weapon:getWeaponPart("Canon") or nil
        ISILSilencerDurability.initialize(part)
    end
end

Events.OnEquipPrimary.Add(onEquipPrimary)
Events.OnWeaponSwing.Add(onWeaponSwing)
Events.OnPlayerUpdate.Add(onPlayerUpdate)
Events.OnGameStart.Add(onGameStart)
Events.OnWeaponSwingHitPoint.Add(onWeaponFired)

if isClient() then
    Events.OnServerCommand.Add(onSuppressorServerCommand)
    Events.OnTick.Add(processPendingNetworkWeaponStates)
end
