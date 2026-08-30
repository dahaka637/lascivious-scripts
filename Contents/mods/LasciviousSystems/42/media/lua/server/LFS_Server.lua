if isClient() and not isCoopHost() then
    return
end

require "LFS_Shared"
require "LFS_Claims"
require "LFS_Upgrades"
require "LFS_VehicleGuard"
require "LFS_Hunter"

local FF = LasciviousFactionsSystem
local Claims = FF.Claims
local H = {}  -- internal server-side helpers namespace (keeps main chunk's local-variable count low)

-- Lua reloads are common while developing/administering a long-running server.
-- Replace our previous callback instead of accumulating another copy of every
-- gated OnTick/command handler on each reload.
function FF._replaceServerHook(event, key, callback)
    if not event then return end
    if FF[key] then event.Remove(FF[key]) end
    FF[key] = callback
    event.Add(callback)
end

require "LFS_LegacyServer"

print("[LFS] server lua loaded (isClient=" .. tostring(isClient())
    .. " isServer=" .. tostring(isServer()) .. " isCoopHost=" .. tostring(isCoopHost()) .. ")")

-- ---------------------------------------------------------------------------
-- Notifications back to a player
-- ---------------------------------------------------------------------------
local function notify(player, key, extra, extra2, requestId)
    if not player then return end
    sendServerCommand(player, FF.MODULE, "notify",
        { key = key, extra = extra, extra2 = extra2, requestId = requestId })
end

-- Multi-line report back to one player (/ff status, /ff admin war|pact list).
-- Declared HERE beside notify, not down with the other debug helpers: adminWar
-- and adminPact call it from further UP the file, where a local declared below
-- is a nil GLOBAL, not an upvalue. That is the same trap that aborted the whole
-- server file in the 1.2.1 incident -- it merely degraded to "attempt to call
-- nil" here because the calls sit inside function bodies.
local function sendReport(player, lines)
    sendServerCommand(player, FF.MODULE, "report", { lines = lines })
end

-- Real-world wall-clock epoch in milliseconds. Persists across server restarts
-- (unlike the in-game clock), which is what claim decay measures "abandoned" against.
local function nowMs()
    return Calendar.getInstance():getTimeInMillis()
end

-- Keep the factions subsystem loadable if the Shop half of the all-in-one mod
-- failed to initialise. Currency-moving operations fail closed; rounding has a
-- small finite fallback so passive bookkeeping/ticks never become an OnTick error.
local function roundShopCredits(value)
    local LS = _G.LasciviousShop
    if LS and type(LS.roundCredits) == "function" then
        local ok, rounded = pcall(LS.roundCredits, value)
        if ok and tonumber(rounded) then return rounded end
    end
    value = tonumber(value) or 0
    if value ~= value or value == math.huge or value == -math.huge then value = 0 end
    value = math.max(0, math.min(9000000000000, value))
    return math.floor(value * 100 + 0.5) / 100
end

-- ---------------------------------------------------------------------------
-- Loot protection via vanilla SafeHouse (the one primitive we reuse)
-- ---------------------------------------------------------------------------
-- PhunZones has no container loot-access protection, so each claim rect is
-- backed by a programmatically-created SafeHouse owned by the faction owner with
-- all members added. Because we create these server-side they are not blocked by
-- the claim zone's own nosafehouse flag (that only gates player-initiated claims).
--
-- Signatures (verified against zombie.iso.areas.SafeHouse in B42; wrapped so a
-- mismatch degrades to a logged warning instead of aborting the claim):
--   SafeHouse.addSafeHouse(int x, int y, int w, int h, String owner) -> SafeHouse
--   sh:addPlayer(username) / sh:removePlayer(username) / sh:getPlayers()
--   SafeHouse.getSafehouseList() ; SafeHouse.removeSafeHouse(sh)
--
-- There is NO sh:syncSafehouse() -- this comment used to claim there was, and the code
-- called it behind an `if sh.syncSafehouse then` guard that silently did nothing, so
-- safehouse changes never reached clients. Verified against the full method list dumped
-- from projectzomboid.jar. Nothing on SafeHouse pushes state to clients; see
-- broadcastSafehouse below for how we do it ourselves.
--
-- The only overloads that exist are the 5-arg one above and
-- addSafeHouse(IsoGridSquare, IsoPlayer). An earlier version passed six arguments
-- with a trailing boolean and unfloored coordinates, which matched nothing and
-- threw "No implementation found for function: addSafeHouse(Double, Double, ...)"
-- on every claim -- so loot protection silently never existed. Kahlua hands Lua
-- numbers to Java as Double, so the coordinates MUST be floored to select the
-- int overload.

-- Run a SafeHouse call defensively; on error log once and return nil so the
-- rest of the claim flow continues.
local function shTry(what, fn)
    local ok, res = pcall(fn)
    if not ok then
        FF.print("WARNING: SafeHouse " .. what .. " failed: " .. tostring(res)
            .. " (loot protection may be inactive; confirm B42 SafeHouse API)")
        return nil
    end
    return res
end

-- Read a boolean ServerOption. Returns nil when the option (or the whole API) is
-- missing, which is a different answer from `false` and the callers rely on that:
-- "we could not find out" must not be reported as "the setting is safe".
local function serverOptionBool(name)
    local so = getServerOptions and getServerOptions()
    if not (so and so.getOptionByName) then return nil end
    local ok, res = pcall(function()
        local opt = so:getOptionByName(name)
        if not (opt and opt.getValue) then return nil end
        local v = opt:getValue()
        if type(v) == "string" then return v == "true" end
        return v == true
    end)
    if not ok then return nil end
    return res
end

local function findSafehouseAt(rec)
    if not (SafeHouse and SafeHouse.getSafehouseList) then return nil end
    local list = shTry("getSafehouseList", function() return SafeHouse.getSafehouseList() end)
    if not list then return nil end
    for i = list:size() - 1, 0, -1 do
        local sh = list:get(i)
        if sh:getX() == rec.x and sh:getY() == rec.y
            and sh:getW() == rec.w and sh:getH() == rec.h then
            return sh
        end
    end
    return nil
end

-- Visit every online player. Declared here rather than beside the raid helpers because
-- the safehouse broadcasts below need it -- a `local function` defined later would be an
-- unresolved global at closure-creation time, not a forward reference.
-- getOnlinePlayers() is backed by GameServer.getPlayers()/GameClient.getPlayers()
-- and, when the engine considers itself NEITHER server nor client (isServer()==false
-- AND isClient()==false -- true singleplayer, no host/join involved), returns a
-- freshly allocated EMPTY ArrayList, never nil. So `players and players.size` is
-- true even with zero players in it, and the old code returned right there --
-- the getSpecificPlayer() fallback below was unreachable in that exact case. That
-- silently starved every fan-out built on this helper (raid/positions/intrusion/
-- territory/upgrades/hunter ticks) of any players at all when tested in plain SP.
local function eachOnlinePlayer(fn)
    local players = getOnlinePlayers and getOnlinePlayers()
    local found = false
    if players and players.size then
        for i = 0, players:size() - 1 do
            local p = players:get(i)
            if p then found = true; fn(p) end
        end
    end
    if not found then
        for i = 0, 3 do
            local p = getSpecificPlayer(i)
            if p then fn(p) end
        end
    end
end

-- Cached roster: { {p = IsoPlayer, user = username}, ... }, refreshed at most once
-- per ONLINE_ROSTER_TTL seconds.
--
-- Every fan-out below used to run its own eachOnlinePlayer pass. The raid,
-- intrusion and member-position ticks can overlap, so this avoids repeating the
-- same getOnlinePlayers()/getUsername() walk several times in one second.
--
-- Only the ROSTER is cached, never the faction bucket: membership is re-read from
-- the O(1) playerIndex on every use, so a notify fired straight after a join/kick
-- still targets the right people. The one staleness window is who is connected,
-- and at worst that means one wasted send to a player who left in the last second
-- -- a race the uncached version had anyway, between its scan and its send.
local ONLINE_ROSTER_TTL = 1
local onlineRoster, onlineRosterAt = nil, -1

-- Drop the roster memo so the next fan-out re-reads it. Called when a client
-- announces itself, so a joining player is never invisible for a second.
function H.invalidateOnlineRoster()
    onlineRoster, onlineRosterAt = nil, -1
end

local function onlinePlayers()
    local now = getTimestamp and getTimestamp() or nil
    if onlineRoster and now and (now - onlineRosterAt) < ONLINE_ROSTER_TTL then
        return onlineRoster
    end
    local list = {}
    eachOnlinePlayer(function(p)
        list[#list + 1] = { p = p, user = FF.identityUsername(p) }
    end)
    onlineRoster, onlineRosterAt = list, now or -1
    return list
end

-- Call an OPTIONAL SafeHouse method, logging once when it does not exist.
--
-- This exists because `if sh.someMethod then sh:someMethod() end` hid a real bug for
-- weeks: we called a non-existent `sh:syncSafehouse()` after every rebuild, the guard
-- skipped it in silence, and so safehouse changes were NEVER pushed to clients. Logs
-- looked perfectly clean the whole time. A missing API must be loud.
local warnedMissing = {}
function H.shOptional(name, obj, fn)
    if obj[name] then return shTry(name, fn) end
    if not warnedMissing[name] then
        warnedMissing[name] = true
        FF.print("WARNING: SafeHouse has no " .. name .. "() in this build; skipping"
            .. " (if members lose claim access, this is why)")
    end
    return nil
end

-- Does this faction have any area opened to allies at all? Such an area embeds the
-- ALLY's member list in this faction's ZONE (zone.ffAllies), so an alliance change or
-- a membership change on either side has to re-project it.
function H.hasAllyArea(faction)
    for _, r in ipairs(faction and faction.claims or {}) do
        if FF.areaAccess(r) == "allies" then return true end
    end
    return false
end

-- Narrower: an ally area that also grants LOOT, which embeds the ally's members in
-- this faction's SAFEHOUSE. Kept separate from hasAllyArea because the two grants are
-- enforced by different systems -- an ally area granting only build/move rides
-- entirely on the zone and needs no safehouse work.
function H.hasAllyLootArea(faction)
    for _, r in ipairs(faction and faction.claims or {}) do
        if FF.areaAccess(r) == "allies" and FF.areaGrants(r).loot then return true end
    end
    return false
end

-- Who belongs on the SafeHouse backing one claim rect. Faction members always; an
-- area opened to allies with the loot grant also admits every mutually-allied
-- faction's members -- the one thing the faction-wide allowAllyBuild/allowAllyMove
-- toggles deliberately do not do.
--
-- Owner-first and deduped, so broadcastSafehouse can send it verbatim while
-- setSafehousePlayers skips the owner (already the safehouse's own owner field).
function H.safehouseRoster(faction, rect)
    local out, seen = {}, {}
    local function add(u)
        if u and not seen[u] then seen[u] = true; out[#out + 1] = u end
    end
    add(faction.owner)
    for user in pairs(faction.members or {}) do add(user) end
    if FF.areaAccess(rect) == "allies" and FF.areaGrants(rect).loot and faction.relations then
        for other, rel in pairs(faction.relations) do
            if rel == "ally" then
                local af = FF.getFaction(other)
                for user in pairs(af and af.members or {}) do add(user) end
            end
        end
    end
    return out
end

-- Push a safehouse to EVERY online client.
--
-- B42 has no server-side "sync this safehouse" API -- `syncSafehouse` does not exist,
-- and the exposed sendSafehouse* globals are client->server request senders. Clients
-- only receive the safehouse list when they connect, so without this a player who is
-- already online never learns about a claim or a membership change until they relog.
--
-- Broadcast scope is deliberately EVERYONE, not just faction members: loot protection
-- is evaluated on the acting client, so a non-member whose client does not know the
-- safehouse exists will not enforce it. Members needed this to gain access; outsiders
-- need it to be denied.
--
-- Mirrors JeevesClaims (workshop 3674013419), which hit the same wall --
-- JeevesClaimsClient.lua:249-300, "Java's native sync may not have delivered it yet".
local function broadcastSafehouse(faction, rec, rect)
    if not (isServer() or isCoopHost()) then return end
    local members = H.safehouseRoster(faction, rect)
    local payload = {
        x = rec.x, y = rec.y, w = rec.w, h = rec.h,
        owner = faction.owner,
        -- A serialized Lua array preserves usernames containing commas. Clients
        -- still accept the legacy comma string during rolling updates.
        members = members,
    }
    eachOnlinePlayer(function(p)
        pcall(function() sendServerCommand(p, FF.MODULE, "syncSafehouse", payload) end)
    end)
end

-- Tell every client to forget a safehouse (unclaim, disband, geometry change).
function H.broadcastSafehouseDrop(rec)
    if not (isServer() or isCoopHost()) then return end
    local payload = { x = rec.x, y = rec.y, w = rec.w, h = rec.h }
    eachOnlinePlayer(function(p)
        pcall(function() sendServerCommand(p, FF.MODULE, "dropSafehouse", payload) end)
    end)
end

local function removeFactionSafehouses(faction)
    if not faction.safehouses then return end
    for _, rec in ipairs(faction.safehouses) do
        local sh = findSafehouseAt(rec)
        if sh then
            shTry("removeSafeHouse", function()
                if SafeHouse.removeSafeHouse then
                    SafeHouse.removeSafeHouse(sh)
                elseif sh.removeSafeHouse then
                    sh:removeSafeHouse()
                end
            end)
        end
        H.broadcastSafehouseDrop(rec)
    end
    FF.log("removed " .. #faction.safehouses .. " safehouse(s)")
    faction.safehouses = nil
end

-- Replace a safehouse's member list in place. Returns true on success.
--
-- Preferred over delete-and-recreate: recreating mints a new SafeHouse object (and a
-- new online id) on every membership change, so any client holding the old one is
-- instantly stale. JeevesClaims mutates in place for the same reason.
function H.setSafehousePlayers(sh, faction, rect)
    local players = shTry("getPlayers", function() return sh:getPlayers() end)
    if not players then return false end
    -- Return a value from inside the pcall: clear() itself returns nothing, so without
    -- this there is no way to tell success from failure through shTry.
    local cleared = shTry("clearPlayers", function() players:clear() return true end)
    if not cleared then return false end
    -- Skip the SafeHouse object's OWN owner, which is not always the faction's current
    -- one: rebuildFactionSafehouses reuses an existing SafeHouse matched on geometry
    -- alone and never re-owns it, so after an ownership transfer the Java object still
    -- names the previous owner. Skipping faction.owner here instead left the NEW owner
    -- out of getPlayers() entirely -- locked out of their own base.
    --
    -- getOwner is PROBED rather than assumed: it is not in the verified signature list
    -- above, and an unguarded shTry would log a warning on every membership sync if the
    -- method is absent. Missing method (or a nil owner) falls back to faction.owner,
    -- which is exactly the old behaviour.
    local shOwner = faction.owner
    if sh.getOwner then
        shOwner = shTry("getOwner", function() return tostring(sh:getOwner()) end) or faction.owner
    end
    for _, user in ipairs(H.safehouseRoster(faction, rect)) do
        if user ~= shOwner then
            H.shOptional("addPlayer", sh, function() sh:addPlayer(user) end)
        end
    end
    return true
end

-- Geometry survives an ownership transfer, but SafeHouse ownership is a separate
-- authority field. Leaving the old leader there permanently granted them implicit
-- loot access even after they later left the faction.
function H.ensureSafehouseOwner(sh, owner)
    if not (sh and owner) then return false end
    local current = nil
    if sh.getOwner then current = shTry("getOwner", function() return tostring(sh:getOwner()) end) end
    if current == owner then return true end
    if not sh.setOwner then return false end
    return shTry("setOwner", function() sh:setOwner(owner); return true end) == true
end

local function rebuildFactionSafehouses(faction)
    if not FF.getOptions().lootProtection then
        removeFactionSafehouses(faction)
        return
    end
    if not (faction.claims and faction.owner and SafeHouse and SafeHouse.addSafeHouse) then
        removeFactionSafehouses(faction)
        return
    end

    -- Rects we already own, so an unchanged claim can be updated in place rather than
    -- torn down and rebuilt.
    local existing = {}
    for _, rec in ipairs(faction.safehouses or {}) do
        existing[rec.x .. ":" .. rec.y .. ":" .. rec.w .. ":" .. rec.h] = rec
    end

    local kept = {}
    local rebuilt = {}
    -- Why a rect got no safehouse. "built 0 safehouse(s)" on its own is indistinguishable
    -- from a silent failure, and a production log showed exactly that for two factions
    -- with land, with nothing anywhere saying whether it was intentional. Loot protection
    -- vanishing quietly is the same failure shape as the SafehouseAllowLoot incident.
    local nOpenLoot, nFailed = 0, 0
    for _, r in ipairs(faction.claims) do
        local x, y = math.floor(r[1]), math.floor(r[2])
        local w = math.floor(r[3] - r[1] + 1)
        local h = math.floor(r[4] - r[2] + 1)
        local rec = { x = x, y = y, w = w, h = h }
        local key = x .. ":" .. y .. ":" .. w .. ":" .. h

        -- An area opened to everyone WITH the loot grant gets no safehouse at all --
        -- the absence of one is what makes its containers public. It is deliberately
        -- left out of `kept`, so a safehouse it used to have is dropped by the orphan
        -- sweep below. A public area WITHOUT the loot grant still gets its normal
        -- members-only safehouse (public to build in, private to loot).
        local openLoot = (FF.areaAccess(r) == "public") and FF.areaGrants(r).loot
        if openLoot then nOpenLoot = nOpenLoot + 1 end

        if not openLoot then
            local sh = existing[key] and findSafehouseAt(rec) or nil
            if sh then
                if H.ensureSafehouseOwner(sh, faction.owner) then
                    kept[key] = true
                else
                    -- A build without setOwner cannot safely reuse the old leader's
                    -- object. Recreate it under the current leader instead.
                    shTry("removeSafeHouse", function()
                        if SafeHouse.removeSafeHouse then SafeHouse.removeSafeHouse(sh)
                        elseif sh.removeSafeHouse then sh:removeSafeHouse() end
                    end)
                    sh = nil
                end
            else
                sh = shTry("addSafeHouse", function()
                    return SafeHouse.addSafeHouse(x, y, w, h, faction.owner)
                end)
            end

            if not sh then
                sh = shTry("addSafeHouse", function()
                    return SafeHouse.addSafeHouse(x, y, w, h, faction.owner)
                end)
            end

            if sh then
                kept[key] = true
                H.setSafehousePlayers(sh, faction, r)
                table.insert(rebuilt, rec)
                broadcastSafehouse(faction, rec, r)
            else
                -- A rect that SHOULD be loot-protected and is not. Warn, not log: this
                -- is a claim silently losing its protection, and it printed nothing at
                -- all before. FF.warn is durable even with the Debug option off.
                nFailed = nFailed + 1
                FF.warn(string.format(
                    "safehouse NOT created for %s's claim at %d,%d (%dx%d) -- that area has NO loot protection",
                    tostring(faction.owner), x, y, w, h))
            end
        end
    end

    -- Drop safehouses for rects that are no longer claimed.
    for key, rec in pairs(existing) do
        if not kept[key] then
            local sh = findSafehouseAt(rec)
            if sh then
                shTry("removeSafeHouse", function()
                    if SafeHouse.removeSafeHouse then SafeHouse.removeSafeHouse(sh) end
                end)
            end
            H.broadcastSafehouseDrop(rec)
        end
    end

    faction.safehouses = rebuilt
    FF.log(string.format(
        "built %d safehouse(s) for owner %s (%d rect(s): %d open-loot public, %d failed)",
        #faction.safehouses, tostring(faction.owner), #faction.claims,
        nOpenLoot, nFailed))
end

-- Membership changed: rebuild the safehouse player list AND re-project the claim
-- zone so its embedded member roster (zone.ffMembers, used by the client-side
-- permission hooks) reflects the new roster. Re-projection is what carries the
-- roster to remote coop clients -- our LasciviousFactionsSystem GlobalModData registry
-- does not reliably reach them, but the PhunZones zone layer does.
local function syncSafehouseMembers(name, faction)
    rebuildFactionSafehouses(faction)
    -- One projection batch for our own zone plus every ally zone that embeds our
    -- roster: an ally who opted into allowAllyBuild/allowAllyMove carries OUR members
    -- in ITS zone (see Claims.zoneProps), so our membership change must re-push those
    -- too or their embedded grant goes stale. Projecting each separately meant a
    -- membership change in an alliance-heavy faction fired one heavy PhunZones rebuild
    -- per ally; batch them into a single saveChanges instead.
    local reproj = {}
    if name and faction.claims and #faction.claims > 0 then
        reproj[#reproj + 1] = { name = name, faction = faction }
    end
    if faction.relations then
        for other, rel in pairs(faction.relations) do
            if rel == "ally" then
                local af = FF.getFaction(other)
                if af and af.claims and #af.claims > 0 then
                    if af.allowAllyBuild or af.allowAllyMove or H.hasAllyArea(af) then
                        reproj[#reproj + 1] = { name = other, faction = af }
                    end
                    -- An ally area granting LOOT also embeds our members in THEIR
                    -- safehouse, which the zone projection above does not touch --
                    -- rebuild it, or a new member of ours cannot loot their open area
                    -- until they relog.
                    if H.hasAllyLootArea(af) then rebuildFactionSafehouses(af) end
                end
            end
        end
    end
    if #reproj > 0 then Claims.projectFactions(reproj) end
end

-- ---------------------------------------------------------------------------
-- Raid helpers
-- ---------------------------------------------------------------------------
local nextRaidTick = 0

-- Native character snapshots arrive frequently, so they set statsDirty instead of
-- syncing per report; a gated tick flushes one FF.sync() when dirty (see statsFlushTick).
local statsDirty = false
local scoreDirtyUsers = {}       -- lightweight client delta, avoids full ModData broadcast
local tributeDirtyFactions = {}  -- passive Shop tax balance deltas, same path

-- Score reports are noisy. Keep only the newest absolute snapshot per player and
-- print it once per flush instead of logging every command.
local killLog = {} -- [username] = { kills=n, hours=n, source=string, events=n }

function H.flushKillLog()
    if not FF.debugEnabled() then
        for user in pairs(killLog) do killLog[user] = nil end
        return
    end
    for user, acc in pairs(killLog) do
        FF.log(string.format("characterScore: %s kills=%d hours=%.2f source=%s (%d reports)",
            tostring(user), math.floor(tonumber(acc.kills) or 0),
            tonumber(acc.hours) or 0, tostring(acc.source or "unknown"),
            tonumber(acc.events) or 1))
        killLog[user] = nil
    end
end

-- Sanity ceilings are intentionally much larger than a legitimate long-lived
-- character. They reject NaN/infinity and broken packets without discarding veteran
-- characters when LFS is first installed on an existing server.
local MAX_CHARACTER_KILLS = 10000000
local MAX_CHARACTER_HOURS = 100000

local function nativeStat(value, maximum, integer)
    value = tonumber(value)
    if not value or value ~= value or value == math.huge or value == -math.huge then return nil end
    value = math.max(0, math.min(maximum, value))
    return integer and math.floor(value) or value
end

-- Read the actual IsoPlayer held by the server. These are the same vanilla counters
-- shown on the character-info screen. Each method is independently guarded so a
-- missing binding in a future build can fall back to the client's absolute snapshot.
function H.readNativeCharacterScore(player)
    if not player then return nil, nil, false end
    local dead = false
    if player.isDead then
        local ok, value = pcall(function() return player:isDead() end)
        dead = ok and value == true
    end
    if dead then return 0, 0, true end

    local kills, hours
    if player.getZombieKills then
        local ok, value = pcall(function() return player:getZombieKills() end)
        if ok then kills = nativeStat(value, MAX_CHARACTER_KILLS, true) end
    end
    if player.getHoursSurvived then
        local ok, value = pcall(function() return player:getHoursSurvived() end)
        if ok then hours = nativeStat(value, MAX_CHARACTER_HOURS, false) end
    end
    return kills, hours, false
end

-- Replace, never increment, the cached score with a snapshot of THIS character.
-- Server-native fields always win. Client values are compatibility fallbacks only
-- when that specific binding is unavailable; taking math.max(server, client) let a
-- modified client submit the sanity ceiling and mint score/claim capacity instantly.
-- The persisted previous-character cache is deliberately not part of the selection:
-- a new character reporting 0 must replace an old character's totals.
local function refreshPlayerScore(player, reportedKills, reportedHours, source)
    if not (player and player.getUsername) then return false end
    local username = FF.identityUsername(player)
    if not username then return false end

    local serverKills, serverHours, dead = H.readNativeCharacterScore(player)
    local clientKills = nativeStat(reportedKills, MAX_CHARACTER_KILLS, true)
    local clientHours = nativeStat(reportedHours, MAX_CHARACTER_HOURS, false)
    local kills, hours

    if dead then
        kills, hours = 0, 0
        source = "death"
    else
        kills = serverKills ~= nil and serverKills or clientKills
        hours = serverHours ~= nil and serverHours or clientHours
    end
    if kills == nil and hours == nil then return false end

    local rec = FF.ensurePlayerScore(username)
    local opts = FF.getOptions()
    local selectedSource = source or ((serverKills ~= nil or serverHours ~= nil) and "server_native" or "client_native")
    local changed = false

    if opts.preserveMemberPowerOnDeath == true then
        local function advancePreservedStat(total, lastRaw, raw)
            if raw == nil then return total, lastRaw, false end
            total = math.max(0, tonumber(total) or 0)
            lastRaw = math.max(0, tonumber(lastRaw) or 0)
            raw = math.max(0, tonumber(raw) or 0)
            if raw + 0.000001 < lastRaw then
                -- New character / missed death event: keep the contributed total
                -- and only re-anchor the current-life native baseline.
                return total, raw, true
            end
            local delta = raw - lastRaw
            if delta < 0 then delta = 0 end
            return total + delta, raw, false
        end

        local newKills, newLastRawKills, killsReset =
            advancePreservedStat(rec.kills, rec.lastRawKills, kills)
        local newHours, newLastRawHours, hoursReset =
            advancePreservedStat(rec.hours, rec.lastRawHours, hours)
        if dead then
            selectedSource = "death_preserved"
        elseif killsReset or hoursReset then
            selectedSource = "native_counter_reset_preserved"
        end

        changed = rec.kills ~= newKills or math.abs(rec.hours - newHours) > 0.000001
            or rec.lastRawKills ~= newLastRawKills
            or math.abs(rec.lastRawHours - newLastRawHours) > 0.000001
            or rec.updatedAt == nil or rec.source == nil

        if changed then
            rec.kills = newKills
            rec.hours = newHours
            -- Compatibility fields used by API schema v1 mirror the current-life
            -- raw baseline while the score total itself can span deaths.
            rec.lastRawKills = newLastRawKills
            rec.lastRawHours = newLastRawHours
            rec.updatedAt = nowMs()
            rec.source = selectedSource
        end
    else
        kills = kills ~= nil and kills or rec.kills
        hours = hours ~= nil and hours or rec.hours
        changed = rec.kills ~= kills or math.abs(rec.hours - hours) > 0.000001
            or rec.lastRawKills ~= kills or math.abs(rec.lastRawHours - hours) > 0.000001
            or rec.updatedAt == nil or rec.source == nil

        if changed then
            rec.kills = kills
            rec.hours = hours
            -- Compatibility fields used by API schema v1 now mirror the absolute snapshot.
            rec.lastRawKills = kills
            rec.lastRawHours = hours
            rec.updatedAt = nowMs()
            rec.source = selectedSource
        end
    end

    if changed then
        statsDirty = true
        scoreDirtyUsers[username] = true
        if FF.debugEnabled() then
            local acc = killLog[username] or { events = 0 }
            acc.kills, acc.hours, acc.source = rec.kills, rec.hours, rec.source
            acc.events = acc.events + 1
            killLog[username] = acc
        end
    end
    return changed
end

-- Public server hook used by the integration API before it snapshots data. Offline
-- players are intentionally untouched: their last native snapshot remains persisted.
function FF.refreshOnlinePlayerScores()
    local changed = false
    eachOnlinePlayer(function(player)
        if refreshPlayerScore(player, nil, nil, "server_native") then changed = true end
    end)
    return changed
end

-- Admin raid simulation override: debugRaidCounts[defenderName] = {attackers, defenders}.
-- When set, the raid tick uses these fake counts instead of counting real players,
local debugRaidCounts = {}

-- (eachOnlinePlayer is declared above the safehouse helpers, which broadcast through it.)

-- Visit every online player whose faction is factionName. Reads the cached roster
-- but resolves membership live, so this is always current with the registry.
local function forEachOnlineMemberOf(factionName, fn)
    if not factionName then return end
    for _, e in ipairs(onlinePlayers()) do
        if FF.getFactionOfPlayer(e.user) == factionName then fn(e.p) end
    end
end

-- Send a notify to every online member of a faction.
local function notifyFaction(factionName, key, extra, extra2)
    forEachOnlineMemberOf(factionName, function(p) notify(p, key, extra, extra2) end)
end

-- Broadcast a server-wide faction event (new faction, disband, alliance, war) to
-- every online player as a chat line. Args is a small array of substitution
-- strings the client formats into its localized template. Gated by sandbox so
-- servers can silence the feed.
local function broadcastEvent(key, args)
    if not FF.getOptions().broadcastFactionEvents then return end
    eachOnlinePlayer(function(p)
        sendServerCommand(p, FF.MODULE, "factionEvent", { key = key, args = args })
    end)
end

-- Increment a faction's informational raid counter. Every caller performs the
-- structural FF.sync() needed for this faction-level field.
local function bumpStat(name, faction, key, n)
    if not (faction and key) then return end
    FF.ensureStats(faction)
    faction.stats[key] = (faction.stats[key] or 0) + (n or 1)
end

-- Count attackers and defenders currently standing inside the defender's claim.
-- "Inside" is resolved through PhunZones via Claims.factionAt, so it reflects the
-- live projected zone, not just the registry rects.
function H.countRaidParticipants(defenderName, attackerName)
    local attackers, defenders = 0, 0
    for _, e in ipairs(onlinePlayers()) do
        local p = e.p
        local x, y = math.floor(p:getX()), math.floor(p:getY())
        if Claims.factionAt(x, y) == defenderName then
            local pf = FF.getFactionOfPlayer(e.user)
            if pf == attackerName then
                attackers = attackers + 1
            elseif pf == defenderName then
                defenders = defenders + 1
            end
        end
    end
    return attackers, defenders
end

-- Successful capture: burn the defender's claim (unclaim + strip loot protection),
-- freeing the land for anyone to re-claim. Mirrors the unclaim teardown.
local function captureBurn(defenderName, defender, attackerName)
    removeFactionSafehouses(defender)
    defender.claims = {}
    Claims.removeFaction(defenderName)
    defender.respawn = nil
    defender.raid = nil
    debugRaidCounts[defenderName] = nil
    -- Authoritative leaderboard/XP credit: attacker won a raid, defender lost a
    -- claim. bumpStat also announces any resulting level-up.
    bumpStat(defenderName, defender, "raidsLost", 1)
    local attacker = FF.getFaction(attackerName)
    if attacker then
        bumpStat(attackerName, attacker, "raidsWon", 1)
    end
    -- War score: burning a claim is a raid won against the defender.
    if FF.addWarScore then FF.addWarScore(attackerName, defenderName, FF.getOptions().warScoreRaidWon) end
    FF.sync()
    FF.print(string.format("raid CAPTURED: %s burned %s's claim", tostring(attackerName), tostring(defenderName)))
    notifyFaction(attackerName, "raid_won", defenderName)
    notifyFaction(defenderName, "raid_lost", attackerName)
end

-- Refund any remaining tribute treasury to the (disbanding) owner's Shop balance.
-- Called by all three disband paths (Handlers.disband, decayDisband below, and
-- Handlers.adminDisband -- see FF.releaseFactionRefs's own docstring, "Called by
-- all three disband paths"), before the faction record is deleted. Declared here,
-- ahead of decayDisband and Handlers.disband, deliberately: a local declared
-- further down in this file is an out-of-scope nil GLOBAL to code above it, which
-- is the exact trap that aborted the whole server file in the 1.2.1 incident (see
-- the notify()/sendReport() comment near the top of this file).
--
-- Confirmed with the user: on disband/decay the treasury goes to the leader, not
-- forfeited. The automatic decay-disband path can fire while the owner is
-- offline, which is exactly why this prefers LasciviousShop.queueCredits
-- (identity-safe deferred delivery) rather than requiring a live player object.
FF._refundFailureWarned = FF._refundFailureWarned or {}
local function refundTributeTreasury(name, faction)
    if not faction then return true end
    FF.ensureTribute(faction)
    local balance = tonumber(faction.tribute.balance) or 0
    if balance <= 0 then return true end
    local refund = faction.tribute.refund
    if type(refund) == "table" and refund.status == "processing" then
        if not FF._refundFailureWarned[name] then
            FF._refundFailureWarned[name] = true
            FF.warn("tribute refund remains ambiguous for faction '" .. tostring(name)
                .. "' (owner=" .. tostring(refund.owner) .. ", amount="
                .. tostring(refund.amount) .. "); disband remains blocked")
        end
        return false
    end
    if not faction.owner then
        if not FF._refundFailureWarned[name] then
            FF._refundFailureWarned[name] = true
            FF.warn("tribute refund blocked for faction '" .. tostring(name)
                .. "': positive treasury has no owner")
        end
        return false
    end
    local LS = _G.LasciviousShop
    local grant = LS and (LS.queueCredits or LS.grantCredits)
    if type(grant) ~= "function" then
        if not FF._refundFailureWarned[name] then
            FF._refundFailureWarned[name] = true
            FF.warn("tribute refund blocked for faction '" .. tostring(name)
                .. "': Shop credit API unavailable")
        end
        return false
    end

    -- Cross-ModData operations are not atomic. Persist a fail-closed reservation
    -- before calling Shop so a crash/retry can never issue the owner twice.
    faction.tribute.refund = {
        status = "processing", owner = faction.owner, amount = balance, startedAt = nowMs(),
    }
    FF.syncNow()
    local ok, granted = pcall(grant, faction.owner, balance, "faction_tribute_refund")
    if not ok then
        if not FF._refundFailureWarned[name] then
            FF._refundFailureWarned[name] = true
            FF.warn("tribute refund became ambiguous for faction '" .. tostring(name)
                .. "', owner '" .. tostring(faction.owner) .. "': " .. tostring(granted)
                .. "; disband remains blocked")
        end
        return false
    end
    if not granted then
        -- Shop conclusively rejected before applying; clear the reservation so a
        -- later retry can proceed once the integration/account issue is fixed.
        faction.tribute.refund = nil
        FF.sync()
        if not FF._refundFailureWarned[name] then
            FF._refundFailureWarned[name] = true
            FF.warn("tribute refund of " .. tostring(balance) .. " blocked disband for faction '"
                .. tostring(name) .. "', owner '" .. tostring(faction.owner) .. "'")
        end
        return false
    end
    -- Clear only after Shop accepted/applied (queueCredits safely follows an
    -- offline username into its eventual Steam-backed identity).
    faction.tribute.balance = 0
    faction.tribute.refund = {
        status = "complete", owner = faction.owner, amount = balance, completedAt = nowMs(),
    }
    FF._refundFailureWarned[name] = nil
    FF.sync()
    return true
end

-- Disband a faction as abandoned (frees its land, clears its roster). Shared by the
-- decay sweep (decayTick) and the admin force-decay tool. Caller handles FF.sync().
local function decayDisband(name, faction)
    -- Never destroy the only persistent copy of a positive treasury when the Shop
    -- integration is temporarily unavailable. The decay sweep will retry later.
    if not refundTributeTreasury(name, faction) then return false end
    local data = FF.getData()
    if FF.dissolveWarsFor then FF.dissolveWarsFor(name) end
    if FF.clearPactsFor then FF.clearPactsFor(name) end
    removeFactionSafehouses(faction)
    -- Clear the claims BEFORE deleting the zone, exactly as unclaim/captureBurn/upkeep
    -- do. Claims.removeFaction's own guard makes this belt-and-braces now, but the
    -- ordering is the thing that used to differ between the paths that orphaned a zone
    -- and the ones that didn't -- keep every path identical so it can't drift back.
    faction.claims = {}
    Claims.removeFaction(name)
    -- Drop every remaining reference to this faction: the reverse index, other
    -- factions' relations and requests, a raid it was mounting, job applications,
    -- the season baseline. Runs AFTER the war and
    -- pact dissolution above, which own those two tables and do more than a plain
    -- drop; this then mops up the plain ally/enemy relations they leave behind. It
    -- also supersedes the `for user in pairs(faction.members)` loop that used to be
    -- here -- it scans playerIndex by value, so it catches rows the member list has
    -- already lost track of.
    if FF.releaseFactionRefs then FF.releaseFactionRefs(name) end
    data.factions[name] = nil
    FF.print(string.format("faction '%s' disbanded by decay/abandonment", name))
    broadcastEvent("faction_decayed", { name })
    -- Members lose the faction, so they lose its character buffs with it.
    return true
end

-- Push a lightweight progress ping to all online members of both factions. Not
-- persisted/synced -- purely transient HUD data; the authoritative raid presence
-- lives in faction.raid (set on declare, cleared on end).
function H.sendRaidProgress(defenderName, raid, attackers, defenders, opts)
    local payload = {
        defender = defenderName,
        attacker = raid.attacker,
        held = math.floor(raid.holdSeconds),
        need = opts.raidHoldSeconds,
        attackers = attackers,
        defenders = defenders,
    }
    -- One roster pass covering both sides rather than two forEachOnlineMemberOf
    -- walks; this runs every second for the life of a raid.
    for _, e in ipairs(onlinePlayers()) do
        local pf = FF.getFactionOfPlayer(e.user)
        if pf == defenderName or pf == raid.attacker then
            sendServerCommand(e.p, FF.MODULE, "raidprogress", payload)
        end
    end
end

-- ---------------------------------------------------------------------------
-- Registry mutation helpers
-- ---------------------------------------------------------------------------

-- ---------------------------------------------------------------------------
-- Command handlers  (each: function(player, args))
-- ---------------------------------------------------------------------------
local Handlers = {}

-- ---------------------------------------------------------------------------
-- Manual invitation transport and persistent decline throttling
-- ---------------------------------------------------------------------------
-- The first refusal is a short 60-second brake; repeated refusals from the same
-- faction escalate sharply and cap at 30 days. Stored in GlobalModData so restarting
-- the server cannot be used to resume spam.
local INVITE_DECLINE_DELAYS = { 60, 3600, 86400, 604800, 2592000 }

local function nowSeconds()
    return math.floor(nowMs() / 1000)
end

function H.findOnlinePlayer(username)
    local found = nil
    eachOnlinePlayer(function(p)
        if not found and FF.identityUsername(p) == username then found = p end
    end)
    return found
end

function H.inviteCooldownRecord(factionName, username, create)
    local root = FF.getData().inviteCooldowns
    local bucket = root[factionName]
    if type(bucket) ~= "table" then
        if not create then return nil, nil end
        bucket = {}
        root[factionName] = bucket
    end
    return bucket and bucket[username] or nil, bucket
end

function H.inviteCooldownRemaining(factionName, username)
    local rec = H.inviteCooldownRecord(factionName, username, false)
    return rec and math.max(0, (tonumber(rec.untilAt) or 0) - nowSeconds()) or 0
end

function H.sendInvitePopup(player, factionName, inviter)
    if not player then return end
    sendServerCommand(player, FF.MODULE, "factionInvitePopup", {
        faction = factionName,
        inviter = inviter or "",
    })
end

function H.sendPendingInvitePopups(player)
    local username = player and FF.identityUsername(player)
    if not username or FF.getFactionOfPlayer(username) then return end
    for factionName, faction in pairs(FF.getData().factions or {}) do
        local invite = faction.invites and faction.invites[username]
        if invite then
            H.sendInvitePopup(player, factionName,
                type(invite) == "table" and invite.inviter or faction.owner)
        end
    end
end

-- Admin gating helpers. Defined HERE, right after Handlers, because several admin
-- handlers (adminWar/adminPact) call adminHandler() further up the file than the
-- rest of the admin tools -- they must exist before the first call, or the whole
-- server file aborts at load ("tried to call nil") and no handlers register.
local function isAdminPlayer(player)
    if not player then return false end
    local al = player.getAccessLevel and player:getAccessLevel()
    if al ~= nil and string.lower(tostring(al)) == "admin" then return true end

    -- isCoopHost() describes the PROCESS, not the player attached to an incoming
    -- OnClientCommand. Granting on that flag alone made every remote guest an LFS
    -- admin on a hosted coop game. Only the actual local host player gets the
    -- access-level-less coop exception.
    if isCoopHost() then
        local okLocal, isLocal = pcall(function()
            return player.isLocalPlayer and player:isLocalPlayer()
        end)
        if okLocal and isLocal then return true end
        local ok, localPlayer = pcall(function() return getPlayer and getPlayer() end)
        if ok and localPlayer and localPlayer == player then return true end
    end
    -- True singleplayer has neither a client nor server access-level service.
    if not isServer() and not isClient() then return true end
    return false
end
FF.isAdminPlayer = isAdminPlayer

-- Wrap a handler so only admins may invoke it.
local function adminHandler(fn)
    return function(player, args)
        if not isAdminPlayer(player) then
            return notify(player, "That command is admin-only.")
        end
        return fn(player, args)
    end
end

-- Load checkpoint: proves the exact fix point of the 1.2.1 load-crash incident is
-- reached (see the comment above isAdminPlayer). Always logged -- see FF.checkpoint.
FF.checkpoint("core handler infrastructure ready")

-- Join-time handshake: a client that is genuinely in-world asks for the registry
-- and we reply TARGETED with the full table inline. This is the guaranteed
-- delivery path (independent of ModData.transmit timing) and mirrors PhunZones'
-- playerSetup command. Live updates after this arrive via FF.sync()/transmit +
-- the client's OnReceiveGlobalModData handler.
Handlers.requestSync = function(player, args)
    if not player then return end
    -- A client announcing itself is the earliest signal that the roster changed;
    -- drop the memo so notifies reach them immediately rather than up to a second late.
    H.invalidateOnlineRoster()
    -- Import the complete native history before sending the first registry. This is
    -- what makes an old character count immediately after LFS is installed.
    refreshPlayerScore(player, nil, nil, "server_native_join")
    sendServerCommand(player, FF.MODULE, "syncData", { data = FF.getData() })
    H.sendPendingInvitePopups(player)
    FF.log("requestSync -> sent registry to " .. tostring(player:getUsername()))
end

-- Auto-generate a short tag from the faction name when the player leaves the tag
-- blank, instead of falling back to the full name (a tag that IS the whole name
-- defeats the point of having a short tag). Multi-word names take one initial per
-- word (capped at 5, e.g. "Wasteland Wanderers" -> "WW"); a single word takes its
-- first few letters instead (e.g. "Legiao" -> "LEGI"). Always non-empty when name
-- is, since name is already required to be non-empty by the caller.
function H.generateTagFromName(name)
    name = tostring(name or "")
    local initials = {}
    for word in name:gmatch("%S+") do
        local first = FF.truncateUtf8(word, 1)
        if first ~= "" then initials[#initials + 1] = first:upper() end
        if #initials >= 5 then break end
    end
    if #initials >= 2 then
        return table.concat(initials)
    end
    local letters = name:gsub("%s+", "")
    if letters == "" then return name end
    return FF.truncateUtf8(letters, 4):upper()
end

-- Registry strings are rendered by rich-text widgets and sent to chat. Strip
-- controls/markup at the authority boundary so a modified client cannot inject
-- tags or multi-line UI content into every other client.
local function safeDisplayText(value, maximum)
    if type(value) ~= "string" then return "" end
    value = value:gsub("[%c]", " "):gsub("[<>]", "")
    value = value:gsub("^%s+", ""):gsub("%s+$", "")
    return FF.truncateUtf8(value, maximum)
end

Handlers.createFaction = function(player, args)
    local username = FF.identityUsername(player)
    local name = args and args.name
    if not name or name == "" then return notify(player, "name_required") end
    local valid, reason = FF.validateFactionName(name)
    if not valid then return notify(player, "invalid_faction_name", reason) end

    local data = FF.getData()
    if data.factions[name] then return notify(player, "name_taken") end
    if data.playerIndex[username] then return notify(player, "already_in_faction") end

    -- Creation is gated by the founder's CURRENT CHARACTER score. Refresh directly
    -- from its vanilla counters first, so a just-connected veteran is never read as 0.
    -- The value is server-owned (with an absolute client-native fallback) and defaults to
    -- zero so fresh test characters can create factions. This is deliberately a
    -- creation-only gate: losing points on death never dissolves an existing faction.
    refreshPlayerScore(player, nil, nil, "server_native_create")
    local opts = FF.getOptions()
    local requiredScore = math.max(0, tonumber(opts.minPersonalScoreToCreateFaction) or 0)
    local personalScore = FF.playerScore(username, opts)
    if personalScore < requiredScore then
        return notify(player, "create_score_too_low",
            string.format("%d / %d", math.floor(personalScore), math.ceil(requiredScore)))
    end

    -- The creation dialog sends the full initial setup; fall back to sane defaults
    -- for any field it omits. New factions are invite-only unless the dialog says
    -- otherwise.
    local tag = safeDisplayText(args.tag, 24)
    if tag == "" then tag = H.generateTagFromName(name) end
    local description = safeDisplayText(args.description, 60)
    local color = nil
    if type(args.color) == "table" then
        local function clamp01(v)
            v = tonumber(v)
            if not v or v ~= v or v == math.huge or v == -math.huge then return nil end
            return math.max(0, math.min(1, v))
        end
        local r, g, b = clamp01(args.color.r), clamp01(args.color.g), clamp01(args.color.b)
        if r and g and b then color = { r = r, g = g, b = b } end
    end

    data.factions[name] = {
        owner = username,
        members = { [username] = "owner" },
        roles = FF.defaultRoles(),
        tag = tag,
        description = description,
        motd = "",                -- owner's message-of-the-day, shown to members on login
        friendlyFire = args.friendlyFire == true,   -- members protected from each other by default
        hideBanner = args.hideBanner == true,
        color = color,            -- nil = use the name-derived accent colour
        joinMode = "closed",
        invites = {},
        relations = {},           -- [otherName] = "ally" | "enemy"
        allyRequests = {},         -- [requesterName] = true (incoming)
        shareMapWithAllies = true,
        created = getGameTime():getWorldAgeHours(),
        lastActive = nowMs(),     -- real-world epoch (ms); drives claim decay
        claims = {},
        respawn = nil,
        loot = true,
        raid = nil,
        stats = { raidsWon = 0, raidsLost = 0, raidsDefended = 0 },
        tribute = { balance = 0, ratePercent = 0, history = {} },
    }
    data.playerIndex[username] = name
    FF.sync()
    notify(player, "faction_created", name)
    broadcastEvent("faction_new", { name })
end

Handlers.disband = function(player, args)
    local username = FF.identityUsername(player)
    local name, faction = FF.getFactionOfPlayer(username)
    if not faction then return notify(player, "not_in_faction") end
    if faction.owner ~= username then return notify(player, "not_owner") end
    if not refundTributeTreasury(name, faction) then
        return notify(player, "tribute_shop_unavailable")
    end

    if FF.dissolveWarsFor then FF.dissolveWarsFor(name) end
    if FF.clearPactsFor then FF.clearPactsFor(name) end
    removeFactionSafehouses(faction)
    faction.claims = {}          -- before removeFaction; see decayDisband
    Claims.removeFaction(name)

    local data = FF.getData()
    if FF.releaseFactionRefs then FF.releaseFactionRefs(name) end   -- see decayDisband
    data.factions[name] = nil
    FF.sync()
    notify(player, "faction_disbanded", name)
    broadcastEvent("faction_disbanded_global", { name })
end

-- The one and only way a player becomes a member. Extracted from Handlers.join so the
-- Every accepted invitation admits people through exactly the same door: the member
-- cap, reverse index and safehouse roster must never drift between entry paths.
--
-- Returns ok(boolean), reasonKey(string|nil). Does NOT check invites or joinMode --
-- that is the caller's gate, because the two callers disagree about it: `join` must
-- honour "closed", whereas a faction accepting an application has by definition already
-- consented. Does NOT sync either; the caller batches that with its own mutations.
local function admitMember(name, faction, player)
    local username = FF.identityUsername(player)
    local data = FF.getData()
    if data.playerIndex[username] then return false, "already_in_faction" end

    -- Member cap (0 = unlimited). Checked before any mutation so a full faction
    -- never silently burns an invite or an application.
    local cap = FF.getOptions().maxMembersPerFaction
    if cap > 0 and FF.memberCount(faction) >= cap then
        return false, "member_cap_reached"
    end

    faction.members[username] = "member"
    data.playerIndex[username] = name
    -- Retire any legacy recruitment record and every stale invitation elsewhere.
    data.lff = data.lff or {}
    data.lff[username] = nil
    for otherName, otherFaction in pairs(data.factions or {}) do
        if otherFaction.invites then otherFaction.invites[username] = nil end
        if data.inviteCooldowns[otherName] and otherName == name then
            data.inviteCooldowns[otherName][username] = nil
        end
    end
    -- New member raises the claim ceiling and gains loot access.
    syncSafehouseMembers(name, faction)
    return true, nil
end
FF.admitMember = admitMember

Handlers.join = function(player, args)
    local username = FF.identityUsername(player)
    local name = args and args.name
    local data = FF.getData()
    local faction = name and data.factions[name]
    if not faction then return notify(player, "no_such_faction") end
    if data.playerIndex[username] then return notify(player, "already_in_faction") end

    -- All membership is manual/invite-only. Kept on the legacy `join` command too so
    -- old clients and /ff join cannot bypass the new popup flow.
    if not (faction.invites and faction.invites[username]) then
        return notify(player, "invite_required")
    end

    local ok, reason = admitMember(name, faction, player)
    if not ok then return notify(player, reason) end

    FF.sync()
    notify(player, "joined_faction", name)
end

Handlers.acceptInvite = Handlers.join

Handlers.leave = function(player, args)
    local username = FF.identityUsername(player)
    local name, faction = FF.getFactionOfPlayer(username)
    if not faction then return notify(player, "not_in_faction") end
    if faction.owner == username then return notify(player, "owner_must_disband") end

    faction.members[username] = nil
    FF.getData().playerIndex[username] = nil
    syncSafehouseMembers(name, faction)
    FF.sync()
    notify(player, "left_faction", name)
end

-- Resolve the caller's faction and require ownership. On failure it sends the
-- appropriate notify and returns nil.
--
-- Lives here, above its first caller, rather than down with the role handlers it used
-- to sit among: a `local function` declared below a call site is not an upvalue to it,
-- it is a nil global. Everything it needs (notify, isAdminPlayer, FF.getFactionOfPlayer)
-- is already defined above.
--
-- Passing `args` OPTS IN to an admin override: an admin may name any faction via
-- args.faction and act on it as though they owned it. It is opt-in per call site
-- rather than blanket, so a handler only gains an admin path when someone decided it
-- should have one -- the settings handlers and ownership transfer do (an admin-created
-- faction is otherwise stuck with its defaults until its owner logs in), while the war,
-- pact, raid and role handlers deliberately do not: each already has a dedicated admin
-- command, and a silent second route into diplomacy is a far bigger change than fixing
-- a faction's settings. A one-argument call behaves exactly as it always did.
--
-- The third return says the caller is acting as an admin from OUTSIDE the faction.
-- Anything that would otherwise assume "the caller is a member" must consult it --
-- see transferOwnership, which would otherwise demote the admin into the roster.
local function ownerFaction(player, args)
    local target = args and args.faction
    if target and target ~= "" and isAdminPlayer(player) then
        local faction = FF.getFaction(target)
        if not faction then
            notify(player, "Admin: no faction '" .. tostring(target) .. "'.")
            return nil
        end
        FF.ensureRoles(faction)
        return target, faction, true
    end
    local username = FF.identityUsername(player)
    local name, faction = FF.getFactionOfPlayer(username)
    if not faction then notify(player, "not_in_faction"); return nil end
    FF.ensureRoles(faction)
    if faction.owner ~= username then notify(player, "not_authorised"); return nil end
    return name, faction
end

-- Owner hands full ownership to an existing member; the outgoing owner drops to
-- the reserved "member" role. This is the only way an owner stops being the owner
-- short of disbanding -- once it happens, Handlers.leave's owner_must_disband
-- check no longer applies to them, so they're free to leave afterward if they wish.
-- Admins may drive this against any faction via args.faction. Everything below is
-- therefore written against `prevOwner` (the faction's own owner) rather than the
-- CALLER: under the admin path those are different people, and demoting the caller
-- would seat the admin in a faction they are not a member of.
Handlers.transferOwnership = function(player, args)
    local name, faction, asAdmin = ownerFaction(player, args)
    if not faction then return end

    local prevOwner = faction.owner
    local target = args and args.username
    if not target or target == prevOwner then return notify(player, "cannot_transfer_self") end
    if not faction.members[target] then return notify(player, "no_such_member") end

    faction.owner = target
    faction.members[target] = "owner"
    faction.members[prevOwner] = "member"
    syncSafehouseMembers(name, faction)
    FF.sync()
    notifyFaction(name, "ownership_transferred", prevOwner, target)
    if asAdmin then
        notify(player, string.format("Admin: %s now owns '%s' (was %s).", target, name, prevOwner))
    end
end

-- Owner/officer promotes or demotes a member of their own faction. The owner's
-- own role can never be changed here -- use Handlers.transferOwnership instead.
Handlers.setMemberRole = function(player, args)
    local username = FF.identityUsername(player)
    local name, faction = FF.getFactionOfPlayer(username)
    if not faction then return notify(player, "not_in_faction") end
    FF.ensureRoles(faction)
    if not FF.roleCan(faction, username, "manageMembers") then return notify(player, "not_authorised") end

    local target = args and args.username
    local role = args and args.role
    if not (target and faction.members[target]) then return notify(player, "no_such_member") end
    if faction.owner == target then return notify(player, "cannot_change_owner") end
    -- Role must be an existing (non-owner) role of this faction.
    if role == "owner" or not (faction.roles and faction.roles[role]) then
        return notify(player, "invalid_role")
    end

    faction.members[target] = role
    -- Re-embed the zone roster so the target's new build/move rights reach clients.
    syncSafehouseMembers(name, faction)
    FF.sync()
    notifyFaction(name, "member_role_changed", target, role)
end

-- Owner/officer removes a member from their own faction. Cannot target the
-- owner (disband instead) or yourself (leave instead).
Handlers.kickMember = function(player, args)
    local username = FF.identityUsername(player)
    local name, faction = FF.getFactionOfPlayer(username)
    if not faction then return notify(player, "not_in_faction") end
    FF.ensureRoles(faction)
    if not FF.roleCan(faction, username, "manageMembers") then return notify(player, "not_authorised") end

    local target = args and args.username
    if not (target and faction.members[target]) then return notify(player, "no_such_member") end
    if faction.owner == target then return notify(player, "cannot_kick_owner") end
    if target == username then return notify(player, "cannot_kick_self") end

    faction.members[target] = nil
    FF.getData().playerIndex[target] = nil
    syncSafehouseMembers(name, faction)
    FF.sync()
    notifyFaction(name, "member_kicked", target)
    -- The kicked player may be online; strip their faction buffs.
end

-- ---------------------------------------------------------------------------
-- Role management (owner-only). A role carries the togglable permissions listed
-- in FF.PERMISSIONS; the owner is implicit and always has all of them. "member"
-- is the reserved fallback role that deletion reassigns to.
-- ---------------------------------------------------------------------------
local PERM_SET = {}
for _, p in ipairs(FF.PERMISSIONS) do PERM_SET[p] = true end
local ROLE_NAME_MAX = 24
function H.validRoleName(role)
    if type(role) ~= "string" or role == "" or role == "owner" then return false end
    if #role > ROLE_NAME_MAX or role ~= role:match("^%s*(.-)%s*$") then return false end
    if role:find("[%c<>]") then return false end
    return true
end

Handlers.createRole = function(player, args)
    local name, faction = ownerFaction(player)
    if not faction then return end
    local role = args and args.name
    if not H.validRoleName(role) then return notify(player, "invalid_role") end
    if faction.roles[role] then return notify(player, "role_exists") end
    local count = 0
    for _ in pairs(faction.roles) do count = count + 1 end
    if count >= FF.getOptions().maxRolesPerFaction then return notify(player, "too_many_roles") end
    -- Seed the full permission set (all FF.PERMISSIONS) so a new role carries every
    -- current key; roleCan treats a missing key as false, but omitting keys here drifts
    -- from the canonical list as permissions are added.
    faction.roles[role] = {
        claim = false, setRespawn = false, build = false, move = false,
        manageMembers = false, startRaid = false, manageTribute = false,
        protectVehicles = false,
    }
    FF.sync()
    notify(player, "role_created", role)
end

Handlers.deleteRole = function(player, args)
    local name, faction = ownerFaction(player)
    if not faction then return end
    local role = args and args.name
    if not role or not faction.roles[role] then return notify(player, "invalid_role") end
    if role == "member" then return notify(player, "cannot_delete_role") end  -- reassignment target
    faction.roles[role] = nil
    local reassigned = false
    for user, r in pairs(faction.members) do
        if r == role then faction.members[user] = "member"; reassigned = true end
    end
    if reassigned then syncSafehouseMembers(name, faction) end
    FF.sync()
    notify(player, "role_deleted", role)
end

Handlers.renameRole = function(player, args)
    local name, faction = ownerFaction(player)
    if not faction then return end
    local role = args and args.name
    local newName = args and args.newName
    if not role or not faction.roles[role] then return notify(player, "invalid_role") end
    if role == "member" then return notify(player, "cannot_delete_role") end   -- keep the reserved fallback
    if not H.validRoleName(newName) then return notify(player, "invalid_role") end
    if faction.roles[newName] then return notify(player, "role_exists") end
    faction.roles[newName] = faction.roles[role]
    faction.roles[role] = nil
    local repointed = false
    for user, r in pairs(faction.members) do
        if r == role then faction.members[user] = newName; repointed = true end
    end
    if repointed then syncSafehouseMembers(name, faction) end
    FF.sync()
    notify(player, "role_renamed", newName)
end

Handlers.setRolePermission = function(player, args)
    local name, faction = ownerFaction(player)
    if not faction then return end
    local role = args and args.name
    local perm = args and args.perm
    if not role or not faction.roles[role] then return notify(player, "invalid_role") end
    if not (perm and PERM_SET[perm]) then return notify(player, "invalid_role") end
    faction.roles[role][perm] = (args.value == true)
    -- build/move changes alter claim-tile gating -> re-embed the zone roster.
    if perm == "build" or perm == "move" then
        syncSafehouseMembers(name, faction)
    end
    FF.sync()
    notify(player, "role_updated", role)
end

-- ---------------------------------------------------------------------------
-- Faction settings (owner-only). Identity/description/appearance + toggles.
-- ---------------------------------------------------------------------------
local FACTION_FLAGS = { friendlyFire = true, hideBanner = true, shareMapWithAllies = true, shareMemberLocations = true,
    allowAllyBuild = true, allowAllyMove = true }
local DESC_MAX = 60   -- single-line PhunZones entry banner; keep it short
local MOTD_MAX = 240  -- message-of-the-day; not on the zone banner, so it can run longer

Handlers.setFactionInfo = function(player, args)
    local name, faction = ownerFaction(player, args)
    if not faction then return end
    if type(args.tag) == "string" and args.tag ~= "" then
        local tag = safeDisplayText(args.tag, 24)
        if tag ~= "" then faction.tag = tag end
    end
    if type(args.description) == "string" then
        faction.description = safeDisplayText(args.description, DESC_MAX)
    end
    -- MOTD is display-only (shown to members on login / in the panel), so it does not
    -- feed the zone and needs no re-project.
    if type(args.motd) == "string" then
        faction.motd = safeDisplayText(args.motd, MOTD_MAX)
    end
    -- The description feeds the zone subtitle -> re-project so it reaches clients.
    if name and faction.claims and #faction.claims > 0 then
        Claims.projectFaction(name, faction)
    end
    FF.sync()
    notify(player, "faction_updated")
end

Handlers.setFactionOption = function(player, args)
    local name, faction = ownerFaction(player, args)
    if not faction then return end
    local key = args and args.key
    if not (key and FACTION_FLAGS[key]) then return end
    faction[key] = (args.value == true)
    -- hideBanner -> zone noannounce; shareMapWithAllies -> zone ffShareWith;
    -- allowAllyBuild/allowAllyMove -> zone ffMembers (ally grants). All four are
    -- carried on the zone, so re-project to push the change to clients.
    if (key == "hideBanner" or key == "shareMapWithAllies"
        or key == "allowAllyBuild" or key == "allowAllyMove")
        and name and faction.claims and #faction.claims > 0 then
        Claims.projectFaction(name, faction)
    end
    FF.sync()
    notify(player, "faction_updated")
end

Handlers.setFactionColor = function(player, args)
    local name, faction = ownerFaction(player, args)
    if not faction then return end
    local r, g, b = tonumber(args and args.r), tonumber(args and args.g), tonumber(args and args.b)
    if r and g and b and r == r and g == g and b == b
        and r ~= math.huge and g ~= math.huge and b ~= math.huge
        and r ~= -math.huge and g ~= -math.huge and b ~= -math.huge then
        local function clamp01(v) return math.max(0, math.min(1, v)) end
        faction.color = { r = clamp01(r), g = clamp01(g), b = clamp01(b) }
    else
        faction.color = nil   -- reset to the name-derived colour
    end
    FF.sync()
    notify(player, "faction_updated")
end

-- ---------------------------------------------------------------------------
-- Faction tribute: an owner-configured tax (0-100%) on members' Shop earnings,
-- collected into a per-faction treasury. This is the mod's first real
-- integration with LasciviousShop -- see LasciviousShop_Server.lua's
-- refreshCredits (the only external caller of FF.creditTributeFromEarnings) and
-- the guarded credit/queue API calls in the transaction paths below.
-- ---------------------------------------------------------------------------

-- Appends one visible history row (deposit/withdraw only -- passive per-tick tax
-- collection never calls this, or the log would fill with one entry per online
-- member every few seconds). Oldest entries fall off past FF.TRIBUTE_HISTORY_MAX.
function H.appendTributeHistory(faction, kind, actor, amount)
    FF.ensureTribute(faction)
    local history = faction.tribute.history
    table.insert(history, { at = nowMs(), kind = kind, actor = actor, amount = amount })
    while #history > FF.TRIBUTE_HISTORY_MAX do
        table.remove(history, 1)
    end
end

-- Replay-protection cache for deposit/withdraw, mirroring the pattern Shop's own
-- purchase flow uses (LasciviousShop_Server.lua's rememberResult/MAX_RECENT_REQUESTS)
-- -- justified here specifically because these move real currency, unlike this
-- file's other handlers. Keyed by "command|requestId" (not bare requestId) so a
-- client bug reusing an id across Deposit and a later Withdraw can't return the
-- wrong cached result.
local TRIBUTE_REQUEST_CACHE_MAX = 20

function H.tributeCacheFor(username)
    local data = FF.getData()
    local cache = data.tributeRequests[username]
    if type(cache) ~= "table" then
        cache = { recentResults = {}, recentOrder = {}, updatedAt = nowMs() }
        data.tributeRequests[username] = cache
    end
    if type(cache.recentResults) ~= "table" then cache.recentResults = {} end
    if type(cache.recentOrder) ~= "table" then cache.recentOrder = {} end
    cache.updatedAt = nowMs()
    return cache
end

local function rememberTributeRequest(cache, cacheKey, key, extra)
    local isNew = cache.recentResults[cacheKey] == nil
    cache.recentResults[cacheKey] = {
        status = "complete", key = key, extra = extra, completedAt = nowMs(),
    }
    cache.updatedAt = nowMs()
    if isNew then table.insert(cache.recentOrder, cacheKey) end
    local protectedSeen = 0
    while #cache.recentOrder > TRIBUTE_REQUEST_CACHE_MAX
        and protectedSeen < #cache.recentOrder do
        local old = table.remove(cache.recentOrder, 1)
        local result = cache.recentResults[old]
        -- An ambiguous cross-ModData operation must remain fail-closed forever;
        -- evicting its marker would make a later retry execute it twice. At most one
        -- processing marker per user is allowed (see tributeCacheHasProcessing).
        if result and result.status == "processing" then
            table.insert(cache.recentOrder, old)
            protectedSeen = protectedSeen + 1
        else
            cache.recentResults[old] = nil
            protectedSeen = 0
        end
    end
end

function FF._tributeCacheHasProcessing(cache, exceptKey)
    for key, result in pairs(cache.recentResults) do
        if key ~= exceptKey and type(result) == "table" and result.status == "processing" then
            return true
        end
    end
    return false
end

-- Reserve the request id before touching the Shop or treasury ModData. There is no
-- atomic transaction spanning two GlobalModData tables, so an exception after an
-- external call is fundamentally ambiguous. Keeping `processing` makes retries
-- fail closed instead of risking a second debit/payment.
function FF._beginTributeRequest(cache, cacheKey, kind, factionName, amount)
    if FF._tributeCacheHasProcessing(cache, cacheKey) then return false end
    if cache.recentResults[cacheKey] == nil then table.insert(cache.recentOrder, cacheKey) end
    local started = nowMs()
    cache.recentResults[cacheKey] = {
        status = "processing", key = "tribute_request_processing",
        kind = kind, faction = factionName, amount = amount, startedAt = started,
    }
    cache.updatedAt = started
    -- Mark the registry dirty before the first cross-system mutation. Normal success
    -- completes in this same turn and the coalescer broadcasts only the final record.
    FF.sync()
    return true
end

-- Called from LasciviousShop_Server.lua's refreshCredits, once per online member
-- per credit tick. Taxes only the kill/hour-derived portion of that tick's
-- earnings (never the debug grant or the one-time retroactive grant -- those never
-- reach this function). Returns the amount the player actually keeps; unchanged
-- when the player isn't in a faction or the rate is 0. Rounds the tribute cut
-- first, then derives the net by subtraction (not a second independent rounding)
-- so the two sides always sum exactly back to killHourEarned -- otherwise a
-- fractional credit is silently created or destroyed on every tick.
function FF.creditTributeFromEarnings(username, killHourEarned)
    killHourEarned = tonumber(killHourEarned) or 0
    if killHourEarned ~= killHourEarned or killHourEarned == math.huge
        or killHourEarned == -math.huge then return 0 end
    if killHourEarned <= 0 then return killHourEarned end
    local name, faction = FF.getFactionOfPlayer(username)
    if not faction then return killHourEarned end
    FF.ensureTribute(faction)
    local rate = math.max(0, math.min(100, tonumber(faction.tribute.ratePercent) or 0))
    if rate <= 0 then return killHourEarned end
    local tributeAmount = roundShopCredits(killHourEarned * rate / 100)
    if tributeAmount <= 0 then return killHourEarned end
    faction.tribute.balance = roundShopCredits(faction.tribute.balance + tributeAmount)
    -- Passive earnings happen for every online member on the Shop credit tick.
    -- Persist the authoritative ModData mutation but fan out only the changed
    -- balance at statsFlushTick; a full registry transmit here was the dominant
    -- steady-state network cost on populated servers.
    tributeDirtyFactions[name] = true
    return killHourEarned - tributeAmount
end

-- Manual contribution (Deposit, for a manageTribute member/owner, or Donate, for
-- anyone) -- both call this; it is the same operation from the treasury's point of
-- view, only the client-side button/label differs. Does write a history row.
function FF.creditTributeDeposit(factionName, amount, actorUsername)
    local faction = FF.getFaction(factionName)
    if not faction then return false end
    FF.ensureTribute(faction)
    amount = tonumber(amount)
    if not amount or amount ~= amount or amount == math.huge or amount == -math.huge
        or amount <= 0 then return false end
    faction.tribute.balance = roundShopCredits(faction.tribute.balance + amount)
    H.appendTributeHistory(faction, "deposit", actorUsername, amount)
    FF.sync()
    return true
end

-- ---------------------------------------------------------------------------
-- Tesouraria upgrade effect: daily interest on the treasury balance.
-- ---------------------------------------------------------------------------
-- 0.1% per level, up to 1% at level 10, applied once every 24 GAME hours
-- (getGameTime():getWorldAgeHours(), the same world-time source
-- workshopProtectionConfirmTick's 1-hour delay already uses) to whatever the
-- balance happens to be at that exact moment -- explicit user spec: "vai ver
-- todos os dias (dias no game) qual o saldo da facção e então aplicar o
-- juro." Deliberately NOT tied to the in-game calendar's actual day-of-month
-- boundary -- a flat 24-hour interval avoids any interaction with sandbox
-- day-length settings or calendar edge cases, the same reasoning
-- FF.VEHICLE_PROTECT_CONFIRM_HOURS already relies on for its own delay.
--
-- faction.tribute.lastInterestAt (game-world hours) is PERSISTED (synced via
-- FF.sync(), not an in-memory-only real-seconds timer like
-- nextProtectConfirmTick/nextGuardTick) specifically so a server restart
-- can't reset or disturb the payout clock -- this moves real treasury
-- balance, unlike the polling-interval constants below, which only gate how
-- OFTEN this function bothers to re-check (a cheap, coarse real-seconds
-- poll; the actual 24-game-hour threshold is what actually matters).
--
-- Catches up on MULTIPLE missed days in one pass (capped) rather than either
-- dropping them or only ever applying one per tick -- if the server was down
-- across a day boundary, each missed day still compounds onto the
-- balance correctly (day 2's interest is computed on top of day 1's
-- payout), and the clock re-anchors off lastAt + 24 each step (not off
-- "now"), so it never drifts later real-time each cycle. Capped at 30
-- iterations purely as a runaway-loop safety net against a corrupted/absurd
-- stored timestamp -- not a real limit under normal play.
local TREASURY_INTEREST_TICK_INTERVAL = 60 -- real seconds; coarse poll, real threshold is 24 game hours
local TREASURY_INTEREST_HOURS = 24
local TREASURY_INTEREST_MAX_CATCHUP_DAYS = 30
local nextTreasuryInterestTick = 0

function H.treasuryInterestTick()
    local now = getTimestamp()
    if now < nextTreasuryInterestTick then return end
    nextTreasuryInterestTick = now + TREASURY_INTEREST_TICK_INTERVAL

    local nowHours = getGameTime():getWorldAgeHours()
    for factionName, faction in pairs(FF.getData().factions) do
        local ok, err = pcall(function()
            local level = FF.upgradeLevel(faction, "treasury")
            local active = level > 0 and FF.upgradesActive(faction)
            FF.ensureTribute(faction)
            local tribute = faction.tribute
            if not active then
                -- Keep the clock from falling behind real elapsed time while
                -- the upgrade is inactive (no level yet, or no active claim
                -- right now) -- upgrade effects pause without an active
                -- claim, the same rule every other LFS upgrade effect
                -- follows, so no catch-up interest should ever accrue for
                -- time spent inactive. Re-anchoring to "now" here means
                -- reactivating later (reclaiming territory) starts counting
                -- fresh instead of paying out a large backlog for the whole
                -- inactive stretch.
                tribute.lastInterestAt = nowHours
                return
            end
            if not tribute.lastInterestAt then
                -- First time this faction's ever been seen with the upgrade
                -- active (fresh faction, or an existing one that just now
                -- reached level 1, or a save that predates this feature) --
                -- start the clock here rather than immediately paying out,
                -- so nobody gets a "free" instant payout just from crossing
                -- the level-1 threshold or from this feature's own rollout.
                tribute.lastInterestAt = nowHours
                return
            end
            local ratePercent = level * 0.1
            local paidAny = false
            local iterations = 0
            while nowHours - tribute.lastInterestAt >= TREASURY_INTEREST_HOURS
                and iterations < TREASURY_INTEREST_MAX_CATCHUP_DAYS do
                iterations = iterations + 1
                local interest = roundShopCredits(tribute.balance * ratePercent / 100)
                tribute.balance = roundShopCredits(tribute.balance + interest)
                tribute.lastInterestAt = tribute.lastInterestAt + TREASURY_INTEREST_HOURS
                -- "Rendimento das ÚLTIMAS 24 horas" is meant to read as the
                -- most recent single day's payout, not a multi-day catch-up
                -- sum -- each loop pass overwrites this with just that pass's
                -- own amount, so it always ends on the latest day's figure.
                tribute.lastInterestAmount = interest
                paidAny = true
            end
            if paidAny then FF.sync() end
        end)
        if not ok then
            FF.warn("treasury interest: faction " .. tostring(factionName) .. " failed: " .. tostring(err))
        end
    end
end
FF._replaceServerHook(Events.OnTick, "_serverTreasuryInterestTick", H.treasuryInterestTick)

-- Owner-only, same 2-arg admin-override form as its Settings-tab siblings
-- (setFactionColor/setFactionOption). Never trusts the client's raw slider value.
Handlers.setFactionTributeRate = function(player, args)
    local name, faction = ownerFaction(player, args)
    if not faction then return end
    FF.ensureTribute(faction)
    local rate = tonumber(args and args.value)
    if not rate or rate ~= rate or rate == math.huge or rate == -math.huge then
        return notify(player, "tribute_invalid_amount")
    end
    faction.tribute.ratePercent = math.floor(math.max(0, math.min(100, rate)))
    FF.sync()
    notify(player, "faction_updated")
end

-- Shared by Handlers.depositTribute (manager/owner) and Handlers.donateTribute
-- (any member) -- confirmed to be the same operation; only which button the
-- client shows differs. No permission beyond "is a member of a faction".
-- Sequencing matters: debit the player's Shop balance FIRST, only credit the
-- treasury if that succeeds, so there is no window where credits vanish or
-- double-apply.
function H.handleTributeContribute(player, args)
    local username = player:getUsername()
    local requestId = args and args.requestId
    if type(requestId) ~= "string" or requestId == "" or #requestId > 80 then
        return notify(player, "tribute_invalid_request", nil, nil,
            type(requestId) == "string" and requestId or nil)
    end
    local name, faction = FF.getFactionOfPlayer(username)
    if not faction then return notify(player, "not_in_faction", nil, nil, requestId) end
    FF.ensureTribute(faction)

    local cache = H.tributeCacheFor(username)
    local cacheKey = "contribute|" .. requestId
    local previous = cache.recentResults[cacheKey]
    if previous then
        local key = previous.status == "processing" and "tribute_request_processing" or previous.key
        return notify(player, key or "tribute_invalid_request", previous.extra, nil, requestId)
    end

    local amount = tonumber(args and args.amount)
    if not amount or amount ~= amount or amount <= 0 or amount > 1000000 then
        rememberTributeRequest(cache, cacheKey, "tribute_invalid_amount")
        return notify(player, "tribute_invalid_amount", nil, nil, requestId)
    end
    amount = roundShopCredits(amount)

    local LS = _G.LasciviousShop
    if not (LS and type(LS.spendCredits) == "function") then
        return notify(player, "tribute_shop_unavailable", nil, nil, requestId)
    end
    if not FF._beginTributeRequest(cache, cacheKey, "contribute", name, amount) then
        return notify(player, "tribute_request_processing", nil, nil, requestId)
    end
    local callOk, ok, reason = pcall(LS.spendCredits, username, amount, "faction_tribute_deposit")
    if not callOk then
        -- spendCredits may have debited before throwing. Leave the processing marker
        -- untouched; retrying is more dangerous than asking an admin to reconcile.
        FF.warn("tribute deposit became ambiguous after Shop spendCredits error for "
            .. tostring(username) .. ": " .. tostring(ok))
        return notify(player, "tribute_request_processing", nil, nil, requestId)
    end
    if not ok then
        local key = reason == "insufficient_credits" and "tribute_insufficient_player_funds" or "tribute_invalid_amount"
        rememberTributeRequest(cache, cacheKey, key)
        return notify(player, key, nil, nil, requestId)
    end

    FF.creditTributeDeposit(name, amount, username)
    rememberTributeRequest(cache, cacheKey, "tribute_deposited", tostring(amount))
    notify(player, "tribute_deposited", tostring(amount), nil, requestId)
end
Handlers.depositTribute = H.handleTributeContribute
Handlers.donateTribute = H.handleTributeContribute

-- Gated on the manageTribute role permission (owner always passes via FF.roleCan).
Handlers.withdrawTribute = function(player, args)
    local username = player:getUsername()
    local requestId = args and args.requestId
    if type(requestId) ~= "string" or requestId == "" or #requestId > 80 then
        return notify(player, "tribute_invalid_request", nil, nil,
            type(requestId) == "string" and requestId or nil)
    end
    local name, faction = FF.getFactionOfPlayer(username)
    if not faction then return notify(player, "not_in_faction", nil, nil, requestId) end
    FF.ensureTribute(faction)
    if not FF.roleCan(faction, username, "manageTribute") then
        return notify(player, "not_authorised", nil, nil, requestId)
    end

    local cache = H.tributeCacheFor(username)
    local cacheKey = "withdraw|" .. requestId
    local previous = cache.recentResults[cacheKey]
    if previous then
        local key = previous.status == "processing" and "tribute_request_processing" or previous.key
        return notify(player, key or "tribute_invalid_request", previous.extra, nil, requestId)
    end

    local amount = tonumber(args and args.amount)
    if not amount or amount ~= amount or amount <= 0 or amount > 1000000 then
        rememberTributeRequest(cache, cacheKey, "tribute_invalid_amount")
        return notify(player, "tribute_invalid_amount", nil, nil, requestId)
    end
    amount = roundShopCredits(amount)

    if (tonumber(faction.tribute.balance) or 0) + 0.0001 < amount then
        rememberTributeRequest(cache, cacheKey, "tribute_insufficient_faction_funds")
        return notify(player, "tribute_insufficient_faction_funds", nil, nil, requestId)
    end

    -- Reserve on the treasury side first (mirrors Shop's own purchase flow), then
    -- refund it if the grant somehow fails -- never let a withdrawal both clear the
    -- treasury AND fail to pay out.
    local LS = _G.LasciviousShop
    if not (LS and type(LS.grantCredits) == "function") then
        return notify(player, "tribute_shop_unavailable", nil, nil, requestId)
    end
    if not FF._beginTributeRequest(cache, cacheKey, "withdraw", name, amount) then
        return notify(player, "tribute_request_processing", nil, nil, requestId)
    end
    faction.tribute.balance = roundShopCredits(faction.tribute.balance - amount)
    local callOk, granted = pcall(LS.grantCredits, username, amount, "faction_tribute_withdraw")
    if not callOk then
        -- grantCredits may have paid before throwing. Do not restore the treasury:
        -- that could duplicate value. Preserve both the reservation and processing
        -- marker for explicit admin reconciliation.
        FF.warn("tribute withdrawal became ambiguous after Shop grantCredits error for "
            .. tostring(username) .. ": " .. tostring(granted))
        FF.sync()
        return notify(player, "tribute_request_processing", nil, nil, requestId)
    end
    if not granted then
        faction.tribute.balance = roundShopCredits(faction.tribute.balance + amount)
        rememberTributeRequest(cache, cacheKey, "tribute_withdraw_failed")
        return notify(player, "tribute_withdraw_failed", nil, nil, requestId)
    end
    H.appendTributeHistory(faction, "withdraw", username, amount)
    rememberTributeRequest(cache, cacheKey, "tribute_withdrawn", tostring(amount))
    FF.sync()
    notify(player, "tribute_withdrawn", tostring(amount), nil, requestId)
end

-- ---------------------------------------------------------------------------
-- Faction upgrades ("Aprimoramentos")
-- ---------------------------------------------------------------------------
-- Owner-only (or admin via args.faction, same as every other ownerFaction()
-- handler): spend exactly one upgrade point to raise one track by one level.
-- No amount field, so there is nothing for a double-fire to corrupt -- a second
-- call either spends a second available point (correct) or fails the same
-- guard the first call would have.
Handlers.allocateUpgradePoint = function(player, args)
    local name, faction = ownerFaction(player, args)
    if not faction then return end
    FF.ensureUpgrades(faction)
    local u = faction.upgrades

    local def = FF.upgradeTypeDef(args and args.upgrade)
    if not def then return notify(player, "upgrade_invalid_type") end

    local level = FF.upgradeLevel(faction, def.key)
    if level >= def.maxLevel then return notify(player, "upgrade_maxed") end
    if (tonumber(u.points) or 0) <= 0 then return notify(player, "upgrade_no_points") end

    u.points = u.points - 1
    u.levels[def.key] = level + 1
    FF.sync()
    notify(player, "upgrade_allocated", def.labelFallback, tostring(level + 1))
end

-- ---------------------------------------------------------------------------
-- Debug tools ("Debug" panel section) -- test actions for the mod author's own
-- testing, never part of normal play. New debug actions belong here as they're
-- added.
-- ---------------------------------------------------------------------------
-- Gated on FF.getOptions().debugToolsEnabled (true singleplayer + the Debug
-- sandbox flag, see LFS_Shared.lua) rather than adminHandler(...): singleplayer
-- has no real admin access level to check against, and gating on singleplayer
-- directly makes that a non-issue instead of something to work around (the
-- previous DEV_OVERRIDE hand-toggled constant existed only to bypass the admin
-- check locally during testing -- no longer needed, this is never true in real
-- MP regardless of what Debug is set to).
Handlers.debugAddPower = function(player, args)
    if not FF.getOptions().debugToolsEnabled then
        return notify(player, "debug_tools_disabled")
    end
    if not isAdminPlayer(player) then return notify(player, "not_authorised") end
    local username = FF.identityUsername(player)
    local name, faction = FF.getFactionOfPlayer(username)
    if not faction then return notify(player, "not_in_faction") end
    faction.debugPowerBonus = (tonumber(faction.debugPowerBonus) or 0) + 100
    FF.sync()
    notify(player, "debug_power_added", "100")
end

-- Owner sets open vs invite-only.
Handlers.setJoinMode = function(player, args)
    local name, faction = ownerFaction(player, args)
    if not faction then return end
    faction.joinMode = "closed"
    FF.sync()
    notify(player, "faction_updated")
end

-- ---------------------------------------------------------------------------
-- Invites (a manageMembers member invites; the target accepts via join)
-- ---------------------------------------------------------------------------
Handlers.invite = function(player, args)
    local username = FF.identityUsername(player)
    local name, faction = FF.getFactionOfPlayer(username)
    if not faction then return notify(player, "not_in_faction") end
    FF.ensureRoles(faction)
    if not FF.roleCan(faction, username, "manageMembers") then return notify(player, "not_authorised") end

    local target = args and args.username
    if type(target) ~= "string" or target == "" then return notify(player, "no_such_member") end
    if faction.members[target] then return notify(player, "already_member") end
    local data = FF.getData()
    local targetPlayer = H.findOnlinePlayer(target)
    if not targetPlayer then return notify(player, "invite_player_offline") end
    if data.playerIndex[target] then return notify(player, "invite_target_has_faction") end

    -- Don't invite into a faction that is already at the member cap.
    local cap = FF.getOptions().maxMembersPerFaction
    if cap > 0 and FF.memberCount(faction) >= cap then
        return notify(player, "member_cap_reached")
    end

    local remaining = H.inviteCooldownRemaining(name, target)
    if remaining > 0 then return notify(player, "invite_cooldown", remaining) end

    faction.invites = faction.invites or {}
    if faction.invites[target] then return notify(player, "invite_pending", target) end
    faction.invites[target] = {
        at = nowSeconds(),
        inviter = username,
    }
    FF.sync()
    notify(player, "invite_sent", target)
    H.sendInvitePopup(targetPlayer, name, username)
end

Handlers.revokeInvite = function(player, args)
    local username = FF.identityUsername(player)
    local name, faction = FF.getFactionOfPlayer(username)
    if not faction then return notify(player, "not_in_faction") end
    FF.ensureRoles(faction)
    if not FF.roleCan(faction, username, "manageMembers") then return notify(player, "not_authorised") end

    local target = args and args.username
    if faction.invites and target then faction.invites[target] = nil end
    FF.sync()
    notify(player, "invite_revoked", target)
end

-- The invited player clears their own pending invite from a faction.
Handlers.declineInvite = function(player, args)
    local username = FF.identityUsername(player)
    local name = args and args.name
    local faction = name and FF.getFaction(name)
    local invite = faction and faction.invites and faction.invites[username]
    if not invite then return end
    faction.invites[username] = nil

    local old, bucket = H.inviteCooldownRecord(name, username, true)
    local declines = math.max(0, tonumber(old and old.declines) or 0) + 1
    local delay = INVITE_DECLINE_DELAYS[math.min(declines, #INVITE_DECLINE_DELAYS)]
    bucket[username] = {
        declines = declines,
        lastDeclinedAt = nowSeconds(),
        untilAt = nowSeconds() + delay,
    }
    FF.sync()
    notify(player, "invite_declined")
    local inviter = type(invite) == "table" and invite.inviter or nil
    local inviterPlayer = inviter and H.findOnlinePlayer(inviter) or nil
    if inviterPlayer then notify(inviterPlayer, "invite_declined_by", username) end
end

FF.checkpoint("membership & roles handlers ready")

-- ---------------------------------------------------------------------------
-- Faction relationships (ally requires accept; enemy is unilateral). Owner-only.
-- ---------------------------------------------------------------------------
-- Re-push SEVERAL factions' zones in one PhunZones saveChanges instead of one
-- each. Every PhunZones projection is a synchronous whole-file disk write + full
-- zone-pipeline rebuild, so an operation that touches 2+ zones (any relationship
-- change, a war settlement, a membership sync with allies) must batch them or it
-- stalls the server main thread -- the "server too busy" watchdog trip. `list`
-- is an array of { name, faction }; Claims.projectFactions filters out any with no
-- claim. Passing one entry is fine (it collapses to a single projection).
local function reprojectZones(list)
    if not (list and #list > 0) then return end
    Claims.projectFactions(list)
    -- Every relationship change funnels through here (alliances, wars, pacts,
    -- coalitions, admin overrides), and an area opened to allies embeds the ally's
    -- roster in this faction's SAFEHOUSE as well as its zone. The safehouse is a
    -- separate mechanism the projection above does not touch, so refresh it here
    -- rather than at each of the dozen call sites. No-op for anyone without an
    -- ally-level area, which is almost everyone.
    for _, item in ipairs(list) do
        if item.faction and H.hasAllyLootArea(item.faction) then
            rebuildFactionSafehouses(item.faction)
        end
    end
end

local function formAlliance(nameA, factionA, nameB, factionB)
    factionA.relations = factionA.relations or {}
    factionB.relations = factionB.relations or {}
    factionA.relations[nameB] = "ally"
    factionB.relations[nameA] = "ally"
    if factionA.allyRequests then factionA.allyRequests[nameB] = nil end
    if factionB.allyRequests then factionB.allyRequests[nameA] = nil end
    -- Both zones' share sets change -> re-push them to clients in ONE projection.
    reprojectZones({ { name = nameA, faction = factionA }, { name = nameB, faction = factionB } })
    broadcastEvent("alliance_formed", { nameA, nameB })
end

Handlers.allyRequest = function(player, args)
    local name, faction = ownerFaction(player)
    if not faction then return end
    local target = args and args.target
    if not target or target == name then return end
    local tf = FF.getFaction(target)
    if not tf then return notify(player, "no_such_faction") end
    if FF.areAllied(name, target) then return end
    -- Reciprocal request already pending from the target -> ally immediately.
    if faction.allyRequests and faction.allyRequests[target] then
        formAlliance(name, faction, target, tf)
        FF.sync()
        notifyFaction(name, "ally_formed", target)
        notifyFaction(target, "ally_formed", name)
        return
    end
    tf.allyRequests = tf.allyRequests or {}
    tf.allyRequests[name] = true
    FF.sync()
    notify(player, "ally_request_sent", target)
    notifyFaction(target, "ally_requested", name)
end

Handlers.allyRespond = function(player, args)
    local name, faction = ownerFaction(player)
    if not faction then return end
    local other = args and args.other
    if not (other and faction.allyRequests and faction.allyRequests[other]) then return end
    if args.accept == true then
        local of = FF.getFaction(other)
        if not of then faction.allyRequests[other] = nil; FF.sync(); return end
        formAlliance(name, faction, other, of)
        FF.sync()
        notifyFaction(name, "ally_formed", other)
        notifyFaction(other, "ally_formed", name)
    else
        faction.allyRequests[other] = nil
        FF.sync()
        notify(player, "ally_declined")
    end
end

Handlers.allyCancel = function(player, args)
    local name, faction = ownerFaction(player)
    if not faction then return end
    local target = args and args.target
    local tf = target and FF.getFaction(target)
    if tf and tf.allyRequests then tf.allyRequests[name] = nil; FF.sync() end
end

Handlers.allyBreak = function(player, args)
    local name, faction = ownerFaction(player)
    if not faction then return end
    local other = args and args.other
    local of = other and FF.getFaction(other)
    if faction.relations then faction.relations[other] = nil end
    if of and of.relations then of.relations[name] = nil end
    reprojectZones({ { name = name, faction = faction }, { name = other, faction = of } })
    FF.sync()
    notifyFaction(name, "ally_broken", other)
    if of then notifyFaction(other, "ally_broken", name) end
end

Handlers.setEnemy = function(player, args)
    local name, faction = ownerFaction(player)
    if not faction then return end
    local target = args and args.target
    if not target or target == name then return end
    faction.relations = faction.relations or {}
    if args.on == true then
        local reproj = {}
        -- Break any alliance first (it's mutual), then mark them our enemy.
        if faction.relations[target] == "ally" then
            local tf = FF.getFaction(target)
            if tf and tf.relations then tf.relations[name] = nil end
            reproj[#reproj + 1] = { name = target, faction = tf }
        end
        faction.relations[target] = "enemy"
        reproj[#reproj + 1] = { name = name, faction = faction }
        reprojectZones(reproj)
        FF.sync()
        notify(player, "enemy_declared", target)
        broadcastEvent("war_declared", { name, target })
    elseif faction.relations[target] == "enemy" then
        faction.relations[target] = nil
        FF.sync()
        notify(player, "relation_cleared")
    end
end

-- ---------------------------------------------------------------------------
-- Wars
-- ---------------------------------------------------------------------------
-- A formal war deepens the enemy relation: declaring sets both factions enemy and
-- opens data.wars[key] = { a, b, declaredAt, target, score={[name]=n} }. War score
-- accrues from raids won and kills against the enemy; the first side to
-- WarScoreTarget wins, relations reset to neutral, and a ceasefire
-- (data.ceasefires[key]) blocks re-declaration for WarCeasefireHours. Disband/decay
-- of a party dissolves the war.

-- Which side of a war a faction fights on: "a"/"b" for a principal or a coalition
-- member, else nil (not involved).
local function warSideOf(war, faction)
    if war.a == faction then return "a" end
    if war.b == faction then return "b" end
    return war.coalition and war.coalition[faction] or nil
end

-- Undo the enemy relations a coalition member holds toward the opposing principal
-- (joinWar set only that one). Used when a war ends. A coalition member's zone needs
-- re-projecting (its relations changed); rather than project each inline -- one heavy
-- PhunZones rebuild per member -- it appends { name, faction } to `acc` so settleWar
-- can project the whole settlement (principals + coalition) in a single batch.
function H.clearCoalitionRelations(war, acc)
    if not war.coalition then return end
    for member, side in pairs(war.coalition) do
        local opp = (side == "a") and war.b or war.a
        local mf, of = FF.getFaction(member), FF.getFaction(opp)
        if mf and mf.relations then
            mf.relations[opp] = nil
            if acc then acc[#acc + 1] = { name = member, faction = mf } end
        end
        if of and of.relations then of.relations[member] = nil end
    end
end

-- Settle a war. reason: "victory" (winner reached target), "surrender" (loser
-- conceded), or "dissolved" (a party vanished -> no ceasefire).
local function settleWar(key, war, winner, loser, reason)
    local data = FF.getData()
    local opts = FF.getOptions()
    local wf, lf = FF.getFaction(winner), FF.getFaction(loser)
    -- Clear the mutual enemy relations the war set (principals + coalition members),
    -- then re-project every affected zone in ONE batch. Previously this was 2 + N
    -- separate PhunZones rebuilds (winner, loser, and one per coalition member) fired
    -- back-to-back on the main thread -- the biggest single source of the stall.
    if wf and wf.relations then wf.relations[loser] = nil end
    if lf and lf.relations then lf.relations[winner] = nil end
    local reproj = {}
    if wf then reproj[#reproj + 1] = { name = winner, faction = wf } end
    if lf then reproj[#reproj + 1] = { name = loser, faction = lf } end
    H.clearCoalitionRelations(war, reproj)
    reprojectZones(reproj)
    data.wars[key] = nil
    if reason ~= "dissolved" and (opts.warCeasefireHours or 0) > 0 then
        data.ceasefires[key] = nowMs() + opts.warCeasefireHours * 3600 * 1000
    end
    FF.sync()
    if reason == "dissolved" then
        broadcastEvent("war_dissolved", { war.a, war.b })
    else
        broadcastEvent("war_won", { winner, loser })
        notifyFaction(winner, "war_victory", loser)
        notifyFaction(loser, "war_defeat", winner)
    end
end

-- The active war (if any) in which `scorer` and `victim` fight on OPPOSING sides,
-- with the side `scorer` is on. Resolves principals and coalition members alike, so a
-- coalition member's raids/captures/kills count toward the shared war.
function H.warSideContext(scorer, victim)
    for key, war in pairs(FF.getData().wars) do
        local ss = warSideOf(war, scorer)
        local vs = warSideOf(war, victim)
        if ss and vs and ss ~= vs then return key, war, ss end
    end
    return nil
end

-- Credit war score for `myName` against `otherName` when they are on opposing sides of
-- a war. Coalition contributions accrue to the side's PRINCIPAL, and the win check is on
-- the principal's total. Exposed so the earlier raid teardown can reach it.
local function addWarScore(myName, otherName, pts)
    if not (myName and otherName and pts and pts ~= 0) then return end
    if not FF.getOptions().warsEnabled then return end
    local key, war, side = H.warSideContext(myName, otherName)
    if not war then return end
    local principal = (side == "a") and war.a or war.b
    war.score = war.score or {}
    war.score[principal] = (war.score[principal] or 0) + pts
    if war.score[principal] >= (war.target or 0) then
        local loser = (side == "a") and war.b or war.a
        settleWar(key, war, principal, loser, "victory")
    else
        FF.sync()
    end
end
FF.addWarScore = addWarScore

-- Disband/decay: dissolve wars where `name` is a principal without creating a ceasefire, and
-- strip `name` from any war it merely joined as a coalition member (that war continues).
local function dissolveWarsFor(name)
    local data = FF.getData()
    local removed = {}
    for key, war in pairs(data.wars) do
        if war.a == name or war.b == name then
            removed[#removed + 1] = key
        elseif war.coalition and war.coalition[name] then
            war.coalition[name] = nil   -- a coalition member left; the war goes on
        end
    end
    local reproj = {}
    for _, key in ipairs(removed) do
        local war = data.wars[key]
        H.clearCoalitionRelations(war, reproj)   -- accumulate; one batch below
        data.wars[key] = nil
        broadcastEvent("war_dissolved", { war.a, war.b })
    end
    reprojectZones(reproj)
    return #removed > 0
end
FF.dissolveWarsFor = dissolveWarsFor

Handlers.declareWar = function(player, args)
    local opts = FF.getOptions()
    if not opts.warsEnabled then return notify(player, "wars_disabled") end
    local name, faction = ownerFaction(player)
    if not faction then return end
    local target = args and args.target
    if not target or target == name then return end
    local tf = FF.getFaction(target)
    if not tf then return notify(player, "no_such_faction") end
    if FF.areAllied(name, target) then return notify(player, "war_rejected_ally") end
    if FF.pactActive(name, target, nowMs()) then return notify(player, "war_rejected_pact") end
    local data = FF.getData()
    local key = FF.warKey(name, target)
    if data.wars[key] then return notify(player, "war_rejected_active") end
    local cf = data.ceasefires[key]
    if cf then
        if nowMs() < cf then return notify(player, "war_rejected_ceasefire") end
        data.ceasefires[key] = nil   -- lapsed -> clean up lazily
    end
    -- War is mutual (unlike one-sided setEnemy): both sides become enemies.
    faction.relations = faction.relations or {}
    tf.relations = tf.relations or {}
    faction.relations[target] = "enemy"
    tf.relations[name] = "enemy"
    reprojectZones({ { name = name, faction = faction }, { name = target, faction = tf } })
    data.wars[key] = { a = name, b = target, declaredAt = nowMs(), target = opts.warScoreTarget, score = {} }
    FF.sync()
    broadcastEvent("war_declared", { name, target })
end

Handlers.surrenderWar = function(player, args)
    local name, faction = ownerFaction(player)
    if not faction then return end
    local target = args and args.target
    if not target then return end
    local key = FF.warKey(name, target)
    local war = key and FF.getData().wars[key]
    if not war then return notify(player, "war_none") end
    settleWar(key, war, target, name, "surrender")   -- opponent wins
end

-- Coalitions: join an ally's war against `target` (a principal of an active war whose
-- OTHER principal is an ally of ours). We fight on the ally's side; our raids/captures/
-- kills against `target`'s side then feed the shared war score (accrued to the ally
-- principal). Sets us enemy of `target` so those actions register.
Handlers.joinWar = function(player, args)
    local opts = FF.getOptions()
    if not opts.warsEnabled then return notify(player, "wars_disabled") end
    local name, faction = ownerFaction(player)
    if not faction then return end
    local target = args and args.target
    if not target or target == name then return end
    if FF.areAllied(name, target) then return notify(player, "coalition_ally_target") end
    -- Find a war where `target` is a principal and we're allied to the other principal.
    local data = FF.getData()
    for _, war in pairs(data.wars) do
        local side = (war.a == target and "a") or (war.b == target and "b") or nil
        if side then
            if warSideOf(war, name) then return notify(player, "coalition_already") end
            local allySide = (side == "a") and "b" or "a"
            local allyPrincipal = (allySide == "a") and war.a or war.b
            if not FF.areAllied(name, allyPrincipal) then return notify(player, "coalition_not_ally") end
            if FF.pactActive(name, target, nowMs()) then return notify(player, "coalition_pact") end
            war.coalition = war.coalition or {}
            war.coalition[name] = allySide
            local tf = FF.getFaction(target)
            faction.relations = faction.relations or {}
            faction.relations[target] = "enemy"
            local reproj = { { name = name, faction = faction } }
            if tf then
                tf.relations = tf.relations or {}; tf.relations[name] = "enemy"
                reproj[#reproj + 1] = { name = target, faction = tf }
            end
            reprojectZones(reproj)
            FF.sync()
            notifyFaction(name, "coalition_joined_self", target)
            broadcastEvent("coalition_joined", { name, allyPrincipal, target })
            return
        end
    end
    notify(player, "coalition_no_war")
end

-- Leave a war we joined as a coalition member against `target`.
Handlers.leaveWar = function(player, args)
    local name, faction = ownerFaction(player)
    if not faction then return end
    local target = args and args.target
    if not target then return end
    local data = FF.getData()
    for _, war in pairs(data.wars) do
        local side = (war.a == target and "a") or (war.b == target and "b") or nil
        if side and war.coalition and war.coalition[name] then
            war.coalition[name] = nil
            local tf = FF.getFaction(target)
            if faction.relations then faction.relations[target] = nil end
            local reproj = { { name = name, faction = faction } }
            if tf and tf.relations then
                tf.relations[name] = nil
                reproj[#reproj + 1] = { name = target, faction = tf }
            end
            reprojectZones(reproj)
            FF.sync()
            broadcastEvent("coalition_left", { name, target })
            return
        end
    end
end

-- War dev levers: list wars/ceasefires, end a war, or add war score.
Handlers.adminWar = adminHandler(function(player, args)
    local sub = (args and args.sub or "list"):lower()
    local data = FF.getData()
    if sub == "end" then
        local key = FF.warKey(args.a, args.b)
        local war = key and data.wars[key]
        if not war then return notify(player, "Admin: no war between those factions.") end
        settleWar(key, war, war.a, war.b, "dissolved")
        notify(player, "Admin: war ended.")
    elseif sub == "score" then
        local n = tonumber(args.n)
        local key = FF.warKey(args.a, args.b)
        local war = key and data.wars[key]
        if not war then return notify(player, "Admin: no war between those factions.") end
        if not n then return notify(player, "Admin: score needs a number.") end
        addWarScore(args.a, args.b, n)   -- may settle if it crosses the target
        notify(player, string.format("Admin: +%d war score for %s vs %s.", n, tostring(args.a), tostring(args.b)))
    else
        local lines = {}
        for _, war in pairs(data.wars) do
            local coA, coB = {}, {}
            for member, side in pairs(war.coalition or {}) do
                table.insert(side == "a" and coA or coB, member)
            end
            table.sort(coA); table.sort(coB)
            local extra = ""
            if #coA > 0 or #coB > 0 then
                extra = string.format("  [%s | %s]",
                    #coA > 0 and table.concat(coA, ",") or "-", #coB > 0 and table.concat(coB, ",") or "-")
            end
            lines[#lines + 1] = string.format("%s vs %s: %d - %d (target %d)%s", war.a, war.b,
                (war.score and war.score[war.a]) or 0, (war.score and war.score[war.b]) or 0, war.target or 0, extra)
        end
        local ms = nowMs()
        for key, exp in pairs(data.ceasefires) do
            local left = exp - ms
            if left > 0 then lines[#lines + 1] = string.format("ceasefire %s: %dh left", key, math.floor(left / 3600000)) end
        end
        table.sort(lines)
        if #lines == 0 then lines = { "No active wars or ceasefires." } end
        sendReport(player, lines)
    end
end)

-- ---------------------------------------------------------------------------
-- Non-aggression pacts
-- ---------------------------------------------------------------------------
-- A mutual pact (proposed by one owner, accepted by the other) blocks war declaration
-- AND raids between the two factions while active. Stored as data.pacts[key] =
-- { a, b, expiresAt }; pending proposals ride faction.pactRequests[other], mirroring
-- alliance requests. Optional term via PactTermDays (0 = indefinite until broken).
local PACT_DAY_MS = 86400 * 1000

-- Normalise a proposed contract (from client args, or a stored pending proposal) into
-- the shape kept on the pact record. Duration falls back to the server PactTermDays
-- default when the proposer didn't pick one; a legacy `true` proposal yields defaults.
function H.sanitizePactContract(opts, raw)
    if type(raw) ~= "table" then raw = {} end
    local durationDays = tonumber(raw.durationDays)
    if durationDays == nil then durationDays = opts.pactTermDays or 0 end
    durationDays = math.max(0, math.min(3650, math.floor(durationDays)))
    -- Clauses may arrive nested under `terms` (stored form) or flat (client args).
    local rt = (type(raw.terms) == "table") and raw.terms or raw
    local terms = {}
    if rt.shareMap == true then terms.shareMap = true end
    if rt.shareLocations == true then terms.shareLocations = true end
    return { durationDays = durationDays, terms = terms }
end

function H.formPact(nameA, factionA, nameB, factionB, opts, contract)
    local data = FF.getData()
    contract = H.sanitizePactContract(opts, contract)
    local expiresAt = contract.durationDays > 0
        and (nowMs() + contract.durationDays * PACT_DAY_MS) or 0
    data.pacts[FF.warKey(nameA, nameB)] = {
        a = nameA, b = nameB,
        expiresAt = expiresAt,
        createdAt = nowMs(),
        durationDays = contract.durationDays,
        terms = contract.terms,
    }
    if factionA.pactRequests then factionA.pactRequests[nameB] = nil end
    if factionB.pactRequests then factionB.pactRequests[nameA] = nil end
    -- A share-map clause changes both factions' claim-visibility set -> re-push zones (one batch).
    reprojectZones({ { name = nameA, faction = factionA }, { name = nameB, faction = factionB } })
    FF.sync()
    notifyFaction(nameA, "pact_formed", nameB)
    notifyFaction(nameB, "pact_formed", nameA)
    broadcastEvent("pact_formed_global", { nameA, nameB })
end

-- Drop every pact touching `name` (disband/decay). Records store a/b explicitly, so no
-- key parsing. Exposed for the earlier-defined teardown paths to reach at runtime.
local function clearPactsFor(name)
    local pacts = FF.getData().pacts
    if not pacts then return end
    for key, p in pairs(pacts) do
        if p.a == name or p.b == name then pacts[key] = nil end
    end
end
FF.clearPactsFor = clearPactsFor

Handlers.proposePact = function(player, args)
    local opts = FF.getOptions()
    if not opts.pactsEnabled then return notify(player, "pacts_disabled") end
    local name, faction = ownerFaction(player)
    if not faction then return end
    local target = args and args.target
    if not target or target == name then return end
    local tf = FF.getFaction(target)
    if not tf then return notify(player, "no_such_faction") end
    if FF.pactActive(name, target, nowMs()) then return notify(player, "pact_exists") end
    -- A pact with someone you're at war with or hold as an enemy is contradictory.
    if FF.warBetween(name, target)
        or (faction.relations and faction.relations[target] == "enemy")
        or (tf.relations and tf.relations[name] == "enemy") then
        return notify(player, "pact_rejected_hostile")
    end
    local contract = H.sanitizePactContract(opts, args)
    -- Reciprocal proposal already pending -> form immediately on the EARLIER proposer's
    -- terms (this player accepts them by proposing back).
    if faction.pactRequests and faction.pactRequests[target] then
        H.formPact(name, faction, target, tf, opts, faction.pactRequests[target])
        return
    end
    tf.pactRequests = tf.pactRequests or {}
    tf.pactRequests[name] = contract   -- store the full offered contract, not just a flag
    FF.sync()
    notify(player, "pact_proposed", target)
    notifyFaction(target, "pact_incoming", name)
end

Handlers.respondPact = function(player, args)
    local name, faction = ownerFaction(player)
    if not faction then return end
    local other = args and args.other
    if not (other and faction.pactRequests and faction.pactRequests[other]) then return end
    if args.accept == true then
        local of = FF.getFaction(other)
        if not of then faction.pactRequests[other] = nil; FF.sync(); return end
        H.formPact(name, faction, other, of, FF.getOptions(), faction.pactRequests[other])
    else
        faction.pactRequests[other] = nil
        FF.sync()
        notify(player, "pact_declined")
    end
end

Handlers.cancelPact = function(player, args)
    local name, faction = ownerFaction(player)
    if not faction then return end
    local target = args and args.target
    local tf = target and FF.getFaction(target)
    if tf and tf.pactRequests then tf.pactRequests[name] = nil; FF.sync() end
end

Handlers.breakPact = function(player, args)
    local name, faction = ownerFaction(player)
    if not faction then return end
    local target = args and args.target
    if not target then return end
    local key = FF.warKey(name, target)
    local pact = FF.getData().pacts[key]
    if not pact then return notify(player, "pact_none") end
    local tf = FF.getFaction(target)
    FF.getData().pacts[key] = nil

    -- A share-map clause changes the visibility set -> re-push both zones (one batch).
    reprojectZones({ { name = name, faction = faction }, { name = target, faction = tf } })
    FF.sync()
    notifyFaction(name, "pact_broken_self", target)
    notifyFaction(target, "pact_broken_by", name)
    broadcastEvent("pact_broken_global", { name, target })
end

-- Pact dev lever: list active pacts, or clear one.
Handlers.adminPact = adminHandler(function(player, args)
    local sub = (args and args.sub or "list"):lower()
    local data = FF.getData()
    if sub == "clear" then
        local key = FF.warKey(args.a, args.b)
        if not (key and data.pacts[key]) then return notify(player, "Admin: no pact between those factions.") end
        data.pacts[key] = nil
        FF.sync()
        notify(player, "Admin: pact cleared.")
    else
        local ms = nowMs()
        local lines = {}
        for _, p in pairs(data.pacts) do
            local term = (p.expiresAt or 0) == 0 and "indefinite"
                or string.format("%dh left", math.max(0, math.floor((p.expiresAt - ms) / 3600000)))
            local clauses = {}
            if p.terms and p.terms.shareMap then clauses[#clauses + 1] = "map" end
            if p.terms and p.terms.shareLocations then clauses[#clauses + 1] = "locations" end
            local extra = string.format("%s%s", term,
                #clauses > 0 and ("; shares " .. table.concat(clauses, "+")) or "")
            lines[#lines + 1] = string.format("%s <-> %s (%s)", p.a, p.b, extra)
        end
        table.sort(lines)
        if #lines == 0 then lines = { "No active pacts." } end
        sendReport(player, lines)
    end
end)

-- Faction chat: fan a member's /f message out to every online member of their
-- faction (and no one else). Purely transient -- nothing is persisted or synced.
Handlers.factionChat = function(player, args)
    if not FF.getOptions().factionChatEnabled then return end
    local username = FF.identityUsername(player)
    local name, faction = FF.getFactionOfPlayer(username)
    if not faction then return notify(player, "not_in_faction") end
    local text = safeDisplayText(args and args.text, 256)
    if text == "" then return end
    local tag = faction.tag or name
    forEachOnlineMemberOf(name, function(p)
        sendServerCommand(p, FF.MODULE, "factionChatMsg",
            { faction = name, tag = tag, author = username, text = text })
    end)
end

Handlers.claim = function(player, args)
    local username = FF.identityUsername(player)
    local name, faction = FF.getFactionOfPlayer(username)
    if not faction then return notify(player, "not_in_faction") end
    FF.ensureRoles(faction)
    if not FF.roleCan(faction, username, "claim") then return notify(player, "not_authorised") end

    -- args comes straight off the wire with no schema, so coerce rather than trust:
    -- FF.normaliseRect carries access/grants through, and FF.sanitiseArea forces
    -- anything unrecognised back to a private area granting nothing. A malformed
    -- payload must never be able to open land it wasn't meant to.
    local payload = args and args.rects
    if type(payload) ~= "table" or #payload == 0 then
        return notify(player, "claim_rejected", "empty")
    end
    -- Coordinate compression is bounded independently from the configurable number
    -- of logical claim areas. This is a protocol/CPU guard against a modified client;
    -- connected fragments still count as one area in normal validation below.
    if #payload > 128 then return notify(player, "claim_rejected", "too_many_rects") end
    local rects = {}
    for i = 1, #payload do
        local src = payload[i]
        if type(src) ~= "table" then return notify(player, "claim_rejected", "empty") end
        for c = 1, 4 do
            local v = src[c]
            if type(v) ~= "number" or v ~= v or math.abs(v) > 10000000 then
                return notify(player, "claim_rejected", "empty")
            end
        end
        rects[i] = FF.sanitiseArea(FF.normaliseRect(src), src.access, src.grants)
    end
    -- Authoritative exact union: overlapping/touching submissions cannot create an
    -- inner claim or double-count tiles, even if the client UI was bypassed.
    rects = FF.canonicaliseClaimRects(rects)
    if #rects > 256 then return notify(player, "claim_rejected", "too_many_rects") end

    local ok, reason = FF.validateClaim(faction, name, rects, FF.getOptions())
    if not ok then return notify(player, "claim_rejected", reason) end

    faction.claims = rects
    Claims.projectFaction(name, faction)
    rebuildFactionSafehouses(faction)
    FF.sync()
    notify(player, "claim_set", tostring(FF.totalArea(rects)))
end

Handlers.unclaim = function(player, args)
    local username = FF.identityUsername(player)
    local name, faction = FF.getFactionOfPlayer(username)
    if not faction then return notify(player, "not_in_faction") end
    FF.ensureRoles(faction)
    if not FF.roleCan(faction, username, "claim") then return notify(player, "not_authorised") end

    removeFactionSafehouses(faction)
    faction.claims = {}
    Claims.removeFaction(name)
    FF.sync()
    notify(player, "claim_cleared")
end

Handlers.setRespawn = function(player, args)
    local username = FF.identityUsername(player)
    local name, faction = FF.getFactionOfPlayer(username)
    if not faction then return notify(player, "not_in_faction") end
    FF.ensureRoles(faction)
    if not FF.roleCan(faction, username, "setRespawn") then return notify(player, "not_authorised") end

    local x = math.floor(player:getX())
    local y = math.floor(player:getY())
    local z = math.floor(player:getZ())
    if not FF.pointInClaim(faction, x, y) then
        return notify(player, "respawn_must_be_in_claim")
    end
    faction.respawn = { x = x, y = y, z = z }
    FF.sync()
    notify(player, "respawn_set")
end

-- Declare a raid on another faction's claim. The raid itself is resolved by the
-- raid tick (outnumber-and-hold); this only validates and arms it.
Handlers.startRaid = function(player, args)
    local opts = FF.getOptions()
    if not opts.raidsEnabled then return notify(player, "raid_rejected", "raids_disabled") end

    local username = FF.identityUsername(player)
    local attackerName, attacker = FF.getFactionOfPlayer(username)
    if not attacker then return notify(player, "not_in_faction") end
    FF.ensureRoles(attacker)
    if not FF.roleCan(attacker, username, "startRaid") then return notify(player, "not_authorised") end

    local targetName = args and args.target
    if not targetName or targetName == "" then return notify(player, "raid_rejected", "no_target") end
    if targetName == attackerName then return notify(player, "raid_rejected", "self_target") end

    local defender = FF.getFaction(targetName)
    if not defender then return notify(player, "raid_rejected", "no_target") end
    if FF.areAllied(attackerName, targetName) then return notify(player, "raid_rejected", "ally_target") end
    if FF.pactActive(attackerName, targetName, nowMs()) then return notify(player, "raid_rejected", "pact_target") end
    if not (defender.claims and #defender.claims > 0) then
        return notify(player, "raid_rejected", "target_no_claim")
    end
    if defender.raid then return notify(player, "raid_rejected", "already_under_raid") end

    -- Raid window: only allow raids during the configured hours (start==end => any
    -- time). Handles a window that wraps past midnight (start > end).
    local ws, we = opts.raidWindowStartHour, opts.raidWindowEndHour
    if ws ~= we then
        local hour = getGameTime():getHour()
        local inWindow
        if ws < we then inWindow = (hour >= ws and hour < we)
        else inWindow = (hour >= ws or hour < we) end
        if not inWindow then return notify(player, "raid_rejected", "outside_window") end
    end

    -- Offline-raid protection: refuse if no defender is online to fight back.
    if opts.offlineRaidProtection then
        local online = 0
        forEachOnlineMemberOf(targetName, function() online = online + 1 end)
        if online == 0 then return notify(player, "raid_rejected", "defenders_offline") end
    end

    -- Per-day attempt cap on the attacking faction; the counter resets each day.
    local today = FF.gameDay()
    local at = attacker.raidAttempts
    if not at or at.day ~= today then
        at = { day = today, count = 0 }
        attacker.raidAttempts = at
    end
    if at.count >= opts.captureAttemptsPerDay then
        return notify(player, "raid_rejected", "attempts_exceeded")
    end
    at.count = at.count + 1

    local now = getTimestamp()
    defender.raid = {
        attacker = attackerName,
        declaredAt = now,
        holdSeconds = 0,
        lastTick = now,
    }
    FF.sync()
    FF.log(string.format("raid declared: %s -> %s (attempt %d/%d today)",
        attackerName, targetName, at.count, opts.captureAttemptsPerDay))
    notifyFaction(attackerName, "raid_declared", targetName)
    notifyFaction(targetName, "raid_incoming", attackerName)
end

-- Attacker calls off their own raid early (they gave up). Ends the siege with no
-- capture; the defender simply keeps the claim. An abandon is NOT scored as a
-- successful defence (that is only for outlasting the full duration) -- it just stops.
-- Any member of the attacking faction with the startRaid role may abandon.
Handlers.abandonRaid = function(player, args)
    local username = FF.identityUsername(player)
    local attackerName, attacker = FF.getFactionOfPlayer(username)
    if not attacker then return notify(player, "not_in_faction") end
    FF.ensureRoles(attacker)
    if not FF.roleCan(attacker, username, "startRaid") then return notify(player, "not_authorised") end

    -- There is no attacker->raid index; the raid lives on the DEFENDER. Scan for the
    -- faction we are currently raiding.
    local data = FF.getData()
    local defenderName, defender
    for fname, faction in pairs(data.factions) do
        if faction.raid and faction.raid.attacker == attackerName then
            defenderName, defender = fname, faction
            break
        end
    end
    if not defender then return notify(player, "raid_rejected", "no_active_raid") end

    defender.raid = nil
    debugRaidCounts[defenderName] = nil
    FF.sync()
    FF.log(string.format("raid abandoned: %s gave up the raid on %s", attackerName, defenderName))
    notifyFaction(attackerName, "raid_abandoned_self", defenderName)
    notifyFaction(defenderName, "raid_abandoned", attackerName)
end

-- ---------------------------------------------------------------------------
-- Debug/verification helpers (Milestone 2)
-- ---------------------------------------------------------------------------
-- (sendReport lives up beside notify -- see the note there.)

-- /ff status: report the caller's faction state and whether the two runtime-
-- only spikes actually took effect (PhunZones zone resolves; safehouse exists).
Handlers.status = function(player, args)
    local username = FF.identityUsername(player)
    local name, faction = FF.getFactionOfPlayer(username)
    local lines = {}
    if not faction then
        sendReport(player, { "You are not in a faction." })
        return
    end
    local mc = FF.memberCount(faction)
    local opts = FF.getOptions()
    local score = FF.factionScore(faction, opts)
    table.insert(lines, string.format("Faction '%s' (owner=%s)", name, tostring(faction.owner)))
    table.insert(lines, string.format("members=%d  score=%d  maxTiles=%d  claimedTiles=%d",
        mc, math.floor(score + 0.5), FF.maxClaimTiles(score, opts), FF.totalArea(faction.claims)))
    local roles = {}
    for user, role in pairs(faction.members) do table.insert(roles, user .. ":" .. role) end
    table.insert(lines, "roster: " .. table.concat(roles, ", "))
    if faction.respawn then
        table.insert(lines, string.format("respawn: (%d,%d,%d)",
            faction.respawn.x, faction.respawn.y, faction.respawn.z))
    else
        table.insert(lines, "respawn: <not set>")
    end
    -- Fix A proof: does PhunZones resolve our zone at the claim centroid?
    local cx, cy = FF.claimCentroid(faction)
    if cx then
        local at = Claims.factionAt(cx, cy)
        table.insert(lines, string.format("PhunZones@centroid(%d,%d) -> %s [%s]",
            cx, cy, tostring(at), at == name and "OK" or "MISMATCH"))
    end
    -- Fix C proof: is there a safehouse for each claim rect?
    local shCount = 0
    for _, rec in ipairs(faction.safehouses or {}) do
        if findSafehouseAt(rec) then shCount = shCount + 1 end
    end
    table.insert(lines, string.format("safehouses present: %d / %d rect(s) [%s]",
        shCount, #(faction.claims or {}),
        (shCount == #(faction.claims or {}) and shCount > 0) and "OK" or "check"))
    -- A correctly-built safehouse still protects nothing while the vanilla
    -- SafehouseAllowLoot option is on, so report the live value next to the count --
    -- the two together are what "is my base actually safe" means.
    local allowLoot = serverOptionBool("SafehouseAllowLoot")
    table.insert(lines, string.format("SafehouseAllowLoot: %s [%s]",
        allowLoot == nil and "<unknown>" or tostring(allowLoot),
        (not FF.getOptions().lootProtection) and "n/a" or
        (allowLoot == false and "OK" or "check")))
    sendReport(player, lines)
end

-- /ff selfcheck: probe that the engine/mod APIs we depend on exist.
Handlers.selfcheck = function(player, args)
    local P = _G.PhunZones
    local function yn(v) return v and "PASS" or "FAIL" end
    local handlerCount = 0
    for _ in pairs(Handlers) do handlerCount = handlerCount + 1 end
    local lines = {
        -- If this handler is answering at all, the dispatcher is alive by definition
        -- (see the boot canary at the end of the file for the count logged at load).
        "command handlers registered:  " .. tostring(handlerCount),
        "PhunZones present:            " .. yn(P ~= nil),
        "PhunZones.saveChanges:        " .. yn(P and P.saveChanges ~= nil),
        "PhunZones.const.modifiedModData: " .. yn(P and P.const and P.const.modifiedModData ~= nil),
        "PhunZones.getLocation:        " .. yn(P and P.getLocation ~= nil),
        "SafeHouse.addSafeHouse:       " .. yn(SafeHouse and SafeHouse.addSafeHouse ~= nil),
        "SafeHouse.getSafehouseList:   " .. yn(SafeHouse and SafeHouse.getSafehouseList ~= nil),
        "getSpecificPlayer:            " .. yn(getSpecificPlayer ~= nil),
        "PhunZones.events.OnDataBuilt: " .. yn(P and P.events and P.events.OnDataBuilt ~= nil),
    }
    -- Vanilla options the safehouse protection depends on. SafehouseAllowLoot must be
    -- off or every safehouse we build is ignored by the engine; SafehouseAllowTrepass
    -- is reported for context only (raids need outsiders able to walk in, so `true`
    -- there is normal and is not flagged).
    -- `graded` is passed explicitly rather than inferred from a nil `want`, because
    -- the value we want IS false and `x and false or nil` collapses to nil in Lua.
    local function optLine(name, graded, want)
        local v = serverOptionBool(name)
        local shown = (v == nil) and "<unknown>" or tostring(v)
        if not graded then return string.format("%s: %s", name, shown) end
        return string.format("%s: %s  %s", name, shown, yn(v == want))
    end
    table.insert(lines, optLine("SafehouseAllowLoot", FF.getOptions().lootProtection, false))
    table.insert(lines, optLine("SafehouseAllowTrepass", false))
    -- Zone liveness: every claim-bearing faction must have a live LFSFACTION_ zone in
    -- PhunZones' built data (the store the map overlay and enter banner read).
    local zones = P and P.data and P.data.zones
    for name, faction in pairs(FF.getData().factions) do
        if faction.claims and #faction.claims > 0 then
            local z = zones and zones[FF.zoneKey(name)]
            local live = z and z.points and #z.points > 0
            table.insert(lines, string.format("zone live [%s]:  %s", name, yn(live)))
        end
    end
    sendReport(player, lines)
end

FF.checkpoint("progression handlers ready")

-- ---------------------------------------------------------------------------
-- Admin debug/testing tools (Milestone 4)
-- ---------------------------------------------------------------------------
-- These bypass ownership/size/overlap validation -- they are gated to admins (or
-- the coop host) and exist so ONE admin can stand up factions, place claims
-- anywhere, populate rosters, and simulate raids without a second player. Free-form
-- confirmation strings are passed straight to notify() (unknown keys fall through
-- to the raw string on the client). isAdminPlayer/adminHandler are defined near the
-- Handlers table (top of the command section) so they exist before the war/pact
-- admin handlers that call adminHandler() earlier in the file.

-- The admin claim tools bypass FF.validateClaim entirely (that is the point of them),
-- which means they also bypass the no-claim zones. Rather than start enforcing a rule
-- on the one path built to ignore rules, say so in the confirmation -- an admin placing
-- a claim inside a zone they set up themselves is usually doing it on purpose, but
-- should know. Returns "" or a suffix.
function H.noClaimWarning(rects)
    local blocked = FF.findNoClaimConflict(rects)
    return blocked and ("  (NOTE: inside no-claim zone '" .. blocked .. "')") or ""
end

-- Project an arbitrary claim set for a faction (no validation) + refresh safehouses.
function H.applyClaims(name, faction, rects)
    faction.claims = FF.canonicaliseClaimRects(rects)
    Claims.projectFaction(name, faction)
    rebuildFactionSafehouses(faction)
end

Handlers.adminCreate = adminHandler(function(player, args)
    local name = args and args.name
    if not name or name == "" then return notify(player, "Usage: /ff admin create <name> [owner]") end
    local valid, reason = FF.validateFactionName(name)
    if not valid then return notify(player, "Admin: bad name -- " .. tostring(reason) .. ".") end
    local data = FF.getData()
    if data.factions[name] then return notify(player, "Admin: faction '" .. name .. "' already exists.") end
    local owner = (args.owner and args.owner ~= "") and args.owner or FF.identityUsername(player)
    if data.playerIndex[owner] then
        return notify(player, "Admin: '" .. owner .. "' is already in a faction.")
    end
    -- Optional overrides for the fields that used to be hardcoded. They stayed wrong
    -- for the faction's whole life before /ff admin set existed, because every setter
    -- was owner-gated -- so an admin-made faction was permanently tag==name with no
    -- description until its owner happened to log in.
    local tag = safeDisplayText(args.tag, 24)
    if tag == "" then tag = H.generateTagFromName(name) end
    local description = safeDisplayText(args.description, DESC_MAX)

    data.factions[name] = {
        owner = owner,
        members = { [owner] = "owner" },
        roles = FF.defaultRoles(),
        tag = tag,
        description = description,
        motd = "",
        friendlyFire = false,
        hideBanner = false,
        color = nil,
        joinMode = "closed",
        invites = {},
        relations = {},
        allyRequests = {},
        shareMapWithAllies = true,
        created = getGameTime():getWorldAgeHours(),
        lastActive = nowMs(),     -- real-world epoch (ms); drives claim decay
        claims = {},
        respawn = nil,
        loot = true,
        raid = nil,
        stats = { raidsWon = 0, raidsLost = 0, raidsDefended = 0 },
        tribute = { balance = 0, ratePercent = 0, history = {} },
    }
    data.playerIndex[owner] = name
    FF.sync()
    notify(player, string.format("Admin: created faction '%s' (owner %s).", name, owner))
end)

Handlers.adminDisband = adminHandler(function(player, args)
    local name = args and args.name
    local faction = FF.getFaction(name)
    if not faction then return notify(player, "Admin: no faction '" .. tostring(name) .. "'.") end
    if not refundTributeTreasury(name, faction) then
        return notify(player, "Admin: Shop unavailable; treasury refund failed, faction kept intact.")
    end
    -- Teardown must match Handlers.disband step for step. This was a reduced copy that
    -- skipped wars, pacts, the event broadcast and the buff reconcile, so an admin
    -- disband left live war/pact records naming a faction that no longer existed and
    -- left granted skills and traits on its ex-members.
    if FF.dissolveWarsFor then FF.dissolveWarsFor(name) end
    if FF.clearPactsFor then FF.clearPactsFor(name) end
    removeFactionSafehouses(faction)
    faction.claims = {}          -- before removeFaction; see decayDisband
    Claims.removeFaction(name)
    local data = FF.getData()
    if FF.releaseFactionRefs then FF.releaseFactionRefs(name) end   -- see decayDisband
    data.factions[name] = nil
    FF.sync()
    notify(player, "Admin: disbanded '" .. name .. "'.")
    broadcastEvent("faction_disbanded_global", { name })
end)

-- Rename a faction, moving every reference to it. The name IS the registry's primary
-- key, so this is a re-key of data.factions plus one pass of the canonical reference
-- walk -- see walkFactionRefs for what "every reference" covers and what it excludes.
--
-- Deleting and recreating is NOT an equivalent: it would lose the claims, stats,
-- roles and relations that make the faction what it is.
Handlers.adminRename = adminHandler(function(player, args)
    local old = args and args.name
    local new = args and args.newName
    local faction = FF.getFaction(old)
    if not faction then return notify(player, "Admin: no faction '" .. tostring(old) .. "'.") end

    local ok, reason = FF.validateFactionName(new)
    if not ok then return notify(player, "Admin: bad name -- " .. reason .. ".") end
    if new == old then return notify(player, "Admin: '" .. old .. "' is already called that.") end

    local data = FF.getData()
    if data.factions[new] then
        return notify(player, "Admin: '" .. new .. "' already exists.")
    end

    -- Refuse mid-raid. A raid pushes per-second transient payloads carrying BOTH faction
    -- names and flips safehouse loot exposure while it runs; renaming underneath it would
    -- have clients reconciling a name that changed between two pings. A raid lasts minutes
    -- and does not survive a restart, so waiting costs nothing.
    --
    -- A WAR is deliberately not a blocker: war records name their sides explicitly and
    -- re-key deterministically, and wars run for days -- refusing during one would make
    -- rename unusable on exactly the servers most likely to want it.
    if faction.raid then
        return notify(player, "Admin: '" .. old .. "' is being raided. End it first "
            .. "(/ff admin endraid " .. old .. ").")
    end
    for defName, f in pairs(data.factions) do
        if f.raid and f.raid.attacker == old then
            return notify(player, "Admin: '" .. old .. "' is raiding " .. defName
                .. ". End it first (/ff admin endraid " .. defName .. ").")
        end
    end

    -- 1. Move the record itself, so the walk below sees the new key as a live faction.
    data.factions[new] = faction
    data.factions[old] = nil

    -- 2. Everything that stores the name as a foreign key.
    local report = FF.remapFactionRefs(old, new, { total = 0, names = {} })

    -- 3-4. Re-project the zone under the new name BEFORE deleting the old one.
    -- Claims.removeFaction fires OnDataBuilt synchronously, which runs healFromBuild,
    -- which re-projects any claimed faction whose zone is missing. With the registry
    -- already renamed, doing it the other way round would make heal project `new` from
    -- inside removeFaction -- correct, but an extra whole-file write and rebuild.
    local hadClaims = faction.claims and #faction.claims > 0
    if hadClaims then Claims.projectFaction(new, faction) end
    Claims.removeFaction(old)

    -- Safehouses need NO rebuild: they key on geometry plus the owner's username, and
    -- a rename changes neither. Do not add a rebuildFactionSafehouses call here.

    FF.sync()

    notifyFaction(new, "faction_renamed", old)
    broadcastEvent("faction_renamed_global", { old, new })
    FF.print(string.format("admin %s renamed faction '%s' -> '%s' (%d reference(s) moved)",
        tostring(player:getUsername()), old, new, report.total or 0))

    -- Report what moved, so an admin can see the fan-out actually happened rather than
    -- having to go and check each system by hand.
    local lines = { string.format("Renamed '%s' -> '%s'.", old, new) }
    lines[#lines + 1] = hadClaims and "  claims: re-projected" or "  claims: none"
    for _, site in ipairs({ "playerIndex", "relations", "allyRequests", "pactRequests",
                            "raids", "wars", "pacts", "ceasefires",
                            "lff.applications", "lff.hidden", "season.baseline" }) do
        if report[site] then lines[#lines + 1] = string.format("  %-18s %d", site, report[site]) end
    end
    sendReport(player, lines)
end)

Handlers.adminAddMember = adminHandler(function(player, args)
    local name = args and args.name
    local user = args and args.username
    local faction = FF.getFaction(name)
    if not faction then return notify(player, "Admin: no faction '" .. tostring(name) .. "'.") end
    if not user or user == "" then
        return notify(player, "Usage: /ff admin addmember <faction> <username> [role]")
    end
    local data = FF.getData()
    if data.playerIndex[user] and data.playerIndex[user] ~= name then
        return notify(player, "Admin: '" .. user .. "' is already in " .. data.playerIndex[user] .. ".")
    end
    FF.ensureRoles(faction)
    local role = args.role
    if not (role and faction.roles[role]) then role = "member" end
    faction.members[user] = role
    data.playerIndex[user] = name
    syncSafehouseMembers(name, faction)
    FF.sync()
    notify(player, string.format("Admin: added %s to '%s' (%d members).", user, name, FF.memberCount(faction)))
end)

Handlers.adminRemoveMember = adminHandler(function(player, args)
    local name = args and args.name
    local user = args and args.username
    local faction = FF.getFaction(name)
    if not faction then return notify(player, "Admin: no faction '" .. tostring(name) .. "'.") end
    if not (user and faction.members[user]) then return notify(player, "Admin: no such member.") end
    if faction.owner == user then
        return notify(player, "Admin: cannot remove the owner (disband instead).")
    end
    faction.members[user] = nil
    FF.getData().playerIndex[user] = nil
    syncSafehouseMembers(name, faction)
    FF.sync()
    notify(player, string.format("Admin: removed %s from '%s'.", user, name))
end)

Handlers.adminClaimHere = adminHandler(function(player, args)
    local name = args and args.name
    local faction = FF.getFaction(name)
    if not faction then return notify(player, "Admin: no faction '" .. tostring(name) .. "'.") end
    local size = tonumber(args.size) or 20
    local half = math.floor(size / 2)
    local cx, cy = math.floor(player:getX()), math.floor(player:getY())
    local rect = FF.normaliseRect({ cx - half, cy - half, cx - half + size - 1, cy - half + size - 1 })
    H.applyClaims(name, faction, { rect })
    FF.sync()
    notify(player, string.format("Admin: claimed %dx%d at (%d,%d) for '%s'.%s",
        size, size, cx, cy, name, H.noClaimWarning({ rect })))
end)

Handlers.adminClaimRect = adminHandler(function(player, args)
    local name = args and args.name
    local faction = FF.getFaction(name)
    if not faction then return notify(player, "Admin: no faction '" .. tostring(name) .. "'.") end
    local x1, y1 = tonumber(args.x1), tonumber(args.y1)
    local x2, y2 = tonumber(args.x2), tonumber(args.y2)
    if not (x1 and y1 and x2 and y2) then
        return notify(player, "Usage: /ff admin claim <faction> <x1> <y1> <x2> <y2>")
    end
    local rect = FF.normaliseRect({ x1, y1, x2, y2 })
    local rects
    if args.add then
        rects = {}
        for i, r in ipairs(faction.claims or {}) do rects[i] = r end
        table.insert(rects, rect)
    else
        rects = { rect }
    end
    H.applyClaims(name, faction, rects)
    FF.sync()
    notify(player, string.format("Admin: %s rect (%d,%d)-(%d,%d) for '%s' (%d tiles).%s",
        args.add and "added" or "set", rect[1], rect[2], rect[3], rect[4], name,
        FF.totalArea(rects), H.noClaimWarning({ rect })))
end)

-- Release every rect a faction holds. Extracted so the by-name command and the
-- right-click-in-a-claim tool below share one teardown and cannot drift apart.
-- Caller handles FF.sync() and the reply to the admin.
function H.clearAllClaims(name, faction)
    removeFactionSafehouses(faction)
    faction.claims = {}
    Claims.removeFaction(name)
    faction.respawn = nil        -- it pointed inside land the faction no longer holds
    notifyFaction(name, "claim_cleared")
end

Handlers.adminUnclaim = adminHandler(function(player, args)
    local name = args and args.name
    local faction = FF.getFaction(name)
    if not faction then return notify(player, "Admin: no faction '" .. tostring(name) .. "'.") end
    H.clearAllClaims(name, faction)
    FF.sync()
    notify(player, "Admin: cleared claims for '" .. name .. "'.")
end)

-- Remove the claim an admin is standing in / right-clicked, without having to know
-- whose it is. args: x, y (tile), all (boolean -- the whole faction claim rather than
-- just the area under the cursor).
--
-- The owner is resolved HERE from the tile, never taken off the wire: the client sends
-- a coordinate, not a faction name. That also makes the orphan case work, where there
-- is no registry faction to name -- only a leftover PhunZones zone.
Handlers.adminRemoveClaimAt = adminHandler(function(player, args)
    local x = tonumber(args and args.x)
    local y = tonumber(args and args.y)
    if not (x and y) then return notify(player, "Admin: bad coordinates.") end
    x, y = math.floor(x), math.floor(y)

    local hitName, hitFaction, hitIndex
    for name, faction in pairs(FF.getData().factions) do
        for i = 1, #(faction.claims or {}) do
            if FF.pointInRect(x, y, faction.claims[i]) then
                hitName, hitFaction, hitIndex = name, faction, i
                break
            end
        end
        if hitName then break end
    end

    -- No live claim covers the tile. There may still be an ORPHAN zone here -- a claim
    -- left behind by a faction that no longer exists, which is precisely the thing an
    -- admin needs to be able to clear by hand. Claims.factionAt reads the zone layer,
    -- so it sees one where the registry cannot.
    if not hitName then
        -- Claims.factionAt intentionally hides orphan zones after cross-checking
        -- the registry, so inspect the raw PhunZones layer for this admin-only GC.
        local ghost = nil
        local P = _G.PhunZones
        if P and P.getLocation then
            local ok, zone = pcall(function() return P.getLocation(x, y) end)
            if ok and zone and zone.key then ghost = FF.factionNameFromZoneKey(zone.key) end
        end
        if ghost and not FF.getFaction(ghost) then
            Claims.removeFaction(ghost)
            FF.print(string.format("admin %s removed orphaned claim zone '%s' at (%d,%d)",
                tostring(player:getUsername()), tostring(ghost), x, y))
            return notify(player, "Admin: removed orphaned claim zone '" .. tostring(ghost) .. "'.")
        end
        return notify(player, string.format("Admin: no claim at (%d,%d).", x, y))
    end

    if args.all then
        H.clearAllClaims(hitName, hitFaction)
        FF.sync()
        FF.print(string.format("admin %s cleared all claims of '%s' via (%d,%d)",
            tostring(player:getUsername()), hitName, x, y))
        return notify(player, "Admin: cleared all claims for '" .. hitName .. "'.")
    end

    local remove = { hitIndex }
    for _, component in ipairs(FF.claimComponents(hitFaction.claims, true)) do
        local matched = false
        for _, index in ipairs(component) do
            if index == hitIndex then matched = true; break end
        end
        if matched then remove = component; break end
    end
    table.sort(remove, function(a, b) return a > b end)
    for _, index in ipairs(remove) do table.remove(hitFaction.claims, index) end
    if #hitFaction.claims == 0 then
        removeFactionSafehouses(hitFaction)
        Claims.removeFaction(hitName)
    else
        Claims.projectFaction(hitName, hitFaction)
        -- rebuildFactionSafehouses' own orphan-rect sweep drops the safehouse of a rect
        -- that is no longer claimed, so the removed area needs nothing extra here.
        rebuildFactionSafehouses(hitFaction)
    end
    if hitFaction.respawn and not FF.pointInClaim(hitFaction, hitFaction.respawn.x, hitFaction.respawn.y) then
        hitFaction.respawn = nil
    end
    FF.sync()
    FF.print(string.format("admin %s removed claim area of '%s' at (%d,%d)",
        tostring(player:getUsername()), hitName, x, y))
    notifyFaction(hitName, "claim_area_removed")
    notify(player, string.format("Admin: removed one claim area of '%s' (%d left).",
        hitName, FF.claimComponentCount(hitFaction.claims)))
end)

-- Sweep every LFSFACTION_ zone with no live claim behind it. `force` because an admin
-- typing the command IS the confirmation the automatic startup sweep withholds when
-- the registry is empty.
-- Sweep everything left behind by factions that no longer exist. Two independent
-- populations: orphaned claim ZONES (the PhunZones layer) and orphaned faction
-- REFERENCES (the registry). Saves made before the teardown was centralised can hold
-- plenty of the latter -- relations pointing at a dead faction, applications to
-- one -- and until now there was no way to find or clear them.
--
-- Typing the command is the confirmation, exactly as adminPurgeClaims always worked.
function H.purgeOrphans(player, what)
    what = (what or "all"):lower()
    local lines = {}

    if what == "dry" then
        local rep = FF.purgeFactionRefs(true)
        if rep.total == 0 then
            lines[#lines + 1] = "No orphaned faction references."
        else
            lines[#lines + 1] = string.format("%d orphaned faction reference(s) would be cleared:", rep.total)
            local names = {}
            for n in pairs(rep.names) do names[#names + 1] = n end
            table.sort(names)
            lines[#lines + 1] = "  dead factions: " .. table.concat(names, ", ")
            for _, site in ipairs({ "playerIndex", "relations", "allyRequests", "pactRequests",
                                    "raids", "lff.applications", "lff.hidden",
                                    "season.baseline", "tributeDelta", "debugRaidCounts" }) do
                if rep[site] then lines[#lines + 1] = string.format("  %-18s %d", site, rep[site]) end
            end
            lines[#lines + 1] = "Nothing was changed. Run /ff admin purge to apply."
        end
        return sendReport(player, lines)
    end

    if what == "all" or what == "refs" then
        local rep = FF.purgeFactionRefs(false)
        if rep.total == 0 then
            lines[#lines + 1] = "Faction references: nothing orphaned."
        else
            local names = {}
            for n in pairs(rep.names) do names[#names + 1] = n end
            table.sort(names)
            lines[#lines + 1] = string.format("Cleared %d reference(s) to: %s",
                rep.total, table.concat(names, ", "))
            FF.print(string.format("admin %s purged %d orphaned faction reference(s)",
                tostring(player:getUsername()), rep.total))
            FF.sync()
        end
    end

    if what == "all" or what == "claims" then
        local n = Claims.purgeOrphanZones(true)
        lines[#lines + 1] = string.format("Purged %d orphaned claim zone(s). See the server log for names.", n)
    end

    if #lines == 0 then
        lines = { "Usage: /ff admin purge [all|refs|claims|dry]" }
    end
    sendReport(player, lines)
end

Handlers.adminPurge = adminHandler(function(player, args)
    H.purgeOrphans(player, args and args.what)
end)

-- Kept as its own command: README and the test scenarios both name it, and "purge the
-- claim zones only" stays a useful thing to ask for on its own.
Handlers.adminPurgeClaims = adminHandler(function(player, args)
    H.purgeOrphans(player, "claims")
end)

Handlers.adminSetRespawn = adminHandler(function(player, args)
    local name = args and args.name
    local faction = FF.getFaction(name)
    if not faction then return notify(player, "Admin: no faction '" .. tostring(name) .. "'.") end
    local x = tonumber(args.x) or math.floor(player:getX())
    local y = tonumber(args.y) or math.floor(player:getY())
    local z = tonumber(args.z) or math.floor(player:getZ())
    faction.respawn = { x = x, y = y, z = z }
    FF.sync()
    notify(player, string.format("Admin: respawn for '%s' set to (%d,%d,%d).", name, x, y, z))
end)

Handlers.adminList = adminHandler(function(player, args)
    local data = FF.getData()
    local lines = {}
    local count = 0
    for name, faction in pairs(data.factions) do
        count = count + 1
        local rects = {}
        for _, r in ipairs(faction.claims or {}) do
            table.insert(rects, string.format("(%d,%d)-(%d,%d)", r[1], r[2], r[3], r[4]))
        end
        local raidStr = ""
        if faction.raid then
            raidStr = string.format(" RAID<-%s hold=%d/%d", tostring(faction.raid.attacker),
                math.floor(faction.raid.holdSeconds or 0), FF.getOptions().raidHoldSeconds)
        end
        table.insert(lines, string.format("%s owner=%s members=%d claims=[%s]%s",
            name, tostring(faction.owner), FF.memberCount(faction),
            table.concat(rects, " "), raidStr))
    end
    if count == 0 then lines = { "No factions exist." } end
    sendReport(player, lines)
end)

-- Force a relationship between two factions (dev tool -- test alliances solo,
-- without needing both factions' owners online to request/accept).
Handlers.adminSetRelation = adminHandler(function(player, args)
    local a = args and args.a
    local b = args and args.b
    local status = (args and args.status or "neutral"):lower()
    local fa = FF.getFaction(a)
    local fb = FF.getFaction(b)
    if not (fa and fb) then return notify(player, "Admin: both factions must exist.") end
    if a == b then return notify(player, "Admin: pick two different factions.") end
    fa.relations = fa.relations or {}
    fb.relations = fb.relations or {}
    if status == "ally" then
        formAlliance(a, fa, b, fb)   -- re-projects both zones
    elseif status == "enemy" then
        fa.relations[b] = "enemy"
        fb.relations[a] = "enemy"   -- mutual, so both Relations tabs show ENEMY
        reprojectZones({ { name = a, faction = fa }, { name = b, faction = fb } })
    else -- neutral / clear
        fa.relations[b] = nil
        fb.relations[a] = nil
        reprojectZones({ { name = a, faction = fa }, { name = b, faction = fb } })
        if fa.allyRequests then fa.allyRequests[b] = nil end
        if fb.allyRequests then fb.allyRequests[a] = nil end
    end
    FF.sync()
    notify(player, string.format("Admin: %s <-> %s set to %s.", a, b, status))
end)

Handlers.adminRaid = adminHandler(function(player, args)
    local attackerName = args and args.attacker
    local defenderName = args and args.defender
    local attacker = FF.getFaction(attackerName)
    local defender = FF.getFaction(defenderName)
    if not attacker then return notify(player, "Admin: no attacker faction '" .. tostring(attackerName) .. "'.") end
    if not defender then return notify(player, "Admin: no defender faction '" .. tostring(defenderName) .. "'.") end
    if attackerName == defenderName then return notify(player, "Admin: a faction cannot raid itself.") end
    if not (defender.claims and #defender.claims > 0) then
        return notify(player, "Admin: '" .. defenderName .. "' has no claim to raid.")
    end
    local now = getTimestamp()
    defender.raid = { attacker = attackerName, declaredAt = now, holdSeconds = 0, lastTick = now }
    FF.sync()
    notifyFaction(attackerName, "raid_declared", defenderName)
    notifyFaction(defenderName, "raid_incoming", attackerName)
    local msg = string.format("Admin: armed raid %s -> %s.", attackerName, defenderName)
    if not FF.getOptions().raidsEnabled then
        msg = msg .. " WARNING: RaidsEnabled is OFF -- the tick will not process it."
    end
    notify(player, msg)
end)

Handlers.adminSimRaid = adminHandler(function(player, args)
    local defenderName = args and args.defender
    local defender = FF.getFaction(defenderName)
    if not defender then return notify(player, "Admin: no faction '" .. tostring(defenderName) .. "'.") end
    local a = tonumber(args.attackers)
    local d = tonumber(args.defenders) or 0
    if not a or a < 0 then
        debugRaidCounts[defenderName] = nil
        return notify(player, "Admin: cleared raid simulation for '" .. defenderName .. "'.")
    end
    debugRaidCounts[defenderName] = { attackers = a, defenders = d }
    notify(player, string.format("Admin: simulating %d attackers vs %d defenders in '%s'.", a, d, defenderName))
end)

Handlers.adminCapture = adminHandler(function(player, args)
    local defenderName = args and args.defender
    local defender = FF.getFaction(defenderName)
    if not defender then return notify(player, "Admin: no faction '" .. tostring(defenderName) .. "'.") end
    if not defender.raid then return notify(player, "Admin: '" .. defenderName .. "' is not under raid.") end
    captureBurn(defenderName, defender, defender.raid.attacker)
    notify(player, "Admin: force-captured '" .. defenderName .. "'.")
end)

Handlers.adminEndRaid = adminHandler(function(player, args)
    local defenderName = args and args.defender
    local defender = FF.getFaction(defenderName)
    if not defender then return notify(player, "Admin: no faction '" .. tostring(defenderName) .. "'.") end
    if not defender.raid then return notify(player, "Admin: '" .. defenderName .. "' is not under raid.") end
    local attackerName = defender.raid.attacker
    defender.raid = nil
    debugRaidCounts[defenderName] = nil
    FF.sync()
    notifyFaction(attackerName, "raid_failed", defenderName)
    notifyFaction(defenderName, "raid_defended", attackerName)
    notify(player, "Admin: ended raid on '" .. defenderName .. "' (defenders keep the claim).")
end)

-- Force a faction to decay/disband right now (no waiting for the real-world clock),
-- to test the claim-decay outcome + faction_decayed broadcast.
Handlers.adminDecay = adminHandler(function(player, args)
    local name = args and args.name
    local faction = FF.getFaction(name)
    if not faction then return notify(player, "Admin: no faction '" .. tostring(name) .. "'.") end
    if not decayDisband(name, faction) then
        return notify(player, "Admin: Shop unavailable; treasury refund failed, faction kept intact.")
    end
    FF.sync()
    notify(player, "Admin: force-decayed (disbanded) '" .. tostring(name) .. "'.")
end)

-- Add to a faction's combat-record counter directly (raidsWon/raidsLost/
-- raidsDefended -- the only faction-level stats left; see FF.ensureStats), so raid
-- outcomes can be driven instantly solo. Goes through bumpStat like the real thing.
local STAT_KEYS = { raidsWon = true, raidsLost = true, raidsDefended = true }

Handlers.adminStat = adminHandler(function(player, args)
    local name = args and args.name
    local faction = FF.getFaction(name)
    if not faction then return notify(player, "Admin: no faction '" .. tostring(name) .. "'.") end
    local stat = args and args.stat
    if not (stat and STAT_KEYS[stat]) then
        return notify(player, "Admin: stat must be one of raidsWon, raidsLost, raidsDefended.")
    end
    local count = math.floor(tonumber(args and args.count) or 0)
    if count == 0 then return notify(player, "Admin: count must be a non-zero number.") end
    bumpStat(name, faction, stat, count)
    FF.sync()
    notify(player, string.format("Admin: %s %s %+d -> %d.", name, stat, count, faction.stats[stat]))
end)

-- Add to a PLAYER's own current-character score directly (kills or hours -- see
-- FF.ensurePlayerScore), so claim-size/leaderboard scoring can be tested without
-- actually grinding zombies or waiting out the clock.
Handlers.adminScore = adminHandler(function(player, args)
    local username = args and args.name
    if type(username) ~= "string" or username == "" then
        return notify(player, "Admin: a player name is required.")
    end
    local stat = args and args.stat
    if stat ~= "kills" and stat ~= "hours" then
        return notify(player, "Admin: stat must be 'kills' or 'hours'.")
    end
    local count = math.floor(tonumber(args and args.count) or 0)
    if count == 0 then return notify(player, "Admin: count must be a non-zero number.") end
    local rec = FF.ensurePlayerScore(username)
    rec[stat] = math.max(0, (rec[stat] or 0) + count)
    FF.sync()
    notify(player, string.format("Admin: %s %s %+d -> %d.", username, stat, count, rec[stat]))
end)

-- ---------------------------------------------------------------------------
-- Command dispatch
-- ---------------------------------------------------------------------------
-- Absolute native snapshot sent by the caller. The username is always resolved from
-- the server-side player object; a client cannot write another player's cache.
Handlers.syncCharacterScore = function(player, args)
    refreshPlayerScore(player, args and args.kills, args and args.hours, "native_snapshot")
end

-- Rolling-update compatibility: old clients may still emit the retired delta command
-- briefly after the server files are updated. Ignore its numbers and read that
-- IsoPlayer directly, avoiding both lost veteran history and accidental double-counting.
Handlers.creditScore = function(player, args)
    refreshPlayerScore(player, nil, nil, "server_native_legacy_client")
end

-- Character death resets only the caller's contribution by default. Claims are
-- deliberately untouched; FF.validateClaim grandfathers their current area and
-- blocks only growth while the faction remains above its score-derived cap. When
-- PreserveMemberPowerOnDeath is enabled, death only resets the current-life raw
-- baselines and keeps the contribution already earned by that member.
Handlers.resetScoreOnDeath = function(player, args)
    local username = FF.identityUsername(player)
    local rec = FF.ensurePlayerScore(username)
    local preservePower = FF.getOptions().preserveMemberPowerOnDeath == true
    if not preservePower then
        rec.kills = 0
        rec.hours = 0
    end
    rec.lastRawKills = 0
    rec.lastRawHours = 0
    rec.updatedAt = nowMs()
    rec.source = preservePower and "death_preserved" or "death"
    if not preservePower then killLog[username] = nil end
    statsDirty = true
    scoreDirtyUsers[username] = true
    -- No notify() here on purpose (removed 2026-08-30, explicit request): the
    -- death screen's halo note fades ~1s after death, well before a player can
    -- actually read "seus pontos foram preservados/zerados apos a morte" --
    -- pure noise, not information anyone could act on in time. The actual
    -- score reset/preserve logic above is unaffected either way.
end

Handlers.requestLegacyStatus = function(player, args)
    if FF.Legacy and FF.Legacy.sendStatus then
        FF.Legacy.sendStatus(player, true)
    end
end

Handlers.legacyCharacterReady = function(player, args)
    if FF.Legacy and FF.Legacy.onCharacterReady then
        FF.Legacy.onCharacterReady(player, args and args.legacyId)
    end
end

FF.checkpoint("admin tools ready")

-- Cheap server-side brakes for commands that otherwise force large geometry/
-- roster work or can be emitted continuously by a modified client. Legitimate UI
-- interactions are far slower than these windows; admin commands are already
-- trusted and intentionally exempt.
local COMMAND_COOLDOWN_MS = {
    requestSync = 2000,
    syncCharacterScore = 1000,
    creditScore = 1000,
    claim = 1500,
    unclaim = 1000,
    factionChat = 350,
    setRolePermission = 500,
    setFactionInfo = 500,
    setFactionColor = 500,
    setFactionOption = 500,
    requestProtectVehicle = 500,
    unprotectVehicle = 500,
    toggleLockVehicle = 350,
    requestLegacyStatus = 1000,
    legacyCharacterReady = 1000,
}
local commandLastAt = {}
local nextCommandRateGc = 0
FF._commandRateClock = 0

function H.commandRateLimited(player, command)
    local wait = COMMAND_COOLDOWN_MS[command]
    if not wait or command:sub(1, 5) == "admin" then return false end
    local username = player and player.getUsername and player:getUsername()
    if not username then return true end
    local now = nowMs()
    -- NTP/manual clock rollback must not leave every player waiting for a timestamp
    -- that is now in the future. Drop only this ephemeral limiter state.
    if now < FF._commandRateClock then
        for oldKey in pairs(commandLastAt) do commandLastAt[oldKey] = nil end
        nextCommandRateGc = now + 300000
    end
    FF._commandRateClock = now
    local key = username .. "\0" .. command
    local last = commandLastAt[key]
    if last and now - last < wait then return true end
    commandLastAt[key] = now
    if now >= nextCommandRateGc then
        nextCommandRateGc = now + 300000
        for oldKey, at in pairs(commandLastAt) do
            if now - at > 300000 then commandLastAt[oldKey] = nil end
        end
    end
    return false
end

function H.onLfsClientCommand(module, command, player, args)
    if module ~= FF.MODULE then return end
    if type(command) ~= "string" or not player then return end
    local handler = Handlers[command]
    if not handler then return end
    if H.commandRateLimited(player, command) then return end
    if type(args) ~= "table" then args = {} end
    -- Guard every command handler. Exceptions used to escape into the event itself,
    -- where the only trace was a Java
    -- stack in the server console naming OnClientCommand rather than the command.
    -- Naming it here is the difference between a five-minute fix and a log dig.
    --
    -- Do not latch the core dispatcher off after one failure: that would take every
    -- faction command down. One bad handler must not stop the others.
    local ok, err = pcall(handler, player, args)
    if not ok then
        FF.warn("handler '" .. tostring(command) .. "' failed: " .. tostring(err))
    end
end
FF._replaceServerHook(Events.OnClientCommand, "_serverClientCommandHook", H.onLfsClientCommand)

-- The single most important checkpoint: this is the exact registration that
-- silently failed to happen in the 1.2.1 incident (every client command became a
-- no-op with no trace in the log). Its presence here proves the dispatcher is live.
FF.checkpoint("command dispatch registered")

-- ---------------------------------------------------------------------------
-- Faction respawn
-- ---------------------------------------------------------------------------
-- NOTE: the respawn relocation lives CLIENT-side in LFS_Respawn.lua.
-- OnPlayerDeath and OnCreatePlayer are client events (they are never registered in
-- the game's server lua and do not fire in a dedicated/coop-host server process),
-- so the earlier server-side handler here never ran on a hosted game. The client
-- records the local player's death and teleports them to the faction respawn on
-- the next character creation.

-- ---------------------------------------------------------------------------
-- Raid tick
-- ---------------------------------------------------------------------------
-- One server-side loop drives every active raid. Gated to ~1s via a getTimestamp()
-- comparison (the pattern PhunZones itself uses -- there is no timer utility).
-- Win rule: attackers must CONTINUOUSLY outnumber the defenders inside the claim;
-- any break resets the hold timer to zero. Hitting RaidHoldSeconds captures (burns)
-- the claim; exceeding RaidMaxDurationSeconds ends the raid in the defenders' favour.
local RAID_TICK_INTERVAL = 1

function H.raidTick()
    local now = getTimestamp()
    if now < nextRaidTick then return end
    nextRaidTick = now + RAID_TICK_INTERVAL

    local opts = FF.getOptions()
    if not opts.raidsEnabled then return end

    local data = FF.getData()
    for name, faction in pairs(data.factions) do
        local raid = faction.raid
        if raid then
            local elapsed = now - (raid.lastTick or now)
            if elapsed < 0 then elapsed = 0 end
            raid.lastTick = now

            local ov = debugRaidCounts[name]
            local attackers, defenders
            if ov then
                attackers, defenders = ov.attackers, ov.defenders
            else
                attackers, defenders = H.countRaidParticipants(name, raid.attacker)
            end
            if attackers >= 1 and attackers > defenders then
                raid.holdSeconds = raid.holdSeconds + elapsed
            else
                raid.holdSeconds = 0
            end

            -- Built only when Debug is on: this fires once per second per active raid,
            -- and FF.log would otherwise format the string just to discard it. Same
            -- reason Claims.zoneTrace checks debugEnabled before walking the zone layer.
            if FF.debugEnabled() then
                FF.log(string.format("raid %s<-%s: hold=%d/%d att=%d def=%d",
                    name, tostring(raid.attacker), math.floor(raid.holdSeconds),
                    opts.raidHoldSeconds, attackers, defenders))
            end

            if raid.holdSeconds >= opts.raidHoldSeconds then
                captureBurn(name, faction, raid.attacker)
            elseif (now - (raid.declaredAt or now)) >= opts.raidMaxDurationSeconds then
                local attackerName = raid.attacker
                faction.raid = nil
                debugRaidCounts[name] = nil
                -- Authoritative leaderboard/XP credit: defender held out.
                bumpStat(name, faction, "raidsDefended", 1)
                FF.sync()
                FF.log(string.format("raid timed out: %s defended against %s", name, tostring(attackerName)))
                notifyFaction(attackerName, "raid_failed", name)
                notifyFaction(name, "raid_defended", attackerName)
            else
                H.sendRaidProgress(name, raid, attackers, defenders, opts)
            end
        end
    end
end

FF._replaceServerHook(Events.OnTick, "_serverRaidTick", H.raidTick)

-- Timed pacts expire lazily in FF.pactActive, but a lapsed record must also be DELETED
-- (so it stops blocking a fresh proposal and stops sharing the map) and both sides told.
-- A light periodic sweep does that; the per-second raid loop is untouched.
local nextPactSweep = 0
local PACT_SWEEP_INTERVAL = 30
function H.pactSweep()
    local now = getTimestamp()
    if now < nextPactSweep then return end
    nextPactSweep = now + PACT_SWEEP_INTERVAL
    local pacts = FF.getData().pacts
    if not pacts then return end
    local ms = nowMs()
    local expired = {}
    for key, p in pairs(pacts) do
        if (p.expiresAt or 0) > 0 and ms >= p.expiresAt then
            expired[#expired + 1] = { key = key, a = p.a, b = p.b,
                shared = p.terms and (p.terms.shareMap or p.terms.shareLocations) }
        end
    end
    if #expired == 0 then return end
    -- One projection batch for every zone touched this sweep, not two per pact.
    local reproj = {}
    for _, e in ipairs(expired) do
        pacts[e.key] = nil
        notifyFaction(e.a, "pact_expired", e.b)
        notifyFaction(e.b, "pact_expired", e.a)
        if e.shared then
            reproj[#reproj + 1] = { name = e.a, faction = FF.getFaction(e.a) }
            reproj[#reproj + 1] = { name = e.b, faction = FF.getFaction(e.b) }
        end
        FF.log(string.format("pact expired: %s <-> %s", tostring(e.a), tostring(e.b)))
    end
    reprojectZones(reproj)
    FF.sync()
end
FF._replaceServerHook(Events.OnTick, "_serverPactSweep", H.pactSweep)

-- ---------------------------------------------------------------------------
-- Member position broadcast
-- ---------------------------------------------------------------------------
-- Feeds the client map overlay's live member markers. Clients cannot read remote
-- players' positions themselves (an IsoPlayer in an unloaded cell has no valid
-- position), so the server pushes them: every ~2s, group online players by
-- faction, then send each faction member the positions they may see -- their own
-- faction always, plus any allied faction that opted into shareMemberLocations.
-- Transient HUD data like raidprogress: never persisted or synced.
-- 2s (was 5s) so member/ally map markers track movement more closely; the payload is
-- small (a few ints per online player) and only goes to players who share a faction.
local POSITIONS_INTERVAL = 2
local nextPositionsTick = 0

function H.positionsTick()
    local now = getTimestamp()
    if now < nextPositionsTick then return end
    nextPositionsTick = now + POSITIONS_INTERVAL
    if not FF.getOptions().memberMarkersEnabled then return end

    -- One pass: bucket live positions per faction and remember the recipients.
    local online = {}       -- [factionName] = { {u,x,y}, ... }
    local recipients = {}   -- { {p=player, faction=name}, ... }
    for _, e in ipairs(onlinePlayers()) do
        local p = e.p
        local fname = (not p:isDead()) and FF.getFactionOfPlayer(e.user) or nil
        if fname then
            online[fname] = online[fname] or {}
            table.insert(online[fname], { u = e.user, x = math.floor(p:getX()), y = math.floor(p:getY()) })
            table.insert(recipients, { p = p, faction = fname })
        end
    end

    -- Per recipient: own faction always + allied factions that opted in. The
    -- recipient's own entry stays in the payload -- the CLIENT filters out the
    -- local player, so other split-screen players on the same machine still show.
    for _, r in ipairs(recipients) do
        local vis = { [r.faction] = online[r.faction] }
        for fname, list in pairs(online) do
            if fname ~= r.faction and FF.sharesLocationsWith(fname, r.faction) then
                vis[fname] = list
            end
        end
        sendServerCommand(r.p, FF.MODULE, "positions", { factions = vis })
    end
end

FF._replaceServerHook(Events.OnTick, "_serverPositionsTick", H.positionsTick)

-- ---------------------------------------------------------------------------
-- Claim intrusion alerts (enemies / at-war only)
-- ---------------------------------------------------------------------------
-- Warn a faction's online members when a HOSTILE player (enemy relation or an active
-- war) steps into their claimed territory. Fires once on the enter-transition, with a
-- per (owner,intruder) cooldown so door-camping can't spam. Reuses the same
-- Claims.factionAt lookup the raid presence check uses, and runs independently of
-- member markers.
local INTRUSION_INTERVAL = 2
local INTRUSION_COOLDOWN = 60
local nextIntrusionTick = 0
local nextIntrusionGc = 0
local lastClaimByPlayer = {}   -- [username] = owner faction it was last seen inside (or nil)
local lastIntrusionAt = {}     -- [owner .. "\0" .. intruder] = timestamp of last alert

function H.hostileTo(ownerName, intruderFaction)
    if not (ownerName and intruderFaction) or ownerName == intruderFaction then return false end
    local owner = FF.getFaction(ownerName)
    if owner and owner.relations and owner.relations[intruderFaction] == "enemy" then return true end
    return FF.warBetween(ownerName, intruderFaction) ~= nil
end

function H.intrusionTick()
    local now = getTimestamp()
    if now < nextIntrusionTick then return end
    nextIntrusionTick = now + INTRUSION_INTERVAL
    if not FF.getOptions().intrusionAlertsEnabled then
        for key in pairs(lastClaimByPlayer) do lastClaimByPlayer[key] = nil end
        for key in pairs(lastIntrusionAt) do lastIntrusionAt[key] = nil end
        return
    end
    -- Cooldown rows have no purpose once expired. Without this, every unique
    -- faction/intruder pair seen over the life of a server remained forever.
    if now >= nextIntrusionGc then
        nextIntrusionGc = now + INTRUSION_COOLDOWN
        for key, at in pairs(lastIntrusionAt) do
            if now - at >= INTRUSION_COOLDOWN then lastIntrusionAt[key] = nil end
        end
    end
    local present = {}
    eachOnlinePlayer(function(p)
        if p:isDead() then return end
        local uname = FF.identityUsername(p)
        present[uname] = true
        local owner = Claims.factionAt(math.floor(p:getX()), math.floor(p:getY()))
        local prev = lastClaimByPlayer[uname]
        lastClaimByPlayer[uname] = owner
        if owner and owner ~= prev then
            -- Just entered `owner`'s claim -- alert if this player is hostile to owner.
            local intruderFaction = FF.getFactionOfPlayer(uname)
            if owner ~= intruderFaction and H.hostileTo(owner, intruderFaction) then
                local key = owner .. "\0" .. uname
                if not lastIntrusionAt[key] or (now - lastIntrusionAt[key]) >= INTRUSION_COOLDOWN then
                    lastIntrusionAt[key] = now
                    notifyFaction(owner, "intrusion", uname)
                end
            end
        end
    end)
    -- Drop offline players so the tracker doesn't grow unbounded.
    for uname in pairs(lastClaimByPlayer) do
        if not present[uname] then lastClaimByPlayer[uname] = nil end
    end
end
FF._replaceServerHook(Events.OnTick, "_serverIntrusionTick", H.intrusionTick)

-- ---------------------------------------------------------------------------
-- Shared cull guard for the territorial safe zone
-- ---------------------------------------------------------------------------
-- The ONE rule every zombie removal in this file must obey: only ever destroy an
-- ordinary, live, hostile zombie.
--
-- The trap this exists for: in B42 a corpse being DRAGGED is not an IsoDeadBody
-- being carried -- ISGrabCorpseAction:complete calls character:pickUpCorpse(body,
-- "BwdDrag"), and the engine REANIMATES the corpse into a real live IsoZombie and
-- grapples the player to it (IsoZombie.bIsReanimatedForGrappleOnly, commented in
-- the engine as "Is this Zed just a reanimated corpse for the purposes of being
-- dragged around"). So a dragged corpse is a NON-DEAD zombie sitting in
-- cell:getZombieList() at the dragging player's feet -- i.e. squarely inside the
-- safe zone's cull filter, since the dragger is themselves the anchor. Culling it
-- destroys the reanimated zombie mid-grapple (the corpse vanishes from the
-- player's hands), leaves the backing IsoDeadBody behind because it was never
-- removed through the real corpse path (it resurfaces later), and strands the
-- player grappled to a destroyed IGrappleable (they get yanked back to it later).
-- An isDead() check alone CANNOT catch this: a grapple-reanimated corpse is not
-- dead. Neither is a fake-dead zombie, which lies on the ground reading as a
-- corpse to every player who walks past it.
--
-- The probes split in two, and the split matters:
--
--   isDead is REQUIRED. It is proven bound (this file has been calling it since
--   1.2.6), so a failure there means the object itself is bad -- skip it, the safe
--   direction, exactly as before.
--
--   Everything else is OPTIONAL. isReanimatedForGrappleOnly / isBeingGrappled are
--   public on IsoZombie in the jar but NO vanilla Lua calls them, so we cannot
--   prove they are bound; isFakeDead is only proven on IsoDeadBody. If one is
--   absent -- or throws on index -- we must ignore that probe and carry on. Failing
--   closed instead would make every zombie non-cullable and silently switch the
--   whole safe zone off, a regression indistinguishable from "working, none
--   nearby". The dragger backstop in territoryTick is what covers this case, and it
--   uses only API vanilla itself calls from Lua.
--
-- Unavailable optional probes are latched after the first miss so a sweep over a
-- few hundred zombies doesn't repeat a failing pcall per zombie per flag.
local CULL_BLOCKERS_OPTIONAL = {
    "isReanimatedForGrappleOnly", -- a corpse someone is dragging RIGHT NOW
    "isBeingGrappled",            -- a player currently has hold of it
    "isFakeDead",                 -- playing dead: reads as a corpse on the ground
    "isForceFakeDead",
    "isReanimatedPlayer",         -- a reanimated player corpse -- somebody's remains
}
local cullProbeMissing = {}

local function cullableZombie(z)
    if not z then return false end
    local ok, dead = pcall(function() return z:isDead() end)
    if not ok or dead then return false end
    for _, probe in ipairs(CULL_BLOCKERS_OPTIONAL) do
        if not cullProbeMissing[probe] then
            local pok, blocked = pcall(function()
                local fn = z[probe]
                if not fn then return nil end
                return fn(z)
            end)
            if not pok then
                cullProbeMissing[probe] = true
                FF.warn("cull guard: " .. probe .. " unavailable in this build; "
                    .. "relying on the drag/grapple proximity guard instead")
            elseif blocked then
                return false
            end
        end
    end
    return true
end

-- ---------------------------------------------------------------------------
-- Territory safe zone (held-claim perk, server/host)
-- ---------------------------------------------------------------------------
-- While a member stands in their OWN claim, periodically cull loaded zombies inside
-- that claim near them -- a "safe while you're home" bubble, not a persistent no-zombie
-- zone (only loaded chunks are reachable, and the vanilla spawner re-streams over time).
-- Uses removeFromWorld/removeFromSquare and is bounded to
-- SafeZoneCullPerTick per present member per sweep to keep the cost flat.
local TERRITORY_INTERVAL = 5
local nextTerritoryTick = 0

function H.territoryTick()
    local now = getTimestamp()
    if now < nextTerritoryTick then return end
    nextTerritoryTick = now + TERRITORY_INTERVAL
    local opts = FF.getOptions()
    if not opts.territorySafeZoneEnabled then return end
    local perTick = opts.safeZoneCullPerTick or 0
    if perTick <= 0 then return end
    local radius = opts.safeZoneRadius or 12
    local radiusSq = radius * radius

    -- Anchors: members currently standing inside their own claim. The same pass
    -- collects `draggers` -- anyone hauling a corpse or grappling -- for the
    -- backstop below.
    local anchors = {}
    local draggers = {}
    eachOnlinePlayer(function(p)
        if p:isDead() then return end
        -- Built only on API vanilla itself calls from Lua (ISGrabCorpseAction,
        -- ISDropCorpseAction, ISCampingMenu), so this guard holds even on a build
        -- that does not bind the per-zombie grapple flags cullableZombie probes.
        local dok, dragging = pcall(function()
            return (p.isDraggingCorpse and p:isDraggingCorpse())
                or (p.isGrappling and p:isGrappling())
        end)
        if not dok or dragging then
            -- Probe failed: assume they might be dragging. Costs one skipped zone.
            draggers[#draggers + 1] = { x = p:getX(), y = p:getY() }
        end
        local fname = FF.getFactionOfPlayer(FF.identityUsername(p))
        if not fname then return end
        local px, py = math.floor(p:getX()), math.floor(p:getY())
        if Claims.factionAt(px, py) == fname then
            anchors[#anchors + 1] = { faction = fname, x = px, y = py, budget = perTick }
        end
    end)
    if #anchors == 0 then return end

    -- A dragged corpse rides at the dragger's own position, so a couple of tiles is
    -- all the clearance this needs.
    local DRAG_GUARD = 3
    local dragGuardSq = DRAG_GUARD * DRAG_GUARD
    local function nearDragger(zx, zy)
        for _, d in ipairs(draggers) do
            local dx, dy = zx - d.x, zy - d.y
            if (dx * dx + dy * dy) <= dragGuardSq then return true end
        end
        return false
    end

    pcall(function()
        local cell = getCell()
        local zlist = cell and cell.getZombieList and cell:getZombieList()
        if not zlist then return end
        local removals = {}
        for i = 0, zlist:size() - 1 do
            local z = zlist:get(i)
            -- Only ordinary live zombies -- never a corpse, a dragged (grapple-
            -- reanimated) body, or anything playing dead. See cullableZombie.
            if cullableZombie(z) then
                local zx, zy = math.floor(z:getX()), math.floor(z:getY())
                -- Backstop for the case where the per-zombie grapple flags are not
                -- bound in this build: nothing near someone dragging or grappling
                -- gets touched, whatever the flags claim.
                if not nearDragger(z:getX(), z:getY()) then
                    for _, a in ipairs(anchors) do
                        if a.budget > 0 then
                            local dx, dy = zx - a.x, zy - a.y
                            if (dx * dx + dy * dy) <= radiusSq and Claims.factionAt(zx, zy) == a.faction then
                                removals[#removals + 1] = z
                                a.budget = a.budget - 1
                                break
                            end
                        end
                    end
                end
            end
        end
        local culled = 0
        for _, z in ipairs(removals) do
            local rok = pcall(function()
                z:removeFromWorld()
                z:removeFromSquare()
            end)
            if rok then culled = culled + 1 end
        end
        if culled > 0 then FF.log(string.format("safe zone: culled %d zombie(s)", culled)) end
    end)
end
FF._replaceServerHook(Events.OnTick, "_serverTerritoryTick", H.territoryTick)

-- ---------------------------------------------------------------------------
-- Leaderboard stats flush
-- ---------------------------------------------------------------------------
-- Character snapshots and passive tribute changes use a compact stateDelta rather
-- than a full ModData.transmit. Flush at most once per interval.
local STATS_FLUSH_INTERVAL = 10
local STATE_FULL_CHECKPOINT_INTERVAL = 300
local nextStatsFlush = 0
local nextStateFullCheckpoint = 0

local function statsFlushTick()
    local now = getTimestamp()
    if now < nextStatsFlush then return end
    nextStatsFlush = now + STATS_FLUSH_INTERVAL
    -- Server-native backstop. It also updates online players even if their client
    -- reporter was disabled; offline records are left untouched and remain cached.
    FF.refreshOnlinePlayerScores()
    H.flushKillLog()          -- one aggregate line per player instead of one per credit
    if statsDirty or not FF.isEmpty(tributeDirtyFactions) then
        local payload = { scores = {}, tributes = {} }
        local changedUsers, changedFactions = {}, {}
        local data = FF.getData()
        for username in pairs(scoreDirtyUsers) do
            local rec = data.playerScore[username]
            if type(rec) == "table" then
                payload.scores[username] = {
                    kills = rec.kills, hours = rec.hours,
                    lastRawKills = rec.lastRawKills, lastRawHours = rec.lastRawHours,
                    updatedAt = rec.updatedAt, source = rec.source,
                }
                changedUsers[#changedUsers + 1] = username
            end
            scoreDirtyUsers[username] = nil
        end
        for name in pairs(tributeDirtyFactions) do
            local faction = data.factions[name]
            if faction then
                FF.ensureTribute(faction)
                payload.tributes[name] = { balance = faction.tribute.balance }
                changedFactions[#changedFactions + 1] = name
            end
            tributeDirtyFactions[name] = nil
        end
        if #changedUsers > 0 or #changedFactions > 0 then
            eachOnlinePlayer(function(p)
                sendServerCommand(p, FF.MODULE, "stateDelta", payload)
            end)
            if FF.API and FF.API._emitChanged then
                FF.API._emitChanged("registry_delta", {
                    scores = changedUsers,
                    tributes = changedFactions,
                })
            end
            -- Reliable server commands are the normal live path. Arm a sparse full
            -- checkpoint for rolling-update/event-loss convergence. Its deadline is
            -- processed outside this dirty block below: otherwise one isolated
            -- score/tribute change would never be checkpointed unless a second
            -- change happened five minutes later.
            if nextStateFullCheckpoint == 0 then
                nextStateFullCheckpoint = now + STATE_FULL_CHECKPOINT_INTERVAL
            end
        end
        statsDirty = false
    end
    if nextStateFullCheckpoint > 0 and now >= nextStateFullCheckpoint then
        nextStateFullCheckpoint = 0
        FF.sync()
    end
end

FF._replaceServerHook(Events.OnTick, "_serverStatsFlushTick", statsFlushTick)

-- ---------------------------------------------------------------------------
-- Faction upgrade milestones
-- ---------------------------------------------------------------------------
-- Score-driven, like the claim-size cap, so it needs its own periodic scan rather
-- than piggy-backing statsFlushTick above (that one only touches ONLINE players'
-- cached kill/hour snapshots; a milestone can be crossed by a faction with nobody
-- online this tick, purely because FF.factionScore is a live sum). Cheap: this is
-- the same pure function the client claim-map UI already calls every frame, just
-- walked once per faction every UPGRADES_TICK_INTERVAL seconds instead.
local UPGRADES_TICK_INTERVAL = 5
local nextUpgradesTick = 0

-- Compute the target directly: a corrupt/admin-inflated score must not turn this
-- periodic tick into tens of thousands of loop iterations. The fixed prefix is
-- tiny; beyond it milestones are an arithmetic progression.
function H.earnedUpgradeMilestones(score)
    score = tonumber(score) or 0
    if score ~= score or score == math.huge or score == -math.huge then return 0 end
    local count = 0
    while count < 8 and FF.upgradeMilestoneAt(count + 1) <= score do count = count + 1 end
    if count == 8 then
        local tailStep = FF.upgradeMilestoneAt(9) - FF.upgradeMilestoneAt(8)
        count = count + math.max(0, math.floor((score - FF.upgradeMilestoneAt(8)) / tailStep))
    end
    return count
end

function H.checkFactionMilestones(name, faction)
    FF.ensureUpgrades(faction)
    local u = faction.upgrades
    local score = FF.factionScore(faction)
    local earned = H.earnedUpgradeMilestones(score)
    local crossed = math.max(0, earned - u.milestonesClaimed)
    if crossed > 0 then
        u.milestonesClaimed = earned
        u.points = u.points + crossed
    end
    if crossed > 0 then
        FF.sync()
        notifyFaction(name, "upgrade_milestone_reached", tostring(crossed))
    end
end

function H.upgradesTick()
    local now = getTimestamp()
    if now < nextUpgradesTick then return end
    nextUpgradesTick = now + UPGRADES_TICK_INTERVAL
    for name, faction in pairs(FF.getData().factions) do
        H.checkFactionMilestones(name, faction)
    end
end

FF._replaceServerHook(Events.OnTick, "_serverUpgradesTick", H.upgradesTick)

-- ---------------------------------------------------------------------------
-- Vehicle auto-maintenance (Oficina / "workshop" upgrade effect)
-- ---------------------------------------------------------------------------
-- Vehicles inside a claim owned by a faction with the "workshop" upgrade AND
-- explicitly PROTECTED by that faction (see LFS_VehicleGuard.lua and the
-- "Vehicle protection & anti-theft locks" section further below -- added
-- after this feature shipped, once it became clear ANY vehicle merely
-- parked/passing through someone's territory got free maintenance, which a
-- rival or random visitor's car should never get) get, gradually: existing
-- parts repaired at a FLAT rate (WORKSHOP_REPAIR_POINTS_PER_HOUR, same speed
-- at every level -- only the level-based ceiling differs, cap = level * 10,
-- so level 10 repairs fully to 100), battery CHARGE recharged (level 5+
-- only, faster at higher levels within that range), and -- ONLY at level 10
-- -- a slow trickle of fuel. Matches all three pillars of
-- ~/Downloads/LASCIVIOUS_Faction_Vehicle_Auto_Maintenance.md's own stated
-- objective (repair / fuel / battery charge). Still does not install/replace
-- missing parts, same as the doc requires.
--
-- Deliberately does NOT require the vehicle to be stopped/engine-off, per
-- explicit user instruction after live testing -- the doc's own suggested
-- guard (doc #13/#14, "avoids someone driving laps for free repair") was
-- judged unnecessary complexity for this mod. If that guard is ever wanted
-- back, it was `not vehicle:isAtRest() or vehicle:isEngineRunning()` added to
-- the eligibility check in workshopProcessVehicle below.
--
-- Every API used here was verified against the decompiled client jar and/or
-- real vanilla Lua before use, not assumed from the research doc:
-- - vehicle:getPartCount()/getPartByIndex()/getPartById()/getBattery() are
--   `default` methods on the zombie.vehicles.VehiclePartOwner interface
--   BaseVehicle implements -- absent from BaseVehicle.class's own bytecode
--   (so a first pass checking only that class found nothing), but real and
--   directly callable on any vehicle object, exactly like vanilla's own
--   ISVehicleMechanics.lua calls them.
-- - The fuel sync flow (part:setContainerContentAmount(x) then
--   vehicle:transmitPartModData(part)) is not guessed: it is the exact
--   sequence vanilla's own ISAddGasolineToVehicle.lua/ISRefuelFromGasPump.lua/
--   ISTakeGasolineFromVehicle.lua all use.
-- - The battery charge flow (item:getCurrentUsesFloat() to read, 0.0..1.0,
--   item:setUsedDelta(x) to write, vehicle:transmitPartUsedDelta(battery) to
--   sync) is not guessed either: it is vanilla's own
--   VehicleUtils.chargeBattery in server/Vehicles/Vehicles.lua, doing exactly
--   this for the antenna/alarm drain mechanic.
-- - Discovery walks EVERY loaded vehicle via getCell():getVehicles():iterator()
--   -- explicitly NOT a radius scan around online players (an earlier pass of
--   this feature tried that, and the user correctly rejected it: territory
--   with no player nearby must still get maintained, or the feature is
--   useless for exactly the situation it exists for). getVehicles() itself
--   returns a genuine java.util.HashSet (confirmed via decompiled bytecode:
--   `new HashSet()`), which has no get(int) -- an earlier pass crashed every
--   tick assuming :size()/:get(i-1) worked on it (it doesn't; that pattern
--   only works on ArrayList-returning getters like getZombieList()). The safe
--   way to walk any java.util.Collection from Kahlua is the standard Java
--   Iterator protocol -- :iterator() then :hasNext()/:next() -- which every
--   Collection guarantees by contract (unlike get(int), which only
--   List implementations promise). Wrapped in pcall with a warn-once flag
--   (workshopIteratorWarned) as a safety net: if this ALSO turns out to not
--   be exposed by Kahlua, it fails ONCE with a clear log line instead of
--   spamming the console or wiping tracked state every tick.
--
-- Rate-based on elapsed WORLD time (getGameTime():getWorldAgeHours(), already
-- used elsewhere in this file), never on tick frequency, so a slower/faster
-- scheduler never changes how much gets repaired. Per-vehicle state
-- (elapsed-time clock + fractional repair carry -- setCondition takes an
-- int, so a slow gain would floor to 0 forever without a carry accumulator,
-- see the doc's own #19-20) lives in a plain in-memory table keyed by
-- vehicle:getId(), NOT in vehicle ModData -- no offline catch-up in this
-- first pass (the doc's own recommended "Fase 1 MVP" scope). Losing this
-- table on a server restart just means every vehicle's clock restarts from
-- "just became eligible" -- zero risk, at most a brief pause, never a wrong
-- repair. Pruned back to only vehicles seen in a successful scan at the end
-- of every tick so it can never grow unbounded over a long server lifetime.
local WORKSHOP_TICK_INTERVAL = 20
local WORKSHOP_REPAIR_CAP_PER_LEVEL = 10          -- cap = level * 10 (0..100)
local WORKSHOP_REPAIR_POINTS_PER_HOUR = 1         -- flat rate, same at every level -- only the cap differs
local WORKSHOP_BATTERY_MIN_LEVEL = 5              -- battery charging does not start until this level
local WORKSHOP_BATTERY_PERCENT_PER_DAY_PER_LEVEL = 2.5 -- level 10 = 25%/day (empty->full in ~4 days)
local WORKSHOP_FUEL_PERCENT_PER_DAY_AT_MAX = 10   -- level 10 only: +10% of tank capacity/day
local nextWorkshopTick = 0
local workshopVehicleState = {}
local workshopIteratorWarned = false

-- Repairs every currently-installed part up to `cap`, never above it and never
-- reducing a part already at/above it (a downgrade must stop future repair,
-- not undo past repair -- doc #27/#50). `carry[partIndex]` holds the
-- fractional condition owed to that part since its last whole point, surviving
-- level changes (doc #105) for as long as the vehicle stays continuously
-- eligible. isInventoryItemUninstalled() skips parts that were never there --
-- this never installs anything (doc #23/#118). Rate is FLAT
-- (WORKSHOP_REPAIR_POINTS_PER_HOUR, same at every level) per explicit user
-- request to keep this balanced -- level only changes the ceiling `cap`, not
-- how fast a part climbs toward it. Still gradual (per-tick gain from real
-- elapsed world time, never a once-a-day lump sum).
function H.workshopRepairVehicle(vehicle, level, elapsedDays, carry)
    local cap = math.min(100, level * WORKSHOP_REPAIR_CAP_PER_LEVEL)
    local gainPerDay = WORKSHOP_REPAIR_POINTS_PER_HOUR * 24
    local changed = false
    for i = 0, vehicle:getPartCount() - 1 do
        local part = vehicle:getPartByIndex(i)
        if part and not part:isInventoryItemUninstalled() then
            local idx = part:getIndex()
            local current = part:getCondition()
            if current >= cap then
                carry[idx] = nil
            else
                local newCarry = (carry[idx] or 0) + gainPerDay * elapsedDays
                local whole = math.floor(newCarry)
                carry[idx] = newCarry - whole
                if whole > 0 then
                    local target = math.min(cap, current + whole)
                    if target > current then
                        part:setCondition(target)
                        vehicle:transmitPartCondition(part)
                        changed = true
                    end
                end
            end
        end
    end
    if changed then
        vehicle:updatePartStats()
        vehicle:setNeedPartsUpdate(true)
    end
end

-- Level-10-only trickle of fuel, as a percent of the tank's own capacity/day
-- (never a flat amount -- keeps the rate proportional across small/large
-- tanks, doc #34). Silently does nothing if the vehicle has no GasTank part
-- (never errors -- doc #69), and never removes fuel already above what the
-- rate alone would have given (doc #85: this system only ever adds).
function H.workshopRefuelVehicle(vehicle, elapsedDays)
    local tank = vehicle:getPartById("GasTank")
    if not tank then return end
    local capacity = tank:getContainerCapacity()
    if not capacity or capacity <= 0 then return end
    local current = tank:getContainerContentAmount()
    local gain = capacity * (WORKSHOP_FUEL_PERCENT_PER_DAY_AT_MAX / 100) * elapsedDays
    local target = math.min(capacity, current + gain)
    if target > current then
        tank:setContainerContentAmount(target)
        vehicle:transmitPartModData(tank)
    end
end

-- Battery CHARGE (0.0..1.0, separate from the battery part's own condition,
-- which the repair pass above already covers) -- gated to level
-- WORKSHOP_BATTERY_MIN_LEVEL (5) and above per explicit user request (levels
-- 1-4 repair parts only, no battery charging at all); still scales with
-- level within that range, per the doc's own #86 ("todos os níveis podem
-- eventualmente chegar a 100% de carga, nível define velocidade"). Mirrors
-- vanilla's own VehicleUtils.chargeBattery exactly (server/Vehicles/
-- Vehicles.lua): reads getCurrentUsesFloat(), writes setUsedDelta(), syncs
-- via transmitPartUsedDelta. Does nothing if there is no battery installed --
-- never creates one (doc #33/#68).
function H.workshopChargeBattery(vehicle, level, elapsedDays)
    local battery = vehicle:getBattery()
    if not battery or battery:isInventoryItemUninstalled() then return end
    local item = battery:getInventoryItem()
    if not item then return end
    local current = item:getCurrentUsesFloat()
    local gain = (level * WORKSHOP_BATTERY_PERCENT_PER_DAY_PER_LEVEL / 100) * elapsedDays
    local target = math.min(1.0, current + gain)
    if target > current then
        item:setUsedDelta(target)
        vehicle:transmitPartUsedDelta(battery)
    end
end

-- One vehicle's worth of eligibility + processing. `seen` is the current
-- tick's set of loaded vehicle ids, used by workshopMaintTick below to prune
-- state for anything no longer loaded.
function H.workshopProcessVehicle(vehicle, seen)
    local id = vehicle:getId()
    seen[id] = true

    local factionName = Claims.factionAt(math.floor(vehicle:getX()), math.floor(vehicle:getY()))
    local faction = factionName and FF.getData().factions[factionName]
    local level = faction and FF.upgradeLevel(faction, "workshop") or 0

    -- Only a CONFIRMED protection entry (see LFS_VehicleGuard.lua's header
    -- comment and workshopProtectionConfirmTick below) makes a vehicle
    -- eligible -- this is what stops any random vehicle merely parked/passing
    -- through the territory from getting free maintenance; a faction has to
    -- explicitly claim it via PROTEGER first.
    local isProtected = false
    if faction then
        FF.ensureVehicleGuard(faction)
        local entry = faction.vehicles.protected[id]
        isProtected = entry ~= nil and entry.protectedAt ~= nil
    end

    -- Eligibility is territorial (claim + upgrade level) AND protection --
    -- no stopped/engine-off requirement, see this section's header comment.
    -- Losing eligibility (leaving the claim, the upgrade being lost, or the
    -- protection itself being removed) drops all state -- re-entering later
    -- starts the clock fresh, never with banked time (doc #46/#48).
    if level <= 0 or not isProtected then
        workshopVehicleState[id] = nil
        return
    end

    local now = getGameTime():getWorldAgeHours()
    local state = workshopVehicleState[id]
    if not state then
        -- Just became eligible: start the clock now, no catch-up for time
        -- spent ineligible before this (doc #47).
        workshopVehicleState[id] = { lastHours = now, carry = {} }
        return
    end

    local elapsedHours = now - state.lastHours
    state.lastHours = now
    if elapsedHours <= 0 then return end
    local elapsedDays = elapsedHours / 24.0

    -- Level can change (upgrade/downgrade, claim conquest) while the vehicle
    -- stays continuously eligible -- the new cap/rate just applies from here
    -- on, existing repair carry is not discarded (doc #49/#105).
    H.workshopRepairVehicle(vehicle, level, elapsedDays, state.carry)
    if level >= WORKSHOP_BATTERY_MIN_LEVEL then
        H.workshopChargeBattery(vehicle, level, elapsedDays)
    end
    if level >= 10 then
        H.workshopRefuelVehicle(vehicle, elapsedDays)
    end
end

-- Walks EVERY loaded vehicle via the Java Iterator protocol -- see this
-- section's header comment for why (getCell():getVehicles() is a HashSet,
-- get(int) isn't valid on it, and a radius-scan-around-players fallback was
-- explicitly rejected: maintenance must not depend on a player being near
-- any given vehicle). The whole walk is one pcall: if :iterator()/:hasNext()/
-- :next() are for some reason not exposed the way every other Java
-- Collection method verified this session has been, this fails ONCE
-- (workshopIteratorWarned) rather than crashing or wiping state every tick.
local function workshopMaintTick()
    local now = getTimestamp()
    if now < nextWorkshopTick then return end
    nextWorkshopTick = now + WORKSHOP_TICK_INTERVAL

    local cell = getCell()
    local vehicles = cell and cell:getVehicles()
    if not vehicles then return end

    local seen = {}
    local ok, err = pcall(function()
        local it = vehicles:iterator()
        while it:hasNext() do
            local vehicle = it:next()
            if vehicle and not seen[vehicle:getId()] then
                -- One vehicle's failure (a modded part throwing on an
                -- unexpected call, say) must never stop maintenance on every
                -- other loaded vehicle this tick (doc #72).
                local pok, perr = pcall(H.workshopProcessVehicle, vehicle, seen)
                if not pok then
                    FF.warn("workshop maintenance: vehicle " .. tostring(vehicle:getId())
                        .. " failed: " .. tostring(perr))
                end
            end
        end
    end)

    if not ok then
        if not workshopIteratorWarned then
            workshopIteratorWarned = true
            FF.warn("workshop maintenance: vehicle iteration failed: " .. tostring(err)
                .. " (will keep retrying every tick; this message will not repeat)")
        end
        return -- nothing was actually seen this tick -- do not prune real state below
    end

    for id in pairs(workshopVehicleState) do
        if not seen[id] then workshopVehicleState[id] = nil end
    end
end
FF._replaceServerHook(Events.OnTick, "_serverWorkshopMaintTick", workshopMaintTick)

-- ---------------------------------------------------------------------------
-- Vehicle protection & anti-theft locks (see LFS_VehicleGuard.lua for the
-- shared data model this section reads/writes -- faction.vehicles.protected
-- and .locked, both keyed by vehicle:getId())
-- ---------------------------------------------------------------------------
-- PROTEGER: a member requests protection on a vehicle currently inside their
-- own faction's territory (Handlers.requestProtectVehicle records the
-- request but does NOT confirm it yet). workshopProtectionConfirmTick, below,
-- waits FF.VEHICLE_PROTECT_CONFIRM_HOURS of GAME time, then re-checks the
-- vehicle is STILL in that same faction's territory with no non-member
-- aboard before actually confirming it (protectedAt gets set) -- this delay
-- and re-check exist specifically so a faction cannot instantly "steal"
-- maintenance rights over a stranger's car that merely happened to be
-- driving through the moment the button was clicked (explicit user design,
-- not a guess). Only a CONFIRMED entry makes workshopMaintTick actually
-- repair the vehicle. Faction losing power later never strips an
-- already-confirmed protection -- FF.vehicleProtectionLimit is only ever
-- checked when a NEW request is made.
--
-- TRANCAR: immediate, no delay, no re-check -- a locked vehicle blocks entry
-- and towing by anyone not a current member of the locking faction, enforced
-- continuously by workshopVehicleGuardTick below (not a one-time check).
-- Independent of protection -- a vehicle can be locked, protected, both, or
-- neither.
--
-- Player-vs-NPC detection uses instanceof(character, "IsoPlayer") --
-- confirmed real, server-side vanilla usage (server/Vehicles/Vehicles.lua's
-- own driver-authorization code uses this exact call), not guessed. Seat
-- iteration (0-indexed, getCharacter(seat) may be nil) matches the pattern
-- used throughout vanilla's own ISVehicleMenu.lua/ISVehicleSeatUI.lua.
-- Detaching a tow uses vehicle:breakConstraint(true, false) -- not a guess:
-- it is the exact call vanilla's own server/Vehicles/VehicleCommands.lua
-- Commands.detachTrailer makes. Ejecting an occupant uses vehicle:exit(char)
-- -- proven only in CLIENT TimedActions (ISExitVehicle.lua/ISEnterVehicle.lua)
-- in vanilla source, never found called from plain server code, so unlike
-- breakConstraint this one is reasoned-not-proven for this exact
-- server-initiated context; needs live confirmation same as the vehicle
-- Set-iterator fix earlier in this file did.
local PROTECT_CONFIRM_TICK_INTERVAL = 20 -- real seconds; the real threshold is 1 GAME hour, so coarse polling is fine
-- Real seconds, deliberately short -- this IS the anti-theft response time.
-- Was 3s; dropped to 1s after live testing showed 3s left enough of a window
-- for a persistent player to start the engine (or even inch the vehicle)
-- before getting ejected. Cheap to run this often: each pass only resolves
-- the already-known locked-vehicle ids via getVehicleById, never scans/
-- iterates the full loaded-vehicle set.
local GUARD_TICK_INTERVAL = 1
local nextProtectConfirmTick = 0
local nextGuardTick = 0

-- Debug-only: usernames currently opted into "treat me as an outsider for my
-- OWN faction's locked vehicles" (Handlers.debugToggleLockSelfTest below),
-- purely so a solo tester can confirm the guard tick actually ejects/blocks
-- without needing a second account. In-memory, never persisted, resets on
-- restart -- exactly like workshopVehicleState above.
local debugIgnoreOwnLock = {}

function H.vehicleRawName(vehicle)
    local ok, script = pcall(function() return vehicle:getScript() end)
    if not (ok and script) then return "vehicle" end
    local ok2, n = pcall(function() return script:getCarModelName() or script:getName() end)
    return (ok2 and n) or "vehicle"
end

-- True if any current occupant is a player who is NOT a member of
-- `factionName`. Used both as the initial guard on a protection REQUEST
-- (doc-independent, explicit user request: "impedir de sequer começar a
-- proteger se tiver alguém dentro dele que não é da facção") and again at
-- confirmation time (same reasoning applies to whoever may have entered
-- during the wait).
function H.vehicleHasOutsiderOccupant(vehicle, factionName)
    local ok, maxSeats = pcall(function() return vehicle:getMaxPassengers() end)
    if not ok or type(maxSeats) ~= "number" then return true end -- fail closed
    for seat = 0, maxSeats - 1 do
        local pok, occ = pcall(function() return vehicle:getCharacter(seat) end)
        if not pok then return true end
        if pok and occ and instanceof(occ, "IsoPlayer") then
            local uok, username = pcall(function() return FF.identityUsername(occ) end)
            if not uok then return true end
            if username then
                local occFaction = FF.getFactionOfPlayer(username)
                if occFaction ~= factionName then return true end
            end
        end
    end
    return false
end

-- ---------------------------------------------------------------------------
-- PROTEGER
-- ---------------------------------------------------------------------------
function Handlers.requestProtectVehicle(player, args)
    local username = FF.identityUsername(player)
    local name, faction = FF.getFactionOfPlayer(username)
    if not faction then return end
    FF.ensureRoles(faction)
    FF.ensureVehicleGuard(faction)
    if not FF.roleCan(faction, username, "protectVehicles") then return notify(player, "not_authorised") end

    local requestedId = tonumber(args and args.vehicleId)
    if not requestedId or requestedId ~= requestedId or requestedId == math.huge
        or requestedId == -math.huge or requestedId < 0 or requestedId > 2147483647 then
        return notify(player, "vehicle_not_found")
    end
    requestedId = math.floor(requestedId)
    local vehicle = getVehicleById(requestedId)
    if not vehicle then
        notify(player, "vehicle_not_found")
        return
    end
    local id = vehicle:getId()
    if faction.vehicles.protected[id] then
        return -- already requested/protected -- nothing to do
    end
    -- One persistent vehicle id must have at most one protecting faction. Without
    -- this, a moved vehicle could be registered/locked by several factions and the
    -- guard outcome depended on table iteration order.
    for otherName, other in pairs(FF.getData().factions) do
        if otherName ~= name then
            FF.ensureVehicleGuard(other)
            if other.vehicles.protected[id] then
                return notify(player, "vehicle_protect_failed", H.vehicleRawName(vehicle))
            end
        end
    end

    local factionAtVehicle = Claims.factionAt(math.floor(vehicle:getX()), math.floor(vehicle:getY()))
    if factionAtVehicle ~= name then
        notify(player, "vehicle_not_in_territory")
        return
    end

    if H.vehicleHasOutsiderOccupant(vehicle, name) then
        notify(player, "vehicle_protect_occupant_blocked")
        return
    end

    local opts = FF.getOptions()
    if FF.vehicleProtectionCount(faction) >= FF.vehicleProtectionLimit(faction, opts) then
        notify(player, "vehicle_protect_limit", tostring(FF.vehicleProtectionLimit(faction, opts)))
        return
    end

    local vname = H.vehicleRawName(vehicle)
    faction.vehicles.protected[id] = {
        requestedAt = getGameTime():getWorldAgeHours(),
        protectedAt = nil,
        name = vname,
    }
    FF.sync()
    notifyFaction(name, "vehicle_protect_requested", vname)
end

-- Unprotecting also clears any lock -- TRANCAR is only ever available for a
-- confirmed-protected vehicle (see Handlers.toggleLockVehicle), so a vehicle
-- can never be left locked-but-unprotected after this.
function Handlers.unprotectVehicle(player, args)
    local username = FF.identityUsername(player)
    local name, faction = FF.getFactionOfPlayer(username)
    if not faction then return end
    FF.ensureRoles(faction)
    FF.ensureVehicleGuard(faction)
    if not FF.roleCan(faction, username, "protectVehicles") then return notify(player, "not_authorised") end
    if faction.vehicles.protected[args.vehicleId] then
        faction.vehicles.protected[args.vehicleId] = nil
        faction.vehicles.locked[args.vehicleId] = nil
        FF.sync()
    end
end

-- Every PROTECT_CONFIRM_TICK_INTERVAL, walks every faction's still-pending
-- (protectedAt == nil) protection requests and confirms or drops each one
-- once FF.VEHICLE_PROTECT_CONFIRM_HOURS of game time have elapsed since it
-- was requested. See this section's header comment for why the delay and
-- re-check exist.
local function workshopProtectionConfirmTick()
    local now = getTimestamp()
    if now < nextProtectConfirmTick then return end
    nextProtectConfirmTick = now + PROTECT_CONFIRM_TICK_INTERVAL

    local nowHours = getGameTime():getWorldAgeHours()
    for factionName, faction in pairs(FF.getData().factions) do
        FF.ensureVehicleGuard(faction)
        for id, entry in pairs(faction.vehicles.protected) do
            if not entry.protectedAt and (nowHours - (entry.requestedAt or nowHours)) >= FF.VEHICLE_PROTECT_CONFIRM_HOURS then
                local ok, err = pcall(function()
                    local vehicle = getVehicleById(id)
                    if not vehicle then
                        -- Not currently loaded (no player anywhere near its
                        -- chunk) -- this is NOT the same as "left the
                        -- territory" or "has an outsider aboard", so it must
                        -- not be treated as a failure. Protection is meant to
                        -- be a persistent faction decision, not something
                        -- that can fail purely because nobody happened to be
                        -- standing nearby at the exact confirmation instant.
                        -- Just wait -- the next tick where it happens to be
                        -- loaded again will confirm or fail it correctly.
                        return
                    end
                    local stillEligible = Claims.factionAt(math.floor(vehicle:getX()), math.floor(vehicle:getY())) == factionName
                        and not H.vehicleHasOutsiderOccupant(vehicle, factionName)
                    if stillEligible then
                        entry.protectedAt = nowHours
                        FF.sync()
                        notifyFaction(factionName, "vehicle_protect_confirmed", entry.name)
                    else
                        -- Never confirmed -- was never eligible to be locked
                        -- either, but clear it anyway in case something set it
                        -- through a path other than the normal gate.
                        faction.vehicles.protected[id] = nil
                        faction.vehicles.locked[id] = nil
                        FF.sync()
                        notifyFaction(factionName, "vehicle_protect_failed", entry.name)
                    end
                end)
                if not ok then
                    FF.warn("vehicle protection confirm: id " .. tostring(id) .. " failed: " .. tostring(err))
                    faction.vehicles.protected[id] = nil
                    faction.vehicles.locked[id] = nil
                    FF.sync()
                end
            end
        end
    end
end
FF._replaceServerHook(Events.OnTick, "_serverWorkshopProtectionConfirmTick", workshopProtectionConfirmTick)

-- ---------------------------------------------------------------------------
-- TRANCAR
-- ---------------------------------------------------------------------------
-- Locking requires a CONFIRMED protection entry -- explicit user requirement:
-- "só se deve poder trancar/destrancar veículos que já estão protegidos".
-- This is the real security boundary (the client-side button gate in
-- LFS_Panel.lua is only a UI convenience, never trust it alone). Unlocking a
-- vehicle that somehow lost protection out from under it (see
-- Handlers.unprotectVehicle / workshopProtectionConfirmTick, which already
-- clear the lock themselves) is still allowed either way -- never worth
-- blocking someone from clearing a lock that shouldn't exist anymore.
function Handlers.toggleLockVehicle(player, args)
    local username = FF.identityUsername(player)
    local name, faction = FF.getFactionOfPlayer(username)
    if not faction then return end
    FF.ensureRoles(faction)
    FF.ensureVehicleGuard(faction)
    if not FF.roleCan(faction, username, "protectVehicles") then return notify(player, "not_authorised") end
    local id = args.vehicleId

    if args.locked then
        local entry = faction.vehicles.protected[id]
        if not (entry and entry.protectedAt) then
            notify(player, "vehicle_lock_needs_protect")
            return
        end
        local vehicle = getVehicleById(id)
        if not vehicle then
            notify(player, "vehicle_not_found")
            return
        end
        local factionAtVehicle = Claims.factionAt(math.floor(vehicle:getX()), math.floor(vehicle:getY()))
        -- Level 10 Oficina: TRANCAR can be switched ON even while the
        -- vehicle is currently outside the territory -- explicit user
        -- clarification, same threshold as FF.vehicleLockBlocksCharacter's
        -- own anywhere-exemption (LFS_VehicleGuard.lua) so both halves of
        -- "level 10 locks anywhere" agree on the same number. DESTRANCAR
        -- (the `else` branch below) has never had a territory requirement at
        -- all -- confirmed correct as-is, nothing to change there.
        local lockAnywhere = FF.upgradesActive(faction)
            and FF.upgradeLevel(faction, "workshop") >= FF.LOCK_ANYWHERE_WORKSHOP_LEVEL
        if factionAtVehicle ~= name and not lockAnywhere then
            notify(player, "vehicle_not_in_territory")
            return
        end
        faction.vehicles.locked[id] = true
    else
        faction.vehicles.locked[id] = nil
    end
    FF.sync()
end

-- Debug-only, see debugIgnoreOwnLock above.
function Handlers.debugToggleLockSelfTest(player, args)
    if not FF.getOptions().debugToolsEnabled then
        return notify(player, "debug_tools_disabled")
    end
    if not isAdminPlayer(player) then return notify(player, "not_authorised") end
    debugIgnoreOwnLock[FF.identityUsername(player)] = args.enabled and true or nil
end

-- Every GUARD_TICK_INTERVAL, walks every LOCKED vehicle across every faction
-- (resolved directly by id via getVehicleById -- no need to scan/iterate all
-- loaded vehicles for this, unlike workshopMaintTick, since the exact set of
-- ids to check is already known from the registry) and:
--  (a) ejects any player occupant who is not a current member of the locking
--      faction (or who has the debug self-test flag on);
--  (b) breaks the tow connection if the vehicle is currently being towed by
--      a vehicle driven by a non-member.
-- Both checks are pcall-isolated per vehicle -- one bad entry (a vehicle that
-- no longer exists, a modded vehicle throwing on an unexpected call) must
-- never stop enforcement on every other locked vehicle this tick.
function H.isOutsider(username, factionName)
    if debugIgnoreOwnLock[username] then return true end
    return FF.getFactionOfPlayer(username) ~= factionName
end

function H.workshopVehicleGuardTick()
    local now = getTimestamp()
    if now < nextGuardTick then return end
    nextGuardTick = now + GUARD_TICK_INTERVAL

    for factionName, faction in pairs(FF.getData().factions) do
        FF.ensureVehicleGuard(faction)
        for id in pairs(faction.vehicles.locked) do
            local ok, err = pcall(function()
                local vehicle = getVehicleById(id)
                if not vehicle then return end

                local maxSeats = vehicle:getMaxPassengers()
                for seat = 0, maxSeats - 1 do
                    local occ = vehicle:getCharacter(seat)
                    if occ and instanceof(occ, "IsoPlayer") then
                        local username = occ:getUsername()
                        if username and H.isOutsider(username, factionName) then
                            vehicle:exit(occ)
                            vehicle:setCharacterPosition(occ, seat, "outside")
                            notify(occ, "vehicle_kicked_locked", factionName)
                        end
                    end
                end

                local towedBy = vehicle:getVehicleTowedBy()
                if towedBy then
                    local towDriver = towedBy:getDriverRegardlessOfTow()
                    local tok, towUsername = pcall(function() return towDriver and towDriver:getUsername() end)
                    if towDriver and instanceof(towDriver, "IsoPlayer") and tok and towUsername
                            and H.isOutsider(towUsername, factionName) then
                        vehicle:breakConstraint(true, false)
                        notifyFaction(factionName, "vehicle_tow_detached")
                    end
                end
            end)
            if not ok then
                FF.warn("vehicle guard: locked vehicle id " .. tostring(id) .. " failed: " .. tostring(err))
            end
        end
    end
end
FF._replaceServerHook(Events.OnTick, "_serverWorkshopVehicleGuardTick", H.workshopVehicleGuardTick)

-- ---------------------------------------------------------------------------
-- Caçador upgrade: approximate detection of non-member players near the
-- faction's territory. Full design/rationale in shared/LFS_Hunter.lua's own
-- header comment -- this is the server-authoritative half: reads REAL
-- player positions (never sent to a client as-is), decides who is currently
-- "detectable" for which faction, and maintains each detected player's
-- speculation circle. LFS_ClaimMap.lua (client) only ever reads the
-- resulting circle (cx, cy, radius, name) -- it never sees a real position.
-- ---------------------------------------------------------------------------
local HUNTER_TICK_INTERVAL = 60 -- real seconds; coarse poll, real threshold is 1 game hour per tracked target
local nextHunterTick = 0

-- Debug-only: usernames currently opted into "treat me as a non-member for my
-- OWN faction's Caçador detection", same purpose/shape as
-- debugIgnoreOwnLock above -- lets a solo tester see themselves appear as a
-- detected blip on their own faction's map without a second account.
local debugIgnoreOwnHunterMembership = {}

function H.isHunterOutsider(username, factionName)
    if debugIgnoreOwnHunterMembership[username] then return true end
    return not FF.isMemberOf(factionName, username)
end

-- Is `t` non-empty? Uses pairs, not next() -- the PZ B42 Kahlua sandbox does
-- not expose next() as a global (confirmed crash: "Object tried to call nil
-- in pcall"), same gotcha client/LFS_Borders.lua's own hasMarkers() already
-- documents. Grep for `next(` before ever reaching for it again anywhere in
-- this mod.
function H.hasAny(t)
    for _ in pairs(t) do return true end
    return false
end

function H.hunterTrackingTick()
    local now = getTimestamp()
    if now < nextHunterTick then return end
    nextHunterTick = now + HUNTER_TICK_INTERVAL

    local nowHours = getGameTime():getWorldAgeHours()
    local roster = onlinePlayers()

    for factionName, faction in pairs(FF.getData().factions) do
        local ok, err = pcall(function()
            local level = FF.upgradeLevel(faction, "hunter")
            local active = FF.upgradesActive(faction)
            if level <= 0 or not active then
                -- Effect paused (no level yet, or claim inactive) -- clear
                -- any stale tracking rather than leaving old circles visible
                -- once the upgrade stops applying, same "pauses, doesn't
                -- linger" rule every other upgrade effect follows.
                if faction.hunter and H.hasAny(faction.hunter.detected) then
                    faction.hunter.detected = {}
                    FF.sync()
                end
                return
            end
            FF.ensureHunterTracking(faction)
            local detected = faction.hunter.detected
            local maxRange = FF.hunterMaxRange(level)
            local revealName = level >= 10
            local changed = false
            local stillInRange = {}

            for _, entry in ipairs(roster) do
                local username = entry.user
                local outsider = username and H.isHunterOutsider(username, factionName)
                if username and outsider then
                    local okPos, px, py = pcall(function() return entry.p:getX(), entry.p:getY() end)
                    if okPos then
                        -- Euclidean, not FF.distanceToClaim's Chebyshev -- a
                        -- detection RADIUS should read as circular around the
                        -- territory, not a square. See FF.hunterDistanceToClaim's
                        -- own comment (shared/LFS_Hunter.lua) for why this is a
                        -- separate metric from the claim-adjacency one elsewhere.
                        local distance = FF.hunterDistanceToClaim(faction, px, py)
                        if distance and distance <= maxRange then
                            stillInRange[username] = true
                            -- Debug-only live telemetry, ONLY for usernames currently under
                            -- the self-test flag -- unlike `detected` (the production
                            -- estimate, deliberately stale between refreshes), this updates
                            -- EVERY tick regardless of whether a new circle was generated,
                            -- so Debug > Caçador can show real position/live distance while
                            -- the tester watches, per explicit ask ("deve atualizar em tempo
                            -- real... a distância em tempo real que o jogador está do
                            -- território"). Real position is fine to expose here -- this is
                            -- the author's own debug tool, already established as more
                            -- revealing than the production map.
                            if debugIgnoreOwnHunterMembership[username] then
                                faction.hunter.debugLive = faction.hunter.debugLive or {}
                                faction.hunter.debugLive[username] = { px = px, py = py, distance = distance, at = nowHours }
                                changed = true
                            end
                            -- Refresh cadence: NO per-level scaling, no game-hour interval
                            -- of any kind -- the user explicitly asked to rip that out
                            -- ("vamos tirar essa praga de atualização diferente entre
                            -- níveis, botar fixamente 60 segundos"). The circle simply
                            -- regenerates the moment the target is found outside it, on
                            -- whichever real-time poll notices that -- HUNTER_TICK_INTERVAL
                            -- (60 real seconds, below) is the ONLY cadence in the system now,
                            -- same for every level.
                            local existing = detected[username]
                            local needsNew = not existing
                            if existing and not FF.hunterPointInCircle(px, py, existing.cx, existing.cy, existing.radius) then
                                needsNew = true
                            end
                            if needsNew then
                                local radius = FF.hunterCircleRadius(distance, level)
                                local cx, cy = FF.hunterRandomPointNear(px, py, radius)
                                detected[username] = {
                                    cx = cx, cy = cy, radius = radius, at = nowHours,
                                    name = revealName and username or nil,
                                }
                                changed = true
                            elseif revealName ~= (existing.name ~= nil) then
                                -- Level just crossed the 10 threshold either way --
                                -- flip the name's visibility without waiting for
                                -- the circle itself to need regenerating.
                                existing.name = revealName and username or nil
                                changed = true
                            end
                        end
                    end
                end
            end

            -- Purge anyone no longer online, no longer an outsider, or now
            -- out of range -- the range cap must be a live filter, not just
            -- a one-time gate at first detection.
            for username in pairs(detected) do
                if not stillInRange[username] then
                    detected[username] = nil
                    changed = true
                end
            end
            if faction.hunter.debugLive then
                for username in pairs(faction.hunter.debugLive) do
                    if not stillInRange[username] then
                        faction.hunter.debugLive[username] = nil
                        changed = true
                    end
                end
            end

            if changed then FF.sync() end
        end)
        if not ok then
            FF.warn("hunter tracking: faction " .. tostring(factionName) .. " failed: " .. tostring(err))
        end
    end
end
FF._replaceServerHook(Events.OnTick, "_serverHunterTrackingTick", H.hunterTrackingTick)
FF.checkpoint("hunter tracking tick registered")

-- Debug-only, see debugIgnoreOwnHunterMembership above.
function Handlers.debugToggleHunterSelfTest(player, args)
    if not FF.getOptions().debugToolsEnabled then
        return notify(player, "debug_tools_disabled")
    end
    if not isAdminPlayer(player) then return notify(player, "not_authorised") end
    local username = FF.identityUsername(player)
    debugIgnoreOwnHunterMembership[username] = args.enabled and true or nil
end

-- Debug-only: forces hunterTrackingTick's own throttle open on the very next
-- Events.OnTick (near-instant, engine ticks run far more than once a real
-- second) instead of waiting up to HUNTER_TICK_INTERVAL (60 real seconds) --
-- so a tester can walk out of their circle and see the result immediately
-- rather than sitting around. Reuses the EXACT same scan/regen/purge logic
-- (just makes it run sooner), so there is no separate "forced scan" code
-- path to drift out of sync with the real one.
function Handlers.debugForceHunterScan(player, args)
    if not FF.getOptions().debugToolsEnabled then
        return notify(player, "debug_tools_disabled")
    end
    if not isAdminPlayer(player) then return notify(player, "not_authorised") end
    nextHunterTick = 0
end

-- ---------------------------------------------------------------------------
-- The canonical faction-name reference walk
-- ---------------------------------------------------------------------------
-- A faction's NAME is its primary key, and a dozen other places store that name as a
-- foreign key. Three operations need to walk exactly the same list:
--
--   rename  -- move every reference from one name to another
--   disband -- drop every reference to a faction that is going away
--   purge   -- drop every reference to a faction that already went away
--
-- They are ONE traversal with three predicates rather than three hand-maintained
-- copies, because the copies drift. Handlers.adminDisband already carries a comment
-- about the time it fell out of step with Handlers.disband, and before this existed
-- every table below was leaked by all three teardown paths: a disbanded faction went
-- on sitting in other factions' relations and appearing in job applications forever.
-- Adding a new faction-keyed table means
-- editing this one function, and rename, disband and purge all learn about it at once.
--
--   matches(name) -> should this reference be touched?
--   replacement   -> the new name, or nil to DROP the reference
--   report        -> optional accumulator: [site] = count, plus .names (a set) and .total
--   dryRun        -> count into `report` and change nothing. It is a flag on this walk
--                    rather than a separate counting pass on purpose: a second pass
--                    would be a second copy of the site list, which is the one thing
--                    this function exists to prevent.
--
-- A non-nil `replacement` only makes sense with an equality predicate -- remapping
-- every dead faction onto a single new name would be nonsense -- so FF.remapFactionRefs
-- is the only caller that passes one.
--
-- Kept in one canonical walker so rename, disband and purge cannot drift apart.
--
-- LUA RULE observed throughout: assigning nil to an existing key during pairs() is
-- safe, but ADDING a key is undefined. Every re-key therefore collects into a scratch
-- list and applies it after the loop.
local function walkFactionRefs(matches, replacement, report, dryRun)
    local data = FF.getData()
    local drop = (replacement == nil)
    local apply = not dryRun

    local function hit(site, name)
        if not report then return end
        report[site] = (report[site] or 0) + 1
        report.total = (report.total or 0) + 1
        report.names = report.names or {}
        report.names[name] = true
    end

    -- Re-key (or drop) a table keyed by faction name. `merge` combines values when the
    -- destination key is already taken; without it the last write wins.
    local function rekey(tbl, site, merge)
        if not tbl then return end
        local taken
        for key, value in pairs(tbl) do
            if matches(key) then
                hit(site, key)
                taken = taken or {}
                taken[#taken + 1] = value
                if apply then tbl[key] = nil end
            end
        end
        if taken and replacement and apply then
            local value = taken[1]
            if merge then
                for i = 2, #taken do value = merge(value, taken[i]) end
                if tbl[replacement] ~= nil then value = merge(tbl[replacement], value) end
            end
            tbl[replacement] = value
        end
    end

    -- 1. Reverse index: username -> faction name. A VALUE scan, not a walk of the
    -- faction's own member list, so it also catches rows whose faction record has
    -- already vanished -- which is exactly what purge exists for. This supersedes the
    -- `for user in pairs(faction.members)` loop the three disband paths each had.
    for user, fname in pairs(data.playerIndex or {}) do
        if matches(fname) then
            hit("playerIndex", fname)
            if apply then data.playerIndex[user] = replacement end   -- nil deletes the row
        end
    end

    -- 2-4. Every OTHER faction's references to this one. The subject's own record is
    -- skipped: on a drop it is about to be deleted wholesale, and on a rename it has
    -- already been moved to the new key by the caller.
    for fname, faction in pairs(data.factions or {}) do
        if not matches(fname) then
            -- 2. Plain ally/enemy relations. dissolveWarsFor only clears the ones a WAR
            -- set, so a relation agreed outside a war survived every teardown.
            rekey(faction.relations, "relations")
            -- 3. Outstanding requests. allyRespond nil-guards a dead target so these
            -- self-heal on next interaction, but until then they render in the UI.
            rekey(faction.allyRequests, "allyRequests")
            rekey(faction.pactRequests, "pactRequests")

            -- 4. A raid this faction is DEFENDING against the subject. Dropping it needs
            -- the same teardown the normal end-of-raid path does, or the defender is left
            -- with loot exposure flipped on and a raid banner that never clears.
            local raid = faction.raid
            if raid and raid.attacker and matches(raid.attacker) then
                hit("raids", raid.attacker)
                if apply then
                    if replacement then
                        raid.attacker = replacement
                    else
                        local prev = raid.attacker
                        faction.raid = nil
                        debugRaidCounts[fname] = nil
                        notifyFaction(fname, "raid_abandoned", prev)
                    end
                end
            end
        end
    end

    -- 5-7. Wars, pacts and ceasefires key on FF.warKey(a,b) -- the sorted pair joined
    -- with "|" -- so a rename moves the KEY as well as the fields inside the record.
    --
    -- DISBAND AND PURGE SKIP THESE. dissolveWarsFor and clearPactsFor own that path and
    -- do considerably more than dropping a row (coalition survival, the war_dissolved
    -- broadcast, batched zone re-projection), and both have already run by the time a
    -- release reaches here.
    if replacement and apply then
        for _, spec in ipairs({ { tbl = data.wars, site = "wars" },
                                { tbl = data.pacts, site = "pacts" } }) do
            local moves
            for key, rec in pairs(spec.tbl or {}) do
                local ma, mb = rec and matches(rec.a), rec and matches(rec.b)
                if ma or mb then
                    hit(spec.site, ma and rec.a or rec.b)
                    if ma then rec.a = replacement end
                    if mb then rec.b = replacement end
                    rekey(rec.score, spec.site .. ".score")          -- wars only; nil-safe
                    rekey(rec.coalition, spec.site .. ".coalition")
                    local newKey = FF.warKey(rec.a, rec.b)
                    if newKey and newKey ~= key then
                        moves = moves or {}
                        moves[#moves + 1] = { key, newKey, rec }
                    end
                end
            end
            for _, m in ipairs(moves or {}) do
                spec.tbl[m[1]] = nil
                spec.tbl[m[2]] = m[3]
            end
        end

        -- A ceasefire stores only an expiry timestamp, so its key is the sole record of
        -- who the pair were and has to be parsed. Unambiguous because adminRename
        -- refuses a name containing "|".
        local cfMoves
        for key, expiry in pairs(data.ceasefires or {}) do
            local a, b = string.match(key, "^(.-)|(.*)$")
            local ma, mb = a and matches(a), b and matches(b)
            if ma or mb then
                hit("ceasefires", ma and a or b)
                local newKey = FF.warKey(ma and replacement or a, mb and replacement or b)
                if newKey and newKey ~= key then
                    cfMoves = cfMoves or {}
                    cfMoves[#cfMoves + 1] = { key, newKey, expiry }
                end
            end
        end
        for _, m in ipairs(cfMoves or {}) do
            data.ceasefires[m[1]] = nil
            data.ceasefires[m[2]] = m[3]
        end
    end

    -- 8. Recruitment: pending applications, and the "don't show me this faction" list.
    for _, entry in pairs(data.lff or {}) do
        rekey(entry.applications, "lff.applications")
        rekey(entry.hidden, "lff.hidden")
    end

    -- 9. Season scoring baseline.
    if data.season then rekey(data.season.baseline, "season.baseline") end

    -- 10. Server-local accumulators keyed by faction name. killLog and
    -- scoreDirtyUsers are deliberately absent: both are keyed by USERNAME.
    rekey(tributeDirtyFactions, "tributeDelta")
    rekey(debugRaidCounts, "debugRaidCounts")

    -- DELIBERATELY NOT WALKED, so nobody "fixes" the omissions later:
    --   the faction's own record, claims, zone and safehouses -- that is its state, not
    --     a reference to it; rename re-projects and disband tears down, both in the caller
    --   data.season.history[*].winner -- a record of what happened. Season 3 WAS won by
    --     that name, whatever the faction is called now
    --   faction.invites -- keyed by USERNAME, not faction name
    --   data.playerScore -- keyed by USERNAME, not faction name; a player's own current
    --     kills/hours are theirs regardless of which faction they belong to
    return report
end

-- Move every reference to `old` onto `new`. Rename only.
function FF.remapFactionRefs(old, new, report)
    if not (old and new) then return report end
    report = walkFactionRefs(function(n) return n == old end, new, report)
    local cooldowns = FF.getData().inviteCooldowns
    if cooldowns and cooldowns[old] then
        cooldowns[new] = cooldowns[old]
        cooldowns[old] = nil
    end
    return report
end

-- Drop every reference to a faction being torn down. Called by all three disband
-- paths. Does NOT sync -- every caller already ends with FF.sync().
function FF.releaseFactionRefs(name, report)
    if not name then return report end
    report = walkFactionRefs(function(n) return n == name end, nil, report)
    FF.getData().inviteCooldowns[name] = nil
    return report
end

-- Drop every reference to a faction that no longer exists. `dryRun` reports without
-- mutating, which is what the startup check uses -- see the reconcile call site for
-- why boot must never mutate.
function FF.purgeFactionRefs(dryRun)
    local data = FF.getData()
    -- A name is dead when no faction record answers to it. Evaluated live rather than
    -- snapshotted, which is what makes this safe to run over a registry that is still
    -- being mutated by the walk itself.
    local isDead = function(n) return n ~= nil and data.factions[n] == nil end
    return walkFactionRefs(isDead, nil, { total = 0, names = {} }, dryRun)
end

-- ---------------------------------------------------------------------------
-- Admin no-claim zones
-- ---------------------------------------------------------------------------
-- Areas where factions may not claim land. The rule itself is one line in
-- FF.validateClaim (shared); everything here is the admin surface plus the one
-- destructive part -- creating a zone over land that is ALREADY claimed removes the
-- overlapping areas.
--
-- Whole claim areas are removed, never clipped. Clipping a rect against a rect yields
-- up to four pieces, which could blow past the score-driven area limit, break the cluster rule, and
-- leave slivers nobody drew. Whole-area removal is also exactly what adminRemoveClaimAt
-- does, so the teardown below and the player-facing message already exist.

-- Remove every claim area overlapping `zone`. Returns a report array for the admin.
function H.stripClaimsInNoClaim(zone)
    local hits = FF.claimsInNoClaim(zone)
    if #hits == 0 then return {} end

    -- Group by faction and remove back-to-front: FF.claimsInNoClaim returns indices
    -- into faction.claims, and removing a low index shifts every higher one.
    local byFaction = {}
    for i = 1, #hits do
        local list = byFaction[hits[i].name]
        if not list then list = {}; byFaction[hits[i].name] = list end
        list[#list + 1] = hits[i].index
    end

    local report, reproj = {}, {}
    for name, indices in pairs(byFaction) do
        local faction = FF.getFaction(name)
        if faction then
            table.sort(indices, function(a, b) return a > b end)
            for i = 1, #indices do
                table.remove(faction.claims, indices[i])
            end
            if #faction.claims == 0 then
                removeFactionSafehouses(faction)
                Claims.removeFaction(name)   -- deletion is its own path, never batched
            else
                -- Collected rather than projected here: every PhunZones projection is a
                -- synchronous whole-file disk write plus a rebuild, and one no-claim zone
                -- can clip several factions at once. One batch, one write.
                reproj[#reproj + 1] = { name = name, faction = faction }
                rebuildFactionSafehouses(faction)
            end
            if faction.respawn
                and not FF.pointInClaim(faction, faction.respawn.x, faction.respawn.y) then
                faction.respawn = nil
            end
            notifyFaction(name, "claim_area_removed")
            report[#report + 1] = string.format("%s: removed %d area(s), %d left",
                name, #indices, #faction.claims)
        end
    end
    if #reproj > 0 then Claims.projectFactions(reproj) end
    table.sort(report)
    return report
end

-- Allocate the first free noclaim_N id.
function H.nextNoClaimId(data)
    local n = 1
    while data.noClaim["noclaim_" .. n] do n = n + 1 end
    return "noclaim_" .. n
end

-- Resolve the zone a command is talking about: an explicit id, or whichever zone
-- covers the tile the context menu clicked. Shared by remove/rename/resize so the three
-- can never disagree about what "this zone" means.
local function resolveNoClaim(data, args)
    local id = args and args.id
    if (not id or id == "") and args and args.x then
        local x, y = math.floor(tonumber(args.x) or 0), math.floor(tonumber(args.y) or 0)
        for zid, zone in pairs(data.noClaim or {}) do
            for i = 1, #(zone.points or {}) do
                if FF.pointInRect(x, y, zone.points[i]) then return zid, zone end
            end
        end
        return nil
    end
    return id, id and data.noClaim[id] or nil
end

-- Store the zone, strip what it now covers, sync, and report both to the admin.
--
-- Resize routes through here too, which is why there is no separate stripping path:
-- writing the record back under the SAME id and re-running stripClaimsInNoClaim over
-- the new geometry removes claims in newly covered land, and harmlessly re-checks the
-- land it already covered, where by definition no claim can exist.
local function commitNoClaim(player, zone, headline, verb)
    local data = FF.getData()
    data.noClaim[zone.id] = zone
    local stripped = H.stripClaimsInNoClaim(zone)
    FF.sync()
    FF.print(string.format("admin %s %s no-claim zone '%s' (%s); stripped %d faction area set(s)",
        tostring(player:getUsername()), verb or "added", zone.name, zone.id, #stripped))
    if #stripped == 0 then
        notify(player, headline)
    else
        table.insert(stripped, 1, headline)
        table.insert(stripped, 2, "Claims removed because they overlapped it:")
        sendReport(player, stripped)
    end
end

Handlers.adminNoClaimList = adminHandler(function(player, args)
    local lines = {}
    for id, zone in pairs(FF.getData().noClaim or {}) do
        local r = zone.points and zone.points[1]
        lines[#lines + 1] = string.format("%s [%s] %s -- %s", id, zone.source or "?",
            r and string.format("(%d,%d)-(%d,%d)%s", r[1], r[2], r[3], r[4],
                #zone.points > 1 and (" +" .. (#zone.points - 1) .. " more") or "") or "no geometry",
            tostring(zone.name))
    end
    if #lines == 0 then
        lines = { "No no-claim zones. /ff admin noclaim here [size] to add one." }
    end
    table.sort(lines)
    sendReport(player, lines)
end)

-- Rect from explicit corners, else a box centred on the admin (default 20x20).
Handlers.adminNoClaimAdd = adminHandler(function(player, args)
    local data = FF.getData()
    local x1, y1 = tonumber(args and args.x1), tonumber(args and args.y1)
    local x2, y2 = tonumber(args and args.x2), tonumber(args and args.y2)
    if not (x1 and y1 and x2 and y2) then
        local size = math.max(1, math.floor(tonumber(args and args.size) or 20))
        local half = math.floor(size / 2)
        local px, py = math.floor(player:getX()), math.floor(player:getY())
        x1, y1 = px - half, py - half
        x2, y2 = x1 + size - 1, y1 + size - 1
    end
    local rect = FF.normaliseRect({ x1, y1, x2, y2 })
    local name = args and args.name
    if not name or name == "" then
        name = string.format("Bloqueio (%d,%d)", rect[1], rect[2])
    end
    local id = H.nextNoClaimId(data)
    commitNoClaim(player, { id = id, name = name, source = "admin", points = { rect } },
        string.format("Admin: blocked claiming in '%s' (%s) at (%d,%d)-(%d,%d).",
            name, id, rect[1], rect[2], rect[3], rect[4]))
end)

-- PhunZones difficulty templates (presets, not real places) skipped when resolving
-- a zone name below.
local ZONE_NAME_TEMPLATES = {
    _default = true, Very_Easy = true, Easy = true, Normal = true,
    Medium = true, Hard = true, Very_Hard = true, void = true,
}

-- Does this resolved PhunZones zone look like a real named place (not a difficulty
-- preset, not one of our own claim zones, not void, has geometry and a title)?
function H.qualifiesAsNamedZone(zone)
    if type(zone) ~= "table" then return false end
    local key = zone.key
    if type(key) ~= "string" or key == "" then return false end
    if ZONE_NAME_TEMPLATES[key] then return false end
    if zone.isVoid then return false end
    if key:sub(1, #FF.ZONE_PREFIX) == FF.ZONE_PREFIX then return false end  -- our own claims
    if not (zone.points and zone.points[1]) then return false end
    return type(zone.title) == "string" and zone.title ~= ""
end

-- Display name for a zone: "Title -- Subtitle" when a subtitle is present.
function H.namedZoneTitle(zone)
    local title = zone.title or zone.key or "?"
    if type(zone.subtitle) == "string" and zone.subtitle ~= "" then
        return title .. " -- " .. zone.subtitle
    end
    return title
end

-- Copy a named PhunZones zone's geometry.
Handlers.adminNoClaimZone = adminHandler(function(player, args)
    local wanted = args and args.title
    if not wanted or wanted == "" then
        return notify(player, "Usage: /ff admin noclaim zone \"<zone name>\"")
    end
    local P = _G.PhunZones
    local lookup = P and P.data and P.data.lookup
    if not lookup then return notify(player, "Admin: PhunZones zone data not available.") end

    local target = wanted:lower()
    local match, matchKey
    for key, zone in pairs(lookup) do
        if H.qualifiesAsNamedZone(zone) then
            local title = H.namedZoneTitle(zone)
            if title:lower() == target or (zone.title or ""):lower() == target
                or key:lower() == target then
                match, matchKey = zone, key
                break
            end
        end
    end
    if not match then
        return notify(player, "Admin: no PhunZones zone named '" .. wanted .. "'.")
    end

    local points = {}
    for _, r in ipairs(match.points) do
        if type(r) == "table" and r[1] and r[4] then
            points[#points + 1] = FF.normaliseRect({ r[1], r[2], r[3], r[4] })
        end
    end
    if not points[1] then
        return notify(player, "Admin: zone '" .. wanted .. "' has no usable geometry.")
    end

    -- Keyed by the zone key, so re-running the command updates rather than duplicates.
    local id = "noclaim_zone_" .. matchKey
    -- Re-running this is how an admin refreshes the geometry after the map mod changed.
    -- Keep a name they set by hand: this is the one thing that can clobber a rename.
    local existing = FF.getData().noClaim[id]
    local renamed = existing and existing.renamed or nil
    local name = renamed and existing.name or H.namedZoneTitle(match)
    commitNoClaim(player, { id = id, name = name, source = "zone", points = points,
        renamed = renamed },
        string.format("Admin: blocked claiming in zone '%s' (%d area(s)).", name, #points),
        existing and "refreshed" or "added")
end)

Handlers.adminNoClaimRemove = adminHandler(function(player, args)
    local data = FF.getData()
    -- The context menu sends a tile instead of an id; resolveNoClaim handles both.
    local id, zone = resolveNoClaim(data, args)
    if not zone then
        return notify(player, "Admin: no no-claim zone '" .. tostring(id) .. "'.")
    end
    data.noClaim[id] = nil
    FF.sync()
    FF.print(string.format("admin %s removed no-claim zone '%s' (%s)",
        tostring(player:getUsername()), tostring(zone.name), id))
    notify(player, "Admin: removed no-claim zone '" .. tostring(zone.name) .. "'.")
end)

-- Rename a no-claim zone. Name only -- no geometry change, so nothing is stripped.
Handlers.adminNoClaimRename = adminHandler(function(player, args)
    local data = FF.getData()
    local id, zone = resolveNoClaim(data, args)
    if not zone then
        return notify(player, "Admin: no no-claim zone '" .. tostring(id) .. "'.")
    end
    local name = args and args.name
    if type(name) ~= "string" then name = nil end
    name = name and name:match("^%s*(.-)%s*$")
    if not name or name == "" then return notify(player, "Admin: a name is required.") end

    local was = zone.name
    zone.name = string.sub(name, 1, 48)
    -- Mark zone-sourced entries so re-running `noclaim zone "<title>"` refreshes the
    -- GEOMETRY without clobbering the admin's name. A single flag is enough because
    -- there is no auto-refresh loop here: source=="zone" is a
    -- one-shot copy, and an explicit re-run of that command is the only thing that can
    -- overwrite it.
    if zone.source == "zone" then zone.renamed = true end
    FF.sync()
    notify(player, string.format("Admin: renamed no-claim zone '%s' -- '%s' is now '%s'.",
        id, tostring(was), zone.name))
end)

-- Move or resize a no-claim zone. Rect from explicit corners, else a box centred on
-- the admin. Replaces the geometry with the single new rect and strips whatever the
-- new area now covers (via commitNoClaim).
Handlers.adminNoClaimResize = adminHandler(function(player, args)
    local data = FF.getData()
    local id, zone = resolveNoClaim(data, args)
    if not zone then
        return notify(player, "Admin: no no-claim zone '" .. tostring(id) .. "'.")
    end
    -- A zone-sourced entry is a copy of a whole PhunZones town, often many rects.
    -- Hand-editing one of them is not something an admin can reason about, and the copy
    -- is re-runnable anyway, so point them at that instead.
    if zone.source == "zone" then
        return notify(player, string.format(
            "Admin: '%s' copies a map zone's geometry (%d area(s)). Resize is for hand-drawn "
            .. "zones -- re-run /ff admin noclaim zone \"<title>\" to refresh it, or add a new one.",
            tostring(zone.name), #(zone.points or {})))
    end

    local x1, y1 = tonumber(args.x1), tonumber(args.y1)
    local x2, y2 = tonumber(args.x2), tonumber(args.y2)
    if not (x1 and y1 and x2 and y2) then
        local size = math.max(1, math.floor(tonumber(args.size) or 20))
        local half = math.floor(size / 2)
        local px, py = math.floor(player:getX()), math.floor(player:getY())
        x1, y1 = px - half, py - half
        x2, y2 = x1 + size - 1, y1 + size - 1
    end
    local rect = FF.normaliseRect({ x1, y1, x2, y2 })

    commitNoClaim(player, {
        id = zone.id, name = zone.name, source = "admin",
        points = { rect }, renamed = zone.renamed,
    }, string.format("Admin: resized no-claim zone '%s' to (%d,%d)-(%d,%d). Claims inside the "
        .. "area it no longer covers are NOT restored.",
        tostring(zone.name), rect[1], rect[2], rect[3], rect[4]), "resized")
end)

Handlers.adminNoClaimClear = adminHandler(function(player, args)
    local data = FF.getData()
    local n = 0
    for _ in pairs(data.noClaim or {}) do n = n + 1 end
    data.noClaim = {}
    FF.sync()
    FF.print(string.format("admin %s cleared all %d no-claim zone(s)",
        tostring(player:getUsername()), n))
    notify(player, string.format("Admin: cleared %d no-claim zone(s).", n))
end)

FF.checkpoint("no-claim zones ready")

-- ---------------------------------------------------------------------------
-- Claim decay (real-world clock)
-- ---------------------------------------------------------------------------
-- A faction is "abandoned" when none of its members have been online for
-- ClaimDecayDays of REAL-WORLD time. activityTick stamps faction.lastActive (a
-- Calendar epoch, so it survives restarts) whenever a member is online; decayTick
-- disbands any faction past the threshold and warns once inside the warn window.
local ACTIVITY_INTERVAL = 60         -- seconds between activity stamps
local DECAY_INTERVAL = 300           -- seconds between decay sweeps
local nextActivityTick = 0
local nextDecayTick = 0
local DAY_MS = 86400 * 1000

-- Long-lived per-user replay/cooldown maps otherwise grow forever and are part of
-- every full registry replication. Sweep on the existing activity tick (no extra
-- OnTick callback): only once per six real hours, and retain 90 days of inactivity.
FF._persistentStateGcNextMs = tonumber(FF._persistentStateGcNextMs) or 0
function FF._runPersistentStateGc(force)
    local ms = nowMs()
    if not force and ms < FF._persistentStateGcNextMs then return false end
    FF._persistentStateGcNextMs = ms + 6 * 60 * 60 * 1000
    local cutoffMs = ms - 90 * DAY_MS
    local cutoffSec = math.floor(cutoffMs / 1000)
    local data = FF.getData()
    local removed, changed = 0, false

    for factionName, bucket in pairs(data.inviteCooldowns) do
        if type(bucket) ~= "table" or not data.factions[factionName] then
            data.inviteCooldowns[factionName] = nil
            removed, changed = removed + 1, true
        else
            for username, rec in pairs(bucket) do
                local last = type(rec) == "table" and math.max(
                    tonumber(rec.lastDeclinedAt) or 0, tonumber(rec.untilAt) or 0) or 0
                if last <= 0 or last < cutoffSec then
                    bucket[username] = nil
                    removed, changed = removed + 1, true
                end
            end
            if FF.isEmpty(bucket) then
                data.inviteCooldowns[factionName] = nil
                changed = true
            end
        end
    end

    for username, cache in pairs(data.tributeRequests) do
        if type(cache) ~= "table" then
            data.tributeRequests[username] = nil
            removed, changed = removed + 1, true
        else
            if type(cache.recentResults) ~= "table" then cache.recentResults = {}; changed = true end
            if type(cache.recentOrder) ~= "table" then cache.recentOrder = {}; changed = true end
            local processing = false
            for _, result in pairs(cache.recentResults) do
                if type(result) == "table" and result.status == "processing" then
                    processing = true
                    break
                end
            end
            local updated = tonumber(cache.updatedAt)
            if not updated or updated ~= updated or updated == math.huge or updated == -math.huge then
                -- Legacy caches get a full retention window on upgrade; deleting them
                -- immediately could make an old request id executable again.
                cache.updatedAt = ms
                changed = true
            elseif not processing and updated < cutoffMs then
                data.tributeRequests[username] = nil
                removed, changed = removed + 1, true
            end
        end
    end
    if changed then
        FF.sync()
        FF.log("persistent cache GC removed " .. tostring(removed) .. " stale row(s)")
    end
    return changed
end

-- Stamp lastActive for every faction with a member currently online. Cheap; the
-- decay resolution (days) does not need finer granularity than a minute.
function H.activityTick()
    local now = getTimestamp()
    if now < nextActivityTick then return end
    nextActivityTick = now + ACTIVITY_INTERVAL

    local seen = {}
    eachOnlinePlayer(function(p)
        if p:isDead() then return end
        local fname = FF.getFactionOfPlayer(p:getUsername())
        if fname then seen[fname] = true end
    end)

    local ms = nowMs()
    local data = FF.getData()
    for name in pairs(seen) do
        local faction = data.factions[name]
        if faction then
            faction.lastActive = ms
            faction.decayWarned = nil    -- activity resets the warning
        end
    end
    FF._runPersistentStateGc(false)
    -- Not synced here: lastActive/decayWarned are server-only bookkeeping; clients
    -- never read them, and decay/disband do their own FF.sync() when they mutate.
end

FF._replaceServerHook(Events.OnTick, "_serverActivityTick", H.activityTick)

-- Sweep for factions abandoned past ClaimDecayDays and disband them (freeing their
-- land). Mirrors the Handlers.disband teardown. Warns online members once when the
-- faction enters the warn window before the deadline.
local function decayTick()
    local now = getTimestamp()
    if now < nextDecayTick then return end
    nextDecayTick = now + DECAY_INTERVAL

    local opts = FF.getOptions()
    local days = opts.claimDecayDays
    if not days or days <= 0 then return end

    local deadlineMs = days * DAY_MS
    local warnMs = math.max(0, days - (opts.claimDecayWarnDays or 0)) * DAY_MS
    local ms = nowMs()
    local data = FF.getData()

    -- Collect first: we mutate data.factions while disbanding.
    local expired, warn = {}, {}
    for name, faction in pairs(data.factions) do
        local idle = ms - (faction.lastActive or ms)
        if idle >= deadlineMs then
            expired[#expired + 1] = name
        elseif idle >= warnMs and not faction.decayWarned then
            warn[#warn + 1] = name
        end
    end

    for _, name in ipairs(warn) do
        local faction = data.factions[name]
        if faction then
            faction.decayWarned = true
            notifyFaction(name, "decay_warning")
        end
    end

    local disbanded = 0
    for _, name in ipairs(expired) do
        local faction = data.factions[name]
        if faction and decayDisband(name, faction) then disbanded = disbanded + 1 end
    end
    if disbanded > 0 then FF.sync() end
end

FF._replaceServerHook(Events.OnTick, "_serverDecayTick", decayTick)

-- ---------------------------------------------------------------------------
-- Leaderboard seasons (real-world clock)
-- ---------------------------------------------------------------------------
-- Every SeasonLengthDays the season rolls over: the top faction by season score is
-- crowned (recorded in history) and a fresh baseline is snapshotted so the next
-- season scores from zero. The baseline is a plain number per faction (its live
-- score at rollover). FF.seasonScore subtracts the baseline; a character death may
-- therefore reduce the live score below it. Real-clock timestamps survive restarts; a season
-- overdue after downtime rolls over exactly once.
local nextSeasonTick = 0
local SEASON_HISTORY_MAX = 12

local function rebaseSeason(season, data)
    local opts = FF.getOptions()
    season.baseline = {}
    for name, faction in pairs(data.factions) do
        season.baseline[name] = FF.factionScore(faction, opts)
    end
end

-- Crown the season's leader, record history, and start a fresh season from a new
-- baseline. Shared by the timer and the admin "end" lever.
function H.rollSeason(ms, opts, data)
    local season = data.season
    local winner, best
    for name, faction in pairs(data.factions) do
        local sc = FF.seasonScore(faction, opts, name)
        if not best or sc > best or (sc == best and (not winner or name < winner)) then
            best, winner = sc, name
        end
    end
    season.history = season.history or {}
    table.insert(season.history, 1, {
        number = season.number or 1,
        winner = winner or "no one",
        score = math.floor((best or 0) + 0.5),
        endedAt = ms,
    })
    while #season.history > SEASON_HISTORY_MAX do table.remove(season.history) end
    local ended = season.number or 1
    season.number = ended + 1
    season.startedAt = ms
    rebaseSeason(season, data)
    FF.sync()
    broadcastEvent("season_ended", { tostring(ended), winner or "no one" })
    FF.print(string.format("season %d ended: winner %s (%d)", ended, tostring(winner), math.floor((best or 0) + 0.5)))
end

function H.seasonTick()
    local now = getTimestamp()
    if now < nextSeasonTick then return end
    nextSeasonTick = now + DECAY_INTERVAL   -- same 300s cadence as decay/upkeep
    local opts = FF.getOptions()
    if not opts.seasonsEnabled then return end
    local data = FF.getData()
    local season = data.season
    local ms = nowMs()
    if (season.startedAt or 0) == 0 then
        season.startedAt = ms         -- first run: start the clock + snapshot a baseline
        rebaseSeason(season, data)
        FF.sync()
        return
    end
    local lengthMs = math.max(1, opts.seasonLengthDays) * DAY_MS
    if ms >= season.startedAt + lengthMs then H.rollSeason(ms, opts, data) end
end
FF._replaceServerHook(Events.OnTick, "_serverSeasonTick", H.seasonTick)

-- Season dev levers: status report, force a rollover now, or reset the clock/baseline.
Handlers.adminSeason = adminHandler(function(player, args)
    local sub = (args and args.sub or "status"):lower()
    local opts = FF.getOptions()
    local data = FF.getData()
    local season = data.season
    if sub == "end" then
        H.rollSeason(nowMs(), opts, data)
        notify(player, "Admin: season rolled over.")
    elseif sub == "restart" then
        season.startedAt = nowMs()
        rebaseSeason(season, data)
        FF.sync()
        notify(player, "Admin: season clock and baseline reset.")
    else
        local ms = nowMs()
        local lines = {}
        if (season.startedAt or 0) == 0 then
            lines[#lines + 1] = string.format("Season %d: not started (enable + wait one tick).", season.number or 1)
        else
            local leftMs = math.max(0, (season.startedAt + math.max(1, opts.seasonLengthDays) * DAY_MS) - ms)
            lines[#lines + 1] = string.format("Season %d: %dh left.", season.number or 1, math.floor(leftMs / 3600000))
        end
        local ranked = {}
        for name, faction in pairs(data.factions) do
            ranked[#ranked + 1] = { name = name, score = FF.seasonScore(faction, opts, name) }
        end
        table.sort(ranked, function(a, b) return a.score > b.score end)
        for i = 1, math.min(#ranked, 5) do
            lines[#lines + 1] = string.format("  %d. %s  %d", i, ranked[i].name, math.floor(ranked[i].score + 0.5))
        end
        if not opts.seasonsEnabled then table.insert(lines, 1, "(SeasonsEnabled is OFF)") end
        sendReport(player, lines)
    end
end)

FF.checkpoint("season tick ready")

-- ---------------------------------------------------------------------------
-- Startup reconcile
-- ---------------------------------------------------------------------------
-- Rebuild PhunZones zones and loot safehouses from the persisted registry after
-- a restart. Deferred to OnServerStarted so PhunZones has initialised its data.
local function reconcile()
    local data = FF.getData()
    -- Retire persisted public-recruitment state from older versions. Invitations stay;
    -- listings/applications and open joining do not.
    data.lff = {}
    -- A processing treasury marker surviving a restart means the server stopped in
    -- the non-atomic window between LFS and Shop ModData. Never guess whether the
    -- external debit/grant happened; keep it fail-closed and surface it to admins.
    local processingCount, processingLogged = 0, 0
    local reconcileNow = nowMs()
    for username, cache in pairs(data.tributeRequests) do
        if type(cache) == "table" and type(cache.recentResults) == "table" then
            for _, result in pairs(cache.recentResults) do
                if type(result) == "table" and result.status == "processing" then
                    local started = tonumber(result.startedAt) or 0
                    if started <= 0 or reconcileNow - started >= 5 * 60 * 1000 then
                        processingCount = processingCount + 1
                        if processingLogged < 20 then
                            processingLogged = processingLogged + 1
                            FF.warn("ambiguous tribute operation requires admin reconciliation: user="
                                .. tostring(username) .. " kind=" .. tostring(result.kind)
                                .. " faction=" .. tostring(result.faction)
                                .. " amount=" .. tostring(result.amount)
                                .. " startedAt=" .. tostring(result.startedAt))
                        end
                    end
                end
            end
        end
    end
    for factionName, faction in pairs(data.factions) do
        local refund = type(faction) == "table" and type(faction.tribute) == "table"
            and faction.tribute.refund or nil
        if type(refund) == "table" and refund.status == "processing" then
            local started = tonumber(refund.startedAt) or 0
            if started <= 0 or reconcileNow - started >= 5 * 60 * 1000 then
                processingCount = processingCount + 1
                if processingLogged < 20 then
                    processingLogged = processingLogged + 1
                    FF.warn("ambiguous disband treasury refund requires admin reconciliation: faction="
                        .. tostring(factionName) .. " owner=" .. tostring(refund.owner)
                        .. " amount=" .. tostring(refund.amount)
                        .. " startedAt=" .. tostring(refund.startedAt))
                end
            end
        end
    end
    if processingCount > processingLogged then
        FF.warn(tostring(processingCount - processingLogged)
            .. " additional ambiguous treasury operation(s) omitted from boot log")
    end
    -- One-time/self-healing migration for claims saved by older builds: collapse any
    -- nested/overlapping rectangles before PhunZones and safehouses are rebuilt. Thus
    -- existing servers gain the new union semantics without forcing every faction to
    -- open the editor and resubmit its territory manually.
    for _, faction in pairs(data.factions) do
        if faction.claims and #faction.claims > 0 then
            faction.claims = FF.canonicaliseClaimRects(faction.claims)
        end
    end
    local projected = Claims.reconcileAll()
    -- Then sweep the other way: delete LFSFACTION_ zones with no live claim behind them.
    -- Releases held by servers that ran a build where disbanding orphaned its zone --
    -- that land was permanently unclaimable and there was no in-game way to free it.
    -- Only after reconcileAll has actually run, so live claims are projected before
    -- any zone is judged an orphan.
    if projected then Claims.purgeOrphanZones() end
    local clearedRaids = 0
    for _, faction in pairs(data.factions) do
        faction.joinMode = "closed"
        faction.recruiting = nil
        faction.pitch = nil
        -- Migrate pre-roles factions so every faction has a roles table before any
        -- enforcement runs (claim-bearing ones were already migrated via reconcileAll).
        FF.ensureRoles(faction)
        -- Seed leaderboard stats on pre-M15 factions before any scoring runs.
        FF.ensureStats(faction)
        -- Give pre-decay factions a fresh activity clock so they don't decay the
        -- instant decay is enabled or immediately after a restart.
        FF.ensureActivity(faction, nowMs())
        -- Raids do not survive a restart: any raid caught mid-siege is abandoned so
        -- we never resume from half-captured state.
        if faction.raid then
            faction.raid = nil
            clearedRaids = clearedRaids + 1
        end
        if faction.claims and #faction.claims > 0 then
            rebuildFactionSafehouses(faction)
        end
    end
    if clearedRaids > 0 then
        FF.sync()
        FF.log("cleared " .. clearedRaids .. " stale raid(s) on startup")
    end
    FF.sync()

    -- Report orphaned faction references; never clear them here. Same reasoning as
    -- Claims.purgeOrphanZones' own startup guard: at boot "the registry has not loaded
    -- yet" and "there genuinely are no factions" look identical, and guessing wrong
    -- deletes live data. An admin typing /ff admin purge IS the confirmation. Saves
    -- made before the teardown was centralised are the ones that will report here.
    local orphans = FF.purgeFactionRefs and FF.purgeFactionRefs(true)
    if orphans and orphans.total > 0 then
        local names = {}
        for n in pairs(orphans.names) do names[#names + 1] = n end
        table.sort(names)
        FF.warn(string.format(
            "%d orphaned faction reference(s) left by: %s. Run /ff admin purge to clear them.",
            orphans.total, table.concat(names, ", ")))
    end
    print("[LFS] reconciled faction claims on startup")
end

-- ---------------------------------------------------------------------------
-- Orphan claim-zone purge retry
-- ---------------------------------------------------------------------------
-- Claims.purgeOrphanZones (non-forced) refuses to run while the faction registry
-- LOOKS empty, because at boot that is indistinguishable from "hasn't loaded yet"
-- -- guessing wrong there would tombstone every real claim on the server. The
-- one-shot attempt inside reconcile() above hits exactly that case on a genuinely
-- fresh save/server: zero factions have been created YET, so a leftover
-- LFSFACTION_ zone from an unrelated, long-gone save (PhunZones' custom-zone file
-- is not save-scoped -- see the comment on Claims.factionAt in LFS_Claims.lua)
-- sits there un-purged, with nothing left to ever retry it. Reported bug: the
-- old zone's border is still drawn in-world, and a brand new, legitimate faction
-- cannot claim that same land -- the claim map's client-side overlap check
-- (LFS_ClaimMap.lua:_overlapsOther) deliberately trusts PhunZones' raw zone
-- presence over our own registry (the registry is not reliably replicated to a
-- joined client, so that check is correct and is NOT what this fixes), and an
-- orphan zone still counts as "occupied" to it.
--
-- Retrying periodically resolves this without weakening the safety check at all:
-- "registry empty" vs "registry not loaded yet" can only ever resolve ONE way
-- over time -- the moment a single real faction exists (the player's own,
-- created whenever they get around to it), the registry is unambiguously not
-- empty, and that retry purges every true orphan for real. Self-terminates on
-- the first non-empty read: every later restart of THIS save has a persistent
-- faction from the very first tick, so reconcile()'s own boot-time call is
-- reliable from then on and this backstop is no longer needed.
local ORPHAN_PURGE_INTERVAL = 60
local nextOrphanPurgeCheck = 0

function H.orphanPurgeTick()
    local now = getTimestamp()
    if now < nextOrphanPurgeCheck then return end
    nextOrphanPurgeCheck = now + ORPHAN_PURGE_INTERVAL
    if not FF.isEmpty(FF.getData().factions) then
        Claims.purgeOrphanZones()
        Events.OnTick.Remove(H.orphanPurgeTick)
    end
end
FF._replaceServerHook(Events.OnTick, "_serverOrphanPurgeTick", H.orphanPurgeTick)

-- ---------------------------------------------------------------------------
-- Optionally take over claiming from vanilla safehouses
-- ---------------------------------------------------------------------------
-- Running both claim systems side by side confuses players and splits ownership
-- between two sources of truth. SafeHouse.canBeSafehouse() checks PlayerSafehouse
-- and AdminSafehouse before anything else and returns null when both are off; the
-- engine only offers the "Claim Safehouse" context entry when it returns non-null,
-- and SafehouseClaimPacket/SafezoneClaimPacket both re-check it server-side. So
-- clearing the two flags closes the player right-click path AND the admin zone
-- editor path, and cannot be bypassed by a modified client.
--
-- Both must be cleared: SafezoneClaimPacket accepts the claim when EITHER
-- PlayerSafehouse is on OR (AdminSafehouse is on and the role can set up
-- safehouses), so clearing only PlayerSafehouse would leave the admin tool open.
--
-- This does NOT remove safehouses that already exist -- players keep (and can
-- still release) anything claimed before the switch. Only new claims are blocked.
local function disableVanillaSafehouses()
    if not FF.getOptions().disableVanillaSafehouses then return end
    local so = getServerOptions()
    if not (so and so.getOptionByName) then
        return FF.print("WARNING: cannot disable vanilla safehouses (no ServerOptions API)")
    end
    for _, name in ipairs({ "PlayerSafehouse", "AdminSafehouse" }) do
        local ok, err = pcall(function()
            local opt = so:getOptionByName(name)
            if opt and opt.setValue then opt:setValue(false) end
        end)
        if not ok then
            FF.print("WARNING: could not clear server option " .. name .. ": " .. tostring(err))
        end
    end
    FF.print("vanilla safehouse claiming disabled (PlayerSafehouse/AdminSafehouse off) "
        .. "-- faction claims are the only claim system; existing safehouses are untouched")
end

function H.disableVanillaSafehousesForLocalAuthority()
    if isClient() and not isCoopHost() then return end
    disableVanillaSafehouses()
end
FF._replaceServerHook(Events.OnServerStarted, "_serverDisableSafehousesStart", disableVanillaSafehouses)
FF._replaceServerHook(Events.OnGameStart, "_serverDisableSafehousesGameStart",
    H.disableVanillaSafehousesForLocalAuthority)

-- ---------------------------------------------------------------------------
-- Make LootProtectionEnabled mean what it says
-- ---------------------------------------------------------------------------
-- Every claim rect is backed by a vanilla SafeHouse (see rebuildFactionSafehouses),
-- and the engine ignores safehouses entirely while the vanilla SafehouseAllowLoot
-- option is on -- its own description is "Allow non-members to take items from
-- safehouses". So a server with LootProtectionEnabled on and SafehouseAllowLoot on
-- builds every safehouse correctly, logs "built N safehouse(s)", passes /ff status,
-- and protects nothing. This was a real incident, not a hypothetical: the README has
-- named `SafehouseAllowLoot = false` a required server setting since 1.2, and nothing
-- checked it, so the mismatch was invisible until players noticed outsiders looting
-- their bases.
--
-- Rather than only warn, we clear it, mirroring disableVanillaSafehouses above: an
-- admin who leaves the mod's own loot protection on has already said what they want,
-- and the vanilla option is the one contradicting them. When LootProtectionEnabled is
-- OFF we do not touch it -- an admin running claims without loot protection should
-- keep whatever vanilla behaviour they configured.
--
-- SafehouseAllowTrepass is deliberately left alone. Raiders have to stand inside a
-- defender's claim for captureBurn to fire, so blocking entry would break raids.
--
-- CAVEAT: unlike PlayerSafehouse/AdminSafehouse -- where the claim packets re-check
-- the option server-side, so clearing it is unbypassable -- loot enforcement is
-- evaluated on the acting client (see broadcastSafehouse's header). Clients read
-- server options at connect, and this runs at OnServerStarted, before any client
-- connects. Confirm with two accounts after a restart; if it turns out not to
-- propagate, the .ini remains the real fix and this stays useful as the warning.
function H.enforceSafehouseLootOption()
    if not FF.getOptions().lootProtection then return end
    local so = getServerOptions and getServerOptions()
    if not (so and so.getOptionByName) then
        return FF.print("WARNING: cannot verify SafehouseAllowLoot (no ServerOptions API)"
            .. " -- set it to false in the server .ini or claims will not be loot-protected")
    end
    if serverOptionBool("SafehouseAllowLoot") == false then return end
    local ok, err = pcall(function()
        local opt = so:getOptionByName("SafehouseAllowLoot")
        if opt and opt.setValue then opt:setValue(false) end
    end)
    if not ok then
        return FF.print("WARNING: could not clear server option SafehouseAllowLoot: "
            .. tostring(err) .. " -- set it to false in the server .ini; until then"
            .. " non-members can loot containers inside every claim")
    end
    FF.print("forced SafehouseAllowLoot=false -- claim loot protection is backed by"
        .. " vanilla safehouses and does nothing while that option is on."
        .. " Set it in the server .ini too so it survives independently of this mod")
end

function H.enforceSafehouseLootForLocalAuthority()
    if isClient() and not isCoopHost() then return end
    H.enforceSafehouseLootOption()
end
FF._replaceServerHook(Events.OnServerStarted, "_serverSafehouseLootStart", H.enforceSafehouseLootOption)
FF._replaceServerHook(Events.OnGameStart, "_serverSafehouseLootGameStart",
    H.enforceSafehouseLootForLocalAuthority)

-- Registered after the two option fixers above so the rebuild it performs happens
-- with SafehouseAllowLoot already corrected.
FF._replaceServerHook(Events.OnServerStarted, "_serverReconcileStart", reconcile) -- dedicated server only

-- SP and coop host have no OnServerStarted; use OnGameStart with the authority test
-- INSIDE the handler: isCoopHost() at file-load time is unreliable, and previously
-- SP never reconciled at all. OnGameStart never fires on a dedicated server, so
-- this cannot double-run with the line above.
function H.reconcileForLocalAuthority()
    if isClient() and not isCoopHost() then return end
    reconcile()
end
FF._replaceServerHook(Events.OnGameStart, "_serverReconcileGameStart", H.reconcileForLocalAuthority)

-- Self-heal: SP puro passou a usar uma identidade fixa (FF.identityUsername,
-- ver LFS_Shared.lua/LasciviousSystemsSteamId.lua) em vez de player:getUsername()
-- cru -- que a engine reescreve com o nome do personagem atual a cada morte/
-- personagem novo nesse modo (IsoPlayer.updateUsername(), decompilado). Corrige
-- o bug (filiacao de faccao "sumindo" ao recriar o personagem), mas deixa orfa
-- qualquer linha de playerIndex/members/owner ja gravada sob o username antigo
-- (nome do personagem) em saves que ja tinham uma faccao antes desse fix. Como
-- so existe UM jogador real por save em SP puro, se sobrar exatamente UMA linha
-- orfa ela so pode ser desse mesmo jogador -- migra automaticamente. Mais de uma
-- e ambiguo (save que ja foi coop/MP antes de virar solo) -- nao adivinha, so
-- avisa no log pra resolucao manual via /ff admin.
function H.migrateSoloSPIdentity()
    if not LasciviousSystemsSteamId.isTrueSoloSP() then return end
    local data = FF.getData()
    local newKey = LasciviousSystemsSteamId.SP_IDENTITY
    if data.playerIndex[newKey] then return end -- already migrated

    local oldKeys = {}
    for user in pairs(data.playerIndex) do
        if user ~= newKey then oldKeys[#oldKeys + 1] = user end
    end
    if #oldKeys == 0 then return end
    if #oldKeys > 1 then
        FF.warn("SP identity migration skipped: " .. #oldKeys
            .. " playerIndex rows found (ambiguous), expected at most 1. Resolve manually via /ff admin if needed.")
        return
    end

    local oldKey = oldKeys[1]
    local factionName = data.playerIndex[oldKey]
    local faction = factionName and data.factions[factionName]
    if not faction then
        data.playerIndex[oldKey] = nil -- stale row pointing at a faction that no longer exists
        FF.sync()
        return
    end

    data.playerIndex[oldKey] = nil
    data.playerIndex[newKey] = factionName
    if faction.members and faction.members[oldKey] then
        faction.members[newKey] = faction.members[oldKey]
        faction.members[oldKey] = nil
    end
    if faction.owner == oldKey then faction.owner = newKey end
    if faction.invites and faction.invites[oldKey] then
        faction.invites[newKey] = faction.invites[oldKey]
        faction.invites[oldKey] = nil
    end
    if data.playerScore and data.playerScore[oldKey] then
        data.playerScore[newKey] = data.playerScore[oldKey]
        data.playerScore[oldKey] = nil
    end
    FF.sync()
    FF.log("SP identity migrated: '" .. tostring(oldKey) .. "' -> '" .. newKey
        .. "' (faction '" .. tostring(factionName) .. "')")
end
FF._replaceServerHook(Events.OnServerStarted, "_serverSoloSPIdentityMigrateStart", H.migrateSoloSPIdentity)
function H.migrateSoloSPIdentityForLocalAuthority()
    if isClient() and not isCoopHost() then return end
    H.migrateSoloSPIdentity()
end
FF._replaceServerHook(Events.OnGameStart, "_serverSoloSPIdentityMigrateGameStart", H.migrateSoloSPIdentityForLocalAuthority)

-- Self-heal: after every PhunZones rebuild, re-project any faction zone the rebuild
-- lost (stale tombstone on disk, stale layer received -- see Claims.healFromBuild).
-- Same deferred-registration pattern as Claims' OnPhysicalZoneChanged hookup: the
-- event exists once PhunZones/core.lua has loaded (LuaEventManager.AddEvent), which
-- mod load order guarantees before OnGameStart at the latest.
function H.registerHealHook()
    local P = _G.PhunZones
    local evName = P and P.events and P.events.OnDataBuilt
    if evName and Events[evName] then
        if FF._serverHealEvent and FF._serverHealHook then
            FF._serverHealEvent.Remove(FF._serverHealHook)
        end
        FF._serverHealEvent = Events[evName]
        FF._serverHealHook = Claims.healFromBuild
        Events[evName].Add(Claims.healFromBuild)
        return true
    end
    return false
end
if not H.registerHealHook() then
    local function registerHealAtGameStart()
        if not H.registerHealHook() then
            FF.warn("PhunZones OnDataBuilt event not found; claim zone self-healing disabled.")
        end
    end
    FF._replaceServerHook(Events.OnGameStart, "_serverRegisterHealGameStart", registerHealAtGameStart)
elseif FF._serverRegisterHealGameStart then
    Events.OnGameStart.Remove(FF._serverRegisterHealGameStart)
    FF._serverRegisterHealGameStart = nil
end

-- Boot canary: the LAST statement this file's top-level (load-time) execution runs.
-- If a future bug aborts the file partway through, this line simply will not appear
-- in the log -- and the last checkpoint that DID print (see FF.checkpoint calls
-- above) bounds where. Always logged (see fileLog's "boot:" prefix), independent of
-- the Debug sandbox toggle, so this is visible on a normal production server too.
do
    -- The counting loop lives in its own nested function on purpose: PZ's Kahlua
    -- compiler (in debug mode) tracks total local-variable registrations per
    -- chunk/function in a fixed 200-slot table that never shrinks, even for
    -- properly-scoped locals. This file's main chunk is already at that ceiling
    -- (100+ top-level `local function` helpers), so a top-level `for k in ... do`
    -- here -- which needs 3 hidden loop locals plus its own variable -- was
    -- overflowing it. Nesting the loop inside an immediately-invoked function
    -- gives it a fresh, empty local-variable budget instead of spending the
    -- chunk's last few slots.
    local handlerCount = (function()
        local n = 0
        for _ in pairs(Handlers) do n = n + 1 end
        return n
    end)()
    FF.print("boot: server lua FULLY loaded (" .. handlerCount .. " command handlers registered)")
end
