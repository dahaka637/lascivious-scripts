--[[
    Burris Quality of Life -- feature registry.

    Features declare themselves at file scope and the registry initialises them
    later, once SandboxVars exists, with each init() wrapped in a pcall.

    The point is blast radius: in the mod this one is inspired by, a single file
    that indexed a global the game had deleted (`ISFireplaceMenu`) threw at load
    and took its whole feature down with no diagnostic. Here a feature that
    throws logs a warning and the other nine keep working.
]]

BQoL = BQoL or {}

local features = {}
local hookedEvents = {}
local initialised = {}

--[[
    Registers a feature.

      id      string    unique, used in log output
      init    function  called once, when the feature's event fires
      sandbox string    optional sandbox key; feature is skipped when it is false
      event   string    optional event name, defaults to "OnGameStart"

    init() is called with no arguments. Register context menu handlers, wrap
    vanilla functions, and read sandbox options from inside it -- not at file
    scope, where SandboxVars does not exist yet.
]]
function BQoL.feature(spec)
    if type(spec) ~= "table" or type(spec.id) ~= "string" or type(spec.init) ~= "function" then
        BQoL.warn("BQoL.feature() called with a malformed spec; ignoring")
        return
    end

    spec.event = spec.event or "OnGameStart"

    --[[
        SandboxVars is only populated once a world loads, so a feature gated on
        a sandbox option but initialised at boot would always read the declared
        default instead of the world's actual setting. Catch that at
        registration rather than shipping a silently-wrong toggle.
    ]]
    if spec.sandbox and spec.event == "OnGameBoot" then
        BQoL.warn("%s is sandbox-gated on %q but initialises at OnGameBoot, " ..
            "where SandboxVars does not exist yet. Use OnGameStart instead.",
            spec.id, spec.sandbox)
    end

    table.insert(features, spec)
end

local function initFeature(spec)
    if initialised[spec.id] then return end
    initialised[spec.id] = true

    if spec.sandbox and not BQoL.getBool(spec.sandbox) then
        BQoL.log("%s: disabled by sandbox option %s", spec.id, spec.sandbox)
        return
    end

    local ok, err = pcall(spec.init)
    if ok then
        BQoL.log("%s: ready", spec.id)
    else
        BQoL.warn("%s failed to initialise: %s", spec.id, tostring(err))
    end
end

local function runEvent(eventName)
    for _, spec in ipairs(features) do
        if spec.event == eventName then
            initFeature(spec)
        end
    end
end

--[[
    OnGameStart never fires on a dedicated server; OnServerStarted is its
    counterpart there. Vanilla does the same pairing -- see
    shared/Util/CustomTileProps.lua:342, `Events.OnServerStarted.Add(OnGameStart)`.

    Listening on both is safe because initialised[] makes init idempotent.
]]
local EVENT_ALIASES = {
    OnGameStart = { "OnGameStart", "OnServerStarted" },
}

--- Wires up one dispatcher per distinct event the registered features asked for.
local function hookEvents()
    for _, spec in ipairs(features) do
        local logical = spec.event

        for _, eventName in ipairs(EVENT_ALIASES[logical] or { logical }) do
            if not hookedEvents[eventName] then
                local event = Events[eventName]

                if not event then
                    BQoL.warn("%s wants unknown event %q; it will never initialise",
                        spec.id, tostring(eventName))
                else
                    hookedEvents[eventName] = true
                    event.Add(function() runEvent(logical) end)
                end
            end
        end
    end
end

local booted = false

--[[
    Runs once every mod file has loaded, which is what makes it safe to hook
    events for features registered in files that load after this one. Feature
    init itself still happens on the feature's own event.
]]
local function bootstrap()
    if booted then return end
    booted = true

    BQoL.info("Burris Quality of Life %s loaded (%d features registered)",
        BQoL.VERSION, #features)
    hookEvents()

    -- Features that asked for OnGameBoot have already missed it by the time
    -- this handler runs, so dispatch them directly.
    runEvent("OnGameBoot")
end

Events.OnGameBoot.Add(bootstrap)

-- Belt and braces for the dedicated server, where OnGameBoot may not fire.
if Events.OnServerStarted then
    Events.OnServerStarted.Add(bootstrap)
end
