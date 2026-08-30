BetterEngineRepair = BetterEngineRepair or {}

local DEFAULT_GAIN_BY_LEVEL = {
    [0] = 3,
    [1] = 3,
    [2] = 3,
    [3] = 3,
    [4] = 5,
    [5] = 5,
    [6] = 5,
    [7] = 10,
    [8] = 10,
    [9] = 10,
    [10] = 20,
}

function BetterEngineRepair.getConditionGain(mechanicsLevel)
    mechanicsLevel = math.floor(math.max(0, math.min(10, tonumber(mechanicsLevel) or 0)))

    local configuredGain = nil
    if SandboxVars and SandboxVars.BetterEngineRepair then
        local optionName = "Mechanics" .. tostring(mechanicsLevel)
        configuredGain = SandboxVars.BetterEngineRepair[optionName]
    end

    local gain = tonumber(configuredGain) or DEFAULT_GAIN_BY_LEVEL[mechanicsLevel]
    gain = math.floor(gain)

    return math.max(1, math.min(100, gain))
end
