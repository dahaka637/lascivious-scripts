-- Photo mode: a toggle for clean screenshots. Hides HUD and player
-- names, optionally calms the weather and pauses time in solo play.
-- On disable every remembered state is restored exactly.
require "ISUI/ISUIHandler"
require "Aegis/AegisTheme"

AegisPhotoMode = AegisPhotoMode or {}
AegisPhotoMode.on = false
-- states captured on enable, nil while the mode is off
AegisPhotoMode.memo = nil
-- timestamp for the delayed HUD-off, keeps the toast readable briefly
AegisPhotoMode.hudAb = nil

local HUD_DELAY_MS = 1200
-- climate indices per engine bytecode: 3 rain, 5 fog, 6 wind, 8 clouds
local CLIMATE_INDICES = { 3, 5, 6, 8 }
-- a touch of clouds looks more natural in photos than an empty sky
local CLOUDS = 0.2

function AegisPhotoMode.isOn()
    return AegisPhotoMode.on == true
end

-- key of the Aegis panel, 0 when none is bound
local function panelKey()
    local key = 0
    if AegisHud and AegisHud.keybind then
        local v = AegisHud.keybind:getValue()
        if type(v) == "number" then key = v end
    end
    return key
end

local function keyName(k)
    local name = nil
    pcall(function() name = Keyboard.getKeyName(k) end)
    if (not name or name == "") and getKeyName then
        pcall(function() name = getKeyName(k) end)
    end
    return name
end

-- hint with the exit key, deliberately shown BEFORE the HUD goes off so
-- the screenshot itself has no text in it
local function showHint()
    local key = panelKey()
    local name = key ~= 0 and keyName(key) or nil
    if name and name ~= "" then
        Aegis.showToast(getText("UI_Aegis_PhotoOn", name))
    else
        Aegis.showToast(getText("UI_Aegis_PhotoOnEsc"))
    end
end

local function enable(withWeather)
    local p = getPlayer()
    if not p or not Aegis.allowed(p) then return end

    -- snapshot first
    local m = { withWeather = withWeather }
    m.hud = ISUIHandler.allUIVisible ~= false
    m.pauseText = UIManager.isShowPausedMessage()
    m.ownName = getCore():isShowYourUsername()
    m.seeAll = p:canSeeAll()
    if AegisShared.isSoloSP() then
        m.speed = UIManager.getSpeedControls():getCurrentGameSpeed()
    end
    AegisPhotoMode.memo = m
    AegisPhotoMode.on = true

    showHint()
    Aegis.logAction("world", withWeather and "Photo mode on (weather calmed)" or "Photo mode on")

    UIManager.setShowPausedMessage(false)
    getCore():setShowYourUsername(false)
    p:setCanSeeAll(false)
    Aegis.syncPowers(p)

    -- real time stop only in solo, an MP client cannot pause
    if AegisShared.isSoloSP() then
        UIManager.getSpeedControls():SetCurrentGameSpeed(0)
    end

    if withWeather then
        -- stop the running weather period, via direct call in solo because
        -- transmitStopWeather is a no-op there
        pcall(function()
            local cm = getClimateManager()
            if isClient() then cm:transmitStopWeather() else cm:stopWeatherAndThunder() end
        end)
        -- override to calm, in MP it only applies after the transmit
        pcall(function()
            local cm = getClimateManager()
            for _, idx in ipairs(CLIMATE_INDICES) do
                local f = cm:getClimateFloat(idx)
                f:setEnableAdmin(true)
                f:setAdminValue(idx == 8 and CLOUDS or 0)
            end
            if isClient() then cm:transmitClientChangeAdminVars() end
        end)
    end

    -- HUD goes off as the last step, slightly delayed because of the toast
    AegisPhotoMode.hudAb = getTimestampMs() + HUD_DELAY_MS
end

local function disable()
    local m = AegisPhotoMode.memo or {}
    local p = getPlayer()
    AegisPhotoMode.on = false
    AegisPhotoMode.memo = nil
    AegisPhotoMode.hudAb = nil

    UIManager.setShowPausedMessage(m.pauseText ~= false)
    getCore():setShowYourUsername(m.ownName ~= false)
    if p then
        p:setCanSeeAll(m.seeAll == true)
        Aegis.syncPowers(p)
    end
    if AegisShared.isSoloSP() then
        UIManager.getSpeedControls():SetCurrentGameSpeed(m.speed or 1)
    end
    if m.withWeather then
        -- weather restore means: admin override off again, no guessing of
        -- old values, nature rolls fresh weather itself
        pcall(function()
            local cm = getClimateManager()
            for _, idx in ipairs(CLIMATE_INDICES) do
                cm:getClimateFloat(idx):setEnableAdmin(false)
            end
            if isClient() then cm:transmitClientChangeAdminVars() end
        end)
    end

    -- HUD back as the last step, only if we hid it ourselves
    if m.hudHidden then
        ISUIHandler.setVisibleAllUI(true)
        ISUIHandler.allUIVisible = true
    end

    Aegis.logAction("world", "Photo mode off")
end

-- withWeather controls the weather calming, default on
function AegisPhotoMode.setOn(on, withWeather)
    on = on == true
    if on == AegisPhotoMode.on then return end
    if on then
        enable(withWeather ~= false)
    else
        disable()
    end
end

function AegisPhotoMode.toggle(withWeather)
    AegisPhotoMode.setOn(not AegisPhotoMode.on, withWeather)
end

-- delayed HUD-off, keeps running in a paused solo game too
Events.OnTickEvenPaused.Add(function()
    local deadline = AegisPhotoMode.hudAb
    if not deadline or getTimestampMs() < deadline then return end
    AegisPhotoMode.hudAb = nil
    local m = AegisPhotoMode.memo
    if not AegisPhotoMode.on or not m then return end
    -- if the HUD was already off before, it stays untouched
    if m.hud == false then return end
    m.hudHidden = true
    ISUIHandler.setVisibleAllUI(false)
    -- sync with the vanilla toggle, setVisibleAllUI does not update the flag
    ISUIHandler.allUIVisible = false
end)

-- way back with hidden HUD: OnKeyPressed still fires, the panel key
-- or ESC ends the mode
Events.OnKeyPressed.Add(function(key)
    if not AegisPhotoMode.on then return end
    local bound = panelKey()
    if key == Keyboard.KEY_ESCAPE or (bound ~= 0 and key == bound) then
        AegisPhotoMode.setOn(false)
    end
end)

-- a fresh world start clears an orphaned state from the previous world
Events.OnGameStart.Add(function()
    AegisPhotoMode.on = false
    AegisPhotoMode.memo = nil
    AegisPhotoMode.hudAb = nil
end)

-- death/respawn spawns a new character without a new Lua start (no
-- OnGameStart), an orphaned photo mode would otherwise keep running with
-- hidden HUD; in MP time does not stop anyway, in solo the time stop is
-- moot after your own death
Events.OnPlayerDeath.Add(function()
    if AegisPhotoMode.isOn() then
        AegisPhotoMode.setOn(false)
    end
end)
