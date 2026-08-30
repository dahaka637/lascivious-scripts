require "ISUI/ISInventoryPaneContextMenu"

ISILPendingWeaponStates = ISILPendingWeaponStates or {}
ISILWeaponStateCompatibility = ISILWeaponStateCompatibility or {}

function ISILWeaponStateCompatibility.rememberWeaponState(character, weapon, part)
    if not character or not weapon or not ISILSilencerStats
        or not ISILSilencerStats.isOurSuppressor(part) then
        return
    end

    local primary = character:getPrimaryHandItem()
    local secondary = character:getSecondaryHandItem()

    ISILPendingWeaponStates[weapon:getID()] = {
        primary = primary,
        secondary = secondary,
        container = weapon:getContainer(),
        wasEquipped = primary == weapon or secondary == weapon,
    }
end

-- Do not replace the global Build 42/GoM upgrade handlers. Guns of Marz and
-- Gunworks use those handlers for their generic-to-directional rail conversion.
-- Instead, decorate only context-menu entries whose part belongs to this mod.
local function wrapSuppressorOption(option)
    if not option or option.ISILWeaponStateWrapped or type(option.onSelect) ~= "function" then
        return
    end

    local part = option.param1
    local typeCheckSucceeded, isWeaponPart = pcall(instanceof, part, "WeaponPart")
    if not typeCheckSucceeded or not isWeaponPart or not ISILSilencerStats
        or not ISILSilencerStats.isOurSuppressor(part) then
        return
    end

    local originalOnSelect = option.onSelect
    option.onSelect = function(weapon, selectedPart, character, ...)
        ISILWeaponStateCompatibility.rememberWeaponState(character, weapon, selectedPart)
        return originalOnSelect(weapon, selectedPart, character, ...)
    end
    option.ISILWeaponStateWrapped = true
end

local function wrapSuppressorOptions(context, menu, visited)
    if not context or not menu or not menu.options then
        return
    end

    visited = visited or {}
    if visited[menu] then
        return
    end
    visited[menu] = true

    for _, option in ipairs(menu.options) do
        wrapSuppressorOption(option)

        if option.subOption then
            local subMenu = context:getSubMenu(option.subOption)
            wrapSuppressorOptions(context, subMenu, visited)
        end
    end
end

local function installTargetedContextHooks(playerIndex, context)
    wrapSuppressorOptions(context, context)
end

Events.OnFillInventoryObjectContextMenu.Add(installTargetedContextHooks)
