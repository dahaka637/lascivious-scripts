-- Server options: every synced public option grouped and searchable,
-- changes go out through the vanilla /changeoption chat command which
-- needs the ChangeAndReloadServerOptions capability and persists to the
-- INI on the server by itself
require "Aegis/AegisWindow"
require "ISUI/ISComboBox"
require "ISUI/ISTextEntryBox"
require "ISUI/ISLabel"

AegisPageOptions = ISPanel:derive("AegisPageOptions")

local NAV_W = 200
local ROW_H = 42
local NAV_ROW_H = 32
-- spacing between two /changeoption sends, the chat pipe is one line per
-- command and a burst of 20+ lines in one tick is asking for trouble
local SEND_GAP_MS = 150

-- the 7 options the server never syncs, the client copy only carries
-- their defaults, so a real value must never be shown here
local SECRET_ORDER = {
    "Password", "RCONPort", "RCONPassword", "DiscordToken",
    "DiscordChatChannel", "DiscordLogChannel", "DiscordCommandChannel",
}
local SECRET = {}
for _, n in ipairs(SECRET_ORDER) do SECRET[string.lower(n)] = true end

-- never editable from this page: the secrets plus everything where a
-- typo silently kills the server (Mods/WorkshopItems live experience of
-- the operator) or cuts the connection out from under every client
local LOCKED_EXTRA = {}
for _, n in ipairs({
    "DefaultPort", "UDPPort", "Map", "Mods", "WorkshopItems",
    "ServerPlayerID", "SteamPort1", "SteamPort2",
}) do LOCKED_EXTRA[string.lower(n)] = true end

-- the operator may open exactly these two behind a double warning, per
-- panel session only: the warning stays effective
local RISK_UNLOCK = { mods = true, workshopitems = true }

-- options only read at boot (bytecode verified list, kept maintainable):
-- exact names plus a few whole families by prefix
local RESTART_EXACT = {}
for _, n in ipairs({
    "DefaultPort", "UDPPort", "Map", "Mods", "WorkshopItems", "MaxPlayers",
    "UPnP", "Seed", "ResetID", "ServerPlayerID", "ServerBrowserAnnouncedIP",
    "Password",
}) do RESTART_EXACT[string.lower(n)] = true end
local RESTART_PREFIX = { "rcon", "discord", "backups", "steamport" }

-- substring grouping misfires on three names (ForWARd, ToSEEDisplay,
-- PeRCONtainer), they belong to the general group
local GROUP_EXCEPT = {
    fastforwardmultiplier = true,
    mouseovertoseedisplayname = true,
    itemnumberslimitpercontainer = true,
}

-- server options carry no vanilla categories, so group by name patterns.
-- Array order is the nav order, CLASSIFY below decides match priority
-- (discord before chat, otherwise DiscordChatChannel lands in chat)
local GROUPS = {
    { id = "pvp",       label = "UI_Aegis_OptGroupPvp",       match = { "pvp", "safety", "war", "knockeddown", "hitreaction" } },
    { id = "safehouse", label = "UI_Aegis_OptGroupSafehouse", match = { "safehouse", "safezone", "sledgehammer" } },
    { id = "factions",  label = "UI_Aegis_OptGroupFactions",  match = { "faction" } },
    { id = "chat",      label = "UI_Aegis_OptGroupChat",      match = { "chat", "voice", "badword", "goodword", "welcome", "radio" } },
    { id = "anticheat", label = "UI_Aegis_OptGroupAntiCheat", match = { "anticheat", "checksum", "steamvac" } },
    { id = "discord",   label = "UI_Aegis_OptGroupDiscord",   match = { "discord", "webhook" } },
    { id = "backup",    label = "UI_Aegis_OptGroupBackup",    match = { "backup", "saveworld" } },
    { id = "net",       label = "UI_Aegis_OptGroupNet",       match = { "map", "mods", "workshop", "port", "upnp", "seed", "public", "steam", "ping", "rcon", "password", "resetid", "serverbrowser", "serverplayerid", "maxplayers", "login", "open", "coop" } },
    { id = "general",   label = "UI_Aegis_OptGroupGeneral",   match = {} },
}
local CLASSIFY = { "anticheat", "discord", "pvp", "safehouse", "factions", "chat", "backup", "net" }

-- ------------------------------------------------------------------
-- Send queue: one /changeoption per SEND_GAP_MS, module level so a page
-- rebuild (window resize) cannot cut a running batch short. The own
-- client copy is patched after each send (/changeoption does not
-- broadcast, other admins keep old values until /reloadoptions)
-- ------------------------------------------------------------------
local SendQueue = { items = {}, running = false, lastMs = 0, sent = 0 }

function SendQueue.tick()
    local now = getTimestampMs()
    if now - SendQueue.lastMs < SEND_GAP_MS then return end
    SendQueue.lastMs = now
    local it = table.remove(SendQueue.items, 1)
    if it then
        -- the command tokenizer splits on whitespace and only quoting
        -- keeps a value with spaces (or an empty one) in one piece, the
        -- same trap the ban reason ran into once. Inner quotes would end
        -- the token early, they become apostrophes
        local wire = string.gsub(it.value, '"', "'")
        SendCommandToServer('/changeoption ' .. it.name .. ' "' .. wire .. '"')
        pcall(function() getServerOptions():putOption(it.name, wire) end)
        Aegis.logAction("server", "Server option " .. it.name .. " = " .. string.sub(it.value, 1, 120))
        SendQueue.sent = SendQueue.sent + 1
    end
    if not SendQueue.items[1] then
        Events.OnTick.Remove(SendQueue.tick)
        SendQueue.running = false
        Aegis.showToast(getText("UI_Aegis_OptApplied", SendQueue.sent))
        SendQueue.sent = 0
        local page = AegisPageOptions.instance
        if page then
            if page.dropPanels then
                page:dropPanels()
                pcall(function() page:selectGroup(page.activeIndex) end)
            end
            if page.updateApply then page:updateApply() end
        end
    end
end

function SendQueue.start(items)
    for _, it in ipairs(items) do table.insert(SendQueue.items, it) end
    if not SendQueue.running and SendQueue.items[1] then
        SendQueue.running = true
        SendQueue.lastMs = 0
        Events.OnTick.Add(SendQueue.tick)
    end
end

-- ------------------------------------------------------------------
-- Group nav list, same pattern as the sandbox page
-- ------------------------------------------------------------------
local NavList = ISPanel:derive("AegisOptionsNavList")

function NavList:new(x, y, w, groups)
    local o = ISPanel:new(x, y, w, math.max(1, #groups) * NAV_ROW_H)
    setmetatable(o, self)
    self.__index = self
    o.background = false
    o.groups = groups
    o.active = 1
    o.hoverT = {}
    return o
end

function NavList:prerender()
    local c = Aegis.col
    for i, grp in ipairs(self.groups) do
        local y = (i - 1) * NAV_ROW_H
        local hovered = self:isMouseOver() and self:getMouseY() >= y and self:getMouseY() < y + NAV_ROW_H
        self.hoverT[i] = Aegis.glide(self.hoverT[i] or 0, hovered and 1 or 0, 0.35)
        local active = self.active == i
        if active then
            Aegis.roundRect(self, 0, y + 2, self.width, NAV_ROW_H - 4, 8, 1, c.card)
            Aegis.roundRect(self, 0, y + 7, 3, NAV_ROW_H - 14, 1, 1, c.gold)
        elseif self.hoverT[i] > 0.01 then
            Aegis.roundRect(self, 0, y + 2, self.width, NAV_ROW_H - 4, 8, 0.5 * self.hoverT[i], c.card)
        end
        local label = grp.name .. " (" .. grp.count .. ")"
        Aegis.text(self, Aegis.fitText(label, UIFont.Small, self.width - 24), 14,
            y + math.floor((NAV_ROW_H - Aegis.fontH(UIFont.Small)) / 2), UIFont.Small,
            active and c.text or c.muted)
    end
end

function NavList:onMouseUp(x, y)
    local i = math.floor(y / NAV_ROW_H) + 1
    local grp = self.groups[i]
    if grp then
        Aegis.sound()
        self.active = i
        if self.onSelect then self.onSelect(self.owner, grp.groupIndex) end
    end
end

-- ------------------------------------------------------------------
-- One option row: name and default hint on the left, markers plus the
-- matching control on the right. The row itself only draws, the live
-- control sits on top of it as a sibling in the scroll panel: nesting
-- it inside the row would lose the doRepaintStencil flag AegisScrollArea
-- sets for its direct children and leave pixels of scrolled out combos
-- ------------------------------------------------------------------
local OptRow = ISPanel:derive("AegisOptionsRow")

function OptRow:new(x, y, w, entry, page)
    local o = ISPanel:new(x, y, w, ROW_H)
    setmetatable(o, self)
    self.__index = self
    o.background = false
    o.entry = entry
    o.page = page
    o.tooltip = entry.tooltip
    o.labelW = math.floor(w * 0.5) - 8
    o.ctrlX = math.floor(w * 0.5) + 44
    o.ctrlW = w - o.ctrlX
    return o
end

function OptRow:valueText()
    local e = self.entry
    if e.hidden then return getText("UI_Aegis_OptHidden") end
    local out = ""
    pcall(function()
        if e.otype == "enum" then
            out = e.opt:getValueTranslationByIndex(e.opt:getValue()) or e.opt:getValueAsString()
        else
            out = e.opt:getValueAsString()
        end
    end)
    return out
end

function OptRow:prerender()
    local c = Aegis.col
    local e = self.entry
    local dim = e.locked and 0.55 or 1
    Aegis.text(self, Aegis.fitText(e.name, UIFont.Small, self.labelW), 0, 3, UIFont.Small, c.text, dim)
    if not e.hidden then
        Aegis.text(self, Aegis.fitText(getText("UI_Aegis_OptDefault") .. " " .. e.default, UIFont.Small, self.labelW),
            0, 3 + Aegis.fontH(UIFont.Small), UIFont.Small, c.muted, 0.8 * dim)
    end
    local mx = self.ctrlX - 22
    if e.restart then
        Aegis.icon(self, "clock", mx, math.floor((ROW_H - 14) / 2), 14, 0.9, c.gold)
        mx = mx - 20
    end
    if e.locked then
        Aegis.icon(self, "lock", mx, math.floor((ROW_H - 14) / 2), 14, 0.9, c.muted)
    end
    if self.readOnly then
        Aegis.text(self, Aegis.fitText(self:valueText(), UIFont.Small, self.ctrlW),
            self.ctrlX, math.floor((ROW_H - Aegis.fontH(UIFont.Small)) / 2), UIFont.Small, c.muted, dim)
    end
    Aegis.updateTooltip(self)
end

-- clicking a locked Mods or WorkshopItems row starts the double warning
-- gate; everything else locked stays locked
function OptRow:onMouseDown(x, y)
    local e = self.entry
    if not e.locked or e.hidden then return false end
    local lname = string.lower(e.name)
    if not RISK_UNLOCK[lname] then return false end
    local page = self.page
    if not page or not page.canEdit or not page:canEdit() then return false end
    AegisConfirm.show(getText("UI_Aegis_OptRiskTitle"), getText("UI_Aegis_OptRiskWarn1"),
        getText("UI_Aegis_OptRiskGo"), page, function(pg)
        AegisConfirm.show(getText("UI_Aegis_OptRiskTitle"), getText("UI_Aegis_OptRiskWarn2"),
            getText("UI_Aegis_OptRiskGo"), pg, function(pg2)
            pg2.riskUnlocked = pg2.riskUnlocked or {}
            pg2.riskUnlocked[lname] = true
            -- locked lives inside the built entries, rebuild them. The
            -- cache has to go first, buildData returns early while groups
            -- still exist and the unlock would never have taken hold
            pg2.groups = nil
            pg2:buildData()
            pg2:dropPanels()
            pg2:rebuildNav()
        end)
    end)
    return true
end

-- ------------------------------------------------------------------
-- Page
-- ------------------------------------------------------------------

function AegisPageOptions.create(window, x, y, w, h)
    local o = ISPanel:new(x, y, w, h)
    setmetatable(o, AegisPageOptions)
    AegisPageOptions.__index = AegisPageOptions
    o.background = false
    o.window = window
    o.groups = nil
    o.touched = {}
    o.groupPanels = {}
    o.filterPanels = {}
    o.activeIndex = 1
    o.needle = ""
    AegisPageOptions.instance = o
    return o
end

-- editable only with the vanilla capability behind /changeoption; the
-- command would fail server side without it, so the page does not
-- pretend otherwise. Solo has no /changeoption at all, a putOption there
-- would neither persist nor survive the session, so solo stays honest
-- read-only instead of faking an apply
function AegisPageOptions:canEdit()
    return isClient() and Aegis.canSee("options") and Aegis.hasCap("ChangeAndReloadServerOptions")
end

local function classify(lname)
    -- the three misfits belong to the general group, not to nowhere:
    -- returning nil dropped them into a nil bucket and they vanished
    -- from every group
    if GROUP_EXCEPT[lname] then return "general" end
    for _, gid in ipairs(CLASSIFY) do
        for _, grp in ipairs(GROUPS) do
            if grp.id == gid then
                for _, pat in ipairs(grp.match) do
                    if string.find(lname, pat, 1, true) then return grp.id end
                end
                break
            end
        end
    end
    return "general"
end

function AegisPageOptions:buildData()
    if self.groups then return end
    local so = getServerOptions()
    local names = {}
    pcall(function()
        local list = so:getPublicOptions()
        for i = 0, list:size() - 1 do
            table.insert(names, list:get(i))
        end
    end)
    -- the secrets are not in the public list but their objects exist
    -- client side (at defaults), list them as hidden and locked rows
    for _, secret in ipairs(SECRET_ORDER) do table.insert(names, secret) end

    local byGroup = {}
    for _, name in ipairs(names) do
        local opt = nil
        pcall(function() opt = so:getOptionByName(name) end)
        if opt then
            local lname = string.lower(name)
            local otype = "string"
            pcall(function() otype = opt:getType() end)
            local hidden = SECRET[lname] == true
            local locked = hidden or (LOCKED_EXTRA[lname] == true
                and not (self.riskUnlocked and self.riskUnlocked[lname]))
            local restart = RESTART_EXACT[lname] == true
            if not restart then
                for _, p in ipairs(RESTART_PREFIX) do
                    if string.find(lname, p, 1, true) == 1 then
                        restart = true
                        break
                    end
                end
            end
            local default = ""
            if not hidden then
                pcall(function()
                    if otype == "enum" then
                        local d = opt:getDefaultValue()
                        default = opt:getValueTranslationByIndex(d) or tostring(d)
                    elseif otype == "boolean" then
                        default = opt:getDefaultValue() and "true" or "false"
                    else
                        default = tostring(opt:getDefaultValue())
                    end
                end)
            end
            local parts = {}
            local vanilla = getTextOrNull("UI_ServerOption_" .. name .. "_tooltip")
            if vanilla then
                table.insert(parts, (string.gsub(vanilla, "\\n", "\n")))
            end
            if hidden then table.insert(parts, getText("UI_Aegis_OptHiddenTip")) end
            if locked and not hidden then table.insert(parts, getText("UI_Aegis_OptLocked")) end
            if restart then table.insert(parts, getText("UI_Aegis_OptRestart")) end
            local entry = {
                name = name, lname = lname, opt = opt, otype = otype,
                hidden = hidden, locked = locked, restart = restart,
                default = default,
                tooltip = parts[1] and table.concat(parts, "\n") or nil,
            }
            local gid = classify(lname)
            byGroup[gid] = byGroup[gid] or {}
            table.insert(byGroup[gid], entry)
        end
    end

    self.groups = {}
    for _, grp in ipairs(GROUPS) do
        local entries = byGroup[grp.id]
        if entries then
            table.sort(entries, function(a, b) return a.name < b.name end)
            table.insert(self.groups, { id = grp.id, name = getText(grp.label), entries = entries })
        end
    end
end

function AegisPageOptions:createChildren()
    local pad = 20
    local innerX = pad + 14
    local innerW = self.width - innerX * 2
    self:buildData()

    self.applyBtn = AegisButton:new(innerX + innerW - 170, pad + 4, 170, 30, getText("UI_Aegis_Apply"), "check", self, AegisPageOptions.onApply)
    self.applyBtn.style = "gold"
    self:addChild(self.applyBtn)

    local navY = pad + 46
    self.search = ISTextEntryBox:new("", innerX, navY, NAV_W, 28)
    self.search:initialise()
    self.search:instantiate()
    self.search.font = UIFont.Small
    self.search:setClearButton(true)
    self.search:setPlaceholderText(getText("UI_Aegis_SearchOption"))
    local page = self
    self.search.onTextChange = function() page:applyFilter() end
    self:addChild(self.search)

    local listY = navY + 38
    local navH = self.height - listY - pad
    self.navArea = AegisScrollArea:new(innerX, listY, NAV_W, navH)
    self:addChild(self.navArea)

    self.contentX = innerX + NAV_W + 16
    self.contentW = innerW - NAV_W - 16
    self.contentY = navY
    self.contentH = self.height - navY - pad

    self:applyFilter()
    self:updateApply()
end

-- entries of a group that match the current needle (search runs over the
-- raw option names, 144 options need it)
function AegisPageOptions:matches(grp)
    if self.needle == "" then return grp.entries end
    local out = {}
    for _, e in ipairs(grp.entries) do
        if string.find(e.lname, self.needle, 1, true) then
            table.insert(out, e)
        end
    end
    return out
end

-- drop every built panel; the next selectGroup rebuilds from live
-- values plus touched. Cached unfiltered panels went stale the moment
-- an option was edited in a filtered view
function AegisPageOptions:dropPanels()
    for _, panel in pairs(self.filterPanels) do self:removeChild(panel) end
    for _, panel in pairs(self.groupPanels) do self:removeChild(panel) end
    self.filterPanels = {}
    self.groupPanels = {}
    self.activePanel = nil
end

function AegisPageOptions:applyFilter()
    self.needle = string.lower(self.search:getInternalText() or "")
    self:dropPanels()
    self:rebuildNav()
end

function AegisPageOptions:rebuildNav()
    local cats = {}
    for i, grp in ipairs(self.groups) do
        local n = #self:matches(grp)
        if n > 0 then
            table.insert(cats, { name = grp.name, count = n, groupIndex = i })
        end
    end
    if self.navList then
        self.navArea:removeChild(self.navList)
    end
    self.navList = NavList:new(0, 0, NAV_W - 14, cats)
    self.navList.owner = self
    self.navList.onSelect = AegisPageOptions.selectGroup
    local stillActive = false
    for _, cat in ipairs(cats) do
        if cat.groupIndex == self.activeIndex then
            stillActive = true
            break
        end
    end
    if stillActive then
        self:selectGroup(self.activeIndex)
    elseif cats[1] then
        self:selectGroup(cats[1].groupIndex)
    elseif self.activePanel then
        self.activePanel:setVisible(false)
        self.activePanel = nil
    end
    for i, cat in ipairs(cats) do
        if cat.groupIndex == self.activeIndex then self.navList.active = i end
    end
    self.navArea:addChild(self.navList)
    self.navArea:setScrollHeight(self.navList.height)
end

function AegisPageOptions:selectGroup(groupIndex)
    if not groupIndex then return end
    if self.activePanel then self.activePanel:setVisible(false) end
    self.activeIndex = groupIndex
    self.activePanel = self:buildGroupPanel(groupIndex)
    if self.activePanel then self.activePanel:setVisible(true) end
end

function AegisPageOptions:buildGroupPanel(idx)
    -- unfiltered panels are cached, filtered ones live until the next
    -- keystroke (applyFilter clears them)
    if self.needle == "" and self.groupPanels[idx] then return self.groupPanels[idx] end
    if self.filterPanels[idx] then return self.filterPanels[idx] end
    local grp = self.groups[idx]
    if not grp then return nil end
    local entries = self:matches(grp)
    local w = self.contentW
    local panel = AegisScrollArea:new(self.contentX, self.contentY, w, self.contentH)
    panel:setVisible(false)
    self:addChild(panel)

    -- extra room on the right: the scroll bar of the host sits there and
    -- the value controls used to run right up against it
    local rowW = w - 28 - 16
    local y = 6
    local page = self
    local editable = self:canEdit()

    for _, e in ipairs(entries) do
        local row = OptRow:new(14, y, rowW, e, page)
        row.readOnly = e.locked or not editable
        panel:addChild(row)
        if not row.readOnly then
            local ctrlX = 14 + row.ctrlX
            local ctrlW = row.ctrlW
            local pending = self.touched[e.name]
            if e.otype == "boolean" then
                local t = AegisToggle:new(ctrlX, y + math.floor((ROW_H - 28) / 2), ctrlW, 28, "", nil, page, AegisPageOptions.onRowToggle)
                t.optEntry = e
                local cur = false
                pcall(function() cur = e.opt:getValue() == true end)
                if pending ~= nil then cur = pending == "true" end
                t:setChecked(cur)
                t.tooltip = e.tooltip
                panel:addChild(t)
            elseif e.otype == "enum" then
                local combo = ISComboBox:new(ctrlX, y + math.floor((ROW_H - 24) / 2), ctrlW, 24, page, AegisPageOptions.onRowCombo)
                combo:initialise()
                combo.optEntry = e
                local num = 0
                pcall(function() num = e.opt:getNumValues() end)
                for i = 1, num do
                    local label = tostring(i)
                    pcall(function() label = e.opt:getValueTranslationByIndex(i) or label end)
                    combo:addOption(label)
                end
                local cur = 1
                pcall(function() cur = e.opt:getValue() end)
                if pending then cur = tonumber(pending) or cur end
                combo.selected = cur
                if e.tooltip then combo.tooltip = { defaultTooltip = e.tooltip } end
                panel:addChild(combo)
            else
                local box = ISTextEntryBox:new("", ctrlX, y + math.floor((ROW_H - 24) / 2), ctrlW, 24)
                box:initialise()
                box:instantiate()
                box.font = UIFont.Small
                box.optEntry = e
                box:setOnlyNumbers(e.otype == "double" or e.otype == "integer")
                local cur = ""
                pcall(function() cur = e.opt:getValueAsString() end)
                if pending ~= nil then cur = pending end
                box:setText(cur)
                box.tooltip = e.tooltip
                box.onTextChange = function() AegisPageOptions.onRowEntry(page, box) end
                panel:addChild(box)
            end
        end
        y = y + ROW_H + 6
    end
    panel:setScrollHeight(y)
    if self.needle == "" then
        self.groupPanels[idx] = panel
    else
        self.filterPanels[idx] = panel
    end
    return panel
end

-- ------------------------------------------------------------------
-- Editing: touched holds the pending value string per option name until
-- Apply sends the batch. Values equal to the live copy drop out again
-- ------------------------------------------------------------------

function AegisPageOptions:setTouched(e, value)
    local current = ""
    pcall(function() current = e.opt:getValueAsString() end)
    if value == current then
        self.touched[e.name] = nil
    else
        self.touched[e.name] = value
    end
    self:updateApply()
end

function AegisPageOptions.onRowToggle(self, checked, toggle)
    self:setTouched(toggle.optEntry, checked and "true" or "false")
end

function AegisPageOptions.onRowCombo(self, combo)
    self:setTouched(combo.optEntry, tostring(combo.selected))
end

function AegisPageOptions.onRowEntry(self, box)
    local e = box.optEntry
    -- newlines would break the (\w+) (.*) parse of /changeoption
    local text = string.gsub(box:getInternalText() or "", "[\r\n]", " ")
    local ok = false
    pcall(function() ok = e.opt:isValidString(text) == true end)
    box:setValid(ok)
    if ok then
        self:setTouched(e, text)
    else
        -- an invalid value must not stay queued from an earlier valid state
        self.touched[e.name] = nil
        self:updateApply()
    end
end

function AegisPageOptions:updateApply()
    if not self.applyBtn then return end
    local n = 0
    for _ in pairs(self.touched) do n = n + 1 end
    self.applyBtn:setEnabled(n > 0 and self:canEdit() and not SendQueue.running)
    self.applyBtn.label = getText("UI_Aegis_Apply") .. (n > 0 and (" (" .. n .. ")") or "")
end

function AegisPageOptions.onApply(self)
    if not self:canEdit() then
        Aegis.showToast(getText(isClient() and "UI_Aegis_OptReadOnly" or "UI_Aegis_OptSolo"))
        self:updateApply()
        return
    end
    local items = {}
    for name, value in pairs(self.touched) do
        table.insert(items, { name = name, value = value })
    end
    if not items[1] then return end
    table.sort(items, function(a, b) return a.name < b.name end)
    SendQueue.start(items)
    self.touched = {}
    self:updateApply()
end

-- ------------------------------------------------------------------
-- Resize survival: rebuildPages throws every panel away, hand over the
-- search text, active group and pending edits to the successor
-- ------------------------------------------------------------------

function AegisPageOptions:saveState()
    local grp = self.groups and self.groups[self.activeIndex]
    return {
        search = self.search and self.search:getInternalText() or "",
        group = grp and grp.id or nil,
        touched = self.touched,
    }
end

function AegisPageOptions:restoreState(state)
    if type(state) ~= "table" then return end
    if type(state.touched) == "table" then self.touched = state.touched end
    if state.group and self.groups then
        for i, grp in ipairs(self.groups) do
            if grp.id == state.group then
                self.activeIndex = i
                break
            end
        end
    end
    -- panels were already built with empty touched, rebuild them so the
    -- pending values show up in the controls again
    for _, panel in pairs(self.groupPanels) do self:removeChild(panel) end
    self.groupPanels = {}
    self.activePanel = nil
    if self.search and state.search and state.search ~= "" then
        self.search:setText(state.search)
    end
    self:applyFilter()
    self:updateApply()
end

-- ------------------------------------------------------------------
-- Frame
-- ------------------------------------------------------------------

function AegisPageOptions:prerender()
    if not self.navArea then return end
    local c = Aegis.col
    local pad = 20
    Aegis.roundFrame(self, pad, pad, self.width - pad * 2, self.height - pad * 2, 10, 1, c.line, c.panel)
    Aegis.icon(self, "gear", pad + 14, pad + 12, 15, 1, c.gold)
    local title = getText("UI_Aegis_NavOptions")
    Aegis.text(self, title, pad + 36, pad + 10, UIFont.Medium, c.text)

    -- one honest hint line: why the page is read-only, or what an apply
    -- does and does not reach
    local hint
    if not isClient() then
        hint = getText("UI_Aegis_OptSolo")
    elseif not self:canEdit() then
        hint = getText("UI_Aegis_OptReadOnly")
    else
        hint = getText("UI_Aegis_OptSyncNote")
    end
    local hx = pad + 36 + Aegis.strW(UIFont.Medium, title) + 16
    local hw = (self.applyBtn.x - 12) - hx
    if hw > 60 then
        Aegis.text(self, Aegis.fitText(hint, UIFont.Small, hw), hx,
            pad + 12 + Aegis.fontH(UIFont.Medium) - Aegis.fontH(UIFont.Small), UIFont.Small, c.muted)
    end

    Aegis.roundFrame(self, self.navArea.x, self.navArea.y, NAV_W, self.navArea.height, 10, 1, c.line, c.card)
    if not self.activePanel then
        Aegis.textCentre(self, getText("UI_Aegis_NoOptionSelected"), self.contentX + math.floor(self.contentW / 2),
            math.floor(self.height / 2), UIFont.Medium, c.muted)
    end
end

AegisWindow.registerPage({
    id = "options",
    icon = "gear",
    label = "UI_Aegis_NavOptions",
    create = AegisPageOptions.create,
})
