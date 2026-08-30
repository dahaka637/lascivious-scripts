-- Player panel pages: overview, statistics, safehouse, distress call
require "Aegis/AegisTheme"
require "Aegis/AegisWidgets"
require "Aegis/AegisPlayerCore"
require "Aegis/AegisPlayerWindow"
require "ISUI/ISUI3DModel"
require "ISUI/ISTextEntryBox"

local MODULE = "AegisPlayer"
-- lost request self healing: pages re ask a few times, then stop
local TRY_MAX = 5
local RETRY_MS = 3000

-- section card in the blue palette (pattern from the dashboard cards)
local function card(el, x, y, w, h, titleKey, icon)
    local c = AegisPlayerCol
    Aegis.roundFrame(el, x, y, w, h, 10, 1, c.line, c.panel)
    if titleKey then
        Aegis.icon(el, icon, x + 14, y + 12, 15, 1, c.accent)
        Aegis.text(el, getText(titleKey), x + 36, y + 10, UIFont.Medium, c.text)
    end
end

-- ==================================================================
-- Overview: own character in 3D plus the values readable client side
-- ==================================================================
AegisPlayerPageMe = ISPanel:derive("AegisPlayerPageMe")
AegisPlayerPageMe.instance = nil

function AegisPlayerPageMe.create(window, x, y, w, h)
    local o = ISPanel:new(x, y, w, h)
    setmetatable(o, AegisPlayerPageMe)
    AegisPlayerPageMe.__index = AegisPlayerPageMe
    o.background = false
    o.window = window
    o.data = {}
    o.nextRefresh = 0
    AegisPlayerPageMe.instance = o
    return o
end

function AegisPlayerPageMe:createChildren()
    -- vanilla model widget, mouse drag rotates the figure by itself
    self.model = ISUI3DModel:new(20 + 60, 20 + 70, 120, 200)
    self.model:setVisible(false)
    self:addChild(self.model)
end

function AegisPlayerPageMe:bindModel()
    local p = getPlayer()
    if not p then return end
    self.model:setState("idle")
    self.model:setDirection(IsoDirections.S)
    self.model:setIsometric(false)
    self.model:setCharacter(p)
    self.model:setVisible(true)
end

function AegisPlayerPageMe:refresh()
    local p = getPlayer()
    if not p then return end
    local d = {}
    local desc = p:getDescriptor()
    if desc then d.name = desc:getForename() .. " " .. desc:getSurname() end
    d.username = p:getUsername()
    d.survived = p:getTimeSurvived()
    d.kills = p:getZombieKills()
    local nut = p:getNutrition()
    if nut then d.weight = math.floor(nut:getWeight() * 10 + 0.5) / 10 end
    -- favourite weapon: highest "Fav:" counter in modData (vanilla pattern,
    -- ISCharacterScreen.loadFavouriteWeapon)
    local best, swing = nil, 0
    for k, v in pairs(p:getModData()) do
        if type(k) == "string" and type(v) == "number" then
            local name = string.match(k, "^Fav:(.+)")
            if name and v > swing then
                best, swing = name, v
            end
        end
    end
    d.favWeapon = best
    -- six strongest skills
    d.perks = {}
    for i = 0, PerkFactory.PerkList:size() - 1 do
        local perk = PerkFactory.PerkList:get(i)
        local level = p:getPerkLevel(perk)
        if level and level > 0 then
            table.insert(d.perks, { name = perk:getName(), level = level })
        end
    end
    table.sort(d.perks, function(a, b) return a.level > b.level end)
    while #d.perks > 6 do table.remove(d.perks) end
    self.data = d
end

function AegisPlayerPageMe:onShow()
    self:bindModel()
    self:refresh()
    self.nextRefresh = getTimestampMs() + 2000
end

function AegisPlayerPageMe:update()
    ISPanel.update(self)
    if not self:isVisible() then return end
    local now = getTimestampMs()
    if now >= self.nextRefresh then
        self.nextRefresh = now + 2000
        self:refresh()
    end
end

function AegisPlayerPageMe:prerender()
    local c = AegisPlayerCol
    local d = self.data or {}
    local pad = 20
    local lw = 240

    -- left: the character
    card(self, pad, pad, lw, self.height - pad * 2, nil, nil)
    local nameY = pad + 300
    Aegis.textCentre(self, Aegis.fitText(d.name or "", UIFont.Medium, lw - 24),
        pad + math.floor(lw / 2), nameY, UIFont.Medium, c.text)
    if d.username and d.username ~= d.name then
        Aegis.textCentre(self, Aegis.fitText(d.username, UIFont.Small, lw - 24),
            pad + math.floor(lw / 2), nameY + Aegis.fontH(UIFont.Medium) + 2, UIFont.Small, c.muted)
    end

    -- right: vitals
    local rx = pad + lw + 20
    local rw = self.width - rx - pad
    card(self, rx, pad, rw, 180, "UI_AegisPlayer_MeStats", "players")
    local cellW = math.floor((rw - 32) / 2)
    local rows = {
        { label = "UI_AegisPlayer_Survived", value = d.survived },
        { label = "UI_AegisPlayer_ZombieKills", value = d.kills },
        { label = "UI_AegisPlayer_Weight", value = d.weight and (tostring(d.weight) .. " kg") or nil },
        { label = "UI_AegisPlayer_FavWeapon", value = d.favWeapon or getText("UI_AegisPlayer_None") },
    }
    for i, row in ipairs(rows) do
        local col = (i - 1) % 2
        local line = math.floor((i - 1) / 2)
        local xx = rx + 16 + col * cellW
        local yy = pad + 48 + line * 62
        Aegis.text(self, getText(row.label), xx, yy, UIFont.Small, c.muted)
        Aegis.text(self, Aegis.fitText(tostring(row.value or "--"), UIFont.Medium, cellW - 12),
            xx, yy + 18, UIFont.Medium, c.text)
    end

    -- strongest skills with a small level bar
    local py = pad + 192
    local ph = self.height - py - pad
    card(self, rx, py, rw, ph, "UI_AegisPlayer_Perks", "gear")
    local perks = d.perks or {}
    if #perks == 0 then
        Aegis.textCentre(self, getText("UI_AegisPlayer_PerksEmpty"),
            rx + math.floor(rw / 2), py + math.floor(ph / 2) - 8, UIFont.Small, c.muted)
    else
        local yy = py + 44
        for _, perk in ipairs(perks) do
            Aegis.text(self, Aegis.fitText(perk.name, UIFont.Small, 150), rx + 16, yy, UIFont.Small, c.text)
            local barX = rx + 180
            local barW = rw - 180 - 56
            Aegis.roundRect(self, barX, yy + 5, barW, 6, 3, 1, c.line)
            local frac = math.min(1, (perk.level or 0) / 10)
            if frac > 0 then
                Aegis.roundRect(self, barX, yy + 5, math.max(4, math.floor(barW * frac)), 6, 3, 1, c.accent)
            end
            Aegis.textRight(self, tostring(perk.level), rx + rw - 16, yy - 2, UIFont.Medium, c.accentHi)
            yy = yy + 42
        end
    end
end

-- ==================================================================
-- Statistics: server side counters plus the server wide top list
-- ==================================================================
AegisPlayerPageStats = ISPanel:derive("AegisPlayerPageStats")
AegisPlayerPageStats.instance = nil

-- kind strings are the SERVER vocabulary (Aegis_PlayerPanel TOP_KINDS),
-- the first build used the ledger field names and every
-- request was silently dropped
local TOP_KINDS = {
    { kind = "kills", label = "UI_AegisPlayer_ZombieKills" },
    { kind = "dist", label = "UI_AegisPlayer_StatDist" },
    { kind = "deaths", label = "UI_AegisPlayer_StatDeaths" },
    { kind = "best", label = "UI_AegisPlayer_StatBestHours" },
}

local function fmtKind(kind, v)
    if kind == "dist" or kind == "distM" then return string.format("%.1f km", (v or 0) / 1000) end
    if kind == "best" or kind == "bestHours" then return string.format("%.1f h", v or 0) end
    return tostring(math.floor((v or 0) + 0.5))
end

function AegisPlayerPageStats.create(window, x, y, w, h)
    local o = ISPanel:new(x, y, w, h)
    setmetatable(o, AegisPlayerPageStats)
    AegisPlayerPageStats.__index = AegisPlayerPageStats
    o.background = false
    o.window = window
    o.stats = nil
    o.top = nil
    o.topKind = "kills"
    o.statsWant = false
    o.statsTries = 0
    o.statsNext = 0
    o.topWant = false
    o.topTries = 0
    o.topNext = 0
    o.topY = 192
    AegisPlayerPageStats.instance = o
    return o
end

function AegisPlayerPageStats:createChildren()
    local pad = 20
    local cardW = self.width - pad * 2
    self.chips = {}
    local bw = math.floor((cardW - 32 - 3 * 8) / 4)
    local bx = pad + 16
    for _, def in ipairs(TOP_KINDS) do
        local btn = AegisButton:new(bx, self.topY + 36, bw, 26, getText(def.label), nil, self, AegisPlayerPageStats.onChip)
        btn.kind = def.kind
        btn.radius = 13
        self:addChild(btn)
        table.insert(self.chips, btn)
        bx = bx + bw + 8
    end
end

function AegisPlayerPageStats.onChip(self, btn)
    if btn.kind == self.topKind then return end
    self.topKind = btn.kind
    self.top = nil
    self.topWant = true
    self.topTries = 0
    self.topNext = 0
end

function AegisPlayerPageStats:onShow()
    self.statsWant = true
    self.statsTries = 0
    self.statsNext = 0
    self.topWant = true
    self.topTries = 0
    self.topNext = 0
end

function AegisPlayerPageStats:update()
    ISPanel.update(self)
    if not self:isVisible() then return end
    local p = getPlayer()
    if not p then return end
    local now = getTimestampMs()
    if self.statsWant and self.statsTries < TRY_MAX and now >= self.statsNext then
        self.statsTries = self.statsTries + 1
        self.statsNext = now + RETRY_MS
        sendClientCommand(p, MODULE, "statsReq", {})
    end
    if self.topWant and self.topTries < TRY_MAX and now >= self.topNext then
        self.topTries = self.topTries + 1
        self.topNext = now + RETRY_MS
        sendClientCommand(p, MODULE, "topReq", { kind = self.topKind })
    end
end

function AegisPlayerPageStats:onStatsSync(args)
    if type(args) ~= "table" then return end
    self.statsWant = false
    self.stats = {
        deaths = tonumber(args.deaths) or 0,
        zkills = tonumber(args.zkills) or 0,
        bandits = tonumber(args.bandits) or 0,
        distM = tonumber(args.distM) or 0,
        bestHours = tonumber(args.bestHours) or 0,
        bestKills = tonumber(args.bestKills) or 0,
        playtimeH = tonumber(args.playtimeH) or 0,
    }
end

function AegisPlayerPageStats:onTopSync(args)
    if type(args) ~= "table" then return end
    local kind = tostring(args.kind or "")
    -- a late reply for a chip the player already left is dropped
    if kind ~= self.topKind then return end
    self.topWant = false
    local tmp = {}
    -- server payload: entries = { { user, value, kills? }, ... }
    if type(args.entries) == "table" then
        -- the net layer does not guarantee array keys, rebuild the order
        for k, e in pairs(args.entries) do
            local idx = tonumber(k)
            if idx and type(e) == "table" then
                table.insert(tmp, { idx = idx, name = tostring(e.user or "?"), value = tonumber(e.value) or 0 })
            end
        end
    end
    table.sort(tmp, function(a, b) return a.idx < b.idx end)
    local rows = {}
    for _, e in ipairs(tmp) do
        if #rows < 10 then
            table.insert(rows, { name = e.name, value = e.value })
        end
    end
    self.top = { kind = kind, rows = rows }
end

function AegisPlayerPageStats:prerender()
    local c = AegisPlayerCol
    local s = self.stats
    local pad = 20
    local gap = 12
    local w = self.width

    local defs1 = {
        { label = "UI_AegisPlayer_StatDeaths", v = s and tostring(s.deaths) },
        { label = "UI_AegisPlayer_ZombieKills", v = s and tostring(s.zkills) },
        { label = "UI_AegisPlayer_StatBandits", v = s and tostring(s.bandits) },
        { label = "UI_AegisPlayer_StatDist", v = s and fmtKind("distM", s.distM) },
    }
    local defs2 = {
        { label = "UI_AegisPlayer_StatBestHours", v = s and fmtKind("bestHours", s.bestHours) },
        { label = "UI_AegisPlayer_StatBestKills", v = s and tostring(s.bestKills) },
        { label = "UI_AegisPlayer_StatPlaytime", v = s and (tostring(math.floor(s.playtimeH + 0.5)) .. " h") },
    }
    local function drawRow(defs, y, cw)
        local x = pad
        for _, def in ipairs(defs) do
            Aegis.roundFrame(self, x, y, cw, 74, 10, 1, c.line, c.panel)
            Aegis.text(self, getText(def.label), x + 14, y + 10, UIFont.Small, c.muted)
            Aegis.text(self, def.v or "--", x + 14, y + 32, UIFont.Large, c.text)
            x = x + cw + gap
        end
    end
    drawRow(defs1, pad, math.floor((w - pad * 2 - gap * 3) / 4))
    drawRow(defs2, pad + 86, math.floor((w - pad * 2 - gap * 2) / 3))

    -- top list card with the category chips
    local ty = self.topY
    local th = self.height - ty - pad
    card(self, pad, ty, w - pad * 2, th, "UI_AegisPlayer_Top10", "crown")
    for _, chip in ipairs(self.chips) do
        if chip.kind == self.topKind then
            Aegis.roundRect(self, chip.x, chip.y + chip.height + 3, chip.width, 3, 1, 1, c.accent)
        end
    end

    local rowsY = ty + 80
    local rows = self.top and self.top.rows
    if not rows then
        Aegis.textCentre(self, getText("UI_AegisPlayer_Waiting"), math.floor(w / 2), rowsY + 20, UIFont.Small, c.muted)
    elseif #rows == 0 then
        Aegis.textCentre(self, getText("UI_AegisPlayer_TopEmpty"), math.floor(w / 2), rowsY + 20, UIFont.Small, c.muted)
    else
        local p = getPlayer()
        local me = p and p:getUsername()
        for i, row in ipairs(rows) do
            local yy = rowsY + (i - 1) * 26
            local mine = row.name == me
            if mine then
                Aegis.roundRect(self, pad + 10, yy - 3, w - pad * 2 - 20, 24, 6, 0.35, c.accentDim)
            end
            Aegis.text(self, tostring(i) .. ".", pad + 20, yy, UIFont.Small, mine and c.accentHi or c.muted)
            Aegis.text(self, Aegis.fitText(row.name, UIFont.Small, w - pad * 2 - 160),
                pad + 48, yy, UIFont.Small, mine and c.accentHi or c.text)
            Aegis.textRight(self, fmtKind(self.top.kind, row.value),
                w - pad - 16, yy, UIFont.Small, mine and c.accentHi or c.text)
        end
    end
end

-- ==================================================================
-- Safehouse: own zone from the client side list, decay from the server
-- ==================================================================
AegisPlayerPageSafehouse = ISPanel:derive("AegisPlayerPageSafehouse")
AegisPlayerPageSafehouse.instance = nil

-- distance to the zone centre, same math and the same compass keys as the
-- vehicles page
local SH_COMPASS = {
    "UI_AegisPlayer_CompassN", "UI_AegisPlayer_CompassNE",
    "UI_AegisPlayer_CompassE", "UI_AegisPlayer_CompassSE",
    "UI_AegisPlayer_CompassS", "UI_AegisPlayer_CompassSW",
    "UI_AegisPlayer_CompassW", "UI_AegisPlayer_CompassNW",
}

local function shDistLine(sh)
    if not sh.x or not sh.y then return nil end
    local p = getPlayer()
    if not p then return nil end
    local dx = (sh.x + (sh.w or 0) / 2) - p:getX()
    local dy = (sh.y + (sh.h or 0) / 2) - p:getY()
    local dist = math.sqrt(dx * dx + dy * dy)
    local bearing = math.deg(math.atan2(dx, -dy))
    if bearing < 0 then bearing = bearing + 360 end
    local sector = math.floor((bearing + 22.5) / 45) % 8 + 1
    return string.format("%d m %s", math.floor(dist + 0.5), getText(SH_COMPASS[sector]))
end

function AegisPlayerPageSafehouse.create(window, x, y, w, h)
    local o = ISPanel:new(x, y, w, h)
    setmetatable(o, AegisPlayerPageSafehouse)
    AegisPlayerPageSafehouse.__index = AegisPlayerPageSafehouse
    o.background = false
    o.window = window
    o.sh = nil
    o.days = nil
    o.shWant = false
    o.shTries = 0
    o.shNext = 0
    o.scanNext = 0
    AegisPlayerPageSafehouse.instance = o
    return o
end

-- respawn in the safehouse: the vanilla feature behind the vanilla server
-- option. Set through the Aegis server, NOT through the vanilla client
-- call: that one needs the zone OBJECT out of the local list, and a zone
-- another mod registers server side does not have to be in that copy, so
-- the switch quietly vanished exactly where it mattered.
-- The label reuses the vanilla translation key, all thirteen languages
-- come for free
function AegisPlayerPageSafehouse:createChildren()
    local pad = 20
    self.respawnToggle = AegisToggle:new(pad + 12, pad + 148, self.width - pad * 2 - 24, 26,
        getText("IGUI_SafehouseUI_Respawn"), nil, self, function(page, checked)
            -- optimistic hold, featHold pattern: without it the next sync
            -- yanks the switch back for the round trip
            page.respawnHold = getTimestampMs() + 4000
            local p = getPlayer()
            if p then
                sendClientCommand(p, MODULE, "shRespawn", { on = checked == true })
            end
        end)
    self.respawnToggle:setVisible(false)
    self:addChild(self.respawnToggle)
end

-- fallback only. The local list is not the truth: a zone that another mod
-- registers server side does not have to be in this client's copy, and
-- that is exactly why a fresh claim showed up in gold and not here. The
-- server answer of shInfoReq wins, this runs until it arrives and in solo
function AegisPlayerPageSafehouse:scan()
    if self.shKnown then return end
    local p = getPlayer()
    local me = p and p:getUsername()
    if not me then return end
    local found = nil
    local list = SafeHouse.getSafehouseList()
    if list then
        for i = 0, list:size() - 1 do
            local sh = list:get(i)
            if sh then
                local owner = tostring(sh:getOwner() or "")
                local mine = owner == me
                local names = {}
                local pl = sh:getPlayers()
                if pl then
                    for j = 0, pl:size() - 1 do
                        local n = tostring(pl:get(j))
                        if n ~= owner then table.insert(names, n) end
                        if n == me then mine = true end
                    end
                end
                if mine then
                    table.insert(names, 1, owner)
                    local rec = { owner = owner, members = names, title = "", w = 0, h = 0 }
                    rec.w = sh:getW()
                    rec.h = sh:getH()
                    rec.x = sh:getX()
                    rec.y = sh:getY()
                    rec.title = tostring(sh:getTitle() or "")
                    found = rec
                    break
                end
            end
        end
    end
    self.sh = found
end

function AegisPlayerPageSafehouse:onShow()
    self:scan()
    self.scanNext = getTimestampMs() + 5000
    self.shWant = true
    self.shTries = 0
    self.shNext = 0
end

-- keep asking while the page is open: a claim taken during the session has
-- to land here on its own, nobody reopens the page to find out
local SH_REFRESH = 10000

function AegisPlayerPageSafehouse:update()
    ISPanel.update(self)
    if not self:isVisible() then return end
    local now = getTimestampMs()
    if now >= self.scanNext then
        self.scanNext = now + 5000
        self:scan()
    end
    local p = getPlayer()
    if not p then return end
    if self.shWant and self.shTries < TRY_MAX and now >= self.shNext then
        self.shTries = self.shTries + 1
        self.shNext = now + RETRY_MS
        sendClientCommand(p, MODULE, "shInfoReq", {})
    elseif not self.shWant and now >= (self.shRefresh or 0) then
        self.shRefresh = now + SH_REFRESH
        sendClientCommand(p, MODULE, "shInfoReq", {})
    end
    -- respawn switch: state and permission both come with shInfoSync, the
    -- local zone copy plays no part anymore (it does not have to contain
    -- a server-registered zone, which is why the switch used to vanish).
    -- Never adopt the state during the optimistic hold after a click
    if self.respawnToggle and now >= (self.respawnNext or 0) then
        self.respawnNext = now + 1000
        local show = isClient() and self.sh ~= nil and self.respawnAllowed == true
        if show and self.respawnSynced ~= nil
            and (not self.respawnHold or now >= self.respawnHold) then
            self.respawnToggle.checked = self.respawnSynced
        end
        self.respawnToggle:setVisible(show)
    end
end

-- the gold distance line toggles the screen navi towards the zone
-- centre, same pointer the vehicles page uses
function AegisPlayerPageSafehouse:onMouseDown(x, y)
    local r = self.naviRect
    if r and self.sh and self.sh.x
        and x >= r.x and x <= r.x + r.w and y >= r.y and y <= r.y + r.h then
        local t = AegisPlayerVehNavi and AegisPlayerVehNavi.target
        if t and t.home then
            AegisPlayerVehNavi.stop()
        else
            local sh = self.sh
            local title = sh.title ~= "" and sh.title or sh.owner
            AegisPlayerVehNavi.start({
                id = "aegis-home", home = true, name = title,
                x = math.floor(sh.x + (sh.w or 0) / 2),
                y = math.floor(sh.y + (sh.h or 0) / 2),
            })
            -- start() reads the name through the vehicle translation,
            -- for the home target the raw title is already right
            if AegisPlayerVehNavi.target then
                AegisPlayerVehNavi.target.home = true
                AegisPlayerVehNavi.target.name = title
            end
        end
        return true
    end
    return ISPanel.onMouseDown(self, x, y)
end

function AegisPlayerPageSafehouse:onShInfo(args)
    self.shWant = false
    if type(args) ~= "table" then return end
    self.shRefresh = getTimestampMs() + SH_REFRESH
    self.days = tonumber(args.days) or nil
    -- respawn rides in the same answer; nil means an older server that
    -- does not carry the fields yet
    self.respawnAllowed = args.respawnAllowed == true
    if args.respawn ~= nil then self.respawnSynced = args.respawn == true end
    -- an answer without the flag comes from an older server: keep the
    -- local scan then, it is all there is
    if not args.known then return end
    self.shKnown = true
    local rec = type(args.sh) == "table" and args.sh or nil
    if rec then
        local names = {}
        for _, n in ipairs(rec.members or {}) do
            if type(n) == "string" then table.insert(names, n) end
        end
        self.sh = {
            owner = tostring(rec.owner or ""),
            members = names,
            title = tostring(rec.title or ""),
            w = tonumber(rec.w) or 0,
            h = tonumber(rec.h) or 0,
            x = tonumber(rec.x),
            y = tonumber(rec.y),
        }
    else
        self.sh = nil
    end
end

function AegisPlayerPageSafehouse:prerender()
    local c = AegisPlayerCol
    local pad = 20
    local w = self.width

    if not self.sh then
        card(self, pad, pad, w - pad * 2, self.height - pad * 2, "UI_AegisPlayer_ShTitle", "home")
        Aegis.textCentre(self, getText("UI_AegisPlayer_ShNone"),
            math.floor(w / 2), math.floor(self.height / 2) - 20, UIFont.Medium, c.text)
        Aegis.textCentre(self, getText("UI_AegisPlayer_ShNoneHint"),
            math.floor(w / 2), math.floor(self.height / 2) + 8, UIFont.Small, c.muted)
        return
    end

    local sh = self.sh
    card(self, pad, pad, w - pad * 2, 190, "UI_AegisPlayer_ShTitle", "home")
    local title = sh.title
    if title == "" then title = sh.owner end
    Aegis.text(self, Aegis.fitText(title, UIFont.Large, w - pad * 2 - 32), pad + 16, pad + 40, UIFont.Large, c.accentHi)
    local size = getText("UI_AegisPlayer_ShSize") .. ": " .. tostring(sh.w) .. "x" .. tostring(sh.h)
        .. " (" .. getText("UI_AegisPlayer_ShTiles", tostring(sh.w * sh.h)) .. ")"
    Aegis.text(self, size, pad + 16, pad + 82, UIFont.Small, c.muted)
    if self.days ~= nil then
        local dc = self.days <= 3 and c.danger or c.muted
        local days = math.floor(self.days * 10 + 0.5) / 10
        Aegis.text(self, getText("UI_AegisPlayer_ShDecay", tostring(days)), pad + 16, pad + 106, UIFont.Small, dc)
    end
    -- the way home, live like on the vehicles page. Gold and clickable
    --: a click points the screen navi at the safehouse,
    -- a second click turns it off. Gold on purpose in the blue panel,
    -- a link has to look different from the labels around it
    local dist = shDistLine(sh)
    self.naviRect = nil
    if dist then
        local t = AegisPlayerVehNavi and AegisPlayerVehNavi.target
        local naviOn = t ~= nil and t.home == true
        local col = naviOn and Aegis.col.goldHi or Aegis.col.gold
        Aegis.icon(self, "pin", pad + 16, pad + 128, 14, 1, col)
        Aegis.text(self, dist, pad + 38, pad + 128, UIFont.Small, col)
        local w = 22 + Aegis.strW(UIFont.Small, dist)
        self.naviRect = { x = pad + 16, y = pad + 124, w = w + 8, h = 22 }
    end

    local my = pad + 202
    local mh = self.height - my - pad
    card(self, pad, my, w - pad * 2, mh, "UI_AegisPlayer_ShMembers", "players")
    local yy = my + 44
    local maxRows = math.floor((mh - 54) / 28)
    for i, name in ipairs(sh.members) do
        if i > maxRows then break end
        local isOwner = name == sh.owner
        if isOwner then
            Aegis.icon(self, "crown", pad + 16, yy, 14, 1, c.accent)
        else
            Aegis.roundRect(self, pad + 21, yy + 5, 4, 4, 2, 1, c.muted)
        end
        Aegis.text(self, Aegis.fitText(name, UIFont.Small, w - pad * 2 - 180), pad + 40, yy, UIFont.Small, c.text)
        if isOwner then
            Aegis.textRight(self, getText("UI_AegisPlayer_ShOwnerTag"), w - pad - 16, yy, UIFont.Small, c.accent)
        end
        yy = yy + 28
    end
end

-- ==================================================================
-- Distress call: free text to the admins, cooldown driven by the server
-- ==================================================================
AegisPlayerPageSos = ISPanel:derive("AegisPlayerPageSos")
AegisPlayerPageSos.instance = nil

-- cap and clean before sending, the server caps again on its side
local function cleanText(s)
    s = tostring(s or ""):gsub("%c", " "):gsub("^%s+", ""):gsub("%s+$", "")
    if #s > 400 then
        s = s:sub(1, 400)
        -- never cut through a UTF-8 sequence
        while #s > 0 do
            local b = s:byte(#s)
            if b >= 128 and b < 192 then
                s = s:sub(1, #s - 1)
            else
                if b >= 192 then s = s:sub(1, #s - 1) end
                break
            end
        end
    end
    return s
end

function AegisPlayerPageSos.create(window, x, y, w, h)
    local o = ISPanel:new(x, y, w, h)
    setmetatable(o, AegisPlayerPageSos)
    AegisPlayerPageSos.__index = AegisPlayerPageSos
    o.background = false
    o.window = window
    o.pending = false
    o.pendingUntil = 0
    o.ackKey = nil
    o.ackUntil = 0
    o.waitUntil = 0
    AegisPlayerPageSos.instance = o
    return o
end

function AegisPlayerPageSos:createChildren()
    local w = self.width
    self.entryX = 40
    self.entryY = 96
    self.entryW = w - 80
    self.entryH = 150
    self.entry = ISTextEntryBox:new("", self.entryX, self.entryY, self.entryW, self.entryH)
    self.entry:initialise()
    self.entry:instantiate()
    self.entry.font = UIFont.Small
    self.entry:setMultipleLine(true)
    self.entry:setMaxLines(6)
    self.entry.javaObject:setEditable(true)
    self.entry:setPlaceholderText(getText("UI_AegisPlayer_SosPlaceholder"))
    self:addChild(self.entry)

    local bw = 240
    self.sendBtn = AegisButton:new(math.floor((w - bw) / 2), self.entryY + self.entryH + 24, bw, 40,
        getText("UI_AegisPlayer_SosSend"), "bolt", self, AegisPlayerPageSos.onSend)
    self:addChild(self.sendBtn)
    self.statusY = self.entryY + self.entryH + 24 + 40 + 16
end

function AegisPlayerPageSos.onSend(self)
    local now = getTimestampMs()
    if now < (self.waitUntil or 0) then return end
    if self.pending and now < self.pendingUntil then return end
    local p = getPlayer()
    if not p then return end
    self.pending = true
    self.pendingUntil = now + 5000
    self.ackKey = nil
    sendClientCommand(p, MODULE, "sos", { text = cleanText(self.entry:getInternalText()) })
end

function AegisPlayerPageSos:onAck(args)
    self.pending = false
    local now = getTimestampMs()
    local wait = (type(args) == "table") and tonumber(args.wait) or nil
    if wait and wait > 0 then
        self.waitUntil = now + wait * 1000
        self.ackKey = nil
        return
    end
    self.ackKey = "UI_AegisPlayer_SosSent"
    self.ackUntil = now + 8000
    self.entry:setText("")
end

function AegisPlayerPageSos:prerender()
    local c = AegisPlayerCol
    local now = getTimestampMs()
    card(self, 20, 20, self.width - 40, self.height - 40, "UI_AegisPlayer_SosTitle", "speaker")
    Aegis.text(self, getText("UI_AegisPlayer_SosHint"), 36, 54, UIFont.Small, c.muted)
    Aegis.roundFrame(self, self.entryX - 2, self.entryY - 2, self.entryW + 4, self.entryH + 4, 6, 1, c.line, c.dark)

    if self.pending and now >= self.pendingUntil then
        self.pending = false
    end
    local waiting = now < (self.waitUntil or 0)
    self.sendBtn:setEnabled(not waiting and not self.pending)

    if waiting then
        local remain = math.ceil((self.waitUntil - now) / 1000)
        Aegis.textCentre(self, getText("UI_AegisPlayer_SosWait", tostring(remain)),
            math.floor(self.width / 2), self.statusY, UIFont.Small, c.muted)
    elseif self.ackKey and now < (self.ackUntil or 0) then
        Aegis.textCentre(self, getText(self.ackKey),
            math.floor(self.width / 2), self.statusY, UIFont.Small, c.ok)
    end
end

-- ==================================================================
-- Server replies and page registry
-- ==================================================================
Events.OnServerCommand.Add(function(module, command, args)
    if module ~= MODULE then return end
    if command == "statsSync" then
        local page = AegisPlayerPageStats.instance
        if page then page:onStatsSync(args) end
    elseif command == "topSync" then
        local page = AegisPlayerPageStats.instance
        if page then page:onTopSync(args) end
    elseif command == "shInfoSync" then
        local page = AegisPlayerPageSafehouse.instance
        if page then page:onShInfo(args) end
    elseif command == "sosAck" then
        local page = AegisPlayerPageSos.instance
        if page then page:onAck(args) end
    end
end)

AegisPlayerWindow.registerPage({
    id = "me",
    icon = "players",
    label = "UI_AegisPlayer_NavMe",
    create = AegisPlayerPageMe.create,
})
AegisPlayerWindow.registerPage({
    id = "stats",
    icon = "dash",
    label = "UI_AegisPlayer_NavStats",
    create = AegisPlayerPageStats.create,
})
AegisPlayerWindow.registerPage({
    id = "safehouse",
    icon = "home",
    label = "UI_AegisPlayer_NavSafehouse",
    create = AegisPlayerPageSafehouse.create,
})
AegisPlayerWindow.registerPage({
    id = "sos",
    icon = "speaker",
    label = "UI_AegisPlayer_NavSos",
    create = AegisPlayerPageSos.create,
})


-- ==================================================================
-- Vanilla fix: the safehouse respawn point swaps width and height
-- (MapSpawnSelect.getSafehouseSpawnRegion adds h/2 to X and w/2 to Y,
-- measured in 42.20). Square zones hide it, elongated ones spawn the
-- fresh character OUTSIDE the house. Same
-- walk as vanilla, halves on the right axes. Lua-to-lua call, so the
-- engine's function cache plays no part here
-- ==================================================================
if MapSpawnSelect and MapSpawnSelect.getSafehouseSpawnRegion then
    function MapSpawnSelect:getSafehouseSpawnRegion()
        if not isClient() then return nil end
        local allowed = getServerOptions():getBoolean("SafehouseAllowRespawn") == true
        if not allowed then return nil end
        local username = getClientUsername()
        if MainScreen.instance.inGame then
            if CoopCharacterCreation.instance.playerIndex > 0 then
                username = CoopUserName.instance:getUserName()
            end
        end
        for i = 0, SafeHouse.getSafehouseList():size() - 1 do
            local safe = SafeHouse.getSafehouseList():get(i)
            if safe:isRespawnInSafehouse(username)
                and (safe:getPlayers():contains(username) or (safe:getOwner() == username)) then
                local x = safe:getX() + math.floor(safe:getW() / 2)
                local y = safe:getY() + math.floor(safe:getH() / 2)
                return { {
                    name = getText("UI_mapspawn_Safehouse"), points = {
                        unemployed = { { posX = x, posY = y, posZ = 0 } },
                    },
                } }
            end
        end
        return nil
    end
end