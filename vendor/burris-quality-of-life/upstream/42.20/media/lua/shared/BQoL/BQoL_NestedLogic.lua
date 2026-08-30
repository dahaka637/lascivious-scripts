--[[
    Burris Quality of Life -- nested container buttons, decision half.

    Vanilla gives a sidebar container button to a narrow set of containers:

      - character window: the main inventory, plus EQUIPPED bags and key rings
        (ISInventoryPage.lua:1569-1580)
      - loot window: world containers, and bags lying loose on a square
        (:1691-1745)
      - vehicles: seats and trunks, plus one level of bags inside them
        (:1589-1604, :1760-1780)

    Which leaves a bag inside a bag, an unequipped bag in your own inventory,
    and a bag inside a crate with no button at all -- you have to open the
    parent and drill in by hand every time.

    This file decides which containers get an extra button and in what order.
    The UI half is client/BQoL/BQoL_NestedContainers.lua; nothing here touches
    a UI object, which is what lets the ordering and the cut-offs be asserted
    on directly. Getting either wrong is invisible in a screenshot and obvious
    after an hour of play.

    Only the player-inventory side actually descends beyond what vanilla
    already buttons. The loot side (crates, lockers, dressers, corpses) stops
    at vanilla's own buttons -- see the comment on shouldNestContainer's loot
    branch below for why: the same network-addressing limitation BLACKLIST
    exists for turns out to cover every loot-side container, not just the
    virtual aggregates BLACKLIST was written for.
]]

BQoL = BQoL or {}
BQoL.Nested = BQoL.Nested or {}

--[[
    Container types that must never be nested.

    The first group are VIRTUAL AGGREGATES: containers that hold a mirror of
    items which live somewhere else. Vanilla's floor container is the model
    (ISInventoryPage.lua:1534 builds it as ItemContainer.new("floor", nil, nil)
    and refills it from the surrounding squares every refresh); several mods add
    their own. Walking one of these hands a second button to every bag that
    already has one from the real container it lives in -- and that second
    button addresses the bag through a container the transfer path cannot
    resolve on a server, so items dragged to it hang with the progress bar full.
    Both faults were reported against 0.9.0.

    The names are CleanUI's, from ISLootWindowContainerControls.lua:47-53, which
    is the closest thing to a canonical list of them. It is worth reading why
    0.9.0 missed the Better Containers one despite carrying "proxInv": these are
    matched as substrings, and "proxInv" is not a substring of "proximityInv" --
    the `imity` intervenes. A name list cannot be relied on to be complete
    anyway, which is what isVirtualContainer below is for; this stays as the
    cheap first pass and as the record of which mods are known to do it.

    The three vehicle types are a different case: vanilla already nests those
    one level, so nesting them again puts two identical buttons in the sidebar
    for the same bag. Substring matching is what makes those work at all -- a
    trailer container reports e.g. "TrailerTrunk", not "Trailer".
]]
local BLACKLIST = {
    -- virtual aggregates
    "floor",
    "proxInv",          -- Proximity Inventory
    "proximityInv",     -- Better Containers, nearby loot
    "twistInv_corpses", -- Better Containers, nearby corpses
    "csrLootBag",       -- Common Sense Reborn, Nearby Loot
    -- already nested one level by vanilla
    "TruckBed",
    "Trailer",
    "Trunk",
}

--- Player-inventory filter, matching the sandbox enum's 1-based values.
BQoL.Nested.FILTER_ALL       = 1
BQoL.Nested.FILTER_POCKETS   = 2
BQoL.Nested.FILTER_EQUIPPED  = 3

--- True when this container type is one nesting must leave alone.
function BQoL.Nested.isBlacklistedType(containerType)
    if type(containerType) ~= "string" then return false end

    for _, needle in ipairs(BLACKLIST) do
        if string.find(containerType, needle, 1, true) then
            return true
        end
    end

    return false
end

--[[
    True when `item` is a key ring.

    Vanilla's own test, from the loop this feature extends
    (ISInventoryPage.lua:1572). The reference mod calls item:isKeyRing(), which
    appears nowhere in vanilla's Lua -- a name that does not resolve is a
    silent nil across the Java bridge rather than an error, so a guard built on
    it would quietly never fire. Both spellings go through tryCall for the
    reason documented on BQoL.tryCall.
]]
function BQoL.Nested.isKeyRing(item)
    if item == nil then return false end

    local ok, isType = BQoL.tryCall(item, { "isItemType" },
        ItemType and ItemType.KEY_RING)
    if ok and isType == true then return true end

    local tagged
    ok, tagged = BQoL.tryCall(item, { "hasTag" }, ItemTag and ItemTag.KEY_RING)
    return ok and tagged == true
end

--[[
    True when a container holds a mirror of items that live somewhere else.

    Structural, so it catches the aggregates BLACKLIST has never heard of --
    which matters, because the reported bug was an aggregate we had not heard
    of and the next one will be too.

    The test is ownership: a real container is reached FROM something. A bag has
    a containing item, a crate or a corpse has a parent IsoObject, a seat or a
    trunk has a vehicle part, and the player's own inventory has the IsoPlayer
    as its parent. A container owned by nothing at all is not somewhere in the
    world you can walk to -- it is a display fiction assembled by the UI, and
    everything in it is on loan from a container that does have an owner.
    Vanilla's own floor container is built exactly this way, with both arguments
    nil (ISInventoryPage.lua:1534).

    Note that `parent` here is inventory:getParent(), NOT the parent button --
    the client half passes them under distinct names for that reason.
]]
function BQoL.Nested.isVirtualContainer(info)
    if type(info) ~= "table" then return false end

    return info.containingItem == nil
        and info.parent == nil
        and info.vehiclePart == nil
end

--[[
    True when an existing container button's contents should be scanned.

    `info` describes one button vanilla already made:
      containerType      string   inventory:getType()
      containingItem     item     the bag this container belongs to, or nil
      parent             object   inventory:getParent(), or nil
      vehiclePart        object   inventory:getVehiclePart(), or nil
      vehiclePartCategory string  "seat" etc, or nil
      isMainInventory    boolean  this is the player's own inventory
      isEquipped         boolean  containingItem is worn
]]
function BQoL.Nested.shouldNestContainer(ctx, info)
    if type(ctx) ~= "table" or type(info) ~= "table" then return false end

    if BQoL.Nested.isBlacklistedType(info.containerType) then return false end
    if BQoL.Nested.isVirtualContainer(info) then return false end

    if ctx.onCharacter then
        if not ctx.nestPlayer then return false end

        --[[
            "Only pockets" means the main inventory and nothing worn; "only
            equipped" is its complement. Both are about which SIDE gets nested,
            so they are tested against the button being scanned rather than
            against the items found inside it.
        ]]
        local filter = ctx.playerFilter or BQoL.Nested.FILTER_ALL
        if filter == BQoL.Nested.FILTER_POCKETS and info.isEquipped then
            return false
        end
        if filter == BQoL.Nested.FILTER_EQUIPPED and info.isMainInventory then
            return false
        end

        return true
    end

    --[[
        Loot-side containers never get an extra button, at any depth. This
        looks like a missing feature but isn't one: it's the only network-safe
        answer.

        Every button this function approves eventually has to survive a round
        trip through zombie.network.fields.ContainerID, which is how a client's
        drag-and-drop identifies a container to the server. Decompiling it
        shows exactly three ways it can address one:

          - owned by the player (this function's onCharacter branch above) --
            resolved server-side by a genuinely recursive item lookup, so any
            depth works. This is the whole nestPlayer feature.
          - owned by a vehicle part -- resolved by a NON-recursive lookup one
            level into the part's own container. That's exactly the one level
            vanilla already buttons itself (:1589-1604, :1760-1780), which is
            why it never reaches this function to begin with.
          - owned by anything else (a crate, a locker, a dresser, a corpse) --
            addressed by an index into that object's own small, fixed list of
            built-in containers (how vanilla tells a fridge's two compartments
            apart, for instance). A bag's own inventory sitting inside one of
            these is not one of the object's registered compartments, so that
            index comes back invalid and the server can't recover the
            container at all. For a corpse it's worse still: corpses aren't
            even in the square's object list ContainerID indexes into, so the
            address is invalid before the compartment index is reached.

        So a crate, a locker, a dresser or a corpse -- everything left once
        the vehicle-part and player cases are accounted for -- has no
        network-safe way to button anything beyond what vanilla already shows
        directly. Approving one anyway doesn't fail loudly: the client sends a
        transfer the server can never resolve, so it never receives the
        isItemTransactionDone/isItemTransactionRejected signal it's waiting on
        and the timed action just sits at 100% forever. That is single-player-
        and listen-server-invisible (there the "client" and "server" are the
        same process and nothing goes over the wire), which is exactly why it
        shipped in 0.9.1 undetected until a dedicated-server report caught it.
    ]]
    return false
end

--[[
    True when `item` deserves a button vanilla did not already give it.

    The equipped/key-ring exclusion is not a preference: those two are exactly
    what the vanilla loop at ISInventoryPage.lua:1571-1579 already covers, and
    adding them again is a duplicate row in the sidebar.
]]
function BQoL.Nested.shouldButtonForItem(ctx, item)
    if item == nil then return false end

    local ok, isContainer = BQoL.tryCall(item, { "IsInventoryContainer" })
    if not ok or isContainer ~= true then return false end

    if ctx and ctx.onCharacter then
        if ctx.isEquipped and ctx.isEquipped(item) then return false end
        if BQoL.Nested.isKeyRing(item) then return false end
    end

    return true
end

--- Calls fn(item) for each item in a Java ItemContainer, safely.
local function eachItem(inventory, fn)
    local ok, items = BQoL.tryCall(inventory, { "getItems" })
    if not ok or items == nil then return end

    local size
    ok, size = BQoL.tryCall(items, { "size" })
    if not ok or type(size) ~= "number" then return end

    for i = 0, size - 1 do
        local got, item = BQoL.tryCall(items, { "get" }, i)
        if got and item ~= nil then
            fn(item)
        end
    end
end

--[[
    Walks a container's contents and returns the buttons to add, in order.

    Depth-first and pre-order, so each bag is immediately followed by the bags
    inside it -- which is what makes the sidebar read as a tree rather than as
    a flat pile in discovery order.

    `depth` is a parameter, not a counter held outside the recursion. The
    reference mod uses a file-local it increments and never decrements, so it
    measures how many containers have been seen so far in the whole subtree
    rather than how deep the current branch is: the first bag opened swallows
    the budget and its siblings get cut off at random.

    `seen` is an optional set of ItemContainers that already have a button. It
    is the last line of defence against a duplicate row, and it is deliberately
    keyed on the container rather than on the item or its name, because that is
    the identity the sidebar actually collides on: two buttons pointing at one
    ItemContainer are the same button drawn twice, whoever added them.

    Three separate things can put one bag in front of this walk twice -- a
    virtual aggregate mirroring a container we also scan directly, a second
    nested-container mod running alongside us, and a bag vanilla already
    buttoned that also turns up inside something we are scanning. Rather than
    enumerate them, refuse to button any container that already has one. The
    caller seeds the set from the buttons vanilla made; this fills it in as it
    goes, so siblings within one walk cannot collide either.

    A skipped bag is not descended into. Its contents are reachable from
    whichever button already owns it, and walking them here would rebuild the
    same subtree under the wrong parent.

    Returns a list of { item = <bag>, parent = <containing item or nil> }.
]]
function BQoL.Nested.collectNested(ctx, inventory, depth, seen)
    local found = {}
    if type(ctx) ~= "table" then return found end

    local maxDepth = tonumber(ctx.maxDepth) or 1
    depth = tonumber(depth) or 1
    if depth > maxDepth then return found end

    seen = seen or {}

    local ok, parent = BQoL.tryCall(inventory, { "getContainingItem" })
    if not ok then parent = nil end

    eachItem(inventory, function(item)
        if not BQoL.Nested.shouldButtonForItem(ctx, item) then return end

        local gotInner, innerInventory = BQoL.tryCall(item, { "getInventory" })
        if not gotInner or innerInventory == nil then return end

        if seen[innerInventory] then return end
        seen[innerInventory] = true

        table.insert(found, { item = item, parent = parent })

        for _, nested in ipairs(BQoL.Nested.collectNested(ctx, innerInventory, depth + 1, seen)) do
            table.insert(found, nested)
        end
    end)

    return found
end
