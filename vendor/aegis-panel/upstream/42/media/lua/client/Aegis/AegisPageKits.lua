-- Kit editor of the admin panel: kit list on the left, properties and
-- contents in the middle, item search on the right. The server owns the
-- registry, this page only mirrors its state.
require "Aegis/AegisWindow"
require "ISUI/ISScrollingListBox"
require "ISUI/ISTextEntryBox"

AegisPageKits = ISPanel:derive("AegisPageKits")

local LIST_W = 230
local ROW_H = 44
local ITEM_ROW_H = 28
local SEARCH_ROW_H = 30
local ROLE_ROW_H = 24
local ROLES_H = 96
local MIN_ITEMS_H = 90
local MAX_KIT_ITEMS = 20
local MAX_KIT_ROLES = 16
local MAX_COUNT = 100
local MAX_ROWS = 200
-- pseudo entry of the gate, mirrors AegisKits.BOOSTER_ROLE on the server
local BOOSTER_ROLE = "@booster"

local function modeLine(kit)
    if kit.mode == "once" then return getText("UI_Aegis_KitModeOnce") end
    if kit.mode == "month" then return getText("UI_Aegis_KitModeMonth") end
    return getText("UI_Aegis_KitModeCd") .. " " .. tostring(kit.cooldownH) .. "h"
end

local function displayName(fullType)
    local name = nil
    pcall(function() name = getItemNameFromFullType(fullType) end)
    if type(name) == "string" and name ~= "" then return name end
    local script = getScriptManager():FindItem(fullType)
    if script then name = script:getDisplayName() end
    if type(name) == "string" and name ~= "" then return name end
    return fullType:match("%.(.+)$") or fullType
end

-- icon texture precedence like the vanilla item viewer
local function resolveIcon(rec)
    if rec.tex ~= nil then return rec.tex end
    local icon = rec.icon
    if rec.iconsFor and rec.iconsFor:size() > 0 then
        icon = rec.iconsFor:get(0)
    end
    rec.tex = icon and tryGetTexture("Item_" .. icon) or false
    return rec.tex
end

function AegisPageKits.create(window, x, y, w, h)
    local o = ISPanel:new(x, y, w, h)
    setmetatable(o, AegisPageKits)
    AegisPageKits.__index = AegisPageKits
    o.background = false
    o.window = window
    o.kits = {}
    o.roleNames = {}
    o.selectedId = nil
    -- roles empty = kit open to everyone with kit access
    o.editor = { id = nil, mode = "once", cooldownH = 24, items = {}, roles = {} }
    o.qty = 1
    o.allItems = nil
    AegisPageKits.instance = o
    return o
end

function AegisPageKits:createChildren()
    local pad = 20
    local page = self

    -- left column: kit list plus new button
    self.newBtn = AegisButton:new(pad + 8, self.height - pad - 44, LIST_W - 16, 32, getText("UI_Aegis_KitNew"), "plus", self, AegisPageKits.onNew)
    self.newBtn.style = "gold"
    self:addChild(self.newBtn)

    -- booster administration lives in its own dialog, the three columns
    -- of this page leave no room for a fourth
    self.boostBtn = AegisButton:new(pad + LIST_W - 36, pad + 8, 26, 26, nil, "crown", self, function()
        AegisBoostManager.toggle()
    end)
    self.boostBtn.radius = 13
    self.boostBtn.iconSize = 14
    self.boostBtn.tooltip = getText("UI_Aegis_BoostManage")
    self:addChild(self.boostBtn)

    self.list = ISScrollingListBox:new(pad + 8, pad + 40, LIST_W - 16, self.newBtn.y - 8 - (pad + 40))
    self.list:initialise()
    self.list:instantiate()
    self.list.itemheight = ROW_H
    self.list.drawBorder = false
    self.list.backgroundColor = { r = 0, g = 0, b = 0, a = 0 }
    self.list.doDrawItem = AegisPageKits.drawKitRow
    self.list:setOnMouseDownFunction(self, AegisPageKits.onSelectKit)
    self:addChild(self.list)

    -- middle and right column geometry, frames are drawn in prerender
    self.editorX = pad + LIST_W + 16
    self.colW = math.floor((self.width - self.editorX - pad - 16) / 2)
    self.searchX = self.editorX + self.colW + 16

    -- claim maintenance needs a name list and a wipe button, that gets its
    -- own dialog like the booster administration; the header corner is the
    -- only free spot in this column
    self.claimBtn = AegisButton:new(self.editorX + self.colW - 36, pad + 8, 26, 26, nil, "clock", self, function(p)
        AegisClaimManager.toggle(p.selectedId, p:selectedKitName())
    end)
    self.claimBtn.radius = 13
    self.claimBtn.iconSize = 14
    self.claimBtn.tooltip = getText("UI_Aegis_KitClaimManage")
    self:addChild(self.claimBtn)

    -- middle column: kit properties and contents
    local ex = self.editorX + 14
    local ew = self.colW - 28
    local ey = pad + 44

    self.nameEntry = ISTextEntryBox:new("", ex, ey, ew, 26)
    self.nameEntry:initialise()
    self.nameEntry:instantiate()
    self.nameEntry.font = UIFont.Small
    self.nameEntry:setPlaceholderText(getText("UI_Aegis_KitName"))
    self.nameEntry.backgroundColor = { r = Aegis.col.dark.r, g = Aegis.col.dark.g, b = Aegis.col.dark.b, a = 1 }
    self.nameEntry.borderColor = { r = Aegis.col.line.r, g = Aegis.col.line.g, b = Aegis.col.line.b, a = 1 }
    self:addChild(self.nameEntry)
    ey = ey + 34

    local half = math.floor((ew - 8) / 2)
    local third = math.floor((ew - 16) / 3)
    self.onceBtn = AegisButton:new(ex, ey, third, 28, getText("UI_Aegis_KitModeOnce"), nil, self, function(p) p.editor.mode = "once" end)
    self.onceBtn.radius = 14
    self:addChild(self.onceBtn)
    self.cdBtn = AegisButton:new(ex + third + 8, ey, third, 28, getText("UI_Aegis_KitModeCd"), nil, self, function(p) p.editor.mode = "cd" end)
    self.cdBtn.radius = 14
    self:addChild(self.cdBtn)
    self.monthBtn = AegisButton:new(ex + (third + 8) * 2, ey, ew - (third + 8) * 2, 28,
        getText("UI_Aegis_KitModeMonth"), nil, self, function(p) p.editor.mode = "month" end)
    self.monthBtn.radius = 14
    self:addChild(self.monthBtn)
    ey = ey + 36

    self.hoursY = ey
    self.hoursEntry = ISTextEntryBox:new("24", ex + ew - 70, ey, 70, 26)
    self.hoursEntry:initialise()
    self.hoursEntry:instantiate()
    self.hoursEntry.font = UIFont.Small
    self.hoursEntry:setOnlyNumbers(true)
    self.hoursEntry.backgroundColor = { r = Aegis.col.dark.r, g = Aegis.col.dark.g, b = Aegis.col.dark.b, a = 1 }
    self.hoursEntry.borderColor = { r = Aegis.col.line.r, g = Aegis.col.line.g, b = Aegis.col.line.b, a = 1 }
    self:addChild(self.hoursEntry)
    ey = ey + 34

    -- role gate: multi select, nothing picked means every player with kit
    -- access sees the kit. On short windows the role list gives way first,
    -- the item list keeps a usable height
    local by = self.height - pad - 46
    -- the claim reset gets a row of its own above save and delete, those
    -- two already fill the width
    local cby = by - 40
    local rolesH = ROLES_H
    local short = MIN_ITEMS_H - (cby - 12 - (ey + 20 + rolesH + 10 + 20))
    if short > 0 then rolesH = math.max(ROLE_ROW_H * 2, rolesH - short) end

    self.rolesLabelY = ey
    self.rolesH = rolesH
    self.roleList = ISScrollingListBox:new(ex, ey + 20, ew, rolesH)
    self.roleList:initialise()
    self.roleList:instantiate()
    self.roleList.itemheight = ROLE_ROW_H
    self.roleList.drawBorder = false
    self.roleList.backgroundColor = { r = 0, g = 0, b = 0, a = 0 }
    self.roleList.doDrawItem = AegisPageKits.drawRoleRow
    self:addChild(self.roleList)
    local roleList = self.roleList
    roleList.aegisPage = self
    function roleList:onMouseDown(x, y)
        ISScrollingListBox.onMouseDown(self, x, y)
        local row = self:rowAt(x, y)
        local entry = row and self.items[row]
        if entry and type(entry.item) == "table" then
            self.aegisPage:toggleRole(entry.item.name)
        end
    end
    ey = ey + 20 + rolesH + 10

    self.itemsLabelY = ey
    self.kitItemList = ISScrollingListBox:new(ex, ey + 20, ew,
        math.max(ITEM_ROW_H, cby - 12 - (ey + 20)))
    self.kitItemList:initialise()
    self.kitItemList:instantiate()
    self.kitItemList.itemheight = ITEM_ROW_H
    self.kitItemList.drawBorder = false
    self.kitItemList.backgroundColor = { r = 0, g = 0, b = 0, a = 0 }
    self.kitItemList.doDrawItem = AegisPageKits.drawKitItemRow
    self:addChild(self.kitItemList)
    -- a click on the x zone of a row removes that entry
    local kitList = self.kitItemList
    kitList.aegisPage = self
    function kitList:onMouseDown(x, y)
        ISScrollingListBox.onMouseDown(self, x, y)
        local row = self:rowAt(x, y)
        if row and row >= 1 and row <= #self.items and x >= self:getWidth() - 30 then
            self.aegisPage:removeKitItem(row)
        end
    end

    self.claimResetBtn = AegisButton:new(ex, cby, ew, 32, getText("UI_Aegis_KitClaimReset"), "refresh",
        self, AegisPageKits.onClaimReset)
    self:addChild(self.claimResetBtn)

    self.saveBtn = AegisButton:new(ex, by, half, 34, getText("UI_Aegis_KitSave"), "check", self, AegisPageKits.onSave)
    self.saveBtn.style = "gold"
    self:addChild(self.saveBtn)
    self.deleteBtn = AegisButton:new(ex + half + 8, by, half, 34, getText("UI_Aegis_KitDelete"), "trash", self, AegisPageKits.onDelete)
    self.deleteBtn.style = "danger"
    self:addChild(self.deleteBtn)

    -- right column: item search feeding the kit contents
    local sx = self.searchX + 14
    local sw = self.colW - 28
    local sy = pad + 44

    self.search = ISTextEntryBox:new("", sx, sy, sw, 26)
    self.search:initialise()
    self.search:instantiate()
    self.search.font = UIFont.Small
    self.search:setClearButton(true)
    self.search:setPlaceholderText(getText("UI_Aegis_KitSearch"))
    self.search.backgroundColor = { r = Aegis.col.dark.r, g = Aegis.col.dark.g, b = Aegis.col.dark.b, a = 1 }
    self.search.borderColor = { r = Aegis.col.line.r, g = Aegis.col.line.g, b = Aegis.col.line.b, a = 1 }
    self.search.onTextChange = function() page:applyFilter() end
    self:addChild(self.search)

    local qy = by - 38
    self.qtyButtons = {}
    local qx = sx
    for _, q in ipairs({ 1, 5, 10 }) do
        local btn = AegisButton:new(qx, qy, 42, 28, tostring(q), nil, self, function(p, b) p.qty = b.qtyValue end)
        btn.qtyValue = q
        btn.radius = 14
        self:addChild(btn)
        table.insert(self.qtyButtons, btn)
        qx = qx + 48
    end
    self.addBtn = AegisButton:new(sx, by, sw, 32, getText("UI_Aegis_KitAdd"), "plus", self, AegisPageKits.onAddItem)
    self:addChild(self.addBtn)

    self.searchList = ISScrollingListBox:new(sx, sy + 34, sw, qy - 12 - (sy + 34))
    self.searchList:initialise()
    self.searchList:instantiate()
    self.searchList.itemheight = SEARCH_ROW_H
    self.searchList.drawBorder = false
    self.searchList.backgroundColor = { r = 0, g = 0, b = 0, a = 0 }
    self.searchList.doDrawItem = AegisPageKits.drawSearchRow
    self:addChild(self.searchList)

    self:refreshRoles()
end

-- ------------------------------------------------------------------
-- Item catalog, cache pattern from the item spawner page
-- ------------------------------------------------------------------

function AegisPageKits:buildCache()
    if self.allItems then return end
    self.allItems = {}
    local list = getScriptManager():getAllItems()
    for i = 0, list:size() - 1 do
        local it = list:get(i)
        if not it:getObsolete() and not it:isHidden() then
            local rec = {
                display = it:getDisplayName() or it:getName(),
                full = it:getFullName(),
                icon = it:getIcon(),
                iconsFor = it:getIconsForTexture(),
            }
            rec.search = string.lower(rec.display .. " " .. rec.full)
            table.insert(self.allItems, rec)
        end
    end
    table.sort(self.allItems, function(a, b) return a.display < b.display end)
end

function AegisPageKits:applyFilter()
    self:buildCache()
    local needle = string.lower(self.search:getInternalText() or "")
    self.searchList:clear()
    local shown = 0
    for _, rec in ipairs(self.allItems) do
        if needle == "" or string.find(rec.search, needle, 1, true) then
            shown = shown + 1
            if shown > MAX_ROWS then break end
            self.searchList:addItem(rec.display, rec)
        end
    end
end

-- ------------------------------------------------------------------
-- Editor state
-- ------------------------------------------------------------------

function AegisPageKits:setKits(list, roleNames)
    if type(roleNames) == "table" then
        self.roleNames = {}
        for i = 1, #roleNames do
            local n = roleNames[i]
            if type(n) == "string" and n ~= "" then table.insert(self.roleNames, n) end
        end
    end
    self.kits = {}
    if type(list) == "table" then
        for i = 1, #list do
            local k = list[i]
            if type(k) == "table" and type(k.id) == "string" then
                table.insert(self.kits, k)
            end
        end
    end
    local keep = self.selectedId
    self.list:clear()
    local sel = nil
    for i, kit in ipairs(self.kits) do
        self.list:addItem(kit.name or kit.id, kit)
        if kit.id == keep then sel = i end
    end
    if sel then
        self.list.selected = sel
        self:onSelectKit(self.kits[sel])
    elseif keep then
        -- the selected kit is gone, fall back to a fresh editor
        self:onNew()
    end
    self:refreshRoles()
end

function AegisPageKits:onSelectKit(kit)
    if type(kit) ~= "table" or type(kit.id) ~= "string" then return end
    self.selectedId = kit.id
    local mode = kit.mode
    if mode ~= "cd" and mode ~= "month" then mode = "once" end
    self.editor = {
        id = kit.id,
        version = tonumber(kit.version) or 0,
        mode = mode,
        cooldownH = tonumber(kit.cooldownH) or 24,
        items = {},
        roles = {},
    }
    local roles = type(kit.roles) == "table" and kit.roles or {}
    for i = 1, #roles do
        if type(roles[i]) == "string" and roles[i] ~= "" then
            table.insert(self.editor.roles, roles[i])
        end
    end
    local items = type(kit.items) == "table" and kit.items or {}
    for i = 1, #items do
        local it = items[i]
        if type(it) == "table" and type(it.fullType) == "string" then
            table.insert(self.editor.items, {
                fullType = it.fullType,
                count = math.max(1, math.min(MAX_COUNT, math.floor(tonumber(it.count) or 1))),
                display = displayName(it.fullType),
            })
        end
    end
    self.nameEntry:setText(kit.name or kit.id)
    self.hoursEntry:setText(tostring(self.editor.cooldownH))
    self:refreshKitItems()
    self:refreshRoles()
end

function AegisPageKits:onNew()
    self.selectedId = nil
    self.list.selected = 0
    self.editor = { id = nil, version = 0, mode = "once", cooldownH = 24, items = {}, roles = {} }
    self.nameEntry:setText("")
    self.hoursEntry:setText("24")
    self:refreshKitItems()
    self:refreshRoles()
end

-- ------------------------------------------------------------------
-- Role gate
-- ------------------------------------------------------------------

function AegisPageKits:hasRole(name)
    for _, r in ipairs(self.editor.roles or {}) do
        if r == name then return true end
    end
    return false
end

function AegisPageKits:toggleRole(name)
    if type(name) ~= "string" or name == "" then return end
    self.editor.roles = self.editor.roles or {}
    for i, r in ipairs(self.editor.roles) do
        if r == name then
            table.remove(self.editor.roles, i)
            self:refreshRoles()
            return
        end
    end
    if #self.editor.roles >= MAX_KIT_ROLES then return end
    table.insert(self.editor.roles, name)
    self:refreshRoles()
end

-- offers only roles the server knows; a name stored on the kit whose role
-- is gone is listed last and marked, so it can be seen and dropped instead
-- of sitting invisible in the file
function AegisPageKits:refreshRoles()
    if not self.roleList then return end
    self.roleList:clear()
    local known = {}
    -- the booster gate rides in the same list as the real roles, they are
    -- or-linked on the server; it always exists, so it goes first
    known[BOOSTER_ROLE] = true
    self.roleList:addItem(BOOSTER_ROLE, {
        name = BOOSTER_ROLE, label = getText("UI_Aegis_KitRoleBooster"), known = true,
    })
    for _, name in ipairs(self.roleNames or {}) do
        known[name] = true
        self.roleList:addItem(name, { name = name, known = true })
    end
    for _, name in ipairs(self.editor.roles or {}) do
        if not known[name] then
            self.roleList:addItem(name, { name = name, known = false })
        end
    end
end

function AegisPageKits:refreshKitItems()
    self.kitItemList:clear()
    for _, it in ipairs(self.editor.items) do
        self.kitItemList:addItem(it.display or it.fullType, it)
    end
end

function AegisPageKits:removeKitItem(row)
    if not self.editor.items[row] then return end
    table.remove(self.editor.items, row)
    self:refreshKitItems()
end

function AegisPageKits:onAddItem()
    local row = self.searchList.items[self.searchList.selected]
    if not row then return end
    local rec = row.item
    for _, it in ipairs(self.editor.items) do
        if it.fullType == rec.full then
            it.count = math.min(MAX_COUNT, it.count + self.qty)
            self:refreshKitItems()
            return
        end
    end
    if #self.editor.items >= MAX_KIT_ITEMS then return end
    table.insert(self.editor.items, {
        fullType = rec.full,
        count = math.min(MAX_COUNT, self.qty),
        display = rec.display,
    })
    self:refreshKitItems()
end

function AegisPageKits:onSave()
    local name = (self.nameEntry:getInternalText() or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if name == "" or #self.editor.items == 0 then return end
    local id = self.editor.id
    if not id then
        id = name:lower():gsub("[^a-z0-9]", "")
        if id == "" then id = "kit" .. tostring(AegisShared.realTime() % 100000) end
        if #id > 24 then id = id:sub(1, 24) end
    end
    local hours = math.max(1, math.min(8760, math.floor(tonumber(self.hoursEntry:getInternalText()) or 24)))
    local items = {}
    for _, it in ipairs(self.editor.items) do
        table.insert(items, { fullType = it.fullType, count = it.count })
    end
    local roles = {}
    for _, r in ipairs(self.editor.roles or {}) do
        table.insert(roles, r)
    end
    -- isNew lets the server hand out a free id instead of landing on an
    -- existing kit; version guards against a second editor saving first
    sendClientCommand(getPlayer(), AegisShared.MODULE, "kitSave", {
        id = id, name = name, mode = self.editor.mode, cooldownH = hours,
        items = items, roles = roles,
        isNew = self.editor.id == nil, version = self.editor.version or 0,
    })
end

function AegisPageKits:onDelete()
    if not self.selectedId then return end
    AegisConfirm.show(getText("UI_Aegis_KitDelete"), getText("UI_Aegis_KitDeleteMsg"),
        getText("UI_Aegis_KitDelete"), self, function(page)
            sendClientCommand(getPlayer(), AegisShared.MODULE, "kitRemove", { id = page.selectedId })
        end)
end

-- ------------------------------------------------------------------
-- Claims
-- ------------------------------------------------------------------

function AegisPageKits:selectedKitName()
    for _, kit in ipairs(self.kits) do
        if kit.id == self.selectedId then return kit.name or kit.id end
    end
    return self.selectedId or ""
end

-- holders of the selected kit, -1 while the answer is still out or belongs
-- to a kit that has been switched away from
function AegisPageKits:claimCount()
    local info = self.claimInfo
    if info and info.id == self.selectedId then return info.total or 0 end
    return -1
end

function AegisPageKits:claimsLocked()
    local info = self.claimInfo
    return info ~= nil and info.id == self.selectedId and info.readable == false
end

function AegisPageKits:requestClaims()
    local id = self.selectedId
    if not id then return end
    self.claimAsk = { id = id, at = AegisShared.realTime() }
    sendClientCommand(getPlayer(), AegisShared.MODULE, "kitClaimList", { id = id })
end

function AegisPageKits:onClaimList(args)
    if type(args) ~= "table" or type(args.id) ~= "string" then return end
    self.claimInfo = {
        id = args.id,
        total = tonumber(args.total) or 0,
        allTotal = tonumber(args.allTotal) or 0,
        readable = args.readable ~= false,
    }
end

function AegisPageKits:onClaimReset()
    if not self.selectedId then return end
    local n = self:claimCount()
    if n <= 0 then return end
    AegisConfirm.show(getText("UI_Aegis_KitClaimReset"),
        getText("UI_Aegis_KitClaimResetMsg", tostring(n)),
        getText("UI_Aegis_KitClaimReset"), self, function(page)
            sendClientCommand(getPlayer(), AegisShared.MODULE, "kitClaimReset",
                { scope = "kit", id = page.selectedId })
        end)
end

function AegisPageKits:onShow()
    self:buildCache()
    self:applyFilter()
    sendClientCommand(getPlayer(), AegisShared.MODULE, "kitList", {})
end

-- ------------------------------------------------------------------
-- Rows
-- ------------------------------------------------------------------

function AegisPageKits.drawKitRow(list, y, item, alt)
    local c = Aegis.col
    local sel = list.selected == item.index
    local hover = list.mouseoverselected == item.index
    if sel then
        Aegis.roundRect(list, 2, y + 1, list:getWidth() - 4, ROW_H - 2, 8, 1, c.card)
        Aegis.roundRect(list, 2, y + 8, 3, ROW_H - 16, 1, 1, c.gold)
    elseif hover then
        Aegis.roundRect(list, 2, y + 1, list:getWidth() - 4, ROW_H - 2, 8, 0.5, c.card)
    end
    local kit = item.item
    Aegis.text(list, Aegis.fitText(kit.name or kit.id, UIFont.Medium, list:getWidth() - 24), 12, y + 4,
        UIFont.Medium, sel and c.text or c.muted)
    Aegis.text(list, modeLine(kit), 12, y + 6 + Aegis.fontH(UIFont.Medium), UIFont.Small, c.goldDim)
    -- gated kits carry a dot, open ones stay plain
    if type(kit.roles) == "table" and #kit.roles > 0 then
        Aegis.roundRect(list, list:getWidth() - 18, y + math.floor(ROW_H / 2) - 4, 8, 8, 4, 1, c.gold)
    end
    return y + ROW_H
end

function AegisPageKits.drawRoleRow(list, y, item, alt)
    local c = Aegis.col
    local page = list.aegisPage
    local rec = item.item
    local on = page and page:hasRole(rec.name) or false
    local hover = list.mouseoverselected == item.index
    if on then
        Aegis.roundRect(list, 2, y + 1, list:getWidth() - 4, ROLE_ROW_H - 2, 8, 1, c.card)
    elseif hover then
        Aegis.roundRect(list, 2, y + 1, list:getWidth() - 4, ROLE_ROW_H - 2, 8, 0.5, c.card)
    end
    local box = ROLE_ROW_H - 10
    Aegis.roundFrame(list, 8, y + 5, box, box, 4, 1, on and c.gold or c.line, c.dark)
    if on then
        Aegis.icon(list, "check", 10, y + 7, box - 4, 1, c.gold)
    end
    local label = rec.label or rec.name
    local tc = c.muted
    if not rec.known then
        label = label .. " " .. getText("UI_Aegis_KitRoleGone")
        tc = c.danger
    elseif on then
        tc = c.text
    end
    Aegis.text(list, Aegis.fitText(label, UIFont.Small, list:getWidth() - box - 26), box + 16,
        y + math.floor((ROLE_ROW_H - Aegis.fontH(UIFont.Small)) / 2), UIFont.Small, tc)
    return y + ROLE_ROW_H
end

function AegisPageKits.drawKitItemRow(list, y, item, alt)
    local c = Aegis.col
    local hover = list.mouseoverselected == item.index
    if hover then
        Aegis.roundRect(list, 2, y + 1, list:getWidth() - 4, ITEM_ROW_H - 2, 8, 0.5, c.card)
    end
    local rec = item.item
    local label = (rec.display or rec.fullType) .. " x" .. tostring(rec.count)
    Aegis.text(list, Aegis.fitText(label, UIFont.Small, list:getWidth() - 46), 10,
        y + math.floor((ITEM_ROW_H - Aegis.fontH(UIFont.Small)) / 2), UIFont.Small, c.text)
    Aegis.icon(list, "close", list:getWidth() - 24, y + math.floor((ITEM_ROW_H - 14) / 2), 14,
        hover and 1 or 0.6, c.danger)
    return y + ITEM_ROW_H
end

function AegisPageKits.drawSearchRow(list, y, item, alt)
    local c = Aegis.col
    local sel = list.selected == item.index
    local hover = list.mouseoverselected == item.index
    if sel then
        Aegis.roundRect(list, 2, y + 1, list:getWidth() - 4, SEARCH_ROW_H - 2, 8, 1, c.card)
    elseif hover then
        Aegis.roundRect(list, 2, y + 1, list:getWidth() - 4, SEARCH_ROW_H - 2, 8, 0.5, c.card)
    end
    local rec = item.item
    local tex = resolveIcon(rec)
    if tex then
        list:drawTextureScaledAspect2(tex, 8, y + math.floor((SEARCH_ROW_H - 20) / 2), 20, 20, 1, 1, 1, 1)
    end
    Aegis.text(list, Aegis.fitText(rec.display, UIFont.Small, list:getWidth() - 44), 34,
        y + math.floor((SEARCH_ROW_H - Aegis.fontH(UIFont.Small)) / 2), UIFont.Small, sel and c.text or c.muted)
    return y + SEARCH_ROW_H
end

-- ------------------------------------------------------------------
-- Frame
-- ------------------------------------------------------------------

function AegisPageKits:prerender()
    local c = Aegis.col
    local pad = 20
    local H = self.height

    Aegis.roundFrame(self, pad, pad, LIST_W, H - pad * 2, 10, 1, c.line, c.panel)
    Aegis.icon(self, "plus", pad + 14, pad + 12, 15, 1, c.gold)
    Aegis.text(self, getText("UI_Aegis_NavKits"), pad + 36, pad + 10, UIFont.Medium, c.text)
    if #self.kits == 0 then
        Aegis.textCentre(self, getText("UI_Aegis_KitEmpty"), pad + math.floor(LIST_W / 2), pad + 70, UIFont.Small, c.muted)
    end

    Aegis.roundFrame(self, self.editorX, pad, self.colW, H - pad * 2, 10, 1, c.line, c.panel)
    Aegis.icon(self, "gear", self.editorX + 14, pad + 12, 15, 1, c.gold)
    Aegis.text(self, getText("UI_Aegis_KitEditor"), self.editorX + 36, pad + 10, UIFont.Medium, c.text)

    Aegis.roundFrame(self, self.searchX, pad, self.colW, H - pad * 2, 10, 1, c.line, c.panel)
    Aegis.icon(self, "search", self.searchX + 14, pad + 12, 15, 1, c.gold)
    Aegis.text(self, getText("UI_Aegis_KitAddItems"), self.searchX + 36, pad + 10, UIFont.Medium, c.text)

    -- mode chips and cooldown hours
    self.onceBtn.style = self.editor.mode == "once" and "gold" or "ghost"
    self.cdBtn.style = self.editor.mode == "cd" and "gold" or "ghost"
    self.monthBtn.style = self.editor.mode == "month" and "gold" or "ghost"
    local cd = self.editor.mode == "cd"
    self.hoursEntry:setVisible(cd)
    if cd then
        Aegis.text(self, getText("UI_Aegis_KitHours"), self.editorX + 14, self.hoursY + 5, UIFont.Small, c.muted)
    end

    local roleCount = #(self.editor.roles or {})
    Aegis.text(self, getText("UI_Aegis_KitRoles"), self.editorX + 14, self.rolesLabelY, UIFont.Small, c.muted)
    Aegis.textRight(self, roleCount == 0 and getText("UI_Aegis_KitRolesAll")
        or (roleCount .. "/" .. MAX_KIT_ROLES),
        self.editorX + self.colW - 14, self.rolesLabelY, UIFont.Small,
        roleCount == 0 and c.goldDim or c.gold)
    -- the booster entry is always in the list, the empty placeholder of the
    -- role box would only ever draw on top of it now

    Aegis.text(self, getText("UI_Aegis_KitItems"), self.editorX + 14, self.itemsLabelY, UIFont.Small, c.muted)
    Aegis.textRight(self, #self.editor.items .. "/" .. MAX_KIT_ITEMS, self.editorX + self.colW - 14,
        self.itemsLabelY, UIFont.Small, c.muted)

    local name = (self.nameEntry:getInternalText() or ""):gsub("^%s+", ""):gsub("%s+$", "")
    self.saveBtn:setEnabled(name ~= "" and #self.editor.items > 0)
    self.deleteBtn:setEnabled(self.selectedId ~= nil)

    local claims = self:claimCount()
    if self.selectedId and claims < 0 then
        -- the server allows one list request per second, a kit picked
        -- faster than that would never get its count
        local ask = self.claimAsk
        if not ask or ask.id ~= self.selectedId or AegisShared.realTime() - ask.at > 2 then
            self:requestClaims()
        end
    end
    self.claimResetBtn.label = getText("UI_Aegis_KitClaimReset")
        .. (claims >= 0 and (" (" .. claims .. ")") or "")
    self.claimResetBtn:setEnabled(claims > 0 and not self:claimsLocked())
    self.claimBtn:setEnabled(self.selectedId ~= nil)

    Aegis.text(self, getText("UI_Aegis_Qty"), self.searchX + 14, self.qtyButtons[1].y - 18, UIFont.Small, c.muted)
    for _, btn in ipairs(self.qtyButtons) do
        btn.style = btn.qtyValue == self.qty and "gold" or "ghost"
    end
    self.addBtn:setEnabled(self.searchList.items[self.searchList.selected] ~= nil)
end

local function claimResetToast(args)
    if type(args) == "table" and args.ok == true then
        Aegis.showToast(getText("UI_Aegis_KitClaimsDone", tostring(tonumber(args.count) or 0)))
        return
    end
    local reason = type(args) == "table" and args.reason or nil
    if reason == "incomplete" then
        Aegis.showToast(getText("UI_Aegis_KitClaimsLocked"))
    elseif reason == "none" then
        Aegis.showToast(getText("UI_Aegis_KitClaimsNone"))
    else
        Aegis.showToast(getText("UI_Aegis_KitClaimsFailed"))
    end
end

Events.OnServerCommand.Add(function(module, command, args)
    if module ~= AegisShared.MODULE then return end
    local page = AegisPageKits.instance
    if not page then return end
    if command == "kitList" then
        -- the panel page shares this command, its payload is role filtered
        -- and carries no gate; the editor must not mirror it
        if args and args.scope == "player" then return end
        page:setKits(args and args.kits or {}, args and args.roles or nil)
    elseif command == "kitSave" then
        if args and args.ok == true then
            -- the server may have picked a free id for a create
            if type(args.id) == "string" then
                page.editor.id = args.id
                page.selectedId = args.id
            end
            Aegis.showToast(getText("UI_Aegis_KitSaved"))
        elseif args and args.reason == "conflict" then
            Aegis.showToast(getText("UI_Aegis_KitConflict"))
        else
            Aegis.showToast(getText("UI_Aegis_KitSaveFailed"))
        end
    elseif command == "kitRemove" then
        if args and args.ok == true then
            Aegis.showToast(getText("UI_Aegis_KitRemoved"))
        end
    elseif command == "kitClaimList" then
        page:onClaimList(args)
    elseif command == "kitClaimReset" then
        claimResetToast(args)
    end
end)

AegisWindow.registerPage({
    id = "kits",
    icon = "plus",
    label = "UI_Aegis_NavKits",
    create = AegisPageKits.create,
})

-- ==================================================================
-- AegisBoostManager: booster administration in its own dialog, opened
-- from the kit editor. Key setup plus the booster list with per entry
-- grant, revoke and unlink. The server gates every command on the kits
-- area, this dialog only mirrors its answers.
-- ==================================================================
AegisBoostManager = ISPanel:derive("AegisBoostManager")
AegisBoostManager.instance = nil

local BOOST_ROW_H = 44
local BOOST_BTN_W = 74
local BOOST_BTN_GAP = 6
local KEY_MIN = 8
local KEY_MAX = 128

-- same rule as secretOk on the server, checked before sending so a typo
-- gets its answer without a round trip
local function boostKeyOk(s)
    if #s < KEY_MIN or #s > KEY_MAX then return false end
    for i = 1, #s do
        local b = string.byte(s, i)
        if not b or b < 32 or b > 126 then return false end
    end
    return true
end

-- three action zones at the right edge of a row, drawn and hit tested
-- with the same numbers
local function rowZones(w)
    local x3 = w - 6 - BOOST_BTN_W
    local x2 = x3 - BOOST_BTN_GAP - BOOST_BTN_W
    local x1 = x2 - BOOST_BTN_GAP - BOOST_BTN_W
    return x1, x2, x3
end

function AegisBoostManager.toggle()
    if AegisBoostManager.instance then
        AegisBoostManager.instance:closeSelf()
        return
    end
    local sw, sh = getCore():getScreenWidth(), getCore():getScreenHeight()
    local o = ISPanel:new(0, 0, sw, sh)
    setmetatable(o, AegisBoostManager)
    AegisBoostManager.__index = AegisBoostManager
    o.background = true
    o.backgroundColor = { r = 0, g = 0, b = 0, a = 0.55 }
    o.borderColor = { r = 0, g = 0, b = 0, a = 0 }
    o.cardW = math.min(sw - 80, 560)
    o.cardH = math.min(sh - 80, 520)
    o.entries = {}
    o.keySet = false
    o.gotList = false
    o:initialise()
    o:addToUIManager()
    o:setAlwaysOnTop(true)

    local cx = math.floor((sw - o.cardW) / 2)
    local cy = math.floor((sh - o.cardH) / 2)
    o.cardX, o.cardY = cx, cy
    local innerX = cx + 16
    local innerW = o.cardW - 32

    o.closeBtn = AegisButton:new(cx + o.cardW - 40, cy + 12, 26, 26, nil, "close", o, AegisBoostManager.closeSelf)
    o.closeBtn.radius = 13
    o:addChild(o.closeBtn)

    o.keyEntry = ISTextEntryBox:new("", innerX, cy + 66, innerW - 98, 26)
    o.keyEntry:initialise()
    o.keyEntry:instantiate()
    o.keyEntry.font = UIFont.Small
    o.keyEntry:setMaxTextLength(KEY_MAX)
    o.keyEntry:setPlaceholderText(getText("UI_Aegis_BoostKeyHint"))
    o.keyEntry.backgroundColor = { r = Aegis.col.dark.r, g = Aegis.col.dark.g, b = Aegis.col.dark.b, a = 1 }
    o.keyEntry.borderColor = { r = Aegis.col.line.r, g = Aegis.col.line.g, b = Aegis.col.line.b, a = 1 }
    o:addChild(o.keyEntry)

    o.keyBtn = AegisButton:new(innerX + innerW - 90, cy + 66, 90, 26,
        getText("UI_Aegis_BoostKeyApply"), "check", o, AegisBoostManager.onSetKey)
    o.keyBtn.style = "gold"
    o:addChild(o.keyBtn)

    -- first grant needs a name field: the list only shows players with a
    -- boost history, a fresh server would otherwise have nobody to click
    o.grantEntry = ISTextEntryBox:new("", innerX, cy + 98, innerW - 98, 26)
    o.grantEntry:initialise()
    o.grantEntry:instantiate()
    o.grantEntry.font = UIFont.Small
    o.grantEntry:setMaxTextLength(48)
    o.grantEntry:setPlaceholderText(getText("UI_Aegis_BoostGrantHint"))
    o.grantEntry.backgroundColor = { r = Aegis.col.dark.r, g = Aegis.col.dark.g, b = Aegis.col.dark.b, a = 1 }
    o.grantEntry.borderColor = { r = Aegis.col.line.r, g = Aegis.col.line.g, b = Aegis.col.line.b, a = 1 }
    o:addChild(o.grantEntry)
    o.grantBtn = AegisButton:new(innerX + innerW - 90, cy + 98, 90, 26,
        getText("UI_Aegis_BoostGrant"), "plus", o, AegisBoostManager.onGrantName)
    o.grantBtn.style = "gold"
    o:addChild(o.grantBtn)

    o.listY = cy + 150
    o.list = ISScrollingListBox:new(innerX, o.listY, innerW, cy + o.cardH - 16 - o.listY)
    o.list:initialise()
    o.list:instantiate()
    o.list.itemheight = BOOST_ROW_H
    o.list.drawBorder = false
    o.list.backgroundColor = { r = 0, g = 0, b = 0, a = 0 }
    o.list.doDrawItem = AegisBoostManager.drawRow
    o.list.manager = o
    function o.list:onMouseDown(x, y)
        ISScrollingListBox.onMouseDown(self, x, y)
        local row = self:rowAt(x, y)
        local entry = row and self.items[row] and self.items[row].item
        if type(entry) ~= "table" then return end
        self.manager:onRowClick(entry, x)
    end
    o:addChild(o.list)

    AegisBoostManager.instance = o
    o:requestList()
    return o
end

function AegisBoostManager:closeSelf()
    self:removeFromUIManager()
    if AegisBoostManager.instance == self then
        AegisBoostManager.instance = nil
    end
end

function AegisBoostManager:send(command, args)
    local p = getPlayer()
    if not p then return end
    sendClientCommand(p, AegisShared.MODULE, command, args or {})
end

function AegisBoostManager:requestList()
    self:send("boostList", {})
end

function AegisBoostManager:onSetKey()
    local key = (self.keyEntry:getInternalText() or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if not boostKeyOk(key) then
        self.keyMsg = { key = "UI_Aegis_BoostKeyBad", tone = "danger" }
        return
    end
    self.keyMsg = nil
    self:send("boostKey", { key = key })
end

function AegisBoostManager:onGrantName()
    local user = (self.grantEntry:getInternalText() or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if user == "" or #user > 48 or user:find("[%c|]") then return end
    self:send("boostGrant", { user = user })
    self.grantEntry:setText("")
end

function AegisBoostManager:onRowClick(entry, x)
    local x1, x2, x3 = rowZones(self.list:getWidth())
    if x >= x3 then
        -- nothing to release without a linked id
        if (entry.discordId or "") ~= "" then
            -- freeing the id also frees it for a NEW player name; with an
            -- active revocation block that door stays shut server side,
            -- still worth an active confirmation
            AegisConfirm.show(getText("UI_Aegis_BoostUnlink"),
                getText("UI_Aegis_BoostUnlinkMsg", entry.user),
                getText("UI_Aegis_BoostUnlink"), self, function(mgr)
                    mgr:send("boostUnlink", { user = entry.user })
                end)
        end
    elseif x >= x2 then
        -- revoke holds until the end of the month (high water mark), that
        -- deserves a confirmation
        AegisConfirm.show(getText("UI_Aegis_BoostRevoke"),
            getText("UI_Aegis_BoostRevokeMsg", entry.user),
            getText("UI_Aegis_BoostRevoke"), self, function(mgr)
                mgr:send("boostRevoke", { user = entry.user })
            end)
    elseif x >= x1 then
        -- server default of 30 days, mirrors a bought month
        self:send("boostGrant", { user = entry.user })
    end
end

function AegisBoostManager:onList(args)
    if type(args) ~= "table" then return end
    self.gotList = true
    self.keySet = args.keySet == true
    self.entries = {}
    self.list:clear()
    for _, e in ipairs(type(args.entries) == "table" and args.entries or {}) do
        if type(e) == "table" and type(e.user) == "string" then
            table.insert(self.entries, e)
            self.list:addItem(e.user, e)
        end
    end
end

function AegisBoostManager:onKeyReply(args)
    if type(args) ~= "table" then return end
    self.keySet = args.keySet == true
    if args.ok == true then
        self.keyMsg = { key = "UI_Aegis_BoostKeyOk", tone = "ok" }
        if self.keyEntry then self.keyEntry:setText("") end
    else
        self.keyMsg = { key = "UI_Aegis_BoostKeyBad", tone = "danger" }
    end
end

function AegisBoostManager:onActionReply(args)
    -- the fresh list rides in on its own push right after
    if type(args) == "table" and args.ok == true then
        Aegis.showToast(getText("UI_Aegis_BoostActionOk"))
    else
        Aegis.showToast(getText("UI_Aegis_BoostActionFailed"))
    end
end

function AegisBoostManager.drawRow(list, y, item, alt)
    local c = Aegis.col
    local w = list:getWidth()
    local entry = item.item
    local hover = list.mouseoverselected == item.index
    if hover then
        Aegis.roundRect(list, 2, y + 1, w - 4, BOOST_ROW_H - 2, 8, 0.4, c.card)
    end
    local x1, x2, x3 = rowZones(w)
    local textW = x1 - 18
    Aegis.text(list, Aegis.fitText(entry.user or "", UIFont.Small, textW), 10, y + 5, UIFont.Small, c.text)
    local active = (tonumber(entry.untilEpoch) or 0) > AegisShared.realTime()
    local line
    if active then
        line = getText("UI_Aegis_BoostUntilLine", AegisShared.timestampReadable(entry.untilEpoch))
    else
        line = getText("UI_Aegis_BoostExpiredLine")
    end
    if (entry.discordId or "") ~= "" then
        line = line .. "  " .. entry.discordId
    end
    Aegis.text(list, Aegis.fitText(line, UIFont.Small, textW), 10,
        y + 7 + Aegis.fontH(UIFont.Small), UIFont.Small, active and c.goldDim or c.muted)

    local by = y + math.floor((BOOST_ROW_H - 24) / 2)
    local function chip(x, labelKey, col, dim)
        local a = dim and 0.35 or 1
        Aegis.roundFrame(list, x, by, BOOST_BTN_W, 24, 12, a, col, c.card)
        Aegis.textCentre(list, getText(labelKey), x + math.floor(BOOST_BTN_W / 2),
            by + math.floor((24 - Aegis.fontH(UIFont.Small)) / 2), UIFont.Small, col, a)
    end
    chip(x1, "UI_Aegis_BoostGrant", c.gold, false)
    chip(x2, "UI_Aegis_BoostRevoke", c.danger, not active)
    chip(x3, "UI_Aegis_BoostUnlink", c.muted, (entry.discordId or "") == "")
    return y + BOOST_ROW_H
end

function AegisBoostManager:prerender()
    ISPanel.prerender(self)
    local c = Aegis.col
    local cx, cy = self.cardX, self.cardY
    Aegis.shadow(self, cx, cy, self.cardW, self.cardH, 26, 0.7)
    Aegis.roundFrame(self, cx, cy, self.cardW, self.cardH, 12, 1, c.line, c.bg)
    Aegis.icon(self, "crown", cx + 16, cy + 15, 15, 1, c.gold)
    Aegis.text(self, getText("UI_Aegis_BoostManage"), cx + 38, cy + 13, UIFont.Medium, c.text)

    Aegis.text(self, getText("UI_Aegis_BoostKeyLabel"), cx + 16, cy + 46, UIFont.Small, c.muted)
    local stateKey = self.keySet and "UI_Aegis_BoostKeySet" or "UI_Aegis_BoostKeyMissing"
    Aegis.textRight(self, getText(stateKey), cx + self.cardW - 16, cy + 46, UIFont.Small,
        self.keySet and c.ok or c.danger)

    if self.keyMsg then
        Aegis.text(self, getText(self.keyMsg.key), cx + 16, cy + 97, UIFont.Small,
            self.keyMsg.tone == "ok" and c.ok or c.danger)
    end
    if self.gotList and #self.entries == 0 then
        Aegis.textCentre(self, getText("UI_Aegis_BoostListEmpty"),
            cx + math.floor(self.cardW / 2), self.listY + 24, UIFont.Small, c.muted)
    end
    local key = (self.keyEntry and self.keyEntry:getInternalText() or ""):gsub("^%s+", ""):gsub("%s+$", "")
    self.keyBtn:setEnabled(key ~= "")
end

Events.OnServerCommand.Add(function(module, command, args)
    if module ~= AegisShared.MODULE then return end
    local mgr = AegisBoostManager.instance
    if not mgr then return end
    if command == "boostList" then
        mgr:onList(args)
    elseif command == "boostKey" then
        mgr:onKeyReply(args)
    elseif command == "boostGrant" or command == "boostRevoke" or command == "boostUnlink" then
        mgr:onActionReply(args)
    end
end)

-- ==================================================================
-- AegisClaimManager: claim history of one kit in its own dialog. Per
-- player reset from the list, plus the wipe of the whole history at the
-- bottom: the claim file lives in the Aegis folder and not in the save,
-- so after a world reset every kit stayed claimed for good.
-- ==================================================================
AegisClaimManager = ISPanel:derive("AegisClaimManager")
AegisClaimManager.instance = nil

local CLAIM_ROW_H = 40
local CLAIM_BTN_W = 84

function AegisClaimManager.toggle(kitId, kitName)
    if AegisClaimManager.instance then
        AegisClaimManager.instance:closeSelf()
        return
    end
    if type(kitId) ~= "string" or kitId == "" then return end
    local sw, sh = getCore():getScreenWidth(), getCore():getScreenHeight()
    local o = ISPanel:new(0, 0, sw, sh)
    setmetatable(o, AegisClaimManager)
    AegisClaimManager.__index = AegisClaimManager
    o.background = true
    o.backgroundColor = { r = 0, g = 0, b = 0, a = 0.55 }
    o.borderColor = { r = 0, g = 0, b = 0, a = 0 }
    o.cardW = math.min(sw - 80, 520)
    o.cardH = math.min(sh - 80, 500)
    o.kitId = kitId
    o.kitName = (type(kitName) == "string" and kitName ~= "") and kitName or kitId
    o.entries = {}
    o.total = 0
    o.allTotal = 0
    o.readable = true
    o.gotList = false
    o.askedAt = 0
    o:initialise()
    o:addToUIManager()
    o:setAlwaysOnTop(true)

    local cx = math.floor((sw - o.cardW) / 2)
    local cy = math.floor((sh - o.cardH) / 2)
    o.cardX, o.cardY = cx, cy
    local innerX = cx + 16
    local innerW = o.cardW - 32

    o.closeBtn = AegisButton:new(cx + o.cardW - 40, cy + 12, 26, 26, nil, "close", o, AegisClaimManager.closeSelf)
    o.closeBtn.radius = 13
    o:addChild(o.closeBtn)

    -- the wipe sits below a separator and away from the row buttons, it
    -- hits every kit and every player at once
    o.allBtn = AegisButton:new(innerX, cy + o.cardH - 52, innerW, 36,
        getText("UI_Aegis_KitClaimAll"), "trash", o, AegisClaimManager.onResetAll)
    o.allBtn.style = "danger"
    o:addChild(o.allBtn)

    o.listY = cy + 76
    o.list = ISScrollingListBox:new(innerX, o.listY, innerW,
        math.max(CLAIM_ROW_H, cy + o.cardH - 86 - o.listY))
    o.list:initialise()
    o.list:instantiate()
    o.list.itemheight = CLAIM_ROW_H
    o.list.drawBorder = false
    o.list.backgroundColor = { r = 0, g = 0, b = 0, a = 0 }
    o.list.doDrawItem = AegisClaimManager.drawRow
    o.list.manager = o
    function o.list:onMouseDown(x, y)
        ISScrollingListBox.onMouseDown(self, x, y)
        local row = self:rowAt(x, y)
        local entry = row and self.items[row] and self.items[row].item
        if type(entry) ~= "table" then return end
        self.manager:onRowClick(entry, x)
    end
    o:addChild(o.list)

    AegisClaimManager.instance = o
    o:requestList()
    return o
end

function AegisClaimManager:closeSelf()
    self:removeFromUIManager()
    if AegisClaimManager.instance == self then
        AegisClaimManager.instance = nil
    end
end

function AegisClaimManager:send(command, args)
    local p = getPlayer()
    if not p then return end
    sendClientCommand(p, AegisShared.MODULE, command, args or {})
end

function AegisClaimManager:requestList()
    self.askedAt = AegisShared.realTime()
    self:send("kitClaimList", { id = self.kitId })
end

function AegisClaimManager:onList(args)
    if type(args) ~= "table" or args.id ~= self.kitId then return end
    self.gotList = true
    self.total = tonumber(args.total) or 0
    self.allTotal = tonumber(args.allTotal) or 0
    self.readable = args.readable ~= false
    self.entries = {}
    self.list:clear()
    for _, e in ipairs(type(args.users) == "table" and args.users or {}) do
        if type(e) == "table" and type(e.user) == "string" then
            table.insert(self.entries, e)
            self.list:addItem(e.user, e)
        end
    end
end

function AegisClaimManager:onRowClick(entry, x)
    if not self.readable then return end
    if x < self.list:getWidth() - 6 - CLAIM_BTN_W then return end
    AegisConfirm.show(getText("UI_Aegis_KitClaimDrop"),
        getText("UI_Aegis_KitClaimDropMsg", entry.user),
        getText("UI_Aegis_KitClaimDrop"), self, function(mgr)
            mgr:send("kitClaimReset", { scope = "user", id = mgr.kitId, user = entry.user })
        end)
end

-- a typed reason instead of one more yes button: this one cannot be hit
-- by accident and the log keeps why the history went away
function AegisClaimManager:onResetAll()
    AegisPrompt.show({
        title = getText("UI_Aegis_KitClaimAll"),
        message = getText("UI_Aegis_KitClaimAllMsg", tostring(self.allTotal or 0)),
        confirmLabel = getText("UI_Aegis_KitClaimAll"),
        danger = true,
        reasonRequired = true,
        target = self,
        onConfirm = function(mgr, reason)
            mgr:send("kitClaimReset", { scope = "all", id = mgr.kitId, reason = reason })
        end,
    })
end

function AegisClaimManager.drawRow(list, y, item, alt)
    local c = Aegis.col
    local w = list:getWidth()
    local entry = item.item
    local hover = list.mouseoverselected == item.index
    if hover then
        Aegis.roundRect(list, 2, y + 1, w - 4, CLAIM_ROW_H - 2, 8, 0.4, c.card)
    end
    local zx = w - 6 - CLAIM_BTN_W
    local textW = zx - 18
    Aegis.text(list, Aegis.fitText(entry.user or "", UIFont.Small, textW), 10, y + 4, UIFont.Small, c.text)
    Aegis.text(list, Aegis.fitText(getText("UI_Aegis_KitClaimAt",
        AegisShared.timestampReadable(tonumber(entry.epoch) or 0)), UIFont.Small, textW), 10,
        y + 6 + Aegis.fontH(UIFont.Small), UIFont.Small, c.muted)

    local locked = list.manager and not list.manager.readable
    local a = locked and 0.35 or 1
    local by = y + math.floor((CLAIM_ROW_H - 24) / 2)
    Aegis.roundFrame(list, zx, by, CLAIM_BTN_W, 24, 12, a, c.danger, c.card)
    Aegis.textCentre(list, getText("UI_Aegis_KitClaimDrop"), zx + math.floor(CLAIM_BTN_W / 2),
        by + math.floor((24 - Aegis.fontH(UIFont.Small)) / 2), UIFont.Small, c.danger, a)
    return y + CLAIM_ROW_H
end

function AegisClaimManager:prerender()
    ISPanel.prerender(self)
    local c = Aegis.col
    local cx, cy = self.cardX, self.cardY
    Aegis.shadow(self, cx, cy, self.cardW, self.cardH, 26, 0.7)
    Aegis.roundFrame(self, cx, cy, self.cardW, self.cardH, 12, 1, c.line, c.bg)
    Aegis.icon(self, "clock", cx + 16, cy + 15, 15, 1, c.gold)
    Aegis.text(self, getText("UI_Aegis_KitClaimManage"), cx + 38, cy + 13, UIFont.Medium, c.text)

    Aegis.text(self, Aegis.fitText(self.kitName, UIFont.Small, self.cardW - 160), cx + 16, cy + 48,
        UIFont.Small, c.goldDim)
    Aegis.textRight(self, getText("UI_Aegis_KitClaimCount", tostring(self.total or 0)),
        cx + self.cardW - 16, cy + 48, UIFont.Small, c.muted)

    if not self.readable then
        Aegis.textCentre(self, getText("UI_Aegis_KitClaimsLocked"),
            cx + math.floor(self.cardW / 2), self.listY + 24, UIFont.Small, c.danger)
    elseif self.gotList and #self.entries == 0 then
        Aegis.textCentre(self, getText("UI_Aegis_KitClaimsEmpty"),
            cx + math.floor(self.cardW / 2), self.listY + 24, UIFont.Small, c.muted)
    elseif (self.total or 0) > #self.entries then
        -- the server caps the list, the rest is still reset by the buttons
        Aegis.textRight(self, getText("UI_Aegis_KitClaimMore", tostring((self.total or 0) - #self.entries)),
            cx + self.cardW - 16, cy + self.cardH - 84, UIFont.Small, c.muted)
    end

    Aegis.hairline(self, cx + 16, cy + self.cardH - 64, self.cardW - 32)
    self.allBtn.label = getText("UI_Aegis_KitClaimAll") .. " (" .. tostring(self.allTotal or 0) .. ")"
    self.allBtn:setEnabled(self.readable and (self.allTotal or 0) > 0)

    -- the list request is throttled server side, a first answer that got
    -- eaten by the page asking a moment earlier is picked up here
    if not self.gotList and AegisShared.realTime() - (self.askedAt or 0) > 2 then
        self:requestList()
    end
end

Events.OnServerCommand.Add(function(module, command, args)
    if module ~= AegisShared.MODULE then return end
    local mgr = AegisClaimManager.instance
    if not mgr then return end
    if command == "kitClaimList" then
        mgr:onList(args)
    end
end)
