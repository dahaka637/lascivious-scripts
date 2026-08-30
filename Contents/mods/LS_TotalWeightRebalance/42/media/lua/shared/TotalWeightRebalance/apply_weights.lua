local vanillaWeights = require("TotalWeightRebalance/weights_vanilla")
local modWeights = require("TotalWeightRebalance/weights_mods")

local WeightManager = {}
local MODULE = "TotalWeightRebalance"
local OPTION_NAME = MODULE .. ".CustomWeights"
local originalWeights = {}
local twrWeights = {}
local customWeights = {}

local function isValidWeight(weight)
    return type(weight) == "number" and weight >= 0 and weight < math.huge
end

local function formatWeight(weight)
    local value = string.format("%.5f", weight)
    value = string.gsub(value, "0+$", "")
    return string.gsub(value, "%.$", "")
end

local function applyScriptWeight(fullType, weight)
    local item = ScriptManager.instance:getItem(fullType)
    if not item or not isValidWeight(weight) then return false end
    item:setActualWeight(weight)
    return true
end

local function parseWeights(value)
    local weights = {}
    for entry in string.gmatch(value or "", "([^;]+)") do
        local fullType, rawWeight = string.match(entry, "^%s*([%w_]+%.[%w_]+)%s*[=:]%s*(.-)%s*$")
        local weight = tonumber(rawWeight)
        if fullType and isValidWeight(weight) then weights[fullType] = weight end
    end
    return weights
end

local function serializeWeights(weights)
    local fullTypes = {}
    for fullType in pairs(weights) do table.insert(fullTypes, fullType) end
    table.sort(fullTypes)

    local entries = {}
    for _, fullType in ipairs(fullTypes) do
        table.insert(entries, fullType .. ":" .. formatWeight(weights[fullType]))
    end
    return table.concat(entries, "; ")
end

local function applyWeightTable(weights, rememberTwrWeight)
    for fullType, weight in pairs(weights) do
        if applyScriptWeight(fullType, weight) and rememberTwrWeight then
            twrWeights[fullType] = weight
        end
    end
end

local function captureOriginalWeights()
    local items = ScriptManager.instance:getAllItems()
    for i = 0, items:size() - 1 do
        local item = items:get(i)
        local fullType = item:getFullName()
        if originalWeights[fullType] == nil then
            originalWeights[fullType] = item:getActualWeight()
        end
    end
end

local function getSandboxValue()
    local options = SandboxVars.TotalWeightRebalance
    return options and options.CustomWeights or ""
end

local function setSandboxValue(value)
    SandboxVars.TotalWeightRebalance.CustomWeights = value
    getSandboxOptions():set(OPTION_NAME, value)
end

local function applyAllWeights()
    captureOriginalWeights()
    twrWeights = {}
    for _, weights in pairs(vanillaWeights) do applyWeightTable(weights, true) end
    for _, weights in ipairs(modWeights) do applyWeightTable(weights, true) end

    customWeights = parseWeights(getSandboxValue())
    applyWeightTable(customWeights)
end

local function applyContainer(container)
    local items = container and container:getItems()
    if not items then return end

    for i = 0, items:size() - 1 do
        local item = items:get(i)
        local weight = customWeights[item:getFullType()]
        if weight then item:setActualWeight(weight) end
        if instanceof(item, "InventoryContainer") then applyContainer(item:getInventory()) end
    end
end

local function applyPlayerInventories()
    local hasCustomWeights = false
    for _ in pairs(customWeights) do
        hasCustomWeights = true
        break
    end
    if not hasCustomWeights then return end

    if isServer() then
        local players = getOnlinePlayers()
        for i = 0, players:size() - 1 do applyContainer(players:get(i):getInventory()) end
        return
    end

    for playerNum = 0, getNumActivePlayers() - 1 do
        local player = getSpecificPlayer(playerNum)
        if player then applyContainer(player:getInventory()) end
    end
end

local function loadSandboxValue(value)
    setSandboxValue(value)
    customWeights = parseWeights(value)
    applyWeightTable(customWeights)
    applyPlayerInventories()
end

local function persistSandboxOptions()
    if isServer() then
        getSandboxOptions():saveServerLuaFile(getServerName())
    else
        save(true)
    end
end

local function saveWeight(fullType, weight)
    local weights = parseWeights(getSandboxValue())
    weights[fullType] = weight
    local value = serializeWeights(weights)
    loadSandboxValue(value)
    persistSandboxOptions()
    return value
end

function WeightManager.getOriginalWeight(fullType)
    return originalWeights[fullType]
end

function WeightManager.getTwrWeight(fullType)
    return twrWeights[fullType] or originalWeights[fullType]
end

function WeightManager.getWeight(fullType)
    return customWeights[fullType] or twrWeights[fullType] or originalWeights[fullType]
end

function WeightManager.formatWeight(weight)
    return formatWeight(weight)
end

function WeightManager.setWeight(player, fullType, weight)
    if not applyScriptWeight(fullType, weight) then return end
    if isClient() then
        sendClientCommand(player, MODULE, "setWeight", { fullType = fullType, weight = weight })
        return
    end
    saveWeight(fullType, weight)
end

local function onClientCommand(module, command, player, args)
    if module ~= MODULE or command ~= "setWeight" then return end

    local admin = player and string.lower(tostring(player:getAccessLevel() or "")) == "admin"
    local fullType = args and args.fullType
    local weight = args and tonumber(args.weight)
    if not admin or type(fullType) ~= "string" then return end
    if not applyScriptWeight(fullType, weight) then return end

    local value = saveWeight(fullType, weight)
    sendServerCommand(MODULE, "weightsChanged", { value = value })
end

local function onServerCommand(module, command, args)
    if module ~= MODULE or command ~= "weightsChanged" then return end
    if not args or type(args.value) ~= "string" then return end
    loadSandboxValue(args.value)
end

Events.OnLoadedTileDefinitions.Add(applyAllWeights)
if not isServer() then Events.OnGameStart.Add(applyPlayerInventories) end
if isServer() then Events.OnClientCommand.Add(onClientCommand) end
if isClient() then Events.OnServerCommand.Add(onServerCommand) end

return WeightManager
