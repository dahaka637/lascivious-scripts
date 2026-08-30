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
local function resolveTarget(args)
    if not args or not args.x or not args.y or not args.z then return nil end

    local square = getCell():getGridSquare(args.x, args.y, args.z)
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

function handlers.prySuccess(playerObj, args)
    local target = resolveTarget(args)
    if not target then
        BQoL.log("prySuccess: no valid target at %s,%s,%s",
            tostring(args and args.x), tostring(args and args.y), tostring(args and args.z))
        return
    end

    BQoL.Pry.applySuccess(target.object, playerObj, target.kind)
end

function handlers.pryFailure(playerObj, args)
    local target = resolveTarget(args)
    if not target then return end

    BQoL.Pry.applyFailure(target.object, playerObj, target.kind)
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
