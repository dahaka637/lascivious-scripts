-- Factions page, server side: delivers factions and safehouses in one
-- response. The faction list also lives server side (persisted in
-- IsoMetaGrid, synced on connect), so it can be read directly here;
-- getPlayers() of a faction does NOT include the owner. Zone annexes
-- are detected via the zone page's group registry (read only), plus
-- the title suffix " +" that zone tier 2 assigns, as a fallback.
if isClient() then return end

require "Aegis_Store"
require "Aegis_Roles"
require "Aegis_Moderation"

local function toClient(player, command, args)
    if isServer() then
        sendServerCommand(player, AegisShared.MODULE, command, args)
    else
        triggerEvent("OnServerCommand", AegisShared.MODULE, command, args)
    end
end

local function deny(player)
    toClient(player, "denied", { area = "factions" })
end

-- anchors of all zone annexes from Aegis/Zones/groups.txt
-- (line format: G|mainX,mainY|x,y,w,h;x,y,w,h;...)
local function annexAnchors()
    local set = {}
    local lines = AegisStore.readLines(AegisStore.ROOT .. "/Zones/groups.txt", 5000)
    for _, line in ipairs(lines or {}) do
        local remaining = line:match("^G|%d+,%d+|(.*)$")
        if remaining then
            for rx, ry in remaining:gmatch("(%d+),(%d+),%d+,%d+") do
                set[rx .. "," .. ry] = true
            end
        end
    end
    return set
end

-- who is currently here; solo only has the local player
local function onlineNames()
    local names = {}
    if isServer() then
        pcall(function()
            local list = getOnlinePlayers()
            for i = 0, list:size() - 1 do
                local p = list:get(i)
                if p then table.insert(names, p:getUsername()) end
            end
        end)
    else
        local p = getPlayer()
        if p then table.insert(names, p:getUsername()) end
    end
    return names
end

local function readFactions()
    local factions = {}
    local seen = {}
    pcall(function()
        local list = Faction.getFactions()
        for i = 0, list:size() - 1 do
            local f = list:get(i)
            local entry = {
                name = f:getName() or "",
                tag = f:getTag() or "",
                owner = f:getOwner() or "",
                color = { r = 1, g = 1, b = 1 },
                members = {},
            }
            pcall(function()
                local c = f:getTagColor()
                if c then
                    entry.color = { r = c:getR(), g = c:getG(), b = c:getB() }
                end
            end)
            pcall(function()
                local m = f:getPlayers()
                for j = 0, m:size() - 1 do
                    table.insert(entry.members, m:get(j))
                end
            end)
            seen[entry.name] = true
            table.insert(factions, entry)
        end
    end)
    -- Faction Framework keeps its factions in its own transmitted ModData,
    -- the vanilla Faction list never sees them, so the page looked empty on
    -- servers running it. Read only, and only when the mod is
    -- really loaded: FF.getData would otherwise create its table for nothing
    pcall(function()
        if not (FF and FF.getData) then return end
        local data = FF.getData()
        if type(data) ~= "table" or type(data.factions) ~= "table" then return end
        for name, f in pairs(data.factions) do
            if type(name) == "string" and name ~= "" and type(f) == "table" and not seen[name] then
                local owner = type(f.owner) == "string" and f.owner or ""
                local entry = {
                    name = name,
                    tag = type(f.tag) == "string" and f.tag or "",
                    owner = owner,
                    color = { r = 1, g = 1, b = 1 },
                    members = {},
                    ff = true,
                }
                if type(f.members) == "table" then
                    for user in pairs(f.members) do
                        if type(user) == "string" and user ~= owner then
                            table.insert(entry.members, user)
                        end
                    end
                    table.sort(entry.members)
                end
                seen[name] = true
                table.insert(factions, entry)
            end
        end
    end)
    return factions
end

local function readSafehouses(annexes)
    local safehouses = {}
    pcall(function()
        local list = SafeHouse.getSafehouseList()
        for i = 0, list:size() - 1 do
            local sh = list:get(i)
            local title = sh:getTitle() or ""
            local entry = {
                title = title,
                owner = sh:getOwner() or "",
                x = sh:getX(), y = sh:getY(), w = sh:getW(), h = sh:getH(),
                players = {},
                annex = annexes[sh:getX() .. "," .. sh:getY()] == true or title:sub(-2) == " +",
            }
            pcall(function()
                local pl = sh:getPlayers()
                for j = 0, pl:size() - 1 do
                    table.insert(entry.players, pl:get(j))
                end
            end)
            table.insert(safehouses, entry)
        end
    end)
    return safehouses
end

-- safehouse count per faction: main rectangles involving at least one
-- faction member (owner included)
local function countSafehouses(factions, safehouses)
    for _, f in ipairs(factions) do
        local set = {}
        if f.owner ~= "" then set[f.owner] = true end
        for _, n in ipairs(f.members) do set[n] = true end
        local count = 0
        for _, sh in ipairs(safehouses) do
            if not sh.annex then
                local involved = set[sh.owner] == true
                if not involved then
                    for _, n in ipairs(sh.players) do
                        if set[n] then
                            involved = true
                            break
                        end
                    end
                end
                if involved then count = count + 1 end
            end
        end
        f.shCount = count
    end
end

-- costly list assembly capped at one request per second and player,
-- same as in the sibling files
local lastRequest = {}
local function throttled(player)
    local name = player and player:getUsername() or "?"
    local now = AegisShared.realTime()
    if lastRequest[name] and now - lastRequest[name] < 1 then return true end
    lastRequest[name] = now
    return false
end

local Commands = {}

Commands.factionList = function(player, args)
    if not AegisRoles.canArea(player, "factions") then deny(player) return end
    if throttled(player) then return end
    local factions = readFactions()
    local safehouses = readSafehouses(annexAnchors())
    countSafehouses(factions, safehouses)
    toClient(player, "factionList", {
        factions = factions,
        safehouses = safehouses,
        online = onlineNames(),
    })
end

local function onClientCommand(module, command, player, args)
    if module ~= AegisShared.MODULE then return end
    -- suspended admins may not use any Aegis area
    if AegisModeration.isSuspended(player) then return end
    if Commands[command] then Commands[command](player, args) end
end

Events.OnClientCommand.Add(onClientCommand)
