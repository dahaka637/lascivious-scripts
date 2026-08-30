-- Factions: two column overview. Left faction list with all safehouses
-- below it (including factionless ones), right details for the selection
-- with members (online/offline), related safehouses and a jump button.
require "Aegis/AegisWindow"
require "ISUI/ISScrollingListBox"

AegisPageFactions = ISPanel:derive("AegisPageFactions")
AegisPageFactions.instance = nil

local LIST_W = 300
local ROW_H = 46
local SH_ROW_H = 40
local REQUEST_MIN_MS = 1500
local POLL_MS = 10000

local function layout(self)
    local pad = 20
    local innerH = self.height - pad * 2
    local factionH = math.floor(innerH * 0.55)
    local shTop = pad + factionH + 12
    return pad, innerH, factionH, shTop
end

-- brighten dark faction colors for the dark theme, raw value stays intact
local function readableColor(color)
    local f = { r = color.r, g = color.g, b = color.b }
    if f.r + f.g + f.b < 0.75 then
        f.r = math.min(1, f.r + 0.35)
        f.g = math.min(1, f.g + 0.35)
        f.b = math.min(1, f.b + 0.35)
    end
    return f
end

local function shName(e)
    return e.title ~= "" and e.title or e.owner
end

local function coordText(e)
    return e.x .. "," .. e.y .. "  " .. e.w .. "x" .. e.h
end

function AegisPageFactions.create(window, x, y, w, h)
    local o = ISPanel:new(x, y, w, h)
    setmetatable(o, AegisPageFactions)
    AegisPageFactions.__index = AegisPageFactions
    o.background = false
    o.window = window
    o.factions = {}
    o.safehouses = {}
    o.online = {}
    o.lastRequest = 0
    AegisPageFactions.instance = o
    return o
end

function AegisPageFactions:createChildren()
    local pad, innerH, factionH, shTop = layout(self)

    self.refreshBtn = AegisButton:new(pad + LIST_W - 36, pad + 6, 30, 28, nil, "refresh", self, AegisPageFactions.request)
    self:addChild(self.refreshBtn)

    self.factionList = ISScrollingListBox:new(pad + 1, pad + 44, LIST_W - 2, factionH - 45)
    self.factionList:initialise()
    self.factionList:instantiate()
    self.factionList.itemheight = ROW_H
    self.factionList.drawBorder = false
    self.factionList.backgroundColor = { r = 0, g = 0, b = 0, a = 0 }
    self.factionList.doDrawItem = AegisPageFactions.drawFactionRow
    self.factionList:setOnMouseDownFunction(self, AegisPageFactions.onSelectFaction)
    self:addChild(self.factionList)

    self.shList = ISScrollingListBox:new(pad + 1, shTop + 34, LIST_W - 2, pad + innerH - shTop - 35)
    self.shList:initialise()
    self.shList:instantiate()
    self.shList.itemheight = SH_ROW_H
    self.shList.drawBorder = false
    self.shList.backgroundColor = { r = 0, g = 0, b = 0, a = 0 }
    self.shList.doDrawItem = AegisPageFactions.drawShRow
    self.shList:setOnMouseDownFunction(self, AegisPageFactions.onSelectSh)
    self:addChild(self.shList)

    local dx = pad + LIST_W + 20
    local dw = self.width - dx - pad
    self.jumpBtn = AegisButton:new(dx + 14, self.height - pad - 50, dw - 28, 36, getText("UI_Aegis_FactionJump"), "pin", self, AegisPageFactions.onJump)
    self.jumpBtn.style = "gold"
    self.jumpBtn:setVisible(false)
    self:addChild(self.jumpBtn)

    -- the only admin path to fully release a safehouse, there was no
    -- other before. Sits above the jump button, same width, own row
    self.releaseBtn = AegisButton:new(dx + 14, self.height - pad - 96, dw - 28, 36, getText("UI_Aegis_FactionRelease"), "trash", self, AegisPageFactions.onRelease)
    self.releaseBtn.style = "danger"
    self.releaseBtn:setVisible(false)
    self:addChild(self.releaseBtn)
end

-- ------------------------------------------------------------------
-- Fetching data: button and onShow request, update polls on a timer
-- ------------------------------------------------------------------

function AegisPageFactions.request(self)
    local now = getTimestampMs()
    if self.lastRequest > 0 and now - self.lastRequest < REQUEST_MIN_MS then return end
    local p = getPlayer()
    if not p then return end
    self.lastRequest = now
    sendClientCommand(p, AegisShared.MODULE, "factionList", {})
end

function AegisPageFactions:onShow()
    self:request()
end

function AegisPageFactions:update()
    ISPanel.update(self)
    if not self:isVisible() or not AegisWindow.instance then return end
    if getTimestampMs() - self.lastRequest >= POLL_MS then
        self:request()
    end
end

function AegisPageFactions:setData(args)
    -- read network tables defensively: pairs plus type check, ipairs
    -- is not reliable on received tables (pattern shList)
    local online = {}
    if type(args.online) == "table" then
        for _, n in pairs(args.online) do
            if type(n) == "string" then online[n] = true end
        end
    end

    local factions = {}
    if type(args.factions) == "table" then
        for _, e in pairs(args.factions) do
            if type(e) == "table" and e.name ~= nil then
                local members = {}
                if type(e.members) == "table" then
                    for _, n in pairs(e.members) do
                        if type(n) == "string" then table.insert(members, n) end
                    end
                end
                table.sort(members)
                local color = { r = 1, g = 1, b = 1 }
                if type(e.color) == "table" then
                    color.r = tonumber(e.color.r) or 1
                    color.g = tonumber(e.color.g) or 1
                    color.b = tonumber(e.color.b) or 1
                end
                table.insert(factions, {
                    name = tostring(e.name),
                    tag = tostring(e.tag or ""),
                    owner = tostring(e.owner or ""),
                    color = color,
                    displayColor = readableColor(color),
                    members = members,
                    shCount = tonumber(e.shCount) or 0,
                    -- came from Faction Framework, not from the vanilla list
                    ff = e.ff == true,
                })
            end
        end
    end
    table.sort(factions, function(a, b) return a.name:lower() < b.name:lower() end)

    local safehouses = {}
    if type(args.safehouses) == "table" then
        for _, e in pairs(args.safehouses) do
            if type(e) == "table" and tonumber(e.x) then
                local players = {}
                if type(e.players) == "table" then
                    for _, n in pairs(e.players) do
                        if type(n) == "string" then table.insert(players, n) end
                    end
                end
                table.insert(safehouses, {
                    title = tostring(e.title or ""),
                    owner = tostring(e.owner or ""),
                    x = math.floor(tonumber(e.x)), y = math.floor(tonumber(e.y) or 0),
                    w = math.floor(tonumber(e.w) or 1), h = math.floor(tonumber(e.h) or 1),
                    players = players,
                    annex = e.annex == true,
                })
            end
        end
    end
    table.sort(safehouses, function(a, b)
        -- annexes go last, otherwise alphabetical
        if a.annex ~= b.annex then return not a.annex end
        return shName(a):lower() < shName(b):lower()
    end)

    self.online = online
    self.factions = factions
    self.safehouses = safehouses
    self:fillLists()
end

function AegisPageFactions:fillLists()
    local item = self.factionList.items[self.factionList.selected]
    local prevFaction = item and item.item.name or nil
    self.factionList:clear()
    self.factionList.selected = -1
    for i, f in ipairs(self.factions) do
        self.factionList:addItem(f.name, f)
        if prevFaction and f.name == prevFaction then
            self.factionList.selected = i
        end
    end

    item = self.shList.items[self.shList.selected]
    local prevSh = item and item.item and not item.item.groupRow
        and (item.item.x .. "|" .. item.item.y) or nil
    self.shList:clear()
    self.shList.selected = -1
    -- one row per owner, the rectangles appear only when that owner is
    -- opened; a painted zone is several safehouses and used to flood the
    -- whole list with its pieces
    self.shOpen = self.shOpen or {}
    local order, byOwner = {}, {}
    for _, e in ipairs(self.safehouses) do
        local owner = e.owner ~= "" and e.owner or "?"
        if not byOwner[owner] then
            byOwner[owner] = {}
            table.insert(order, owner)
        end
        table.insert(byOwner[owner], e)
    end
    table.sort(order, function(a, b) return a:lower() < b:lower() end)
    for _, owner in ipairs(order) do
        local list = byOwner[owner]
        local tiles = 0
        for _, e in ipairs(list) do tiles = tiles + (e.w or 0) * (e.h or 0) end
        self.shList:addItem(owner, { groupRow = true, owner = owner,
            count = #list, tiles = tiles, open = self.shOpen[owner] == true })
        if self.shOpen[owner] then
            for _, e in ipairs(list) do
                local i = #self.shList.items + 1
                self.shList:addItem(shName(e), e)
                if prevSh and (e.x .. "|" .. e.y) == prevSh then
                    self.shList.selected = i
                end
            end
        end
    end
    self:updateButtons()
end

-- ------------------------------------------------------------------
-- Selection: faction and safehouse are mutually exclusive
-- ------------------------------------------------------------------

function AegisPageFactions:selectedFaction()
    local item = self.factionList.items[self.factionList.selected]
    return item and item.item or nil
end

function AegisPageFactions:selectedSafehouse()
    local item = self.shList.items[self.shList.selected]
    local e = item and item.item or nil
    if e and e.groupRow then return nil end
    return e
end

function AegisPageFactions.onSelectFaction(self, item)
    self.shList.selected = -1
    self:updateButtons()
end

function AegisPageFactions.onSelectSh(self, e)
    -- invokeOnMouseDownFunction passes items[selected].item, so this is
    -- already the entry itself and must not be unwrapped again
    if e and e.groupRow then
        -- owner rows open and close, they are no target for the buttons
        self.shOpen = self.shOpen or {}
        self.shOpen[e.owner] = not self.shOpen[e.owner]
        self.shList.selected = -1
        self:fillLists()
        return
    end
    self.factionList.selected = -1
    self:updateButtons()
end

function AegisPageFactions:updateButtons()
    if not self.jumpBtn then return end
    local sh = self:selectedSafehouse()
    local jumpVisible = sh ~= nil and Aegis.canSee("world")
    self.jumpBtn:setVisible(jumpVisible)
    self.jumpBtn:setEnabled(jumpVisible)
    -- release lives on the zones area, not world: an admin with only
    -- teleport rights must not get a button that fails server side
    local releaseVisible = sh ~= nil and Aegis.canSee("zones")
    if self.releaseBtn then
        self.releaseBtn:setVisible(releaseVisible)
        self.releaseBtn:setEnabled(releaseVisible)
    end
end

-- all factions where the name is owner or member
function AegisPageFactions:factionOf(name)
    if name == "" then return nil end
    for _, f in ipairs(self.factions) do
        if f.owner == name then return f end
        for _, n in ipairs(f.members) do
            if n == name then return f end
        end
    end
    return nil
end

-- main safehouses that faction members are involved in
-- (same rule as server side for shCount)
function AegisPageFactions:factionSafehouses(f)
    local set = {}
    if f.owner ~= "" then set[f.owner] = true end
    for _, n in ipairs(f.members) do set[n] = true end
    local res = {}
    for _, sh in ipairs(self.safehouses) do
        if not sh.annex then
            local involved = set[sh.owner] == true
            if not involved then
                for _, n in ipairs(sh.players) do
                    if set[n] then
                        involved = true
                        break
                    end
                end
            end
            if involved then table.insert(res, sh) end
        end
    end
    return res
end

-- ------------------------------------------------------------------
-- List rows
-- ------------------------------------------------------------------

function AegisPageFactions.drawFactionRow(list, y, item, alt)
    local c = Aegis.col
    local sel = list.selected == item.index
    local hover = list.mouseoverselected == item.index
    if sel then
        Aegis.roundRect(list, 2, y + 2, list:getWidth() - 4, ROW_H - 4, 8, 1, c.card)
        Aegis.roundRect(list, 2, y + 10, 3, ROW_H - 20, 1, 1, c.gold)
    elseif hover then
        Aegis.roundRect(list, 2, y + 2, list:getWidth() - 4, ROW_H - 4, 8, 0.5, c.card)
    end
    local f = item.item
    local x = 14
    if f.ff then
        -- mark the source: these factions live in Faction Framework and
        -- cannot be touched from here, only looked at
        Aegis.text(list, "FF", x, y + 5, UIFont.Small, c.goldDim)
        x = x + Aegis.strW(UIFont.Small, "FF") + 6
    end
    if f.tag ~= "" then
        local tag = "[" .. f.tag .. "]"
        Aegis.text(list, tag, x, y + 5, UIFont.Small, f.displayColor)
        x = x + Aegis.strW(UIFont.Small, tag) + 6
    end
    Aegis.text(list, Aegis.fitText(f.name, UIFont.Small, list:getWidth() - x - 44), x, y + 5, UIFont.Small, sel and c.text or c.muted)
    Aegis.textRight(list, tostring(#f.members + 1), list:getWidth() - 12, y + 5, UIFont.Small, c.goldDim)
    local uy = y + 7 + Aegis.fontH(UIFont.Small)
    Aegis.icon(list, "crown", 14, uy + 1, 11, 1, c.gold)
    Aegis.text(list, Aegis.fitText(f.owner, UIFont.Small, list:getWidth() - 44), 30, uy, UIFont.Small, c.muted)
    return y + ROW_H
end

function AegisPageFactions.drawShRow(list, y, item, alt)
    local c = Aegis.col
    local sel = list.selected == item.index
    local hover = list.mouseoverselected == item.index
    if sel then
        Aegis.roundRect(list, 2, y + 2, list:getWidth() - 4, SH_ROW_H - 4, 8, 1, c.card)
        Aegis.roundRect(list, 2, y + 8, 3, SH_ROW_H - 16, 1, 1, c.gold)
    elseif hover then
        Aegis.roundRect(list, 2, y + 2, list:getWidth() - 4, SH_ROW_H - 4, 8, 0.5, c.card)
    end
    local e = item.item
    if e.groupRow then
        Aegis.icon(list, e.open and "minus" or "plus", 12, y + 6, 11, 1, c.gold)
        Aegis.text(list, Aegis.fitText(e.owner, UIFont.Small, list:getWidth() - 120), 30, y + 4, UIFont.Small, c.text)
        local uy2 = y + 5 + Aegis.fontH(UIFont.Small)
        local parts = e.count .. " " .. getText(e.count == 1 and "UI_Aegis_ShOnePart" or "UI_Aegis_ShParts")
        Aegis.text(list, parts, 30, uy2, UIFont.Small, c.muted)
        Aegis.textRight(list, e.tiles .. " " .. getText("UI_Aegis_ZoneTiles"),
            list:getWidth() - 12, uy2, UIFont.Small, c.goldDim)
        return y + SH_ROW_H
    end
    Aegis.text(list, Aegis.fitText(shName(e), UIFont.Small, list:getWidth() - 40), 26, y + 4, UIFont.Small, sel and c.text or c.muted)
    if e.annex then
        Aegis.textRight(list, "+", list:getWidth() - 12, y + 4, UIFont.Small, c.gold)
    end
    local uy = y + 5 + Aegis.fontH(UIFont.Small)
    Aegis.text(list, Aegis.fitText(e.owner, UIFont.Small, list:getWidth() - 130), 26, uy, UIFont.Small, c.muted)
    Aegis.textRight(list, coordText(e), list:getWidth() - 12, uy, UIFont.Small, c.goldDim)
    return y + SH_ROW_H
end

-- ------------------------------------------------------------------
-- Jumping there: MP via the vanilla command, solo sets it directly
-- ------------------------------------------------------------------

function AegisPageFactions.onJump(self)
    local e = self:selectedSafehouse()
    if not e or not Aegis.canSee("world") then return end
    local zx = math.floor(e.x + e.w / 2)
    local zy = math.floor(e.y + e.h / 2)
    if isClient() then
        SendCommandToServer("/teleportto " .. zx .. "," .. zy .. ",0")
    else
        local p = getPlayer()
        if p then
            pcall(function() p:teleportTo(zx, zy, 0.0) end)
        end
    end
    Aegis.logAction("factions", string.format("Jumped to safehouse: %s (%d,%d)", shName(e), zx, zy))
    Aegis.showToast(getText("UI_Aegis_FactionJump") .. ": " .. shName(e))
end

-- ------------------------------------------------------------------
-- Releasing: main plus every annex, server side (Aegis_Zones.shRelease)
-- ------------------------------------------------------------------

function AegisPageFactions.onRelease(self)
    local e = self:selectedSafehouse()
    if not e or not Aegis.canSee("zones") then return end
    local x, y = e.x, e.y
    local label = shName(e)
    AegisConfirm.show(getText("UI_Aegis_FactionRelease"), getText("UI_Aegis_ConfirmRelease", label),
        getText("UI_Aegis_FactionRelease"), self, function()
            local p = getPlayer()
            if not p then return end
            sendClientCommand(p, AegisShared.MODULE, "shRelease", { x = x, y = y })
            Aegis.logAction("factions", string.format("Safehouse release requested: %s (%d,%d)", label, x, y))
        end)
end

-- ------------------------------------------------------------------
-- Detail pane on the right
-- ------------------------------------------------------------------

function AegisPageFactions:onlineDot(x, y, name)
    local c = Aegis.col
    Aegis.roundRect(self, x, y + 4, 7, 7, 3, 1, self.online[name] and c.ok or c.muted)
end

function AegisPageFactions:drawFaction(f, dx, dw, pad)
    local c = Aegis.col
    local x = dx + 14
    local yy = pad + 12
    local lineH = Aegis.fontH(UIFont.Small) + 4

    Aegis.roundRect(self, x, yy + 4, 14, 14, 4, 1, f.displayColor)
    local header = f.name
    if f.tag ~= "" then header = "[" .. f.tag .. "] " .. f.name end
    Aegis.text(self, Aegis.fitText(header, UIFont.Large, dw - 48), x + 22, yy - 4, UIFont.Large, c.text)
    yy = yy + Aegis.fontH(UIFont.Large) + 4
    Aegis.icon(self, "crown", x, yy + 2, 12, 1, c.gold)
    self:onlineDot(x + 18, yy, f.owner)
    Aegis.text(self, f.owner, x + 32, yy, UIFont.Small, c.text)
    yy = yy + lineH + 2
    Aegis.text(self, getText("UI_Aegis_FactionMembers") .. ": " .. (#f.members + 1)
        .. "    " .. getText("UI_Aegis_FactionSafehouses") .. ": " .. f.shCount, x, yy, UIFont.Small, c.muted)
    yy = yy + lineH + 12

    -- two columns: members left, member safehouses right
    local col2 = dx + math.floor(dw * 0.45)
    local bottom = self.height - pad - 16
    Aegis.text(self, getText("UI_Aegis_FactionMembers"), x, yy, UIFont.Small, c.gold)
    Aegis.text(self, getText("UI_Aegis_FactionSafehouses"), col2, yy, UIFont.Small, c.gold)
    local top = yy + lineH + 4

    local names = { f.owner }
    for _, n in ipairs(f.members) do table.insert(names, n) end
    local sy = top
    for i, n in ipairs(names) do
        if sy + lineH > bottom then
            Aegis.text(self, "+" .. (#names - i + 1), x + 14, sy, UIFont.Small, c.muted)
            break
        end
        self:onlineDot(x, sy, n)
        local nx = x + 14
        if i == 1 then
            Aegis.icon(self, "crown", nx, sy + 2, 11, 1, c.gold)
            nx = nx + 16
        end
        Aegis.text(self, Aegis.fitText(n, UIFont.Small, col2 - nx - 16), nx, sy, UIFont.Small, self.online[n] and c.text or c.muted)
        sy = sy + lineH
    end

    sy = top
    local shs = self:factionSafehouses(f)
    if #shs == 0 then
        Aegis.text(self, getText("UI_Aegis_FactionNoSafehouse"), col2, sy, UIFont.Small, c.muted)
    end
    for i, e in ipairs(shs) do
        if sy + lineH * 2 > bottom then
            Aegis.text(self, "+" .. (#shs - i + 1), col2, sy, UIFont.Small, c.muted)
            break
        end
        Aegis.text(self, Aegis.fitText(shName(e), UIFont.Small, dx + dw - col2 - 14), col2, sy, UIFont.Small, c.text)
        Aegis.text(self, coordText(e), col2 + 12, sy + lineH, UIFont.Small, c.goldDim)
        sy = sy + lineH * 2 + 2
    end
end

function AegisPageFactions:drawSafehouse(e, dx, dw, pad)
    local c = Aegis.col
    local x = dx + 14
    local yy = pad + 12
    local lineH = Aegis.fontH(UIFont.Small) + 4

    Aegis.text(self, Aegis.fitText(shName(e), UIFont.Large, dw - 28), x, yy - 4, UIFont.Large, c.text)
    yy = yy + Aegis.fontH(UIFont.Large) + 4
    Aegis.text(self, coordText(e) .. "  (" .. (e.w * e.h) .. " " .. getText("UI_Aegis_ZoneTiles") .. ")", x, yy, UIFont.Small, c.goldDim)
    yy = yy + lineH
    if e.annex then
        Aegis.text(self, getText("UI_Aegis_FactionAnnex"), x, yy, UIFont.Small, c.muted)
        yy = yy + lineH
    end
    local faction = self:factionOf(e.owner)
    Aegis.icon(self, "crown", x, yy + 2, 12, 1, c.gold)
    self:onlineDot(x + 18, yy, e.owner)
    local ownerLine = e.owner
    if faction then
        ownerLine = ownerLine .. "  [" .. (faction.tag ~= "" and faction.tag or faction.name) .. "]"
    end
    Aegis.text(self, Aegis.fitText(ownerLine, UIFont.Small, dw - 46), x + 32, yy, UIFont.Small, c.text)
    yy = yy + lineH + 12

    Aegis.text(self, getText("UI_Aegis_FactionMembers"), x, yy, UIFont.Small, c.gold)
    yy = yy + lineH + 4
    -- reserve room for whichever buttons are actually showing: jump alone,
    -- release alone (teleport rights only vs. zone rights only), both, or
    -- neither
    local reserve = 16
    if self.jumpBtn and self.jumpBtn:isVisible() then reserve = 60 end
    if self.releaseBtn and self.releaseBtn:isVisible() then reserve = math.max(reserve, 106) end
    local bottom = self.height - pad - reserve
    for i, n in ipairs(e.players) do
        if yy + lineH > bottom then
            Aegis.text(self, "+" .. (#e.players - i + 1), x + 14, yy, UIFont.Small, c.muted)
            break
        end
        self:onlineDot(x, yy, n)
        local nx = x + 14
        if n == e.owner then
            Aegis.icon(self, "crown", nx, yy + 2, 11, 1, c.gold)
            nx = nx + 16
        end
        Aegis.text(self, Aegis.fitText(n, UIFont.Small, dw - (nx - dx) - 14), nx, yy, UIFont.Small, self.online[n] and c.text or c.muted)
        yy = yy + lineH
    end
end

function AegisPageFactions:prerender()
    local c = Aegis.col
    local pad, innerH, factionH, shTop = layout(self)

    Aegis.roundFrame(self, pad, pad, LIST_W, factionH, 10, 1, c.line, c.panel)
    Aegis.icon(self, "players", pad + 14, pad + 12, 15, 1, c.gold)
    Aegis.text(self, getText("UI_Aegis_NavFactions"), pad + 36, pad + 10, UIFont.Medium, c.text)

    Aegis.roundFrame(self, pad, shTop, LIST_W, pad + innerH - shTop, 10, 1, c.line, c.panel)
    Aegis.icon(self, "home", pad + 14, shTop + 10, 15, 1, c.gold)
    Aegis.text(self, getText("UI_Aegis_FactionSafehouses"), pad + 36, shTop + 8, UIFont.Medium, c.text)

    local dx = pad + LIST_W + 20
    local dw = self.width - dx - pad
    Aegis.roundFrame(self, dx, pad, dw, innerH, 10, 1, c.line, c.panel)

    local f = self:selectedFaction()
    local sh = self:selectedSafehouse()
    if f then
        self:drawFaction(f, dx, dw, pad)
    elseif sh then
        self:drawSafehouse(sh, dx, dw, pad)
    elseif #self.factions == 0 and #self.safehouses == 0 then
        -- solo usually has no factions, show a hint instead of empty space
        Aegis.textCentre(self, getText("UI_Aegis_FactionNone"), dx + math.floor(dw / 2), math.floor(self.height / 2) - 20, UIFont.Medium, c.muted)
        Aegis.textCentre(self, getText("UI_Aegis_FactionNoneHint"), dx + math.floor(dw / 2), math.floor(self.height / 2) + 6, UIFont.Small, c.muted)
    else
        Aegis.textCentre(self, getText("UI_Aegis_NoSelection"), dx + math.floor(dw / 2), math.floor(self.height / 2), UIFont.Medium, c.muted)
    end
end

-- server responses, in solo they arrive via the same event path
Events.OnServerCommand.Add(function(module, command, args)
    if module ~= "AegisAdmin" then return end
    local page = AegisPageFactions.instance
    if command == "factionList" then
        if page and args then page:setData(args) end
    elseif command == "shRelease" then
        if not page then return end
        if args and args.ok then
            -- "stuck" means Knox Claim still holds the property, so its own
            -- upkeep puts the zone back shortly. Reporting plain success
            -- there is a lie the admin only discovers minutes later
            Aegis.showToast(getText(args.knox == "stuck"
                and "UI_Aegis_FactionReleaseKnox" or "UI_Aegis_FactionReleaseDone"))
            page.shList.selected = -1
            page:updateButtons()
            page:request()
        else
            Aegis.showToast(getText("UI_Aegis_FactionReleaseFailed"))
        end
    end
end)

-- request fresh on every faction change while the page is open
Events.SyncFaction.Add(function()
    local page = AegisPageFactions.instance
    if page and page:isVisible() and AegisWindow.instance then
        page:request()
    end
end)

AegisWindow.registerPage({
    id = "factions",
    icon = "home",
    label = "UI_Aegis_NavFactions",
    create = AegisPageFactions.create,
})
