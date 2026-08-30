local AttachedItemMigration = {}

local function getAttachedLocation(character, item)
    if not character or not character.getAttachedItems then return nil end
    local okItems, attachedItems = pcall(character.getAttachedItems, character)
    if not okItems or not attachedItems or not attachedItems.getLocation then return nil end
    local okLocation, location = pcall(attachedItems.getLocation, attachedItems, item)
    if okLocation then return location end
    return nil
end

function AttachedItemMigration.move(character, item, target, syncFn)
    local originalModel = item:getAttachedToModel()
    if originalModel == target then return "unchanged", nil end
    local originalLocation = getAttachedLocation(character, item)
    local modelSet, modelError = pcall(item.setAttachedToModel, item, target)
    if not modelSet then return "failed", tostring(modelError) end
    local attached, attachError = pcall(character.setAttachedItem, character, target, item)
    if not attached then
        local errors = { tostring(attachError) }
        local rolledBack, rollbackError = pcall(item.setAttachedToModel, item, originalModel)
        if not rolledBack then
            errors[#errors + 1] = "model rollback failed: " .. tostring(rollbackError)
        end
        local currentLocation = getAttachedLocation(character, item)
        if originalLocation and currentLocation ~= originalLocation then
            local restored, restoreError = pcall(character.setAttachedItem, character, originalLocation, item)
            if not restored then
                errors[#errors + 1] = "attachment rollback failed: " .. tostring(restoreError)
            end
        end
        return "failed", table.concat(errors, "; ")
    end
    if syncFn then
        local synced, syncError = pcall(syncFn, character, item)
        if not synced then return "moved", tostring(syncError) end
    end
    return "moved", nil
end

return AttachedItemMigration
