-- Distress call alerts for admins. A player pressing SOS in the blue
-- panel used to land as a toast in the admin window header, which is
-- closed most of the time, so the call effectively went nowhere. Every
-- call now becomes its own card at the top of the screen with the name,
-- the message, the position and a jump button.
--
-- The host element covers ONLY the card stack, never the whole screen:
-- a fullscreen panel starves the world right click, and a 1x1 host would
-- let a click on a button fall through into the world as well.
require "Aegis/AegisTheme"
require "Aegis/AegisWidgets"

AegisSosAlert = AegisSosAlert or {}
AegisSosAlert.calls = {}
AegisSosAlert.host = nil

local CARD_W = 420
local CARD_H = 92
local GAP = 8
local TOP = 58
local LIFE_MS = 90000
local MAX_CARDS = 4
local BTN_W = 120
local BTN_H = 24

local Host = ISPanel:derive("AegisSosAlertHost")

local function stackHeight()
    local n = #AegisSosAlert.calls
    if n == 0 then return 0 end
    return n * CARD_H + (n - 1) * GAP
end

local function dropHost()
    if not AegisSosAlert.host then return end
    AegisSosAlert.host:removeFromUIManager()
    AegisSosAlert.host = nil
end

local function syncHost()
    if #AegisSosAlert.calls == 0 then
        dropHost()
        return
    end
    local sw = getCore():getScreenWidth()
    local x = math.floor((sw - CARD_W) / 2)
    local h = stackHeight()
    if not AegisSosAlert.host then
        local o = ISPanel:new(x, TOP, CARD_W, h)
        setmetatable(o, Host)
        Host.__index = Host
        o.background = false
        o:initialise()
        o:addToUIManager()
        o:setAlwaysOnTop(true)
        AegisSosAlert.host = o
        return
    end
    local host = AegisSosAlert.host
    host:setX(x)
    host:setHeight(h)
end

function AegisSosAlert.push(args)
    -- only staff sees this at all; the server already filters, this is
    -- the belt for a stray packet
    if not Aegis.allowed(getPlayer()) then return end
    table.insert(AegisSosAlert.calls, 1, {
        name = tostring(args.par or "?"),
        text = type(args.text) == "string" and args.text or "",
        x = tonumber(args.x),
        y = tonumber(args.y),
        z = tonumber(args.z) or 0,
        at = getTimestampMs(),
    })
    while #AegisSosAlert.calls > MAX_CARDS do
        table.remove(AegisSosAlert.calls)
    end
    syncHost()
end

function AegisSosAlert.dismiss(idx)
    table.remove(AegisSosAlert.calls, idx)
    syncHost()
end

function Host:update()
    local now = getTimestampMs()
    local changed = false
    for i = #AegisSosAlert.calls, 1, -1 do
        if now - AegisSosAlert.calls[i].at > LIFE_MS then
            table.remove(AegisSosAlert.calls, i)
            changed = true
        end
    end
    if changed then syncHost() end
end

-- card local geometry, y grows downward inside the host
local function cardY(i)
    return (i - 1) * (CARD_H + GAP)
end

function Host:render()
    local c = Aegis.col
    local f = UIFont.Small
    local mx, my = self:getMouseX(), self:getMouseY()
    for i, call in ipairs(AegisSosAlert.calls) do
        local y = cardY(i)
        Aegis.shadow(self, 0, y, CARD_W, CARD_H, 18, 0.55)
        Aegis.roundFrame(self, 0, y, CARD_W, CARD_H, 12, 0.97, c.danger, c.bg)
        Aegis.icon(self, "speaker", 14, y + 12, 18, 1, c.danger)
        Aegis.text(self, getText("UI_Aegis_SosNotice", call.name), 40, y + 10, UIFont.Medium, c.goldHi)

        local where = "?"
        if call.x and call.y then
            where = math.floor(call.x) .. "," .. math.floor(call.y)
            local dist = nil
            pcall(function()
                local p = getPlayer()
                if not p then return end
                local dx, dy = call.x - p:getX(), call.y - p:getY()
                dist = math.floor(math.sqrt(dx * dx + dy * dy) + 0.5)
            end)
            if dist then where = where .. "  (" .. dist .. " m)" end
        end
        Aegis.textRight(self, where, CARD_W - 14, y + 12, f, c.goldDim)

        if call.text ~= "" then
            Aegis.text(self, Aegis.fitText(call.text, f, CARD_W - 60), 40, y + 36, f, c.text)
        end

        local by = y + CARD_H - 32
        local jx = CARD_W - 14 - BTN_W * 2 - 8
        local dx = CARD_W - 14 - BTN_W
        local overJump = call.x ~= nil and mx >= jx and mx <= jx + BTN_W and my >= by and my <= by + BTN_H
        local overDrop = mx >= dx and mx <= dx + BTN_W and my >= by and my <= by + BTN_H
        if call.x then
            Aegis.roundFrame(self, jx, by, BTN_W, BTN_H, 12, 1, c.gold, overJump and c.card or c.dark)
            Aegis.textCentre(self, getText("UI_Aegis_FactionJump"), jx + BTN_W / 2, by + 4, f, c.goldHi)
        end
        Aegis.roundFrame(self, dx, by, BTN_W, BTN_H, 12, 1, c.line, overDrop and c.card or c.dark)
        Aegis.textCentre(self, getText("UI_Aegis_RelClose"), dx + BTN_W / 2, by + 4, f, c.muted)
    end
end

-- the host consumes clicks inside the stack, so nothing reaches the
-- world below; everything outside the stack is untouched
function Host:onMouseDown(x, y)
    self:bringToTop()
    return true
end

function Host:onMouseUp(x, y)
    local by, jx, dx = nil, CARD_W - 14 - BTN_W * 2 - 8, CARD_W - 14 - BTN_W
    for i, call in ipairs(AegisSosAlert.calls) do
        by = cardY(i) + CARD_H - 32
        if y >= by and y <= by + BTN_H then
            if call.x and x >= jx and x <= jx + BTN_W then
                Aegis.teleportSmart(call.x, call.y, call.z)
                Aegis.logAction("players", string.format("SOS answered: %s at %d,%d",
                    call.name, math.floor(call.x or 0), math.floor(call.y or 0)))
                AegisSosAlert.dismiss(i)
                return true
            end
            if x >= dx and x <= dx + BTN_W then
                AegisSosAlert.dismiss(i)
                return true
            end
        end
    end
    return true
end

-- a fresh session starts without stale calls
Events.OnGameStart.Add(function()
    AegisSosAlert.calls = {}
    dropHost()
end)
