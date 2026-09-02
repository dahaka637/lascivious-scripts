local pending = {}      
local applied = {}         
local PENDING_TIMEOUT_MS = 3000

local function onServerCommand(module, command, args)
    if module ~= "SprintDiveWindows" then return end
    if not args or not args.id then return end

    local id = args.id

    local localPlayer = getPlayer()
    if localPlayer and localPlayer:getOnlineID() == id then return end

    if command == "diveOutcome" then
        if not args.outcome then return end
        pending[id] = {
            outcome = args.outcome,
            dive = (args.dive == true),
            ms = getTimestampMs(),
        }
        return
    end

    if command == "diveLanding" then
        if not args.x or not args.y then return end

        local player = getPlayerByOnlineID(id)
        if not player then return end

        local x, y, z = args.x, args.y, args.z or 0

        player:setSitOnFurnitureObject(nil)

        player:setX(x)
        player:setY(y)
        player:setZ(z)

        player:setNextX(x)
        player:setNextY(y)

        player:setLastX(x)
        player:setLastY(y)
        player:setLastZ(z)
        return
    end
end

local function applyPending()
    if table.isempty(pending) then return end

    local now = getTimestampMs()

    for id, entry in pairs(pending) do
        if (now - entry.ms) > PENDING_TIMEOUT_MS then
            pending[id] = nil
        else
            local player = getPlayerByOnlineID(id)
            if player and player:getVariableBoolean("ClimbingFence") then
                local current = player:getVariableString("ClimbFenceOutcome")
                if current == "success" or current == "fall" then
                    player:setVariable("ClimbFenceOutcome", entry.outcome)
                end
            
                if entry.dive then
                    player:setVariable("DiveThruWindow", true)
                    applied[id] = true
                end

                pending[id] = nil
            end
        end
    end
end

local function clearApplied()
    if table.isempty(applied) then return end

    for id, _ in pairs(applied) do
        local player = getPlayerByOnlineID(id)
        if not player then
            applied[id] = nil
        elseif not player:getVariableBoolean("ClimbingFence") then
            player:clearVariable("DiveThruWindow")
            applied[id] = nil
        end
    end
end

if isClient() then
    Events.OnServerCommand.Add(onServerCommand)
    Events.OnTick.Add(applyPending)
    Events.OnTick.Add(clearApplied)
end
