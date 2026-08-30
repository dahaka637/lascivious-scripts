-- Animals: search, large rotatable 3D stage, hologram placement with
-- degree rotation, spawning and removal. Same layout as the vehicles page.
require "Aegis/AegisWindow"
require "ISUI/ISScrollingListBox"
require "ISUI/ISTextEntryBox"
require "Vehicles/ISUI/ISUI3DScene"

AegisPageAnimals = ISPanel:derive("AegisPageAnimals")

local LIST_W = 270
local ROW_H = 32

-- rough radius per type for the placement hologram: no dimensions exist
-- on AnimalDefinitions/AnimalBreed level (only on the live IsoAnimal
-- instance via getAnimalSize), so these are empirical values per type
local SIZE = {
    Rat = 0.28, Mouse = 0.28, Chicken = 0.32, Rabbit = 0.32,
    Turkey = 0.42, Raccoon = 0.42,
    Sheep = 0.6, Goat = 0.6, Pig = 0.62,
    Cow = 0.85, Deer = 0.8,
}
local SIZE_DEFAULT = 0.5

-- ==================================================================
-- Stage with real drag rotation (AnimationClipViewer pattern, see
-- AegisVehicleScene): drag rotates, shift+drag pans, mouse wheel zooms
-- ==================================================================
AegisAnimalScene = ISUI3DScene:derive("AegisAnimalScene")

function AegisAnimalScene:onMouseDown(x, y)
    ISUI3DScene.onMouseDown(self, x, y)
    self.rotating = not (isKeyDown(Keyboard.KEY_LSHIFT) or isKeyDown(Keyboard.KEY_RSHIFT))
end

function AegisAnimalScene:onMouseMove(dx, dy)
    if self.mouseDown and self.rotating then
        local current = self.javaObject:fromLua0("getViewRotation")
        local rx = math.max(-20, math.min(70, current:x() + dy / 4))
        local ry = current:y() + dx / 2
        self.javaObject:fromLua3("setViewRotation", rx, ry, current:z())
        return
    end
    ISUI3DScene.onMouseMove(self, dx, dy)
end

function AegisAnimalScene:onMouseUp(x, y)
    ISUI3DScene.onMouseUp(self, x, y)
    self.rotating = false
end

function AegisAnimalScene:onMouseUpOutside(x, y)
    ISUI3DScene.onMouseUpOutside(self, x, y)
    self.rotating = false
end

-- ==================================================================
-- Placement mode: fullscreen overlay, footprint plus 3D hologram at the
-- cursor, mouse wheel rotates by degrees, R in 30 degree steps (pattern
-- AegisVehiclePlacer). The facing is actually applied on spawn
-- (IsoGameCharacter:faceDirection, snapped to 8 directions), after that
-- the animal AI takes over the facing on its own
-- ==================================================================
AegisAnimalPlacer = ISPanel:derive("AegisAnimalPlacer")
AegisAnimalPlacer.instance = nil

function AegisAnimalPlacer.start(animal)
    if AegisAnimalPlacer.instance then return end
    local sw, sh = getCore():getScreenWidth(), getCore():getScreenHeight()
    local o = ISPanel:new(0, 0, sw, sh)
    setmetatable(o, AegisAnimalPlacer)
    AegisAnimalPlacer.__index = AegisAnimalPlacer
    o.background = false
    o.animal = animal
    o.angle = 0
    local size = SIZE[animal.type] or SIZE_DEFAULT
    o.halfW, o.halfL, o.bodyHeight = size, size, size * 1.3
    o:initialise()
    o:addToUIManager()
    o:setAlwaysOnTop(true)
    o:setWantKeyEvents(true)
    AegisAnimalPlacer.instance = o
    if AegisWindow.instance then
        AegisWindow.instance:setVisible(false)
    end
    o:createHologram()
    return o
end

function AegisAnimalPlacer:createHologram()
    local placer = self
    pcall(function()
        local holo = ISUI3DScene:new(0, 0, 200, 170)
        holo.background = false
        holo:initialise()
        holo:instantiate()
        self:addChild(holo)
        local jo = holo.javaObject
        jo:fromLua1("setDrawGrid", false)
        jo:fromLua1("setDrawGridAxes", false)
        jo:fromLua3("createAnimal", "animal", self.animal.def, self.animal.breed)
        -- SceneCharacter (base class of SceneAnimal) starts with a dimmed
        -- model alpha (bytecode: setCharacterAlpha calls
        -- AnimatedModel.setAlpha), without this call the animal looks
        -- translucent (ghost look, found by a user)
        jo:fromLua2("setCharacterAlpha", "animal", 1.0)
        jo:fromLua1("setView", "UserDefined")
        jo:fromLua1("setMaxZoom", 20)
        jo:fromLua1("setZoom", 5)
        holo.onMouseDown = function(s, x, y) placer:onMouseDown(placer:getMouseX(), placer:getMouseY()) end
        holo.onRightMouseDown = function(s, x, y) placer:onRightMouseDown(x, y) end
        holo.onMouseWheel = function(s, del) return placer:onMouseWheel(del) end
        holo.onMouseMove = function() end
        holo.onMouseUp = function() end
        self.holo = holo
    end)
end

function AegisAnimalPlacer:finish()
    self:removeFromUIManager()
    AegisAnimalPlacer.instance = nil
    if AegisWindow.instance then
        AegisWindow.instance:setVisible(true)
    end
end

function AegisAnimalPlacer:mouseWorld()
    local p = getPlayer()
    local z = p and math.floor(p:getZ()) or 0
    local zoom = getCore():getZoom(0)
    local wx = IsoUtils.XToIso(getMouseX() * zoom, getMouseY() * zoom, z)
    local wy = IsoUtils.YToIso(getMouseX() * zoom, getMouseY() * zoom, z)
    return math.floor(wx), math.floor(wy), z
end

local function cornerToUI(ax, ay, cx, cy, px, py, z)
    local zoom = getCore():getZoom(0)
    local dx = (IsoUtils.XToScreen(px, py, z, 0) - IsoUtils.XToScreen(cx, cy, z, 0)) / zoom
    local dy = (IsoUtils.YToScreen(px, py, z, 0) - IsoUtils.YToScreen(cx, cy, z, 0)) / zoom
    return ax + dx, ay + dy
end

function AegisAnimalPlacer:render()
    local c = Aegis.col
    local wx, wy, z = self:mouseWorld()
    local cx, cy = wx, wy
    local anchorX = isoToScreenX(0, cx, cy, z)
    local anchorY = isoToScreenY(0, cx, cy, z)

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
    for i = 1, 4 do
        local a, b = pts[i], pts[i % 4 + 1]
        self:drawLine2(a.x, a.y, b.x, b.y, 0.9, c.goldHi.r, c.goldHi.g, c.goldHi.b)
        self:drawLine2(a.x, a.y + 1, b.x, b.y + 1, 0.5, c.gold.r, c.gold.g, c.gold.b)
    end
    self:drawLine2(pts[1].x, pts[1].y, pts[3].x, pts[3].y, 0.25, c.gold.r, c.gold.g, c.gold.b)
    self:drawLine2(pts[2].x, pts[2].y, pts[4].x, pts[4].y, 0.25, c.gold.r, c.gold.g, c.gold.b)

    if self.holo then
        pcall(function()
            local SCALE = 1406
            local PX_PER_METER = 90.5
            local worldZoom = getCore():getZoom(0)
            local pxPerMeter = PX_PER_METER / worldZoom
            local radius = math.sqrt(self.halfW * self.halfW + self.halfL * self.halfL) + self.bodyHeight * 0.5
            local cap = math.max(300, getCore():getScreenHeight() - 60)
            local targetWidth = math.max(140, math.min(cap, math.floor(radius * pxPerMeter * 2 * 1.6 + 40)))
            local step = math.max(1, math.min(20, math.floor(5 * math.log(SCALE / (worldZoom * targetWidth)) + 0.5)))
            local width = math.floor(SCALE / (worldZoom * math.exp(0.2 * step)))
            if step ~= self.holoLevel then
                self.holoLevel = step
                self.holo.javaObject:fromLua1("setZoom", step)
            end
            if width ~= self.holo.width then
                self.holo:setWidth(width)
                self.holo:setHeight(width)
            end
            self.holo.javaObject:fromLua3("setViewRotation", 30, 135 - self.angle, 0)
            self.holo:setX(math.floor(anchorX) - math.floor(width / 2))
            self.holo:setY(math.floor(anchorY) - math.floor(width / 2))
        end)
    end

    local midX = math.floor(self.width / 2)
    local label = self.animal.display .. "  (" .. tostring(self.angle) .. "\194\176)"
    local hint = getText("UI_Aegis_PlaceHint")
    local w = math.max(Aegis.strW(UIFont.Medium, label), Aegis.strW(UIFont.Small, hint)) + 48
    Aegis.roundFrame(self, midX - math.floor(w / 2), 24, w, 62, 10, 0.95, c.gold, c.dark)
    Aegis.textCentre(self, label, midX, 32, UIFont.Medium, c.goldHi)
    Aegis.textCentre(self, hint, midX, 36 + Aegis.fontH(UIFont.Medium), UIFont.Small, c.muted)
end

function AegisAnimalPlacer:onMouseDown(x, y)
    local wx, wy, z = self:mouseWorld()
    local p = getPlayer()
    sendClientCommand(p, "AegisAdmin", "spawnanimal", {
        type = self.animal.type, breed = self.animal.breedName, name = self.animal.display,
        x = wx, y = wy, z = z, angle = self.angle,
    })
    self:finish()
end

function AegisAnimalPlacer:onRightMouseDown(x, y)
    self:finish()
end

function AegisAnimalPlacer:onMouseWheel(del)
    self.angle = (self.angle - del) % 360
    return true
end

function AegisAnimalPlacer:isKeyConsumed(key)
    return key == Keyboard.KEY_ESCAPE or key == Keyboard.KEY_R
end

function AegisAnimalPlacer:onKeyPress(key)
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

function AegisPageAnimals.create(window, x, y, w, h)
    local o = ISPanel:new(x, y, w, h)
    setmetatable(o, AegisPageAnimals)
    AegisPageAnimals.__index = AegisPageAnimals
    o.background = false
    o.window = window
    o.animals = nil
    return o
end

function AegisPageAnimals:buildCache()
    if self.animals then return end
    self.animals = {}
    local defs = getAllAnimalsDefinitions()
    for i = 0, defs:size() - 1 do
        local def = defs:get(i)
        local type = def:getAnimalType()
        local typeName = getTextOrNull("IGUI_AnimalType_" .. type) or type
        local breeds = def:getBreeds()
        for j = 0, breeds:size() - 1 do
            local breed = breeds:get(j)
            local breedName = breed:getName()
            local breedDisplay = getTextOrNull("IGUI_Breed_" .. breedName) or breedName
            local display = typeName .. " (" .. breedDisplay .. ")"
            table.insert(self.animals, {
                type = type, def = def, breed = breed, breedName = breedName,
                display = display,
                search = string.lower(display .. " " .. type .. " " .. breedName),
            })
        end
    end
    table.sort(self.animals, function(a, b) return a.display < b.display end)
end

function AegisPageAnimals:createChildren()
    local pad = 20
    self:buildCache()

    self.search = ISTextEntryBox:new("", pad + 1, pad + 44, LIST_W - 2, 28)
    self.search:initialise()
    self.search:instantiate()
    self.search.font = UIFont.Small
    self.search:setClearButton(true)
    self.search:setPlaceholderText(getText("UI_Aegis_SearchAnimal"))
    local page = self
    self.search.onTextChange = function() page:applyFilter() end
    self:addChild(self.search)

    self.removeBtn = AegisButton:new(pad + 1, self.height - pad - 37, LIST_W - 2, 36, getText("UI_Aegis_RemoveAnimal"), "trash", self, AegisPageAnimals.onRemoveNear)
    self.removeBtn.style = "danger"
    self.removeBtn:setEnabled(false)
    self:addChild(self.removeBtn)

    self.list = ISScrollingListBox:new(pad + 1, pad + 82, LIST_W - 2, self.height - pad * 2 - 83 - 48)
    self.list:initialise()
    self.list:instantiate()
    self.list.itemheight = ROW_H
    self.list.drawBorder = false
    self.list.backgroundColor = { r = 0, g = 0, b = 0, a = 0 }
    self.list.doDrawItem = AegisPageAnimals.drawRow
    self.list:setOnMouseDownFunction(self, AegisPageAnimals.onSelect)
    self:addChild(self.list)

    local sx = pad + LIST_W + 20
    local sw = self.width - sx - pad
    local by = self.height - pad - 50
    local hintH = Aegis.fontH(UIFont.Small)
    local sceneBottom = by - hintH - 16
    pcall(function()
        local scene = AegisAnimalScene:new(sx + 14, pad + 46, sw - 28, sceneBottom - (pad + 46))
        scene:initialise()
        scene:instantiate()
        scene.backgroundColor = { r = Aegis.col.dark.r, g = Aegis.col.dark.g, b = Aegis.col.dark.b, a = 1 }
        scene.borderColor = { r = Aegis.col.line.r, g = Aegis.col.line.g, b = Aegis.col.line.b, a = 1 }
        self:addChild(scene)
        local jo = scene.javaObject
        jo:fromLua1("setDrawGrid", false)
        jo:fromLua1("setDrawGridAxes", false)
        jo:fromLua1("setMaxZoom", 20)
        local first = self.animals[1]
        if first then
            jo:fromLua3("createAnimal", "animal", first.def, first.breed)
            jo:fromLua2("setCharacterAlpha", "animal", 1.0)
        end
        jo:fromLua1("setView", "UserDefined")
        jo:fromLua3("setViewRotation", 15, 45, 0)
        jo:fromLua1("setZoom", 4)
        self.scene = scene
    end)

    local mid = sx + 14 + math.floor((sw - 28) / 2)
    self.rotlBtn = AegisButton:new(mid - 50, sceneBottom - 44, 44, 34, nil, "rotl", self, function(page)
        if (page.rotFrames or 0) <= 6 then page:rotateScene(-15) end
    end)
    self.rotlBtn.iconSize = 18
    self.rotlBtn.tooltip = getText("UI_Aegis_RotateLeft")
    self:addChild(self.rotlBtn)
    self.rotrBtn = AegisButton:new(mid + 6, sceneBottom - 44, 44, 34, nil, "rotr", self, function(page)
        if (page.rotFrames or 0) <= 6 then page:rotateScene(15) end
    end)
    self.rotrBtn.iconSize = 18
    self.rotrBtn.tooltip = getText("UI_Aegis_RotateRight")
    self:addChild(self.rotrBtn)

    local bw = math.floor((sw - 28 - 12) / 2)
    self.placeBtn = AegisButton:new(sx + 14, by, bw, 38, getText("UI_Aegis_PlaceVehicle"), "pin", self, AegisPageAnimals.onPlace)
    self.placeBtn.style = "gold"
    self.placeBtn.tooltip = getText("UI_Aegis_PlaceHint")
    self:addChild(self.placeBtn)
    self.hereBtn = AegisButton:new(sx + 14 + bw + 12, by, bw, 38, getText("UI_Aegis_SpawnHere"), "horde", self, AegisPageAnimals.onSpawnHere)
    self:addChild(self.hereBtn)

    self:applyFilter()
end

function AegisPageAnimals:applyFilter()
    local needle = string.lower(self.search:getInternalText() or "")
    self.list:clear()
    self.list.selected = -1
    for _, t in ipairs(self.animals) do
        if needle == "" or string.find(t.search, needle, 1, true) then
            self.list:addItem(t.display, t)
        end
    end
    if self.list.items[1] then
        self.list.selected = 1
        self:updateScene()
    end
end

function AegisPageAnimals.drawRow(list, y, item, alt)
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
    local nameW = list:getWidth() - 14 - 10
    if rec._fitW ~= nameW then
        rec._fitW = nameW
        rec._fit = Aegis.fitText(rec.display, UIFont.Small, nameW)
    end
    Aegis.text(list, rec._fit, 14, y + math.floor((ROW_H - Aegis.fontH(UIFont.Small)) / 2), UIFont.Small, sel and c.text or c.muted)
    return y + ROW_H
end

function AegisPageAnimals.onSelect(self, rec)
    self:updateScene()
end

function AegisPageAnimals:selectedAnimal()
    local item = self.list.items[self.list.selected]
    return item and item.item or nil
end

function AegisPageAnimals:updateScene()
    local t = self:selectedAnimal()
    if not t or not self.scene then return end
    pcall(function()
        self.scene.javaObject:fromLua3("setAnimalDefinition", "animal", t.def, t.breed)
        self.scene.javaObject:fromLua2("setCharacterAlpha", "animal", 1.0)
    end)
end

function AegisPageAnimals.onPlace(self)
    local t = self:selectedAnimal()
    if not t then return end
    AegisAnimalPlacer.start(t)
end

function AegisPageAnimals.onSpawnHere(self)
    local t = self:selectedAnimal()
    if not t then return end
    local p = getPlayer()
    local z = p and math.floor(p:getZ()) or 0
    sendClientCommand(p, "AegisAdmin", "spawnanimal", {
        type = t.type, breed = t.breedName, name = t.display,
        x = math.floor(p:getX()) + ZombRand(3) - 1, y = math.floor(p:getY()) + ZombRand(3) - 1, z = z, angle = 0,
    })
end

-- nearest animal in range, no vanilla equivalent of getNearVehicle()
local function nearestAnimal(radius)
    local p = getPlayer()
    if not p then return nil end
    local list = getCell():getObjectListForLua()
    local px, py = p:getX(), p:getY()
    local nearest, nearestDist = nil, radius * radius
    for i = 0, list:size() - 1 do
        local obj = list:get(i)
        if instanceof(obj, "IsoAnimal") then
            local dx, dy = obj:getX() - px, obj:getY() - py
            local dist = dx * dx + dy * dy
            if dist <= nearestDist then
                nearest = obj
                nearestDist = dist
            end
        end
    end
    return nearest
end

function AegisPageAnimals.onRemoveNear(self)
    local animal = nearestAnimal(5)
    if not animal then return end
    local name = animal:getCustomName()
    if not name or name == "" then
        name = getTextOrNull("IGUI_AnimalType_" .. animal:getAnimalType()) or animal:getAnimalType()
    end
    local id = animal:getAnimalID()
    AegisConfirm.show(getText("UI_Aegis_RemoveAnimal"), getText("UI_Aegis_ConfirmRemoveAnimal", name or ""), getText("UI_Aegis_DeleteItem"), self, function()
        if isClient() then
            sendClientCommandV(getPlayer(), "animal", "remove", "id", id)
        else
            removeAnimal(id)
        end
        Aegis.logAction("animals", "Animal removed: " .. (name or "animal"))
        Aegis.showToast(getText("UI_Aegis_AnimalRemoved"))
    end)
end

function AegisPageAnimals:rotateScene(degrees)
    if not self.scene then return end
    pcall(function()
        local jo = self.scene.javaObject
        local current = jo:fromLua0("getViewRotation")
        jo:fromLua3("setViewRotation", current:x(), current:y() + degrees, current:z())
    end)
end

function AegisPageAnimals:update()
    ISPanel.update(self)
    if self.removeBtn then
        self.removeBtn:setEnabled(nearestAnimal(5) ~= nil)
    end
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

function AegisPageAnimals:prerender()
    local c = Aegis.col
    local pad = 20

    Aegis.roundFrame(self, pad, pad, LIST_W, self.height - pad * 2, 10, 1, c.line, c.panel)
    Aegis.icon(self, "horde", pad + 14, pad + 12, 15, 1, c.gold)
    Aegis.text(self, getText("UI_Aegis_Animals"), pad + 36, pad + 10, UIFont.Medium, c.text)

    local sx = pad + LIST_W + 20
    local sw = self.width - sx - pad
    Aegis.roundFrame(self, sx, pad, sw, self.height - pad * 2, 10, 1, c.line, c.panel)
    local t = self:selectedAnimal()
    if t then
        Aegis.text(self, t.display, sx + 14, pad + 10, UIFont.Medium, c.text)
    end
    local hintH = Aegis.fontH(UIFont.Small)
    Aegis.textCentre(self, getText("UI_Aegis_SceneHint"), sx + math.floor(sw / 2),
        self.height - pad - 50 - hintH - 8, UIFont.Small, c.muted)
end

AegisWindow.registerPage({
    id = "animals",
    icon = "horde",
    label = "UI_Aegis_Animals",
    create = AegisPageAnimals.create,
})
