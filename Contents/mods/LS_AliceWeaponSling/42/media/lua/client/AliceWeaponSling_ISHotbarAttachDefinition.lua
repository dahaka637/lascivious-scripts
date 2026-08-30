if not ISHotbarAttachDefinition then return end

local function getTranslatedText(key, fallback)
    return getTextOrNull(key) or fallback
end

local function hasSlotType(slotType)
    for _, def in ipairs(ISHotbarAttachDefinition) do
        if def and def.type == slotType then return true end
    end
    return false
end

local function addSlingSlot(slot)
    if not hasSlotType(slot.type) then
        table.insert(ISHotbarAttachDefinition, slot)
    end
end

addSlingSlot({
    type = "AliceSling",
    name = getTranslatedText("IGUI_HotbarAttachment_AliceSling", "Sling - \\"),
    animset = "belt left",
    attachments = {
        Rifle = "AliceSlingRifle",
        BigBlade = "AliceSlingWeapon",
        BigBonk = "AliceSlingWeapon",
        BigWeapon = "AliceSlingWeapon",
        Shovel = "AliceSlingShovel",
    },
})

addSlingSlot({
    type = "AliceSlingAlt",
    name = getTranslatedText("IGUI_HotbarAttachment_AliceSlingAlt", "Sling - /"),
    animset = "belt left",
    attachments = {
        Rifle = "AliceSlingRifle2",
        BigBlade = "AliceSlingWeapon2",
        BigBonk = "AliceSlingWeapon2",
        BigWeapon = "AliceSlingWeapon2",
        Shovel = "AliceSlingShovel2",
    },
})

addSlingSlot({
    type = "AliceSlingAlt2",
    name = getTranslatedText("IGUI_HotbarAttachment_AliceSlingAlt2", "Sling --"),
    animset = "belt left",
    attachments = {
        Rifle = "AliceSlingRifle3",
        BigBlade = "AliceSlingWeapon3",
        BigBonk = "AliceSlingWeapon3",
        BigWeapon = "AliceSlingWeapon3",
        Shovel = "AliceSlingShovel3",
    },
})

addSlingSlot({
    type = "AliceSlingBack",
    name = getTranslatedText("IGUI_HotbarAttachment_AliceSlingBack", "Sling (Back)"),
    animset = "back",
    attachments = {
        Rifle = "AliceSlingRifle Back",
        BigBlade = "AliceSlingWeapon Back",
        BigBonk = "AliceSlingWeapon Back",
        BigWeapon = "AliceSlingWeapon Back",
        Shovel = "AliceSlingShovel Back",
    },
})

ISHotbarAttachDefinition.replacements = ISHotbarAttachDefinition.replacements or {}
ISHotbarAttachDefinition.replacements[1] = ISHotbarAttachDefinition.replacements[1] or { replacement = {} }
ISHotbarAttachDefinition.replacements[1].replacement = ISHotbarAttachDefinition.replacements[1].replacement or {}

local replacements = {
    RifleAliceSling = "AliceSlingRifleBag",
    ShovelAliceSling = "AliceSlingShovelBag",
    BigWeaponAliceSling = "AliceSlingWeaponBag",
    BigBladeAliceSling = "AliceSlingBladeBag",
    BigBonkAliceSling = "AliceSlingBladeBag",
}

for key, value in pairs(replacements) do
    ISHotbarAttachDefinition.replacements[1].replacement[key] = value
end