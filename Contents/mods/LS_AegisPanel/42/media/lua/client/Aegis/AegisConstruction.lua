-- Construction radar, client side: hover tooltip over stamped objects.
-- The overlay is a click-through fullscreen element and only exists
-- while the radar is on; when off nothing runs per frame.
-- Stamps already sit locally in modData (build packet, furniture sync,
-- existing ones via chunk streaming), so no server request per hover.
require "Aegis/AegisTheme"
require "Aegis/AegisWidgets"
require "Aegis/AegisBuilder"

AegisConstruction = AegisConstruction or {}

AegisConstructionOverlay = ISPanel:derive("AegisConstructionOverlay")
AegisConstructionOverlay.instance = nil

function AegisConstruction.isOn()
    return AegisConstructionOverlay.instance ~= nil
end

function AegisConstruction.setOn(on)
    if on and not AegisConstructionOverlay.instance then
        if not Aegis.canSee("tools") then return end
        local sw, sh = getCore():getScreenWidth(), getCore():getScreenHeight()
        local o = ISPanel:new(0, 0, sw, sh)
        setmetatable(o, AegisConstructionOverlay)
        AegisConstructionOverlay.__index = AegisConstructionOverlay
        o.background = false
        o:initialise()
        o:addToUIManager()
        o.javaObject:setConsumeMouseEvents(false)
        AegisConstructionOverlay.instance = o
    elseif not on and AegisConstructionOverlay.instance then
        AegisConstructionOverlay.instance:removeFromUIManager()
        AegisConstructionOverlay.instance = nil
    end
end

function AegisConstruction.toggle()
    AegisConstruction.setOn(not AegisConstruction.isOn())
end

-- ---------- tooltip card ----------
local PAD = 10

local function drawCard(el, card)
    local c = Aegis.col
    local f = UIFont.Small
    local lineH = Aegis.fontH(f)
    local header = getText("UI_Aegis_BuildTooltipBy")
    local sprite = Aegis.fitText(card.sprite, f, 240)
    local w = math.max(
        lineH + 6 + Aegis.strW(f, header) + 6 + Aegis.strW(f, card.name),
        Aegis.strW(f, card.time),
        Aegis.strW(f, sprite)) + PAD * 2
    local h = PAD * 2 + lineH * 3 + 8

    local mx, my = getMouseX(), getMouseY()
    local sw, sh = getCore():getScreenWidth(), getCore():getScreenHeight()
    local x, y = mx + 18, my + 18
    if x + w > sw - 6 then x = mx - w - 6 end
    if y + h > sh - 6 then y = my - h - 6 end

    Aegis.roundFrame(el, x, y, w, h, 8, 0.95, c.gold, c.dark)
    local tx, ty = x + PAD, y + PAD
    Aegis.icon(el, "pin", tx, ty, lineH, 1, c.gold)
    Aegis.text(el, header, tx + lineH + 6, ty, f, c.muted)
    Aegis.text(el, card.name, tx + lineH + 6 + Aegis.strW(f, header) + 6, ty, f, c.goldHi)
    ty = ty + lineH + 4
    Aegis.text(el, card.time, tx, ty, f, c.text)
    ty = ty + lineH + 4
    Aegis.text(el, sprite, tx, ty, f, c.muted)
end

-- UIManager.getLastPicked does NOT work: UIManager.updateTooltip
-- (bytecode verified) first looks for a UI element under the mouse each
-- frame and aborts the world object search entirely once one is found,
-- a check that runs purely on the bounding box and ignores
-- setConsumeMouseEvents. Our own click-through fullscreen overlay
-- satisfies that check itself every frame, so UIManager.lastPicked stays
-- nil the WHOLE time the radar is on, regardless of object type; that
-- is the real cause, not the cache timing.
-- Picking via IsoObjectPicker directly (vanilla pattern in
-- server/ISObjectClickHandler.lua) bypasses UIManager.lastPicked, and
-- trying several types covers everything Aegis_Construction.lua stamps
-- (walls/doors/windows/build stations)
local function pickObject()
    local mx, my = getMouseX(), getMouseY()
    local obj = IsoObjectPicker.Instance:PickThumpable(mx, my)
    if obj then return obj end
    obj = IsoObjectPicker.Instance:PickDoor(mx, my, true)
    if obj then return obj end
    obj = IsoObjectPicker.Instance:PickWindow(mx, my)
    if obj then return obj end
    obj = IsoObjectPicker.Instance:PickWindowFrame(mx, my)
    if obj then return obj end
    obj = IsoObjectPicker.Instance:PickHoppable(mx, my)
    if obj then return obj end
    -- floors have no engine picker: resolve the square under the mouse on
    -- the player's level and use its floor object (the stamp check in the
    -- caller keeps unstamped map floors silent)
    local p = getPlayer()
    if p then
        local z = math.floor(p:getZ())
        local wx = math.floor(screenToIsoX(0, mx, my, z))
        local wy = math.floor(screenToIsoY(0, mx, my, z))
        local sq = getCell():getGridSquare(wx, wy, z)
        if sq then obj = sq:getFloor() end
    end
    return obj
end

function AegisConstructionOverlay:update()
    ISPanel.update(self)
    self.picked = pickObject()
end

function AegisConstructionOverlay:render()
    local obj = self.picked
    if not obj then
        self.lastObj = nil
        return
    end
    -- over the Aegis window the window wins, otherwise the card sticks to it
    local window = AegisWindow and AegisWindow.instance
    if window and window:isVisible() and window:isMouseOver() then return end

    -- cache the stamp per object briefly, the freshness cap still
    -- catches modData syncs that arrive late
    local now = getTimestampMs()
    if obj ~= self.lastObj or now >= (self.freshUntil or 0) then
        self.lastObj = obj
        self.freshUntil = now + 500
        self.card = nil
        local raw = nil
        if obj:hasModData() then raw = obj:getModData().aegisBuild or obj:getModData().aegisBau end
        if type(raw) == "string" then
            local name, epoch = raw:match("^([^|]+)|(%d+)$")
            if name then
                local sprite = nil
                local spr = obj:getSprite()
                if spr then sprite = spr:getName() end
                self.card = {
                    name = name,
                    time = AegisShared.timestampReadable(tonumber(epoch) or 0),
                    sprite = sprite or "?",
                }
            end
        end
    end

    if self.card then
        drawCard(self, self.card)
    end
end

-- ---------- restore ghost preview ----------
--: before rebuilding, show WHAT stood there as a ghost
-- in the world instead of only a sprite name in a text confirm. The
-- fullscreen layer stays click-through and only draws; the card at the
-- bottom is its own small panel and carries the actual buttons, so the
-- world stays playable while the preview is up
AegisRestorePreview = AegisRestorePreview or {}

local PreviewLayer = ISPanel:derive("AegisRestorePreviewLayer")
local PreviewCard = ISPanel:derive("AegisRestorePreviewCard")

function AegisRestorePreview.isOn()
    return AegisRestorePreview.layer ~= nil
end

function AegisRestorePreview.stop()
    if AegisRestorePreview.layer then
        AegisRestorePreview.layer:removeFromUIManager()
    end
    if AegisRestorePreview.card then
        AegisRestorePreview.card:removeFromUIManager()
    end
    -- bring the panel back only if the preview actually took it away
    if AegisRestorePreview.layer and AegisWindow.instance then
        AegisWindow.instance:setVisible(true)
    end
    AegisRestorePreview.layer = nil
    AegisRestorePreview.card = nil
    AegisRestorePreview.row = nil
end

function AegisRestorePreview.start(row)
    AegisRestorePreview.stop()
    if not row or not row.x then return end
    AegisRestorePreview.row = row

    -- multi tile structures bring their full piece list, single pieces
    -- become a one-entry list; painter order back to front so nearer
    -- pieces cover farther ones like the engine would
    local pieces = {}
    if row.parts then
        for _, p in ipairs(row.parts) do table.insert(pieces, p) end
    else
        table.insert(pieces, { x = row.x, y = row.y, z = row.z, sprite = row.sprite })
    end
    table.sort(pieces, function(a, b)
        if a.z ~= b.z then return a.z < b.z end
        return (a.x + a.y) < (b.x + b.y)
    end)

    local sw, sh = getCore():getScreenWidth(), getCore():getScreenHeight()
    local layer = ISPanel:new(0, 0, sw, sh)
    setmetatable(layer, PreviewLayer)
    PreviewLayer.__index = PreviewLayer
    layer.background = false
    layer.pieces = pieces
    layer:initialise()
    layer:addToUIManager()
    layer.javaObject:setConsumeMouseEvents(false)
    AegisRestorePreview.layer = layer
    -- same pattern as the build brush: the panel steps aside so the
    -- ghost is actually visible, stop brings it back
    if AegisWindow.instance then AegisWindow.instance:setVisible(false) end

    -- top left by default so the ghost in the world stays clear, and the
    -- admin can drag the card wherever it suits; the spot is remembered
    local cardW, cardH = 470, 132
    local cx = tonumber(Aegis.getPref("restoreCardX")) or 40
    local cy = tonumber(Aegis.getPref("restoreCardY")) or 90
    cx = math.max(0, math.min(cx, sw - cardW))
    cy = math.max(0, math.min(cy, sh - cardH))
    local card = ISPanel:new(cx, cy, cardW, cardH)
    setmetatable(card, PreviewCard)
    PreviewCard.__index = PreviewCard
    card.background = false
    card.row = row
    card:initialise()
    card:addToUIManager()
    card:setAlwaysOnTop(true)

    local bw = math.floor((cardW - 16 * 2 - 12 * 2) / 3)
    local by = cardH - 46
    local jump = AegisButton:new(16, by, bw, 34, getText("UI_Aegis_FactionJump"), nil, card, function(panel)
        Aegis.teleportSmart(panel.row.x, panel.row.y, panel.row.z)
        Aegis.logAction("world", string.format("Restore preview teleport to %d,%d,%d", panel.row.x, panel.row.y, panel.row.z))
    end)
    if not Aegis.canSee("world") then jump:setEnabled(false) end
    card:addChild(jump)
    local confirm = AegisButton:new(16 + bw + 12, by, bw, 34, getText("UI_Aegis_ClRestore"), nil, card, function(panel)
        -- the card carries its own status line: the window toast lives in
        -- a header this preview has hidden, so a refusal used to be
        -- invisible and the button looked dead
        panel.status = getText("UI_Aegis_ClRestore") .. "..."
        AegisConstruction.requestRestore(panel.row)
        -- keep the preview up until the server answers: on success the
        -- OnServerCommand handler below closes it, on failure the admin
        -- keeps the ghost for a second try or a screenshot
    end)
    confirm.style = "gold"
    card:addChild(confirm)
    local cancel = AegisButton:new(16 + (bw + 12) * 2, by, bw, 34, getText("UI_Aegis_Cancel"), nil, card, function()
        AegisRestorePreview.stop()
    end)
    card:addChild(cancel)
    AegisRestorePreview.card = card
end

function PreviewLayer:render()
    local c = Aegis.col
    for _, p in ipairs(self.pieces) do
        AegisBuilder.drawTile(self, p.x, p.y, p.z, 0.9, c.gold)
        AegisBuilder.drawGhost(self, p.sprite, p.x, p.y, p.z, 0.55)
    end
end

function PreviewCard:prerender()
    local c = Aegis.col
    local f = UIFont.Small
    Aegis.shadow(self, 0, 0, self.width, self.height, 20, 0.6)
    Aegis.roundFrame(self, 0, 0, self.width, self.height, 12, 1, c.gold, c.bg)
    Aegis.icon(self, "refresh", 16, 14, 15, 1, c.gold)
    Aegis.text(self, getText("UI_Aegis_ClRestore"), 38, 12, UIFont.Medium, c.text)
    if self.status then
        Aegis.text(self, self.status, 16, self.height - 72, f, c.goldHi)
    end
    -- live distance so the admin sees right away whether the ghost can
    -- even be on screen or a jump is needed first
    local where = self.row.x .. "," .. self.row.y .. "," .. self.row.z
    local p = getPlayer()
    if p then
        local dx, dy = p:getX() - self.row.x, p:getY() - self.row.y
        local d = math.floor(math.sqrt(dx * dx + dy * dy))
        where = where .. "  (" .. d .. "m)"
    end
    Aegis.textRight(self, where, self.width - 16, 16, f, c.goldDim)
    Aegis.text(self, getText("UI_Aegis_ClPreviewHint"), 16, 14 + Aegis.fontH(UIFont.Medium) + 6, f, c.muted)
end

-- draggable by its own body, the buttons keep their clicks
function PreviewCard:onMouseDown(x, y)
    self:bringToTop()
    self.dragging = true
end

function PreviewCard:onMouseMove(dx, dy)
    if not self.dragging then return end
    local sw, sh = getCore():getScreenWidth(), getCore():getScreenHeight()
    self:setX(math.max(0, math.min(self.x + dx, sw - self.width)))
    self:setY(math.max(0, math.min(self.y + dy, sh - self.height)))
end

function PreviewCard:onMouseMoveOutside(dx, dy)
    self:onMouseMove(dx, dy)
end

function PreviewCard:onMouseUp(x, y)
    if not self.dragging then return end
    self.dragging = false
    Aegis.setPref("restoreCardX", math.floor(self.x))
    Aegis.setPref("restoreCardY", math.floor(self.y))
end

function PreviewCard:onMouseUpOutside(x, y)
    self:onMouseUp(x, y)
end

-- ---------- journal fetch for the panel ----------
-- response lands in AegisConstruction.list; a future display page
-- hooks in via AegisConstruction.onList
function AegisConstruction.requestList(date, n)
    if not Aegis.canSee("tools") then return end
    local args = { n = n or 100 }
    if date then args.date = date end
    sendClientCommand(getPlayer(), AegisShared.MODULE, "constructionList", args)
end

-- rebuild a demolished piece; kind/north come straight from the log row
-- (server Aegis_Construction.lua chooses the actual primitive). Multi
-- tile structures carry their full piece list, one click restores all
function AegisConstruction.requestRestore(row)
    if not Aegis.canSee("tools") then return end
    sendClientCommand(getPlayer(), AegisShared.MODULE, "constructionRestore", {
        x = row.x, y = row.y, z = row.z, sprite = row.sprite,
        kind = row.kind, north = row.north == true,
        parts = row.parts,
    })
end

Events.OnServerCommand.Add(function(module, command, args)
    if module ~= AegisShared.MODULE then return end
    if command == "constructionList" then
        AegisConstruction.list = args
        if AegisConstruction.onList then AegisConstruction.onList(args) end
    elseif command == "constructionRestore" then
        local text
        if args and args.ok then
            text = getText("UI_Aegis_ClRestored")
        elseif args and (args.reason == "stairs" or args.reason == "garage") then
            text = getText("UI_Aegis_ClRestoreStairs")
        else
            text = getText("UI_Aegis_ClRestoreFailed")
        end
        Aegis.showToast(text)
        if args and args.ok then
            -- the rebuilt piece now stands where the ghost was
            AegisRestorePreview.stop()
        elseif AegisRestorePreview.card then
            AegisRestorePreview.card.status = text
        end
    elseif command == "denied" and AegisRestorePreview.card then
        -- a refusal must be readable on the card, not only as world text;
        -- same two keys the generic handler in AegisHud uses
        AegisRestorePreview.card.status = getText(
            (args and args.reason == "capability") and "UI_Aegis_DeniedCap" or "UI_Aegis_Denied")
    end
end)
