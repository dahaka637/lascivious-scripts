require "CyesPushDoors/Settings"

local CPD = CyesPushDoors
local S = CPD.Settings
local MOD_ID = "CyesPushDoors"
local MOD_NAME = "Cye's Push Doors!"

local options = nil
local registered = false
local tick = 0

local function currentLanguage()
    local name = ""
    local base = ""

    if Translator and Translator.getLanguage then
        local okLanguage, language = pcall(function() return Translator.getLanguage() end)
        if okLanguage and language then
            local okName, valueName = pcall(function() return language:name() end)
            if okName and valueName ~= nil then name = string.upper(tostring(valueName)) end
            local okBase, valueBase = pcall(function() return language:base() end)
            if okBase and valueBase ~= nil then base = string.upper(tostring(valueBase)) end
        end
    end

    if name == "" and getCore then
        local okCore, core = pcall(getCore)
        if okCore and core and core.getOptionLanguageName then
            local okName, valueName = pcall(function() return core:getOptionLanguageName() end)
            if okName and valueName ~= nil then name = string.upper(tostring(valueName)) end
        end
    end

    return name, base
end

local function useSpanishText()
    local name, base = currentLanguage()
    if name == "ES" or name == "ES_MX" or base == "ES" then return true end
    if string.find(name, "ESPAÑOL", 1, true) ~= nil then return true end
    if string.find(name, "ESPANOL", 1, true) ~= nil then return true end
    if string.find(name, "SPANISH", 1, true) ~= nil then return true end
    return false
end

local function localText(english, spanish)
    if useSpanishText() then return spanish end
    return english
end


local function hasEntry()
    if not PZAPI or not PZAPI.ModOptions or not PZAPI.ModOptions.Data then return false end
    for i = 1, #PZAPI.ModOptions.Data do
        if PZAPI.ModOptions.Data[i] == options then return true end
    end
    return false
end

local function registerOptions()
    if not options or not PZAPI or not PZAPI.ModOptions then return end
    PZAPI.ModOptions.Dict = PZAPI.ModOptions.Dict or {}
    PZAPI.ModOptions.Data = PZAPI.ModOptions.Data or {}
    PZAPI.ModOptions.Dict[MOD_ID] = options
    if not hasEntry() then
        table.insert(PZAPI.ModOptions.Data, options)
    end
    registered = true
end

local function unregisterOptions()
    if not options or not PZAPI or not PZAPI.ModOptions then return end
    if PZAPI.ModOptions.Dict then
        PZAPI.ModOptions.Dict[MOD_ID] = nil
    end
    if PZAPI.ModOptions.Data then
        for i = #PZAPI.ModOptions.Data, 1, -1 do
            if PZAPI.ModOptions.Data[i] == options then
                table.remove(PZAPI.ModOptions.Data, i)
            end
        end
    end
    registered = false
end

local function applyOptions()
    if not options then return end
    local feedback = options:getOption("ImpactFeedback")
    if feedback then
        S.setClientImpactFeedback(feedback:getValue() == true)
    end
end

local function createOptions()
    if options then return end
    if not PZAPI or not PZAPI.ModOptions then return end

    options = PZAPI.ModOptions:create(MOD_ID, MOD_NAME)
    options:addTickBox(
        "ImpactFeedback",
        localText("Impact Feedback", "Feedback de impacto"),
        true,
        localText("Play impact sounds and visual hit reactions.", "Reproduce sonidos de impacto y reacciones visuales.")
    )

    options.apply = function(self)
        applyOptions()
    end

    registered = true
end

local function refreshVisibility()
    createOptions()
    if not options then return end

    if S.hideIndividualOptions() then
        if registered then unregisterOptions() end
    else
        if not registered then registerOptions() end
        applyOptions()
    end
end

local function onGameBoot()
    createOptions()
end

local function onMainMenuEnter()
    createOptions()
    registerOptions()
    applyOptions()
end

local function onGameStart()
    refreshVisibility()
end

local function onTick()
    tick = tick + 1
    if tick % 120 == 0 then
        refreshVisibility()
    end
end

if Events.OnGameBoot then Events.OnGameBoot.Add(onGameBoot) end
if Events.OnMainMenuEnter then Events.OnMainMenuEnter.Add(onMainMenuEnter) end
if Events.OnGameStart then Events.OnGameStart.Add(onGameStart) end
if Events.OnTick then Events.OnTick.Add(onTick) end
