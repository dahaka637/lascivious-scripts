--[[
    Burris Quality of Life -- prying rules.

    Shared between the context menu, the timed action and the server command
    handler so that all three agree on what is priable and whether an attempt
    succeeded. Lives in shared/ because the server needs it too.
]]

require "BQoL/BQoL_Core"

BQoL = BQoL or {}
BQoL.Pry = BQoL.Pry or {}

local Pry = BQoL.Pry

-- ------------------------------------------------------------ tool lookup

--[[
    Item tags that make something a prying tool.

    Tag-based rather than a hardcoded item list, which means TireIron
    (base:prybar) works too -- vanilla tags it alongside the two crowbars, and
    a hardcoded list would have missed it. Modded crowbars that carry the
    vanilla tags are picked up for free; anything else can register itself via
    BQoL.API.addPryTool().
]]
local TOOL_TAGS = { "CROWBAR", "PRY_BAR" }

local function notBroken(item)
    return not item:isBroken()
end

--[[
    Finds a usable prying tool anywhere in the player's inventory, including
    inside bags. Returns the item, or nil.
]]
function Pry.findTool(playerObj)
    if not playerObj then return nil end

    local inventory = playerObj:getInventory()
    if not inventory then return nil end

    -- Tagged tools first: this is the common case.
    for _, tagName in ipairs(TOOL_TAGS) do
        local tag = ItemTag and ItemTag[tagName]
        if tag then
            local ok, item = BQoL.safe(
                "Pry.findTool:" .. tagName,
                function() return inventory:getFirstTagEvalRecurse(tag, notBroken) end
            )
            if ok and item then return item end
        end
    end

    -- Then anything explicitly registered through the public API.
    for fullType in pairs(BQoL.API.getPryTools()) do
        local ok, item = BQoL.safe(
            "Pry.findTool:" .. fullType,
            function() return inventory:getFirstTypeEvalRecurse(fullType, notBroken) end
        )
        if ok and item then return item end
    end

    return nil
end

-- -------------------------------------------------------- target checking

--- True when the object is a garage door (or part of one).
function Pry.isGarageDoor(object)
    if not object then return false end

    local ok, objects = BQoL.safe(
        "Pry.isGarageDoor",
        function() return buildUtil.getGarageDoorObjects(object) end
    )
    return ok and objects ~= nil and objects[1] ~= nil
end

--[[
    Doors at or above this max health count as reinforced.

    2000 is the security-door tier exactly. IsoDoor's constructors in 42.20
    set maxHealth from a fixed ladder -- 100 for the weak/glass sprites, 500
    for the ordinary wooden default, 800 for metal, and 2000 for security
    doors, the ones that cannot be opened from outside without the key. So
    this threshold means "a security door, or anything at least as tough",
    and every ordinary world door falls below it with 1200 to spare.

    Player-built doors are IsoThumpable and also report maxHealth, on the
    carpentry ladder of 900 at level 3 rising to 3000 at level 10. Levels 7
    and up (2100+) therefore read as reinforced too. That is deliberate and
    self-consistent rather than a side effect: such a door genuinely has more
    health than a security door, so it should take the same Strength to
    force. Safehouse doors are gated separately by PrySafeDoors, which is off
    by default.

    Taken from the bytecode of IsoDoor.<init>, not from the wiki -- the wiki's
    door page is still marked as written for 42.3.1.
]]
local REINFORCED_MAX_HEALTH = 2000

--- Max health of a door, or nil when the object does not report one.
function Pry.getMaxHealth(object)
    local ok, health = BQoL.tryCall(object, { "getMaxHealth" })
    if not ok then return nil end
    return tonumber(health)
end

--[[
    Reinforced doors need a higher Strength level.

    Health-driven, because that is the only signal B42 actually exposes. There
    is no material accessor on the Lua side: IsoDoor does carry a Material
    enum with PrisonMetalDoor, MetalDoor, MetalGate, WoodDoor and WeakWooden,
    but it is ParameterMeleeHitSurface$Material -- private audio state, with
    only getMaterialFromString beside it. The public surface relevant here is
    getHealth() and getMaxHealth(), and max health is the better signal
    anyway: it is what makes a door hard to force in the first place, it needs
    no sprite list, and modded doors get it for free.

    The sprite registry is still honoured and still first. It was the *only*
    rule before, which is why this function could never return true: the
    backing table in BQoL_API starts empty and nothing in the mod ever calls
    addReinforcedDoorSprite, so PryReinforcedDoorLevel gated nothing and the
    reinforced tooltip never rendered. It stays as the override for map mods
    whose doors do not carry distinctive health.
]]
function Pry.isReinforced(object)
    if not object then return false end

    local ok, sprite = BQoL.safe("Pry.isReinforced:sprite", function()
        return object:getSprite()
    end)

    if ok and sprite then
        local ok2, name = BQoL.safe("Pry.isReinforced:name", function()
            return sprite:getName()
        end)
        if ok2 and name and BQoL.API.getReinforcedDoorSprites()[name] == true then
            return true
        end
    end

    local maxHealth = Pry.getMaxHealth(object)
    return maxHealth ~= nil and maxHealth >= REINFORCED_MAX_HEALTH
end

--[[
    True when the object is open.

    Both spellings are tried because B42 does not agree with itself: IsoDoor
    has IsOpen() and isOpen(), IsoWindow and IsoThumpable have only IsOpen().
    classify originally called the lowercase name alone, which on a window
    resolves to nil -- so the guard never fired and every window in the game,
    open or shut, was offered Pry Open. See the note on BQoL.tryCall.
]]
function Pry.isOpen(object)
    local ok, open = BQoL.tryCall(object, { "IsOpen", "isOpen" })
    return ok and open == true
end

--[[
    True when a window is locked.

    Windows carry their own single lock flag -- isLocked()/setIsLocked(), the
    pair vanilla's DebugContextMenu uses (client/DebugUIs/DebugContextMenu.lua
    :853). There is no isLockedByKey() on IsoWindow; that is a door concept.

    classify used to check nothing at all here, so Pry Open was offered on
    windows that were simply closed and would have opened on a click. The rule
    now matches the door rule: an unlocked window is not a prying target.
]]
function Pry.isWindowLocked(object)
    local ok, locked = BQoL.tryCall(object, { "isLocked" })
    return ok and locked == true
end

--[[
    True when something about the object makes prying meaningless, whatever
    its lock state says.

      isInvincible   mapper flag for objects that must never be forced
      isPermaLocked  windows the map author sealed; they never open
      isBarricaded   unlocking changes nothing until the planks come off
      isSmashed      the glass is already gone; climb through instead
      isDestroyed    nothing left to lever

    Every one is duck-typed because the three classes do not share them:
    IsoWindow has isPermaLocked and isSmashed, IsoDoor and IsoThumpable have
    neither. A missing accessor means "not blocked for that reason", which is
    the correct reading -- a door cannot be perma-locked.
]]
local BLOCKERS = {
    { "isInvincible" },
    { "isPermaLocked" },
    { "isBarricaded" },
    { "isSmashed" },
    { "isDestroyed" },
}

function Pry.isBlocked(object)
    if not object then return true end

    for _, names in ipairs(BLOCKERS) do
        local ok, blocked = BQoL.tryCall(object, names)
        if ok and blocked == true then return true end
    end

    return false
end

--[[
    True when a door is locked in either of the two ways B42 tracks it.

    IsoDoor and IsoThumpable each carry two independent lock states -- bLocked
    and bLockedByKey, with separate isLocked()/isLockedByKey() accessors. They
    are not aliases. An ordinary house door that world-gen locked is locked by
    *key*; isLocked() covers padlocks and the manually-locked state, and every
    isLocked() call in vanilla Lua is on a vehicle door, not a building one.

    Checking only isLocked(), as this did originally, meant classify() refused
    almost every locked house door in the game, so the Pry Open option never
    appeared on the doors players actually want to force. That is what "prying
    does not work" turned out to be; it had nothing to do with the earlier
    multiplayer fixes, which is why they did not help.

    Still requires the door to be locked somehow -- an unlocked door just
    opens, so offering to lever it is noise. (Common Sense's equivalent ends
    in an unconditional `return true`, offering Pry Open on every closed door
    including unlocked ones; that is not copied here.)
]]
function Pry.isDoorLocked(object)
    if not object then return false end

    local ok, locked = BQoL.safe("Pry.isDoorLocked", function()
        if object.isLocked and object:isLocked() then return true end
        if object.isLockedByKey and object:isLockedByKey() then return true end
        return false
    end)

    return ok and locked == true
end

--[[
    Reimplementation of ISWorldObjectContextMenu.isThumpDoor (:2176).

    Not called through: that function lives in client/ISUI/, which a dedicated
    server never loads, and Pry.classify runs on the server -- BQoL_Commands
    re-classifies the target rather than trusting the client. Calling the
    client version there indexed a nil global, the pcall in the command
    handler swallowed it, and the door simply never opened in multiplayer
    with nothing but a warning in the server log.

    The vanilla body is pure instanceof checks with no UI dependency, so it is
    reproduced verbatim rather than worked around.
]]
function Pry.isThumpDoor(object)
    if instanceof(object, "IsoThumpable") then
        if object:isDoor() or object:isWindow() then return true end
    end
    if instanceof(object, "IsoWindow") or instanceof(object, "IsoDoor") then
        return true
    end
    if instanceof(object, "IsoWindowFrame") then return true end
    return false
end

--[[
    The half of the decision that can change from tick to tick: whether the
    target is still worth levering right now.

    Shared with BQoL_PryAction:isValid on purpose. When classify offers the
    option and isValid disagrees, the action starts and aborts on its first
    tick, which reads in game as the action being silently cancelled -- so the
    two must not be able to drift apart. tools/test/pry_lock.lua asserts they
    agree.
]]
function Pry.stillPriable(object, kind)
    if not object then return false end
    if Pry.isBlocked(object) then return false end

    -- An unlocked door or window opens by itself; nothing to force.
    if kind == "window" then
        if Pry.isOpen(object) then return false end
        return Pry.isWindowLocked(object)
    end

    return Pry.isDoorLocked(object)
end

--[[
    Classifies a world object as a prying target.

    Returns a table { object, kind, garage } where kind is "door" or "window",
    or nil when the object cannot be pried. Respects the per-kind sandbox
    toggles, so a disabled category simply never classifies.
]]
function Pry.classify(object)
    if not object then return nil end
    if not Pry.isThumpDoor(object) then return nil end

    local isWindow = instanceof(object, "IsoWindow")
        or (instanceof(object, "IsoThumpable") and object:isWindow())

    if isWindow then
        if not BQoL.getBool("PryWindows") then return nil end
        if not Pry.stillPriable(object, "window") then return nil end
        return { object = object, kind = "window", garage = false }
    end

    local isDoor = instanceof(object, "IsoDoor")
        or (instanceof(object, "IsoThumpable") and object:isDoor())

    if not isDoor then return nil end

    if not Pry.stillPriable(object, "door") then return nil end

    local garage = Pry.isGarageDoor(object)

    if garage then
        if not BQoL.getBool("PryGarageDoors") then return nil end
    else
        if not BQoL.getBool("PryBuildingDoors") then return nil end
    end

    return { object = object, kind = "door", garage = garage }
end

--[[
    Safehouse doors are gated behind their own option so that players cannot
    force their way into each other's bases unless the server allows it.
]]
function Pry.isBlockedBySafehouse(object)
    if BQoL.getBool("PrySafeDoors") then return false end
    if not SafeHouse then return false end

    local square = object and object:getSquare()
    if not square then return false end

    local ok, safehouse = BQoL.safe(
        "Pry.isBlockedBySafehouse",
        function() return SafeHouse.getSafeHouse(square) end
    )

    return ok and safehouse ~= nil
end

-- ------------------------------------------------------------ skill checks

--- Strength level, floored at 1 so callers can divide by it safely.
function Pry.getStrength(playerObj)
    local ok, level = BQoL.safe(
        "Pry.getStrength",
        function() return playerObj:getPerkLevel(Perks.Strength) end
    )
    return math.max(1, (ok and tonumber(level)) or 1)
end

--[[
    Burglar is a profession in B42, not a trait -- its description is literally
    "Less chance of breaking window locks", which is exactly this mechanic.
]]
function Pry.isBurglar(playerObj)
    local ok, name = BQoL.safe("Pry.isBurglar", function()
        local profession = playerObj:getDescriptor():getCharacterProfession()
        if not profession then return nil end
        -- Vanilla is inconsistent about whether this is an object or a string.
        if type(profession) == "string" then return profession end
        return profession:getName()
    end)

    if not ok or not name then return false end
    return string.lower(tostring(name)) == "burglar"
end

--- True when the player is strong enough to attempt a reinforced door.
function Pry.canForceReinforced(playerObj)
    return Pry.getStrength(playerObj) >= BQoL.getNumber("PryReinforcedDoorLevel")
end

--[[
    Rolls a prying attempt.

    `penalty` is added to the failure chance -- vehicle doors are harder than
    building doors. Strength 1 is near-hopeless, Strength 10 is reliable.
    Burglars get a flat floor on their odds.

    Every divisor is guarded: the mod this is modelled on divides by the raw
    perk level, which is a crash at Strength 0.
]]
function Pry.roll(playerObj, penalty)
    penalty = tonumber(penalty) or 0

    local failChance = BQoL.divide(180, Pry.getStrength(playerObj), 100) + penalty
    failChance = failChance * BQoL.getNumber("PryChanceMultiplier")

    if Pry.isBurglar(playerObj) then
        failChance = math.min(failChance, 10)
    end

    failChance = math.max(0, math.min(100, failChance))

    BQoL.log("Pry: fail chance %.1f%%", failChance)
    return ZombRand(100) >= failChance
end

-- ------------------------------------------------------------- side effects

--[[
    Drains endurance. Guarded against a zero Fitness level.

    B42 removed Stats.getEndurance and Stats.setEndurance in favour of a
    generic pair keyed on the CharacterStat enum. Verified directly against
    zombie.characters.Stats: it has get and set, an `endurance` field, and no
    getEndurance/setEndurance at all. The old pair therefore raised "Object
    tried to call nil" on every completed pry -- which, because of where the
    callers put this, killed the whole feature rather than just the stat.

    Wrapped in its entirety on purpose. Endurance cost is cosmetic; if this
    API drifts again it must degrade to "no endurance drain", never take the
    caller down with it.
]]
function Pry.tire(playerObj, amount)
    local stats = playerObj and playerObj:getStats()
    if not stats then return end
    if not (CharacterStat and CharacterStat.ENDURANCE) then return end

    BQoL.safe("Pry.tire", function()
        local fitness = math.max(1, tonumber(playerObj:getPerkLevel(Perks.Fitness)) or 1)
        local current = stats:get(CharacterStat.ENDURANCE)
        local drained = current - BQoL.divide(amount, fitness / 2, amount)

        stats:set(CharacterStat.ENDURANCE, math.max(0, drained))
    end)
end

--- Sound played while levering, and on a failed attempt.
function Pry.getSounds(isGarage)
    if isGarage then
        return "PrisonMetalDoorBlocked", "PrisonMetalDoorBreak"
    end
    return "BeginRemoveBarricadePlankCrowbar", "BreakBarricadePlank"
end
