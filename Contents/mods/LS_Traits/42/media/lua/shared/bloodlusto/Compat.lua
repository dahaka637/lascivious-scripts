local Compat = {}

local cachedTraits = nil

local function getTraitByResource(resource)
    if not resource or not CharacterTrait or not CharacterTrait.get or not ResourceLocation then
        return nil
    end

    local ok, trait = pcall(function()
        return CharacterTrait.get(ResourceLocation.of(resource))
    end)

    if ok then
        return trait
    end

    return nil
end

local function getTraits()
    cachedTraits = cachedTraits or {}

    cachedTraits.bloodlustOverwhelming = cachedTraits.bloodlustOverwhelming or getTraitByResource("bloodlusto:bloodlusto")
    cachedTraits.etwBloodlust = cachedTraits.etwBloodlust or getTraitByResource("ETW:Bloodlust")
    cachedTraits.regretNothing = cachedTraits.regretNothing or getTraitByResource("RegretNothing:RegretNothing")
    cachedTraits.pacifist = cachedTraits.pacifist or (CharacterTrait and CharacterTrait.PACIFIST or nil)
    cachedTraits.hemophobic = cachedTraits.hemophobic or (CharacterTrait and CharacterTrait.HEMOPHOBIC or nil)

    return cachedTraits
end

local function hasTrait(player, trait)
    if player == nil or trait == nil then
        return false
    end

    local ok, result = pcall(function()
        return player:hasTrait(trait)
    end)

    return ok and result == true
end

function Compat.getBloodlustOverwhelmingTrait()
    return getTraits().bloodlustOverwhelming
end

function Compat.getETWBloodlustTrait()
    return getTraits().etwBloodlust
end

function Compat.getRegretNothingTrait()
    return getTraits().regretNothing
end

function Compat.getPacifistTrait()
    return getTraits().pacifist
end

function Compat.getHemophobicTrait()
    return getTraits().hemophobic
end

function Compat.hasBloodlustOverwhelming(player)
    return hasTrait(player, getTraits().bloodlustOverwhelming)
end

function Compat.hasBlockingBloodlustTrait(player)
    local traits = getTraits()
    return hasTrait(player, traits.etwBloodlust)
        or hasTrait(player, traits.regretNothing)
        or hasTrait(player, traits.pacifist)
        or hasTrait(player, traits.hemophobic)
end

function Compat.setMutualExclusive(traitA, traitB)
    if traitA ~= nil and traitB ~= nil and CharacterTraitDefinition and CharacterTraitDefinition.setMutualExclusive then
        local ok = pcall(function()
            CharacterTraitDefinition.setMutualExclusive(traitA, traitB)
        end)

        return ok == true
    end

    return false
end

return Compat
