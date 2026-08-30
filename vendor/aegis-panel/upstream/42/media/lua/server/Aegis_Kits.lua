-- Kit registry and claims: admins define kits (one time or cooldown based),
-- entitled players fetch them through the player panel. Registry and claim
-- history live under Aegis/Player/, the grant follows the moderation cart
-- pattern. Claim history is append only and keyed by username, so a claim
-- survives death, respawn and reconnect. A kit may be gated to Aegis roles;
-- the gate is enforced on the list and on the claim, never only in the UI.
if isClient() then return end

require "Aegis_Store"
require "Aegis_Roles"
require "Aegis_Log"
require "Aegis_Moderation"
require "Aegis_Boost"

AegisKits = AegisKits or {}

local PLAYER_MODULE = "AegisPlayer"

-- pseudo entry in the gate of a kit: unlocked while the player holds
-- booster status. Sits next to real role names and is or-linked with them,
-- the "@" cannot collide with a role name (roles are player facing labels)
local BOOSTER_ROLE = "@booster"
AegisKits.BOOSTER_ROLE = BOOSTER_ROLE

local KITS_FILE = AegisStore.ROOT .. "/Player/kits.txt"
local CLAIMS_FILE = AegisStore.ROOT .. "/Player/claims.txt"

local MAX_KITS = 100
local MAX_KIT_ITEMS = 20
local PER_ENTRY = 100
local PER_KIT_TOTAL = 500
local MAX_CD_HOURS = 8760
local MAX_NAME = 48
local MAX_ID = 24
local MAX_KIT_ROLES = 16
local MAX_ROLE_NAME = 48
local MAX_USER = 48
-- claim holders sent to the editor at most; the file itself may hold up
-- to 50000 lines, that list has no business on a client
local CLAIM_LIST_CAP = 300

-- "once" = one grant ever, "cd" = fixed cooldown in hours, "month" = one
-- grant per calendar month (not 720 hours)
local MODES = { once = true, cd = true, month = true }

local MONTH_DAYS = { 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 }

local function daysInMonth(y, m)
    if m == 2 and ((y % 4 == 0 and y % 100 ~= 0) or y % 400 == 0) then return 29 end
    return MONTH_DAYS[m] or 30
end

-- both stamps go through the same calendar, so the verdict does not shift
-- with the server timezone
local function sameMonth(a, b)
    local ta = AegisShared.dateParts(a)
    local tb = AegisShared.dateParts(b)
    if type(ta) ~= "table" or type(tb) ~= "table" then return false end
    return ta.year == tb.year and ta.month == tb.month
end

-- hours left until the first of the next month, derived from the elapsed
-- part of the current month so no epoch inversion is needed
local function monthWaitHours(now)
    local t = AegisShared.dateParts(now)
    if type(t) ~= "table" then return 0 end
    local elapsed = (t.day - 1) * 86400 + t.hour * 3600 + t.min * 60 + t.sec
    local left = daysInMonth(t.year, t.month) * 86400 - elapsed
    if left < 0 then left = 0 end
    return math.floor(left / 360 + 0.5) / 10
end

-- id -> { id, name, mode ("once"|"cd"), cooldownH, items = { { fullType, count } },
--         roles = { roleName } (empty = open to everyone with kit access) }
local kits = nil
local kitsIncomplete = false
-- username -> { kitId -> epoch of the latest claim }
local claims = nil
local claimsIncomplete = false

local function cap(v, max)
    local s = tostring(v):gsub("%c", " ")
    if #s > max then s = s:sub(1, max) end
    return s
end

local function idOk(id)
    return type(id) == "string" and id ~= "" and #id <= MAX_ID and id:match("^[a-z0-9]+$") ~= nil
end

-- the fullType must stay clear of the separators of the kit line format
local function typeOk(t)
    return type(t) == "string" and t ~= "" and #t <= 100 and not t:find("[%c%s|;:]")
end

-- role names may carry spaces and commas (AegisShared.sanitizeName keeps
-- them), only the field separator and control chars are out
local function roleOk(name)
    return type(name) == "string" and name ~= "" and #name <= MAX_ROLE_NAME
        and not name:find("[%c|]")
end

-- ---------- registry file ----------
-- line: K|id|name|mode|cooldownH|item:count;item:count[|role|role...]
--
-- the role gate is trailing and one role per field, so old six field lines
-- keep loading (no roles = open to everyone with kit access) and a role
-- name containing a comma or semicolon cannot break the format

local function parseKitLine(line)
    local parts = {}
    for field in string.gmatch(line .. "|", "([^|]*)|") do
        table.insert(parts, field)
    end
    if parts[1] ~= "K" then return nil end
    local id, name, mode, cd, itemsField = parts[2], parts[3], parts[4], parts[5], parts[6]
    if not idOk(id) then return nil end
    if not MODES[mode] then return nil end
    local items = {}
    for entry in (itemsField or ""):gmatch("[^;]+") do
        local fullType, count = entry:match("^([^:]+):(%d+)$")
        if fullType and typeOk(fullType) and #items < MAX_KIT_ITEMS then
            table.insert(items, {
                fullType = fullType,
                count = math.max(1, math.min(PER_ENTRY, tonumber(count) or 1)),
            })
        end
    end
    local roles = {}
    local seen = {}
    for i = 7, #parts do
        local r = parts[i]
        if roleOk(r) and not seen[r] and #roles < MAX_KIT_ROLES then
            seen[r] = true
            table.insert(roles, r)
        end
    end
    return {
        id = id,
        name = (name and name ~= "") and name or id,
        mode = mode,
        cooldownH = math.max(1, math.min(MAX_CD_HOURS, math.floor(tonumber(cd) or 24))),
        items = items,
        roles = roles,
    }
end

local function kitLine(kit)
    local parts = {}
    for _, it in ipairs(kit.items) do
        table.insert(parts, it.fullType .. ":" .. tostring(it.count))
    end
    local line = "K|" .. kit.id .. "|" .. kit.name:gsub("[%c|]", " ") .. "|" .. kit.mode
        .. "|" .. tostring(kit.cooldownH) .. "|" .. table.concat(parts, ";")
    for _, r in ipairs(kit.roles or {}) do
        line = line .. "|" .. r
    end
    return line
end

local function loadKits()
    if kits then return end
    kits = {}
    kitsIncomplete = false
    local lines, truncated = AegisStore.readLines(KITS_FILE, 2000)
    if lines == nil or truncated then kitsIncomplete = true end
    for _, line in ipairs(lines or {}) do
        local kit = parseKitLine(line)
        if kit then kits[kit.id] = kit end
    end
end

-- full rewrite, refused after an incomplete read (zone registry pattern):
-- rewriting on top of a partial load would silently drop unread kits
local function saveKits()
    if kitsIncomplete then
        print("[Aegis] Kit registry write-protected, change not saved")
        return false
    end
    local lines = {}
    for _, kit in pairs(kits) do
        table.insert(lines, kitLine(kit))
    end
    table.sort(lines)
    local content = table.concat(lines, "\n")
    if #lines > 0 then content = content .. "\n" end
    return AegisStore.write(KITS_FILE, content)
end

-- ---------- claim file ----------
-- append only, line: C|user|kitId|epoch

local function loadClaims()
    if claims then return end
    claims = {}
    claimsIncomplete = false
    local lines, truncated = AegisStore.readLines(CLAIMS_FILE, 50000)
    if lines == nil or truncated then claimsIncomplete = true end
    for _, line in ipairs(lines or {}) do
        local user, kitId, epoch = line:match("^C|([^|]+)|([^|]+)|(%d+)$")
        if user and idOk(kitId) then
            claims[user] = claims[user] or {}
            local e = tonumber(epoch) or 0
            if e > (claims[user][kitId] or 0) then claims[user][kitId] = e end
        end
    end
    -- cooldown kits append forever; near the read cap the file gets
    -- compacted to one line per user and kit (the map holds exactly
    -- that), otherwise claims would eventually block server wide
    --. Only after a complete read, a truncated read
    -- must never shrink the file
    if not claimsIncomplete and lines and #lines > 20000 then
        local out = {}
        for user, kitMap in pairs(claims) do
            for kitId, e in pairs(kitMap) do
                table.insert(out, "C|" .. user .. "|" .. kitId .. "|" .. tostring(e))
            end
        end
        table.sort(out)
        local content = table.concat(out, "\n")
        if #out > 0 then content = content .. "\n" end
        AegisStore.write(CLAIMS_FILE, content)
        print("[Aegis] kit claims compacted: " .. tostring(#lines) .. " -> " .. tostring(#out) .. " lines")
    end
end

-- full rewrite out of the map, one line per user and kit. The file only
-- knows appends, there is no delete line in the format, so dropping a
-- single claim always costs the whole file. Refused after an incomplete
-- read, that would wipe every claim the read never saw
local function saveClaims()
    if claimsIncomplete then
        print("[Aegis] Claim history incomplete, write refused")
        return false
    end
    local out = {}
    for user, kitMap in pairs(claims) do
        for kitId, e in pairs(kitMap) do
            table.insert(out, "C|" .. user .. "|" .. kitId .. "|" .. tostring(e))
        end
    end
    table.sort(out)
    local content = table.concat(out, "\n")
    if #out > 0 then content = content .. "\n" end
    return AegisStore.write(CLAIMS_FILE, content)
end

-- ---------- exports ----------

local function scriptFor(fullType)
    local script = getScriptManager():FindItem(fullType)
    if not script then return nil end
    -- exclude corpses by script name, getTypeString does not exist on the
    -- script in B42 (see the moderation cart)
    local n = script:getName()
    if n and n:find("Corpse") then return nil end
    return script
end

function AegisKits.list()
    loadKits()
    local out = {}
    for _, kit in pairs(kits) do
        table.insert(out, kit)
    end
    table.sort(out, function(a, b)
        if a.name ~= b.name then return a.name < b.name end
        return a.id < b.id
    end)
    return out
end

-- a role name is accepted when it exists, or when this kit already carries
-- it: a role deleted meanwhile must not drop out of the gate on the next
-- save, that would widen the kit back to everyone behind the admin's back
local function roleAccepted(name, stored)
    if name == BOOSTER_ROLE then return true end
    if AegisRoles and AegisRoles.roleExists then
        local ok, res = pcall(AegisRoles.roleExists, name)
        if ok and res == true then return true end
    end
    for _, r in ipairs(stored or {}) do
        if r == name then return true end
    end
    return false
end

-- booster status of a username, read through the boost store
local function isBooster(userName)
    if type(userName) ~= "string" or userName == "" then return false end
    if not (AegisBoost and AegisBoost.isBooster) then return false end
    local ok, res = pcall(AegisBoost.isBooster, userName)
    return ok and res == true
end

-- true while the boost store failed to read completely; booster gated kits
-- lock then instead of silently closing (a drop reads like a revoke)
local function boostStoreDown()
    if not (AegisBoost and AegisBoost.available) then return false end
    local ok, res = pcall(AegisBoost.available)
    return not ok or res == false
end

local function boostKeySet()
    if not (AegisBoost and AegisBoost.keySet) then return false end
    local ok, res = pcall(AegisBoost.keySet)
    return ok and res == true
end

local function hasBoosterGate(kit)
    for _, r in ipairs(kit and kit.roles or {}) do
        if r == BOOSTER_ROLE then return true end
    end
    return false
end

-- gate of a kit: no entry = open. Stored names of roles that no longer
-- exist never match; they stay in the file so a role recreated under the
-- same name works again and so nobody is silently let in. @booster is
-- checked against the boost store and counts like any other entry, so a
-- kit gated to "Veteran" plus @booster opens for either
local function kitAllowedFor(kit, roleName, userName)
    local list = kit and kit.roles
    if type(list) ~= "table" or #list == 0 then return true, "open" end
    for _, r in ipairs(list) do
        if r == BOOSTER_ROLE then
            -- an unreadable boost store never opens the gate, the caller
            -- reports "unavailable" instead
            if not boostStoreDown() and isBooster(userName) then return true, "boost" end
        elseif type(roleName) == "string" and roleName ~= "" and r == roleName then
            -- the second value is WHY the player gets this kit (shown next
            -- to the name); only his own role travels, never the catalog
            return true, r
        end
    end
    return false
end

-- boost scope: no pp.kits, access exists only through the configured boost
-- key. Exactly the booster gated kits open, everything else stays hidden
local function kitVisibleFor(kit, roleName, userName, boostOnly)
    if boostOnly then
        if not hasBoosterGate(kit) then return false end
        if not boostStoreDown() and isBooster(userName) then return true, "boost" end
        return false
    end
    return kitAllowedFor(kit, roleName, userName)
end

-- assigned role of a username, never rights
local function roleOf(name)
    if not isServer() then return nil end
    if not (AegisRoles and AegisRoles.assignedRole) then return nil end
    local ok, r = pcall(AegisRoles.assignedRole, name)
    if ok and type(r) == "string" and r ~= "" then return r end
    return nil
end

-- a create whose derived id is taken must not land on the existing kit:
-- that silently replaced its items AND dropped its role gate
function AegisKits.freeId(id)
    loadKits()
    if not idOk(id) or not kits[id] then return id end
    local base = id
    for n = 2, 99 do
        local suffix = tostring(n)
        local trimmed = base
        if #trimmed + #suffix > MAX_ID then trimmed = trimmed:sub(1, MAX_ID - #suffix) end
        local candidate = trimmed .. suffix
        if not kits[candidate] then return candidate end
    end
    return nil
end

function AegisKits.versionOf(id)
    loadKits()
    local kit = idOk(id) and kits[id] or nil
    return kit and (kit.version or 1) or 0
end

function AegisKits.save(kit)
    loadKits()
    if type(kit) ~= "table" or not idOk(kit.id) then return false end
    if not MODES[kit.mode] then return false end
    local items = {}
    local total = 0
    for _, it in pairs(type(kit.items) == "table" and kit.items or {}) do
        if #items >= MAX_KIT_ITEMS then break end
        if type(it) == "table" and typeOk(it.fullType) and scriptFor(it.fullType) then
            local count = math.max(1, math.min(PER_ENTRY, math.floor(tonumber(it.count) or 1)))
            if total + count <= PER_KIT_TOTAL then
                total = total + count
                table.insert(items, { fullType = it.fullType, count = count })
            end
        end
    end
    if #items == 0 then return false end
    local stored = kits[kit.id]
    if not stored then
        local n = 0
        for _ in pairs(kits) do n = n + 1 end
        if n >= MAX_KITS then return false end
    end
    local roles = {}
    local seenRole = {}
    for _, r in pairs(type(kit.roles) == "table" and kit.roles or {}) do
        if #roles >= MAX_KIT_ROLES then break end
        if roleOk(r) and not seenRole[r] and roleAccepted(r, stored and stored.roles) then
            seenRole[r] = true
            table.insert(roles, r)
        end
    end
    table.sort(roles)
    -- memory only counter against a stale second editor; clients always
    -- read it from the payload, so a restart starting at 1 is harmless
    kits[kit.id] = {
        id = kit.id,
        name = cap(kit.name or kit.id, MAX_NAME),
        mode = kit.mode,
        cooldownH = math.max(1, math.min(MAX_CD_HOURS, math.floor(tonumber(kit.cooldownH) or 24))),
        items = items,
        roles = roles,
        version = (stored and stored.version or 0) + 1,
    }
    return saveKits()
end

-- gate of a kit as log text, "all" without any entry
function AegisKits.rolesText(id)
    loadKits()
    local kit = idOk(id) and kits[id] or nil
    if not kit or type(kit.roles) ~= "table" or #kit.roles == 0 then return "all" end
    return table.concat(kit.roles, ", ")
end

function AegisKits.remove(id)
    loadKits()
    if not idOk(id) or not kits[id] then return false end
    kits[id] = nil
    return saveKits()
end

-- claim for the sender himself: true on success, otherwise false plus a
-- reason ("once"|"cooldown"|"gone"|"unavailable"|"error") and the remaining
-- hours for cooldown. boostOnly mirrors the list scope of the sender. Grant
-- first, record after: a failed grant must not burn the claim, a recorded
-- claim without items would eat the kit.
function AegisKits.claim(player, kitId, boostOnly)
    loadKits()
    loadClaims()
    local name = player:getUsername()
    if type(name) ~= "string" or name == "" or name:find("[%c|]") then
        return false, "error"
    end
    if claimsIncomplete then
        -- a partial claim history could hand out one time kits twice
        print("[Aegis] Claim history incomplete, claims blocked")
        return false, "error"
    end
    local kit = idOk(kitId) and kits[kitId] or nil
    if not kit then return false, "gone" end
    -- the gate is enforced here, not only in the list: a hand sent request
    -- for a foreign kit must fail the same way a missing kit does
    if isServer() and not kitVisibleFor(kit, roleOf(name), name, boostOnly) then
        -- the list shows these locked, the claim answer matches
        if hasBoosterGate(kit) and boostStoreDown() then return false, "unavailable" end
        return false, "gone"
    end
    if player:isDead() then return false, "error" end
    local now = AegisShared.realTime()
    local last = claims[name] and claims[name][kit.id]
    if last then
        if kit.mode == "once" then return false, "once" end
        if kit.mode == "month" then
            -- one grant per calendar month, the wait runs to the first of
            -- the next one and not 720 hours from the last claim
            if sameMonth(last, now) then
                return false, "month", monthWaitHours(now)
            end
        else
            local waitS = kit.cooldownH * 3600 - (now - last)
            if waitS > 0 then
                return false, "cooldown", math.floor(waitS / 360 + 0.5) / 10
            end
        end
    end
    local granted = 0
    for _, it in ipairs(kit.items) do
        if scriptFor(it.fullType) then
            local okGrant = pcall(function()
                local items = player:getInventory():AddItems(it.fullType, it.count)
                sendAddItemsToContainer(player:getInventory(), items)
            end)
            if okGrant then granted = granted + it.count end
        end
    end
    if granted == 0 then return false, "error" end
    claims[name] = claims[name] or {}
    claims[name][kit.id] = now
    AegisStore.append(CLAIMS_FILE, "C|" .. name .. "|" .. kit.id .. "|" .. tostring(now))
    AegisLog.write("Actions", "Kits", name, "Kit claimed by " .. name .. ": " .. kit.id .. " (" .. granted .. " items)")
    return true
end

-- ---------- claim maintenance ----------

-- holders of a claim on one kit, raw: username plus the epoch of the last
-- claim. No text is built here, on a dedicated server getText hands back
-- the bare key. Second return is the real total, the list itself is capped
function AegisKits.claimUsers(kitId)
    loadClaims()
    if not idOk(kitId) then return {}, 0 end
    local out = {}
    for user, kitMap in pairs(claims) do
        if kitMap[kitId] then
            table.insert(out, { user = user, epoch = kitMap[kitId] })
        end
    end
    table.sort(out, function(a, b) return a.user < b.user end)
    local total = #out
    while #out > CLAIM_LIST_CAP do table.remove(out) end
    return out, total
end

-- claims across every kit, the number a full reset drops
function AegisKits.claimTotal()
    loadClaims()
    local n = 0
    for _, kitMap in pairs(claims) do
        for _ in pairs(kitMap) do n = n + 1 end
    end
    return n
end

-- false while the history came in only partly; the page greys its reset
-- out then and the server refuses anyway
function AegisKits.claimsReadable()
    loadClaims()
    return not claimsIncomplete
end

-- claim reset. scope "kit" clears one kit for everybody, "user" one player
-- on one kit, "all" the whole history. The last one is what a world wipe
-- needs: the claim file sits in the Aegis folder and not in the save, so a
-- fresh world used to start with every kit still claimed. Map and file are
-- changed together, otherwise the reset would only bite after a restart.
-- Returns the number of cleared claims, or nil plus a reason key
-- ("incomplete"|"none"|"error")
function AegisKits.resetClaims(scope, kitId, userName)
    loadClaims()
    if claimsIncomplete then
        -- rewriting on top of a partial read would drop foreign claims
        print("[Aegis] Claim history incomplete, reset blocked")
        return nil, "incomplete"
    end
    local removed = 0
    if scope == "all" then
        removed = AegisKits.claimTotal()
        claims = {}
    elseif scope == "kit" then
        if not idOk(kitId) then return nil, "error" end
        for _, kitMap in pairs(claims) do
            if kitMap[kitId] then
                kitMap[kitId] = nil
                removed = removed + 1
            end
        end
    elseif scope == "user" then
        if not idOk(kitId) then return nil, "error" end
        if type(userName) ~= "string" or userName == "" or userName:find("[%c|]") then
            return nil, "error"
        end
        local kitMap = claims[userName]
        if kitMap and kitMap[kitId] then
            kitMap[kitId] = nil
            removed = 1
        end
    else
        return nil, "error"
    end
    if removed == 0 then return nil, "none" end
    -- an emptied map keeps its user alive in memory and in the file
    local empty = {}
    for user, kitMap in pairs(claims) do
        local any = false
        for _ in pairs(kitMap) do
            any = true
            break
        end
        if not any then table.insert(empty, user) end
    end
    for _, user in ipairs(empty) do claims[user] = nil end
    if not saveClaims() then
        -- the map already dropped the entries, without a fresh read memory
        -- and file would disagree until the next restart
        claims = nil
        loadClaims()
        return nil, "error"
    end
    return removed
end

-- ---------- network ----------

-- reply to the sender only: over the network in MP, in solo directly to
-- the OnServerCommand listeners of the same process
local function toClient(player, module, command, args)
    if isServer() then
        sendServerCommand(player, module, command, args)
    else
        triggerEvent("OnServerCommand", module, command, args)
    end
end

-- one throttle slot per username and command
local lastReq = {}
local function throttled(name, command, seconds)
    local now = AegisShared.realTime()
    local key = name .. "\n" .. command
    if lastReq[key] and now - lastReq[key] < seconds then return true end
    lastReq[key] = now
    return false
end

local function senderName(player)
    local name = player:getUsername()
    if type(name) == "string" and name ~= "" then return name end
    return nil
end

-- kit entitlement of the sender via the pp column of the role file; reads
-- assignment plus panel flags only, never rights (roles must not grant
-- admin access). "full" with the kits flag; without it a configured boost
-- key still yields "boost" (redeem strip plus the booster gated kits, the
-- claim path mirrors the same rule). Solo has no role file, the workshop
-- player counts as fully entitled there.
local function panelKitScope(name)
    -- server switch (sandbox): kits off closes the whole player side in
    -- BOTH modes, booster strip included. The admin editor keeps working
    if not AegisShared.featureOn("PlayerKits") then return nil end
    if not isServer() then return "full" end
    if not (AegisRoles and AegisRoles.playerPanelFor) then return nil end
    local ok, pp = pcall(AegisRoles.playerPanelFor, name)
    if not ok or type(pp) ~= "table" then return nil end
    if pp.kits == true then return "full" end
    if boostKeySet() then return "boost" end
    return nil
end

-- player scope: role filtered and without the gate itself, the role
-- catalog is admin data. Admin scope carries the gate for the editor.
local function kitPayload(playerScope, roleName, shared, userName, boostOnly)
    local list = {}
    local hidden = 0
    for _, kit in ipairs(shared or AegisKits.list()) do
        local pass, locked, why = true, false, nil
        if playerScope and isServer() then
            pass, why = kitVisibleFor(kit, roleName, userName, boostOnly)
            -- an unreadable boost store keeps booster kits on the page,
            -- locked; hiding them would read like a revoke to the player
            if not pass and hasBoosterGate(kit) and boostStoreDown() then
                pass = true
                locked = true
            end
        end
        if not pass then hidden = hidden + 1 end
        if pass then
            local items = {}
            for _, it in ipairs(kit.items) do
                table.insert(items, { fullType = it.fullType, count = it.count })
            end
            local entry = {
                id = kit.id, name = kit.name, mode = kit.mode,
                cooldownH = kit.cooldownH, items = items,
            }
            if locked then entry.locked = true end
            if playerScope and why and why ~= "open" then entry.why = why end
            if not playerScope then
                local roles = {}
                for _, r in ipairs(kit.roles or {}) do table.insert(roles, r) end
                entry.roles = roles
                entry.version = kit.version or 1
            end
            table.insert(list, entry)
        end
    end
    return list, hidden
end

local function knownRoleNames()
    if not (AegisRoles and AegisRoles.roleNames) then return {} end
    local ok, names = pcall(AegisRoles.roleNames)
    if ok and type(names) == "table" then return names end
    return {}
end

-- the two pages share the kitList command, scope tells them apart: the
-- admin editor drops player payloads and the panel page drops admin ones
local function pushList(player, playerScope, name, shared, boostOnly)
    if playerScope then
        -- hidden tells the page apart: an empty list because the role
        -- lacks a gate reads differently from no kits existing at all
        local list, hidden = kitPayload(true, roleOf(name), shared, name, boostOnly)
        toClient(player, AegisShared.MODULE, "kitList",
            { kits = list, scope = "player", hidden = hidden })
    else
        toClient(player, AegisShared.MODULE, "kitList",
            { kits = kitPayload(false), roles = knownRoleNames() })
    end
end

local function deny(player)
    toClient(player, AegisShared.MODULE, "denied", { area = "kits" })
end

-- fresh panel list for one player, called by the role side after an
-- assignment or role edit so a gained or lost kit shows up without a
-- reconnect. Lost entitlement sends an empty list instead of nothing, or
-- the page would keep showing the old kits
function AegisKits.pushPlayerList(player)
    if not player then return end
    local name = senderName(player)
    if not name then return end
    local scope = panelKitScope(name)
    if not scope then
        toClient(player, AegisShared.MODULE, "kitList", { kits = {}, scope = "player" })
        return
    end
    pushList(player, true, name, nil, scope == "boost")
end

-- after a registry change: every online panel player gets its own filtered
-- list, otherwise a changed gate only lands on the next page open
local function pushAllPlayers()
    if not isServer() then return end
    pcall(function()
        local players = getOnlinePlayers()
        if not players then return end
        -- one registry pass for everyone, the filter per player only reads
        -- from it; rebuilding it per player was quadratic on a full server
        local shared = AegisKits.list()
        for i = 0, players:size() - 1 do
            local p = players:get(i)
            if p then
                local name = senderName(p)
                local scope = name and panelKitScope(name) or nil
                if scope then pushList(p, true, name, shared, scope == "boost") end
            end
        end
    end)
end

-- ---------- admin module commands ----------

local AdminCommands = {}

-- readable for admins with the kits area AND for entitled panel players.
-- args.player asks for the panel view, which is role filtered even for an
-- admin: his own panel page must match what he may actually claim
AdminCommands.kitList = function(player, args)
    local name = senderName(player)
    if not name then return end
    local wantPanel = type(args) == "table" and args.player == true
    -- own throttle slot per view, otherwise the editor and the panel page
    -- of the same admin cancel each other out when both open at once
    if throttled(name, wantPanel and "kitListPanel" or "kitList", 1) then return end
    if not wantPanel and AegisRoles.canArea(player, "kits") then
        pushList(player, false)
        return
    end
    local scope = panelKitScope(name)
    if not scope then return end
    pushList(player, true, name, nil, scope == "boost")
end

AdminCommands.kitSave = function(player, args)
    if not AegisRoles.canArea(player, "kits") then deny(player) return end
    local name = senderName(player)
    if not name then return end
    if throttled(name, "kitSave", 1) then return end
    if type(args) ~= "table" then return end
    local kit = {
        id = type(args.id) == "string" and cap(args.id, MAX_ID) or nil,
        name = type(args.name) == "string" and cap(args.name, MAX_NAME) or nil,
        mode = args.mode,
        cooldownH = args.cooldownH,
        items = args.items,
        roles = args.roles,
    }
    -- a create claims a free id: reusing the derived one would replace an
    -- existing kit and drop its role gate without a word
    if args.isNew == true and idOk(kit.id) then
        kit.id = AegisKits.freeId(kit.id)
    end
    if not idOk(kit.id) then
        toClient(player, AegisShared.MODULE, "kitSave", { ok = false })
        return
    end
    -- stale editor guard, same contract as the roles page: the client
    -- echoes the version it was shown, a mismatch means somebody else
    -- saved in between and would silently lose that change
    local have = AegisKits.versionOf(kit.id)
    if args.isNew ~= true and have > 0 and have ~= (tonumber(args.version) or 0) then
        toClient(player, AegisShared.MODULE, "kitSave",
            { ok = false, reason = "conflict", id = kit.id })
        pushList(player, false)
        return
    end
    local before = AegisKits.rolesText(kit.id)
    local ok = AegisKits.save(kit) == true
    if ok then
        AegisLog.write("Actions", name, kit.id, "Kit saved: " .. kit.id)
        local after = AegisKits.rolesText(kit.id)
        if after ~= before then
            AegisLog.write("Actions", name, kit.id,
                "Kit roles changed: " .. kit.id .. " (" .. before .. " -> " .. after .. ")")
        end
    end
    toClient(player, AegisShared.MODULE, "kitSave", { ok = ok, id = kit.id })
    if ok then
        pushList(player, false)
        pushAllPlayers()
    end
end

AdminCommands.kitRemove = function(player, args)
    if not AegisRoles.canArea(player, "kits") then deny(player) return end
    local name = senderName(player)
    if not name then return end
    if throttled(name, "kitRemove", 1) then return end
    local id = (type(args) == "table" and type(args.id) == "string") and cap(args.id, MAX_ID) or nil
    local ok = id ~= nil and AegisKits.remove(id) == true
    if ok then
        AegisLog.write("Actions", name, id, "Kit removed: " .. id)
    end
    toClient(player, AegisShared.MODULE, "kitRemove", { ok = ok, id = id })
    if ok then
        pushList(player, false)
        pushAllPlayers()
    end
end

-- who holds a claim on one kit, plus the totals the editor shows on its
-- buttons. Names and epochs travel raw, the page builds the text
local function pushClaimList(player, kitId)
    local users, total = AegisKits.claimUsers(kitId)
    toClient(player, AegisShared.MODULE, "kitClaimList", {
        id = kitId, users = users, total = total,
        allTotal = AegisKits.claimTotal(), readable = AegisKits.claimsReadable(),
    })
end

AdminCommands.kitClaimList = function(player, args)
    if not AegisRoles.canArea(player, "kits") then deny(player) return end
    local name = senderName(player)
    if not name then return end
    if throttled(name, "kitClaimList", 1) then return end
    local id = (type(args) == "table" and type(args.id) == "string") and cap(args.id, MAX_ID) or nil
    if not idOk(id) then return end
    pushClaimList(player, id)
end

AdminCommands.kitClaimReset = function(player, args)
    if not AegisRoles.canArea(player, "kits") then deny(player) return end
    local name = senderName(player)
    if not name then return end
    if throttled(name, "kitClaimReset", 1) then return end
    if type(args) ~= "table" then return end
    local scope = args.scope
    if scope ~= "kit" and scope ~= "user" and scope ~= "all" then return end
    local id = type(args.id) == "string" and cap(args.id, MAX_ID) or nil
    local user = type(args.user) == "string" and cap(args.user, MAX_USER) or nil
    local removed, reason = AegisKits.resetClaims(scope, id, user)
    if not removed then
        toClient(player, AegisShared.MODULE, "kitClaimReset",
            { ok = false, scope = scope, id = id, reason = reason })
        return
    end
    local what = "kit " .. tostring(id)
    local target = id or ""
    if scope == "all" then
        what = "every kit"
        target = "claims"
    elseif scope == "user" then
        what = "kit " .. tostring(id) .. " for " .. tostring(user)
        target = user or ""
    end
    -- the full wipe asks for a reason in the dialog, it belongs in the log
    local note = type(args.reason) == "string" and cap(args.reason, 100) or ""
    if note ~= "" then what = what .. ", reason: " .. note end
    AegisLog.write("Actions", name, target,
        "Kit claims reset: " .. what .. " (" .. tostring(removed) .. " claims)")
    toClient(player, AegisShared.MODULE, "kitClaimReset",
        { ok = true, scope = scope, id = id, user = user, count = removed })
    if idOk(id) then pushClaimList(player, id) end
    -- claim state is not part of the kit payload, the push keeps the panel
    -- lists of everybody current after the change
    pushAllPlayers()
end

-- ---------- player module commands ----------

local PlayerCommands = {}

-- the claimer is always the sender himself, args only pick the kit
PlayerCommands.kitClaim = function(player, args)
    args = args or {}
    local name = senderName(player)
    if not name then return end
    if throttled(name, "kitClaim", 2) then return end
    local id = type(args.id) == "string" and cap(args.id, MAX_ID) or ""
    local scope = panelKitScope(name)
    if not scope then
        toClient(player, PLAYER_MODULE, "kitClaim", { ok = false, id = id, reason = "gone" })
        return
    end
    local claimed, reason, wait = AegisKits.claim(player, id, scope == "boost")
    if claimed then
        toClient(player, PLAYER_MODULE, "kitClaim", { ok = true, id = id })
    else
        toClient(player, PLAYER_MODULE, "kitClaim", { ok = false, id = id, reason = reason, wait = wait })
    end
end

local function onClientCommand(module, command, player, args)
    if module ~= AegisShared.MODULE and module ~= PLAYER_MODULE then return end
    -- suspended senders keep no authority in any Aegis area
    if AegisModeration.isSuspended(player) then return end
    if module == AegisShared.MODULE then
        if AdminCommands[command] then AdminCommands[command](player, args) end
    else
        if PlayerCommands[command] then PlayerCommands[command](player, args) end
    end
end

Events.OnClientCommand.Add(onClientCommand)
