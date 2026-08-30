-- Inventory manager: view, take and delete the target player's items,
-- hand over own items. MP goes through the vanilla InvMng channel, solo is direct.
require "Aegis/AegisTheme"
require "Aegis/AegisWidgets"
require "ISUI/ISScrollingListBox"

AegisInventory = ISPanel:derive("AegisInventory")
AegisInventory.instance = nil

local ROW_H = 30
local CARD_W = 760
local CARD_H = 540
local LIST_W = 330

function AegisInventory.show(username, onlineID, displayName)
    local p = getPlayer()
    if not p or not Aegis.allowed(p) or not Aegis.canSee("players") then return end
    if AegisInventory.instance then
        AegisInventory.instance:closeSelf()
    end
    -- the vanilla window shares the same receive channel, must not run in parallel
    if ISPlayerStatsManageInvUI and ISPlayerStatsManageInvUI.instance then
        pcall(function() ISPlayerStatsManageInvUI.Close() end)
    end
    local sw, sh = getCore():getScreenWidth(), getCore():getScreenHeight()
    local o = ISPanel:new(0, 0, sw, sh)
    setmetatable(o, AegisInventory)
    AegisInventory.__index = AegisInventory
    o.background = true
    o.backgroundColor = { r = 0, g = 0, b = 0, a = 0.55 }
    o.borderColor = { r = 0, g = 0, b = 0, a = 0 }
    o.username = username
    o.onlineID = onlineID or -1
    o.displayName = displayName or username
    o.solo = not isClient()
    o.isSelf = o.solo or (getPlayer() and getPlayer():getUsername() == username)
    -- on narrow windows push right-aligned so the close button stays visible
    o.cardX = math.min(math.floor((sw - CARD_W) / 2), sw - CARD_W)
    o.cardY = math.max(0, math.floor((sh - CARD_H) / 2))
    o:initialise()
    o:addToUIManager()
    o:setAlwaysOnTop(true)
    AegisInventory.instance = o
    return o
end

function AegisInventory:closeSelf()
    self:removeFromUIManager()
    if AegisInventory.instance == self then
        AegisInventory.instance = nil
    end
end

function AegisInventory:createChildren()
    local cx, cy = self.cardX, self.cardY

    self.closeBtn = AegisButton:new(cx + CARD_W - 42, cy + 12, 30, 30, nil, "close", self, AegisInventory.closeSelf)
    self.closeBtn.radius = 15
    self:addChild(self.closeBtn)

    self.refreshBtn = AegisButton:new(cx + CARD_W - 42 - 38, cy + 12, 30, 30, nil, "refresh", self, AegisInventory.refreshAll)
    self.refreshBtn.radius = 15
    self:addChild(self.refreshBtn)

    -- left: target's inventory
    self.targetList = ISScrollingListBox:new(cx + 16, cy + 82, LIST_W, CARD_H - 82 - 74)
    self.targetList:initialise()
    self.targetList:instantiate()
    self.targetList.itemheight = ROW_H
    self.targetList.drawBorder = false
    self.targetList.backgroundColor = { r = 0, g = 0, b = 0, a = 0 }
    self.targetList.doDrawItem = AegisInventory.drawRow
    self:addChild(self.targetList)

    local bw = math.floor((LIST_W - 12) / 2)
    if not self.isSelf then
        self.takeBtn = AegisButton:new(cx + 16, cy + CARD_H - 52, bw, 34, getText("UI_Aegis_TakeItem"), "bring", self, AegisInventory.onTake)
        self:addChild(self.takeBtn)
        self.deleteBtn = AegisButton:new(cx + 16 + bw + 12, cy + CARD_H - 52, bw, 34, getText("UI_Aegis_DeleteItem"), "trash", self, AegisInventory.onDelete)
    else
        self.deleteBtn = AegisButton:new(cx + 16, cy + CARD_H - 52, LIST_W, 34, getText("UI_Aegis_DeleteItem"), "trash", self, AegisInventory.onDelete)
    end
    self.deleteBtn.style = "danger"
    self:addChild(self.deleteBtn)

    -- right: own inventory for handing over, only useful for a foreign target
    if not self.isSelf then
        local mx = cx + CARD_W - 16 - LIST_W
        self.myList = ISScrollingListBox:new(mx, cy + 82, LIST_W, CARD_H - 82 - 74)
        self.myList:initialise()
        self.myList:instantiate()
        self.myList.itemheight = ROW_H
        self.myList.drawBorder = false
        self.myList.backgroundColor = { r = 0, g = 0, b = 0, a = 0 }
        self.myList.doDrawItem = AegisInventory.drawRow
        self:addChild(self.myList)

        self.giveBtn = AegisButton:new(mx, cy + CARD_H - 52, LIST_W, 34, getText("UI_Aegis_GiveOwn"), "items", self, AegisInventory.onGiveOwn)
        self.giveBtn.style = "gold"
        self:addChild(self.giveBtn)
    end

    self:refreshAll()
end

-- ------------------------------------------------------------------
-- Data
-- ------------------------------------------------------------------

-- group own/local inventory by full type
local function groupedLocalItems(inv)
    local map = {}
    local rows = {}
    local items = inv:getItems()
    for i = 0, items:size() - 1 do
        local it = items:get(i)
        local full = it:getFullType()
        local rec = map[full]
        if not rec then
            rec = {
                fullType = full,
                name = it:getDisplayName() or it:getName(),
                tex = it:getTex(),
                count = 0,
                refs = {},
            }
            map[full] = rec
            table.insert(rows, rec)
        end
        rec.count = rec.count + 1
        table.insert(rec.refs, it)
    end
    table.sort(rows, function(a, b) return a.name < b.name end)
    return rows
end

function AegisInventory:refreshAll()
    if self.solo then
        self:fillList(self.targetList, groupedLocalItems(getPlayer():getInventory()))
    else
        sendRequestInventory(tonumber(self.onlineID) or -1, tostring(self.username))
        if self.myList then
            self:fillList(self.myList, groupedLocalItems(getPlayer():getInventory()))
        end
    end
end

function AegisInventory:fillList(list, rows)
    list:clear()
    list.selected = -1
    for _, rec in ipairs(rows) do
        list:addItem(rec.name, rec)
    end
end

-- server response to sendRequestInventory
function AegisInventory.receiveItems(itemtable)
    local self = AegisInventory.instance
    if not self or self.solo then return end
    local rows = {}
    -- besides the items the table also carries capacityWeight/maxWeight as numbers
    for _, v in pairs(itemtable) do
        if type(v) == "table" and v.fullType then
            table.insert(rows, {
                fullType = v.fullType,
                itemId = v.itemId,
                name = getItemName(v.fullType) or v.fullType,
                tex = getItemTex(v.fullType),
                count = tonumber(v.count) or 1,
            })
        end
    end
    table.sort(rows, function(a, b) return a.name < b.name end)
    self:fillList(self.targetList, rows)
end

Events.MngInvReceiveItems.Add(AegisInventory.receiveItems)

-- ------------------------------------------------------------------
-- Actions
-- ------------------------------------------------------------------

local function selectedRec(list)
    local item = list and list.items[list.selected]
    return item and item.item or nil
end

-- the server resolves Take/Remove ONLY via the online ID, no username
-- fallback; look it up fresh when outside streaming range
function AegisInventory:resolveID()
    if self.onlineID and self.onlineID >= 0 then return true end
    local p = getPlayerFromUsername(self.username)
    if p then
        self.onlineID = p:getOnlineID()
        return true
    end
    Aegis.showToast(getText("UI_Aegis_OutOfRange"))
    return false
end

function AegisInventory.onTake(self)
    local rec = selectedRec(self.targetList)
    if not rec or self.solo then return end
    if not self:resolveID() then return end
    -- vanilla pattern: pull stacks by full type, single items by item ID
    if rec.count > 1 then
        InvMngGetItem(0, rec.fullType, self.onlineID, self.username)
    else
        InvMngGetItem(rec.itemId, nil, self.onlineID, self.username)
    end
    Aegis.logAction("players", "Item taken by " .. self.username .. ": " .. rec.fullType)
    self:refreshAll()
end

function AegisInventory.onDelete(self)
    local rec = selectedRec(self.targetList)
    if not rec then return end
    if self.solo then
        local it = rec.refs and rec.refs[1]
        if it then
            local p = getPlayer()
            pcall(function() p:removeWornItem(it, false) end)
            pcall(function() p:removeFromHands(it) end)
            p:getInventory():Remove(it)
        end
        self:refreshAll()
    else
        if not self:resolveID() then return end
        InvMngRemoveItem(rec.itemId, self.onlineID, self.username)
        self:refreshAll()
    end
    Aegis.logAction("players", "Item deleted from " .. self.username .. ": " .. rec.fullType)
end

-- escape quotes and backslashes, otherwise a player name can break out
-- of the /additem command or inject extra commands
local function escapeCmdArg(s)
    return tostring(s or ""):gsub("\\", "\\\\"):gsub("\"", "\\\"")
end

function AegisInventory.onGiveOwn(self)
    local rec = selectedRec(self.myList)
    if not rec or self.solo then return end
    -- real transfer: spawn a copy on the target, remove the own copy
    SendCommandToServer("/additem \"" .. escapeCmdArg(self.username) .. "\" \"" .. escapeCmdArg(rec.fullType) .. "\"")
    local it = rec.refs and rec.refs[1]
    if it then
        local p = getPlayer()
        local inv = p:getInventory()
        pcall(function() p:removeWornItem(it, false) end)
        pcall(function() p:removeFromHands(it) end)
        inv:Remove(it)
        sendRemoveItemFromContainer(inv, it)
    end
    Aegis.logAction("players", "Own item handed to " .. self.username .. ": " .. rec.fullType)
    self:refreshAll()
end

-- ------------------------------------------------------------------
-- Rendering
-- ------------------------------------------------------------------

function AegisInventory.drawRow(list, y, item, alt)
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
    if rec.tex then
        list:drawTextureScaledAspect2(rec.tex, 10, y + math.floor((ROW_H - 22) / 2), 22, 22, 1, 1, 1, 1)
    end
    local nameW = list:getWidth() - 42 - 56
    if rec._fitW ~= nameW then
        rec._fitW = nameW
        rec._fit = Aegis.fitText(rec.name, UIFont.Small, nameW)
    end
    Aegis.text(list, rec._fit, 42, y + math.floor((ROW_H - Aegis.fontH(UIFont.Small)) / 2), UIFont.Small, sel and c.text or c.muted)
    if rec.count and rec.count > 1 then
        Aegis.textRight(list, "x" .. tostring(rec.count), list:getWidth() - 12, y + math.floor((ROW_H - Aegis.fontH(UIFont.Small)) / 2), UIFont.Small, c.goldHi)
    end
    return y + ROW_H
end

function AegisInventory:prerender()
    ISPanel.prerender(self)
    local c = Aegis.col
    local cx, cy = self.cardX, self.cardY

    Aegis.shadow(self, cx, cy, CARD_W, CARD_H, 30, 0.7)
    Aegis.roundFrame(self, cx, cy, CARD_W, CARD_H, 12, 1, c.line, c.bg)
    Aegis.icon(self, "items", cx + 18, cy + 16, 18, 1, c.gold)
    Aegis.text(self, getText("UI_Aegis_InvTitle", self.displayName), cx + 46, cy + 14, UIFont.Medium, c.text)

    Aegis.text(self, getText("UI_Aegis_TargetInv"), cx + 16, cy + 56, UIFont.Small, c.muted)
    Aegis.roundFrame(self, cx + 14, cy + 78, LIST_W + 4, CARD_H - 78 - 70, 8, 1, c.line, c.panel)
    if #self.targetList.items == 0 then
        Aegis.textCentre(self, getText("UI_Aegis_InvEmpty"), cx + 16 + math.floor(LIST_W / 2), cy + 200, UIFont.Small, c.muted)
    end

    if self.myList then
        local mx = cx + CARD_W - 16 - LIST_W
        Aegis.text(self, getText("UI_Aegis_MyInv"), mx, cy + 56, UIFont.Small, c.muted)
        Aegis.roundFrame(self, mx - 2, cy + 78, LIST_W + 4, CARD_H - 78 - 70, 8, 1, c.line, c.panel)
    end
end

function AegisInventory:onMouseDown(x, y)
    -- swallow clicks on the dim background
end
