-- Player management: list with avatars, detail card with 3D preview and actions
require "Aegis/AegisWindow"
require "Aegis/AegisInventory"
require "Aegis/AegisCompare"
require "Aegis/AegisRelations"
require "Aegis/AegisFollow"
require "Aegis/AegisPlayerStats"
require "ISUI/ISScrollingListBox"
require "ISUI/ISUI3DModel"
require "ISUI/ISTextEntryBox"

AegisPagePlayers = ISPanel:derive("AegisPagePlayers")
AegisPagePlayers.instance = nil

local LIST_W = 280
local ROW_H = 46

-- ==================================================================
-- AegisNote: small window for a player's private admin note
-- (persisted server side, all admins see the same note)
-- ==================================================================
AegisNote = ISPanel:derive("AegisNote")
-- running generation per opened window: tells the noteSaved reply of an
-- old (already closed) note apart from the current one, see
-- receiveNoteSaved
local aegisNoteGenCounter = 0

function AegisNote.show(target, page)
    if AegisNote.instance then AegisNote.instance:close() end
    local sw, sh = getCore():getScreenWidth(), getCore():getScreenHeight()
    local w, h = 460, 320
    local o = ISPanel:new(math.floor((sw - w) / 2), math.floor((sh - h) / 2), w, h)
    setmetatable(o, AegisNote)
    AegisNote.__index = AegisNote
    o.background = false
    o.target = target
    o.page = page
    o.loaded = false
    o.touched = false
    o.version = 0
    aegisNoteGenCounter = aegisNoteGenCounter + 1
    o.gen = aegisNoteGenCounter
    o:initialise()
    o:addToUIManager()
    o:setAlwaysOnTop(true)
    AegisNote.instance = o
    sendClientCommand(getPlayer(), "AegisAdmin", "noteGet", { target = target })
    return o
end

function AegisNote:createChildren()
    self.entry = ISTextEntryBox:new("", 20, 56, self.width - 40, self.height - 56 - 52)
    self.entry:initialise()
    self.entry:instantiate()
    self.entry.font = UIFont.Small
    self.entry:setMultipleLine(true)
    self.entry:setMaxLines(40)
    self.entry.javaObject:setEditable(true)
    local note = self
    self.entry.onTextChange = function() note.touched = true end
    self:addChild(self.entry)

    local bw = math.floor((self.width - 48) / 2)
    self.saveBtn = AegisButton:new(20, self.height - 44, bw, 32, getText("UI_Aegis_NoteSave"), "check", self, AegisNote.onSave)
    self.saveBtn.style = "gold"
    -- only savable once the existing note is loaded, otherwise a too
    -- early click overwrites it with the still empty field
    self.saveBtn:setEnabled(false)
    self:addChild(self.saveBtn)
    self.closeBtn = AegisButton:new(28 + bw, self.height - 44, bw, 32, getText("UI_Aegis_Cancel"), nil, self, AegisNote.close)
    self:addChild(self.closeBtn)
end

function AegisNote:applyText(lines, version)
    -- if the admin already started typing before the reply arrived,
    -- the typed text wins instead of being overwritten by the server reply
    if not self.touched then
        self.entry:setText(table.concat(lines or {}, "\n"))
    end
    self.loaded = true
    self.version = version or 0
    self.saveBtn:setEnabled(true)
end

function AegisNote.onSave(self)
    if not self.loaded then return end
    -- close only after the server reply: on a version conflict
    -- (see receiveNoteConflict) the window stays open instead of
    -- pretending the note was already saved
    self.saveBtn:setEnabled(false)
    sendClientCommand(getPlayer(), "AegisAdmin", "noteSet", {
        target = self.target, text = self.entry:getInternalText() or "", version = self.version or 0, gen = self.gen,
    })
end

function AegisNote:close()
    self:removeFromUIManager()
    if AegisNote.instance == self then AegisNote.instance = nil end
end

function AegisNote:prerender()
    local c = Aegis.col
    Aegis.shadow(self, 0, 0, self.width, self.height, 26, 0.7)
    Aegis.roundFrame(self, 0, 0, self.width, self.height, 12, 1, c.line, c.bg)
    Aegis.icon(self, "logs", 18, 16, 18, 1, c.gold)
    Aegis.text(self, getText("UI_Aegis_NoteTitle") .. " " .. tostring(self.target), 46, 18, UIFont.Medium, c.text)
    Aegis.roundFrame(self, 20, 56, self.width - 40, self.height - 56 - 52, 6, 1, c.line, c.dark)
end

function AegisPagePlayers.create(window, x, y, w, h)
    local o = ISPanel:new(x, y, w, h)
    setmetatable(o, AegisPagePlayers)
    AegisPagePlayers.__index = AegisPagePlayers
    o.background = false
    o.window = window
    o.selected = nil
    o.selectedObj = nil
    o.buttons = {}
    o.showOffline = false
    AegisPagePlayers.instance = o
    return o
end

function AegisPagePlayers:createChildren()
    local pad = 20

    self.list = ISScrollingListBox:new(pad + 1, pad + 44, LIST_W - 2, self.height - pad * 2 - 45)
    self.list:initialise()
    self.list:instantiate()
    self.list.itemheight = ROW_H
    self.list.font = UIFont.Medium
    self.list.drawBorder = false
    self.list.backgroundColor = { r = 0, g = 0, b = 0, a = 0 }
    self.list.doDrawItem = AegisPagePlayers.drawPlayerRow
    self.list:setOnMouseDownFunction(self, AegisPagePlayers.onSelectPlayer)
    self:addChild(self.list)

    self.refreshBtn = AegisButton:new(pad + LIST_W - 36, pad + 6, 30, 28, nil, "refresh", self, AegisPagePlayers.requestRefresh)
    self:addChild(self.refreshBtn)

    -- add offline users: the vanilla path getUsers()/requestUsers()
    -- returns the full server user catalog, not just online players
    self.offlineBtn = AegisButton:new(pad + LIST_W - 36 - 34, pad + 6, 30, 28, nil, "eye", self, AegisPagePlayers.onToggleOffline)
    self.offlineBtn.tooltip = getText("UI_Aegis_ShowOffline")
    if not isClient() then self.offlineBtn:setEnabled(false) end
    self:addChild(self.offlineBtn)

    -- detail page on the right
    local dx = pad + LIST_W + 20
    local dw = self.width - dx - pad

    self.model = ISUI3DModel:new(dx + 18, pad + 56, 120, 200)
    self.model:setVisible(false)
    self:addChild(self.model)

    local actions = {
        { key = "tpTo",  label = "UI_Aegis_TeleportTo", icon = "pin",   mpOnly = true },
        { key = "bring", label = "UI_Aegis_Bring",      icon = "bring", mpOnly = true },
        { key = "follow", label = "UI_Aegis_Follow",    icon = "ghost", mpOnly = true, tooltip = "UI_Aegis_FollowTooltip" },
        { key = "heal",  label = "UI_Aegis_Heal",       icon = "heal", tooltip = "UI_Aegis_HealTooltip" },
        { key = "care",  label = "UI_Aegis_Care",       icon = "check", tooltip = "UI_Aegis_CareTooltip" },
        { key = "giveItem", label = "UI_Aegis_GiveItem", icon = "plus" },
        { key = "inv",   label = "UI_Aegis_Inventory",  icon = "items", tooltip = "UI_Aegis_InventoryTooltip" },
        { key = "god",   label = "UI_Aegis_ToggleGod",  icon = "shield", mpOnly = true },
        { key = "invis", label = "UI_Aegis_ToggleInvisible", icon = "eye", mpOnly = true },
        { key = "stats", label = "UI_Aegis_OpenStats",  icon = "gear" },
        { key = "cmp",   label = "UI_Aegis_CmpOpen", icon = "search" },
        { key = "rel",   label = "UI_Aegis_RelOpen", icon = "players" },
        { key = "repair", label = "UI_Aegis_Repair",    icon = "wand", tooltip = "UI_Aegis_RepairTooltip" },
        { key = "carry", label = "UI_Aegis_CarryWeight", icon = "items", tooltip = "UI_Aegis_CarryWeightTooltip" },
        { key = "note",  label = "UI_Aegis_Note",       icon = "logs", tooltip = "UI_Aegis_NoteTooltip" },
        -- warn and mute in solo too: the workshop needs a way to test
        -- the flows including the log against oneself
        { key = "warn",  label = "UI_Aegis_Warn",       icon = "bolt" },
        { key = "mute",  label = "UI_Aegis_Mute",       icon = "ghost", tooltip = "UI_Aegis_MuteTooltip" },
        { key = "kick",  label = "UI_Aegis_Kick",       icon = "kick",  mpOnly = true, danger = true },
        { key = "tempban", label = "UI_Aegis_TempBan",  icon = "clock", mpOnly = true, danger = true },
        { key = "ban",   label = "UI_Aegis_Ban",        icon = "ban",   mpOnly = true, danger = true },
        -- purely username based like warn/mute/ban, so it also works
        -- against a name that is not online right now (the usual case
        -- for a banned player)
        { key = "unban", label = "UI_Aegis_Unban",      icon = "check", mpOnly = true, gold = true },
        { key = "statsreset", label = "UI_Aegis_StatsReset", icon = "refresh", danger = true,
            tooltip = "UI_Aegis_StatsResetTooltip" },
    }
    local bx = dx + 160
    local bw = math.floor((dw - 160 - 30) / 2)
    local startY = pad + 118

    -- adapt row height to the available height (like the nav condensing
    -- in AegisWindow): in MP with all 16 actions the lower rows ran past
    -- the card frame at tight window heights (~560px)
    local visibleCount = 0
    for _, def in ipairs(actions) do
        if not def.mpOnly or isClient() then visibleCount = visibleCount + 1 end
    end
    local rowCount = math.max(1, math.ceil(visibleCount / 2))
    local available = (self.height - pad) - startY
    local stepY, btnH = 44, 36
    if rowCount * stepY > available then
        stepY = math.max(30, math.floor(available / rowCount))
        btnH = math.max(22, stepY - 8)
    end

    local by = startY
    local col = 0
    for _, def in ipairs(actions) do
        if not def.mpOnly or isClient() then
            local btn = AegisButton:new(bx + col * (bw + 12), by, bw, btnH, getText(def.label), def.icon, self, AegisPagePlayers["on_" .. def.key])
            if def.danger then btn.style = "danger" elseif def.gold then btn.style = "gold" end
            if def.tooltip then btn.tooltip = getText(def.tooltip) end
            btn:setEnabled(false)
            btn:setVisible(false)
            self:addChild(btn)
            self.buttons[def.key] = btn
            col = col + 1
            if col == 2 then
                col = 0
                by = by + stepY
            end
        end
    end

    self:fillList()
end

-- ------------------------------------------------------------------
-- List
-- ------------------------------------------------------------------

function AegisPagePlayers:fillList()
    -- drop the offline cache on every refill, otherwise it lags behind
    -- the online section: without this a player who was online while the
    -- cache was built would vanish from the WHOLE list after disconnect
    -- instead of moving to the offline section (see offlineUsers)
    self.offlineCache = nil
    self.list:clear()
    -- clear() sets selected to 1, but nothing should be marked without a real selection
    self.list.selected = -1
    if isClient() then
        local known = {}
        local rows = Aegis.scoreboard or {}
        for _, row in ipairs(rows) do
            row.online = true
            known[row.username] = true
            self.list:addItem(row.displayName, row)
        end
        if self.showOffline then
            for _, entry in ipairs(self:offlineUsers()) do
                if not known[entry.username] then
                    self.list:addItem(entry.displayName, entry)
                end
            end
        end
    else
        local p = getPlayer()
        if p then
            self.list:addItem(p:getDescriptor():getForename(), {
                username = p:getUsername(),
                displayName = p:getDescriptor():getForename() .. " " .. p:getDescriptor():getSurname(),
                avatar = nil,
                solo = true,
                online = true,
            })
        end
    end
    -- rebind selection to the new rows
    if self.selected then
        for i, item in ipairs(self.list.items) do
            if item.item.username == self.selected.username then
                self.list.selected = i
                return
            end
        end
        self:select(nil)
    end
end

-- a full user catalog pass is cached within one fillList pass (repeated
-- calls read the same build), but fillList itself drops the cache on
-- every pass, otherwise the offline view lags behind online changes
function AegisPagePlayers:offlineUsers()
    if self.offlineCache then return self.offlineCache end
    local list = {}
    local users = getUsers()
    if users then
        for i = 0, users:size() - 1 do
            local u = users:get(i)
            local name = u:getUsername()
            local online = u:isOnline()
            if name and not online then
                local display = u:getDisplayName()
                if not display or display == "" then display = name end
                local lastConn = u:getLastConnection()
                -- a vanilla ban is already visible client side here
                -- (NetworkUser role "banned"); the Aegis ban list is
                -- known only to the server, see banStatus
                local r = u:getRole()
                local vanillaBanned = r ~= nil and r:getName() == "banned"
                table.insert(list, {
                    username = name, displayName = display, avatar = nil,
                    online = false, lastConnection = lastConn, vanillaBanned = vanillaBanned,
                })
            end
        end
    end
    self.offlineCache = list
    return list
end

function AegisPagePlayers.onToggleOffline(self)
    self.showOffline = not self.showOffline
    self.offlineCache = nil
    if self.showOffline and isClient() then
        requestUsers()
    end
    self:fillList()
end

function AegisPagePlayers.drawPlayerRow(list, y, item, alt)
    local c = Aegis.col
    local sel = list.selected == item.index
    local hover = list.mouseoverselected == item.index

    if sel then
        Aegis.roundRect(list, 2, y + 2, list:getWidth() - 4, ROW_H - 4, 8, 1, c.card)
        Aegis.roundRect(list, 2, y + 10, 3, ROW_H - 20, 1, 1, c.gold)
    elseif hover then
        Aegis.roundRect(list, 2, y + 2, list:getWidth() - 4, ROW_H - 4, 8, 0.5, c.card)
    end

    local data = item.item
    local offline = data.online == false
    local ax = 14
    local circleA = offline and 0.4 or 1
    if data.avatar then
        list:drawTextureScaled(data.avatar, ax, y + math.floor((ROW_H - 32) / 2), 32, 32, circleA, 1, 1, 1)
    else
        Aegis.roundRect(list, ax, y + math.floor((ROW_H - 32) / 2), 32, 32, 16, circleA, c.cardHi)
        local initial = string.upper(string.sub(data.displayName or "?", 1, 1))
        Aegis.textCentre(list, initial, ax + 16, y + math.floor((ROW_H - Aegis.fontH(UIFont.Medium)) / 2), UIFont.Medium, offline and c.muted or c.gold)
    end
    local tagW = 0
    if offline then
        local tag = getText("UI_Aegis_Offline")
        tagW = Aegis.strW(UIFont.Small, tag) + 12
        Aegis.textRight(list, tag, list:getWidth() - 12, y + 6, UIFont.Small, c.muted)
    end
    local tc = offline and c.muted or (sel and c.text or c.muted)
    local nameW = list:getWidth() - (ax + 42) - 10 - tagW
    if data._fitW ~= nameW then
        data._fitW = nameW
        data._fit = Aegis.fitText(data.displayName or data.username, UIFont.Medium, nameW)
    end
    Aegis.text(list, data._fit, ax + 42, y + 6, UIFont.Medium, tc)
    local subLine = data.username and data.username ~= data.displayName and data.username or nil
    if offline and data.lastConnection and data.lastConnection ~= "" then
        subLine = (subLine and (subLine .. "  ") or "") .. getText("UI_Aegis_LastSeen", data.lastConnection)
    end
    if subLine then
        Aegis.text(list, Aegis.fitText(subLine, UIFont.Small, list:getWidth() - (ax + 42) - 10), ax + 42, y + 8 + Aegis.fontH(UIFont.Medium), UIFont.Small, c.muted)
    end
    return y + ROW_H
end

function AegisPagePlayers.onSelectPlayer(self, item)
    self:select(item)
end

function AegisPagePlayers:select(data)
    self.selected = data
    self.selectedObj = nil
    if data then
        if data.solo then
            self.selectedObj = getPlayer()
        else
            self.selectedObj = getPlayerFromUsername(data.username)
        end
    end
    if self.selectedObj then
        self.model:setState("idle")
        self.model:setDirection(IsoDirections.S)
        self.model:setIsometric(false)
        self.model:setCharacter(self.selectedObj)
        self.model:setVisible(true)
    else
        self.model:setVisible(false)
    end
    for key, btn in pairs(self.buttons) do
        btn:setEnabled(data ~= nil)
        btn:setVisible(data ~= nil)
    end
    if data then
        -- no range gate here: the actions are
        -- username based almost throughout, either a quoted slash command
        -- or a server command whose resolveTarget falls back to
        -- findByUsername, and the server sees every online player no
        -- matter how far away. The old blanket rule "no streamed object,
        -- no button" came from the offline rows and wrongly caught online
        -- players outside the own streaming range as well. The few
        -- actions that really need the object now say so on click:
        -- stats below, the inventory viewer via resolveID

        -- only currently connected players can be kicked
        if self.buttons.kick and data.online == false then
            self.buttons.kick:setEnabled(false)
        end
        -- follow needs a live connection too; distance does not matter,
        -- the position comes from the server
        if self.buttons.follow and data.online == false then
            self.buttons.follow:setEnabled(false)
        end
        -- offer unban only when actually banned (it was
        -- always active before). Online = definitely not banned (the guard
        -- in Aegis_Moderation.lua would throw banned players right back
        -- out). A vanilla ban is already known via the NetworkUser role
        -- (fillList), the Aegis ban list only the server knows, so a
        -- short request for that
        if self.buttons.unban then
            if data.online ~= false then
                self.buttons.unban:setEnabled(false)
            elseif data.vanillaBanned then
                self.buttons.unban:setEnabled(true)
            else
                self.buttons.unban:setEnabled(false)
                self.banStatusQuery = data.username
                sendClientCommand(getPlayer(), "AegisAdmin", "banStatus", { target = data.username })
            end
        end
        -- repair only affects your own inventory
        local me = getPlayer() and getPlayer():getUsername()
        if self.buttons.repair then self.buttons.repair:setEnabled(data.username == me or data.solo == true) end
        -- you do not kick or fetch yourself
        if data.username == me then
            for _, key in ipairs({ "tpTo", "bring", "follow", "kick", "ban", "god", "invis" }) do
                if self.buttons[key] then self.buttons[key]:setEnabled(false) end
            end
            -- self warnings exist only in the solo workshop, in MP the
            -- server would silently drop them
            if isClient() and self.buttons.warn then
                self.buttons.warn:setEnabled(false)
            end
        end
    end
end

function AegisPagePlayers.requestRefresh(self)
    -- a real refresh should also refresh the offline cache, not just
    -- the online list
    self.offlineCache = nil
    if isClient() then
        scoreboardUpdate()
    else
        self:fillList()
    end
end

-- window resize rebuilds the page; selection and the offline switch
-- travel to the successor so the admin stays on his player
function AegisPagePlayers:saveState()
    return {
        username = self.selected and self.selected.username or nil,
        showOffline = self.showOffline,
    }
end

function AegisPagePlayers:restoreState(state)
    if type(state) ~= "table" then return end
    self.showOffline = state.showOffline == true
    self:fillList()
    if not state.username then return end
    for i, item in ipairs(self.list.items) do
        if item.item and item.item.username == state.username then
            self.list.selected = i
            self:select(item.item)
            return
        end
    end
end

function AegisPagePlayers:onShow()
    self:requestRefresh()
    self:fillList()
end

-- ------------------------------------------------------------------
-- Actions
-- ------------------------------------------------------------------

-- strip quotes, backslashes and control chars before the name lands in a
-- quoted vanilla slash command token: the server tokenizer has no escaping,
-- a " inside would end the token early and smuggle the rest in as an extra
-- argument (same pattern as cleanReason in Aegis_Moderation.lua)
local function quoted(name)
    name = tostring(name or ""):gsub("%c", " "):gsub("[\"\\]", " ")
    return "\"" .. name .. "\""
end

function AegisPagePlayers.on_tpTo(self)
    if not self.selected then return end
    -- seated in a vehicle the car comes along, on foot this falls back to
    -- the vanilla slash command which bypasses Aegis; entry goes through
    -- the relay, wording states intent, the server can still refuse
    Aegis.teleportSmart(nil, nil, nil, self.selected.username)
    Aegis.logAction("players", "Teleport requested to " .. self.selected.username)
end

function AegisPagePlayers.on_bring(self)
    if not self.selected then return end
    local me = getPlayer():getUsername()
    SendCommandToServer("/teleportplayer " .. quoted(self.selected.username) .. " " .. quoted(me))
    Aegis.logAction("players", "Fetch requested: " .. self.selected.username)
end

-- toggles the spectator follow; AegisFollow logs start and stop itself
function AegisPagePlayers.on_follow(self)
    if not self.selected then return end
    AegisFollow.start(self.selected.username)
end

function AegisPagePlayers.on_heal(self)
    if not self.selected then return end
    local args = {}
    if isClient() then
        args = { id = -1, username = self.selected.username }
        if self.selectedObj then args.id = self.selectedObj:getOnlineID() end
    end
    -- fires in-process in solo, the handler heals and logs
    sendClientCommand(getPlayer(), "AegisAdmin", "heal", args)
    Aegis.showToast(getText("UI_Aegis_Heal") .. ": " .. (self.selected.displayName or self.selected.username))
end

-- set the target's max carry weight: number prompt, the target client
-- applies it (server relay like heal, stats are player-owned)
function AegisPagePlayers.on_carry(self)
    if not self.selected then return end
    local target = self.selected.displayName or self.selected.username
    local prompt = AegisPrompt.show{
        title = getText("UI_Aegis_CarryWeight"),
        message = getText("UI_Aegis_CarryWeightPrompt", target) .. " " .. getText("UI_Aegis_CarryWeightHint"),
        confirmLabel = getText("UI_Aegis_Apply"),
        reasonRequired = true,
        target = self,
        onConfirm = function(page, textValue)
            local value = tonumber(textValue)
            if not value then return end
            value = math.floor(value)
            -- 0 restores the game default, everything else clamps to range
            if value ~= 0 then value = math.max(5, math.min(1000, value)) end
            local args = { value = value }
            if isClient() then
                args.id = -1
                args.username = page.selected and page.selected.username
                if page.selectedObj then args.id = page.selectedObj:getOnlineID() end
            end
            sendClientCommand(getPlayer(), "AegisAdmin", "carryWeight", args)
            Aegis.showToast(getText("UI_Aegis_CarryWeight") .. ": " .. tostring(value))
        end,
    }
    pcall(function() prompt.entry:setOnlyNumbers(true) end)
end

function AegisPagePlayers.on_care(self)
    if not self.selected then return end
    local args = {}
    if isClient() then
        args = { id = -1, username = self.selected.username }
        if self.selectedObj then args.id = self.selectedObj:getOnlineID() end
    end
    sendClientCommand(getPlayer(), "AegisAdmin", "care", args)
    Aegis.showToast(getText("UI_Aegis_Care") .. ": " .. (self.selected.displayName or self.selected.username))
end

function AegisPagePlayers.on_inv(self)
    if not self.selected then return end
    local id = self.selectedObj and self.selectedObj:getOnlineID() or -1
    AegisInventory.show(self.selected.username, id, self.selected.displayName)
end

function AegisPagePlayers.on_giveItem(self)
    if not self.selected then return end
    local target = self.selected.username
    self.window:switchPage("items")
    local itemsPage = self.window:page("items")
    if itemsPage and itemsPage.selectTargetUsername then
        itemsPage:selectTargetUsername(target)
    end
end

function AegisPagePlayers.on_repair(self)
    local p = getPlayer()
    if not p then return end
    local items = p:getInventory():getItems()
    for i = 0, items:size() - 1 do
        local it = items:get(i)
        if it:getCondition() < it:getConditionMax() then
            it:setCondition(it:getConditionMax())
        end
    end
    Aegis.logAction("players", "Own gear repaired")
    Aegis.showToast(getText("UI_Aegis_Repair"))
end

function AegisPagePlayers.on_god(self)
    if not self.selected then return end
    SendCommandToServer("/godmodplayer " .. quoted(self.selected.username))
    -- the vanilla command toggles, only the server knows the target state
    Aegis.logAction("players", "Godmode toggle requested: " .. self.selected.username)
end

function AegisPagePlayers.on_invis(self)
    if not self.selected then return end
    SendCommandToServer("/invisibleplayer " .. quoted(self.selected.username))
    Aegis.logAction("players", "Invisibility toggle requested: " .. self.selected.username)
end

-- own window instead of ISPlayerStatsUI: it reads and writes through the
-- server, so a streamed object is no longer needed and a player outside the
-- own range works. Only a live connection is still required, offline
-- characters live in ServerPlayerDB which is not exposed to Lua
function AegisPagePlayers.on_stats(self)
    if not self.selected then return end
    if isClient() and self.selected.online == false then
        Aegis.showToast(getText("UI_Aegis_Offline"))
        return
    end
    local id = self.selectedObj and self.selectedObj:getOnlineID() or -1
    AegisPlayerStats.open(self.selected.username, id, self.selected.displayName)
end

function AegisPagePlayers.on_cmp(self)
    if not self.selected then return end
    AegisCompare.open(self.selected.username)
end

function AegisPagePlayers.on_rel(self)
    if not self.selected then return end
    AegisRelations.open(self.selected.username)
end

local function modAction(kind, target, reason, hours)
    sendClientCommand(getPlayer(), "AegisAdmin", "modAction", {
        kind = kind, target = target, reason = reason or "", hours = hours,
    })
end

function AegisPagePlayers.on_kick(self)
    if not self.selected then return end
    local name = self.selected.username
    AegisPrompt.show({
        title = getText("UI_Aegis_Kick"),
        message = getText("UI_Aegis_ConfirmKick", name),
        confirmLabel = getText("UI_Aegis_Kick"),
        danger = true,
        target = self,
        onConfirm = function(_, reason) modAction("kick", name, reason) end,
    })
end

function AegisPagePlayers.on_ban(self)
    if not self.selected then return end
    local name = self.selected.username
    AegisPrompt.show({
        title = getText("UI_Aegis_Ban"),
        message = getText("UI_Aegis_ConfirmBan", name),
        confirmLabel = getText("UI_Aegis_Ban"),
        danger = true,
        reasonRequired = true,
        target = self,
        onConfirm = function(_, reason) modAction("ban", name, reason) end,
    })
end

Events.OnServerCommand.Add(function(module, command, args)
    if module ~= "AegisPlayer" or command ~= "statsReset" then return end
    if args and args.ok then
        Aegis.showToast(getText("UI_Aegis_StatsResetDone", tonumber(args.touched) or 0))
    end
end)

-- opens the picker for the recorded statistics. Counters that ran wrong
-- cannot be recomputed afterwards, nothing records which kills or deaths
-- were real, so clearing them is the only honest repair
function AegisPagePlayers.on_statsreset(self)
    if not self.selected then return end
    AegisStatsReset.show(self.selected.username)
end

function AegisPagePlayers.on_unban(self)
    if not self.selected then return end
    local name = self.selected.username
    AegisConfirm.show(getText("UI_Aegis_Unban"), getText("UI_Aegis_ConfirmUnban", name),
        getText("UI_Aegis_Unban"), self, function()
            sendClientCommand(getPlayer(), "AegisAdmin", "unban", { target = name })
        end)
end

function AegisPagePlayers.on_tempban(self)
    if not self.selected then return end
    local name = self.selected.username
    AegisPrompt.show({
        title = getText("UI_Aegis_TempBan"),
        message = getText("UI_Aegis_ConfirmTempBan", name),
        confirmLabel = getText("UI_Aegis_TempBan"),
        danger = true,
        reasonRequired = true,
        chips = {
            { label = "1 h", value = 1 }, { label = "12 h", value = 12 },
            { label = getText("UI_Aegis_Day1"), value = 24 }, { label = getText("UI_Aegis_Day3"), value = 72 },
            { label = getText("UI_Aegis_Day7"), value = 168 },
        },
        target = self,
        onConfirm = function(_, reason, hours) modAction("tempban", name, reason, hours or 24) end,
    })
end

function AegisPagePlayers.on_warn(self)
    if not self.selected then return end
    local name = self.selected.username
    AegisPrompt.show({
        title = getText("UI_Aegis_Warn"),
        message = getText("UI_Aegis_ConfirmWarn", name),
        confirmLabel = getText("UI_Aegis_Warn"),
        reasonRequired = true,
        target = self,
        onConfirm = function(_, reason) modAction("warn", name, reason) end,
    })
end

function AegisPagePlayers.on_mute(self)
    if not self.selected then return end
    local name = self.selected.username
    AegisPrompt.show({
        title = getText("UI_Aegis_Mute"),
        message = getText("UI_Aegis_ConfirmMute", name),
        confirmLabel = getText("UI_Aegis_Mute"),
        -- a real duration comes first, otherwise the dialog opens with
        -- "unmute" preselected and a too early click lifts the mute
        -- instead of setting it
        chips = {
            { label = "15 min", value = 15 }, { label = "5 min", value = 5 },
            { label = "30 min", value = 30 }, { label = "60 min", value = 60 },
            { label = getText("UI_Aegis_Unmute"), value = 0 },
        },
        target = self,
        onConfirm = function(_, reason, minutes)
            -- 0 is truthy in Lua: "minutes or 15" would wrongly bump a
            -- deliberate unmute (0) back to 15 minutes
            if minutes == nil then minutes = 15 end
            sendClientCommand(getPlayer(), "AegisAdmin", "muteSet", { target = name, reason = reason, minutes = minutes })
        end,
    })
end

function AegisPagePlayers.on_note(self)
    if not self.selected then return end
    AegisNote.show(self.selected.username, self)
end

function AegisPagePlayers:receiveNote(args)
    if AegisNote.instance and args and AegisNote.instance.target == args.target then
        AegisNote.instance:applyText(args.lines, args.version)
    end
end

function AegisPagePlayers:receiveNoteSaved(args)
    -- target alone is not enough: if the admin closes/reopens the note
    -- before the reply to an older save attempt arrives, the late reply
    -- would hit the NEW instance and silently drop unsaved typing,
    -- see AegisNote.show/gen
    if AegisNote.instance and args and AegisNote.instance.target == args.target and AegisNote.instance.gen == args.gen then
        Aegis.showToast(getText("UI_Aegis_NoteSaved"))
        AegisNote.instance:close()
    end
end

-- server detected a version conflict (another admin saved since loading):
-- warn and reload the current version. If the admin already typed
-- (touched), applyText keeps his text and only takes over the fresh
-- version, a second save then goes through; without own changes it just
-- shows the new note
function AegisPagePlayers:receiveNoteConflict(args)
    if not (AegisNote.instance and args and AegisNote.instance.target == args.target) then return end
    Aegis.showToast(getText("UI_Aegis_NoteConflict"))
    AegisNote.instance.saveBtn:setEnabled(true)
    sendClientCommand(getPlayer(), "AegisAdmin", "noteGet", { target = args.target })
end

-- banStatus reply: apply only if the selection has not changed since,
-- otherwise a late reply for the OLD player would enable the button
-- for the NEW one
function AegisPagePlayers:receiveBanStatus(args)
    if not args or self.banStatusQuery ~= args.target then return end
    if not self.selected or self.selected.username ~= args.target then return end
    if self.buttons.unban then
        self.buttons.unban:setEnabled(args.banned == true)
    end
end

-- ------------------------------------------------------------------
-- Frame
-- ------------------------------------------------------------------

function AegisPagePlayers:prerender()
    local c = Aegis.col
    local pad = 20

    Aegis.roundFrame(self, pad, pad, LIST_W, self.height - pad * 2, 10, 1, c.line, c.panel)
    Aegis.icon(self, "players", pad + 14, pad + 12, 15, 1, c.gold)
    Aegis.text(self, getText("UI_Aegis_NavPlayers"), pad + 36, pad + 10, UIFont.Medium, c.text)
    if self.offlineBtn then self.offlineBtn.style = self.showOffline and "gold" or "ghost" end
    if self.buttons.follow then
        local active = self.selected and AegisFollow.current() == self.selected.username
        self.buttons.follow.style = active and "gold" or "ghost"
    end

    local dx = pad + LIST_W + 20
    local dw = self.width - dx - pad
    Aegis.roundFrame(self, dx, pad, dw, self.height - pad * 2, 10, 1, c.line, c.panel)

    if self.selected then
        Aegis.roundFrame(self, dx + 14, pad + 52, 128, 208, 8, 1, c.line, c.dark)
        Aegis.text(self, self.selected.displayName or self.selected.username, dx + 160, pad + 52, UIFont.Large, c.text)
        if self.selected.username then
            Aegis.text(self, self.selected.username, dx + 160, pad + 56 + Aegis.fontH(UIFont.Large), UIFont.Small, c.muted)
        end
        if not self.selectedObj and isClient() then
            -- short and limited to the avatar column (128px): a longer
            -- line used to run under the action buttons to the right
            local hint = self.selected.online == false and getText("UI_Aegis_Offline") or getText("UI_Aegis_OutOfRange")
            Aegis.text(self, Aegis.fitText(hint, UIFont.Small, 128), dx + 14, pad + 268, UIFont.Small, c.muted)
        end
    else
        Aegis.textCentre(self, getText("UI_Aegis_NoSelection"), dx + math.floor(dw / 2), math.floor(self.height / 2), UIFont.Medium, c.muted)
    end
end

-- scoreboard arrival: fill the global cache, refresh the page
local function onScoreboard(usernames, displayNames, steamIDs)
    local rows = {}
    for i = 0, usernames:size() - 1 do
        local row = {
            username = usernames:get(i),
            displayName = displayNames:get(i),
        }
        if getSteamModeActive() and steamIDs then
            row.steamID = steamIDs:get(i)
            row.avatar = getSteamAvatarFromSteamID(row.steamID)
        end
        table.insert(rows, row)
    end
    Aegis.scoreboard = rows
    local page = AegisPagePlayers.instance
    if page and page:isVisible() and AegisWindow.instance then
        page:fillList()
    end
end

Events.OnScoreboardUpdate.Add(onScoreboard)

Events.OnMiniScoreboardUpdate.Add(function()
    if isClient() and AegisWindow.instance then
        scoreboardUpdate()
    end
end)

AegisWindow.registerPage({
    id = "players",
    icon = "players",
    label = "UI_Aegis_NavPlayers",
    create = AegisPagePlayers.create,
})
