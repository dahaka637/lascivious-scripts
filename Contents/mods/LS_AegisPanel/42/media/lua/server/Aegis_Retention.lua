-- Retention rotation: zone backups stay active for 14 days, then 30 days
-- archived, after 44 days the content is cleared (Kahlua cannot delete
-- files). Moderation logs are kept forever, session logs rotate along,
-- otherwise storage grows without bound on busy servers.
if isClient() then return end

require "Aegis_Store"

AegisRetention = AegisRetention or {}

-- nil means keep forever, otherwise { activeDays = x, archiveDays = y }
AegisRetention.ZONES = AegisShared.RETENTION
AegisRetention.LOG = {
    Bans = nil,
    Kicks = nil,
    Warnings = nil,
    ChatModeration = nil,
    Deaths = nil,
    Actions = AegisShared.RETENTION,
    AdminSessions = AegisShared.RETENTION,
    PlayerSessions = AegisShared.RETENTION,
}

local STATUS_FILE = AegisStore.ROOT .. "/Status/rotation.txt"
local INTERVAL = 20 * 3600

local lastRun = nil

local function loadLastRun()
    if lastRun ~= nil then return lastRun end
    lastRun = 0
    local lines = AegisStore.readLines(STATUS_FILE, 2)
    if lines and lines[1] then
        lastRun = tonumber(lines[1]) or 0
    end
    return lastRun
end

local function rememberRun(now)
    lastRun = now
    AegisStore.write(STATUS_FILE, tostring(now) .. "\n")
end

-- age one manifest: archive, clear, write back.
-- A partially read manifest is never rewritten, otherwise the unread
-- entries and their files would vanish from the world.
local function rotate(manifestPath, rules)
    if not rules then return end
    local entries, incomplete = AegisStore.readManifest(manifestPath)
    if incomplete or #entries == 0 then return end
    local kept = {}
    local changed = false
    for _, e in ipairs(entries) do
        local age = AegisShared.ageDays(e.epoch)
        if age > rules.activeDays + rules.archiveDays and AegisStore.delete(e.path) then
            changed = true
        else
            if age > rules.activeDays and e.status ~= "archiviert" then
                e.status = "archiviert"
                changed = true
            end
            table.insert(kept, e)
        end
    end
    if changed then
        AegisStore.writeManifest(manifestPath, kept)
    end
end

function AegisRetention.run()
    rotate(AegisStore.ZONES_MANIFEST, AegisRetention.ZONES)
    for _, area in ipairs(AegisShared.LOG_AREAS) do
        rotate(AegisStore.ROOT .. "/Log/" .. area .. "/manifest.txt", AegisRetention.LOG[area])
    end
end

-- guard on real clock, EveryTenMinutes counts game time and only serves as a tick
local function check()
    local now = AegisShared.realTime()
    if now <= 0 then return end
    if now - loadLastRun() < INTERVAL then return end
    rememberRun(now)
    AegisRetention.run()
end

Events.EveryTenMinutes.Add(check)
