-- Server: restart timer with announcements, world backup, event directing
require "Aegis/AegisWindow"
require "ISUI/ISComboBox"

local INTERVALS = { 0, 3, 6, 12, 18, 24 }

AegisPageServer = ISPanel:derive("AegisPageServer")

function AegisPageServer.create(window, x, y, w, h)
    local o = ISPanel:new(x, y, w, h)
    setmetatable(o, AegisPageServer)
    AegisPageServer.__index = AegisPageServer
    o.background = false
    o.window = window
    o.colW = math.floor((w - 60) / 2)
    o.remaining = -1
    o.statusSince = 0
    AegisPageServer.instance = o
    return o
end

function AegisPageServer:createChildren()
    local pad = 20
    local x = pad + 14
    local w = self.colW - 28

    -- restart left: pick minutes, start with confirmation
    local y = pad + 72
    local minutes = { 5, 10, 15, 30 }
    local bw = math.floor((w - 12) / 2)
    local col = 0
    for _, m in ipairs(minutes) do
        local btn = AegisButton:new(x + col * (bw + 12), y, bw, 34, m .. " min", "clock", self, function(page)
            page:startRestart(m)
        end)
        self:addChild(btn)
        col = col + 1
        if col == 2 then
            col = 0
            y = y + 42
        end
    end
    y = y + 6
    -- scheduled restart: click time and day instead of free text
    self.planDays = 0
    self.timeBtn = AegisButton:new(x, y, bw, 34, getText("UI_Aegis_RestartAtTime"), "clock", self, AegisPageServer.onTimePick)
    self:addChild(self.timeBtn)
    self.dateBtn = AegisButton:new(x + bw + 12, y, bw, 34, getText("UI_Aegis_Today"), "clock", self, AegisPageServer.onDate)
    self:addChild(self.dateBtn)
    y = y + 42
    self.planBtn = AegisButton:new(x, y, w, 34, getText("UI_Aegis_RestartPlan"), "check", self, AegisPageServer.onPlan)
    self.planBtn.style = "gold"
    self:addChild(self.planBtn)
    y = y + 42
    -- recurring rhythm: pick interval and start time, then confirm;
    -- runs server side and survives restarts
    self.intervalCombo = ISComboBox:new(x, y, w, 26, self, nil)
    self.intervalCombo:initialise()
    for _, hours in ipairs(INTERVALS) do
        if hours == 0 then
            self.intervalCombo:addOption(getText("UI_Aegis_RestartAutoOff"))
        else
            self.intervalCombo:addOption(getText("UI_Aegis_RestartAutoEvery", hours))
        end
    end
    self.intervalCombo.selected = 1
    self:addChild(self.intervalCombo)
    self.intervalY = y
    y = y + 34
    self.anchorBtn = AegisButton:new(x, y, bw, 34, getText("UI_Aegis_RestartAutoFromPick"), "clock", self, AegisPageServer.onAnchor)
    self:addChild(self.anchorBtn)
    self.autoBtn = AegisButton:new(x + bw + 12, y, bw, 34, getText("UI_Aegis_Apply"), "check", self, AegisPageServer.onAutoApply)
    self:addChild(self.autoBtn)
    y = y + 42
    self.abortBtn = AegisButton:new(x, y, w, 34, getText("UI_Aegis_RestartAbort"), "ban", self, AegisPageServer.onAbort)
    self.abortBtn.style = "danger"
    self:addChild(self.abortBtn)
    self.restartBottom = y + 34 + 18

    -- world left below: power grid, water grid, world backup.
    -- power/water hang live off the shut modifiers (no cache, takes
    -- effect immediately): -1 = off, 2147483647 = vanilla value for "never shut off"
    local sy = self.restartBottom + 42
    self.saveY = sy - 26
    self.powerToggle = AegisToggle:new(x, sy, w, 28, getText("UI_Aegis_PowerGrid"), "bolt", self, function(page, checked)
        page:setGrid("ElecShutModifier", checked)
    end)
    self:addChild(self.powerToggle)
    sy = sy + 34
    self.waterToggle = AegisToggle:new(x, sy, w, 28, getText("UI_Aegis_WaterGrid"), "rain", self, function(page, checked)
        page:setGrid("WaterShutModifier", checked)
    end)
    self:addChild(self.waterToggle)
    sy = sy + 38
    self.saveBtn = AegisButton:new(x, sy, w, 36, getText("UI_Aegis_SaveWorld"), "check", self, AegisPageServer.onSave)
    self.saveBtn.style = "gold"
    self.saveBtn.tooltip = getText("UI_Aegis_SaveWorldTooltip")
    if not isClient() then
        -- in solo the game saves itself on exit
        self.saveBtn:setEnabled(false)
    end
    self:addChild(self.saveBtn)
    self.saveBottom = sy + 36 + 14
    self:readGrids()

    -- feature switches (workshop request): the sandbox options that turn
    -- whole Aegis blocks off, right here instead of buried in a txt file.
    -- They write through the same vanilla sandbox channel the grids use
    self.featY = self.saveBottom + 12
    local fy = self.featY + 34
    self.featToggles = {}
    -- no switch for the event director: the combos are an admin tool, and
    -- keeping admins away from them is what the role rights are for (user
    -- decision). The three below change what PLAYERS can do
    local FEATURES = {
        { opt = "PlayerPanel", label = "UI_Aegis_FeatPanel", icon = "players", tip = "Sandbox_AegisPlayerPanel_tooltip" },
        { opt = "PlayerClaims", label = "UI_Aegis_FeatClaims", icon = "home", tip = "Sandbox_AegisPlayerClaims_tooltip" },
        { opt = "PlayerKits", label = "UI_Aegis_FeatKits", icon = "plus", tip = "Sandbox_AegisPlayerKits_tooltip" },
    }
    for _, def in ipairs(FEATURES) do
        local t = AegisToggle:new(x, fy, w, 28, getText(def.label), def.icon, self, function(page, checked)
            page:setFeature(def.opt, checked)
        end)
        -- hover explains what the switch does, same texts the sandbox shows
        t.tooltip = getTextOrNull(def.tip)
        t:setChecked(AegisShared.featureOn(def.opt))
        self:addChild(t)
        self.featToggles[def.opt] = t
        fy = fy + 34
    end
    self.featBottom = fy + 10

    -- directing right: button combos built from existing pieces
    local ex = pad + self.colW + 20 + 14
    local ew = self.colW - 28
    local ey = pad + 72
    local combos = {
        { label = "UI_Aegis_EventStormShow", icon = "storm", tooltip = "UI_Aegis_EventStormShowTooltip", fn = AegisPageServer.onStormShow },
        { label = "UI_Aegis_EventSiege", icon = "horde", tooltip = "UI_Aegis_EventSiegeTooltip", fn = AegisPageServer.onSiege },
        { label = "UI_Aegis_EventHeli", icon = "heli", tooltip = "UI_Aegis_EventHeliTooltip", fn = AegisPageServer.onHeliAlarm },
        { label = "UI_Aegis_EventAirdrop", icon = "heli", tooltip = "UI_Aegis_EventAirdropTooltip", fn = AegisPageServer.onAirdrop },
        { label = "UI_Aegis_EventFirestorm", icon = "storm", tooltip = "UI_Aegis_EventFirestormTooltip", fn = AegisPageServer.onFirestorm },
        { label = "UI_Aegis_EventAmbush", icon = "horde", tooltip = "UI_Aegis_EventAmbushTooltip", fn = AegisPageServer.onAmbush },
    }
    for _, def in ipairs(combos) do
        local btn = AegisButton:new(ex, ey, ew, 38, getText(def.label), def.icon, self, def.fn)
        btn.tooltip = getText(def.tooltip)
        self:addChild(btn)
        ey = ey + 46
    end
    self.directorBottom = ey + 8

    -- announcement card, right column under the director
    local ay = self.directorBottom + 12
    self.announceY = ay
    self.announceEntry = ISTextEntryBox:new("", ex, ay + 40, ew, 28)
    self.announceEntry:initialise()
    self.announceEntry:instantiate()
    self.announceEntry.font = UIFont.Small
    self.announceEntry:setPlaceholderText(getText("UI_Aegis_Announce"))
    self:addChild(self.announceEntry)
    self.announceBtn = AegisButton:new(ex, ay + 76, ew, 30, getText("UI_Aegis_AnnounceSend"), "speaker", self, AegisPageServer.onAnnounce)
    self.announceBtn.style = "gold"
    self:addChild(self.announceBtn)
    self.announceBottom = ay + 76 + 30 + 14

    -- server branding (community request): the header name of both
    -- panels. Sits in the right column next to the feature switches
    --, and yields downwards if the announcement card
    -- reaches further than the switches do
    self.brandY = math.max(self.featY, self.announceBottom + 12)
    local by = self.brandY
    self.brandEntry = ISTextEntryBox:new("", ex, by + 60, ew, 28)
    self.brandEntry:initialise()
    self.brandEntry:instantiate()
    self.brandEntry.font = UIFont.Small
    self.brandEntry:setMaxTextLength(24)
    self.brandEntry:setPlaceholderText("AEGIS")
    local current = (AegisBrand and AegisBrand.name) or ""
    if current == "" then
        -- nothing set yet: offer the public server name as a start,
        -- guarded because solo has no server options
        pcall(function()
            local v = getServerOptions():getOption("PublicName")
            if type(v) == "string" then current = v end
        end)
    end
    self.brandEntry:setText(AegisPageServer.capBrand(current))
    self:addChild(self.brandEntry)
    self.brandBtn = AegisButton:new(ex, by + 96, ew, 30, getText("UI_Aegis_Apply"), "check", self, AegisPageServer.onBrandApply)
    self.brandBtn.style = "gold"
    self:addChild(self.brandBtn)
    self.brandBottom = by + 96 + 30 + 14

    -- fixed layout, the window scrolls the page when it is shorter
    -- (see AegisWindow.switchPage)
    self.designH = math.max(self.announceBottom, self.brandBottom, self.featBottom) + pad
end

-- 24 char cap of the server side, byte safe for umlauts so the entry
-- never shows a cut open UTF-8 sequence
function AegisPageServer.capBrand(s)
    s = tostring(s or "")
    if #s <= 24 then return s end
    -- kahlua strings count UTF-16 units; only a surrogate pair can break
    -- at the cut, drop a dangling high half (same rule as the server)
    s = s:sub(1, 24)
    local b = #s > 0 and s:byte(#s) or nil
    if b and b >= 55296 and b <= 56319 then s = s:sub(1, #s - 1) end
    return s
end

-- header rename for both panels; empty text returns to AEGIS. The
-- server validates and logs, every head follows the brandSync broadcast
function AegisPageServer.onBrandApply(self)
    local text = self.brandEntry:getInternalText() or ""
    text = text:gsub("[%c|]", ""):gsub("^%s+", ""):gsub("%s+$", "")
    text = AegisPageServer.capBrand(text)
    sendClientCommand(getPlayer(), AegisShared.MODULE, "brandSet", { name = text })
    Aegis.showToast(getText("UI_Aegis_BrandTitle"))
end

-- posts a server alert into everyone's chat; the vanilla tokenizer
-- splits on unquoted spaces, so the text must travel in double quotes
-- and embedded double quotes become single quotes
function AegisPageServer.onAnnounce(self)
    local text = self.announceEntry:getInternalText() or ""
    text = text:gsub("^%s+", ""):gsub("%s+$", "")
    if text == "" then return end
    text = text:gsub('"', "'")
    -- golden fullscreen banner for everyone plus the banner's own chat
    -- line; the vanilla /servermsg red overlay was dropped on purpose
    -- (user feedback: the red floating text looked out of place)
    sendClientCommand(getPlayer(), AegisShared.MODULE, "announce", { text = text })
    self.announceEntry:setText("")
    Aegis.logAction("server", "Announcement sent: " .. text)
    Aegis.showToast(getText("UI_Aegis_AnnounceSent"))
end

function AegisPageServer:onShow()
    local p = getPlayer()
    if p then
        sendClientCommand(p, AegisShared.MODULE, "restartStatus", {})
    end
    self:readGrids()
end

-- current grid state from the live option computation
function AegisPageServer:readGrids()
    if not self.powerToggle then return end
    self.powerToggle:setChecked(getSandboxOptions():doesPowerGridExist())
    pcall(function()
        local days = getWorld():getWorldAgeDays()
        local limit = getSandboxOptions():getOptionByName("WaterShutModifier"):getValue()
        self.waterToggle:setChecked(days < limit)
    end)
end

-- toggle grid via the shut modifier; in MP through the vanilla options
-- copy with sendToServer (server persists and distributes to everyone),
-- in solo set directly plus toLua for the SandboxVars readers
function AegisPageServer:setGrid(option, on)
    local value = on and 2147483647 or -1
    if isClient() then
        local copy = SandboxOptions.new()
        copy:copyValuesFrom(getSandboxOptions())
        copy:set(option, value)
        copy:sendToServer()
    else
        getSandboxOptions():set(option, value)
        getSandboxOptions():toLua()
    end
    local grid = option == "ElecShutModifier" and "power grid" or "water grid"
    Aegis.logAction("server", grid .. (on and " turned on" or " turned off"))
    Aegis.showToast((option == "ElecShutModifier" and getText("UI_Aegis_PowerGrid") or getText("UI_Aegis_WaterGrid")))
end

-- feature switch through the same vanilla sandbox channel as the grids:
-- the server persists and distributes, every client sees the new value
function AegisPageServer:setFeature(option, on)
    if isClient() then
        local copy = SandboxOptions.new()
        copy:copyValuesFrom(getSandboxOptions())
        copy:set("AegisEvents." .. option, on == true)
        copy:sendToServer()
    else
        getSandboxOptions():set("AegisEvents." .. option, on == true)
        getSandboxOptions():toLua()
    end
    -- hold the frame sync off until the server echoes the new value,
    -- otherwise the toggle snaps back for the round trip
    self.featHold = getTimestampMs() + 3000
    Aegis.logAction("server", "Feature " .. option .. (on and " turned on" or " turned off"))
end

-- the LOCAL wall clock. The engine global getHourMinute() reads
-- java.util.Calendar.getInstance, which runs in the machine's timezone
-- (measured in the bytecode). The old path took hour and minute from the
-- UTC calendar math in AegisShared.dateParts, so every planned clock time
-- was off by the timezone: entering 00:11 restarted at 02:11 local. Falls back to the UTC parts if the global ever goes away
local function localClock()
    local h, m = nil, nil
    if getHourMinute then
        local hh, mm = tostring(getHourMinute() or ""):match("(%d+)%D+(%d+)")
        h, m = tonumber(hh), tonumber(mm)
    end
    if h and m and h >= 0 and h <= 23 and m >= 0 and m <= 59 then
        return { hour = h, min = m }
    end
    local parts = AegisShared.dateParts(AegisShared.realTime())
    return { hour = parts.hour, min = parts.min }
end

-- minutes the local clock runs ahead of UTC, from the same two clocks the
-- planners use. Sampled fresh on every call, daylight saving can flip
-- during a session
local function tzOffsetMin()
    local utc = AegisShared.dateParts(AegisShared.realTime())
    local loc = localClock()
    local diff = (loc.hour * 60 + loc.min) - (utc.hour * 60 + utc.min)
    -- midnight wrap: the two clocks can sit on different days
    if diff > 720 then diff = diff - 1440 end
    if diff < -720 then diff = diff + 1440 end
    return diff
end

function AegisPageServer:startRestart(minutes)
    AegisConfirm.show(getText("UI_Aegis_Restart"), getText("UI_Aegis_RestartConfirm", minutes),
        getText("UI_Aegis_Restart"), self, function()
            sendClientCommand(getPlayer(), AegisShared.MODULE, "restart", { minutes = minutes })
        end)
end

function AegisPageServer:planRestart(minutes, display)
    if not minutes or minutes < 1 then
        Aegis.showToast(getText("UI_Aegis_RestartPast"))
        return
    end
    if minutes > 10080 then
        Aegis.showToast(getText("UI_Aegis_RestartTooFar"))
        return
    end
    AegisConfirm.show(getText("UI_Aegis_Restart"), getText("UI_Aegis_RestartConfirmAt", display),
        getText("UI_Aegis_Restart"), self, function()
            sendClientCommand(getPlayer(), AegisShared.MODULE, "restart", { minutes = minutes })
        end)
end

function AegisPageServer.onTimePick(self)
    local now = localClock()
    AegisTimePicker.show(getText("UI_Aegis_RestartAtTime"), self, function(page, hour, minute)
        page.planHour, page.planMinute = hour, minute
        page.timeBtn.label = AegisTimePicker.format(hour, minute)
    end, self.planHour or now.hour, self.planMinute or now.min)
end

function AegisPageServer.onDate(self)
    AegisDatePicker.show(getText("UI_Aegis_RestartAtDate"), self, function(page, days, display)
        page.planDays = days
        page.dateBtn.label = display
    end, 7)
end

function AegisPageServer.onPlan(self)
    if not self.planHour then
        Aegis.showToast(getText("UI_Aegis_RestartPickTime"))
        return
    end
    local now = localClock()
    local dayDiff = (self.planHour - now.hour) * 60 + (self.planMinute - now.min)
    local days = self.planDays
    local dayLabel = AegisDatePicker.tagText(days)
    -- a time already past today means its next occurrence
    if days == 0 and dayDiff <= 0 then
        days = 1
        dayLabel = getText("UI_Aegis_Tomorrow")
    end
    self:planRestart(days * 1440 + dayDiff,
        dayLabel .. " " .. AegisTimePicker.format(self.planHour, self.planMinute))
end

function AegisPageServer.onAbort(self)
    sendClientCommand(getPlayer(), AegisShared.MODULE, "restart", { cancel = true })
end

function AegisPageServer.onAnchor(self)
    local now = localClock()
    AegisTimePicker.show(getText("UI_Aegis_RestartAutoFromPick"), self, function(page, hour, minute)
        page.anchorHour, page.anchorMinute = hour, minute
        page.anchorBtn.label = getText("UI_Aegis_RestartAutoFrom", AegisTimePicker.format(hour, minute))
    end, self.anchorHour or now.hour, self.anchorMinute or now.min)
end

function AegisPageServer.onAutoApply(self)
    local hours = INTERVALS[self.intervalCombo.selected or 1] or 0
    local args = { hours = hours }
    if hours > 0 then
        if not self.anchorHour then
            Aegis.showToast(getText("UI_Aegis_RestartPickTime"))
            return
        end
        -- first slot: next occurrence of the anchor time, or an earlier
        -- interval step before it if one falls in between
        local now = localClock()
        local startIn = (self.anchorHour - now.hour) * 60 + (self.anchorMinute - now.min)
        if startIn <= 0 then startIn = startIn + 1440 end
        while startIn - hours * 60 > 0 do startIn = startIn - hours * 60 end
        args.startIn = startIn
    end
    sendClientCommand(getPlayer(), AegisShared.MODULE, "restartInterval", args)
    Aegis.showToast(hours == 0 and getText("UI_Aegis_RestartAutoOff") or getText("UI_Aegis_RestartAutoEvery", hours))
end

function AegisPageServer.onSave(self)
    if isClient() then
        SendCommandToServer("/save")
        Aegis.logAction("server", "World save requested")
        Aegis.showToast(getText("UI_Aegis_SaveWorld"))
    end
end

-- ---------- director combos, all knobs from the sandbox ----------

local function eventValue(name, default)
    local value = SandboxVars and SandboxVars.AegisEvents and SandboxVars.AegisEvents[name]
    if value ~= nil then return value end
    return default
end

function AegisPageServer.onStormShow(self)
    local duration = tonumber(eventValue("StormHours", 8)) or 8
    local cm = getClimateManager()
    if isClient() then
        cm:transmitTriggerStorm(duration)
    else
        cm:triggerCustomWeatherStage(WeatherPeriod.STAGE_STORM, duration)
    end
    pcall(function() AegisPageWorld.weatherKick("STAGE_STORM") end)
    -- thunder volley via own tick in update
    self.thunderLeft = tonumber(eventValue("StormThunder", 6)) or 6
    self.thunderInterval = math.floor((tonumber(eventValue("StormThunderGap", 1.2)) or 1.2) * 1000)
    self.thunderNextAt = getTimestampMs() + self.thunderInterval
    Aegis.logAction("server", "Event triggered: storm show")
    Aegis.showToast(getText("UI_Aegis_EventStormShow"))
end

function AegisPageServer.onSiege(self)
    local p = getPlayer()
    if not p then return end
    local waves = tonumber(eventValue("SiegeWaves", 3)) or 3
    local count = tonumber(eventValue("SiegeCount", 40)) or 40
    local dist = tonumber(eventValue("SiegeDistance", 60)) or 60
    local gap = tonumber(eventValue("SiegeGap", 12)) or 12
    for i = 1, waves do
        sendClientCommand(p, AegisShared.MODULE, "horde", {
            x = math.floor(p:getX()), y = math.floor(p:getY()), z = math.floor(p:getZ()),
            count = count,
            radius = tonumber(eventValue("SiegeRadius", 10)) or 10,
            dist = dist + (i - 1) * gap,
            sprinter = eventValue("SiegeSprinters", false) == true,
            crawler = eventValue("SiegeCrawlers", false) == true,
            lureMinutes = tonumber(eventValue("SiegeLureMinutes", 5)) or 5,
        })
    end
    if eventValue("SiegeGunshot", true) == true then
        if isClient() then
            SendCommandToServer("/gunshot")
        else
            pcall(function() getAmbientStreamManager():doGunEvent() end)
        end
    end
    Aegis.logAction("server", "Event triggered: siege (" .. waves .. " horde waves)")
    Aegis.showToast(getText("UI_Aegis_EventSiege"))
end

function AegisPageServer.onHeliAlarm(self)
    local p = getPlayer()
    if not p then return end
    if isClient() then
        SendCommandToServer("/chopper")
    else
        testHelicopter()
    end
    local count = tonumber(eventValue("HeliCount", 15)) or 15
    if count > 0 then
        sendClientCommand(p, AegisShared.MODULE, "horde", {
            x = math.floor(p:getX()), y = math.floor(p:getY()), z = math.floor(p:getZ()),
            count = count,
            radius = tonumber(eventValue("HeliRadius", 8)) or 8,
            dist = tonumber(eventValue("HeliDistance", 80)) or 80,
        })
    end
    Aegis.logAction("server", "Event triggered: heli alert")
    Aegis.showToast(getText("UI_Aegis_EventHeli"))
end

function AegisPageServer.onAirdrop(self)
    local p = getPlayer()
    if not p then return end
    if isClient() then
        SendCommandToServer("/chopper")
    else
        testHelicopter()
    end
    sendClientCommand(p, AegisShared.MODULE, "horde", {
        x = math.floor(p:getX()), y = math.floor(p:getY()), z = math.floor(p:getZ()),
        count = tonumber(eventValue("AirdropCount", 20)) or 20,
        radius = tonumber(eventValue("AirdropRadius", 10)) or 10,
        paratrooper = true,
        height = tonumber(eventValue("AirdropHeight", 5)) or 5,
    })
    Aegis.logAction("server", "Event triggered: airdrop")
    Aegis.showToast(getText("UI_Aegis_EventAirdrop"))
end

function AegisPageServer.onFirestorm(self)
    local p = getPlayer()
    if not p then return end
    local duration = tonumber(eventValue("FirestormHours", 6)) or 6
    local cm = getClimateManager()
    if isClient() then
        cm:transmitTriggerStorm(duration)
    else
        cm:triggerCustomWeatherStage(WeatherPeriod.STAGE_STORM, duration)
    end
    pcall(function() AegisPageWorld.weatherKick("STAGE_STORM") end)
    self.thunderLeft = tonumber(eventValue("FirestormThunder", 4)) or 4
    self.thunderInterval = 1200
    self.thunderNextAt = getTimestampMs() + self.thunderInterval
    -- each horde call picks its own random direction, several calls
    -- means burning groups closing in from several sides
    local waves = tonumber(eventValue("FirestormWaves", 3)) or 3
    for _ = 1, waves do
        sendClientCommand(p, AegisShared.MODULE, "horde", {
            x = math.floor(p:getX()), y = math.floor(p:getY()), z = math.floor(p:getZ()),
            count = tonumber(eventValue("FirestormCount", 15)) or 15,
            radius = 8,
            onFire = true,
            dist = tonumber(eventValue("FirestormDistance", 50)) or 50,
            lureMinutes = 5,
        })
    end
    Aegis.logAction("server", "Event triggered: firestorm")
    Aegis.showToast(getText("UI_Aegis_EventFirestorm"))
end

function AegisPageServer.onAmbush(self)
    local p = getPlayer()
    if not p then return end
    if eventValue("AmbushRain", true) == true then
        if isClient() then
            SendCommandToServer("/startrain")
        end
    end
    sendClientCommand(p, AegisShared.MODULE, "horde", {
        x = math.floor(p:getX()), y = math.floor(p:getY()), z = math.floor(p:getZ()),
        count = tonumber(eventValue("AmbushCount", 25)) or 25,
        radius = tonumber(eventValue("AmbushRadius", 6)) or 6,
        crawler = true,
    })
    Aegis.logAction("server", "Event triggered: crawler ambush")
    Aegis.showToast(getText("UI_Aegis_EventAmbush"))
end

function AegisPageServer:update()
    ISPanel.update(self)
    if self.thunderLeft and self.thunderLeft > 0 and getTimestampMs() >= (self.thunderNextAt or 0) then
        local p = getPlayer()
        if p then
            sendClientCommand(p, "event", "thunder", { x = p:getX(), y = p:getY(), isAll = false })
        end
        self.thunderLeft = self.thunderLeft - 1
        self.thunderNextAt = getTimestampMs() + (self.thunderInterval or 1200)
    end
end

function AegisPageServer:receiveStatus(remaining, intHours, intNext)
    self.remaining = tonumber(remaining) or -1
    self.statusSince = getTimestampMs()
    local hours = tonumber(intHours) or 0
    if self.intervalCombo then
        for i, value in ipairs(INTERVALS) do
            if value == hours then
                self.intervalCombo.selected = i
                break
            end
        end
    end
    -- anchor button mirrors the server's next automatic slot, shown in
    -- the admin's local clock (the epoch is timezone free, only the
    -- display needs the shift)
    intNext = tonumber(intNext) or 0
    if self.anchorBtn and hours > 0 and intNext > 0 then
        local t = AegisShared.dateParts(intNext + tzOffsetMin() * 60)
        self.anchorHour, self.anchorMinute = t.hour, t.min
        self.anchorBtn.label = getText("UI_Aegis_RestartAutoFrom", AegisTimePicker.format(t.hour, t.min))
    end
end

function AegisPageServer:prerender()
    if not self.directorBottom then return end
    local c = Aegis.col
    local pad = 20
    local x = pad + 14

    Aegis.roundFrame(self, pad, pad, self.colW, self.restartBottom - pad, 10, 1, c.line, c.panel)
    Aegis.icon(self, "clock", pad + 14, pad + 12, 15, 1, c.gold)
    Aegis.text(self, getText("UI_Aegis_Restart"), pad + 36, pad + 10, UIFont.Medium, c.text)
    local status = getText("UI_Aegis_RestartNone")
    local color = c.muted
    if self.remaining >= 0 then
        local elapsed = math.floor((getTimestampMs() - self.statusSince) / 1000)
        local remaining = math.max(0, self.remaining - elapsed)
        local clock
        if remaining >= 3600 then
            clock = math.floor(remaining / 3600) .. ":" .. string.format("%02d:%02d", math.floor((remaining % 3600) / 60), remaining % 60)
        else
            clock = math.floor(remaining / 60) .. ":" .. string.format("%02d", remaining % 60)
        end
        status = getText("UI_Aegis_RestartIn") .. " " .. clock
        color = c.goldHi
    end
    Aegis.text(self, status, x, pad + 40, UIFont.Small, color)

    Aegis.roundFrame(self, pad, self.saveY - 10, self.colW, self.saveBottom - self.saveY + 10, 10, 1, c.line, c.panel)
    Aegis.icon(self, "check", pad + 14, self.saveY + 2, 15, 1, c.gold)
    Aegis.text(self, getText("UI_Aegis_NavWorld"), pad + 36, self.saveY, UIFont.Medium, c.text)

    -- feature switch card: state follows the sandbox truth every frame,
    -- someone else may have flipped an option in the meantime; the event
    -- combos grey out with their switch
    Aegis.roundFrame(self, pad, self.featY, self.colW, self.featBottom - self.featY, 10, 1, c.line, c.panel)
    Aegis.icon(self, "gear", pad + 14, self.featY + 12, 15, 1, c.gold)
    Aegis.text(self, getText("UI_Aegis_CardFeatures"), pad + 36, self.featY + 10, UIFont.Medium, c.text)
    if getTimestampMs() > (self.featHold or 0) then
        for opt, t in pairs(self.featToggles or {}) do
            t:setChecked(AegisShared.featureOn(opt))
        end
    end
    local ex = pad + self.colW + 20
    -- branding card, right column next to the feature switches
    Aegis.roundFrame(self, ex, self.brandY, self.colW, self.brandBottom - self.brandY, 10, 1, c.line, c.panel)
    Aegis.icon(self, "crown", ex + 14, self.brandY + 12, 15, 1, c.gold)
    Aegis.text(self, getText("UI_Aegis_BrandTitle"), ex + 36, self.brandY + 10, UIFont.Medium, c.text)
    Aegis.text(self, Aegis.fitText(getText("UI_Aegis_BrandHint"), UIFont.Small, self.colW - 28),
        ex + 14, self.brandY + 36, UIFont.Small, c.muted)

    Aegis.roundFrame(self, ex, pad, self.colW, self.directorBottom - pad, 10, 1, c.line, c.panel)
    Aegis.icon(self, "bolt", ex + 14, pad + 12, 15, 1, c.gold)
    Aegis.text(self, getText("UI_Aegis_Director"), ex + 36, pad + 10, UIFont.Medium, c.text)
    Aegis.text(self, getText("UI_Aegis_DirectorHint"), ex + 14, pad + 40, UIFont.Small, c.muted)

    Aegis.roundFrame(self, ex, self.announceY, self.colW, self.announceBottom - self.announceY, 10, 1, c.line, c.panel)
    Aegis.icon(self, "speaker", ex + 14, self.announceY + 12, 15, 1, c.gold)
    Aegis.text(self, getText("UI_Aegis_Announce"), ex + 36, self.announceY + 10, UIFont.Medium, c.text)
end

-- server replies, in solo via the same event path
Events.OnServerCommand.Add(function(module, command, args)
    if module ~= "AegisAdmin" then return end
    if command == "restartStatus" then
        local page = AegisPageServer.instance
        if page and args then page:receiveStatus(args.remaining, args.intHours, args.intNext) end
    end
end)

AegisWindow.registerPage({
    id = "server",
    icon = "gear",
    label = "UI_Aegis_NavServer",
    create = AegisPageServer.create,
})
