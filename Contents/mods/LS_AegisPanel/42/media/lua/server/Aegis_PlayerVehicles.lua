-- Own vehicles for the player panel: a player registers cars he holds
-- the key for, the panel lists them with the last known position and
-- the client navi guides him back to a lost one. Ledger file with the
-- incomplete read guard from Aegis_PlayerStats, replies go only to the
-- sender and every command is gated on the panel unlock.
if isClient() then return end

require "Aegis_Store"
require "Aegis_Roles"
require "Aegis_Log"
require "Aegis_Moderation"

local MODULE = "AegisPlayer"
local FILE = AegisStore.ROOT .. "/Player/vehicles.txt"
-- how many vehicles a player may remember. Sandbox option,
-- a missing option keeps the old five so existing servers do not change
-- behaviour on update. Read on every call, not cached: an admin can
-- change it live on the sandbox page
local function maxVehicles()
    local n = nil
    local v = SandboxVars and SandboxVars.AegisEvents
        and SandboxVars.AegisEvents.PlayerVehicles
    if v ~= nil then n = math.floor(tonumber(v) or 0) end
    if not n or n < 0 then n = 5 end
    return math.min(n, 20)
end
local SAVE_RANGE = 10
-- how long a client snapshot counts as current, the panel greys out
-- older numbers with the stale note
local STATE_FRESH = 120
-- one accepted state push per user and vehicle, a bit under the 30s the
-- client keeps between pushes so a late packet is not dropped
local STATE_GATE = 25

-- reply to the caller: over the network in MP, in solo directly to the
-- OnServerCommand listeners of the same process
local function toClient(player, command, args)
    if isServer() then
        sendServerCommand(player, MODULE, command, args)
    else
        triggerEvent("OnServerCommand", MODULE, command, args)
    end
end

local function nameOk(name)
    return type(name) == "string" and name ~= "" and #name <= 48
        and not name:find("[%c|]")
end

-- separator safe text for the pipe ledger, never cut through UTF-8
local function sanitize(v, max)
    local s = tostring(v or ""):gsub("[%c|]", " ")
    if #s > max then
        s = s:sub(1, max)
        while #s > 0 do
            local b = s:byte(#s)
            if b >= 128 and b < 192 then
                s = s:sub(1, #s - 1)
            else
                if b >= 192 then s = s:sub(1, #s - 1) end
                break
            end
        end
    end
    return s
end

-- a client sending NaN or inf would sail through every comparison
local function finiteInt(v)
    v = tonumber(v)
    if not v or v ~= v or v == math.huge or v == -math.huge then return nil end
    return math.floor(v)
end

-- percent from a client, nil when absent or not a real number
local function pct(v)
    v = tonumber(v)
    if not v or v ~= v or v == math.huge or v == -math.huge then return nil end
    v = math.floor(v + 0.5)
    if v < 0 then return 0 end
    if v > 100 then return 100 end
    return v
end

-- vehState carries no generic gate: it needs a burst of up to five
-- pushes when a page opens, the real limit is one push per user and
-- vehicle (STATE_GATE) and only for vehicles already in his ledger
-- vehState carries its own per vehicle gate (STATE_GATE), vehStateAny is
-- the cheap per user gate in front of the ledger lookup
local THROTTLE = { vehSave = 3, vehList = 5, vehForget = 3, vehState = 0, vehStateAny = 2 }
local lastCall = {}

local function throttled(name, command)
    local limit = THROTTLE[command] or 2
    if limit <= 0 then return false end
    local now = AegisShared.realTime()
    local key = name .. ":" .. command
    if lastCall[key] and now - lastCall[key] < limit then return true end
    lastCall[key] = now
    return false
end

-- last accepted state push per user and vehicle, memory only
local lastState = {}

-- nil unless the roles file unlocks the panel for this user
local function panelFor(name)
    if not AegisRoles.playerPanelFor then return nil end
    local ok, pp = pcall(AegisRoles.playerPanelFor, name)
    if ok and type(pp) == "table" then return pp end
    return nil
end

-- solo has no server roles, the panel is always on there
local function unlocked(name)
    if not isServer() then return true end
    return panelFor(name) ~= nil
end

-- ---------- ledger ----------
-- line: V|user|vehId|script|name|x|y|epoch|cond|fuel|batt|engine|key
-- the four state fields are a later addition and stay optional: old
-- lines load without them, absent values travel as empty fields. They
-- are measured by the client and only ever stored here, see vehState.
-- Their age (stateAt) stays in memory, after a restart every snapshot
-- counts as stale until a client reports again.
-- key is the newest column and the cure for the id problem: the net id
-- dies with every server restart, so entries went husk, no position,
-- no bars. Saving now stamps the key into the vehicle's
-- modData, and refreshPositions heals the id whenever the stamp is
-- found again. Lines without a key are from before and stay husks once
-- their id died, there is nothing left to recognize them by
local byUser = {}
local loaded = false
local incomplete = false
-- running number for fresh vehicle stamps, uniqueness comes from the
-- realTime suffix riding along
local vehKeySeq = 0

local function load()
    if loaded then return end
    loaded = true
    byUser = {}
    local lines, truncated = AegisStore.readLines(FILE, 20000)
    if lines == nil then
        -- read error: continue empty, retry on next access, and never
        -- rewrite the file from this state
        loaded = false
        incomplete = true
        return
    end
    incomplete = truncated == true
    for _, line in ipairs(lines) do
        local parts = {}
        for field in string.gmatch(line .. "|", "([^|]*)|") do
            table.insert(parts, field)
        end
        local id = tonumber(parts[3])
        if parts[1] == "V" and nameOk(parts[2]) and id then
            local list = byUser[parts[2]] or {}
            byUser[parts[2]] = list
            -- LOADING never drops rows: lowering the option would silently
            -- delete vehicles people already own. The limit only guards
            -- NEW entries (see vehSave), existing ones live until released
            table.insert(list, {
                id = math.floor(id),
                script = parts[4] or "",
                name = parts[5] or "",
                x = math.floor(tonumber(parts[6]) or 0),
                y = math.floor(tonumber(parts[7]) or 0),
                epoch = tonumber(parts[8]) or 0,
                cond = tonumber(parts[9]),
                fuel = tonumber(parts[10]),
                batt = tonumber(parts[11]),
                engine = tonumber(parts[12]),
                key = (parts[13] ~= nil and parts[13] ~= "") and parts[13] or nil,
            })
        end
    end
end

local function save()
    if incomplete then
        print("[Aegis] Player vehicles write-protected, change not saved")
        return
    end
    local lines = {}
    for user, list in pairs(byUser) do
        for _, e in ipairs(list) do
            table.insert(lines, table.concat({
                "V", user, tostring(e.id), e.script, e.name,
                tostring(e.x), tostring(e.y), tostring(e.epoch),
                e.cond and tostring(e.cond) or "",
                e.fuel and tostring(e.fuel) or "",
                e.batt and tostring(e.batt) or "",
                e.engine and tostring(e.engine) or "",
                e.key or "",
            }, "|"))
        end
    end
    table.sort(lines)
    local content = table.concat(lines, "\n")
    if #lines > 0 then content = content .. "\n" end
    AegisStore.write(FILE, content)
end

-- Condition, tank, battery and engine are NOT read here. The server side
-- of a B42 session sees the parts without their installed items: a mint
-- van reported condition 15 and engine 0 while the vanilla mechanics
-- window on the client showed 100 everywhere, and the gas tank reports
-- capacity 0 without its tank item (the script has no capacity line, the
-- engine falls back to the item), so tank and battery came out empty.
-- The numbers now arrive from the client through vehState. No fallback
-- measurement is left standing: a wrong number that looks right is worse
-- than an empty bar

-- the vehicle wearing this stamp, out of everything the server has
-- loaded. VehicleManager.instance:getVehicles is an ArrayList on the
-- server, unlike the cell set the client sees
local function findByStamp(key)
    local found = nil
    -- some servers do not have this global at all
    if VehicleManager == nil then return nil end
    pcall(function()
        -- a Java-null instance is not caught by this pcall (bridge
        -- exception, not a Lua error), the crash reports from the
        -- community all sat right here: check in plain Lua first
        local vm = VehicleManager.instance
        if not vm then return end
        local list = vm:getVehicles()
        for i = 0, list:size() - 1 do
            local v = list:get(i)
            if v and tostring(v:getModData().aegisVehKey) == key then
                found = v
                return
            end
        end
    end)
    return found
end

-- refresh last known positions from vehicles the server still has
-- loaded; an unloaded cell simply keeps the stored spot. The file is
-- only rewritten when a coordinate really changed, a confirmed but
-- unchanged vehicle updates the timestamp in memory alone
local function refreshPositions(name)
    load()
    local list = byUser[name]
    if not list then return end
    local changed = false
    for _, e in ipairs(list) do
        local car = nil
        pcall(function() car = getVehicleById(e.id) end)
        -- the id is reused after restarts: with a stamp on file the hit
        -- has to prove itself, and a miss earns one sweep through the
        -- loaded vehicles. A healed id is written back, from then on the
        -- fast path works again for everyone including the client
        if e.key then
            local proven = false
            if car then
                pcall(function()
                    proven = tostring(car:getModData().aegisVehKey) == e.key
                end)
            end
            if not proven then car = findByStamp(e.key) end
            if car then
                local nid = nil
                pcall(function() nid = car:getId() end)
                if nid and math.floor(nid) ~= e.id then
                    print("[Aegis] Player vehicle '" .. tostring(e.name) .. "' of " .. name
                        .. ": id healed " .. tostring(e.id) .. " -> " .. tostring(math.floor(nid)))
                    e.id = math.floor(nid)
                    changed = true
                end
            end
        end
        if car then
            local x, y = nil, nil
            pcall(function()
                x = math.floor(car:getX())
                y = math.floor(car:getY())
            end)
            if x and y then
                if x ~= e.x or y ~= e.y then
                    e.x, e.y = x, y
                    changed = true
                end
                e.epoch = AegisShared.realTime()
            end
        end
    end
    if changed then save() end
end

-- fresh marks a state snapshot young enough to pass as current, it lives
-- in memory only and never enters the ledger
local function entriesFor(name)
    load()
    local now = AegisShared.realTime()
    local out = {}
    for _, e in ipairs(byUser[name] or {}) do
        table.insert(out, {
            id = e.id, key = e.key, script = e.script, name = e.name,
            x = e.x, y = e.y, epoch = e.epoch,
            cond = e.cond, fuel = e.fuel, batt = e.batt, engine = e.engine,
            fresh = e.stateAt ~= nil and (now - e.stateAt) <= STATE_FRESH,
        })
    end
    return out
end

local function pushList(player, name)
    refreshPositions(name)
    toClient(player, "vehList", { entries = entriesFor(name) })
end

-- ownership proof: the matching key in the OWN inventory, or the sender
-- himself sits in exactly this vehicle (id compare, never object
-- identity, Kahlua wrappers are not stable). isKeysInIgnition was no
-- proof at all: it is plain vehicle state, true for ANY bystander while
-- an owner drives or parks with the key inside (a
-- stranger could register foreign cars and track them forever)
local function ownsKey(player, car)
    local keyOk, hasKey = pcall(function()
        return player:getInventory():haveThisKeyId(car:getKeyId()) == true
    end)
    if keyOk and hasKey then return true end
    local seated = false
    pcall(function()
        local mine = player:getVehicle()
        seated = mine ~= nil and mine:getId() == car:getId()
    end)
    return seated
end

local Commands = {}

Commands.vehList = function(player, name, args)
    pushList(player, name)
end

Commands.vehSave = function(player, name, args)
    local id = finiteInt(args.id)
    if not id then
        toClient(player, "vehSave", { ok = false, reason = "failed" })
        return
    end
    local car = nil
    pcall(function() car = getVehicleById(id) end)
    if not car then
        toClient(player, "vehSave", { ok = false, reason = "far" })
        return
    end
    local dist2 = nil
    pcall(function()
        local dx = car:getX() - player:getX()
        local dy = car:getY() - player:getY()
        dist2 = dx * dx + dy * dy
    end)
    if not dist2 or dist2 > SAVE_RANGE * SAVE_RANGE then
        toClient(player, "vehSave", { ok = false, reason = "far" })
        return
    end
    if not ownsKey(player, car) then
        toClient(player, "vehSave", { ok = false, reason = "key" })
        return
    end
    local scriptFull, scriptName = "", ""
    pcall(function()
        local script = car:getScript()
        if script then
            scriptFull = tostring(script:getFullName() or "")
            scriptName = tostring(script:getName() or "")
        end
    end)
    local x, y = nil, nil
    pcall(function()
        x = math.floor(car:getX())
        y = math.floor(car:getY())
    end)
    if scriptFull == "" or not x or not y then
        toClient(player, "vehSave", { ok = false, reason = "failed" })
        return
    end
    -- an admin nickname wins over the script name; both travel raw, the
    -- client resolves IGUI_VehicleName<name> and falls back to the text
    local label = scriptName
    pcall(function()
        local nick = car:getModData().AegisName
        if type(nick) == "string" and nick ~= "" then label = nick end
    end)
    label = sanitize(label, 40)
    scriptFull = sanitize(scriptFull, 80)
    load()
    if incomplete then
        toClient(player, "vehSave", { ok = false, reason = "failed" })
        return
    end
    local list = byUser[name] or {}
    byUser[name] = list
    -- the stamp decides whether this vehicle is already known: a car that
    -- was stamped in an earlier session carries a dead id, matching by id
    -- alone would file it a second time
    local carKey = nil
    pcall(function()
        local s = car:getModData().aegisVehKey
        if type(s) == "string" and s ~= "" then carKey = s end
    end)
    local entry = nil
    for _, e in ipairs(list) do
        if (carKey and e.key == carKey) or e.id == id then
            entry = e
            break
        end
    end
    if not entry then
        if #list >= maxVehicles() then
            toClient(player, "vehSave", { ok = false, reason = "limit" })
            return
        end
        entry = { id = id }
        table.insert(list, entry)
    end
    -- fresh stamp for a fresh car; the id is healed either way
    if not carKey then
        vehKeySeq = vehKeySeq + 1
        carKey = "av" .. tostring(vehKeySeq) .. "-" .. tostring(AegisShared.realTime())
        pcall(function()
            car:getModData().aegisVehKey = carKey
            car:transmitModData()
        end)
    end
    entry.key = carKey
    entry.id = id
    entry.script = scriptFull
    entry.name = label
    entry.x, entry.y = x, y
    entry.epoch = AegisShared.realTime()
    -- the client measured the vehicle it is standing at and sends the
    -- numbers along, a client that sends none clears the old ones
    entry.cond, entry.fuel = pct(args.cond), pct(args.fuel)
    entry.batt, entry.engine = pct(args.batt), pct(args.engine)
    entry.stateAt = AegisShared.realTime()
    lastState[name .. ":" .. id] = entry.stateAt
    save()
    AegisLog.write("Actions", name, name,
        string.format("Vehicle saved: %s (id %d) at %d,%d", label, id, x, y))
    toClient(player, "vehSave", { ok = true, id = id })
    pushList(player, name)
end

-- client measured state for one of the sender's own vehicles. Ownership
-- is the ledger entry itself: an id the sender never registered is
-- dropped before anything is written, so a spammed id cannot even grow
-- the gate table. No reply, the client already shows what it measured
Commands.vehState = function(player, name, args)
    local id = finiteInt(args.id)
    if not id then return end
    -- coarse per user gate BEFORE the ledger lookup: the per vehicle gate
    -- below only arms for ids the sender really owns, so a foreign id
    -- would otherwise pass the expensive path on every packet. A player pushes at most one vehicle every few seconds
    if throttled(name, "vehStateAny") then return end
    local key = name .. ":" .. id
    local now = AegisShared.realTime()
    if lastState[key] and now - lastState[key] < STATE_GATE then return end
    load()
    if incomplete then return end
    local entry = nil
    for _, e in ipairs(byUser[name] or {}) do
        if e.id == id then
            entry = e
            break
        end
    end
    if not entry then return end
    lastState[key] = now
    local cond, fuel = pct(args.cond), pct(args.fuel)
    local batt, engine = pct(args.batt), pct(args.engine)
    local changed = cond ~= entry.cond or fuel ~= entry.fuel
        or batt ~= entry.batt or engine ~= entry.engine
    entry.cond, entry.fuel = cond, fuel
    entry.batt, entry.engine = batt, engine
    entry.stateAt = now
    if changed then save() end
end

Commands.vehForget = function(player, name, args)
    local id = finiteInt(args.id)
    if not id then
        toClient(player, "vehForget", { ok = false, reason = "failed" })
        return
    end
    load()
    if incomplete then
        toClient(player, "vehForget", { ok = false, reason = "failed" })
        return
    end
    local list = byUser[name]
    local at = nil
    if list then
        for i, e in ipairs(list) do
            if e.id == id then
                at = i
                break
            end
        end
    end
    if not at then
        toClient(player, "vehForget", { ok = false, reason = "failed" })
        return
    end
    local gone = table.remove(list, at)
    if #list == 0 then byUser[name] = nil end
    lastState[name .. ":" .. id] = nil
    save()
    AegisLog.write("Actions", name, name,
        string.format("Vehicle forgotten: %s (id %d)", gone.name or "?", id))
    toClient(player, "vehForget", { ok = true, id = id })
    pushList(player, name)
end

local function onClientCommand(module, command, player, args)
    if module ~= MODULE then return end
    -- suspended senders keep no authority in any Aegis area
    if AegisModeration.isSuspended(player) then return end
    local handler = Commands[command]
    if not handler then return end
    local name = player:getUsername()
    if not nameOk(name) then return end
    if not unlocked(name) then return end
    if throttled(name, command) then return end
    handler(player, name, args or {})
end

Events.OnClientCommand.Add(onClientCommand)
