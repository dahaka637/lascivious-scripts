local modelTable = require "ISIL_ModelTable"

local modelParts = {
    [0] = {
        "ModelWeaponPart = Base.Silencer Base.SilencerRifle muzzle muzzle",
        "ModelWeaponPart = Base.MetalPipeSilencer Base.MetalPipeSilencer muzzle muzzle",
        "ModelWeaponPart = Base.TorchSilencer Base.TorchSilencer muzzle muzzle",
        "ModelWeaponPart = Base.WaterBottleSilencer Base.WaterBottleSilencer muzzle muzzle",
        "ModelWeaponPart = Base.PotatoSilencer Base.PotatoSilencer muzzle muzzle",
    },
    [1] = {
        "ModelWeaponPart = Base.Silencer Base.SilencerRifle muzzle muzzle",
        "ModelWeaponPart = Base.MetalPipeSilencer Base.MetalPipeSilencerRifle muzzle muzzle",
    },
    [2] = {
        "ModelWeaponPart = Base.Silencer Base.SilencerRifle muzzle muzzle",
        "ModelWeaponPart = Base.MetalPipeSilencer Base.MetalPipeSilencerRifle muzzle muzzle",
        "ModelWeaponPart = Base.TorchSilencer Base.TorchSilencerRifle muzzle muzzle",
        "ModelWeaponPart = Base.WaterBottleSilencer Base.WaterBottleSilencerRifle muzzle muzzle",
        "ModelWeaponPart = Base.PotatoSilencer Base.PotatoSilencerRifle muzzle muzzle",
    },
}

for weaponFullType, modelFamily in pairs(modelTable) do
    local scriptItem = ScriptManager.instance:getItem(weaponFullType)
    if scriptItem then
        for _, parameter in ipairs(modelParts[modelFamily]) do
            scriptItem:DoParam(parameter)
        end
    end
end
