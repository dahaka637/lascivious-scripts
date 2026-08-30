require("RYUKU_WanderingZombies_Time")

WZ_LONE = 1
WZ_HORDE = 2
WZ_SHARED = 3
WZ_PERFORMANCE = 4

local STAMP_HOUR = 60 * 60

local sandboxVars =
{
    [WZ_LONE] = {},
    [WZ_HORDE] = {},
    [WZ_SHARED] = {},
    [WZ_PERFORMANCE] = {}
}

-------------------
-- WZSandboxVars --
-------------------

---@class WZSandboxVars
---@field private _init boolean
---@field private _updateCooldown integer
---@field private _hordeCount integer
WZSandboxVars =
{
    _init = false,
    _updateCooldown = 0,
    _hordeCount = 0
}

---@return boolean
function WZSandboxVars:isInitiated()
    return self._init
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
    return sandboxVars[idx][name]
end

---@param name string
---@param inHorde boolean?
function WZSandboxVars:getZ(name, inHorde)
    return sandboxVars[(inHorde and WZ_HORDE) or WZ_LONE][name]
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

    local stime = sandboxVars[idx][name .. "StampStart"]
    if not stime then return false end

    local etime = sandboxVars[idx][name .. "StampEnd"]
    if not etime then return false end

    return time >= stime and time < etime
end

---@param name string
---@param getHordeVar boolean?
---@return boolean
function WZSandboxVars:isTimeInit(name, getHordeVar)
    local idx = (getHordeVar == true and WZ_HORDE) or WZ_LONE
    return sandboxVars[idx][name .. "StampStart"] ~= nil and sandboxVars[idx][name .. "StampEnd"] ~= nil
end

---@param name string
---@param getHordeVar boolean?
---@return boolean
function WZSandboxVars:isTimeElapsed(name, getHordeVar)
    local idx = (getHordeVar and WZ_HORDE) or WZ_LONE
    local etime = sandboxVars[idx][name .. "StampEnd"]
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
    return sandboxVars[WZ_HORDE][speedTable[speed]] == true
end

------------
-- Update --
------------

---@param idx integer
---@param name string
---@param value any
---@param updateTable table
local function updateValue(idx, name, value, updateTable)
    if sandboxVars[idx][name] == value then return end

    if updateTable[idx] == nil then updateTable[idx] = {} end
    sandboxVars[idx][name] = value
    updateTable[idx][name] = value
    updateTable.size = updateTable.size + 1

    -- detect changes in the time and time dependant settings, and reset the timestamps
    if string.find(name, "Hour")
        or string.find(name, "Chance")
        or string.find(name, "Radius")
        or string.find(name, "Destructive")
    then
        local key = "Wander"
        if string.find(name, "Flee") then key = "Flee"
        elseif string.find(name, "Homing") then key = "Homing" end

        sandboxVars[idx][key .. "StampStart"] = nil
        sandboxVars[idx][key .. "StampEnd"] = nil
    end
end

---@param idx integer
---@param name string
---@return integer
local function getPossibleRandValue(idx, name)
    local min = sandboxVars[idx][name .. "Min"]
    if min ~= nil then
        if sandboxVars[idx][name .. "Dropdown"] < 2 then return min end

        local max = sandboxVars[idx][name .. "Max"]
        if min == max then return min
        elseif min < max then return ZombRand(min, max + 1)
        else
            if string.find(name, "StartHour") then
                max = max + 24
                local result = ZombRand(min, max + 1)
                if result > 23 then return result - 24
                else return result end
            end

            return ZombRand(max, min + 1)
        end
    end

    if sandboxVars[idx][name] < 4 then return sandboxVars[idx][name] end
    return ZombRand(3) + 1
end

local modData
function WZSandboxVars:update()
    if getTimeInMillis() < self._updateCooldown then return end

    getSandboxOptions():set("ZombieConfig.RallyGroupSize", 0)
    if not isClient() then SandboxVars.ZombieConfig.RallyGroupSize = 0 end

    -- load existing time related data
    if not self._init then
        self._init = true
        modData = ModData.getOrCreate("WanderingZombies")
        for idx = 1, 2 do
            if modData[idx] ~= nil then
                for _, moveType in pairs({ "Flee", "Homing", "Wander" }) do
                    sandboxVars[idx][moveType .. "StampStart"] = modData[idx][moveType .. "StampStart"]
                    sandboxVars[idx][moveType .. "StampEnd"] = modData[idx][moveType .. "StampEnd"]

                    for _, settingName in pairs({ "Chance", "Radius", "RadiusInterrupt", "Destructive" }) do
                        if string.find(settingName, "Radius") == nil or moveType ~= "Wander" then
                            sandboxVars[idx][moveType .. settingName] = modData[idx][moveType .. settingName]
                        end
                    end
                end
            else
                modData[idx] = {}
            end
        end
    end

    local updateTable = { size = 0 }
    for idx, v in pairs({ "WZLoneZombie", "WZHordeZombie", "WZShared", "WZPerformance" }) do
        for name, value in pairs(SandboxVars[v]) do
            updateValue(idx, name, value, updateTable)
        end
    end

    self._updateCooldown = getTimeInMillis() + sandboxVars[WZ_PERFORMANCE].SandboxVarsUpdateFreq

    local time, endTime, randValue
    local start, total, cooldown
    local timeTable = WZTime:getTable()
    local nextTimeTable = WZTime:getTable()
    for idx = 1, 2 do
        for _, moveType in pairs({ "Flee", "Homing", "Wander" }) do
            if self:isTimeElapsed(moveType, idx == 2) then
                -- update start/end timestamps
                start = getPossibleRandValue(idx, moveType .. "StartHour")
                total = getPossibleRandValue(idx, moveType .. "TotalHours")
                cooldown = getPossibleRandValue(idx, moveType .. "CooldownHours")

                nextTimeTable.hour = start + cooldown % 24
                nextTimeTable.day = timeTable.day + math.floor(cooldown / 24)
                if nextTimeTable.hour < timeTable.hour and nextTimeTable.day == timeTable.day then
                    if self:isTimeInit(moveType, idx == 2) then nextTimeTable.day = timeTable.day + 1 end
                end

                time = os.time(nextTimeTable)
                endTime = time + total * STAMP_HOUR
                updateValue(idx, moveType .. "StampStart", time, updateTable)
                updateValue(idx, moveType .. "StampEnd", endTime, updateTable)
                modData[idx][moveType .. "StampStart"] = time
                modData[idx][moveType .. "StampEnd"] = endTime

                -- update randomised values
                for _, settingName in pairs({ "Chance", "Radius", "RadiusInterrupt", "Destructive" }) do
                    if string.find(settingName, "Radius") == nil or moveType ~= "Wander" then
                        randValue = getPossibleRandValue(idx, moveType .. settingName)
                        updateValue(idx, moveType .. settingName, randValue, updateTable)
                        modData[idx][moveType .. settingName] = randValue
                    end
                end
            end
        end
    end

    if (isServer() or isCoopHost()) and updateTable.size > 0 then
        updateTable.size = nil
        sendServerCommand("WanderingZombies", "WZSVUpdate", updateTable)
    end
end

local function WZTick()
    WZSandboxVars:update()
end

if isServer() or isCoopHost() or not isClient() then Events.OnTick.Add(WZTick) end

------------------------
-- Client Init/Update --
------------------------

---@param module string
---@param command string
---@param args table
local function OnServerCommand(module, command, args)
    if module ~= "WanderingZombies" then return end

    if command == "WZSVUpdate" then
        for idx, _ in pairs(args) do
            for name, value in pairs(args[idx]) do
                sandboxVars[idx][name] = value
            end
        end
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

---@param module string
---@param command string
---@param player zombie.characters.IsoPlayer
---@param args table
local function OnClientCommand(module, command, player, args)
    if module ~= "WanderingZombies" then return end
    if command ~= "WZSVInit" then return end

    sendServerCommand(player, "WanderingZombies", "WZSVInit", sandboxVars)
end

if isServer() or isCoopHost() then Events.OnClientCommand.Add(OnClientCommand) end
