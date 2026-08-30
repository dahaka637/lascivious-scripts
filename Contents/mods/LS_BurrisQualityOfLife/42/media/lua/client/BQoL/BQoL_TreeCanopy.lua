--[[
    Burris Quality of Life -- jumbo tree canopy fix.

    Build 42.20 added huge jumbo trees whose canopies sketch over indoor
    rooms and hide the road while driving. This feature fades or hides them
    client-side:

      - indoors, every jumbo tree within TreeCanopyIndoorRadius is hidden
        (canopy and trunk) so furniture and windows stay visible;
      - while driving, canopies of the biggest tier ahead of the vehicle are
        faded -- trunks stay, because what you can hit must remain visible;
      - while moving on foot, canopies of the biggest tier around you are
        faded, restoring when you stand still.

    Everything is done through IsoObject.setTargetAlpha, vanilla's own
    occlusion-fade mechanism (verified public in the shipped 42.20 jar), so
    the engine smoothly lerps the fade and restores it when we stop
    asserting. Alpha is render state only: nothing is written to the save,
    nothing is sent to the server, and in multiplayer each client sees its
    own view. In local split screen both players share one rendering of the
    world, so fades applied for one player show on both screens -- same
    limitation the mod this is inspired by has.

    Scans are throttled: the affected set is rebuilt every SCAN_INTERVAL
    ticks rather than every frame, and objects that leave the set are
    restored once and forgotten. Chunk unloading invalidates nothing -- a
    reloaded tree comes back with vanilla alpha and is re-faded on the next
    scan if still in range.
]]

require "BQoL/BQoL_Core"
require "BQoL/BQoL_TreeCanopyLogic"

local TreeCanopy = BQoL.TreeCanopy

--- Ticks between full scans. At 60 ticks a second this is four scans a
--- second -- often enough that driving never outruns the look-ahead, rare
--- enough that the square scan is not measurable in a frame profile.
local SCAN_INTERVAL = 15

--- Below this movement per tick (tiles) the player counts as standing still,
--- so canopies restore instead of flickering from animation jitter.
local MOVEMENT_EPSILON = 0.005

-- ------------------------------------------------------- jumbo name sets

--[[
    Sprite-prefix lists built once from IsoTreeJumbo.Jumbos, vanilla's own
    registry of jumbo tree descriptions. Each TreeDescription record exposes
    main/treetop/trunk/stump/burned/burnedFrozen base names; treetop goes to
    the canopy list, everything else to the trunk list.

    Built lazily because the class is not guaranteed to be loaded at file
    scope, and wrapped in BQoL.safe so a future game update that reshapes
    the registry degrades to "no registry matching" rather than killing the
    feature -- getSize() and the JUMBO name marker still classify trees.
]]
local canopyPrefixes, trunkPrefixes

local function addPrefix(list, value)
    if type(value) == "string" and value ~= "" then
        table.insert(list, value)
    end
end

local function buildNameSets()
    if canopyPrefixes then return end
    canopyPrefixes, trunkPrefixes = {}, {}

    if not IsoTreeJumbo then
        BQoL.log("TreeCanopy: IsoTreeJumbo not present; size/marker fallback only")
        return
    end

    BQoL.safe("TreeCanopy.buildNameSets", function()
        local iterator = IsoTreeJumbo.Jumbos:entrySet():iterator()
        while iterator:hasNext() do
            local entry = iterator:next()
            local description = entry:getValue()

            addPrefix(canopyPrefixes, description:treetop())
            addPrefix(trunkPrefixes, description:main())
            addPrefix(trunkPrefixes, description:trunk())
            addPrefix(trunkPrefixes, description:stump())
            addPrefix(trunkPrefixes, description:burned())
            addPrefix(trunkPrefixes, description:burnedFrozen())
        end

        BQoL.log("TreeCanopy: %d canopy prefixes, %d trunk prefixes",
            #canopyPrefixes, #trunkPrefixes)
    end)
end

-- ------------------------------------------------------------ object scan

--[[
    Classifies one world object. Returns "canopy" or "trunk" for jumbo tree
    parts, nil otherwise. `outdoorsOnly` restricts to the biggest tier.
]]
local function classifyObject(object, outdoorsOnly)
    if not instanceof(object, "IsoTree") then return nil end

    local ok, size = BQoL.safe("TreeCanopy.getSize", function() return object:getSize() end)
    if not ok then return nil end
    size = tonumber(size) or 0

    if outdoorsOnly and not TreeCanopy.isBigJumboSize(size) then return nil end
    if not outdoorsOnly and not TreeCanopy.isJumboSize(size) then
        -- API-registered sprites may not carry a jumbo size; still honour them.
        local ok2, spriteName = BQoL.safe("TreeCanopy.sprite", function()
            return object:getSprite() and object:getSprite():getName() end)
        if ok2 and spriteName then
            return TreeCanopy.matchSpriteRole(spriteName,
                canopyPrefixes, trunkPrefixes, BQoL.API.getJumboTreeSprites())
        end
        return nil
    end

    local ok3, spriteName = BQoL.safe("TreeCanopy.sprite", function()
        return object:getSprite() and object:getSprite():getName() end)
    if not ok3 or not spriteName then return nil end

    local role = TreeCanopy.matchSpriteRole(spriteName,
        canopyPrefixes, trunkPrefixes, BQoL.API.getJumboTreeSprites())

    --[[
        Registry miss on a jumbo-sized tree: the JUMBO name marker keeps the
        tree recognised. Outdoors the safe fallback is "trunk" (leave it
        visible); indoors the caller hides every jumbo part anyway.
    ]]
    if not role and TreeCanopy.hasJumboMarker(spriteName) then
        role = "trunk"
    end

    return role
end

-- ----------------------------------------------------------- alpha state

--[[
    Objects we currently hold a non-vanilla alpha target on, keyed by the
    object itself. Values are the target alpha, so a re-scan that changes a
    canopy's distance can retarget without a restore first.
]]
local affected = {}

local function assertAlpha(object, target)
    BQoL.safe("TreeCanopy.setAlpha", function()
        object:setTargetAlpha(target)
    end)
    affected[object] = target
end

local function restoreAll()
    for object in pairs(affected) do
        -- The object may have streamed out with the chunk; a dead reference
        -- just gets dropped, its replacement loads with vanilla alpha.
        BQoL.safe("TreeCanopy.restore", function()
            object:setTargetAlpha(1)
        end)
    end
    affected = {}
end

--- Releases objects that are no longer in the wanted set.
local function reconcile(wanted)
    for object in pairs(affected) do
        if not wanted[object] then
            BQoL.safe("TreeCanopy.restore", function()
                object:setTargetAlpha(1)
            end)
            affected[object] = nil
        end
    end
end

-- ------------------------------------------------------------ state scan

local lastX, lastY
local tickCount = 0

--[[
    Collects jumbo tree parts on the squares within `radius` of (cx, cy) and
    applies the alpha for their role. Returns the wanted set for reconcile().
]]
local function scanArea(cx, cy, z, radius, outdoorsOnly, hideStyle)
    local cell = getCell()
    local wanted = {}
    local maxDist = math.max(1, radius)

    for dx = -radius, radius do
        for dy = -radius, radius do
            local square = cell:getGridSquare(cx + dx, cy + dy, z)
            if square then
                local objects = square:getObjects()
                for i = 0, objects:size() - 1 do
                    local object = objects:get(i)
                    local role = classifyObject(object, outdoorsOnly)

                    if role then
                        local dist = math.sqrt(dx * dx + dy * dy)
                        local target

                        if not outdoorsOnly then
                            -- Indoors: hide every jumbo part outright.
                            target = 0
                        elseif role == "canopy" then
                            if hideStyle == 2 then
                                target = 0
                            else
                                target = TreeCanopy.canopyAlpha(dist / maxDist, 0.2)
                            end
                        else
                            target = 1 -- trunk: always visible outdoors
                        end

                        wanted[object] = true
                        if affected[object] ~= target then
                            assertAlpha(object, target)
                        end
                    end
                end
            end
        end
    end

    return wanted
end

local function onTick()
    -- Live master switch: sandbox changes take effect without a reload, and
    -- turning the feature off must hand every tree back to vanilla, not
    -- leave the last fade frozen on screen.
    if not BQoL.getBool("TreeCanopyEnabled") then
        restoreAll()
        return
    end

    tickCount = tickCount + 1
    if tickCount % SCAN_INTERVAL ~= 0 then return end

    local player = getPlayer()
    if not player then
        restoreAll()
        return
    end

    buildNameSets()

    local ok, square = BQoL.safe("TreeCanopy.square", function()
        return player:getCurrentSquare() end)
    if not ok or not square then
        restoreAll()
        return
    end

    local px, py, pz = player:getX(), player:getY(), square:getZ()
    local ix, iy = math.floor(px), math.floor(py)

    -- Movement from position deltas: one code path covers walking, running
    -- and being a passenger, with no animation-state API to drift under us.
    -- The delta is captured before lastX/lastY are updated, so the driving
    -- look-ahead can reuse it as the direction of travel.
    local deltaX, deltaY, moved = 0, 0, 0
    if lastX then
        deltaX, deltaY = px - lastX, py - lastY
        moved = math.sqrt(deltaX * deltaX + deltaY * deltaY)
    end
    lastX, lastY = px, py

    local wanted = nil

    -- BQoL.safe returns (ok, result): both values must be captured here.
    -- `local indoors = BQoL.safe(...) and true or false` would keep only the
    -- first return value -- the success flag -- and treat every successful
    -- call as "indoors", which is exactly the bug this comment now guards.
    local okRoom, inRoom = BQoL.safe("TreeCanopy.indoors", function()
        return square:isInARoom() end)
    local indoors = okRoom and inRoom == true

    if indoors then
        local radius = math.max(0, BQoL.getNumber("TreeCanopyIndoorRadius"))
        if radius > 0 then
            wanted = scanArea(ix, iy, pz, radius, false, 1)
        end
    else
        local okVehicle, vehicle = BQoL.safe("TreeCanopy.vehicle", function()
            return player:getVehicle() end)
        if not okVehicle then vehicle = nil end

        if vehicle and BQoL.getBool("TreeCanopyWhileDriving") then
            local okSpeed, speedKmh = BQoL.safe("TreeCanopy.speed", function()
                return vehicle:getCurrentSpeedKmHour() end)
            local speed = (okSpeed and tonumber(speedKmh)) or 0

            if speed > 2 then
                -- Look ahead along the movement vector so canopies are
                -- cleared where the vehicle is going, not where it sits.
                local range = BQoL.getNumber("TreeCanopyDrivingRange")
                local ahead = TreeCanopy.lookaheadTiles(speed, range)
                local dirX, dirY = 0, 0
                if moved > MOVEMENT_EPSILON * SCAN_INTERVAL then
                    local len = math.sqrt(deltaX * deltaX + deltaY * deltaY)
                    if len > 0 then dirX, dirY = deltaX / len, deltaY / len end
                end
                local cx = math.floor(px + dirX * ahead * 0.5)
                local cy2 = math.floor(py + dirY * ahead * 0.5)
                local scanRadius = math.max(4, math.floor(ahead * 0.6))
                wanted = scanArea(cx, cy2, pz, scanRadius, true,
                    BQoL.getNumber("TreeCanopyHideStyle"))
            end
        elseif not vehicle and BQoL.getBool("TreeCanopyOnFoot")
            and moved > MOVEMENT_EPSILON * SCAN_INTERVAL then
            local radius = TreeCanopy.onFootRadius(BQoL.getNumber("TreeCanopyOnFootRange"))
            wanted = scanArea(ix, iy, pz, radius, true,
                BQoL.getNumber("TreeCanopyHideStyle"))
        end
    end

    reconcile(wanted or {})
end

BQoL.feature{
    id = "TreeCanopy",
    sandbox = "TreeCanopyEnabled",
    init = function()
        Events.OnTick.Add(onTick)
    end,
}
