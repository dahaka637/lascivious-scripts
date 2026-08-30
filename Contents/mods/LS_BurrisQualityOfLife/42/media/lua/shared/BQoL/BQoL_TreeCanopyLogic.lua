--[[
    Burris Quality of Life -- tree canopy decision logic.

    Pure functions over plain values, so the rules can be exercised by
    tools/test/tree_canopy.lua without a running game. The client module
    (BQoL_TreeCanopy.lua) does the game-object plumbing and calls into here
    for every decision.

    Jumbo tree sizes come from the tile packs shipped in B42.20:
    media/jumbo_trees.tiles uses tree sizes 5 and 6, media/jumbo_trees_big.tiles
    uses 7 and 8. Normal growing trees use 1-4 (tiledefinitions_erosion).
    Verified against the shipped 42.20 media files.

    Behaviour modelled on the Jumbo Tree Indoor Fix workshop description:
    indoors every jumbo size is hidden; outdoors only the biggest tier is
    faded, so the forest keeps its shape; trunks always stay visible while
    driving or walking, because what you can hit must remain on screen.
]]

require "BQoL/BQoL_Core"

BQoL = BQoL or {}
BQoL.TreeCanopy = BQoL.TreeCanopy or {}

local TreeCanopy = BQoL.TreeCanopy

-- ------------------------------------------------------------ size classes

--- Lowest IsoTree size that counts as a jumbo tree (5-6 = jumbo, 7-8 = big).
TreeCanopy.JUMBO_SIZE_MIN = 5

--- Lowest size faded outdoors. The smaller tier is left alone while driving
--- or walking so the forest scenery stays intact; indoors covers every tier.
TreeCanopy.BIG_JUMBO_SIZE_MIN = 7

--- True when an IsoTree size belongs to any jumbo tier.
function TreeCanopy.isJumboSize(size)
    return (tonumber(size) or 0) >= TreeCanopy.JUMBO_SIZE_MIN
end

--- True when an IsoTree size belongs to the tier faded outdoors.
function TreeCanopy.isBigJumboSize(size)
    return (tonumber(size) or 0) >= TreeCanopy.BIG_JUMBO_SIZE_MIN
end

-- ------------------------------------------------------------- tuning math

--[[
    On-foot scan radius per sandbox range value (1 = standard, 2 = narrow,
    3 = minimal). Standard is wide enough that a canopy never pops in at the
    edge of the screen; minimal only clears the tiles directly overhead.
]]
function TreeCanopy.onFootRadius(rangeValue)
    local ranges = { [1] = 10, [2] = 6, [3] = 3 }
    return ranges[tonumber(rangeValue)] or ranges[1]
end

--[[
    How far ahead of a moving vehicle canopies are faded, in tiles.

    Scales with speed so wrecks and zombies hidden under a canopy stop being
    a surprise at highway speed, while crawling through a forest trail only
    clears what is right in front of the bonnet. The "short" range halves it
    for players who want the forest to close in more.

    `speedKmh` is clamped so a weird reading (teleport, physics spike) cannot
    produce an absurd scan area.
]]
function TreeCanopy.lookaheadTiles(speedKmh, rangeValue)
    local speed = math.max(0, math.min(120, tonumber(speedKmh) or 0))
    local base = 8 + speed * 0.1

    if tonumber(rangeValue) == 2 then
        base = base * 0.5
    end

    return math.floor(base + 0.5)
end

--[[
    Alpha applied to a canopy sprite at a given distance fraction.

    distFrac is distance / maxDistance clamped to 0..1: 0 is right on top of
    the player, 1 is at the edge of the affected area. Nearby canopies fade
    almost away; distant ones stay nearly solid, which avoids a visible wall
    of popping at the scan boundary. `floor` is the most transparent a canopy
    ever gets outdoors -- never fully gone, so the forest still reads as
    forest (that is what separates "fade" from "trunk only").
]]
function TreeCanopy.canopyAlpha(distFrac, floor)
    local frac = tonumber(distFrac) or 0
    frac = math.max(0, math.min(1, frac))

    local minimum = tonumber(floor) or 0.2
    return minimum + (1 - minimum) * frac
end

-- ----------------------------------------------------------- sprite roles

--[[
    Decides whether a sprite name is part of a jumbo tree, and which role it
    plays. `canopyPrefixes` and `trunkPrefixes` are lists built at runtime
    from IsoTreeJumbo.Jumbos; `apiSprites` is the BQoL.API registry mapping
    sprite name -> "canopy"/"trunk".

    Matching is prefix-based because the registry holds base names
    ("e_yellowwoodJUMBO_treetop") while placed objects carry indexed tile
    names ("..._1_3"). Returns "canopy", "trunk", or nil when the sprite is
    not recognised as part of a jumbo tree.
]]
function TreeCanopy.matchSpriteRole(spriteName, canopyPrefixes, trunkPrefixes, apiSprites)
    if type(spriteName) ~= "string" or spriteName == "" then return nil end

    local registered = apiSprites and apiSprites[spriteName]
    if registered then return registered end

    for _, prefix in ipairs(canopyPrefixes or {}) do
        if spriteName == prefix or spriteName:sub(1, #prefix) == prefix then
            return "canopy"
        end
    end

    for _, prefix in ipairs(trunkPrefixes or {}) do
        if spriteName == prefix or spriteName:sub(1, #prefix) == prefix then
            return "trunk"
        end
    end

    return nil
end

--[[
    Fallback for sprites that carry the JUMBO marker in their name but were
    not matched against the registry (a new species added by a game update,
    for example). Vanilla jumbo tile names all contain "JUMBO".

    Outdoors the safe default is "trunk" -- fading something we failed to
    classify could hide a trunk, and hiding a trunk hides something the
    player can crash into. Indoors every jumbo is hidden anyway, so the
    fallback costs nothing there.
]]
function TreeCanopy.hasJumboMarker(spriteName)
    return type(spriteName) == "string" and spriteName:find("JUMBO", 1, true) ~= nil
end
