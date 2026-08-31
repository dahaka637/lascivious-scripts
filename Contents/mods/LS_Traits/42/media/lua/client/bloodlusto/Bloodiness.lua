
local SB = require('bloodlusto/Sandbox')


---@class BloodinessTracker
---@field fresh number fresh blood amount
---@field last number last blood amount that was updated
---@field last_at number

---@class BloodinessValues
---@field total number
---@field total_fresh number
---@field total_freshness number
---@field overall number
---@field overall_freshness number



local Bloodiness = {};


---@param data table
---@param key string
---@param bloodiness number
---@return BloodinessTracker
local function getBloodinessTracker(data, key, bloodiness)
    data[key] = data[key] or {}
    data = data[key]

    local at = getGametimeTimestamp()

    data.fresh = data.fresh or bloodiness
    data.last = data.last or bloodiness
    data.last_at = data.last_at or at

    return data
end

---@param data BloodinessTracker
---@param bloodiness number
---@param decay_rate number
local function updateBloodinessTracker(data, bloodiness, decay_rate)
    local at = getGametimeTimestamp()

    if bloodiness > data.last then
        data.fresh = math.clamp(data.fresh + (bloodiness - data.last), 0, bloodiness)
    elseif bloodiness < data.last then
        data.fresh = math.clamp(data.fresh - (data.last - bloodiness), 0, bloodiness)
    elseif data.last_at ~= at then
        local minutes_passed = (at - data.last_at) / 60
        data.fresh = math.clamp(data.fresh - (minutes_passed * decay_rate), 0, bloodiness)
    end

    data.last = bloodiness
    data.last_at = at
    return data.fresh
end

--- @param player IsoPlayer
--- @return BloodinessValues
function Bloodiness.get(player)
    local player_data = player:getModData()
    player_data['BloodlustO:Bloodiness'] = player_data['BloodlustO:Bloodiness'] or {}

    -- Bloodiness --
    local bloodiness = {}
    local all_fresh_bloodiness = {}

    -- Body
    local body_visual = player:getHumanVisual()
    for i=0, BloodBodyPartType.MAX:index()-1 do
        local part = BloodBodyPartType.FromIndex(i)
        local part_bloodiness = body_visual:getBlood(part)
        bloodiness[tostring(part)] = part_bloodiness
        table.insert(all_fresh_bloodiness, {
            data = getBloodinessTracker(player_data['BloodlustO:Bloodiness'], tostring(part), part_bloodiness),
            bloodiness = part_bloodiness,
            multiplier = 1,
            parts = { tostring(part) }
        })
    end

    -- Clothing
    local worn_items = player:getWornItems()
    for i=0, worn_items:size() - 1 do
        local item = worn_items:get(i):getItem()
        if item:IsClothing() then
            local covers = item:getCoveredParts()
            if covers:size() ~= 0 then
                local item_bloodiness = item:getBloodLevel() * 0.01
                local parts = {}
                for i=0, covers:size()-1 do
                    local part = tostring(covers:get(i))
                    bloodiness[part] = bloodiness[part] + item_bloodiness
                    table.insert(parts, part)
                end
                table.insert(all_fresh_bloodiness, {
                    data = getBloodinessTracker(item:getModData(), 'BloodlustO:Bloodiness', item_bloodiness),
                    bloodiness = item_bloodiness,
                    multiplier = (1 / covers:size()),
                    parts = parts
                })
            end
        end
    end

    -- Weapon
    local held_item = player:getPrimaryHandItem()
    if held_item ~= nil and held_item:IsWeapon() then
        bloodiness['Weapon'] = held_item:getBloodLevel()
        table.insert(all_fresh_bloodiness, {
            data = getBloodinessTracker(held_item:getModData(), 'BloodlustO:Bloodiness', bloodiness['Weapon']),
            bloodiness = bloodiness['Weapon'],
            multiplier = 0.5,
            parts = { 'Weapon' }
        })
    else
        bloodiness['Weapon'] = 0
    end

    -- Overall
    local total = 0
    local total_uncapped = 0
    local count = 0
    for part, part_bloodiness in pairs(bloodiness) do
        total = total + math.min(part_bloodiness, 1)
        total_uncapped = total_uncapped + part_bloodiness
        count = count + 1
    end
    local overall = total / count

    -- Fresh --
    local fresh_bloodiness = {}
    if SB.FreshBloodinessDecayMode == 1 then
        local weighted_fresh = 0
        for _, v in ipairs(all_fresh_bloodiness) do
            v.weighted = v.data.fresh * v.multiplier
            weighted_fresh = weighted_fresh + v.weighted
        end
        for _, v in ipairs(all_fresh_bloodiness) do
            local proportion = weighted_fresh > 0 and v.weighted / weighted_fresh or 0
            local decay_rate = (SB.FreshBloodinessDecayPerMinute*0.01 * v.multiplier) * proportion
            local part_fresh_bloodiness =  updateBloodinessTracker(v.data, v.bloodiness, decay_rate)
            for _, part in ipairs(v.parts) do
                if fresh_bloodiness[part] then
                    fresh_bloodiness[part] = fresh_bloodiness[part] + part_fresh_bloodiness
                else
                    fresh_bloodiness[part] = part_fresh_bloodiness
                end
            end
        end
    else
        for _, v in ipairs(all_fresh_bloodiness) do
            local decay_rate = SB.FreshBloodinessDecayPerMinute*0.01 * v.multiplier
            local part_fresh_bloodiness =  updateBloodinessTracker(v.data, v.bloodiness, decay_rate)
            for _, part in ipairs(v.parts) do
                if fresh_bloodiness[part] then
                    fresh_bloodiness[part] = fresh_bloodiness[part] + part_fresh_bloodiness
                else
                    fresh_bloodiness[part] = part_fresh_bloodiness
                end
            end
        end
    end
    local total_fresh = 0
    local total_fresh_uncapped = 0
    for part, part_bloodiness in pairs(fresh_bloodiness) do
        total_fresh = total_fresh + math.min(part_bloodiness, 1)
        total_fresh_uncapped = total_fresh_uncapped + part_bloodiness
    end
    local overall_fresh = total_fresh / count

    -- Result
    return {
        total = total_uncapped,
        total_fresh = total_fresh_uncapped,
        total_freshness = total_fresh_uncapped > 0 and total_fresh_uncapped / total_uncapped or 0,
        overall = overall,
        overall_freshness = overall_fresh > 0 and overall_fresh / overall or 0,
    }
end


-- NOTE: Clothing that is taken off is forgotten, so this doesn't really work for bloodiness decrease tracking
local prev_bloodiness = {}
--- @param player IsoPlayer
function Bloodiness.getChange(player)
    local current = {}

    -- Body
    local body_visual = player:getHumanVisual()
    for i=0, BloodBodyPartType.MAX:index()-1 do
        local part = BloodBodyPartType.FromIndex(i)
        current[tostring(part)] = body_visual:getBlood(part)
    end

    -- Clothing
    local worn_items = player:getWornItems()
    for i=0, worn_items:size() - 1 do
        local item = worn_items:get(i):getItem()
        if item:IsClothing() then
            local covers = item:getCoveredParts():size()
            if covers ~= 0 then
                local part_blood = item:getBloodLevel() * 0.01
                current[tostring(item)] = part_blood * (1 + ((covers - 1) * 0.5)) -- +50% for each part covered
            end
        end
    end

    -- Weapon
    local held_item = player:getPrimaryHandItem()
    if held_item ~= nil and held_item:IsWeapon() then
        current['primary_weapon'] = held_item:getBloodLevel()
    end

    local change = 0
    for k, v in pairs(current) do
        local prev = prev_bloodiness[k]
        if prev then
            change = change + (v - prev)
        end
    end
    prev_bloodiness = current
    return change * 100
end


return Bloodiness
