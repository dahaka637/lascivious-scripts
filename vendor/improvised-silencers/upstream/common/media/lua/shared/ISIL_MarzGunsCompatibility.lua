-- Automatic Guns of Marz compatibility for Build 42.
--
-- Guns of Marz already declares which weapons accept parts in the Canon
-- (muzzle) slot. Reusing those lists keeps this patch compatible with future
-- GoM updates without hard-coding every weapon ID here. GoM firearms omitted
-- from those lists are discovered separately and use their model-level muzzle
-- attachment without changing the established Canon path.

local activatedMods = getActivatedMods()

local oldMarzActive = activatedMods and activatedMods:contains("MarzGuns")
local newMarzActive = activatedMods and activatedMods:contains("GunsOfMarz")

if not oldMarzActive and not newMarzActive then
    return
end

local ISIL_MARZ_MODULE = "MarzGuns"
ISILWeaponSoundFamilies = ISILWeaponSoundFamilies or {}
local mountsLoaded, ISIL_ModelMounts = pcall(require, "ISIL_ModelMounts")
local ISIL_MARZ_DIRECT_MUZZLE = {}

-- These weapons are already suppressed by design or are internal/special
-- weapon states that must never receive an additional suppressor.
local ISIL_MARZ_FALLBACK_EXCLUDED = {
    ["MarzGuns.ASVAL"] = true,
    ["MarzGuns.MP5SD"] = true,
    ["MarzGuns.M79"] = true,
    ["MarzGuns.M203_Weapon"] = true,
    ["MarzGuns.MASTERKEY_Weapon"] = true,
}

if not mountsLoaded or not ISIL_ModelMounts then
    print("[Improvised Silencers] WARN: Visual mount helper could not be loaded; using standard GoM muzzle mounts.")
end

local ISIL_MODEL_PARTS = {
    pistol = {
        "ModelWeaponPart = Base.Silencer Base.SilencerRifle canon muzzle",
        "ModelWeaponPart = Base.MetalPipeSilencer Base.MetalPipeSilencer canon muzzle",
        "ModelWeaponPart = Base.TorchSilencer Base.TorchSilencer canon muzzle",
        "ModelWeaponPart = Base.WaterBottleSilencer Base.WaterBottleSilencer canon muzzle",
        "ModelWeaponPart = Base.PotatoSilencer Base.PotatoSilencer canon muzzle",
    },
    shotgun = {
        "ModelWeaponPart = Base.Silencer Base.SilencerRifle muzzle muzzle",
        "ModelWeaponPart = Base.MetalPipeSilencer Base.MetalPipeSilencerRifle muzzle muzzle",
    },
    rifle = {
        "ModelWeaponPart = Base.Silencer Base.SilencerRifle canon muzzle",
        "ModelWeaponPart = Base.MetalPipeSilencer Base.MetalPipeSilencerRifle canon muzzle",
        "ModelWeaponPart = Base.TorchSilencer Base.TorchSilencerRifle canon muzzle",
        "ModelWeaponPart = Base.WaterBottleSilencer Base.WaterBottleSilencerRifle canon muzzle",
        "ModelWeaponPart = Base.PotatoSilencer Base.PotatoSilencerRifle canon muzzle",
    },
}

-- GoM places the muzzle points on these weapons slightly ahead of the visible
-- barrel. Move only their offsets to the verified canon positions while
-- preserving the original muzzle rotations used by ISIL suppressor models.
local ISIL_MARZ_MUZZLE_OFFSETS = {
    ["MarzGuns.M16A2"] = { 0.0000, 0.4565, 0.0244 },
    ["MarzGuns.M4A1"] = { 0.0000, 0.3599, 0.0243 },
}

for modelScript, offset in pairs(ISIL_MARZ_MUZZLE_OFFSETS) do
    local model = getScriptManager():getModelScript(modelScript)
    local muzzle = model and model:getAttachmentById("muzzle") or nil

    if muzzle then
        muzzle:getOffset():set(offset[1], offset[2], offset[3])
    else
        print("[Improvised Silencers] WARN: GoM muzzle offset could not be applied to " .. modelScript)
    end
end

local ISIL_MARZ_VISUAL_MOUNTS = {
    ["MarzGuns.CAR15"] = {
        id = "isil_suppressor_mount",
        modelScript = "MarzGuns.CAR15",
        offset = { 0.0000, 0.3787, 0.0258 },
        rotationAttachment = "muzzle",
    },
    ["MarzGuns.AR15"] = {
        id = "isil_suppressor_mount",
        modelScript = "MarzGuns.AR15",
        offset = { 0.0000, 0.4816, 0.0247 },
        rotationAttachment = "muzzle",
    },
    ["MarzGuns.XM177"] = {
        id = "isil_suppressor_mount",
        modelScript = "MarzGuns.XM177",
        offset = { 0.0000, 0.3701, 0.0258 },
        rotationAttachment = "muzzle",
    },
    ["MarzGuns.M1895"] = {
        id = "isil_suppressor_mount",
        modelScript = "MarzGuns.M1895",
        offset = { 0.0000, 0.4722, 0.0313 },
        rotationAttachment = "muzzle",
    },
    ["MarzGuns.M14"] = {
        id = "isil_suppressor_mount",
        modelScript = "MarzGuns.M14",
        offset = { 0.0000, 0.5372, 0.0304 },
        rotationAttachment = "muzzle",
    },
    ["MarzGuns.BAR"] = {
        id = "isil_suppressor_mount",
        modelScript = "MarzGuns.BAR",
        offset = { 0.0000, 0.5187, 0.0283 },
        rotationAttachment = "muzzle",
    },
    ["MarzGuns.SKS"] = {
        id = "isil_suppressor_mount",
        modelScript = "MarzGuns.SKS",
        offset = { 0.0000, 0.5161, 0.0214 },
        rotationAttachment = "muzzle",
    },
    ["MarzGuns.MODEL_70"] = {
        id = "isil_suppressor_mount",
        modelScript = "MarzGuns.MODEL_70",
        offset = { 0.0000, 0.4300, 0.0199 },
        rotationAttachment = "muzzle",
    },
}

local function ISIL_modelPartsFor(fullType, modelFamily)
    local parentAttachment = "muzzle"
    local config = ISIL_MARZ_VISUAL_MOUNTS[fullType]
    local modelParts = ISIL_MODEL_PARTS[modelFamily]

    -- Newly discovered weapons do not have GoM's Canon attachment contract.
    -- Attach only their ISIL model parts directly to the verified muzzle point.
    if ISIL_MARZ_DIRECT_MUZZLE[fullType] and modelFamily ~= "shotgun" then
        modelParts = {}

        for _, parameter in ipairs(ISIL_MODEL_PARTS[modelFamily]) do
            local mappedParameter = string.gsub(parameter, " canon muzzle$", " muzzle muzzle")
            table.insert(modelParts, mappedParameter)
        end
    end

    if config and mountsLoaded and ISIL_ModelMounts then
        local mountId, reason = ISIL_ModelMounts.ensure(config)

        if mountId then
            parentAttachment = mountId
        else
            print("[Improvised Silencers] WARN: GoM visual mount fallback for "
                .. fullType .. ": " .. tostring(reason))
        end
    end

    if parentAttachment == "muzzle" then
        return modelParts
    end

    local result = {}

    for _, parameter in ipairs(modelParts) do
        local mappedParameter = string.gsub(parameter, " muzzle$", " " .. parentAttachment)
        table.insert(result, mappedParameter)
    end

    return result
end

local function ISIL_createItem(fullType)
    local ok, item = pcall(function()
        return instanceItem(fullType)
    end)

    if ok then
        return item
    end

    return nil
end

local function ISIL_isRangedWeaponScript(scriptItem)
    return scriptItem
        and scriptItem:isItemType(ItemType.WEAPON)
        and scriptItem:isRanged()
end

local function ISIL_getScriptModelFamily(scriptItem)
    local swingAnim = string.lower(tostring(scriptItem and scriptItem:getSwingAnim() or ""))
    local ammoType = string.lower(tostring(scriptItem and scriptItem:getAmmoType() or ""))

    if swingAnim == "handgun" then
        return "pistol"
    end

    if string.find(ammoType, "shell_12g", 1, true) then
        return "shotgun"
    end

    return "rifle"
end

local function ISIL_registerGunworksStats()
    local okCSA, customStats = pcall(require, "WeaponSystems/Utils/CustomStatsAttachments")
    local okSF, statsFactory = pcall(require, "WeaponSystems/Utils/StatsFactory")

    if not okCSA or not okSF or not customStats or not statsFactory then
        print("[Improvised Silencers] WARN: Gunworks stats integration could not be loaded.")
        return false
    end

    customStats.RegisterRestoreStats({
        "SoundRadius",
        "SoundVolume",
        "SwingSound",
        "MuzzleFlashModelKey",
    })

    customStats.RegisterMultipleParts({
        ["Base.Silencer"] = {
            statsFactory.Multiply("SoundRadius", 0.20),
            statsFactory.Multiply("SoundVolume", 0.30),
            statsFactory.Set("MuzzleFlashModelKey", nil),
        },
        ["Base.MetalPipeSilencer"] = {
            statsFactory.Multiply("SoundRadius", 0.40),
            statsFactory.Multiply("SoundVolume", 0.50),
            statsFactory.Set("MuzzleFlashModelKey", nil),
        },
        ["Base.TorchSilencer"] = {
            statsFactory.Multiply("SoundRadius", 0.60),
            statsFactory.Multiply("SoundVolume", 0.70),
            statsFactory.Set("MuzzleFlashModelKey", nil),
        },
        ["Base.WaterBottleSilencer"] = {
            statsFactory.Multiply("SoundRadius", 0.80),
            statsFactory.Multiply("SoundVolume", 0.80),
            statsFactory.Set("MuzzleFlashModelKey", nil),
        },
        ["Base.PotatoSilencer"] = {
            statsFactory.Multiply("SoundRadius", 0.90),
            statsFactory.Multiply("SoundVolume", 0.90),
            statsFactory.Set("MuzzleFlashModelKey", nil),
        },
    })

    return true
end

local function ISIL_getMarzMuzzleWeapons()
    local result = {}
    local seen = {}
    local scriptManager = getScriptManager()
    local allItems = scriptManager and scriptManager:getAllItems() or nil

    if not allItems then
        return result
    end

    -- Read every GoM Canon part rather than relying on suppressor names. This
    -- includes weapons supported by suppressors, compensators and muzzle brakes.
    for i = 0, allItems:size() - 1 do
        local scriptItem = allItems:get(i)

        if scriptItem
            and scriptItem:getModuleName() == ISIL_MARZ_MODULE
            and scriptItem:isItemType(ItemType.WEAPON_PART) then
            local part = ISIL_createItem(scriptItem:getFullName())

            if part and instanceof(part, "WeaponPart") and part:getPartType() == "Canon" then
                local mountOn = part:getMountOn()

                if mountOn then
                    for mountIndex = 0, mountOn:size() - 1 do
                        local weaponFullType = mountOn:get(mountIndex)

                        if weaponFullType and not seen[weaponFullType] then
                            local weaponScript = scriptManager:getItem(weaponFullType)

                            if ISIL_isRangedWeaponScript(weaponScript) then
                                seen[weaponFullType] = true
                                table.insert(result, weaponFullType)
                            end
                        end
                    end
                end
            end
        end
    end

    table.sort(result)
    return result
end

local function ISIL_appendMountOn(attachmentFullType, weaponTypes)
    local scriptItem = getScriptManager():getItem(attachmentFullType)
    local attachment = ISIL_createItem(attachmentFullType)

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

local function ISIL_addMarzShotguns(weaponTypes)
    local seen = {}

    for _, fullType in ipairs(weaponTypes) do
        seen[fullType] = true
    end

    local scriptManager = getScriptManager()
    local allItems = scriptManager and scriptManager:getAllItems() or nil

    if not allItems then
        return 0
    end

    local added = 0

    for i = 0, allItems:size() - 1 do
        local scriptItem = allItems:get(i)

        if scriptItem and scriptItem:getModuleName() == ISIL_MARZ_MODULE then
            local fullType = scriptItem:getFullName()

            if fullType and not seen[fullType] then
                if ISIL_isRangedWeaponScript(scriptItem)
                    and ISIL_getScriptModelFamily(scriptItem) == "shotgun" then
                    seen[fullType] = true
                    table.insert(weaponTypes, fullType)
                    added = added + 1
                end
            end
        end
    end

    table.sort(weaponTypes)
    return added
end

local function ISIL_getWeaponMuzzleModel(scriptItem)
    local scriptManager = getScriptManager()
    local weaponSprite = tostring(scriptItem and scriptItem:getWeaponSprite() or "")

    if not scriptManager or weaponSprite == "" then
        return nil
    end

    local model = scriptManager:getModelScript(weaponSprite)

    if not model and not string.find(weaponSprite, ".", 1, true) then
        model = scriptManager:getModelScript(ISIL_MARZ_MODULE .. "." .. weaponSprite)
    end

    if model and model:getAttachmentById("muzzle") then
        return model
    end

    return nil
end

local function ISIL_isMarzFallbackWeapon(fullType, scriptItem)
    if ISIL_MARZ_FALLBACK_EXCLUDED[fullType]
        or not ISIL_isRangedWeaponScript(scriptItem) then
        return false
    end

    -- Exclude current and future standalone GoM grenade-launcher ammunition.
    -- A regular rifle carrying an M203 still uses normal rifle ammunition and
    -- therefore remains eligible.
    local ammoType = string.lower(tostring(scriptItem:getAmmoType() or ""))

    if string.find(ammoType, "40mm", 1, true) then
        return false
    end

    return ISIL_getWeaponMuzzleModel(scriptItem) ~= nil
end

local function ISIL_addMarzFallbackWeapons(weaponTypes)
    local seen = {}

    for _, fullType in ipairs(weaponTypes) do
        seen[fullType] = true
    end

    local scriptManager = getScriptManager()
    local allItems = scriptManager and scriptManager:getAllItems() or nil

    if not allItems then
        return 0
    end

    local added = 0

    for i = 0, allItems:size() - 1 do
        local scriptItem = allItems:get(i)

        if scriptItem and scriptItem:getModuleName() == ISIL_MARZ_MODULE then
            local fullType = scriptItem:getFullName()

            if fullType and not seen[fullType] then
                if ISIL_isMarzFallbackWeapon(fullType, scriptItem) then
                    seen[fullType] = true
                    ISIL_MARZ_DIRECT_MUZZLE[fullType] = true
                    table.insert(weaponTypes, fullType)
                    added = added + 1
                end
            end
        end
    end

    table.sort(weaponTypes)
    return added
end

local function ISIL_addMarzModels(weaponTypes)
    for _, fullType in ipairs(weaponTypes) do
        local scriptItem = getScriptManager():getItem(fullType)

        if ISIL_isRangedWeaponScript(scriptItem) then
            local modelFamily = ISIL_getScriptModelFamily(scriptItem)
            ISILWeaponSoundFamilies[fullType] = modelFamily

            for _, parameter in ipairs(ISIL_modelPartsFor(fullType, modelFamily)) do
                scriptItem:DoParam(parameter)
            end
        end
    end
end

local marzWeapons = ISIL_getMarzMuzzleWeapons()
local marzShotgunsAdded = ISIL_addMarzShotguns(marzWeapons)
local marzFallbackAdded = ISIL_addMarzFallbackWeapons(marzWeapons)

if #marzWeapons > 0 then
    ISIL_registerGunworksStats()

    local marzNonShotguns = {}

    for _, weaponFullType in ipairs(marzWeapons) do
        local weaponScript = getScriptManager():getItem(weaponFullType)

        if ISIL_isRangedWeaponScript(weaponScript)
            and ISIL_getScriptModelFamily(weaponScript) ~= "shotgun" then
            table.insert(marzNonShotguns, weaponFullType)
        end
    end

    ISIL_appendMountOn("Base.Silencer", marzWeapons)
    ISIL_appendMountOn("Base.MetalPipeSilencer", marzWeapons)
    ISIL_appendMountOn("Base.TorchSilencer", marzNonShotguns)
    ISIL_appendMountOn("Base.WaterBottleSilencer", marzNonShotguns)
    ISIL_appendMountOn("Base.PotatoSilencer", marzNonShotguns)

    ISIL_addMarzModels(marzWeapons)
    print("[Improvised Silencers] Added Guns of Marz compatibility for " .. #marzWeapons
        .. " weapons (including " .. marzShotgunsAdded .. " separately detected shotguns and "
        .. marzFallbackAdded .. " direct-muzzle fallback weapons).")
end
