AegisShared = AegisShared or {}

-- network module name, client and server use the same constant
AegisShared.MODULE = "AegisAdmin"

-- area permissions: one id per Aegis page, controls visibility and use
AegisShared.AREAS = {
    "dashboard", "powers", "players", "items", "vehicles", "animals",
    "world", "zones", "horde", "server", "options", "factions", "tools",
    "kits", "sandbox", "logs", "roles",
}

-- Areas split off a wider one later on. A role saved before the split
-- carries no key for the new area, and a missing key counts as denied,
-- so the page would vanish for every existing role without anyone
-- touching it. The server hands the new area once to every role that
-- holds the parent (migration in Aegis_Roles); naming the relationship
-- here keeps both sides from drifting apart
AegisShared.AREA_PARENT = { options = "server" }
-- bump this whenever AREA_PARENT gains an entry, the marker line in
-- rollen.txt records which migrations already ran
AegisShared.AREA_MIGRATION = 1

-- log areas below Aegis/Log/
AegisShared.LOG_AREAS = {
    "Bans", "Kicks", "Warnings", "ChatModeration", "Actions", "AdminSessions", "PlayerSessions", "Deaths",
}

-- zone backup retention: 14 days active, then 30 days archive, then gone
AegisShared.RETENTION = { activeDays = 14, archiveDays = 30 }

function AegisShared.isSoloSP()
    return not isClient() and not isServer()
end

-- ---------- admin status from the access level ----------
-- B42 access levels ARE role names, including custom ones ("Owner") and
-- the default "user" every normal player carries (a name
-- blacklist that only excluded none treated every player as staff). The
-- verdict therefore comes from the role REGISTRY: getRoles() objects are
-- stable engine singletons and Role.hasAdminTool is plain capability
-- data on them, unlike the flaky per player role wrapper.
-- vanilla names read from zombie/characters/Roles.class: the actual level
-- string is "priority", not "priorityuser" (that was the getter's name,
-- not the role's), which meant it never matched here and fell through to
-- the registry-unreadable fallback below, so a Priority player saw the
-- empty panel. Kept both spellings, one is free
local PLAIN_LEVELS = { [""] = true, none = true, user = true, banned = true, priority = true, priorityuser = true }
-- the four vanilla staff levels, all of them carry AdminTool (measured on
-- the B42 role registry). They pass without asking the registry at all, so
-- a real admin still gets in when the registry cannot be read
local STAFF_LEVELS = { admin = true, moderator = true, gm = true, observer = true }

-- second return value says whether the registry could be READ at all. That
-- is the difference between "this level is provably not a staff role" and
-- "we could not find out", and the two must not share a verdict
function AegisShared.roleForLevel(level)
    local found, readable = nil, false
    pcall(function()
        local list = getRoles()
        if not list then return end
        local n = list:size()
        if n <= 0 then return end
        readable = true
        for i = 0, n - 1 do
            local role = list:get(i)
            if role and tostring(role:getName()):lower() == level then
                found = role
                return
            end
        end
    end)
    return found, readable
end

-- the verdict is asked every frame (HUD button, window update), the
-- registry scan must not run that often; role edits are rare, a short
-- memo is invisible to the admin
local levelMemo = {}

function AegisShared.levelIsAdmin(level)
    level = tostring(level or ""):lower()
    if PLAIN_LEVELS[level] then return false end
    if STAFF_LEVELS[level] then return true end
    local now = AegisShared.realTime()
    local m = levelMemo[level]
    if m and now - m.at < 5 then return m.verdict end

    local role, readable = AegisShared.roleForLevel(level)
    local verdict
    if role then
        -- the honest answer: this level IS a role, ask it
        local ok, res = pcall(function() return role:hasAdminTool() == true end)
        verdict = (ok and res) == true
    elseif readable then
        -- The registry was readable and this level is not a role in it, so
        -- it is a rank or head tag name and nothing more. This used to
        -- default to STAFF, and since an admin without an assigned Aegis
        -- role gets full access (Aegis roles only narrow, never grant),
        -- every custom rank on a server silently held the whole panel,
        -- server side included (a "Veteran" rank without
        -- the admin tool had everything). Named is not the same as staff
        verdict = false
    else
        -- registry not readable at all: keep the old way out, locking real
        -- admins out is the worse failure. The four vanilla staff levels
        -- above never even reach this branch
        verdict = true
    end

    -- one line per verdict change, not per call: this is the question that
    -- cost us two live incidents, it must be answerable from the log
    if not m or m.verdict ~= verdict then
        print("[Aegis] access level '" .. level .. "' counts as "
            .. (verdict and "staff" or "player") .. " ("
            .. (role and "role found" or (readable and "not a role in the registry" or "registry unreadable"))
            .. ")")
    end
    levelMemo[level] = { at = now, verdict = verdict }
    return verdict
end

-- feature switches from the AegisEvents sandbox page (workshop request):
-- readable on both sides, a missing option means on so existing servers
-- keep what they had
function AegisShared.featureOn(name)
    local on = true
    local v = SandboxVars and SandboxVars.AegisEvents and SandboxVars.AegisEvents[name]
    if v ~= nil then on = v == true end
    return on
end

-- epoch seconds of the real clock, independent of game time
function AegisShared.realTime()
    local t = getTimestamp()
    if type(t) == "number" and t > 0 then return t end
    return 0
end

-- calendar parts without the os library, days-since-epoch per Howard Hinnant
local function utcParts(epoch)
    local days = math.floor(epoch / 86400)
    local remaining = epoch - days * 86400
    local z = days + 719468
    local era = math.floor(z / 146097)
    local doe = z - era * 146097
    local yoe = math.floor((doe - math.floor(doe / 1460) + math.floor(doe / 36524) - math.floor(doe / 146096)) / 365)
    local y = yoe + era * 400
    local doy = doe - (365 * yoe + math.floor(yoe / 4) - math.floor(yoe / 100))
    local mp = math.floor((5 * doy + 2) / 153)
    local d = doy - math.floor((153 * mp + 2) / 5) + 1
    local m = mp < 10 and mp + 3 or mp - 9
    if m <= 2 then y = y + 1 end
    return {
        year = y, month = m, day = d,
        hour = math.floor(remaining / 3600),
        min = math.floor((remaining % 3600) / 60),
        sec = remaining % 60,
    }
end

-- os.date is nailed to UTC in the game's Kahlua build (the zone field is
-- a private static final), but getHourMinute() runs through
-- Calendar.getInstance() and carries the machine's local clock. The
-- difference between that and the UTC clock is the zone offset, measured
-- in quarter hours so second-level jitter between the two reads drops out
local zoneOffset, zoneMeasured
local function offsetMinutes()
    local now = AegisShared.realTime()
    if zoneOffset and zoneMeasured and now - zoneMeasured < 600 then
        return zoneOffset
    end
    local off = 0
    local ok, hm = pcall(getHourMinute)
    if ok and type(hm) == "string" then
        local h, m = hm:match("^(%d+):(%d+)$")
        if h then
            local u = utcParts(now)
            local diff = (tonumber(h) * 60 + tonumber(m)) - (u.hour * 60 + u.min)
            if diff > 720 then diff = diff - 1440 end
            if diff <= -720 then diff = diff + 1440 end
            off = math.floor(diff / 15 + 0.5) * 15
        end
    end
    zoneOffset, zoneMeasured = off, now
    return off
end

function AegisShared.dateParts(epoch)
    return utcParts(epoch + offsetMinutes() * 60)
end

function AegisShared.timestamp(epoch)
    local t = AegisShared.dateParts(epoch)
    return string.format("%04d-%02d-%02d_%02d-%02d-%02d", t.year, t.month, t.day, t.hour, t.min, t.sec)
end

function AegisShared.dateShort(epoch)
    local t = AegisShared.dateParts(epoch)
    return string.format("%04d-%02d-%02d", t.year, t.month, t.day)
end

function AegisShared.timestampReadable(epoch)
    local t = AegisShared.dateParts(epoch)
    return string.format("%02d.%02d.%04d %02d:%02d", t.day, t.month, t.year, t.hour, t.min)
end

-- time of day only, for lines inside a per-day file
function AegisShared.timeShort(epoch)
    local t = AegisShared.dateParts(epoch)
    return string.format("%02d:%02d:%02d", t.hour, t.min, t.sec)
end

function AegisShared.ageDays(epoch)
    local now = AegisShared.realTime()
    if now <= 0 or not epoch or epoch <= 0 then return 0 end
    return (now - epoch) / 86400
end

-- defuse names for file paths and manifest lines: Windows forbidden chars,
-- control chars, pipe as field separator and dot runs are stripped
function AegisShared.sanitizeName(s)
    s = tostring(s or "")
    s = s:gsub("[%c<>:\"/\\|%?%*]", "_")
    s = s:gsub("%.%.+", "_")
    s = s:gsub("^[%. ]+", ""):gsub("[%. ]+$", "")
    if #s > 48 then s = s:sub(1, 48) end
    if s == "" then s = "Unbekannt" end
    return s
end

-- converts the UI rotation angle (placement footprint: 0 deg = north, grows
-- clockwise) into the angle car:setAngles() needs for the same world
-- direction. Verified from the B42 bytecode of addVehicleDebug: the engine
-- rotates a freshly spawned vehicle towards direction D via
-- rotation = D:toAngle() + 180 deg, and D:toAngle() = ordinal(D)*45 deg runs
-- COUNTER-clockwise (N=0 deg,NW=45 deg,W=90 deg,SW=135 deg,S=180 deg,SE=225 deg,E=270 deg,NE=315 deg).
-- The placement footprint rotates clockwise, so the UI angle's sign must be
-- flipped, plus the +180 deg offset. Without this conversion the vehicle spawned
-- facing a different direction than the footprint showed.
function AegisShared.worldAngle(uiAngle)
    return (180 - (tonumber(uiAngle) or 0)) % 360
end

-- admin-spawned vehicles come factory fresh: all random loot from glove box,
-- seats and trunk is removed, only the key stays
function AegisShared.emptyVehicle(car)
    if not car then return end
    pcall(function()
        for i = 0, car:getPartCount() - 1 do
            local part = car:getPartByIndex(i)
            local inv = part and part:getItemContainer()
            if inv then inv:removeAllItems() end
        end
    end)
end

-- delivery state after spawn: loot out, all doors and the trunk unlocked
-- (sandbox LockedCar otherwise locks admin spawns too), key into the glove
-- box. Without a glove box (trailers, wrecks) it goes into the recipient's
-- inventory; vehicles without seats need none at all. sendAddItemToContainer
-- is the vanilla sync pattern from Commands.getKey and a no-op in solo.
function AegisShared.vehicleHandover(car, recipient)
    if not car then return end
    AegisShared.emptyVehicle(car)
    pcall(function()
        for i = 0, car:getPartCount() - 1 do
            local part = car:getPartByIndex(i)
            local door = part and part:getDoor()
            if door then
                door:setLocked(false)
                door:setLockBroken(false)
            end
        end
    end)
    pcall(function() car:setTrunkLocked(false) end)

    -- each step guarded separately: a failure at door/script must not swallow
    -- the key, a failure at the glove box must not block the inventory
    -- fallback (a single big pcall would have spawned no key at all on any
    -- error)
    local skipKey = false
    pcall(function()
        local script = car:getScript()
        if script and (script:getPassengerCount() == 0 or script:neverSpawnKey()) then
            skipKey = true
        end
    end)
    if skipKey then return end

    local key = nil
    pcall(function() key = car:createVehicleKey() end)
    if not key then return end

    local inv = nil
    pcall(function()
        local part = car:getPartById("GloveBox")
        if part then inv = part:getItemContainer() end
    end)
    if not inv and recipient then
        pcall(function() inv = recipient:getInventory() end)
    end
    if not inv then return end

    pcall(function() inv:AddItem(key) end)
    pcall(function() sendAddItemToContainer(inv, key) end)
end

-- full body reset, same approach as the vanilla health cheat (healthFullBody)
function AegisShared.fullHeal(player)
    if not player then return end
    local bodyParts = player:getBodyDamage():getBodyParts()
    for i = 1, bodyParts:size() do
        local part = bodyParts:get(i - 1)
        part:RestoreToFullHealth()
        -- clear bite and wound infection flags too, RestoreToFullHealth
        -- leaves them set (vanilla cure precedent: ClientCommands.lua
        -- "bite" action clears exactly these three)
        part:SetBitten(false)
        part:SetInfected(false)
        part:SetFakeInfected(false)
        part:setInfectedWound(false)
        if part:getStiffness() > 0 then
            part:setStiffness(0)
            player:getFitness():removeStiffnessValue(BodyPartType.ToString(part:getType()))
        end
    end
    -- the systemic Knox infection is what actually kills: without this a
    -- bitten player kept zombifying after a full heal
    local bd = player:getBodyDamage()
    bd:setInfected(false)
    bd:setInfectionTime(-1)
    bd:setInfectionMortalityDuration(-1)
end

-- vegetation detection like the vanilla sledgehammer guard (model:
-- server/BuildingObjects/ISDestroyCursor.lua:canDestroy, which has a "must
-- not be destroyed" list). Narrowed here to the truly vegetation related
-- criteria, WITHOUT water (blends_natural_02), curbs, ads, street lamps and
-- trash: those are only on the vanilla list because the sledgehammer must
-- not break them either, but they are no plants
function AegisShared.isVegetation(obj)
    if not obj then return false end
    local ok, res = pcall(function()
        if instanceof(obj, "IsoTree") then return true end
        local props = obj:getProperties()
        if props and props:has(IsoFlagType.vegitation) then return true end
        local sprite = obj:getSprite()
        local name = sprite and sprite:getName()
        if not name then return false end
        if luautils.stringStarts(name, "blends_grassoverlays") then return true end
        if luautils.stringStarts(name, "d_") then return true end
        if luautils.stringStarts(name, "e_") then return true end
        if luautils.stringStarts(name, "f_") then return true end
        if luautils.stringStarts(name, "vegetation_")
            and not (luautils.stringStarts(name, "vegetation_indoor") or luautils.stringStarts(name, "vegetation_drying")) then
            return true
        end
        return false
    end)
    return ok and res == true
end

