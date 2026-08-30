-- Player values: the Aegis window that replaces the vanilla ISPlayerStatsUI.
-- Everything on screen comes from the statsData reply of Aegis_Stats.lua and
-- nothing from the local IsoPlayer: the admin copy of a foreign player is the
-- snapshot from the connect packet and never gets refreshed, so skills, traits
-- and survived time read from it would be plain wrong.
-- The two pushes the engine cannot do itself are answered here for EVERY
-- client, admin or not: statsBoostApply writes the perk boost map (it lives in
-- SurvivorDesc and travels in no packet) and statsIdentityApply writes names
-- and profession (they ride only in ChangePlayerStats, which a server cannot
-- send). Both handlers sit at file scope on purpose.
require "ISUI/ISPanel"
require "ISUI/ISScrollingListBox"
require "ISUI/ISTextEntryBox"
require "Aegis/AegisTheme"
require "Aegis/AegisWidgets"
require "Aegis/AegisWindow"

AegisPlayerStats = ISPanel:derive("AegisPlayerStats")
AegisPlayerStats.instance = nil

local DEF_W, DEF_H = 960, 640
local MIN_W, MIN_H = 760, 540
local EDGE = 12
local HEADER = 56
local PAD = 12
local LEFT_W = 372
local ROW_H = 26
local CHIP_H = 24
local SKILL_ROW = 22
local FOOT_H = 76
-- right margins: the scrollbar is 17 px wide and sits at width - 16, so
-- anything right aligned has to end before it. The picker rows are narrower
-- than the skill list, hence the smaller value
local PICK_RIGHT = 26
local SKILL_RIGHT = 30
-- identity buttons size themselves: a fixed width either cut the label in
-- the wordier languages (russian "automatic" alone needs 82 px) or ate the
-- value column next to it. AegisButton spends 12 px on padding
local BTN_MIN = 54
local BTN_MAX = 120
local BTN_H = 20

local function btnWidth(label)
    local w = Aegis.strW(UIFont.Small, label or "")
    return math.max(BTN_MIN, math.min(BTN_MAX, w + 16))
end
-- caption column of the identity rows, sized for the longest caption
-- (Spanish "Nombre de usuario" at 114 px), not for the German ones
local IDENT_LABEL_W = 118
-- identity block: caption plus nine rows plus a little air
local IDENT_ROWS = 9
local IDENT_H = 26 + IDENT_ROWS * ROW_H + 8

-- server budget is 2 reads and 8 writes per second and admin, anything over
-- that gets no answer at all. Stay well below both
local POLL_MS = 2000
local READ_GAP = 800
local WRITE_GAP = 150
local ANSWER_TIMEOUT = 6000

local NAME_MAX = 32
local WEIGHT_MIN = 35
local WEIGHT_MAX = 130
local LEVEL_MAX = 10
local BOOST_MAX = 3

local FAIL_KEY = {
    value = "UI_Aegis_StatFailValue",
    same = "UI_Aegis_StatFailSame",
    engine = "UI_Aegis_StatFailEngine",
    asleep = "UI_Aegis_StatFailAsleep",
    dead = "UI_Aegis_StatFailDead",
}

-- ------------------------------------------------------------------
-- engine lookups: the dedicated server sends ids only, every label,
-- texture and cost is resolved here
-- ------------------------------------------------------------------

local perkMap = nil

local function perks()
    if perkMap then return perkMap end
    local map = {}
    local count = 0
    for i = 0, PerkFactory.PerkList:size() - 1 do
        local perk = PerkFactory.PerkList:get(i)
        local id = perk and perk:getId()
        if id then
            map[id] = perk
            count = count + 1
        end
    end
    -- an empty list means the scripts are not parsed yet, do not pin that
    if count > 0 then perkMap = map end
    return map
end

local perkText = {}

-- vanilla wording: skill name plus its category in brackets
local function perkLabel(id)
    local cached = perkText[id]
    if cached then return cached end
    local label = id
    local perk = perks()[id]
    if perk then
        pcall(function()
            local parent = perk:getParent()
            if parent then
                label = perk:getName() .. " (" .. PerkFactory.getPerkName(parent) .. ")"
            else
                label = perk:getName()
            end
        end)
    end
    perkText[id] = label
    return label
end

local function parentLabel(id)
    local perk = perks()[id]
    if not perk then return id end
    local label = id
    pcall(function() label = PerkFactory.getPerkName(perk) end)
    return label
end

local traitCache = {}

-- nil is a valid answer: a trait whose definition left with a mod is still on
-- the character and must stay removable
local function traitDef(id)
    local rec = traitCache[id]
    if rec ~= nil then return rec or nil end
    rec = false
    pcall(function()
        local t = CharacterTrait.get(ResourceLocation.of(id))
        if not t then return end
        local def = CharacterTraitDefinition.getCharacterTraitDefinition(t)
        if not def then return end
        rec = {
            id = id,
            label = def:getLabel() or id,
            desc = def:getDescription() or "",
            cost = def:getCost() or 0,
            tex = def:getTexture(),
            mpOff = def:isDisabledInMultiplayer() == true,
            def = def,
        }
    end)
    traitCache[id] = rec
    return rec or nil
end

local function traitLabel(id)
    local rec = traitDef(id)
    return rec and rec.label or id
end

local profCache = {}

local function profDef(id)
    local rec = profCache[id]
    if rec ~= nil then return rec or nil end
    rec = false
    pcall(function()
        local p = CharacterProfession.get(ResourceLocation.of(id))
        if not p then return end
        local def = CharacterProfessionDefinition.getCharacterProfessionDefinition(p)
        if not def then return end
        rec = { id = id, label = def:getUIName() or id, desc = def:getDescription() or "", tex = def:getTexture() }
    end)
    profCache[id] = rec
    return rec or nil
end

local function profLabel(id)
    if not id or id == "" then return getText("UI_Aegis_StatNone") end
    local rec = profDef(id)
    return rec and rec.label or id
end

-- network tables can arrive with a missing field, drawText on nil throws
local function str(value, fallback)
    if type(value) == "string" and value ~= "" then return value end
    return fallback or ""
end

-- the vanilla percentage readout (50/75/100/125) does not match AddXP at all,
-- these are the factors the engine really applies
local function boostFactor(perkId, boost)
    boost = tonumber(boost) or 0
    local noDrop = perkId == "Sprinting" or perkId == "Fitness" or perkId == "Strength"
    local noHigh = perkId == "Fitness" or perkId == "Strength"
    if boost <= 0 then
        if noDrop then return 1.0 end
        return 0.25
    end
    if boost == 1 then
        if perkId == "Sprinting" then return 1.25 end
        return 1.0
    end
    if noHigh then return 1.0 end
    if boost == 2 then return 1.33 end
    return 1.66
end

local function factorText(perkId, boost)
    return string.format("%.2f", boostFactor(perkId, boost)) .. "x"
end

-- vanilla decomposition of the survived hours
local function survivedText(hours)
    hours = tonumber(hours) or 0
    local whole = math.floor(hours)
    local days = math.floor(whole / 24)
    local restHours = whole % 24
    local months = math.floor(days / 30)
    local restDays = days % 30
    local years = math.floor(months / 12)
    local restMonths = months % 12
    local parts = {}
    if years > 0 then parts[#parts + 1] = getText("UI_Aegis_StatYears", tostring(years)) end
    if restMonths > 0 then parts[#parts + 1] = getText("UI_Aegis_StatMonths", tostring(restMonths)) end
    if restDays > 0 then parts[#parts + 1] = getText("UI_Aegis_StatDays", tostring(restDays)) end
    if restHours > 0 then parts[#parts + 1] = getText("UI_Aegis_StatHours", tostring(restHours)) end
    if #parts == 0 then
        return getText("UI_Aegis_StatMinutes", tostring(math.floor(hours * 60)))
    end
    return table.concat(parts, " ")
end

-- ------------------------------------------------------------------
-- picker card: floating list next to the window, used for traits and
-- professions. Dies with its owner
-- ------------------------------------------------------------------

AegisStatsPicker = ISPanel:derive("AegisStatsPicker")
AegisStatsPicker.instance = nil

local PICK_W = 330
local PICK_ROW = 26

function AegisStatsPicker.show(owner, title, entries, onPick)
    if AegisStatsPicker.instance then AegisStatsPicker.instance:close() end
    local sw, sh = getCore():getScreenWidth(), getCore():getScreenHeight()
    local wanted = 58 + #entries * PICK_ROW + 12
    local h = math.max(200, math.min(wanted, sh - 60))
    local x = owner:getX() + owner:getWidth() + 10
    if x + PICK_W > sw - 8 then x = math.max(8, owner:getX() - PICK_W - 10) end
    local y = math.max(8, math.min(owner:getY() + 30, sh - h - 8))
    local o = ISPanel:new(x, y, PICK_W, h)
    setmetatable(o, AegisStatsPicker)
    AegisStatsPicker.__index = AegisStatsPicker
    o.background = false
    o.owner = owner
    o.title = title
    o.entries = entries
    o.onPick = onPick
    o:initialise()
    o:addToUIManager()
    o:setAlwaysOnTop(true)
    AegisStatsPicker.instance = o
    return o
end

function AegisStatsPicker:createChildren()
    self.closeBtn = AegisButton:new(self.width - 36, 11, 26, 26, nil, "close", self, AegisStatsPicker.close)
    self.closeBtn.radius = 13
    self:addChild(self.closeBtn)

    self.list = ISScrollingListBox:new(6, 46, self.width - 12, self.height - 52)
    self.list:initialise()
    self.list:instantiate()
    self.list.itemheight = PICK_ROW
    self.list.drawBorder = false
    self.list.backgroundColor = { r = 0, g = 0, b = 0, a = 0 }
    self.list.doDrawItem = AegisStatsPicker.drawRow
    self.list:setOnMouseDownFunction(self, AegisStatsPicker.onPickRow)
    self:addChild(self.list)

    for _, entry in ipairs(self.entries) do
        self.list:addItem(entry.label or entry.id or "", entry)
    end
    self.list.selected = -1
end

function AegisStatsPicker:close()
    -- the tooltip is its own element in the manager, it would stay on
    -- screen after the card is gone
    Aegis.updateTooltipAt(self, nil, 0, 0)
    self:removeFromUIManager()
    if AegisStatsPicker.instance == self then AegisStatsPicker.instance = nil end
end

function AegisStatsPicker.onPickRow(self, entry)
    if type(entry) ~= "table" or entry.header then
        self.list.selected = -1
        return
    end
    local pick = self.onPick
    self:close()
    if pick then pick(entry.id) end
end

function AegisStatsPicker.drawRow(list, y, item, alt)
    local c = Aegis.col
    local entry = item.item
    local w = list:getWidth()
    local ty = y + math.floor((PICK_ROW - Aegis.fontH(UIFont.Small)) / 2)
    if entry.header then
        Aegis.text(list, entry.label, 8, ty, UIFont.Small, c.goldDim)
        Aegis.hairline(list, 8, y + PICK_ROW - 2, w - 8 - PICK_RIGHT, 0.6)
        return y + PICK_ROW
    end
    if list.selected == item.index then
        Aegis.roundRect(list, 2, y + 1, w - 4, PICK_ROW - 2, 6, 0.5, c.card)
    end
    local tx = 8
    if entry.tex then
        pcall(function()
            list:drawTextureScaledAspect2(entry.tex, 6, y + 3, 20, 20, 1, 1, 1, 1)
        end)
        tx = 32
    end
    -- the note never gets more than half the row, and the label keeps the
    -- rest: a long note used to be drawn over the label instead of yielding
    local noteText, noteW = nil, 0
    if entry.note then
        noteText = Aegis.fitText(entry.note, UIFont.Small, math.max(40, math.floor(w * 0.5)))
        noteW = Aegis.strW(UIFont.Small, noteText) + PICK_RIGHT + 4
    end
    local labelColor = entry.warn and c.danger or c.text
    local label = Aegis.fitText(entry.label, UIFont.Small, math.max(24, w - tx - noteW - PICK_RIGHT))
    Aegis.text(list, label, tx, ty, UIFont.Small, labelColor)
    if noteText then
        local noteColor = c.muted
        if entry.warn then noteColor = c.danger end
        Aegis.textRight(list, noteText, w - PICK_RIGHT, ty, UIFont.Small, noteColor)
    end
    return y + PICK_ROW
end

function AegisStatsPicker:prerender()
    local c = Aegis.col
    Aegis.shadow(self, 0, 0, self.width, self.height, 22, 0.6)
    Aegis.roundFrame(self, 0, 0, self.width, self.height, 12, 1, c.line, c.bg)
    Aegis.text(self, Aegis.fitText(self.title, UIFont.Medium, self.width - 54), 14, 13, UIFont.Medium, c.goldHi)
    Aegis.hairline(self, 1, 44, self.width - 2)
    -- what the entry under the cursor actually does. The vanilla list
    -- tracks the hovered row itself in mouseoverselected, a row is drawn
    -- and not an element, so the tooltip is driven from here
    local tip = nil
    local list = self.list
    if list and list:isMouseOver() and not list:isMouseOverScrollBar() then
        local item = list.items and list.items[list.mouseoverselected]
        local entry = item and item.item
        if type(entry) == "table" and not entry.header then tip = entry.tip end
    end
    Aegis.updateTooltipAt(self, tip, getMouseX() + 18, getMouseY() + 12)
end

function AegisStatsPicker:onMouseMoveOutside(dx, dy)
    Aegis.updateTooltipAt(self, nil, 0, 0)
end

-- the card belongs to one window, an orphan would keep answering clicks.
-- Tearing it down happens here and not in prerender, removing an element
-- from the manager mid draw is asking for trouble
function AegisStatsPicker:update()
    if AegisPlayerStats.instance ~= self.owner then self:close() end
end

function AegisStatsPicker:onMouseDown(x, y)
    self:bringToTop()
end

-- ------------------------------------------------------------------
-- the window
-- ------------------------------------------------------------------

function AegisPlayerStats.open(username, onlineId, displayName)
    local p = getPlayer()
    if not p or not Aegis.allowed(p) or not Aegis.canSee("players") then return end
    username = tostring(username or "")
    local open = AegisPlayerStats.instance
    if open then
        if open.username == username then
            open:bringToTop()
            open:request(true)
            return open
        end
        open:close()
    end
    local sw, sh = getCore():getScreenWidth(), getCore():getScreenHeight()
    local minW = math.min(MIN_W, sw - 40)
    local minH = math.min(MIN_H, sh - 40)
    local w = math.max(minW, math.min(tonumber(Aegis.getPref("statW")) or DEF_W, sw - EDGE * 2))
    local h = math.max(minH, math.min(tonumber(Aegis.getPref("statH")) or DEF_H, sh - EDGE * 2))
    local o = ISPanel:new(math.floor((sw - w) / 2), math.floor((sh - h) / 2), w, h)
    setmetatable(o, AegisPlayerStats)
    AegisPlayerStats.__index = AegisPlayerStats
    o.background = false
    o.username = username
    o.onlineId = tonumber(onlineId) or -1
    o.displayName = tostring(displayName or username)
    o.data = nil
    o.queue = {}
    o.chipRows = {}
    o.skillRows = {}
    o.selPerk = nil
    o.minimumWidth = minW
    o.minimumHeight = minH
    o:initialise()
    o:addToUIManager()
    o:setAlwaysOnTop(true)
    AegisPlayerStats.instance = o
    o:request(true)
    return o
end

function AegisPlayerStats:close()
    if AegisStatsPicker.instance and AegisStatsPicker.instance.owner == self then
        AegisStatsPicker.instance:close()
    end
    self:removeFromUIManager()
    if AegisPlayerStats.instance == self then AegisPlayerStats.instance = nil end
end

-- ------------------------------------------------------------------
-- geometry: children do not anchor in ISPanel, every position is set by
-- hand here and again after each resize
-- ------------------------------------------------------------------

function AegisPlayerStats:layout()
    self.topY = HEADER + PAD
    self.bodyH = self.height - HEADER - PAD * 2
    self.traitY = self.topY + IDENT_H + PAD
    self.traitH = self.bodyH - IDENT_H - PAD
    self.rightX = PAD + LEFT_W + PAD
    self.rightW = self.width - self.rightX - PAD
end

local function rowY(self, index)
    return self.topY + 26 + (index - 1) * ROW_H
end

function AegisPlayerStats:createChildren()
    self:layout()
    local right = PAD + LEFT_W - 12

    self.closeBtn = AegisButton:new(self.width - 40, 13, 30, 30, nil, "close", self, AegisPlayerStats.close)
    self.closeBtn.radius = 15
    self:addChild(self.closeBtn)

    self.refreshBtn = AegisButton:new(self.width - 78, 13, 30, 30, nil, "refresh", self, function(win)
        win:request(true)
    end)
    self.refreshBtn.radius = 15
    self.refreshBtn.tooltip = getText("UI_Aegis_StatRefresh")
    self:addChild(self.refreshBtn)

    self.invBtn = AegisButton:new(self.width - 116, 13, 30, 30, nil, "items", self, AegisPlayerStats.onInventory)
    self.invBtn.radius = 15
    self.invBtn.tooltip = getText("UI_Aegis_StatOpenInventory")
    self:addChild(self.invBtn)

    -- needs open in their own card next to the window on purpose. The body
    -- here is calibrated by hand down to the pixel, and squeezing a block
    -- of twelve sliders between the existing sections is exactly how the
    -- happened
    self.needsBtn = AegisButton:new(self.width - 154, 13, 30, 30, nil, "check", self, AegisPlayerStats.onNeeds)
    self.needsBtn.radius = 15
    self.needsBtn.tooltip = getText("UI_Aegis_StatNeeds")
    self:addChild(self.needsBtn)

    -- identity buttons sit at fixed rows and are only as wide as their own
    -- label needs. A fixed width would either cut the label in the wordier
    -- languages or eat the value column, which is what the display name row
    -- with its two buttons ran into
    local function identBtn(row, label, fn, rightOf)
        local w = btnWidth(label)
        local x = right - w - (rightOf or 0)
        local b = AegisButton:new(x, rowY(self, row) + 3, w, BTN_H, label, nil, self, fn)
        self:addChild(b)
        return b
    end

    local changeLabel = getText("UI_Aegis_StatChange")
    self.changeW = btnWidth(changeLabel)
    self.dispBtn = identBtn(2, changeLabel, AegisPlayerStats.onDisplayName)
    self.dispAutoBtn = identBtn(2, getText("UI_Aegis_StatAuto"),
        AegisPlayerStats.onDisplayAuto, self.changeW + 4)
    self.autoW = self.dispAutoBtn.width

    self.foreBtn = identBtn(3, changeLabel, AegisPlayerStats.onForename)
    self.surBtn = identBtn(4, changeLabel, AegisPlayerStats.onSurname)
    self.profBtn = identBtn(5, changeLabel, AegisPlayerStats.onProfession)
    self.weightBtn = identBtn(6, changeLabel, AegisPlayerStats.onWeight)

    self.roleBtn = identBtn(9, getText("UI_Aegis_StatOpen"), AegisPlayerStats.onRoles)
    self.roleBtn.tooltip = getText("UI_Aegis_StatOpenRoles")

    -- traits: chips are drawn by hand inside the scroll host, one widget per
    -- trait would rebuild the child list on every server reply
    self.traitScroll = AegisScrollArea:new(PAD + 1, self.traitY + 30, LEFT_W - 2, self.traitH - 72)
    self:addChild(self.traitScroll)
    -- 17 is the vanilla scrollbar width (ISScrollBar.lua:276); 14 left the
    -- last three pixels of a chip row running under the bar
    self.traitPanel = ISPanel:new(0, 0, self.traitScroll.width - 17, 10)
    self.traitPanel.background = false
    self.traitPanel.owner = self
    self.traitPanel.render = AegisPlayerStats.renderChips
    self.traitPanel.onMouseDown = AegisPlayerStats.onChipDown
    self.traitScroll:addChild(self.traitPanel)

    self.addTraitBtn = AegisButton:new(PAD + 12, self.traitY + self.traitH - 36, LEFT_W - 24, 26,
        getText("UI_Aegis_StatAddTrait"), "plus", self, AegisPlayerStats.onAddTrait)
    self:addChild(self.addTraitBtn)

    -- skills
    self.skillList = ISScrollingListBox:new(self.rightX + 1, self.topY + 50, self.rightW - 2, self.bodyH - 50 - FOOT_H)
    self.skillList:initialise()
    self.skillList:instantiate()
    self.skillList.itemheight = SKILL_ROW
    self.skillList.drawBorder = false
    self.skillList.backgroundColor = { r = 0, g = 0, b = 0, a = 0 }
    self.skillList.doDrawItem = AegisPlayerStats.drawSkillRow
    self.skillList:setOnMouseDownFunction(self, AegisPlayerStats.onSelectSkill)
    self:addChild(self.skillList)

    self.xpBtn = AegisButton:new(0, 0, 10, 28, getText("UI_Aegis_StatGiveXP"), nil, self, AegisPlayerStats.onGiveXp)
    self:addChild(self.xpBtn)
    self.upBtn = AegisButton:new(0, 0, 10, 28, getText("UI_Aegis_StatLevelUp"), nil, self, function(win)
        win:sendXp({ mode = "up" })
    end)
    self:addChild(self.upBtn)
    self.downBtn = AegisButton:new(0, 0, 10, 28, getText("UI_Aegis_StatLevelDown"), nil, self, function(win)
        win:sendXp({ mode = "down" })
    end)
    self:addChild(self.downBtn)
    self.setBtn = AegisButton:new(0, 0, 10, 28, getText("UI_Aegis_StatSetLevel"), nil, self, AegisPlayerStats.onSetLevel)
    self:addChild(self.setBtn)

    self.boostBtns = {}
    for value = 0, BOOST_MAX do
        local btn = AegisButton:new(0, 0, 40, 26, tostring(value), nil, self, function(win, b)
            win:sendXp({ mode = "boost", boost = b.value })
        end)
        btn.value = value
        btn.radius = 13
        self:addChild(btn)
        self.boostBtns[value + 1] = btn
    end

    self.grip = AegisResizeGrip:new(self.width - 22, self.height - 22, 22, 22, self)
    self.grip.anchorRight = false
    self.grip.anchorBottom = false
    self.grip.resizeFunction = AegisPlayerStats.applyResize
    self.grip:initialise()
    self:addChild(self.grip)

    self:placeChrome()
end

function AegisPlayerStats:placeChrome()
    self:layout()
    self.closeBtn:setX(self.width - 40)
    self.refreshBtn:setX(self.width - 78)
    self.invBtn:setX(self.width - 116)

    self.traitScroll:setY(self.traitY + 30)
    self.traitScroll:setHeight(math.max(20, self.traitH - 72))
    -- setWidth alone leaves the scrollbar on its old x, it re-anchors in lua
    if self.traitScroll.vscroll then
        self.traitScroll.vscroll:setX(self.traitScroll.width - 16)
        self.traitScroll.vscroll:setHeight(self.traitScroll.height)
    end
    self.addTraitBtn:setY(self.traitY + self.traitH - 36)

    self.skillList:setX(self.rightX + 1)
    self.skillList:setY(self.topY + 50)
    self.skillList:setWidth(math.max(80, self.rightW - 2))
    self.skillList:setHeight(math.max(40, self.bodyH - 50 - FOOT_H))
    if self.skillList.vscroll then
        -- the bar is 17 px wide and paints from x+3 to x+15, so 16 keeps it
        -- inside the card border (same value the rest of the panel uses)
        self.skillList.vscroll:setX(self.skillList.width - 16)
        self.skillList.vscroll:setHeight(self.skillList.height)
    end

    local innerW = self.rightW - 24
    local bw = math.floor((innerW - 18) / 4)
    local by = self.topY + self.bodyH - FOOT_H + 6
    local bx = self.rightX + 12
    for i, btn in ipairs({ self.xpBtn, self.upBtn, self.downBtn, self.setBtn }) do
        btn:setX(bx + (i - 1) * (bw + 6))
        btn:setY(by)
        btn:setWidth(math.max(40, bw))
    end

    local chipY = by + 34
    local chipX = self.rightX + self.rightW - 12 - (4 * 40 + 3 * 6)
    for i, btn in ipairs(self.boostBtns) do
        btn:setX(chipX + (i - 1) * 46)
        btn:setY(chipY)
    end

    if self.grip then
        self.grip:setX(self.width - self.grip.width)
        self.grip:setY(self.height - self.grip.height)
    end
    self:layoutChips()
end

function AegisPlayerStats:applyResize(w, h)
    local sw, sh = getCore():getScreenWidth(), getCore():getScreenHeight()
    w = math.min(w, sw - EDGE - self.x)
    h = math.min(h, sh - EDGE - self.y)
    w = math.max(w, self.minimumWidth)
    h = math.max(h, self.minimumHeight)
    if w == self.width and h == self.height then return end
    self:setWidth(w)
    self:setHeight(h)
    self:placeChrome()
end

function AegisPlayerStats:onResizeDone()
    if self.width == self.resizeStartW and self.height == self.resizeStartH then return end
    Aegis.setPref("statW", math.floor(self.width))
    Aegis.setPref("statH", math.floor(self.height))
end

-- ------------------------------------------------------------------
-- traffic
-- ------------------------------------------------------------------

function AegisPlayerStats:args(extra)
    local args = { username = self.username }
    if type(self.onlineId) == "number" and self.onlineId >= 0 then args.id = self.onlineId end
    if type(extra) == "table" then
        for k, v in pairs(extra) do args[k] = v end
    end
    return args
end

-- one read at a time, the poll and the refresh button share the same gate so
-- the server side budget of two per second can never be hit
function AegisPlayerStats:request(force)
    local now = getTimestampMs()
    if force then
        if now < (self.lastRead or 0) + READ_GAP then return end
    elseif now < (self.nextRead or 0) then
        return
    end
    self.lastRead = now
    self.nextRead = now + POLL_MS
    if not self.data then self.waitingSince = self.waitingSince or now end
    sendClientCommand(getPlayer(), AegisShared.MODULE, "statsRead", self:args())
end

-- writes go through a queue with a fixed gap: a fast admin clicking level up
-- eight times in a row would otherwise burn the whole write budget and the
-- extra clicks would be answered with silence
function AegisPlayerStats:write(command, extra)
    -- a prompt or a picker outlives the window it was opened from, a late
    -- confirm must not fire at a target the admin already left
    if AegisPlayerStats.instance ~= self then return end
    table.insert(self.queue, { cmd = command, args = self:args(extra) })
end

function AegisPlayerStats:sendXp(extra)
    if not self.selPerk then
        Aegis.showToast(getText("UI_Aegis_StatPickSkill"))
        return
    end
    extra.perk = self.selPerk
    self:write("statsXp", extra)
end

function AegisPlayerStats:update()
    local now = getTimestampMs()
    if #self.queue > 0 and now >= (self.nextWrite or 0) then
        self.nextWrite = now + WRITE_GAP
        local job = table.remove(self.queue, 1)
        sendClientCommand(getPlayer(), AegisShared.MODULE, job.cmd, job.args)
    end
    self:request(false)
    -- never sit in a blocking load state: an over budget request gets no
    -- answer at all, so the window has to time out on its own
    if not self.data and self.waitingSince and now > self.waitingSince + ANSWER_TIMEOUT then
        self.noAnswer = true
    end
end

function AegisPlayerStats:receive(args)
    if type(args) ~= "table" then return end
    local name = type(args.username) == "string" and args.username or ""
    -- a reply for another target belongs to an older window, drop it
    if name ~= "" and self.username ~= "" and name ~= self.username then return end
    self.noAnswer = false
    self.waitingSince = nil
    if args.gone then
        self:close()
        Aegis.showToast(getText("UI_Aegis_StatGone"))
        return
    end
    if type(args.id) == "number" and args.id >= 0 then self.onlineId = args.id end
    self.data = args
    -- a quiet answer belongs to a slider still under the hand: keep the data
    -- (the needs card reads it straight from here) but no toast and no
    -- rebuild. The release sends once more without the flag, and the poll
    -- rebuilds within two seconds anyway
    if args.quiet and args.ok then return end
    self:report(args)
    self:rebuild()
end

function AegisPlayerStats:report(args)
    if args.action == "read" then return end
    if not args.ok then
        Aegis.showToast(getText(FAIL_KEY[args.reason or ""] or "UI_Aegis_StatFailEngine"))
        return
    end
    if args.note == "weight" then
        Aegis.showToast(getText("UI_Aegis_StatNoteWeight", tostring(args.noteValue)))
    elseif args.note == "noeffect" then
        Aegis.showToast(getText("UI_Aegis_StatNoteNoEffect"))
    elseif args.note == "forced" then
        Aegis.showToast(getText("UI_Aegis_StatNoteForced"))
    else
        Aegis.showToast(getText("UI_Aegis_StatDone"))
    end
end

-- ------------------------------------------------------------------
-- filling from the reply, never from the local player object
-- ------------------------------------------------------------------

function AegisPlayerStats:rebuild()
    local d = self.data or {}
    self.traitIds = {}
    for _, id in pairs(d.traits or {}) do
        if type(id) == "string" and id ~= "" then table.insert(self.traitIds, id) end
    end
    table.sort(self.traitIds, function(a, b) return traitLabel(a) < traitLabel(b) end)
    self:layoutChips()

    local rows = {}
    for _, row in pairs(d.perks or {}) do
        if type(row) == "table" and type(row.id) == "string" then
            rows[#rows + 1] = {
                id = row.id,
                label = perkLabel(row.id),
                group = parentLabel(row.parent or ""),
                level = tonumber(row.level) or 0,
                xp = tonumber(row.xp) or 0,
                need = tonumber(row.need) or -1,
                boost = tonumber(row.boost) or 0,
                mult = tonumber(row.mult) or 0,
            }
        end
    end
    table.sort(rows, function(a, b)
        if a.group ~= b.group then return a.group < b.group end
        return a.label < b.label
    end)
    self.skillRows = rows

    local keep = self.selPerk
    self.skillList:clear()
    -- clear puts the selection back on row one, no selection needs -1
    self.skillList.selected = -1
    self.selPerk = nil
    for i, row in ipairs(rows) do
        self.skillList:addItem(row.label, row)
        if keep and row.id == keep then
            self.skillList.selected = i
            self.selPerk = keep
        end
    end
end

function AegisPlayerStats:selectedRow()
    if not self.selPerk then return nil end
    for _, row in ipairs(self.skillRows or {}) do
        if row.id == self.selPerk then return row end
    end
    return nil
end

function AegisPlayerStats.onSelectSkill(self, row)
    if type(row) == "table" and type(row.id) == "string" then
        self.selPerk = row.id
    end
end

function AegisPlayerStats:layoutChips()
    if not self.traitPanel or not self.traitScroll then return end
    -- keep the chips clear of the scrollbar, it paints 17 px wide inside the
    -- host and the removal crosses sit at the right edge of every chip
    self.traitPanel:setWidth(math.max(60, self.traitScroll.width - 22))
    local left = 8
    local right = self.traitPanel.width - 10
    local room = right - left
    local rows = {}
    local x, y = left, 6
    for _, id in ipairs(self.traitIds or {}) do
        local rec = traitDef(id)
        local label = Aegis.fitText(rec and rec.label or id, UIFont.Small, math.max(24, room - 40))
        local w = math.min(room, Aegis.strW(UIFont.Small, label) + 40)
        if x > left and x + w > right then
            x = left
            y = y + CHIP_H + 6
        end
        rows[#rows + 1] = {
            id = id, label = label, x = x, y = y, w = w,
            cost = rec and rec.cost or 0,
        }
        x = x + w + 6
    end
    self.chipRows = rows
    local h = (#rows > 0) and (y + CHIP_H + 10) or 10
    self.traitPanel:setHeight(h)
    self.traitScroll:setScrollHeight(h)
end

function AegisPlayerStats.renderChips(panel)
    local win = panel.owner
    local c = Aegis.col
    if #(win.chipRows or {}) == 0 then
        Aegis.text(panel, getText("UI_Aegis_StatNoTraits"), 8, 6, UIFont.Small, c.muted)
        return
    end
    local mx, my = panel:getMouseX(), panel:getMouseY()
    local over = panel:isMouseOver()
    for _, chip in ipairs(win.chipRows) do
        local hot = over and mx >= chip.x + chip.w - 22 and mx <= chip.x + chip.w
            and my >= chip.y and my <= chip.y + CHIP_H
        Aegis.roundFrame(panel, chip.x, chip.y, chip.w, CHIP_H, 12, 1, c.line, c.card)
        local textC = chip.cost < 0 and c.muted or c.goldHi
        Aegis.text(panel, chip.label, chip.x + 12, chip.y + math.floor((CHIP_H - Aegis.fontH(UIFont.Small)) / 2),
            UIFont.Small, textC)
        Aegis.icon(panel, "close", chip.x + chip.w - 19, chip.y + 7, 10, hot and 1 or 0.5,
            hot and c.danger or c.muted)
    end
end

function AegisPlayerStats.onChipDown(panel, x, y)
    local win = panel.owner
    for _, chip in ipairs(win.chipRows or {}) do
        if x >= chip.x + chip.w - 22 and x <= chip.x + chip.w and y >= chip.y and y <= chip.y + CHIP_H then
            Aegis.sound()
            win:write("statsTrait", { trait = chip.id, add = false })
            return
        end
    end
end

-- ------------------------------------------------------------------
-- actions
-- ------------------------------------------------------------------

local function nameOf(self)
    local d = self.data
    if d and type(d.displayName) == "string" and d.displayName ~= "" then return d.displayName end
    return self.displayName or self.username
end

local function namePrompt(self, title, message, current, kind)
    local prompt = AegisPrompt.show({
        title = title,
        message = message,
        confirmLabel = getText("UI_Aegis_Apply"),
        target = self,
        onConfirm = function(win, text)
            win:write("statsName", { kind = kind, value = text })
        end,
    })
    prompt.entry:setMaxTextLength(NAME_MAX)
    prompt.entry:setText(current or "")
end

function AegisPlayerStats:onForename()
    namePrompt(self, getText("UI_Aegis_StatForename"),
        getText("UI_Aegis_StatNamePrompt", nameOf(self)),
        self.data and self.data.forename or "", "fore")
end

function AegisPlayerStats:onSurname()
    namePrompt(self, getText("UI_Aegis_StatSurname"),
        getText("UI_Aegis_StatNamePrompt", nameOf(self)),
        self.data and self.data.surname or "", "sur")
end

function AegisPlayerStats:onDisplayName()
    namePrompt(self, getText("UI_Aegis_StatDisplayName"),
        getText("UI_Aegis_StatDisplayPrompt", nameOf(self)),
        self.data and self.data.displayName or "", "disp")
end

-- empty display name means back to automatic on the server
function AegisPlayerStats:onDisplayAuto()
    self:write("statsName", { kind = "disp", value = "" })
end

function AegisPlayerStats:onWeight()
    local current = self.data and self.data.weight or 80
    local prompt = AegisPrompt.show({
        title = getText("UI_Aegis_StatWeight"),
        message = getText("UI_Aegis_StatWeightPrompt", nameOf(self)),
        confirmLabel = getText("UI_Aegis_Apply"),
        target = self,
        onConfirm = function(win, text)
            local value = tonumber(text)
            if not value then
                Aegis.showToast(getText("UI_Aegis_StatFailValue"))
                return
            end
            value = math.max(WEIGHT_MIN, math.min(WEIGHT_MAX, value))
            win:write("statsWeight", { weight = value })
        end,
    })
    prompt.entry:setOnlyNumbers(true)
    prompt.entry:setText(tostring(math.floor(current + 0.5)))
end

function AegisPlayerStats:onProfession()
    local held = self.data and self.data.profession or ""
    local jobless = tostring(CharacterProfession.UNEMPLOYED)
    local entries = {}
    pcall(function()
        local defs = CharacterProfessionDefinition.getProfessions()
        for i = 0, defs:size() - 1 do
            local def = defs:get(i)
            local t = def and def:getType()
            if t then
                local id = tostring(t)
                entries[#entries + 1] = {
                    id = id,
                    label = def:getUIName() or id,
                    tex = def:getTexture(),
                    -- unemployed goes on top, same as the character creation
                    first = (id == jobless),
                    note = (id == held) and getText("UI_Aegis_StatCurrent") or nil,
                }
            end
        end
    end)
    table.sort(entries, function(a, b)
        if a.first ~= b.first then return a.first == true end
        return a.label < b.label
    end)
    if #entries == 0 then
        Aegis.showToast(getText("UI_Aegis_StatNothingLeft"))
        return
    end
    local win = self
    AegisStatsPicker.show(self, getText("UI_Aegis_StatPickProfession"), entries, function(id)
        if AegisPlayerStats.instance ~= win then return end
        win:write("statsProfession", { profession = id })
    end)
end

function AegisPlayerStats:onAddTrait()
    local held = {}
    for _, id in ipairs(self.traitIds or {}) do held[id] = true end
    local good, bad = {}, {}
    -- the engine hands out the same definition more than once and mods add
    -- traits that share a label, both showed up as duplicate rows
    local seenId, seenLabel = {}, {}
    pcall(function()
        local defs = CharacterTraitDefinition.getTraits()
        for i = 0, defs:size() - 1 do
            local def = defs:get(i)
            local t = def and def:getType()
            local id = t and tostring(t) or nil
            if id and seenId[id] then id = nil end
            if id then seenId[id] = true end
            if id and not held[id] then
                local cost = def:getCost() or 0
                local warn, note = false, nil
                if def:isDisabledInMultiplayer() == true and isClient() then
                    warn = true
                    note = getText("UI_Aegis_StatTraitMpOff")
                end
                -- a trait the character already excludes is not refused by the
                -- server, so say it here instead of letting it surprise later
                pcall(function()
                    local excl = def:getMutuallyExclusiveTraits()
                    if excl then
                        for k = 0, excl:size() - 1 do
                            local other = excl:get(k)
                            if other and held[tostring(other)] then
                                warn = true
                                note = getText("UI_Aegis_StatTraitConflict")
                            end
                        end
                    end
                end)
                local shown = def:getLabel() or id
                local entry = nil
                if not seenLabel[shown] then
                    seenLabel[shown] = true
                    -- what the trait actually does, straight from the engine
                    -- definition. The row only has space for a short note,
                    -- the full text rides along in the hover tooltip
                    local desc = nil
                    pcall(function() desc = def:getDescription() end)
                    if type(desc) ~= "string" or desc == "" then
                        desc = nil
                    else
                        desc = (string.gsub(desc, "<[^>]*>", " "))
                    end
                    local tip = shown
                    if cost ~= 0 then
                        tip = tip .. " (" .. getText("UI_Aegis_StatTraitCost", tostring(cost)) .. ")"
                    end
                    if desc then tip = tip .. " <LINE> " .. desc end
                    if note then tip = tip .. " <LINE> " .. note end
                    entry = {
                        id = id, label = shown, tex = def:getTexture(),
                        cost = cost, warn = warn, tip = tip,
                        note = note or (cost ~= 0 and tostring(cost) or nil),
                    }
                end
                if entry == nil then
                    -- label already listed, skip this definition
                elseif cost >= 0 then
                    good[#good + 1] = entry
                else
                    bad[#bad + 1] = entry
                end
            end
        end
    end)
    local byLabel = function(a, b) return a.label < b.label end
    table.sort(good, byLabel)
    table.sort(bad, byLabel)
    local entries = {}
    if #good > 0 then
        entries[#entries + 1] = { header = true, label = getText("UI_Aegis_StatTraitGood") }
        for _, e in ipairs(good) do entries[#entries + 1] = e end
    end
    if #bad > 0 then
        entries[#entries + 1] = { header = true, label = getText("UI_Aegis_StatTraitBad") }
        for _, e in ipairs(bad) do entries[#entries + 1] = e end
    end
    if #entries == 0 then
        Aegis.showToast(getText("UI_Aegis_StatNothingLeft"))
        return
    end
    local win = self
    AegisStatsPicker.show(self, getText("UI_Aegis_StatPickTrait"), entries, function(id)
        if AegisPlayerStats.instance ~= win then return end
        win:write("statsTrait", { trait = id, add = true })
    end)
end

function AegisPlayerStats:onGiveXp()
    if not self.selPerk then
        Aegis.showToast(getText("UI_Aegis_StatPickSkill"))
        return
    end
    local row = self:selectedRow()
    AegisPrompt.show({
        title = getText("UI_Aegis_StatGiveXP"),
        message = getText("UI_Aegis_StatXpPrompt", row and row.label or self.selPerk),
        confirmLabel = getText("UI_Aegis_Apply"),
        chips = {
            { label = getText("UI_Aegis_StatXpExact"), value = "exact" },
            { label = getText("UI_Aegis_StatXpMult"), value = "mult" },
        },
        target = self,
        onConfirm = function(win, text, choice)
            local amount = tonumber(text)
            if not amount or amount == 0 then
                Aegis.showToast(getText("UI_Aegis_StatFailValue"))
                return
            end
            win:sendXp({ mode = "xp", amount = amount, mult = choice == "mult" })
        end,
    })
end

function AegisPlayerStats:onSetLevel()
    if not self.selPerk then
        Aegis.showToast(getText("UI_Aegis_StatPickSkill"))
        return
    end
    local row = self:selectedRow()
    local chips = {}
    for level = 0, LEVEL_MAX do
        chips[#chips + 1] = { label = tostring(level), value = level }
    end
    AegisPrompt.show({
        title = getText("UI_Aegis_StatSetLevel"),
        message = getText("UI_Aegis_StatLevelPrompt", row and row.label or self.selPerk),
        confirmLabel = getText("UI_Aegis_Apply"),
        chips = chips,
        target = self,
        onConfirm = function(win, text, choice)
            local level = tonumber(text) or choice
            if type(level) ~= "number" then
                Aegis.showToast(getText("UI_Aegis_StatFailValue"))
                return
            end
            win:sendXp({ mode = "level", level = math.max(0, math.min(LEVEL_MAX, math.floor(level))) })
        end,
    })
end

function AegisPlayerStats:onInventory()
    if AegisInventory and AegisInventory.show then
        AegisInventory.show(self.username, self.onlineId or -1, nameOf(self))
    end
end

-- the role itself belongs on the roles page, this only jumps there
function AegisPlayerStats:onRoles()
    if not Aegis.canSee("roles") then
        Aegis.showToast(getText("UI_Aegis_StatNoRolePage"))
        return
    end
    local win = AegisWindow.instance
    if not win then return end
    -- the panel can sit collapsed in its mini bar, switching a page behind
    -- that would look like nothing happened
    if AegisMiniBar and AegisMiniBar.instance then
        AegisMiniBar.instance:restore()
    else
        win:bringToTop()
    end
    win:switchPage("roles")
end

-- ------------------------------------------------------------------
-- rendering
-- ------------------------------------------------------------------

function AegisPlayerStats.drawSkillRow(list, y, item, alt)
    local c = Aegis.col
    local row = item.item
    local w = list:getWidth()
    local ty = y + math.floor((SKILL_ROW - Aegis.fontH(UIFont.Small)) / 2)
    if list.selected == item.index then
        Aegis.roundRect(list, 2, y + 1, w - 4, SKILL_ROW - 2, 6, 0.55, c.card)
    end
    local nameW = w - 224
    if row._fitW ~= nameW then
        row._fitW = nameW
        row._fit = Aegis.fitText(row.label, UIFont.Small, math.max(24, nameW))
    end
    Aegis.text(list, row._fit, 10, ty, UIFont.Small, row.level > 0 and c.text or c.muted)
    Aegis.textRight(list, tostring(row.level), w - 150, ty, UIFont.Small,
        row.level >= LEVEL_MAX and c.goldHi or c.text)
    local xp
    if row.need < 0 then
        xp = getText("UI_Aegis_StatMax")
    else
        xp = string.format("%.1f / %d", row.xp, math.floor(row.need + 0.5))
    end
    Aegis.textRight(list, xp, w - 70, ty, UIFont.Small, c.muted)
    -- clear of the scrollbar: it is 17 px wide sitting at width - 16, so it
    -- paints up to width - 1 and the boost figure used to touch it
    Aegis.textRight(list, tostring(row.boost), w - SKILL_RIGHT, ty, UIFont.Small,
        row.boost > 0 and c.goldHi or c.muted)
    return y + SKILL_ROW
end

local function identRow(self, index, label, value, valueColor)
    local c = Aegis.col
    local y = rowY(self, index)
    local right = PAD + LEFT_W - 12
    -- reserve exactly what the buttons of this row really occupy, they size
    -- themselves from their label
    local reserved = 0
    if index == 2 then
        reserved = (self.changeW or 0) + (self.autoW or 0) + 4
    elseif index == 3 or index == 4 or index == 5 or index == 6 then
        reserved = self.changeW or 0
    elseif index == 9 then
        reserved = (self.roleBtn and self.roleBtn.width) or 0
    end
    local lx = PAD + 12
    local vx = lx + IDENT_LABEL_W
    -- the caption gets truncated too, otherwise a long one runs straight
    -- into the value column and both become unreadable
    Aegis.text(self, Aegis.fitText(label, UIFont.Small, IDENT_LABEL_W - 8), lx, y + 4, UIFont.Small, c.muted)
    local vw = right - reserved - vx - 8
    Aegis.text(self, Aegis.fitText(value, UIFont.Small, math.max(24, vw)), vx, y + 4, UIFont.Small, valueColor or c.text)
end

function AegisPlayerStats:prerender()
    local c = Aegis.col
    local d = self.data
    Aegis.shadow(self, 0, 0, self.width, self.height, 26, 0.6)
    Aegis.roundFrame(self, 0, 0, self.width, self.height, 14, 1, c.line, c.bg)
    Aegis.icon(self, "players", 18, 15, 22, 1, c.gold)
    Aegis.text(self, Aegis.fitText(getText("UI_Aegis_StatTitle"), UIFont.Medium, self.width - 180),
        50, 9, UIFont.Medium, c.goldHi)
    local sub = nameOf(self)
    if d and type(d.username) == "string" and d.username ~= "" and d.username ~= sub then
        sub = sub .. "  " .. d.username
    end
    if d and d.asleep then
        sub = sub .. "  " .. getText("UI_Aegis_StatAsleep")
    end
    Aegis.text(self, Aegis.fitText(sub, UIFont.Small, self.width - 180), 50, 11 + Aegis.fontH(UIFont.Medium),
        UIFont.Small, c.muted)
    Aegis.hairline(self, 1, HEADER, self.width - 2)

    -- identity card
    Aegis.roundFrame(self, PAD, self.topY, LEFT_W, IDENT_H, 10, 1, c.line, c.panel)
    Aegis.text(self, getText("UI_Aegis_StatIdentity"), PAD + 12, self.topY + 7, UIFont.Small, c.goldDim)
    if d then
        local none = getText("UI_Aegis_StatNone")
        identRow(self, 1, getText("UI_Aegis_StatUsername"), str(d.username, self.username))
        identRow(self, 2, getText("UI_Aegis_StatDisplayName"), str(d.displayName, none))
        identRow(self, 3, getText("UI_Aegis_StatForename"), str(d.forename, none))
        identRow(self, 4, getText("UI_Aegis_StatSurname"), str(d.surname, none))
        identRow(self, 5, getText("UI_Aegis_StatProfession"), profLabel(d.profession))
        identRow(self, 6, getText("UI_Aegis_StatWeight"), string.format("%.1f", tonumber(d.weight) or 0))
        identRow(self, 7, getText("UI_Aegis_StatSurvived"), survivedText(d.hours))
        identRow(self, 8, getText("UI_Aegis_StatAccess"), str(d.level, none))
        identRow(self, 9, getText("UI_Aegis_StatAegisRole"), str(d.role, none))
    else
        Aegis.text(self, self.noAnswer and getText("UI_Aegis_StatNoAnswer") or getText("UI_Aegis_StatLoading"),
            PAD + 12, self.topY + 34, UIFont.Small, self.noAnswer and c.danger or c.muted)
    end

    -- traits card
    Aegis.roundFrame(self, PAD, self.traitY, LEFT_W, self.traitH, 10, 1, c.line, c.panel)
    Aegis.text(self, getText("UI_Aegis_StatTraits"), PAD + 12, self.traitY + 7, UIFont.Small, c.goldDim)

    -- skills card
    Aegis.roundFrame(self, self.rightX, self.topY, self.rightW, self.bodyH, 10, 1, c.line, c.panel)
    Aegis.text(self, getText("UI_Aegis_StatSkills"), self.rightX + 12, self.topY + 7, UIFont.Small, c.goldDim)
    local hy = self.topY + 30
    local lw = self.rightW
    Aegis.text(self, getText("UI_Aegis_StatSkill"), self.rightX + 10, hy, UIFont.Small, c.muted)
    Aegis.textRight(self, getText("UI_Aegis_StatLevel"), self.rightX + lw - 150, hy, UIFont.Small, c.muted)
    Aegis.textRight(self, getText("UI_Aegis_StatXP"), self.rightX + lw - 70, hy, UIFont.Small, c.muted)
    Aegis.textRight(self, getText("UI_Aegis_StatBoost"), self.rightX + lw - SKILL_RIGHT, hy, UIFont.Small, c.muted)
    Aegis.hairline(self, self.rightX + 8, self.topY + 47, lw - 16)

    -- footer state: a level at either end is a dead end, the server would
    -- only answer with "same"
    local row = self:selectedRow()
    local live = d ~= nil and row ~= nil
    self.xpBtn:setEnabled(live)
    self.setBtn:setEnabled(live)
    self.upBtn:setEnabled(live and row.level < LEVEL_MAX)
    self.downBtn:setEnabled(live and row.level > 0)
    for _, btn in ipairs(self.boostBtns) do
        btn:setEnabled(d ~= nil and row ~= nil)
        btn.style = (row and row.boost == btn.value) and "gold" or "ghost"
        btn.tooltip = row and getText("UI_Aegis_StatBoostFactor", factorText(row.id, btn.value)) or nil
    end
    local by = self.topY + self.bodyH - FOOT_H + 40
    if row then
        local note = getText("UI_Aegis_StatBoost") .. " " .. factorText(row.id, row.boost)
        if row.mult and row.mult > 0 then
            note = note .. "   " .. getText("UI_Aegis_StatMultiplier") .. " " .. string.format("%.2f", row.mult)
        end
        Aegis.text(self, Aegis.fitText(note, UIFont.Small, self.rightW - 220), self.rightX + 12, by + 5, UIFont.Small, c.muted)
    else
        Aegis.text(self, getText("UI_Aegis_StatPickSkill"), self.rightX + 12, by + 5, UIFont.Small, c.muted)
    end

    local hasData = d ~= nil
    self.dispBtn:setEnabled(hasData)
    self.dispAutoBtn:setEnabled(hasData)
    self.foreBtn:setEnabled(hasData)
    self.surBtn:setEnabled(hasData)
    self.profBtn:setEnabled(hasData)
    self.weightBtn:setEnabled(hasData)
    self.addTraitBtn:setEnabled(hasData)
end

function AegisPlayerStats:onMouseDown(x, y)
    self:bringToTop()
    if y <= HEADER then
        self.dragging = true
    end
end

function AegisPlayerStats:onMouseMove(dx, dy)
    if self.dragging then
        self:setX(self.x + dx)
        self:setY(self.y + dy)
    end
end

function AegisPlayerStats:onMouseMoveOutside(dx, dy)
    self:onMouseMove(dx, dy)
end

function AegisPlayerStats:onMouseUp(x, y)
    self.dragging = false
end

function AegisPlayerStats:onMouseUpOutside(x, y)
    self.dragging = false
end

-- ------------------------------------------------------------------
-- the two pushes every client has to answer, window open or not
-- ------------------------------------------------------------------

local function localPlayer(id, username)
    local found = nil
    if type(id) == "number" and id >= 0 then
        pcall(function() found = getPlayerByOnlineID(id) end)
    end
    if found then return found end
    local me = getPlayer()
    if not me then return nil end
    if type(username) == "string" and username ~= "" then
        local name = me:getUsername()
        if name == username then return me end
        return nil
    end
    if not isClient() then return me end
    return nil
end

-- absolute values for every perk, so a push that arrives twice cannot double
-- a boost. The map hangs off SurvivorDesc and rides in no packet, but client
-- side timed actions read the client's own copy
local function applyBoosts(args)
    if type(args) ~= "table" or type(args.boosts) ~= "table" then return end
    -- resolve like applyIdentity does: one connection can carry up to four
    -- players in splitscreen, and the targeted send only addresses the
    -- connection. Writing to getPlayer would hit the wrong character
    local me = localPlayer(tonumber(args.id) or -1, args.username)
    if not me then return end
    for _, boost in pairs(args.boosts) do
        if type(boost) == "table" and type(boost.p) == "string" then
            local perk = perks()[boost.p]
            if perk then
                pcall(function() me:getXp():setPerkBoost(perk, tonumber(boost.v) or 0) end)
            end
        end
    end
end

-- names and profession ride only in ChangePlayerStats, which no server can
-- send, and every client draws the tag over the head from its own copy
local function applyIdentity(args)
    if type(args) ~= "table" then return end
    local target = localPlayer(tonumber(args.id) or -1, args.username)
    if not target then return end
    local d = target:getDescriptor()
    if type(args.forename) == "string" then d:setForename(args.forename) end
    if type(args.surname) == "string" then d:setSurname(args.surname) end
    if type(args.profession) == "string" and args.profession ~= "" then
        pcall(function()
            local prof = CharacterProfession.get(ResourceLocation.of(args.profession))
            if prof then target:getDescriptor():setCharacterProfession(prof) end
        end)
    end
    if args.auto == true then
        target:resetDisplayName()
    elseif type(args.displayName) == "string" then
        target:setDisplayName(args.displayName)
    end
    pcall(function() triggerEvent("OnMiniScoreboardUpdate") end)
end

Events.OnServerCommand.Add(function(module, command, args)
    if module ~= AegisShared.MODULE then return end
    if command == "statsBoostApply" then
        applyBoosts(args)
        return
    end
    if command == "statsIdentityApply" then
        applyIdentity(args)
        return
    end
    if command ~= "statsData" then return end
    local win = AegisPlayerStats.instance
    if win then win:receive(args) end
end)

-- ==================================================================
-- AegisNeedsPanel: hunger, thirst and the rest as free sliders, the
-- thing the vanilla debug menu can and the panel could not (community
-- request). Its own card next to the values window, same lifecycle as
-- AegisStatsPicker: it belongs to one window and dies with it.
-- The bounds come from the server, which reads them off CharacterStat,
-- so nothing here has to know the engine ranges
-- ==================================================================
AegisNeedsPanel = ISPanel:derive("AegisNeedsPanel")
AegisNeedsPanel.instance = nil

local NEED_W = 300
local NEED_ROW = 34
-- four sends per second while dragging: the window may write eight times
-- per second before the server drops the rest, so this stays inside it
local NEED_SEND_GAP = 250
-- after a send the answer carries the server value back. Until it lands the
-- slider must keep what the hand set, otherwise the knob jumps back for the
-- round trip and the whole thing feels stuck (same pattern as featHold on
-- the dashboard feature switches).
-- LONGER than one poll cycle on purpose: the window polls every 2000ms,
-- and a poll answer that left the server just before the release carries
-- the old value. With a hold of 1200 that stale answer was adopted right
-- after the hold ran out and the knob visibly snapped back until the next
-- poll corrected it. 3500 outlives the stale answer
local NEED_HOLD = 3500
local NEED_LABEL = {
    HUNGER = "UI_Aegis_NeedHunger", THIRST = "UI_Aegis_NeedThirst",
    FATIGUE = "UI_Aegis_NeedFatigue", ENDURANCE = "UI_Aegis_NeedEndurance",
    STRESS = "UI_Aegis_NeedStress", PANIC = "UI_Aegis_NeedPanic",
    BOREDOM = "UI_Aegis_NeedBoredom", UNHAPPINESS = "UI_Aegis_NeedUnhappy",
    PAIN = "UI_Aegis_NeedPain", SICKNESS = "UI_Aegis_NeedSickness",
    INTOXICATION = "UI_Aegis_NeedDrunk", WETNESS = "UI_Aegis_NeedWetness",
}

function AegisPlayerStats:onNeeds()
    if AegisNeedsPanel.instance then
        AegisNeedsPanel.instance:close()
        return
    end
    AegisNeedsPanel.show(self)
end

function AegisNeedsPanel.show(owner)
    local rows = owner.data and owner.data.needs
    if type(rows) ~= "table" or #rows == 0 then
        Aegis.showToast(getText("UI_Aegis_StatWait"))
        return
    end
    local sw, sh = getCore():getScreenWidth(), getCore():getScreenHeight()
    local h = 52 + #rows * NEED_ROW + 12
    if h > sh - 40 then h = sh - 40 end
    local x = owner:getX() - NEED_W - 10
    if x < 8 then x = math.min(owner:getX() + owner:getWidth() + 10, sw - NEED_W - 8) end
    local y = math.max(8, math.min(owner:getY(), sh - h - 8))
    local o = ISPanel:new(x, y, NEED_W, h)
    setmetatable(o, AegisNeedsPanel)
    AegisNeedsPanel.__index = AegisNeedsPanel
    o.background = false
    o.owner = owner
    o:initialise()
    o:addToUIManager()
    o:setAlwaysOnTop(true)
    AegisNeedsPanel.instance = o
    return o
end

function AegisNeedsPanel:createChildren()
    self.closeBtn = AegisButton:new(self.width - 36, 11, 26, 26, nil, "close", self, AegisNeedsPanel.close)
    self.closeBtn.radius = 13
    self:addChild(self.closeBtn)

    self.sliders = {}
    local rows = self.owner.data.needs
    local y = 46
    for _, row in ipairs(rows) do
        local lo = tonumber(row.lo) or 0
        local hi = tonumber(row.hi) or 1
        local s = AegisSlider:new(120, y, self.width - 132, 24, self, nil)
        -- percent on screen, the real range travels to the server: the
        -- engine bounds differ per stat and must not be guessed here
        s:setValues(0, 100, 1, "%")
        s.needId = row.s
        s.needLo = lo
        s.needHi = hi
        s:setValue((hi > lo) and ((tonumber(row.v) or lo) - lo) / (hi - lo) * 100 or 0, true)
        -- live while dragging, but throttled: the raw slider fires on every
        -- pixel and would burn the write budget (8 per second) in one
        -- stroke. Four per second feels immediate and stays well inside it
        s.onChange = function(panel, value, sl)
            local now = getTimestampMs()
            if now < (sl.needNextSend or 0) then return end
            sl.needNextSend = now + NEED_SEND_GAP
            AegisNeedsPanel.send(panel, sl, true)
        end
        -- the release always sends the final value, the throttle above can
        -- have swallowed the last pixels of the drag
        s.onMouseUp = function(sl, mx, my)
            sl.dragging = false
            sl.needNextSend = 0
            AegisNeedsPanel.send(self, sl)
        end
        s.onMouseUpOutside = s.onMouseUp
        self:addChild(s)
        self.sliders[row.s] = s
        y = y + NEED_ROW
    end
end

-- quiet is the send during the drag. Every write is answered with a full
-- stats block, and the window turns that into a toast plus a complete
-- rebuild. Once per release that is right, four times per second it buries
-- the screen in toasts and rebuilds the window under the hand. The flag
-- travels to the server and comes back in the answer, so the client can
-- tell the drag answers from the one the admin asked for
function AegisNeedsPanel.send(self, slider, quiet)
    local win = self.owner
    if AegisPlayerStats.instance ~= win then return end
    local span = slider.needHi - slider.needLo
    local value = slider.needLo + (slider.value / 100) * span
    slider.needHold = getTimestampMs() + NEED_HOLD
    win:write("statsNeed", { stat = slider.needId, value = value, quiet = quiet or nil })
end

function AegisNeedsPanel:close()
    self:removeFromUIManager()
    if AegisNeedsPanel.instance == self then AegisNeedsPanel.instance = nil end
end

-- follow the server truth, but never yank the knob out of a dragging hand
function AegisNeedsPanel:update()
    local win = self.owner
    if AegisPlayerStats.instance ~= win or not win:isVisible() then
        self:close()
        return
    end
    local rows = win.data and win.data.needs
    if type(rows) ~= "table" then return end
    for _, row in ipairs(rows) do
        local s = self.sliders[row.s]
        if s and not s.dragging and getTimestampMs() >= (s.needHold or 0) then
            local span = s.needHi - s.needLo
            local pct = (span > 0) and ((tonumber(row.v) or s.needLo) - s.needLo) / span * 100 or 0
            s:setValue(pct, true)
        end
    end
end

function AegisNeedsPanel:prerender()
    local c = Aegis.col
    Aegis.shadow(self, 0, 0, self.width, self.height, 22, 0.6)
    Aegis.roundFrame(self, 0, 0, self.width, self.height, 12, 1, c.line, c.bg)
    Aegis.text(self, getText("UI_Aegis_StatNeeds"), 14, 13, UIFont.Medium, c.goldHi)
    Aegis.hairline(self, 1, 40, self.width - 2)
    local y = 46
    for _, row in ipairs(self.owner.data.needs or {}) do
        local key = NEED_LABEL[row.s]
        Aegis.text(self, Aegis.fitText(key and getText(key) or row.s, UIFont.Small, 104), 14,
            y + math.floor((24 - Aegis.fontH(UIFont.Small)) / 2), UIFont.Small, c.text)
        y = y + NEED_ROW
    end
end

function AegisNeedsPanel:onMouseDown(x, y)
    self:bringToTop()
    self.dragging = y <= 40
    return true
end

function AegisNeedsPanel:onMouseMove(dx, dy)
    if self.dragging then
        self:setX(self.x + dx)
        self:setY(self.y + dy)
    end
end

function AegisNeedsPanel:onMouseMoveOutside(dx, dy) self:onMouseMove(dx, dy) end
function AegisNeedsPanel:onMouseUp(x, y) self.dragging = false end
function AegisNeedsPanel:onMouseUpOutside(x, y) self.dragging = false end
