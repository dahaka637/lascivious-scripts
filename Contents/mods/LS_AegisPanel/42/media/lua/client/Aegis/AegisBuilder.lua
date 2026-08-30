-- Build brush: pick a piece from the palette, drag it across tiles,
-- confirm to build for everyone. Floors paint every dragged tile (line
-- rastered like the zone brush), walls and fences paint the dragged line
-- only, facing picked per segment axis. Mouse-to-tile conversion and the
-- tile outlines follow AegisClearing.lua. The server does the actual
-- building (server/Aegis_Builder.lua), the client only collects tiles.
require "Aegis/AegisTheme"
require "Aegis/AegisWidgets"
require "Vehicles/ISUI/ISUI3DScene"

AegisBuilder = AegisBuilder or {}

local MAX_TILES = 400

-- every sprite name below is taken from the vanilla B42 build entity
-- scripts (media/scripts/generated/entities) or vanilla lua, no guesses
local CATALOG = {
    {
        id = "floors", label = "UI_Aegis_BuilderFloors", mode = "floor",
        pieces = {
            { label = "Wood floor 1", sprite = "carpentry_02_58" },
            { label = "Wood floor 2", sprite = "carpentry_02_57" },
            { label = "Wood floor 3", sprite = "carpentry_02_56" },
            { label = "White tile", sprite = "floors_interior_tilesandwood_01_0" },
            { label = "Checker tile", sprite = "floors_interior_tilesandwood_01_5" },
            { label = "Brick floor", sprite = "floors_exterior_tilesandstone_01_6" },
            { label = "Metal floor", sprite = "constructedobjects_01_86" },
            { label = "Gravel", sprite = "blends_street_01_55" },
            { label = "Asphalt", sprite = "floors_exterior_street_01_16" },
            { label = "Dirt", sprite = "blends_natural_01_64" },
        },
    },
    {
        id = "walls", label = "UI_Aegis_BuilderWalls", mode = "wall",
        pieces = {
            { label = "Wood wall 1", w = "walls_exterior_wooden_01_44", n = "walls_exterior_wooden_01_45" },
            { label = "Wood wall 2", w = "walls_exterior_wooden_01_40", n = "walls_exterior_wooden_01_41" },
            { label = "Wood wall 3", w = "walls_exterior_wooden_01_24", n = "walls_exterior_wooden_01_25" },
            { label = "Wood wall frame", w = "carpentry_02_100", n = "carpentry_02_101" },
            { label = "Log wall", w = "carpentry_02_80", n = "carpentry_02_81" },
            { label = "Stone wall", w = "walls_logs_96", n = "walls_logs_97" },
            { label = "Brick wall 1", w = "walls_exterior_house_01_20", n = "walls_exterior_house_01_21" },
            { label = "Brick wall 2", w = "walls_exterior_house_01_4", n = "walls_exterior_house_01_5" },
            { label = "Metal wall 1", w = "constructedobjects_01_64", n = "constructedobjects_01_65" },
            { label = "Metal wall 2", w = "constructedobjects_01_48", n = "constructedobjects_01_49" },
        },
    },
    {
        id = "frames", label = "UI_Aegis_BuilderFrames", mode = "wall",
        pieces = {
            { label = "Wood window frame 1", w = "walls_exterior_wooden_01_52", n = "walls_exterior_wooden_01_53" },
            { label = "Wood window frame 2", w = "walls_exterior_wooden_01_32", n = "walls_exterior_wooden_01_33" },
            { label = "Brick window frame", w = "walls_exterior_house_01_12", n = "walls_exterior_house_01_13" },
            { label = "Metal window frame", w = "constructedobjects_01_56", n = "constructedobjects_01_57" },
            { label = "Stone window frame", w = "walls_logs_104", n = "walls_logs_105" },
            { label = "Log window frame", w = "walls_logs_48", n = "walls_logs_49" },
            { label = "Wood door frame", w = "walls_exterior_wooden_01_34", n = "walls_exterior_wooden_01_35" },
            { label = "Brick door frame", w = "walls_exterior_house_01_14", n = "walls_exterior_house_01_15" },
            { label = "Metal door frame", w = "constructedobjects_01_58", n = "constructedobjects_01_59" },
            { label = "Stone door frame", w = "walls_logs_106", n = "walls_logs_107" },
        },
    },
    {
        id = "fences", label = "UI_Aegis_BuilderFences", mode = "wall",
        pieces = {
            { label = "Wood fence 1", w = "carpentry_02_40", n = "carpentry_02_41" },
            { label = "Wood fence 2", w = "carpentry_02_44", n = "carpentry_02_45" },
            { label = "Wood fence 3", w = "carpentry_02_48", n = "carpentry_02_49" },
            { label = "Log fence", w = "crafted_04_116", n = "crafted_04_115" },
            { label = "Stick fence", w = "crafted_04_124", n = "crafted_04_123" },
            { label = "Metal fence 1", w = "constructedobjects_01_82", n = "constructedobjects_01_81" },
            { label = "Metal fence 2", w = "constructedobjects_01_83", n = "constructedobjects_01_80" },
            { label = "Big wire fence", w = "fencing_01_58", n = "fencing_01_57" },
            { label = "Barbed wire", w = "fencing_01_20", n = "fencing_01_21" },
            { label = "Sandbags", w = "carpentry_02_12", n = "carpentry_02_13" },
        },
    },
}

-- custom pieces come from the sprite inspector, stored client side in the
-- admin's own Zomboid/Lua folder, line format C|sprite|label (same file
-- pattern as the weather presets in AegisPageWorld.lua)
local CUSTOM_FILE = "AegisCustomPieces.txt"
local customCache = nil

local function loadCustom()
    if customCache then return customCache end
    customCache = {}
    -- append writer first: creates folder and file without touching
    -- content, a bare getFileReader throws on a fresh Lua folder
    pcall(function()
        local w = getFileWriter(CUSTOM_FILE, true, true)
        if w then w:close() end
    end)
    pcall(function()
        local reader = getFileReader(CUSTOM_FILE, true)
        if not reader then return end
        local line = reader:readLine()
        while line ~= nil do
            local sprite, label = string.match(line, "^C|([^|]+)|([^|]*)$")
            if sprite then
                table.insert(customCache, { sprite = sprite, label = label ~= "" and label or sprite })
            end
            line = reader:readLine()
        end
        reader:close()
    end)
    return customCache
end

local function writeCustom()
    pcall(function()
        local w = getFileWriter(CUSTOM_FILE, true, false)
        if not w then return end
        for _, p in ipairs(customCache or {}) do
            w:write("C|" .. p.sprite .. "|" .. p.label .. "\n")
        end
        w:close()
    end)
end

-- called by the inspector on world click; duplicates are kept once,
-- returns true only when the piece is new
function AegisBuilder.addCustom(sprite)
    if type(sprite) ~= "string" or sprite == "" then return false end
    sprite = sprite:gsub("|", "")
    local list = loadCustom()
    for _, p in ipairs(list) do
        if p.sprite == sprite then return false end
    end
    local label = sprite
    if #label > 26 then label = label:sub(1, 26) end
    table.insert(list, { sprite = sprite, label = label })
    writeCustom()
    return true
end

function AegisBuilder.removeCustomAt(idx)
    local list = loadCustom()
    if not list[idx] then return end
    table.remove(list, idx)
    writeCustom()
end

-- the custom category only exists while pieces are stored; mode "object"
-- paints like floors but builds plain world objects server side
local function categories()
    local cats = {}
    for _, cat in ipairs(CATALOG) do table.insert(cats, cat) end
    local custom = loadCustom()
    if #custom > 0 then
        table.insert(cats, { id = "custom", label = "UI_Aegis_BuilderCustom", mode = "object", pieces = custom })
    end
    return cats
end

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

local function drawTile(el, tx, ty, z, a, color)
    local project = screenProjection(tx, ty, z)
    if not project then return end
    local corners = {
        { tx, ty }, { tx + 1, ty }, { tx + 1, ty + 1 }, { tx, ty + 1 },
    }
    for i = 1, 4 do
        local p, q = corners[i], corners[i % 4 + 1]
        local x1, y1 = project(p[1], p[2])
        local x2, y2 = project(q[1], q[2])
        el:drawLine2(x1, y1, x2, y2, a, color.r, color.g, color.b)
    end
end

-- ==================================================================
-- Editor: fullscreen over the world with a compact palette card
-- ==================================================================
AegisBuilderEditor = ISPanel:derive("AegisBuilderEditor")
AegisBuilderEditor.instance = nil

local PAL_W = 240
local ROW_H = 40

function AegisBuilder.start()
    if AegisBuilderEditor.instance then return end
    if not Aegis.canSee("tools") then return end
    local sw, sh = getCore():getScreenWidth(), getCore():getScreenHeight()
    local o = ISPanel:new(0, 0, sw, sh)
    setmetatable(o, AegisBuilderEditor)
    AegisBuilderEditor.__index = AegisBuilderEditor
    o.background = false
    o.dragging = false
    o.cats = categories()
    o.catIdx = 1
    o.pieceIdx = 1
    o.tiles = {}      -- key "x|y" -> { x, y, z, n = bool or nil }
    o.count = 0
    o:initialise()
    o:addToUIManager()
    o:setAlwaysOnTop(true)
    o:setWantKeyEvents(true)
    AegisBuilderEditor.instance = o
    if AegisWindow.instance then AegisWindow.instance:setVisible(false) end
    return o
end

function AegisBuilderEditor:createChildren()
    local palH = math.min(self.height - 48, 96 + #CATALOG[1].pieces * ROW_H + 96)
    self.palX = 24
    self.palY = math.floor((self.height - palH) / 2)
    self.palH = palH

    -- full tilesheet browser. Sits directly under the category tabs, NOT
    -- at the bottom: down there it hid behind the empty space of a short
    -- category and was simply not found
    self.browseBtn = AegisButton:new(self.palX + 12, self.palY + 72,
        PAL_W - 24, 26, getText("UI_Aegis_BuilderBrowse"), "items", self, function()
            AegisTileBrowser.show()
        end)
    self.browseBtn.style = "gold"
    self.browseBtn.tooltip = getText("UI_Aegis_BuilderBrowseTooltip")
    self:addChild(self.browseBtn)

    local bw = math.floor((PAL_W - 36) / 2)
    self.confirmBtn = AegisButton:new(self.palX + 12, self.palY + palH - 40,
        bw, 30, getText("UI_Aegis_BuilderConfirm"), "check", self, function(page)
            page:apply()
        end)
    self.confirmBtn.style = "gold"
    self:addChild(self.confirmBtn)
    self.cancelBtn = AegisButton:new(self.palX + 24 + bw, self.palY + palH - 40,
        bw, 30, getText("UI_Aegis_BuilderCancel"), "close", self, function(page)
            page:finish()
        end)
    self:addChild(self.cancelBtn)
end

function AegisBuilderEditor:finish()
    if AegisTileBrowser and AegisTileBrowser.instance then
        AegisTileBrowser.instance:close()
    end
    self:removeFromUIManager()
    AegisBuilderEditor.instance = nil
    if AegisWindow.instance then AegisWindow.instance:setVisible(true) end
end

function AegisBuilderEditor:category()
    return self.cats[self.catIdx]
end

function AegisBuilderEditor:piece()
    return self:category().pieces[self.pieceIdx]
end

function AegisBuilderEditor:inPalette(x, y)
    -- the open tile browser counts as palette too: the editor covers the
    -- whole screen, so without this a click inside the browser would also
    -- paint a tile on the world underneath it
    local br = AegisTileBrowser and AegisTileBrowser.instance
    if br then
        local bx, by = br:getX(), br:getY()
        if x >= bx and x <= bx + br:getWidth() and y >= by and y <= by + br:getHeight() then
            return true
        end
    end
    return x >= self.palX and x <= self.palX + PAL_W
        and y >= self.palY and y <= self.palY + self.palH
end

function AegisBuilderEditor:clearTiles()
    self.tiles = {}
    self.count = 0
end

function AegisBuilderEditor:addTile(tx, ty, north)
    local key = tx .. "|" .. ty
    local old = self.tiles[key]
    if not old and self.count >= MAX_TILES then
        self:warnLimit()
        return
    end
    if not old then self.count = self.count + 1 end
    self.tiles[key] = { x = tx, y = ty, z = playerLevel(), n = north }
end

function AegisBuilderEditor:warnLimit()
    local now = getTimestampMs()
    if now < (self.warnUntil or 0) then return end
    self.warnUntil = now + 1500
    Aegis.showToast(getText("UI_Aegis_BuilderTooMany", MAX_TILES))
end

-- floors: rasterize from the last sample to the current tile so fast
-- strokes stay gapless, same technique as the zone brush
function AegisBuilderEditor:paintFloor()
    local tx, ty = mouseTile()
    local lx, ly = self.lastX or tx, self.lastY or ty
    local steps = math.max(math.abs(tx - lx), math.abs(ty - ly))
    for i = 0, steps do
        local t = steps == 0 and 0 or i / steps
        self:addTile(math.floor(lx + (tx - lx) * t + 0.5), math.floor(ly + (ty - ly) * t + 0.5))
    end
    self.lastX, self.lastY = tx, ty
end

-- walls and fences: the current drag is one axis-locked segment from the
-- anchor, horizontal runs get the N face, vertical runs the W face
function AegisBuilderEditor:paintLine()
    local tx, ty = mouseTile()
    for key, t in pairs(self.tiles) do
        if t.seg then
            self.tiles[key] = nil
            self.count = self.count - 1
        end
    end
    local ax, ay = self.dragX, self.dragY
    local horizontal = math.abs(tx - ax) >= math.abs(ty - ay)
    if horizontal then
        for x = math.min(ax, tx), math.max(ax, tx) do
            self:addTile(x, ay, true)
            local t = self.tiles[x .. "|" .. ay]
            if t then t.seg = true end
        end
    else
        for y = math.min(ay, ty), math.max(ay, ty) do
            self:addTile(ax, y, false)
            local t = self.tiles[ax .. "|" .. y]
            if t then t.seg = true end
        end
    end
end

-- ghost preview: the piece texture drawn half transparent on the tile.
-- Anchor: tile canvas bottom sits on the diamond's bottom corner, the
-- trim offsets shift the cut texture back into canvas position
local function drawGhost(el, sprite, tx, ty, z, a)
    if not sprite then return end
    local tex = getTexture(sprite)
    if not tex then return end
    local project = screenProjection(tx, ty, z)
    if not project then return end
    local lx = project(tx, ty + 1)
    local rx = project(tx + 1, ty)
    local _, by = project(tx + 1, ty + 1)
    local origW = tex:getWidthOrig()
    if origW <= 0 then return end
    local scale = (rx - lx) / origW
    local x = lx + tex:getOffsetX() * scale
    local y = by - tex:getHeightOrig() * scale + tex:getOffsetY() * scale
    el:drawTextureScaled(tex, x, y, tex:getWidth() * scale, tex:getHeight() * scale, a, 1, 1, 1)
end

-- shared with the restore preview in AegisConstruction.lua, same math
-- keeps both ghosts pixel identical
AegisBuilder.drawGhost = drawGhost
AegisBuilder.drawTile = drawTile

function AegisBuilderEditor:onMouseDown(x, y)
    if self:inPalette(x, y) then
        self:paletteClick(x, y)
        return
    end
    self.dragging = true
    self.lastX, self.lastY = nil, nil
    self.dragX, self.dragY = mouseTile()
end

function AegisBuilderEditor:onMouseUp(x, y)
    self:endDrag()
end

function AegisBuilderEditor:onMouseUpOutside(x, y)
    self:endDrag()
end

function AegisBuilderEditor:endDrag()
    if self.dragging and self:category().mode == "wall" then
        -- the finished segment sticks, the next drag starts a new one
        for _, t in pairs(self.tiles) do t.seg = nil end
    end
    self.dragging = false
    self.lastX, self.lastY = nil, nil
end

function AegisBuilderEditor:onRightMouseDown(x, y)
    if self.count > 0 then
        self:clearTiles()
    else
        self:finish()
    end
end

function AegisBuilderEditor:paletteClick(x, y)
    -- clicks the browser already handled, the editor stays out of them
    if not (x >= self.palX and x <= self.palX + PAL_W
        and y >= self.palY and y <= self.palY + self.palH) then
        return
    end
    local relY = y - self.palY
    -- category tabs
    if relY >= 40 and relY < 68 then
        local tabW = math.floor((PAL_W - 24) / #self.cats)
        local idx = math.floor((x - self.palX - 12) / tabW) + 1
        if self.cats[idx] and idx ~= self.catIdx then
            self.catIdx = idx
            self.pieceIdx = 1
            self.scroll = 0
            self:clearTiles()
        end
        return
    end
    -- piece rows, mirrors the listY in renderPalette
    local listY = 108
    if relY < listY then return end
    local idx = math.floor((relY - listY) / ROW_H) + 1 + (self.scroll or 0)
    if idx >= 1 and self:category().pieces[idx] then
        -- custom rows carry a remove zone on the right edge
        if self:category().id == "custom" and x >= self.palX + PAL_W - 32 then
            AegisBuilder.removeCustomAt(idx)
            self.cats = categories()
            if not self.cats[self.catIdx] then self.catIdx = 1 end
            self.pieceIdx = 1
            self:clearTiles()
            return
        end
        self.pieceIdx = idx
    end
end

function AegisBuilderEditor:apply()
    if self.count == 0 then
        self:finish()
        return
    end
    if self.count > MAX_TILES then
        self:warnLimit()
        return
    end
    local cat = self:category()
    local piece = self:piece()
    local tiles = {}
    for _, t in pairs(self.tiles) do
        table.insert(tiles, { x = t.x, y = t.y, z = t.z, n = t.n == true })
    end
    local args = { mode = cat.mode, tiles = tiles }
    if cat.mode == "floor" or cat.mode == "object" then
        args.sprite = piece.sprite
    else
        args.spriteW = piece.w
        args.spriteN = piece.n
    end
    sendClientCommand(getPlayer(), AegisShared.MODULE, "builderApply", args)
    Aegis.logAction("tools", string.format("Build brush: %s on %d tiles", piece.label, self.count))
    self:finish()
end

function AegisBuilderEditor:render()
    local c = Aegis.col
    local z = playerLevel()
    if self.dragging then
        if self:category().mode == "wall" then
            self:paintLine()
        else
            self:paintFloor()
        end
    end
    local piece = self:piece()
    local mode = self:category().mode
    local function ghostSprite(north)
        if mode == "wall" then
            if north then return piece.n end
            return piece.w
        end
        return piece.sprite
    end
    for _, t in pairs(self.tiles) do
        drawGhost(self, ghostSprite(t.n), t.x, t.y, t.z, 0.55)
        drawTile(self, t.x, t.y, t.z, 0.9, c.gold)
    end
    local mx, my = getMouseX(), getMouseY()
    if not self:inPalette(mx, my) then
        local tx, ty = mouseTile()
        drawGhost(self, ghostSprite(false), tx, ty, z, 0.4)
        drawTile(self, tx, ty, z, 0.9, c.goldHi)
    end

    -- header card
    local midX = math.floor(self.width / 2)
    local header = getText("UI_Aegis_BuilderTiles", self.count)
    local hint = getText("UI_Aegis_BuilderTooltip")
    local w = math.max(Aegis.strW(UIFont.Medium, header), Aegis.strW(UIFont.Small, hint)) + 48
    Aegis.roundFrame(self, midX - math.floor(w / 2), 24, w, 62, 10, 0.95, c.gold, c.dark)
    Aegis.textCentre(self, header, midX, 32, UIFont.Medium, c.goldHi)
    Aegis.textCentre(self, hint, midX, 36 + Aegis.fontH(UIFont.Medium), UIFont.Small, c.muted)
end

-- The palette card belongs in PRERENDER, not in render: the engine draws
-- child elements between the two, so a card painted in render lands ON TOP
-- of its own buttons. That is why confirm, cancel and the new browse button
-- were invisible (they still answered clicks, which is why it went
-- unnoticed for so long). Every other Aegis page draws its cards in
-- prerender for exactly this reason
function AegisBuilderEditor:prerender()
    ISPanel.prerender(self)
    self:renderPalette()
end

function AegisBuilderEditor:renderPalette()
    local c = Aegis.col
    local px, py = self.palX, self.palY
    Aegis.shadow(self, px, py, PAL_W, self.palH, 16, 0.5)
    Aegis.roundFrame(self, px, py, PAL_W, self.palH, 10, 0.97, c.gold, c.dark)
    Aegis.text(self, getText("UI_Aegis_Builder"), px + 12, py + 10, UIFont.Medium, c.goldHi)

    -- category tabs
    local tabW = math.floor((PAL_W - 24) / #self.cats)
    for i, cat in ipairs(self.cats) do
        local tx = px + 12 + (i - 1) * tabW
        local active = i == self.catIdx
        if active then
            Aegis.roundRect(self, tx, py + 40, tabW - 4, 26, 6, 1, c.card)
        end
        local label = getText(cat.label)
        Aegis.textCentre(self, label, tx + math.floor((tabW - 4) / 2),
            py + 44, UIFont.Small, active and c.goldHi or c.muted)
    end

    -- piece rows, sprite texture as thumbnail when reachable by name.
    -- Long lists (custom grows with every inspector click) scroll with
    -- the mouse wheel, arrows mark hidden rows
    -- the browse button now occupies the row under the tabs
    local listY = py + 108
    local maxRows = math.floor((self.palH - 108 - 52) / ROW_H)
    local pieces = self:category().pieces
    local maxScroll = math.max(0, #pieces - maxRows)
    if (self.scroll or 0) > maxScroll then self.scroll = maxScroll end
    local scroll = self.scroll or 0
    if scroll > 0 then
        Aegis.textCentre(self, "^", px + math.floor(PAL_W / 2), listY - 14, UIFont.Small, c.goldHi)
    end
    if scroll < maxScroll then
        Aegis.textCentre(self, "v", px + math.floor(PAL_W / 2), listY + maxRows * ROW_H - 2, UIFont.Small, c.goldHi)
    end
    for i = scroll + 1, math.min(#pieces, scroll + maxRows) do
        local piece = pieces[i]
        local ry = listY + (i - scroll - 1) * ROW_H
        if i == self.pieceIdx then
            Aegis.roundRect(self, px + 8, ry, PAL_W - 16, ROW_H - 4, 6, 1, c.card)
        end
        local sprite = piece.sprite or piece.w
        local tex = getTexture(sprite)
        if tex then
            self:drawTextureScaledAspect(tex, px + 14, ry + 2, 32, ROW_H - 8, 1, 1, 1, 1)
        end
        local labelW = PAL_W - 54 - 12
        if self:category().id == "custom" then
            labelW = labelW - 20
            -- remove zone, mirrored by the click handling in paletteClick
            Aegis.text(self, "x", px + PAL_W - 26, ry + math.floor((ROW_H - 4 - Aegis.fontH(UIFont.Small)) / 2),
                UIFont.Small, c.danger)
        end
        Aegis.text(self, Aegis.fitText(piece.label, UIFont.Small, labelW), px + 54,
            ry + math.floor((ROW_H - 4 - Aegis.fontH(UIFont.Small)) / 2),
            UIFont.Small, i == self.pieceIdx and c.goldHi or c.text)
    end
end

-- tilesheets keep the rotations of a piece in aligned blocks of four,
-- R walks the block and skips gaps in the sheet
local function rotatedSprite(sprite)
    local base, num = string.match(sprite or "", "^(.-)_(%d+)$")
    if not base then return nil end
    num = tonumber(num)
    local block = math.floor(num / 4) * 4
    for step = 1, 3 do
        local cand = base .. "_" .. (block + (num - block + step) % 4)
        if getTexture(cand) then return cand end
    end
    return nil
end

function AegisBuilderEditor:rotatePiece()
    local cat = self:category()
    local piece = self:piece()
    if not piece then return end
    if cat.mode == "wall" then
        -- walls come as west/north pairs, R swaps the pair
        piece.w, piece.n = piece.n, piece.w
        return
    end
    local turned = rotatedSprite(piece.sprite)
    if turned then piece.sprite = turned end
end

function AegisBuilderEditor:onMouseWheel(del)
    if self:inPalette(getMouseX(), getMouseY()) then
        self.scroll = math.max(0, (self.scroll or 0) + (del > 0 and 1 or -1))
        return true
    end
    return false
end

function AegisBuilderEditor:isKeyConsumed(key)
    return key == Keyboard.KEY_ESCAPE or key == Keyboard.KEY_RETURN or key == Keyboard.KEY_R
end

function AegisBuilderEditor:onKeyPress(key)
    if key == Keyboard.KEY_RETURN then
        self:apply()
        GameKeyboard.eatKeyPress(key)
    elseif key == Keyboard.KEY_ESCAPE then
        self:finish()
        GameKeyboard.eatKeyPress(key)
    elseif key == Keyboard.KEY_R then
        self:rotatePiece()
        GameKeyboard.eatKeyPress(key)
    end
end

-- ==================================================================
-- Tile browser: every tilesheet the game knows, not just our palette.
-- The hand picked catalog above stays the quick road, this is the full
-- set, the same view the debug tile picker offers. Mechanism taken from vanilla ISTilesPickerDebugUI:
--   getWorld():getAllTilesName()  -> every sheet name
--   "<sheet>_<n>", n = 0..255      -> the sprites on it, 8 per row
--   getTexture(name) == nil        -> that slot is empty
-- Picking one drops it into the same custom category the sprite
-- inspector already feeds, so building, ghosting and rotating need no
-- new code at all
-- ==================================================================
AegisTileBrowser = ISPanel:derive("AegisTileBrowser")
AegisTileBrowser.instance = nil

local BR_W, BR_H = 900, 620
local SHEET_W = 260
local CELL = 64
local COLS = 8
local SHEET_ROWS = 32
-- both panes share these bounds. The info line lives BELOW them, it used to
-- be drawn inside the frames and overlapped the content
local PANE_TOP = 88
local PANE_BOT = BR_H - 46
-- SCROLL_W is the gutter each pane keeps free on its right. The bar itself
-- is drawn narrower and centred in it, so the surrounding layout maths stay
-- exactly as they were when this column still held arrow buttons
local SCROLL_W = 26
local BAR_W = 12
local BAR_INSET = math.floor((SCROLL_W - BAR_W) / 2)
local THUMB_MIN = 26
local SHEET_ROW_H = 26
-- hovering blows the tile up. In the grid a tile is 58 pixels and several
-- sheets differ only in a detail, which is unreadable at that size
local PREVIEW = 176

local sheetCache = nil

-- A few tiles carry a real 3D model. Measured in Vanilla 42: 45 sprites
-- out of 5 sheets, 38 of them doors, defined in
-- media/scripts/generated/models_isoobject.txt with the SPRITE as the model
-- name. Mods can add their own, so the test is this lookup and never a list.
-- The whole road is public methods, no field access, which matters since
-- 42.20 locked Lua field access behind -debug: IsoSprite holds its model in
-- a public FIELD, and that way would have been shut. Vanilla's own
-- SpriteModelEditor takes the field road and is a debug window for it.
local modelCache = {}

local function modelFor(sprite)
    local hit = modelCache[sprite]
    if hit ~= nil then return hit or nil end
    local found = false
    local sm = getScriptManager()
    if sm then
        if sm:getModelScript("Base." .. sprite) then
            found = "Base." .. sprite
        elseif sm:getModelScript(sprite) then
            found = sprite
        end
    end
    modelCache[sprite] = found
    return found or nil
end

local function addSheet(set, list, spriteName)
    local base = string.match(spriteName or "", "^(.-)_%d+$")
    if not base or base == "" or set[base] then return false end
    set[base] = true
    table.insert(list, base)
    return true
end

-- Every sheet name reachable from the squares around the player. This is
-- the source that PROVABLY exists at runtime: the engine's own
-- getWorld():getAllTilesName() is debug data and comes back EMPTY in a
-- normal client (measured, the browser showed 0 of 0), even though the
-- method itself is public. A sprite sitting in the world, on the other
-- hand, is real by definition, and its name carries the sheet it came from
local SCAN_RADIUS = 40

local function scanWorldSheets(set, list)
    local found = 0
    pcall(function()
        local p = getPlayer()
        local cell = getCell()
        if not p or not cell then return end
        local px, py, pz = math.floor(p:getX()), math.floor(p:getY()), math.floor(p:getZ())
        for x = px - SCAN_RADIUS, px + SCAN_RADIUS do
            for y = py - SCAN_RADIUS, py + SCAN_RADIUS do
                local sq = cell:getGridSquare(x, y, pz)
                if sq then
                    local objs = sq:getObjects()
                    for i = 0, objs:size() - 1 do
                        local o = objs:get(i)
                        local spr = o and o:getSprite()
                        local nm = spr and spr:getName()
                        if nm and addSheet(set, list, nm) then found = found + 1 end
                    end
                end
            end
        end
    end)
    return found
end

local function allSheets()
    if sheetCache then return sheetCache end
    local set = {}
    sheetCache = {}
    -- 1. the engine list, when it happens to be filled (debug sessions)
    local fromEngine = 0
    local list = getWorld():getAllTilesName()
    if list then
        for i = 0, list:size() - 1 do
            local name = list:get(i)
            if type(name) == "string" and name ~= "" and not set[name] then
                set[name] = true
                table.insert(sheetCache, name)
                fromEngine = fromEngine + 1
            end
        end
    end
    -- 2. the sheets our own palette is built from, always available
    local fromCatalog = 0
    for _, cat in ipairs(CATALOG) do
        for _, piece in ipairs(cat.pieces) do
            if addSheet(set, sheetCache, piece.sprite or piece.w) then fromCatalog = fromCatalog + 1 end
            if piece.n and addSheet(set, sheetCache, piece.n) then fromCatalog = fromCatalog + 1 end
        end
    end
    for _, piece in ipairs(loadCustom()) do
        if addSheet(set, sheetCache, piece.sprite) then fromCatalog = fromCatalog + 1 end
    end
    -- 3. everything standing around the admin right now
    local fromWorld = scanWorldSheets(set, sheetCache)
    table.sort(sheetCache)
    print("[Aegis] tile browser: " .. #sheetCache .. " sheet(s) (engine list " .. fromEngine
        .. ", palette " .. fromCatalog .. ", world scan " .. fromWorld .. ")")
    return sheetCache
end

function AegisTileBrowser.show()
    if AegisTileBrowser.instance then
        AegisTileBrowser.instance:close()
        return
    end
    -- rescan on every open: the world part of the list depends on where
    -- the admin is standing right now
    sheetCache = nil
    local sw, sh = getCore():getScreenWidth(), getCore():getScreenHeight()
    local o = ISPanel:new(math.floor((sw - BR_W) / 2), math.floor((sh - BR_H) / 2), BR_W, BR_H)
    setmetatable(o, AegisTileBrowser)
    AegisTileBrowser.__index = AegisTileBrowser
    o.background = false
    o.filter = ""
    o.sheetIdx = 1
    o.sheetScroll = 0
    o.gridScroll = 0
    o:initialise()
    o:addToUIManager()
    o:setAlwaysOnTop(true)
    AegisTileBrowser.instance = o
    return o
end

function AegisTileBrowser:close()
    if self.scene then
        self.scene:setVisible(false)
        self.scene = nil
        self.sceneScript = nil
    end
    self:removeFromUIManager()
    AegisTileBrowser.instance = nil
end

-- sheets whose name contains the filter, always a fresh list so the
-- filter box stays responsive without a rebuild step
function AegisTileBrowser:sheets()
    local all = allSheets()
    if self.filter == "" then return all end
    local needle = self.filter:lower()
    local out = {}
    for _, name in ipairs(all) do
        if string.find(name:lower(), needle, 1, true) then table.insert(out, name) end
    end
    return out
end

function AegisTileBrowser:createChildren()
    local c = Aegis.col
    local page = self
    self.search = ISTextEntryBox:new("", 14, 52, SHEET_W - 28, 26)
    self.search:initialise()
    self.search:instantiate()
    self.search.font = UIFont.Small
    self.search:setClearButton(true)
    self.search.backgroundColor = { r = c.dark.r, g = c.dark.g, b = c.dark.b, a = 1 }
    self.search.borderColor = { r = c.line.r, g = c.line.g, b = c.line.b, a = 1 }
    self.search.onTextChange = function()
        page.filter = page.search:getInternalText() or ""
        page.sheetIdx = 1
        page.sheetScroll = 0
        page.gridScroll = 0
    end
    self:addChild(self.search)
    self.closeBtn = AegisButton:new(BR_W - 42, 12, 30, 30, nil, "close", self, AegisTileBrowser.close)
    self.closeBtn.radius = 15
    self:addChild(self.closeBtn)

    -- both panes carry a real draggable bar instead of the arrow buttons
    -- they had first. They are drawn, not children, so they
    -- cannot end up underneath a card the way the palette buttons did
    self.drag = nil

    -- the 3D stage for the handful of tiles that own a model. Same setup as
    -- the vehicle preview in the player panel, which is proven, plus the
    -- view angle vanilla's sprite model editor uses for iso objects
    pcall(function()
        local sc = ISUI3DScene:new(0, 0, PREVIEW, PREVIEW)
        sc:initialise()
        sc:instantiate()
        sc.backgroundColor = { r = c.dark.r, g = c.dark.g, b = c.dark.b, a = 1 }
        sc.borderColor = { r = c.line.r, g = c.line.g, b = c.line.b, a = 1 }
        self:addChild(sc)
        local jo = sc.javaObject
        -- it must not swallow the mouse, the browser needs every move to
        -- know which tile is hovered and every click to add one
        jo:setConsumeMouseEvents(false)
        jo:fromLua1("setDrawGrid", false)
        jo:fromLua1("setDrawGridAxes", false)
        jo:fromLua1("setMaxZoom", 20)
        jo:fromLua1("setView", "UserDefined")
        jo:fromLua3("setViewRotation", 30.0, 315.0, 0.0)
        jo:fromLua1("setZoom", 7)
        -- the default camera carries the object too high in the frame. This
        -- runs EXACTLY ONCE, on a fresh stage where the pan provably sits at
        -- zero: dragView takes raw mouse deltas and ADDS them, and the pan
        -- has no exposed reset, which is why the vehicle preview has to
        -- build a new stage per vehicle. Here
        -- one stage serves every model, so a repeat per hovered tile would
        -- walk the view off the frame within a few tiles
        jo:fromLua2("dragView", 0, math.floor(PREVIEW / 4))
        sc:setVisible(false)
        self.scene = sc
    end)
end

-- swap the stage over to another model, creating the object on first use
function AegisTileBrowser:showModel(script, x, y)
    local sc = self.scene
    if not sc then return false end
    local ok = pcall(function()
        if self.sceneScript ~= script then
            if self.sceneScript == nil then
                sc.javaObject:fromLua2("createModel", "tile", script)
            else
                sc.javaObject:fromLua2("setModelScript", "tile", script)
            end
            self.sceneScript = script
        end
        sc:setX(x)
        sc:setY(y)
        sc:setVisible(true)
    end)
    return ok
end

-- geometry of one bar, or nil when everything fits and no bar is needed.
-- Shared by drawing and hit testing so the two can never drift apart
function AegisTileBrowser:barAt(paneRight, scroll, maxScroll, visible, total)
    if maxScroll <= 0 or total <= visible then return nil end
    local trackX = paneRight - SCROLL_W + BAR_INSET
    local trackY = PANE_TOP + 4
    local trackH = (PANE_BOT - PANE_TOP) - 8
    local thumbH = math.max(THUMB_MIN, math.floor(trackH * visible / total))
    local span = trackH - thumbH
    local thumbY = trackY + math.floor(span * (scroll / maxScroll))
    return { x = trackX, y = trackY, h = trackH, tw = BAR_W,
             thumbY = thumbY, thumbH = thumbH, span = span, maxScroll = maxScroll }
end

function AegisTileBrowser:drawBar(b)
    if not b then return end
    local c = Aegis.col
    Aegis.roundRect(self, b.x, b.y, b.tw, b.h, 6, 1, c.dark)
    local hot = self.drag ~= nil
    Aegis.roundRect(self, b.x, b.thumbY, b.tw, b.thumbH, 6, 1, hot and c.goldDim or c.line)
end

-- left bar sits in the sheet pane, right bar in the tile grid
function AegisTileBrowser:sheetBar()
    local total = #self:sheets()
    local rows = self:sheetRows()
    return self:barAt(SHEET_W - 12, self.sheetScroll, math.max(0, total - rows), rows, total)
end

function AegisTileBrowser:gridBar()
    local vis = self.gridVisRows or 1
    local total = self.gridTotalRows or 0
    return self:barAt(BR_W - 16, self.gridScroll, self.gridMaxScroll or 0, vis, total)
end

function AegisTileBrowser:sheetRows()
    return math.floor((PANE_BOT - PANE_TOP - 8) / SHEET_ROW_H)
end

function AegisTileBrowser:scrollSheets(dir)
    local maxScroll = math.max(0, #self:sheets() - self:sheetRows())
    self.sheetScroll = math.max(0, math.min(maxScroll, self.sheetScroll + dir * math.max(1, self:sheetRows() - 1)))
end

function AegisTileBrowser:scrollGrid(dir)
    self.gridScroll = math.max(0, math.min(self.gridMaxScroll or 0, self.gridScroll + dir))
end

function AegisTileBrowser:prerender()
    ISPanel.prerender(self)
    local c = Aegis.col
    Aegis.shadow(self, 0, 0, BR_W, BR_H, 26, 0.7)
    Aegis.roundFrame(self, 0, 0, BR_W, BR_H, 12, 1, c.line, c.bg)
    Aegis.text(self, getText("UI_Aegis_BuilderBrowse"), 16, 14, UIFont.Medium, c.goldHi)

    -- sheet list on the left, the rows keep clear of the scroll column
    local sheets = self:sheets()
    local rows = self:sheetRows()
    local maxScroll = math.max(0, #sheets - rows)
    if self.sheetScroll > maxScroll then self.sheetScroll = maxScroll end
    local paneH = PANE_BOT - PANE_TOP
    Aegis.roundFrame(self, 8, PANE_TOP, SHEET_W - 16, paneH, 8, 1, c.line, c.panel)
    local textW = SHEET_W - 40 - SCROLL_W
    self:setStencilRect(10, PANE_TOP + 2, SHEET_W - 20, paneH - 4)
    for i = self.sheetScroll + 1, math.min(#sheets, self.sheetScroll + rows) do
        local ry = PANE_TOP + 4 + (i - self.sheetScroll - 1) * SHEET_ROW_H
        if i == self.sheetIdx then
            Aegis.roundRect(self, 12, ry, SHEET_W - 28 - SCROLL_W, SHEET_ROW_H - 2, 6, 1, c.card)
        end
        Aegis.text(self, Aegis.fitText(sheets[i], UIFont.Small, textW), 20, ry + 4,
            UIFont.Small, i == self.sheetIdx and c.goldHi or c.muted)
    end
    self:clearStencilRect()
    self:drawBar(self:sheetBar())
    -- info line BELOW the frames, never inside them
    Aegis.text(self, #sheets .. " / " .. #allSheets(), 16, BR_H - 32, UIFont.Small, c.muted)

    -- grid and hover card belong here too, not in render: the 3D stage is a
    -- child, children draw between prerender and render, and the card has to
    -- sit above the grid while the stage sits above the card
    self:drawGrid()
    self:drawHover()
end

function AegisTileBrowser:drawGrid()
    local c = Aegis.col
    local sheets = self:sheets()
    local sheet = sheets[self.sheetIdx]
    local gx, gy = SHEET_W + 8, PANE_TOP
    local gw, gh = BR_W - gx - 16, PANE_BOT - PANE_TOP
    Aegis.roundFrame(self, gx, gy, gw, gh, 8, 1, c.line, c.panel)
    if not sheet then
        Aegis.textCentre(self, getText("UI_Aegis_BuilderNoSheet"), gx + math.floor(gw / 2),
            gy + math.floor(gh / 2), UIFont.Small, c.muted)
        return
    end
    self:setStencilRect(gx + 2, gy + 2, gw - 4 - SCROLL_W, gh - 4)
    local visRows = math.max(1, math.floor(gh / CELL))
    local maxRow = 0
    for row = 1, SHEET_ROWS do
        for col = 1, COLS do
            local idx = (col - 1) + (row - 1) * COLS
            local tex = getTexture(sheet .. "_" .. idx)
            if tex then
                maxRow = math.max(maxRow, row)
                local ry = gy + 4 + (row - 1 - self.gridScroll) * CELL
                if ry > gy - CELL and ry < gy + gh then
                    local rx = gx + 8 + (col - 1) * CELL
                    self:drawTextureScaledAspect(tex, rx, ry, CELL - 6, CELL - 6, 1, 1, 1, 1)
                end
            end
        end
    end
    self:clearStencilRect()
    self.gridMaxScroll = math.max(0, maxRow - visRows)
    -- the bar needs both numbers, and only render knows them
    self.gridVisRows = visRows
    self.gridTotalRows = maxRow
    if self.gridScroll > self.gridMaxScroll then self.gridScroll = self.gridMaxScroll end
    self:drawBar(self:gridBar())
    Aegis.text(self, sheet, gx + 8, BR_H - 32, UIFont.Small, c.goldDim)
    if self.gridMaxScroll > 0 then
        Aegis.textRight(self, (self.gridScroll + 1) .. " / " .. (self.gridMaxScroll + 1),
            BR_W - 20, BR_H - 32, UIFont.Small, c.muted)
    end
end

-- a press on the thumb starts a drag, one above or below it pages, the
-- same two gestures the vanilla bars offer
function AegisTileBrowser:barClick(b, kind, x, y)
    if not b then return false end
    if x < b.x - 4 or x > b.x + b.tw + 4 then return false end
    if y < b.y or y > b.y + b.h then return false end
    if y >= b.thumbY and y <= b.thumbY + b.thumbH then
        self.drag = { kind = kind, grab = y - b.thumbY }
    elseif kind == "sheets" then
        self:scrollSheets(y < b.thumbY and -1 or 1)
    else
        local page = math.max(1, self.gridVisRows or 1)
        self:scrollGrid((y < b.thumbY and -1 or 1) * page)
    end
    return true
end

function AegisTileBrowser:dragTo(y)
    local d = self.drag
    if not d then return end
    local b = (d.kind == "sheets") and self:sheetBar() or self:gridBar()
    if not b or b.span <= 0 then return end
    local frac = math.max(0, math.min(1, (y - b.y - d.grab) / b.span))
    local v = math.floor(frac * b.maxScroll + 0.5)
    if d.kind == "sheets" then self.sheetScroll = v else self.gridScroll = v end
end

function AegisTileBrowser:onMouseMove(dx, dy)
    if self.drag then self:dragTo(getMouseY() - self:getAbsoluteY()) end
    return true
end

-- dragging a bar must survive the cursor leaving the window, otherwise a
-- fast pull sticks the thumb halfway
function AegisTileBrowser:onMouseMoveOutside(dx, dy)
    if self.drag then self:dragTo(getMouseY() - self:getAbsoluteY()) end
    return true
end

function AegisTileBrowser:onMouseUp(x, y)
    self.drag = nil
    return true
end

function AegisTileBrowser:onMouseUpOutside(x, y)
    self.drag = nil
    return true
end

-- the single place that maps a point in the grid back to a sprite. The
-- click and the hover preview both go through it, so they cannot drift
-- apart the way two hand written copies of the same maths would
function AegisTileBrowser:tileAt(x, y)
    if y < PANE_TOP or y > PANE_BOT then return nil end
    local sheet = self:sheets()[self.sheetIdx]
    if not sheet then return nil end
    local gx = SHEET_W + 8
    if x < gx or x >= BR_W - 16 - SCROLL_W - 8 then return nil end
    local col = math.floor((x - gx - 8) / CELL) + 1
    local row = math.floor((y - PANE_TOP - 4) / CELL) + 1 + self.gridScroll
    if col < 1 or col > COLS or row < 1 then return nil end
    local name = sheet .. "_" .. ((col - 1) + (row - 1) * COLS)
    local tex = getTexture(name)
    if not tex then return nil end
    return name, tex
end

-- The card is drawn in prerender, BEFORE the children, because the 3D stage
-- is a child and has to end up on top of it. The stage keeps a 12 pixel
-- margin to the card edge, so nothing of the card gets covered and the
-- border needs no second pass over the top
function AegisTileBrowser:drawHover()
    if self.scene then self.scene:setVisible(false) end
    if self.drag then return end
    local mx = getMouseX() - self:getAbsoluteX()
    local my = getMouseY() - self:getAbsoluteY()
    local name, tex = self:tileAt(mx, my)
    if not name then return end
    local c = Aegis.col
    local cw = math.max(PREVIEW + 24, Aegis.strW(UIFont.Small, name) + 24)
    local ch = PREVIEW + 42
    -- beside the cursor, and flipped or pulled back in wherever the card
    -- would otherwise leave the window
    local cx, cy = mx + 22, my + 22
    if cx + cw > BR_W - 8 then cx = mx - cw - 22 end
    if cy + ch > BR_H - 8 then cy = BR_H - 8 - ch end
    if cx < 8 then cx = 8 end
    if cy < 8 then cy = 8 end
    local ix = cx + math.floor((cw - PREVIEW) / 2)
    Aegis.shadow(self, cx, cy, cw, ch, 18, 0.6)
    Aegis.roundFrame(self, cx, cy, cw, ch, 10, 1, c.line, c.bg)
    -- a model where there is one, the flat sprite everywhere else. If the
    -- stage refuses for any reason the sprite still gets drawn
    local script = modelFor(name)
    if not (script and self:showModel(script, ix, cy + 12)) then
        self:drawTextureScaledAspect(tex, ix, cy + 12, PREVIEW, PREVIEW, 1, 1, 1, 1)
    end
    Aegis.textCentre(self, name, cx + math.floor(cw / 2), cy + PREVIEW + 18, UIFont.Small, c.goldHi)
end

function AegisTileBrowser:onMouseDown(x, y)
    -- outside both panes (header, info line) nothing is selectable
    if y < PANE_TOP or y > PANE_BOT then return true end
    -- the bars own their gutters, test them before anything else
    if self:barClick(self:sheetBar(), "sheets", x, y) then return true end
    if self:barClick(self:gridBar(), "grid", x, y) then return true end
    -- sheet list, the gutter on its right belongs to the bar
    if x < SHEET_W - 12 - SCROLL_W then
        local idx = math.floor((y - PANE_TOP - 4) / SHEET_ROW_H) + 1 + self.sheetScroll
        if self:sheets()[idx] then
            self.sheetIdx = idx
            self.gridScroll = 0
        end
        return true
    end
    if x < SHEET_W then return true end
    local name = self:tileAt(x, y)
    if name then
        if AegisBuilder.addCustom(name) then
            Aegis.showToast(getText("UI_Aegis_BuilderAdded", name))
        else
            Aegis.showToast(getText("UI_Aegis_BuilderKnown", name))
        end
        -- the open editor picks the new piece up right away
        local ed = AegisBuilderEditor.instance
        if ed then
            ed.cats = categories()
            for i, cat in ipairs(ed.cats) do
                if cat.id == "custom" then
                    ed.catIdx = i
                    ed.pieceIdx = #cat.pieces
                    ed.scroll = math.max(0, #cat.pieces - 6)
                end
            end
            ed:clearTiles()
        end
        return true
    end
    return true
end

function AegisTileBrowser:onMouseWheel(del)
    local mx = getMouseX() - self:getAbsoluteX()
    if mx < SHEET_W then
        local rows = self:sheetRows()
        local maxScroll = math.max(0, #self:sheets() - rows)
        self.sheetScroll = math.max(0, math.min(maxScroll, self.sheetScroll + (del > 0 and 3 or -3)))
    else
        self:scrollGrid(del > 0 and 1 or -1)
    end
    return true
end

Events.OnServerCommand.Add(function(module, command, args)
    if module ~= AegisShared.MODULE then return end
    if command == "builderDone" and args then
        if args.ok then
            Aegis.showToast(getText("UI_Aegis_BuilderDone", args.built or 0))
        else
            Aegis.showToast(getText("UI_Aegis_BuilderTooMany", MAX_TILES))
        end
    end
end)
