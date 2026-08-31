
require "MF_ISMoodle"

MF.createMoodle('BloodlustO_KillCraving');
MF.createMoodle('BloodlustO_Bloodlust');
MF.createMoodle('BloodlustO_PreFrenzy');
MF.createMoodle('BloodlustO_BloodyFrenzy');
MF.createMoodle('BloodlustO_BufferedExertion');
MF.createMoodle('BloodlustO_FrenzyBacklash');
MF.createMoodle('BloodlustO_FightlessCombat');
MF.createMoodle('BloodlustO_Bloodiness');



local Utils = {}

local MoodleLevel = {
    ["-4"] = 0.1, -- bad4
    ["-3"] = 0.2, -- bad3
    ["-2"] = 0.3, -- bad2
    ["-1"] = 0.4, -- bad1
    ["0"] = 0.5,
    ["1"] = 0.6, -- good1
    ["2"] = 0.7, -- good2
    ["3"] = 0.8, -- good3
    ["4"] = 0.9, -- good4
}


--- @class MoodleOptions
--- @field wiggle boolean
--- @field desc string

--- @param player IsoPlayer
--- @param key string
--- @param level number
--- @param options MoodleOptions
function Utils.updateMoodle(player, key, level, options)
    if player ~= getPlayer() then return end

    local moodle = MF.getMoodle('BloodlustO_'..key, player:getPlayerNum())
    if not moodle then return end

    local flevel = MoodleLevel[tostring(level)]
    moodle:setValue(flevel)

    if options and options.wiggle then
        moodle:doWiggle()
    end

    if level ~= 0 then
        local badgood = level > 0 and 'Good' or 'Bad'
        local desc = getText('Moodles_BloodlustO_'..key..'_'..badgood..'_desc_lvl'..tostring(math.abs(level)))
        if options and options.add_to_tooltip then
            desc = desc..'\n'..options.add_to_tooltip
        end
        moodle:setDescription(moodle:getGoodBadNeutral(), level, desc)
    end
end
--- @param player IsoPlayer
--- @param key string
function Utils.wiggleMoodle(player, key)
    local moodle = MF.getMoodle('BloodlustO_'..key, player:getPlayerNum())
    if not moodle then return end
    moodle:doWiggle()
end

function Utils.getMinuteValueIncrease(elapsed, total, curve)
    elapsed = math.min(elapsed, total)
    local prev_progress = (elapsed - 1) / total
    local curr_progress = elapsed / total
    return (curr_progress ^ curve) - (prev_progress ^ curve)
end

--- @param player IsoPlayer
--- @return BloodlustModData
function Utils.getModData(player)
    local player_data = player:getModData()
    player_data.BloodlustO = player_data.BloodlustO or {
        bloodlust = 0,
        frenzy_progress = 0,
        buffered_exertion = 0,
        last_kill_at = getGametimeTimestamp(),
        last_hit_at = getGametimeTimestamp(),
        bloodiness = {}
    }
    return player_data.BloodlustO
end

function Utils.getVariant(type, default)
    local variants = Utils.getVariants(type, default)
    return variants[ZombRand(#variants) + 1]
end
function Utils.getVariants(type, default)
    local variants = {}
    local keyType = tostring(type):gsub("[^%w_]", "_")
    for i = 1, 99 do
        local key = 'UI_BloodlustO_'..keyType..'_'..tostring(i)
        local variant = getText(key)
        if not variant or variant == key then break end
        table.insert(variants, variant)
    end
    return #variants > 0 and variants or { default }
end


--- @param o1 IsoMovingObject
--- @param o2 IsoMovingObject
function Utils.getDistanceSq(o1, o2)
    local floor_distance = (o1:getZ() - o2:getZ()) * 3
    return o1:getDistanceSq(o2) + (floor_distance * floor_distance)
end
--- @param o1 IsoMovingObject
--- @param o2 IsoMovingObject
function Utils.getDistanceInTiles(o1, o2)
    return math.sqrt(Utils.getDistanceSq(o1, o2))
end

--region Temporal Experience

--- @param perk PerkFactory.Perk
--- @param total_xp number
local function getLevelFromTotalXP(perk, total_xp)
    local current_level = 1
    while current_level <= 10 do
        if total_xp < perk:getTotalXpForLevel(current_level) then
            return current_level - 1
        end
        current_level = current_level + 1
    end
    return 10
end

--- @param perk PerkFactory.Perk
--- @param current_xp number
--- @param levels number float
local function calcXpForLevels(perk, current_xp, levels, max_level)
    local total_xp_to_add = 0
    while levels > 0 do
        local level = getLevelFromTotalXP(perk, current_xp)
        if level >= max_level then return total_xp_to_add end

        local xp_for_next_level = perk:getXpForLevel(level+1)
        local xp_to_level_up = perk:getTotalXpForLevel(level+1) - current_xp

        local progress_left = xp_to_level_up / xp_for_next_level
        local progress_to_add = math.min(
                levels, -- how much we can add
                progress_left -- progress left
        )
        if progress_to_add <= 0 then return math.ceil(total_xp_to_add) end

        local xp_to_add = xp_for_next_level * progress_to_add

        current_xp = current_xp + xp_to_add
        total_xp_to_add = total_xp_to_add + xp_to_add
        levels = levels - progress_to_add
    end
    return math.ceil(total_xp_to_add)
end

--- @param player IsoPlayer
--- @param perk PerkFactory.Perk
--- @param levels number
function Utils.addTemporalLevels(player, data, perk, levels, max_level)
    local key = "temp_xp_added:"..tostring(perk)

    local xp = player:getXp()
    local current_xp = xp:getXP(perk) - (data[key] or 0)
    local target_xp_to_add = calcXpForLevels(perk, current_xp, levels, max_level)
    local new_xp = current_xp + target_xp_to_add

    local level = getLevelFromTotalXP(perk, new_xp)
    if player:getPerkLevel(perk) ~= level then
        -- Note: This workaround exists to bypass level up notification
        xp:setXPToLevel(perk, level)
        player:setPerkLevelDebug(perk, level)
        if level < 10 then
            local over_level = new_xp - perk:getTotalXpForLevel(level)
            xp:AddXP(perk, over_level, false, false, false, false)
        end
        data[key] = target_xp_to_add
    end
end

--- @param player IsoPlayer
--- @param perk PerkFactory.Perk
function Utils.removeTemporalLevels(player, data, perk)
    local key = "temp_xp_added:"..tostring(perk)
    if data[key] then
        local xp = player:getXp()
        xp:AddXP(perk, -data[key], false, false, false, false)
        Utils.log("Removed all added "..tostring(perk).." xp: "..tostring(data[key]))
        data[key] = nil
    end
end

--endregion

function Utils.log(message)
    print("[BloodlustO] "..tostring(message))
end

return Utils
