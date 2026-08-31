--[[
    Burris Quality of Life -- sandbox option access.

    Every option in media/sandbox-options.txt is mirrored here with its default.
    BQoL.get() never returns nil for a known key: if the sandbox var is missing
    (old save, malformed options file, typo) the default is used instead.

    This exists because the mod this one is inspired by referenced three sandbox
    vars it never declared. One silently disabled a whole feature; the other two
    were latent "attempt to perform arithmetic on a nil value" crashes.
]]

BQoL = BQoL or {}

--- Sandbox namespace. Options are declared as `option BurrisQoL.<key>`.
local NAMESPACE = "BurrisQoL"

--- Authoritative defaults. Keys match sandbox-options.txt exactly.
local DEFAULTS = {
    -- prying
    PryEnabled                = true,
    PryBuildingDoors          = true,
    PryGarageDoors            = true,
    PrySafeDoors              = false,
    PryWindows                = true,
    PryVehicleDoors           = true,
    PryShatterVehicleWindows  = true,
    PryReinforcedDoorLevel    = 8,
    PryWindowShatterChance    = 20,
    PryChanceMultiplier       = 1,

    -- ground pickup
    CollectEnabled            = true,
    CollectDisableLoot        = false,
    CollectLootMultiplier     = 1,

    -- wash menu
    WashEnabled               = true,

    -- equip from ground
    EquipFromGroundEnabled    = true,

    -- can-opening injury
    CanInjuryEnabled          = true,
    CanInjuryChance           = 25,
    CanInjurySeverity         = 1,

    -- tourniquet
    TourniquetEnabled         = true,
    TourniquetBleedFraction   = 0.3,
    TourniquetPain            = 20,

    -- small tweaks
    TweakReadWhileWalking     = true,
    TweakEquipWhileWalking    = true,

    -- corpse storage
    CorpseTrunkEnabled        = true,

    -- inventory QoL
    ReloadAllMagazinesEnabled = true,
    ReplaceBandageEnabled     = true,
    NoFloorLimitEnabled       = true,
    InventorySelectionFixEnabled = true,

    -- nested container buttons (filter is a 1-based index, as in sandbox-options.txt)
    --
    -- Off by default, and the only feature here that is. It shipped on in
    -- 0.9.0 without ever having been loaded into a running game, and the two
    -- faults that came back were both in the loot window, where it interacts
    -- with whatever else a server has installed. Both are closed now --
    -- isVirtualContainer covers the aggregate case, and BQoL_NestedLogic's
    -- shouldNestContainer no longer nests anything on the loot side at all,
    -- for the reason documented there -- but the caution stays. Opt in.
    NestedContainersEnabled      = false,
    NestedContainersDepth        = 2,
    NestedContainersPlayer       = true,
    NestedContainersPlayerFilter = 1,  -- 1 = everything, 2 = only pockets, 3 = only equipped
    NestedContainersParentIcon   = true,

    -- tree canopy (enum values are 1-based indices, matching sandbox-options.txt)
    TreeCanopyEnabled         = true,
    TreeCanopyHideStyle       = 1,  -- 1 = fade, 2 = trunk only
    TreeCanopyWhileDriving    = true,
    TreeCanopyDrivingRange    = 1,  -- 1 = long, 2 = short
    TreeCanopyOnFoot          = true,
    TreeCanopyOnFootRange     = 1,  -- 1 = standard, 2 = narrow, 3 = minimal
    TreeCanopyIndoorRadius    = 24,

    -- zombie collision
    ZombieCollisionEnabled    = false,
    ZombieCollisionMaxZombies = 12,
    ZombieCollisionScanRadius = 8,
    ZombieCollisionPushRadius = 0.5,
    ZombieCollisionPushForce  = 0.05,
    ZombieCollisionScope      = 1,  -- 1 = chasing, 2 = aggressive, 3 = all

    -- debug
    Debug                     = false,
}

BQoL.DEFAULTS = DEFAULTS

--[[
    Whether we have already complained about a missing namespace. One line per
    session is a diagnostic; one line per option read is a flood.
]]
local warnedMissingNamespace = false

--[[
    Complains, once, when the world has SandboxVars but no BurrisQoL page.

    This is the state a multiplayer client is in when the server does not have
    the mod installed: the server's sandbox values replace the client's
    wholesale, our namespace never arrives, and every BQoL.get() silently
    falls back to its declared default -- all of which are `true`. The mod's
    own sandbox page still renders in the main menu, so the toggles look live
    and simply have no effect, with nothing in the log to say why.

    Reported as "the sandbox toggles do nothing", which is exactly what it
    looks like from the inside.
]]
local function warnIfNamespaceMissing()
    if warnedMissingNamespace then return end
    warnedMissingNamespace = true

    BQoL.warn("SandboxVars has no %q page; every option is falling back to " ..
        "its default. In multiplayer this means the server does not have " ..
        "this mod installed -- the server's sandbox settings replace the " ..
        "client's, so toggling options here will have no effect.", NAMESPACE)
end

--[[
    Reads a sandbox option by its bare key, e.g. BQoL.get("PryEnabled").

    Falls back to the declared default when SandboxVars is not yet populated
    (the table only exists once a world is loaded) or the key is absent.
]]
function BQoL.get(key)
    local default = DEFAULTS[key]

    if default == nil then
        -- Unknown key: a typo at the call site. Loud, because it is a bug.
        BQoL.warn("unknown sandbox key %q", tostring(key))
        return nil
    end

    if not SandboxVars then
        -- Before a world loads there is nothing to read; not worth a warning.
        return default
    end

    local vars = SandboxVars[NAMESPACE]
    if not vars then
        warnIfNamespaceMissing()
        return default
    end

    local value = vars[key]
    if value == nil then
        return default
    end

    return value
end

--[[
    Boolean read that is guaranteed to return a real boolean.

    Use this for every on/off gate rather than testing BQoL.get() directly.
    BQoL.get returns whatever the Lua/Java bridge hands over, and in Lua the
    number 0 and the string "false" are both truthy -- so a boolean arriving
    as anything other than a Lua boolean would make `if not BQoL.get(k)`
    silently stop disabling anything, with the option still rendering
    correctly in the sandbox UI. Cheap insurance against a whole class of
    "the toggle does nothing" report.
]]
function BQoL.getBool(key)
    local value = BQoL.get(key)

    if value == nil or value == false then return false end
    if value == 0 or value == "false" or value == "0" then return false end

    return true
end

--- Numeric read that is guaranteed to return a number.
function BQoL.getNumber(key)
    local value = tonumber(BQoL.get(key))
    if value == nil then
        return tonumber(DEFAULTS[key]) or 0
    end
    return value
end
