-- Relations radar card: shows a player's top partners by shared
-- minutes over the last 7 days, data comes from the server.
require "Aegis/AegisTheme"
require "Aegis/AegisWidgets"

AegisRelations = ISPanel:derive("AegisRelations")
AegisRelations.instance = nil

local CARD_W = 460
local ROW_H = 40
local MAX_ROWS = 10

local function fmtMinutes(minutes)
    minutes = math.max(0, math.floor(tonumber(minutes) or 0))
    if minutes >= 60 then
        return getText("UI_Aegis_RelHourMin", tostring(math.floor(minutes / 60)), tostring(minutes % 60))
    end
    return getText("UI_Aegis_RelMin", tostring(minutes))
end

function AegisRelations.open(username)
    if AegisRelations.instance then
        AegisRelations.instance:closeSelf()
    end
    local sw, sh = getCore():getScreenWidth(), getCore():getScreenHeight()
    local o = ISPanel:new(0, 0, sw, sh)
    setmetatable(o, AegisRelations)
    AegisRelations.__index = AegisRelations
    o.background = true
    o.backgroundColor = { r = 0, g = 0, b = 0, a = 0.55 }
    o.borderColor = { r = 0, g = 0, b = 0, a = 0 }
    o.username = tostring(username or "")
    -- in solo nobody records encounters, the card says so honestly
    o.solo = not isClient()
    o.partners = nil
    o.maxMinutes = 1
    o.nextRequest = 0
    o.cardH = o.solo and 190 or (52 + MAX_ROWS * ROW_H + 26 + 52)
    o.cardX = math.floor((sw - CARD_W) / 2)
    o.cardY = math.max(0, math.floor((sh - o.cardH) / 2))
    o:initialise()
    o:addToUIManager()
    o:setAlwaysOnTop(true)
    AegisRelations.instance = o
    if not o.solo then o:request() end
    return o
end

function AegisRelations:closeSelf()
    self:removeFromUIManager()
    if AegisRelations.instance == self then
        AegisRelations.instance = nil
    end
end

function AegisRelations:createChildren()
    local cx, cy = self.cardX, self.cardY
    local by = cy + self.cardH - 52
    if self.solo then
        self.closeBtn = AegisButton:new(cx + 16, by, CARD_W - 32, 36, getText("UI_Aegis_RelClose"), "close", self, AegisRelations.closeSelf)
        self:addChild(self.closeBtn)
        return
    end
    local bw = math.floor((CARD_W - 48) / 2)
    self.refreshBtn = AegisButton:new(cx + 16, by, bw, 36, getText("UI_Aegis_RelRefresh"), "refresh", self, AegisRelations.onRefresh)
    self.refreshBtn.style = "gold"
    self:addChild(self.refreshBtn)
    self.closeBtn = AegisButton:new(cx + 32 + bw, by, bw, 36, getText("UI_Aegis_RelClose"), "close", self, AegisRelations.closeSelf)
    self:addChild(self.closeBtn)
end

function AegisRelations.onRefresh(self)
    self:request()
end

-- lightly throttled request, the server caps at 1/s anyway
function AegisRelations:request()
    if self.solo then return end
    local now = getTimestampMs()
    if now < self.nextRequest then return end
    self.nextRequest = now + 1000
    self.partners = nil
    local p = getPlayer()
    if p then
        sendClientCommand(p, AegisShared.MODULE, "relationData", { username = self.username })
    end
end

function AegisRelations:receive(args)
    if args and args.throttled then
        -- server declined (1/s cap), wait briefly and retry the
        -- request automatically instead of hanging on the loading text
        self.retryAt = getTimestampMs() + 400
        return
    end
    local list = {}
    if args and type(args.partners) == "table" then
        -- network tables arrive without reliable order, sort again
        for _, e in pairs(args.partners) do
            if type(e) == "table" and e.name then
                table.insert(list, {
                    name = tostring(e.name),
                    total = math.floor(tonumber(e.total) or 0),
                    today = math.floor(tonumber(e.today) or 0),
                })
            end
        end
    end
    table.sort(list, function(a, b)
        if a.total ~= b.total then return a.total > b.total end
        return a.name < b.name
    end)
    local maxMin = 1
    for _, e in ipairs(list) do
        if e.total > maxMin then maxMin = e.total end
    end
    self.maxMinutes = maxMin
    self.partners = list
end

function AegisRelations:prerender()
    ISPanel.prerender(self)
    local c = Aegis.col
    local cx, cy = self.cardX, self.cardY
    Aegis.shadow(self, cx, cy, CARD_W, self.cardH, 26, 0.7)
    Aegis.roundFrame(self, cx, cy, CARD_W, self.cardH, 12, 1, c.line, c.bg)
    Aegis.icon(self, "players", cx + 18, cy + 16, 18, 1, c.gold)
    Aegis.text(self, Aegis.fitText(getText("UI_Aegis_RelTitle", self.username), UIFont.Medium, CARD_W - 60),
        cx + 46, cy + 14, UIFont.Medium, c.text)

    if self.solo then
        Aegis.textCentre(self, getText("UI_Aegis_RelSolo1"), cx + math.floor(CARD_W / 2), cy + 66, UIFont.Small, c.muted)
        Aegis.textCentre(self, getText("UI_Aegis_RelSolo2"), cx + math.floor(CARD_W / 2), cy + 86, UIFont.Small, c.muted)
        return
    end

    local innerX = cx + 20
    local innerW = CARD_W - 40
    local listY = cy + 52
    local list = self.partners
    if list == nil then
        Aegis.textCentre(self, getText("UI_Aegis_RelLoading"), cx + math.floor(CARD_W / 2), listY + 44, UIFont.Small, c.muted)
    elseif #list == 0 then
        Aegis.textCentre(self, getText("UI_Aegis_RelEmpty"), cx + math.floor(CARD_W / 2), listY + 44, UIFont.Small, c.muted)
    else
        local maxMin = math.max(1, self.maxMinutes or 1)
        local rightW = 120
        local barW = innerW - rightW - 8
        for i = 1, math.min(#list, MAX_ROWS) do
            local e = list[i]
            local y = listY + (i - 1) * ROW_H
            if i % 2 == 0 then
                Aegis.roundRect(self, cx + 12, y, CARD_W - 24, ROW_H - 2, 8, 0.35, c.panel)
            end
            Aegis.text(self, Aegis.fitText(e.name, UIFont.Small, barW), innerX, y + 2, UIFont.Small, c.text)
            Aegis.textRight(self, fmtMinutes(e.total), innerX + innerW, y + 2, UIFont.Small, c.goldHi)
            -- bar scales against the longest relation in the list
            Aegis.roundRect(self, innerX, y + 25, barW, 7, 3, 1, c.line)
            local fillW = math.max(4, math.floor(barW * e.total / maxMin))
            Aegis.roundRect(self, innerX, y + 25, math.min(barW, fillW), 7, 3, 1, c.gold)
            if e.today > 0 then
                Aegis.textRight(self, getText("UI_Aegis_RelToday", fmtMinutes(e.today)), innerX + innerW, y + 20, UIFont.Small, c.muted)
            end
        end
    end

    Aegis.text(self, Aegis.fitText(getText("UI_Aegis_RelHint"), UIFont.Small, innerW),
        innerX, cy + 52 + MAX_ROWS * ROW_H + 6, UIFont.Small, c.muted)
end

function AegisRelations:onMouseDown(x, y)
    -- swallow clicks on the dim background
end

function AegisRelations:update()
    if self.retryAt and getTimestampMs() >= self.retryAt then
        self.retryAt = nil
        self.nextRequest = 0
        self:request()
    end
end

Events.OnServerCommand.Add(function(module, command, args)
    if module ~= "AegisAdmin" then return end
    if command ~= "relationData" then return end
    local self = AegisRelations.instance
    if self and args and tostring(args.username or "") == self.username then
        self:receive(args)
    end
end)
