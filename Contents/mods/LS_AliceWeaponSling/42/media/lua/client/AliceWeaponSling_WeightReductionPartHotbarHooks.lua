require "Hotbar/ISHotbar"
require "TimedActions/ISDetachItemHotbar"

AliceWeaponSling = AliceWeaponSling or {}

local function removeAliceWeightPart(character, item)
    if not character or not item then return end

    if AliceWeaponSling.removeWeightReductionPart then
        pcall(AliceWeaponSling.removeWeightReductionPart, character, item)
    end
end

if ISDetachItemHotbar
        and ISDetachItemHotbar.perform
        and not ISDetachItemHotbar.AliceWeaponSling_WeightPartRemove then
    ISDetachItemHotbar.AliceWeaponSling_WeightPartRemove = true

    local vanillaPerform = ISDetachItemHotbar.perform

    function ISDetachItemHotbar:perform(...)
        removeAliceWeightPart(self.character or (self.hotbar and self.hotbar.chr), self.item)
        return vanillaPerform(self, ...)
    end
end

if ISHotbar
        and ISHotbar.removeItem
        and not ISHotbar.AliceWeaponSling_WeightPartRemove then
    ISHotbar.AliceWeaponSling_WeightPartRemove = true

    local vanillaRemoveItem = ISHotbar.removeItem

    function ISHotbar:removeItem(item, doAnim, ...)
        if doAnim == false then
            removeAliceWeightPart(self.chr, item)
        end

        return vanillaRemoveItem(self, item, doAnim, ...)
    end
end