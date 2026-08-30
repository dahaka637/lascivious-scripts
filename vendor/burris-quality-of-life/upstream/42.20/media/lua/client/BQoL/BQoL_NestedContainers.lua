--[[
    Burris Quality of Life -- container buttons for bags inside bags.

    Which containers get a button and in what order is decided in
    shared/BQoL/BQoL_NestedLogic.lua. This file is the UI half: it adds the
    buttons, puts them in order, and works around one vanilla bug that only
    reordering exposes.

    It runs on OnRefreshInventoryWindowContainers at reason "buttonsAdded"
    (triggered at ISInventoryPage.lua:1801). That is the one moment where every
    vanilla button already exists and vanilla's own layout and scroll-height
    pass (:1898-1900) has not run yet, so the extra buttons are picked up by it
    rather than needing a second pass of our own.
]]

require "BQoL/BQoL_Core"

--- Mods that already do this; two of us would mean two buttons per bag.
local CONFLICTS = { "nm_nested_containers" }

--- Field the pooled buttons' original render is parked in once wrapped.
local RENDER_KEY = "BQoL_originalRender"

--- Field the overlay reads its icon from. Nil means "draw nothing".
local PARENT_TEX_KEY = "BQoL_parentTex"

-- --------------------------------------------------------------- helpers

--- Reads the sandbox options once per refresh into the context the logic wants.
local function buildContext(inventoryPage, playerObj)
    return {
        onCharacter  = inventoryPage.onCharacter and true or false,
        nestPlayer   = BQoL.getBool("NestedContainersPlayer"),
        playerFilter = BQoL.getNumber("NestedContainersPlayerFilter"),
        maxDepth     = BQoL.getNumber("NestedContainersDepth"),
        isEquipped   = function(item)
            local ok, equipped = BQoL.tryCall(playerObj, { "isEquipped" }, item)
            return ok and equipped == true
        end,
    }
end

--- Describes one button vanilla already made, for shouldNestContainer.
local function describe(inventory, playerObj)
    local _, containerType = BQoL.tryCall(inventory, { "getType" })
    local _, containingItem = BQoL.tryCall(inventory, { "getContainingItem" })
    local _, vehiclePart = BQoL.tryCall(inventory, { "getVehiclePart" })

    --[[
        The container's owning IsoObject -- a crate, a corpse, the IsoPlayer for
        the player's own inventory. Read for isVirtualContainer, which treats
        "owned by nothing" as the signature of a display-only aggregate. Note
        this is inventory:getParent() and has nothing to do with the parent
        BUTTON or with containingItem.
    ]]
    local _, parent = BQoL.tryCall(inventory, { "getParent" })

    local partCategory
    if vehiclePart then
        local ok, category = BQoL.tryCall(vehiclePart, { "getCategory" })
        if ok then partCategory = category end
    end

    local isEquipped = false
    if containingItem then
        local ok, equipped = BQoL.tryCall(playerObj, { "isEquipped" }, containingItem)
        isEquipped = ok and equipped == true
    end

    local _, playerInventory = BQoL.tryCall(playerObj, { "getInventory" })

    return {
        containerType       = containerType,
        containingItem      = containingItem,
        parent              = parent,
        vehiclePart         = vehiclePart,
        vehiclePartCategory = partCategory,
        isMainInventory     = inventory == playerInventory,
        isEquipped          = isEquipped,
    }
end

--[[
    Adds one nested button, tinted like vanilla tints a clothing container.

    The tint is not decoration -- without it every dyed bag renders in its
    undyed colour, so the nested buttons stop matching the ones vanilla drew
    directly above them. Copied from ISInventoryPage.lua:1575-1578.
]]
local function addButton(inventoryPage, item)
    local ok, inventory = BQoL.tryCall(item, { "getInventory" })
    if not ok or inventory == nil then return nil end

    local _, texture = BQoL.tryCall(item, { "getTex" })
    local _, name = BQoL.tryCall(item, { "getName" })

    local button = inventoryPage:addContainerButton(inventory, texture, name, name)
    if not button then return nil end

    local visual = select(2, BQoL.tryCall(item, { "getVisual" }))
    local clothing = select(2, BQoL.tryCall(item, { "getClothingItem" }))
    if visual and clothing then
        BQoL.safe("NestedContainers.tint", function()
            local tint = visual:getTint(clothing)
            button:setTextureRGBA(tint:getRedFloat(), tint:getGreenFloat(),
                tint:getBlueFloat(), 1.0)
        end)
    end

    return button
end

--[[
    Installs the parent-icon overlay on a button, once and for good.

    The icon it draws is read from a field on the button at draw time rather
    than captured when the wrapper was built. That is the whole design, and it
    is what makes the overlay safe on these particular buttons: they come out
    of ISInventoryPage's buttonPool and are handed straight back out for a
    different container on the next refresh (:1541-1546), so a closure holding
    last refresh's texture would go on drawing it over whatever the button had
    since become. Clearing one field is the entire cleanup, and an unwrapped
    field simply draws nothing.

    Wrapping once also means the closures cannot stack. Re-wrapping an already
    wrapped render every refresh would add one more nested call per refresh for
    as long as the window stayed open.
]]
local function ensureOverlay(button, cleanUI)
    if button[RENDER_KEY] then return end

    local original = button.render
    button[RENDER_KEY] = original

    button.render = function(self)
        original(self)

        local texture = self[PARENT_TEX_KEY]
        if not texture then return end

        -- CleanUI draws a tighter button; the vanilla margin overhangs it.
        local margin = cleanUI and 4 or 1
        local size = self.height / (cleanUI and 2.5 or 2)
        self:drawTextureScaled(texture, self.width - size - margin,
            self.height - size - margin, size, size, 1)
    end
end

-- ----------------------------------------------------------- the handler

local disarmed = false

local function nest(inventoryPage)
    local playerObj = getSpecificPlayer(inventoryPage.player)
    if not playerObj then return end

    local ctx = buildContext(inventoryPage, playerObj)
    local showParentIcon = BQoL.getBool("NestedContainersParentIcon")
    local cleanUI = BQoL.isModActive("CleanUI")

    --[[
        Ordered list of every button the sidebar should end up with: each
        existing one, immediately followed by whatever nests inside it.

        It has to be a separate table. addContainerButton appends to
        self.backpacks as it goes, so that table is growing underneath this
        loop -- hence the numeric bound, evaluated once, over the count that
        was there before any nesting. Without it the buttons this loop adds
        would be re-scanned as if they were vanilla's, and each one would nest
        its own contents a second time.
    ]]
    local ordered = {}
    local parentOf = {}

    --[[
        Every ItemContainer that already has a button, seeded before the walk
        starts and shared across it.

        The seeding is the half that matters here: it is what stops us adding a
        second button for a bag vanilla buttoned directly -- a bag lying on the
        ground, say, which also turns up inside whatever aggregate container
        another mod mirrored the square into. collectNested keeps filling it in
        so that two branches of one walk cannot collide either.
    ]]
    local seen = {}

    local existing = inventoryPage.backpacks
    for i = 1, #existing do
        if existing[i].inventory then seen[existing[i].inventory] = true end
    end

    for i = 1, #existing do
        local button = existing[i]
        table.insert(ordered, button)

        local inventory = button.inventory
        if inventory and BQoL.Nested.shouldNestContainer(ctx, describe(inventory, playerObj)) then
            for _, entry in ipairs(BQoL.Nested.collectNested(ctx, inventory, 1, seen)) do
                local nested = addButton(inventoryPage, entry.item)
                if nested then
                    table.insert(ordered, nested)
                    parentOf[nested] = entry.parent
                end
            end
        end
    end

    --[[
        Vanilla's own y arithmetic, from addContainerButton (:1465).

        The sort afterwards is not cosmetic. Vanilla sets the sidebar's scroll
        height from self.backpacks[#self.backpacks]:getBottom() (:1900, :533),
        which is only the bottom-most button if the list is in visual order --
        and the nested buttons were appended after the Floor button, not in
        the position they are drawn in. Without the sort the sidebar refuses
        to scroll down to them.
    ]]
    for i, button in ipairs(ordered) do
        button:setY(((i - 1) * inventoryPage.buttonSize) - 1)
    end
    table.sort(inventoryPage.backpacks, function(a, b) return a.y < b.y end)

    for _, button in ipairs(inventoryPage.backpacks) do
        --[[
            Suppress vanilla's double dispatch. addContainerButton sets both
            button.onclick and button.onMouseUp (:1487-1490), and
            onBackpackMouseUp (:1360) calls ISButton.onMouseUp -- which fires
            onclick -> page:onBackpackClick(button) -- and THEN calls
            page:onBackpackClick(self) itself. The first click runs
            selectContainer -> refreshBackpacks, which recycles every button
            into buttonPool and re-binds them in order (:1541-1546), so by the
            time the second dispatch runs the button it holds may point at a
            different container. In vanilla the rebuild is order-stable and
            the second call is a harmless repeat; once the buttons are
            reordered it opens the wrong container.

            ISButton:onMouseUp returns early on a nil onclick
            (ISButton.lua:42-44), leaving exactly one dispatch. Nothing calls
            forceClick() on a backpack button -- the only place onclick is
            invoked unguarded -- and addContainerButton already silences the
            activate sound, so nothing else is lost. Vanilla re-assigns
            onclick on every refresh, so switching this feature off mid-session
            leaks nothing.
        ]]
        button.onclick = nil

        --[[
            Cleared for every button on every pass, before this one is given
            its own icon. A pooled button that used to be nested and is now
            something else therefore loses the icon in the same sweep that
            would have set it.
        ]]
        button[PARENT_TEX_KEY] = nil

        local parentItem = showParentIcon and parentOf[button]
        if parentItem then
            local ok, texture = BQoL.tryCall(parentItem, { "getTex" })
            if ok and texture ~= nil then
                ensureOverlay(button, cleanUI)
                button[PARENT_TEX_KEY] = texture
            end
        end
    end
end

local function onRefresh(inventoryPage, reason)
    if disarmed or reason ~= "buttonsAdded" then return end
    if not inventoryPage or type(inventoryPage.backpacks) ~= "table" then return end

    --[[
        Disarmed rather than merely logged. This runs on every
        refreshBackpacks, which is several times a second while a container
        window is open, so a fault that warns and carries on would fill
        console.txt and keep re-breaking the sidebar. One warning, then the
        sidebar goes back to being vanilla's.
    ]]
    local ok, err = pcall(nest, inventoryPage)
    if not ok then
        disarmed = true
        BQoL.warn("NestedContainers failed and has been disabled for this " ..
            "session: %s", tostring(err))

        --[[
            Hand the sidebar back in a clean state. The buttons it already
            added stay until vanilla's next refresh rebuilds the list, but a
            half-finished pass can leave an icon on a button whose parent it
            never got to reassign -- and with the handler disarmed there is no
            later pass to clear it.
        ]]
        for _, button in ipairs(inventoryPage.backpacks) do
            button[PARENT_TEX_KEY] = nil
        end
    end
end

local function install()
    for _, modId in ipairs(CONFLICTS) do
        if BQoL.isModActive(modId) then
            BQoL.log("NestedContainers: standing down, %s is enabled", modId)
            return
        end
    end

    Events.OnRefreshInventoryWindowContainers.Add(onRefresh)
end

BQoL.feature{
    id = "NestedContainers",
    sandbox = "NestedContainersEnabled",
    init = install,
}
