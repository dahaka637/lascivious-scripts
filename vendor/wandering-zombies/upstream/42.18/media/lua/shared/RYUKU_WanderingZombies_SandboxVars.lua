require("RYUKU_Utility_RNG")
require("RYUKU_WanderingZombies_Time")

WZ_LONE = 1
WZ_HORDE = 2
WZ_SHARED = 3
WZ_DIRECTOR = 4
WZ_SANDBOX_VERSION = 1

local groupKeys = {
    "WZLoneZombie",
    "WZHordeZombie",
    "WZShared",
    "WZDirector",
}

local sandboxVars =
{
    [WZ_LONE] = {},
    [WZ_HORDE] = {},
    [WZ_SHARED] = {},
    [WZ_PERFORMANCE] = {},
    [WZ_DIRECTOR] = {},
}

local STAMP_HOUR = 60 * 60

local moveTypes = { "Flee", "Homing", "Wander" }

-------------------
-- WZSandboxVars --
-------------------

---@class WZSandboxVars
---@field private _init boolean
---@field private _updateCooldown integer
---@field private _zombieCount integer
---@field private _hordeCount integer
WZSandboxVars =
{
    _init = false,
    _updateCooldown = 0,
    _zombieCount = 0,
    _hordeCount = 0
}

---@return boolean
function WZSandboxVars:isInitiated()
    return self._init
end

------------------
-- Zombie Count --
------------------

---@return integer
function WZSandboxVars:getZombieCount()
    return self._zombieCount
end

---@param count integer
function WZSandboxVars:setZombieCount(count)
    self._zombieCount = count
end

-----------------
-- Horde Count --
-----------------

---@return integer
function WZSandboxVars:getHordeCount()
    return self._hordeCount
end

---@param delta integer
function WZSandboxVars:updateHordeCount(delta)
    self._hordeCount = math.max(0, self._hordeCount + delta)
end

---------------
-- Get Value --
---------------

---@param idx integer
---@param name string
---@return any
function WZSandboxVars:get(idx, name)
    return sandboxVars[idx].key[name]
end

---@param name string
---@param inHorde boolean?
function WZSandboxVars:getZ(name, inHorde)
    return sandboxVars[(inHorde and WZ_HORDE) or WZ_LONE].key[name]
end

----------
-- Time --
----------

---@param name string
---@param getHordeVar boolean?
---@return boolean
function WZSandboxVars:isTimeNow(name, getHordeVar)
    local time = WZTime:getTimestamp()
    local idx = (getHordeVar == true and WZ_HORDE) or WZ_LONE

    local stime = sandboxVars[idx].key[name .. "StampStart"]
    if not stime then return false end

    local etime = sandboxVars[idx].key[name .. "StampEnd"]
    if not etime then return false end

    return time >= stime and time < etime
end

---@param name string
---@param getHordeVar boolean?
---@return boolean
function WZSandboxVars:isTimeInit(name, getHordeVar)
    local idx = (getHordeVar == true and WZ_HORDE) or WZ_LONE
    return sandboxVars[idx].key[name .. "StampStart"] ~= nil and sandboxVars[idx].key[name .. "StampEnd"] ~= nil
end

---@param name string
---@param getHordeVar boolean?
---@return boolean
function WZSandboxVars:isTimeElapsed(name, getHordeVar)
    local idx = (getHordeVar and WZ_HORDE) or WZ_LONE
    local etime = sandboxVars[idx].key[name .. "StampEnd"]
    return etime == nil or WZTime:getTimestamp() >= etime
end

-----------
-- Speed --
-----------

local speedTable =
{
    [1] = "AllowSprinters",
    [2] = "AllowFastShamblers",
    [3] = "AllowShamblers",
    [4] = "",
    [5] = "AllowCrawlers"
}

---@param speed integer
---@return boolean
function WZSandboxVars:isSpeedAllowed(speed)
    return sandboxVars[WZ_HORDE].key[speedTable[speed]] == true
end

------------
-- Update --
------------

---@param idx integer
---@param name string
---@return integer
local function getPossibleRandValue(idx, name)
    local min = sandboxVars[idx].key[name .. "Min"]
    if min ~= nil then
        if sandboxVars[idx].key[name .. "Dropdown"] < 2 then return min end

        local max = sandboxVars[idx].key[name .. "Max"]
        if min == max then return min
        elseif min < max then return RYRNG:range(min, max)
        else
            if string.find(name, "StartHour") then
                max = max + 24
                local result = RYRNG:range(min, max)
                if result > 23 then return result - 24
                else return result end
            end

            return RYRNG:range(max, min)
        end
    elseif name:find("Destructive") then
        if sandboxVars[idx].key[name] < 4 then return sandboxVars[idx].key[name] end
        return RYRNG:range(1, 3)
    elseif name:find("Interrupt") then
        if sandboxVars[idx].key[name] < 3 then return sandboxVars[idx].key[name] end
        return RYRNG:range(1, 2)
    else
        print("WZSandboxVars.getPossibleRandValue: unknown - " .. tostring(name))
        return 0
    end
end

---@param groupIdx integer
---@param optionKey string
---@param value any
local function sendUpdate(groupIdx, optionKey, value)
    if isCoopHost() or isServer() then
        sendServerCommand("WanderingZombies", "WZSVUpdate", { g = groupIdx, o = optionKey, v = value })
    end
end

local cachedValue, svValue
---@param groupIdx integer
---@param optionKey string
---@return any, boolean
function WZSandboxVars:getUpdatedValue(groupIdx, optionKey)
    cachedValue = sandboxVars[groupIdx].key[optionKey]
    svValue = SandboxVars[groupKeys[groupIdx]][optionKey]
    if cachedValue ~= svValue then return svValue, true end
    return cachedValue, false
end

local modData
local startHour, totalHours, cooldownHours
local nextStamp, nextEndStamp
---@param groupIdx integer
---@param moveType string
---@param forceUpdate boolean?
function WZSandboxVars:updateStamps(groupIdx, moveType, forceUpdate)
    local randValue
    local currentStamp = WZTime:getTimestamp()
    local currentTime = WZTime:getTable()
    local nextTime = WZTime:getTable()
    if forceUpdate or self:isTimeElapsed(moveType, groupIdx == WZ_HORDE) then
        -- update start/end timestamps
        startHour = getPossibleRandValue(groupIdx, moveType .. "StartHour")
        totalHours = getPossibleRandValue(groupIdx, moveType .. "TotalHours")
        cooldownHours = getPossibleRandValue(groupIdx, moveType .. "CooldownHours")

        nextTime.hour = startHour + cooldownHours % 24
        nextTime.day = currentTime.day + math.floor(cooldownHours / 24)
        nextStamp = os.time(nextTime)
        nextEndStamp = nextStamp + totalHours * STAMP_HOUR

        -- push the period of activity to the next day when:
        --   same day
        --   start stamp is less than the current stamp
        --   end stamp is less than the current stamp
        --   time is initialised
        if nextTime.day == currentTime.day
            and nextStamp < currentStamp
            and nextEndStamp < currentStamp
            and self:isTimeInit(moveType, groupIdx == 2)
        then
            nextTime.day = nextTime.day + 1
            nextStamp = os.time(nextTime)
            nextEndStamp = nextStamp + totalHours * STAMP_HOUR
        end

        -- %c returns incorrect time ?
        print("[" .. tostring(groupIdx) .. "]" .. moveType .. " activity: "
              .. os.date("%d/%m/%y %H:%M:%S", nextStamp) .. " -> "
              .. os.date("%d/%m/%y %H:%M:%S", nextEndStamp)
        )

        local startKey = moveType .. "StampStart"
        local endKey = moveType .. "StampEnd"
        sendUpdate(groupIdx, startKey, nextStamp)
        sendUpdate(groupIdx, endKey, nextEndStamp)
        sandboxVars[groupIdx].key[startKey] = nextStamp
        sandboxVars[groupIdx].key[endKey] = nextEndStamp
        modData[groupIdx][startKey] = nextStamp
        modData[groupIdx][endKey] = nextEndStamp

        -- update randomised values
        for _, settingName in pairs({ "Chance", "Radius", "RadiusInterrupt", "Destructive" }) do
            if string.find(settingName, "Radius") == nil or moveType ~= "Wander" then
                local optionKeyValue = moveType .. settingName .. "Value"
                randValue = getPossibleRandValue(groupIdx, moveType .. settingName)
                sandboxVars[groupIdx].key[optionKeyValue] = randValue
                modData[groupIdx][optionKeyValue] = randValue
                sendUpdate(groupIdx, optionKeyValue, randValue)
            end
        end
    end
end

local groupTable
local groupIdx, optionIdx
local optionKey, optionValue, optionChanged
local rallyGroupOption ---@type zombie.config.IntegerConfigOption
local dirtyTimestamps = false
function WZSandboxVars:update()
    if not self._init then
        self._init = true

        -- setup option index and values
        for idx, key in ipairs(groupKeys) do
            groupTable = sandboxVars[idx]
            groupTable.index = {}
            groupTable.key = {}
            for k, v in pairs(SandboxVars[key]) do
                table.insert(groupTable.index, k)
                groupTable.key[k] = v
            end
        end

        -- reset/grab saved moddata
        modData = ModData.getOrCreate("WanderingZombies")
        for gIdx = WZ_LONE, WZ_HORDE do
            if modData.ver == WZ_SANDBOX_VERSION and modData[gIdx] ~= nil then
                for _, moveType in pairs(moveTypes) do
                    sandboxVars[gIdx].key[moveType .. "StampStart"] = modData[gIdx][moveType .. "StampStart"]
                    sandboxVars[gIdx].key[moveType .. "StampEnd"] = modData[gIdx][moveType .. "StampEnd"]

                    for _, settingName in pairs({ "Chance", "Radius", "RadiusInterrupt", "Destructive" }) do
                        if string.find(settingName, "Radius") == nil or moveType ~= "Wander" then
                            sandboxVars[gIdx].key[moveType .. settingName .. "Value"] = modData[gIdx][moveType .. settingName .. "Value"]
                        end
                    end
                end
            else
                modData[gIdx] = {}
                for _, moveType in pairs(moveTypes) do self:updateStamps(gIdx, moveType) end
            end
        end

        modData.ver = WZ_SANDBOX_VERSION
        optionIdx = 1
        groupIdx = 1
        return
    end

    groupTable = sandboxVars[groupIdx]
    optionKey = groupTable.index[optionIdx]
    optionValue, optionChanged = self:getUpdatedValue(groupIdx, optionKey)
    if optionChanged then
        groupTable.key[optionKey] = optionValue
        sendUpdate(groupIdx, optionKey, optionValue)

        -- detect changes in the time and time dependant settings
        if not dirtyTimestamps and (groupIdx == WZ_LONE or groupIdx == WZ_HORDE) then
            dirtyTimestamps = optionKey:find("Hour")
                or optionKey:find("Chance")
                or optionKey:find("Radius")
                or optionKey:find("Destructive")
        end
    end

    optionIdx = optionIdx + 1
    if optionIdx > #groupTable.index then
        if groupIdx == WZ_LONE or groupIdx == WZ_HORDE then
            for _, moveType in pairs(moveTypes) do self:updateStamps(groupIdx, moveType, dirtyTimestamps) end
            dirtyTimestamps = false
        end

        optionIdx = 1
        groupIdx = groupIdx + 1
        if groupIdx > #groupKeys then groupIdx = 1 end
    end
end

local function WZTick()
    WZSandboxVars:update()
end

if isServer() or isCoopHost() or not isClient() then Events.OnTick.Add(WZTick) end

Events.OnTick.Add(function()
    if SandboxVars.ZombieConfig.RallyGroupSize ~= 0 then
        getSandboxOptions():set("ZombieConfig.RallyGroupSize", 0)
        SandboxVars.ZombieConfig.RallyGroupSize = 0
    end
end)

------------------------
-- Client Init/Update --
------------------------

---@param mod string
---@param command string
---@param args table
local function OnServerCommand(mod, command, args)
    if mod ~= "WanderingZombies" then return end

    if command == "WZSVUpdate" then
        sandboxVars[args.g].key[args.o] = args.v
    elseif command == "WZSVInit" then
        WZSandboxVars._init = true
        sandboxVars = args
    end
end

local function PlayerIDTick()
    local player = getPlayer()
    if player == nil or player:getOnlineID() == -1 then return end

    Events.OnTick.Remove(PlayerIDTick)
    sendClientCommand(player, "WanderingZombies", "WZSVInit", {})
end

local function OnLoad()
    Events.OnTick.Add(PlayerIDTick)
end

if isClient() and not isCoopHost() then
    Events.OnServerCommand.Add(OnServerCommand)
    Events.OnLoad.Add(OnLoad)
end

---@param mod string
---@param command string
---@param player zombie.characters.IsoPlayer
---@param args table
local function OnClientCommand(mod, command, player, args)
    if mod ~= "WanderingZombies" then return end
    if command ~= "WZSVInit" then return end

    local sv = {}
    for i = WZ_LONE, WZ_DIRECTOR do sv[i] = { key = sandboxVars[i].key } end
    sendServerCommand(player, "WanderingZombies", "WZSVInit", sv)
end

if isServer() or isCoopHost() then Events.OnClientCommand.Add(OnClientCommand) end
