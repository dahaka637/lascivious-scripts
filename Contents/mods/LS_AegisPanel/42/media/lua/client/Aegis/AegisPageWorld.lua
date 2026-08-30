-- World control: time of day, weather, events
require "Aegis/AegisWindow"
require "ISUI/ISComboBox"

AegisPageWorld = ISPanel:derive("AegisPageWorld")

function AegisPageWorld.create(window, x, y, w, h)
    local o = ISPanel:new(x, y, w, h)
    setmetatable(o, AegisPageWorld)
    AegisPageWorld.__index = AegisPageWorld
    o.background = false
    o.window = window
    o.colW = math.floor((w - 60) / 2)
    return o
end

function AegisPageWorld:createChildren()
    local pad = 20
    local x = pad + 14
    local w = self.colW - 28

    -- time card, left column
    local y = pad + 46
    local presets = {
        { label = "UI_Aegis_Morning",  icon = "sun",   hour = 7 },
        { label = "UI_Aegis_Noon",     icon = "sun",   hour = 12 },
        { label = "UI_Aegis_Evening",  icon = "moon",  hour = 19 },
        { label = "UI_Aegis_Midnight", icon = "moon",  hour = 0 },
    }
    local bw = math.floor((w - 12) / 2)
    local col = 0
    for _, def in ipairs(presets) do
        local btn = AegisButton:new(x + col * (bw + 12), y, bw, 34, getText(def.label), def.icon, self, function(page)
            page:setTime(def.hour)
        end)
        self:addChild(btn)
        col = col + 1
        if col == 2 then col = 0 y = y + 42 end
    end
    y = y + 8
    self.timeSlider = AegisSlider:new(x, y, w - 90, 24, self, nil)
    self.timeSlider:setValues(0, 23, 1, ":00")
    self.timeSlider:setValue(12, true)
    self:addChild(self.timeSlider)
    self.setTimeBtn = AegisButton:new(x + w - 80, y - 4, 80, 30, getText("UI_Aegis_SetTime"), nil, self, function(page)
        page:setTime(page.timeSlider.value)
    end)
    self.setTimeBtn.style = "gold"
    self:addChild(self.setTimeBtn)
    y = y + 36
    -- live line with IG date, time and season, text is built in prerender
    self.timeRowY = y
    y = y + 20
    local dbw = math.floor((w - 12) / 2)
    self.dateBtn = AegisButton:new(x, y, dbw, 30, getText("UI_Aegis_IgDate"), "pin", self, AegisPageWorld.onDate)
    self:addChild(self.dateBtn)
    self.clockBtn = AegisButton:new(x + dbw + 12, y, dbw, 30, getText("UI_Aegis_IgTime"), "clock", self, AegisPageWorld.onTimePick)
    self:addChild(self.clockBtn)
    self.timeBottom = y + 30 + 12

    -- weather card, bottom left
    local wy = self.timeBottom + 58
    self.durSlider = AegisSlider:new(x, wy, w, 24, self, nil)
    self.durSlider:setValues(4, 96, 4, "h")
    self.durSlider:setValue(24, true)
    self:addChild(self.durSlider)
    wy = wy + 34
    local weather = {
        { label = "UI_Aegis_Storm",    icon = "storm", stage = "STAGE_STORM",          transmit = "transmitTriggerStorm" },
        { label = "UI_Aegis_Tropical", icon = "rain",  stage = "STAGE_TROPICAL_STORM", transmit = "transmitTriggerTropical" },
        { label = "UI_Aegis_Blizzard", icon = "snow",  stage = "STAGE_BLIZZARD",       transmit = "transmitTriggerBlizzard" },
    }
    for _, def in ipairs(weather) do
        local btn = AegisButton:new(x, wy, w, 34, getText(def.label), def.icon, self, function(page)
            page:triggerWeather(def)
        end)
        self:addChild(btn)
        wy = wy + 42
    end
    -- roulette and stop share one row, the time card above needs the
    -- space and the page ends around 575 px
    local hbw = math.floor((w - 12) / 2)
    self.rouletteBtn = AegisButton:new(x, wy, hbw, 34, getText("UI_Aegis_Roulette"), "refresh", self, AegisPageWorld.onRoulette)
    self.rouletteBtn.tooltip = getText("UI_Aegis_RouletteTooltip")
    self:addChild(self.rouletteBtn)
    self.stopBtn = AegisButton:new(x + hbw + 12, wy, hbw, 34, getText("UI_Aegis_StopWeather"), "ban", self, AegisPageWorld.onStopWeather)
    self:addChild(self.stopBtn)
    self.weatherBottom = wy + 34 + 40

    -- events card, right column
    local ex = pad + self.colW + 20 + 14
    local ew = self.colW - 28
    local ey = pad + 46
    -- the helicopter lives as a configurable heli alert in the server-side
    -- event director, a second button here would be redundant
    local events = {
        { label = "UI_Aegis_Thunder",  icon = "bolt",    fn = AegisPageWorld.onThunder },
        { label = "UI_Aegis_Gunshot",  icon = "speaker", fn = AegisPageWorld.onGunshot },
        { label = "UI_Aegis_Firework", icon = "storm",   fn = AegisPageWorld.onFirework, tooltip = "UI_Aegis_FireworkTooltip" },
    }
    for _, def in ipairs(events) do
        local btn = AegisButton:new(ex, ey, ew, 36, getText(def.label), def.icon, self, def.fn)
        if def.tooltip then btn.tooltip = getText(def.tooltip) end
        self:addChild(btn)
        ey = ey + 42
    end
    ey = ey + 6
    self.noiseSlider = AegisSlider:new(ex, ey + 22, ew, 24, self, nil)
    self.noiseSlider:setValues(10, 500, 10, "")
    self.noiseSlider:setValue(120, true)
    self:addChild(self.noiseSlider)
    self.noiseBtn = AegisButton:new(ex, ey + 56, ew, 34, getText("UI_Aegis_Noise"), "speaker", self, AegisPageWorld.onNoise)
    self:addChild(self.noiseBtn)
    self.noiseY = ey
    self.eventsBottom = ey + 56 + 34 + 20

    -- instant rain via the climate admin override, kicks in without ramp-up
    local ry = self.eventsBottom + 12 + 74 + 12
    self.rainY = ry
    self.rainSlider = AegisSlider:new(ex, ry + 36, ew, 24, self, nil)
    self.rainSlider:setValues(10, 100, 10, "%")
    self.rainSlider:setValue(80, true)
    self:addChild(self.rainSlider)
    local rbw = math.floor((ew - 12) / 2)
    self.rainOnBtn = AegisButton:new(ex, ry + 70, rbw, 32, getText("UI_Aegis_RainOn"), "rain", self, function(page) page:setRain(true) end)
    self.rainOnBtn.style = "gold"
    self:addChild(self.rainOnBtn)
    self.rainOffBtn = AegisButton:new(ex + rbw + 12, ry + 70, rbw, 32, getText("UI_Aegis_RainOff"), "ban", self, function(page) page:setRain(false) end)
    self:addChild(self.rainOffBtn)
    self.rainBottom = ry + 70 + 32 + 14

    -- weather designer, full width below both columns; compact three-row
    -- layout because the page bottom sits close (~655 px inner height)
    local dx = pad + 14
    local dw = self.width - 2 * pad
    local innerW = dw - 28
    local dy = math.max(self.weatherBottom, self.rainBottom) + 6
    self.designerY = dy

    -- preset row: anchored to the RIGHT edge so nothing falls off the
    -- card on a narrow window;
    -- when even that gets tight the row moves below the title line and
    -- the whole block grows by one row
    local comboW = 200
    local presetW = comboW + 8 + 150 + 8 + 110 + 8 + 110
    local wrapped = pad + 250 + presetW > dx + innerW
    local py = dy + 3
    local px = dx + innerW - presetW
    if wrapped then
        py = dy + 30
        px = dx
        self.designerSliderY = dy + 34 + 30
        -- the combo absorbs whatever the narrow card cannot offer
        comboW = math.max(120, math.min(200, innerW - 8 * 3 - 150 - 110 - 110))
    end
    self.presetCombo = ISComboBox:new(px, py + 1, comboW, 24, self, nil)
    self.presetCombo:initialise()
    self:addChild(self.presetCombo)
    self.presetSaveBtn = AegisButton:new(px + comboW + 8, py, 150, 26, getText("UI_Aegis_WdSave"), "plus", self, AegisPageWorld.onPresetSave)
    self:addChild(self.presetSaveBtn)
    self.presetApplyBtn = AegisButton:new(px + comboW + 166, py, 110, 26, getText("UI_Aegis_WdApply"), "check", self, AegisPageWorld.onPresetApply)
    self:addChild(self.presetApplyBtn)
    self.presetDeleteBtn = AegisButton:new(px + comboW + 284, py, 110, 26, getText("UI_Aegis_WdDelete"), "minus", self, AegisPageWorld.onPresetDelete)
    self:addChild(self.presetDeleteBtn)

    -- four climate sliders in one row, label drawn left of each track
    local cellW = math.floor((innerW - 3 * 12) / 4)
    local sliderDefs = {
        { key = "clouds", label = "UI_Aegis_WdClouds", default = 70 },
        { key = "rain",   label = "UI_Aegis_WdRain",   default = 60 },
        { key = "fog",    label = "UI_Aegis_WdFog",    default = 0 },
        { key = "wind",   label = "UI_Aegis_WdWind",   default = 30 },
    }
    self.designerSliderY = self.designerSliderY or (dy + 34)
    self.designerCells = {}
    for i, def in ipairs(sliderDefs) do
        local cx = dx + (i - 1) * (cellW + 12)
        local s = AegisSlider:new(cx + 58, self.designerSliderY, cellW - 58, 24, self, nil)
        s:setValues(0, 100, 5, "%")
        s.valueW = 40
        s:setValue(def.default, true)
        self:addChild(s)
        table.insert(self.designerCells, { key = def.key, label = def.label, x = cx, slider = s })
    end

    -- thunder cadence chips plus apply/stop
    self.thunderMinutes = 0
    self.thunderChips = {}
    local chipY = self.designerSliderY + 28
    local chx = dx
    for _, m in ipairs({ 0, 1, 2, 3, 5, 10 }) do
        local label = m == 0 and getText("UI_Aegis_WdThunderOff") or (m .. " min")
        local cw = Aegis.strW(UIFont.Small, label) + 20
        local chip = AegisButton:new(chx, chipY, cw, 26, label, nil, self, function(page, b)
            page.thunderMinutes = b.chipValue
        end)
        chip.chipValue = m
        chip.radius = 13
        if m > 0 then chip.tooltip = getText("UI_Aegis_WdThunder", m) end
        self:addChild(chip)
        table.insert(self.thunderChips, chip)
        chx = chx + cw + 6
    end
    self.designerApplyBtn = AegisButton:new(dx + innerW - 214, chipY, 104, 26, getText("UI_Aegis_WdApply"), "check", self, AegisPageWorld.onDesignerApply)
    self.designerApplyBtn.style = "gold"
    self:addChild(self.designerApplyBtn)
    self.designerStopBtn = AegisButton:new(dx + innerW - 104, chipY, 104, 26, getText("UI_Aegis_WdStop"), "ban", self, AegisPageWorld.onDesignerStop)
    self:addChild(self.designerStopBtn)
    self.designerBottom = chipY + 26 + 6
    -- the whole layout is fixed, the window puts the page into a scroll
    -- host when it cannot offer this much (see AegisWindow.switchPage)
    self.designH = self.designerBottom + pad

    self:refreshPresetCombo(nil)
end

function AegisPageWorld:onShow()
    if isClient() then
        getClimateManager():transmitRequestAdminVars()
    end
end

function AegisPageWorld:setRain(on)
    local cm = getClimateManager()
    pcall(function()
        local precip = cm:getClimateFloat(3)
        local cloud = cm:getClimateFloat(8)
        if on then
            local v = self.rainSlider.value / 100
            precip:setEnableAdmin(true)
            precip:setAdminValue(v)
            cloud:setEnableAdmin(true)
            cloud:setAdminValue(math.max(0.6, v))
        else
            precip:setEnableAdmin(false)
            cloud:setEnableAdmin(false)
        end
        if isClient() then
            cm:transmitClientChangeAdminVars()
        end
    end)
    Aegis.logAction("world", on and ("Instant rain on (" .. self.rainSlider.value .. "%)") or "Instant rain off")
end

-- ------------------------------------------------------------------
-- Time
-- ------------------------------------------------------------------

function AegisPageWorld:setTime(hour)
    -- fires in-process in solo, the handler sets the clock and logs
    sendClientCommand(getPlayer(), "AegisAdmin", "settime", { hour = hour })
end

-- getCalender():get(7) returns 1 = Sunday through 7 = Saturday
local WEEKDAYS = { "UI_Aegis_Wd0", "UI_Aegis_Wd1", "UI_Aegis_Wd2", "UI_Aegis_Wd3", "UI_Aegis_Wd4", "UI_Aegis_Wd5", "UI_Aegis_Wd6" }

-- MP-safe hour/minute: see Aegis.hourMinute in AegisTheme.lua for the
-- verified engine reasons (timeOfDay smooths after a jump,
-- serverTimeOfDay is correct immediately). Wrapper instead of a top-level
-- alias so the mod file load order does not matter (Aegis.hourMinute is
-- resolved at call time, not when this file loads)
local function hourMinute(gt)
    return Aegis.hourMinute(gt)
end

-- readable line like "Mo 09.07.1993, 14:32, Sommer"
local function igTimeText()
    local gt = getGameTime()
    local hour, minute = hourMinute(gt)
    local text = string.format("%02d.%02d.%d, %s", gt:getDayPlusOne(), gt:getMonth() + 1, gt:getYear(),
        AegisTimePicker.format(hour, minute))
    local okw, wd = pcall(function() return gt:getCalender():get(7) end)
    if okw and WEEKDAYS[wd] then
        text = getText(WEEKDAYS[wd]) .. " " .. text
    end
    local oks, season = pcall(function() return getClimateManager():getSeason():getSeasonNameTranslated() end)
    if oks and season and season ~= "" then
        text = text .. ", " .. tostring(season)
    end
    return text
end

function AegisPageWorld.onTimePick(self)
    local gt = getGameTime()
    local hour, minute = hourMinute(gt)
    AegisTimePicker.show(getText("UI_Aegis_IgTime"), self, function(page, s, m)
        sendClientCommand(getPlayer(), "AegisAdmin", "setWorldTime", { hour = s, minute = m })
    end, hour, minute)
end

function AegisPageWorld.onDate(self)
    AegisDateDialog.show(self, function(page, day, month, year)
        page:sendDate(day, month, year)
    end)
end

-- send the date, the current clock time carries over unchanged so the
-- clock does not jump; going backwards asks for confirmation first
function AegisPageWorld:sendDate(day, month, year)
    local gt = getGameTime()
    local function apply()
        local now = getGameTime()
        local hour, minute = hourMinute(now)
        sendClientCommand(getPlayer(), "AegisAdmin", "setWorldTime", {
            year = year, month = month, day = day,
            hour = hour, minute = minute,
        })
        Aegis.showToast(getText("UI_Aegis_IgDateSet"))
    end
    local oldDate = gt:getYear() * 10000 + (gt:getMonth() + 1) * 100 + gt:getDayPlusOne()
    local newDate = year * 10000 + month * 100 + day
    if newDate < oldDate then
        AegisConfirm.show(getText("UI_Aegis_IgDate"), getText("UI_Aegis_IgBack"), getText("UI_Aegis_Apply"), self, apply)
    else
        apply()
    end
end

-- ------------------------------------------------------------------
-- Weather
-- ------------------------------------------------------------------

-- instant weather kick: triggered weather ramps up over many in-game
-- minutes; while the real period builds underneath, the visible climate
-- values are overridden right away and handed back ~20s later so the
-- genuine system takes over seamlessly. MP uses the climate admin channel
-- (server broadcasts to every client), solo the local scenario overrides
-- (vanilla pattern, AiteronScenario)
local KICK_MS = 20000
local kickUntil = nil

local KICK_VALUES = {
    STAGE_STORM          = { cloud = 1.0, precip = 0.85, fog = 0.15, wind = 0.85 },
    STAGE_TROPICAL_STORM = { cloud = 1.0, precip = 1.0,  fog = 0.10, wind = 1.0 },
    STAGE_BLIZZARD       = { cloud = 1.0, precip = 1.0,  fog = 0.45, wind = 1.0, snow = true },
}

local function kickApply(enable, values)
    local cm = getClimateManager()
    local floats = {
        cloud = ClimateManager.FLOAT_CLOUD_INTENSITY,
        precip = ClimateManager.FLOAT_PRECIPITATION_INTENSITY,
        fog = ClimateManager.FLOAT_FOG_INTENSITY,
        wind = ClimateManager.FLOAT_WIND_INTENSITY,
    }
    if isClient() then
        for key, id in pairs(floats) do
            local v = cm:getClimateFloat(id)
            v:setEnableAdmin(enable)
            if enable then v:setAdminValue(values[key] or 0) end
        end
        local snow = cm:getClimateBool(ClimateManager.BOOL_IS_SNOW)
        snow:setEnableAdmin(enable and values.snow == true)
        if enable and values.snow then snow:setAdminValue(true) end
        cm:transmitClientChangeAdminVars()
    else
        for key, id in pairs(floats) do
            local v = cm:getClimateFloat(id)
            v:setEnableOverride(enable)
            if enable then v:setOverride(values[key] or 0, 1.5) end
        end
        local snow = cm:getClimateBool(ClimateManager.BOOL_IS_SNOW)
        snow:setEnableOverride(enable and values.snow == true)
        if enable and values.snow then snow:setOverride(true) end
    end
end

function AegisPageWorld.weatherKick(stageName)
    local values = KICK_VALUES[stageName]
    if not values then return end
    local ok, err = pcall(kickApply, true, values)
    if ok then
        kickUntil = getTimestampMs() + KICK_MS
    else
        print("[Aegis] weather kick failed: " .. tostring(err))
    end
end

function AegisPageWorld.weatherKickStop()
    if not kickUntil then return end
    kickUntil = nil
    pcall(kickApply, false, KICK_VALUES.STAGE_STORM)
end

Events.OnTick.Add(function()
    if kickUntil and getTimestampMs() >= kickUntil then
        AegisPageWorld.weatherKickStop()
    end
end)

function AegisPageWorld:triggerWeather(def)
    local dur = self.durSlider.value
    local cm = getClimateManager()
    if isClient() then
        cm[def.transmit](cm, dur)
    else
        cm:triggerCustomWeatherStage(WeatherPeriod[def.stage], dur)
    end
    AegisPageWorld.weatherKick(def.stage)
    Aegis.logAction("world", "Weather triggered: " .. tostring(def.stage) .. " (" .. dur .. " h)")
end

function AegisPageWorld.onStopWeather(self)
    AegisPageWorld.weatherKickStop()
    AegisPageWorld.designerStop()
    local cm = getClimateManager()
    if isClient() then
        cm:transmitStopWeather()
    else
        cm:stopWeatherAndThunder()
    end
    Aegis.logAction("world", "Weather stopped")
end

-- surprises with a random weather event and a random duration
function AegisPageWorld.onRoulette(self)
    local pool = {
        { stage = "STAGE_STORM",          transmit = "transmitTriggerStorm" },
        { stage = "STAGE_TROPICAL_STORM", transmit = "transmitTriggerTropical" },
        { stage = "STAGE_BLIZZARD",       transmit = "transmitTriggerBlizzard" },
    }
    local pick = pool[ZombRand(#pool) + 1]
    local dur = ZombRand(8, 49)
    local cm = getClimateManager()
    if isClient() then
        cm[pick.transmit](cm, dur)
    else
        cm:triggerCustomWeatherStage(WeatherPeriod[pick.stage], dur)
    end
    AegisPageWorld.weatherKick(pick.stage)
    Aegis.logAction("world", "Weather roulette: " .. tostring(pick.stage) .. " (" .. dur .. " h)")
    Aegis.showToast(getText("UI_Aegis_RouletteResult"))
end

-- ------------------------------------------------------------------
-- Weather designer: free mix of the four climate floats plus an
-- optional thunder cadence. MP uses the climate admin channel, solo
-- the local overrides, same split as the weather kick above
-- ------------------------------------------------------------------

local DESIGNER_FLOATS = {
    clouds = "FLOAT_CLOUD_INTENSITY",
    rain   = "FLOAT_PRECIPITATION_INTENSITY",
    fog    = "FLOAT_FOG_INTENSITY",
    wind   = "FLOAT_WIND_INTENSITY",
}

-- module level so onStopWeather and the page tick share one state
local designer = { active = false, thunderEveryMs = 0, thunderNextAt = 0 }

local function designerSet(enable, values)
    local cm = getClimateManager()
    for key, name in pairs(DESIGNER_FLOATS) do
        local v = cm:getClimateFloat(ClimateManager[name])
        if isClient() then
            v:setEnableAdmin(enable)
            if enable then v:setAdminValue((values[key] or 0) / 100) end
        else
            v:setEnableOverride(enable)
            if enable then v:setOverride((values[key] or 0) / 100, 1.5) end
        end
    end
    if isClient() then
        cm:transmitClientChangeAdminVars()
    end
end

function AegisPageWorld:designerValues()
    local values = {}
    for _, cell in ipairs(self.designerCells) do
        values[cell.key] = cell.slider.value
    end
    return values
end

function AegisPageWorld.onDesignerApply(self)
    local values = self:designerValues()
    local ok, err = pcall(designerSet, true, values)
    if not ok then
        print("[Aegis] weather designer failed: " .. tostring(err))
        return
    end
    designer.active = true
    local mins = self.thunderMinutes or 0
    designer.thunderEveryMs = mins * 60000
    designer.thunderNextAt = getTimestampMs() + designer.thunderEveryMs
    Aegis.logAction("world", string.format(
        "Weather designer applied: clouds %d%%, rain %d%%, fog %d%%, wind %d%%, thunder %s",
        values.clouds, values.rain, values.fog, values.wind,
        mins > 0 and ("every " .. mins .. " min") or "off"))
    Aegis.showToast(getText("UI_Aegis_WeatherDesigner"))
end

-- shared stop path, onStopWeather calls this too
function AegisPageWorld.designerStop()
    if not designer.active then return end
    designer.active = false
    designer.thunderEveryMs = 0
    pcall(designerSet, false, {})
    Aegis.logAction("world", "Weather designer stopped")
end

function AegisPageWorld.onDesignerStop(self)
    AegisPageWorld.designerStop()
end

-- designer thunder loop, driven from the page tick in update()
local function designerTick()
    if not designer.active or designer.thunderEveryMs <= 0 then return end
    if getTimestampMs() < designer.thunderNextAt then return end
    designer.thunderNextAt = getTimestampMs() + designer.thunderEveryMs
    local p = getPlayer()
    if p then
        sendClientCommand(p, "event", "thunder", { x = p:getX(), y = p:getY(), isAll = false })
    end
end

-- presets live client side in the admin's own Zomboid/Lua folder,
-- line format P|name|clouds|rain|fog|wind|thunderMin
local PRESET_FILE = "AegisWeatherPresets.txt"
local presetsCache = nil

local function loadPresets()
    if presetsCache then return presetsCache end
    presetsCache = {}
    -- append writer first: creates folder and file without touching
    -- content, a bare getFileReader throws a raw IOException on a fresh
    -- Lua folder (same guard as the server file layer in Aegis_Store)
    pcall(function()
        local w = getFileWriter(PRESET_FILE, true, true)
        if w then w:close() end
    end)
    pcall(function()
        local reader = getFileReader(PRESET_FILE, true)
        if not reader then return end
        local line = reader:readLine()
        while line ~= nil do
            local name, c, r, f, wd, t = string.match(line, "^P|([^|]+)|(%d+)|(%d+)|(%d+)|(%d+)|(%d+)$")
            if name then
                table.insert(presetsCache, {
                    name = name,
                    clouds = tonumber(c), rain = tonumber(r),
                    fog = tonumber(f), wind = tonumber(wd),
                    thunder = tonumber(t),
                })
            end
            line = reader:readLine()
        end
        reader:close()
    end)
    return presetsCache
end

local function writePresets()
    pcall(function()
        local w = getFileWriter(PRESET_FILE, true, false)
        if not w then return end
        for _, p in ipairs(presetsCache or {}) do
            w:write(string.format("P|%s|%d|%d|%d|%d|%d\n", p.name, p.clouds, p.rain, p.fog, p.wind, p.thunder))
        end
        w:close()
    end)
end

function AegisPageWorld:refreshPresetCombo(selectName)
    local combo = self.presetCombo
    if not combo then return end
    combo:clear()
    local list = loadPresets()
    if #list == 0 then
        combo:addOption(getText("UI_Aegis_WdPresets"))
        combo.selected = 1
        return
    end
    local sel = 1
    for i, p in ipairs(list) do
        combo:addOption(p.name)
        if p.name == selectName then sel = i end
    end
    combo.selected = sel
end

function AegisPageWorld:selectedPreset()
    local list = loadPresets()
    if #list == 0 then return nil end
    return list[self.presetCombo.selected or 1]
end

function AegisPageWorld.onPresetSave(self)
    local prompt = AegisPrompt.show({
        title = getText("UI_Aegis_WdSave"),
        message = getText("UI_Aegis_WdName"),
        confirmLabel = getText("UI_Aegis_WdSave"),
        reasonRequired = true,
        target = self,
        onConfirm = function(page, name)
            name = name:gsub("[|\r\n]", ""):sub(1, 32)
            if name == "" then return end
            local values = page:designerValues()
            local entry = {
                name = name,
                clouds = values.clouds, rain = values.rain,
                fog = values.fog, wind = values.wind,
                thunder = page.thunderMinutes or 0,
            }
            local list = loadPresets()
            local replaced = false
            for i, p in ipairs(list) do
                if p.name == name then
                    list[i] = entry
                    replaced = true
                    break
                end
            end
            if not replaced then table.insert(list, entry) end
            writePresets()
            page:refreshPresetCombo(name)
            Aegis.showToast(name)
        end,
    })
    prompt.entry:setPlaceholderText(getText("UI_Aegis_WdName"))
end

function AegisPageWorld.onPresetApply(self)
    local preset = self:selectedPreset()
    if not preset then return end
    for _, cell in ipairs(self.designerCells) do
        cell.slider:setValue(preset[cell.key] or 0, true)
    end
    self.thunderMinutes = preset.thunder or 0
    AegisPageWorld.onDesignerApply(self)
end

function AegisPageWorld.onPresetDelete(self)
    local preset = self:selectedPreset()
    if not preset then return end
    local list = loadPresets()
    for i, p in ipairs(list) do
        if p.name == preset.name then
            table.remove(list, i)
            break
        end
    end
    writePresets()
    self:refreshPresetCombo(nil)
    Aegis.showToast(preset.name)
end

-- ------------------------------------------------------------------
-- Events
-- ------------------------------------------------------------------

-- thunderclap without a log line, the firework tick also calls this
local function thunderClap()
    local p = getPlayer()
    -- vanilla server path, fires in-process in solo
    sendClientCommand(p, "event", "thunder", { x = p:getX(), y = p:getY(), isAll = false })
end

function AegisPageWorld.onThunder(self)
    thunderClap()
    Aegis.logAction("world", "Thunder triggered")
end

function AegisPageWorld.onGunshot(self)
    if isClient() then
        SendCommandToServer("/gunshot")
    else
        -- same path as the server command, audible shot included
        pcall(function() getAmbientStreamManager():doGunEvent() end)
        local p = getPlayer()
        addSound(p, p:getX(), p:getY(), p:getZ(), 250, 100)
    end
    Aegis.logAction("world", "Gunshot sound triggered")
end

function AegisPageWorld.onNoise(self)
    local p = getPlayer()
    addSound(p, p:getX(), p:getY(), p:getZ(), self.noiseSlider.value, 100)
    Aegis.logAction("world", "Noise spawned (radius " .. self.noiseSlider.value .. ")")
end

-- little celebration: five thunderclaps in rhythm, troll-worthy for wins/events
function AegisPageWorld.onFirework(self)
    self.fireworkLeft = 5
    self.fireworkNext = 0
    Aegis.logAction("world", "Thunder fireworks triggered")
end

function AegisPageWorld:update()
    ISPanel.update(self)
    designerTick()
    if self.fireworkLeft and self.fireworkLeft > 0 and getTimestampMs() >= self.fireworkNext then
        thunderClap()
        self.fireworkLeft = self.fireworkLeft - 1
        self.fireworkNext = getTimestampMs() + 450
    end
end

-- ------------------------------------------------------------------
-- IG date dialog: set day, month, year with minus/plus, the day clamps
-- live to the real month length (leap years included).
-- Built like the pickers in AegisWidgets, onPick(target, day, month, year)
-- ------------------------------------------------------------------
AegisDateDialog = ISPanel:derive("AegisDateDialog")

local FIELD_LABEL = { tag = "UI_Aegis_IgDay", month = "UI_Aegis_IgMonth", year = "UI_Aegis_IgYear" }

function AegisDateDialog.show(target, onPick)
    local sw, sh = getCore():getScreenWidth(), getCore():getScreenHeight()
    local o = ISPanel:new(0, 0, sw, sh)
    setmetatable(o, AegisDateDialog)
    AegisDateDialog.__index = AegisDateDialog
    o.background = true
    o.backgroundColor = { r = 0, g = 0, b = 0, a = 0.55 }
    o.borderColor = { r = 0, g = 0, b = 0, a = 0 }
    o.target = target
    o.onPick = onPick
    local gt = getGameTime()
    o.tag = gt:getDayPlusOne()
    o.month = gt:getMonth() + 1
    o.year = gt:getYear()
    o.cardW = 360
    o.cardH = 48 + 3 * 38 + 24 + 36 + 16
    o:initialise()
    o:addToUIManager()
    o:setAlwaysOnTop(true)

    local cx = math.floor((sw - o.cardW) / 2)
    local cy = math.floor((sh - o.cardH) / 2)
    local innerX = cx + 16
    local innerW = o.cardW - 32
    local y = cy + 48

    o.rows = {}
    for _, field in ipairs({ "tag", "month", "year" }) do
        local f = field
        local minus = AegisButton:new(innerX + innerW - 148, y, 28, 28, nil, "minus", o, function(panel)
            panel:nudge(f, -1)
        end)
        o:addChild(minus)
        local plus = AegisButton:new(innerX + innerW - 28, y, 28, 28, nil, "plus", o, function(panel)
            panel:nudge(f, 1)
        end)
        o:addChild(plus)
        table.insert(o.rows, { field = f, y = y })
        y = y + 38
    end
    o.hintY = y
    y = y + 24

    local hw = math.floor((innerW - 12) / 2)
    local cancel = AegisButton:new(innerX, y, hw, 36, getText("UI_Aegis_Cancel"), nil, o, AegisDateDialog.onCancel)
    o:addChild(cancel)
    local ok = AegisButton:new(innerX + hw + 12, y, hw, 36, getText("UI_Aegis_Apply"), nil, o, AegisDateDialog.onConfirm)
    ok.style = "gold"
    o:addChild(ok)
    return o
end

-- day and month wrap around, the year clamps at the edge
function AegisDateDialog:nudge(field, delta)
    local gt = getGameTime()
    if field == "tag" then
        local maxDay = gt:daysInMonth(self.year, self.month - 1)
        self.tag = self.tag + delta
        if self.tag < 1 then self.tag = maxDay end
        if self.tag > maxDay then self.tag = 1 end
    elseif field == "month" then
        self.month = self.month + delta
        if self.month < 1 then self.month = 12 end
        if self.month > 12 then self.month = 1 end
    else
        self.year = math.max(1993, math.min(2100, self.year + delta))
    end
    local maxDay = gt:daysInMonth(self.year, self.month - 1)
    if self.tag > maxDay then self.tag = maxDay end
end

function AegisDateDialog:onCancel()
    self:removeFromUIManager()
end

function AegisDateDialog:onConfirm()
    self:removeFromUIManager()
    if self.onPick then self.onPick(self.target, self.tag, self.month, self.year) end
end

function AegisDateDialog:prerender()
    ISPanel.prerender(self)
    local c = Aegis.col
    local cx = math.floor((self.width - self.cardW) / 2)
    local cy = math.floor((self.height - self.cardH) / 2)
    Aegis.shadow(self, cx, cy, self.cardW, self.cardH, 26, 0.7)
    Aegis.roundFrame(self, cx, cy, self.cardW, self.cardH, 12, 1, c.line, c.bg)
    Aegis.text(self, getText("UI_Aegis_IgDate"), cx + 16, cy + 14, UIFont.Medium, c.text)
    Aegis.textRight(self, string.format("%02d.%02d.%d", self.tag, self.month, self.year),
        cx + self.cardW - 16, cy + 14, UIFont.Medium, c.goldHi)

    local innerX = cx + 16
    local innerW = self.cardW - 32
    local ty = math.floor((28 - Aegis.fontH(UIFont.Small)) / 2)
    for _, row in ipairs(self.rows) do
        Aegis.text(self, getText(FIELD_LABEL[row.field]), innerX, row.y + ty, UIFont.Small, c.muted)
        local value
        if row.field == "tag" then
            value = string.format("%02d", self.tag)
        elseif row.field == "month" then
            -- month names come from the game's sandbox translations
            value = getText("Sandbox_StartMonth_option" .. self.month)
        else
            value = tostring(self.year)
        end
        Aegis.textCentre(self, value, innerX + innerW - 74, row.y + ty, UIFont.Small, c.text)
    end
    Aegis.text(self, getText("UI_Aegis_IgDateHint"), innerX, self.hintY, UIFont.Small, c.muted)
end

-- ------------------------------------------------------------------
-- Frame
-- ------------------------------------------------------------------

local function sectionCard(self, x, y, w, h, titleKey, icon)
    local c = Aegis.col
    Aegis.roundFrame(self, x, y, w, h, 10, 1, c.line, c.panel)
    Aegis.icon(self, icon, x + 14, y + 12, 15, 1, c.gold)
    Aegis.text(self, getText(titleKey), x + 36, y + 10, UIFont.Medium, c.text)
end

function AegisPageWorld:prerender()
    if not self.rainBottom then return end
    local c = Aegis.col
    local pad = 20

    sectionCard(self, pad, pad, self.colW, self.timeBottom - pad, "UI_Aegis_Time", "clock")
    -- refresh the IG clock once per second instead of per frame
    if not self.nextTimeAt or getTimestampMs() >= self.nextTimeAt then
        self.nextTimeAt = getTimestampMs() + 1000
        self.timeText = Aegis.fitText(igTimeText(), UIFont.Small, self.colW - 28)
    end
    Aegis.text(self, self.timeText or "", pad + 14, self.timeRowY, UIFont.Small, c.text)
    sectionCard(self, pad, self.timeBottom + 12, self.colW, self.weatherBottom - self.timeBottom - 12, "UI_Aegis_Weather", "storm")
    Aegis.text(self, getText("UI_Aegis_Duration"), pad + 14, self.timeBottom + 44, UIFont.Small, c.muted)
    Aegis.text(self, getText("UI_Aegis_StormHint"), pad + 14, self.stopBtn:getBottom() + 8, UIFont.Small, c.muted)

    local ex = pad + self.colW + 20
    sectionCard(self, ex, pad, self.colW, self.eventsBottom - pad, "UI_Aegis_Events", "bolt")
    Aegis.text(self, getText("UI_Aegis_NoiseRadius"), ex + 14, self.noiseY + 4, UIFont.Small, c.muted)

    -- instant rain card
    sectionCard(self, ex, self.rainY - 10, self.colW, self.rainBottom - self.rainY + 10, "UI_Aegis_InstantRain", "rain")
    Aegis.text(self, getText("UI_Aegis_Intensity"), ex + 14, self.rainY + 20, UIFont.Small, c.muted)

    -- weather designer card, full width below both columns
    sectionCard(self, pad, self.designerY, self.width - 2 * pad, self.designerBottom - self.designerY, "UI_Aegis_WeatherDesigner", "storm")
    for _, cell in ipairs(self.designerCells) do
        Aegis.text(self, Aegis.fitText(getText(cell.label), UIFont.Small, 54), cell.x, self.designerSliderY + 4, UIFont.Small, c.muted)
    end
    for _, chip in ipairs(self.thunderChips) do
        chip.style = (chip.chipValue == (self.thunderMinutes or 0)) and "gold" or "ghost"
    end

    -- show running weather below the events
    local sy = self.eventsBottom + 12
    local sh = 74
    Aegis.roundFrame(self, ex, sy, self.colW, sh, 10, 1, c.line, c.panel)
    local running, progress = false, 0
    local wp = getClimateManager():getWeatherPeriod()
    if wp and wp:isRunning() then
        running, progress = true, wp:getTotalProgress()
    end
    if running then
        Aegis.text(self, getText("UI_Aegis_WeatherRunning"), ex + 14, sy + 12, UIFont.Small, c.text)
        local barW = self.colW - 28
        Aegis.roundRect(self, ex + 14, sy + 42, barW, 6, 3, 1, c.line)
        Aegis.roundRect(self, ex + 14, sy + 42, math.max(6, barW * math.min(progress or 0, 1)), 6, 3, 1, c.gold)
    else
        Aegis.text(self, getText("UI_Aegis_WeatherCalm"), ex + 14, sy + 12, UIFont.Small, c.muted)
    end
end

-- the server broadcasts the absolute date after every change: the engine's
-- 10-second clock sync carries no date, without this step connected
-- clients would stay on the old calendar day
Events.OnServerCommand.Add(function(module, command, args)
    if module ~= "AegisAdmin" or command ~= "timeSync" or not args then return end
    local gt = getGameTime()
    local year, month, day = tonumber(args.year), tonumber(args.month), tonumber(args.day)
    if year and month and day then
        gt:setYear(year)
        gt:setMonth(month)
        gt:setDay(day)
    end
    -- snap the smoothed local clock: world lighting and getHour ease toward
    -- serverTimeOfDay after an admin jump, which made time changes look
    -- like nothing happened. One-shot snapping is not
    -- enough: an engine SyncClockPacket already in flight with the OLD
    -- time can land right after and throw the clock back, the race
    -- depends on packet timing. The snap is therefore held
    -- and re-applied for a short window until the engine sync carries the
    -- new time itself
    local tod = tonumber(args.tod)
    if tod then
        AegisPageWorld.timeSnap = { tod = tod, holdUntil = getTimestampMs() + 15000, nextAt = 0 }
    end
end)

local function applyTimeSnap(tod)
    -- getGameTime() can transiently return nil (state transitions,
    -- reconnects); pcall alone doesn't stop the engine from surfacing
    -- the caught exception as a popup, so guard before touching it
    local gt = getGameTime()
    if not gt then return end
    pcall(function() gt:setTimeOfDay(tod) end)
    pcall(function() gt:setLastTimeOfDay(tod) end)
    -- serverTimeOfDay/serverLastTimeOfDay/lastLastTimeOfDay are public
    -- Java fields but Kahlua exposes GameTime through methods only, no
    -- field-write metatable (bytecode check: no setServerTimeOfDay/
    -- setLastLastTimeOfDay exist either); direct assignment always threw
    -- "attempted index of non-table", silently eaten by pcall every tick
    -- while a snap was held
    local climate = getClimateManager()
    if climate then
        pcall(function() climate:forceDayInfoUpdate() end)
    end
end

Events.OnTick.Add(function()
    local snap = AegisPageWorld.timeSnap
    if not snap then return end
    local now = getTimestampMs()
    if now >= snap.holdUntil then
        AegisPageWorld.timeSnap = nil
        return
    end
    if now >= snap.nextAt then
        snap.nextAt = now + 500
        applyTimeSnap(snap.tod)
    end
end)

AegisWindow.registerPage({
    id = "world",
    icon = "world",
    label = "UI_Aegis_NavWorld",
    create = AegisPageWorld.create,
})
