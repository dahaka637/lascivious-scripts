CyesPushDoors = CyesPushDoors or {}
local CPD = CyesPushDoors

CPD.ZOMBIE_REACTIONS = CPD.ZOMBIE_REACTIONS or {}
CPD.ZOMBIE_REACTION_GROUPS = CPD.ZOMBIE_REACTION_GROUPS or {}

local function copyDefinition(definition)
    local copy = {}
    for key, value in pairs(definition or {}) do
        copy[key] = value
    end
    return copy
end

local function randomIndex(count)
    count = tonumber(count) or 0
    if count <= 0 then return nil end
    if ZombRand then return ZombRand(count) + 1 end
    return math.random(1, count)
end

local function safeMethod(object, methodName, ...)
    if not object then return nil, false end
    local okLookup, method = pcall(function() return object[methodName] end)
    if not okLookup or not method then return nil, false end
    local ok, result = pcall(method, object, ...)
    if not ok then return nil, false end
    return result, true
end

function CPD.registerZombieReaction(id, definition)
    id = tostring(id or "")
    if id == "" or type(definition) ~= "table" then return false end

    local stored = copyDefinition(definition)
    stored.id = id
    stored.type = tostring(stored.type or "hitReaction")
    CPD.ZOMBIE_REACTIONS[id] = stored
    return true
end

function CPD.registerZombieReactionGroup(id, definition)
    id = tostring(id or "")
    if id == "" or type(definition) ~= "table" then return false end

    local stored = copyDefinition(definition)
    stored.id = id
    stored.mode = tostring(stored.mode or "random")
    stored.reactions = stored.reactions or {}
    CPD.ZOMBIE_REACTION_GROUPS[id] = stored
    return true
end

function CPD.getZombieReaction(id)
    if id == nil then return nil end
    return CPD.ZOMBIE_REACTIONS[tostring(id)]
end

function CPD.getZombieReactionGroup(id)
    if id == nil then return nil end
    return CPD.ZOMBIE_REACTION_GROUPS[tostring(id)]
end

function CPD.findZombieReaction(requested)
    if requested == nil then return nil end
    requested = tostring(requested)

    local direct = CPD.getZombieReaction(requested)
    if direct then return direct end

    for _, definition in pairs(CPD.ZOMBIE_REACTIONS) do
        if definition and (
            requested == tostring(definition.reaction)
            or requested == tostring(definition.observedAnimation)
        ) then
            return definition
        end
    end
    return nil
end

local function definitionMatchesRequested(definition, requested)
    if not definition or requested == nil then return false end
    requested = tostring(requested)
    return requested == tostring(definition.id)
        or requested == tostring(definition.reaction)
        or requested == tostring(definition.observedAnimation)
end

local function findRequestedInGroup(group, requested)
    if not group or requested == nil then return nil end
    local entries = group.reactions or {}
    for i = 1, #entries do
        local definition = CPD.getZombieReaction(entries[i])
        if definitionMatchesRequested(definition, requested) then
            return definition
        end
    end
    return nil
end

function CPD.selectZombieReaction(sourceId, requested)
    local direct = CPD.getZombieReaction(sourceId)
    if direct then
        if requested == nil or definitionMatchesRequested(direct, requested) then
            return direct
        end
        return nil
    end

    local group = CPD.getZombieReactionGroup(sourceId)
    if not group then return nil end

    if requested ~= nil then
        return findRequestedInGroup(group, requested)
    end

    local entries = group.reactions or {}
    if #entries == 0 then return nil end

    if group.mode == "random" then
        local index = randomIndex(#entries)
        return index and CPD.getZombieReaction(entries[index]) or nil
    end

    return CPD.getZombieReaction(entries[1])
end

function CPD.playZombieReaction(zombie, sourceId, requested)
    if not zombie then return false, nil, nil, "no-zombie" end

    local alive, aliveOk = safeMethod(zombie, "isAlive")
    if aliveOk and alive ~= true then
        return false, nil, nil, "not-alive"
    end

    local definition = CPD.selectZombieReaction(sourceId, requested)
    if not definition then
        return false, requested, nil, "not-registered"
    end

    local kind = tostring(definition.type or "hitReaction")

    if kind == "hitReaction" then
        local reaction = tostring(definition.reaction or "")
        local event = tostring(definition.event or "wasHit")
        if reaction == "" then return false, reaction, definition.id, "missing-reaction" end

        if definition.clearStaggerBack ~= false then
            safeMethod(zombie, "setStaggerBack", false)
        end
        if definition.clearKnockedDown == true then
            safeMethod(zombie, "setKnockedDown", false)
        end

        local _, reactionOk = safeMethod(zombie, "setHitReaction", reaction)
        if not reactionOk then
            return false, reaction, definition.id, "setHitReaction"
        end

        local _, eventOk = safeMethod(zombie, "reportEvent", event)
        if not eventOk then
            return false, reaction, definition.id, "wasHit"
        end

        return true, reaction, definition.id, nil
    end

    if kind == "event" then
        local event = tostring(definition.event or "")
        if event == "" then return false, event, definition.id, "missing-event" end
        local _, eventOk = safeMethod(zombie, "reportEvent", event)
        if not eventOk then return false, event, definition.id, "reportEvent" end
        return true, event, definition.id, nil
    end

    if kind == "animation" then
        local animation = tostring(definition.animation or definition.observedAnimation or "")
        if animation == "" then return false, animation, definition.id, "missing-animation" end
        local _, animOk = safeMethod(zombie, "PlayAnimUnlooped", animation)
        if not animOk then return false, animation, definition.id, "PlayAnimUnlooped" end
        return true, animation, definition.id, nil
    end

    return false, nil, definition.id, "unsupported-type"
end

CPD.registerZombieReaction("DoorHitChestL", {
    type = "hitReaction",
    reaction = "ShotChest",
    event = "wasHit",
    observedAnimation = "Zombie_ShotChestL",
})

CPD.registerZombieReaction("DoorHitChestR", {
    type = "hitReaction",
    reaction = "ShotChestStepR",
    event = "wasHit",
    observedAnimation = "Zombie_ShotChestStepR",
})

CPD.registerZombieReactionGroup("DoorNormalHit", {
    mode = "random",
    reactions = {
        "DoorHitChestL",
        "DoorHitChestR",
    },
})

CPD.registerZombieReaction("SlidingDoorHitLegL", {
    type = "hitReaction",
    reaction = "ShotLegL",
    event = "wasHit",
    observedAnimation = "Zombie_ShotLeg_L",
    clearKnockedDown = true,
})

CPD.registerZombieReaction("SlidingDoorHitLegR", {
    type = "hitReaction",
    reaction = "ShotLegR",
    event = "wasHit",
    observedAnimation = "Zombie_ShotLeg_R",
    clearKnockedDown = true,
})

CPD.registerZombieReaction("SlidingDoorCrawlerFloorFront", {
    type = "hitReaction",
    reaction = "FloorOnFront",
    event = "wasHit",
    observedAnimation = "Zombie_HitReact_FloorOnFront",
})

CPD.registerZombieReaction("SlidingDoorCrawlerKneesToFloorFront", {
    type = "hitReaction",
    reaction = "OnKneesToFloorFront",
    event = "wasHit",
    observedAnimation = "Zombie_OnKnees_ToFloorFront",
})

CPD.registerZombieReactionGroup("SlidingDoorStandingHit", {
    mode = "random",
    reactions = {
        "SlidingDoorHitLegL",
        "SlidingDoorHitLegR",
    },
})

CPD.registerZombieReactionGroup("SlidingDoorCrawlerHit", {
    mode = "random",
    reactions = {
        "SlidingDoorCrawlerFloorFront",
        "SlidingDoorCrawlerKneesToFloorFront",
    },
})
