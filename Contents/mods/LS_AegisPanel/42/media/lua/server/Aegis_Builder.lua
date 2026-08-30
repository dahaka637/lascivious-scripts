-- Build brush, server side: turns the tile list from the client palette
-- into real built objects for everyone. Floors reuse the plain map object
-- path from the zone restore (IsoObject plus transmitAddObjectToSquare),
-- walls and fences the player-built path (IsoThumpable plus
-- AddSpecialObject plus transmitCompleteItemToClients). Every piece gets
-- the same stamp and journal line as regular builds, so it shows up in
-- the construction radar and the log viewer. No undo: the pieces are
-- normal built objects, removable with sledgehammer or the clearing tool.
if isClient() then return end

require "Aegis_Store"
require "Aegis_Roles"
require "Aegis_Log"
require "Aegis_Moderation"

local MAX_TILES = 400

local function toClient(player, command, args)
    if isServer() then
        sendServerCommand(player, AegisShared.MODULE, command, args)
    else
        triggerEvent("OnServerCommand", AegisShared.MODULE, command, args)
    end
end

-- the tools area right is the whole gate: whoever
-- gets the area may do everything in it. The former second bar demanded
-- access level exactly "admin", which silently locked out every other
-- staff level even with the area assigned
local function permitted(player)
    if not AegisRoles.canArea(player, "tools") then
        if isServer() then
            sendServerCommand(player, "AegisAdmin", "denied", { area = "tools" })
        end
        return false
    end
    return true
end

-- stamp and journal exactly like server/Aegis_Construction.lua, so the
-- pieces appear in radar and log viewer with the regular "bau" action
local function stamp(obj, name)
    obj:getModData().aegisBuild = tostring(name):gsub("|", "_") .. "|" .. tostring(AegisShared.realTime())
end

local function journal(name, x, y, z, sprite)
    local now = AegisShared.realTime()
    local path = AegisStore.ROOT .. "/Construction/" .. AegisShared.dateShort(now) .. ".txt"
    AegisStore.append(path, table.concat({
        AegisShared.timeShort(now),
        tostring(name):gsub("|", "_"),
        "bau",
        tostring(x) .. "," .. tostring(y) .. "," .. tostring(z),
        tostring(sprite or "?"):gsub("|", "_"),
    }, "|"))
end

-- floor path from the zone restore: replace whatever floor is there,
-- transmitAddObjectToSquare inserts locally and broadcasts itself
local function buildFloor(cell, sq, sprite)
    local floor = sq:getFloor()
    if floor then
        pcall(function() sq:transmitRemoveItemFromSquare(floor, false) end)
    end
    local obj = IsoObject.new(cell, sq, sprite)
    sq:transmitAddObjectToSquare(obj, 0)
    return obj
end

-- objects go through the vanilla moveable placer, the same call the debug
-- brush uses (ISBrushToolTileCursor). Building a plain IsoObject instead
-- looked fine but was a trap: furniture sprites carry a sprite grid, and
-- the engine refuses to remove a grid piece whose partners are missing
-- (transmitRemoveItemFromSquare returns -1 and does nothing). Such a piece
-- survived clearing, picking up and the sledgehammer alike. The placer
-- derives type, health, thump sound, containers and the grid from the
-- sprite properties, so the result behaves like real furniture.
local function buildObject(cell, sq, sprite)
    local obj = nil
    local ok = pcall(function()
        local probe = IsoObject.new(sq, sprite)
        local props = ISMoveableSpriteProps.new(probe:getSprite())
        props.rawWeight = 10
        props:placeMoveableInternal(sq, instanceItem("Base.Plank"), sprite)
    end)
    if ok then
        -- the placer inserts under world items, so the piece is not
        -- necessarily last; find it back by sprite for stamping
        local objects = sq:getObjects()
        for i = objects:size() - 1, 0, -1 do
            local o = objects:get(i)
            local n = o:getSprite() and o:getSprite():getName()
            if n == sprite then
                obj = o
                break
            end
        end
    end
    if obj then return obj end
    -- placer refused this sprite (no moveable properties): fall back to the
    -- plain path so map tiles and decals still work as before
    local plain = IsoObject.new(cell, sq, sprite)
    sq:transmitAddObjectToSquare(plain, sq:getObjects():size())
    return plain
end

-- wall and fence path from the zone restore: stamp before the transmit so
-- the modData travels inside the complete-item packet
local function buildWall(cell, sq, sprite, north, name)
    local obj = IsoThumpable.new(cell, sq, sprite, north, {})
    obj:setMaxHealth(400)
    obj:setHealth(400)
    stamp(obj, name)
    sq:AddSpecialObject(obj)
    if isServer() then pcall(function() obj:transmitCompleteItemToClients() end) end
    triggerEvent("OnObjectAdded", obj)
    return obj
end

local Commands = {}

Commands.builderApply = function(player, args)
    if not permitted(player) then return end
    if not args or type(args.tiles) ~= "table" then return end
    local mode = args.mode
    if mode ~= "wall" and mode ~= "object" then mode = "floor" end
    if #args.tiles > MAX_TILES then
        toClient(player, "builderDone", { ok = false })
        return
    end
    if mode ~= "wall" and type(args.sprite) ~= "string" then return end
    if mode == "wall" and (type(args.spriteW) ~= "string" or type(args.spriteN) ~= "string") then return end

    local cell = getCell()
    local name = player:getUsername()
    local built, skipped = 0, 0
    for _, t in ipairs(args.tiles) do
        local x = math.floor(tonumber(t.x) or 0)
        local y = math.floor(tonumber(t.y) or 0)
        local z = math.floor(tonumber(t.z) or 0)
        local sq = getSquare(x, y, z)
        if not sq then
            skipped = skipped + 1
        else
            local sprite = mode ~= "wall" and args.sprite
                or (t.n == true and args.spriteN or args.spriteW)
            local ok, obj = pcall(function()
                if mode == "floor" then
                    return buildFloor(cell, sq, sprite)
                elseif mode == "object" then
                    return buildObject(cell, sq, sprite)
                end
                return buildWall(cell, sq, sprite, t.n == true, name)
            end)
            if ok and obj then
                if mode ~= "wall" then
                    stamp(obj, name)
                    pcall(function() obj:transmitModData() end)
                end
                journal(name, x, y, z, sprite)
                sq:RecalcProperties()
                built = built + 1
            else
                skipped = skipped + 1
            end
        end
    end
    AegisLog.write("Actions", name, mode,
        string.format("Build brush: %d built, %d skipped", built, skipped))
    toClient(player, "builderDone", { ok = true, built = built, skipped = skipped })
end

Events.OnClientCommand.Add(function(module, command, player, args)
    if module ~= AegisShared.MODULE then return end
    -- suspended admins may not use any Aegis area
    if AegisModeration.isSuspended(player) then return end
    if Commands[command] then Commands[command](player, args) end
end)
