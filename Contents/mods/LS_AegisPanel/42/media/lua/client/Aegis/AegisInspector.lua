-- Sprite inspector: hover any world tile and see the identity of every
-- object stacked on it (sprite name, type, container). Meant for admins
-- to learn sprite names for the builder and other tools. Click while the
-- inspector is on copies the top sprite name to the clipboard.
require "Aegis/AegisTheme"
require "Aegis/AegisBuilder"

AegisInspector = AegisInspector or {}

local overlay = nil

function AegisInspector.isOn()
    return overlay ~= nil
end

local function shortType(obj)
    if instanceof(obj, "IsoTree") then return "Tree" end
    if instanceof(obj, "IsoThumpable") then return "Built" end
    if instanceof(obj, "IsoDoor") then return "Door" end
    if instanceof(obj, "IsoWindow") then return "Window" end
    if instanceof(obj, "IsoCurtain") then return "Curtain" end
    if instanceof(obj, "IsoWorldInventoryObject") then return "Item" end
    return "Object"
end

-- all objects on the square, floor first, with sprite and container info.
-- skipFloor drops the floor object: used for levels above the player,
-- where the cursor means the facade (signs, wall decor), never the
-- interior floor behind it
local function collectRows(sq, skipFloor, hitTest)
    local rows = {}
    local floorObj = sq:getFloor()
    local function add(obj)
        if skipFloor and obj == floorObj then return end
        if hitTest and not hitTest(obj) then return end
        local spr = obj:getSprite()
        local sprite = spr and spr:getName() or nil
        if not sprite then return end
        local info = shortType(obj)
        local cont = obj:getContainer()
        if cont then info = info .. ", container: " .. tostring(cont:getType()) end
        table.insert(rows, { sprite = sprite, info = info })
    end
    local objects = sq:getObjects()
    for i = 0, objects:size() - 1 do add(objects:get(i)) end
    local special = sq:getSpecialObjects()
    for i = 0, special:size() - 1 do add(special:get(i)) end
    return rows
end

AegisInspectorOverlay = ISPanel:derive("AegisInspectorOverlay")

-- scan every level under the cursor, highest first: facade objects (wall
-- signs on upper floors) live above the player's level, resolving only
-- the own z picked the interior behind the wall instead
local MAX_LEVEL = 7

function AegisInspectorOverlay:update()
    ISPanel.update(self)
    local now = getTimestampMs()
    if now < (self.nextScan or 0) then return end
    self.nextScan = now + 100
    self.rows = nil
    self.clickTarget = nil
    pcall(function()
        local p = getPlayer()
        if not p then return end
        local mx, my = getMouseX(), getMouseY()
        local cell = getCell()
        -- pixel-precise pick: every object can test whether the cursor
        -- hits its rendered pixels (sprite mask). Facade signs and walls
        -- live on neighbor squares, hence the 3x3 sweep per level. The
        -- mask wants zoomed coordinates, both spaces are tried
        local zoom = getCore():getZoom(0)
        local zx = math.floor(mx * zoom)
        local zy = math.floor(my * zoom)
        local function maskHit(obj)
            local hit = false
            pcall(function()
                hit = obj:isMaskClicked(mx, my, false) or obj:isMaskClicked(zx, zy, false)
            end)
            return hit
        end
        -- indoors the levels above are cut away, their masks would still
        -- hit
        local topZ = MAX_LEVEL
        local psq = p:getSquare()
        if psq and psq:getRoom() then topZ = math.floor(p:getZ()) end
        for z = topZ, 0, -1 do
            local wx = math.floor(screenToIsoX(0, mx, my, z))
            local wy = math.floor(screenToIsoY(0, mx, my, z))
            for dy = -1, 1 do
                for dx = -1, 1 do
                    local sq = cell:getGridSquare(wx + dx, wy + dy, z)
                    if sq then
                        local rows = collectRows(sq, false, maskHit)
                        if #rows > 0 then
                            self.tileX, self.tileY = sq:getX(), sq:getY()
                            for _, row in ipairs(rows) do row.level = z end
                            self.rows = rows
                            self.clickTarget = rows[#rows].sprite
                            return
                        end
                    end
                end
            end
        end
        -- only the level the cursor actually targets: the highest one
        -- with objects wins, lower floors stay hidden (user feedback:
        -- the full stack was too much)
        local pz = math.floor(p:getZ())
        for z = topZ, 0, -1 do
            local wx = math.floor(screenToIsoX(0, mx, my, z))
            local wy = math.floor(screenToIsoY(0, mx, my, z))
            local sq = cell:getGridSquare(wx, wy, z)
            if sq then
                -- above the player only non-floor objects count, and the
                -- south/east facade walls live on the neighbor squares
                local above = z > pz
                local rows = collectRows(sq, above)
                if above then
                    for _, nb in ipairs({ { wx + 1, wy }, { wx, wy + 1 } }) do
                        local nsq = cell:getGridSquare(nb[1], nb[2], z)
                        if nsq then
                            for _, row in ipairs(collectRows(nsq, true)) do
                                table.insert(rows, row)
                            end
                        end
                    end
                end
                if #rows > 0 then
                    self.tileX, self.tileY = wx, wy
                    for _, row in ipairs(rows) do row.level = z end
                    self.rows = rows
                    -- click target: topmost object of this level
                    self.clickTarget = rows[#rows].sprite
                    return
                end
            end
        end
    end)
end

function AegisInspectorOverlay:render()
    local rows = self.rows
    if not rows or #rows == 0 then return end
    local window = AegisWindow and AegisWindow.instance
    if window and window:isVisible() and window:isMouseOver() then return end
    pcall(function()
        local c = Aegis.col
        local pad = 10
        local lineH = Aegis.fontH(UIFont.Small) + 3
        local w = 200
        for _, row in ipairs(rows) do
            w = math.max(w, Aegis.strW(UIFont.Small, row.sprite) + 24)
            w = math.max(w, Aegis.strW(UIFont.Small, row.info) + 34)
        end
        w = math.min(w + pad * 2, 420)
        local h = pad * 2 + lineH + #rows * (lineH * 2 + 4)
        local x = getMouseX() + 24
        local y = getMouseY() + 24
        local sw, sh = getCore():getScreenWidth(), getCore():getScreenHeight()
        if x + w > sw then x = getMouseX() - w - 12 end
        if y + h > sh then y = sh - h - 8 end
        Aegis.shadow(self, x, y, w, h, 16, 0.5)
        Aegis.roundFrame(self, x, y, w, h, 8, 0.96, c.gold, c.dark)
        Aegis.text(self, tostring(self.tileX) .. "," .. tostring(self.tileY), x + pad, y + pad - 2, UIFont.Small, c.goldDim)
        local ry = y + pad + lineH
        for _, row in ipairs(rows) do
            Aegis.roundRect(self, x + pad, ry + 5, 4, 4, 2, 1, c.gold)
            Aegis.text(self, Aegis.fitText(row.sprite, UIFont.Small, w - pad * 2 - 40), x + pad + 10, ry, UIFont.Small, c.text)
            if row.level then
                Aegis.textRight(self, "z" .. tostring(row.level), x + w - pad, ry, UIFont.Small, c.goldDim)
            end
            Aegis.text(self, Aegis.fitText(row.info, UIFont.Small, w - pad * 2 - 12), x + pad + 10, ry + lineH, UIFont.Small, c.muted)
            ry = ry + lineH * 2 + 4
        end
    end)
end

function AegisInspector.setOn(on)
    if on and not overlay then
        if not (Aegis.allowed(getPlayer()) and Aegis.canSee("tools")) then return end
        local sw, sh = getCore():getScreenWidth(), getCore():getScreenHeight()
        local o = ISPanel:new(0, 0, sw, sh)
        setmetatable(o, AegisInspectorOverlay)
        AegisInspectorOverlay.__index = AegisInspectorOverlay
        o.background = false
        o:initialise()
        o:addToUIManager()
        o.javaObject:setConsumeMouseEvents(false)
        overlay = o
    elseif not on and overlay then
        overlay:removeFromUIManager()
        overlay = nil
    end
end

function AegisInspector.toggle()
    AegisInspector.setOn(not AegisInspector.isOn())
end

-- while the inspector is on, a world click also copies the topmost sprite
-- name (the overlay never eats the click itself, gameplay is unaffected)
Events.OnMouseDown.Add(function(x, y)
    if not overlay or not overlay.rows or #overlay.rows == 0 then return end
    local window = AegisWindow and AegisWindow.instance
    if window and window:isVisible() and window:isMouseOver() then return end
    local sprite = overlay.clickTarget or overlay.rows[#overlay.rows].sprite
    Clipboard.setClipboard(sprite)
    -- the same click also feeds the builder's custom category; the toast
    -- names the store only the first time a sprite lands there
    local added = false
    pcall(function() added = AegisBuilder.addCustom(sprite) end)
    if added then
        Aegis.showToast(getText("UI_Aegis_InspectorStored") .. ": " .. sprite)
    else
        Aegis.showToast(getText("UI_Aegis_InspectorCopied") .. ": " .. sprite)
    end
end)
