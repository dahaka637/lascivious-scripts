-- Aegis role system: roles bundle area rights, assignments attach them
-- to usernames. Vanilla admins without an assignment keep full access
-- so nobody locks themselves out on first start.
if isClient() then return end

require "Aegis_Store"

AegisRoles = AegisRoles or {}

local FILE = AegisStore.ROOT .. "/Roles/roles.txt"

local roles = {}
local assignments = {}
local loaded = false
-- highest area migration this file has already been through, read from
-- and written back to the M| marker line
local migrationDone = 0

local validAreas = {}
for _, b in ipairs(AegisShared.AREAS) do validAreas[b] = true end

-- optional trailing color field, floats 0..1 as "r,g,b"
local function clamp01(v)
    v = tonumber(v)
    if not v then return nil end
    if v < 0 then v = 0 elseif v > 1 then v = 1 end
    return v
end

local function parseColor(text)
    if type(text) ~= "string" then return nil end
    local r, g, b = text:match("^([%d%.]+),([%d%.]+),([%d%.]+)$")
    r, g, b = clamp01(r), clamp01(g), clamp01(b)
    if r and g and b then return { r = r, g = g, b = b } end
    return nil
end

-- optional player panel field "panel:1,tiles:600,kits:1" per role: the
-- extra budgets for the blue player window. Missing field = no extras.
-- The panel key is legacy: every player has the panel now, it is
-- still parsed and written so old roles.txt keeps loading
local MAX_CLAIM_TILES = 2000

local function clampTiles(v)
    v = tonumber(v)
    if not v then return 0 end
    v = math.floor(v)
    if v < 0 then v = 0 elseif v > MAX_CLAIM_TILES then v = MAX_CLAIM_TILES end
    return v
end

local function parsePlayerPanel(text)
    if type(text) ~= "string" then return nil end
    local pp = nil
    for key, value in text:gmatch("(%a+):(%d+)") do
        if key == "panel" or key == "tiles" or key == "kits" or key == "tag" then
            -- panel is accepted so old lines still parse, its value is
            -- dropped: it blocks nothing any more
            pp = pp or { panel = true, tiles = 0, kits = false, tag = true }
            if key == "tiles" then
                pp.tiles = clampTiles(value)
            elseif key == "kits" then
                pp.kits = value == "1"
            elseif key == "tag" then
                -- head tag on assignment; missing on old lines means on
                pp.tag = value == "1"
            end
        end
    end
    return pp
end

-- panel is normalized hard to true so stored lines and fresh saves look
-- the same, no matter what an old file or an older client carried
local function sanitizePlayerPanel(t)
    if type(t) ~= "table" then return nil end
    return { panel = true, tiles = clampTiles(t.tiles), kits = t.kits == true, tag = t.tag ~= false }
end

local function playerPanelField(pp)
    return "panel:" .. (pp.panel and "1" or "0")
        .. ",tiles:" .. tostring(pp.tiles or 0)
        .. ",kits:" .. (pp.kits and "1" or "0")
        .. ",tag:" .. (pp.tag ~= false and "1" or "0")
end

local function save()
    local lines = {}
    for name, role in pairs(roles) do
        local rights = {}
        for b in pairs(role.rights) do table.insert(rights, b) end
        table.sort(rights)
        local line = "R|" .. name .. "|" .. table.concat(rights, ",") .. "|" .. tostring(role.sort or 999) .. "|" .. tostring(role.version or 1)
        if role.color then
            line = line .. "|" .. string.format("%.3f,%.3f,%.3f", role.color.r, role.color.g, role.color.b)
        end
        if role.pp then
            line = line .. "|" .. playerPanelField(role.pp)
        end
        table.insert(lines, line)
    end
    for user, rname in pairs(assignments) do
        table.insert(lines, "A|" .. user:gsub("|", "_") .. "|" .. rname)
    end
    table.sort(lines)
    -- sorted after the rest on purpose, the marker is bookkeeping and
    -- not part of the data an admin might read first
    table.insert(lines, "M|areas|" .. tostring(migrationDone or 0))
    local content = table.concat(lines, "\n")
    if #lines > 0 then content = content .. "\n" end
    AegisStore.write(FILE, content)
end

-- one time hand over for areas that were split off a wider one: every
-- role holding the parent keeps the new page until an admin takes it
-- away deliberately. Without this the split would quietly revoke the
-- page for everyone, because the stored rights are a set of granted
-- names and a missing name reads as denied
local function migrateAreas()
    local target = AegisShared.AREA_MIGRATION or 0
    if migrationDone >= target then return end
    local changed = 0
    for _, role in pairs(roles) do
        for area, parent in pairs(AegisShared.AREA_PARENT or {}) do
            if role.rights[area] == nil and role.rights[parent] == true then
                role.rights[area] = true
                changed = changed + 1
            end
        end
    end
    migrationDone = target
    -- written even without a change, otherwise the marker never lands
    -- and the pass would run again on every single load
    save()
    if changed > 0 then
        print("[Aegis] Rollen: " .. changed .. " neue Bereichsrechte an die Traeger des Oberbereichs vergeben")
    end
end

local function load()
    if loaded then return end
    loaded = true
    roles = {}
    assignments = {}
    local lines = AegisStore.readLines(FILE, 5000)
    if lines == nil then
        -- read error: continue empty but retry on next access
        loaded = false
        lines = {}
    end
    local pendingAssignments = {}
    for _, line in ipairs(lines) do
        -- generic field split: legacy lines carry fewer fields, newer ones
        -- may carry more; anything beyond the known fields is ignored
        local parts = {}
        for field in string.gmatch(line .. "|", "([^|]*)|") do
            table.insert(parts, field)
        end
        local kind, a, b, c, d = parts[1], parts[2], parts[3], parts[4], parts[5]
        if kind == "R" and a and a ~= "" then
            local rights = {}
            for part in (b or ""):gmatch("[^,]+") do
                if validAreas[part] then rights[part] = true end
            end
            -- trailing fields are matched by content, not position: color
            -- and player panel are both optional, either one may be absent.
            -- Scan starts at field 4 so a hand written short line like
            -- "R|name|rights|panel:1,tiles:600" works too; sort and
            -- version are plain numbers and match neither pattern
            local color, pp = nil, nil
            for i = 4, #parts do
                color = color or parseColor(parts[i])
                pp = pp or parsePlayerPanel(parts[i])
            end
            -- version missing on legacy data without conflict field, start at 1
            roles[a] = { rights = rights, sort = tonumber(c) or 999, version = tonumber(d) or 1, color = color, pp = pp }
        elseif kind == "A" and a and a ~= "" then
            table.insert(pendingAssignments, { user = a, role = b or "" })
        elseif kind == "M" and a == "areas" then
            migrationDone = tonumber(b) or 0
        end
    end
    for _, entry in ipairs(pendingAssignments) do
        if roles[entry.role] then assignments[entry.user] = entry.role end
    end
    -- make sort values gapless, legacy entries without a value go last
    local names = {}
    for name in pairs(roles) do table.insert(names, name) end
    table.sort(names, function(x, y)
        local sx, sy = roles[x].sort or 999, roles[y].sort or 999
        if sx ~= sy then return sx < sy end
        return x < y
    end)
    for i, name in ipairs(names) do roles[name].sort = i end
    -- never migrate on top of a failed read, save() would then write the
    -- empty set over the real file
    if loaded then migrateAreas() end
end

local function isVanillaAdmin(player)
    if not isServer() then return true end
    local ok, res = pcall(function()
        -- the level string alone is NOT enough: "user" is the default
        -- level of every normal player in B42 and custom head tag roles
        -- are levels too. The
        -- registry lookup in AegisShared.levelIsAdmin resolves the level
        -- to its stable role object and reads hasAdminTool there; the
        -- per player role wrapper stays the last resort only
        local levelOk, level = pcall(function()
            return tostring(player:getAccessLevel() or ""):lower()
        end)
        if levelOk then
            return AegisShared.levelIsAdmin(level)
        end
        local role = player:getRole()
        return role and role:hasAdminTool() or false
    end)
    return ok and res == true
end

AegisRoles.isVanillaAdmin = isVanillaAdmin

-- Anti lockout for role management. This used to accept ANY level with
-- the admin tool, and that was far too wide: measured on the B42 role
-- registry, observer, gm and moderator all carry AdminTool, but only
-- "admin" carries RolesWrite. An observer could therefore open the roles
-- page and hand himself every area. The vanilla
-- capability is the honest yardstick: a real server admin can never lock
-- himself out, everyone else needs the area granted explicitly
local function hasVanillaRolesWrite(player)
    if not isServer() then return true end
    local role = player and player:getRole()
    if not role then return false end
    local cap = Capability and Capability.RolesWrite
    if not cap then return false end
    return role:hasCapability(cap) == true
end

AegisRoles.hasVanillaRolesWrite = hasVanillaRolesWrite

-- nil = full access, false = nothing at all, otherwise the role's rights table
--
-- admin only: an Aegis role can only NARROW what a
-- vanilla admin may do, it never grants access by itself. Without admin
-- status there is nothing, no matter what is assigned. Two reasons: the
-- client hides the icon by the same rule, so a role holder without admin
-- status could not reach the panel anyway, and role assignment doubles as
-- the cosmetic head tag for ordinary players, which must not hand out
-- rights as a side effect
function AegisRoles.effectiveRights(player)
    if not isServer() then return nil end
    if not isVanillaAdmin(player) then return false end
    load()
    local name = player and player:getUsername()
    local rname = name and assignments[name]
    if rname and roles[rname] then
        return roles[rname].rights
    end
    return nil
end

function AegisRoles.canArea(player, area)
    local r = AegisRoles.effectiveRights(player)
    if r == nil then return true end
    if r == false then return false end
    return r[area] == true
end

function AegisRoles.canManageRoles(player)
    return hasVanillaRolesWrite(player) or AegisRoles.canArea(player, "roles")
end

-- does the player have access to the suite at all
function AegisRoles.hasAccess(player)
    local r = AegisRoles.effectiveRights(player)
    if r == nil then return true end
    if r == false then return false end
    for _ in pairs(r) do return true end
    return false
end

-- send a client its own rights, plus the name of the assigned Aegis role
-- (if any) for display in the window footer
function AegisRoles.pushRights(player)
    if not isServer() or not player then return end
    load()
    local r = AegisRoles.effectiveRights(player)
    local role = assignments[player:getUsername()]
    if r == nil then
        sendServerCommand(player, AegisShared.MODULE, "rightsSync", { full = true, role = role })
    elseif r == false then
        sendServerCommand(player, AegisShared.MODULE, "rightsSync", { none = true, role = role })
    else
        local list = {}
        for b in pairs(r) do table.insert(list, b) end
        sendServerCommand(player, AegisShared.MODULE, "rightsSync", { rights = list, role = role })
    end
end

local function findOnline(username)
    local players = getOnlinePlayers()
    if not players then return nil end
    for i = 0, players:size() - 1 do
        local p = players:get(i)
        if p and p:getUsername() == username then return p end
    end
    return nil
end

local function pushAllWithRole(rname)
    if not isServer() then return end
    for user, assigned in pairs(assignments) do
        if assigned == rname then
            local p = findOnline(user)
            if p then
                AegisRoles.pushRights(p)
                -- pp fields may have changed with the role, the blue
                -- panel state travels along
                if AegisPlayerPanel and AegisPlayerPanel.push then
                    AegisPlayerPanel.push(p)
                end
                -- the kit gate reads the role name, a role edit can change
                -- what this player may claim
                if AegisKits and AegisKits.pushPlayerList then
                    AegisKits.pushPlayerList(p)
                end
            end
        end
    end
end

-- player panel package for a username. EVERYONE who joins the server has
-- the panel, admins included, so this always
-- returns a package and never nil. A role only adds the extra stages
-- claim tiles and kit access; the pp field panel is not read any more.
-- Without an assigned role: role nil, claimTiles 0, kits false.
-- Invariant: this NEVER consults effectiveRights, a role must not hand
-- out admin rights as a side effect
function AegisRoles.playerPanelFor(username)
    if type(username) ~= "string" or username == "" then
        return { role = nil, color = nil, claimTiles = 0, kits = false }
    end
    load()
    local rname = assignments[username]
    local role = rname and roles[rname]
    local pp = role and role.pp
    -- tag color comes from the engine role of the player, if readable
    local color = nil
    pcall(function()
        local p = findOnline(username)
        if not p then return end
        local r = p:getRole()
        local c = r and r:getColor()
        if c then color = { r = c:getR(), g = c:getG(), b = c:getB() } end
    end)
    return {
        role = rname,
        color = color,
        claimTiles = pp and (pp.tiles or 0) or 0,
        -- kit access defaults to ON (workshop request): a player without a
        -- role may claim kits whose role list is empty, which is what an
        -- open kit means. A role takes it away by storing kits false; WHICH
        -- kits someone sees stays with kitAllowedFor either way
        kits = (pp == nil) or (pp.kits == true),
    }
end

-- role catalog for other server modules (kit gate); names only, in the
-- order set on the roles page. Never exposes rights
function AegisRoles.roleNames()
    load()
    local out = {}
    for name in pairs(roles) do table.insert(out, name) end
    table.sort(out, function(a, b)
        local sa, sb = roles[a].sort or 999, roles[b].sort or 999
        if sa ~= sb then return sa < sb end
        return a < b
    end)
    return out
end

function AegisRoles.roleExists(name)
    if type(name) ~= "string" or name == "" then return false end
    load()
    return roles[name] ~= nil
end

-- assigned role name of a username, nil without an assignment
function AegisRoles.assignedRole(username)
    if type(username) ~= "string" or username == "" then return nil end
    load()
    return assignments[username]
end

-- editor entry: the caller must have passed canManageRoles already, the
-- role command path checks that before this is reached
function AegisRoles.setPlayerPanel(roleName, opts)
    if type(roleName) ~= "string" or type(opts) ~= "table" then return false end
    load()
    local role = roles[roleName]
    if not role then return false end
    role.pp = sanitizePlayerPanel(opts)
    save()
    return true
end

-- full data set for the roles page
local function sendRoleData(player)
    load()
    local roleList = {}
    for name, role in pairs(roles) do
        local rights = {}
        for b in pairs(role.rights) do table.insert(rights, b) end
        table.sort(rights)
        local pp = role.pp and { panel = role.pp.panel, tiles = role.pp.tiles, kits = role.pp.kits, tag = role.pp.tag ~= false } or nil
        table.insert(roleList, { name = name, rights = rights, version = role.version or 1, color = role.color, pp = pp })
    end
    -- order is set by the admin via drag and drop, not alphabetically
    table.sort(roleList, function(a, b)
        local sa, sb = roles[a.name].sort or 999, roles[b.name].sort or 999
        if sa ~= sb then return sa < sb end
        return a.name < b.name
    end)
    local assignmentList = {}
    for user, rname in pairs(assignments) do
        table.insert(assignmentList, { user = user, role = rname })
    end
    table.sort(assignmentList, function(a, b) return a.user < b.user end)
    if isServer() then
        sendServerCommand(player, AegisShared.MODULE, "roleData", { roles = roleList, assignments = assignmentList })
    elseif AegisRolesClient then
        AegisRolesClient.receive({ roles = roleList, assignments = assignmentList })
    end
end

local function deny(player, area)
    if isServer() then
        sendServerCommand(player, AegisShared.MODULE, "denied", { area = area })
    end
end

-- save attempt rejected because of a stale version, e.g. two admins
-- editing the same role at once
local function reject(player, reason)
    if isServer() then
        sendServerCommand(player, AegisShared.MODULE, "roleSave", { ok = false, reason = reason })
    end
end

local Commands = {}

-- role operations go into the actions log; AegisLog loads after this
-- file (require chain), so resolve at runtime instead of require
local function logAction(player, target, text)
    if AegisLog and AegisLog.write then
        AegisLog.write("Actions", player:getUsername(), target, text)
    end
end

Commands.rightsReq = function(player, args)
    AegisRoles.pushRights(player)
end

Commands.roleList = function(player, args)
    if not AegisRoles.canManageRoles(player) then deny(player, "roles") return end
    sendRoleData(player)
end

Commands.roleSave = function(player, args)
    if not AegisRoles.canManageRoles(player) then deny(player, "roles") return end
    if not args or type(args.name) ~= "string" then return end
    load()
    local name = AegisShared.sanitizeName(args.name)
    local existing = roles[name]
    -- staleness check: saving an existing role requires holding the last
    -- loaded version, otherwise another admin saved in the meantime and
    -- their change would be lost silently
    if existing and existing.version ~= (tonumber(args.version) or 0) then
        reject(player, "conflict")
        sendRoleData(player)
        return
    end
    local rights = {}
    if type(args.rights) == "table" then
        for _, b in pairs(args.rights) do
            if validAreas[b] then rights[b] = true end
        end
    end
    -- existing role keeps its slot, new one goes to the end
    local sort = existing and existing.sort
    if not sort then
        sort = 1
        for _, role in pairs(roles) do
            if (role.sort or 0) >= sort then sort = (role.sort or 0) + 1 end
        end
    end
    -- a save without a color keeps the stored one, so a rights-only save
    -- does not wipe the tag color
    local color = existing and existing.color or nil
    if type(args.color) == "table" then
        local r, g, b = clamp01(args.color.r), clamp01(args.color.g), clamp01(args.color.b)
        if r and g and b then color = { r = r, g = g, b = b } end
    end
    -- like the color: a save without pp fields keeps the stored ones, so
    -- the color pick path and older clients do not wipe them
    local pp = existing and existing.pp or nil
    if type(args.pp) == "table" then
        pp = sanitizePlayerPanel(args.pp)
    end
    roles[name] = { rights = rights, sort = sort, version = (existing and existing.version or 0) + 1, color = color, pp = pp }
    save()
    pushAllWithRole(name)
    local list = {}
    for b in pairs(rights) do table.insert(list, b) end
    table.sort(list)
    local ppText = ""
    if type(args.pp) == "table" and pp then
        ppText = "; claim tiles " .. tostring(pp.tiles)
            .. ", kits " .. (pp.kits and "on" or "off")
    end
    logAction(player, name, "Role saved: " .. name
        .. " (rights: " .. (#list > 0 and table.concat(list, ", ") or "none") .. ppText .. ")")
    sendRoleData(player)
end

-- new order from the drag and drop on the roles page
Commands.roleOrder = function(player, args)
    if not AegisRoles.canManageRoles(player) then deny(player, "roles") return end
    if not args or type(args.names) ~= "table" then return end
    load()
    local sort = 1
    local order = {}
    for _, name in ipairs(args.names) do
        if type(name) == "string" and roles[name] then
            roles[name].sort = sort
            sort = sort + 1
            table.insert(order, name)
        end
    end
    save()
    logAction(player, "Roles", "Role order changed: " .. table.concat(order, " > "))
    sendRoleData(player)
end

Commands.roleDelete = function(player, args)
    if not AegisRoles.canManageRoles(player) then deny(player, "roles") return end
    if not args or type(args.name) ~= "string" then return end
    load()
    local name = args.name
    if not roles[name] then return end
    roles[name] = nil
    local affected = {}
    for user, rname in pairs(assignments) do
        if rname == name then table.insert(affected, user) end
    end
    for _, user in ipairs(affected) do assignments[user] = nil end
    save()
    if isServer() then
        for _, user in ipairs(affected) do
            local p = findOnline(user)
            if p then
                AegisRoles.pushRights(p)
                -- the assignment is gone with the role: panel budgets and
                -- the kit gate change in the same moment
                if AegisPlayerPanel and AegisPlayerPanel.push then
                    AegisPlayerPanel.push(p)
                end
                if AegisKits and AegisKits.pushPlayerList then
                    AegisKits.pushPlayerList(p)
                end
            end
        end
    end
    logAction(player, name, "Role deleted: " .. name
        .. (#affected > 0 and (" (" .. #affected .. " assignments removed)") or ""))
    sendRoleData(player)
end

Commands.roleAssign = function(player, args)
    if not AegisRoles.canManageRoles(player) then deny(player, "roles") return end
    if not args or type(args.user) ~= "string" or args.user == "" then return end
    -- full sanitizeName would mangle real usernames, so only block the
    -- characters that break the file format or the manifest
    if #args.user > 48 or args.user:find("[%c|]") then return end
    load()
    local user = args.user
    local rname = args.role
    if rname == "" then rname = nil end
    if rname ~= nil and not roles[rname] then return end
    assignments[user] = rname
    save()
    if isServer() then
        local p = findOnline(user)
        if p then
            AegisRoles.pushRights(p)
            -- the blue panel state changes with the assignment, deliver
            -- it now instead of waiting for the next reconnect
            if AegisPlayerPanel and AegisPlayerPanel.push then
                AegisPlayerPanel.push(p)
            end
            -- same for the kit list, the gate follows the role name
            if AegisKits and AegisKits.pushPlayerList then
                AegisKits.pushPlayerList(p)
            end
        end
    end
    logAction(player, user, rname and ("Role assigned: " .. rname) or "Role assignment removed")
    sendRoleData(player)
end

local function onClientCommand(module, command, player, args)
    if module ~= AegisShared.MODULE then return end
    -- no "require Aegis_Moderation" here: that file requires Aegis_Roles
    -- back, the module is loaded anyway (all server lua files of the
    -- suite load before the first client command)
    if AegisModeration.isSuspended(player) then return end
    if Commands[command] then Commands[command](player, args) end
end

Events.OnClientCommand.Add(onClientCommand)
