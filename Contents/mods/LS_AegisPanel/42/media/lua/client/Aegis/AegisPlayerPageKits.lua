-- Kits page of the player panel: every kit as a card with a content
-- preview and a claim button. The catalog comes from the admin kitList
-- command (the server also answers entitled panel players), claims run
-- over the player module and stay self scoped on the server. The list is
-- role filtered by the server, this page only ever sees its own kits.
require "ISUI/ISPanel"
require "ISUI/ISTextEntryBox"
require "Aegis/AegisTheme"
require "Aegis/AegisWidgets"
require "Aegis/AegisPlayerCore"
require "Aegis/AegisPlayerWindow"

AegisPlayerPageKits = ISPanel:derive("AegisPlayerPageKits")
AegisPlayerPageKits.instance = nil

local MODULE = "AegisPlayer"
local CARD_H = 92
local RETRY_MS = 3000
local TRY_MAX = 5
-- redemption strip above the cards; the server hides it entirely when no
-- boost key is configured, so the whole block only costs height when used
local BOOST_H = 112
local MAX_CODE = 96

-- one message per rejection reason of AegisBoost.redeem
local REJECT_KEYS = {
    throttle = "UI_AegisPlayer_BoostTooFast",
    locked = "UI_AegisPlayer_BoostLocked",
    nokey = "UI_AegisPlayer_BoostOff",
    format = "UI_AegisPlayer_BoostBadFormat",
    sig = "UI_AegisPlayer_BoostBadCode",
    expired = "UI_AegisPlayer_BoostCodeExpired",
    idtaken = "UI_AegisPlayer_BoostIdTaken",
    playerbound = "UI_AegisPlayer_BoostOtherId",
    used = "UI_AegisPlayer_BoostUsed",
}

local function modeLine(kit)
    if kit.mode == "once" then return getText("UI_Aegis_KitModeOnce") end
    if kit.mode == "month" then return getText("UI_Aegis_KitModeMonth") end
    return getText("UI_Aegis_KitModeCd") .. " " .. tostring(kit.cooldownH) .. "h"
end

local function displayName(fullType)
    local name = nil
    pcall(function() name = getItemNameFromFullType(fullType) end)
    if type(name) == "string" and name ~= "" then return name end
    local script = getScriptManager():FindItem(fullType)
    if script then name = script:getDisplayName() end
    if type(name) == "string" and name ~= "" then return name end
    return fullType:match("%.(.+)$") or fullType
end

local function claimAllowed()
    if not isClient() then return true end
    local s = AegisPlayerClient and AegisPlayerClient.state
    -- boostReady mirrors the server side boost scope: without the kits
    -- flag only the booster kits arrive, claiming those stays legal
    return type(s) == "table" and (s.kits == true or s.boostReady == true)
end

function AegisPlayerPageKits.create(window, x, y, w, h)
    local o = ISPanel:new(x, y, w, h)
    setmetatable(o, AegisPlayerPageKits)
    AegisPlayerPageKits.__index = AegisPlayerPageKits
    o.background = false
    o.window = window
    o.kits = {}
    o.status = {}
    o.claimBtns = {}
    o.gotList = false
    o.tries = 0
    -- stays hidden until the server reports a configured key
    o.boostKey = false
    o.boostUntil = 0
    o.boostLinked = false
    AegisPlayerPageKits.instance = o
    return o
end

-- the redeem strip sits at the BOTTOM of the page: a fixed
-- home that does not move when the kit list grows or shrinks
function AegisPlayerPageKits:boostTop()
    return self.height - 20 - (BOOST_H - 12)
end

function AegisPlayerPageKits:createChildren()
    local pad = 20
    local w = self.width - pad * 2 - 16
    self.boostY = self:boostTop()

    self.boostEntry = ISTextEntryBox:new("", pad + 8, self.boostY + 46, math.max(80, w - 128), 26)
    self.boostEntry:initialise()
    self.boostEntry:instantiate()
    self.boostEntry.font = UIFont.Small
    self.boostEntry:setMaxTextLength(MAX_CODE)
    -- the code format is uppercase only, typing it lowercase must still work
    self.boostEntry:setForceUpperCase(true)
    self.boostEntry:setPlaceholderText(getText("UI_AegisPlayer_BoostHint"))
    self.boostEntry.backgroundColor = { r = AegisPlayerCol.dark.r, g = AegisPlayerCol.dark.g, b = AegisPlayerCol.dark.b, a = 1 }
    self.boostEntry.borderColor = { r = AegisPlayerCol.line.r, g = AegisPlayerCol.line.g, b = AegisPlayerCol.line.b, a = 1 }
    self:addChild(self.boostEntry)

    self.boostBtn = AegisButton:new(pad + 8 + w - 118, self.boostY + 46, 118, 26,
        getText("UI_AegisPlayer_BoostRedeem"), "check", self, AegisPlayerPageKits.onRedeem)
    self.boostBtn.accent = AegisPlayerCol.accent
    self:addChild(self.boostBtn)

    self:rebuildScroll()
end

-- the scroll area is rebuilt instead of resized: its scrollbar is sized at
-- creation and does not follow a later setHeight
function AegisPlayerPageKits:rebuildScroll()
    local pad = 20
    local top = pad + 40
    local bottom = self.height - pad - 8
    if self.boostKey then bottom = self:boostTop() - 10 end
    local h = math.max(60, bottom - top)
    if self.scroll then
        self:removeChild(self.scroll)
        self.scroll = nil
        self.cards = nil
    end
    self.scroll = AegisScrollArea:new(pad + 8, top, self.width - pad * 2 - 16, h)
    self:addChild(self.scroll)
    local on = self.boostKey == true
    if self.boostEntry then self.boostEntry:setVisible(on) end
    if self.boostBtn then
        self.boostBtn:setVisible(on)
        self.boostBtn:setEnabled(on)
    end
    self:rebuildCards()
end

-- ------------------------------------------------------------------
-- Data
-- ------------------------------------------------------------------

function AegisPlayerPageKits:requestList()
    local p = getPlayer()
    if not p then return end
    self.requestedAt = getTimestampMs()
    self.tries = self.tries + 1
    -- player flag: asks for the panel view, role filtered even for admins
    sendClientCommand(p, AegisShared.MODULE, "kitList", { player = true })
    sendClientCommand(p, MODULE, "boostInfo", {})
end

-- ------------------------------------------------------------------
-- Booster code
-- ------------------------------------------------------------------

function AegisPlayerPageKits:onBoostInfo(args)
    if type(args) ~= "table" then return end
    self.boostAnswered = true
    local was = self.boostKey
    self.boostKey = args.keySet == true
    self.boostUntil = tonumber(args.untilEpoch) or 0
    self.boostLinked = args.linked == true
    if was ~= self.boostKey then self:rebuildScroll() end
end

function AegisPlayerPageKits:onRedeem()
    if self.boostPending or not self.boostKey then return end
    local p = getPlayer()
    if not p or not self.boostEntry then return end
    local code = (self.boostEntry:getInternalText() or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if code == "" then return end
    self.boostPending = true
    self.boostPendingAt = getTimestampMs()
    self.boostMsg = nil
    sendClientCommand(p, MODULE, "boostRedeem", { code = code })
end

function AegisPlayerPageKits:onRedeemReply(args)
    self.boostPending = false
    if type(args) ~= "table" then return end
    if args.ok == true then
        self.boostMsg = { key = "UI_AegisPlayer_BoostOk", tone = "ok" }
        self.boostUntil = tonumber(args.untilEpoch) or self.boostUntil
        self.boostLinked = true
        if self.boostEntry then self.boostEntry:setText("") end
        AegisPlayerWindow.toast(getText("UI_AegisPlayer_BoostOk"))
    else
        self.boostMsg = { key = REJECT_KEYS[args.reason] or "UI_AegisPlayer_BoostError", tone = "danger" }
    end
end

function AegisPlayerPageKits:drawBoost()
    local c = AegisPlayerCol
    local pad = 20
    local x = pad + 8
    local w = self.width - pad * 2 - 16
    -- recomputed every frame: the window stretches children live during a
    -- grip drag and rebuilds only on release, a stored y would drift
    local y = self:boostTop()
    self.boostY = y
    if self.boostEntry then
        self.boostEntry:setX(x)
        self.boostEntry:setY(y + 46)
        self.boostEntry:setWidth(math.max(80, w - 128))
    end
    if self.boostBtn then
        self.boostBtn:setX(x + w - 118)
        self.boostBtn:setY(y + 46)
        self.boostBtn:setWidth(118)
    end
    Aegis.roundFrame(self, x, y, w, BOOST_H - 12, 10, 1, c.line, c.card)
    Aegis.icon(self, "crown", x + 12, y + 9, 14, 1, c.accentHi)
    Aegis.text(self, getText("UI_AegisPlayer_BoostTitle"), x + 34, y + 7, UIFont.Medium, c.text)

    local line, tone
    if self.boostUntil and self.boostUntil > AegisShared.realTime() then
        line = getText("UI_AegisPlayer_BoostUntil", AegisShared.timestampReadable(self.boostUntil))
        tone = c.ok
    elseif self.boostLinked then
        line = getText("UI_AegisPlayer_BoostLapsed")
        tone = c.muted
    else
        line = getText("UI_AegisPlayer_BoostNone")
        tone = c.muted
    end
    Aegis.text(self, Aegis.fitText(line, UIFont.Small, w - 24), x + 12, y + 28, UIFont.Small, tone)

    if self.boostMsg then
        local msg = getText(self.boostMsg.key)
        Aegis.text(self, Aegis.fitText(msg, UIFont.Small, w - 24), x + 12, y + 76, UIFont.Small,
            self.boostMsg.tone == "ok" and c.ok or c.danger)
    end
end

function AegisPlayerPageKits:setKits(list, hidden)
    self.kits = {}
    if type(list) == "table" then
        for i = 1, #list do
            local k = list[i]
            if type(k) == "table" and type(k.id) == "string" then
                table.insert(self.kits, k)
            end
        end
    end
    self.gotList = true
    -- how many kits the server held back for this role; without it an
    -- empty list would claim a role gate even when no kit exists at all
    self.hidden = tonumber(hidden) or 0
    self:rebuildCards()
end

-- one preview line per kit, resolved lazily and cached on the kit table
function AegisPlayerPageKits:preview(kit)
    if kit._preview then return kit._preview end
    local parts = {}
    local items = type(kit.items) == "table" and kit.items or {}
    for i = 1, #items do
        local it = items[i]
        if type(it) == "table" and type(it.fullType) == "string" then
            table.insert(parts, displayName(it.fullType) .. " x" .. tostring(math.floor(tonumber(it.count) or 1)))
        end
    end
    kit._preview = table.concat(parts, ", ")
    return kit._preview
end

-- ------------------------------------------------------------------
-- Cards
-- ------------------------------------------------------------------

-- the cards live on an inner panel inside the scroll area, so a rebuild
-- replaces one child and leaves the scrollbar alone
function AegisPlayerPageKits:rebuildCards()
    if not self.scroll then return end
    if self.cards then self.scroll:removeChild(self.cards) end
    self.claimBtns = {}
    local w = self.scroll.width - 16
    local need = #self.kits * (CARD_H + 12) + 12
    local h = math.max(need, self.scroll.height)
    local panel = ISPanel:new(0, 0, w, h)
    panel:initialise()
    panel.background = false
    panel.page = self
    panel.prerender = AegisPlayerPageKits.drawCards
    self.scroll:addChild(panel)
    self.scroll:setScrollHeight(h)
    self.cards = panel

    local y = 12
    for _, kit in ipairs(self.kits) do
        local btn = AegisButton:new(w - 132, y + math.floor((CARD_H - 30) / 2), 118, 30,
            getText("UI_Aegis_KitClaim"), "check", self, function(page, b) page:onClaim(b.kitId) end)
        btn.kitId = kit.id
        -- locked rides on the payload: the booster check is unavailable,
        -- the card stays visible but cannot be claimed
        btn.kitLocked = kit.locked == true
        btn.accent = AegisPlayerCol.accent
        panel:addChild(btn)
        table.insert(self.claimBtns, btn)
        y = y + CARD_H + 12
    end
end

function AegisPlayerPageKits.drawCards(panel)
    local page = panel.page
    local c = AegisPlayerCol
    local w = panel.width
    local y = 12
    for _, kit in ipairs(page.kits) do
        Aegis.roundFrame(panel, 0, y, w, CARD_H, 10, 1, c.line, c.card)
        local title = Aegis.fitText(kit.name or kit.id, UIFont.Medium, w - 160)
        Aegis.text(panel, title, 14, y + 8, UIFont.Medium, c.text)
        -- why this kit is yours: the role it came through
        -- or the booster status, right next to the name. Open kits carry
        -- no tag, they belong to everyone
        if kit.why then
            local tag = kit.why == "boost" and getText("UI_AegisPlayer_BoostTitle") or kit.why
            local tx = 14 + Aegis.strW(UIFont.Medium, title) + 8
            -- room left in the name lane, measured from tx. Subtracting an
            -- absolute x from a width went negative for every name long
            -- enough to be cut, and fitText answers a negative budget with
            -- a stub that then ran under the claim button
            local room = (14 + (w - 160)) - tx
            if room >= 24 then
                Aegis.text(panel, Aegis.fitText("[" .. tag .. "]", UIFont.Small, room),
                    tx, y + 8 + Aegis.fontH(UIFont.Medium) - Aegis.fontH(UIFont.Small) - 1,
                    UIFont.Small, c.accentHi)
            end
        end
        local st = page.status[kit.id]
        local line, lineC
        if st then
            line = st.par and getText(st.key, st.par) or getText(st.key)
            if st.tone == "ok" then lineC = c.ok
            elseif st.tone == "warn" then lineC = c.accentHi
            elseif st.tone == "danger" then lineC = c.danger
            else lineC = c.muted end
        elseif kit.locked == true then
            line = getText("UI_AegisPlayer_KitUnavailable")
            lineC = c.accentHi
        else
            line = modeLine(kit)
            lineC = c.accent
        end
        Aegis.text(panel, line, 14, y + 32, UIFont.Small, lineC)
        Aegis.text(panel, Aegis.fitText(page:preview(kit), UIFont.Small, w - 160), 14,
            y + CARD_H - 12 - Aegis.fontH(UIFont.Small), UIFont.Small, c.muted)
        y = y + CARD_H + 12
    end
    -- empty means "nothing unlocked for your role", not "no kits exist":
    -- the server filtered before sending
    if page.gotList and #page.kits == 0 then
        local key = (page.hidden or 0) > 0 and "UI_AegisPlayer_KitsNone" or "UI_Aegis_KitEmpty"
        Aegis.textCentre(panel, getText(key), math.floor(w / 2), 40, UIFont.Small, c.muted)
    end
end

-- ------------------------------------------------------------------
-- Claim
-- ------------------------------------------------------------------

function AegisPlayerPageKits:onClaim(kitId)
    if self.pendingId or not claimAllowed() then return end
    local p = getPlayer()
    if not p then return end
    self.pendingId = kitId
    self.pendingAt = getTimestampMs()
    sendClientCommand(p, MODULE, "kitClaim", { id = kitId })
end

function AegisPlayerPageKits:onClaimReply(args)
    if type(args) ~= "table" then return end
    local id = type(args.id) == "string" and args.id or nil
    if not id then return end
    if self.pendingId == id then self.pendingId = nil end
    if args.ok == true then
        self.status[id] = { key = "UI_Aegis_KitClaimed", tone = "ok" }
        AegisPlayerWindow.toast(getText("UI_Aegis_KitClaimed"))
    elseif args.reason == "cooldown" then
        self.status[id] = { key = "UI_Aegis_KitCooldown", par = tostring(tonumber(args.wait) or "?"), tone = "warn" }
    elseif args.reason == "month" then
        self.status[id] = { key = "UI_Aegis_KitMonthWait", par = tostring(tonumber(args.wait) or "?"), tone = "warn" }
    elseif args.reason == "once" then
        self.status[id] = { key = "UI_Aegis_KitOnceUsed", tone = "muted" }
    elseif args.reason == "unavailable" then
        self.status[id] = { key = "UI_AegisPlayer_KitUnavailable", tone = "warn" }
    else
        self.status[id] = { key = "UI_Aegis_KitFailed", tone = "danger" }
    end
end

-- ------------------------------------------------------------------
-- Frame
-- ------------------------------------------------------------------

-- a resize rebuilds the page; carrying list and boost state over avoids
-- an empty page until the throttled server replies arrive again
function AegisPlayerPageKits:saveState()
    return { kits = self.kits, hidden = self.hidden, gotList = self.gotList,
        boostKey = self.boostKey, boostUntil = self.boostUntil, boostLinked = self.boostLinked }
end

function AegisPlayerPageKits:restoreState(state)
    if type(state) ~= "table" then return end
    if state.boostKey ~= nil then
        self.boostKey = state.boostKey == true
        self.boostUntil = tonumber(state.boostUntil) or 0
        self.boostLinked = state.boostLinked == true
        self.boostAnswered = true
        -- createChildren ran before this state arrived and laid the page
        -- out without the redeem strip; rebuild with the flag in hand,
        -- otherwise field and button stay hidden after a resize
        self:rebuildScroll()
    end
    if state.gotList == true and type(state.kits) == "table" then
        self:setKits(state.kits, state.hidden)
    end
end

function AegisPlayerPageKits:onShow()
    self.tries = 0
    self.boostAnswered = false
    self:requestList()
end

function AegisPlayerPageKits:update()
    ISPanel.update(self)
    -- lost request self healing, same rhythm as the other panel pages;
    -- both answers ride the same request, either one missing retries
    if (not self.gotList or not self.boostAnswered) and self.requestedAt and self.tries < TRY_MAX
        and getTimestampMs() - self.requestedAt >= RETRY_MS then
        self:requestList()
    end
    -- a lost reply must not lock the buttons forever
    if self.pendingId and getTimestampMs() - (self.pendingAt or 0) > 6000 then
        self.pendingId = nil
    end
    if self.boostPending and getTimestampMs() - (self.boostPendingAt or 0) > 6000 then
        self.boostPending = false
    end
end

function AegisPlayerPageKits:prerender()
    local c = AegisPlayerCol
    local pad = 20
    Aegis.roundFrame(self, pad, pad, self.width - pad * 2, self.height - pad * 2, 10, 1, c.line, c.panel)
    Aegis.icon(self, "items", pad + 14, pad + 12, 15, 1, c.accent)
    Aegis.text(self, getText("UI_AegisPlayer_NavKits"), pad + 36, pad + 10, UIFont.Medium, c.text)
    if self.boostKey then
        self:drawBoost()
        if self.boostBtn then
            local code = self.boostEntry and (self.boostEntry:getInternalText() or "") or ""
            self.boostBtn:setEnabled(code ~= "" and not self.boostPending)
        end
    end
    local allowed = claimAllowed()
    for _, btn in ipairs(self.claimBtns) do
        btn:setEnabled(allowed and self.pendingId == nil and not btn.kitLocked)
    end
end

Events.OnServerCommand.Add(function(module, command, args)
    local page = AegisPlayerPageKits.instance
    if not page then return end
    if module == AegisShared.MODULE and command == "kitList" then
        -- only the panel payload, the admin editor gets the full catalog
        -- over the same command
        if not (args and args.scope == "player") then return end
        page:setKits(args.kits or {}, args.hidden)
    elseif module == MODULE and command == "kitClaim" then
        page:onClaimReply(args)
    elseif module == MODULE and command == "boostInfo" then
        page:onBoostInfo(args)
    elseif module == MODULE and command == "boostRedeem" then
        page:onRedeemReply(args)
    end
end)

AegisPlayerWindow.registerPage({
    id = "kits",
    icon = "items",
    label = "UI_AegisPlayer_NavKits",
    create = AegisPlayerPageKits.create,
})
