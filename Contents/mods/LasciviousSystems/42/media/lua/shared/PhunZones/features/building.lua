local Core = PhunZones
Core.iniBuilding = function()
    if ISBuildingObject and ISBuildingObject.tryBuild and ISBuildingObject.isValid
        and not Core._buildingObjectHooksInstalled then
        Core._buildingObjectHooksInstalled = true
        local oldTryBuild = ISBuildingObject.tryBuild
        function ISBuildingObject:tryBuild(x, y, z)
            local playerObj = getSpecificPlayer(self.player)
            local zone = Core.getLocation(x, y) or {}
            if self.selectedSqDrop then
                -- assert placing an item
                if zone and zone.noplacing == true then
                    if playerObj then playerObj:setHaloNote(getText("IGUI_PhunZones_SayNoPlacing"), 255, 255, 0, 300) end
                    return false
                end
            else
                -- assert building an item
                if zone and zone.nobuilding == true and self.sledgehammer == nil and self.cacheObject == nil then
                    if playerObj then playerObj:setHaloNote(getText("IGUI_PhunZones_SayNoBuild"), 255, 255, 0, 300) end
                    return false
                end
            end

            return oldTryBuild(self, x, y, z)
        end

        local oldFn = ISBuildingObject.isValid
        function ISBuildingObject:isValid(square)
            if not square then return false end
            local playerObj = getSpecificPlayer(self.player)
            local zone = Core.getLocation(square) or {}
            if zone and zone.nobuilding == true and self.sledgehammer == nil and self.cacheObject == nil then
                if playerObj then playerObj:setHaloNote(getText("IGUI_PhunZones_SayNoBuild"), 255, 255, 0, 300) end
                return false
            end
            return oldFn(self, square)
        end
    end
    if ISBuildIsoEntity and ISBuildIsoEntity.isValid and not Core._buildIsoEntityHookInstalled then
        Core._buildIsoEntityHookInstalled = true
        local oldIsoEntityIsValid = ISBuildIsoEntity.isValid
        function ISBuildIsoEntity:isValid(square)
            if not square then return false end
            local playerObj = getSpecificPlayer(self.player)
            local zone = Core.getLocation(square) or {}
            if zone and zone.nobuilding == true and self.sledgehammer == nil and self.cacheObject == nil then
                if playerObj then playerObj:setHaloNote(getText("IGUI_PhunZones_SayNoBuild"), 255, 255, 0, 300) end
                return false
            end
            return oldIsoEntityIsValid(self, square)
        end
    end

    -- if ISMoveableCursor then
    --     local oldISMoveableCursorIsValid = ISMoveableCursor.isValid
    --     function ISMoveableCursor:isValid(square)
    --         if not square then
    --             return false
    --         end
    --         local zone = Core.getLocation(square) or {}
    --         local mode = self.moveableMode
    --         print(mode)
    --         if mode == "pickup" then

    --         end
    --         if zone and zone.noplacing == true then
    --             getSpecificPlayer(0):setHaloNote(getText("IGUI_PhunZones_SayNoPlacing"), 255, 255, 0, 300);
    --             return false
    --         end
    --         return oldISMoveableCursorIsValid(self, square)
    --     end
    -- end

    if buildUtil and buildUtil.canBePlace and not Core._buildUtilHookInstalled then
        Core._buildUtilHookInstalled = true
        local oldBuildUtilCanBePlace = buildUtil.canBePlace
        function buildUtil.canBePlace(...)
            local playerObj = getSpecificPlayer(0)
            local zone = Core.getEffectiveZone(playerObj)
            if zone and zone.nobuilding == true then
                if playerObj then playerObj:setHaloNote(getText("IGUI_PhunZones_SayNoBuild"), 255, 255, 0, 300) end
                return false
            end
            return oldBuildUtilCanBePlace(...)
        end

    end

end
