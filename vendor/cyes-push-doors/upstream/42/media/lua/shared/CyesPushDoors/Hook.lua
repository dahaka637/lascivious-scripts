require "CyesPushDoors/Core"

pcall(require, "ISUI/ISWorldObjectContextMenu")
pcall(require, "ISObjectClickHandler")
pcall(require, "TimedActions/ISContextualActions")
pcall(require, "ISUI/ISButtonPrompt")

CyesPushDoors = CyesPushDoors or {}
local CPD = CyesPushDoors

CPD._pendingDoorOpens = CPD._pendingDoorOpens or {}
CPD._observedDoors = CPD._observedDoors or {}
CPD._localInteractionIntents = CPD._localInteractionIntents or {}
CPD._hookTick = CPD._hookTick or 0

local function nowMs()
    if getTimestampMs then return getTimestampMs() end
    return math.floor(os.time() * 1000)
end

local function readOpen(door)
    if not door then return nil end
    local ok, value = pcall(CPD.getLogicalDoorOpenState, door)
    if ok and value ~= nil then return value == true end
    return nil
end

local function doorLabel(door)
    if not door then return "nil" end
    local ok, sq = pcall(function() return door:getSquare() end)
    if not ok or not sq then return tostring(door) end
    local index = -1
    pcall(function() index = door:getObjectIndex() end)
    return tostring(sq:getX()) .. "," .. tostring(sq:getY()) .. "," .. tostring(sq:getZ()) .. "#" .. tostring(index)
end

CPD._doorDiagnosticSeen = CPD._doorDiagnosticSeen or {}

local function safeDoorValue(fn, fallback)
    local ok, value = pcall(fn)
    if ok and value ~= nil then return value end
    return fallback
end

local function spriteName(sprite)
    if not sprite then return "nil" end
    return tostring(safeDoorValue(function() return sprite:getName() end, tostring(sprite)))
end

local function propertyList(props)
    if not props then return "none" end
    local names = safeDoorValue(function() return props:getPropertyNames() end, nil)
    if not names then return "unavailable" end

    local count = safeDoorValue(function() return names:size() end, 0) or 0
    local out = {}
    for i = 0, count - 1 do
        local name = safeDoorValue(function()
            local getter = names.get
            if getter then return getter(names, i) end
            return nil
        end, nil)
        if name ~= nil then
            name = tostring(name)
            local value = nil
            local valMethod = safeDoorValue(function() return props.Val end, nil)
            if valMethod then
                value = safeDoorValue(function() return valMethod(props, name) end, nil)
            end
            if value == nil or tostring(value) == "" then
                out[#out + 1] = name
            else
                out[#out + 1] = name .. "=" .. tostring(value)
            end
        end
    end
    if #out == 0 then return "none" end
    return table.concat(out, "; ")
end

function CPD.logDoorIdentity(door, source)
    if not door or not CPD.Config or CPD.Config.DOOR_ID_DIAGNOSTIC ~= true then return end

    local label = doorLabel(door)
    local now = nowMs()
    local last = CPD._doorDiagnosticSeen[door]
    if last and (now - last) < 1500 then return end
    CPD._doorDiagnosticSeen[door] = now

    local currentSprite = safeDoorValue(function() return door:getSprite() end, nil)
    local currentName = safeDoorValue(function() return door:getSpriteName() end, nil)
    if currentName == nil and currentSprite then currentName = spriteName(currentSprite) end

    local openSprite = safeDoorValue(function() return door:getOpenSprite() end, nil)
    local openName = spriteName(openSprite)
    local objectName = tostring(safeDoorValue(function() return door:getObjectName() end, "unknown"))
    local name = tostring(safeDoorValue(function() return door:getName() end, "nil"))
    local north = tostring(safeDoorValue(function() return door:getNorth() end, "unknown"))
    local doubleIndex = tostring(safeDoorValue(function()
        if IsoDoor and IsoDoor.getDoubleDoorIndex then return IsoDoor.getDoubleDoorIndex(door) end
        return -1
    end, -1))
    local garageIndex = tostring(safeDoorValue(function()
        if IsoDoor and IsoDoor.getGarageDoorIndex then return IsoDoor.getGarageDoorIndex(door) end
        return -1
    end, -1))
    local thumpSound = tostring(safeDoorValue(function() return door:getThumpSound() end, "nil"))
    local material = tostring(safeDoorValue(function() return CPD.getDoorMaterial(door) end, "unknown"))
    local health = tostring(safeDoorValue(function() return door:getHealth() end, "?"))
    local maxHealth = tostring(safeDoorValue(function() return door:getMaxHealth() end, "?"))

    print("[Cye's Push Doors!] [CPD DOOR ID] sprite=" .. tostring(currentName or "nil") ..
        " | openSprite=" .. openName ..
        " | object=" .. objectName ..
        " | name=" .. name ..
        " | north=" .. north ..
        " | double=" .. doubleIndex ..
        " | garage=" .. garageIndex ..
        " | material=" .. material ..
        " | thumpSound=" .. thumpSound ..
        " | health=" .. health .. "/" .. maxHealth ..
        " | square=" .. label ..
        " | source=" .. tostring(source or "unknown"))

    local props = safeDoorValue(function() return door:getProperties() end, nil)
    print("[Cye's Push Doors!] [CPD DOOR PROPS] sprite=" .. tostring(currentName or "nil") .. " | " .. propertyList(props))

    if openSprite then
        local openProps = safeDoorValue(function() return openSprite:getProperties() end, nil)
        print("[Cye's Push Doors!] [CPD OPEN PROPS] sprite=" .. openName .. " | " .. propertyList(openProps))
    end
end

local function getExpectedTransition(door)
    if not door or not CPD.isSupportedDoor(door) then return nil, nil end
    local current = readOpen(door)
    if current == nil then return nil, nil end

    if CPD.isGarageDoor(door) then
        if current == true then return false, "close" end
        return nil, nil
    end

    if current == false then return true, "open" end
    return nil, nil
end

local function interactionKind(door)
    if not door then return "unknown" end
    if CPD.isGarageDoor(door) then return "garage" end
    if CPD.isDoubleDoor(door) then return "double-door" end
    if instanceof(door, "IsoThumpable") then return "thumpable-door" end
    if instanceof(door, "IsoDoor") then return "iso-door" end
    return "unknown"
end

local function identityDoor(door)
    if door and CPD.isGarageDoor(door) then
        return CPD.getGarageDoorMaster(door) or door
    end
    if door and CPD.isDoubleDoor(door) then
        return CPD.getDoubleDoorMaster(door) or door
    end
    return door
end

local function isAttachedDoor(door)
    if not door or not CPD.isSupportedDoor(door) then return false end
    local okSquare, square = pcall(function() return door:getSquare() end)
    if not okSquare or not square then return false end
    local okIndex, index = pcall(function() return door:getObjectIndex() end)
    if okIndex and index ~= nil and tonumber(index) ~= nil and tonumber(index) < 0 then
        return false
    end
    return true
end

local function worldKeySafe(door)
    if not door then return nil end
    local ok, key = pcall(CPD.getDoorWorldKey, door)
    if ok and key and key ~= "unknown" then return tostring(key) end
    return nil
end

local function removePendingReference(target)
    if not target then return end
    for i = #CPD._pendingDoorOpens, 1, -1 do
        if CPD._pendingDoorOpens[i] == target then
            table.remove(CPD._pendingDoorOpens, i)
            return
        end
    end
end

CPD._recentInteractionTransitions = CPD._recentInteractionTransitions or {}

local function recentInteractionMatches(key, transition, windowMs)
    if not key then return false end
    local recent = CPD._recentInteractionTransitions[key]
    if not recent then return false end
    local age = nowMs() - (tonumber(recent.at) or 0)
    return age >= 0 and age < (tonumber(windowMs) or 0) and recent.transition == transition
end

local function markInteractionTransition(key, transition)
    if not key then return end
    CPD._recentInteractionTransitions[key] = {
        at = nowMs(),
        transition = transition,
    }
end

local function pendingRejectedInteractionMatches(key, transition)
    if not key then return false end
    for i = #CPD._pendingDoorOpens, 1, -1 do
        local pending = CPD._pendingDoorOpens[i]
        if pending and not pending.resolved and pending.key == key and
           pending.transition == transition and pending.impactEligible ~= true then
            return true, pending.impactReason
        end
    end
    return false, nil
end

local function pruneRecentInteractions(now)
    if (CPD._hookTick % 600) ~= 0 then return end
    local keepMs = math.max(
        tonumber(CPD.Config.SCANNER_AFTER_INTERACTION_SUPPRESS_MS) or 1000,
        tonumber(CPD.Config.INTERACTION_REPORT_DEDUPE_MS) or 300
    ) + 5000
    for key, recent in pairs(CPD._recentInteractionTransitions) do
        if not recent or (now - (tonumber(recent.at) or 0)) > keepMs then
            CPD._recentInteractionTransitions[key] = nil
        end
    end
end

local function resolveTrackedDoor(pending)
    if not pending then return nil end

    local door = pending.door
    if isAttachedDoor(door) then
        local key = worldKeySafe(door)
        if key == pending.key then return door end
        
        
        
        
        if pending.kind == "double-door" and CPD.isDoubleDoor(door) then
            return door
        end
    end

    if pending.doorArgs then
        local ok, found = pcall(CPD.findDoor, pending.doorArgs)
        if ok and isAttachedDoor(found) then
            if worldKeySafe(found) == pending.key or
               (pending.kind == "double-door" and CPD.isDoubleDoor(found)) then
                pending.door = found
                return found
            end
        end
    end

    
    
    
    local master = pending.identityDoor
    if isAttachedDoor(master) and worldKeySafe(master) == pending.key then
        pending.door = master
        return master
    end

    return nil
end

local function makeInteractionArgs(door, impactSquare, transition, kind)
    local args = CPD.makeDoorArgs(door, impactSquare, true, transition)
    if args then
        args.interactionKind = kind or interactionKind(door)
    end
    return args
end

function CPD.trackPendingDoorOpen(character, door, source)
    if not character or not door or not CPD.isSupportedDoor(door) then return nil end

    local expectedOpen, transition = getExpectedTransition(door)
    if expectedOpen == nil then return nil end

    local idDoor = identityDoor(door)
    local key = worldKeySafe(idDoor or door)
    if not key then return nil end

    CPD.logDoorIdentity(door, source or "interaction")

    local impactContext, impactReason = CPD.getInteractionImpactContext(character, door)
    local impactSquare = impactContext and impactContext.anchor or nil
    local impactEligible = impactContext ~= nil

    if impactContext then
        CPD.mpDebug("INTERACTION_GEOMETRY",
            "key=" .. tostring(key) ..
            " transition=" .. tostring(transition) ..
            " playerSide=" .. tostring(impactContext.playerSide) ..
            " impactSide=" .. tostring(impactContext.impactSide) ..
            " anchor=" .. tostring(impactSquare and (impactSquare:getX() .. "," .. impactSquare:getY() .. "," .. impactSquare:getZ()) or "nil") ..
            " distanceSq=" .. tostring(impactContext.entryDistanceSq) ..
            " facingDot=" .. tostring(impactContext.facingDot))
    else
        CPD.mpDebug("INTERACTION_GEOMETRY_SKIP",
            "key=" .. tostring(key) ..
            " transition=" .. tostring(transition) ..
            " reason=" .. tostring(impactReason or "unknown"))
    end

    local kind = interactionKind(door)
    local args = makeInteractionArgs(door, impactSquare, transition, kind)
    local now = nowMs()

    
    
    
    for i = #CPD._pendingDoorOpens, 1, -1 do
        local pending = CPD._pendingDoorOpens[i]
        if pending and not pending.resolved and pending.key == key and
           pending.transition == transition and pending.expectedOpen == expectedOpen then
            pending.character = character
            pending.source = source or pending.source
            pending.lastTouched = now
            pending.impactSquare = impactSquare or pending.impactSquare
            pending.impactEligible = impactEligible
            pending.impactReason = impactReason
            pending.doorArgs = args or pending.doorArgs
            pending.door = door or pending.door
            pending.identityDoor = idDoor or pending.identityDoor
            pending.kind = kind or pending.kind
            CPD.mpDebug("INTERACTION_MERGE",
                "key=" .. tostring(key) ..
                " kind=" .. tostring(pending.kind) ..
                " transition=" .. tostring(transition) ..
                " source=" .. tostring(source))
            return pending
        end
    end

    local pending = {
        character = character,
        door = door,
        identityDoor = idDoor,
        doorArgs = args,
        key = key,
        kind = kind,
        impactSquare = impactSquare,
        impactEligible = impactEligible,
        impactReason = impactReason,
        started = now,
        lastTouched = now,
        source = source or "unknown",
        expectedOpen = expectedOpen,
        transition = transition,
        resolved = false,
    }
    CPD._pendingDoorOpens[#CPD._pendingDoorOpens + 1] = pending

    CPD.mpDebug("INTERACTION_BEGIN",
        "key=" .. tostring(key) ..
        " kind=" .. tostring(kind) ..
        " transition=" .. tostring(transition) ..
        " source=" .. tostring(source or "unknown"))
    return pending
end

function CPD.handleLocalDoorTransition(character, door, transition, source, preferredImpactSquare, interaction)
    if not character or not door or not CPD.isSupportedDoor(door) then return false end

    local garage = CPD.isGarageDoor(door)
    transition = transition or (garage and "close" or "open")
    local current = readOpen(door)
    if transition == "open" and current ~= true then return false end
    if transition == "close" and current ~= false then return false end

    local key = worldKeySafe(identityDoor(door) or door)
    local isInteraction = interaction == true

    if isInteraction and recentInteractionMatches(
        key,
        transition,
        tonumber(CPD.Config.INTERACTION_REPORT_DEDUPE_MS) or 300
    ) then
        CPD.mpDebug("INTERACTION_DEDUPE",
            "suppressed duplicate interaction key=" .. tostring(key) ..
            " transition=" .. tostring(transition) ..
            " source=" .. tostring(source or "unknown"))
        return false
    end

    CPD.log("TRANSITION detected=" .. tostring(transition) .. " " .. doorLabel(door) .. " via " .. tostring(source or "unknown"))

    if isInteraction then
        markInteractionTransition(key, transition)
    end

    if isClient and isClient() then
        local args = CPD.makeDoorArgs(door, preferredImpactSquare, isInteraction, transition)
        if args then args.interactionKind = interactionKind(door) end
        if args and sendClientCommand then
            local okSend, err = pcall(function()
                sendClientCommand(character, "CyesPushDoors", "doorOpened", args)
            end)
            if okSend then
                CPD.mpDebug(isInteraction and "CLIENT_INTERACTION_SEND" or "CLIENT_SCANNER_SEND",
                    "key=" .. tostring(key) ..
                    " kind=" .. tostring(args.interactionKind) ..
                    " transition=" .. tostring(transition) ..
                    " source=" .. tostring(source or "unknown"))
                return true
            end
            CPD.mpDebug("CLIENT_SEND_ERROR", tostring(err))
        end
        return false
    end

    CPD.mpDebug(isInteraction and "SP_INTERACTION_RESOLVE" or "SP_SCANNER_RESOLVE",
        "key=" .. tostring(key) ..
        " kind=" .. tostring(interactionKind(door)) ..
        " transition=" .. tostring(transition) ..
        " source=" .. tostring(source or "unknown"))
    return CPD.resolveDoorImpact(character, door, preferredImpactSquare, transition)
end

function CPD.handleLocalDoorOpened(character, door, source, preferredImpactSquare)
    return CPD.handleLocalDoorTransition(character, door, "open", source, preferredImpactSquare, false)
end

local function finishTrackedInteraction(pending, phase)
    if not pending or pending.resolved then return false end
    local door = resolveTrackedDoor(pending)
    if not door then return false end

    if readOpen(door) ~= pending.expectedOpen then return false end

    pending.resolved = true
    CPD.mpDebug("INTERACTION_STATE_READY",
        "phase=" .. tostring(phase or "unknown") ..
        " key=" .. tostring(pending.key) ..
        " kind=" .. tostring(pending.kind) ..
        " transition=" .. tostring(pending.transition) ..
        " delayMs=" .. tostring(nowMs() - (pending.started or nowMs())))

    if pending.impactEligible ~= true or not pending.impactSquare then
        CPD.mpDebug("INTERACTION_IMPACT_SKIP",
            "key=" .. tostring(pending.key) ..
            " kind=" .. tostring(pending.kind) ..
            " transition=" .. tostring(pending.transition) ..
            " reason=" .. tostring(pending.impactReason or "invalid-geometry"))
        markInteractionTransition(pending.key, pending.transition)
        CPD.mpDebug("INTERACTION_SCANNER_BLOCK",
            "key=" .. tostring(pending.key) ..
            " transition=" .. tostring(pending.transition) ..
            " reason=" .. tostring(pending.impactReason or "invalid-geometry"))
        removePendingReference(pending)
        return false
    end

    CPD.handleLocalDoorTransition(
        pending.character,
        door,
        pending.transition,
        tostring(phase or "interaction") .. " / " .. tostring(pending.source),
        pending.impactSquare,
        true
    )
    removePendingReference(pending)
    return true
end

local function packResults(...)
    return { n = select("#", ...), ... }
end

local unpackResults = table.unpack or unpack

local function invokeTracked(character, door, source, vanillaCall)
    local pending = CPD.trackPendingDoorOpen(character, door, source)
    local results = packResults(vanillaCall())
    
    
    
    finishTrackedInteraction(pending, "post-vanilla")
    return unpackResults(results, 1, results.n)
end

local function wrapTableFunction(tbl, key, slot, wrapperFactory)
    if not tbl or type(tbl[key]) ~= "function" then return false end
    local current = tbl[key]
    local wrapped = CPD[slot .. "Wrapped"]
    if current == wrapped then return true end

    local newWrapped = wrapperFactory(current)
    CPD[slot .. "Original"] = current
    CPD[slot .. "Wrapped"] = newWrapped
    tbl[key] = newWrapped
    CPD.log("Hooked " .. key .. " (" .. slot .. ")")
    return true
end

local function installHooks()
    wrapTableFunction(ISWorldObjectContextMenu, "onOpenCloseDoor", "WorldOpenCloseDoor", function(vanilla)
        return function(worldobjects, door, player, ...)
            local playerObj = getSpecificPlayer(player)
            local extra = { n = select("#", ...), ... }
            return invokeTracked(playerObj, door, "ISWorldObjectContextMenu.onOpenCloseDoor", function()
                return vanilla(worldobjects, door, player, unpackResults(extra, 1, extra.n))
            end)
        end
    end)

    wrapTableFunction(ISObjectClickHandler, "doClickDoor", "ClickDoor", function(vanilla)
        return function(object, playerNum, playerObj, ...)
            local extra = { n = select("#", ...), ... }
            return invokeTracked(playerObj, object, "ISObjectClickHandler.doClickDoor", function()
                return vanilla(object, playerNum, playerObj, unpackResults(extra, 1, extra.n))
            end)
        end
    end)

    wrapTableFunction(ISObjectClickHandler, "doClickThumpable", "ClickThumpable", function(vanilla)
        return function(object, playerNum, playerObj, ...)
            local extra = { n = select("#", ...), ... }
            if object and instanceof(object, "IsoThumpable") and CPD.isSupportedDoor(object) then
                return invokeTracked(playerObj, object, "ISObjectClickHandler.doClickThumpable", function()
                    return vanilla(object, playerNum, playerObj, unpackResults(extra, 1, extra.n))
                end)
            end
            return vanilla(object, playerNum, playerObj, unpackResults(extra, 1, extra.n))
        end
    end)

    wrapTableFunction(ISButtonPrompt, "openDoor", "ButtonPromptOpenDoor", function(vanilla)
        return function(self, door, ...)
            local playerObj = nil
            if self and self.player ~= nil then
                playerObj = getSpecificPlayer(self.player)
            end
            local extra = { n = select("#", ...), ... }
            return invokeTracked(playerObj, door, "ISButtonPrompt.openDoor", function()
                return vanilla(self, door, unpackResults(extra, 1, extra.n))
            end)
        end
    end)

    if ContextualActionHandlers then
        wrapTableFunction(ContextualActionHandlers, "OpenDoor", "ContextualOpenDoor", function(vanilla)
            return function(action, playerObj, door, arg2, arg3, arg4, ...)
                local extra = { n = select("#", ...), ... }
                return invokeTracked(playerObj, door, "ContextualActionHandlers.OpenDoor", function()
                    return vanilla(action, playerObj, door, arg2, arg3, arg4, unpackResults(extra, 1, extra.n))
                end)
            end
        end)
    end
end

local function updatePendingDoorOpens()
    if #CPD._pendingDoorOpens == 0 then return end

    local now = nowMs()
    local timeout = tonumber(CPD.Config.PENDING_INTERACTION_TIMEOUT_MS) or 3500
    for i = #CPD._pendingDoorOpens, 1, -1 do
        local pending = CPD._pendingDoorOpens[i]
        local remove = false

        if not pending or pending.resolved or not pending.character then
            remove = true
        elseif (now - (pending.started or now)) > timeout then
            CPD.mpDebug("INTERACTION_EXPIRE",
                "key=" .. tostring(pending.key) ..
                " kind=" .. tostring(pending.kind) ..
                " source=" .. tostring(pending.source))
            remove = true
        else
            local door = resolveTrackedDoor(pending)
            if not door then
                CPD.mpDebug("INTERACTION_STALE",
                    "waiting for valid door key=" .. tostring(pending.key) ..
                    " kind=" .. tostring(pending.kind))
            elseif readOpen(door) == pending.expectedOpen then
                pending.resolved = true
                CPD.mpDebug("INTERACTION_STATE_READY",
                    "phase=onTick key=" .. tostring(pending.key) ..
                    " kind=" .. tostring(pending.kind) ..
                    " transition=" .. tostring(pending.transition) ..
                    " delayMs=" .. tostring(now - (pending.started or now)))
                if pending.impactEligible == true and pending.impactSquare then
                    CPD.handleLocalDoorTransition(
                        pending.character,
                        door,
                        pending.transition,
                        "pending-state transition / " .. tostring(pending.source),
                        pending.impactSquare,
                        true
                    )
                else
                    CPD.mpDebug("INTERACTION_IMPACT_SKIP",
                        "key=" .. tostring(pending.key) ..
                        " kind=" .. tostring(pending.kind) ..
                        " transition=" .. tostring(pending.transition) ..
                        " reason=" .. tostring(pending.impactReason or "invalid-geometry"))
                    markInteractionTransition(pending.key, pending.transition)
                    CPD.mpDebug("INTERACTION_SCANNER_BLOCK",
                        "key=" .. tostring(pending.key) ..
                        " transition=" .. tostring(pending.transition) ..
                        " reason=" .. tostring(pending.impactReason or "invalid-geometry"))
                end
                remove = true
            end
        end

        if remove then
            table.remove(CPD._pendingDoorOpens, i)
        end
    end
end

local function canPromoteScannerToInteraction(playerObj, door, key, transition)
    if not playerObj or not door or not key then return false end
    if not playerObj:isAlive() then return false end

    
    
    if recentInteractionMatches(
        key,
        transition,
        tonumber(CPD.Config.SCANNER_AFTER_INTERACTION_SUPPRESS_MS) or 1000
    ) then
        return false
    end

    local maxDist = tonumber(CPD.Config.SCANNER_LOCAL_INTERACTION_DISTANCE) or 1.60
    local distanceSq = CPD.getPlayerDoorDistanceSq(playerObj, door)
    if distanceSq > (maxDist * maxDist) then return false end

    local playerSquare = playerObj:getCurrentSquare()
    local doorSquare = door:getSquare()
    if not playerSquare or not doorSquare or playerSquare:getZ() ~= doorSquare:getZ() then
        return false
    end

    return true
end

local function selectLogicalReportDoor(master, playerObj)
    if not master then return master end

    local parts = nil
    if CPD.isGarageDoor(master) then
        parts = CPD.getGarageDoorParts(master)
    elseif CPD.isDoubleDoor(master) then
        parts = CPD.getDoubleDoorParts(master)
    else
        return master
    end

    if not playerObj or #parts <= 1 then return parts[1] or master end

    local best = parts[1] or master
    local bestDistance = math.huge
    for i = 1, #parts do
        local part = parts[i]
        if isAttachedDoor(part) then
            local d = CPD.getPlayerDoorDistanceSq(playerObj, part)
            if d < bestDistance then
                bestDistance = d
                best = part
            end
        end
    end
    return best
end

local LOCAL_INTENT_TTL_MS = 1400

local function configuredInteractKey()
    local core = getCore and getCore() or nil
    if core then
        local names = { "Interact", "Interact with World", "InteractWorld" }
        for i = 1, #names do
            local ok, value = pcall(function() return core:getKey(names[i]) end)
            value = ok and tonumber(value) or nil
            if value and value > 0 then
                return value, names[i]
            end
        end
    end

    return 18, "fallback-E"
end

local function clearExpiredLocalInteractionIntents()
    local now = nowMs()
    for key, intent in pairs(CPD._localInteractionIntents) do
        if not intent or (now - (tonumber(intent.at) or 0)) > LOCAL_INTENT_TTL_MS then
            CPD._localInteractionIntents[key] = nil
        end
    end
end

local function findLocalIntentCandidate(playerObj)
    if not playerObj or not playerObj:isAlive() then return nil end
    local psq = playerObj:getCurrentSquare()
    if not psq then return nil end

    local maxDist = tonumber(CPD.Config.SCANNER_LOCAL_INTERACTION_DISTANCE) or 1.60
    local maxDistSq = maxDist * maxDist
    local seen = {}
    local validBest = nil
    local invalidBest = nil
    local px, py, pz = psq:getX(), psq:getY(), psq:getZ()

    for x = px - 2, px + 2 do
        for y = py - 2, py + 2 do
            local sq = getCell():getGridSquare(x, y, pz)
            if sq then
                local objects = sq:getObjects()
                if objects then
                    local count = tonumber(objects:size()) or 0
                    for i = 0, count - 1 do
                        local object = objects:get(i)
                        if isAttachedDoor(object) then
                            local idDoor = identityDoor(object)
                            local key = worldKeySafe(idDoor)
                            if key and not seen[key] then
                                seen[key] = true
                                local reportDoor = object
                                if CPD.isGarageDoor(idDoor) or CPD.isDoubleDoor(idDoor) then
                                    reportDoor = selectLogicalReportDoor(idDoor, playerObj)
                                end

                                if isAttachedDoor(reportDoor) then
                                    local expectedOpen, transition = getExpectedTransition(idDoor or reportDoor)
                                    if expectedOpen ~= nil and transition then
                                        local distanceSq = CPD.getPlayerDoorDistanceSq(playerObj, reportDoor)
                                        if distanceSq <= maxDistSq then
                                            local context, reason = CPD.getInteractionImpactContext(playerObj, reportDoor)
                                            local candidate = {
                                                key = key,
                                                door = reportDoor,
                                                identityDoor = idDoor,
                                                kind = interactionKind(reportDoor),
                                                expectedOpen = expectedOpen,
                                                transition = transition,
                                                impactSquare = context and context.anchor or nil,
                                                impactSide = context and context.impactSide or nil,
                                                impactEligible = context ~= nil,
                                                impactReason = reason,
                                                distanceSq = distanceSq,
                                                entryDistanceSq = context and context.entryDistanceSq or distanceSq,
                                            }

                                            if context then
                                                if not validBest or candidate.entryDistanceSq < validBest.entryDistanceSq then
                                                    validBest = candidate
                                                end
                                            elseif not invalidBest or candidate.distanceSq < invalidBest.distanceSq then
                                                invalidBest = candidate
                                            end
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    return validBest or invalidBest
end

local function armLocalInteractionIntent(keyCode)
    if not (isClient and isClient()) then return end

    local interactKey, bindingName = configuredInteractKey()
    if tonumber(keyCode) ~= tonumber(interactKey) then return end

    CPD._localInteractionIntents = {}

    local playerObj = getPlayer and getPlayer() or nil
    local candidate = findLocalIntentCandidate(playerObj)
    if not candidate then
        CPD.mpDebug("INPUT_INTENT_NONE",
            "keyCode=" .. tostring(keyCode) .. " binding=" .. tostring(bindingName))
        return
    end

    candidate.player = playerObj
    candidate.at = nowMs()
    candidate.keyCode = tonumber(keyCode)
    candidate.binding = bindingName
    CPD._localInteractionIntents[candidate.key] = candidate

    CPD.mpDebug(candidate.impactEligible and "INPUT_INTENT_BEGIN" or "INPUT_INTENT_REJECT",
        "key=" .. tostring(candidate.key) ..
        " kind=" .. tostring(candidate.kind) ..
        " transition=" .. tostring(candidate.transition) ..
        " impactSide=" .. tostring(candidate.impactSide or "nil") ..
        " distanceSq=" .. tostring(candidate.distanceSq) ..
        " reason=" .. tostring(candidate.impactReason or "ok") ..
        " binding=" .. tostring(bindingName))
end

local function consumeLocalInteractionIntent(key, transition, reportDoor)
    clearExpiredLocalInteractionIntents()
    local intent = key and CPD._localInteractionIntents[key] or nil
    if not intent then return nil, "no-local-interaction-intent" end

    CPD._localInteractionIntents[key] = nil
    local age = nowMs() - (tonumber(intent.at) or nowMs())
    if age < 0 or age > LOCAL_INTENT_TTL_MS then
        return nil, "expired-local-interaction-intent"
    end
    if intent.transition ~= transition then
        return nil, "transition-mismatch"
    end
    if not reportDoor or not isAttachedDoor(reportDoor) then
        return nil, "invalid-report-door"
    end
    if intent.impactEligible ~= true or not intent.impactSquare then
        return intent, intent.impactReason or "invalid-input-geometry"
    end
    if not CPD.isEntrySideSquare(reportDoor, intent.impactSquare) then
        intent.impactEligible = false
        intent.impactReason = "stale-input-impact-square"
        return intent, intent.impactReason
    end
    return intent, nil
end

local function captureScannerGeometry(state, playerObj, reportDoor)
    if not state then return nil, nil end
    local context, reason = CPD.getInteractionImpactContext(playerObj, reportDoor)
    state.geometryTick = CPD._hookTick
    state.geometryMs = nowMs()
    state.impactSquare = context and context.anchor or nil
    state.impactSide = context and context.impactSide or nil
    state.impactReason = reason
    return context, reason
end

local function selectScannerImpactGeometry(state, playerObj, reportDoor)
    local ageTicks = state and state.geometryTick and (CPD._hookTick - state.geometryTick) or math.huge
    local cachedSquare = state and state.impactSquare or nil
    local cachedValid = ageTicks <= 4 and cachedSquare and CPD.isEntrySideSquare(reportDoor, cachedSquare)

    if cachedValid then
        return cachedSquare, state.impactSide, "pre-transition", nil, ageTicks
    end

    return nil, nil, "none", "no-valid-pre-transition-geometry", ageTicks
end

local function observeDoor(door, playerObj, scanSeen)
    if not door or not CPD.isSupportedDoor(door) then return end

    local idDoor = identityDoor(door)
    if not idDoor then return end
    local key = worldKeySafe(idDoor)
    if not key then return end
    if scanSeen and scanSeen[key] then return end
    if scanSeen then scanSeen[key] = true end

    local reportDoor = door
    if CPD.isGarageDoor(idDoor) or CPD.isDoubleDoor(idDoor) then
        reportDoor = selectLogicalReportDoor(idDoor, playerObj)
    end
    if not isAttachedDoor(reportDoor) then return end

    local current = readOpen(idDoor)
    if current == nil then return end

    local state = CPD._observedDoors[key]
    if state == nil then
        state = {
            open = current,
            lastSeen = CPD._hookTick,
            lastTransitionMs = 0,
        }
        CPD._observedDoors[key] = state
        captureScannerGeometry(state, playerObj, reportDoor)
        return
    end

    state.lastSeen = CPD._hookTick

    local transition = nil
    if CPD.isGarageDoor(idDoor) then
        if state.open == true and current == false then transition = "close" end
    else
        if state.open == false and current == true then transition = "open" end
    end

    if transition then
        local now = nowMs()
        if (now - (state.lastTransitionMs or 0)) >= CPD.Config.IMPACT_DEDUPE_MS then
            state.lastTransitionMs = now

            local rejectedPending, rejectedReason = pendingRejectedInteractionMatches(key, transition)
            if rejectedPending then
                CPD.mpDebug("SCANNER_SUPPRESS",
                    "rejected interaction pending key=" .. tostring(key) ..
                    " transition=" .. tostring(transition) ..
                    " reason=" .. tostring(rejectedReason or "invalid-geometry"))
            elseif recentInteractionMatches(
                key,
                transition,
                tonumber(CPD.Config.SCANNER_AFTER_INTERACTION_SUPPRESS_MS) or 1000
            ) then
                CPD.mpDebug("SCANNER_SUPPRESS",
                    "interaction already reported key=" .. tostring(key) ..
                    " transition=" .. tostring(transition))
            else
                CPD.logDoorIdentity(reportDoor, "nearby " .. tostring(transition) .. " scanner")

                if isClient and isClient() then
                    local intent, intentReason = consumeLocalInteractionIntent(key, transition, reportDoor)
                    if not intent then
                        CPD.mpDebug("SCANNER_OBSERVER_SKIP",
                            "key=" .. tostring(key) ..
                            " transition=" .. tostring(transition) ..
                            " reason=" .. tostring(intentReason or "no-local-interaction-intent"))
                    elseif intent.impactEligible ~= true or not intent.impactSquare then
                        markInteractionTransition(key, transition)
                        CPD.mpDebug("SCANNER_INPUT_INTENT_REJECT",
                            "key=" .. tostring(key) ..
                            " transition=" .. tostring(transition) ..
                            " reason=" .. tostring(intentReason or intent.impactReason or "invalid-input-geometry"))
                    else
                        CPD.mpDebug("SCANNER_GEOMETRY",
                            "key=" .. tostring(key) ..
                            " transition=" .. tostring(transition) ..
                            " source=input-intent" ..
                            " impactSide=" .. tostring(intent.impactSide or "unknown") ..
                            " ageMs=" .. tostring(nowMs() - (intent.at or nowMs())))
                        CPD.mpDebug("SCANNER_PROMOTE_INTERACTION",
                            "key=" .. tostring(key) ..
                            " transition=" .. tostring(transition) ..
                            " kind=" .. tostring(interactionKind(reportDoor)) ..
                            " ownership=local-input-intent" ..
                            " distanceSq=" .. tostring(intent.distanceSq))

                        CPD.handleLocalDoorTransition(
                            playerObj,
                            reportDoor,
                            transition,
                            "local input intent / nearby scanner",
                            intent.impactSquare,
                            true
                        )
                    end
                else
                    local preferred, impactSide, geometrySource, impactReason, ageTicks =
                        selectScannerImpactGeometry(state, playerObj, reportDoor)

                    if not preferred then
                        CPD.mpDebug("SCANNER_IMPACT_SKIP",
                            "key=" .. tostring(key) ..
                            " transition=" .. tostring(transition) ..
                            " reason=" .. tostring(impactReason or "invalid-geometry"))
                    else
                        CPD.mpDebug("SCANNER_GEOMETRY",
                            "key=" .. tostring(key) ..
                            " transition=" .. tostring(transition) ..
                            " source=" .. tostring(geometrySource) ..
                            " impactSide=" .. tostring(impactSide or "unknown") ..
                            " ageTicks=" .. tostring(ageTicks))

                        local promotedInteraction = canPromoteScannerToInteraction(
                            playerObj, reportDoor, key, transition
                        )
                        if promotedInteraction then
                            CPD.mpDebug("SCANNER_PROMOTE_INTERACTION",
                                "key=" .. tostring(key) ..
                                " transition=" .. tostring(transition) ..
                                " kind=" .. tostring(interactionKind(reportDoor)) ..
                                " distanceSq=" .. tostring(CPD.getPlayerDoorDistanceSq(playerObj, reportDoor)))
                        end

                        CPD.handleLocalDoorTransition(
                            playerObj,
                            reportDoor,
                            transition,
                            promotedInteraction and "nearby scanner promoted local interaction" or
                                ("nearby " .. tostring(transition) .. " scanner"),
                            preferred,
                            promotedInteraction
                        )
                    end
                end
            end
        end
    end

    state.open = current
    captureScannerGeometry(state, playerObj, reportDoor)
end

local function scanNearbyDoors()
    local playerObj = getPlayer and getPlayer() or nil
    if not playerObj or not playerObj:isAlive() then return end
    local psq = playerObj:getCurrentSquare()
    if not psq then return end

    local scanSeen = {}
    local px, py, pz = psq:getX(), psq:getY(), psq:getZ()
    for x = px - 2, px + 2 do
        for y = py - 2, py + 2 do
            local sq = getCell():getGridSquare(x, y, pz)
            if sq then
                local objects = sq:getObjects()
                if objects then
                    local snapshot = {}
                    local count = 0
                    local okCount, sizeValue = pcall(function() return objects:size() end)
                    if okCount then count = tonumber(sizeValue) or 0 end

                    for i = 0, count - 1 do
                        local okGet, object = pcall(function() return objects:get(i) end)
                        if okGet and object then
                            snapshot[#snapshot + 1] = object
                        end
                    end

                    for i = 1, #snapshot do
                        local object = snapshot[i]
                        local okIndex, objectIndex = pcall(function() return object:getObjectIndex() end)
                        local okSquare, objectSquare = pcall(function() return object:getSquare() end)
                        local attached = okSquare and objectSquare ~= nil and
                            (not okIndex or objectIndex == nil or tonumber(objectIndex) == nil or tonumber(objectIndex) >= 0)

                        if attached then
                            local okObserve, err = pcall(observeDoor, object, playerObj, scanSeen)
                            if not okObserve then
                                CPD.log("Nearby door observer skipped an invalid/stale object: " .. tostring(err))
                            end
                        end
                    end
                end
            end
        end
    end

    if (CPD._hookTick % 600) == 0 then
        for key, state in pairs(CPD._observedDoors) do
            if not state or (CPD._hookTick - (state.lastSeen or 0)) > 600 then
                CPD._observedDoors[key] = nil
            end
        end
    end
end

local function onTick()
    CPD._hookTick = CPD._hookTick + 1
    updatePendingDoorOpens()
    CPD.updatePendingZombieDamage()

    if (CPD._hookTick % 2) == 0 then
        scanNearbyDoors()
    end

    pruneRecentInteractions(nowMs())
    if isClient and isClient() then clearExpiredLocalInteractionIntents() end

    if (CPD._hookTick % 300) == 0 then
        installHooks()
    end
end

installHooks()
if Events and Events.OnGameStart then Events.OnGameStart.Add(installHooks) end
if Events and Events.OnTick then Events.OnTick.Add(onTick) end
if Events and Events.OnKeyStartPressed then Events.OnKeyStartPressed.Add(armLocalInteractionIntent) end

CPD.mpDebug("HOOK_LOAD", "v1.0.2 active")
