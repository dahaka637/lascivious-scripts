-- Keep Gunworks' late-added universal attachment menu beside the vanilla
-- weapon-upgrade controls. This changes presentation only; the original
-- option object and its existing submenu remain untouched.

local function ISIL_isInstanceOf(object, className)
    if not object then return false end

    local succeeded, matches = pcall(instanceof, object, className)
    return succeeded and matches
end

local function ISIL_isGoMWeaponSelected(items)
    for _, entry in ipairs(items or {}) do
        local item = nil

        if ISIL_isInstanceOf(entry, "InventoryItem") then
            item = entry
        elseif type(entry) == "table" and entry.items then
            item = entry.items[1]
        end

        if ISIL_isInstanceOf(item, "HandWeapon") then
            local fullType = item:getFullType()

            if fullType and string.sub(fullType, 1, 9) == "MarzGuns." then
                return true
            end
        end
    end

    return false
end

local function ISIL_isGoMRailUpgradeMenu(context, option)
    local subMenu = option.subOption and context:getSubMenu(option.subOption) or nil

    if not subMenu or not subMenu.options then
        return false
    end

    local railPrefix = "MarzGuns.Picatinny_Rail_"
    local genericRail = instanceItem("MarzGuns.Picatinny_Rail")
    local genericRailName = genericRail and genericRail:getDisplayName() or nil

    for _, childOption in ipairs(subMenu.options) do
        local outcomePart = childOption.param1

        if ISIL_isInstanceOf(outcomePart, "WeaponPart") then
            local fullType = outcomePart:getFullType()

            if fullType and string.sub(fullType, 1, #railPrefix) == railPrefix then
                return true
            end
        elseif genericRailName and childOption.name == genericRailName then
            return true
        end
    end

    return false
end

local function ISIL_positionAddWeaponUpgradeMenu(playerIndex, context, items)
    if not context or not context.options then return end
    if not ISIL_isGoMWeaponSelected(items) then return end

    local addName = getText("ContextMenu_Add_Weapon_Upgrade")
    local removeName = getText("ContextMenu_Remove_Weapon_Upgrade")
    local addIndex = nil
    local removeIndex = nil
    local addOption = nil

    for index, option in ipairs(context.options) do
        if option.name == addName then
            addIndex = index
            addOption = option
        elseif option.name == removeName then
            removeIndex = index
        end
    end

    if not addIndex or not removeIndex or addIndex == removeIndex - 1
        or not ISIL_isGoMRailUpgradeMenu(context, addOption) then
        return
    end

    table.remove(context.options, addIndex)

    if addIndex < removeIndex then
        removeIndex = removeIndex - 1
    end

    table.insert(context.options, removeIndex, addOption)

    context:calcHeight()
    context:setWidth(context:calcWidth())
end

local activatedMods = getActivatedMods()

if activatedMods and (activatedMods:contains("MarzGuns") or activatedMods:contains("GunsOfMarz")) then
    Events.OnFillInventoryObjectContextMenu.Add(ISIL_positionAddWeaponUpgradeMenu)
end
