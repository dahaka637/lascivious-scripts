require "Moveables/ISMoveablesAction"
local Core = PhunZones

if ISMoveablesAction and ISMoveablesAction.isValid and not Core._movablesHookInstalled then
    Core._movablesHookInstalled = true
    local oldISMoveablesAction = ISMoveablesAction.isValid
    function ISMoveablesAction:isValid()
        local character = self.character
        local square = character and character:getSquare()

        if not square then
            return false
        end
        local zone = Core.getEffectiveZone(character)
        if zone and zone.noplacing == true and self.mode == "place" then
            character:setHaloNote(getText("IGUI_PhunZones_SayNoPlacing"), 255, 255, 0, 300)
            return false
        elseif zone and zone.nopickup == true and self.mode == "pickup" then
            character:setHaloNote(getText("IGUI_PhunZones_SayNoPickup"), 255, 255, 0, 300)
            return false
        elseif zone and zone.noscrap == true and self.mode == "scrap" then
            character:setHaloNote(getText("IGUI_PhunZones_SayNoScrap"), 255, 255, 0, 300)
            return false
        end
        return oldISMoveablesAction(self)
    end
end
