-- Lascivious Factions System - claim/zone abstraction.
-- The single place that talks to PhunZones. Callers ask "who owns this tile?"
-- and subscribe to claim enter/leave; they never touch PhunZones directly, so
-- if the spatial backend ever changes only this file moves.
--
-- Faction claims are a *projection* of our authoritative registry onto
-- PhunZones zones keyed "LFSFACTION_<name>". The registry is the source of truth;
-- these zones are regenerated from it. The server calls PhunZones.saveChanges /
-- addDeletion directly (server context), so members claim through our own
-- validation without needing the CanSetupNonPVPZone admin capability that the
-- PhunZones modifyZone command requires.

require "LFS_Shared"

local FF = LasciviousFactionsSystem
FF.Claims = FF.Claims or {}
local Claims = FF.Claims

local function pz()
    return _G.PhunZones -- global set by PhunZones/core.lua; may be nil pre-init
end

-- ---------------------------------------------------------------------------
-- Queries
-- ---------------------------------------------------------------------------

-- Faction name whose claim contains (x,y), or nil. Prefers PhunZones' resolved
-- lookup; falls back to a direct registry scan if PhunZones isn't ready yet.
--
-- Cross-checked against FF's own registry before being trusted: PhunZones'
-- zone layer is a projection that can outlive the faction it was made for.
-- Concretely, in singleplayer, deleting a save and starting a new one does
-- NOT reset PhunZones' own custom-zone file the way it resets our ModData
-- registry (that file isn't scoped per-save, it's vendored third-party
-- persistence we don't touch) -- so a "LFSFACTION_<name>" zone from an
-- unrelated, long-gone save can still be sitting there when a brand new
-- save boots. The boot-time orphan purge (Claims.purgeOrphanZones) exists
-- for exactly this, but deliberately refuses to run when the registry looks
-- empty (it can't tell "genuinely no factions yet" from "hasn't loaded this
-- tick", and guessing wrong there would delete real claims) -- which a
-- fresh save always is, so the purge never actually fires in time. Checking
-- existence right here, at the one place every caller in the mod resolves
-- claim ownership through, makes a stale zone permanently harmless (treated
-- as unclaimed) regardless of whether the purge ever runs.
function Claims.factionAt(x, y)
    local data = FF.getData()
    local P = pz()
    if P and P.getLocation then
        local zone = P.getLocation(x, y)
        if zone and zone.key then
            local name = FF.factionNameFromZoneKey(zone.key)
            if name and data.factions[name] then return name end
        end
    end
    -- Fallback: scan the registry directly (rare; only before PhunZones init).
    -- Already registry-driven, so it can never surface an orphaned name.
    for name, faction in pairs(data.factions) do
        if FF.pointInClaim(faction, x, y) then
            return name
        end
    end
    return nil
end

-- Faction name, embedded member set, AND the per-area grant for the claim
-- containing (x,y). Returns:
--   owningFactionName(string|nil), memberSet(table|nil),
--   areaAccess(string|nil), areaGrants(table|nil), allyMembers(table|nil)
-- The member set is read straight off the PhunZones zone, so it is available on any
-- client the zone reached -- unlike the LasciviousFactionsSystem registry. memberSet is nil
-- when the tile is unclaimed OR when the zone predates member embedding (older
-- projection).
--
-- The trailing three describe the individual rect the tile falls in, and are all nil
-- unless that rect has actually been opened -- so they are nil for every zone written
-- before 1.2.9 and for every all-private claim, which keeps the old behaviour. Finding
-- the rect means walking the zone's points, bounded by the score-driven area count;
-- this sits on the permission-hook hot path, so the loop is skipped entirely unless
-- the zone has an opened area, and the results are returned as plain values rather
-- than a table to keep the common path allocation-free.
--
-- Same registry cross-check as Claims.factionAt above, and for the same
-- reason: without it, FF.playerCanActAt would read a real member roster off
-- an orphaned zone and enforce permissions for a faction that no longer
-- exists, instead of treating the tile as unclaimed.
function Claims.factionMembersAt(x, y)
    local P = pz()
    if P and P.getLocation then
        local zone = P.getLocation(x, y)
        if zone and zone.key then
            local name = FF.factionNameFromZoneKey(zone.key)
            if name and FF.getData().factions[name] then
                local access = zone.ffAreaAccess
                if access and zone.points then
                    for i = 1, #zone.points do
                        if access[i] and access[i] ~= "private"
                            and FF.pointInRect(x, y, zone.points[i]) then
                            return name, zone.ffMembers, access[i],
                                zone.ffAreaGrants and zone.ffAreaGrants[i] or nil,
                                zone.ffAllies
                        end
                    end
                end
                return name, zone.ffMembers
            end
        end
    end
    return nil
end

-- ---------------------------------------------------------------------------
-- Enter / leave subscriptions
-- ---------------------------------------------------------------------------
-- PhunZones fires OnPhysicalZoneChanged(obj, stored) where stored.at.zone is the
-- new zone key. We track the previous faction per player so we can emit clean
-- enter/leave pairs even when crossing directly between two claims.

local enterCbs, leaveCbs = {}, {}
local lastFactionByPlayer = {}

function Claims.onEnterClaim(cb)
    if type(cb) == "function" then table.insert(enterCbs, cb); return true end
    return false
end
function Claims.onLeaveClaim(cb)
    if type(cb) == "function" then table.insert(leaveCbs, cb); return true end
    return false
end

local function playerKey(player)
    return player and player.getUsername and player:getUsername() or tostring(player)
end

local function onPhysicalZoneChanged(obj, stored)
    if not (obj and instanceof and instanceof(obj, "IsoPlayer")) then return end
    local newKey = stored and stored.at and stored.at.zone
    local newFaction = newKey and FF.factionNameFromZoneKey(newKey) or nil
    if newFaction and not FF.getFaction(newFaction) then newFaction = nil end

    local pk = playerKey(obj)
    local prevFaction = lastFactionByPlayer[pk]
    if prevFaction == newFaction then return end
    lastFactionByPlayer[pk] = newFaction

    if prevFaction then
        for i = 1, #leaveCbs do
            local ok, err = pcall(leaveCbs[i], obj, prevFaction)
            if not ok then FF.warn("claim leave callback failed: " .. tostring(err)) end
        end
    end
    if newFaction then
        for i = 1, #enterCbs do
            local ok, err = pcall(enterCbs[i], obj, newFaction)
            if not ok then FF.warn("claim enter callback failed: " .. tostring(err)) end
        end
    end
end

-- Register with PhunZones' event once it (and its event) exist. The event name
-- string is stable even before the module fully inits, so this is safe at load.
local function registerZoneEvent()
    local P = pz()
    local evName = P and P.events and P.events.OnPhysicalZoneChanged
    if evName and Events[evName] then
        if Claims._physicalZoneEvent and Claims._physicalZoneHook then
            Claims._physicalZoneEvent.Remove(Claims._physicalZoneHook)
        end
        Claims._physicalZoneEvent = Events[evName]
        Claims._physicalZoneHook = onPhysicalZoneChanged
        Events[evName].Add(onPhysicalZoneChanged)
        return true
    end
    return false
end

if not registerZoneEvent() then
    -- PhunZones not loaded yet; retry once the game boots.
    local function registerZoneEventAtGameStart()
        if not registerZoneEvent() then
            FF.warn("PhunZones OnPhysicalZoneChanged event not found; "
                .. "claim enter/leave feedback disabled. Is phunzones2 installed and loaded first?")
        end
    end
    if Claims._zoneGameStartHook then Events.OnGameStart.Remove(Claims._zoneGameStartHook) end
    Claims._zoneGameStartHook = registerZoneEventAtGameStart
    Events.OnGameStart.Add(registerZoneEventAtGameStart)
elseif Claims._zoneGameStartHook then
    Events.OnGameStart.Remove(Claims._zoneGameStartHook)
    Claims._zoneGameStartHook = nil
end
if Events.OnDisconnect then
    local function clearZonePlayerState()
        for key in pairs(lastFactionByPlayer) do lastFactionByPlayer[key] = nil end
    end
    if Claims._zoneDisconnectHook then Events.OnDisconnect.Remove(Claims._zoneDisconnectHook) end
    Claims._zoneDisconnectHook = clearZonePlayerState
    Events.OnDisconnect.Add(clearZonePlayerState)
end

-- ---------------------------------------------------------------------------
-- Projection into PhunZones (server-side)
-- ---------------------------------------------------------------------------
-- Builds the PhunZones zone property table for a faction claim. nosafehouse
-- enforces the "claims replace safehouses" rule: nobody can vanilla-claim inside
-- a faction claim. (The loot-protection safehouse we create server-side in
-- LFS_Server is added programmatically and is unaffected by this
-- player-facing block.)
--
-- We deliberately do NOT set PhunZones' nobuilding/noplacing/nopickup/noscrap/
-- nodestruction flags: those are blanket (all-or-nothing) and would block our own
-- faction members too. Per-action, membership-aware gating lives in
-- LFS_Permissions.lua instead.
local function zoneProps(name, faction, rects, opts)
    -- saveChanges MERGES fields into the persisted custom layer and never removes
    -- them, so we must explicitly reset every field we might have set in the past
    -- rather than just omitting it. Two consequences we clear here:
    --   * disabled=false un-tombstones a zone re-claimed under a previously-deleted
    --     name (removeFaction() -> addDeletion sets disabled=true); without this the
    --     claim "succeeds" but PhunZones' mod filter silently drops the zone.
    --   * the old blanket nobuilding/noplacing/nopickup/noscrap/nodestruction flags
    --     (set by earlier versions) must be forced false, else they linger in the
    --     persisted zone and block our OWN members. Membership gating now lives in
    --     LFS_Permissions.lua instead.
    -- Embed the member roster ON the zone. PhunZones' zone layer reliably reaches
    -- remote coop clients (we transmit it in transmitZones), whereas our
    -- LasciviousFactionsSystem GlobalModData registry does not -- so the client-side
    -- permission hooks read membership from here (zone.ffMembers) rather than the
    -- registry, which may be empty on a joined client.
    -- Each entry carries the two claim-affecting permissions of the member's role
    -- (owner -> both true), so per-role build/move gating works on joined clients
    -- without the registry. FF.playerCanActAt also accepts the legacy `true` form
    -- for zones written before per-role embedding.
    FF.ensureRoles(faction)
    local ffMembers = {}
    if faction.members then
        for user in pairs(faction.members) do
            ffMembers[user] = {
                build = FF.roleCan(faction, user, "build"),
                move  = FF.roleCan(faction, user, "move"),
            }
        end
    end
    -- Owner-togglable: let ALLIED factions' members build/craft (allowAllyBuild) and/or
    -- place/scrap/destroy (allowAllyMove) in this claim, by embedding them into the same
    -- ffMembers roster the permission hooks already read -- no change needed to
    -- FF.playerCanActAt or Permissions.lua. Flat grant (not per-role) since it is a
    -- single claim-owner decision, not something the ally's own roles control. Guarded
    -- so an ally member who happens to share a username with an existing entry never
    -- overrides it (shouldn't normally overlap).
    if (faction.allowAllyBuild or faction.allowAllyMove) and faction.relations then
        for other, rel in pairs(faction.relations) do
            if rel == "ally" then
                local af = FF.getFaction(other)
                if af and af.members then
                    for user in pairs(af.members) do
                        if ffMembers[user] == nil then
                            ffMembers[user] = {
                                build = faction.allowAllyBuild == true,
                                move  = faction.allowAllyMove == true,
                            }
                        end
                    end
                end
            end
        end
    end
    -- Embed the set of ally factions allowed to see this claim on their map, so the
    -- persistent map overlay reads visibility from the reliably-synced zone layer
    -- instead of the FF registry. Always a table (empty when not sharing) because
    -- saveChanges only MERGES fields -- an omitted field would keep a stale value.
    -- Ally is mutual, so this faction's "ally" relations ARE the shared-with set.
    local ffShareWith = {}
    if faction.shareMapWithAllies ~= false and faction.relations then
        for other, rel in pairs(faction.relations) do
            if rel == "ally" then ffShareWith[other] = true end
        end
    end
    -- Pact partners with a share-map clause also see this claim (a pact is mutual). The
    -- server reprojects both zones when such a pact forms, breaks, or expires, so this
    -- set stays current without checking expiry here.
    local pacts = FF.getData().pacts
    if pacts and name then
        for _, p in pairs(pacts) do
            if p.terms and p.terms.shareMap then
                local other = (p.a == name and p.b) or (p.b == name and p.a) or nil
                if other then ffShareWith[other] = true end
            end
        end
    end
    -- Per-area access, index-aligned with `points`. Two parallel arrays rather than
    -- keys on the point entries themselves: `points` is handed to PhunZones, whose
    -- tolerance for extra keys on a point is not something this mod can verify, so
    -- the geometry it receives stays exactly four numbers (see the sanitised copy
    -- below). Both arrays are always present -- saveChanges only MERGES, so omitting
    -- them would leave a stale grant live on a zone whose areas were closed again.
    --
    -- ffAllies is the flat set of allied factions' members, consulted by
    -- FF.playerCanActAt for an "allies"-level area. It is separate from the
    -- ffMembers ally injection above, which is the faction-wide allowAllyBuild /
    -- allowAllyMove grant: that one makes an ally a pseudo-member everywhere in the
    -- claim, this one opens a single area. Only built when an area needs it.
    local ffAreaAccess, ffAreaGrants, ffAllies = {}, {}, {}
    local anyAllyArea = false
    for i = 1, #(rects or {}) do
        local access = FF.areaAccess(rects[i])
        ffAreaAccess[i] = access
        ffAreaGrants[i] = FF.areaGrants(rects[i])
        if access == "allies" then anyAllyArea = true end
    end
    if anyAllyArea and faction.relations then
        for other, rel in pairs(faction.relations) do
            if rel == "ally" then
                local af = FF.getFaction(other)
                for user in pairs(af and af.members or {}) do ffAllies[user] = true end
            end
        end
    end

    -- Sanitised geometry: a fresh 4-number copy per rect. Two reasons this cannot be
    -- `points = rects`. The access/grants keys must not reach PhunZones (above), and
    -- passing the live registry array by reference means anything PhunZones does to
    -- zone.points mutates faction.claims in place.
    local points = {}
    for i = 1, #(rects or {}) do
        local r = rects[i]
        points[i] = { r[1], r[2], r[3], r[4] }
    end

    -- The mod supplies its own movable territory text overlay. Always suppress
    -- PhunZones' title/subtitle welcome box so the two presentations never overlap.
    return {
        points = points,
        isolated = true,        -- don't inherit _default combat/title props
        nosafehouse = true,
        -- Empty strings explicitly clear values left in PhunZones' merge-based store
        -- by older versions; omitting/nil would preserve the stale welcome text.
        title = "",
        subtitle = "",
        noannounce = true,
        ffMembers = ffMembers,
        ffShareWith = ffShareWith,
        ffAreaAccess = ffAreaAccess,
        ffAreaGrants = ffAreaGrants,
        ffAllies = ffAllies,
        disabled = false,
        nobuilding = false,
        noplacing = false,
        nopickup = false,
        noscrap = false,
        nodestruction = false,
    }
end

-- Debug-gated snapshot of the persisted zone layer, logged either side of every
-- mutation we make.
--
-- This exists because of a production incident: disbanding one faction tombstoned an
-- UNRELATED live faction's zone as collateral damage, and the only reason that faction
-- did not silently lose its base is that healFromBuild noticed and put it back. The
-- suspected cause is on PhunZones' side -- Core.buildZoneData -> loadAdminConfig
-- re-reads the whole custom-zone file from DISK on every rebuild and overwrites
-- ModData with it, so any lag between a write and the next read resurrects stale
-- tombstones wholesale -- but a log cannot prove flush timing. These before/after
-- pairs are what will: they say whether a zone was already missing when we read the
-- layer, or went missing across our own write.
--
-- Counts plus the tombstoned key names only, never geometry: this runs on every claim
-- edit, and the whole point of the change alongside it is to stop flooding the log.
function Claims.zoneTrace(tag)
    if not FF.debugEnabled() then return end
    local P = pz()
    if not (P and P.const) then return end
    local custom = ModData.get(P.const.modifiedModData)
    if custom == nil then
        FF.log("zones[" .. tostring(tag) .. "]: PhunZones layer not loaded")
        return
    end
    local total, disabled = 0, {}
    for key, zone in pairs(custom) do
        if FF.factionNameFromZoneKey(key) then
            total = total + 1
            if type(zone) == "table" and zone.disabled == true then
                disabled[#disabled + 1] = key
            end
        end
    end
    table.sort(disabled)
    FF.log(string.format("zones[%s]: %d LFSFACTION_ zone(s), %d tombstoned%s",
        tostring(tag), total, #disabled,
        #disabled > 0 and (" -- " .. table.concat(disabled, ", ")) or ""))
end

-- Push PhunZones' custom-zone layer to all clients.
-- CRITICAL (spike 3): PhunZones.saveChanges / addDeletion update the host's zone
-- data but never call ModData.transmit, and their zoneUpdated server-command is
-- undefined (nil) -- so on their own our claim changes never reach clients. We
-- transmit the PhunZones ModData table ourselves, which fires PhunZones' own
-- OnReceiveGlobalModData handler on every client -> updateZoneData -> claim
-- becomes visible/queryable client-side.
local function transmitZones(P)
    if isClient() and not isCoopHost() then return end
    local tableName = P and P.const and P.const.modifiedModData
    if tableName and ModData.transmit then
        ModData.transmit(tableName)
    end
end

-- Regenerate the PhunZones zone for a single faction from the registry.
-- Server/host only (saveChanges persists + rebuilds there; we transmit to clients).
function Claims.projectFaction(name, faction)
    local P = pz()
    if not (P and P.saveChanges) then
        FF.print("ERROR: PhunZones.saveChanges unavailable; cannot project claim for " .. tostring(name))
        return
    end
    local opts = FF.getOptions()
    if not (faction.claims and #faction.claims > 0) then
        Claims.removeFaction(name)
        return
    end
    Claims.zoneTrace("project " .. tostring(name) .. " pre")
    P.saveChanges({ [FF.zoneKey(name)] = zoneProps(name, faction, faction.claims, opts) })
    transmitZones(P)
    Claims.zoneTrace("project " .. tostring(name) .. " post")
end

-- Batch projection: ONE PhunZones saveChanges (= one whole-file disk write + one
-- full zone-pipeline rebuild + one client sync) for any number of factions, instead
-- of one per zone. This is the fix for the "server too busy" watchdog stalls: a
-- relationship change touches 2 zones and a war settlement 2+N, and calling
-- projectFaction per zone runs that heavy synchronous saveChanges once EACH.
-- PhunZones' saveChanges already merges a multi-key table in a single pass (it is
-- what Claims.healFromBuild below relies on), so batching is behaviourally identical
-- to N separate calls -- only the disk/rebuild/broadcast count drops to one.
--
-- `list` is an array of { name = <string>, faction = <table> }. Each claimed
-- faction is (re)projected. A faction with NO claim is skipped, not deleted --
-- matching the single-zone reproject helper this replaces: these callers refresh
-- an existing claim's embedded metadata (relations, share sets, rosters), and a
-- faction that never had a claim simply has no zone to refresh. Zone deletion is
-- the separate removeFaction path (unclaim/disband). Server/host only.
function Claims.projectFactions(list)
    local P = pz()
    if not (P and P.saveChanges) then
        FF.print("ERROR: PhunZones.saveChanges unavailable; cannot batch-project claims")
        return
    end
    local opts = FF.getOptions()
    -- Dedupe by zone key (last entry wins) so a faction named twice in one operation
    -- is written once, not twice.
    local changes, seen, any = {}, {}, false
    for _, item in ipairs(list) do
        local name, faction = item.name, item.faction
        if name and faction and not seen[name]
            and faction.claims and #faction.claims > 0 then
            seen[name] = true
            changes[FF.zoneKey(name)] = zoneProps(name, faction, faction.claims, opts)
            any = true
        end
    end
    if not any then return end   -- nothing claimed to project; no disk write/rebuild
    Claims.zoneTrace("projectBatch pre")
    P.saveChanges(changes)       -- one merge = one whole-file write + one rebuild
    transmitZones(P)             -- one client sync for the whole batch
    Claims.zoneTrace("projectBatch post")
end

-- Faction names whose zone is being torn down RIGHT NOW. Consulted by
-- Claims.healFromBuild, which must not undo a deletion that is still in progress.
--
-- This is not paranoia, it is the fix for a shipped bug. PhunZones' addDeletion ends
-- with updateZoneData(), which fires OnDataBuilt SYNCHRONOUSLY, inside our call --
-- and healFromBuild is hooked to that event. So a caller that deletes the zone while
-- the faction still holds its claims (which every disband path did) had the zone
-- resurrected by our own heal one instruction later, then deleted the registry
-- record, leaving an orphan zone nothing could ever remove: land that still painted
-- borders, still denied build/move through its stale ffMembers, and still blocked the
-- claim editor's overlap check forever. Ordering at the call site fixes it too and is
-- done as well, but the guard is what makes it impossible to reintroduce.
local removingZones = {}

-- Remove a faction's PhunZones zone (disband / unclaim). Server/host only.
function Claims.removeFaction(name)
    local P = pz()
    if not (P and P.addDeletion) then
        -- Previously a silent no-op, which is how an undeletable claim could happen
        -- with nothing in the log. Match the error projectFaction already prints.
        FF.print("ERROR: PhunZones.addDeletion unavailable; cannot remove claim zone for "
            .. tostring(name))
        return
    end
    removingZones[name] = true
    Claims.zoneTrace("remove " .. tostring(name) .. " pre")
    local ok, err = pcall(function()
        P.addDeletion(FF.zoneKey(name))
        transmitZones(P)
    end)
    removingZones[name] = nil
    Claims.zoneTrace("remove " .. tostring(name) .. " post")
    if not ok then
        FF.print("ERROR: removing claim zone for " .. tostring(name) .. ": " .. tostring(err))
    end
end

-- Rebuild every LFSFACTION_* zone from the registry. Call once on server start so
-- PhunZones reflects persisted claims after a restart.
-- Returns true if it actually ran, false if it deferred because PhunZones' custom
-- layer was not loaded yet -- purgeOrphanZones is gated on that answer, since a purge
-- against an unloaded layer would read an empty zone set and conclude nothing.
function Claims.reconcileAll()
    local P = pz()
    -- If PhunZones hasn't loaded its custom layer yet (SP/coop OnGameStart precedes
    -- Core:ini's first-tick run), do NOT project now: saveChanges would merge into an
    -- empty layer and persist it, wiping other admin-customised zones. The OnDataBuilt
    -- heal hook re-projects right after the first real build instead.
    if not (P and P.const) or ModData.get(P.const.modifiedModData) == nil then
        print("[LFS] reconcileAll: PhunZones layer not loaded yet; deferring to OnDataBuilt heal")
        return false
    end
    -- One batched saveChanges for every claimed faction, not one per faction: on a
    -- server with many claims the per-faction loop was N whole-file writes + N full
    -- rebuilds at startup, a long synchronous hang before the server was ready.
    local data = FF.getData()
    local list = {}
    for name, faction in pairs(data.factions) do
        if faction.claims and #faction.claims > 0 then
            list[#list + 1] = { name = name, faction = faction }
        end
    end
    if #list > 0 then Claims.projectFactions(list) end
    return true
end

-- Delete every LFSFACTION_* zone with no live claim behind it: the faction is gone from
-- the registry, or still exists but holds no claims. These are ORPHANS -- land that
-- paints borders, denies build/move through a stale ffMembers roster, and fails the
-- claim editor's overlap check, with no faction anywhere that could release it.
--
-- Deliberately NOT folded into healFromBuild. That runs on every PhunZones rebuild,
-- including ones fired part-way through our own mutations, and a delete-capable pass
-- on that path is how a transient inconsistency becomes permanent data loss. This is
-- called at exactly two well-defined moments instead: server start (after
-- reconcileAll has projected the live claims) and an explicit admin command.
--
-- `force` skips the empty-registry safety check -- see the caller in
-- LFS_Server. Server/host only. Returns the number of zones purged.
function Claims.purgeOrphanZones(force)
    if isClient() and not isCoopHost() then return 0 end
    local P = pz()
    if not (P and P.saveChanges and P.const) then return 0 end
    -- Same guard as healFromBuild: never touch the layer before PhunZones has loaded
    -- it, or we persist an incomplete one and drop other admins' custom zones.
    local custom = ModData.get(P.const.modifiedModData)
    if custom == nil then return 0 end

    local data = FF.getData()
    local factions = data and data.factions
    if not factions then return 0 end

    -- Read the PERSISTED custom layer rather than the built zone set: a zone already
    -- tombstoned there is gone as far as gameplay is concerned and re-deleting it
    -- would be a pointless disk write, while the built set omits it entirely.
    local changes, purged = {}, {}
    for key, zone in pairs(custom) do
        local fname = FF.factionNameFromZoneKey(key)
        if fname and type(zone) == "table" and zone.disabled ~= true then
            local f = factions[fname]
            if not (f and f.claims and #f.claims > 0) then
                changes[key] = { disabled = true }
                purged[#purged + 1] = fname
            end
        end
    end
    if #purged == 0 then return 0 end

    -- The one state where "the registry has not loaded" and "there genuinely are no
    -- factions" are indistinguishable -- and guessing wrong here deletes every claim
    -- on the server. Report and do nothing; the admin command passes force.
    if not force and FF.isEmpty(factions) then
        print("[LFS] " .. #purged .. " orphan claim zone(s) found but the faction registry is "
            .. "empty; not purging automatically. Run /ff admin purgeclaims to confirm.")
        return 0
    end

    -- One batched saveChanges -- one whole-file write plus one pipeline rebuild for
    -- the entire sweep. addDeletion in a loop would be N synchronous rebuilds, which
    -- is exactly the pattern that produced PhunZones' "server is too busy" stalls.
    -- Tombstoning via saveChanges is the same disabled=true addDeletion writes.
    for i = 1, #purged do removingZones[purged[i]] = true end
    Claims.zoneTrace("purge pre")
    local ok, err = pcall(function()
        P.saveChanges(changes)
        transmitZones(P)
    end)
    for i = 1, #purged do removingZones[purged[i]] = nil end
    Claims.zoneTrace("purge post")
    if not ok then
        FF.print("ERROR: purging orphan claim zones: " .. tostring(err))
        return 0
    end
    print("[LFS] purged orphan claim zone(s): " .. table.concat(purged, ", "))
    return #purged
end

-- ---------------------------------------------------------------------------
-- Self-healing projection
-- ---------------------------------------------------------------------------
-- PhunZones rebuilds its live zone data (Core.data) from its persisted custom
-- layer on several triggers (playerSetup/zoneUpdated commands, received
-- GlobalModData, addDeletion). If that layer went stale -- e.g. a disabled=true
-- tombstone left on disk, or PhunZones' addDeletion never persisting on a coop
-- host -- the rebuild silently drops our LFSFACTION_ zones while the registry still
-- holds the claims: map overlay and enter banner die, Make Claim tab lives on.
-- Rather than chase each trigger, re-assert the projection after EVERY rebuild.

local healing = false -- reentrancy guard: our own heal triggers a nested OnDataBuilt

-- Registered (server/coop-host only, from LFS_Server) on PhunZones'
-- OnDataBuilt event, which fires synchronously with the freshly built
-- { cells, zones, lookup } after every rebuild. Re-projects any registry faction
-- whose claims lost their LFSFACTION_ zone; zoneProps sets disabled=false, so a
-- stale tombstone is cleared in the same pass.
-- NOTE: does not remove orphan LFSFACTION_ zones whose faction no longer exists;
-- removeFaction handles the normal path and orphan GC is out of scope here.
function Claims.healFromBuild(result)
    if healing then return end
    if isClient() and not isCoopHost() then return end -- authority only, checked at runtime
    local P = pz()
    if not (P and P.saveChanges and P.const) then return end
    -- Never heal before PhunZones' custom layer has actually loaded: early builds
    -- on a coop host see nil ModData, and healing then would persist an incomplete
    -- layer, dropping other admin-customised zones.
    if ModData.get(P.const.modifiedModData) == nil then return end
    local zones = result and result.zones
    if type(zones) ~= "table" then return end

    local data = FF.getData()
    local opts = FF.getOptions()
    local changes, missing = {}, {}
    for name, faction in pairs(data.factions or {}) do
        -- Skip a zone that is mid-deletion: this handler runs synchronously INSIDE
        -- Claims.removeFaction (addDeletion -> updateZoneData -> OnDataBuilt), where
        -- "the zone is missing" is the intended outcome, not damage to repair.
        if removingZones[name] then
            -- deliberately nothing
        elseif faction.claims and #faction.claims > 0 then
            local z = zones[FF.zoneKey(name)]
            if not (z and z.points and #z.points > 0) then
                changes[FF.zoneKey(name)] = zoneProps(name, faction, faction.claims, opts)
                missing[#missing + 1] = name
            end
        end
    end
    if #missing == 0 then return end

    -- saveChanges -> updateZoneData fires a nested OnDataBuilt inside this handler.
    -- Normally the nested pass finds the zone present and stops, but a zone that can
    -- never survive the pipeline would recurse forever without the flag; with it, a
    -- persistent failure costs one retry per external rebuild. One batched
    -- saveChanges call = a single persist + rebuild instead of one per faction.
    healing = true
    local ok, err = pcall(function()
        P.saveChanges(changes)
        transmitZones(P)
    end)
    healing = false
    if ok then
        print("[LFS] re-projected missing claim zone(s): " .. table.concat(missing, ", "))
    else
        FF.print("ERROR: healing claim zones: " .. tostring(err))
    end
end

return Claims
