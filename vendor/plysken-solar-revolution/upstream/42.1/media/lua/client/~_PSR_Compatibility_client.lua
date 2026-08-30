local PSR = require "PSR/Utilities"   -- PSRUI déjà chargé par !_PSR_Compatibility_client (require redondant retiré)

if zombie.inventory.types.DrainableComboItem and zombie.inventory.types.DrainableComboItem.class then
    PSR.patchClassMetaMethod(zombie.inventory.types.DrainableComboItem.class, "DoTooltip", PSR.UI.DoTooltip_patch)
end

require "ISUI/ISInventoryPane"
ISInventoryPane.drawItemDetails = PSR.UI.ISInventoryPane_drawItemDetails_patch(ISInventoryPane.drawItemDetails)
