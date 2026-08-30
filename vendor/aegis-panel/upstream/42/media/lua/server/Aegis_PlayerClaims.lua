-- Self claims for the player panel: the role grants a tile budget and
-- the player draws ONE rectangle that becomes a real safehouse. The
-- rectangle can never sit free in the world, it must attach to the
-- player's own house (claimed or admin given), touching or overlapping
-- it. Every rule runs server side, the client only delivers numbers.
if isClient() then return end

require "Aegis_Store"
require "Aegis_Roles"
require "Aegis_Log"
require "Aegis_Moderation"
require "Aegis_Zones"

local MODULE = "AegisPlayer"

local MIN_EDGE = 3
local MAX_EDGE = 80
local MAX_COORD = 1000000
-- breathing room to the next foreign zone, in tiles
local GAP = 2

local function toClient(player, command, args)
    if isServer() then
        sendServerCommand(player, MODULE, command, args)
    else
        triggerEvent("OnServerCommand", MODULE, command, args)
    end
end

local function cap(v, max)
    local s = tostring(v):gsub("%c", " ")
    if #s > max then s = s:sub(1, max) end
    return s
end

-- per command throttle keyed by username, claims touch files and the
-- full safehouse list
local THROTTLE = { claimInfo = 2, claimSet = 5, claimRelease = 5 }
local lastCall = {}

local function throttled(name, command)
    local now = AegisShared.realTime()
    local key = name .. ":" .. command
    if lastCall[key] and now - lastCall[key] < (THROTTLE[command] or 2) then return true end
    lastCall[key] = now
    return false
end

-- budget only from server data: role assignment plus pp column,
-- never from args (AegisRoles.playerPanelFor reads exactly that)
local function budgetFor(name)
    local pp = nil
    if AegisRoles.playerPanelFor then pp = AegisRoles.playerPanelFor(name) end
    if not pp then return 0 end
    return math.max(0, math.floor(tonumber(pp.claimTiles) or 0))
end

-- occupied tiles: only the self claim zone counts against the budget,
-- the house it hangs on keeps its area for free
local function usedTiles(name)
    local pt = AegisZones.playerClaimFor(name)
    if not pt then return 0, false end
    local used = 0
    local sh = AegisZones.safehouseAt(pt.x, pt.y)
    if sh and sh.owner == name then used = sh.w * sh.h end
    local g = AegisZones.groupFor(pt.x, pt.y)
    if g then
        for _, p in ipairs(g.parts) do used = used + p.w * p.h end
    end
    return used, true
end

-- the houses a player owns; the anchor of an existing self claim is a
-- claim, not a house
local function ownHomes(name)
    local claim = AegisZones.playerClaimFor(name)
    local homes = {}
    for _, r in ipairs(AegisZones.ownedBy(name)) do
        if not (claim and r.x == claim.x and r.y == claim.y) then
            table.insert(homes, r)
        end
    end
    return homes
end

-- edge adjacent counts as touching, a one tile gap does not
local function touchesRect(x, y, w, h, r)
    return x < r.x + r.w + 1 and x + w > r.x - 1
        and y < r.y + r.h + 1 and y + h > r.y - 1
end

-- spawn protection like the vanilla claim: a rectangle over a server
-- spawn point is refused. The list comes from the same Lua loader
-- vanilla uses server side (SpawnRegionMgr, shared/SpawnRegions.lua);
-- when it cannot be read the rule is suspended with a console note
local spawnPoints = nil
local spawnLoaded = false

local function loadSpawnPoints()
    if spawnLoaded then return end
    spawnLoaded = true
    pcall(function()
        if not (SpawnRegionMgr and SpawnRegionMgr.getSpawnRegions) then return end
        local regions = SpawnRegionMgr.getSpawnRegions()
        if type(regions) ~= "table" then return end
        local pts = {}
        for _, region in ipairs(regions) do
            if type(region) == "table" and type(region.points) == "table" then
                for _, list in pairs(region.points) do
                    if type(list) == "table" then
                        for _, p in ipairs(list) do
                            if type(p) == "table" and tonumber(p.posX) and tonumber(p.posY) then
                                local px, py = tonumber(p.posX), tonumber(p.posY)
                                -- legacy point format: cell index plus offset
                                if tonumber(p.worldX) then px = tonumber(p.worldX) * 300 + px end
                                if tonumber(p.worldY) then py = tonumber(p.worldY) * 300 + py end
                                table.insert(pts, { x = math.floor(px), y = math.floor(py) })
                            end
                        end
                    end
                end
            end
        end
        spawnPoints = pts
    end)
    if not spawnPoints then
        print("[Aegis] Player claims: spawn list not readable, spawn rule suspended")
    end
end

local function touchesSpawn(x, y, w, h)
    loadSpawnPoints()
    if not spawnPoints then return false end
    for _, p in ipairs(spawnPoints) do
        if p.x >= x and p.x < x + w and p.y >= y and p.y < y + h then return true end
    end
    return false
end

local function sendInfo(player, name)
    local pt = AegisZones.playerClaimFor(name)
    if pt then
        -- claim gone behind our back (admin removal or decay), the
        -- stale registry line must not block a fresh claim forever
        local sh = AegisZones.safehouseAt(pt.x, pt.y)
        if not sh or sh.owner ~= name then
            print("[Aegis] zone claim of " .. name .. " at " .. pt.x .. "," .. pt.y
                .. " no longer backed by a safehouse, registry line cleared")
            AegisZones.setPlayerClaim(name, nil)
        end
    end
    local used, has = usedTiles(name)
    local payload = { tiles = budgetFor(name), used = used, has = has }
    -- own house position so the client editor can point the player there
    local home = ownHomes(name)[1]
    if home then
        payload.home = { x = home.x, y = home.y, w = home.w, h = home.h }
    end
    toClient(player, "claimInfoSync", payload)
end

local Commands = {}

Commands.claimInfo = function(player, name, args)
    sendInfo(player, name)
end

-- every comparison below is written as a rejection test, and every
-- comparison with NaN is false: a client sending 0/0 would sail through
-- range, budget and overlap untouched. Only finite
-- numbers pass this gate
local function finiteInt(v)
    v = tonumber(v)
    if not v or v ~= v or v == math.huge or v == -math.huge then return nil end
    return math.floor(v)
end

Commands.claimSet = function(player, name, args)
    -- server switch (sandbox): with player claims off nobody claims,
    -- whatever the role budget says
    if not AegisShared.featureOn("PlayerClaims") then
        toClient(player, "claimSet", { ok = false, reason = "off" })
        return
    end
    -- budget stays first, it doubles as the panel unlock gate
    local budget = budgetFor(name)
    if budget <= 0 then
        toClient(player, "claimSet", { ok = false, reason = "budget" })
        return
    end
    -- a claim exists only as an extension of the own house, without a
    -- house nothing else is worth checking
    local homes = ownHomes(name)
    if #homes == 0 then
        toClient(player, "claimSet", { ok = false, reason = "noHouse" })
        return
    end
    local x = finiteInt(args.x)
    local y = finiteInt(args.y)
    local w = finiteInt(args.w)
    local h = finiteInt(args.h)
    if not x or not y or not w or not h then
        toClient(player, "claimSet", { ok = false, reason = "data" })
        return
    end
    -- normalize a drag that went up or left
    if w < 0 then x, w = x + w, -w end
    if h < 0 then y, h = y + h, -h end
    if x < 0 or y < 0 or x + w > MAX_COORD or y + h > MAX_COORD
        or w < MIN_EDGE or h < MIN_EDGE or w > MAX_EDGE or h > MAX_EDGE then
        toClient(player, "claimSet", { ok = false, reason = "data" })
        return
    end
    if w * h > budget then
        toClient(player, "claimSet", { ok = false, reason = "budget" })
        return
    end
    -- a claim the registry cannot record would dodge the budget after
    -- the next restart, better no claim at all
    if not AegisZones.registryWritable() then
        toClient(player, "claimSet", { ok = false, reason = "failed" })
        return
    end
    if AegisZones.playerClaimFor(name) then
        toClient(player, "claimSet", { ok = false, reason = "has" })
        return
    end
    -- vanilla rule SafehouseDaySurvivedToClaim, suspended when the
    -- option cannot be read
    local needDays = nil
    pcall(function() needDays = getServerOptions():getInteger("SafehouseDaySurvivedToClaim") end)
    needDays = tonumber(needDays)
    if needDays and needDays > 0 then
        local hours = player:getHoursSurvived()
        if tonumber(hours) and tonumber(hours) < needDays * 24 then
            toClient(player, "claimSet", { ok = false, reason = "days", need = needDays })
            return
        end
    end
    if touchesSpawn(x, y, w, h) then
        toClient(player, "claimSet", { ok = false, reason = "spawn" })
        return
    end
    -- a rectangle anchored exactly on an existing safehouse would share
    -- its onlineId (Cantor of x,y) and a later release would find the
    -- house first, so that anchor is off limits even on own ground
    if AegisZones.safehouseAt(x, y) then
        toClient(player, "claimSet", { ok = false, reason = "overlap" })
        return
    end
    -- the rectangle must touch or overlap the own house (or an annex of
    -- its zone); the matching house is the exemption for the overlap
    -- checks below, everything foreign still blocks
    local attach = nil
    for _, home in ipairs(homes) do
        if touchesRect(x, y, w, h, home) then
            attach = home
        else
            local g = AegisZones.groupFor(home.x, home.y)
            if g then
                for _, p in ipairs(g.parts) do
                    if touchesRect(x, y, w, h, p) then attach = home break end
                end
            end
        end
        if attach then break end
    end
    if not attach then
        toClient(player, "claimSet", { ok = false, reason = "detached" })
        return
    end
    -- real overlap is refused even on the own zone: the exemption is
    -- there so the claim may TOUCH the house, not so it may lie on top of
    -- it. Two rectangles over the same ground protect it twice and read
    -- as a broken zone in every list. Touching passes,
    -- the engine test is half open
    if AegisZones.overlapsAny(x, y, w, h) then
        toClient(player, "claimSet", { ok = false, reason = "overlap" })
        return
    end
    local ex, ey = math.max(0, x - GAP), math.max(0, y - GAP)
    if AegisZones.overlapsAny(ex, ey, x + w + GAP - ex, y + h + GAP - ey, attach.x, attach.y) then
        toClient(player, "claimSet", { ok = false, reason = "near" })
        return
    end
    -- owner and title are the username, never taken from args
    if not AegisZones.buildSafehouseFor({ x = x, y = y, w = w, h = h }, name, name) then
        print("[Aegis] zone claimSet by " .. name .. " failed: engine refused the build")
        toClient(player, "claimSet", { ok = false, reason = "failed" })
        return
    end
    print("[Aegis] zone claimSet by " .. name .. ": " .. x .. "," .. y .. " " .. w .. "x" .. h)
    AegisZones.setPlayerClaim(name, x, y)
    AegisLog.write("Actions", cap(name, 48), cap(name, 48),
        string.format("Player claim created: %d,%d %dx%d (%d tiles)", x, y, w, h, w * h))
    toClient(player, "claimSet", { ok = true })
    sendInfo(player, name)
end

Commands.claimRelease = function(player, name, args)
    local pt = AegisZones.playerClaimFor(name)
    if not pt then
        toClient(player, "claimRelease", { ok = false, reason = "none" })
        return
    end
    -- a release the registry cannot record would leave an orphan P line
    -- that blocks every future claimSet forever
    if not AegisZones.registryWritable() then
        toClient(player, "claimRelease", { ok = false, reason = "failed" })
        return
    end
    local sh = AegisZones.safehouseAt(pt.x, pt.y)
    if sh and sh.owner == name then
        -- one step for main, annexes and registry entry; leaving the
        -- rest to the guard made it report a removal from outside
        AegisZones.releaseZoneAt(pt.x, pt.y)
    end
    print("[Aegis] zone claimRelease by " .. name .. ": " .. pt.x .. "," .. pt.y)
    AegisZones.setPlayerClaim(name, nil)
    AegisLog.write("Actions", cap(name, 48), cap(name, 48),
        string.format("Player claim released: %d,%d", pt.x, pt.y))
    toClient(player, "claimRelease", { ok = true })
    sendInfo(player, name)
end

local function onClientCommand(module, command, player, args)
    if module ~= MODULE then return end
    -- suspended players lose the panel backend too
    if AegisModeration.isSuspended(player) then return end
    local handler = Commands[command]
    if not handler then return end
    local name = player:getUsername()
    if type(name) ~= "string" or name == "" or #name > 48 or name:find("[%c|]") then return end
    if throttled(name, command) then return end
    handler(player, name, args or {})
end

Events.OnClientCommand.Add(onClientCommand)
