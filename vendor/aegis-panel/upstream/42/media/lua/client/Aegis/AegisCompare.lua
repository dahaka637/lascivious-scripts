-- Player comparison: fullscreen card with two players side by side.
-- Core stats on top per column, skills as shared rows (levels directly
-- opposite, differences subtly gold highlighted), aggregated inventory
-- below. Player B is picked inside the card, names come from the B42
-- scoreboard (same route as the players page).
require "Aegis/AegisTheme"
require "Aegis/AegisWidgets"
require "ISUI/ISScrollingListBox"
require "ISUI/ISComboBox"

AegisCompare = ISPanel:derive("AegisCompare")
AegisCompare.instance = nil

local CARD_W = 780
local CARD_H = 540
local PAD = 16
local GAP = 12
local COL_W = math.floor((CARD_W - PAD * 2 - GAP) / 2)
local SKILL_ROW = 20
local INV_ROW = 26
local REQUEST_COOLDOWN = 1500

-- perk id to translated name, built once locally from the PerkList
local perkNames = nil
local function perkName(id)
    if not perkNames then
        perkNames = {}
        for i = 0, PerkFactory.PerkList:size() - 1 do
            local perk = PerkFactory.PerkList:get(i)
            perkNames[perk:getId()] = perk:getName()
        end
    end
    return perkNames[id] or id
end

-- trait name to translated label via the CharacterTraitDefinitions
local traitNames = nil
local function traitName(name)
    if not traitNames then
        traitNames = {}
        local defs = CharacterTraitDefinition.getTraits()
        for i = 0, defs:size() - 1 do
            local def = defs:get(i)
            traitNames[def:getType():getName()] = def:getLabel()
        end
    end
    return traitNames[name] or name
end

function AegisCompare.open(usernameA)
    if AegisCompare.instance then AegisCompare.instance:close() end
    local sw, sh = getCore():getScreenWidth(), getCore():getScreenHeight()
    local o = ISPanel:new(0, 0, sw, sh)
    setmetatable(o, AegisCompare)
    AegisCompare.__index = AegisCompare
    o.background = true
    o.backgroundColor = { r = 0, g = 0, b = 0, a = 0.55 }
    o.borderColor = { r = 0, g = 0, b = 0, a = 0 }
    o.nameA = usernameA
    o.nameB = nil
    o.dataA = nil
    o.dataB = nil
    o.distance = nil
    o.floors = 0
    o.solo = not isClient()
    o.nextRequest = 0
    o.nextComboAt = 0
    o.requestPending = false
    o.logged = nil
    o.comboState = nil
    -- shift right-aligned on narrow screens so the close button stays visible
    o.cardX = math.min(math.floor((sw - CARD_W) / 2), sw - CARD_W)
    o.cardY = math.max(0, math.floor((sh - CARD_H) / 2))
    o:initialise()
    o:addToUIManager()
    o:setAlwaysOnTop(true)
    AegisCompare.instance = o
    if isClient() then scoreboardUpdate() end
    o:request()
    return o
end

-- every child sits at an absolute offset from the card corner, so moving
-- the card means moving them along
function AegisCompare:layout()
    local cx, cy = self.cardX, self.cardY
    self.closeBtn:setX(cx + CARD_W - 42)
    self.closeBtn:setY(cy + 12)
    self.refreshBtn:setX(cx + CARD_W - 42 - 38)
    self.refreshBtn:setY(cy + 12)
    if self.comboB then
        self.comboB:setX(cx + PAD + COL_W + GAP)
        self.comboB:setY(cy + 44)
    end
    self.skillList:setX(cx + PAD + 1)
    self.skillList:setY(cy + 219)
    self.invA:setX(cx + PAD + 1)
    self.invA:setY(cy + 357)
    self.invB:setX(cx + PAD + COL_W + GAP + 1)
    self.invB:setY(cy + 357)
end

function AegisCompare:createChildren()
    local cx, cy = self.cardX, self.cardY

    self.closeBtn = AegisButton:new(cx + CARD_W - 42, cy + 12, 30, 30, nil, "close", self, AegisCompare.close)
    self.closeBtn.radius = 15
    self:addChild(self.closeBtn)

    self.refreshBtn = AegisButton:new(cx + CARD_W - 42 - 38, cy + 12, 30, 30, nil, "refresh", self, AegisCompare.request)
    self.refreshBtn.radius = 15
    self:addChild(self.refreshBtn)

    -- pick player B right inside the card; nobody available in solo
    if not self.solo then
        self.comboB = ISComboBox:new(cx + PAD + COL_W + GAP, cy + 44, COL_W, 26, self, AegisCompare.onPickB)
        self.comboB:initialise()
        self:addChild(self.comboB)
        self:fillCombo()
    end

    -- skills as one shared list across both columns so the levels
    -- sit next to each other per row and stay comparable
    self.skillList = ISScrollingListBox:new(cx + PAD + 1, cy + 219, CARD_W - PAD * 2 - 2, 114)
    self.skillList:initialise()
    self.skillList:instantiate()
    self.skillList.itemheight = SKILL_ROW
    self.skillList.drawBorder = false
    self.skillList.backgroundColor = { r = 0, g = 0, b = 0, a = 0 }
    self.skillList.doDrawItem = AegisCompare.drawSkillRow
    self:addChild(self.skillList)

    self.invA = ISScrollingListBox:new(cx + PAD + 1, cy + 357, COL_W - 2, CARD_H - 357 - PAD - 1)
    self.invA:initialise()
    self.invA:instantiate()
    self.invA.itemheight = INV_ROW
    self.invA.drawBorder = false
    self.invA.backgroundColor = { r = 0, g = 0, b = 0, a = 0 }
    self.invA.doDrawItem = AegisCompare.drawInvRow
    self:addChild(self.invA)

    self.invB = ISScrollingListBox:new(cx + PAD + COL_W + GAP + 1, cy + 357, COL_W - 2, CARD_H - 357 - PAD - 1)
    self.invB:initialise()
    self.invB:instantiate()
    self.invB.itemheight = INV_ROW
    self.invB.drawBorder = false
    self.invB.backgroundColor = { r = 0, g = 0, b = 0, a = 0 }
    self.invB.doDrawItem = AegisCompare.drawInvRow
    self:addChild(self.invB)
end

function AegisCompare.close(self)
    self:removeFromUIManager()
    if AegisCompare.instance == self then AegisCompare.instance = nil end
end

-- ------------------------------------------------------------------
-- Data
-- ------------------------------------------------------------------

-- fill the combo from the scoreboard cache; only rebuild when the
-- name list actually changed (selection is preserved)
function AegisCompare:fillCombo()
    if not self.comboB then return end
    local names = {}
    for _, row in ipairs(Aegis.scoreboard or {}) do
        if row.username and row.username ~= self.nameA then
            table.insert(names, row.username)
        end
    end
    table.sort(names)
    local state = table.concat(names, "|")
    if state == self.comboState then return end
    self.comboState = state
    self.comboB:clear()
    self.comboB:addOption(getText("UI_Aegis_CmpChooseSecond"))
    local sel = 1
    for i, n in ipairs(names) do
        self.comboB:addOption(n)
        if n == self.nameB then sel = i + 1 end
    end
    self.comboB.selected = sel
    -- the previous player B went offline
    if self.nameB and sel == 1 then
        self.nameB = nil
        self.dataB = nil
        self.distance = nil
        self:buildLists()
    end
end

function AegisCompare.onPickB(self, combo)
    local idx = combo.selected or 1
    if idx <= 1 then
        self.nameB = nil
        self.dataB = nil
        self.distance = nil
        self:buildLists()
        return
    end
    local opt = combo.options[idx]
    self.nameB = type(opt) == "table" and opt.text or opt
    self.dataB = nil
    self.distance = nil
    self:request()
end

-- throttled request, doubles as the refresh button callback;
-- a call landing inside the cooldown is retried later by update()
function AegisCompare.request(self)
    local now = getTimestampMs()
    if now < (self.nextRequest or 0) then
        self.requestPending = true
        return
    end
    self.requestPending = false
    self.nextRequest = now + REQUEST_COOLDOWN
    local args = { a = self.nameA }
    if self.nameB then args.b = self.nameB end
    sendClientCommand(getPlayer(), AegisShared.MODULE, "compareData", args)
    -- one log entry per pair, refreshing does not spam
    if self.nameB then
        local pair = self.nameA .. "|" .. self.nameB
        if self.logged ~= pair then
            self.logged = pair
            Aegis.logAction("players", "Player compare: " .. self.nameA .. " vs " .. self.nameB)
        end
    end
end

function AegisCompare:receive(args)
    if not args or type(args.a) ~= "table" then return end
    -- drop stale reply from an earlier pair
    if args.a.username ~= self.nameA then return end
    self.dataA = args.a
    if args.b and self.nameB and args.b.username == self.nameB then
        self.dataB = args.b
        self.distance = args.distance
        self.floors = args.floors or 0
    elseif not self.nameB then
        self.dataB = nil
        self.distance = nil
    end
    self:buildLists()
end

-- read network tables with pairs like AegisModerationClient does,
-- ordering is established by the sort anyway
local function invRows(block)
    local rows = {}
    for _, e in pairs(block and block.inv or {}) do
        if type(e) == "table" and e.t then
            table.insert(rows, {
                t = e.t, n = e.n or 1, g = e.g or 0,
                name = getItemName(e.t) or e.t,
                tex = getItemTex(e.t),
            })
        end
    end
    table.sort(rows, function(x, y)
        if x.n ~= y.n then return x.n > y.n end
        return x.name < y.name
    end)
    return rows
end

function AegisCompare:buildLists()
    local a, b = self.dataA, self.dataB
    local both = a and not a.missing and b and not b.missing

    -- skill union of both players, same row = same perk
    local map = {}
    local rows = {}
    local function take(block, field)
        if not block or block.missing then return end
        for _, s in pairs(block.skills or {}) do
            if type(s) == "table" and s.id then
                local rec = map[s.id]
                if not rec then
                    rec = { id = s.id, name = perkName(s.id) }
                    map[s.id] = rec
                    table.insert(rows, rec)
                end
                rec[field] = s.level
            end
        end
    end
    take(a, "la")
    take(b, "lb")
    table.sort(rows, function(x, y) return x.name < y.name end)
    for _, rec in ipairs(rows) do
        rec.diff = both and (rec.la or 0) ~= (rec.lb or 0) or false
    end
    self.skillList:clear()
    self.skillList.selected = -1
    for _, rec in ipairs(rows) do
        self.skillList:addItem(rec.name, rec)
    end

    self.invA:clear()
    self.invA.selected = -1
    if a and not a.missing then
        for _, rec in ipairs(invRows(a)) do self.invA:addItem(rec.name, rec) end
    end
    self.invB:clear()
    self.invB.selected = -1
    if b and not b.missing then
        for _, rec in ipairs(invRows(b)) do self.invB:addItem(rec.name, rec) end
    end
end

-- scoreboard arrives asynchronously, refresh the combo on a timer;
-- a request stuck in the throttle is retried here
function AegisCompare:update()
    local now = getTimestampMs()
    if now >= (self.nextComboAt or 0) then
        self.nextComboAt = now + 2000
        self:fillCombo()
    end
    if self.requestPending and now >= (self.nextRequest or 0) then
        self:request()
    end
end

-- ------------------------------------------------------------------
-- Rendering
-- ------------------------------------------------------------------

function AegisCompare.drawSkillRow(list, y, item, alt)
    local c = Aegis.col
    local w = list:getWidth()
    local rec = item.item
    if rec.diff then
        Aegis.roundRect(list, 2, y + 1, w - 4, SKILL_ROW - 2, 6, 0.14, c.gold)
    end
    local ty = y + math.floor((SKILL_ROW - Aegis.fontH(UIFont.Small)) / 2)
    Aegis.textCentre(list, rec.name, math.floor(w / 2), ty, UIFont.Small, rec.diff and c.text or c.muted)
    local ca = (rec.diff and (rec.la or 0) > (rec.lb or 0)) and c.goldHi or c.text
    local cb = (rec.diff and (rec.lb or 0) > (rec.la or 0)) and c.goldHi or c.text
    Aegis.textCentre(list, rec.la and tostring(rec.la) or "-", math.floor(w * 0.25), ty, UIFont.Small, ca)
    Aegis.textCentre(list, rec.lb and tostring(rec.lb) or "-", math.floor(w * 0.75), ty, UIFont.Small, cb)
    return y + SKILL_ROW
end

function AegisCompare.drawInvRow(list, y, item, alt)
    local c = Aegis.col
    local rec = item.item
    local w = list:getWidth()
    local ty = y + math.floor((INV_ROW - Aegis.fontH(UIFont.Small)) / 2)
    if rec.tex then
        list:drawTextureScaledAspect2(rec.tex, 8, y + math.floor((INV_ROW - 20) / 2), 20, 20, 1, 1, 1, 1)
    end
    -- the scroll bar sits on top of the right edge, the weight used to
    -- disappear underneath it as soon as the list had more rows than height
    local bar = 0
    if list.isVScrollBarVisible and list:isVScrollBarVisible() and list.vscroll then
        bar = list.vscroll:getWidth()
    end
    local right = w - 10 - bar
    local nameW = right - 34 - 86
    if rec._fitW ~= nameW then
        rec._fitW = nameW
        rec._fit = Aegis.fitText(rec.name, UIFont.Small, nameW)
    end
    Aegis.text(list, rec._fit, 34, ty, UIFont.Small, c.text)
    Aegis.textRight(list, tostring(rec.g), right, ty, UIFont.Small, c.muted)
    Aegis.textRight(list, "x" .. tostring(rec.n), right - 48, ty, UIFont.Small, c.goldHi)
    return y + INV_ROW
end

local function statRow(self, x, y, label, value)
    local c = Aegis.col
    Aegis.text(self, label, x, y, UIFont.Small, c.muted)
    Aegis.text(self, Aegis.fitText(value, UIFont.Small, COL_W - 116), x + 112, y, UIFont.Small, c.text)
end

function AegisCompare:drawBlock(colX, block)
    local c = Aegis.col
    local cy = self.cardY
    if not block then
        Aegis.text(self, getText("UI_Aegis_CmpNoData"), colX, cy + 78, UIFont.Small, c.muted)
        return
    end
    if block.missing then
        Aegis.text(self, Aegis.fitText(getText("UI_Aegis_CmpOffline"), UIFont.Small, COL_W), colX, cy + 78, UIFont.Small, c.danger)
        return
    end
    local y = cy + 78
    statRow(self, colX, y, getText("UI_Aegis_CmpSurvived"), tostring(block.hours or 0) .. " h")
    y = y + 17
    statRow(self, colX, y, getText("UI_Aegis_CmpKills"), tostring(block.kills or 0))
    y = y + 17
    statRow(self, colX, y, getText("UI_Aegis_CmpPosition"), tostring(block.x) .. ", " .. tostring(block.y) .. ", " .. tostring(block.z))
    y = y + 17
    statRow(self, colX, y, getText("UI_Aegis_CmpCarryLoad"), tostring(block.last or 0) .. " / " .. tostring(block.maxWeight or "?"))
    y = y + 17
    if not block._weaponText then
        block._weaponText = block.weapon and (getItemName(block.weapon) or block.weapon) or "-"
    end
    statRow(self, colX, y, getText("UI_Aegis_CmpWeapon"), block._weaponText)
    y = y + 17
    if not block._traitText then
        local parts = {}
        for _, t in pairs(block.traits or {}) do
            if type(t) == "string" then table.insert(parts, traitName(t)) end
        end
        table.sort(parts)
        block._traitText = #parts > 0 and table.concat(parts, ", ") or "-"
    end
    statRow(self, colX, y, getText("UI_Aegis_CmpTraits"), block._traitText)
end

function AegisCompare:prerender()
    ISPanel.prerender(self)
    local c = Aegis.col
    local cx, cy = self.cardX, self.cardY
    local colAx = cx + PAD
    local colBx = cx + PAD + COL_W + GAP

    Aegis.shadow(self, cx, cy, CARD_W, CARD_H, 30, 0.7)
    Aegis.roundFrame(self, cx, cy, CARD_W, CARD_H, 12, 1, c.line, c.bg)
    Aegis.icon(self, "players", cx + 18, cy + 16, 18, 1, c.gold)
    Aegis.text(self, getText("UI_Aegis_CmpTitle"), cx + 46, cy + 14, UIFont.Medium, c.text)

    -- header per column: fixed player A left, combo or solo hint right
    Aegis.text(self, Aegis.fitText(self.nameA, UIFont.Medium, COL_W), colAx, cy + 46, UIFont.Medium, c.goldHi)
    if self.solo then
        Aegis.text(self, Aegis.fitText(getText("UI_Aegis_CmpSoloInfo"), UIFont.Small, COL_W), colBx, cy + 50, UIFont.Small, c.muted)
    end
    self:drawBlock(colAx, self.dataA)
    if not self.solo then
        if self.nameB then
            self:drawBlock(colBx, self.dataB)
        else
            Aegis.text(self, Aegis.fitText(getText("UI_Aegis_CmpChooseSecond"), UIFont.Small, COL_W), colBx, cy + 78, UIFont.Small, c.muted)
        end
    end

    -- distance line in the middle, only when both are online
    if self.distance then
        local text = getText("UI_Aegis_CmpDistance", tostring(self.distance))
        if (self.floors or 0) > 0 then
            text = text .. ", " .. getText("UI_Aegis_CmpFloors", tostring(self.floors))
        end
        Aegis.textCentre(self, text, cx + math.floor(CARD_W / 2), cy + 184, UIFont.Small, c.goldHi)
    end

    -- Skills
    Aegis.text(self, getText("UI_Aegis_CmpSkills"), colAx, cy + 200, UIFont.Small, c.muted)
    Aegis.roundFrame(self, cx + PAD, cy + 218, CARD_W - PAD * 2, 116, 8, 1, c.line, c.panel)
    if #self.skillList.items == 0 and self.dataA and not self.dataA.missing then
        Aegis.textCentre(self, getText("UI_Aegis_CmpNoSkills"), cx + math.floor(CARD_W / 2), cy + 268, UIFont.Small, c.muted)
    end

    -- inventory per column
    Aegis.text(self, getText("UI_Aegis_CmpInventory"), colAx, cy + 338, UIFont.Small, c.muted)
    Aegis.text(self, getText("UI_Aegis_CmpInventory"), colBx, cy + 338, UIFont.Small, c.muted)
    if self.dataA and self.dataA.invTruncated then
        Aegis.textRight(self, getText("UI_Aegis_CmpTruncated"), colAx + COL_W, cy + 338, UIFont.Small, c.muted)
    end
    if self.dataB and self.dataB.invTruncated then
        Aegis.textRight(self, getText("UI_Aegis_CmpTruncated"), colBx + COL_W, cy + 338, UIFont.Small, c.muted)
    end
    Aegis.roundFrame(self, cx + PAD, cy + 356, COL_W, CARD_H - 356 - PAD, 8, 1, c.line, c.panel)
    Aegis.roundFrame(self, colBx, cy + 356, COL_W, CARD_H - 356 - PAD, 8, 1, c.line, c.panel)
    if #self.invA.items == 0 and self.dataA and not self.dataA.missing then
        Aegis.textCentre(self, getText("UI_Aegis_CmpInvEmpty"), colAx + math.floor(COL_W / 2), cy + 430, UIFont.Small, c.muted)
    end
    if #self.invB.items == 0 and self.dataB and not self.dataB.missing then
        Aegis.textCentre(self, getText("UI_Aegis_CmpInvEmpty"), colBx + math.floor(COL_W / 2), cy + 430, UIFont.Small, c.muted)
    end
end

-- drag by the card header, the strip left of the two round buttons
function AegisCompare:onMouseDown(x, y)
    local cx, cy = self.cardX, self.cardY
    if x >= cx and x <= cx + CARD_W - 84 and y >= cy and y <= cy + 54 then
        self.dragging = true
        self.dragX = x - cx
        self.dragY = y - cy
    end
end

function AegisCompare:onMouseUp(x, y)
    self.dragging = false
end

function AegisCompare:onMouseUpOutside(x, y)
    self.dragging = false
end

function AegisCompare:onMouseMove(dx, dy)
    if not self.dragging then return end
    local sw, sh = getCore():getScreenWidth(), getCore():getScreenHeight()
    self.cardX = math.max(0, math.min(sw - CARD_W, self.cardX + dx))
    self.cardY = math.max(0, math.min(sh - CARD_H, self.cardY + dy))
    self:layout()
end

function AegisCompare:onMouseMoveOutside(dx, dy)
    self:onMouseMove(dx, dy)
end

Events.OnServerCommand.Add(function(module, command, args)
    if module ~= AegisShared.MODULE then return end
    if command ~= "compareData" then return end
    local self = AegisCompare.instance
    if self then self:receive(args) end
end)
