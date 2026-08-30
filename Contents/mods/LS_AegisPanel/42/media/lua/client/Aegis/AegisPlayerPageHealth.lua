-- Health page of the player panel: the real vanilla body graphic on the
-- left, vitals overview or per part wound details on the right.
-- The figure is an ISBodyPartPanel derivative, so it uses the shipped
-- anatomy textures (base plate, per part masks, outlines) instead of
-- hand drawn shapes. Colors come from an own scheme in the blue palette,
-- fed by the same 500ms cache the rest of the page reads.
-- Everything is read client side from the local player, no server round
-- trip. Treating a part queues the real vanilla timed actions
-- (ISApplyBandage, ISDisinfect), so the character visibly patches
-- himself up in game.
require "ISUI/ISPanel"
require "ISUI/BodyParts/ISBodyPartPanel"
require "ISUI/ISInventoryPaneContextMenu"
require "TimedActions/ISApplyBandage"
require "TimedActions/ISDisinfect"
require "TimedActions/ISInventoryTransferUtil"
require "Aegis/AegisTheme"
require "Aegis/AegisWidgets"
require "Aegis/AegisPlayerCore"
require "Aegis/AegisPlayerWindow"

AegisPlayerPageHealth = ISPanel:derive("AegisPlayerPageHealth")
AegisPlayerPageHealth.instance = nil

local REFRESH_MS = 500

-- the vanilla body textures are 123x302; everything is drawn scaled and
-- the hit test divides the mouse back down, so the figure can grow
-- without tearing the click zones apart. SCALE_SOFT is the roomy default
-- and the point where the growth rules below take over, small windows
-- shrink the figure so it never leaves the body card. SCALE_MAX is the
-- hard ceiling: the anatomy art ships at one resolution only and its
-- thinnest feature is the 1px outline stroke, which still reads as a
-- line at 2.6x and smears into a band past that
local SCALE_SOFT = 1.5
local SCALE_MAX = 2.6
local SCALE_MIN = 0.9
local TEX_W, TEX_H = 123, 302
local PART_MAX = 16

-- left column share of the page width. The shrink regime keeps the old
-- share, past SCALE_SOFT the figure draws from a tighter one so the
-- vitals and treatment card on the right keeps its width
local COL_SHARE = 0.42
local COL_SHARE_BIG = 0.34
-- legend plus hint lines under the figure (120), reserved with a bit of
-- slack once the figure grows past SCALE_SOFT: the leftover is split
-- above and below, so the head keeps clear of the title
local FOOTER_H = 148

-- scale for a given page size: card height minus title and a bottom
-- margin (the click hint yields on its own when space runs out), left
-- column capped at a share of the page width (70px of it is card
-- frame). Up to SCALE_SOFT this is the shrink path, above it the footer
-- and the tighter column share bound the growth, so the result never
-- drops below what the plain shrink path would give. The floor keeps the
-- parts clickable; below it the page stencil takes over
local function fitScale(w, h)
    local availH = (h - 40) - 48 - 12
    local availW = math.floor(w * COL_SHARE) - 70
    local s = math.min(availH / TEX_H, availW / TEX_W)
    if s > SCALE_SOFT then
        local bigW = math.floor(w * COL_SHARE_BIG) - 70
        s = math.min(s, (availH - FOOTER_H) / TEX_H, bigW / TEX_W)
        if s < SCALE_SOFT then s = SCALE_SOFT end
        if s > SCALE_MAX then s = SCALE_MAX end
    end
    if s < SCALE_MIN then s = SCALE_MIN end
    return s
end

-- wound markers are 8x8 source art, the first thing to go mushy when
-- scaled up. Past SCALE_SOFT they grow at half rate so they stay dots on
-- the small hand and foot masks instead of covering them
local function markerScale(s)
    if s <= SCALE_SOFT then return s end
    return SCALE_SOFT + (s - SCALE_SOFT) * 0.5
end

local function grab(fn)
    local ok, res = pcall(fn)
    if ok then return res end
    return nil
end

local function clamp01(v)
    if not v then return nil end
    if v < 0 then return 0 end
    if v > 1 then return 1 end
    return v
end

-- gentle sine pulse, roughly 1.2s period, continuous across wraps
local function pulse01(now)
    return 0.5 + 0.5 * math.sin((now % 1200) / 1200 * 6.28318)
end

-- extra tones on top of the blue palette: healthy body stays a calm blue
-- grey, light wounds go amber, severe ones use the danger red. BODY_BASE
-- is the dark plate under the part masks, it shows through wherever a
-- part is dimmed
local BODY_OK   = { r = 0.46, g = 0.53, b = 0.64 }
local BODY_BASE = { r = 0.15, g = 0.18, b = 0.23 }
local AMBER     = { r = 0.83, g = 0.62, b = 0.25 }

-- section card in the blue palette (pattern from the other panel pages)
local function card(el, x, y, w, h, titleKey, icon)
    local c = AegisPlayerCol
    Aegis.roundFrame(el, x, y, w, h, 10, 1, c.line, c.panel)
    if titleKey then
        Aegis.icon(el, icon, x + 14, y + 12, 15, 1, c.accent)
        Aegis.text(el, getText(titleKey), x + 36, y + 10, UIFont.Medium, c.text)
    end
end

local function barColor(frac)
    local c = AegisPlayerCol
    if not frac then return c.muted end
    if frac >= 0.6 then return c.ok end
    if frac >= 0.3 then return AMBER end
    return c.danger
end

-- naive word wrap, the left card is narrow enough that the German hint
-- needs two lines
local function wrapLines(str, font, maxW)
    local lines = {}
    if not str or str == "" then return lines end
    local cur = nil
    for word in string.gmatch(str, "%S+") do
        local try = cur and (cur .. " " .. word) or word
        if cur and Aegis.strW(font, try) > maxW then
            table.insert(lines, Aegis.fitText(cur, font, maxW))
            cur = word
        else
            cur = try
        end
    end
    if cur then table.insert(lines, Aegis.fitText(cur, font, maxW)) end
    return lines
end

-- ------------------------------------------------------------------
-- Body part naming. The panel addresses parts by their BodyPartType
-- index (0 to 16), the same order ISBodyPartPanel builds its masks in.
-- Labels are resolved by enum name so a reordered enum cannot mislabel
-- anything; the index list is only the fallback for an unreadable name.
-- ------------------------------------------------------------------
local NAME_KEYS = {
    Hand_L     = "UI_AegisPlayer_SegHandL",
    Hand_R     = "UI_AegisPlayer_SegHandR",
    ForeArm_L  = "UI_AegisPlayer_SegForeArmL",
    ForeArm_R  = "UI_AegisPlayer_SegForeArmR",
    UpperArm_L = "UI_AegisPlayer_SegUpperArmL",
    UpperArm_R = "UI_AegisPlayer_SegUpperArmR",
    Torso_Upper = "UI_AegisPlayer_SegTorsoUpper",
    Torso_Lower = "UI_AegisPlayer_SegTorsoLower",
    Head       = "UI_AegisPlayer_SegHead",
    Neck       = "UI_AegisPlayer_SegNeck",
    Groin      = "UI_AegisPlayer_SegGroin",
    UpperLeg_L = "UI_AegisPlayer_SegUpperLegL",
    UpperLeg_R = "UI_AegisPlayer_SegUpperLegR",
    LowerLeg_L = "UI_AegisPlayer_SegLowerLegL",
    LowerLeg_R = "UI_AegisPlayer_SegLowerLegR",
    Foot_L     = "UI_AegisPlayer_SegFootL",
    Foot_R     = "UI_AegisPlayer_SegFootR",
}

local INDEX_KEYS = {
    [0] = "UI_AegisPlayer_SegHandL",
    [1] = "UI_AegisPlayer_SegHandR",
    [2] = "UI_AegisPlayer_SegForeArmL",
    [3] = "UI_AegisPlayer_SegForeArmR",
    [4] = "UI_AegisPlayer_SegUpperArmL",
    [5] = "UI_AegisPlayer_SegUpperArmR",
    [6] = "UI_AegisPlayer_SegTorsoUpper",
    [7] = "UI_AegisPlayer_SegTorsoLower",
    [8] = "UI_AegisPlayer_SegHead",
    [9] = "UI_AegisPlayer_SegNeck",
    [10] = "UI_AegisPlayer_SegGroin",
    [11] = "UI_AegisPlayer_SegUpperLegL",
    [12] = "UI_AegisPlayer_SegUpperLegR",
    [13] = "UI_AegisPlayer_SegLowerLegL",
    [14] = "UI_AegisPlayer_SegLowerLegR",
    [15] = "UI_AegisPlayer_SegFootL",
    [16] = "UI_AegisPlayer_SegFootR",
}

local keyCache = nil
local function partKey(idx)
    if not keyCache then
        keyCache = {}
        for i = 0, PART_MAX do
            local key = nil
            local t = grab(function() return BodyPartType.FromIndex(i) end)
            if t then
                local name = grab(function() return BodyPartType.ToString(t) end)
                if name then key = NAME_KEYS[tostring(name)] end
            end
            keyCache[i] = key or INDEX_KEYS[i]
        end
    end
    return keyCache[idx] or ""
end

-- one row per wound state, ordered severe to light. sev 2 pulses red on
-- the figure, sev 1 draws amber, sev 0 never colors a part
local WOUNDS = {
    { flag = "bleeding",       sev = 2, key = "UI_AegisPlayer_WndBleeding",       hint = "UI_AegisPlayer_WndBleedingHint" },
    { flag = "bitten",         sev = 2, key = "UI_AegisPlayer_WndBitten",         hint = "UI_AegisPlayer_WndBittenHint" },
    { flag = "deepWound",      sev = 2, key = "UI_AegisPlayer_WndDeep",           hint = "UI_AegisPlayer_WndDeepHint" },
    { flag = "bullet",         sev = 2, key = "UI_AegisPlayer_WndBullet",         hint = "UI_AegisPlayer_WndBulletHint" },
    { flag = "glass",          sev = 2, key = "UI_AegisPlayer_WndGlass",          hint = "UI_AegisPlayer_WndGlassHint" },
    { flag = "zombieInf",      sev = 2, key = "UI_AegisPlayer_WndZombieInf",      hint = "UI_AegisPlayer_WndZombieInfHint" },
    { flag = "woundInf",       sev = 2, key = "UI_AegisPlayer_WndWoundInf",       hint = "UI_AegisPlayer_WndWoundInfHint" },
    { flag = "fracture",       sev = 2, key = "UI_AegisPlayer_WndFracture",       hint = "UI_AegisPlayer_WndFractureHint" },
    { flag = "fractureSplint", sev = 1, key = "UI_AegisPlayer_WndFractureSplint", hint = "UI_AegisPlayer_WndFractureSplintHint" },
    { flag = "burnt",          sev = 1, key = "UI_AegisPlayer_WndBurnt",          hint = "UI_AegisPlayer_WndBurntHint" },
    { flag = "cut",            sev = 1, key = "UI_AegisPlayer_WndCut",            hint = "UI_AegisPlayer_WndCutHint" },
    { flag = "scratched",      sev = 1, key = "UI_AegisPlayer_WndScratched",      hint = "UI_AegisPlayer_WndScratchedHint" },
    { flag = "bandaged",       sev = 0, key = "UI_AegisPlayer_WndBandaged",       hint = "UI_AegisPlayer_WndBandagedHint" },
}

-- readable wound states per body part, read set from AegisDeaths woundLines
local function readPart(part)
    local f = {}
    local function flag(name, fn)
        if grab(fn) == true then f[name] = true end
    end
    flag("bitten", function() return part:bitten() end)
    flag("scratched", function() return part:scratched() end)
    flag("cut", function() return part:isCut() end)
    flag("deepWound", function() return part:deepWounded() end)
    flag("bleeding", function() return part:bleeding() end)
    flag("burnt", function() return part:isBurnt() end)
    flag("bullet", function() return part:haveBullet() end)
    flag("glass", function() return part:haveGlass() end)
    flag("woundInf", function() return part:isInfectedWound() end)
    -- vanilla keeps the real zombie infection uncertain on purpose, this
    -- flag answers it outright (server request: sandbox switch to hide it
    -- again for servers that want the uncertainty kept)
    if AegisShared.featureOn("PlayerHealthInfection") then
        flag("zombieInf", function() return part:IsInfected() end)
    end
    flag("bandaged", function() return part:bandaged() end)
    -- no isFractured in B42, fracture time is the proof
    if (grab(function() return part:getFractureTime() end) or 0) > 0 then
        if grab(function() return part:isSplint() end) == true then
            f.fractureSplint = true
        else
            f.fracture = true
        end
    end
    f.hp = tonumber(grab(function() return part:getHealth() end))
    return f
end

-- treatable means the vanilla injury gate of the health panel passes
-- (ISHealthPanel BaseHandler:isInjured): open injury, stitches or a
-- splint, and no bandage on top yet
local function partTreatable(part)
    return grab(function()
        return (part:HasInjury() or part:stitched() or part:getSplintFactor() > 0)
            and not part:bandaged()
    end) == true
end

-- ------------------------------------------------------------------
-- Item search, same net as the vanilla health panel: every container
-- ISInventoryPaneContextMenu.getContainers reaches plus one bag level.
-- Bandage test is getBandagePower() > 0 (covers ripped sheets), the
-- disinfect test mirrors HDisinfect:checkItem (alcohol fluid or a
-- drainable with alcohol power 4)
-- ------------------------------------------------------------------
local function isBandageItem(item)
    return (grab(function() return item:getBandagePower() end) or 0) > 0
end

local function isDisinfectItem(item)
    return grab(function()
        if item:hasComponent(ComponentType.FluidContainer) then
            local fc = item:getFluidContainer()
            return fc:getAmount() > 0.15
                and (fc:getProperties():getAlcohol() / fc:getAmount() + 0.001) >= 0.4
        end
        return item:IsDrainable() and item:getAlcoholPower() == 4.0
    end) == true
end

local function findMedItems(p)
    local band, disi = nil, nil
    local containers = grab(function() return ISInventoryPaneContextMenu.getContainers(p) end)
    if not containers then return nil, nil end
    local queue = {}
    local n = grab(function() return containers:size() end) or 0
    for i = 0, n - 1 do
        local cont = grab(function() return containers:get(i) end)
        if cont then table.insert(queue, cont) end
    end
    local qi = 1
    while queue[qi] and qi <= 64 do
        local cont = queue[qi]
        qi = qi + 1
        local items = grab(function() return cont:getItems() end)
        local cnt = items and grab(function() return items:size() end) or 0
        for i = 0, cnt - 1 do
            local item = grab(function() return items:get(i) end)
            if item then
                if grab(function() return item:IsInventoryContainer() end) == true then
                    local inv = grab(function() return item:getInventory() end)
                    if inv then table.insert(queue, inv) end
                else
                    if not band and isBandageItem(item) then band = item end
                    if not disi and isDisinfectItem(item) then disi = item end
                end
                if band and disi then return band, disi end
            end
        end
    end
    return band, disi
end

-- queue the vanilla way (HApplyBandage:perform): move the item into the
-- main inventory first if needed, then chain the medical action
local function queueTreat(p, item, makeAction)
    local ok, act = pcall(makeAction)
    if not ok or not act then return end
    if grab(function() return p:getInventory():contains(item) end) == true then
        ISTimedActionQueue.add(act)
        return
    end
    local okMove, move = pcall(function()
        return ISInventoryTransferUtil.newInventoryTransferAction(p, item, item:getContainer(), p:getInventory())
    end)
    if not okMove or not move then return end
    ISTimedActionQueue.add(move)
    ISTimedActionQueue.addAfter(move, act)
end

-- ==================================================================
-- The figure: vanilla anatomy textures, Aegis colors
-- ==================================================================
-- Color scheme handed to ISBodyPartPanel. Value 1 is untouched, 0.5 is
-- lightly hurt, 0 is severe. Built lazily because Color is a Java class
local colorScheme = nil
local function figureScheme()
    if colorScheme then return colorScheme end
    local c = AegisPlayerCol
    colorScheme = {
        { val = 0.0, color = Color.new(c.danger.r, c.danger.g, c.danger.b, 1) },
        { val = 0.5, color = Color.new(AMBER.r, AMBER.g, AMBER.b, 1) },
        { val = 1.0, color = Color.new(BODY_OK.r, BODY_OK.g, BODY_OK.b, 1) },
    }
    return colorScheme
end

AegisHealthFigure = ISBodyPartPanel:derive("AegisHealthFigure")

function AegisHealthFigure:new(player, x, y, target, onPartSelected, scale)
    local o = ISBodyPartPanel.new(self, player, x, y, target, onPartSelected)
    -- the base class sizes itself to the raw texture, the scaled figure
    -- needs its own box or clicks stop at the wrong edge
    o.scale = scale or SCALE_SOFT
    o.markerScale = markerScale(o.scale)
    o.width = math.floor(TEX_W * o.scale)
    o.height = math.floor(TEX_H * o.scale)
    o.selectedIdx = nil
    o.hoverIdx = nil
    return o
end

-- runs once after initialise: every mask gets its own index plus cached
-- color floats, so the frame loop never touches Java
function AegisHealthFigure:setup()
    if not self.bps then return end
    self.nodeW, self.nodeH = 0, 0
    self.nodeOW, self.nodeOH = 0, 0
    pcall(function()
        self.nodeW = self.nodes.nodeTex:getWidthOrig()
        self.nodeH = self.nodes.nodeTex:getHeightOrig()
        self.nodeOW = self.nodes.nodeOutlineTex:getWidth()
        self.nodeOH = self.nodes.nodeOutlineTex:getHeight()
    end)
    for i = 1, #self.bps do
        local bp = self.bps[i]
        bp.aegisIdx = i - 1
        bp.aegisLevel = 0
        bp.aegisRim = false
        bp.aegisR, bp.aegisG, bp.aegisB = BODY_OK.r, BODY_OK.g, BODY_OK.b
        self:applyPart(bp.aegisIdx, 1, 0, false)
    end
end

-- one cache entry into the figure. level 0 healthy, 1 light, 2 severe;
-- rim marks a bandaged or splinted part
function AegisHealthFigure:applyPart(idx, value, level, rim)
    local bp = self.bps and self.bps[idx + 1]
    if not bp then return end
    bp.aegisLevel = level or 0
    bp.aegisRim = rim == true
    self:setValue(bp.bodyPartType, value, true)
    bp.aegisR = bp.color:getRedFloat()
    bp.aegisG = bp.color:getGreenFloat()
    bp.aegisB = bp.color:getBlueFloat()
end

function AegisHealthFigure:clearSelection()
    self.selectedIdx = nil
    self.selectedBp = false
    self.lockedSelection = false
end

function AegisHealthFigure:prerender()
    ISPanelJoypad.prerender(self)
end

function AegisHealthFigure:render()
    ISPanelJoypad.render(self)
    if not self.bps then return end
    local c = AegisPlayerCol
    local pulse = pulse01(getTimestampMs())

    -- CAREFUL: the bps textures are TRIMMED atlas entries. drawTexture
    -- adds their offset and uses their real size on its own, which is why
    -- vanilla can draw everything at 0,0. drawTextureScaled does not, so
    -- every plate has to carry its own offset and size, scaled (live
    -- scaling to the full canvas stretched every mask
    -- across the whole figure)
    local s = self.scale
    local ms = self.markerScale or s
    local function plate(tex, a, r, g, b)
        if not tex then return end
        self:drawTextureScaled(tex,
            tex:getOffsetX() * s, tex:getOffsetY() * s,
            tex:getWidth() * s, tex:getHeight() * s, a, r, g, b)
    end
    -- masks keep their metrics cached by the base class
    local function mask(bp, a, r, g, b)
        self:drawTextureScaled(bp.texture,
            bp.offsetX * s, bp.offsetY * s,
            bp.width * s, bp.height * s, a, r, g, b)
    end

    if self.baseTexture then
        plate(self.baseTexture, self.backgroundAlpha,
            BODY_BASE.r, BODY_BASE.g, BODY_BASE.b)
    end

    for i = 1, #self.bps do
        local bp = self.bps[i]
        -- aegisR is only there once setup ran, never draw a raw mask
        if bp.texture and bp.aegisR then
            local a = self.defaultAlpha
            if self.selectedIdx ~= nil then
                if bp.aegisIdx == self.selectedIdx then
                    a = self.selectedAlpha
                else
                    a = self.deselectedAlpha
                end
            end
            if bp.aegisIdx == self.hoverIdx and bp.aegisIdx ~= self.selectedIdx then
                a = math.min(1, a + 0.24)
            end
            mask(bp, a, bp.aegisR, bp.aegisG, bp.aegisB)
            -- the old pulse idea lives on here: severe parts breathe red
            if bp.aegisLevel >= 2 then
                mask(bp, a * (0.14 + 0.34 * pulse), c.danger.r, c.danger.g, c.danger.b)
            end
            if bp.aegisIdx == self.hoverIdx and bp.aegisIdx ~= self.selectedIdx then
                mask(bp, 0.14, 1, 1, 1)
            end
        end
    end

    -- vanilla draws the outline plate untinted on top, it carries the
    -- anatomy lines that separate the masks
    if self.outlineTex then
        plate(self.outlineTex, 0.85, 1, 1, 1)
    end

    if not self.nodes.enabled then return end
    local nodeTex, nodeOutline = self.nodes.nodeTex, self.nodes.nodeOutlineTex
    if not nodeTex or not nodeOutline then return end
    for i = 1, #self.bps do
        local bp = self.bps[i]
        local sel = bp.aegisR ~= nil and bp.aegisIdx == self.selectedIdx
        if bp.aegisR and (sel or bp.aegisLevel >= 1 or bp.aegisRim) then
            local nr, ng, nb = bp.aegisR, bp.aegisG, bp.aegisB
            if sel then
                nr, ng, nb = c.accentHi.r, c.accentHi.g, c.accentHi.b
            elseif bp.aegisRim and bp.aegisLevel < 2 then
                nr, ng, nb = c.accent.r, c.accent.g, c.accent.b
            end
            local a = sel and self.nodeAlpha or (self.nodeAlpha * 0.7)
            -- markers are trimmed atlas entries too: draw their real size
            -- centred on the part centre. The centre follows the figure
            -- scale, the marker size the damped one
            local cx = (bp.centerX + bp.nodeOffsetX) * s
            local cy = (bp.centerY + bp.nodeOffsetY) * s
            local function marker(tex)
                if not tex then return end
                local mw, mh = tex:getWidth() * ms, tex:getHeight() * ms
                self:drawTextureScaled(tex, cx - mw / 2, cy - mh / 2, mw, mh, a, nr, ng, nb)
            end
            marker(nodeTex)
            marker(nodeOutline)
        end
    end
end

-- the vanilla lookup compares against raw texture offsets, so the mouse
-- has to come back down to texture space before asking (the figure is
-- drawn at self.scale)
function AegisHealthFigure:getPartForCoordinate(mx, my)
    return ISBodyPartPanel.getPartForCoordinate(self, mx / self.scale, my / self.scale)
end

-- hover only marks, the vanilla hover selection would fight the click
-- toggle below
function AegisHealthFigure:onMouseMove(dx, dy)
    local bp = self:getPartForCoordinate(self:getMouseX(), self:getMouseY())
    self.hoverIdx = bp and bp.aegisIdx or nil
end

function AegisHealthFigure:onMouseMoveOutside(dx, dy)
    self.hoverIdx = nil
end

function AegisHealthFigure:onMouseDown(x, y)
    return true
end

function AegisHealthFigure:onMouseUp(x, y)
    local bp = self:getPartForCoordinate(x, y)
    local idx = bp and bp.aegisIdx or nil
    if idx == nil then return end
    Aegis.sound()
    if self.selectedIdx == idx then
        self.selectedIdx = nil
        self.selectedBp = false
    else
        self.selectedIdx = idx
        -- keep the vanilla field in step for anything inherited
        self.selectedBp = bp
    end
    self.lockedSelection = self.selectedIdx ~= nil
    if self.onPartSelected then
        self.onPartSelected(self.functionTarget, self.selectedIdx)
    end
end

function AegisHealthFigure:onRightMouseUp(x, y)
    if self.selectedIdx == nil then return end
    self:clearSelection()
    if self.onPartSelected then
        self.onPartSelected(self.functionTarget, nil)
    end
end

-- ------------------------------------------------------------------
-- Page
-- ------------------------------------------------------------------
function AegisPlayerPageHealth.create(window, x, y, w, h)
    local o = ISPanel:new(x, y, w, h)
    setmetatable(o, AegisPlayerPageHealth)
    AegisPlayerPageHealth.__index = AegisPlayerPageHealth
    o.background = false
    o.window = window
    o.data = { parts = {} }
    o.selected = nil
    o.nextRefresh = 0
    AegisPlayerPageHealth.instance = o
    return o
end

-- rebuildPages recreates the page at the current content size, so the
-- scale always matches the window the figure will live in. Everything
-- else on the page reads figScale/figW/figH, never the figure element:
-- the live stretch mutates child sizes mid drag
function AegisPlayerPageHealth:applyScale()
    self.scaleW, self.scaleH = self.width, self.height
    self.figScale = fitScale(self.width, self.height)
    self.figW = math.floor(TEX_W * self.figScale)
    self.figH = math.floor(TEX_H * self.figScale)
    local fig = self.figure
    if fig then
        fig.scale = self.figScale
        fig.markerScale = markerScale(self.figScale)
        fig:setWidth(self.figW)
        fig:setHeight(self.figH)
    end
end

function AegisPlayerPageHealth:createChildren()
    self:applyScale()
    self.bandageBtn = AegisButton:new(0, 0, 120, 34, getText("UI_AegisPlayer_HealthBandage"),
        "heal", self, AegisPlayerPageHealth.onBandage)
    self.bandageBtn:setVisible(false)
    self:addChild(self.bandageBtn)
    self.disinfectBtn = AegisButton:new(0, 0, 120, 34, getText("UI_AegisPlayer_HealthDisinfect"),
        nil, self, AegisPlayerPageHealth.onDisinfect)
    self.disinfectBtn:setVisible(false)
    self:addChild(self.disinfectBtn)
    self:buildFigure()
end

-- the whole build is guarded: ISBodyPartPanel reads the player, the
-- BodyPartType enum and 19 textures during initialise. If any of that is
-- unavailable the page simply runs without a figure instead of tearing
-- down the panel
function AegisPlayerPageHealth:buildFigure()
    local p = getPlayer()
    if not p then return end
    local page = self
    local ok, fig = pcall(function()
        local f = AegisHealthFigure:new(p, 0, 0, page, AegisPlayerPageHealth.onFigurePart, page.figScale)
        f:initialise()
        return f
    end)
    if not ok or not fig then return end
    fig:setAlphas(0.88, 1.0, 1.0, 0.34, 0.9)
    fig:setColorScheme(figureScheme())
    fig:enableNodes("media/ui/BodyParts/bps_node_diamond",
        "media/ui/BodyParts/bps_node_diamond_outline")
    fig:setup()
    self.figure = fig
    self:addChild(fig)
end

function AegisPlayerPageHealth:onFigurePart(idx)
    self.selected = idx
end

-- the mask set is picked once from the character's sex, a respawn can
-- hand us a different one while the page lives on
function AegisPlayerPageHealth:rebuildFigure()
    if self.figure then
        self:removeChild(self.figure)
        self.figure = nil
    end
    self.selected = nil
    self:buildFigure()
end

function AegisPlayerPageHealth:refresh()
    local p = getPlayer()
    if not p then return end
    local d = { parts = {} }

    local female = grab(function() return p:isFemale() end)
    if self.figure and female ~= nil and self.figure.bFemale ~= female then
        self:rebuildFigure()
    end

    local bd = grab(function() return p:getBodyDamage() end)
    if bd then
        d.overall = tonumber(grab(function() return bd:getOverallBodyHealth() end))
        d.infected = AegisShared.featureOn("PlayerHealthInfection")
            and grab(function() return bd:isInfected() end) == true
        d.temp = tonumber(grab(function()
            local thermo = bd:getThermoregulator()
            if not thermo then return nil end
            return thermo:getCoreTemperature()
        end))
        local parts = grab(function() return bd:getBodyParts() end)
        local n = parts and grab(function() return parts:size() end) or 0
        for i = 0, n - 1 do
            local part = grab(function() return parts:get(i) end)
            local ptype = part and grab(function() return part:getType() end) or nil
            local idx = ptype and tonumber(grab(function() return BodyPartType.ToIndex(ptype) end)) or nil
            if idx and idx >= 0 and idx <= PART_MAX then
                local st = { sev = 0, rim = false, hp = nil, wounds = {}, treat = false }
                local f = readPart(part)
                for _, wd in ipairs(WOUNDS) do
                    if f[wd.flag] then
                        if wd.sev > st.sev then st.sev = wd.sev end
                        table.insert(st.wounds, wd)
                    end
                end
                if f.bandaged or f.fractureSplint then st.rim = true end
                if f.hp then
                    -- battered part without a listed wound still shows amber
                    if f.hp < 75 and st.sev < 1 then st.sev = 1 end
                    st.hp = f.hp
                end
                st.treat = partTreatable(part)
                d.parts[idx] = st
            end
        end
        self:pushFigure(d)
    end

    -- medical supplies for the button states, names only. The items are
    -- searched again on click so nothing stale is ever handed to an action.
    -- Skipped once dead: findMedItems asks vanilla's inventory pane helper,
    -- which reaches for the inventory UI without checking it still exists
    -- and throws every call while there is none (a wall
    -- of "attempted index: inventoryPane of non-table: null" until respawn)
    local dead = grab(function() return p:isDead() end) == true
    local band, disi = nil, nil
    if not dead then band, disi = findMedItems(p) end
    d.bandageName = band and grab(function() return band:getName() end) or nil
    d.disinfectName = disi and grab(function() return disi:getName() end) or nil

    -- vitals: B42 stat map first, the classic getters as fallback
    d.hunger = tonumber(grab(function() return p:getStats():get(CharacterStat.HUNGER) end))
    if d.hunger == nil then d.hunger = tonumber(grab(function() return p:getStats():getHunger() end)) end
    d.thirst = tonumber(grab(function() return p:getStats():get(CharacterStat.THIRST) end))
    if d.thirst == nil then d.thirst = tonumber(grab(function() return p:getStats():getThirst() end)) end
    d.fatigue = tonumber(grab(function() return p:getStats():get(CharacterStat.FATIGUE) end))
    if d.fatigue == nil then d.fatigue = tonumber(grab(function() return p:getStats():getFatigue() end)) end
    d.endurance = tonumber(grab(function() return p:getStats():get(CharacterStat.ENDURANCE) end))
    if d.endurance == nil then d.endurance = tonumber(grab(function() return p:getStats():getEndurance() end)) end
    d.weight = tonumber(grab(function()
        local nut = p:getNutrition()
        if not nut then return nil end
        return nut:getWeight()
    end))

    self.data = d
end

-- cache to figure values. Healthy parts stay in the upper band and only
-- drift towards amber as their condition drops, so a bruise reads
-- differently from an open wound
function AegisPlayerPageHealth:pushFigure(d)
    local fig = self.figure
    if not fig then return end
    for idx = 0, PART_MAX do
        local st = d.parts[idx]
        local sev = st and st.sev or 0
        local hp = st and st.hp or 100
        local v
        if sev >= 2 then
            v = 0
        elseif sev == 1 then
            v = 0.28 + 0.22 * clamp01(hp / 100)
        else
            v = 0.70 + 0.30 * clamp01((hp - 75) / 25)
        end
        fig:applyPart(idx, v, sev, st and st.rim or false)
    end
end

function AegisPlayerPageHealth:onShow()
    self:refresh()
    self.nextRefresh = getTimestampMs() + REFRESH_MS
end

function AegisPlayerPageHealth:update()
    ISPanel.update(self)
    if not self:isVisible() then return end
    local now = getTimestampMs()
    if now >= self.nextRefresh then
        self.nextRefresh = now + REFRESH_MS
        self:refresh()
    end
end

-- ------------------------------------------------------------------
-- Treatment: queue the real vanilla timed actions on the own character
-- (client side only, the engine syncs timed actions itself)
-- ------------------------------------------------------------------

-- body part behind the current selection, refetched fresh by type
function AegisPlayerPageHealth:selectedTreatPart()
    local idx = self.selected
    if idx == nil then return nil, nil end
    local st = self.data and self.data.parts and self.data.parts[idx] or nil
    if not st or not st.treat then return nil, nil end
    local p = getPlayer()
    if not p then return nil, nil end
    local part = grab(function()
        return p:getBodyDamage():getBodyPart(BodyPartType.FromIndex(idx))
    end)
    return part, p
end

function AegisPlayerPageHealth:onBandage()
    local part, p = self:selectedTreatPart()
    if not part then return end
    local band = findMedItems(p)
    if not band then return end
    queueTreat(p, band, function()
        return ISApplyBandage:new(p, p, band, part, true)
    end)
    self.nextRefresh = 0
end

function AegisPlayerPageHealth:onDisinfect()
    local part, p = self:selectedTreatPart()
    if not part then return end
    local _, disi = findMedItems(p)
    if not disi then return end
    queueTreat(p, disi, function()
        return ISDisinfect:new(p, p, disi, part)
    end)
    self.nextRefresh = 0
end

-- ------------------------------------------------------------------
-- Left: the body card. The figure is a child element sized by figScale,
-- the card is laid out around it, never the other way round
-- ------------------------------------------------------------------
function AegisPlayerPageHealth:drawBodyCard(x, y, w, h)
    local c = AegisPlayerCol
    card(self, x, y, w, h, "UI_AegisPlayer_HealthBody", "heal")
    local fig = self.figure
    if not fig then return end
    -- page fields, not fig.width: the live stretch mutates child widths
    local figW = self.figW or fig.width
    local figH = self.figH or fig.height
    -- pin the element box back, otherwise the stretched width drags the
    -- click zones away from the drawn figure for the length of the drag
    if fig.width ~= figW then fig:setWidth(figW) end
    if fig.height ~= figH then fig:setHeight(figH) end

    local textW = w - 24
    local lineH = Aegis.fontH(UIFont.Small)
    if self.hintW ~= textW then
        self.hintW = textW
        self.hintLines = wrapLines(getText("UI_AegisPlayer_HealthClickHint"), UIFont.Small, textW)
    end

    -- reserve the real footer height, then centre the figure in what is
    -- left. Only tall cards also get the legend
    local hintH = #self.hintLines * lineH + 16
    local roomy = h - 48 - hintH - figH >= 68
    local bottom = hintH + (roomy and 78 or 0)
    local figX = x + math.floor((w - figW) / 2)
    -- the figure never leaves the card: on a short window it sits right
    -- under the title instead of centring itself out of the frame (live
    -- the old maths let it hang into the world)
    local space = h - 48 - bottom - figH
    local figY = y + 48 + math.max(0, math.floor(space / 2))
    if space < 0 then figY = y + 48 end
    fig:setX(figX)
    fig:setY(figY)

    if roomy then
        local ly = figY + figH + 16
        local rows = {
            { key = "UI_AegisPlayer_HealthLegendOk", col = BODY_OK },
            { key = "UI_AegisPlayer_HealthLegendLight", col = AMBER },
            { key = "UI_AegisPlayer_HealthLegendBad", col = c.danger },
        }
        for _, row in ipairs(rows) do
            Aegis.roundRect(self, x + 16, ly + 5, 8, 8, 4, 1, row.col)
            Aegis.text(self, Aegis.fitText(getText(row.key), UIFont.Small, textW - 22),
                x + 32, ly, UIFont.Small, c.muted)
            ly = ly + 20
        end
    end

    -- the hint keeps clear of the figure: on a short card the feet would
    -- otherwise sit on the text
    local hy = y + h - 12 - #self.hintLines * lineH
    if hy < figY + figH + 6 then return end
    for _, line in ipairs(self.hintLines) do
        Aegis.textCentre(self, line, x + math.floor(w / 2), hy, UIFont.Small, c.muted)
        hy = hy + lineH
    end
end

-- ------------------------------------------------------------------
-- Right: vitals overview
-- ------------------------------------------------------------------
function AegisPlayerPageHealth:drawBar(x, y, w, labelKey, frac, valueText)
    local c = AegisPlayerCol
    Aegis.text(self, getText(labelKey), x, y, UIFont.Small, c.muted)
    Aegis.textRight(self, valueText or "--", x + w, y, UIFont.Small, c.text)
    Aegis.roundRect(self, x, y + 20, w, 10, 5, 1, c.dark)
    if frac and frac > 0 then
        Aegis.roundRect(self, x, y + 20, math.max(6, math.floor(w * math.min(1, frac))), 10, 5, 1, barColor(frac))
    end
end

function AegisPlayerPageHealth:drawTempBar(x, y, w, temp)
    local c = AegisPlayerCol
    Aegis.text(self, getText("UI_AegisPlayer_HealthBarTemp"), x, y, UIFont.Small, c.muted)
    local col = c.text
    if temp then
        local off = math.abs(temp - 37)
        if off > 2 then col = c.danger
        elseif off > 0.8 then col = AMBER
        else col = c.ok end
    end
    Aegis.textRight(self, temp and string.format("%.1f C", temp) or "--", x + w, y, UIFont.Small, col)
    local ty = y + 20
    local TMIN, TMAX = 30, 42
    Aegis.roundRect(self, x, ty, w, 10, 5, 1, c.dark)
    -- ideal band 36.5 to 37.5
    local bx = x + math.floor(w * (36.5 - TMIN) / (TMAX - TMIN))
    local bandW = math.max(4, math.floor(w / (TMAX - TMIN)))
    Aegis.roundRect(self, bx, ty, bandW, 10, 3, 0.8, c.accentDim)
    if temp then
        local frac = (temp - TMIN) / (TMAX - TMIN)
        if frac < 0 then frac = 0 end
        if frac > 1 then frac = 1 end
        Aegis.roundRect(self, x + math.floor((w - 4) * frac), ty - 3, 4, 16, 2, 1, col)
    end
end

function AegisPlayerPageHealth:drawVitals(d, x, y, w, h)
    local c = AegisPlayerCol
    card(self, x, y, w, h, "UI_AegisPlayer_HealthOverview", "heal")
    local bx = x + 16
    local bw = w - 32
    local yy = y + 48

    self:drawBar(bx, yy, bw, "UI_AegisPlayer_HealthBarHealth", d.overall and d.overall / 100,
        d.overall and (tostring(math.floor(d.overall + 0.5)) .. "%"))
    yy = yy + 48

    -- hunger, thirst and fatigue count up towards bad, show the good side
    local function level(v, invert)
        if v == nil then return nil end
        if v < 0 then v = 0 end
        if v > 1 then v = 1 end
        if invert then v = 1 - v end
        return v
    end
    local rows = {
        { key = "UI_AegisPlayer_HealthBarFood", frac = level(d.hunger, true) },
        { key = "UI_AegisPlayer_HealthBarWater", frac = level(d.thirst, true) },
        { key = "UI_AegisPlayer_HealthBarEnergy", frac = level(d.fatigue, true) },
        { key = "UI_AegisPlayer_HealthBarEndurance", frac = level(d.endurance, false) },
    }
    for _, row in ipairs(rows) do
        self:drawBar(bx, yy, bw, row.key, row.frac,
            row.frac and (tostring(math.floor(row.frac * 100 + 0.5)) .. "%"))
        yy = yy + 48
    end

    self:drawTempBar(bx, yy, bw, d.temp)
    yy = yy + 56

    Aegis.text(self, getText("UI_AegisPlayer_HealthWeight"), bx, yy, UIFont.Small, c.muted)
    local wtxt = d.weight and (tostring(math.floor(d.weight * 10 + 0.5) / 10) .. " kg") or "--"
    Aegis.textRight(self, wtxt, bx + bw, yy, UIFont.Small, c.text)
end

-- ------------------------------------------------------------------
-- Right: wound details of the selected part
-- ------------------------------------------------------------------
function AegisPlayerPageHealth:drawDetails(d, idx, x, y, w, h)
    local c = AegisPlayerCol
    card(self, x, y, w, h, partKey(idx), "heal")
    local st = d.parts and d.parts[idx]
    if st and st.hp then
        local pct = math.floor(st.hp + 0.5)
        Aegis.textRight(self, getText("UI_AegisPlayer_HealthPartHp", tostring(pct)),
            x + w - 16, y + 12, UIFont.Small, barColor(st.hp / 100))
    end

    local wounds = st and st.wounds or {}
    if #wounds == 0 then
        Aegis.textCentre(self, getText("UI_AegisPlayer_HealthNoWounds"),
            x + math.floor(w / 2), y + math.floor(h / 2) - 30, UIFont.Medium, c.ok)
    else
        local yy = y + 48
        local rowH = 44
        -- bottom stays free for the treat buttons and the back hint
        local maxRows = math.floor((h - 48 - 84) / rowH)
        local shown = math.min(#wounds, math.max(1, maxRows))
        for i = 1, shown do
            local wd = wounds[i]
            local dotC = c.accent
            if wd.sev >= 2 then dotC = c.danger
            elseif wd.sev == 1 then dotC = AMBER end
            Aegis.roundRect(self, x + 18, yy + 5, 8, 8, 4, 1, dotC)
            Aegis.text(self, Aegis.fitText(getText(wd.key), UIFont.Small, w - 60),
                x + 36, yy, UIFont.Small, c.text)
            Aegis.text(self, Aegis.fitText(getText(wd.hint), UIFont.Small, w - 60),
                x + 36, yy + 18, UIFont.Small, c.muted)
            yy = yy + rowH
        end
        if #wounds > shown then
            Aegis.text(self, getText("UI_AegisPlayer_HealthMore", tostring(#wounds - shown)),
                x + 36, yy, UIFont.Small, c.muted)
        end
    end

    Aegis.textCentre(self, getText("UI_AegisPlayer_HealthBackHint"),
        x + math.floor(w / 2), y + h - 30, UIFont.Small, c.muted)
end

-- park the treat buttons inside the details card and gate them on the
-- cached state: injury on the part plus a matching item somewhere in
-- the inventory. Tooltips carry the found item or the missing reason
function AegisPlayerPageHealth:layoutTreatButtons(d, idx, x, y, w, h)
    local st = d.parts and d.parts[idx]
    local canTreat = st ~= nil and st.treat == true
    local bw = math.floor((w - 32 - 12) / 2)
    local by = y + h - 72

    self.bandageBtn:setX(x + 16)
    self.bandageBtn:setY(by)
    self.bandageBtn:setWidth(bw)
    self.bandageBtn:setHeight(34)
    self.bandageBtn:setVisible(true)
    self.bandageBtn:setEnabled(canTreat and d.bandageName ~= nil)
    if canTreat and d.bandageName == nil then
        self.bandageBtn.tooltip = getText("UI_AegisPlayer_HealthNoBandage")
    else
        self.bandageBtn.tooltip = d.bandageName
    end

    self.disinfectBtn:setX(x + 16 + bw + 12)
    self.disinfectBtn:setY(by)
    self.disinfectBtn:setWidth(bw)
    self.disinfectBtn:setHeight(34)
    self.disinfectBtn:setVisible(true)
    self.disinfectBtn:setEnabled(canTreat and d.disinfectName ~= nil)
    if canTreat and d.disinfectName == nil then
        self.disinfectBtn.tooltip = getText("UI_AegisPlayer_HealthNoDisinfect")
    else
        self.disinfectBtn.tooltip = d.disinfectName
    end
end

-- ------------------------------------------------------------------
-- Frame
-- ------------------------------------------------------------------
function AegisPlayerPageHealth:prerender()
    -- the window only clips while the grip drags; the scale floor can
    -- still overflow on tiny screens and the live stretch reuses the old
    -- scale, so the page clips itself every frame
    self:setStencilRect(0, 0, self.width, self.height)
    local c = AegisPlayerCol
    local d = self.data or { parts = {} }
    local pad = 20
    -- follow the live stretch: the window only rebuilds on release, so
    -- without this the figure keeps the scale of the size it was built at
    -- and a shrinking window cuts it off instead of shrinking it
    if not self.figW or self.scaleW ~= self.width or self.scaleH ~= self.height then
        self:applyScale()
    end
    -- the card follows the figure width, never the other way round
    local leftW = self.figW + 70

    self:drawBodyCard(pad, pad, leftW, self.height - pad * 2)

    local rx = pad + leftW + 16
    local rw = self.width - rx - pad
    local ry = pad
    if d.infected then
        local a = 0.7 + 0.3 * pulse01(getTimestampMs())
        Aegis.roundFrame(self, rx, ry, rw, 42, 10, a, c.danger, c.dark)
        Aegis.icon(self, "heal", rx + 14, ry + 12, 18, a, c.danger)
        Aegis.text(self, getText("UI_AegisPlayer_HealthInfected"), rx + 42, ry + 11, UIFont.Medium, c.danger, a)
        ry = ry + 54
    end

    if self.selected ~= nil then
        self:drawDetails(d, self.selected, rx, ry, rw, self.height - ry - pad)
        self:layoutTreatButtons(d, self.selected, rx, ry, rw, self.height - ry - pad)
    else
        self:drawVitals(d, rx, ry, rw, self.height - ry - pad)
        if self.bandageBtn then self.bandageBtn:setVisible(false) end
        if self.disinfectBtn then self.disinfectBtn:setVisible(false) end
    end
end

-- closes the clip opened in prerender, children render in between
function AegisPlayerPageHealth:render()
    self:clearStencilRect()
end

AegisPlayerWindow.registerPage({
    id = "health",
    icon = "heal",
    label = "UI_AegisPlayer_NavHealth",
    create = AegisPlayerPageHealth.create,
})
