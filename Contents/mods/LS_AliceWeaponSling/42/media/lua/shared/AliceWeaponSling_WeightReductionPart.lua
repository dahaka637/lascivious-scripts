AliceWeaponSling = AliceWeaponSling or {}

AliceWeaponSling.WeightReductionPart = AliceWeaponSling.WeightReductionPart or {}

local AWS = AliceWeaponSling.WeightReductionPart

AWS.PART_FULL_TYPE = "Base.AliceWeaponSlingWeightReductionPart"
AWS.PART_TYPE = "Sling"
AWS.MODDATA_KEY = "AliceWeaponSlingWeightReductionPart"

local slingSlotTypes = {
    AliceSling = true,
    AliceSlingAlt = true,
    AliceSlingAlt2 = true,
    AliceSlingBack = true,
}

local function isAliceSlingSlotType(slotType)
    return slotType ~= nil and slingSlotTypes[tostring(slotType)] == true
end

local function isAliceSlingAttached(item)
    if not item or not item.getAttachedSlotType then return false end
    return isAliceSlingSlotType(item:getAttachedSlotType())
end

local function isHandWeapon(item)
    return item ~= nil and instanceof(item, "HandWeapon")
end

local function isEligibleWeapon(item)
    if not isHandWeapon(item) then return false end

    if not item:isRanged() or not item:isAimedFirearm() then return false end

    local attachmentType = item.getAttachmentType and item:getAttachmentType() or nil
    local maxRange = item.getMaxRange and item:getMaxRange() or 0

    return item:isTwoHandWeapon()
        or item:isRequiresEquippedBothHands()
        or attachmentType == "Rifle"
        or attachmentType == "Shotgun"
        or maxRange >= 10
end

local function getInstalledSlingPart(weapon)
    if not weapon or not weapon.getWeaponPart then return nil end
    return weapon:getWeaponPart(AWS.PART_TYPE)
end

local function isOurPart(part)
    return part ~= nil
        and part.getFullType ~= nil
        and part:getFullType() == AWS.PART_FULL_TYPE
end

local function syncWeapon(character, weapon)
    if syncHandWeaponFields and character and weapon then
        pcall(syncHandWeaponFields, character, weapon)
    elseif syncItemFields and character and weapon then
        pcall(syncItemFields, character, weapon)
    end
end

function AWS.apply(character, weapon)
    if not character or not weapon then return false end
    if not isAliceSlingAttached(weapon) then return false end
    if not isEligibleWeapon(weapon) then return false end

    local existingPart = getInstalledSlingPart(weapon)
    if existingPart then
        if isOurPart(existingPart) then
            weapon:getModData()[AWS.MODDATA_KEY] = true
            return true
        end

        return false
    end

    local part = instanceItem(AWS.PART_FULL_TYPE)
    if not part then return false end

    local attached = false

    if weapon.attachWeaponPart then
        attached = pcall(function()
            weapon:attachWeaponPart(character, part)
        end)

        if not attached then
            attached = pcall(function()
                weapon:attachWeaponPart(part, true)
            end)
        end
    end

    if attached then
        weapon:getModData()[AWS.MODDATA_KEY] = true
        syncWeapon(character, weapon)
        return true
    end

    return false
end

function AWS.remove(character, weapon)
    if not character or not weapon then return false end
    if not isHandWeapon(weapon) then return false end

    local modData = weapon:getModData()
    if not modData[AWS.MODDATA_KEY] then return false end

    local part = getInstalledSlingPart(weapon)
    if not isOurPart(part) then
        modData[AWS.MODDATA_KEY] = nil
        return false
    end

    local detached = false

    if weapon.detachWeaponPart then
        detached = pcall(function()
            weapon:detachWeaponPart(character, part)
        end)

        if not detached then
            detached = pcall(function()
                weapon:detachWeaponPart(part)
            end)
        end
    end

    modData[AWS.MODDATA_KEY] = nil

    if detached then
        syncWeapon(character, weapon)
        return true
    end

    return false
end

function AWS.refresh(character, weapon)
    if not weapon then return end

    if isAliceSlingAttached(weapon) then
        AWS.apply(character, weapon)
    else
        AWS.remove(character, weapon)
    end
end

function AliceWeaponSling.applyWeightReductionPart(character, weapon)
    return AWS.apply(character, weapon)
end

function AliceWeaponSling.removeWeightReductionPart(character, weapon)
    return AWS.remove(character, weapon)
end

function AliceWeaponSling.refreshWeightReductionPart(character, weapon)
    return AWS.refresh(character, weapon)
end

function AliceWeaponSling_CannotDetachHiddenWeightPart(character, weapon, part)
    return false
end