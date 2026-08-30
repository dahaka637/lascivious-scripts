-- Claim page of the player panel: shows the tile budget of the role,
-- lets the player draw ONE zone directly in the world and release it
-- again. The zone must touch or overlap the player's own safehouse,
-- the editor shows the house outline and live feedback for that.
-- Rectangle editor follows AegisClearingEditor, the server in
-- Aegis_PlayerClaims.lua re-checks every rule.
require "ISUI/ISPanel"
require "Aegis/AegisTheme"
require "Aegis/AegisWidgets"
require "Aegis/AegisPlayerCore"

AegisPlayerPageClaim = ISPanel:derive("AegisPlayerPageClaim")
AegisPlayerPageClaim.instance = nil

local MODULE = "AegisPlayer"
local MIN_EDGE = 3
local MAX_EDGE = 80
-- beyond this distance to the own house the editor shows a walk hint
local FAR_TILES = 60

-- ---------- world helpers (pattern from AegisClearing.lua) ----------
local function playerLevel()
    local p = getPlayer()
    return p and math.floor(p:getZ()) or 0
end

local function mouseTile()
    local z = playerLevel()
    local zoom = getCore():getZoom(0)
    local wx = IsoUtils.XToIso(getMouseX() * zoom, getMouseY() * zoom, z)
    local wy = IsoUtils.YToIso(getMouseX() * zoom, getMouseY() * zoom, z)
    return math.floor(wx), math.floor(wy)
end

local function screenProjection(wx, wy, z)
    local anchorX = isoToScreenX(0, wx, wy, z)
    local anchorY = isoToScreenY(0, wx, wy, z)
    local zoom = getCore():getZoom(0)
    local baseX = IsoUtils.XToScreen(wx, wy, z, 0)
    local baseY = IsoUtils.YToScreen(wx, wy, z, 0)
    return function(px, py)
        return anchorX + (IsoUtils.XToScreen(px, py, z, 0) - baseX) / zoom,
            anchorY + (IsoUtils.YToScreen(px, py, z, 0) - baseY) / zoom
    end
end

local function rectEdges(r)
    return {
        { r.x, r.y, r.x + r.w, r.y },
        { r.x, r.y + r.h, r.x + r.w, r.y + r.h },
        { r.x, r.y, r.x, r.y + r.h },
        { r.x + r.w, r.y, r.x + r.w, r.y + r.h },
    }
end

local function drawEdges(el, edges, wx, wy, z, a, color)
    local project = screenProjection(wx, wy, z)
    if not project then return end
    for _, k in ipairs(edges) do
        local x1, y1 = project(k[1], k[2])
        local x2, y2 = project(k[3], k[4])
        el:drawLine2(x1, y1, x2, y2, a, color.r, color.g, color.b)
        el:drawLine2(x1, y1 + 1, x2, y2 + 1, a * 0.5, color.r, color.g, color.b)
    end
end

local function requestInfo()
    local p = getPlayer()
    if p then sendClientCommand(p, MODULE, "claimInfo", {}) end
end

-- ==================================================================
-- Editor: fullscreen over the world, drag rectangle, Enter confirms
-- ==================================================================
AegisPlayerClaimEditor = ISPanel:derive("AegisPlayerClaimEditor")
AegisPlayerClaimEditor.instance = nil

function AegisPlayerClaimEditor.start(budget, home)
    if AegisPlayerClaimEditor.instance then return end
    local sw, sh = getCore():getScreenWidth(), getCore():getScreenHeight()
    local o = ISPanel:new(0, 0, sw, sh)
    setmetatable(o, AegisPlayerClaimEditor)
    AegisPlayerClaimEditor.__index = AegisPlayerClaimEditor
    o.background = false
    o.dragging = false
    o.budget = budget
    o.home = home
    local tx, ty = mouseTile()
    -- start the preview on the one tile border of the house so the
    -- player sees where the zone has to attach
    if home then
        tx = math.max(home.x - 1, math.min(tx, home.x + home.w))
        ty = math.max(home.y - 1, math.min(ty, home.y + home.h))
    end
    o.newRect = { x = tx, y = ty, w = 1, h = 1 }
    o:initialise()
    o:addToUIManager()
    o:setAlwaysOnTop(true)
    o:setWantKeyEvents(true)
    AegisPlayerClaimEditor.instance = o
    if AegisPlayerWindow and AegisPlayerWindow.instance then
        AegisPlayerWindow.instance:setVisible(false)
    end
    return o
end

function AegisPlayerClaimEditor:finish()
    self:removeFromUIManager()
    AegisPlayerClaimEditor.instance = nil
    if AegisPlayerWindow and AegisPlayerWindow.instance then
        AegisPlayerWindow.instance:setVisible(true)
    end
end

-- same touch rule as the server: edge adjacent counts, a gap does not
function AegisPlayerClaimEditor:attached()
    local hp = self.home
    if not hp then return false end
    local n = self.newRect
    return n.x < hp.x + hp.w + 1 and n.x + n.w > hp.x - 1
        and n.y < hp.y + hp.h + 1 and n.y + n.h > hp.y - 1
end

-- chebyshev distance from the player to the house rectangle
function AegisPlayerClaimEditor:homeDistance()
    local hp = self.home
    if not hp then return nil end
    local p = getPlayer()
    if not p then return nil end
    local px, py = math.floor(p:getX()), math.floor(p:getY())
    local dx = math.max(hp.x - px, px - (hp.x + hp.w - 1), 0)
    local dy = math.max(hp.y - py, py - (hp.y + hp.h - 1), 0)
    return math.max(dx, dy)
end

function AegisPlayerClaimEditor:valid()
    local n = self.newRect
    return n.w >= MIN_EDGE and n.h >= MIN_EDGE and n.w * n.h <= self.budget
        and self:attached()
end

function AegisPlayerClaimEditor:render()
    local c = AegisPlayerCol
    local z = playerLevel()
    if self.dragging then
        local mx, my = mouseTile()
        local x1, x2 = math.min(self.dragX, mx), math.max(self.dragX, mx)
        local y1, y2 = math.min(self.dragY, my), math.max(self.dragY, my)
        if x2 - x1 + 1 > MAX_EDGE then x2 = x1 + MAX_EDGE - 1 end
        if y2 - y1 + 1 > MAX_EDGE then y2 = y1 + MAX_EDGE - 1 end
        self.newRect = { x = x1, y = y1, w = x2 - x1 + 1, h = y2 - y1 + 1 }
    end
    -- house outline as the attach target, subdued next to the new rect
    if self.home then
        local hp = self.home
        drawEdges(self, rectEdges(hp), hp.x, hp.y, z, 0.8, c.accentDim)
    end
    local n = self.newRect
    local over = n.w * n.h > self.budget
    local edgeC = (over or not self:attached()) and c.danger or c.accent
    drawEdges(self, rectEdges(n), n.x, n.y, z, 0.95, edgeC)

    -- live area versus budget while dragging, red once over; a third
    -- line points at the house when the rect hangs loose or the house
    -- is too far away to see
    local midX = math.floor(self.width / 2)
    local header = n.w .. "x" .. n.h .. " = " .. (n.w * n.h) .. " / " .. self.budget
    local hint = getText("UI_AegisPlayer_ClaimHint")
    local extra = nil
    local dist = self:homeDistance()
    if dist and dist > FAR_TILES then
        extra = getText("UI_AegisPlayer_ClaimFarHint", tostring(dist))
    elseif self.home and not self:attached() then
        extra = getText("UI_AegisPlayer_ClaimHintAttach")
    end
    local w = math.max(Aegis.strW(UIFont.Medium, header), Aegis.strW(UIFont.Small, hint))
    if extra then w = math.max(w, Aegis.strW(UIFont.Small, extra)) end
    w = w + 48
    local boxH = extra and (62 + Aegis.fontH(UIFont.Small) + 4) or 62
    Aegis.roundFrame(self, midX - math.floor(w / 2), 24, w, boxH, 10, 0.95, edgeC, c.dark)
    Aegis.textCentre(self, header, midX, 32, UIFont.Medium, over and c.danger or c.text)
    local hy = 36 + Aegis.fontH(UIFont.Medium)
    Aegis.textCentre(self, hint, midX, hy, UIFont.Small, c.muted)
    if extra then
        Aegis.textCentre(self, extra, midX, hy + Aegis.fontH(UIFont.Small) + 4, UIFont.Small, c.danger)
    end
end

function AegisPlayerClaimEditor:onMouseDown(x, y)
    self.dragX, self.dragY = mouseTile()
    self.dragging = true
end

function AegisPlayerClaimEditor:onMouseUp(x, y)
    self.dragging = false
end

function AegisPlayerClaimEditor:onMouseUpOutside(x, y)
    self.dragging = false
end

function AegisPlayerClaimEditor:onRightMouseDown(x, y)
    self:finish()
end

function AegisPlayerClaimEditor:apply()
    if not self:valid() then return end
    local n = self.newRect
    self:finish()
    sendClientCommand(getPlayer(), MODULE, "claimSet", { x = n.x, y = n.y, w = n.w, h = n.h })
end

function AegisPlayerClaimEditor:isKeyConsumed(key)
    return key == Keyboard.KEY_ESCAPE or key == Keyboard.KEY_RETURN
end

function AegisPlayerClaimEditor:onKeyPress(key)
    if key == Keyboard.KEY_RETURN then
        self:apply()
        GameKeyboard.eatKeyPress(key)
    elseif key == Keyboard.KEY_ESCAPE then
        self:finish()
        GameKeyboard.eatKeyPress(key)
    end
end

-- ==================================================================
-- Page
-- ==================================================================
function AegisPlayerPageClaim.create(window, x, y, w, h)
    local o = ISPanel:new(x, y, w, h)
    setmetatable(o, AegisPlayerPageClaim)
    AegisPlayerPageClaim.__index = AegisPlayerPageClaim
    o.background = false
    o.window = window
    -- until the first claimInfoSync the budget comes from ppSync state
    o.info = { loaded = false, tiles = 0, used = 0, has = false }
    o.statusKey = nil
    o.statusPar = nil
    o.statusGood = false
    AegisPlayerPageClaim.instance = o
    return o
end

function AegisPlayerPageClaim:budget()
    if self.info.loaded then return self.info.tiles or 0 end
    local st = AegisPlayerClient and AegisPlayerClient.state
    if not st then return 0 end
    return math.max(0, math.floor(tonumber(st.claimTiles) or 0))
end

function AegisPlayerPageClaim:createChildren()
    local pad = 20
    local x = pad + 14
    -- four text lines above the buttons: attach hint, budget, used, status
    local y = pad + 46 + 4 * 26 + 16

    self.drawBtn = AegisButton:new(x, y, 190, 34, getText("UI_AegisPlayer_ClaimDraw"), "pin", self, AegisPlayerPageClaim.onDraw)
    self:addChild(self.drawBtn)

    self.releaseBtn = AegisButton:new(x + 190 + 12, y, 190, 34, getText("UI_AegisPlayer_ClaimRelease"), "trash", self, AegisPlayerPageClaim.onRelease)
    self.releaseBtn.style = "danger"
    self:addChild(self.releaseBtn)

    self:refreshButtons()
    requestInfo()
end

function AegisPlayerPageClaim:refreshButtons()
    local show = self:budget() > 0
    self.drawBtn:setVisible(show)
    self.releaseBtn:setVisible(show)
    -- drawing needs an own house to attach the zone to
    self.drawBtn:setEnabled(show and self.info.loaded and not self.info.has and self.info.home ~= nil)
    self.releaseBtn:setEnabled(show and self.info.loaded and self.info.has)
end

function AegisPlayerPageClaim.onDraw(self)
    if AegisPlayerClaimEditor.instance then return end
    if not self.info.loaded or self.info.has or not self.info.home then return end
    self.statusKey = nil
    AegisPlayerClaimEditor.start(self:budget(), self.info.home)
end

function AegisPlayerPageClaim.onRelease(self)
    if not self.info.has then return end
    self.statusKey = nil
    AegisConfirm.show(getText("UI_AegisPlayer_ClaimRelease"),
        getText("UI_AegisPlayer_ClaimReleaseConfirm"),
        getText("UI_AegisPlayer_ClaimRelease"), nil, function()
            sendClientCommand(getPlayer(), MODULE, "claimRelease", {})
        end)
end

function AegisPlayerPageClaim:onShow()
    requestInfo()
end

-- a resize rebuilds the page; carrying the last claim info over avoids
-- a flash of "no claim" until the server answers again
function AegisPlayerPageClaim:saveState()
    return { info = self.info }
end

function AegisPlayerPageClaim:restoreState(state)
    if type(state) == "table" and type(state.info) == "table" and state.info.loaded then
        self.info = state.info
    end
end

function AegisPlayerPageClaim:prerender()
    local c = AegisPlayerCol
    local pad = 20
    Aegis.roundFrame(self, pad, pad, self.width - pad * 2, self.height - pad * 2, 10, 1, c.line, c.panel)
    Aegis.icon(self, "home", pad + 14, pad + 12, 15, 1, c.accent)
    Aegis.text(self, getText("UI_AegisPlayer_NavClaim"), pad + 36, pad + 10, UIFont.Medium, c.text)

    local x = pad + 14
    local y = pad + 46
    if self:budget() <= 0 then
        -- role without claim budget: hint only, no controls
        Aegis.text(self, getText("UI_AegisPlayer_ClaimNoBudget"), x, y, UIFont.Small, c.muted)
        return
    end
    Aegis.text(self, getText("UI_AegisPlayer_ClaimAttachHint"), x, y, UIFont.Small, c.muted)
    y = y + 26
    Aegis.text(self, getText("UI_AegisPlayer_ClaimBudget", tostring(self:budget())), x, y, UIFont.Small, c.text)
    y = y + 26
    Aegis.text(self, getText("UI_AegisPlayer_ClaimUsed", tostring(self.info.used or 0)), x, y, UIFont.Small, c.text)
    y = y + 26
    if self.info.has then
        Aegis.text(self, getText("UI_AegisPlayer_ClaimStatusHas"), x, y, UIFont.Small, c.accentHi)
    elseif self.info.loaded and not self.info.home then
        Aegis.text(self, getText("UI_AegisPlayer_ClaimNeedHouse"), x, y, UIFont.Small, c.danger)
    else
        Aegis.text(self, getText("UI_AegisPlayer_ClaimStatusNone"), x, y, UIFont.Small, c.muted)
    end
    if self.statusKey then
        local sc = self.statusGood and c.ok or c.danger
        local text
        if self.statusPar then
            text = getText(self.statusKey, self.statusPar)
        else
            text = getText(self.statusKey)
        end
        Aegis.text(self, text, x, y + 26 + 34 + 16, UIFont.Small, sc)
    end
end

-- ---------- server replies ----------
local REASON_KEYS = {
    has = "UI_AegisPlayer_ClaimErrHas",
    budget = "UI_AegisPlayer_ClaimErrBudget",
    overlap = "UI_AegisPlayer_ClaimErrOverlap",
    near = "UI_AegisPlayer_ClaimErrNear",
    spawn = "UI_AegisPlayer_ClaimErrSpawn",
    days = "UI_AegisPlayer_ClaimErrDays",
    data = "UI_AegisPlayer_ClaimErrData",
    none = "UI_AegisPlayer_ClaimErrNone",
    failed = "UI_AegisPlayer_ClaimErrFailed",
    noHouse = "UI_AegisPlayer_ClaimErrNoHouse",
    off = "UI_AegisPlayer_ClaimErrOff",
    detached = "UI_AegisPlayer_ClaimErrDetached",
}

local function setStatus(page, args, okKey)
    if args.ok then
        page.statusKey = okKey
        page.statusGood = true
        page.statusPar = nil
        return
    end
    page.statusKey = REASON_KEYS[args.reason] or "UI_AegisPlayer_ClaimErrFailed"
    page.statusGood = false
    if args.reason == "days" then
        page.statusPar = tostring(math.floor(tonumber(args.need) or 0))
    else
        page.statusPar = nil
    end
end

Events.OnServerCommand.Add(function(module, command, args)
    if module ~= MODULE then return end
    local page = AegisPlayerPageClaim.instance
    if not page or not args then return end
    if command == "claimInfoSync" then
        local home = nil
        local ht = args.home
        if type(ht) == "table" and tonumber(ht.x) and tonumber(ht.y) and tonumber(ht.w) and tonumber(ht.h) then
            home = {
                x = math.floor(tonumber(ht.x)), y = math.floor(tonumber(ht.y)),
                w = math.floor(tonumber(ht.w)), h = math.floor(tonumber(ht.h)),
            }
        end
        page.info = {
            loaded = true,
            tiles = math.max(0, math.floor(tonumber(args.tiles) or 0)),
            used = math.max(0, math.floor(tonumber(args.used) or 0)),
            has = args.has == true,
            home = home,
        }
        page:refreshButtons()
    elseif command == "claimSet" then
        setStatus(page, args, "UI_AegisPlayer_ClaimDone")
    elseif command == "claimRelease" then
        setStatus(page, args, "UI_AegisPlayer_ClaimReleased")
    end
end)

-- ---------- registration ----------
-- the window file sorts after this one in the folder load order, so
-- try right away and once more when everything is loaded
local function registerPage()
    if AegisPlayerPageClaim.registered then return end
    if not (AegisPlayerWindow and AegisPlayerWindow.registerPage) then return end
    AegisPlayerPageClaim.registered = true
    AegisPlayerWindow.registerPage({
        id = "claim",
        icon = "home",
        label = "UI_AegisPlayer_NavClaim",
        create = AegisPlayerPageClaim.create,
    })
end

registerPage()
Events.OnGameStart.Add(registerPage)
