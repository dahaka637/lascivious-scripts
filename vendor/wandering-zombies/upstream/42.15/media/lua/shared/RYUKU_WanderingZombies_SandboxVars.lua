require("RYUKU_WanderingZombies_Time")

WZ_LONE = 1
WZ_HORDE = 2
WZ_SHARED = 3
WZ_PERFORMANCE = 4
WZ_DIRECTOR = 5
WZ_SANDBOX_VERSION = 1

local STAMP_HOUR = 60 * 60

local sandboxVars =
{
    [WZ_LONE] = {},
    [WZ_HORDE] = {},
    [WZ_SHARED] = {},
    [WZ_PERFORMANCE] = {},
    [WZ_DIRECTOR] = {},
}

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
    elseif name:find("Destructive") then
        if sandboxVars[idx][name] < 4 then return sandboxVars[idx][name] end
        return ZombRand(3) + 1
    elseif name:find("Interrupt") then
        if sandboxVars[idx][name] < 3 then return sandboxVars[idx][name] end
        return ZombRand(2) + 1
    else
        print("WZSandboxVars.getPossibleRandValue: unknown - " .. tostring(name))
        return 0
    end
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
            if modData.ver == WZ_SANDBOX_VERSION and modData[idx] ~= nil then
                for _, moveType in pairs({ "Flee", "Homing", "Wander" }) do
                    sandboxVars[idx][moveType .. "StampStart"] = modData[idx][moveType .. "StampStart"]
                    sandboxVars[idx][moveType .. "StampEnd"] = modData[idx][moveType .. "StampEnd"]

                    for _, settingName in pairs({ "Chance", "Radius", "RadiusInterrupt", "Destructive" }) do
                        if string.find(settingName, "Radius") == nil or moveType ~= "Wander" then
                            sandboxVars[idx][moveType .. settingName .. "Value"] = modData[idx][moveType .. settingName .. "Value"]
                        end
                    end
                end
            else
                modData[idx] = {}
            end
        end

        modData.ver = WZ_SANDBOX_VERSION
    end

    local updateTable = { size = 0 }
    for idx, v in pairs({ "WZLoneZombie", "WZHordeZombie", "WZShared", "WZPerformance", "WZDirector" }) do
        for name, value in pairs(SandboxVars[v]) do
            updateValue(idx, name, value, updateTable)
        end
    end

    self._updateCooldown = getTimeInMillis() + sandboxVars[WZ_PERFORMANCE].SandboxVarsUpdateFreq

    local nextStamp, nextEndStamp, randValue
    local start, total, cooldown
    local currentStamp = WZTime:getTimestamp()
    local currentTime = WZTime:getTable()
    local nextTime = WZTime:getTable()
    for idx = 1, 2 do
        for _, moveType in pairs({ "Flee", "Homing", "Wander" }) do
            if self:isTimeElapsed(moveType, idx == 2) then
                -- update start/end timestamps
                start = getPossibleRandValue(idx, moveType .. "StartHour")
                total = getPossibleRandValue(idx, moveType .. "TotalHours")
                cooldown = getPossibleRandValue(idx, moveType .. "CooldownHours")

                nextTime.hour = start + cooldown % 24
                nextTime.day = currentTime.day + math.floor(cooldown / 24)
                nextStamp = os.time(nextTime)
                nextEndStamp = nextStamp + total * STAMP_HOUR

                -- push the period of activity to the next day when:
                --   same day
                --   start stamp is less than the current stamp
                --   end stamp is less than the current stamp
                --   time is initialised
                if nextTime.day == currentTime.day
                    and nextStamp < currentStamp
                    and nextEndStamp < currentStamp
                    and self:isTimeInit(moveType, idx == 2)
                then
                    nextTime.day = nextTime.day + 1
                    nextStamp = os.time(nextTime)
                    nextEndStamp = nextStamp + total * STAMP_HOUR
                end

                -- %c returns incorrect time ?
                print("[" .. tostring(idx) .. "]" .. moveType .. " activity: "
                      .. os.date("%d/%m/%y %H:%M:%S", nextStamp) .. " -> "
                      .. os.date("%d/%m/%y %H:%M:%S", nextEndStamp)
                )

                updateValue(idx, moveType .. "StampStart", nextStamp, updateTable)
                updateValue(idx, moveType .. "StampEnd", nextEndStamp, updateTable)
                modData[idx][moveType .. "StampStart"] = nextStamp
                modData[idx][moveType .. "StampEnd"] = nextEndStamp

                -- update randomised values
                for _, settingName in pairs({ "Chance", "Radius", "RadiusInterrupt", "Destructive" }) do
                    if string.find(settingName, "Radius") == nil or moveType ~= "Wander" then
                        randValue = getPossibleRandValue(idx, moveType .. settingName)
                        updateValue(idx, moveType .. settingName .. "Value", randValue, updateTable)
                        modData[idx][moveType .. settingName .. "Value"] = randValue
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
