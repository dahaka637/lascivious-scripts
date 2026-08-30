local Core = PhunZones

if ISDestroyStuffAction and ISDestroyStuffAction.isValid and not Core._destroyActionHookInstalled then
Core._destroyActionHookInstalled = true
local oldDestroyStuffAction = ISDestroyStuffAction.isValid

ISDestroyStuffAction.isValid = function(self)

    if self.character then

        local p = self.character
        local md = Core.getEffectiveZone(p)

        if md and md.nodestruction == true then
            p:setHaloNote(getText("IGUI_PhunZones_SayNoDestruction"), 255, 255, 0, 300);
            return false
        end

    end
    return oldDestroyStuffAction(self)

end
end

if ISDestroyCursor and ISDestroyCursor.isValid and not Core._destroyCursorHookInstalled then
    Core._destroyCursorHookInstalled = true
    local oldISDestroyIsValid = ISDestroyCursor.isValid
    function ISDestroyCursor:isValid(square)
        if not square then
            return false
        end
        local zone = Core.getLocation(square) or {}
        local noDestroy = zone.nodestruction == true
        if noDestroy then
            self.character:setHaloNote(getText("IGUI_PhunZones_SayNoDestruction"), 255, 255, 0, 300);
            return false
        end
        return oldISDestroyIsValid(self, square)
    end
end
