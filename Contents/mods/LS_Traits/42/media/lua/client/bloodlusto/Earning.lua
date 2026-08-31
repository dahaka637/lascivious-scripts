local BloodlustTrait = require("bloodlusto/Registries").traits.Bloodlust
local Bloodiness = require('bloodlusto/Bloodiness')
local Compat = require('bloodlusto/Compat')
local Utils = require('bloodlusto/Utils')
local GrantedTraitDependencies = require("LS_Traits_GrantedTraitDependencies")


local SB = require('bloodlusto/Sandbox')



local Earning = BloodlustO_Earning or {}
BloodlustO_Earning = Earning

local function isLocalPlayer(player)
    if player == nil then
        return false
    end

    local ok, result = pcall(function()
        return player:isLocalPlayer()
    end)

    if ok then
        return result == true
    end

    return player == getPlayer()
end


--- @param zombie IsoZombie
function Earning.onZombieKill(zombie)
    if not SB.EarnIt then return end

    local player = zombie:getAttackedBy()
    if not instanceof(player, "IsoPlayer") then return end
    if not isLocalPlayer(player) then return end
    if player:hasTrait(BloodlustTrait) then return end
    if Compat.hasBlockingBloodlustTrait(player) then return end

    local data = Earning.getData(player)
    local bloodiness = Bloodiness.get(player)

    if bloodiness.overall < SB.BloodinessForBloodyKills/100 then return end
    data.bloody_kills = (data.bloody_kills or 0) + 1

    if data.bloody_kills >= SB.BloodyKillsToEarn then
        Earning.earn(player)
    end
end
Events.OnZombieDead.Add(Earning.onZombieKill)


function Earning.onEveryHour()
    if not SB.EarnIt then return end

    local player = getPlayer()
    if not player then return end
    if player:hasTrait(BloodlustTrait) then return end
    if Compat.hasBlockingBloodlustTrait(player) then return end
    if not SB.BloodyKillsDecayInSleep and player:isAsleep() then return end

    local data = Earning.getData(player)
    if not data.bloody_kills then return end

    local bloodiness = Bloodiness.get(player)
    if bloodiness.overall >= SB.BloodyKillsDecayBelowBloodiness/100 then return end

    data.bloody_kills = data.bloody_kills - SB.BloodyKillsDecayPerHour
    if data.bloody_kills <= 0 then
        data.bloody_kills = nil
    end
end
Events.EveryHours.Add(Earning.onEveryHour)


function Earning.earn(player)
    player:getCharacterTraits():add(BloodlustTrait)
    GrantedTraitDependencies.ensure(player, "BloodlustEarning")
    player:getModData()['BloodlustO:Earning'] = nil

    if SB.SendIntoFrenzyOnceEarned then
        local data = Utils.getModData(player)
        data.bloodlust = 100
        data.frenzy_progress = SB.BloodlustOverreducedForFrenzy
    end

    player:addLineChatElement(Utils.getVariant("frenzy:instakill", "HAHAHAHAHA"), 1, 0, 0)
    addSound(player, player:getX(), player:getY(), player:getZ(), SB.InstakillSoundRadiusInFrenzy, 1.0)
end

function Earning.getData(player)
    local data = player:getModData()
    data['BloodlustO:Earning'] = data['BloodlustO:Earning'] or {}
    return data['BloodlustO:Earning']
end
