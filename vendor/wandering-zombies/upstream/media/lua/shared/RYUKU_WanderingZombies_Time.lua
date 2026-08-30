local gameTime ---@type zombie.GameTime
local dateTable = {}

---@class WZTime
WZTime = {}

---@param timeTable table?
---@return integer
function WZTime:getTimestamp(timeTable)
    if timeTable ~= nil then return os.time(timeTable) end
    if not gameTime then gameTime = getGameTime() end

    dateTable.day = gameTime:getDay() + 1
    dateTable.month = gameTime:getMonth() + 1
    dateTable.year = gameTime:getYear()
    dateTable.hour = gameTime:getHour()
    dateTable.min = gameTime:getMinutes()
    return os.time(dateTable)
end

---@return table
function WZTime:getTable()
    if not gameTime then gameTime = getGameTime() end
    return {
        day = gameTime:getDay() + 1,
        month = gameTime:getMonth() + 1,
        year = gameTime:getYear(),
        hour = gameTime:getHour(),
        min = gameTime:getMinutes()
    }
end
