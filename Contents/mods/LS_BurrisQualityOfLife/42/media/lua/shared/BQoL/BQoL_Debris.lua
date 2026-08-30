--[[
    Burris Quality of Life -- ground-debris sprite mappings.

    Registers the `d_generic_1` tileset (tiledefinitions_erosion.tiles.txt) --
    the loose twigs, grass tufts and rocks scattered on grass that you can see
    but mostly cannot right-click and pick up.

    "Mostly" is the operative word, and this is grounded in real data, not a
    guess. Vanilla already has a working pickup path for this tileset:
    ISWorldObjectContextMenuLogic offers ISWorldObjectContextMenu.
    onPickupGroundCoverItem (shared/TimedActions/ISPickUpGroundCoverItem.lua)
    for any sprite whose tiledef entry carries a `CustomName` property whose
    value it recognises (GroundCoverItems in that same file: Twigs,
    TreeBranch2, StoneTwigs, LargeStone, FlatStone, 4Stones, Log, Limestone).

    Checked every sprite in the tileset for that property directly. Of 80:

      - 20 carry a recognised CustomName -- vanilla already handles these,
        left untouched here (indices 8,9-15,22-25,28,31,40-45 -- see the
        SKIP list below for the exact set, which includes two values,
        "Small" and "Stone2", that don't match any GroundCoverItems key and
        so may or may not actually work; left alone rather than risk a
        duplicate menu entry on a guess).
      - 28 carry no CustomName at all, in the light/non-blocking rows
        (BlocksPlacement unset -- confirmed thin twig/grass silhouettes via
        the tileset's own depth map).
      - 32 carry no CustomName at all, in the solid/blocking rows
        (BlocksPlacement set -- confirmed via the same depth map to include
        genuine round rock shapes, mixed with sticks/logs the silhouette
        alone couldn't cleanly separate).

    Those last 60 are the real gap, and almost certainly what actually
    prompted this feature: the chunky rock-looking sprites sit in the
    BlocksPlacement-set group, which is entirely untagged in vanilla.

    Mapped in tiers rather than per-sprite, since finer distinctions within
    a tier aren't reliably readable from a depth map alone: light group ->
    Twigs, most of the solid group -> Stone2. If a specific sprite should
    give something else once you've actually looked at it in-game, override
    it with BQoL.API.addDebrisMapping("d_generic_1_<N>", { { "Base.Whatever", count } }).

    That "mixed with sticks/logs" note above isn't a hedge -- vanilla's own
    tagged sprites in this tileset back it up. CustomName "Log" (index 31)
    and "TreeBranch2" (index 12) both sit in the light, non-blocking rows,
    right next to the untagged Twigs-like sprites, while every stone variant
    (LargeStone/FlatStone/4Stones/Stone2) sits in a blocking row. Thin sticks
    not blocking movement and rocks/logs doing so tracks -- but it also means
    some of the untagged *solid* sprites are plausibly logs rather than
    rocks. There's no atlas coordinate data available to say exactly which
    (see above), so rather than fold everything into Stone2 and hide that,
    the last 8-wide band of the solid group is split off to Log/TreeBranch2
    as an explicit, correctable guess.
]]

require "BQoL/BQoL_API"

local LIGHT_ITEMS = { { "Base.Twigs", 1 } }
local STONE_ITEMS = { { "Base.Stone2", 1 } }
local LOG_ITEMS = { { "Base.Log", 1 } }
local BRANCH_ITEMS = { { "Base.TreeBranch2", 1 } }

-- Untagged, light/non-blocking rows (0-47).
local LIGHT_INDICES = {
    0, 1, 2, 3, 4, 5, 6, 7,
    16, 17, 18, 19, 20, 21,
    26, 27, 29, 30,
    32, 33, 34, 35, 36, 37, 38, 39,
    46, 47,
}

-- Untagged, solid/blocking rows (48-95, three 8-wide bands) -- kept as Stone2.
local SOLID_STONE_INDICES = {
    48, 49, 50, 51, 52, 53, 54, 55,
    64, 65, 66, 67, 68, 69, 70, 71,
    80, 81, 82, 83, 84, 85, 86, 87,
}

-- Untagged, solid/blocking, last band (96-103) -- split to wood, see above.
local SOLID_LOG_INDICES = { 96, 97, 98, 99 }
local SOLID_BRANCH_INDICES = { 100, 101, 102, 103 }

for _, i in ipairs(LIGHT_INDICES) do
    BQoL.API.addDebrisMapping("d_generic_1_" .. i, LIGHT_ITEMS)
end
for _, i in ipairs(SOLID_STONE_INDICES) do
    BQoL.API.addDebrisMapping("d_generic_1_" .. i, STONE_ITEMS)
end
for _, i in ipairs(SOLID_LOG_INDICES) do
    BQoL.API.addDebrisMapping("d_generic_1_" .. i, LOG_ITEMS)
end
for _, i in ipairs(SOLID_BRANCH_INDICES) do
    BQoL.API.addDebrisMapping("d_generic_1_" .. i, BRANCH_ITEMS)
end
