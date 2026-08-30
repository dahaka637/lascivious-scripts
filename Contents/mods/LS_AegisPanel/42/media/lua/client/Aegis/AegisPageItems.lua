-- Item spawner: search across all definitions, icons, quantity, target player
require "Aegis/AegisWindow"
require "ISUI/ISScrollingListBox"
require "ISUI/ISTextEntryBox"
require "ISUI/ISComboBox"

AegisPageItems = ISPanel:derive("AegisPageItems")

local ROW_H = 36
local MAX_ROWS = 400
local MAX_QTY = 100

function AegisPageItems.create(window, x, y, w, h)
    local o = ISPanel:new(x, y, w, h)
    setmetatable(o, AegisPageItems)
    AegisPageItems.__index = AegisPageItems
    o.background = false
    o.window = window
    o.allItems = nil
    o.categories = nil
    o.filtered = {}
    o.qty = 1
    o.recent = {}
    o.cart = {}
    o.truncated = false
    return o
end

-- ------------------------------------------------------------------
-- Data base: read all script items once
-- ------------------------------------------------------------------

-- every item script carries the mod it was loaded from (getModID on the
-- script side, the engine fills it per file while loading). Vanilla items
-- answer with the constant below
local VANILLA_MOD = "pz-vanilla"

local function modLabel(id)
    if id == VANILLA_MOD then return "Project Zomboid" end
    local label = id
    local info = getModInfoByID(id)
    local name = info and info:getName()
    if name and name ~= "" then label = name end
    return label
end

function AegisPageItems:buildCache()
    if self.allItems then return end
    self.allItems = {}
    local seen = {}
    local cats = {}
    local mods, modNames = {}, {}
    local list = getScriptManager():getAllItems()
    for i = 0, list:size() - 1 do
        local it = list:get(i)
        if not it:getObsolete() and not it:isHidden() then
            local cat = it:getDisplayCategory()
            local mod = it:getModID() or VANILLA_MOD
            if not modNames[mod] then
                modNames[mod] = modLabel(mod)
                table.insert(mods, mod)
            end
            local rec = {
                display = it:getDisplayName() or it:getName(),
                full = it:getFullName(),
                icon = it:getIcon(),
                iconsFor = it:getIconsForTexture(),
                cat = cat,
                mod = mod,
                modLabel = modNames[mod],
            }
            -- the mod name searches along, so typing "filibuster" finds
            -- the whole mod without touching the filter
            rec.search = string.lower(rec.display .. " " .. rec.full .. " " .. rec.modLabel)
            table.insert(self.allItems, rec)
            if cat and not seen[cat] then
                seen[cat] = true
                table.insert(cats, cat)
            end
        end
    end
    table.sort(self.allItems, function(a, b) return a.display < b.display end)
    table.sort(cats, function(a, b)
        return self.catLabel(a) < self.catLabel(b)
    end)
    self.categories = cats
    -- vanilla first, the rest by display name
    table.sort(mods, function(a, b)
        if a == VANILLA_MOD then return true end
        if b == VANILLA_MOD then return false end
        return modNames[a] < modNames[b]
    end)
    self.mods = mods
    self.modNames = modNames
end

function AegisPageItems.catLabel(cat)
    local label = getTextOrNull("IGUI_ItemCat_" .. cat)
    return label or cat
end

-- resolve icon texture lazily on first draw, precedence like the vanilla viewer
local function resolveIcon(rec)
    if rec.tex ~= nil then return rec.tex end
    local icon = rec.icon
    if rec.iconsFor and rec.iconsFor:size() > 0 then
        icon = rec.iconsFor:get(0)
    end
    rec.tex = icon and tryGetTexture("Item_" .. icon) or false
    return rec.tex
end

-- ------------------------------------------------------------------
-- Layout
-- ------------------------------------------------------------------

function AegisPageItems:createChildren()
    local pad = 20
    local innerX = pad + 14
    local innerW = self.width - innerX * 2

    self.search = ISTextEntryBox:new("", innerX, pad + 44, math.floor(innerW * 0.34), 26)
    self.search:initialise()
    self.search:instantiate()
    self.search.font = UIFont.Small
    self.search:setClearButton(true)
    self.search.backgroundColor = { r = Aegis.col.dark.r, g = Aegis.col.dark.g, b = Aegis.col.dark.b, a = 1 }
    self.search.borderColor = { r = Aegis.col.line.r, g = Aegis.col.line.g, b = Aegis.col.line.b, a = 1 }
    local page = self
    self.search.onTextChange = function() page:applyFilter() end
    self:addChild(self.search)

    self.catCombo = ISComboBox:new(innerX + self.search.width + 12, pad + 44, math.floor(innerW * 0.21), 26, self, AegisPageItems.applyFilter)
    self.catCombo:initialise()
    self:addChild(self.catCombo)

    -- source mod filter (community request). Always visible, even when
    -- vanilla is the only entry: hiding it left a hole in the filter row
    -- that read as something broken
    self.modCombo = ISComboBox:new(self.catCombo:getRight() + 12, pad + 44, math.floor(innerW * 0.21), 26, self, AegisPageItems.applyFilter)
    self.modCombo:initialise()
    self:addChild(self.modCombo)

    if isClient() then
        self.targetCombo = ISComboBox:new(self.modCombo:getRight() + 12, pad + 44, innerW - self.search.width - self.catCombo.width - self.modCombo.width - 36, 26, self, nil)
        self.targetCombo:initialise()
        self:addChild(self.targetCombo)
    end

    self.list = ISScrollingListBox:new(innerX, pad + 118, innerW, self.height - pad - 60 - (pad + 118 - pad))
    -- measured from the bottom: frame border at H-20, chips need 22px
    -- plus margin, buttons 32px plus gaps. 112 leaves chips ending at
    -- H-32, comfortably inside the border
    self.list:setHeight(self.height - (pad + 118) - 112)
    self.list:initialise()
    self.list:instantiate()
    self.list.itemheight = ROW_H
    self.list.drawBorder = false
    self.list.backgroundColor = { r = 0, g = 0, b = 0, a = 0 }
    self.list.doDrawItem = AegisPageItems.drawItemRow
    self:addChild(self.list)

    -- quantity chips, cart and give buttons below the list
    local by = self.list:getBottom() + 16
    local qx = innerX
    self.qtyButtons = {}
    for _, q in ipairs({ 1, 5, 10, 25 }) do
        local btn = AegisButton:new(qx, by, 44, 32, tostring(q), nil, self, function(p, b) p:setQty(b.qtyValue) end)
        btn.qtyValue = q
        btn.radius = 16
        self:addChild(btn)
        table.insert(self.qtyButtons, btn)
        qx = qx + 52
    end
    self.cartBtn = AegisButton:new(innerX + innerW - 460, by, 150, 32, getText("UI_Aegis_AddToCart"), "plus", self, AegisPageItems.onAddCart)
    self:addChild(self.cartBtn)
    self.cartGiveBtn = AegisButton:new(innerX + innerW - 302, by, 150, 32, getText("UI_Aegis_GiveCart"), "check", self, function(p)
        if #p.cart > 0 then p:sendCart() end
    end)
    self:addChild(self.cartGiveBtn)
    self.giveBtn = AegisButton:new(innerX + innerW - 144, by, 144, 32, getText("UI_Aegis_Give"), "items", self, AegisPageItems.onGive)
    self.giveBtn.style = "gold"
    self:addChild(self.giveBtn)

    self:setQty(1)
end

-- a resize rebuilds the page; the cart is session state the admin is
-- actively filling, losing it on a window drag reads as a bug
function AegisPageItems:saveState()
    local sel = self.list.items[self.list.selected]
    return {
        cart = self.cart, qty = self.qty,
        search = self.search and self.search:getInternalText() or "",
        selectedFull = sel and sel.item and sel.item.full or nil,
    }
end

function AegisPageItems:restoreState(state)
    if type(state) ~= "table" then return end
    if type(state.cart) == "table" then self.cart = state.cart end
    if tonumber(state.qty) then self:setQty(tonumber(state.qty)) end
    if self.search and type(state.search) == "string" and state.search ~= "" then
        self.search:setText(state.search)
    end
    self:applyFilter()
    if state.selectedFull then
        for i, item in ipairs(self.list.items) do
            if item.item and item.item.full == state.selectedFull then
                self.list.selected = i
                break
            end
        end
    end
end

-- Cart: collect entries and hand them out in one logged batch
function AegisPageItems:onAddCart()
    local item = self.list.items[self.list.selected]
    if not item then return end
    local rec = item.item
    for _, pos in ipairs(self.cart) do
        if pos.full == rec.full then
            pos.count = math.min(MAX_QTY, pos.count + self.qty)
            self:cartToast()
            return
        end
    end
    table.insert(self.cart, { full = rec.full, display = rec.display, count = math.min(MAX_QTY, self.qty) })
    self:cartToast()
end

function AegisPageItems:cartToast()
    local n = 0
    for _, pos in ipairs(self.cart) do n = n + pos.count end
    Aegis.showToast(getText("UI_Aegis_CartCount") .. " " .. #self.cart .. " (" .. n .. ")")
end

function AegisPageItems:sendCart()
    if #self.cart == 0 then return end
    local target = self:targetUsername()
    local items = {}
    for _, pos in ipairs(self.cart) do
        table.insert(items, { fullType = pos.full, count = pos.count })
    end
    if isClient() then
        sendClientCommand(getPlayer(), "AegisAdmin", "giveItems", { target = target, items = items })
    else
        local inv = getPlayer():getInventory()
        local parts = {}
        for _, pos in ipairs(self.cart) do
            for i = 1, pos.count do
                local obj = instanceItem(pos.full)
                if obj then
                    if obj:getType() == "CorpseAnimal" then obj:createAndStoreDefaultDeadBody(nil) end
                    inv:AddItem(obj)
                end
            end
            table.insert(parts, pos.full .. " x" .. pos.count)
        end
        -- the solo direct path never reaches the giveItems handler, log via relay
        Aegis.logAction("items", "Cart handout: " .. table.concat(parts, ", "))
        Aegis.showToast(getText("UI_Aegis_ItemsGiven"))
    end
    self.cart = {}
end

function AegisPageItems:selectTargetUsername(name)
    if not self.targetCombo then return end
    for i, opt in ipairs(self.targetCombo.options) do
        if opt == name then
            self.targetCombo.selected = i
            return
        end
    end
end

function AegisPageItems:setQty(q)
    self.qty = q
    for _, btn in ipairs(self.qtyButtons) do
        btn.style = (btn.qtyValue == q) and "gold" or "ghost"
    end
end

function AegisPageItems:onShow()
    self:buildCache()
    if not self.catCombo.options or #self.catCombo.options == 0 then
        self.catCombo:addOption(getText("UI_Aegis_All"))
        for _, cat in ipairs(self.categories) do
            self.catCombo:addOption(self.catLabel(cat))
        end
        self.catCombo.selected = 1
        self.modCombo:addOption(getText("UI_Aegis_ItemsAllMods"))
        for _, mod in ipairs(self.mods) do
            self.modCombo:addOption(self.modNames[mod])
        end
        self.modCombo.selected = 1
        self:applyFilter()
    end
    if self.targetCombo then
        local prev = self.targetCombo.options[self.targetCombo.selected]
        self.targetCombo:clear()
        self.targetCombo:addOption(getText("UI_Aegis_Me"))
        for _, row in ipairs(Aegis.scoreboard or {}) do
            local me = getPlayer() and getPlayer():getUsername()
            if row.username ~= me then
                self.targetCombo:addOption(row.username)
            end
        end
        self.targetCombo.selected = 1
        if prev then
            for i, opt in ipairs(self.targetCombo.options) do
                if opt == prev then self.targetCombo.selected = i end
            end
        end
    end
end

-- ------------------------------------------------------------------
-- Filter
-- ------------------------------------------------------------------

function AegisPageItems:applyFilter()
    self:buildCache()
    local needle = string.lower(self.search:getInternalText() or "")
    local catIndex = self.catCombo.selected or 1
    local wantCat = nil
    if catIndex > 1 and self.categories[catIndex - 1] then
        wantCat = self.categories[catIndex - 1]
    end
    local modIndex = self.modCombo and self.modCombo.selected or 1
    local wantMod = nil
    if modIndex > 1 and self.mods and self.mods[modIndex - 1] then
        wantMod = self.mods[modIndex - 1]
    end

    -- keep the selection glued to the ITEM, not the row index: after a
    -- new search the old index points at a different row and the cart
    -- button would add whatever sits there now
    local keep = self.list.items[self.list.selected]
    local keepFull = keep and keep.item and keep.item.full or nil
    self.list:clear()
    self.list.selected = -1
    self.truncated = false
    local shown = 0
    for _, rec in ipairs(self.allItems) do
        local okCat = (wantCat == nil) or (rec.cat == wantCat)
        local okMod = (wantMod == nil) or (rec.mod == wantMod)
        if okCat and okMod and (needle == "" or string.find(rec.search, needle, 1, true)) then
            shown = shown + 1
            if shown > MAX_ROWS then
                self.truncated = true
                break
            end
            self.list:addItem(rec.display, rec)
            if keepFull and rec.full == keepFull then
                self.list.selected = #self.list.items
            end
        end
    end
end

function AegisPageItems.drawItemRow(list, y, item, alt)
    local c = Aegis.col
    local sel = list.selected == item.index
    local hover = list.mouseoverselected == item.index
    if sel then
        Aegis.roundRect(list, 2, y + 1, list:getWidth() - 4, ROW_H - 2, 8, 1, c.card)
        Aegis.roundRect(list, 2, y + 8, 3, ROW_H - 16, 1, 1, c.gold)
    elseif hover then
        Aegis.roundRect(list, 2, y + 1, list:getWidth() - 4, ROW_H - 2, 8, 0.5, c.card)
    end
    local rec = item.item
    local tex = resolveIcon(rec)
    if tex then
        list:drawTextureScaledAspect2(tex, 12, y + math.floor((ROW_H - 24) / 2), 24, 24, 1, 1, 1, 1)
    end
    local nameW = list:getWidth() - 48 - 240
    if rec._fitW ~= nameW then
        rec._fitW = nameW
        rec._fit = Aegis.fitText(rec.display, UIFont.Small, nameW)
        -- source mod behind the name, same pattern as the kit origin
        -- tags: only for mod items, a "Project Zomboid" on every vanilla
        -- row would just be noise. Dropped when the name leaves no room
        rec._modX = nil
        if rec.mod ~= "pz-vanilla" then
            local used = Aegis.strW(UIFont.Small, rec._fit)
            local room = nameW - used - 10
            if room > 30 then
                rec._modX = 48 + used + 10
                rec._modFit = Aegis.fitText(rec.modLabel, UIFont.Small, room)
            end
        end
    end
    local textY = y + math.floor((ROW_H - Aegis.fontH(UIFont.Small)) / 2)
    Aegis.text(list, rec._fit, 48, textY, UIFont.Small, sel and c.text or c.muted)
    if rec._modX then
        Aegis.text(list, rec._modFit, rec._modX, textY, UIFont.Small, c.goldDim)
    end
    Aegis.textRight(list, rec.full, list:getWidth() - 14, textY, UIFont.Small, c.goldDim)
    return y + ROW_H
end

-- ------------------------------------------------------------------
-- Give
-- ------------------------------------------------------------------

function AegisPageItems:targetUsername()
    if not isClient() then return nil end
    if not self.targetCombo or (self.targetCombo.selected or 1) == 1 then
        return getPlayer():getUsername()
    end
    return self.targetCombo.options[self.targetCombo.selected]
end

function AegisPageItems.onGive(self)
    local item = self.list.items[self.list.selected]
    if not item then return end
    self:give(item.item)
end

function AegisPageItems:give(rec)
    local count = math.min(self.qty, MAX_QTY)
    if isClient() then
        -- one logged server command instead of an /additem loop
        sendClientCommand(getPlayer(), "AegisAdmin", "giveItems", {
            target = self:targetUsername(),
            items = { { fullType = rec.full, count = count } },
        })
    else
        local inv = getPlayer():getInventory()
        for i = 1, count do
            local obj = instanceItem(rec.full)
            if obj then
                -- animal corpses need a body, pattern from ISItemsListTable
                if obj:getType() == "CorpseAnimal" then
                    obj:createAndStoreDefaultDeadBody(nil)
                end
                inv:AddItem(obj)
            end
        end
        -- the solo direct path never reaches the giveItems handler, log via relay
        Aegis.logAction("items", "Item given: " .. rec.full .. " x" .. count)
        Aegis.showToast(getText("UI_Aegis_ItemsGiven"))
    end
    -- maintain recent history
    for i, r in ipairs(self.recent) do
        if r.full == rec.full then table.remove(self.recent, i) break end
    end
    table.insert(self.recent, 1, rec)
    if #self.recent > 6 then table.remove(self.recent) end
end

-- ------------------------------------------------------------------
-- Frame
-- ------------------------------------------------------------------

function AegisPageItems:prerender()
    local c = Aegis.col
    local pad = 20
    Aegis.roundFrame(self, pad, pad, self.width - pad * 2, self.height - pad * 2, 10, 1, c.line, c.panel)
    Aegis.icon(self, "search", pad + 14, pad + 12, 15, 1, c.gold)
    Aegis.text(self, getText("UI_Aegis_NavItems"), pad + 36, pad + 10, UIFont.Medium, c.text)

    local innerX = pad + 14
    -- recent row
    local ry = pad + 84
    Aegis.text(self, getText("UI_Aegis_Recent"), innerX, ry + 4, UIFont.Small, c.muted)
    local rx = innerX + Aegis.strW(UIFont.Small, getText("UI_Aegis_Recent")) + 12
    self.recentRects = {}
    for _, rec in ipairs(self.recent) do
        local tex = resolveIcon(rec)
        local label = rec.display
        if string.len(label) > 18 then label = string.sub(label, 1, 16) .. ".." end
        local cw = 30 + Aegis.strW(UIFont.Small, label)
        if rx + cw > self.width - pad - 14 then break end
        Aegis.roundFrame(self, rx, ry, cw, 24, 12, 1, c.line, c.card)
        if tex then
            self:drawTextureScaledAspect2(tex, rx + 6, ry + 4, 16, 16, 1, 1, 1, 1)
        end
        Aegis.text(self, label, rx + 26, ry + math.floor((24 - Aegis.fontH(UIFont.Small)) / 2), UIFont.Small, c.text)
        table.insert(self.recentRects, { x = rx, y = ry, w = cw, h = 24, rec = rec })
        rx = rx + cw + 8
    end

    if self.truncated then
        Aegis.textRight(self, getText("UI_Aegis_MoreResults"), self.width - pad - 14, pad + 12, UIFont.Small, c.muted)
    end

    -- quantity label and cart contents
    if self.qtyButtons and self.qtyButtons[1] then
        Aegis.text(self, getText("UI_Aegis_Qty"), innerX, self.qtyButtons[1].y - 18, UIFont.Small, c.muted)
        local n = 0
        for _, pos in ipairs(self.cart) do n = n + pos.count end
        if self.cartGiveBtn then
            self.cartGiveBtn.label = getText("UI_Aegis_GiveCart") .. (n > 0 and (" (" .. n .. ")") or "")
            self.cartGiveBtn.style = n > 0 and "gold" or "ghost"
            self.cartGiveBtn:setEnabled(n > 0)
        end
        -- cart entries as chips, one click removes the entry again
        self.cartRects = {}
        if #self.cart > 0 then
            local cy = self.qtyButtons[1].y + 42
            local cx = innerX + Aegis.strW(UIFont.Small, getText("UI_Aegis_Cart")) + 10
            Aegis.text(self, getText("UI_Aegis_Cart"), innerX, cy + 3, UIFont.Small, c.muted)
            for i, pos in ipairs(self.cart) do
                local label = pos.display .. " x" .. pos.count
                if string.len(label) > 26 then label = string.sub(label, 1, 24) .. ".." end
                local cw = 22 + Aegis.strW(UIFont.Small, label)
                if cx + cw > self.width - pad - 14 then
                    Aegis.text(self, "+" .. tostring(#self.cart - i + 1), cx, cy + 3, UIFont.Small, c.muted)
                    break
                end
                Aegis.roundFrame(self, cx, cy, cw, 22, 11, 1, c.line, c.card)
                Aegis.text(self, label, cx + 8, cy + math.floor((22 - Aegis.fontH(UIFont.Small)) / 2), UIFont.Small, c.goldDim)
                Aegis.icon(self, "close", cx + cw - 14, cy + 6, 9, 0.8, c.muted)
                table.insert(self.cartRects, { x = cx, y = cy, w = cw, h = 22, index = i })
                cx = cx + cw + 8
            end
        end
    end
end

function AegisPageItems:onMouseUp(x, y)
    for _, rect in ipairs(self.cartRects or {}) do
        if x >= rect.x and x <= rect.x + rect.w and y >= rect.y and y <= rect.y + rect.h then
            Aegis.sound()
            table.remove(self.cart, rect.index)
            self:cartToast()
            return
        end
    end
    for _, rect in ipairs(self.recentRects or {}) do
        if x >= rect.x and x <= rect.x + rect.w and y >= rect.y and y <= rect.y + rect.h then
            Aegis.sound()
            self:give(rect.rec)
            return
        end
    end
end

AegisWindow.registerPage({
    id = "items",
    icon = "items",
    label = "UI_Aegis_NavItems",
    create = AegisPageItems.create,
})
