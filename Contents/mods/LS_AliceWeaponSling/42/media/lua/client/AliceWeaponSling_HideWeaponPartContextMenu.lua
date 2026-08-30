AliceWeaponSling = AliceWeaponSling or {}

local AWS_PART_FULL_TYPE = "Base.AliceWeaponSlingWeightReductionPart"

local function isAliceHiddenWeightPart(part)
    return part ~= nil
        and part.getFullType ~= nil
        and part:getFullType() == AWS_PART_FULL_TYPE
end

if ISInventoryPaneContextMenu and not ISInventoryPaneContextMenu.AliceWeaponSling_HideHiddenPart then
    ISInventoryPaneContextMenu.AliceWeaponSling_HideHiddenPart = true

    local vanillaOnRemoveUpgradeWeapon = ISInventoryPaneContextMenu.onRemoveUpgradeWeapon

    ISInventoryPaneContextMenu.onRemoveUpgradeWeapon = function(weapon, part, playerObj)
        if isAliceHiddenWeightPart(part) then
            return
        end

        return vanillaOnRemoveUpgradeWeapon(weapon, part, playerObj)
    end
end

if ISRemoveWeaponUpgrade and not ISRemoveWeaponUpgrade.AliceWeaponSling_BlockHiddenPart then
    ISRemoveWeaponUpgrade.AliceWeaponSling_BlockHiddenPart = true

    local vanillaIsValid = ISRemoveWeaponUpgrade.isValid
    local vanillaComplete = ISRemoveWeaponUpgrade.complete

    function ISRemoveWeaponUpgrade:isValid(...)
        if self.weapon and self.partType then
            local part = self.weapon:getWeaponPart(self.partType)
            if isAliceHiddenWeightPart(part) then
                return false
            end
        end

        return vanillaIsValid(self, ...)
    end

    function ISRemoveWeaponUpgrade:complete(...)
        if self.weapon and self.partType then
            local part = self.weapon:getWeaponPart(self.partType)
            if isAliceHiddenWeightPart(part) then
                return false
            end
        end

        return vanillaComplete(self, ...)
    end
end