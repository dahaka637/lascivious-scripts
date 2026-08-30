if isServer() then return end
require("PZAPI/ModOptions")
require("RYUKU_WanderingZombies_Director")

-------------------
-- Process Limit --
-------------------

-- TODO: add ModOptions to meta files
---@class ProcessLimit
---@field getValue fun(): integer

local perfOptions = PZAPI.ModOptions:create("WanderingZombiesPMO", "Wandering Zombies")
local perfProcessLimit = perfOptions:addSlider(
    "WZProcessLimit",
    getText("Sandbox_WZPerformance_ZombieProcessLimit"),
    1,
    20,
    1,
    4,
    "Sandbox_WZPerformance_ZombieProcessLimit_tooltip"
) --[[@as ProcessLimit]]

----------------------
-- On Zombie Update --
----------------------

local zombies ---@type WZLinkedList?
local trackedZombies = setmetatable({}, { __mode = "k" })
local gameTime
local function OnZombieUpdate(zombie)
    if not WZSandboxVars:isInitiated() then return end
    if zombies == nil then
        zombies = WZLinkedList:new("zombies")
        gameTime = getGameTime()
    end

    if isClient() and zombie:isRemoteZombie() then return end
    if zombie:isSitAgainstWall() then return end

    -- Bandits mod compatibility
    if zombie:getVariableBoolean("Bandit") then return end

    -- Keep tracking state client-local. IsoZombie modData persists with the save,
    -- while these wrappers do not, so modData cannot safely be used as the guard.
    if trackedZombies[zombie] == nil then
        local wzZombie = WZZombie:new(zombie)
        trackedZombies[zombie] = wzZombie
        zombies:push(wzZombie)
    end
end

Events.OnZombieUpdate.Add(OnZombieUpdate)

-------------
-- On Tick --
-------------


local updateDelta ---@type number
local frameCutoff = 1 / 50
local processLimitDelta = 0 ---@type number
local processLimit ---@type integer
local processedCount ---@type integer

local link ---@type WZLinkedListLink
local wzZombie ---@type WZZombie
local hordeZombie ---@type WZZombie?
local hordeLink ---@type WZLinkedListLink?
local hordeCurrentLink ---@type WZLinkedListLink?
local hordeDistance
local hordeGroupSpeed
local hordeSize
local hordeMerge
local hordeLimit
local chebyshevDistance

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

local function WZTick()
    if zombies == nil then
        WZSandboxVars:setZombieCount(0)
        return
    end

    WZSandboxVars:setZombieCount(zombies:size())
    WZDirector:update(zombies:size())

    -- scale to one zombie update per second
    -- limited by:
    --   <50 fps: <= scale down from 1 zombie per frame
    --   ZombieProcessLimit is absolute max per frame
    processedCount = 0
    updateDelta = gameTime:getRealworldSecondsSinceLastUpdate()
    processLimitDelta = processLimitDelta + math.min(
        zombies:size() * updateDelta,
        (updateDelta > frameCutoff and (frameCutoff / updateDelta)) or perfProcessLimit:getValue()
    )

    processLimit = math.floor(processLimitDelta)
    processLimitDelta = processLimitDelta - processLimit

    processedCount = 0
    while processedCount < processLimit and processedCount < zombies:size() do
        link = zombies:next()
        processedCount = processedCount + 1

        wzZombie = link:getRef() --[[@as WZZombie]]
        local isoZombie = wzZombie._ref
        if wzZombie:update() == nil then
            trackedZombies[isoZombie] = nil
            zombies:remove(link)
            if wzZombie == hordeZombie then clearHordeZombie() end
        elseif hordeZombie == nil
            and wzZombie:isInit()
            and wzZombie:isOutside()
            and WZSandboxVars:isSpeedAllowed(wzZombie:getSpeed())
            and wzZombie:isValidHordeZombie()
        then
            hordeZombie = wzZombie
            hordeLink = link
        end
    end

    -- only continue if zombie is valid, hordes are enabled and the desired world age has been reached
    if hordeZombie == nil or hordeLink == nil then return end
    if not WZSandboxVars:get(WZ_HORDE, "Hordes")
        or getGameTime():getWorldAgeHours() < WZSandboxVars:get(WZ_HORDE, "WorldAgeHours")
        or not hordeZombie:isValid()
        or not hordeZombie:isOutside()
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
    chebyshevDistance = WZSandboxVars:get(WZ_SHARED, "ChebyshevDistance") --[[@as boolean]]

    local pos, speed
    local hordePos = hordeZombie:getPosition()
    local hordeSpeed = hordeZombie:getSpeed()
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
        if not wzZombie:isInit()
            or not wzZombie:isValid()
            or not wzZombie:isValidHordeZombie()
        then
            break
        end

        pos = wzZombie:getPosition()
        speed = wzZombie:getSpeed()

        -- target zombie must:
        --      share the same z position as the searching zombie NOTE: cached
        --      speed is allowed
        --      if grouping by speed is enabled, have same speed as searching zombie
        --      have the same value for Outside NOTE: cached
        --      be within the Create/Join/Merge Distance
        if pos.z == hordePos.z
            and wzZombie:isOutside()
            and WZSandboxVars:isSpeedAllowed(speed)
            and (not hordeGroupSpeed or speed == hordeSpeed)
            and ((chebyshevDistance and hordePos:chebyshevTo(pos)) or hordePos:distanceTo(pos)) <= hordeDistance
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
