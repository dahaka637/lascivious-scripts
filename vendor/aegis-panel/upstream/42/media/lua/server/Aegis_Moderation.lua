-- Moderation core: kick, ban, tempban and warning with evidence package,
-- timed chat mutes, private admin notes and the cart item grant.
-- B42 has no server Lua API for ban/kick, so the server only orchestrates:
-- check permissions, save evidence, then hand enforcement back to the
-- admin client (slash command) or make the target client disconnect
-- itself (Aegis suspensions, moderators without vanilla rights).
if isClient() then return end

require "Aegis_Store"
require "Aegis_Roles"
require "Aegis_Log"

AegisModeration = AegisModeration or {}

local BANS = AegisStore.ROOT .. "/Moderation/sperren.txt"
local MUTES = AegisStore.ROOT .. "/Moderation/mutes.txt"
local HISTORY_DIR = AegisStore.ROOT .. "/Moderation/Historie/"
local NOTES = AegisStore.ROOT .. "/Notes/"

local MAX_REASON = 200
local MAX_HISTORY = 2000
local CART_PER_ENTRY = 100
local CART_TOTAL = 500
local CART_MAX_ENTRIES = 200

-- simple scatter hash as suffix against filename collisions: different
-- usernames that sanitizeName collapses to the same string (special
-- characters, truncation) still end up in separate files
local function keyHash(s)
    local h = 5381
    for i = 1, #s do
        h = (h * 33 + s:byte(i)) % 1000000007
    end
    return h
end

local function targetFile(dir, target)
    return dir .. AegisShared.sanitizeName(target) .. "_" .. tostring(keyHash(target)) .. ".txt"
end

-- ---------- load and save lists ----------
local bans = nil
local mutes = nil

local function loadList(path)
    local list = {}
    local lines = AegisStore.readLines(path, 2000) or {}
    for _, line in ipairs(lines) do
        local user, expiry, reason, admin = line:match("^([^|]+)|([^|]+)|([^|]*)|([^|]*)$")
        if user then
            list[user] = { expiry = tonumber(expiry) or 0, reason = reason, admin = admin }
        end
    end
    return list
end

local function saveList(path, list)
    local lines = {}
    for user, e in pairs(list) do
        table.insert(lines, table.concat({
            user, tostring(e.expiry or 0), (e.reason or ""):gsub("[%c|]", " "), (e.admin or ""):gsub("[%c|]", " "),
        }, "|"))
    end
    table.sort(lines)
    local content = table.concat(lines, "\n")
    if #lines > 0 then content = content .. "\n" end
    AegisStore.write(path, content)
end

local function banList()
    if not bans then bans = loadList(BANS) end
    return bans
end

local function muteList()
    if not mutes then mutes = loadList(MUTES) end
    return mutes
end

-- expiry 0 means unlimited
local function isActive(entry, now)
    return entry and (entry.expiry == 0 or entry.expiry > now)
end

-- ---------- history (warnings, kicks, bans per target) ----------
-- one file per target instead of a shared file: a single global
-- historie.txt would eventually hit the read cap on a long running
-- server and entries beyond it would be invisible forever
local function historyAppend(kind, target, admin, reason)
    AegisStore.append(targetFile(HISTORY_DIR, target), table.concat({
        tostring(AegisShared.realTime()), kind, target:gsub("[%c|]", " "),
        admin:gsub("[%c|]", " "), (reason or ""):gsub("[%c|]", " "),
    }, "|"))
end

local function historyFor(target)
    local entries = {}
    local lines = AegisStore.readLines(targetFile(HISTORY_DIR, target), MAX_HISTORY) or {}
    for _, line in ipairs(lines) do
        local epoch, kind, _, admin, reason = line:match("^([^|]+)|([^|]+)|([^|]*)|([^|]*)|([^|]*)$")
        if epoch then
            table.insert(entries, { epoch = tonumber(epoch) or 0, kind = kind, admin = admin, reason = reason })
        end
    end
    return entries
end

local function warnCount(target)
    local n = 0
    for _, e in ipairs(historyFor(target)) do
        if e.kind == "warn" then n = n + 1 end
    end
    return n
end

-- ---------- evidence package ----------
-- getInventory exists ONLY on InventoryContainer, not on InventoryItem
-- (bytecode). Calling it on a plain item throws a Java exception that PZ
-- dumps as a FULL stack trace even when pcall catches it, so walking a
-- normal inventory wrote hundreds of log lines per second on a live
-- server. IsInventoryContainer is the cheap test that exists on the base
-- class, and it has to come FIRST
local function bagInventory(it)
    local isBag = false
    pcall(function() isBag = it:IsInventoryContainer() == true end)
    if not isBag then return nil end
    local inv = nil
    pcall(function() inv = it:getInventory() end)
    return inv
end

local function inventoryLines(players, lines)
    local count = {}
    local order = {}
    local function collect(container, depth)
        if not container or depth > 4 then return end
        local items = container:getItems()
        for i = 0, items:size() - 1 do
            local it = items:get(i)
            local full = it:getFullType()
            if not count[full] then
                count[full] = 0
                table.insert(order, { full = full, name = it:getDisplayName() })
            end
            count[full] = count[full] + 1
            local inner = bagInventory(it)
            if inner then collect(inner, depth + 1) end
        end
    end
    pcall(function() collect(players:getInventory(), 1) end)
    table.insert(lines, "Inventory (" .. #order .. " types):")
    for i = 1, math.min(#order, 400) do
        local e = order[i]
        table.insert(lines, "  " .. e.full .. " x" .. count[e.full] .. " (" .. tostring(e.name) .. ")")
    end
    if #order > 400 then
        table.insert(lines, "  ... more types truncated")
    end
end

local function evidencePackage(targetName, targetPlayer, reason, shot)
    local lines = {}
    table.insert(lines, "Reason: " .. (reason ~= "" and reason or "none given"))
    if targetPlayer then
        pcall(function()
            table.insert(lines, string.format("Position: %d, %d, %d",
                math.floor(targetPlayer:getX()), math.floor(targetPlayer:getY()), math.floor(targetPlayer:getZ())))
            table.insert(lines, "OnlineID: " .. tostring(targetPlayer:getOnlineID())
                .. "  SteamID: " .. tostring(targetPlayer:getSteamID())
                .. "  Survived: " .. string.format("%.1f", targetPlayer:getHoursSurvived()) .. " h")
        end)
        local info = AegisLog.sessionInfo and AegisLog.sessionInfo(targetName)
        if info and info.since then
            table.insert(lines, "Session since: " .. AegisShared.timestampReadable(info.since))
        end
        inventoryLines(targetPlayer, lines)
    else
        table.insert(lines, "Target was offline at the time of the action, no position/inventory snapshot.")
    end
    local history = historyFor(targetName)
    table.insert(lines, "Prior incidents: " .. #history)
    for i = math.max(1, #history - 9), #history do
        local e = history[i]
        table.insert(lines, "  " .. AegisShared.timestampReadable(e.epoch) .. "  " .. e.kind
            .. " by " .. tostring(e.admin) .. (e.reason ~= "" and (": " .. e.reason) or ""))
    end
    if shot then
        table.insert(lines, "Screenshot: " .. shot .. " (in the admin's Screenshots folder)")
    end
    return table.concat(lines, "\n")
end

-- ---------- enforcement ----------
local function findOnline(username)
    local players = getOnlinePlayers()
    if players then
        for i = 0, players:size() - 1 do
            local p = players:get(i)
            if p and p:getUsername() == username then return p end
        end
    end
    -- solo: the local player is the whole server
    if not isServer() then
        local p = getPlayer()
        if p and p:getUsername() == username then return p end
    end
    return nil
end

-- reply to one client: over the network in MP, in solo directly to the
-- OnServerCommand listeners of the same process
local function toClient(player, command, args)
    if isServer() then
        sendServerCommand(player, AegisShared.MODULE, command, args)
    else
        triggerEvent("OnServerCommand", AegisShared.MODULE, command, args)
    end
end

-- the target client disconnects itself, the only kick path without vanilla rights
local function forceDisconnect(targetPlayer, reason)
    if not targetPlayer then return end
    sendServerCommand(targetPlayer, AegisShared.MODULE, "forceDisconnect", { reason = reason or "" })
end

-- capability read on the stable registry role resolved from the access
-- level (see AegisShared.levelIsAdmin for why neither the raw level
-- string nor the per player role wrapper can be trusted)
local function vanillaCan(player, capName)
    local ok, res = pcall(function()
        local levelOk, level = pcall(function()
            return tostring(player:getAccessLevel() or ""):lower()
        end)
        if levelOk then
            local role = AegisShared.roleForLevel(level)
            if role then
                local capOk, has = pcall(function()
                    local cap = Capability[capName]
                    if cap == nil then return role:hasAdminTool() == true end
                    return role:hasCapability(cap) == true
                end)
                if capOk then return has end
            end
            return AegisShared.levelIsAdmin(level)
        end
        local role = player:getRole()
        return role and role:hasCapability(Capability[capName]) or false
    end)
    return ok and res == true
end

-- remaining seconds instead of absolute time, against clock skew between server and client
local function muteListForSync()
    local now = AegisShared.realTime()
    local list = {}
    for user, e in pairs(muteList()) do
        if isActive(e, now) then
            table.insert(list, { user = user, remaining = e.expiry == 0 and 0 or (e.expiry - now) })
        end
    end
    return list
end

-- push mute state to everyone: deliberately the broadcast form, every client
-- needs the list; only call on a real change (guard/muteSet), never on
-- request of a single client (see muteReq)
local function muteBroadcast()
    if isServer() then
        sendServerCommand(AegisShared.MODULE, "muteSync", { list = muteListForSync() })
    else
        triggerEvent("OnServerCommand", AegisShared.MODULE, "muteSync", { list = muteListForSync() })
    end
end

-- ---------- guard: enforce suspensions, clear expired entries ----------
-- also runs in solo: expired mutes must leave the file, the forced
-- disconnect is a no-op there anyway
local function guard()
    local now = AegisShared.realTime()

    local players = getOnlinePlayers()
    if players then
        for i = 0, players:size() - 1 do
            local p = players:get(i)
            local e = p and banList()[p:getUsername()]
            if isActive(e, now) then
                forceDisconnect(p, e.reason or "")
            end
        end
    end

    local changed = false
    for user, e in pairs(banList()) do
        if not isActive(e, now) then
            banList()[user] = nil
            changed = true
        end
    end
    if changed then saveList(BANS, bans) end

    changed = false
    for user, e in pairs(muteList()) do
        if not isActive(e, now) then
            muteList()[user] = nil
            changed = true
        end
    end
    if changed then
        saveList(MUTES, mutes)
        muteBroadcast()
    end
end

Events.EveryOneMinute.Add(guard)

-- ---------- commands ----------
local function deny(player, area)
    toClient(player, "denied", { area = area })
end

local function cleanReason(reason)
    -- strip quotes: the reason goes unchecked into a quoted slash command
    -- token, a " inside would end the token early
    reason = tostring(reason or ""):gsub("%c", " "):gsub("[|\"]", " ")
    if #reason > MAX_REASON then reason = reason:sub(1, MAX_REASON) end
    return reason
end

local function targetOk(target)
    return type(target) == "string" and target ~= "" and #target <= 48 and not target:find("[%c|\"]")
end

local Commands = {}

local AREA_BY_KIND = { kick = "Kicks", ban = "Bans", tempban = "Bans", warn = "Warnings" }

Commands.modAction = function(player, args)
    if not AegisRoles.canArea(player, "players") then deny(player, "players") return end
    if not args or not AREA_BY_KIND[args.kind] or not targetOk(args.target) then return end
    local kind = args.kind
    local target = args.target
    local admin = player:getUsername()
    -- acting on yourself stays locked; only the solo workshop may warn
    -- itself for testing (there is no other target there)
    if target == admin and (isServer() or kind ~= "warn") then return end
    local reason = cleanReason(args.reason)
    if (kind == "ban" or kind == "tempban") and reason == "" then return end
    local now = AegisShared.realTime()
    local targetPlayer = findOnline(target)

    -- save evidence while the target is still connected
    local shot = nil
    if kind ~= "warn" then
        shot = "Aegis_" .. kind .. "_" .. AegisShared.sanitizeName(target) .. "_" .. AegisShared.timestamp(now) .. ".png"
    end
    AegisLog.write(AREA_BY_KIND[kind], admin, target, evidencePackage(target, targetPlayer, reason, shot))
    historyAppend(kind, target, admin, reason)

    local command = nil
    if kind == "warn" then
        if targetPlayer then
            toClient(targetPlayer, "warning", {
                reason = reason, count = warnCount(target),
            })
        end
    elseif kind == "kick" then
        if vanillaCan(player, "KickUser") then
            command = "/kickuser \"" .. target .. "\""
        else
            forceDisconnect(targetPlayer, reason)
        end
    elseif kind == "ban" then
        if vanillaCan(player, "BanUnbanUser") then
            -- the reason must be quoted, otherwise the vanilla tokenizer
            -- splits it at the first space and the ban command matches no
            -- argument variant anymore (verified: BanUserCommand regex)
            command = "/banuser \"" .. target .. "\" -r \"" .. (reason ~= "" and reason or "Aegis") .. "\""
        else
            -- without the vanilla right, fall back to an unlimited Aegis suspension
            banList()[target] = { expiry = 0, reason = reason, admin = admin }
            saveList(BANS, bans)
            forceDisconnect(targetPlayer, reason)
        end
    elseif kind == "tempban" then
        local hours = math.max(1, math.min(24 * 90, math.floor(tonumber(args.hours) or 24)))
        banList()[target] = { expiry = now + hours * 3600, reason = reason, admin = admin }
        saveList(BANS, bans)
        forceDisconnect(targetPlayer, reason)
    end

    -- enforcement and evidence screenshot run on the admin client
    toClient(player, "enforcement", {
        kind = kind, target = target, reason = reason, command = command, shot = shot,
    })
end

-- Aegis suspension list lookup for the unban button (it used to be
-- active even against unbanned players). Vanilla
-- bans are already visible client side via getUsers()/NetworkUser:getRole()=="banned",
-- ONLY the Aegis list (fallback ban without vanilla right, tempban)
-- needs this server round trip
Commands.banStatus = function(player, args)
    if not AegisRoles.canArea(player, "players") then deny(player, "players") return end
    if not args or not targetOk(args.target) then return end
    local target = args.target
    local banned = isActive(banList()[target], AegisShared.realTime())
    toClient(player, "banStatus", { target = target, banned = banned })
end

-- counterpart to ban/tempban: ALWAYS clears the Aegis suspension list
-- (covers both the fallback ban without vanilla right and tempbans) and
-- additionally relays /unbanuser if the admin has the vanilla ban right,
-- so the ban is lifted no matter which of the two paths created it
Commands.unban = function(player, args)
    if not AegisRoles.canArea(player, "players") then deny(player, "players") return end
    if not args or not targetOk(args.target) then return end
    local target = args.target
    local admin = player:getUsername()
    local reason = cleanReason(args.reason)

    if banList()[target] then
        banList()[target] = nil
        saveList(BANS, bans)
    end

    local command = nil
    if vanillaCan(player, "BanUnbanUser") then
        command = "/unbanuser \"" .. target .. "\""
    end

    AegisLog.write("Bans", admin, target, "Unbanned" .. (reason ~= "" and ("\nReason: " .. reason) or ""))
    historyAppend("unban", target, admin, reason)

    toClient(player, "enforcement", { kind = "unban", target = target, reason = reason, command = command })
end

Commands.muteSet = function(player, args)
    if not AegisRoles.canArea(player, "players") then deny(player, "players") return end
    if not args or not targetOk(args.target) then return end
    local target = args.target
    local admin = player:getUsername()
    local reason = cleanReason(args.reason)
    local minutes = math.floor(tonumber(args.minutes) or 0)
    local now = AegisShared.realTime()

    if minutes <= 0 then
        muteList()[target] = nil
        AegisLog.write("ChatModeration", admin, target, "Mute lifted")
    else
        minutes = math.min(minutes, 60 * 24 * 7)
        muteList()[target] = { expiry = now + minutes * 60, reason = reason, admin = admin }
        AegisLog.write("ChatModeration", admin, target,
            "Muted for " .. minutes .. " min" .. (reason ~= "" and ("\nReason: " .. reason) or ""))
        historyAppend("mute", target, admin, reason)
    end
    saveList(MUTES, mutes)
    muteBroadcast()
    toClient(player, "enforcement", { kind = "mute", target = target, reason = reason })
end

-- reply to the requester instead of broadcasting, otherwise a client can
-- force the server into broadcasts to everyone else by spamming
local lastMuteReq = {}

Commands.muteReq = function(player, args)
    local name = player:getUsername()
    local now = AegisShared.realTime()
    if lastMuteReq[name] and now - lastMuteReq[name] < 2 then return end
    lastMuteReq[name] = now
    toClient(player, "muteSync", { list = muteListForSync() })
end

-- note version = write time, stored as header line "AEGIS_V<epoch>" in the
-- text file. A later save can tell whether another admin changed the note
-- in the meantime (reading only the first line is enough for the check,
-- no full file pass needed)
local function noteVersion(target)
    local lines = AegisStore.readLines(targetFile(NOTES, target), 1) or {}
    local v = lines[1] and lines[1]:match("^AEGIS_V(%d+)$")
    return tonumber(v) or 0
end

Commands.noteGet = function(player, args)
    if not AegisRoles.canArea(player, "players") then deny(player, "players") return end
    if not args or not targetOk(args.target) then return end
    local lines = AegisStore.readLines(targetFile(NOTES, args.target), 201) or {}
    local version = 0
    if lines[1] and lines[1]:match("^AEGIS_V%d+$") then
        version = tonumber(lines[1]:match("^AEGIS_V(%d+)$"))
        table.remove(lines, 1)
    end
    toClient(player, "noteData", { target = args.target, lines = lines, version = version })
end

Commands.noteSet = function(player, args)
    if not AegisRoles.canArea(player, "players") then deny(player, "players") return end
    if not args or not targetOk(args.target) or type(args.text) ~= "string" then return end
    -- prevent last write wins: if the version sent along at load time
    -- differs from the current one, another admin saved in the meantime,
    -- then reject rather than silently swallowing their change
    local currentVersion = noteVersion(args.target)
    if (tonumber(args.version) or 0) ~= currentVersion then
        toClient(player, "noteConflict", { target = args.target })
        return
    end
    local text = args.text
    if #text > 4000 then text = text:sub(1, 4000) end
    local newVersion = math.max(AegisShared.realTime(), currentVersion + 1)
    AegisStore.write(targetFile(NOTES, args.target), "AEGIS_V" .. newVersion .. "\n" .. text)
    -- only the event, never the content: notes stay private
    AegisLog.write("Actions", player:getUsername(), args.target, "Note updated")
    -- mirror gen back unchanged: the client uses it to tell whether the
    -- reply still belongs to the currently open note window, see AegisNote.show
    toClient(player, "noteSaved", { target = args.target, version = newVersion, gen = args.gen })
end

-- cart: one grant, one log entry, one sync per entry
Commands.giveItems = function(player, args)
    if not isServer() then return end
    if not AegisRoles.canArea(player, "items") then deny(player, "items") return end
    if not vanillaCan(player, "AddItem") then
        sendServerCommand(player, AegisShared.MODULE, "denied", { area = "items", reason = "capability" })
        return
    end
    if not args or not targetOk(args.target) or type(args.items) ~= "table" then return end
    local targetPlayer = findOnline(args.target)
    if not targetPlayer or targetPlayer:isDead() then return end

    local admin = player:getUsername()
    local total = 0
    local granted = {}
    local processed = 0
    for _, pos in pairs(args.items) do
        processed = processed + 1
        if processed > CART_MAX_ENTRIES then break end
        if type(pos) == "table" and type(pos.fullType) == "string" then
            local count = math.max(1, math.min(CART_PER_ENTRY, math.floor(tonumber(pos.count) or 1)))
            if total + count > CART_TOTAL then break end
            local script = getScriptManager():FindItem(pos.fullType)
            local typeOk = script ~= nil
            if typeOk then
                -- exclude corpses: script:getTypeString() does not exist in
                -- B42 (only on item instances, not on the script), the name
                -- is the right way (e.g. "CorpseAnimal")
                local name = script:getName()
                if name and name:find("Corpse") then typeOk = false end
            end
            if typeOk then
                local ok = pcall(function()
                    local items = targetPlayer:getInventory():AddItems(pos.fullType, count)
                    sendAddItemsToContainer(targetPlayer:getInventory(), items)
                end)
                if ok then
                    total = total + count
                    table.insert(granted, pos.fullType .. " x" .. count)
                end
            end
        end
    end

    if #granted > 0 then
        AegisLog.write("Actions", admin, args.target,
            "Cart grant (" .. total .. " items):\n  " .. table.concat(granted, "\n  "))
    end
    toClient(player, "giveItems", { ok = #granted > 0, target = args.target, total = total })
end

-- export for all other server files: every own OnClientCommand dispatcher
-- must check this itself, B42 cannot filter packets by the Aegis
-- suspension, otherwise a suspended sender keeps full authority in every
-- Aegis area except this one as long as his client ignores the forced
-- disconnect
function AegisModeration.isSuspended(player)
    return player ~= nil and isActive(banList()[player:getUsername()], AegisShared.realTime())
end

local function onClientCommand(module, command, player, args)
    if module ~= AegisShared.MODULE then return end
    if AegisModeration.isSuspended(player) then return end
    if Commands[command] then Commands[command](player, args) end
end

Events.OnClientCommand.Add(onClientCommand)
