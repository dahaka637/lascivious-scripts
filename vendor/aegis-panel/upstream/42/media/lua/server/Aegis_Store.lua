-- File storage layer of the suite under Zomboid/Lua/Aegis/.
-- Kahlua cannot list directories, so each storage branch keeps
-- a manifest as the single source of truth for its files.
if isClient() then return end

AegisStore = AegisStore or {}

local ROOT = "Aegis"

-- path is valid only if it stays safely under the root
local function pathOk(relPath)
    if type(relPath) ~= "string" or relPath == "" then return false end
    if relPath:find("%.%.") then return false end
    if relPath:find("|") or relPath:find("\\") then return false end
    if relPath:sub(1, #ROOT + 1) ~= ROOT .. "/" then return false end
    if relPath:sub(-1) == "/" then return false end
    return true
end

AegisStore.pathOk = pathOk
AegisStore.ROOT = ROOT

-- write errors must never vanish silently again: once per path
-- the real cause goes to the console (the pcall wrapper used to
-- swallow every cause, in testing the disk stayed empty without a word)
local reported = {}
local function reportError(kind, relPath, reason)
    if reported[relPath] then return end
    reported[relPath] = true
    print("[Aegis] " .. kind .. " failed: " .. tostring(relPath) .. " -> " .. tostring(reason))
end

function AegisStore.write(relPath, content)
    if not pathOk(relPath) then reportError("Write", relPath, "path rejected") return false end
    local ok, err = pcall(function()
        local w = getFileWriter(relPath, true, false)
        if not w then error("getFileWriter lieferte nil") end
        w:write(content or "")
        w:close()
    end)
    if not ok then reportError("Write", relPath, err) end
    return ok
end

function AegisStore.append(relPath, line)
    if not pathOk(relPath) then reportError("Append", relPath, "path rejected") return false end
    local ok, err = pcall(function()
        local w = getFileWriter(relPath, true, true)
        if not w then error("getFileWriter lieferte nil") end
        w:writeln(line or "")
        w:close()
    end)
    if not ok then reportError("Append", relPath, err) end
    return ok
end

-- ensures file+folder exist WITHOUT touching existing content: getFileWriter
-- in append mode creates the full folder path via mkdirs when needed
-- and writes nothing (known safe, see AegisStore.append).
-- getFileReader in contrast calls File.createNewFile internally and throws
-- a java.io.IOException "No such file or directory" when the parent folder
-- was never created; this happens on EVERY first access to a fresh branch
-- (new server, freshly renamed folder) and the engine logs it as a raw
-- Java exception BEFORE our pcall kicks in, visible to admins as an error
-- even though the pcall has no consequences
local function ensureFile(relPath)
    pcall(function()
        local w = getFileWriter(relPath, true, true)
        if w then w:close() end
    end)
end

-- returns lines plus a truncation flag; reader is closed in every case,
-- on read failure nil comes back instead of a silent partial table
function AegisStore.readLines(relPath, maxLines)
    if not pathOk(relPath) then return nil end
    maxLines = maxLines or 500
    ensureFile(relPath)
    local reader = nil
    local lines = nil
    local truncated = false
    local ok = pcall(function()
        reader = getFileReader(relPath, true)
        if not reader then return end
        lines = {}
        local line = reader:readLine()
        while line ~= nil do
            if #lines >= maxLines then
                truncated = true
                break
            end
            table.insert(lines, line)
            line = reader:readLine()
        end
    end)
    if reader then pcall(function() reader:close() end) end
    if not ok then return nil end
    return lines, truncated
end

-- like readLines but WITHOUT ensureFile: for pure probe reads on
-- paths that are intentionally absent (migrateIf checks the old
-- deprecated path for legacy data; hitting a never-created folder
-- must not create an empty shell there, nil comes back as before,
-- exactly like prior to the ensureFile introduction)
function AegisStore.readLinesReadOnly(relPath, maxLines)
    if not pathOk(relPath) then return nil end
    maxLines = maxLines or 500
    local reader = nil
    local lines = nil
    local truncated = false
    local ok = pcall(function()
        -- false: never create the file - createIfNull=true ran createNewFile
        -- on a deliberately missing folder and threw an IOException stack
        -- trace into the log on every fresh-install server boot (looked
        -- like a mod crash to server admins)
        reader = getFileReader(relPath, false)
        if not reader then return end
        lines = {}
        local line = reader:readLine()
        while line ~= nil do
            if #lines >= maxLines then
                truncated = true
                break
            end
            table.insert(lines, line)
            line = reader:readLine()
        end
    end)
    if reader then pcall(function() reader:close() end) end
    if not ok then return nil end
    return lines, truncated
end

-- returns the LAST maxLines of a file (ring buffer); the cap bounds the
-- total work. For daily journals: readLines only shows the file start,
-- newly appended lines stayed invisible beyond the read cap
function AegisStore.readLastLines(relPath, maxLines, cap)
    if not pathOk(relPath) then return nil end
    maxLines = maxLines or 300
    cap = cap or 20000
    ensureFile(relPath)
    local reader = nil
    local ring = nil
    local total = 0
    local ok = pcall(function()
        reader = getFileReader(relPath, true)
        if not reader then return end
        ring = {}
        local line = reader:readLine()
        while line ~= nil and total < cap do
            total = total + 1
            ring[((total - 1) % maxLines) + 1] = line
            line = reader:readLine()
        end
    end)
    if reader then pcall(function() reader:close() end) end
    if not ok or not ring then return nil end
    local n = math.min(total, maxLines)
    local lines = {}
    for i = 1, n do
        local idx = ((total - n + i - 1) % maxLines) + 1
        table.insert(lines, ring[idx])
    end
    return lines, total > maxLines
end

-- Kahlua cannot truly delete files: deleteSave blocks any path with dot
-- sequences in B42 and only clears directories anyway, java.io.File is
-- not exposed. Final stage of rotation is therefore emptying the file,
-- leaving a 0-byte shell with no content.
function AegisStore.delete(relPath)
    if not pathOk(relPath) then return false end
    return AegisStore.write(relPath, "")
end

-- manifest line: status|epoch|path|admin|target
local function entryToLine(e)
    return table.concat({
        e.status or "aktiv",
        tostring(e.epoch or 0),
        e.path or "",
        (e.admin or ""):gsub("|", "_"),
        (e.target or ""):gsub("|", "_"),
    }, "|")
end

local function lineToEntry(line)
    -- deliberately WITHOUT $ anchor: the live server has legacy data with a
    -- sixth field (earlier dev build), the hard anchor silently dropped every
    -- such line and the protocol list stayed empty even though the files
    -- were there; extra fields are simply ignored
    local status, epoch, path, admin, target = line:match("^([^|]+)|([^|]+)|([^|]+)|([^|]*)|([^|]*)")
    if not status or not pathOk(path) then return nil end
    return { status = status, epoch = tonumber(epoch) or 0, path = path, admin = admin, target = target }
end

-- second return value: true if the manifest was not read completely
-- (cap reached or read failure); nobody may rewrite it in that case
function AegisStore.readManifest(manifestPath)
    local entries = {}
    local lines, truncated = AegisStore.readLines(manifestPath, 50000)
    if not lines then return entries, true end
    for _, line in ipairs(lines) do
        local e = lineToEntry(line)
        if e then table.insert(entries, e) end
    end
    return entries, truncated == true
end

function AegisStore.appendManifest(manifestPath, entry)
    if not pathOk(manifestPath) then return false end
    return AegisStore.append(manifestPath, entryToLine(entry))
end

function AegisStore.writeManifest(manifestPath, entries)
    if not pathOk(manifestPath) then return false end
    local lines = {}
    for _, e in ipairs(entries) do
        table.insert(lines, entryToLine(e))
    end
    local content = table.concat(lines, "\n")
    if #lines > 0 then content = content .. "\n" end
    return AegisStore.write(manifestPath, content)
end

-- zone backups: one folder per admin, one file per zone and day.
-- Same day overwrites and refreshes the manifest entry.
local ZONES_MANIFEST = ROOT .. "/Zones/manifest.txt"
AegisStore.ZONES_MANIFEST = ZONES_MANIFEST

-- self test of the file layer, runs once at world start: writes,
-- appends and reads back a probe file and reports the result
-- visibly in the console (search term "[Aegis]")
local function selfTest()
    local path = ROOT .. "/Status/selftest.txt"
    local wrote = AegisStore.write(path, "Start " .. tostring(AegisShared.realTime()) .. "\n")
    local appended = AegisStore.append(path, "append ok")
    local lines = AegisStore.readLines(path, 5)
    print("[Aegis] File layer: write=" .. tostring(wrote)
        .. " append=" .. tostring(appended)
        .. " read=" .. tostring(lines and #lines or "ERROR")
        .. " (context: isClient=" .. tostring(isClient()) .. " isServer=" .. tostring(isServer()) .. ")")
end

Events.OnGameStart.Add(selfTest)
Events.OnServerStarted.Add(selfTest)

-- one-time migration after the English folder rename:
-- copies the content of a known file from the old German path to the
-- new one if nothing is there yet. Kahlua cannot delete the old folder
-- (see AegisStore.delete), it stays behind as an empty leftover,
-- which is harmless.
function AegisStore.migrateIf(oldPath, newPath)
    if not pathOk(oldPath) or not pathOk(newPath) then return false end
    local newLines = AegisStore.readLines(newPath, 1)
    if newLines and #newLines > 0 then return false end
    local oldLines = AegisStore.readLinesReadOnly(oldPath, 50000)
    if not oldLines or #oldLines == 0 then return false end
    local content = table.concat(oldLines, "\n") .. "\n"
    return AegisStore.write(newPath, content)
end

-- covers only the files with real live state (role assignments, zone
-- groups, zone manifest, restart plan); protocol/construction/notes
-- legacy data stays unmigrated on purpose, same trade-off as the area
-- rename. Two-hop chains (Rollen -> Roles/rollen -> Roles/roles) land
-- in the newest file because the hops run in order
local function migrateLegacy()
    AegisStore.migrateIf(ROOT .. "/Rollen/rollen.txt", ROOT .. "/Roles/rollen.txt")
    AegisStore.migrateIf(ROOT .. "/Roles/rollen.txt", ROOT .. "/Roles/roles.txt")
    AegisStore.migrateIf(ROOT .. "/Zonen/manifest.txt", ZONES_MANIFEST)
    AegisStore.migrateIf(ROOT .. "/Zonen/gruppen.txt", ROOT .. "/Zones/gruppen.txt")
    AegisStore.migrateIf(ROOT .. "/Zones/gruppen.txt", ROOT .. "/Zones/groups.txt")
    AegisStore.migrateIf(ROOT .. "/Status/neustart.txt", ROOT .. "/Status/restart.txt")
    AegisStore.migrateIf(ROOT .. "/Status/sicherung.txt", ROOT .. "/Status/backup.txt")
    AegisStore.migrateIf(ROOT .. "/Status/sitzungen.txt", ROOT .. "/Status/sessions.txt")
end

Events.OnGameStart.Add(migrateLegacy)
Events.OnServerStarted.Add(migrateLegacy)

function AegisStore.zoneBackup(adminName, zoneName, content)
    local admin = AegisShared.sanitizeName(adminName)
    local zone = AegisShared.sanitizeName(zoneName)
    local now = AegisShared.realTime()
    local entries = AegisStore.readManifest(ZONES_MANIFEST)

    -- different zones can collapse onto the same sanitized name,
    -- then the new one gets a counter instead of overwriting the foreign file
    local base = ROOT .. "/Zones/" .. admin .. "/" .. zone .. "_" .. AegisShared.dateShort(now)
    local path = base .. ".txt"
    for run = 2, 9 do
        local foreign = false
        for _, e in ipairs(entries) do
            if e.path:lower() == path:lower() and e.target ~= zone then
                foreign = true
                break
            end
        end
        if not foreign then break end
        path = base .. "_" .. run .. ".txt"
    end

    if not AegisStore.write(path, content or "") then return false end
    for _, e in ipairs(entries) do
        if e.path == path then
            e.epoch = now
            e.status = "aktiv"
            return AegisStore.writeManifest(ZONES_MANIFEST, entries)
        end
    end
    return AegisStore.appendManifest(ZONES_MANIFEST, {
        status = "aktiv", epoch = now, path = path, admin = admin, target = zone,
    })
end
