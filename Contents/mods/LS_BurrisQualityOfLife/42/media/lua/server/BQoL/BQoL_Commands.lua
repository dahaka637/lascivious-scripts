--[[
    Burris Quality of Life -- server-side command handlers.

    Multiplayer clients cannot mutate the world, so world-changing outcomes are
    sent here as commands and re-resolved server-side. Clients send square
    coordinates rather than object references, because object handles do not
    survive the trip.

    This file is never loaded on a multiplayer client (server/ is server-only),
    which is exactly what we want.
]]

require "BQoL/BQoL_PryOutcome"
require "BQoL/BQoL_TourniquetLogic"

--[[
    Re-finds the prying target on the given square.

    Deliberately re-classifies rather than trusting the client: a client that
    asks to open a door which is not actually priable gets nothing.
]]
local function finiteNumber(value)
    value = tonumber(value)
    if not value or value ~= value or value == math.huge or value == -math.huge then return nil end
    return value
end

local function resolveTarget(args)
    if type(args) ~= "table" then return nil end
    local x, y, z = finiteNumber(args.x), finiteNumber(args.y), finiteNumber(args.z)
    if not x or not y or not z then return nil end
    x, y, z = math.floor(x), math.floor(y), math.floor(z)

    local square = getCell():getGridSquare(x, y, z)
    if not square then return nil end

    local objects = square:getObjects()
    for i = 0, objects:size() - 1 do
        local object = objects:get(i)
        local candidate = BQoL.Pry.classify(object)

        if candidate and candidate.kind == args.kind then
            return candidate
        end
    end

    return nil
end

local handlers = {}

local pryCooldown = {}
local PRY_COOLDOWN_MS = 1200

local function tooSoon(playerObj)
    if not playerObj then return true end
    local name = tostring(playerObj:getUsername() or playerObj:getOnlineID())
    local now = getTimestampMs and getTimestampMs() or math.floor(os.time() * 1000)
    if (pryCooldown[name] or 0) > now then return true end
    pryCooldown[name] = now + PRY_COOLDOWN_MS
    return false
end

local function targetIsNear(playerObj, object)
    local square = object and object:getSquare()
    if not playerObj or not square then return false end
    if math.floor(playerObj:getZ()) ~= square:getZ() then return false end
    return math.abs(playerObj:getX() - (square:getX() + 0.5)) <= 2
        and math.abs(playerObj:getY() - (square:getY() + 0.5)) <= 2
end

function handlers.pryAttempt(playerObj, args)
    if tooSoon(playerObj) then return end
    local target = resolveTarget(args)
    if not target then
        BQoL.log("pryAttempt: no valid target at %s,%s,%s",
            tostring(args and args.x), tostring(args and args.y), tostring(args and args.z))
        return
    end
    if not targetIsNear(playerObj, target.object) then return end
    if BQoL.Pry.isBlockedBySafehouse(target.object) then return end
    if not BQoL.Pry.findTool(playerObj) then return end
    if target.kind == "door" and BQoL.Pry.isReinforced(target.object)
        and not BQoL.Pry.canForceReinforced(playerObj) then return end

    if BQoL.Pry.roll(playerObj, 0) then
        BQoL.Pry.applySuccess(target.object, playerObj, target.kind)
    else
        pcall(function() playerObj:Say(getText("IGUI_BQoL_PryFailed")) end)
        local _, breakSound = BQoL.Pry.getSounds(target.garage)
        pcall(function() playerObj:playSound(breakSound) end)
        pcall(function()
            addSound(playerObj, playerObj:getX(), playerObj:getY(), playerObj:getZ(), 10, 6)
        end)
        BQoL.Pry.applyFailure(target.object, playerObj, target.kind)
    end
    BQoL.Pry.tire(playerObj, target.kind == "window" and 0.05 or 0.07)
end

--[[
    A doctor opening someone else's health panel asking which of their limbs
    are tied off.

    Tourniquet state is mod data on the patient, written here and pushed to
    clients as it changes -- so a doctor who was not connected, or not looking,
    when it was applied has never seen it. Without this they get a limb with no
    "- Tourniquet" line and no way to untie it.
]]
function handlers.tourniquetRequest(playerObj, args)
    if not args or not args.online then return end

    local patient = getPlayerByOnlineID(args.online)
    if not patient then return end

    BQoL.Tourniquet.push(patient, playerObj)
end

--[[
    A player reporting that they took a leg tourniquet off through the clothing
    UI, which is a supported way to untie a limb now that the item is visible.

    The claim is not taken at face value: the server re-derives the orphan list
    from its own copy of what the player is wearing -- already up to date,
    because ISUnequipAction calls sendEquip before it fires the event the
    client reacted to. A client that sends this while still wearing the thing
    gets its own state pushed back at it and nothing else.
]]
function handlers.tourniquetUnequipped(playerObj, args)
    if not args or not args.online then return end

    local patient = getPlayerByOnlineID(args.online)
    if not patient or patient ~= playerObj then return end

    local _, orphans = BQoL.Tourniquet.reconcile(patient)
    if not orphans then
        BQoL.Tourniquet.push(patient)
        return
    end

    -- The belt goes back to the player: they are the one who took it off.
    for _, bodyPart in ipairs(orphans) do
        BQoL.Tourniquet.untie(patient, bodyPart, patient)
    end
end

local function onClientCommand(module, command, playerObj, args)
    if module ~= BQoL.COMMAND_MODULE then return end

    local handler = handlers[command]
    if not handler then
        BQoL.warn("unknown client command %q", tostring(command))
        return
    end

    -- One bad command must not take down the server's event handler.
    local ok, err = pcall(handler, playerObj, args)
    if not ok then
        BQoL.warn("command %q failed: %s", tostring(command), tostring(err))
    end
end

--[[
    Registered unconditionally rather than through the feature registry: the
    handler must exist whenever any feature might send a command, and it costs
    nothing when idle.
]]
Events.OnClientCommand.Add(onClientCommand)

--- Lets later features add their own commands without touching this file.
BQoL.addCommandHandler = function(name, fn)
    if type(name) ~= "string" or type(fn) ~= "function" then
        BQoL.warn("addCommandHandler: bad arguments")
        return
    end
    handlers[name] = fn
end
