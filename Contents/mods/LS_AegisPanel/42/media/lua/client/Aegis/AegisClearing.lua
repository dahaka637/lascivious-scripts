-- Clear area: drag a rectangle, confirm. First pass removes only
-- vegetation, a second pass on the same (now bare) area then removes
-- everything except the floor. The server decides purely from the
-- current world state (see server/Aegis_Clearing.lua), no state kept
-- in the client. Rectangle drawing and mouse-to-tile conversion follow
-- the pattern from AegisPageZones.lua (vehicle placer technique,
-- isoToScreen as anchor + XToScreen deltas).
require "Aegis/AegisTheme"
require "Aegis/AegisWidgets"

AegisClearing = AegisClearing or {}

local MAX_EDGE = 24

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

-- ---------- Preview count: same rule as the server, read only ----------
local function preview(x, y, w, h, z)
    local mode, count, notLoaded = "all", 0, 0
    local found = false
    for tx = x, x + w - 1 do
        for ty = y, y + h - 1 do
            if not found then
                local sq = getSquare(tx, ty, z)
                if not sq then
                    notLoaded = notLoaded + 1
                else
                    local objects = sq:getObjects()
                    for i = 0, objects:size() - 1 do
                        if AegisShared.isVegetation(objects:get(i)) then
                            found = true
                            break
                        end
                    end
                end
            end
        end
    end
    if found then mode = "vegetation" end
    -- second pass just for counting, with the mode now fixed
    for tx = x, x + w - 1 do
        for ty = y, y + h - 1 do
            local sq = getSquare(tx, ty, z)
            if sq then
                local objects = sq:getObjects()
                local floor = sq:getFloor()
                for i = 0, objects:size() - 1 do
                    local obj = objects:get(i)
                    if obj and obj ~= floor then
                        if mode == "vegetation" then
                            if AegisShared.isVegetation(obj) then count = count + 1 end
                        else
                            count = count + 1
                        end
                    end
                end
            end
        end
    end
    return mode, count, notLoaded
end

-- ==================================================================
-- Editor: fullscreen over the world, drag rectangle, Enter confirms
-- ==================================================================
AegisClearingEditor = ISPanel:derive("AegisClearingEditor")
AegisClearingEditor.instance = nil

function AegisClearing.start()
    if AegisClearingEditor.instance then return end
    if not Aegis.canSee("tools") then return end
    local sw, sh = getCore():getScreenWidth(), getCore():getScreenHeight()
    local o = ISPanel:new(0, 0, sw, sh)
    setmetatable(o, AegisClearingEditor)
    AegisClearingEditor.__index = AegisClearingEditor
    o.background = false
    o.dragging = false
    local tx, ty = mouseTile()
    o.newRect = { x = tx, y = ty, w = 1, h = 1 }
    o:initialise()
    o:addToUIManager()
    o:setAlwaysOnTop(true)
    o:setWantKeyEvents(true)
    AegisClearingEditor.instance = o
    if AegisWindow.instance then AegisWindow.instance:setVisible(false) end
    return o
end

function AegisClearingEditor:finish()
    self:removeFromUIManager()
    AegisClearingEditor.instance = nil
    if AegisWindow.instance then AegisWindow.instance:setVisible(true) end
end

function AegisClearingEditor:render()
    local c = Aegis.col
    local z = playerLevel()
    if self.dragging then
        local mx, my = mouseTile()
        local x1, x2 = math.min(self.dragX, mx), math.max(self.dragX, mx)
        local y1, y2 = math.min(self.dragY, my), math.max(self.dragY, my)
        if x2 - x1 + 1 > MAX_EDGE then x2 = x1 + MAX_EDGE - 1 end
        if y2 - y1 + 1 > MAX_EDGE then y2 = y1 + MAX_EDGE - 1 end
        self.newRect = { x = x1, y = y1, w = x2 - x1 + 1, h = y2 - y1 + 1 }
    end
    local n = self.newRect
    drawEdges(self, rectEdges(n), n.x, n.y, z, 0.95, c.danger)

    local midX = math.floor(self.width / 2)
    local header = n.w .. "x" .. n.h
    local hint = getText("UI_Aegis_ClearAreaHint")
    local w = math.max(Aegis.strW(UIFont.Medium, header), Aegis.strW(UIFont.Small, hint)) + 48
    Aegis.roundFrame(self, midX - math.floor(w / 2), 24, w, 62, 10, 0.95, c.danger, c.dark)
    Aegis.textCentre(self, header, midX, 32, UIFont.Medium, c.text)
    Aegis.textCentre(self, hint, midX, 36 + Aegis.fontH(UIFont.Medium), UIFont.Small, c.muted)
end

function AegisClearingEditor:onMouseDown(x, y)
    self.dragX, self.dragY = mouseTile()
    self.dragging = true
end

function AegisClearingEditor:onMouseUp(x, y)
    self.dragging = false
end

function AegisClearingEditor:onMouseUpOutside(x, y)
    self.dragging = false
end

function AegisClearingEditor:onRightMouseDown(x, y)
    self:finish()
end

function AegisClearingEditor:apply()
    local n = self.newRect
    local z = playerLevel()
    local mode, count, notLoaded = preview(n.x, n.y, n.w, n.h, z)
    self:finish()
    if count == 0 and notLoaded == 0 then
        Aegis.showToast(getText("UI_Aegis_ClearAreaEmpty"))
        return
    end
    local title = getText("UI_Aegis_ClearArea")
    local text
    if mode == "vegetation" then
        text = getText("UI_Aegis_ClearAreaConfirmVeg", count, n.w, n.h)
    else
        text = getText("UI_Aegis_ClearAreaConfirmAll", count, n.w, n.h)
    end
    if notLoaded > 0 then
        text = text .. " " .. getText("UI_Aegis_ClearAreaUnloaded", notLoaded)
    end
    AegisConfirm.show(title, text, title, nil, function()
        sendClientCommand(getPlayer(), AegisShared.MODULE, "clearing", { x = n.x, y = n.y, z = z, w = n.w, h = n.h })
    end)
end

function AegisClearingEditor:isKeyConsumed(key)
    return key == Keyboard.KEY_ESCAPE or key == Keyboard.KEY_RETURN
end

function AegisClearingEditor:onKeyPress(key)
    if key == Keyboard.KEY_RETURN then
        self:apply()
        GameKeyboard.eatKeyPress(key)
    elseif key == Keyboard.KEY_ESCAPE then
        self:finish()
        GameKeyboard.eatKeyPress(key)
    end
end

-- reverts this admin's last executed clearing, no confirmation dialog
-- on purpose: this is the fast correction path for "did it wrong by
-- accident", not another prompt
function AegisClearing.undo()
    if not Aegis.canSee("tools") then return end
    sendClientCommand(getPlayer(), AegisShared.MODULE, "clearingUndo", {})
end

Events.OnServerCommand.Add(function(module, command, args)
    if module ~= AegisShared.MODULE then return end
    if command == "clearingStart" and args and args.ok == false then
        -- queue full: without this the confirm would be silent for the
        -- admin, since otherwise only clearingDone ever raises a toast
        Aegis.showToast(getText("UI_Aegis_BackupBusy"))
    elseif command == "clearingDone" and args then
        local key = args.mode == "vegetation" and "UI_Aegis_ClearAreaDoneVeg" or "UI_Aegis_ClearAreaDoneAll"
        local text = getText(key, args.removed or 0)
        if (args.notRestorable or 0) > 0 then
            text = text .. " " .. getText("UI_Aegis_ClearAreaNotRestorable", args.notRestorable)
        end
        Aegis.showToast(text)
    elseif command == "clearingUndoDone" and args then
        if args.none then
            Aegis.showToast(getText("UI_Aegis_ClearAreaNoLast"))
        else
            Aegis.showToast(getText("UI_Aegis_ClearAreaUndoDone", args.restored or 0))
        end
    end
end)
