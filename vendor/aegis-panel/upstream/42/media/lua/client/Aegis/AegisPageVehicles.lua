-- Vehicles: search, big rotatable 3D stage, hologram placement with
-- degree rotation, key in the ignition, remove vehicles
require "Aegis/AegisWindow"
require "Aegis/AegisVehicleDetail"
require "ISUI/ISScrollingListBox"
require "ISUI/ISTextEntryBox"
require "Vehicles/ISUI/ISUI3DScene"

AegisPageVehicles = ISPanel:derive("AegisPageVehicles")

local LIST_W = 270
local ROW_H = 32

-- ==================================================================
-- Stage with real drag rotation (pattern AnimationClipViewer):
-- drag rotates, Shift+drag pans, mouse wheel zooms
-- ==================================================================
AegisVehicleScene = ISUI3DScene:derive("AegisVehicleScene")

function AegisVehicleScene:onMouseDown(x, y)
    ISUI3DScene.onMouseDown(self, x, y)
    self.rotating = not (isKeyDown(Keyboard.KEY_LSHIFT) or isKeyDown(Keyboard.KEY_RSHIFT))
end

function AegisVehicleScene:onMouseMove(dx, dy)
    if self.mouseDown and self.rotating then
        local current = self.javaObject:fromLua0("getViewRotation")
        local rx = math.max(-20, math.min(70, current:x() + dy / 4))
        local ry = current:y() + dx / 2
        self.javaObject:fromLua3("setViewRotation", rx, ry, current:z())
        return
    end
    ISUI3DScene.onMouseMove(self, dx, dy)
end

function AegisVehicleScene:onMouseUp(x, y)
    ISUI3DScene.onMouseUp(self, x, y)
    self.rotating = false
end

function AegisVehicleScene:onMouseUpOutside(x, y)
    ISUI3DScene.onMouseUpOutside(self, x, y)
    self.rotating = false
end

-- ==================================================================
-- Placement mode: fullscreen overlay, footprint plus 3D hologram at
-- the cursor, mouse wheel rotates by single degrees, R in 30 steps
-- ==================================================================
AegisVehiclePlacer = ISPanel:derive("AegisVehiclePlacer")
AegisVehiclePlacer.instance = nil

function AegisVehiclePlacer.start(vehicle)
    if AegisVehiclePlacer.instance then return end
    local sw, sh = getCore():getScreenWidth(), getCore():getScreenHeight()
    local o = ISPanel:new(0, 0, sw, sh)
    setmetatable(o, AegisVehiclePlacer)
    AegisVehiclePlacer.__index = AegisVehiclePlacer
    o.background = false
    o.vehicle = vehicle
    o.angle = 0
    -- footprint and height from the physics extents. Only guard against
    -- degenerate values; generous minimums (previously 0.8/1.6) painted
    -- the van footprint almost twice as large as the vehicle itself
    local ext = vehicle.script:getExtents()
    o.halfW = math.max(0.3, ext:x() / 2)
    o.halfL = math.max(0.6, ext:z() / 2)
    o.bodyHeight = math.max(0.5, ext:y())
    o:initialise()
    o:addToUIManager()
    o:setAlwaysOnTop(true)
    o:setWantKeyEvents(true)
    AegisVehiclePlacer.instance = o
    if AegisWindow.instance then
        AegisWindow.instance:setVisible(false)
    end
    o:createHologram()
    return o
end

-- floating 3D model above the cursor; the Java scene does not clear its
-- own background, without a Lua background only the model remains
function AegisVehiclePlacer:createHologram()
    local placer = self
    pcall(function()
        local holo = ISUI3DScene:new(0, 0, 240, 190)
        holo.background = false
        holo:initialise()
        holo:instantiate()
        self:addChild(holo)
        local jo = holo.javaObject
        jo:fromLua1("setDrawGrid", false)
        jo:fromLua1("setDrawGridAxes", false)
        jo:fromLua1("createVehicle", "vehicle")
        jo:fromLua2("setVehicleScript", "vehicle", self.vehicle.full)
        -- without a UserDefined view the scene ignores every setViewRotation
        jo:fromLua1("setView", "UserDefined")
        jo:fromLua1("setMaxZoom", 20)
        jo:fromLua1("setZoom", 5)
        -- input belongs to the placer, not the preview
        holo.onMouseDown = function(s, x, y) placer:onMouseDown(placer:getMouseX(), placer:getMouseY()) end
        holo.onRightMouseDown = function(s, x, y) placer:onRightMouseDown(x, y) end
        holo.onMouseWheel = function(s, del) return placer:onMouseWheel(del) end
        holo.onMouseMove = function() end
        holo.onMouseUp = function() end
        self.holo = holo
    end)
end

-- the result toast arrives in every mode with the server reply (AegisHud)
function AegisVehiclePlacer:finish()
    self:removeFromUIManager()
    AegisVehiclePlacer.instance = nil
    if AegisWindow.instance then
        AegisWindow.instance:setVisible(true)
    end
end

-- mouse to world per the vanilla idiom (ISMenuContextWorld: UI coordinate times zoom)
function AegisVehiclePlacer:mouseWorld()
    local p = getPlayer()
    local z = p and math.floor(p:getZ()) or 0
    local zoom = getCore():getZoom(0)
    local wx = IsoUtils.XToIso(getMouseX() * zoom, getMouseY() * zoom, z)
    local wy = IsoUtils.YToIso(getMouseX() * zoom, getMouseY() * zoom, z)
    return math.floor(wx), math.floor(wy), z
end

-- convert a world corner relative to the anchor into UI pixels; camera
-- offset and JigglyFix cancel out in the difference
local function cornerToUI(ax, ay, cx, cy, px, py, z)
    local zoom = getCore():getZoom(0)
    local dx = (IsoUtils.XToScreen(px, py, z, 0) - IsoUtils.XToScreen(cx, cy, z, 0)) / zoom
    local dy = (IsoUtils.YToScreen(px, py, z, 0) - IsoUtils.YToScreen(cx, cy, z, 0)) / zoom
    return ax + dx, ay + dy
end

function AegisVehiclePlacer:render()
    local c = Aegis.col
    local wx, wy, z = self:mouseWorld()
    -- the anchor is exactly where the engine spawns: addVehicleDebug
    -- calls setX(square.x) WITHOUT +0.5 (bytecode), so the tile CORNER.
    -- With a cell-center anchor the vehicle stood half a tile off the
    -- preview. isoToScreenX/Y handle camera offset and zoom in one go
    local cx, cy = wx, wy
    local anchorX = isoToScreenX(0, cx, cy, z)
    local anchorY = isoToScreenY(0, cx, cy, z)

    -- footprint corners rotated by the angle
    local rad = math.rad(self.angle)
    local cosA, sinA = math.cos(rad), math.sin(rad)
    local base = {
        { -self.halfW, -self.halfL }, { self.halfW, -self.halfL },
        { self.halfW, self.halfL }, { -self.halfW, self.halfL },
    }
    local pts = {}
    for i, corner in ipairs(base) do
        local rx = corner[1] * cosA - corner[2] * sinA
        local ry = corner[1] * sinA + corner[2] * cosA
        local sx, sy = cornerToUI(anchorX, anchorY, cx, cy, cx + rx, cy + ry, z)
        pts[i] = { x = sx, y = sy }
    end
    -- golden outline, drawn twice for glow
    for i = 1, 4 do
        local a, b = pts[i], pts[i % 4 + 1]
        self:drawLine2(a.x, a.y, b.x, b.y, 0.9, c.goldHi.r, c.goldHi.g, c.goldHi.b)
        self:drawLine2(a.x, a.y + 1, b.x, b.y + 1, 0.5, c.gold.r, c.gold.g, c.gold.b)
    end
    self:drawLine2(pts[1].x, pts[1].y, pts[3].x, pts[3].y, 0.25, c.gold.r, c.gold.g, c.gold.b)
    self:drawLine2(pts[2].x, pts[2].y, pts[4].x, pts[4].y, 0.25, c.gold.r, c.gold.g, c.gold.b)

    -- anchor the hologram on the ground cell: couple the scene zoom to
    -- the world zoom (pixels per meter of the world camera:
    -- PX_PER_METER/worldZoom, derived from calcMatrices:
    -- width times e^(0.2*level) = SCALE/worldZoom)
    if self.holo then
        pcall(function()
            local SCALE = 1406
            local PX_PER_METER = 90.5
            local worldZoom = getCore():getZoom(0)
            local pxPerMeter = PX_PER_METER / worldZoom
            -- frame as big as the vehicle really needs: footprint diagonal
            -- plus half the height, with a safety margin for the slanted
            -- camera and arbitrary rotation. Cap by screen height instead
            -- of a fixed 700px: when zooming in the model needs more pixels
            -- per meter and the fixed cap cut half of it off
            local radius = math.sqrt(self.halfW * self.halfW + self.halfL * self.halfL) + self.bodyHeight * 0.5
            local cap = math.max(400, getCore():getScreenHeight() - 40)
            local desiredWidth = math.max(160, math.min(cap, math.floor(radius * pxPerMeter * 2 * 1.35 + 40)))
            local level = math.max(1, math.min(20, math.floor(5 * math.log(SCALE / (worldZoom * desiredWidth)) + 0.5)))
            local width = math.floor(SCALE / (worldZoom * math.exp(0.2 * level)))
            if level ~= self.holoLevel then
                self.holoLevel = level
                self.holo.javaObject:fromLua1("setZoom", level)
            end
            if width ~= self.holo.width then
                self.holo:setWidth(width)
                self.holo:setHeight(width)
            end
            -- camera pitch 30 degrees like the world dimetry. Base yaw 135:
            -- the footprint long axis (world +Y) projects onto screen
            -- direction (-2,1), satisfied by -45 - angle and 135 - angle
            -- (45 - angle sat 90 degrees sideways); the footprint is front
            -- symmetric, only the live comparison with the spawned vehicle
            -- decided for 135 (at -45 the front faced the wrong way)
            self.holo.javaObject:fromLua3("setViewRotation", 30, 135 - self.angle, 0)
            -- the vehicle origin IS the ground plane and projects onto the
            -- widget center, so the widget is simply centered on the anchor
            -- (the earlier ground offset lifted the model too high)
            self.holo:setX(math.floor(anchorX) - math.floor(width / 2))
            self.holo:setY(math.floor(anchorY) - math.floor(width / 2))
        end)
    end

    -- header with name, angle and control hint
    local midX = math.floor(self.width / 2)
    local label = self.vehicle.display .. "  (" .. tostring(self.angle) .. "\194\176)"
    local hint = getText("UI_Aegis_PlaceHint")
    local w = math.max(Aegis.strW(UIFont.Medium, label), Aegis.strW(UIFont.Small, hint)) + 48
    Aegis.roundFrame(self, midX - math.floor(w / 2), 24, w, 62, 10, 0.95, c.gold, c.dark)
    Aegis.textCentre(self, label, midX, 32, UIFont.Medium, c.goldHi)
    Aegis.textCentre(self, hint, midX, 36 + Aegis.fontH(UIFont.Medium), UIFont.Small, c.muted)
end

function AegisVehiclePlacer:onMouseDown(x, y)
    local wx, wy, z = self:mouseWorld()
    -- one path for solo and MP: the loopback fires OnClientCommand in
    -- singleplayer too, spawn and log run in the server handler, the
    -- result toast arrives with the reply
    sendClientCommand(getPlayer(), "AegisAdmin", "spawnvehicle", {
        script = self.vehicle.full, name = self.vehicle.display,
        x = wx, y = wy, z = z, angle = self.angle,
        wear = AegisPageVehicles.wear,
    })
    self:finish()
end

function AegisVehiclePlacer:onRightMouseDown(x, y)
    self:finish()
end

-- mouse wheel: fine tuning in 1 degree steps
function AegisVehiclePlacer:onMouseWheel(del)
    self.angle = (self.angle - del) % 360
    return true
end

-- consume keys ourselves, otherwise ESC also opens the pause menu
-- and R reloads the weapon (pattern ISVehicleSeatUI)
function AegisVehiclePlacer:isKeyConsumed(key)
    return key == Keyboard.KEY_ESCAPE or key == Keyboard.KEY_R
end

function AegisVehiclePlacer:onKeyPress(key)
    if key == Keyboard.KEY_R then
        self.angle = (self.angle + 30) % 360
        Aegis.sound()
    elseif key == Keyboard.KEY_ESCAPE then
        self:finish()
        GameKeyboard.eatKeyPress(key)
    end
end

-- ==================================================================
-- Page
-- ==================================================================

function AegisPageVehicles.create(window, x, y, w, h)
    local o = ISPanel:new(x, y, w, h)
    setmetatable(o, AegisPageVehicles)
    AegisPageVehicles.__index = AegisPageVehicles
    o.background = false
    o.window = window
    o.vehicles = nil
    return o
end

function AegisPageVehicles:buildCache()
    if self.vehicles then return end
    self.vehicles = {}
    local scripts = getScriptManager():getAllVehicleScripts()
    for i = 1, scripts:size() do
        local script = scripts:get(i - 1)
        local raw = script:getName()
        local name = string.lower(raw)
        -- the smashed entries are damage states of a car that is already in
        -- the list; the burnt ones are separate wrecks and belong in it
        local wreck = string.contains(name, "burnt")
        if not string.contains(name, "smashed") then
            local display = getTextOrNull("IGUI_VehicleName" .. raw)
            if not display and wreck then
                -- only a third of the burnt scripts carry their own name,
                -- the rest fall back to the intact model plus the row tag
                local base = raw:gsub("[Bb]urnt", "")
                display = getTextOrNull("IGUI_VehicleName" .. base)
            end
            display = display or raw
            local seats = script:getPassengerCount()
            table.insert(self.vehicles, {
                full = script:getFullName(),
                display = display,
                script = script,
                seats = seats,
                wreck = wreck,
                trailer = string.lower(script:getFullName()):find("trailer", 1, true) ~= nil,
                search = string.lower(display .. " " .. script:getFullName()),
            })
        end
    end
    table.sort(self.vehicles, function(a, b) return a.display < b.display end)
end

local WEAR_H = 28

local WEAR_CHOICES = {
    { key = "new",   label = "UI_Aegis_WearNew",   tip = "UI_Aegis_WearNewTip" },
    { key = "used",  label = "UI_Aegis_WearUsed",  tip = "UI_Aegis_WearUsedTip" },
    { key = "wreck", label = "UI_Aegis_WearWreck", tip = "UI_Aegis_WearWreckTip" },
}
AegisPageVehicles.wear = AegisPageVehicles.wear or "new"

function AegisPageVehicles:createChildren()
    local pad = 20
    self:buildCache()

    self.search = ISTextEntryBox:new("", pad + 1, pad + 44, LIST_W - 2, 28)
    self.search:initialise()
    self.search:instantiate()
    self.search.font = UIFont.Small
    self.search:setClearButton(true)
    self.search:setPlaceholderText(getText("UI_Aegis_SearchVehicle"))
    local page = self
    self.search.onTextChange = function() page:applyFilter() end
    self:addChild(self.search)

    -- action row now holds Edit + Remove instead of Service + Remove
    local nbw = math.floor((LIST_W - 2 - 8) / 2)
    self.editBtn = AegisButton:new(pad + 1, self.height - pad - 37, nbw, 36, getText("UI_Aegis_EditVehicle"), "gear", self, AegisPageVehicles.onEditNear)
    self.editBtn.style = "gold"
    self.editBtn.tooltip = getText("UI_Aegis_EditVehicleTooltip")
    self.editBtn:setEnabled(false)
    self:addChild(self.editBtn)
    self.removeBtn = AegisButton:new(pad + 1 + nbw + 8, self.height - pad - 37, nbw, 36, getText("UI_Aegis_RemoveVehicle"), "trash", self, AegisPageVehicles.onRemoveNear)
    self.removeBtn.style = "danger"
    self.removeBtn:setEnabled(false)
    self:addChild(self.removeBtn)

    self.list = ISScrollingListBox:new(pad + 1, pad + 82, LIST_W - 2, self.height - pad * 2 - 83 - 48)
    self.list:initialise()
    self.list:instantiate()
    self.list.itemheight = ROW_H
    self.list.drawBorder = false
    self.list.backgroundColor = { r = 0, g = 0, b = 0, a = 0 }
    self.list.doDrawItem = AegisPageVehicles.drawRow
    self.list:setOnMouseDownFunction(self, AegisPageVehicles.onSelect)
    self:addChild(self.list)

    -- big 3D stage on the right, room below for the hint line and buttons
    local sx = pad + LIST_W + 20
    local sw = self.width - sx - pad
    local by = self.height - pad - 50
    local hintH = Aegis.fontH(UIFont.Small)
    -- own row for the condition switch, above the hint line
    local wearY = by - WEAR_H - 10
    local sceneBottom = wearY - hintH - 14
    pcall(function()
        local scene = AegisVehicleScene:new(sx + 14, pad + 46, sw - 28, sceneBottom - (pad + 46))
        scene:initialise()
        scene:instantiate()
        scene.backgroundColor = { r = Aegis.col.dark.r, g = Aegis.col.dark.g, b = Aegis.col.dark.b, a = 1 }
        scene.borderColor = { r = Aegis.col.line.r, g = Aegis.col.line.g, b = Aegis.col.line.b, a = 1 }
        self:addChild(scene)
        local jo = scene.javaObject
        jo:fromLua1("setDrawGrid", false)
        jo:fromLua1("setDrawGridAxes", false)
        jo:fromLua1("setMaxZoom", 20)
        jo:fromLua1("createVehicle", "vehicle")
        -- without a UserDefined view the scene ignores every setViewRotation,
        -- then neither mouse nor arrow rotates (model AnimationClipViewer:resetView)
        jo:fromLua1("setView", "UserDefined")
        jo:fromLua3("setViewRotation", 15, 45, 0)
        jo:fromLua1("setZoom", 6)
        self.scene = scene
    end)

    -- rotate arrows below the vehicle: click rotates one step,
    -- holding rotates continuously (see update)
    local center = sx + 14 + math.floor((sw - 28) / 2)
    self.rotlBtn = AegisButton:new(center - 50, sceneBottom - 44, 44, 34, nil, "rotl", self, function(page)
        if (page.rotFrames or 0) <= 6 then page:rotateScene(-15) end
    end)
    self.rotlBtn.iconSize = 18
    self.rotlBtn.tooltip = getText("UI_Aegis_RotateLeft")
    self:addChild(self.rotlBtn)
    self.rotrBtn = AegisButton:new(center + 6, sceneBottom - 44, 44, 34, nil, "rotr", self, function(page)
        if (page.rotFrames or 0) <= 6 then page:rotateScene(15) end
    end)
    self.rotrBtn.iconSize = 18
    self.rotrBtn.tooltip = getText("UI_Aegis_RotateRight")
    self:addChild(self.rotrBtn)

    local bw = math.floor((sw - 28 - 12) / 2)
    self.placeBtn = AegisButton:new(sx + 14, by, bw, 38, getText("UI_Aegis_PlaceVehicle"), "pin", self, AegisPageVehicles.onPlace)
    self.placeBtn.style = "gold"
    self.placeBtn.tooltip = getText("UI_Aegis_PlaceHint")
    self:addChild(self.placeBtn)
    self.hereBtn = AegisButton:new(sx + 14 + bw + 12, by, bw, 38, getText("UI_Aegis_SpawnHere"), "car", self, AegisPageVehicles.onSpawnHere)

    -- condition of the next spawn, remembered for the session
    local cw = math.floor((bw * 2 + 12 - 8) / 3)
    self.wearBtns = {}
    for i, def in ipairs(WEAR_CHOICES) do
        local b = AegisButton:new(sx + 14 + (i - 1) * (cw + 4), wearY, cw, WEAR_H,
            getText(def.label), nil, self, function(page)
                AegisPageVehicles.wear = def.key
                page:refreshWear()
            end)
        b.tooltip = getText(def.tip)
        self:addChild(b)
        table.insert(self.wearBtns, { btn = b, key = def.key })
    end
    self:refreshWear()
    self:addChild(self.hereBtn)

    self:applyFilter()
end

function AegisPageVehicles:applyFilter()
    local needle = string.lower(self.search:getInternalText() or "")
    self.list:clear()
    self.list.selected = -1
    for _, v in ipairs(self.vehicles) do
        if needle == "" or string.find(v.search, needle, 1, true) then
            self.list:addItem(v.display, v)
        end
    end
    if self.list.items[1] then
        self.list.selected = 1
        self:updateScene()
    end
end

function AegisPageVehicles.drawRow(list, y, item, alt)
    local c = Aegis.col
    local sel = list.selected == item.index
    local hover = list.mouseoverselected == item.index
    if sel then
        Aegis.roundRect(list, 2, y + 1, list:getWidth() - 4, ROW_H - 2, 8, 1, c.card)
        Aegis.roundRect(list, 2, y + 7, 3, ROW_H - 14, 1, 1, c.gold)
    elseif hover then
        Aegis.roundRect(list, 2, y + 1, list:getWidth() - 4, ROW_H - 2, 8, 0.5, c.card)
    end
    local rec = item.item
    -- no seats means not enterable; skip the tag for trailers,
    -- their name already says so and it would show twice
    local tagW = 0
    if rec.wreck then
        local tag = getText("UI_Aegis_VehicleWreck")
        tagW = Aegis.strW(UIFont.Small, tag) + 12
        Aegis.textRight(list, tag, list:getWidth() - 12, y + math.floor((ROW_H - Aegis.fontH(UIFont.Small)) / 2), UIFont.Small, c.goldDim)
    elseif rec.seats == 0 and not rec.trailer then
        local tag = getText("UI_Aegis_NoSeats")
        tagW = Aegis.strW(UIFont.Small, tag) + 12
        Aegis.textRight(list, tag, list:getWidth() - 12, y + math.floor((ROW_H - Aegis.fontH(UIFont.Small)) / 2), UIFont.Small, c.goldDim)
    end
    local nameW = list:getWidth() - 14 - 10 - tagW
    if rec._fitW ~= nameW then
        rec._fitW = nameW
        rec._fit = Aegis.fitText(rec.display, UIFont.Small, nameW)
    end
    Aegis.text(list, rec._fit, 14, y + math.floor((ROW_H - Aegis.fontH(UIFont.Small)) / 2), UIFont.Small, sel and c.text or c.muted)
    return y + ROW_H
end

function AegisPageVehicles.onSelect(self, rec)
    self:updateScene()
end

function AegisPageVehicles:selectedVehicle()
    local item = self.list.items[self.list.selected]
    return item and item.item or nil
end

function AegisPageVehicles:updateScene()
    local v = self:selectedVehicle()
    if not v or not self.scene then return end
    pcall(function()
        self.scene.javaObject:fromLua2("setVehicleScript", "vehicle", v.full)
    end)
end

function AegisPageVehicles.onPlace(self)
    local v = self:selectedVehicle()
    if not v then return end
    AegisVehiclePlacer.start(v)
end

-- highlights the chosen condition, the others stay quiet
function AegisPageVehicles:refreshWear()
    for _, e in ipairs(self.wearBtns or {}) do
        e.btn.style = (e.key == AegisPageVehicles.wear) and "gold" or nil
    end
end

function AegisPageVehicles.onSpawnHere(self)
    local v = self:selectedVehicle()
    if not v then return end
    local p = getPlayer()
    -- one path for solo and MP, see AegisVehiclePlacer:onMouseDown
    sendClientCommand(p, "AegisAdmin", "spawnvehicle", {
        script = v.full, name = v.display,
        x = math.floor(p:getX()), y = math.floor(p:getY()), z = math.floor(p:getZ()), angle = 0,
        wear = AegisPageVehicles.wear,
    })
end

-- open the detail window for the nearest vehicle (replaces the old
-- service button; refuel+repair now lives in the detail window's
-- "Service" tab, server-side via Commands.vehicleService)
function AegisPageVehicles.onEditNear(self)
    local p = getPlayer()
    local vehicle = p and p:getNearVehicle()
    if not vehicle then return end
    AegisVehicleDetail.open(vehicle:getId(), vehicle)
end

-- remove the nearest vehicle in range, with confirmation
function AegisPageVehicles.onRemoveNear(self)
    local p = getPlayer()
    local vehicle = p and p:getNearVehicle()
    if not vehicle then return end
    local name = getTextOrNull("IGUI_VehicleName" .. (vehicle:getScript() and vehicle:getScript():getName() or "")) or ""
    AegisConfirm.show(getText("UI_Aegis_RemoveVehicle"), getText("UI_Aegis_ConfirmRemoveVehicle", name), getText("UI_Aegis_DeleteItem"), self, function()
        if isClient() then
            sendClientCommand(p, "vehicle", "remove", { vehicle = vehicle:getId() })
        else
            vehicle:permanentlyRemove()
        end
        Aegis.logAction("vehicles", "Vehicle removed: " .. (name ~= "" and name or "vehicle"))
        Aegis.showToast(getText("UI_Aegis_VehicleRemoved"))
    end)
end

function AegisPageVehicles:rotateScene(deg)
    if not self.scene then return end
    pcall(function()
        local jo = self.scene.javaObject
        local current = jo:fromLua0("getViewRotation")
        jo:fromLua3("setViewRotation", current:x(), current:y() + deg, current:z())
    end)
end

function AegisPageVehicles:update()
    ISPanel.update(self)
    if self.removeBtn then
        local p = getPlayer()
        local near = p ~= nil and p:getNearVehicle() ~= nil
        self.removeBtn:setEnabled(near)
        self.editBtn:setEnabled(near)
    end
    -- held arrow rotates continuously, a short click stays a single step
    if self.rotlBtn and self.rotlBtn.pressed then
        self.rotFrames = (self.rotFrames or 0) + 1
        if self.rotFrames > 6 then self:rotateScene(-3 * Aegis.delta()) end
    elseif self.rotrBtn and self.rotrBtn.pressed then
        self.rotFrames = (self.rotFrames or 0) + 1
        if self.rotFrames > 6 then self:rotateScene(3 * Aegis.delta()) end
    else
        self.rotFrames = 0
    end
end

function AegisPageVehicles:prerender()
    local c = Aegis.col
    local pad = 20

    Aegis.roundFrame(self, pad, pad, LIST_W, self.height - pad * 2, 10, 1, c.line, c.panel)
    Aegis.icon(self, "car", pad + 14, pad + 12, 15, 1, c.gold)
    Aegis.text(self, getText("UI_Aegis_NavVehicles"), pad + 36, pad + 10, UIFont.Medium, c.text)

    local sx = pad + LIST_W + 20
    local sw = self.width - sx - pad
    Aegis.roundFrame(self, sx, pad, sw, self.height - pad * 2, 10, 1, c.line, c.panel)
    local v = self:selectedVehicle()
    if v then
        Aegis.text(self, v.display, sx + 14, pad + 10, UIFont.Medium, c.text)
        Aegis.textRight(self, v.full, sx + sw - 14, pad + 14, UIFont.Small, c.goldDim)
    end
    local hintH = Aegis.fontH(UIFont.Small)
    Aegis.textCentre(self, getText("UI_Aegis_SceneHint"), sx + math.floor(sw / 2),
        self.height - pad - 50 - WEAR_H - 10 - hintH - 6, UIFont.Small, c.muted)
end

AegisWindow.registerPage({
    id = "vehicles",
    icon = "car",
    label = "UI_Aegis_NavVehicles",
    create = AegisPageVehicles.create,
})
