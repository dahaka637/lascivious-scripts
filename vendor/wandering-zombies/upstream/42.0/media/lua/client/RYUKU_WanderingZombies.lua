if isServer() then return end
require("RYUKU_WanderingZombies_Zombie")

----------------------
-- On Zombie Update --
----------------------

local zombies ---@type WZLinkedList?
local function OnZombieUpdate(zombie)
    if not WZSandboxVars:isInitiated() then return end
    if zombies == nil then zombies = WZLinkedList:new("zombies") end
    if isClient() and zombie:isRemoteZombie() then return end

    -- Bandits mod compatibility
    if zombie:getVariableBoolean("Bandit") then return end

    -- FIXME: WZZombie should probably be pooled
    if zombie:getModData().wz == nil then
        zombies:push(WZZombie:new(zombie))
    end
end

Events.OnZombieUpdate.Add(OnZombieUpdate)

-------------
-- On Tick --
-------------

local link ---@type WZLinkedListLink
local processedCount ---@type integer
local processLimit ---@type integer
local wzZombie ---@type WZZombie
local hordeZombie ---@type WZZombie?
local hordeLink ---@type WZLinkedListLink?
local hordeCurrentLink ---@type WZLinkedListLink?
local hordeDistance
local hordeGroupSpeed
local hordeSize
local hordeMerge
local hordeLimit
local hasTargetAction

local function clearHordeZombie()
    hordeZombie = nil
    hordeLink = nil
    hordeCurrentLink = nil
end

local function nextHordeZombie()
    if hordeCurrentLink ~= nil then
        hordeLink = hordeCurrentLink:getNext()
        hordeCurrentLink = hordeLink
        hordeZombie = hordeLink:getRef() --[[@as WZZombie]]
        if not hordeZombie:isInit() then clearHordeZombie() end
    end
end

local debugDelay = 0
local function WZTick()
    if zombies == nil then return end

    -- when the process limit is at the default of 4, it scales
    -- it increases based on the number of zombies, up to 480 zombies, where it maxes out at 8
    -- when the zombie count exceeds 960, it scales down from 8, to help with performance
    -- when the zombie count is below 240, it decreases
    processedCount = 0
    local pLimit = WZSandboxVars:get(WZ_PERFORMANCE, "ZombieProcessLimit") --[[@as integer]]
    if pLimit == 4 then
        local mod = zombies:size() / 240
        if zombies:size() > 240 then
            pLimit = pLimit + math.min(4, mod)
            if zombies:size() > 960 then pLimit = math.max(1, pLimit * (960 / zombies:size())) end
        elseif zombies:size() < 240 then pLimit = pLimit * mod end

        processLimit = math.fmod(processLimit or 0, 1) + pLimit
    else
        processLimit = pLimit
    end


    if getTimeInMillis() > debugDelay then
        print("zombies: " .. tostring(zombies:size()) .. " / " .. tostring(WZSandboxVars:getHordeCount()) .. " / " .. tostring(processLimit))
        debugDelay = getTimeInMillis() + 5000
    end

    while processedCount < processLimit and processedCount < zombies:size() do
        link = zombies:next()
        processedCount = processedCount + 1

        wzZombie = link:getRef() --[[@as WZZombie]]
        if wzZombie:update() == nil then
            zombies:remove(link)
            if wzZombie == hordeZombie then clearHordeZombie() end
        elseif hordeZombie == nil
            and wzZombie:isInit()
            and WZSandboxVars:isSpeedAllowed(wzZombie:getSpeed())
        then
            hordeZombie = wzZombie
            hordeLink = link
        end
    end

    -- only continue if zombie is valid, hordes are enabled and the desired world age has been reached
    if hordeZombie == nil or hordeLink == nil then return end
    if not WZSandboxVars:get(WZ_HORDE, "Hordes") or
        getGameTime():getWorldAgeHours() < WZSandboxVars:get(WZ_HORDE, "WorldAgeHours") or
        not hordeZombie:isValid()
    then
        clearHordeZombie()
        return
    end

    if hordeCurrentLink == nil then hordeCurrentLink = hordeLink end

    processedCount = 0
    hordeDistance = WZSandboxVars:get(WZ_HORDE, "CreateJoinMergeDistance") --[[@as integer]]
    hordeGroupSpeed = WZSandboxVars:get(WZ_HORDE, "GroupBySpeed") --[[@as boolean]]
    hordeSize = WZSandboxVars:get(WZ_HORDE, "HordeSize") --[[@as integer]]
    hordeMerge = WZSandboxVars:get(WZ_HORDE, "HordesMerge") --[[@as boolean]]
    hordeLimit = WZSandboxVars:get(WZ_HORDE, "HordeLimit") --[[@as integer]]
    hasTargetAction = WZSandboxVars:get(WZ_HORDE, "HasTargetAction") --[[@as integer]]

    local pos
    local hordePos = hordeZombie:getPosition()
    while processedCount < processLimit and processedCount < zombies:size() do
        -- horde size reached
        if not hordeMerge and hordeSize > 0 and hordeZombie:getHordeSize() >= hordeSize then
            nextHordeZombie()
            break
        end

        hordeCurrentLink = hordeCurrentLink:getNext()
        -- processed all zombies
        if hordeCurrentLink == hordeLink then
            nextHordeZombie()
            break
        end

        wzZombie = hordeCurrentLink:getRef() --[[@as WZZombie]]
        processedCount = processedCount + 1
        if not wzZombie:isInit() or not wzZombie:isValid() then break end
        pos = wzZombie:getPosition()

        -- target zombie must:
        --      share the same z position as the searching zombie
        --      be within the Create/Join/Merge Distance
        --      have the same value for Outside
        --      not have a target if Has Target Action is set to Leave Horde
        --      have a speed that is allowed to be in hordes
        --      if grouping by speed is enabled, have same speed as searching zombie
        if pos.z == hordePos.z
            and hordePos:distanceTo(pos) <= hordeDistance
            and hordeZombie:isOutside() == wzZombie:isOutside()
            and (hasTargetAction ~= 1 or not wzZombie:hasTarget())
            and WZSandboxVars:isSpeedAllowed(wzZombie:getSpeed())
            and (not hordeGroupSpeed or wzZombie:getSpeed() == hordeZombie:getSpeed())
        then
            if wzZombie:isInHorde() then
                if not hordeZombie:isInHorde() then
                    -- join existing horde
                    if hordeMerge or hordeSize == 0 or wzZombie:getHordeSize() < hordeSize then
                        wzZombie:addFollower(hordeZombie)
                        nextHordeZombie()
                        break
                    end
                elseif hordeMerge then
                    local smaller = wzZombie
                    local larger = hordeZombie
                    if hordeZombie:getHordeSize() < wzZombie:getHordeSize() then
                        smaller = hordeZombie
                        larger = wzZombie
                    end

                    if smaller:mergeHordeWith(larger) then
                        nextHordeZombie()
                        break
                    end
                end
            elseif hordeZombie:isInHorde() or hordeLimit == 0 or WZSandboxVars:getHordeCount() < hordeLimit then
                hordeZombie:addFollower(wzZombie)
            end
        end
    end
end

Events.OnTick.Add(WZTick)
