require "PhunZones/core"

local Core = PhunZones
local allLocations = require("PhunZones/data")

local getActivatedMods = getActivatedMods

local LEGACY_FIELDS = {
    region = true,
    zone = true
}

local function finiteNumber(value)
    local n = tonumber(value)
    if not n or n ~= n or n == math.huge or n == -math.huge then return nil end
    return n
end
-- ---------------------------------------------------------------------------
-- MOD FILTER
-- Evaluates a zone's mod conditions against currently active mods.
-- Returns true if the zone should be included, false if it should be dropped.
--
-- Supported fields on a zone:
--   modsRequired = "mod1;mod2"   include if ANY of these mods are active
--   modsAllRequired = "mod1;mod2" include if ALL of these mods are active
--   modsExcluded = "mod1;mod2"   exclude if ANY of these mods are active
-- ---------------------------------------------------------------------------
-- Normalise a mod name: ensure it always starts with "\".
-- Handles data saved before the UI auto-prepend was added.
local function normMod(m)
    if type(m) ~= "string" then return "" end
    return (m:sub(1, 1) == "\\" and m:sub(2)) or m
end

local function passesModFilter(zone)
    if type(zone) ~= "table" then return false end
    local activeMods = getActivatedMods()
    if not activeMods then return true end

    -- modsRequired: include only if at least one listed mod is active
    if type(zone.modsRequired) == "string" and zone.modsRequired ~= "" then
        local mods = luautils.split(zone.modsRequired .. ";", ";")
        local found = false
        for _, m in ipairs(mods) do
            if m ~= "" and activeMods:contains(normMod(m)) then
                found = true
                break
            end
        end
        if not found then
            return false
        end
    end

    -- modsAllRequired: include only if every listed mod is active
    if type(zone.modsAllRequired) == "string" and zone.modsAllRequired ~= "" then
        local mods = luautils.split(zone.modsAllRequired .. ";", ";")
        for _, m in ipairs(mods) do
            if m ~= "" and not activeMods:contains(normMod(m)) then
                return false
            end
        end
    end

    -- modsExcluded: exclude if any listed mod is active
    if type(zone.modsExcluded) == "string" and zone.modsExcluded ~= "" then
        local mods = luautils.split(zone.modsExcluded .. ";", ";")
        for _, m in ipairs(mods) do
            if m ~= "" and activeMods:contains(normMod(m)) then
                return false
            end
        end
    end

    return true
end

-- ---------------------------------------------------------------------------
-- NORMALISE FORMAT
-- Converts old nested subzone format into the new flat format with explicit
-- `inherits` fields. New-format configs pass through unchanged.
-- Safe to remove once old configs are no longer in circulation.
--
-- addDefaultInherits (bool): when true, zones without an explicit `inherits`
-- get `inherits = "_default"` injected. Pass false for the custom/admin layer
-- so that absent `inherits` means "keep whatever the base layer says" rather
-- than "override with _default".
-- ---------------------------------------------------------------------------
function Core.normaliseFormat(zones, addDefaultInherits)
    local flat = {}
    for key, zone in pairs(type(zones) == "table" and zones or {}) do
        if type(zone) == "table" then
        if key == "_default" then
            flat["_default"] = Core.tools.shallowCopy(zone)
            flat["_default"].inherits = nil -- _default is the root; inheriting from anything would create a cycle
        else
            local entry = {}
            for k, v in pairs(zone) do
                if k ~= "subzones" and not LEGACY_FIELDS[k] then
                    entry[k] = v
                end
            end

            if addDefaultInherits and not entry.inherits and not entry.isolated then
                entry.inherits = "_default"
            end

            flat[key] = entry

            if zone.subzones then
                for subKey, sub in pairs(zone.subzones) do
                    local subEntry = Core.tools.shallowCopy(sub)
                    if addDefaultInherits and not subEntry.inherits then
                        subEntry.inherits = key
                    end
                    flat[key .. "_" .. subKey] = subEntry
                end
            end
        end
        end
    end
    return flat
end

-- ---------------------------------------------------------------------------
-- MERGE LAYERS
-- Merges base (shipped defaults) with custom (admin config).
-- Admin values always win. Tombstones (disabled = true) suppress base entries.
-- Admin can introduce entirely new zones not present in base.
-- ---------------------------------------------------------------------------
function Core.mergeLayers(base, custom)
    local result = {}

    for k, v in pairs(type(base) == "table" and base or {}) do
        if type(v) == "table" then result[k] = Core.tools.shallowCopy(v) end
    end

    for k, v in pairs(type(custom) == "table" and custom or {}) do
        if type(v) == "table" then
        if result[k] then
            for field, val in pairs(v) do
                if field == "points" and type(val) == "table" and #val == 0 then
                    -- preserve base points
                else
                    result[k][field] = val
                end
            end
        else
            result[k] = Core.tools.shallowCopy(v)
        end
        end
    end

    return result
end

-- ---------------------------------------------------------------------------
-- APPLY MOD FILTER
-- Drops zones that fail their mod conditions.
-- Runs after merging layers so admin overrides are respected before filtering.
-- ---------------------------------------------------------------------------
function Core.applyModFilter(zones)
    local filtered = {}
    for key, zone in pairs(type(zones) == "table" and zones or {}) do
        if key == "_default" then
            filtered[key] = zone
        elseif zone.disabled then
            print("PhunZones: dropping zone '" .. key .. "' (disabled)")
        elseif passesModFilter(zone) then
            filtered[key] = zone
        else
            print("PhunZones: dropping zone '" .. key .. "' (mod filter)")
        end
    end
    return filtered
end

-- ---------------------------------------------------------------------------
-- ASSIGN ORDERS
-- Ensures every zone has a deterministic numeric order value.
-- Children are always assigned a strictly higher order than their parent,
-- guaranteeing children take precedence over parents in spatial lookups.
-- Explicit `order` values on zones are honoured as a floor.
-- ---------------------------------------------------------------------------
function Core.assignOrders(zones)
    if type(zones) ~= "table" then return {} end
    local assigned = {}
    local counter = 0
    local keys = {}
    for key in pairs(zones) do table.insert(keys, key) end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)

    -- Detect cycles before assigning to avoid infinite recursion
    local function hasCycle(key, visited, stack)
        if stack[key] then
            return true
        end
        if visited[key] then
            return false
        end
        visited[key] = true
        stack[key] = true
        local zone = zones[key]
        if zone and zone.inherits then
            if hasCycle(zone.inherits, visited, stack) then
                return true
            end
        end
        stack[key] = nil
        return false
    end

    for _, key in ipairs(keys) do
        if hasCycle(key, {}, {}) then
            print("PhunZones: cycle detected involving zone '" .. tostring(key) .. "', breaking chain")
            if zones[key] then
                zones[key].inherits = nil
            end
        end
    end

    local function getOrder(key)
        if assigned[key] then
            return assigned[key]
        end
        local zone = zones[key]
        if not zone then
            return 0
        end

        local parentOrder = 0
        if zone.inherits and zones[zone.inherits] then
            parentOrder = getOrder(zone.inherits)
        end

        counter = counter + 1
        -- Honour explicit order as a floor, but always beat the parent
        local order = math.max(counter, parentOrder + 1)
        local explicit = finiteNumber(zone.order)
        if explicit then
            order = math.max(explicit, parentOrder + 1)
        end
        assigned[key] = order
        return order
    end

    -- _default gets the lowest possible order (everything overrides it)
    assigned["_default"] = 0
    if zones["_default"] then
        zones["_default"].order = 0
    end

    for _, key in ipairs(keys) do
        if key ~= "_default" then
            getOrder(key)
        end
    end

    -- Write assigned orders back to zones
    for key, order in pairs(assigned) do
        if zones[key] then
            zones[key].order = order
        end
    end

    return zones
end

-- ---------------------------------------------------------------------------
-- RESOLVE INHERITANCE
-- Builds a fully resolved property set for each zone by walking the
-- inheritance chain from most-general to most-specific.
-- `points` and structural fields are never inherited.
-- Results are stored in a separate lookup table; raw zones are unchanged.
-- ---------------------------------------------------------------------------
local NEVER_INHERIT = {
    points = true,
    inherits = true,
    isolated = true,
    order = true,
    modsRequired = true,
    modsAllRequired = true,
    modsExcluded = true,
    disabled = true
}

function Core.resolveInheritance(zones)
    local resolved = {}

    local function resolve(key, stack)
        if resolved[key] then
            return resolved[key]
        end

        -- Cycle guard (should not occur after assignOrders, but belt-and-braces)
        if stack[key] then
            print("PhunZones: cycle during resolution at '" .. key .. "'")
            return {}
        end
        stack[key] = true

        local zone = zones[key]
        if not zone then
            return {}
        end

        local result = {}

        -- Layer in parent properties first
        if zone.inherits then
            local parent = resolve(zone.inherits, stack)
            for k, v in pairs(parent) do
                result[k] = v
            end
        end

        -- Layer in this zone's own properties (skipping structural fields)
        for k, v in pairs(zone) do
            if not NEVER_INHERIT[k] then
                result[k] = v
            end
        end

        -- Structural fields on the resolved entry come from the zone itself
        result.points = zone.points
        result.order = zone.order
        result.key = key

        resolved[key] = result
        stack[key] = nil
        return result
    end

    for key, _ in pairs(zones) do
        resolve(key, {})
    end

    return resolved
end

-- ---------------------------------------------------------------------------
-- BUILD CHUNK MAP
-- Groups zone rects by map chunk (300 unit cells) for fast spatial lookup.
-- Uses raw zone points, not resolved properties.
-- Each cell entry contains enough info to test point containment and
-- identify the zone for property lookup.
-- ---------------------------------------------------------------------------
local CHUNK_SIZE = 300
local MAX_RECT_CHUNK_CELLS = 100000

function Core.buildChunkMap(zones)
    -- Flatten all zone rects into a sortable array
    local flattened = {}
    local keys = {}
    for key in pairs(type(zones) == "table" and zones or {}) do table.insert(keys, key) end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)

    for _, key in ipairs(keys) do
        local zone = zones[key]
        if key ~= "_default" and type(zone) == "table" and type(zone.points) == "table" then
            for rectIndex, rect in ipairs(zone.points) do
                if type(rect) == "table" then
                    local x1, y1 = finiteNumber(rect[1]), finiteNumber(rect[2])
                    local x2, y2 = finiteNumber(rect[3]), finiteNumber(rect[4])
                    if x1 and y1 and x2 and y2 then
                        if x1 > x2 then x1, x2 = x2, x1 end
                        if y1 > y2 then y1, y2 = y2, y1 end
                        table.insert(flattened, {key, finiteNumber(zone.order) or 0,
                            x1, y1, x2, y2, rectIndex})
                    else
                        print("PhunZones: ignoring malformed rectangle in zone '" .. tostring(key) .. "'")
                    end
                end
            end
        end
    end

    -- Sort descending: highest order tested first (wins on overlap)
    table.sort(flattened, function(a, b)
        if a[2] ~= b[2] then return a[2] > b[2] end
        if tostring(a[1]) ~= tostring(b[1]) then return tostring(a[1]) < tostring(b[1]) end
        return a[7] < b[7]
    end)

    -- Build chunk map
    local cells = {}
    for _, v in ipairs(flattened) do
        local x1, y1, x2, y2 = v[3], v[4], v[5], v[6]
        local cx1 = math.floor(x1 / CHUNK_SIZE)
        local cy1 = math.floor(y1 / CHUNK_SIZE)
        local cx2 = math.floor(x2 / CHUNK_SIZE)
        local cy2 = math.floor(y2 / CHUNK_SIZE)
        local chunkCells = (cx2 - cx1 + 1) * (cy2 - cy1 + 1)

        if chunkCells > MAX_RECT_CHUNK_CELLS then
            print("PhunZones: ignoring oversized rectangle in zone '" .. tostring(v[1]) .. "' (" ..
                tostring(chunkCells) .. " chunk cells)")
        else
            for cx = cx1, cx2 do
                for cy = cy1, cy2 do
                    local ckey = cx .. "_" .. cy
                    if not cells[ckey] then
                        cells[ckey] = {}
                    end
                    -- Store: zone key + rect bounds (for point-in-rect test)
                    table.insert(cells[ckey], {v[1], x1, y1, x2, y2})
                end
            end
        end
    end

    return cells
end

-- ---------------------------------------------------------------------------
-- LOAD ADMIN CONFIG
-- Loads the admin customisation file from disk (server/SP only).
-- Returns empty table if missing or malformed.
-- ---------------------------------------------------------------------------

-- Converts a v1 admin config into a v2-compatible flat data table.
-- v1 stored: deletions (region->zone->true) + nested subzones with many fields.
-- v2 stores:  flat zone keys, disabled=true tombstones, only points preserved.
local function migrateV1toV2(d)
    local result = {}

    -- Convert v1 deletions into disabled tombstones.
    -- v1 key "main" refers to the parent region zone itself.
    if type(d.deletions) == "table" then
        for region, zones in pairs(d.deletions) do
            if type(region) == "string" and type(zones) == "table" then
                for zoneName in pairs(zones) do
                    if type(zoneName) == "string" then
                        local key = (zoneName == "main") and region or (region .. "_" .. zoneName)
                        result[key] = { disabled = true }
                    end
                end
            end
        end
    end

    -- Flatten data: promote subzones to top level, strip all fields except points.
    if type(d.data) == "table" then
        for key, zone in pairs(d.data) do
            if type(key) == "string" and type(zone) == "table" then
                local entry = result[key] or {}
                if type(zone.points) == "table" then entry.points = zone.points end
                entry.inherits = "Medium"
                result[key] = entry

                if type(zone.subzones) == "table" then
                    for subKey, sub in pairs(zone.subzones) do
                        if type(subKey) == "string" and type(sub) == "table" then
                            local subEntry = result[key .. "_" .. subKey] or {}
                            if type(sub.points) == "table" then subEntry.points = sub.points end
                            subEntry.inherits = key
                            result[key .. "_" .. subKey] = subEntry
                        end
                    end
                end
            end
        end
    end

    return result
end

function Core.loadAdminConfig()
    if isClient() then
        -- Clients receive customisations via ModData, not from disk
        return ModData.get(Core.const.modifiedModData) or {}
    end

    local d = Core.tools.loadTable(Core.const.modifiedLuaFile)
    if d == nil then
        print("PhunZones: no customisation file found at ./lua/" .. Core.const.modifiedLuaFile ..
                  " (normal if no zones have been customised)")
        ModData.add(Core.const.modifiedModData, {})
        return {}
    end

    if type(d) ~= "table" or type(d.data) ~= "table" then
        print("PhunZones: unexpected format in ./lua/" .. Core.const.modifiedLuaFile .. ", skipping")
        ModData.add(Core.const.modifiedModData, {})
        return {}
    end

    local data = d.data

    if d.version == 1 then
        print("PhunZones: detected v1 format in admin config, backing up to PhunZones_Old.lua")
        if not Core.tools.saveTable("PhunZones_Old.lua", d) then
            print("PhunZones: warning: could not write v1 backup")
        end
        print("PhunZones: migrating v1 admin config to v2 format")
        data = migrateV1toV2(d)
        d.version = 2
        if not Core.tools.saveTable(Core.const.modifiedLuaFile, {
            version = 2,
            data = data
        }) then
            print("PhunZones: warning: could not persist migrated v2 config")
        end
    end

    -- Store in ModData so it survives and is accessible for transmission
    ModData.add(Core.const.modifiedModData, data)

    print("PhunZones: loaded customisations from ./lua/" .. Core.const.modifiedLuaFile)
    return data
end

-- ---------------------------------------------------------------------------
-- SAVE CHANGES
-- Accepts a table of zone changes keyed by zone key.
-- Merges into the custom layer, persists, and syncs to clients.
-- Single zone changes are just a batch of one:
--   Core.saveChanges({ MarchRidge = { zeds = false } })
-- ---------------------------------------------------------------------------
function Core.saveChanges(changes)
    if type(changes) ~= "table" then return false end
    local hasChanges = false
    for _ in pairs(changes) do
        hasChanges = true
        break
    end
    if not hasChanges then return false end

    -- Load existing custom layer
    local existing = ModData.get(Core.const.modifiedModData) or {}
    if type(existing) ~= "table" then existing = {} end
    local custom = Core.tools.deepCopy(existing)

    -- Merge all changes into the custom layer in one pass
    for key, zoneData in pairs(changes) do
        if type(key) == "string" and key ~= "" and type(zoneData) == "table" then
            if type(custom[key]) ~= "table" then custom[key] = {} end
            for field, val in pairs(zoneData) do
                custom[key][field] = val
            end
        end
    end

    if isClient() and not isCoopHost() then
        ModData.add(Core.const.modifiedModData, custom)
        -- Send the full batch up to server in one command
        sendClientCommand(getPlayer(), Core.name, Core.commands.modifyZone, {
            changes = changes
        })
    else
        -- Persist full custom layer to disk
        if not Core.tools.saveTable(Core.const.modifiedLuaFile, {
            version = 2,
            data = custom
        }) then
            print("PhunZones: failed to persist zone changes; update was not published")
            return false
        end
        ModData.add(Core.const.modifiedModData, custom)
        -- Broadcast the batch to all clients in one command
        sendServerCommand(Core.name, Core.commands.zoneUpdated, {
            changes = changes
        })
        -- Reprocess locally once for the entire batch
        Core.updateZoneData(true)
    end
    return true
end

-- Substitui a camada administrativa inteira (usado pelo editor de
-- exportacao/importacao). A persistencia acontece antes de publicar o novo
-- ModData, portanto uma falha de escrita nunca deixa a sessao mostrando um
-- estado que desaparecera no proximo restart.
function Core.replaceZones(replacement, requestId)
    if type(replacement) ~= "table" then return false end

    if isClient() and not isCoopHost() then
        local player = getPlayer()
        if not player or type(requestId) ~= "string" or requestId == "" or #requestId > 80 then return false end
        sendClientCommand(player, Core.name, Core.commands.replaceZones, {
            zones = replacement,
            requestId = requestId
        })
        return "pending"
    end

    local custom = Core.tools.deepCopy(replacement)
    if not Core.tools.saveTable(Core.const.modifiedLuaFile, {
        version = 2,
        data = custom
    }) then
        print("PhunZones: failed to persist imported zone data; replacement was not published")
        return false
    end

    ModData.add(Core.const.modifiedModData, custom)
    sendServerCommand(Core.name, Core.commands.zoneUpdated, {
        replace = true,
        data = custom
    })
    if ModData.transmit then ModData.transmit(Core.const.modifiedModData) end
    Core.updateZoneData(true)
    return true
end

-- ---------------------------------------------------------------------------
-- ADD DELETION
-- Marks a zone as disabled in the admin config, persists to disk,
-- and triggers a rebuild.
-- ---------------------------------------------------------------------------
function Core.addDeletion(key)
    if type(key) ~= "string" or key == "" then return false end
    local custom = {}

    if not isClient() then
        local d = Core.tools.loadTable(Core.const.modifiedLuaFile)
        if d and type(d.data) == "table" then
            custom = d.data
        end
    else
        custom = ModData.get(Core.const.modifiedModData) or {}
    end
    if type(custom) ~= "table" then custom = {} end

    Core.debugLn("marking zone '" .. tostring(key) .. "' as disabled")

    -- Tombstone: disabled = true suppresses the zone in mergeLayers
    custom[key] = custom[key] or {}
    custom[key].disabled = true

    if not isClient() then
        if not Core.tools.saveTable(Core.const.modifiedLuaFile, {
            version = 2,
            data = custom
        }) then
            print("PhunZones: failed to persist deletion for '" .. tostring(key) .. "'")
            return false
        end
    end

    ModData.add(Core.const.modifiedModData, custom)
    Core.updateZoneData()
    return true
end

-- ---------------------------------------------------------------------------
-- BUILD ZONE DATA
-- Runs the full processing pipeline and returns the result.
-- Does not store globally or trigger events.
-- filter: when false, skips mod filtering (useful for UI editor which
-- needs to see all zones including those excluded by current modset)
-- ---------------------------------------------------------------------------
function Core.buildZoneData(filter)

    local custom = Core.loadAdminConfig()
    local flatBase = Core.normaliseFormat(allLocations, true)
    -- Custom layer must NOT auto-inject inherits=_default: absent inherits means
    -- "keep whatever the base layer says", not "override parent to _default".
    local flatCustom = Core.normaliseFormat(custom, false)
    local merged = Core.mergeLayers(flatBase, flatCustom)

    if filter then
        merged = Core.applyModFilter(merged)
    end

    local ordered = Core.assignOrders(merged)
    local lookup = Core.resolveInheritance(ordered)
    local cells = Core.buildChunkMap(ordered)

    return {
        cells = cells,
        zones = ordered,
        lookup = lookup
    }
end

-- ---------------------------------------------------------------------------
-- UPDATE ZONE DATA
-- Runs the pipeline, stores results globally, and triggers OnZonesUpdated.
-- This is the authoritative rebuild — call this on startup and after saves.
-- ---------------------------------------------------------------------------
function Core.updateZoneData()
    local result = Core.buildZoneData(true) -- always filter mods for live data
    Core.data = result
    triggerEvent(Core.events.OnDataBuilt, result)
    return result
end
