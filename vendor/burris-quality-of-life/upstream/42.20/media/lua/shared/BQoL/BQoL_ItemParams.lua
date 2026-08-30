--[[
    Burris Quality of Life -- script item parameter tweaks.

    Lives in shared/ deliberately, and this is load-bearing.

    ScriptManager is per-process, so a DoParam() call only affects the process
    that made it. On a dedicated server the game client loads client/ + shared/
    and the server process loads server/ + shared/ -- nothing else crosses over.
    So a script-item tweak has to run wherever the code that *reads* it runs.

    AttachmentType is read entirely by client UI: ISHotbar:canBeAttached and
    friends call item:getAttachmentType() (client/Hotbar/ISHotbar.lua:102,141),
    and the only other reference in the whole codebase is
    shared/TimedActions/ISAttachItemHotbar.lua. There is no server-side
    consumer. Putting this in server/ therefore made the tweak a no-op in
    multiplayer -- the flashlight simply refused to hang from the belt, with
    no error anywhere -- while singleplayer kept working because there both
    trees load into one process. It was in server/ until exactly that was
    reported from a live server.

    Runs on OnGameStart, not OnGameBoot: SandboxVars does not exist until a
    world loads, so a sandbox-gated feature initialised at boot would always
    see the declared default rather than the world's actual setting. The
    registry maps that to OnServerStarted on a dedicated server.

    AttachmentType is consulted when the game decides whether an item may go in
    a slot, which happens at runtime, so applying it at world load is soon
    enough.

    Known limitation: ScriptManager is process-global, so the change persists
    for the rest of the session. Loading a world with the option on and then a
    second world with it off, without restarting the game, leaves the second
    world with the tweak still applied.
]]

require "BQoL/BQoL_Core"
--[[
    Explicit, and required. BQoL.feature lives in BQoL_Registry, and within
    shared/BQoL/ the game loads files alphabetically -- BQoL_ItemParams sorts
    before BQoL_Registry, so without this the feature call at the bottom of
    this file hits a nil. Every other BQoL.feature caller is under client/,
    which the game loads only after all of shared/, so they get the registry
    for free; this file does not. It was in server/ (also loaded after
    shared/) until the multiplayer fix moved it here.
]]
require "BQoL/BQoL_Registry"

--[[
    Handheld flashlights get the Screwdriver attachment type so they can hang
    from the belt tool loop.

    Neither of these declares an AttachmentType in vanilla 42.20, so against
    vanilla alone we are adding one rather than replacing anything.
    `Screwdriver` is a real slot used by 14 vanilla items (Screwdriver, Scalpel,
    LetterOpener, IcePick, Scissors, ...) and is the tool loop
    (ISHotbarAttachDefinition.lua:14, :34).

    Against other mods we do replace, and deliberately -- see the note on
    retrofit below.
]]
local FLASHLIGHTS = {
    "Base.HandTorch",
    "Base.Flashlight_Crafted",
}

--- The slot every flashlight is retrofitted into. One name, one place.
local ATTACH_TYPE = "Screwdriver"

--- Set form of FLASHLIGHTS, for the per-item test below.
local IS_FLASHLIGHT = {}
for _, fullType in ipairs(FLASHLIGHTS) do
    IS_FLASHLIGHT[fullType] = true
end

--[[
    Published so the client half (BQoL_FlashlightSlot) works off the same list
    rather than a second copy of it. ISHotbar is client-only, so the code that
    consumes these cannot live here.
]]
BQoL.ItemParams = BQoL.ItemParams or {}
BQoL.ItemParams.ATTACH_TYPE = ATTACH_TYPE

--- True when `item` is one of the flashlights this feature retrofits.
function BQoL.ItemParams.isFlashlight(item)
    if item == nil then return false end

    local ok, fullType = BQoL.tryCall(item, { "getFullType" })
    if not ok or fullType == nil then return false end

    return IS_FLASHLIGHT[fullType] == true
end

--[[
    Gives one flashlight the attachment type it should have had at construction.

    Returns true when it actually changed something, so callers can log a real
    count rather than a number of items inspected.

    Narrow in WHICH ITEMS it touches -- the two full types in FLASHLIGHTS and
    nothing else -- and deliberately not narrow in what it writes. It replaces
    whatever type the item is carrying. 0.9.0 shipped the other way round,
    filling in a missing type only, and that is the bug this restores:

      AttachmentType is copied from the script item at construction and never
      re-read. Our own DoParam runs at OnGameStart, which is AFTER the player's
      inventory is deserialised, so any mod that patches the same script item at
      OnGameBoot wins for every carried item -- and one does. HavenFall's
      ESHF_TweakItem sets Base.HandTorch to `Torch` on OnGameBoot, so the
      carried torch comes back with a non-nil, non-belt type. The 0.9.0 guard
      read that as another mod's deliberate choice, declined, and the torch
      stopped going on the belt at all. The retrofit is not the place to
      arbitrate: TweakFlashlightSlot being on is the player asking for these two
      items on the tool loop, so on these two items we win, and the overwrite is
      logged so the conflict is visible in console.txt rather than silent.

    Still idempotent, which the caller needs: the client wrap runs inside
    ISHotbar's per-frame policing loop (see BQoL_FlashlightSlot), so the second
    call has to report no change or it would be a write every frame for the rest
    of the session. Testing against ATTACH_TYPE rather than against nil gives
    that just as well.
]]
function BQoL.ItemParams.retrofit(item)
    if not BQoL.ItemParams.isFlashlight(item) then return false end

    local ok, current = BQoL.tryCall(item, { "getAttachmentType" })
    if not ok or current == ATTACH_TYPE then return false end

    local wrote = BQoL.tryCall(item, { "setAttachmentType" }, ATTACH_TYPE)

    if wrote and current ~= nil then
        BQoL.log("ItemParams: %s carried attachment type %q; replaced with %q",
            tostring(select(2, BQoL.tryCall(item, { "getFullType" }))),
            tostring(current), ATTACH_TYPE)
    end

    return wrote
end

local function applyFlashlightSlot()
    local manager = getScriptManager()
    if not manager then
        BQoL.warn("ItemParams: no ScriptManager")
        return
    end

    local applied = 0

    for _, fullType in ipairs(FLASHLIGHTS) do
        local scriptItem = manager:getItem(fullType)

        if not scriptItem then
            -- Expected when another mod removed the item; not an error.
            BQoL.log("ItemParams: %s not found, skipping", fullType)
        else
            local ok = BQoL.safe(
                "ItemParams:" .. fullType,
                function() scriptItem:DoParam("AttachmentType = " .. ATTACH_TYPE) end
            )
            if ok then applied = applied + 1 end
        end

    end

    BQoL.log("ItemParams: flashlight slot applied to %d item(s)", applied)
end

--[[
    Retrofits flashlights that already existed when the script was patched.

    This is the half that was missing, and without it the feature does nothing
    for the one flashlight a player actually cares about.

    InventoryItem carries its own attachmentType field and copies it from the
    script item at construction; it never re-reads it. Verified directly in
    game: hold a reference to an item created before DoParam and it still
    reports nil afterwards, while an item created after reports Screwdriver.
    So patching the script only ever affects items built later.

    The tweak runs at OnGameStart, but the player's own inventory is
    deserialised before that, so a carried torch keeps attachmentType = nil
    permanently. Loot elsewhere is fine: container contents are rebuilt when
    their chunk loads, which is after OnGameStart.

    That makes the player's inventory the bounded set that needs fixing, and
    InventoryItem:setAttachmentType is writable at runtime (also verified) --
    including back to nil, so the sandbox toggle is still honourable.

    This sweep is the eager path and is NOT sufficient on its own: it cannot
    run before ISHotbar has already decided to strip the belt attachment. See
    the header of client/BQoL/BQoL_FlashlightSlot.lua, which is what actually
    fixes that.
]]
local function retrofitCarried(playerObj)
    if not playerObj then return 0 end

    local inventory = playerObj:getInventory()
    if not inventory then return 0 end

    local changed = 0

    for _, fullType in ipairs(FLASHLIGHTS) do
        local ok, items = BQoL.safe("ItemParams.retrofit:" .. fullType,
            function() return inventory:getAllTypeRecurse(fullType) end)

        if ok and items then
            for i = 0, items:size() - 1 do
                if BQoL.ItemParams.retrofit(items:get(i)) then
                    changed = changed + 1
                end
            end
        end
    end

    return changed
end

--[[
    Deferred by one tick rather than run inline with the script patch.

    On a multiplayer client the player's inventory arrives from the server and
    is not necessarily populated when OnGameStart fires, so sweeping there can
    find nothing. OnPlayerUpdate is guaranteed to have a real player; the
    sweep waits for a non-empty inventory, then removes itself so it costs
    nothing thereafter.
]]
local function scheduleRetrofit()
    -- Hard cap so a permanently-empty inventory (or a broken event) does not
    -- keep the handler alive for the whole session. 600 ticks is ~10s.
    local ticks = 0
    local MAX_TICKS = 600

    local function sweep(playerObj)
        ticks = ticks + 1

        --[[
            Retiring on the first tick defeated the purpose: on an MP client
            the carried inventory syncs in after the first OnPlayerUpdate, so
            the one sweep ran against an empty inventory and the flashlights
            that needed retrofitting kept their missing attachmentType for
            the whole session. Wait until there is something to inspect.
        ]]
        local inventory = playerObj and playerObj:getInventory()
        local hasItems = inventory and not inventory:getItems():isEmpty()
        if not hasItems and ticks < MAX_TICKS then return end

        Events.OnPlayerUpdate.Remove(sweep)

        local changed = retrofitCarried(playerObj)
        BQoL.log("ItemParams: retrofitted %d carried flashlight(s)", changed)
    end

    Events.OnPlayerUpdate.Add(sweep)
end

BQoL.feature{
    id = "ItemParams",
    sandbox = "TweakFlashlightSlot",
    init = function()
        applyFlashlightSlot()
        scheduleRetrofit()
    end,
}
