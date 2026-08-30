require "CyesPushDoors/Config"
require "CyesPushDoors/Settings"

CyesPushDoors = CyesPushDoors or {}
local CPD = CyesPushDoors
local C = CPD.Config
local S = CPD.Settings

CPD._recentImpacts = CPD._recentImpacts or {}
CPD._pendingZombieDamage = CPD._pendingZombieDamage or {}
CPD._pendingZombieNetworkVerify = CPD._pendingZombieNetworkVerify or {}
CPD._impactRecoveryUntil = CPD._impactRecoveryUntil or {}

local function emitServerDebugFile(tag, msg, renderedLine)
    if not (isServer and isServer()) then return end
    local sink = CPD and CPD._serverDebugFileSink or nil
    if type(sink) ~= "function" then return end
    pcall(sink, tag, msg, renderedLine)
end

local function log(msg)
    if C.DEBUG == true then
        local rendered = "[Cye's Push Doors!] " .. tostring(msg)
        print(rendered)
        emitServerDebugFile("LOG", msg, rendered)
    end
end
CPD.log = log

local function mpDebug(tag, msg)
    if C.DEBUG ~= true then return end
    local side = "LOCAL"
    if isServer and isServer() then
        side = "SERVER"
    elseif isClient and isClient() then
        side = "CLIENT"
    end
    local label = tostring(C.DEBUG_LABEL or C.VERSION or "DEBUG")
    local rendered = "[CPD " .. label .. "][" .. side .. "][" .. tostring(tag) .. "] " .. tostring(msg)
    print(rendered)
    if side == "SERVER" then
        emitServerDebugFile(tag, msg, rendered)
    end
end
CPD.mpDebug = mpDebug

require "CyesPushDoors/Reactions"

local function clamp(value, lo, hi)
    if value < lo then return lo end
    if value > hi then return hi end
    return value
end

local function randomFloat(lo, hi)
    if lo == hi then return lo end
    if ZombRandFloat then
        return ZombRandFloat(lo, hi)
    end
    return lo + ((ZombRand(100000) / 100000.0) * (hi - lo))
end

local function randomIntInclusive(lo, hi)
    lo = math.floor(tonumber(lo) or 0)
    hi = math.floor(tonumber(hi) or lo)
    if hi < lo then lo, hi = hi, lo end
    if hi == lo then return lo end
    return lo + ZombRand((hi - lo) + 1)
end

local function shuffledCopy(list)
    local copy = {}
    for i = 1, #list do copy[i] = list[i] end
    for i = #copy, 2, -1 do
        local j = randomIntInclusive(1, i)
        copy[i], copy[j] = copy[j], copy[i]
    end
    return copy
end

local function safeCall(object, methodName, ...)
    if not object then return nil end
    local okLookup, method = pcall(function() return object[methodName] end)
    if not okLookup or not method then return nil end
    local ok, result = pcall(method, object, ...)
    if ok then return result end
    return nil
end

function CPD.getStrength(character)
    if not character then return 0 end
    local level = safeCall(character, "getPerkLevel", Perks.Strength) or 0
    return clamp(tonumber(level) or 0, 0, 10)
end

function CPD.getFitness(character)
    if not character then return 0 end
    local level = safeCall(character, "getPerkLevel", Perks.Fitness) or 0
    return clamp(tonumber(level) or 0, 0, 10)
end

local function getArmPartDefs()
    if not BodyPartType then return {} end
    return {
        { name="Hand_L",     type=BodyPartType.Hand_L },
        { name="ForeArm_L",  type=BodyPartType.ForeArm_L },
        { name="UpperArm_L", type=BodyPartType.UpperArm_L },
        { name="Hand_R",     type=BodyPartType.Hand_R },
        { name="ForeArm_R",  type=BodyPartType.ForeArm_R },
        { name="UpperArm_R", type=BodyPartType.UpperArm_R },
    }
end

local function getArmBodyPart(character, partType)
    if not character or not partType then return nil end
    local bodyDamage = safeCall(character, "getBodyDamage")
    if not bodyDamage then return nil end
    return safeCall(bodyDamage, "getBodyPart", partType)
end

function CPD.getArmStrainBySide(character)
    if not character then return 0, 0 end
    local leftMaximum = 0
    local rightMaximum = 0
    local defs = getArmPartDefs()
    for i = 1, #defs do
        local def = defs[i]
        local part = getArmBodyPart(character, def.type)
        local stiffness = tonumber(safeCall(part, "getStiffness")) or 0
        if string.sub(def.name, -2) == "_L" then
            if stiffness > leftMaximum then leftMaximum = stiffness end
        else
            if stiffness > rightMaximum then rightMaximum = stiffness end
        end
    end
    return clamp(leftMaximum, 0, 100), clamp(rightMaximum, 0, 100)
end

function CPD.getArmStrain(character)
    local leftStrain, rightStrain = CPD.getArmStrainBySide(character)
    return math.max(leftStrain, rightStrain)
end

function CPD.getArmStrainThresholds()
    local scale = S.armStrainUsageLimitMultiplier()
    local thresholds = C.ARM_STRAIN_THRESHOLDS or {}
    return {
        light = (tonumber(thresholds.light) or 5.0) * scale,
        medium = (tonumber(thresholds.medium) or 12.0) * scale,
        high = (tonumber(thresholds.high) or 20.0) * scale,
    }
end

function CPD.getArmStrainUsageLimit()
    return (tonumber(C.ARM_STRAIN_USAGE_LIMIT) or 20.0) * S.armStrainUsageLimitMultiplier()
end

function CPD.getArmStrainBand(character)
    local strain = CPD.getArmStrain(character)
    local thresholds = CPD.getArmStrainThresholds()
    if strain >= thresholds.high then return "high", strain end
    if strain >= thresholds.medium then return "medium", strain end
    if strain >= thresholds.light then return "light", strain end
    return "none", strain
end

function CPD.getArmStrainModifiers(character)
    local band, strain = CPD.getArmStrainBand(character)
    local row = C.ARM_STRAIN_DEBUFF[band] or C.ARM_STRAIN_DEBUFF.none
    local penalty = S.armStrainPenaltyMultiplier()
    local baseDamage = tonumber(row.damageMult) or 1.0
    local baseKnockdown = tonumber(row.knockdownMult) or 1.0
    return {
        band = band,
        strain = strain,
        damageMult = clamp(1.0 - ((1.0 - baseDamage) * penalty), 0.0, 1.0),
        knockdownMult = clamp(1.0 - ((1.0 - baseKnockdown) * penalty), 0.0, 1.0),
    }
end

local function recoveryNowMs()
    if getTimestampMs then return getTimestampMs() end
    return math.floor(os.time() * 1000)
end

function CPD.getImpactRecoveryBand(character)
    local band, strain = CPD.getArmStrainBand(character)
    if band == "high" and not CPD.isImpactBlockedByArmStrain(character) then
        band = "medium"
    end
    return band, strain
end

function CPD.getImpactRecoveryDurationMs(character)
    local band, strain = CPD.getImpactRecoveryBand(character)
    local durations = C.ARM_STRAIN_RECOVERY_MS or {}
    local baseMs = tonumber(durations[band]) or tonumber(durations.none) or 750
    local durationMs = math.max(0, math.floor((baseMs * S.armStrainRecoveryMultiplier()) + 0.5))
    return durationMs, band, strain
end

function CPD.getImpactRecoveryRemainingMs(character)
    if not character then return 0, "none" end
    local untilAt = tonumber(CPD._impactRecoveryUntil[character]) or 0
    local remaining = untilAt - recoveryNowMs()
    if remaining <= 0 then
        CPD._impactRecoveryUntil[character] = nil
        return 0, CPD.getImpactRecoveryBand(character)
    end
    local band = CPD.getImpactRecoveryBand(character)
    return math.ceil(remaining), band
end

function CPD.isImpactRecoveryActive(character)
    local remaining, band = CPD.getImpactRecoveryRemainingMs(character)
    return remaining > 0, remaining, band
end

function CPD.startImpactRecovery(character)
    if not character then return 0, "none", 0 end
    local durationMs, band, strain = CPD.getImpactRecoveryDurationMs(character)
    if durationMs <= 0 then
        CPD._impactRecoveryUntil[character] = nil
        return 0, band, strain
    end
    CPD._impactRecoveryUntil[character] = recoveryNowMs() + durationMs
    return durationMs, band, strain
end

local function getSandboxMuscleStrainMultiplier()
    if SandboxVars and SandboxVars.MuscleStrainFactor ~= nil then
        return math.max(0, tonumber(SandboxVars.MuscleStrainFactor) or 1.0)
    end
    return 1.0
end

function CPD.setArmStrainAbsolute(character, values)
    if not character or not values then return end
    local defs = getArmPartDefs()
    for i = 1, #defs do
        local def = defs[i]
        local value = tonumber(values[def.name])
        if value ~= nil then
            local part = getArmBodyPart(character, def.type)
            if part then safeCall(part, "setStiffness", clamp(value, 0, 100)) end
        end
    end
end

function CPD.getArmStrainParts(character)
    local values = {}
    local defs = getArmPartDefs()
    for i = 1, #defs do
        local def = defs[i]
        local part = getArmBodyPart(character, def.type)
        values[def.name] = tonumber(safeCall(part, "getStiffness")) or 0
    end
    return values
end

function CPD.isImpactBlockedByArmStrain(character)
    if not character then return false end

    local limit = CPD.getArmStrainUsageLimit()
    local leftStrain, rightStrain = CPD.getArmStrainBySide(character)
    return leftStrain >= limit and rightStrain >= limit
end

function CPD.applyArmStrain(character, fitness, targetCount, doorProfile)
    targetCount = math.max(0, tonumber(targetCount) or 0)
    if not character or targetCount <= 0 then return 0 end

    fitness = clamp(tonumber(fitness) or CPD.getFitness(character), 0, 10)
    local perTarget = tonumber(C.FITNESS_ARM_STRAIN_PER_TARGET[fitness]) or 0
    if doorProfile and doorProfile.garage == true then
        perTarget = tonumber(C.GARAGE_FITNESS_ARM_STRAIN_PER_TARGET[fitness]) or perTarget
    elseif doorProfile and doorProfile.doubleDoor == true then
        perTarget = tonumber(C.DOUBLE_DOOR_FITNESS_ARM_STRAIN_PER_TARGET[fitness]) or perTarget
    end

    local amount = perTarget * targetCount * getSandboxMuscleStrainMultiplier() * S.armStrainGainMultiplier()
    if doorProfile and doorProfile.garage == true then
        amount = amount * S.garageArmStrainMultiplier()
    end
    if amount <= 0 then return 0 end

    local values = {}
    local defs = getArmPartDefs()
    for i = 1, #defs do
        local def = defs[i]
        local part = getArmBodyPart(character, def.type)
        if part then
            local current = tonumber(safeCall(part, "getStiffness")) or 0
            local newValue = clamp(current + amount, 0, 100)
            safeCall(part, "setStiffness", newValue)
            values[def.name] = newValue
        end
    end

    if isServer and isServer() and sendServerCommand then
        sendServerCommand(character, "CyesPushDoors", "armStrainSync", values)
    end

    log("Arm strain fitness=" .. tostring(fitness) ..
        " targets=" .. tostring(targetCount) ..
        " profile=" .. tostring(doorProfile and doorProfile.kind or "standard") ..
        " added=" .. string.format("%.3f", amount) ..
        " maxNow=" .. string.format("%.3f", CPD.getArmStrain(character)))
    return amount
end

function CPD.isSupportedDoor(door)
    if not door then return false end
    if instanceof(door, "IsoDoor") then return true end
    if instanceof(door, "IsoThumpable") then
        local ok, isDoor = pcall(function() return door:isDoor() end)
        return ok and isDoor == true
    end
    return false
end

function CPD.isGarageDoor(door)
    if not door or not IsoDoor or not IsoDoor.getGarageDoorIndex then return false end
    local ok, index = pcall(IsoDoor.getGarageDoorIndex, door)
    return ok and index ~= nil and tonumber(index) ~= nil and tonumber(index) >= 0
end

function CPD.getGarageDoorParts(door)
    if not CPD.isGarageDoor(door) then
        return door and { door } or {}
    end

    local first = nil
    if IsoDoor and IsoDoor.getGarageDoorFirst then
        local ok, value = pcall(IsoDoor.getGarageDoorFirst, door)
        if ok then first = value end
    end
    first = first or door

    local result = {}
    local seen = {}
    local current = first
    for i = 1, 3 do
        if not current or seen[current] then break end
        result[#result + 1] = current
        seen[current] = true

        if IsoDoor and IsoDoor.getGarageDoorNext then
            local ok, value = pcall(IsoDoor.getGarageDoorNext, current)
            if ok then
                current = value
            else
                current = nil
            end
        else
            current = nil
        end
    end

    if #result == 0 then result[1] = door end
    return result
end

function CPD.getGarageDoorMaster(door)
    local parts = CPD.getGarageDoorParts(door)
    return parts[1] or door
end




function CPD.isDoubleDoor(door)
    if not door or CPD.isGarageDoor(door) or not IsoDoor or not IsoDoor.getDoubleDoorIndex then
        return false
    end
    local ok, index = pcall(IsoDoor.getDoubleDoorIndex, door)
    index = ok and tonumber(index) or nil
    return index ~= nil and index >= 0
end

function CPD.getDoubleDoorParts(door)
    if not CPD.isDoubleDoor(door) then
        return door and { door } or {}
    end

    local result = {}
    local seen = {}
    local function addPart(part)
        if not part or seen[part] or not CPD.isSupportedDoor(part) then return end
        seen[part] = true
        result[#result + 1] = part
    end

    addPart(door)

    
    
    
    if IsoDoor and IsoDoor.getDoubleDoorObject then
        for index = 0, 4 do
            local ok, part = pcall(IsoDoor.getDoubleDoorObject, door, index)
            if ok then addPart(part) end
        end
    end

    
    
    table.sort(result, function(a, b)
        local ai, bi = math.huge, math.huge
        if IsoDoor and IsoDoor.getDoubleDoorIndex then
            local oka, va = pcall(IsoDoor.getDoubleDoorIndex, a)
            local okb, vb = pcall(IsoDoor.getDoubleDoorIndex, b)
            if oka and tonumber(va) then ai = tonumber(va) end
            if okb and tonumber(vb) then bi = tonumber(vb) end
        end
        if ai ~= bi then return ai < bi end

        local asq = safeCall(a, "getSquare")
        local bsq = safeCall(b, "getSquare")
        if asq and bsq then
            if asq:getZ() ~= bsq:getZ() then return asq:getZ() < bsq:getZ() end
            if asq:getY() ~= bsq:getY() then return asq:getY() < bsq:getY() end
            if asq:getX() ~= bsq:getX() then return asq:getX() < bsq:getX() end
        end
        return (tonumber(safeCall(a, "getObjectIndex")) or 0) <
               (tonumber(safeCall(b, "getObjectIndex")) or 0)
    end)

    if #result == 0 then result[1] = door end
    return result
end

function CPD.getDoubleDoorMaster(door)
    local parts = CPD.getDoubleDoorParts(door)
    return parts[1] or door
end

function CPD.getLogicalDoorOpenState(door)
    if not door then return nil end

    if CPD.isDoubleDoor(door) then
        local parts = CPD.getDoubleDoorParts(door)
        local sawState = false
        for i = 1, #parts do
            local state = safeCall(parts[i], "IsOpen")
            if state ~= nil then
                sawState = true
                if state == true then return true end
            end
        end
        if sawState then return false end
    end

    return safeCall(door, "IsOpen")
end

function CPD.getDoorSpriteName(door)
    if not door then return nil end
    local name = safeCall(door, "getSpriteName")
    if name ~= nil then return tostring(name) end

    local sprite = safeCall(door, "getSprite")
    local spriteName = safeCall(sprite, "getName")
    if spriteName ~= nil then return tostring(spriteName) end
    return nil
end

function CPD.getDoorProfileKey(door)
    if not door then return "standard" end
    if CPD.isGarageDoor(door) then return "garage" end
    if CPD.isDoubleDoor(door) then return "doubleDoor" end

    local sliding = C.SPECIAL_SLIDING_DOOR_SPRITES or {}
    local profiles = C.DOOR_PROFILE_BY_SPRITE or {}

    local current = CPD.getDoorSpriteName(door)
    if current and sliding[current] == true then return "slidingGlass" end
    if current and profiles[current] then return profiles[current] end

    local openSprite = safeCall(door, "getOpenSprite")
    local openName = safeCall(openSprite, "getName")
    if openName then
        openName = tostring(openName)
        if sliding[openName] == true then return "slidingGlass" end
        if profiles[openName] then return profiles[openName] end
    end

    return "standard"
end

function CPD.isSlidingGlassDoor(door)
    return CPD.getDoorProfileKey(door) == "slidingGlass"
end

function CPD.getDoorImpactProfile(door, strength)
    local kind = CPD.getDoorProfileKey(door)

    if kind == "garage" then
        local damage = C.GARAGE_DOOR_ZOMBIE_DAMAGE[strength] or C.GARAGE_DOOR_ZOMBIE_DAMAGE[0]
        return {
            kind = "garage",
            garage = true,
            doubleDoor = false,
            sliding = false,
            maxZombies = nil,
            neverZombieKnockdown = false,
            neverPlayerKnockdown = false,
            forceZombieStun = false,
            zombieDamageMin = tonumber(damage.min) or 0,
            zombieDamageMax = tonumber(damage.max) or 0,
            playerDamageMult = tonumber(C.GARAGE_DOOR_PLAYER_DAMAGE_MULT) or 2.0,
            doorWearMult = tonumber(C.GARAGE_DOOR_WEAR_MULT) or 1.00,
            ignoreMaterialWear = true,
        }
    end

    if kind == "doubleDoor" then
        local damage = C.DOUBLE_DOOR_ZOMBIE_DAMAGE[strength] or C.DOUBLE_DOOR_ZOMBIE_DAMAGE[0]
        return {
            kind = "doubleDoor",
            garage = false,
            doubleDoor = true,
            sliding = false,
            maxZombies = nil,
            neverZombieKnockdown = false,
            neverPlayerKnockdown = false,
            forceZombieStun = false,
            zombieDamageMin = tonumber(damage.min) or 0,
            zombieDamageMax = tonumber(damage.max) or 0,
            maxZombieDamageFraction = tonumber(C.DOUBLE_DOOR_MAX_ZOMBIE_DAMAGE_FRACTION) or 0.85,
            playerDamageMult = tonumber(C.DOUBLE_DOOR_PLAYER_DAMAGE_MULT) or 0.75,
            doorWearMult = 1.00,
            ignoreMaterialWear = false,
        }
    end

    if kind == "slidingGlass" then
        local damage = C.SLIDING_DOOR_ZOMBIE_DAMAGE[strength] or C.SLIDING_DOOR_ZOMBIE_DAMAGE[0]
        return {
            kind = "slidingGlass",
            garage = false,
            doubleDoor = false,
            sliding = true,
            maxZombies = tonumber(C.SLIDING_DOOR_MAX_ZOMBIES[strength]) or 1,
            neverZombieKnockdown = true,
            neverPlayerKnockdown = true,
            forceZombieStun = true,
            zombieDamageMin = tonumber(damage.min) or 0,
            zombieDamageMax = tonumber(damage.max) or 0,
            playerDamageMult = tonumber(C.SLIDING_DOOR_PLAYER_DAMAGE_MULT) or 0.20,
            doorWearMult = tonumber(C.SLIDING_DOOR_WEAR_MULT) or 1.50,
            ignoreMaterialWear = true,
        }
    end

    local values = (C.DOOR_PROFILE_VALUES or {})[kind] or (C.DOOR_PROFILE_VALUES or {}).standard or {}
    return {
        kind = kind,
        garage = false,
        doubleDoor = false,
        sliding = false,
        maxZombies = nil,
        neverZombieKnockdown = false,
        neverPlayerKnockdown = false,
        forceZombieStun = false,
        zombieDamageMult = tonumber(values.zombieDamageMult) or 1.0,
        playerDamageMult = tonumber(values.playerDamageMult) or 1.0,
        doorWearMult = tonumber(values.doorWearMult) or 1.0,
        ignoreMaterialWear = values.ignoreMaterialWear == true,
    }
end

local function appendMaterialText(parts, value)
    if value ~= nil then
        parts[#parts + 1] = string.lower(tostring(value))
    end
end

function CPD.getDoorMaterial(door)
    local parts = {}
    appendMaterialText(parts, safeCall(door, "getSpriteName"))
    appendMaterialText(parts, safeCall(door, "getThumpSound"))
    appendMaterialText(parts, safeCall(door, "getBreakSound"))
    appendMaterialText(parts, safeCall(door, "getName"))

    local props = safeCall(door, "getProperties")
    if props then
        local val = props.Val
        if val then
            local ok1, material = pcall(val, props, "Material")
            if ok1 then appendMaterialText(parts, material) end
            local ok2, material2 = pcall(val, props, "Material2")
            if ok2 then appendMaterialText(parts, material2) end
        end
    end

    local text = table.concat(parts, " ")
    local metalHints = {
        "metal", "steel", "iron", "chain", "wire", "security",
        "prison", "industrial", "chainlink"
    }
    for i = 1, #metalHints do
        if string.find(text, metalHints[i], 1, true) then
            return "metal"
        end
    end
    return "wood"
end

function CPD.getDoorWorldKey(door)
    local keyedDoor = door
    if CPD.isGarageDoor(door) then
        keyedDoor = CPD.getGarageDoorMaster(door) or door
    elseif CPD.isDoubleDoor(door) then
        keyedDoor = CPD.getDoubleDoorMaster(door) or door
    end

    local sq = keyedDoor and keyedDoor:getSquare() or nil
    if not sq then return "unknown" end
    return sq:getX() .. ":" .. sq:getY() .. ":" .. sq:getZ() .. ":" .. tostring(keyedDoor:getObjectIndex())
end

function CPD.getPlayerDoorDistanceSq(player, door)
    if not player or not door then return math.huge end
    local sq = door:getSquare()
    if not sq then return math.huge end
    local dx = player:getX() - (sq:getX() + 0.5)
    local dy = player:getY() - (sq:getY() + 0.5)
    return (dx * dx) + (dy * dy)
end

local function nowMs()
    if getTimestampMs then return getTimestampMs() end
    return math.floor(os.time() * 1000)
end

function CPD.isDuplicateImpact(opener, door)
    local key = CPD.getDoorWorldKey(door)
    local now = nowMs()
    local last = CPD._recentImpacts[key]
    if last and (now - last) < C.IMPACT_DEDUPE_MS then
        return true
    end
    CPD._recentImpacts[key] = now

    CPD._recentImpactPruneAt = tonumber(CPD._recentImpactPruneAt) or 0
    if (now - CPD._recentImpactPruneAt) >= 60000 then
        CPD._recentImpactPruneAt = now
        for oldKey, oldTime in pairs(CPD._recentImpacts) do
            if not oldTime or (now - oldTime) > 10000 then
                CPD._recentImpacts[oldKey] = nil
            end
        end
    end

    return false
end

function CPD.getDoorSideSquares(door)
    if not door then return nil, nil end
    local same = safeCall(door, "getSquare")
    if not same then return nil, nil end

    local opposite = safeCall(door, "getOppositeSquare")
    if opposite then return same, opposite end

    local north = safeCall(door, "getNorth")
    if north == nil then return same, nil end

    local x, y, z = same:getX(), same:getY(), same:getZ()
    if north == true then
        opposite = getCell():getGridSquare(x, y - 1, z)
    else
        opposite = getCell():getGridSquare(x - 1, y, z)
    end
    return same, opposite
end

local function squareDistanceToCharacter(square, character)
    if not square or not character then return math.huge end
    local dx = character:getX() - (square:getX() + 0.5)
    local dy = character:getY() - (square:getY() + 0.5)
    return (dx * dx) + (dy * dy)
end

function CPD.getImpactSquare(opener, door)
    if not opener or not door then return nil end

    local same, opposite = CPD.getDoorSideSquares(door)
    local openerSq = safeCall(opener, "getCurrentSquare")

    if openerSq and same and openerSq == same then
        return opposite
    end
    if openerSq and opposite and openerSq == opposite then
        return same
    end

    if same and opposite then
        if squareDistanceToCharacter(same, opener) <= squareDistanceToCharacter(opposite, opener) then
            return opposite
        end
        return same
    end

    return safeCall(door, "getOtherSideOfDoor", opener)
end

local function entrySquaresSameCoordinates(a, b)
    if not a or not b then return false end
    return a:getX() == b:getX() and a:getY() == b:getY() and a:getZ() == b:getZ()
end

local function entrySquareKey(square)
    if not square then return nil end
    return square:getX() .. ":" .. square:getY() .. ":" .. square:getZ()
end

local function appendUniqueEntrySquare(list, seen, square)
    local key = entrySquareKey(square)
    if not key or seen[key] then return end
    seen[key] = true
    list[#list + 1] = square
end

local function getEntryParts(door)
    if CPD.isGarageDoor(door) then
        return CPD.getGarageDoorParts(door)
    end
    if CPD.isDoubleDoor(door) then
        return CPD.getDoubleDoorParts(door)
    end
    return door and { door } or {}
end

function CPD.getEntrySideBands(door)
    local parts = getEntryParts(door)
    if #parts == 0 then return {}, {} end

    if #parts == 1 and not CPD.isGarageDoor(door) and not CPD.isDoubleDoor(door) then
        local same, opposite = CPD.getDoorSideSquares(parts[1])
        return same and { same } or {}, opposite and { opposite } or {}
    end

    local representative = door
    local sameRef, oppositeRef = CPD.getDoorSideSquares(representative)
    if not sameRef or not oppositeRef then
        for i = 1, #parts do
            local same, opposite = CPD.getDoorSideSquares(parts[i])
            if same and opposite then
                representative = parts[i]
                sameRef, oppositeRef = same, opposite
                break
            end
        end
    end
    if not sameRef or not oppositeRef then return {}, {} end

    local rawDx = oppositeRef:getX() - sameRef:getX()
    local rawDy = oppositeRef:getY() - sameRef:getY()
    if rawDx == 0 and rawDy == 0 then return {}, {} end

    local offsetX, offsetY = 0, 0
    if math.abs(rawDx) >= math.abs(rawDy) then
        offsetX = rawDx >= 0 and 1 or -1
    else
        offsetY = rawDy >= 0 and 1 or -1
    end

    local minT, maxT, z = nil, nil, sameRef:getZ()
    for i = 1, #parts do
        local square = safeCall(parts[i], "getSquare")
        if square and square:getZ() == z then
            local tangent = offsetX ~= 0 and square:getY() or square:getX()
            minT = minT and math.min(minT, tangent) or tangent
            maxT = maxT and math.max(maxT, tangent) or tangent
        end
    end

    if minT == nil or maxT == nil then return {}, {} end

    local sameBand, oppositeBand = {}, {}
    local sameSeen, oppositeSeen = {}, {}
    local cell = getCell and getCell() or nil
    if not cell then return {}, {} end

    for tangent = minT, maxT do
        local sameSquare, oppositeSquare = nil, nil
        if offsetX ~= 0 then
            sameSquare = cell:getGridSquare(sameRef:getX(), tangent, z)
            oppositeSquare = cell:getGridSquare(sameRef:getX() + offsetX, tangent, z)
        else
            sameSquare = cell:getGridSquare(tangent, sameRef:getY(), z)
            oppositeSquare = cell:getGridSquare(tangent, sameRef:getY() + offsetY, z)
        end
        appendUniqueEntrySquare(sameBand, sameSeen, sameSquare)
        appendUniqueEntrySquare(oppositeBand, oppositeSeen, oppositeSquare)
    end

    if #sameBand == 0 or #oppositeBand == 0 then
        return {}, {}
    end

    return sameBand, oppositeBand
end

local function bandContainsSquare(band, square)
    if not square then return false end
    for i = 1, #band do
        if band[i] == square or entrySquaresSameCoordinates(band[i], square) then
            return true
        end
    end
    return false
end

local function bandDistanceSqToCharacter(band, character)
    local best = math.huge
    if not character then return best end
    for i = 1, #band do
        local distance = squareDistanceToCharacter(band[i], character)
        if distance < best then best = distance end
    end
    return best
end

local function nearestSquareInBand(band, character)
    local best, bestDistance = nil, math.huge
    for i = 1, #band do
        local distance = squareDistanceToCharacter(band[i], character)
        if distance < bestDistance then
            bestDistance = distance
            best = band[i]
        end
    end
    return best
end

local function getCharacterFacingVector(character)
    if not character then return nil, nil end

    local forward = safeCall(character, "getForwardDirection")
    if forward then
        local fx = tonumber(safeCall(forward, "getX"))
        local fy = tonumber(safeCall(forward, "getY"))
        if fx == nil or fy == nil then
            local okX, rawX = pcall(function() return forward.x end)
            local okY, rawY = pcall(function() return forward.y end)
            if fx == nil and okX then fx = tonumber(rawX) end
            if fy == nil and okY then fy = tonumber(rawY) end
        end
        if fx and fy and ((fx * fx) + (fy * fy)) > 0.0001 then
            local length = math.sqrt((fx * fx) + (fy * fy))
            return fx / length, fy / length
        end
    end

    local dir = safeCall(character, "getDir")
    if dir == nil then return nil, nil end
    local text = string.upper(tostring(dir))
    local token = text:match("([NSEW][NSEW]?)$") or text
    local diagonal = 0.70710678118
    local vectors = {
        N = { 0, -1 }, NE = { diagonal, -diagonal },
        E = { 1, 0 }, SE = { diagonal, diagonal },
        S = { 0, 1 }, SW = { -diagonal, diagonal },
        W = { -1, 0 }, NW = { -diagonal, -diagonal },
    }
    local vector = vectors[token]
    if not vector then return nil, nil end
    return vector[1], vector[2]
end

local function bandCenter(band)
    if not band or #band == 0 then return nil, nil end
    local x, y = 0, 0
    for i = 1, #band do
        x = x + band[i]:getX() + 0.5
        y = y + band[i]:getY() + 0.5
    end
    return x / #band, y / #band
end

local function closestEntryPlanePoint(character, sameBand, oppositeBand)
    if not character or not sameBand or not oppositeBand then return nil, nil, math.huge end
    local count = math.min(#sameBand, #oppositeBand)
    local bestX, bestY, bestDistance = nil, nil, math.huge

    for i = 1, count do
        local x = ((sameBand[i]:getX() + 0.5) + (oppositeBand[i]:getX() + 0.5)) * 0.5
        local y = ((sameBand[i]:getY() + 0.5) + (oppositeBand[i]:getY() + 0.5)) * 0.5
        local dx = character:getX() - x
        local dy = character:getY() - y
        local distance = (dx * dx) + (dy * dy)
        if distance < bestDistance then
            bestDistance = distance
            bestX, bestY = x, y
        end
    end

    return bestX, bestY, bestDistance
end

function CPD.getPlayerEntrySide(opener, door)
    if not opener or not door then return nil, "missing" end
    local sameBand, oppositeBand = CPD.getEntrySideBands(door)
    if #sameBand == 0 or #oppositeBand == 0 then return nil, "missing-bands" end

    local openerSquare = safeCall(opener, "getCurrentSquare")
    local inSame = bandContainsSquare(sameBand, openerSquare)
    local inOpposite = bandContainsSquare(oppositeBand, openerSquare)
    if inSame ~= inOpposite then
        return inSame and "same" or "opposite", nil, sameBand, oppositeBand
    end

    local sameX, sameY = bandCenter(sameBand)
    local oppositeX, oppositeY = bandCenter(oppositeBand)
    if not sameX or not oppositeX then
        return nil, "missing-center", sameBand, oppositeBand
    end

    local nx = oppositeX - sameX
    local ny = oppositeY - sameY
    local lengthSq = (nx * nx) + (ny * ny)
    if lengthSq <= 0.0001 then
        return nil, "ambiguous-side", sameBand, oppositeBand
    end
    local length = math.sqrt(lengthSq)
    nx, ny = nx / length, ny / length

    local planeX = (sameX + oppositeX) * 0.5
    local planeY = (sameY + oppositeY) * 0.5
    local signed = ((opener:getX() - planeX) * nx) + ((opener:getY() - planeY) * ny)
    local epsilon = 0.05
    if math.abs(signed) <= epsilon then
        return nil, "ambiguous-side", sameBand, oppositeBand
    end

    return signed < 0 and "same" or "opposite", nil, sameBand, oppositeBand
end

function CPD.getInteractionImpactContext(opener, door)
    local playerSide, reason, sameBand, oppositeBand = CPD.getPlayerEntrySide(opener, door)
    if not playerSide then return nil, reason or "no-player-side" end

    local planeX, planeY, planeDistanceSq = closestEntryPlanePoint(opener, sameBand, oppositeBand)
    if not planeX or not planeY then return nil, "missing-entry-plane" end

    local maxDistance = tonumber(C.IMPACT_INTERACTION_MAX_DISTANCE) or 1.75
    if planeDistanceSq > (maxDistance * maxDistance) then
        return nil, "too-far"
    end

    local facingX, facingY = getCharacterFacingVector(opener)
    if facingX == nil or facingY == nil then
        return nil, "facing-unavailable"
    end

    local sameX, sameY = bandCenter(sameBand)
    local oppositeX, oppositeY = bandCenter(oppositeBand)
    if not sameX or not oppositeX then return nil, "missing-center" end

    local nx = oppositeX - sameX
    local ny = oppositeY - sameY
    local normalLengthSq = (nx * nx) + (ny * ny)
    if normalLengthSq <= 0.0001 then return nil, "ambiguous-facing" end
    local normalLength = math.sqrt(normalLengthSq)
    nx, ny = nx / normalLength, ny / normalLength

    local towardEntryX = playerSide == "same" and nx or -nx
    local towardEntryY = playerSide == "same" and ny or -ny
    local facingDot = (facingX * towardEntryX) + (facingY * towardEntryY)
    local minDot = tonumber(C.IMPACT_INTERACTION_FACING_DOT_MIN)
    if minDot == nil then minDot = -0.01 end
    if facingDot < minDot then
        return nil, "not-facing-entry"
    end

    local impactSide = playerSide == "same" and "opposite" or "same"
    local playerBand = playerSide == "same" and sameBand or oppositeBand
    local impactBand = impactSide == "same" and sameBand or oppositeBand
    local anchor = nearestSquareInBand(impactBand, opener)
    if not anchor then return nil, "missing-impact-anchor" end

    return {
        playerSide = playerSide,
        impactSide = impactSide,
        playerBand = playerBand,
        impactBand = impactBand,
        anchor = anchor,
        entryDistanceSq = planeDistanceSq,
        facingDot = facingDot,
    }, nil
end

function CPD.getImpactBandFromPreferred(door, preferredImpactSquare)
    if not door or not preferredImpactSquare then return nil, nil end
    local sameBand, oppositeBand = CPD.getEntrySideBands(door)
    if bandContainsSquare(sameBand, preferredImpactSquare) then
        return sameBand, "same"
    end
    if bandContainsSquare(oppositeBand, preferredImpactSquare) then
        return oppositeBand, "opposite"
    end
    return nil, nil
end

function CPD.isEntrySideSquare(door, square)
    local band = CPD.getImpactBandFromPreferred(door, square)
    return band ~= nil
end

function CPD.getGarageImpactSquares(opener, door, preferredImpactSquare)
    local band = CPD.getImpactBandFromPreferred(door, preferredImpactSquare)
    if band then return band end
    local context = CPD.getInteractionImpactContext(opener, door)
    return context and context.impactBand or {}
end

function CPD.getDoubleDoorImpactSquares(opener, door, preferredImpactSquare)
    local band, selectedSide = CPD.getImpactBandFromPreferred(door, preferredImpactSquare)
    if not band then
        local context = CPD.getInteractionImpactContext(opener, door)
        if context then
            band = context.impactBand
            selectedSide = context.impactSide
        end
    end
    band = band or {}

    mpDebug("DOUBLE_DOOR_BAND",
        "key=" .. tostring(CPD.getDoorWorldKey(door)) ..
        " parts=" .. tostring(#CPD.getDoubleDoorParts(door)) ..
        " side=" .. tostring(selectedSide or "none") ..
        " selectedBand=" .. tostring(#band))
    return band
end

function CPD.getDoubleDoorImpactPart(door, impactSquare)
    if not door or not impactSquare or not CPD.isDoubleDoor(door) then return door end
    local parts = CPD.getDoubleDoorParts(door)
    local best = nil
    local bestDistance = math.huge
    for i = 1, #parts do
        local part = parts[i]
        local sq = safeCall(part, "getSquare")
        if sq then
            local dx = (sq:getX() + 0.5) - (impactSquare:getX() + 0.5)
            local dy = (sq:getY() + 0.5) - (impactSquare:getY() + 0.5)
            local d = (dx * dx) + (dy * dy)
            if d < bestDistance then
                bestDistance = d
                best = part
            end
        elseif not best then
            best = part
        end
    end
    return best or CPD.getDoubleDoorMaster(door) or door
end

function CPD.collectTargetsFromSquares(squares, opener)
    local targets = {}
    local squareByTarget = {}
    local seen = {}

    for i = 1, #squares do
        local square = squares[i]
        local found = CPD.collectTargets(square, opener)
        for j = 1, #found do
            local target = found[j]
            if not seen[target] then
                seen[target] = true
                targets[#targets + 1] = target
                squareByTarget[target] = square
            end
        end
    end

    return targets, squareByTarget
end


local function sameSquareCoordinates(a, b)
    if not a or not b then return false end
    return safeCall(a, "getX") == safeCall(b, "getX") and
           safeCall(a, "getY") == safeCall(b, "getY") and
           safeCall(a, "getZ") == safeCall(b, "getZ")
end

local function objectOccupiesSquare(object, square)
    if not object or not square then return false end

    
    
    
    local objectSquare = safeCall(object, "getCurrentSquare") or safeCall(object, "getSquare")
    if objectSquare and sameSquareCoordinates(objectSquare, square) then
        return true
    end

    
    
    
    local ox = tonumber(safeCall(object, "getX"))
    local oy = tonumber(safeCall(object, "getY"))
    local oz = tonumber(safeCall(object, "getZ"))
    local sx = tonumber(safeCall(square, "getX"))
    local sy = tonumber(safeCall(square, "getY"))
    local sz = tonumber(safeCall(square, "getZ"))
    if not ox or not oy or not oz or not sx or not sy or not sz then return false end

    return math.floor(ox) == sx and math.floor(oy) == sy and math.floor(oz) == sz
end

local function addTargetUnique(result, seen, object, opener)
    if not object or object == opener or seen[object] then return false end
    if instanceof(object, "IsoZombie") or instanceof(object, "IsoPlayer") then
        seen[object] = true
        result[#result + 1] = object
        return true
    end
    return false
end

local function scanJavaListForSquare(list, square, opener, result, seen)
    local inspected = 0
    local matched = 0
    if not list then return inspected, matched end

    local okSize, size = pcall(function() return list:size() end)
    if not okSize or not size then return inspected, matched end

    inspected = tonumber(size) or 0
    for i = 0, inspected - 1 do
        local okGet, object = pcall(function() return list:get(i) end)
        if okGet and object and object ~= opener and objectOccupiesSquare(object, square) then
            if addTargetUnique(result, seen, object, opener) then
                matched = matched + 1
            end
        end
    end

    return inspected, matched
end

local function debugNearestServerZombies(square, zombieList)
    if not square or not zombieList then return end

    local sx = tonumber(safeCall(square, "getX"))
    local sy = tonumber(safeCall(square, "getY"))
    local sz = tonumber(safeCall(square, "getZ"))
    if not sx or not sy or not sz then return end

    local okSize, size = pcall(function() return zombieList:size() end)
    if not okSize or not size then return end

    local nearby = {}
    for i = 0, (tonumber(size) or 0) - 1 do
        local okGet, zombie = pcall(function() return zombieList:get(i) end)
        if okGet and zombie then
            local zx = tonumber(safeCall(zombie, "getX"))
            local zy = tonumber(safeCall(zombie, "getY"))
            local zz = tonumber(safeCall(zombie, "getZ"))
            if zx and zy and zz and math.floor(zz) == sz then
                local dx = zx - (sx + 0.5)
                local dy = zy - (sy + 0.5)
                local d2 = (dx * dx) + (dy * dy)
                if d2 <= 6.25 then
                    nearby[#nearby + 1] = {
                        d2 = d2,
                        text = tostring(safeCall(zombie, "getOnlineID")) .. "@" ..
                            string.format("%.2f,%.2f,%.2f", zx, zy, zz),
                    }
                end
            end
        end
    end

    table.sort(nearby, function(a, b) return a.d2 < b.d2 end)
    local parts = {}
    for i = 1, math.min(#nearby, 5) do parts[#parts + 1] = nearby[i].text end
    mpDebug("TARGET_NEAR",
        "square=" .. sx .. "," .. sy .. "," .. sz ..
        " nearby=" .. (#parts > 0 and table.concat(parts, " | ") or "none"))
end

function CPD.collectTargets(square, opener)
    local result = {}
    local seen = {}
    if not square then return result end

    local movingCount = 0
    local moving = safeCall(square, "getMovingObjects")
    if moving then
        local okSize, size = pcall(function() return moving:size() end)
        if okSize and size then
            movingCount = tonumber(size) or 0
            for i = 0, movingCount - 1 do
                local okGet, object = pcall(function() return moving:get(i) end)
                if okGet and object and object ~= opener then
                    addTargetUnique(result, seen, object, opener)
                end
            end
        end
    end

    
    
    
    
    if isServer and isServer() then
        local zombieInspected, zombieMatched = 0, 0
        local playerInspected, playerMatched = 0, 0
        local cell = getCell and getCell() or nil
        local zombieList = cell and safeCall(cell, "getZombieList") or nil

        zombieInspected, zombieMatched = scanJavaListForSquare(
            zombieList, square, opener, result, seen
        )

        local players = nil
        if getOnlinePlayers then
            local okPlayers, value = pcall(getOnlinePlayers)
            if okPlayers then players = value end
        end
        playerInspected, playerMatched = scanJavaListForSquare(
            players, square, opener, result, seen
        )

        mpDebug("TARGET_SCAN",
            "square=" .. tostring(safeCall(square, "getX")) .. "," ..
                tostring(safeCall(square, "getY")) .. "," ..
                tostring(safeCall(square, "getZ")) ..
            " moving=" .. tostring(movingCount) ..
            " zombieList=" .. tostring(zombieInspected) ..
            " zombieMatched=" .. tostring(zombieMatched) ..
            " playerList=" .. tostring(playerInspected) ..
            " playerMatched=" .. tostring(playerMatched) ..
            " total=" .. tostring(#result))

        if #result == 0 then
            debugNearestServerZombies(square, zombieList)
        end
    end

    return result
end

local function targetScore(square, opener)
    local targets = CPD.collectTargets(square, opener)
    local zombies, players = 0, 0
    for i = 1, #targets do
        local target = targets[i]
        if instanceof(target, "IsoZombie") and target:isAlive() then
            zombies = zombies + 1
        elseif instanceof(target, "IsoPlayer") and target:isAlive() then
            players = players + 1
        end
    end

    return (zombies * 100) + (players * 10) + #targets, zombies, players
end

function CPD.isDoorSideSquare(door, square)
    if not door or not square then return false end
    local same, opposite = CPD.getDoorSideSquares(door)
    if square == same or square == opposite then return true end
    if same and square:getX() == same:getX() and square:getY() == same:getY() and square:getZ() == same:getZ() then return true end
    if opposite and square:getX() == opposite:getX() and square:getY() == opposite:getY() and square:getZ() == opposite:getZ() then return true end
    return false
end

function CPD.getTargetAwareImpactSquare(opener, door)
    return CPD.getImpactSquare(opener, door)
end

function CPD.findPreferredImpactSquare(args, door)
    if not args or args.impactX == nil or args.impactY == nil or args.impactZ == nil then return nil end
    local square = getCell():getGridSquare(tonumber(args.impactX), tonumber(args.impactY), tonumber(args.impactZ))
    if square and CPD.isEntrySideSquare(door, square) then return square end
    return nil
end

function CPD.notifyCombatTextDoorHit(opener, zombie, oldHealth, newHealth)
    if not opener or not zombie then return end
    oldHealth = tonumber(oldHealth)
    newHealth = tonumber(newHealth)
    if not oldHealth or not newHealth or newHealth >= oldHealth then return end

    if isServer and isServer() and sendServerCommand then
        local sq = zombie:getCurrentSquare()
        if not sq then return end
        pcall(function()
            sendServerCommand(opener, "CyesPushDoors", "combatTextHit", {
                id = safeCall(zombie, "getOnlineID"),
                x = sq:getX(), y = sq:getY(), z = sq:getZ(),
                oldHealth = oldHealth,
                newHealth = newHealth,
            })
        end)
        return
    end

    if CPD.onCombatTextDoorHit then
        pcall(CPD.onCombatTextDoorHit, zombie, oldHealth, newHealth)
    end
end

local function notifyZombieClients(zombie, newHealth, knockedDown, staggered, crawlerStunned, slidingAnimated, hitAnimation, staggerAnimation)
    if not isServer or not isServer() or not sendServerCommand then return end

    local zombieId = tonumber(safeCall(zombie, "getOnlineID"))
    if zombieId == nil or zombieId < 0 then
        mpDebug("SERVER_SYNC_SKIP", "zombieImpact not broadcast because zombie has invalid online id=" .. tostring(zombieId))
        return
    end
    local sq = safeCall(zombie, "getCurrentSquare")
    if not sq then
        mpDebug("SERVER_SYNC_SKIP", "zombieImpact not broadcast because zombie has no current square; zombieId=" .. tostring(zombieId))
        return
    end

    local stamp = getTimestampMs and getTimestampMs() or math.floor(os.time() * 1000)
    local payload = {
        id = zombieId,
        x = sq:getX(), y = sq:getY(), z = sq:getZ(),
        health = tonumber(newHealth),
        knockedDown = knockedDown == true,
        staggered = staggered == true,
        crawlerStunned = crawlerStunned == true,
        slidingAnimated = slidingAnimated == true,
        hitAnimation = hitAnimation,
        staggerAnimation = staggerAnimation,
        syncToken = tostring(zombieId) .. ":" .. tostring(stamp),
    }

    mpDebug("SERVER_SYNC_BROADCAST",
        "zombieImpact zombieId=" .. tostring(payload.id) ..
        " hp=" .. tostring(payload.health) ..
        " knock=" .. tostring(payload.knockedDown) ..
        " stagger=" .. tostring(payload.staggered) ..
        " staggerAnim=" .. tostring(payload.staggerAnimation) ..
        " token=" .. tostring(payload.syncToken))

    local ok, err = pcall(function()
        
        
        sendServerCommand("CyesPushDoors", "zombieImpact", payload)
    end)
    if ok then
        mpDebug("SERVER_SYNC_BROADCAST_OK", "zombieId=" .. tostring(payload.id) .. " token=" .. tostring(payload.syncToken))
    else
        mpDebug("SERVER_SYNC_BROADCAST_FAIL", "zombieId=" .. tostring(payload.id) .. " error=" .. tostring(err))
    end
end

local function getCapacityCount(capacityTable, strength, zombieCount, multiplier)
    zombieCount = math.max(0, tonumber(zombieCount) or 0)
    if zombieCount <= 0 then return 0 end

    local cap = capacityTable[strength] or capacityTable[0]
    multiplier = tonumber(multiplier) or 1.0

    if cap and cap.all == true then
        if multiplier >= 1.0 then return zombieCount end
        return math.min(zombieCount, math.max(1, math.floor((zombieCount * multiplier) + 0.5)))
    end

    local minCount = cap and tonumber(cap.min) or 0
    local maxCount = cap and tonumber(cap.max) or minCount
    if maxCount <= 0 then return 0 end

    local base = randomIntInclusive(minCount, maxCount)
    local scaled = math.floor((base * multiplier) + 0.5)
    if base > 0 and multiplier > 0 and scaled < 1 then scaled = 1 end
    return math.min(zombieCount, math.max(0, scaled))
end

function CPD.getZombieAffectedCount(strength, zombieCount)
    return getCapacityCount(C.AFFECTED_CAPACITY, strength, zombieCount, S.zombiesAffectedMultiplier())
end

function CPD.getDoubleDoorAffectedCount(strength, zombieCount)
    return getCapacityCount(
        C.DOUBLE_DOOR_AFFECTED_CAPACITY,
        strength,
        zombieCount,
        S.zombiesAffectedMultiplier()
    )
end

function CPD.getZombieKnockdownCount(strength, zombieCount)
    return getCapacityCount(C.KNOCKDOWN_CAPACITY, strength, zombieCount, 1.0)
end

function CPD.getDoubleDoorKnockdownCount(strength, zombieCount)
    return getCapacityCount(C.DOUBLE_DOOR_KNOCKDOWN_CAPACITY, strength, zombieCount, 1.0)
end

function CPD.limitZombieTargets(zombies, impactSquare, count)
    count = math.max(0, math.floor(tonumber(count) or 0))
    if count <= 0 then return {} end
    if count >= #zombies then return zombies end

    local cx = impactSquare and (impactSquare:getX() + 0.5) or 0
    local cy = impactSquare and (impactSquare:getY() + 0.5) or 0
    local sorted = {}
    for i = 1, #zombies do
        sorted[i] = zombies[i]
    end

    table.sort(sorted, function(a, b)
        local adx = a:getX() - cx
        local ady = a:getY() - cy
        local bdx = b:getX() - cx
        local bdy = b:getY() - cy
        local da = (adx * adx) + (ady * ady)
        local db = (bdx * bdx) + (bdy * bdy)
        if da == db then
            local aid = tonumber(safeCall(a, "getOnlineID")) or 0
            local bid = tonumber(safeCall(b, "getOnlineID")) or 0
            return aid < bid
        end
        return da < db
    end)

    local result = {}
    for i = 1, math.min(count, #sorted) do
        result[#result + 1] = sorted[i]
    end
    return result
end

function CPD.prepareZombieHealth(zombie)
    if not zombie or not zombie:isAlive() then return nil end

    local health = tonumber(safeCall(zombie, "getHealth"))
    local firstUpdate = safeCall(zombie, "isFirstUpdate") == true
    local invalid = health == nil or health ~= health or health <= 0

    if invalid then
        log("Zombie health invalid; impact skipped health=" .. tostring(health) .. " firstUpdate=" .. tostring(firstUpdate))
        return nil
    end

    if firstUpdate then
        log("Zombie health pre-init health=" .. tostring(health) .. " firstUpdate=" .. tostring(firstUpdate))
        safeCall(zombie, "DoZombieStats")
        health = tonumber(safeCall(zombie, "getHealth"))
        if health == nil or health ~= health or health <= 0 then
            log("Zombie health invalid after init; impact skipped health=" .. tostring(health))
            return nil
        end
    end

    return health
end

function CPD.queueZombieDamageVerification(opener, zombie, expectedHealth, lethal)
    if not zombie then return end
    local expected = math.max(0, tonumber(expectedHealth) or 0)
    CPD._pendingZombieDamage[zombie] = {
        opener = opener,
        expectedHealth = expected,
        lethal = lethal == true,
        ticks = C.ZOMBIE_DAMAGE_VERIFY_TICKS,
    }

    if C.DEBUG == true and isServer and isServer() then
        local now = getTimestampMs and getTimestampMs() or math.floor(os.time() * 1000)
        CPD._pendingZombieNetworkVerify[zombie] = {
            expectedHealth = expected,
            lethal = lethal == true,
            verifyAt = now + 750,
        }
    end
end

function CPD.updatePendingZombieDamage()
    for zombie, pending in pairs(CPD._pendingZombieDamage) do
        local remove = false
        if not zombie or not pending then
            remove = true
        elseif not zombie:isAlive() then
            remove = true
        else
            local current = tonumber(safeCall(zombie, "getHealth"))
            if pending.lethal then

                if current == nil or current > 0 then
                    safeCall(zombie, "setAttackedBy", pending.opener)
                    safeCall(zombie, "setHealth", 0)

                    if pending.opener then
                        pcall(function() zombie:Kill(pending.opener, false) end)
                    end
                    log("Reasserted lethal door damage current=" .. tostring(current))
                end
            elseif current ~= nil and current == current and current > (pending.expectedHealth + C.ZOMBIE_HEALTH_EPSILON) then

                if safeCall(zombie, "isFirstUpdate") == true then
                    safeCall(zombie, "DoZombieStats")
                    current = tonumber(safeCall(zombie, "getHealth")) or current
                end
                if current > (pending.expectedHealth + C.ZOMBIE_HEALTH_EPSILON) then
                    safeCall(zombie, "setHealth", pending.expectedHealth)
                    log("Reapplied door damage health=" .. tostring(current) .. "->" .. tostring(pending.expectedHealth))
                end
            end

            pending.ticks = (pending.ticks or 1) - 1
            if pending.ticks <= 0 then remove = true end
        end

        if remove then CPD._pendingZombieDamage[zombie] = nil end
    end

    if C.DEBUG == true and isServer and isServer() then
        local now = getTimestampMs and getTimestampMs() or math.floor(os.time() * 1000)
        for zombie, pending in pairs(CPD._pendingZombieNetworkVerify) do
            if not zombie or not pending then
                CPD._pendingZombieNetworkVerify[zombie] = nil
            elseif now >= (pending.verifyAt or 0) then
                local actual = tonumber(safeCall(zombie, "getHealth"))
                mpDebug("SERVER_VERIFY_750MS",
                    "zombieId=" .. tostring(safeCall(zombie, "getOnlineID")) ..
                    " expected=" .. tostring(pending.expectedHealth) ..
                    " actual=" .. tostring(actual) ..
                    " alive=" .. tostring(safeCall(zombie, "isAlive")))
                CPD._pendingZombieNetworkVerify[zombie] = nil
            end
        end
    end
end

function CPD.applyImpactDirection(target, door, impactSquare, strength)
    if not target or not door then return end
    local same, opposite = CPD.getDoorSideSquares(door)
    local cx, cy
    if same and opposite then
        cx = ((same:getX() + 0.5) + (opposite:getX() + 0.5)) * 0.5
        cy = ((same:getY() + 0.5) + (opposite:getY() + 0.5)) * 0.5
    else
        local dsq = door:getSquare()
        if not dsq then return end
        cx, cy = dsq:getX() + 0.5, dsq:getY() + 0.5
    end

    local tx = target:getX()
    local ty = target:getY()
    local dx, dy = tx - cx, ty - cy
    local len = math.sqrt((dx * dx) + (dy * dy))
    if len < 0.001 and impactSquare then
        dx = (impactSquare:getX() + 0.5) - cx
        dy = (impactSquare:getY() + 0.5) - cy
        len = math.sqrt((dx * dx) + (dy * dy))
    end
    if len < 0.001 then return end

    dx, dy = dx / len, dy / len
    if Vector2 and Vector2.new then
        local ok, vec = pcall(Vector2.new, dx, dy)
        if ok and vec then safeCall(target, "setHitDir", vec) end
    end
    safeCall(target, "setHitForce", 0.20 + (0.045 * (tonumber(strength) or 0)))
end

local DOOR_STAGGER_REACTION_GROUP = "DoorNormalHit"

function CPD.selectDoorStaggerReaction(requestedReaction)
    local definition = CPD.selectZombieReaction(DOOR_STAGGER_REACTION_GROUP, requestedReaction)
    if not definition then return nil end
    return definition.reaction or definition.id
end

function CPD.playDoorStaggerReaction(zombie, requestedReaction)
    if not zombie or not safeCall(zombie, "isAlive") then return false end

    local ok, selected, selectedId, stage = CPD.playZombieReaction(
        zombie,
        DOOR_STAGGER_REACTION_GROUP,
        requestedReaction
    )

    if not ok then
        log("Door stagger hit reaction failed selected=" .. tostring(selected) .. " stage=" .. tostring(stage or "router"))
        return false, selected
    end

    log("Door stagger hit reaction=" .. tostring(selected) .. " method=setHitReaction+wasHit")
    return true, selected, selectedId
end

function CPD.selectDoorStaggerAnimation(requestedAnimation)
    return CPD.selectDoorStaggerReaction(requestedAnimation)
end

function CPD.playDoorStaggerAnimation(zombie, requestedAnimation)
    return CPD.playDoorStaggerReaction(zombie, requestedAnimation)
end

local SLIDING_STANDING_REACTION_GROUP = "SlidingDoorStandingHit"
local SLIDING_CRAWLER_REACTION_GROUP = "SlidingDoorCrawlerHit"

local function slidingReactionGroup(zombie)
    local crawler = safeCall(zombie, "isCrawling") == true
    return crawler and SLIDING_CRAWLER_REACTION_GROUP or SLIDING_STANDING_REACTION_GROUP
end

function CPD.selectSlidingDoorReaction(zombie, requestedReaction)
    local groupId = slidingReactionGroup(zombie)
    local definition = CPD.selectZombieReaction(groupId, requestedReaction)

    if not definition and requestedReaction ~= nil and CPD.findZombieReaction then
        definition = CPD.findZombieReaction(requestedReaction)
    end

    return definition
end

function CPD.playSlidingDoorReaction(zombie, requestedReaction)
    if not zombie or not safeCall(zombie, "isAlive") then return false end

    local definition = CPD.selectSlidingDoorReaction(zombie, requestedReaction)
    if not definition then return false, requestedReaction end

    local ok, reaction, selectedId, stage = CPD.playZombieReaction(zombie, definition.id)
    local selectedClip = definition.observedAnimation or reaction or definition.id

    if not ok then
        log("Sliding-door hit reaction failed selected=" .. tostring(selectedClip) ..
            " reaction=" .. tostring(reaction) .. " stage=" .. tostring(stage or "router"))
        return false, selectedClip
    end

    log("Sliding-door hit reaction=" .. tostring(reaction) .. " selected=" .. tostring(selectedClip))
    return true, selectedClip, selectedId
end

function CPD.selectSlidingDoorAnimation(zombie, requestedAnimation)
    local definition = CPD.selectSlidingDoorReaction(zombie, requestedAnimation)
    if not definition then return nil end
    return definition.observedAnimation or definition.reaction or definition.id
end

function CPD.playSlidingDoorAnimation(zombie, requestedAnimation)
    return CPD.playSlidingDoorReaction(zombie, requestedAnimation)
end

function CPD.applyZombieImpact(opener, zombie, strength, forceKnockdown, door, impactSquare, impactMods, doorProfile)
    if not zombie or not zombie:isAlive() then return false end
    if isServer and isServer() then
        local onlineId = tonumber(safeCall(zombie, "getOnlineID"))
        if onlineId == nil or onlineId < 0 then
            mpDebug("SERVER_ZOMBIE_SKIP", "impact skipped because zombie has invalid online id=" .. tostring(onlineId))
            return false
        end
    end
    local row = C.STRENGTH[strength] or C.STRENGTH[0]
    impactMods = impactMods or C.ARM_STRAIN_DEBUFF.none
    doorProfile = doorProfile or CPD.getDoorImpactProfile(door, strength)

    safeCall(zombie, "setAttackedBy", opener)
    local health = CPD.prepareZombieHealth(zombie)
    if not health then return false end

    local damageMult = tonumber(impactMods.damageMult) or 1.0
    local knockdownMult = tonumber(impactMods.knockdownMult) or 1.0
    local knockdownChance = clamp(knockdownMult * S.zombieKnockdownChance(), 0.0, 1.0)

    local damageMin = row.zombieDamageMin
    local damageMax = row.zombieDamageMax
    if doorProfile.zombieDamageMin ~= nil then
        damageMin = tonumber(doorProfile.zombieDamageMin) or 0
        damageMax = tonumber(doorProfile.zombieDamageMax) or damageMin
    else
        local profileDamageMult = tonumber(doorProfile.zombieDamageMult) or 1.0
        damageMin = damageMin * profileDamageMult
        damageMax = damageMax * profileDamageMult
    end

    local fraction = randomFloat(damageMin, damageMax) * damageMult * S.zombieDamageMultiplier()
    local maxFraction = tonumber(doorProfile.maxZombieDamageFraction)
    if maxFraction ~= nil then
        fraction = math.min(fraction, math.max(0, maxFraction))
    end
    local damage = math.max(0, health * fraction)
    local newHealth = math.max(0, health - damage)

    local lethal = damage > 0 and (newHealth <= 0 or newHealth <= C.ZOMBIE_FINISH_HEALTH)
    local crawler = safeCall(zombie, "isCrawling") == true
    if crawler and not S.affectCrawlers() then return false end
    local knockedDown = false
    local crawlerStunned = false
    local slidingAnimated = false
    local slidingAnimation = nil
    local staggerAnimation = nil

    if not lethal then
        if doorProfile.sliding == true then
            slidingAnimated = doorProfile.forceZombieStun == true
            if slidingAnimated then
                slidingAnimation = CPD.selectSlidingDoorAnimation(zombie)
            end
        elseif crawler then
            crawlerStunned = true
        elseif forceKnockdown == true then
            knockedDown = randomFloat(0.0, 1.0) < knockdownChance
        end
    end

    local staggered = not lethal and not knockedDown and not crawlerStunned and not slidingAnimated
    if staggered then
        staggerAnimation = CPD.selectDoorStaggerAnimation()
    end
    CPD.applyImpactDirection(zombie, door, impactSquare, strength)

    if lethal then
        safeCall(zombie, "setHealth", 0)
        pcall(function() zombie:Kill(opener, false) end)
        newHealth = 0
        CPD.queueZombieDamageVerification(opener, zombie, 0, true)
    else
        safeCall(zombie, "setHealth", newHealth)
        local after = tonumber(safeCall(zombie, "getHealth"))
        if after ~= nil and after > (newHealth + C.ZOMBIE_HEALTH_EPSILON) then
            safeCall(zombie, "setHealth", newHealth)
        end
        CPD.queueZombieDamageVerification(opener, zombie, newHealth, false)

        if slidingAnimated then
            if S.impactFeedbackEnabled() and (not isServer or not isServer()) then
                CPD.playSlidingDoorAnimation(zombie, slidingAnimation)
            end
        elseif crawlerStunned then
            safeCall(zombie, "setHitLegsWhileOnFloor", true)
            safeCall(zombie, "setHitTime", C.CRAWLER_STUN_HIT_TIME)
        elseif knockedDown then
            local okKnock = pcall(function() zombie:knockDown(false) end)
            if not okKnock then safeCall(zombie, "setKnockedDown", true) end
        else
            if S.impactFeedbackEnabled() and (not isServer or not isServer()) then
                CPD.playDoorStaggerAnimation(zombie, staggerAnimation)
            end
        end
    end

    log("Zombie door damage strength=" .. strength ..
        " profile=" .. tostring(doorProfile.kind or "standard") ..
        " crawler=" .. tostring(crawler) ..
        " strainBand=" .. tostring(impactMods.band or "none") ..
        " damageMult=" .. string.format("%.2f", damageMult) ..
        " knockMult=" .. string.format("%.2f", knockdownMult) ..
        " knockChance=" .. string.format("%.2f", knockdownChance) ..
        " health=" .. tostring(health) ..
        " fraction=" .. string.format("%.4f", fraction) ..
        " damage=" .. string.format("%.4f", damage) ..
        " expected=" .. tostring(newHealth) ..
        " knockedDown=" .. tostring(knockedDown) ..
        " crawlerStunned=" .. tostring(crawlerStunned) ..
        " slidingAnimated=" .. tostring(slidingAnimated) ..
        " hitAnimation=" .. tostring(slidingAnimation) ..
        " staggerAnimation=" .. tostring(staggerAnimation) ..
        " lethal=" .. tostring(lethal))

    local dbgSq = safeCall(zombie, "getCurrentSquare")
    mpDebug("SERVER_ZOMBIE_RESULT",
        "zombieId=" .. tostring(safeCall(zombie, "getOnlineID")) ..
        " hp=" .. tostring(health) .. "->" .. tostring(newHealth) ..
        " damage=" .. tostring(damage) ..
        " lethal=" .. tostring(lethal) ..
        " knock=" .. tostring(knockedDown) ..
        " stagger=" .. tostring(staggered) ..
        " square=" .. tostring(dbgSq and (dbgSq:getX() .. "," .. dbgSq:getY() .. "," .. dbgSq:getZ()) or "nil"))

    notifyZombieClients(zombie, newHealth, knockedDown, staggered, crawlerStunned, slidingAnimated, slidingAnimation, staggerAnimation)
    CPD.notifyCombatTextDoorHit(opener, zombie, health, newHealth)
    return true, knockedDown, crawlerStunned
end

function CPD.getPlayerContest(opener, target)
    local aStrength = CPD.getStrength(opener)
    local aFitness = CPD.getFitness(opener)
    local tStrength = CPD.getStrength(target)
    local tFitness = CPD.getFitness(target)

    local strengthWin = aStrength > tStrength
    local fitnessWin = aFitness > tFitness

    if strengthWin and fitnessWin then
        return 1.00, 1.35, aStrength, aFitness, tStrength, tFitness
    end
    if strengthWin or fitnessWin then
        return 0.50, 1.00, aStrength, aFitness, tStrength, tFitness
    end
    return 0.00, 0.65, aStrength, aFitness, tStrength, tFitness
end

function CPD.applyPlayerImpact(opener, target, strength, door, impactSquare, impactMods, doorProfile)
    if not target or not target:isAlive() then return false end

    local allowDamage = S.damagePlayers()
    local allowKnockdown = S.knockDownPlayers()
    if not allowDamage and not allowKnockdown then return false end

    impactMods = impactMods or C.ARM_STRAIN_DEBUFF.none
    doorProfile = doorProfile or CPD.getDoorImpactProfile(door, strength)

    local chance, damageMult = CPD.getPlayerContest(opener, target)
    local row = C.STRENGTH[strength] or C.STRENGTH[0]
    local strainDamageMult = tonumber(impactMods.damageMult) or 1.0
    local strainKnockMult = tonumber(impactMods.knockdownMult) or 1.0
    local profileDamageMult = tonumber(doorProfile.playerDamageMult) or 1.0
    local knockdownChance = clamp(chance * strainKnockMult * S.playerKnockdownChance(), 0.0, 1.0)

    local damage = 0
    if allowDamage then
        damage = row.playerDamage * damageMult * strainDamageMult * profileDamageMult * randomFloat(0.85, 1.15)
    end

    local knockedDown = false
    if allowKnockdown and doorProfile.neverPlayerKnockdown ~= true then
        knockedDown = randomFloat(0.0, 1.0) < knockdownChance
    end

    CPD.applyImpactDirection(target, door, impactSquare, strength)

    local bodyDamage = target:getBodyDamage()
    if bodyDamage and damage > 0 then
        bodyDamage:ReduceGeneralHealth(damage)
    end

    if knockedDown then
        target:setKnockedDown(true)
    end

    if isServer and isServer() and sendServerCommand then
        sendServerCommand(target, "CyesPushDoors", "playerImpact", {
            knockedDown = knockedDown,
        })
    end

    log("Player door impact strength=" .. tostring(strength) ..
        " profile=" .. tostring(doorProfile.kind or "standard") ..
        " damage=" .. string.format("%.4f", damage) ..
        " knockChance=" .. string.format("%.2f", knockdownChance) ..
        " knockedDown=" .. tostring(knockedDown))
    return damage > 0 or knockedDown
end

function CPD.getDoorImpactSound(door)
    local sound = safeCall(door, "getThumpSound")
    if sound == nil then return nil end
    sound = tostring(sound)
    if sound == "" or sound == "nil" then return nil end
    return sound
end

function CPD.playImpactSoundForOpener(opener, door)
    if not opener then return end
    local sound = CPD.getDoorImpactSound(door)
    if not sound then
        log("Impact registered but door has no thump sound")
        return
    end

    if isServer and isServer() and sendServerCommand then
        sendServerCommand(opener, "CyesPushDoors", "impactSound", {
            sound = sound,
            playerId = safeCall(opener, "getOnlineID"),
        })
        return
    end

    if S.impactFeedbackEnabled() then
        safeCall(opener, "playSoundLocal", sound)
    end
end

local function syncDoorHealth(door, health)
    if instanceof(door, "IsoThumpable") then
        pcall(function() door:syncIsoThumpable() end)
    end

    if isServer and isServer() and sendServerCommand then
        local sq = door:getSquare()
        if sq then
            sendServerCommand("CyesPushDoors", "doorHealth", {
                x = sq:getX(), y = sq:getY(), z = sq:getZ(),
                index = door:getObjectIndex(),
                health = health,
            })
        end
    end
end

local function destroyDoor(door)
    if not door then return end

    if CPD.isGarageDoor(door) and IsoDoor and IsoDoor.destroyGarageDoor then
        local okDestroy, result = pcall(IsoDoor.destroyGarageDoor, door)
        if okDestroy and result == true then return end
    end

    if IsoDoor and IsoDoor.getDoubleDoorIndex and IsoDoor.destroyDoubleDoor then
        local ok, index = pcall(IsoDoor.getDoubleDoorIndex, door)
        if ok and index ~= nil and tonumber(index) and tonumber(index) >= 0 then
            local destroyed = false
            local okDestroy, result = pcall(IsoDoor.destroyDoubleDoor, door)
            if okDestroy then destroyed = result == true end
            if destroyed then return end
        end
    end

    pcall(function() door:destroy() end)
end

function CPD.applyDoorWear(door, strength, zombieCount, playerCount, doorProfile)
    zombieCount = math.max(0, tonumber(zombieCount) or 0)
    playerCount = math.max(0, tonumber(playerCount) or 0)
    local targetCount = zombieCount + playerCount
    if targetCount <= 0 or not door then return false end

    strength = clamp(tonumber(strength) or 0, 0, 10)
    local row = C.STRENGTH[strength]
    if not row then return false end

    doorProfile = doorProfile or CPD.getDoorImpactProfile(door, strength)
    local garage = CPD.isGarageDoor(door)
    local doubleDoor = CPD.isDoubleDoor(door)
    local healthDoor = door
    if garage then
        healthDoor = CPD.getGarageDoorMaster(door) or door
    elseif doubleDoor then
        healthDoor = CPD.getDoubleDoorMaster(door) or door
    end
    local health = safeCall(healthDoor, "getHealth")
    local maxHealth = safeCall(healthDoor, "getMaxHealth")
    if not health or not maxHealth or maxHealth <= 0 then return false end

    if S.doorWearMultiplier() <= 0 then return false end

    local material = CPD.getDoorMaterial(healthDoor)
    local materialMult = 1.0
    if doorProfile.ignoreMaterialWear ~= true then
        materialMult = C.MATERIAL_DOOR_DAMAGE_MULTIPLIER[material] or 1.0
    end

    local profileWearMult = tonumber(doorProfile.doorWearMult) or 1.0
    local rawWear = 0

    if garage then
        
        
        local garageRow = (C.GARAGE_DOOR_WEAR_PER_TARGET or {})[strength]
            or (C.GARAGE_DOOR_WEAR_PER_TARGET or {})[0]
        if not garageRow then return false end

        local durabilityMult = math.max(0.05, tonumber(C.GARAGE_DOOR_DURABILITY_MULT) or 0.75)
        local wearHealthBasis = maxHealth / durabilityMult
        local zombieWearMult = math.max(0, tonumber(C.GARAGE_ZOMBIE_WEAR_MULT) or 1.0)
        local playerWearMult = math.max(0, tonumber(C.GARAGE_PLAYER_WEAR_MULT) or 1.0)

        for i = 1, zombieCount do
            local wearFraction = randomFloat(garageRow.min, garageRow.max)
            rawWear = rawWear + (wearHealthBasis * wearFraction * zombieWearMult)
        end
        for i = 1, playerCount do
            local wearFraction = randomFloat(garageRow.min, garageRow.max)
            rawWear = rawWear + (wearHealthBasis * wearFraction * playerWearMult)
        end
    else
        if strength <= 0 then return false end
        for i = 1, targetCount do
            local wearFraction = randomFloat(row.doorWearMin, row.doorWearMax)
            rawWear = rawWear + (maxHealth * wearFraction)
        end
    end

    local sandboxWearMult = S.doorWearMultiplier()
    if garage then
        sandboxWearMult = sandboxWearMult * S.garageDoorWearMultiplier()
    end

    local wear = math.floor((rawWear * materialMult * profileWearMult * sandboxWearMult) + 0.5)
    if wear < 1 then wear = 1 end

    local newHealth = math.max(0, health - wear)
    if garage then
        local parts = CPD.getGarageDoorParts(door)
        for i = 1, #parts do
            safeCall(parts[i], "setHealth", newHealth)
            syncDoorHealth(parts[i], newHealth)
        end
    elseif doubleDoor then
        local parts = CPD.getDoubleDoorParts(door)
        for i = 1, #parts do
            safeCall(parts[i], "setHealth", newHealth)
            syncDoorHealth(parts[i], newHealth)
        end
    else
        door:setHealth(newHealth)
        syncDoorHealth(door, newHealth)
    end

    log("Door impact strength=" .. strength ..
        " profile=" .. tostring(doorProfile.kind or "standard") ..
        " material=" .. material ..
        " zombies=" .. zombieCount ..
        " players=" .. playerCount ..
        " wear=" .. wear ..
        " health=" .. health .. "->" .. newHealth)

    if newHealth <= 0 then
        destroyDoor(door)
        return true
    end

    return false
end

function CPD.rollGarageBreakChance(door, strength, conditionHealth, conditionMaxHealth)
    if not door or not CPD.isGarageDoor(door) then return false end
    if S.doorWearMultiplier() <= 0 then return false end

    strength = clamp(tonumber(strength) or 0, 0, 10)
    local healthDoor = CPD.getGarageDoorMaster(door) or door
    local health = tonumber(safeCall(healthDoor, "getHealth")) or 0
    local maxHealth = tonumber(safeCall(healthDoor, "getMaxHealth")) or 0
    if maxHealth <= 0 then return false end
    if health <= 0 then
        destroyDoor(door)
        return true
    end

    local failureMult = S.garageFailureChanceMultiplier()
    if failureMult <= 0 then return false end

    local strengthChance = tonumber((C.GARAGE_FORCE_BREAK_CHANCE or {})[strength]) or 0
    local chanceHealth = tonumber(conditionHealth) or health
    local chanceMaxHealth = tonumber(conditionMaxHealth) or maxHealth
    if chanceMaxHealth <= 0 then chanceMaxHealth = maxHealth end
    local lostCondition = clamp(1.0 - (chanceHealth / chanceMaxHealth), 0.0, 1.0)
    local conditionChance = lostCondition * (tonumber(C.GARAGE_CONDITION_BREAK_CHANCE_MAX) or 0.20)
    local maxChance = tonumber(C.GARAGE_TOTAL_BREAK_CHANCE_MAX) or 0.75
    local baseChance = strengthChance + conditionChance
    local totalChance = clamp(baseChance * failureMult, 0.0, maxChance)

    if totalChance <= 0 then return false end

    local roll = randomFloat(0.0, 1.0)
    log("Garage failure roll strength=" .. tostring(strength) ..
        " strengthChance=" .. string.format("%.3f", strengthChance) ..
        " conditionChance=" .. string.format("%.3f", conditionChance) ..
        " multiplier=" .. string.format("%.2f", failureMult) ..
        " total=" .. string.format("%.3f", totalChance) ..
        " roll=" .. string.format("%.3f", roll))

    if roll < totalChance then
        local stressRow = (C.GARAGE_FORCE_STRESS_DAMAGE or {})[strength]
            or (C.GARAGE_FORCE_STRESS_DAMAGE or {})[0]
        if not stressRow then return false end

        local stressFraction = randomFloat(stressRow.min, stressRow.max)
        if stressFraction <= 0 then return false end
        local structuralDamage = math.floor((maxHealth * stressFraction) + 0.5)
        if structuralDamage < 1 then structuralDamage = 1 end

        local newHealth = math.max(0, health - structuralDamage)
        local parts = CPD.getGarageDoorParts(door)
        for i = 1, #parts do
            safeCall(parts[i], "setHealth", newHealth)
            syncDoorHealth(parts[i], newHealth)
        end

        if newHealth <= 0 then
            destroyDoor(door)
            log("Garage door failed from force/condition")
            return true
        end
    end

    return false
end

function CPD.resolveDoorImpact(opener, door, preferredImpactSquare, transition)
    if not opener or not door then return false end
    if not CPD.isSupportedDoor(door) then return false end

    local garage = CPD.isGarageDoor(door)
    local doubleDoor = CPD.isDoubleDoor(door)
    transition = transition or (garage and "close" or "open")
    if garage and transition ~= "close" then return false end
    if not garage and transition ~= "open" then return false end

    local openState = CPD.getLogicalDoorOpenState(door)
    if garage and openState ~= false then return false end
    if not garage and openState ~= true then return false end

    if CPD.isImpactBlockedByArmStrain(opener) then
        log("Door impact blocked by arm strain usage limit")
        mpDebug("IMPACT_STRAIN_BLOCK",
            "player=" .. tostring(safeCall(opener, "getUsername") or opener) ..
            " usageLimit=" .. string.format("%.2f", CPD.getArmStrainUsageLimit()))
        return false
    end

    local recovering, recoveryRemainingMs, recoveryBand = CPD.isImpactRecoveryActive(opener)
    if recovering then
        log("Door impact skipped during muscle recovery")
        mpDebug("IMPACT_RECOVERY_BLOCK",
            "player=" .. tostring(safeCall(opener, "getUsername") or opener) ..
            " band=" .. tostring(recoveryBand) ..
            " remainingMs=" .. tostring(recoveryRemainingMs))
        return false
    end

    if CPD.isDuplicateImpact(opener, door) then return false end

    local impactSquares, impactSide = CPD.getImpactBandFromPreferred(door, preferredImpactSquare)
    local geometrySource = "preferred"
    if not impactSquares then
        local context, geometryReason = CPD.getInteractionImpactContext(opener, door)
        if context then
            impactSquares = context.impactBand
            impactSide = context.impactSide
            geometrySource = "runtime"
        else
            impactSquares = {}
            geometrySource = "invalid:" .. tostring(geometryReason or "unknown")
        end
    end

    mpDebug("IMPACT_GEOMETRY",
        "key=" .. tostring(CPD.getDoorWorldKey(door)) ..
        " transition=" .. tostring(transition) ..
        " source=" .. tostring(geometrySource) ..
        " impactSide=" .. tostring(impactSide or "none") ..
        " squares=" .. tostring(#impactSquares))

    if doubleDoor then
        mpDebug("DOUBLE_DOOR_GROUP",
            "key=" .. tostring(CPD.getDoorWorldKey(door)) ..
            " parts=" .. tostring(#CPD.getDoubleDoorParts(door)) ..
            " impactSquares=" .. tostring(#impactSquares))
    end

    if #impactSquares == 0 then
        log("Door transition but no impact square could be resolved")
        return false
    end

    local targets, targetSquares = CPD.collectTargetsFromSquares(impactSquares, opener)
    mpDebug("SERVER_TARGETS",
        "transition=" .. tostring(transition) ..
        " garage=" .. tostring(garage) ..
        " doubleDoor=" .. tostring(doubleDoor) ..
        " impactSquares=" .. tostring(#impactSquares) ..
        " rawTargets=" .. tostring(#targets))
    log("Impact transition=" .. tostring(transition) ..
        " garage=" .. tostring(garage) ..
        " doubleDoor=" .. tostring(doubleDoor) ..
        " squares=" .. tostring(#impactSquares) ..
        " targets=" .. tostring(#targets))
    if #targets == 0 then return false end

    local strength = CPD.getStrength(opener)
    local doorProfile = CPD.getDoorImpactProfile(door, strength)

    local zombies = {}
    local players = {}
    for i = 1, #targets do
        local target = targets[i]
        if instanceof(target, "IsoZombie") and target:isAlive() then
            if S.affectCrawlers() or safeCall(target, "isCrawling") ~= true then
                zombies[#zombies + 1] = target
            end
        elseif instanceof(target, "IsoPlayer") and target:isAlive() then
            players[#players + 1] = target
        end
    end

    if #zombies > 0 then
        local cap = 0
        if doorProfile.sliding == true then
            local baseCap = math.max(1, math.floor(tonumber(doorProfile.maxZombies) or 1))
            cap = math.max(1, math.floor((baseCap * S.zombiesAffectedMultiplier()) + 0.5))
            if cap > 3 then cap = 3 end
        elseif doorProfile.doubleDoor == true then
            cap = CPD.getDoubleDoorAffectedCount(strength, #zombies)
        else
            cap = CPD.getZombieAffectedCount(strength, #zombies)
        end
        if (garage or doubleDoor) and cap < #zombies then
            
            
            
            local shuffledMultiTargets = shuffledCopy(zombies)
            local limited = {}
            for i = 1, cap do
                limited[i] = shuffledMultiTargets[i]
            end
            zombies = limited
        else
            zombies = CPD.limitZombieTargets(zombies, impactSquares[1], cap)
        end
        log("Zombie target capacity profile=" .. tostring(doorProfile.kind or "standard") ..
            " cap=" .. tostring(cap) .. " affected=" .. tostring(#zombies))
    end

    local initialImpactMods = CPD.getArmStrainModifiers(opener)
    local fitness = CPD.getFitness(opener)

    local garageConditionHealthBefore = nil
    local garageConditionMaxHealthBefore = nil
    if garage then
        local healthDoor = CPD.getGarageDoorMaster(door) or door
        garageConditionHealthBefore = tonumber(safeCall(healthDoor, "getHealth"))
        garageConditionMaxHealthBefore = tonumber(safeCall(healthDoor, "getMaxHealth"))
    end

    local knockableZombies = {}
    if doorProfile.neverZombieKnockdown ~= true then
        for i = 1, #zombies do
            if safeCall(zombies[i], "isCrawling") ~= true then
                knockableZombies[#knockableZombies + 1] = zombies[i]
            end
        end
    end

    local shuffledZombies = shuffledCopy(knockableZombies)
    local knockdownCount = 0
    if doorProfile.neverZombieKnockdown ~= true then
        if doorProfile.doubleDoor == true then
            knockdownCount = CPD.getDoubleDoorKnockdownCount(strength, #shuffledZombies)
        else
            knockdownCount = CPD.getZombieKnockdownCount(strength, #shuffledZombies)
        end
    end

    local knockdownSet = {}
    for i = 1, knockdownCount do
        knockdownSet[shuffledZombies[i]] = true
    end

    local zombieHits = 0
    local playerHits = 0
    local actualZombieKnockdowns = 0
    local crawlerStuns = 0
    local garageBroken = false
    local strainBlockedMidImpact = false

    for i = 1, #zombies do
        if garageBroken then break end
        if CPD.isImpactBlockedByArmStrain(opener) then
            strainBlockedMidImpact = true
            break
        end

        local impactMods = CPD.getArmStrainModifiers(opener)
        local zombie = zombies[i]
        local targetSquare = targetSquares[zombie] or impactSquares[1]
        local impactDoor = doubleDoor and CPD.getDoubleDoorImpactPart(door, targetSquare) or door
        local hit, knockedDown, crawlerStunned = CPD.applyZombieImpact(
            opener, zombie, strength, knockdownSet[zombie] == true, impactDoor, targetSquare, impactMods, doorProfile
        )
        if hit then
            zombieHits = zombieHits + 1
            if knockedDown then actualZombieKnockdowns = actualZombieKnockdowns + 1 end
            if crawlerStunned then crawlerStuns = crawlerStuns + 1 end

            
            
            
            
            CPD.applyArmStrain(opener, fitness, 1, doorProfile)
        end
    end

    for i = 1, #players do
        if garageBroken then break end
        if CPD.isImpactBlockedByArmStrain(opener) then
            strainBlockedMidImpact = true
            break
        end

        local impactMods = CPD.getArmStrainModifiers(opener)
        local target = players[i]
        local targetSquare = targetSquares[target] or impactSquares[1]
        local impactDoor = doubleDoor and CPD.getDoubleDoorImpactPart(door, targetSquare) or door
        if CPD.applyPlayerImpact(opener, target, strength, impactDoor, targetSquare, impactMods, doorProfile) then
            playerHits = playerHits + 1
            CPD.applyArmStrain(opener, fitness, 1, doorProfile)
        end
    end

    local hitCount = zombieHits + playerHits
    local recoveryMs = 0
    local recoveryBandEnd = "none"
    if hitCount > 0 then
        CPD.playImpactSoundForOpener(opener, door)
        if garage then
            garageBroken = CPD.applyDoorWear(door, strength, zombieHits, playerHits, doorProfile) == true
            if not garageBroken then
                garageBroken = CPD.rollGarageBreakChance(
                    door, strength, garageConditionHealthBefore, garageConditionMaxHealthBefore
                ) == true
            end
        else
            CPD.applyDoorWear(door, strength, zombieHits, playerHits, doorProfile)
        end
        recoveryMs, recoveryBandEnd = CPD.startImpactRecovery(opener)
        mpDebug("IMPACT_RECOVERY_START",
            "player=" .. tostring(safeCall(opener, "getUsername") or opener) ..
            " band=" .. tostring(recoveryBandEnd) ..
            " durationMs=" .. tostring(recoveryMs) ..
            " hits=" .. tostring(hitCount))
    end

    local finalImpactMods = CPD.getArmStrainModifiers(opener)
    log("Resolved impact transition=" .. tostring(transition) ..
        " strength=" .. strength ..
        " profile=" .. tostring(doorProfile.kind or "standard") ..
        " strainBandStart=" .. tostring(initialImpactMods.band) ..
        " strainStart=" .. string.format("%.2f", initialImpactMods.strain or 0) ..
        " strainBandEnd=" .. tostring(finalImpactMods.band) ..
        " strainEnd=" .. string.format("%.2f", finalImpactMods.strain or 0) ..
        " usageLimit=" .. string.format("%.2f", CPD.getArmStrainUsageLimit()) ..
        " recoveryBand=" .. tostring(recoveryBandEnd) ..
        " recoveryMs=" .. tostring(recoveryMs) ..
        " zombieHits=" .. zombieHits ..
        " zombieKnockdowns=" .. actualZombieKnockdowns ..
        " crawlerStuns=" .. crawlerStuns ..
        " playerHits=" .. playerHits ..
        " strainBlockedMidImpact=" .. tostring(strainBlockedMidImpact) ..
        " garageBroken=" .. tostring(garageBroken))

    return hitCount > 0
end

function CPD.resolveDoorOpening(opener, door, preferredImpactSquare)
    return CPD.resolveDoorImpact(opener, door, preferredImpactSquare, "open")
end

function CPD.makeDoorArgs(door, impactSquare, interaction, transition)
    if not door or not door:getSquare() then return nil end
    local sq = door:getSquare()
    local args = {
        x = sq:getX(), y = sq:getY(), z = sq:getZ(),
        index = door:getObjectIndex(),
        interaction = interaction == true,
        transition = transition or (CPD.isGarageDoor(door) and "close" or "open"),
    }
    if impactSquare and CPD.isEntrySideSquare(door, impactSquare) then
        args.impactX = impactSquare:getX()
        args.impactY = impactSquare:getY()
        args.impactZ = impactSquare:getZ()
    end
    return args
end

function CPD.findDoor(args)
    if not args or args.x == nil or args.y == nil or args.z == nil or args.index == nil then return nil end
    local sq = getCell():getGridSquare(tonumber(args.x), tonumber(args.y), tonumber(args.z))
    if not sq then return nil end
    local index = tonumber(args.index)
    if not index or index < 0 or index >= sq:getObjects():size() then return nil end
    local object = sq:getObjects():get(index)
    if CPD.isSupportedDoor(object) then return object end
    return nil
end

function CPD.validateServerRequest(player, door, transition)
    if not player or not player:isAlive() or not door then return false end

    local garage = CPD.isGarageDoor(door)
    transition = transition or (garage and "close" or "open")
    if garage and transition ~= "close" then return false end
    if not garage and transition ~= "open" then return false end

    local sq = door:getSquare()
    if not sq or sq:getZ() ~= player:getZ() then return false end

    local dx = player:getX() - (sq:getX() + 0.5)
    local dy = player:getY() - (sq:getY() + 0.5)
    local distSq = (dx * dx) + (dy * dy)
    if CPD.isDoubleDoor(door) then
        local parts = CPD.getDoubleDoorParts(door)
        for i = 1, #parts do
            local partSq = safeCall(parts[i], "getSquare")
            if partSq and partSq:getZ() == player:getZ() then
                local pdx = player:getX() - (partSq:getX() + 0.5)
                local pdy = player:getY() - (partSq:getY() + 0.5)
                local partDistSq = (pdx * pdx) + (pdy * pdy)
                if partDistSq < distSq then distSq = partDistSq end
            end
        end
    end
    local maxDist = C.MAX_SERVER_VALIDATION_DISTANCE
    if distSq > (maxDist * maxDist) then return false end

    local open = CPD.getLogicalDoorOpenState(door)
    if garage then
        if open ~= nil and open ~= false then return false end
    else
        if open ~= nil and open ~= true then return false end
    end

    return true
end

return CyesPushDoors
