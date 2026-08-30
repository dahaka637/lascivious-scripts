-- Lascivious Factions System - stable server-side integration API.
--
-- Other server mods should consume this module instead of reading/mutating the
-- transmitted GlobalModData registry directly. Every public getter returns a fresh,
-- JSON-safe snapshot: changing it cannot corrupt faction state. See API.md in the mod
-- root for the schema and bridge examples.

if isClient() and not isCoopHost() then return end

require "LFS_Shared"
require "LFS_Json"

local FF = LasciviousFactionsSystem
local Json = FF.Json

FF.API = FF.API or {}
local API = FF.API
LasciviousFactionsSystemAPI = API       -- convenient, explicit alias for integrations

API.SCHEMA_VERSION = 2
API.MOD_ID = "LasciviousSystems"              -- actual Build 42 mod.info id
API.MOD_VERSION = "1.0.0"                     -- actual Build 42 mod.info version
API.SYSTEM_ID = "LasciviousFactionsSystem"    -- stable namespace/ModData identity
API.IDENTITY_MODDATA = "LasciviousFactionsSystemAPIIdentity"
local savedRevision = tonumber(API._revision)
if not savedRevision or savedRevision ~= savedRevision
    or savedRevision == math.huge or savedRevision == -math.huge then savedRevision = 0 end
API._revision = math.max(0, math.floor(savedRevision))
if type(API._listeners) ~= "table" then API._listeners = {} end
local savedListenerId = tonumber(API._nextListenerId)
if not savedListenerId or savedListenerId ~= savedListenerId
    or savedListenerId == math.huge or savedListenerId == -math.huge then savedListenerId = 1 end
API._nextListenerId = math.max(1, math.floor(savedListenerId))

local function finiteNumber(value, fallback)
    local n = tonumber(value)
    if not n or n ~= n or n == math.huge or n == -math.huge then return fallback end
    return n
end

local function nowMs()
    local ok, value = pcall(function() return Calendar.getInstance():getTimeInMillis() end)
    if ok and value then return value end
    return (getTimestamp and getTimestamp() or 0) * 1000
end

local function emptyArray(list)
    return #list == 0 and Json.EMPTY_ARRAY or list
end

local function shallowCopy(source)
    local out = {}
    for key, value in pairs(source or {}) do
        local kind = type(value)
        if kind == "string" or kind == "boolean" then
            out[key] = value
        elseif kind == "number" then
            out[key] = finiteNumber(value, nil)
        end
    end
    return out
end

local function plainCopy(source, depth)
    if type(source) ~= "table" then return source end
    depth = (depth or 0) + 1
    if depth > 24 then return nil end
    local out = {}
    for key, value in pairs(source) do
        local kind = type(value)
        if kind == "table" then out[key] = plainCopy(value, depth)
        elseif kind == "string" or kind == "boolean" then out[key] = value
        elseif kind == "number" then out[key] = finiteNumber(value, nil) end
    end
    return out
end

local function sortedKeys(source)
    local out = {}
    for key in pairs(source or {}) do out[#out + 1] = tostring(key) end
    table.sort(out)
    return out
end

local function validSteamId(value)
    if value == nil then return nil end
    local text = tostring(value)
    if text == "" or text == "0" or text == "nil" then return nil end
    -- Reject scientific notation or rounded Lua doubles. A missing SteamID is safer
    -- than exporting a plausible-looking but incorrect account identifier.
    if not string.match(text, "^%d+$") or #text < 15 or #text > 20 then return nil end
    return text
end

local function onlinePlayerMap()
    local found = {}
    local ok, players = pcall(function() return getOnlinePlayers and getOnlinePlayers() end)
    if ok and players then
        pcall(function()
            for i = 0, players:size() - 1 do
                local player = players:get(i)
                if player and player.getUsername then
                    found[tostring(player:getUsername())] = player
                end
            end
        end)
    end
    -- Single-player and an early coop-host frame may not expose getOnlinePlayers().
    local localPlayer = getPlayer and getPlayer() or nil
    if localPlayer and localPlayer.getUsername then
        found[tostring(localPlayer:getUsername())] = localPlayer
    end
    return found
end

local function identityStore()
    local store = ModData.getOrCreate(API.IDENTITY_MODDATA)
    if type(store.players) ~= "table" then store.players = {} end
    return store
end

local function readPlayerField(player, method, fallback)
    if not (player and player[method]) then return fallback end
    local ok, value = pcall(function() return player[method](player) end)
    if ok and value ~= nil then return value end
    return fallback
end

-- Record only server-observed identity. Steam IDs are strings on purpose: a SteamID64
-- cannot safely round-trip through Lua/JSON as a double.
function API.rememberPlayer(player, silent)
    if not (player and player.getUsername) then return nil end
    local username = tostring(readPlayerField(player, "getUsername", ""))
    if username == "" then return nil end

    local steamId
    if getSteamIDFromUsername then
        local ok, value = pcall(getSteamIDFromUsername, username)
        if ok then steamId = validSteamId(value) end
    end
    if not steamId then
        steamId = validSteamId(readPlayerField(player, "getSteamID", nil))
    end

    local store = identityStore()
    local previous = store.players[username] or {}
    local displayName = tostring(readPlayerField(player, "getDisplayName",
        readPlayerField(player, "getFullName", previous.displayName or username)))
    local identityChanged = previous.username == nil
        or previous.steamId ~= (steamId or previous.steamId)
        or previous.displayName ~= displayName
    local rec = {
        username = username,
        steamId = steamId or previous.steamId,
        displayName = displayName,
        lastSeenAt = nowMs(),
    }
    store.players[username] = rec
    if identityChanged and not silent and API._emitChanged then
        API._emitChanged("identity_changed", { username = username })
    end
    return rec
end

function API.refreshIdentities(silent)
    local online = onlinePlayerMap()
    for _, player in pairs(online) do API.rememberPlayer(player, silent) end
    local signature = table.concat(sortedKeys(online), "\0")
    if API._presenceSignature == nil then
        API._presenceSignature = signature
    elseif signature ~= API._presenceSignature then
        API._presenceSignature = signature
        if not silent and API._emitChanged then API._emitChanged("presence_changed") end
    end
    return online
end

local function identityFor(username, player)
    local rec = player and API.rememberPlayer(player)
        or (identityStore().players or {})[username]
    local steamId = rec and validSteamId(rec.steamId) or nil
    if not steamId and getSteamIDFromUsername then
        local ok, value = pcall(getSteamIDFromUsername, username)
        if ok then steamId = validSteamId(value) end
        if steamId then
            local store = identityStore()
            rec = rec or { username = username }
            rec.steamId = steamId
            store.players[username] = rec
        end
    end
    return rec, steamId
end

local function hsv(h, s, v)
    local i = math.floor(h * 6)
    local f = h * 6 - i
    local p = v * (1 - s)
    local q = v * (1 - f * s)
    local t = v * (1 - (1 - f) * s)
    i = i % 6
    local r, g, b
    if i == 0 then r, g, b = v, t, p
    elseif i == 1 then r, g, b = q, v, p
    elseif i == 2 then r, g, b = p, v, t
    elseif i == 3 then r, g, b = p, q, v
    elseif i == 4 then r, g, b = t, p, v
    else r, g, b = v, p, q end
    return { r = r, g = g, b = b }
end

local function factionColor(name, faction)
    local source = "generated"
    local color
    local cr = type(faction.color) == "table" and finiteNumber(faction.color.r, nil) or nil
    local cg = type(faction.color) == "table" and finiteNumber(faction.color.g, nil) or nil
    local cb = type(faction.color) == "table" and finiteNumber(faction.color.b, nil) or nil
    if cr and cg and cb then
        source = "custom"
        color = {
            r = math.max(0, math.min(1, cr)),
            g = math.max(0, math.min(1, cg)),
            b = math.max(0, math.min(1, cb)),
        }
    else
        local hash = 5381
        local text = tostring(name or "")
        for i = 1, #text do hash = (hash * 33 + string.byte(text, i)) % 2147483648 end
        color = hsv((hash % 360) / 360, 0.55, 0.85)
    end
    color.source = source
    color.hex = string.format("#%02X%02X%02X",
        math.floor(color.r * 255 + 0.5), math.floor(color.g * 255 + 0.5),
        math.floor(color.b * 255 + 0.5))
    return color
end

local function scoreSnapshot(username, opts)
    local rec = (FF.getData().playerScore or {})[username] or {}
    local kills = math.max(0, finiteNumber(rec.kills, 0))
    local hours = math.max(0, finiteNumber(rec.hours, 0))
    local killPoints = kills * opts.pointsPerZombieKill
    local hourPoints = hours * opts.pointsPerHourSurvived
    return {
        zombieKills = kills,
        hoursSurvived = hours,
        zombieKillPoints = killPoints,
        survivalPoints = hourPoints,
        total = killPoints + hourPoints,
        lastReportedZombieKills = math.max(0, finiteNumber(rec.lastRawKills, 0)),
        lastReportedHoursSurvived = math.max(0, finiteNumber(rec.lastRawHours, 0)),
        observedAt = finiteNumber(rec.updatedAt, nil),
        source = tostring(rec.source or "persisted_cache"),
    }
end

-- Make API reads dynamic for connected characters. LFS_Server provides this hook;
-- the guard keeps the API load-order independent and leaves offline caches untouched.
local function refreshOnlineScores()
    if not FF.refreshOnlinePlayerScores then return end
    local ok, err = pcall(FF.refreshOnlinePlayerScores)
    if not ok then FF.warn("API native score refresh failed: " .. tostring(err)) end
end

local function permissionsFor(faction, username)
    local out = {}
    for _, permission in ipairs(FF.PERMISSIONS or {}) do
        out[permission] = FF.roleCan(faction, username, permission) == true
    end
    return out
end

local function memberSnapshot(username, role, faction, opts, online)
    local player = online[username]
    local identity, steamId = identityFor(username, player)
    return {
        username = username,
        displayName = identity and identity.displayName or username,
        steamId = steamId,
        accountId = steamId and ("steam:" .. steamId) or ("username:" .. username),
        online = player ~= nil,
        onlineId = player and tonumber(readPlayerField(player, "getOnlineID", nil)) or nil,
        accessLevel = player and tostring(readPlayerField(player, "getAccessLevel", "")) or nil,
        lastSeenAt = identity and identity.lastSeenAt or nil,
        role = role or "member",
        owner = faction.owner == username,
        permissions = permissionsFor(faction, username),
        score = scoreSnapshot(username, opts),
    }
end

local function rectSnapshot(rect, index)
    rect = type(rect) == "table" and rect or {}
    local x1, y1 = math.floor(finiteNumber(rect[1], 0)), math.floor(finiteNumber(rect[2], 0))
    local x2, y2 = math.floor(finiteNumber(rect[3], 0)), math.floor(finiteNumber(rect[4], 0))
    local grants = FF.areaGrants(rect)
    return {
        index = index,
        x1 = x1, y1 = y1, x2 = x2, y2 = y2,
        width = x2 - x1 + 1,
        height = y2 - y1 + 1,
        tiles = FF.rectArea(rect),
        access = FF.areaAccess(rect),
        grants = { loot = grants.loot, build = grants.build, move = grants.move },
    }
end

local function areasSnapshot(claims)
    local areas = {}
    for areaIndex, component in ipairs(FF.claimComponents(claims or {}, true)) do
        local rects, rawRects, keyParts = {}, {}, {}
        local minX, minY, maxX, maxY
        for _, rectIndex in ipairs(component) do
            local rect = claims[rectIndex]
            rawRects[#rawRects + 1] = rect
            local snap = rectSnapshot(rect, rectIndex)
            rects[#rects + 1] = snap
            keyParts[#keyParts + 1] = string.format("%d,%d,%d,%d", snap.x1, snap.y1, snap.x2, snap.y2)
            minX = minX and math.min(minX, snap.x1) or snap.x1
            minY = minY and math.min(minY, snap.y1) or snap.y1
            maxX = maxX and math.max(maxX, snap.x2) or snap.x2
            maxY = maxY and math.max(maxY, snap.y2) or snap.y2
        end
        table.sort(keyParts)
        local first = claims[component[1]]
        areas[#areas + 1] = {
            index = areaIndex,
            geometryKey = FF.areaAccess(first) .. "@" .. table.concat(keyParts, ";"),
            access = FF.areaAccess(first),
            grants = FF.areaGrants(first),
            tiles = FF.totalArea(rawRects),
            bounds = { x1 = minX, y1 = minY, x2 = maxX, y2 = maxY },
            rectangles = emptyArray(rects),
        }
    end
    return emptyArray(areas)
end

local function territorySnapshot(faction, score, opts)
    local claims = FF.canonicaliseClaimRects(faction.claims or {})
    local rectangles = {}
    for i, rect in ipairs(claims) do rectangles[#rectangles + 1] = rectSnapshot(rect, i) end
    local claimed = FF.totalArea(claims)
    local maximum = FF.maxClaimTiles(score, opts)
    local maximumAreas = FF.maxClaimAreas(score, opts)
    -- Quota follows disconnected geometry, not internal access-policy seams. The
    -- `areas` list remains access-sensitive so integrations can still inspect every
    -- independently managed private/allies/public section.
    local areaCount = FF.claimComponentCount(claims)
    local policyAreaCount = #FF.claimComponents(claims, true)
    local areaStep = math.max(1, tonumber(opts.pointsPerClaimArea) or 2500)
    local respawn
    if type(faction.respawn) == "table" then
        respawn = {
            x = tonumber(faction.respawn.x), y = tonumber(faction.respawn.y),
            z = tonumber(faction.respawn.z) or 0,
        }
    end
    return {
        claimedTiles = claimed,
        maximumTiles = maximum,
        maximumWholeTiles = math.floor(maximum),
        remainingTiles = math.max(0, maximum - claimed),
        aboveLimit = claimed > maximum,
        rectangleCount = #rectangles,
        areaCount = areaCount,
        policyAreaCount = policyAreaCount,
        maximumAreas = maximumAreas,
        remainingAreas = math.max(0, maximumAreas - areaCount),
        aboveAreaLimit = areaCount > maximumAreas,
        pointsUntilNextArea = areaStep - (math.floor(math.max(0, score)) % areaStep),
        publicAreaCount = FF.countPublicAreas and FF.countPublicAreas(claims) or 0,
        respawn = respawn,
        rectangles = emptyArray(rectangles),
        areas = areasSnapshot(claims),
    }
end

local function requestList(source)
    local out = {}
    for name, value in pairs(source or {}) do
        local entry = { faction = tostring(name) }
        if type(value) == "table" then
            entry.durationDays = tonumber(value.durationDays)
            entry.terms = shallowCopy(value.terms)
        end
        out[#out + 1] = entry
    end
    table.sort(out, function(a, b) return a.faction < b.faction end)
    return emptyArray(out)
end

local function inviteCooldownList(data, factionName)
    local rows = {}
    local now = math.floor(nowMs() / 1000)
    for username, rec in pairs((data.inviteCooldowns or {})[factionName] or {}) do
        rows[#rows + 1] = {
            username = tostring(username),
            declines = math.max(0, tonumber(rec.declines) or 0),
            lastDeclinedAtUnixSeconds = tonumber(rec.lastDeclinedAt),
            blockedUntilUnixSeconds = tonumber(rec.untilAt) or 0,
            remainingSeconds = math.max(0, (tonumber(rec.untilAt) or 0) - now),
        }
    end
    table.sort(rows, function(a, b) return a.username < b.username end)
    return emptyArray(rows)
end

local function pendingInvitationList(faction)
    local rows = {}
    for username, invite in pairs(faction.invites or {}) do
        rows[#rows + 1] = {
            username = tostring(username),
            invitedAtUnixSeconds = type(invite) == "table" and tonumber(invite.at) or nil,
            inviter = type(invite) == "table" and tostring(invite.inviter or "") or "",
        }
    end
    table.sort(rows, function(a, b) return a.username < b.username end)
    return emptyArray(rows)
end

local function factionSnapshot(name, faction, opts, online, ranks)
    local members = {}
    for username, role in pairs(faction.members or {}) do
        members[#members + 1] = memberSnapshot(tostring(username), tostring(role), faction, opts, online)
    end
    table.sort(members, function(a, b)
        if a.owner ~= b.owner then return a.owner end
        return a.username < b.username
    end)

    local roles = {}
    for roleName, permissions in pairs(faction.roles or FF.defaultRoles()) do
        roles[#roles + 1] = { name = tostring(roleName), permissions = shallowCopy(permissions) }
    end
    table.sort(roles, function(a, b) return a.name < b.name end)

    local relations = {}
    for other, status in pairs(faction.relations or {}) do
        relations[#relations + 1] = { faction = tostring(other), status = tostring(status) }
    end
    table.sort(relations, function(a, b) return a.faction < b.faction end)

    local invites = sortedKeys(faction.invites)
    local score = FF.factionScore(faction, opts)
    local seasonScore = FF.seasonScore(faction, opts, name)
    return {
        id = name,
        name = name,
        tag = tostring(faction.tag or name),
        description = tostring(faction.description or ""),
        motd = tostring(faction.motd or ""),
        owner = tostring(faction.owner or ""),
        memberCount = #members,
        members = emptyArray(members),
        roles = emptyArray(roles),
        color = factionColor(name, faction),
        createdAtWorldHour = tonumber(faction.created),
        lastActiveAt = tonumber(faction.lastActive),
        joinMode = "invite_only",
        recruiting = false,
        recruitmentPitch = "",
        settings = {
            friendlyFire = faction.friendlyFire == true,
            showEntryBanner = faction.hideBanner ~= true,
            shareMapWithAllies = faction.shareMapWithAllies ~= false,
            shareMemberLocations = faction.shareMemberLocations == true,
            allowAllyBuild = faction.allowAllyBuild == true,
            allowAllyMove = faction.allowAllyMove == true,
        },
        score = {
            current = score,
            season = seasonScore,
            currentRank = ranks.current[name],
            seasonRank = ranks.season[name],
        },
        territory = territorySnapshot(faction, score, opts),
        relations = emptyArray(relations),
        allianceRequests = requestList(faction.allyRequests),
        pactRequests = requestList(faction.pactRequests),
        pendingInvites = emptyArray(invites),
        pendingInvitationDetails = pendingInvitationList(faction),
        inviteDeclineCooldowns = inviteCooldownList(FF.getData(), name),
        raid = type(faction.raid) == "table" and plainCopy(faction.raid) or nil,
        raidStats = {
            won = tonumber(faction.stats and faction.stats.raidsWon) or 0,
            lost = tonumber(faction.stats and faction.stats.raidsLost) or 0,
            defended = tonumber(faction.stats and faction.stats.raidsDefended) or 0,
        },
    }
end

local function rankingMaps(data, opts)
    local current, season = {}, {}
    for name, faction in pairs(data.factions or {}) do
        current[#current + 1] = { name = name, score = FF.factionScore(faction, opts) }
        season[#season + 1] = { name = name, score = FF.seasonScore(faction, opts, name) }
    end
    local function rank(rows)
        table.sort(rows, function(a, b)
            if a.score ~= b.score then return a.score > b.score end
            return a.name < b.name
        end)
        local out = {}
        for i, row in ipairs(rows) do out[row.name] = i end
        return out
    end
    return { current = rank(current), season = rank(season) }
end

local function playerSnapshot(username, opts, online, factionName)
    local player = online[username]
    local identity, steamId = identityFor(username, player)
    return {
        username = username,
        displayName = identity and identity.displayName or username,
        steamId = steamId,
        accountId = steamId and ("steam:" .. steamId) or ("username:" .. username),
        faction = factionName,
        online = player ~= nil,
        onlineId = player and tonumber(readPlayerField(player, "getOnlineID", nil)) or nil,
        accessLevel = player and tostring(readPlayerField(player, "getAccessLevel", "")) or nil,
        lastSeenAt = identity and identity.lastSeenAt or nil,
        score = scoreSnapshot(username, opts),
    }
end

local function listRecords(source)
    local rows = {}
    for key, value in pairs(source or {}) do
        local row = type(value) == "table" and shallowCopy(value) or {}
        row.key = tostring(key)
        if type(value) == "table" then
            if type(value.score) == "table" then row.score = shallowCopy(value.score) end
            if type(value.coalition) == "table" then row.coalition = shallowCopy(value.coalition) end
            if type(value.terms) == "table" then row.terms = shallowCopy(value.terms) end
        elseif type(value) == "number" then
            row.expiresAt = value
        end
        rows[#rows + 1] = row
    end
    table.sort(rows, function(a, b) return a.key < b.key end)
    return emptyArray(rows)
end

local function noClaimSnapshot(data)
    local zones = {}
    for id, zone in pairs(data.noClaim or {}) do
        local rectangles = {}
        for i, rect in ipairs(zone.points or {}) do rectangles[#rectangles + 1] = rectSnapshot(rect, i) end
        zones[#zones + 1] = {
            id = tostring(zone.id or id), name = tostring(zone.name or id),
            source = tostring(zone.source or "admin"), rectangles = emptyArray(rectangles),
            tiles = FF.totalArea(zone.points or {}),
        }
    end
    table.sort(zones, function(a, b) return a.id < b.id end)
    return emptyArray(zones)
end

local function recruitmentSnapshot(data)
    -- Kept as an empty array so schema-1 bridges that display this field degrade
    -- cleanly. Public listings/applications no longer exist in schema 2.
    return Json.EMPTY_ARRAY
end

local function emitChanged(eventType, details)
    API._revision = API._revision + 1
    local event = {
        type = eventType or "registry_changed",
        revision = API._revision,
        at = nowMs(),
        details = details,
    }
    for id, callback in pairs(API._listeners) do
        local ok, err = pcall(callback, event)
        if not ok then
            FF.warn("API listener " .. tostring(id) .. " failed: " .. tostring(err))
        end
    end
end
API._emitChanged = emitChanged

-- Wrap the registry's mutation signal once. This does not change sync timing; it only
-- gives integrations a lightweight notification that a new snapshot is available.
if FF.sync ~= API._syncWrapper then
    local originalSync = FF.sync
    local function wrappedSync(...)
        local newlyDirty = originalSync(...)
        -- A burst of mutations is one eventual snapshot/transmit, so integrations
        -- receive one revision notification as well, not one per call site.
        if newlyDirty then emitChanged("registry_changed") end
        return newlyDirty
    end
    API._syncWrapper = wrappedSync
    API._syncWrapped = true -- compatibility flag for integrations that inspected it
    FF.sync = wrappedSync
end

function API.subscribe(callback)
    if type(callback) ~= "function" then return nil, "callback must be a function" end
    local id = API._nextListenerId
    API._nextListenerId = id + 1
    API._listeners[id] = callback
    return id
end

function API.unsubscribe(id)
    if API._listeners[id] == nil then return false end
    API._listeners[id] = nil
    return true
end

function API.getRevision()
    return API._revision
end

function API.getVersion()
    return { schemaVersion = API.SCHEMA_VERSION, modVersion = API.MOD_VERSION }
end

function API.getFactionNames()
    return emptyArray(sortedKeys(FF.getData().factions))
end

local function allFactionSnapshots(data, opts, online)
    local ranks = rankingMaps(data, opts)
    local factions = {}
    for _, name in ipairs(sortedKeys(data.factions)) do
        factions[#factions + 1] = factionSnapshot(name, data.factions[name], opts, online, ranks)
    end
    return emptyArray(factions)
end

local function allPlayerSnapshots(data, opts, online)
    local usernames = {}
    for username in pairs(data.playerScore or {}) do usernames[username] = true end
    for username in pairs(data.playerIndex or {}) do usernames[username] = true end
    for username in pairs((identityStore().players or {})) do usernames[username] = true end
    local players = {}
    for _, username in ipairs(sortedKeys(usernames)) do
        players[#players + 1] = playerSnapshot(username, opts, online, data.playerIndex[username])
    end
    return emptyArray(players)
end

-- Convenience getter for integrations that only need the faction collection. Like
-- every other getter, this returns detached snapshots and is safe to serialize or
-- modify locally.
function API.getFactions()
    refreshOnlineScores()
    local data, opts = FF.getData(), FF.getOptions()
    local online = API.refreshIdentities(true)
    return allFactionSnapshots(data, opts, online)
end

function API.getPlayers()
    refreshOnlineScores()
    local data, opts = FF.getData(), FF.getOptions()
    return allPlayerSnapshots(data, opts, API.refreshIdentities(true))
end

-- Compact geometry-oriented view for map exports. `territory.rectangles` remains the
-- authoritative exact geometry; `territory.areas` is the connected-area grouping.
function API.getTerritories()
    local out = {}
    for _, faction in ipairs(API.getFactions()) do
        out[#out + 1] = {
            factionId = faction.id,
            faction = faction.name,
            tag = faction.tag,
            color = faction.color,
            score = faction.score.current,
            territory = faction.territory,
        }
    end
    return emptyArray(out)
end

function API.getSnapshot()
    refreshOnlineScores()
    local data, opts = FF.getData(), FF.getOptions()
    local online = API.refreshIdentities(true)
    local factions = allFactionSnapshots(data, opts, online)
    local players = allPlayerSnapshots(data, opts, online)

    local season = data.season or {}
    local history = {}
    for i, item in ipairs(season.history or {}) do
        local row = shallowCopy(item); row.index = i; history[#history + 1] = row
    end

    return {
        schemaVersion = API.SCHEMA_VERSION,
        modId = API.MOD_ID,
        modVersion = API.MOD_VERSION,
        generatedAt = nowMs(),
        revision = API._revision,
        summary = {
            factionCount = #factions,
            playerCount = #players,
            onlinePlayerCount = #sortedKeys(online),
            claimedTiles = (function()
                local total = 0
                for _, faction in ipairs(factions) do total = total + faction.territory.claimedTiles end
                return total
            end)(),
        },
        scoring = {
            pointsPerZombieKill = opts.pointsPerZombieKill,
            pointsPerHourSurvived = opts.pointsPerHourSurvived,
            deathResetsCharacterScore = true,
        },
        claimRules = {
            baseTiles = opts.baseClaimTiles,
            tilesPerScorePoint = opts.tilesPerScorePoint,
            maximumTiles = opts.maxClaimTiles,
            minimumFactionSize = opts.minFactionSizeToClaim,
            baseAreas = 1,
            areaLimitMode = "faction_score",
            pointsPerAdditionalArea = opts.pointsPerClaimArea,
            maximumPublicAreas = opts.maxPublicClaimAreas,
            maximumSeparation = opts.maxClaimSeparation,
            bufferTiles = opts.claimBufferTiles,
        },
        membershipRules = {
            invitationOnly = true,
            invitationTargets = "online_players_without_faction",
            declineCooldownSeconds = { 60, 3600, 86400, 604800, 2592000 },
            declineCooldownCapsAtLastValue = true,
        },
        sandbox = shallowCopy(opts),
        factions = emptyArray(factions),
        players = emptyArray(players),
        wars = listRecords(data.wars),
        ceasefires = listRecords(data.ceasefires),
        pacts = listRecords(data.pacts),
        noClaimZones = noClaimSnapshot(data),
        recruitment = recruitmentSnapshot(data),
        season = {
            number = tonumber(season.number) or 1,
            startedAt = tonumber(season.startedAt) or 0,
            baseline = shallowCopy(season.baseline),
            history = emptyArray(history),
        },
    }
end

function API.getFaction(name)
    refreshOnlineScores()
    local data, opts = FF.getData(), FF.getOptions()
    local faction = data.factions and data.factions[name]
    if not faction then return nil end
    return factionSnapshot(name, faction, opts, API.refreshIdentities(true), rankingMaps(data, opts))
end

function API.getPlayer(username)
    if type(username) ~= "string" or username == "" then return nil end
    refreshOnlineScores()
    local data, opts = FF.getData(), FF.getOptions()
    local known = (data.playerScore and data.playerScore[username])
        or (data.playerIndex and data.playerIndex[username])
        or ((identityStore().players or {})[username])
    if not known then return nil end
    return playerSnapshot(username, opts, API.refreshIdentities(true), data.playerIndex[username])
end

function API.findFactionByPlayer(username)
    local name = username and FF.getData().playerIndex[username] or nil
    return name, name and API.getFaction(name) or nil
end

function API.getFactionAt(x, y)
    x, y = math.floor(finiteNumber(x, 0)), math.floor(finiteNumber(y, 0))
    local data = FF.getData()
    for _, name in ipairs(sortedKeys(data.factions)) do
        local faction = data.factions[name]
        for index, rect in ipairs(faction.claims or {}) do
            if FF.pointInRect(x, y, rect) then
                return name, API.getFaction(name), rectSnapshot(rect, index)
            end
        end
    end
    return nil
end

function API.toJSON(value, pretty)
    if value == nil then value = API.getSnapshot() end
    return Json.encode(value, pretty and { indent = "  " } or nil)
end

function API.getSnapshotJSON(pretty)
    return API.toJSON(API.getSnapshot(), pretty)
end

-- Capture identities without waiting for a bridge poll. Any command received from a
-- client proves that player is a real server-side IsoPlayer; the module filter is
-- intentionally omitted so joining players are remembered even before LFS is opened.
if Events and Events.OnClientCommand then
    if API._identityCommandHook then Events.OnClientCommand.Remove(API._identityCommandHook) end
    local function identityCommandHook(module, command, player, args)
        if player then API.rememberPlayer(player) end
    end
    API._identityCommandHook = identityCommandHook
    Events.OnClientCommand.Add(identityCommandHook)
end

local nextIdentityRefresh = 0
if Events and Events.OnTick then
    if API._identityTickHook then Events.OnTick.Remove(API._identityTickHook) end
    local function identityTickHook()
        local now = getTimestamp and getTimestamp() or 0
        if now < nextIdentityRefresh then return end
        nextIdentityRefresh = now + 30
        API.refreshIdentities()
    end
    API._identityTickHook = identityTickHook
    Events.OnTick.Add(identityTickHook)
end

FF.checkpoint("server integration API ready (schema " .. API.SCHEMA_VERSION .. ")")

return API
