-- Role management: create roles, toggle area rights, assign players.
-- The server owns the data, this page only mirrors its state.
require "Aegis/AegisWindow"
require "Aegis/AegisRoleTag"
require "ISUI/ISScrollingListBox"
require "ISUI/ISComboBox"
require "ISUI/ISTextEntryBox"

AegisPageRoles = ISPanel:derive("AegisPageRoles")
AegisRolesClient = AegisRolesClient or {}

local LIST_W = 250
local ROW_H = 40

local AREA_LABEL = {
    dashboard = "UI_Aegis_NavDashboard",
    powers = "UI_Aegis_NavPowers",
    players = "UI_Aegis_NavPlayers",
    items = "UI_Aegis_NavItems",
    vehicles = "UI_Aegis_NavVehicles",
    animals = "UI_Aegis_Animals",
    world = "UI_Aegis_NavWorld",
    zones = "UI_Aegis_NavZones",
    horde = "UI_Aegis_NavHorde",
    server = "UI_Aegis_NavServer",
    options = "UI_Aegis_NavOptions",
    factions = "UI_Aegis_NavFactions",
    tools = "UI_Aegis_NavTools",
    kits = "UI_Aegis_NavKits",
    sandbox = "UI_Aegis_NavSandbox",
    logs = "UI_Aegis_NavLogs",
    roles = "UI_Aegis_NavRoles",
}

-- One area can carry more than one panel page (server options ride on
-- "server"). Without this the extra page was nowhere to be seen on the
-- roles page and looked like it had no rights entry at all
function AegisPageRoles.areaTooltip(area)
    local names = {}
    for _, def in ipairs(AegisWindow.pages) do
        if (def.area or def.id) == area then
            table.insert(names, getText(def.label))
        end
    end
    if #names <= 1 then return nil end
    return getText("UI_Aegis_RoleAreaCovers", table.concat(names, ", "))
end

local function comboText(combo)
    local idx = combo and combo.selected or 0
    local opt = combo and combo.options and combo.options[idx]
    if type(opt) == "table" then opt = opt.text end
    if not opt or opt == "" then return nil end
    return opt
end

function AegisPageRoles.create(window, x, y, w, h)
    local o = ISPanel:new(x, y, w, h)
    setmetatable(o, AegisPageRoles)
    AegisPageRoles.__index = AegisPageRoles
    o.background = false
    o.window = window
    o.roles = {}
    o.assignments = {}
    o.selectedRole = nil
    AegisPageRoles.instance = o
    return o
end

function AegisPageRoles:createChildren()
    local pad = 20

    -- left: role list plus creation
    self.list = ISScrollingListBox:new(pad + 1, pad + 6, LIST_W - 2, self.height - pad * 2 - 86)
    self.list:initialise()
    self.list:instantiate()
    self.list.itemheight = ROW_H
    self.list.font = UIFont.Medium
    self.list.drawBorder = false
    self.list.backgroundColor = { r = 0, g = 0, b = 0, a = 0 }
    self.list.doDrawItem = AegisPageRoles.drawRoleRow
    self.list:setOnMouseDownFunction(self, AegisPageRoles.onSelectRole)
    self:addChild(self.list)

    -- drag and drop: grabbing and moving a row sets the rank order,
    -- on release the new order is reported to the server
    local list = self.list
    list.aegisPage = self
    function list:onMouseDown(x, y)
        ISScrollingListBox.onMouseDown(self, x, y)
        local page = self.aegisPage
        page.dragIndex = (self.selected and self.selected > 0) and self.selected or nil
        page.dragMoved = false
        -- double click on the same row opens the tag color picker
        local row = self:rowAt(x, y)
        local now = getTimestampMs()
        if row and row >= 1 and row == page.lastClickRow and now - (page.lastClickAt or 0) <= 400 then
            page.lastClickRow = nil
            page.lastClickAt = 0
            page.dragIndex = nil
            local item = self.items[row]
            if item then page:openColorPick(item.item) end
        else
            page.lastClickRow = row
            page.lastClickAt = now
        end
    end
    function list:onMouseMove(dx, dy)
        ISScrollingListBox.onMouseMove(self, dx, dy)
        local page = self.aegisPage
        if not page.dragIndex then return end
        local target = self:rowAt(self:getMouseX(), self:getMouseY())
        if target and target >= 1 and target <= #self.items and target ~= page.dragIndex then
            local item = table.remove(self.items, page.dragIndex)
            table.insert(self.items, target, item)
            for i, it in ipairs(self.items) do it.index = i end
            self.selected = target
            page.dragIndex = target
            page.dragMoved = true
        end
    end
    local function dragEnd(self)
        local page = self.aegisPage
        if page.dragMoved then page:sendOrder() end
        page.dragIndex = nil
        page.dragMoved = false
    end
    function list:onMouseUp(x, y)
        ISScrollingListBox.onMouseUp(self, x, y)
        dragEnd(self)
    end
    function list:onMouseUpOutside(x, y)
        ISScrollingListBox.onMouseUpOutside(self, x, y)
        dragEnd(self)
    end

    self.nameEntry = ISTextEntryBox:new("", pad + 1, self.height - pad - 70, LIST_W - 2, 26)
    self.nameEntry:initialise()
    self.nameEntry:instantiate()
    self:addChild(self.nameEntry)

    self.addBtn = AegisButton:new(pad + 1, self.height - pad - 38, LIST_W - 2, 32, getText("UI_Aegis_RoleAdd"), "plus", self, AegisPageRoles.onAdd)
    self.addBtn.style = "gold"
    self:addChild(self.addBtn)

    -- top right: rights of the selected role
    local dx = pad + LIST_W + 20
    local dw = self.width - dx - pad
    local tw = math.floor((dw - 28 - 12) / 2)
    self.toggles = {}
    local col, ty = 0, pad + 44
    for _, b in ipairs(AegisShared.AREAS) do
        local t = AegisToggle:new(dx + 14 + col * (tw + 12), ty, tw, 28, getText(AREA_LABEL[b] or b), nil, self, AegisPageRoles.onToggle)
        t.area = b
        t.tooltip = AegisPageRoles.areaTooltip(b)
        t:setEnabled(false)
        self:addChild(t)
        self.toggles[b] = t
        col = col + 1
        if col == 2 then
            col = 0
            ty = ty + 34
        end
    end
    if col ~= 0 then ty = ty + 34 end

    -- player panel extras of the role, saved through the same roleSave
    -- command as the rights. The panel itself is not switchable: every
    -- player has it, a role only raises the budgets. Tiles 0 keeps self
    -- claims off entirely
    local smallH = Aegis.fontH(UIFont.Small)
    ty = ty + 8
    self.ppHeaderY = ty
    ty = ty + smallH + 6
    self.ppKitsToggle = AegisToggle:new(dx + 14, ty, tw, 28, getText("UI_Aegis_RolePanelKits"), nil, self, AegisPageRoles.onToggle)
    self.ppKitsToggle:setEnabled(false)
    self:addChild(self.ppKitsToggle)
    -- head tag of the role, next to the kit gate: switchable at any
    -- time, the save applies it to every online wearer
    self.ppTagToggle = AegisToggle:new(dx + 14 + tw + 12, ty, tw, 28, getText("UI_Aegis_RolePanelTag"), nil, self, AegisPageRoles.onToggle)
    self.ppTagToggle:setEnabled(false)
    self:addChild(self.ppTagToggle)
    ty = ty + 34
    self.ppTilesY = ty
    local tilesLabelW = math.min(Aegis.strW(UIFont.Small, getText("UI_Aegis_RolePanelTiles")) + 12, math.floor((dw - 28) * 0.4))
    self.ppTilesSlider = AegisSlider:new(dx + 14 + tilesLabelW, ty, dw - 28 - tilesLabelW, 24, self, nil)
    self.ppTilesSlider:setValues(0, 2000, 10, "")
    self.ppTilesSlider:setValue(0, true)
    self:addChild(self.ppTilesSlider)
    ty = ty + 28
    self.ppHintY = ty
    ty = ty + smallH + 4

    self.rightsBottom = ty + 10

    self.saveBtn = AegisButton:new(dx + 14, self.rightsBottom, tw, 34, getText("UI_Aegis_RoleSave"), "check", self, AegisPageRoles.onSave)
    self.saveBtn.style = "gold"
    self.saveBtn:setEnabled(false)
    self:addChild(self.saveBtn)

    self.deleteBtn = AegisButton:new(dx + 14 + tw + 12, self.rightsBottom, tw, 34, getText("UI_Aegis_RoleDelete"), "trash", self, AegisPageRoles.onDelete)
    self.deleteBtn.style = "danger"
    self.deleteBtn:setEnabled(false)
    self:addChild(self.deleteBtn)
    self.rightsBottom = self.rightsBottom + 34 + 16

    -- bottom right: assignments and head tag side by side as two
    -- equal-height column cards (user feedback: stacked looked needlessly
    -- long), inside a shared scroll container (user feedback: with many
    -- area tiles the content spilled past the window edge; real pixel
    -- clipping via AegisScrollArea solves that regardless of window size
    -- or area count). Each column gets its own full width for combos and
    -- button instead of sharing a row, otherwise texts get squeezed in
    -- narrow windows
    self.scrollY = self.rightsBottom + 8
    -- floor of 40 keeps the probe build sane when the window reports a
    -- height smaller than the fixed layout above (designH rebuild follows)
    self.scrollH = math.max(40, self.height - self.scrollY - pad)
    self.scroll = AegisScrollArea:new(dx, self.scrollY, dw, self.scrollH)
    self:addChild(self.scroll)
    local sw = dw - 16 -- room for the scrollbar on the right

    local COLUMN_GAP = 20
    local columnW = math.floor((sw - COLUMN_GAP) / 2)
    local assignX = 0
    local tagX = columnW + COLUMN_GAP

    -- assignments: player combo, role combo and button on separate rows
    local sy = 34
    self.userCombo = ISComboBox:new(assignX + 14, sy, columnW - 28, 26, self, nil)
    self.userCombo:initialise()
    self.scroll:addChild(self.userCombo)
    sy = sy + 34

    self.roleCombo = ISComboBox:new(assignX + 14, sy, columnW - 28, 26, self, nil)
    self.roleCombo:initialise()
    self.scroll:addChild(self.roleCombo)
    sy = sy + 34

    self.assignBtn = AegisButton:new(assignX + 14, sy, columnW - 28, 28, getText("UI_Aegis_RoleAssign"), nil, self, AegisPageRoles.onAssign)
    self.scroll:addChild(self.assignBtn)
    sy = sy + 28 + 10

    -- sized tighter (shows 3 rows, scrolls internally beyond that) instead
    -- of reserving 150px for usually just a handful of assignments
    -- (user feedback: needlessly stretched out)
    local ASSIGN_LIST_H = 90
    self.assignList = ISScrollingListBox:new(assignX + 14, sy, columnW - 28, ASSIGN_LIST_H)
    self.assignList:initialise()
    self.assignList:instantiate()
    self.assignList.itemheight = 30
    self.assignList.font = UIFont.Small
    self.assignList.drawBorder = false
    self.assignList.backgroundColor = { r = 0, g = 0, b = 0, a = 0 }
    self.assignList.doDrawItem = AegisPageRoles.drawAssignment
    self.assignList:setOnMouseDownFunction(self, AegisPageRoles.onAssignmentClick)
    self.scroll:addChild(self.assignList)
    local assignCardBottom = sy + ASSIGN_LIST_H + 14

    -- head tag: pick a player, desired name and color come via prompt,
    -- own column, same vertical order as before (combo, current role,
    -- button, hint text)
    self.tagW = columnW
    self.tagLocalY = 0

    self.tagCombo = ISComboBox:new(tagX + 14, self.tagLocalY + 34, self.tagW - 28, 26, self, nil)
    self.tagCombo:initialise()
    self.scroll:addChild(self.tagCombo)

    self.tagBtn = AegisButton:new(tagX + 14, self.tagLocalY + 92, self.tagW - 28, 30, getText("UI_Aegis_HeadTagButton"), "crown", self, AegisPageRoles.onHeadTag)
    self.tagBtn.style = "gold"
    self.scroll:addChild(self.tagBtn)

    local tagHeight = self.tagLocalY + 132 + #self:tagHintLines() * Aegis.fontH(UIFont.Small) + 16
    -- bring both cards to the same height (the taller of the two),
    -- otherwise the shorter column looks cut off next to the other
    local cardHeight = math.max(assignCardBottom, tagHeight)
    self.scroll:setScrollHeight(math.max(cardHeight, self.scrollH))

    -- the player panel block grew the fixed layout: report the height it
    -- really needs (at least a usable strip of the two cards), small
    -- windows then host the whole page in a scroll instead of pushing
    -- the cards out of the frame
    self.designH = self.scrollY + math.min(cardHeight, 140) + pad

    -- draw the frames and text of the two cards inside the scroll container
    -- instead of the outer page prerender, or they would not scroll and clip
    local scroll, page = self.scroll, self
    function scroll:prerender()
        AegisScrollArea.prerender(self)
        local c = Aegis.col
        Aegis.roundFrame(self, assignX, 0, columnW, cardHeight, 10, 1, c.line, c.panel)
        Aegis.icon(self, "players", assignX + 14, 10, 15, 1, c.gold)
        Aegis.text(self, Aegis.fitText(getText("UI_Aegis_RoleAssignments"), UIFont.Medium, columnW - 50), assignX + 36, 8, UIFont.Medium, c.text)

        Aegis.roundFrame(self, tagX, 0, columnW, cardHeight, 10, 1, c.line, c.panel)
        Aegis.icon(self, "crown", tagX + 14, 10, 15, 1, c.gold)
        Aegis.text(self, Aegis.fitText(getText("UI_Aegis_HeadTag"), UIFont.Medium, columnW - 50), tagX + 36, 8, UIFont.Medium, c.text)

        local role = page:tagRoleName()
        local line = role and getText("UI_Aegis_HeadTagRole", role) or getText("UI_Aegis_HeadTagRoleUnknown")
        Aegis.text(self, Aegis.fitText(line, UIFont.Small, columnW - 28), tagX + 14, 64, UIFont.Small, c.muted)

        local hy = 132
        for _, hint in ipairs(page:tagHintLines()) do
            Aegis.text(self, hint, tagX + 14, hy, UIFont.Small, c.muted)
            hy = hy + Aegis.fontH(UIFont.Small)
        end
    end
end

function AegisPageRoles:onShow()
    self:requestData()
    if isClient() then
        -- request the scoreboard actively, otherwise the player combo stays
        -- empty until someone visits the players page
        pcall(scoreboardUpdate)
        -- refresh the engine role catalog, the head tag reads it locally
        pcall(requestRoles)
    end
    self:fillPlayerCombo()
end

function AegisPageRoles:requestData()
    local p = getPlayer()
    if not p then return end
    sendClientCommand(p, AegisShared.MODULE, "roleList", {})
end

function AegisPageRoles:fillPlayerCombo()
    self:fillCombo(self.userCombo)
    self:fillCombo(self.tagCombo)
end

function AegisPageRoles:fillCombo(combo)
    if not combo then return end
    -- keep the selection across the refill
    local previous = nil
    if combo.options and combo.selected and combo.options[combo.selected] then
        local opt = combo.options[combo.selected]
        previous = type(opt) == "table" and opt.text or opt
    end
    combo:clear()
    if isClient() then
        for _, row in ipairs(Aegis.scoreboard or {}) do
            combo:addOption(row.username)
        end
    else
        local p = getPlayer()
        if p then combo:addOption(p:getUsername()) end
    end
    if combo.options and #combo.options > 0 then
        combo.selected = 1
        if previous then
            for i, opt in ipairs(combo.options) do
                local text = type(opt) == "table" and opt.text or opt
                if text == previous then
                    combo.selected = i
                    break
                end
            end
        end
    end
end

-- ------------------------------------------------------------------
-- apply server data
-- ------------------------------------------------------------------

function AegisPageRoles:setData(data)
    self.roles = data.roles or {}
    self.assignments = data.assignments or {}

    local keepName = self.selectedRole and self.selectedRole.name
    self.selectedRole = nil

    self.list:clear()
    self.list.selected = -1
    for i, role in ipairs(self.roles) do
        self.list:addItem(role.name, role)
        if role.name == keepName then
            self.list.selected = i
            self.selectedRole = role
        end
    end
    if not self.selectedRole and self.roles[1] then
        self.list.selected = 1
        self.selectedRole = self.roles[1]
    end
    self:showRole()

    self.roleCombo:clear()
    self.roleCombo:addOption(getText("UI_Aegis_RoleNone"))
    for _, role in ipairs(self.roles) do
        self.roleCombo:addOption(role.name)
    end
    self.roleCombo.selected = 1

    self.assignList:clear()
    self.assignList.selected = -1
    for _, z in ipairs(self.assignments) do
        self.assignList:addItem(z.user, z)
    end
end

function AegisPageRoles:showRole()
    local role = self.selectedRole
    local rights = {}
    if role then
        for _, b in ipairs(role.rights or {}) do rights[b] = true end
    end
    for b, t in pairs(self.toggles) do
        t:setChecked(rights[b] == true)
        t:setEnabled(role ~= nil)
    end
    local pp = role and role.pp or nil
    if self.ppKitsToggle then
        self.ppKitsToggle:setChecked((pp and pp.kits) == true)
        self.ppKitsToggle:setEnabled(role ~= nil)
        self.ppTagToggle:setChecked(pp == nil or pp.tag ~= false)
        self.ppTagToggle:setEnabled(role ~= nil)
        self.ppTilesSlider:setValue(pp and pp.tiles or 0, true)
    end
    self.saveBtn:setEnabled(role ~= nil)
    self.deleteBtn:setEnabled(role ~= nil)
end

-- ------------------------------------------------------------------
-- actions
-- ------------------------------------------------------------------

function AegisPageRoles.onSelectRole(self, role)
    self.selectedRole = role
    self:showRole()
end

function AegisPageRoles:sendOrder()
    local p = getPlayer()
    if not p then return end
    local names = {}
    for _, item in ipairs(self.list.items) do
        table.insert(names, item.item.name)
    end
    sendClientCommand(p, AegisShared.MODULE, "roleOrder", { names = names })
end

function AegisPageRoles.onToggle(self, checked, toggle)
end

function AegisPageRoles.onAdd(self)
    local name = self.nameEntry:getInternalText() or ""
    name = name:gsub("^%s+", ""):gsub("%s+$", "")
    if name == "" then return end
    local p = getPlayer()
    if not p then return end
    self.selectedRole = { name = AegisShared.sanitizeName(name), rights = {} }
    sendClientCommand(p, AegisShared.MODULE, "roleSave", { name = name, rights = {} })
    self.nameEntry:setText("")
end

function AegisPageRoles.onSave(self)
    if not self.selectedRole then return end
    local p = getPlayer()
    if not p then return end
    local rights = {}
    for b, t in pairs(self.toggles) do
        if t.checked then table.insert(rights, b) end
    end
    -- show the toast only on server confirmation (roleData response), not
    -- optimistically here: otherwise "saved" contradicts the conflict
    -- toast if the server rejects right after
    self.waitingForSave = true
    local tagOn = self.ppTagToggle == nil or self.ppTagToggle.checked == true
    -- the reply handler applies the tag change to online wearers, it
    -- needs to know what was saved and for which role
    self.savedTag = { role = self.selectedRole.name, on = tagOn,
        color = self.selectedRole.color }
    sendClientCommand(p, AegisShared.MODULE, "roleSave", {
        name = self.selectedRole.name,
        rights = rights,
        version = self.selectedRole.version,
        -- no panel field any more, the server normalizes it to on
        pp = {
            tiles = self.ppTilesSlider and self.ppTilesSlider.value or 0,
            kits = self.ppKitsToggle and self.ppKitsToggle.checked == true,
            tag = tagOn,
        },
    })
end

-- put the saved tag setting on every online wearer of the role: on
-- creates or refits the engine tag, off takes a marked tag away. Offline
-- players follow on their next assignment
function AegisPageRoles:applyTagSetting(saved)
    if not saved or type(self.assignments) ~= "table" then return end
    for _, a in ipairs(self.assignments) do
        if a.role == saved.role and type(a.user) == "string" then
            if saved.on then
                -- refit only reachable wearers: the deep offline toast in
                -- createAndAssign reads like the save itself had failed
                local reachable = not isClient()
                if not reachable then
                    pcall(function() reachable = getPlayerFromUsername(a.user) ~= nil end)
                end
                if reachable and AegisRoleTag.currentRole(a.user) ~= saved.role then
                    AegisRoleTag.createAndAssign(a.user, saved.role, saved.color)
                elseif not reachable then
                    print("[Aegis] tag: refit skipped for " .. tostring(a.user)
                        .. " (offline or not streamed), follows on next assignment")
                end
            else
                local current = AegisRoleTag.currentRole(a.user)
                if current and AegisRoleTag.isTagRole(current) then
                    AegisRoleTag.resetPlayerTag(a.user)
                end
            end
        end
    end
end

function AegisPageRoles.onDelete(self)
    if not self.selectedRole then return end
    local name = self.selectedRole.name
    AegisConfirm.show(getText("UI_Aegis_RoleDelete"), getText("UI_Aegis_ConfirmRoleDelete", name),
        getText("UI_Aegis_RoleDelete"), self, function(target)
            local p = getPlayer()
            if not p then return end
            target.selectedRole = nil
            sendClientCommand(p, AegisShared.MODULE, "roleDelete", { name = name })
            -- also retire the matching head tag: move every online wearer
            -- back to a plain role, then janitor-delete the engine role
            pcall(function()
                local online = getOnlinePlayers()
                if not online then return end
                for i = 0, online:size() - 1 do
                    local pl = online:get(i)
                    if pl then
                        local r = pl:getRole()
                        if r and r:getName() == name then
                            AegisRoleTag.resetPlayerTag(pl:getUsername())
                        end
                    end
                end
            end)
            AegisRoleTag.removeTagRole(name)
        end)
end

function AegisPageRoles.onAssign(self)
    local p = getPlayer()
    if not p then return end
    local userIdx = self.userCombo.selected or 0
    local user = self.userCombo.options and self.userCombo.options[userIdx]
    if type(user) == "table" then user = user.text end
    if not user or user == "" then return end
    local roleIdx = self.roleCombo.selected or 1
    local role = ""
    local roleColor = nil
    local areaCount = 0
    if roleIdx > 1 and self.roles[roleIdx - 1] then
        role = self.roles[roleIdx - 1].name
        roleColor = self.roles[roleIdx - 1].color
        areaCount = #(self.roles[roleIdx - 1].rights or {})
    end
    -- the role itself decides about the head tag (pp.tag)
    local wantTag = true
    if roleIdx > 1 and self.roles[roleIdx - 1] then
        local pp = self.roles[roleIdx - 1].pp
        wantTag = pp == nil or pp.tag ~= false
    end
    local function doAssign()
        sendClientCommand(p, AegisShared.MODULE, "roleAssign", { user = user, role = role })
        -- an Aegis role assignment also puts the same name above the head
        --: create and assign the matching engine head tag in
        -- one go, in the role's tag color (nil falls back to gold), unless the
        -- target already wears it. Removal (empty role) also clears a marked
        -- head tag
        if role ~= "" then
            if wantTag then
                if AegisRoleTag.currentRole(user) ~= role then
                    AegisRoleTag.createAndAssign(user, role, roleColor)
                end
            else
                -- tag switched off for this assignment: a marked tag from
                -- an earlier round comes off, the base role stays
                local current = AegisRoleTag.currentRole(user)
                if current and AegisRoleTag.isTagRole(current) then
                    AegisRoleTag.resetPlayerTag(user)
                end
            end
        else
            local current = AegisRoleTag.currentRole(user)
            if current and AegisRoleTag.isTagRole(current) then
                AegisRoleTag.resetPlayerTag(user)
            end
        end
    end
    if role == "" then
        doAssign()
        return
    end
    -- active confirmation before assigning: states in
    -- plain words whether the player only wears the head tag or also
    -- gets Aegis areas. Tag-only roles (Spieler, Donator, ...) never
    -- show the Aegis icon, the sidebar button stays admin-gated
    local message
    if areaCount > 0 then
        message = getText("UI_Aegis_RoleAssignAreas", user, role, tostring(areaCount))
    else
        message = getText("UI_Aegis_RoleAssignTagOnly", user, role)
    end
    AegisPrompt.show{
        title = getText("UI_Aegis_RoleAssign"),
        message = message,
        confirmLabel = getText("UI_Aegis_RoleAssign"),
        onConfirm = function() doAssign() end,
    }
end

-- clicking an assignment preselects player and role in the combos
function AegisPageRoles.onAssignmentClick(self, assignment)
    if not assignment then return end
    if self.userCombo.options then
        for i, opt in ipairs(self.userCombo.options) do
            local text = type(opt) == "table" and opt.text or opt
            if text == assignment.user then
                self.userCombo.selected = i
                break
            end
        end
    end
    for i, role in ipairs(self.roles) do
        if role.name == assignment.role then
            self.roleCombo.selected = i + 1
            break
        end
    end
end

-- tag color for a role, opened by double clicking its row. AegisPrompt
-- already carries the chips; the reason entry is optional there, so it is
-- simply hidden for the pick. The save sends the role's current rights
-- along, the server keeps a color when a save omits it anyway
function AegisPageRoles:openColorPick(role)
    if not role then return end
    local chips = AegisRoleTag.colorChips()
    local prompt = AegisPrompt.show{
        title = getText("UI_Aegis_RoleColor"),
        message = getText("UI_Aegis_RoleColorPick", role.name),
        confirmLabel = getText("UI_Aegis_RoleColorApply"),
        chips = chips,
        target = self,
        onConfirm = function(target, _, color)
            local p = getPlayer()
            if not p or type(color) ~= "table" then return end
            target.waitingForSave = true
            sendClientCommand(p, AegisShared.MODULE, "roleSave", {
                name = role.name,
                rights = role.rights or {},
                version = role.version,
                color = { r = color.r, g = color.g, b = color.b },
            })
            -- players already wearing the matching head tag get the new
            -- color right away instead of only on the next assignment
            AegisRoleTag.recolorTagRole(role.name, color)
        end,
    }
    pcall(function() prompt.entry:setVisible(false) end)
    -- preselect the chip matching the stored color
    if role.color then
        for _, chip in ipairs(chips) do
            local c = chip.value
            if math.abs(c.r - role.color.r) < 0.01 and math.abs(c.g - role.color.g) < 0.01
                and math.abs(c.b - role.color.b) < 0.01 then
                prompt.choice = c
                break
            end
        end
    end
end

-- head tag: ask for the desired name via prompt, color via the chips,
-- then confirm and hand off to AegisRoleTag
function AegisPageRoles.onHeadTag(self)
    if not Aegis.canSee("roles") then return end
    local user = comboText(self.tagCombo)
    if not user then return end
    local prompt = AegisPrompt.show{
        title = getText("UI_Aegis_HeadTag"),
        message = getText("UI_Aegis_HeadTagPrompt", user),
        confirmLabel = getText("UI_Aegis_HeadTagContinue"),
        reasonRequired = true,
        chips = AegisRoleTag.colorChips(),
        target = self,
        onConfirm = function(target, name, color)
            AegisConfirm.show(getText("UI_Aegis_HeadTag"),
                getText("UI_Aegis_HeadTagWarning", user, name),
                getText("UI_Aegis_HeadTagButton"), target, function()
                    AegisRoleTag.createAndAssign(user, name, color)
                end)
        end,
    }
    pcall(function() prompt.entry:setPlaceholderText(getText("UI_Aegis_HeadTagName")) end)
end

-- engine role of the selected player, looked up throttled instead of per frame
function AegisPageRoles:tagRoleName()
    local user = comboText(self.tagCombo)
    if not user then return nil end
    local now = getTimestampMs()
    local cache = self.tagRoleCache
    if cache and cache.user == user and now < cache.untilMs then return cache.name end
    local name = AegisRoleTag.currentRole(user)
    self.tagRoleCache = { user = user, name = name, untilMs = now + 1000 }
    return name
end

-- wrap the hint text to panel width, computed once
function AegisPageRoles:tagHintLines()
    if self.tagHint then return self.tagHint end
    local maxW = self.tagW - 28
    local lines = {}
    local current = ""
    for word in string.gmatch(getText("UI_Aegis_HeadTagHint"), "%S+") do
        local candidate = current == "" and word or (current .. " " .. word)
        if current ~= "" and Aegis.strW(UIFont.Small, candidate) > maxW then
            table.insert(lines, current)
            current = word
        else
            current = candidate
        end
    end
    if current ~= "" then table.insert(lines, current) end
    self.tagHint = lines
    return lines
end

-- ------------------------------------------------------------------
-- drawing
-- ------------------------------------------------------------------

function AegisPageRoles.drawRoleRow(list, y, item, alt)
    local c = Aegis.col
    local sel = list.selected == item.index
    local hover = list.mouseoverselected == item.index

    if sel then
        Aegis.roundRect(list, 2, y + 2, list:getWidth() - 4, ROW_H - 4, 8, 1, c.card)
        Aegis.roundRect(list, 2, y + 10, 3, ROW_H - 20, 1, 1, c.gold)
    elseif hover then
        Aegis.roundRect(list, 2, y + 2, list:getWidth() - 4, ROW_H - 4, 8, 0.5, c.card)
    end

    -- grip dots to signal the row can be dragged
    for _, dy in ipairs({ 13, 19, 25 }) do
        Aegis.roundRect(list, 9, y + dy, 3, 3, 1, 0.7, c.muted)
        Aegis.roundRect(list, 14, y + dy, 3, 3, 1, 0.7, c.muted)
    end

    local role = item.item
    local tc = sel and c.text or c.muted
    Aegis.text(list, Aegis.fitText(role.name, UIFont.Medium, list:getWidth() - 80), 24, y + math.floor((ROW_H - Aegis.fontH(UIFont.Medium)) / 2), UIFont.Medium, tc)
    -- small dot in the picked tag color (double click changes it)
    if role.color then
        Aegis.roundRect(list, list:getWidth() - 42, y + math.floor(ROW_H / 2) - 4, 8, 8, 4, 1, role.color)
    end
    Aegis.textRight(list, tostring(#(role.rights or {})), list:getWidth() - 14, y + math.floor((ROW_H - Aegis.fontH(UIFont.Small)) / 2), UIFont.Small, c.goldDim)
    return y + ROW_H
end

function AegisPageRoles.drawAssignment(list, y, item, alt)
    local c = Aegis.col
    local hover = list.mouseoverselected == item.index
    if hover then
        Aegis.roundRect(list, 2, y + 1, list:getWidth() - 4, 28, 6, 0.5, c.card)
    end
    local z = item.item
    -- both sides share the row, long names/roles would overlap otherwise
    local roleW = math.min(Aegis.strW(UIFont.Small, z.role), math.floor((list:getWidth() - 24) * 0.45))
    local userW = list:getWidth() - 24 - roleW - 8
    Aegis.text(list, Aegis.fitText(z.user, UIFont.Small, userW), 12, y + 6, UIFont.Small, c.text)
    Aegis.textRight(list, Aegis.fitText(z.role, UIFont.Small, roleW), list:getWidth() - 12, y + 6, UIFont.Small, c.gold)
    return y + 30
end

-- self healing: if one of the two player combos stayed empty although the
-- scoreboard cache has entries (the head tag dropdown could stay empty
-- although the population logic is identical for both combos), do a
-- cheap check on every frame and refill on demand
-- instead of waiting for the next scoreboard event
function AegisPageRoles:checkCombos()
    if #(Aegis.scoreboard or {}) == 0 then return end
    local broken = (self.userCombo and self.userCombo.selected == 0)
        or (self.tagCombo and self.tagCombo.selected == 0)
    if broken then self:fillPlayerCombo() end
end

function AegisPageRoles:prerender()
    local c = Aegis.col
    local pad = 20
    self:checkCombos()

    Aegis.roundFrame(self, pad, pad, LIST_W, self.height - pad * 2 - 80, 10, 1, c.line, c.panel)

    local dx = pad + LIST_W + 20
    local dw = self.width - dx - pad
    Aegis.roundFrame(self, dx, pad, dw, self.rightsBottom and (self.rightsBottom - pad + 8) or 100, 10, 1, c.line, c.panel)
    Aegis.icon(self, "roles", dx + 14, pad + 12, 15, 1, c.gold)
    local title = self.selectedRole and self.selectedRole.name or getText("UI_Aegis_RoleNoneSelected")
    Aegis.text(self, Aegis.fitText(title, UIFont.Medium, dw - 60), dx + 36, pad + 10, UIFont.Medium, self.selectedRole and c.text or c.muted)
    -- labels of the player panel block, next to its widgets
    if self.ppHeaderY then
        Aegis.text(self, getText("UI_Aegis_RolePanelSection"), dx + 14, self.ppHeaderY, UIFont.Small, c.gold)
        Aegis.text(self, getText("UI_Aegis_RolePanelTiles"), dx + 14, self.ppTilesY + 4, UIFont.Small, c.muted)
        Aegis.text(self, getText("UI_Aegis_RolePanelTilesHint"), dx + 14, self.ppHintY, UIFont.Small, c.muted)
    end
    -- the assignments and head tag cards draw themselves in the scroll
    -- container (self.scroll:prerender, see createChildren)
end

-- server responses, in solo the server side calls in here directly
function AegisRolesClient.receive(data)
    local page = AegisPageRoles.instance
    if not page or not data then return end
    page:setData(data)
end

Events.OnServerCommand.Add(function(module, command, args)
    if module ~= "AegisAdmin" then return end
    local page = AegisPageRoles.instance
    if command == "roleData" then
        -- roleData follows every save, successful or rejected; only on
        -- success is waitingForSave still set
        if page and page.waitingForSave then
            page.waitingForSave = nil
            Aegis.showToast(getText("UI_Aegis_RoleSaved"))
            local saved = page.savedTag
            page.savedTag = nil
            pcall(function() page:applyTagSetting(saved) end)
        end
        AegisRolesClient.receive(args)
    elseif command == "roleSave" and args and args.ok == false then
        if page then page.waitingForSave = nil end
        Aegis.showToast(getText("UI_Aegis_RoleConflict"))
    end
end)

-- scoreboard responses refresh the player combo while the page is open;
-- the Aegis.scoreboard cache is filled by the players page handler, which
-- runs before this one because of the require order
Events.OnScoreboardUpdate.Add(function()
    local page = AegisPageRoles.instance
    if page and page:isVisible() and page.userCombo then
        page:fillPlayerCombo()
    end
end)

AegisWindow.registerPage({
    id = "roles",
    icon = "roles",
    label = "UI_Aegis_NavRoles",
    create = AegisPageRoles.create,
})
