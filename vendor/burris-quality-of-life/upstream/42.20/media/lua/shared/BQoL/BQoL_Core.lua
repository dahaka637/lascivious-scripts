--[[
    Burris Quality of Life -- core namespace and helpers.

    Files under a single mod root load in alphabetical order by path, so this
    file is NOT guaranteed to load before its siblings. Every BQoL module
    therefore bootstraps the namespace itself and only touches other modules
    from inside functions (i.e. at call time, never at load time).
]]

BQoL = BQoL or {}

BQoL.VERSION = "0.9.3"
BQoL.MOD_ID = "BurrisQoL"

--- Command module name used for sendClientCommand / OnClientCommand.
BQoL.COMMAND_MODULE = "BQoL"

-- ---------------------------------------------------------------- logging

local function emit(level, fmt, ...)
    local ok, msg = pcall(string.format, fmt, ...)
    if not ok then
        -- A bad format string must never take down the caller.
        msg = tostring(fmt)
    end
    print("[BQoL] " .. level .. ": " .. msg)
end

--- Always printed. Use sparingly -- boot banner, genuine problems.
function BQoL.info(fmt, ...)
    emit("INFO", fmt, ...)
end

--- Always printed. Something is wrong but the mod carries on.
function BQoL.warn(fmt, ...)
    emit("WARN", fmt, ...)
end

--- Only printed when the Debug sandbox option is on. Safe in hot paths.
function BQoL.log(fmt, ...)
    -- Guarded on existence, not just called: this file can load before
    -- BQoL_Settings.lua does, and logging must never be the thing that breaks.
    if BQoL.getBool and BQoL.getBool("Debug") then
        emit("DEBUG", fmt, ...)
    end
end

-- ------------------------------------------------------------ safe calls

--[[
    Wraps a call that reaches into the Java API. B42 moved a lot of Lua surface
    into Java between point releases, so anything that could vanish under us
    goes through here rather than being called bare.

    Returns ok, result -- on failure it logs once and returns false, nil.
]]
function BQoL.safe(what, fn, ...)
    if type(fn) ~= "function" then
        BQoL.warn("%s: not callable", tostring(what))
        return false, nil
    end

    local ok, result = pcall(fn, ...)
    if not ok then
        BQoL.warn("%s failed: %s", tostring(what), tostring(result))
        return false, nil
    end

    return true, result
end

--- True when `obj` exists and `obj[name]` is callable.
function BQoL.has(obj, name)
    return obj ~= nil and type(obj) == "table" and type(obj[name]) == "function"
end

--[[
    Calls the first accessor in `names` that the object actually has.

    Returns ok, result -- ok is false when the object is nil or none of the
    names resolve, exactly like BQoL.safe.

    This exists because of a bug that shipped and hid for several releases.
    Duck-typing a Java object as `obj.foo and obj:foo()` looks defensive, but
    the Lua/Java bridge is case-sensitive and a wrong-case name is not an
    error -- it is a silent nil, so the whole guard quietly evaluates to false
    and the caller carries on as if the check had passed. B42 is inconsistent
    about this in exactly the places that matter: IsoWindow and IsoThumpable
    expose only IsOpen(), while IsoDoor carries both IsOpen() and isOpen().
    Pry.classify checked the lowercase spelling, so its "skip open windows"
    guard never once fired and Pry Open was offered on every window in the
    game.

    Passing every plausible spelling through here means a name that is wrong
    on one class still works via another, and a name that is wrong on all of
    them reports ok == false instead of pretending to be a negative answer.
]]
function BQoL.tryCall(object, names, ...)
    if object == nil then return false, nil end

    for _, name in ipairs(names) do
        if object[name] ~= nil then
            return BQoL.safe("tryCall:" .. name, function(...)
                return object[name](object, ...)
            end, ...)
        end
    end

    return false, nil
end

--[[
    True when the mod with this id is in the active mod list.

    Used to stand down from a feature another installed mod already provides,
    rather than applying it twice -- two nested container buttons for one bag,
    two implementations of the same vanilla patch.

    The answer cannot change without a restart, so it is cached. Wrapped in
    safe() because getActivatedMods() is a client global: on a dedicated server
    this must answer "no", not throw.
]]
local activeMods = nil

function BQoL.isModActive(modId)
    if type(modId) ~= "string" then return false end

    if activeMods == nil then
        activeMods = {}

        local ok, list = BQoL.safe("isModActive", getActivatedMods)
        if ok and list then
            for i = 0, list:size() - 1 do
                local id = tostring(list:get(i))

                --[[
                    Vanilla's own two readers (ISPauseModListUI.lua:19,
                    ServerSettingsScreen.lua:2295) treat these as bare ids and
                    feed them straight to getModInfoByID. A separator prefix is
                    stripped rather than matched against, so a build that ever
                    does hand back a path does not silently match nothing --
                    which is the shape of the bug in the mod that inspired the
                    nested-container feature, whose check compares against
                    "\\" .. modID and therefore never fires.
                ]]
                id = string.gsub(id, "^[\\/]+", "")
                activeMods[id] = true
            end
        end
    end

    return activeMods[modId] == true
end

--- True when a global function/table path like "ISCampingMenu.onAddAllFuel" resolves.
function BQoL.resolve(path)
    local current = _G
    for part in string.gmatch(path, "[^%.]+") do
        if type(current) ~= "table" then return nil end
        current = current[part]
        if current == nil then return nil end
    end
    return current
end

--[[
    True when this machine can queue a timed action onto `character`.

    A shared timed action that defines complete() is mirrored to the server by
    LuaTimedActionNew, and a multiplayer client then skips its own Lua
    complete() altogether -- so for those actions complete() runs either in
    single player, or on the server, and nowhere else. See the note above
    BQoL_ApplyTourniquet:complete and commit eb54803.

    That makes ISTimedActionQueue a trap inside complete(): it lives in
    media/lua/client/, which a dedicated server never loads, so the global is
    nil there and indexing it kills the action mid-way -- "attempted index: add
    of non-table" -- which NetTimedAction then reports as "Perform failed".

    The isLocalPlayer half matters on a listen server, where the queue does
    exist but belongs to the host: without it a remote player's mirrored action
    would be queued onto the host's machine. Called through tryCall rather than
    bare, for the case-sensitivity reason documented there.
]]
function BQoL.hasLocalQueue(character)
    if not ISTimedActionQueue then return false end

    local ok, isLocal = BQoL.tryCall(character, { "isLocalPlayer" })
    return ok and isLocal == true
end

-- ------------------------------------------------------------- utilities

--- Clamped, zero-safe division. Guards the level-0 divide-by-zero class of bug.
function BQoL.divide(numerator, denominator, fallback)
    denominator = tonumber(denominator) or 0
    if denominator == 0 then
        return fallback or 0
    end
    return numerator / denominator
end

--[[
    Collects the squares a world context-menu click should consider.

    B42 does not reliably put the object you clicked into `worldobjects` -- the
    thing under the cursor is often the floor or a wall on the same tile -- so
    the 3x3 around fetchVars.clickedSquare is scanned as well. Squares are
    deduplicated, so a caller never sees the same tile twice.

    Client-only in practice (fetchVars is a client structure), but it lives here
    because several client features need it and duplicating a subtle scan is how
    they drift apart.
]]
function BQoL.gatherSquares(worldobjects)
    local squares, seen = {}, {}

    local function add(square)
        if square and not seen[square] then
            seen[square] = true
            table.insert(squares, square)
        end
    end

    for _, object in ipairs(worldobjects or {}) do
        if object and object.getSquare then
            add(object:getSquare())
        end
    end

    local clicked = ISWorldObjectContextMenu
        and ISWorldObjectContextMenu.fetchVars
        and ISWorldObjectContextMenu.fetchVars.clickedSquare

    --[[
        The clicked square must be checked before its neighbours, not merely
        included among them. worldobjects often resolves to a wall or floor
        rather than the door/window itself (see the comment above), so the
        add() calls above can easily finish without ever having queued the
        clicked square -- at which point the dx/dy loop below queued it only
        as a side effect of hitting dx=0,dy=0 partway through a fixed scan
        order, with three neighbours (dx=-1) already ahead of it. findTarget
        in BQoL_Pry_Menu returns the *first* classifiable object across these
        squares, so a window one tile from the door and scanned first was
        being offered -- and pried -- instead of the door the player actually
        clicked on.
    ]]
    if clicked then
        add(clicked)

        local cell = getCell()
        for dx = -1, 1 do
            for dy = -1, 1 do
                if dx ~= 0 or dy ~= 0 then
                    add(cell:getGridSquare(
                        clicked:getX() + dx, clicked:getY() + dy, clicked:getZ()))
                end
            end
        end
    end

    return squares
end

--- Attaches a tooltip to a context menu option using the pooled allocator.
function BQoL.tooltip(option, description)
    if not option then return end

    -- Guarded like gatherSquares above: this lives in shared/, and
    -- ISWorldObjectContextMenu only exists on a client. Every current caller
    -- is client menu code, so this is insurance rather than a live fix.
    if not ISWorldObjectContextMenu then return end

    local tooltip = ISWorldObjectContextMenu.addToolTip()
    tooltip.description = description
    option.toolTip = tooltip
    return tooltip
end
