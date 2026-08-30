-- Lascivious Factions System - shared core.
-- Holds the global namespace, the authoritative-data accessor, and the pure
-- helper logic (claim-size scaling, rectangle math, overlap checks) that both
-- the client and server sides rely on. Nothing here touches the world, and the
-- only IO is the opt-in debug file log below; it is safe to require from any
-- context.

require "LasciviousSystems_SteamId"

LasciviousFactionsSystem = LasciviousFactionsSystem or {}
local FF = LasciviousFactionsSystem

print("[LFS] shared lua loaded")

FF.MODULE = "LasciviousFactionsSystem"       -- client/server command channel
FF.MODDATA = "LasciviousFactionsSystem"      -- transmitted GlobalModData table name
FF.ZONE_PREFIX = "LFSFACTION_"          -- PhunZones zone key prefix for our claims
FF.VERSION = 1

-- PZ's Kahlua sandbox does not expose the `next` global -- calling it throws
-- "Object tried to call nil". Test table emptiness with pairs instead.
function FF.isEmpty(t)
    if not t then return true end
    for _ in pairs(t) do return false end
    return true
end

-- Lua 5.1/Kahlua string indices are bytes. Cutting a Portuguese (or any UTF-8)
-- name with `sub(1, n)` can leave half a codepoint and later break Java text
-- rendering/formatting. Keep at most `maximum` codepoints while accepting malformed
-- legacy bytes defensively as one-byte characters. This needs no utf8 library, which
-- Kahlua does not consistently expose.
function FF.truncateUtf8(value, maximum)
    value = tostring(value or "")
    maximum = tonumber(maximum)
    if not maximum or maximum ~= maximum or maximum == math.huge or maximum == -math.huge then
        maximum = 0
    end
    maximum = math.max(0, math.floor(maximum))
    if maximum == 0 or value == "" then return "" end
    local i, count, bytes = 1, 0, #value
    while i <= bytes and count < maximum do
        local b = string.byte(value, i)
        local width = 1
        if b and b >= 194 and b <= 223 then width = 2
        elseif b and b >= 224 and b <= 239 then width = 3
        elseif b and b >= 240 and b <= 244 then width = 4 end
        if i + width - 1 > bytes then
            width = 1
        else
            for j = i + 1, i + width - 1 do
                local continuation = string.byte(value, j)
                if not continuation or continuation < 128 or continuation > 191 then
                    width = 1
                    break
                end
            end
        end
        i = i + width
        count = count + 1
    end
    return value:sub(1, i - 1)
end

-- ---------------------------------------------------------------------------
-- Sandbox options
-- ---------------------------------------------------------------------------

-- Mirrors the getOptions() pattern used by the other mods in this repo
-- (see DynamicDesensitized.lua). Reads once, applies defaults, returns a plain
-- table so callers never poke SandboxVars directly.
--
-- MEMOIZED behind a 1-second TTL, because this builds a sizeable table and sits on
-- genuinely hot paths: the always-on minimap overlay alone called it multiple times
-- per frame (ISMiniMapInner:prerender plus the claim-border draw), with nameplates
-- adding more -- hundreds of short-lived tables a second at 60fps, all of it garbage.
--
-- Returning a SHARED table is only safe because no caller mutates it; that was checked
-- across every call site before this cache went in. Treat the result as read-only --
-- if you ever need a tweaked copy, copy it.
--
-- The TTL rather than a permanent cache: sandbox values are fixed for a session in
-- normal play, but an admin can edit them live in MP, and a one-second staleness window
-- keeps that working without a restart. Same getTimestamp() throttle idiom as the
-- server ticks and the in-world border refresh.
local optionsCache, optionsCacheAt = nil, -1
local OPTIONS_TTL = 1

-- Drop the memo so the next getOptions() re-reads SandboxVars. For tests and for any
-- future hook that knows the sandbox changed.
function FF.invalidateOptions()
    optionsCache, optionsCacheAt = nil, -1
end

function FF.getOptions()
    -- getTimestamp is absent in some early-boot contexts; fall back to no caching
    -- rather than serving a stale table forever.
    local now = getTimestamp and getTimestamp() or nil
    if optionsCache and now and (now - optionsCacheAt) < OPTIONS_TTL then
        return optionsCache
    end

    local o = (SandboxVars and SandboxVars.LasciviousFactionsSystem) or {}
    local built = {
        baseClaimTiles = o.BaseClaimTiles or 400,
        -- Score-driven claim scaling (replaces the old per-member scaling): see
        -- FF.factionScore / FF.maxClaimTiles below. Kills and hours survived are
        -- tallied per current character by default (reset on death) and summed
        -- over the faction's CURRENT members. PreserveMemberPowerOnDeath can opt
        -- into account-style accumulation while still using the current character's
        -- native counters as the safe input baseline.
        pointsPerZombieKill = o.PointsPerZombieKill or 1,
        pointsPerHourSurvived = o.PointsPerHourSurvived or 1,
        preserveMemberPowerOnDeath = o.PreserveMemberPowerOnDeath == true,
        minPersonalScoreToCreateFaction = o.MinPersonalScoreToCreateFaction or 0,
        tilesPerScorePoint = o.TilesPerScorePoint or 5,
        maxClaimTiles = o.MaxClaimTiles or 40000,
        minFactionSizeToClaim = o.MinFactionSizeToClaim or 1,
        -- One disconnected claim area is available immediately; each complete block
        -- of score unlocks another. This replaces the old fixed area-count cap.
        pointsPerClaimArea = math.max(1, tonumber(o.PointsPerClaimArea) or 2500),
        -- No longer a sandbox option (2026-08-21, explicit request: "essa
        -- distância máxima... tu tira e também remove essa exigência") --
        -- already defaulted to 0/unlimited, so removing the option requires
        -- no change here.
        maxClaimSeparation = o.MaxClaimSeparation or 0,       -- 0 = unlimited
        maxPublicClaimAreas = o.MaxPublicClaimAreas or 2,     -- 0 = public areas disabled
        claimBufferTiles = o.ClaimBufferTiles or 10,          -- 0 = no buffer required
        maxRolesPerFaction = o.MaxRolesPerFaction or 8,
        maxMembersPerFaction = o.MaxMembersPerFaction or 0,   -- 0 = unlimited
        claimDecayDays = o.ClaimDecayDays or 0,               -- 0 = off
        claimDecayWarnDays = o.ClaimDecayWarnDays or 3,
        territorySafeZoneEnabled = o.TerritorySafeZoneEnabled == true,
        safeZoneCullPerTick = o.SafeZoneCullPerTick or 6,     -- zombies cleared per member per sweep
        safeZoneRadius = o.SafeZoneRadius or 12,              -- tiles around a present member
        -- Four independent categories (see client/LFS_Territory.lua) -- mood,
        -- health, fatigue and light hunger/thirst/wetness relief while standing in
        -- your own faction's claim. All on by default; each can be switched off
        -- without touching the others.
        territoryMoodBuffEnabled = o.TerritoryMoodBuffEnabled ~= false,
        territoryHealthBuffEnabled = o.TerritoryHealthBuffEnabled ~= false,
        territoryFatigueBuffEnabled = o.TerritoryFatigueBuffEnabled ~= false,
        territoryNeedsBuffEnabled = o.TerritoryNeedsBuffEnabled ~= false,
        -- Multiplies every own-territory wellbeing effect. Zero is a convenient
        -- live-admin kill switch while preserving the four feature toggles.
        territoryWellbeingPower = math.max(0, tonumber(o.TerritoryWellbeingPower) or 1),
        raidWindowStartHour = o.RaidWindowStartHour or 0,
        raidWindowEndHour = o.RaidWindowEndHour or 0,         -- start==end => always open
        -- Default flipped false->true 2026-08-21, explicit request ("já
        -- deixe default ativo também").
        offlineRaidProtection = o.OfflineRaidProtection ~= false,
        respawnEnabled = o.FactionRespawnEnabled ~= false,
        showClaimsOnMinimap = o.ShowClaimsOnMinimap ~= false,
        memberMarkersEnabled = o.MemberMarkersEnabled ~= false,
        showMembersOnMinimap = o.ShowMembersOnMinimap ~= false,
        lootProtection = o.LootProtectionEnabled ~= false,
        -- No longer a sandbox option (2026-08-21, explicit request: "marca
        -- como default ativo... pode remover essa opção do sandbox") --
        -- always on now.
        disableVanillaSafehouses = true,
        enforcePermissions = o.EnforceClaimPermissions ~= false,
        enforceFriendlyFire = o.EnforceFriendlyFire ~= false,
        raidsEnabled = o.RaidsEnabled == true,
        captureAttemptsPerDay = o.CaptureAttemptsPerDay or 1,
        raidHoldSeconds = o.RaidHoldSeconds or 300,
        raidMaxDurationSeconds = o.RaidMaxDurationSeconds or 1800,
        raidForcePvp = o.RaidForcePvp ~= false,
        factionChatEnabled = o.FactionChatEnabled ~= false,
        broadcastFactionEvents = o.BroadcastFactionEvents ~= false,
        showFactionTagsInChat = o.ShowFactionTagsInChat ~= false,
        hudIconPosition = o.HudIconPosition or 1,   -- 0 hidden / 1 left sidebar / 2 top-right corner
        showFactionSidebarButton = o.ShowFactionSidebarButton ~= false,
        showNameplates = o.ShowNameplates or 1,   -- 0 off / 1 members+allies / 2 all
        -- Legacy/API compatibility only. Native username rendering now owns the
        -- distance and line-of-sight rules, so this is no longer a visible setting.
        nameplateRange = o.NameplateRange or 20,
        showEnemyNameplates = o.ShowEnemyNameplates ~= false,  -- red-tag enemies/at-war
        showHudTicker = o.ShowHudTicker ~= false,              -- on-screen season/war strip
        intrusionAlertsEnabled = o.IntrusionAlertsEnabled ~= false,
        showClaimBordersInWorld = o.ShowClaimBordersInWorld ~= false,
        claimBorderRange = o.ClaimBorderRange or 24,
        leaderboardEnabled = o.LeaderboardEnabled ~= false,
        -- Default flipped false->true 2026-08-21, explicit request ("e
        -- deixe default ativo").
        warsEnabled = o.WarsEnabled ~= false,
        warScoreTarget = o.WarScoreTarget or 100,            -- points to win a war
        warScoreRaidWon = o.WarScoreRaidWon or 25,
        warScoreKill = o.WarScoreKill or 2,
        warCeasefireHours = o.WarCeasefireHours or 48,       -- real hours before re-declaring
        pactsEnabled = o.PactsEnabled ~= false,
        pactTermDays = o.PactTermDays or 0,                  -- 0 = indefinite until broken
        seasonsEnabled = o.SeasonsEnabled == true,
        seasonLengthDays = o.SeasonLengthDays or 14,         -- real days per season
        debug = o.Debug == true,
        alwaysLogErrors = o.AlwaysLogErrors ~= false,
        -- Gates the faction panel's "Debug" section (see LFS_Panel.lua's
        -- visibleSections) and its server-side handlers. No longer its own sandbox
        -- option (DebugToolsEnabled, removed 2026-08-30) -- just the Debug flag
        -- above. This is a FEATURE flag only, not the security boundary: every
        -- debugXxx Handler in LFS_Server.lua additionally requires
        -- isAdminPlayer(player), same helper every other admin-only command
        -- already uses -- true SP, the local host of a coop game (explicitly not
        -- remote guests -- see its own comment), or a real dedicated-server
        -- admin. Off by default (Debug defaults to false) -- nothing to remember
        -- to flip back before shipping.
        debugToolsEnabled = o.Debug == true,
    }

    optionsCache, optionsCacheAt = built, now or -1
    return built
end

-- Forward declaration: FF.print is defined before the file-log implementation.
local fileLog

-- Always-on namespaced print (errors/important events).
function FF.print(msg)
    print("[LFS] " .. tostring(msg))
    if fileLog then fileLog(tostring(msg)) end
end

-- Is the Debug sandbox option on? Exposed so a caller that would have to BUILD an
-- expensive message can skip the work rather than formatting it and throwing it away
-- (see Claims.zoneTrace, which walks the whole zone layer).
function FF.debugEnabled()
    return ((SandboxVars and SandboxVars.LasciviousFactionsSystem) or {}).Debug == true
end

-- Verbose log, gated by the Debug sandbox option.
function FF.log(msg)
    if FF.debugEnabled() then
        FF.print(msg)
    end
end

-- Warning: always printed to console (like FF.print) AND, with AlwaysLogErrors on
-- (default), always durably written to the debug file regardless of the Debug
-- toggle -- see fileLog below. Use for a failure that changes behaviour a player or
-- admin would notice (a hook not installing, a sync failing, a render failing).
function FF.warn(msg)
    FF.print("WARNING: " .. tostring(msg))
end

-- Load/boot milestone marker: same always-logged treatment as FF.warn, but for
-- informational "we got this far" checkpoints rather than failures. See the
-- checkpoint calls through LFS_Server.lua's top-level load.
function FF.checkpoint(msg)
    FF.print("checkpoint: " .. tostring(msg))
end

-- ---------------------------------------------------------------------------
-- Debug file log (Debug sandbox option, plus always-on error/checkpoint lines)
-- ---------------------------------------------------------------------------
-- With Debug on, messages emitted through FF.print/FF.log are also appended to
-- a log file, so admins can collect diagnostics without scraping console.txt. The
-- engine's writeLog (the same API the vanilla admin logs use) timestamps each
-- line and writes it to the game's Logs folder on the machine that printed it:
--   Zomboid/Logs/logs_<date>/<time>_LasciviousFactionsSystem.txt
-- (server lines in the server's Logs, each client's lines in its own).
-- NOTE: this used to claim a mod cannot write inside its own install directory.
-- That is wrong, and was measured to be wrong on a real dedicated server (see the
-- filesystem findings in README.md): getModFileWriter writes to a mod-scoped folder
-- and is not subject to the ini/cfg/txt/log/json extension allowlist that constrains
-- getFileWriter. The game Logs folder is still the right place for THIS log -- it
-- puts the mod log beside console.txt where people already look, and writeLog
-- timestamps and rotates it for us -- but that is a choice, not a limitation.
--
-- Debug defaults OFF, which historically meant nothing reached this file on a
-- normal server -- including the moment something actually broke (a 1.2.0
-- server-side load crash left the file with 4 uninformative lines). So lines
-- carrying one of four leading markers -- WARNING:, ERROR:, checkpoint:, boot: --
-- bypass the Debug gate and are written unconditionally as long as the
-- AlwaysLogErrors sandbox option (default true) is on. Everything else keeps the
-- original Debug-gated behaviour unchanged.
local ALWAYS_LOG_PREFIXES = { "WARNING:", "ERROR:", "checkpoint:", "boot:" }
local function alwaysLogLine(line)
    for _, p in ipairs(ALWAYS_LOG_PREFIXES) do
        if line:sub(1, #p) == p then return true end
    end
    return false
end

fileLog = function(line)
    pcall(function()
        local opts = (SandboxVars and SandboxVars.LasciviousFactionsSystem) or {}
        local debugOn = opts.Debug == true
        local force = opts.AlwaysLogErrors ~= false and alwaysLogLine(line)
        if not (debugOn or force) then return end
        local side = isServer() and "server" or (isClient() and "client" or "sp")
        -- writeLog punctuates every entry with its own trailing full stop, so any
        -- message that already ends in one comes out as "..". Drop ours and let the
        -- engine supply it, rather than hunting the periods out of dozens of strings.
        if line:sub(-1) == "." then line = line:sub(1, -2) end
        writeLog("LasciviousFactionsSystem", "[" .. side .. "] " .. line)
    end)
end

-- Do not replace _G.print. An earlier tee inspected every print issued by every
-- loaded mod/game subsystem, an invasive global hook whose lifetime and ordering
-- could not be controlled. Durable LFS messages now flow explicitly through
-- FF.print/FF.warn/FF.checkpoint; direct informational prints remain console-only.

-- One recognisable session-start line, always logged (see fileLog's checkpoint:
-- bypass) so "is the file even being written to" is answerable from the file
-- itself without needing Debug on first.
local function logSessionStart()
    local opts = (SandboxVars and SandboxVars.LasciviousFactionsSystem) or {}
    FF.checkpoint(string.format("session start (Debug=%s, AlwaysLogErrors=%s)",
        tostring(opts.Debug == true), tostring(opts.AlwaysLogErrors ~= false)))
end
if Events and Events.OnGameStart then
    if FF._sessionGameStartHook then Events.OnGameStart.Remove(FF._sessionGameStartHook) end
    FF._sessionGameStartHook = logSessionStart
    Events.OnGameStart.Add(logSessionStart)
end
if Events and Events.OnServerStarted then
    if FF._sessionServerStartHook then Events.OnServerStarted.Remove(FF._sessionServerStartHook) end
    FF._sessionServerStartHook = logSessionStart
    Events.OnServerStarted.Add(logSessionStart)
end

-- ---------------------------------------------------------------------------
-- Authoritative data
-- ---------------------------------------------------------------------------
-- Single transmitted GlobalModData table. The server mutates it and calls
-- FF.sync(); clients treat their copy as a read-only cache refreshed on
-- OnReceiveGlobalModData. Shape:
--   data.factions[name]     = { owner, members={[user]=roleName}, tag, created,
--                               roles={ [roleName]={ <perm>=bool,... } },
--                               claims={ {x1,y1,x2,y2, access=, grants=}, ... },
--                               respawn, loot, raid }
--   data.playerIndex[user]  = factionName   (reverse lookup)
function FF.getData()
    local data = ModData.getOrCreate(FF.MODDATA)
    -- Treat malformed/partially-written roots as an empty collection instead of
    -- letting a single bad save value turn every pairs()/index operation into a
    -- permanent load-time failure. Valid tables are retained verbatim.
    if type(data.factions) ~= "table" then data.factions = {} end
    if type(data.playerIndex) ~= "table" then data.playerIndex = {} end
    -- Per-player cache: [username] = { kills, hours, lastRawKills, lastRawHours,
    -- updatedAt, source }. `kills`/`hours` are the authoritative values used by
    -- score math. By default they mirror the current character's vanilla counters
    -- and reset on death. With PreserveMemberPowerOnDeath enabled, they become
    -- accumulated account-style totals; `lastRaw*` still mirror only the current
    -- character baseline so future kills/hours can be added without double-counting.
    -- `lastRaw*` also remain compatibility aliases for API consumers from schema v1.
    -- A faction's score (FF.factionScore) is the live sum of this table over its CURRENT
    -- members -- a player who leaves takes their points with them.
    if type(data.playerScore) ~= "table" then data.playerScore = {} end
    -- Persistent decline throttles, keyed by faction then target username. The server
    -- owns this table; clients receive it only because the registry is the mod's single
    -- replicated state object. Entries contain no secret information.
    if type(data.inviteCooldowns) ~= "table" then data.inviteCooldowns = {} end
    -- Tribute deposit/withdraw replay-protection cache: [username] = { recentResults=
    -- {[command.."|"..requestId]={status="processing"|"complete",...}},
    -- recentOrder={command.."|"..requestId, ...}, updatedAt=epochMs }.
    -- Server owns this table; clients receive it only because the registry is the
    -- mod's single replicated state object, same as inviteCooldowns above.
    if type(data.tributeRequests) ~= "table" then data.tributeRequests = {} end
    -- Active wars: [key "A|B" sorted] = { a, b, declaredAt (ms), target, score={[name]=n} }.
    -- Ceasefires: [key] = expiresAt (ms), blocking re-declaration after a war ends.
    if type(data.wars) ~= "table" then data.wars = {} end
    if type(data.ceasefires) ~= "table" then data.ceasefires = {} end
    -- Leaderboard season: number, startedAt (ms), baseline={[faction]=score at season
    -- start} for season-relative scoring, history={ {number, winner, score, endedAt}, ... }
    -- (newest first, capped). The baseline is subtracted for season-relative display
    -- (see FF.seasonScore); character death may reduce that relative score.
    if type(data.season) ~= "table" then
        data.season = { number = 1, startedAt = 0, baseline = {}, history = {} }
    end
    if type(data.season.baseline) ~= "table" then data.season.baseline = {} end
    if type(data.season.history) ~= "table" then data.season.history = {} end
    -- Non-aggression pacts: [key "A|B" sorted] = { a, b, expiresAt (ms; 0 = indefinite) }.
    -- Mutual; blocks war declaration and raids between the two while active.
    if type(data.pacts) ~= "table" then data.pacts = {} end
    -- Admin no-claim zones: areas where factions may not claim land (spawn towns, a
    -- shared trade hub, a landmark the server wants kept neutral).
    --   [id] = { id, name, source, points = { {x1,y1,x2,y2}, ... } }
    -- source is "admin" (a rectangle drawn in-world) or "zone" (geometry copied from a
    -- named PhunZones landmark). A global list of named rectangles, so it replicates and
    -- draws the same way as a claim. Empty table = the feature is off; there is nothing
    -- to configure.
    if type(data.noClaim) ~= "table" then data.noClaim = {} end
    return data
end

-- Push the authoritative table to all clients. Server/host only; a no-op guard
-- keeps it harmless if called client-side.
--
-- ModData.transmit sends the WHOLE registry -- every faction, claim, war and pact,
-- on the order of a couple hundred KB on a busy server -- and there are many call
-- sites. Sending that synchronously per mutation meant a role rename or a claim edit
-- each cost a full broadcast to every client, and bursts were far worse: disbanding
-- a ten-member faction touches ten player records back to back.
--
-- So FF.sync() only marks the registry dirty and a tick coalesces: at most one
-- transmit per SYNC_FLUSH_INTERVAL no matter how many call sites fired. The
-- accompanying `notify`/`factionEvent` server commands are display-only (the client
-- formats a localized template out of `args` rather than re-reading the registry),
-- so a chat line landing a fraction of a second before the data behind it is not
-- observable. Anything that genuinely needs the data on the wire first calls
-- FF.syncNow().
local SYNC_FLUSH_INTERVAL = 0.2
local syncDirty = false
local nextSyncFlush = 0

-- Millisecond wall clock. getTimestamp() is whole seconds, which would quantize the
-- flush to 1 Hz -- five times slower than intended. Same Calendar idiom the server
-- uses for its own nowMs().
local function syncClockMs()
    local ok, ms = pcall(function() return Calendar.getInstance():getTimeInMillis() end)
    return ok and ms or nil
end

-- Transmit immediately, bypassing the coalescing window.
function FF.syncNow()
    if isClient() and not isCoopHost() then
        return false
    end
    syncDirty = false
    ModData.transmit(FF.MODDATA)
    return true
end

function FF.sync()
    if isClient() and not isCoopHost() then
        return false
    end
    local newlyDirty = not syncDirty
    syncDirty = true
    return newlyDirty
end

local function syncFlushTick()
    if not syncDirty then return end
    local now = syncClockMs()
    -- No clock (very early boot): flush rather than sit on a dirty registry forever.
    if now then
        if now < nextSyncFlush then return end
        nextSyncFlush = now + SYNC_FLUSH_INTERVAL * 1000
    end
    FF.syncNow()
end

-- Registered unconditionally: the side guard lives in FF.sync, so on a remote client
-- syncDirty is never set and this returns on its first line.
if Events and Events.OnTick then
    if FF._syncFlushTick then Events.OnTick.Remove(FF._syncFlushTick) end
    FF._syncFlushTick = syncFlushTick
    Events.OnTick.Add(syncFlushTick)
end

function FF.getFaction(name)
    if not name then return nil end
    return FF.getData().factions[name]
end

-- A chave de identidade certa para QUALQUER leitura/escrita de estado
-- persistido deste modulo (playerIndex, faction.members, faction.owner,
-- invites, playerScore, roster de findOnlinePlayer, etc.) -- nunca
-- player:getUsername() cru. Em MP/coop-host de verdade e identico a
-- getUsername() (ja estavel la); em SP puro devolve a mesma constante fixa
-- sempre, independente do personagem atual. Ver LasciviousSystemsSteamId.lua
-- (M.SP_IDENTITY) para a decompilacao que prova por que getUsername() cru NAO
-- e estavel em SP puro -- usar isso diretamente teria reintroduzido, so que
-- para o sistema de faccoes inteiro, o mesmo bug de precisao/instabilidade
-- que M.accountKey ja existe para resolver do lado do SteamID.
function FF.identityUsername(player)
    if not player then return nil end
    if LasciviousSystemsSteamId.isTrueSoloSP() then
        return LasciviousSystemsSteamId.SP_IDENTITY
    end
    local ok, username = pcall(function() return player:getUsername() end)
    if ok and type(username) == "string" and username ~= "" then return username end
    return nil
end

function FF.getFactionOfPlayer(username)
    if not username then return nil end
    local data = FF.getData()
    local name = data.playerIndex[username]
    return name, name and data.factions[name] or nil
end

-- Is this username a member (any role) of the named faction?
function FF.isMemberOf(factionName, username)
    if not (factionName and username) then return false end
    local faction = FF.getFaction(factionName)
    return faction ~= nil and faction.members ~= nil and faction.members[username] ~= nil
end

-- Read-only cross-system boundary for PvP side effects (Shop kill-credit theft,
-- combat rewards, etc.). True means LFS considers this exact player pair protected:
-- distinct users, same live faction, global enforcement enabled, and that faction
-- has not opted into friendly fire. Callers must not infer this from client damage,
-- because Build 42 offers no cancellable server damage event.
function FF.isFriendlyFireProtected(attackerUsername, victimUsername)
    if not (attackerUsername and victimUsername) or attackerUsername == victimUsername then return false end
    if not FF.getOptions().enforceFriendlyFire then return false end
    local attackerFaction = FF.getFactionOfPlayer(attackerUsername)
    if not attackerFaction or attackerFaction ~= FF.getFactionOfPlayer(victimUsername) then return false end
    local faction = FF.getFaction(attackerFaction)
    return faction ~= nil and faction.friendlyFire ~= true
end

-- ---------------------------------------------------------------------------
-- Roles & permissions
-- ---------------------------------------------------------------------------
-- Each faction has a `roles` map { [roleName] = { <perm>=bool, ... } } and each
-- member is assigned a role name via members[user]. The owner is implicit (never
-- stored in `roles`) and always has every permission. "member" is the reserved
-- fallback role that role deletion reassigns to.

-- Canonical permission list (drives UI + validation). Order = UI display order.
FF.PERMISSIONS = { "claim", "setRespawn", "build", "move", "manageMembers", "startRaid", "manageTribute", "protectVehicles" }

-- The two default roles every faction starts with. Their names match the old
-- lowercase enum values, so pre-roles saves migrate for free (existing
-- members[user]="officer"/"member" already point at these).
function FF.defaultRoles()
    return {
        officer = { claim = true,  setRespawn = true,  build = true, move = true, manageMembers = true,  startRaid = true,  manageTribute = true,  protectVehicles = true },
        member  = { claim = false, setRespawn = false, build = true, move = true, manageMembers = false, startRaid = false, manageTribute = false, protectVehicles = false },
    }
end

-- Migration entry point: give a faction the default roles if it has none.
-- Idempotent -- safe to call on every access.
function FF.ensureRoles(faction)
    if faction and type(faction.members) ~= "table" then faction.members = {} end
    if faction and type(faction.roles) ~= "table" then
        faction.roles = FF.defaultRoles()
    end
    -- "member" is the reserved reassignment target. A corrupt/very old save
    -- without it made deleteRole leave members pointing at a nil role forever.
    if faction and type(faction.roles.member) ~= "table" then
        faction.roles.member = FF.defaultRoles().member
    end
    -- Backfill for factions whose `roles` already existed before protectVehicles
    -- was added -- the branch above only ever seeds FRESH defaults for a
    -- faction with no roles table at all, so an existing "officer" role would
    -- otherwise silently read protectVehicles as false forever (roleCan
    -- treats a missing key as false), contradicting the explicit "on by
    -- default for Líder/Oficial" request. The nil-check makes this
    -- self-limiting: once set here (or later flipped by the owner via the
    -- Roles UI), the key is no longer nil, so this never fires again for that
    -- faction/role. Custom roles are deliberately left untouched, same as any
    -- other permission a custom role doesn't explicitly opt into.
    if faction and faction.roles and type(faction.roles.officer) == "table"
        and faction.roles.officer.protectVehicles == nil then
        faction.roles.officer.protectVehicles = true
    end
    return faction
end

-- May this member exercise `perm` in their faction? Owner -> always true.
-- Nil-safe: unknown member, unknown role, or missing flag -> false. Replaces the
-- old isOwnerOrOfficer gate.
function FF.roleCan(faction, username, perm)
    if not (faction and username and perm) then return false end
    if faction.owner == username then return true end
    local roleName = faction.members and faction.members[username]
    if not roleName then return false end
    local role = faction.roles and faction.roles[roleName]
    return type(role) == "table" and role[perm] == true
end

-- ---------------------------------------------------------------------------
-- Player score & faction strength
-- ---------------------------------------------------------------------------
-- "Faction strength" is a single number: the live sum, over the faction's CURRENT
-- members, of each member's kill/survival totals (data.playerScore, see FF.getData).
-- It is the ONLY scoring concept in this mod -- it drives claim size
-- (FF.maxClaimTiles below) and the leaderboard alike. A player who leaves a faction
-- takes their points with them; by default death resets only that player's record
-- (see LFS_Kills.lua/LFS_Respawn.lua), which may leave existing claims above the new
-- cap. PreserveMemberPowerOnDeath keeps the contributed total instead.

-- Migration entry point: give a faction a zeroed combat-record table if it has
-- none. Purely informational (raid win/loss/defence counters shown in the UI) --
-- it does NOT feed FF.factionScore. Idempotent -- safe to call on every access.
function FF.ensureStats(faction)
    if faction and type(faction.stats) ~= "table" then
        faction.stats = { raidsWon = 0, raidsLost = 0, raidsDefended = 0 }
    end
    if faction then
        for _, key in ipairs({ "raidsWon", "raidsLost", "raidsDefended" }) do
            local value = tonumber(faction.stats[key]) or 0
            if value ~= value or value == math.huge or value == -math.huge then value = 0 end
            faction.stats[key] = math.max(0, math.floor(value))
        end
    end
    return faction
end

-- Migration entry point: give a faction a zeroed tribute treasury if it has none
-- (pre-tribute saves). Idempotent -- safe to call on every access. `history` is a
-- plain ordered list of { at, kind="deposit"|"withdraw", actor, amount }, oldest
-- first, trimmed to FF.TRIBUTE_HISTORY_MAX entries (see appendTributeHistory in
-- LFS_Server.lua). Passive per-tick tax collection never appends here -- only
-- manual deposit/withdraw/donate actions do.
FF.TRIBUTE_HISTORY_MAX = 100

function FF.ensureTribute(faction)
    if faction and type(faction.tribute) ~= "table" then
        faction.tribute = { balance = 0, ratePercent = 0, history = {} }
    end
    if faction then
        local balance = tonumber(faction.tribute.balance) or 0
        if balance ~= balance or balance == math.huge or balance == -math.huge then balance = 0 end
        faction.tribute.balance = math.max(0, math.min(9000000000000, balance))
        local rate = tonumber(faction.tribute.ratePercent) or 0
        if rate ~= rate or rate == math.huge or rate == -math.huge then rate = 0 end
        faction.tribute.ratePercent = math.max(0, math.min(100, rate))
        if type(faction.tribute.history) ~= "table" then faction.tribute.history = {} end
    end
    return faction
end

-- Migration entry point for claim decay: stamp a real-world "last active" epoch on
-- factions that predate the field so they start with a fresh clock (and don't decay
-- the instant decay is enabled). Idempotent -- safe to call on every access. `nowMs`
-- is the current Calendar epoch in ms, passed in by the caller (this file does no IO).
function FF.ensureActivity(faction, nowMs)
    if faction then
        local value = tonumber(faction.lastActive)
        if not value or value ~= value or value == math.huge or value == -math.huge or value < 0 then
            faction.lastActive = nowMs
        else
            faction.lastActive = value
        end
    end
    return faction
end

-- One player's native-stat cache, seeded to zero on first read. Idempotent and safe
-- for old saves whose records predate the snapshot fields.
function FF.ensurePlayerScore(username)
    if not username then return nil end
    local scores = FF.getData().playerScore
    local rec = scores[username]
    if not rec then
        rec = { kills = 0, hours = 0, lastRawKills = 0, lastRawHours = 0 }
        scores[username] = rec
    end
    local function scoreValue(value, fallback)
        value = tonumber(value)
        if not value or value ~= value or value == math.huge or value == -math.huge then
            value = fallback or 0
        end
        return math.max(0, value)
    end
    rec.kills = scoreValue(rec.kills, 0)
    rec.hours = scoreValue(rec.hours, 0)
    rec.lastRawKills = scoreValue(rec.lastRawKills, rec.kills)
    rec.lastRawHours = scoreValue(rec.lastRawHours, rec.hours)
    return rec
end

-- One member's own score: zombie kills + hours survived, each weighted by its sandbox
-- multiplier. Pure -- reads the last authoritative score stored server-side. By
-- default this is the current-character snapshot; with PreserveMemberPowerOnDeath it
-- is the accumulated total across deaths. Online snapshots refresh continuously;
-- offline snapshots persist in GlobalModData.
function FF.playerScore(username, opts)
    opts = opts or FF.getOptions()
    local rec = username and FF.getData().playerScore[username]
    if not rec then return 0 end
    local kills = tonumber(rec.kills) or 0
    local hours = tonumber(rec.hours) or 0
    if kills ~= kills or kills == math.huge or kills == -math.huge then kills = 0 end
    if hours ~= hours or hours == math.huge or hours == -math.huge then hours = 0 end
    return math.max(0, kills) * opts.pointsPerZombieKill
        + math.max(0, hours) * opts.pointsPerHourSurvived
end

-- Faction score: the live sum of FF.playerScore over the faction's CURRENT
-- members, plus any debug bonus (see LFS_Server.lua's Handlers.debugAddPower --
-- an admin-only, sandbox-gated test action, 0 on every faction otherwise). No IO
-- -> safe to call from client UI.
function FF.factionScore(faction, opts)
    if not (faction and faction.members) then return 0 end
    opts = opts or FF.getOptions()
    local total = 0
    for user in pairs(faction.members) do
        total = total + FF.playerScore(user, opts)
    end
    local bonus = tonumber(faction.debugPowerBonus) or 0
    if bonus ~= bonus or bonus == math.huge or bonus == -math.huge then bonus = 0 end
    return total + bonus
end

-- Season-relative score: the live score minus the faction's score at the moment
-- the season started (data.season.baseline[name], a plain number snapshotted when
-- the season rolls over). A missing baseline (faction created mid-season) subtracts
-- 0, which is correct -- it had nothing to its name yet. Pure.
function FF.seasonScore(faction, opts, name)
    if not faction then return 0 end
    opts = opts or FF.getOptions()
    local baseline = (FF.getData().season or {}).baseline
    local snap = baseline and name and baseline[name] or 0
    return FF.factionScore(faction, opts) - snap
end

-- ---------------------------------------------------------------------------
-- Faction relationships (ally / enemy)
-- ---------------------------------------------------------------------------
-- faction.relations[other] = "ally" | "enemy" (this faction's own stance). Ally
-- is always MUTUAL (only ever set via accept, cleared on either side's break);
-- enemy is one-sided. faction.allyRequests[requester] = true holds incoming
-- alliance requests. faction.shareMapWithAllies (default true) opts into letting
-- allies see this faction's claims. faction.shareMemberLocations (default FALSE)
-- opts into letting allies see this faction's members' live map markers --
-- independent of claim sharing because positions are far more sensitive.

-- Are these two factions mutually allied?
function FF.areAllied(nameA, nameB)
    if not (nameA and nameB) or nameA == nameB then return false end
    local a = FF.getFaction(nameA)
    local b = FF.getFaction(nameB)
    if not (a and b and a.relations and b.relations) then return false end
    return a.relations[nameB] == "ally" and b.relations[nameA] == "ally"
end

-- Order-independent key for the war/ceasefire between two factions.
function FF.warKey(nameA, nameB)
    if not (nameA and nameB) then return nil end
    if nameA > nameB then nameA, nameB = nameB, nameA end
    return nameA .. "|" .. nameB
end

FF.FACTION_NAME_MAX = 32

-- Is this usable as a faction name? Returns ok(boolean), reason(string|nil).
--
-- Introduced for the admin rename, where a bad name is far more expensive than at
-- creation: the name is the registry's primary key and a dozen tables store it as a
-- foreign key, so an unrepresentable one is baked into all of them.
--
-- Existing saves are never renamed by this validator; it only gates newly-created
-- names and explicit admin renames.
function FF.validateFactionName(name)
    if type(name) ~= "string" or name == "" then return false, "a name is required" end
    if name ~= name:match("^%s*(.-)%s*$") then
        return false, "no leading or trailing spaces"
    end
    if FF.truncateUtf8(name, FF.FACTION_NAME_MAX) ~= name then
        return false, "at most " .. FF.FACTION_NAME_MAX .. " characters"
    end
    -- "|" is FF.warKey's separator. A name containing one makes war and ceasefire keys
    -- ambiguous and unparseable, which is how the rename walk finds them.
    if name:find("|", 1, true) then return false, "no '|' character" end
    -- Faction names/tags are embedded in ISRichTextPanel output. Keep markup out of
    -- the registry at its source rather than trusting every display surface to escape.
    if name:find("<", 1, true) or name:find(">", 1, true) then
        return false, "no '<' or '>' characters"
    end
    -- Reject control bytes but retain UTF-8 names (important for Portuguese and
    -- existing player expectations). Java supplies valid strings at this boundary.
    for i = 1, #name do
        local b = string.byte(name, i)
        if b < 32 or b == 127 then return false, "no control characters" end
    end
    return true
end

-- The active war record between two factions (data.wars), or nil. Pure registry read,
-- so the client UI and server share it.
function FF.warBetween(nameA, nameB)
    local key = FF.warKey(nameA, nameB)
    if not key then return nil end
    local wars = FF.getData().wars
    return wars and wars[key] or nil
end

-- Seconds remaining on the ceasefire between two factions (0 if none/expired). Pure.
function FF.ceasefireLeft(nameA, nameB, nowMsValue)
    local key = FF.warKey(nameA, nameB)
    local cfs = key and FF.getData().ceasefires
    local exp = cfs and cfs[key]
    if not exp then return 0 end
    return math.max(0, math.floor((exp - (nowMsValue or 0)) / 1000))
end

-- Is there an active non-aggression pact between two factions? Pure registry read.
-- `nowMsValue` (Calendar ms) is needed to evaluate a timed pact; an indefinite pact
-- (expiresAt == 0) is always active. A record with an elapsed expiry reads inactive
-- (the server deletes lapsed records lazily where it already touches them).
function FF.pactActive(nameA, nameB, nowMsValue)
    local key = FF.warKey(nameA, nameB)
    local pacts = key and FF.getData().pacts
    local p = pacts and pacts[key]
    if not p then return false end
    if (p.expiresAt or 0) == 0 then return true end
    return (nowMsValue or 0) < p.expiresAt
end

-- The pact record between two factions, or nil. Pure registry read.
function FF.pactBetween(nameA, nameB)
    local key = FF.warKey(nameA, nameB)
    local pacts = key and FF.getData().pacts
    return pacts and pacts[key] or nil
end

-- Does a pact between the two carry the given clause? (share_map / share_locations).
-- Expiry isn't checked here -- the server's sweep deletes lapsed pacts promptly and
-- reprojects, so a record's presence is authoritative enough for a map/location toggle.
function FF.pactHasClause(nameA, nameB, clause)
    local p = FF.pactBetween(nameA, nameB)
    return p ~= nil and p.terms ~= nil and p.terms[clause] == true
end

-- May `viewerName`'s members see `ownerName`'s claims? Allied + owner opted in, OR an
-- active pact with a share_map clause.
function FF.sharesMapWith(ownerName, viewerName)
    if FF.areAllied(ownerName, viewerName) then
        local owner = FF.getFaction(ownerName)
        if owner ~= nil and owner.shareMapWithAllies ~= false then return true end
    end
    return FF.pactHasClause(ownerName, viewerName, "shareMap")
end

-- May `viewerName`'s members see `ownerName`'s members' LIVE LOCATIONS on the map?
-- Opt-in for allies (default off), OR a pact with a share_locations clause.
function FF.sharesLocationsWith(ownerName, viewerName)
    if FF.areAllied(ownerName, viewerName) then
        local owner = FF.getFaction(ownerName)
        if owner ~= nil and owner.shareMemberLocations == true then return true end
    end
    return FF.pactHasClause(ownerName, viewerName, "shareLocations")
end

-- Access resolver used by the permission hooks: may this player exercise `perm`
-- ("build" / "move") on tile (x,y)? Returns allowed(boolean), owningFaction(string|nil).
--   * not a claim               -> allowed
--   * permissions disabled       -> allowed
--   * claim owned by another / role lacks perm -> denied
-- Pure: reads the registry (via FF.Claims) only. FF.Claims is referenced lazily so
-- Shared has no load-order dependency on the Claims module.
-- Called from the client-side permission hooks (hot path -- keep it allocation-
-- light and unlogged). Membership + per-role claim rights are read from the
-- PhunZones zone's embedded roster (Claims.factionMembersAt), which reaches remote
-- coop clients; the LasciviousFactionsSystem registry is only a fallback for older zones.
-- The embedded roster entry is either a per-perm table { build=bool, move=bool }
-- or, on zones written before per-role embedding, the boolean `true` (any member).
-- A non-member falls through to the per-AREA grant (Claims.factionMembersAt's trailing
-- returns): the individual rect the tile sits in may have been opened to allies or to
-- everyone. Only `build`/`move` resolve here -- `loot` is the SafeHouse's job and
-- never reaches this function.
function FF.playerCanActAt(username, x, y, perm)
    if not FF.getOptions().enforcePermissions then return true, nil end
    local Claims = FF.Claims
    if not (Claims and Claims.factionMembersAt) then return true, nil end
    local owner, members, areaAccess, areaGrants, areaAllies = Claims.factionMembersAt(x, y)
    if not owner then return true, nil end               -- not inside any claim
    if not username or username == "" then return true, owner end
    if members ~= nil then
        -- Authoritative, client-synced roster embedded on the zone.
        local entry = members[username]
        if entry ~= nil then
            if entry == true then return true, owner end -- legacy zone: any member allowed
            if type(entry) == "table" then
                return (perm == nil) or (entry[perm] == true), owner
            end
            return false, owner
        end
        -- Not on the roster. Before denying, check whether the specific AREA the tile
        -- falls in has been opened. areaAccess is nil on zones written before per-area
        -- access and on any area still private, which keeps the members-only default.
        if areaAccess and perm ~= nil and areaGrants and areaGrants[perm] == true then
            if areaAccess == "public" then return true, owner end
            if areaAccess == "allies" and areaAllies and areaAllies[username] then
                return true, owner
            end
        end
        return false, owner
    end
    -- Zone predates roster embedding: fall back to the registry if we have it,
    -- else fail OPEN so a stale zone never locks out a legitimate member.
    local faction = FF.getFaction(owner)
    if not faction then return true, owner end
    if faction.members == nil or faction.members[username] == nil then return false, owner end
    return (perm == nil) or FF.roleCan(faction, username, perm), owner
end

function FF.zoneKey(name)
    return FF.ZONE_PREFIX .. name
end

function FF.factionNameFromZoneKey(key)
    if type(key) ~= "string" then return nil end
    if key:sub(1, #FF.ZONE_PREFIX) == FF.ZONE_PREFIX then
        return key:sub(#FF.ZONE_PREFIX + 1)
    end
    return nil
end

-- Current whole in-game day, used to reset per-day raid attempt counters. Guards
-- against getGameTime() not being ready (returns 0 as a harmless fallback).
function FF.gameDay()
    local gt = getGameTime and getGameTime()
    if gt and gt.getWorldAgeHours then
        return math.floor(gt:getWorldAgeHours() / 24)
    end
    return 0
end

function FF.memberCount(faction)
    local n = 0
    if faction and faction.members then
        for _ in pairs(faction.members) do
            n = n + 1
        end
    end
    return n
end

-- ---------------------------------------------------------------------------
-- Pure claim math
-- ---------------------------------------------------------------------------

-- How many tiles a faction may claim in total, driven by its live strength score
-- (FF.factionScore) rather than raw member count -- a small but active faction can
-- out-claim a large but idle one.
function FF.maxClaimTiles(score, opts)
    opts = opts or FF.getOptions()
    local allowed = opts.baseClaimTiles + opts.tilesPerScorePoint * (score or 0)
    return math.min(allowed, opts.maxClaimTiles)
end

-- Number of disconnected territory areas unlocked by faction score. Every faction
-- starts with one area; each complete PointsPerClaimArea block adds one more.
function FF.maxClaimAreas(score, opts)
    opts = opts or FF.getOptions()
    local step = math.max(1, tonumber(opts.pointsPerClaimArea) or 2500)
    return 1 + math.floor(math.max(0, tonumber(score) or 0) / step)
end

-- Inclusive tile area of a {x1,y1,x2,y2} rect (normalised so x1<=x2, y1<=y2).
function FF.rectArea(rect)
    local w = math.abs(rect[3] - rect[1]) + 1
    local h = math.abs(rect[4] - rect[2]) + 1
    return w * h
end

function FF.totalArea(rects)
    -- Claims are unions of rectangles.  Older saves (and an in-progress drag) may
    -- contain overlaps, so summing the rectangles would charge the same tile more
    -- than once.  canonicaliseClaimRects is defined a little further below, after
    -- the per-area metadata helpers it needs.
    if FF.canonicaliseClaimRects then
        local canonical = FF.canonicaliseClaimRects(rects)
        local total = 0
        for i = 1, #canonical do total = total + FF.rectArea(canonical[i]) end
        return total
    end
    local total = 0
    for i = 1, #(rects or {}) do
        total = total + FF.rectArea(rects[i])
    end
    return total
end

-- ---------------------------------------------------------------------------
-- Per-area access
--
-- A claim rect may carry two optional named keys beside its four coordinates:
--   access = "private" | "allies" | "public"        -- WHO the grant reaches
--   grants = { loot=, build=, move= }                -- WHAT they may do
-- nil means "private with no grants", which is the pre-1.2.9 behaviour, so old
-- saves need no migration. A grant key that is simply absent reads as false.
-- Members of the owning faction are never affected -- their access always comes
-- from their role.
--
-- The grant kinds are enforced by two different systems:
--   * `loot`         -- by the vanilla SafeHouse the server builds per rect: the
--                       rect gets NO safehouse, so vanilla loot rules apply to
--                       everyone (authoritative). See rebuildFactionSafehouses.
--   * `build`/`move` -- by the client-side permission hooks reading the zone
--                       (advisory). See LFS_Permissions.lua's header.
-- ---------------------------------------------------------------------------
FF.CLAIM_ACCESS = { "private", "allies", "public" }
FF.AREA_GRANTS = { "loot", "build", "move" }

local ACCESS_VALID = { private = true, allies = true, public = true }

-- Access level of a rect, defaulting to "private" for anything unrecognised.
function FF.areaAccess(rect)
    local a = rect and rect.access
    return (a ~= nil and ACCESS_VALID[a]) and a or "private"
end

-- Grant set of a rect as a plain table. A private area grants nothing regardless
-- of what is stored, so callers never have to check the level as well.
function FF.areaGrants(rect)
    if FF.areaAccess(rect) == "private" then
        return { loot = false, build = false, move = false }
    end
    local g = rect and rect.grants
    if type(g) ~= "table" then g = {} end
    return {
        loot  = g.loot == true,
        build = g.build == true,
        move  = g.move == true,
    }
end

-- Coerce untrusted access/grants onto `dest` (a rect). Anything unrecognised
-- degrades to private/no-grant rather than being rejected -- a malformed area
-- must never be able to open land it wasn't meant to.
function FF.sanitiseArea(dest, access, grants)
    if not ACCESS_VALID[access] or access == "private" then
        dest.access, dest.grants = nil, nil
        return dest
    end
    dest.access = access
    if type(grants) ~= "table" then grants = {} end
    dest.grants = {
        loot  = grants.loot == true,
        build = grants.build == true,
        move  = grants.move == true,
    }
    return dest
end

-- Normalise a rect so x1<=x2 and y1<=y2. Returns a fresh table.
-- Carries per-area access through: this is the canonical rect constructor, used by
-- FF.requestClaim and Handlers.claim, so preserving the metadata here is what stops
-- it being silently dropped on the way to the registry.
function FF.normaliseRect(rect)
    local out = {
        math.min(rect[1], rect[3]),
        math.min(rect[2], rect[4]),
        math.max(rect[1], rect[3]),
        math.max(rect[2], rect[4]),
    }
    if rect.access ~= nil then FF.sanitiseArea(out, rect.access, rect.grants) end
    -- Client-only paint flags.  The server never persists these, but carrying them
    -- here lets the claim editor split an L-shaped expansion without losing which
    -- pieces are pending/current-preview pieces.
    if rect.new == true then out.new = true end
    if rect.preview == true then out.preview = true end
    return out
end

-- A compact signature for metadata that must not silently bleed from one area into
-- another while a union is split into rectangles.  `new`/`preview` are deliberately
-- optional: geometry grouping ignores paint state, while canonicalisation preserves it.
local function areaStyleKey(rect, includePaint)
    local g = FF.areaGrants(rect)
    local key = FF.areaAccess(rect) .. "|" .. tostring(g.loot) .. "|"
        .. tostring(g.build) .. "|" .. tostring(g.move)
    if includePaint then
        key = key .. "|" .. tostring(rect and rect.new == true)
            .. "|" .. tostring(rect and rect.preview == true)
    end
    return key
end

local function copyAreaMetadata(dest, src)
    FF.sanitiseArea(dest, src and src.access, src and src.grants)
    if src and src.new == true then dest.new = true end
    if src and src.preview == true then dest.preview = true end
    return dest
end

-- Exact rectangle union, represented again as non-overlapping rectangles.  Coordinate
-- compression keeps this proportional to the number of rectangles rather than the
-- number of world tiles, so even a very large claim remains cheap.  Earlier entries
-- win where rectangles overlap: the already-owned area is passed first by the editor,
-- which preserves its access settings while only the genuinely new tiles inherit the
-- settings of the drag.
function FF.canonicaliseClaimRects(rects)
    local clean, xs, ys, seenX, seenY = {}, {}, {}, {}, {}
    for i = 1, #(rects or {}) do
        local src = rects[i]
        if type(src) == "table" and type(src[1]) == "number" and type(src[2]) == "number"
            and type(src[3]) == "number" and type(src[4]) == "number" then
            local r = FF.normaliseRect(src)
            r[1], r[2], r[3], r[4] = math.floor(r[1]), math.floor(r[2]),
                math.floor(r[3]), math.floor(r[4])
            copyAreaMetadata(r, src)
            clean[#clean + 1] = r
            local xb, xe, yb, ye = r[1], r[3] + 1, r[2], r[4] + 1
            if not seenX[xb] then seenX[xb] = true; xs[#xs + 1] = xb end
            if not seenX[xe] then seenX[xe] = true; xs[#xs + 1] = xe end
            if not seenY[yb] then seenY[yb] = true; ys[#ys + 1] = yb end
            if not seenY[ye] then seenY[ye] = true; ys[#ys + 1] = ye end
        end
    end
    if #clean == 0 then return {} end
    table.sort(xs); table.sort(ys)

    local result, active = {}, {}
    for yi = 1, #ys - 1 do
        local y1, y2 = ys[yi], ys[yi + 1] - 1
        local row, xi = {}, 1
        while xi < #xs do
            local cellX = xs[xi]
            local owner = nil
            for ri = 1, #clean do
                local r = clean[ri]
                if cellX >= r[1] and cellX <= r[3] and y1 >= r[2] and y1 <= r[4] then
                    owner = r
                    break
                end
            end
            if not owner then
                xi = xi + 1
            else
                local style = areaStyleKey(owner, true)
                local runStart, runEnd = xi, xi
                while runEnd + 1 < #xs do
                    local nx = xs[runEnd + 1]
                    local nextOwner = nil
                    for ri = 1, #clean do
                        local r = clean[ri]
                        if nx >= r[1] and nx <= r[3] and y1 >= r[2] and y1 <= r[4] then
                            nextOwner = r
                            break
                        end
                    end
                    if not nextOwner or areaStyleKey(nextOwner, true) ~= style then break end
                    runEnd = runEnd + 1
                end
                local rx1, rx2 = xs[runStart], xs[runEnd + 1] - 1
                local key = style .. "@" .. tostring(rx1) .. ":" .. tostring(rx2)
                local prior = active[key]
                if prior and prior[4] + 1 == y1 then
                    prior[4] = y2
                    row[key] = prior
                else
                    local out = copyAreaMetadata({ rx1, y1, rx2, y2 }, owner)
                    result[#result + 1] = out
                    row[key] = out
                end
                xi = runEnd + 1
            end
        end
        active = row
    end
    return result
end

-- Rectangles belong to one logical area when they overlap or share an EDGE.  Merely
-- touching at a corner does not join two territories.  Access/grant boundaries remain
-- separate logical areas so a public shop beside a private base can still be managed
-- independently.
function FF.rectsEdgeConnected(a, b)
    local overlapX = a[1] <= b[3] and a[3] >= b[1]
    local overlapY = a[2] <= b[4] and a[4] >= b[2]
    if overlapX and overlapY then return true end
    if overlapY and (a[3] + 1 == b[1] or b[3] + 1 == a[1]) then return true end
    if overlapX and (a[4] + 1 == b[2] or b[4] + 1 == a[2]) then return true end
    return false
end

function FF.claimComponents(rects, accessSensitive)
    local n = #(rects or {})
    local parent = {}
    for i = 1, n do parent[i] = i end
    local function find(i)
        while parent[i] ~= i do
            parent[i] = parent[parent[i]]
            i = parent[i]
        end
        return i
    end
    for i = 1, n - 1 do
        for j = i + 1, n do
            local sameStyle = (accessSensitive == false)
                or areaStyleKey(rects[i], false) == areaStyleKey(rects[j], false)
            if sameStyle and FF.rectsEdgeConnected(rects[i], rects[j]) then
                parent[find(i)] = find(j)
            end
        end
    end
    local groups, byRoot = {}, {}
    for i = 1, n do
        local root = find(i)
        local g = byRoot[root]
        if not g then g = {}; byRoot[root] = g; groups[#groups + 1] = g end
        g[#g + 1] = i
    end
    return groups
end

function FF.claimComponentCount(rects)
    -- Area quota is geometric. Access/grant seams are management policies inside
    -- one continuous territory, not extra detached territories. Counting them here
    -- caused a connected expansion to be rejected as "too many areas" whenever it
    -- touched a neighbouring fragment with a different access policy.
    return #FF.claimComponents(rects, false)
end

-- How many logical public areas exist (not how many rectangles happen to encode them).
function FF.countPublicAreas(rects)
    local public = {}
    for i = 1, #(rects or {}) do
        if FF.areaAccess(rects[i]) == "public" then public[#public + 1] = rects[i] end
    end
    return #FF.claimComponents(public, true)
end

-- External edge segments of a rectangle union, in world tile-boundary coordinates.
-- Internal seams disappear because a segment is emitted only when the neighbouring
-- compressed cell is empty.  Used by the claim editor to display one continuous shape.
function FF.claimBoundarySegments(rects)
    local canonical = FF.canonicaliseClaimRects(rects)
    if #canonical == 0 then return {} end
    local xs, ys, sx, sy = {}, {}, {}, {}
    for _, r in ipairs(canonical) do
        local valuesX, valuesY = { r[1], r[3] + 1 }, { r[2], r[4] + 1 }
        for _, v in ipairs(valuesX) do if not sx[v] then sx[v] = true; xs[#xs + 1] = v end end
        for _, v in ipairs(valuesY) do if not sy[v] then sy[v] = true; ys[#ys + 1] = v end end
    end
    table.sort(xs); table.sort(ys)
    local occupied = {}
    for yi = 1, #ys - 1 do
        occupied[yi] = {}
        for xi = 1, #xs - 1 do
            local x, y = xs[xi], ys[yi]
            for _, r in ipairs(canonical) do
                if x >= r[1] and x <= r[3] and y >= r[2] and y <= r[4] then
                    occupied[yi][xi] = true
                    break
                end
            end
        end
    end

    local horizontal, vertical = {}, {}
    local function interval(bucket, key, a, b)
        bucket[key] = bucket[key] or {}
        bucket[key][#bucket[key] + 1] = { a, b }
    end
    for yi = 1, #ys - 1 do
        for xi = 1, #xs - 1 do
            if occupied[yi][xi] then
                if yi == 1 or not occupied[yi - 1][xi] then
                    interval(horizontal, ys[yi], xs[xi], xs[xi + 1])
                end
                if yi == #ys - 1 or not occupied[yi + 1][xi] then
                    interval(horizontal, ys[yi + 1], xs[xi], xs[xi + 1])
                end
                if xi == 1 or not occupied[yi][xi - 1] then
                    interval(vertical, xs[xi], ys[yi], ys[yi + 1])
                end
                if xi == #xs - 1 or not occupied[yi][xi + 1] then
                    interval(vertical, xs[xi + 1], ys[yi], ys[yi + 1])
                end
            end
        end
    end
    local out = {}
    local function merge(bucket, horizontalAxis)
        for fixed, spans in pairs(bucket) do
            table.sort(spans, function(a, b) return a[1] < b[1] end)
            local a, b = spans[1][1], spans[1][2]
            for i = 2, #spans do
                if spans[i][1] <= b then
                    b = math.max(b, spans[i][2])
                else
                    if horizontalAxis then out[#out + 1] = { a, fixed, b, fixed }
                    else out[#out + 1] = { fixed, a, fixed, b } end
                    a, b = spans[i][1], spans[i][2]
                end
            end
            if horizontalAxis then out[#out + 1] = { a, fixed, b, fixed }
            else out[#out + 1] = { fixed, a, fixed, b } end
        end
    end
    merge(horizontal, true); merge(vertical, false)
    return out
end

-- Standard inclusive AABB overlap test on two normalised rects.
function FF.rectsOverlap(a, b)
    return a[1] <= b[3] and a[3] >= b[1] and a[2] <= b[4] and a[4] >= b[2]
end

-- Chebyshev edge-to-edge gap (in tiles) between two normalised rects: the smallest
-- number of tiles separating them along the axis where they are furthest apart.
-- Overlapping or touching rects return 0.
function FF.rectGap(a, b)
    local dx = math.max(0, a[1] - b[3], b[1] - a[3])
    local dy = math.max(0, a[2] - b[4], b[2] - a[4])
    return math.max(dx, dy)
end

-- Are all claim rects part of a single cluster under "edge gap <= maxGap"? This is
-- what lets a multi-building base (a chain of boxes, each near the next) be one legal
-- claim while a rectangle stranded far from the rest is rejected. maxGap <= 0 disables
-- the rule (any layout allowed); 0 or 1 rects are trivially clustered. Pure; used by
-- both the server validator and the client drag preview so they always agree.
--
-- PUBLIC areas are exempt and do not participate at all -- a trade hub is meant to
-- sit somewhere neutral, away from your base, and that is the whole point of opening
-- it. They neither have to be near the cluster nor can they act as a bridge linking
-- two otherwise-stranded private groups. `allies` areas are NOT exempt: they are
-- still your own territory, and exempting them would reopen the land-grab this rule
-- exists to stop. MaxPublicClaimAreas bounds the exemption.
function FF.claimsClustered(rects, maxGap)
    maxGap = maxGap or 0
    if maxGap <= 0 then return true end

    local clustered = {}
    for i = 1, #(rects or {}) do
        if FF.areaAccess(rects[i]) ~= "public" then
            clustered[#clustered + 1] = rects[i]
        end
    end
    rects = clustered
    local n = #rects
    if n <= 1 then return true end

    -- Union-find over storage rectangles; an L-shaped logical area may use several,
    -- but the server's protocol complexity guard keeps the O(n^2) pass bounded.
    local parent = {}
    for i = 1, n do parent[i] = i end
    local function find(i)
        while parent[i] ~= i do
            parent[i] = parent[parent[i]]
            i = parent[i]
        end
        return i
    end
    for i = 1, n - 1 do
        for j = i + 1, n do
            if FF.rectGap(rects[i], rects[j]) <= maxGap then
                parent[find(i)] = find(j)
            end
        end
    end

    -- Single cluster iff every rect resolves to the same root.
    local root = find(1)
    for i = 2, n do
        if find(i) ~= root then return false end
    end
    return true
end

function FF.pointInRect(x, y, rect)
    return x >= rect[1] and x <= rect[3] and y >= rect[2] and y <= rect[4]
end

function FF.pointInClaim(faction, x, y)
    if not (faction and faction.claims) then return false end
    for i = 1, #faction.claims do
        if FF.pointInRect(x, y, faction.claims[i]) then
            return true
        end
    end
    return false
end

-- Approximate centre of a claim (centre of its first rect). Used as a fallback
-- respawn anchor when no explicit respawn point is set.
function FF.claimCentroid(faction)
    local rects = faction and faction.claims
    if not (rects and rects[1]) then return nil end
    local r = rects[1]
    return math.floor((r[1] + r[3]) / 2), math.floor((r[2] + r[4]) / 2)
end

-- Chebyshev distance (tiles) from (x, y) to the NEAREST tile of any of this
-- faction's claim rects -- 0 if the point is inside/touching one. Reuses
-- FF.rectGap (already the mod's established edge-to-edge distance metric for
-- claim adjacency/buffer rules) by treating the point as a zero-size rect, so
-- this stays consistent with every other distance check in this file instead
-- of introducing a second, differently-shaped metric (e.g. euclidean). nil
-- if the faction has no claims at all. Used by the Caçador upgrade
-- (LFS_Hunter.lua) to size its detection circle by proximity to territory.
function FF.distanceToClaim(faction, x, y)
    local rects = faction and faction.claims
    if not (rects and #rects > 0) then return nil end
    local point = { x, y, x, y }
    local min = nil
    for _, r in ipairs(rects) do
        local gap = FF.rectGap(r, point)
        if not min or gap < min then min = gap end
    end
    return min
end

-- Does any proposed rect overlap a claim belonging to a *different* faction?
-- Returns the conflicting faction name, or nil if clear.
function FF.findClaimConflict(proposedRects, excludeFactionName)
    local data = FF.getData()
    for name, faction in pairs(data.factions) do
        if name ~= excludeFactionName and faction.claims then
            for i = 1, #proposedRects do
                for j = 1, #faction.claims do
                    if FF.rectsOverlap(proposedRects[i], faction.claims[j]) then
                        return name
                    end
                end
            end
        end
    end
    return nil
end

-- Does any proposed rect sit within `buffer` tiles of a DIFFERENT, non-allied
-- faction's claim? This is a distinct rule from overlap (above, which is always
-- illegal) and from FF.claimsClustered (which governs how close a faction's OWN
-- areas must stay to each other) -- it stops a faction planting a claim directly
-- against a rival's border as a taunt/griefing move, while still letting allies
-- build claim-to-claim on purpose. Allied factions are exempt entirely; a PUBLIC
-- area on the proposing side is also exempt, since a trading post is meant to be
-- reachable and may legitimately sit at the edge of someone else's territory.
-- Returns the conflicting faction name, or nil if clear.
function FF.findClaimBufferConflict(proposedRects, factionName, opts)
    opts = opts or FF.getOptions()
    local buffer = opts.claimBufferTiles or 0
    if buffer <= 0 then return nil end
    local data = FF.getData()
    for name, faction in pairs(data.factions) do
        if name ~= factionName and faction.claims and not FF.areAllied(factionName, name) then
            for i = 1, #proposedRects do
                if FF.areaAccess(proposedRects[i]) ~= "public" then
                    for j = 1, #faction.claims do
                        if FF.rectGap(proposedRects[i], faction.claims[j]) < buffer then
                            return name
                        end
                    end
                end
            end
        end
    end
    return nil
end

-- ---------------------------------------------------------------------------
-- Admin no-claim zones
-- ---------------------------------------------------------------------------
-- These live here rather than in a file of their own because FF.validateClaim (below)
-- calls them, and Shared.lua cannot require a file that requires it back. Note that a
-- nil FF.<field> lookup is invisible to tools/check-lua.sh -- it only sees bare globals
-- -- so a load-order mistake here would ship silently. Keep them in this file.

-- Name of the no-claim zone covering (x,y), or nil. Used by the admin context menu.
function FF.noClaimAt(x, y)
    for _, zone in pairs(FF.getData().noClaim or {}) do
        for i = 1, #(zone.points or {}) do
            if FF.pointInRect(x, y, zone.points[i]) then
                return zone.name or zone.id
            end
        end
    end
    return nil
end

-- Does any proposed rect touch a no-claim zone? Returns the zone's name, or nil.
function FF.findNoClaimConflict(proposedRects)
    local zones = FF.getData().noClaim
    if not zones then return nil end
    for _, zone in pairs(zones) do
        for i = 1, #(proposedRects or {}) do
            for j = 1, #(zone.points or {}) do
                if FF.rectsOverlap(proposedRects[i], zone.points[j]) then
                    return zone.name or zone.id
                end
            end
        end
    end
    return nil
end

-- Every claim area currently overlapping `zone`, as { {name=, index=}, ... }. The
-- report the server's auto-strip consumes when a zone is created over live territory.
-- Indices are into faction.claims and are only valid until something removes one, so
-- the caller must remove them in descending index order (or per faction, back to front).
function FF.claimsInNoClaim(zone)
    local hits = {}
    local points = zone and zone.points
    if not points then return hits end
    for name, faction in pairs(FF.getData().factions) do
        local claims = faction.claims or {}
        for _, component in ipairs(FF.claimComponents(claims, true)) do
            local componentHit = false
            for _, i in ipairs(component) do
                for j = 1, #points do
                    if FF.rectsOverlap(claims[i], points[j]) then
                        componentHit = true
                        break
                    end
                end
                if componentHit then break end
            end
            if componentHit then
                for _, i in ipairs(component) do
                    hits[#hits + 1] = { name = name, index = i }
                end
            end
        end
    end
    return hits
end

-- Full validation for a proposed claim. Returns ok(boolean), reasonKey(string).
-- If a score loss left the faction above its cap, an existing claim is grandfathered:
-- members may keep it or shrink/rearrange it, but cannot increase its total area until
-- their score once again supports the larger size.
-- Pure except for reading the shared data table (for overlap checks).
function FF.validateClaim(faction, factionName, proposedRects, opts)
    opts = opts or FF.getOptions()
    if not proposedRects or #proposedRects == 0 then
        return false, "empty"
    end
    local proposedAreas = FF.claimComponentCount(proposedRects)
    local currentAreas = FF.claimComponentCount(faction and faction.claims)
    local maxAreas = FF.maxClaimAreas(FF.factionScore(faction, opts), opts)
    -- A death/member departure may put an old territory over the new dynamic cap.
    -- Grandfather it exactly like tile capacity: reductions and connected reshaping
    -- remain legal, but adding another disconnected area does not.
    if proposedAreas > maxAreas and proposedAreas > currentAreas then
        return false, "too_many_rects"
    end
    if FF.memberCount(faction) < opts.minFactionSizeToClaim then
        return false, "faction_too_small"
    end
    local proposedArea = FF.totalArea(proposedRects)
    local currentArea = FF.totalArea(faction and faction.claims)
    local maxArea = FF.maxClaimTiles(FF.factionScore(faction, opts), opts)
    if proposedArea > maxArea and proposedArea > currentArea then
        return false, "too_large"
    end
    local conflict = FF.findClaimConflict(proposedRects, factionName)
    if conflict then
        return false, "overlap"
    end
    -- Admin no-claim zones. Placed with the other overlap rules rather than up front
    -- because it is the rarest -- most servers define none, and the loop is over an
    -- empty table then.
    if FF.findNoClaimConflict(proposedRects) then
        return false, "no_claim_zone"
    end
    if FF.findClaimBufferConflict(proposedRects, factionName, opts) then
        return false, "too_close"
    end
    if not FF.claimsClustered(proposedRects, opts.maxClaimSeparation) then
        return false, "too_scattered"
    end
    -- Bounds the separation exemption above: public areas may sit anywhere, so
    -- without a cap they would be a way to claim scattered chokepoints for free.
    -- 0 turns public areas off entirely (the admin kill switch).
    if FF.countPublicAreas(proposedRects) > opts.maxPublicClaimAreas then
        return false, "too_many_public"
    end
    return true, nil
end

return FF
