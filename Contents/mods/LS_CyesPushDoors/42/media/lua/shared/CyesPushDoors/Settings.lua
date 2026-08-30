require "CyesPushDoors/Config"

CyesPushDoors = CyesPushDoors or {}
CyesPushDoors.Settings = CyesPushDoors.Settings or {}

local S = CyesPushDoors.Settings

S.ClientImpactFeedback = true

local function boolValue(value, default)
    if value == nil then return default end
    return value == true
end

local function numberValue(value, default, minValue, maxValue)
    local n = tonumber(value)
    if n == nil then n = default end
    if minValue ~= nil and n < minValue then n = minValue end
    if maxValue ~= nil and n > maxValue then n = maxValue end
    return n
end

function S.isNetworkClient()
    return isClient and isClient() == true
end

function S.isNetworkServer()
    return isServer and isServer() == true
end

function S.getSandbox()
    if SandboxVars and SandboxVars.CyesPushDoors then
        return SandboxVars.CyesPushDoors
    end
    return {}
end

function S.hideIndividualOptions()
    if not S.isNetworkClient() then return false end
    return boolValue(S.getSandbox().HideIndividualOptions, false)
end

function S.globalImpactFeedback()
    return boolValue(S.getSandbox().GlobalImpactFeedback, true)
end

function S.setClientImpactFeedback(value)
    S.ClientImpactFeedback = value ~= false
end

function S.isLocalServerOwner()
    if not S.isNetworkClient() then
        return S.isNetworkServer()
    end

    if isCoopHost then
        local ok, value = pcall(isCoopHost)
        if ok then return value == true end
    end

    return false
end

function S.impactFeedbackEnabled()
    if S.isNetworkClient() and S.hideIndividualOptions() then
        return S.globalImpactFeedback()
    end
    if S.isNetworkServer() then
        local sandbox = S.getSandbox()
        if boolValue(sandbox.HideIndividualOptions, false) then
            return boolValue(sandbox.GlobalImpactFeedback, true)
        end
        return true
    end
    return S.ClientImpactFeedback ~= false
end

function S.zombieDamageMultiplier()
    return numberValue(S.getSandbox().ZombieDamageMultiplier, 1.0, 0.0, 2.0)
end

function S.zombiesAffectedMultiplier()
    return numberValue(S.getSandbox().ZombiesAffectedMultiplier, 1.0, 0.25, 2.0)
end

function S.zombieKnockdownChance()
    return numberValue(S.getSandbox().ZombieKnockdownChance, 35, 0, 100) / 100
end

function S.doorWearMultiplier()
    return numberValue(S.getSandbox().DoorWearMultiplier, 1.0, 0.0, 3.0)
end

function S.garageDoorWearMultiplier()
    return numberValue(S.getSandbox().GarageDoorWearMultiplier, 1.0, 0.25, 3.0)
end

function S.garageFailureChanceMultiplier()
    return numberValue(S.getSandbox().GarageFailureChanceMultiplier, 1.0, 0.0, 3.0)
end

function S.armStrainGainMultiplier()
    return numberValue(S.getSandbox().ArmStrainGainMultiplier, 1.0, 0.0, 3.0)
end

function S.armStrainUsageLimitMultiplier()
    return numberValue(S.getSandbox().ArmStrainUsageLimitMultiplier, 1.0, 0.25, 5.0)
end

function S.garageArmStrainMultiplier()
    return numberValue(S.getSandbox().GarageArmStrainMultiplier, 1.0, 0.25, 3.0)
end

function S.armStrainPenaltyMultiplier()
    return numberValue(S.getSandbox().ArmStrainPenaltyMultiplier, 1.0, 0.0, 2.0)
end

function S.armStrainRecoveryMultiplier()
    return numberValue(S.getSandbox().ArmStrainRecoveryMultiplier, 1.0, 0.25, 3.0)
end

function S.damagePlayers()
    return boolValue(S.getSandbox().DamagePlayers, true)
end

function S.knockDownPlayers()
    return boolValue(S.getSandbox().KnockDownPlayers, true)
end

function S.playerKnockdownChance()
    return numberValue(S.getSandbox().PlayerKnockdownChance, 25, 0, 100) / 100
end

function S.affectCrawlers()
    return boolValue(S.getSandbox().AffectCrawlers, true)
end

return CyesPushDoors.Settings
