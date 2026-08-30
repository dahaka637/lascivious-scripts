-- Optional Vanilla Firearms Expansion [CLASSIC] compatibility for Build 42.

if not getActivatedMods():contains("VFExpansion1") then
    return
end

ISILWeaponSoundFamilies = ISILWeaponSoundFamilies or {}

local configLoaded = pcall(require, "Config/VFE_ConfigData")
local mountsLoaded, ISIL_ModelMounts = pcall(require, "ISIL_ModelMounts")

if not configLoaded or not VFExpansion or not VFExpansion.WEAPONS
    or not VFExpansion.WEAPONS.VFE then
    print("[Improvised Silencers] WARN: Vanilla Firearms Expansion weapon data could not be loaded.")
    return
end

if not mountsLoaded or not ISIL_ModelMounts then
    print("[Improvised Silencers] WARN: Visual mount helper could not be loaded; using standard VFE muzzle mounts.")
end

local ISIL_VFE_EXCLUDED = {
    -- These weapons already have an integral suppressor.
    MP5SD = true,
    MK2SD = true,
    MK23SOCOM = true,
    ShotgunSilent = true,
    CAR15D = true,
    CAR15DFolded = true,

    -- These special weapon states are not suitable for a muzzle attachment.
    AssaultRifleMasterkey = true,
    AssaultRifleMasterkeyShotgun = true,
    M60MMG = true,
    M60MMG_Bipod = true,
}

local ISIL_VFE_SILENCER_MODEL = "Base.ISILSilencerRifleVFE"

-- Never make the attachment invisible if a future game/mod update prevents
-- the VFE-only rendering alias from loading. The normal model remains a safe
-- visual fallback and does not affect suppressor functionality.
if not getScriptManager():getModelScript(ISIL_VFE_SILENCER_MODEL) then
    print("[Improvised Silencers] WARN: VFE professional suppressor model alias is unavailable; using the standard model.")
    ISIL_VFE_SILENCER_MODEL = "Base.SilencerRifle"
end

local ISIL_VFE_MODEL_PARTS = {
    pistol = {
        "ModelWeaponPart = Base.Silencer " .. ISIL_VFE_SILENCER_MODEL .. " muzzle muzzle",
        "ModelWeaponPart = Base.MetalPipeSilencer Base.MetalPipeSilencerVFE muzzle muzzle",
        "ModelWeaponPart = Base.TorchSilencer Base.TorchSilencerVFE muzzle muzzle",
        "ModelWeaponPart = Base.WaterBottleSilencer Base.WaterBottleSilencerVFE muzzle muzzle",
        "ModelWeaponPart = Base.PotatoSilencer Base.PotatoSilencer muzzle muzzle",
    },
    shotgun = {
        "ModelWeaponPart = Base.Silencer " .. ISIL_VFE_SILENCER_MODEL .. " muzzle muzzle",
        "ModelWeaponPart = Base.MetalPipeSilencer Base.MetalPipeSilencerRifleVFE muzzle muzzle",
    },
    rifle = {
        "ModelWeaponPart = Base.Silencer " .. ISIL_VFE_SILENCER_MODEL .. " muzzle muzzle",
        "ModelWeaponPart = Base.MetalPipeSilencer Base.MetalPipeSilencerRifleVFE muzzle muzzle",
        "ModelWeaponPart = Base.TorchSilencer Base.TorchSilencerRifleVFE muzzle muzzle",
        "ModelWeaponPart = Base.WaterBottleSilencer Base.WaterBottleSilencerRifleVFE muzzle muzzle",
        "ModelWeaponPart = Base.PotatoSilencer Base.PotatoSilencerRifle muzzle muzzle",
    },
}

-- Some VFE models need a suppressor-only mount because their muzzle-flash
-- anchor does not line up exactly with the visible end of the barrel.  Keep
-- the original muzzle rotation, but use a verified suppressor position.
local ISIL_VFE_AK47_MOUNTS = {
    {
        id = "isil_suppressor_mount",
        modelScript = "Base.AK47Solid",
        offset = { 0.0000, 0.3900, 0.0092 },
        rotationAttachment = "muzzle",
    },
    {
        id = "isil_suppressor_mount",
        modelScript = "Base.AK47Solid_NoMag",
        offset = { 0.0000, 0.3900, 0.0092 },
        rotationAttachment = "muzzle",
    },
    {
        id = "isil_suppressor_mount",
        modelScript = "Base.AK47SolidFGS",
        offset = { 0.0000, 0.3900, 0.0092 },
        rotationAttachment = "muzzle",
    },
    {
        id = "isil_suppressor_mount",
        modelScript = "Base.AK47SolidFGS_NoMag",
        offset = { 0.0000, 0.3900, 0.0092 },
        rotationAttachment = "muzzle",
    },
    {
        id = "isil_suppressor_mount",
        modelScript = "Base.AK47Unfolded",
        offset = { 0.0004, 0.3900, 0.0092 },
        rotationAttachment = "muzzle",
    },
    {
        id = "isil_suppressor_mount",
        modelScript = "Base.AK47Unfolded_NoMag",
        offset = { 0.0004, 0.3900, 0.0092 },
        rotationAttachment = "muzzle",
    },
    {
        id = "isil_suppressor_mount",
        modelScript = "Base.AK47Folded",
        offset = { 0.0000, 0.3900, 0.0092 },
        rotationAttachment = "muzzle",
    },
    {
        id = "isil_suppressor_mount",
        modelScript = "Base.AK47Folded_NoMag",
        offset = { 0.0000, 0.3900, 0.0092 },
        rotationAttachment = "muzzle",
    },
}

local ISIL_VFE_VISUAL_MOUNTS = {
    AK47 = ISIL_VFE_AK47_MOUNTS,
    AK47Unfolded = ISIL_VFE_AK47_MOUNTS,
    AK47Folded = ISIL_VFE_AK47_MOUNTS,
    Pistol = {
        id = "isil_suppressor_mount",
        modelScript = "Base.Handgun03",
        offset = { 0.0000, 0.1500, 0.0090 },
        rotationAttachment = "muzzle",
    },
    Pistol2 = {
        id = "isil_suppressor_mount",
        modelScript = "Base.M1911",
        offset = { 0.0000, 0.1450, 0.0180 },
        rotationAttachment = "muzzle",
    },
    Shotgun = {
        id = "isil_suppressor_mount",
        modelScript = "Base.Shotgun",
        positionAttachment = "choketube",
        rotationAttachment = "muzzle",
    },
    Shotgun2 = {
        id = "isil_suppressor_mount",
        modelScript = "Base.Shotgun2",
        offset = { 0.0000, -0.5488, 0.0255 },
        rotationAttachment = "muzzle",
    },
    ShotgunSemi = {
        id = "isil_suppressor_mount",
        modelScript = "Base.ShotgunSemi",
        positionAttachment = "choketube",
        rotationAttachment = "muzzle",
    },
    ShotgunSawnoff = {
        id = "isil_suppressor_mount",
        modelScript = "Base.ShotgunSawnOff",
        offset = { 0.0000, -0.2390, 0.0255 },
        rotationAttachment = "muzzle",
    },
    DoubleBarrelShotgun = {
        id = "isil_suppressor_mount",
        modelScript = "Base.DoubleBarrelShotgun",
        offset = { 0.0090, 0.5260, 0.0240 },
        rotationAttachment = "muzzle",
    },
}

local function ISIL_VFE_modelPartsFor(itemId, modelFamily)
    local parentAttachment = "muzzle"
    local config = ISIL_VFE_VISUAL_MOUNTS[itemId]

    if config and mountsLoaded and ISIL_ModelMounts then
        local configs = config.modelScript and { config } or config
        local mountId = nil
        local allMounted = true

        for _, mountConfig in ipairs(configs) do
            local ensuredId, reason = ISIL_ModelMounts.ensure(mountConfig)

            if ensuredId then
                mountId = ensuredId
            else
                allMounted = false
                print("[Improvised Silencers] WARN: VFE visual mount fallback for Base."
                    .. itemId .. ": " .. tostring(reason))
            end
        end

        if allMounted and mountId then
            parentAttachment = mountId
        end
    end

    if parentAttachment == "muzzle" then
        return ISIL_VFE_MODEL_PARTS[modelFamily]
    end

    local result = {}

    for _, parameter in ipairs(ISIL_VFE_MODEL_PARTS[modelFamily]) do
        local mappedParameter = string.gsub(parameter, " muzzle$", " " .. parentAttachment)
        table.insert(result, mappedParameter)
    end

    return result
end

local function ISIL_VFE_createItem(fullType)
    local ok, item = pcall(instanceItem, fullType)
    return ok and item or nil
end

local function ISIL_VFE_appendMountOn(attachmentFullType, weaponTypes)
    local scriptItem = getScriptManager():getItem(attachmentFullType)
    local attachment = ISIL_VFE_createItem(attachmentFullType)

    if not scriptItem or not attachment or not instanceof(attachment, "WeaponPart") then
        return false
    end

    local combined = {}
    local seen = {}
    local currentMountOn = attachment:getMountOn()

    if currentMountOn then
        for i = 0, currentMountOn:size() - 1 do
            local fullType = currentMountOn:get(i)

            if fullType and not seen[fullType] then
                seen[fullType] = true
                table.insert(combined, fullType)
            end
        end
    end

    for _, fullType in ipairs(weaponTypes) do
        if not seen[fullType] then
            seen[fullType] = true
            table.insert(combined, fullType)
        end
    end

    scriptItem:DoParam("MountOn = " .. table.concat(combined, ";"))
    return true
end

local function ISIL_VFE_modelFamily(itemId, weapon)
    local weaponClass = VFExpansion.WEAPON_CLASS and VFExpansion.WEAPON_CLASS[itemId]

    if weaponClass == "shotgun" or weaponClass == "autoshotgun" then
        return "shotgun"
    end

    if weaponClass == "pistol" or weaponClass == "smg" then
        return "pistol"
    end

    local reloadType = string.lower(tostring(weapon:getWeaponReloadType() or ""))
    local ammoType = string.lower(tostring(weapon:getAmmoType() or ""))

    if reloadType == "handgun" or reloadType == "revolver" then
        return "pistol"
    end

    if string.find(reloadType, "shotgun", 1, true)
        or string.find(ammoType, "shotgun_shells", 1, true) then
        return "shotgun"
    end

    return "rifle"
end

local vfeWeapons = {}
local vfeNonShotguns = {}
local familyCounts = { pistol = 0, shotgun = 0, rifle = 0 }
ISILVFEWeaponTypes = ISILVFEWeaponTypes or {}

for _, itemId in ipairs(VFExpansion.WEAPONS.VFE) do
    if not ISIL_VFE_EXCLUDED[itemId] then
        local fullType = "Base." .. itemId
        local scriptItem = getScriptManager():getItem(fullType)
        local weapon = ISIL_VFE_createItem(fullType)

        if scriptItem and weapon and instanceof(weapon, "HandWeapon") and weapon:isRanged() then
            local modelFamily = ISIL_VFE_modelFamily(itemId, weapon)

            for _, parameter in ipairs(ISIL_VFE_modelPartsFor(itemId, modelFamily)) do
                scriptItem:DoParam(parameter)
            end

            table.insert(vfeWeapons, fullType)
            ISILVFEWeaponTypes[fullType] = true
            ISILWeaponSoundFamilies[fullType] = modelFamily
            familyCounts[modelFamily] = familyCounts[modelFamily] + 1

            if modelFamily ~= "shotgun" then
                table.insert(vfeNonShotguns, fullType)
            end
        end
    end
end

if #vfeWeapons > 0 then
    ISIL_VFE_appendMountOn("Base.Silencer", vfeWeapons)
    ISIL_VFE_appendMountOn("Base.MetalPipeSilencer", vfeWeapons)
    ISIL_VFE_appendMountOn("Base.TorchSilencer", vfeNonShotguns)
    ISIL_VFE_appendMountOn("Base.WaterBottleSilencer", vfeNonShotguns)
    ISIL_VFE_appendMountOn("Base.PotatoSilencer", vfeNonShotguns)

    print("[Improvised Silencers] Added Vanilla Firearms Expansion compatibility for "
        .. #vfeWeapons .. " weapons (" .. familyCounts.pistol .. " pistol/SMG, "
        .. familyCounts.shotgun .. " shotgun, " .. familyCounts.rifle .. " rifle/carbine).")
end
