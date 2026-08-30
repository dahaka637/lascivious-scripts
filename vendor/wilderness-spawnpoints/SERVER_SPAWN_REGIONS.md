# Wilderness Spawnpoints — Server Spawn Regions

The dedicated server uses an explicit spawn-region table. These 29 paths were added to the existing table in `/home/dahaka/Zomboid/Server/LASCIVIOUS_spawnregions.lua` on 2026-08-28 without replacing its vanilla entries. The live configuration uses the reviewed PTBR titles as display names; the stable technical identifiers below remain a portable reference for the same paths.

```lua
{ name = "LS_WS_Cabin_Abandonned", file = "media/maps/LS_WS_Cabin_Abandonned/spawnpoints.lua" },
{ name = "LS_WS_Cabin_BoardingSchool", file = "media/maps/LS_WS_Cabin_BoardingSchool/spawnpoints.lua" },
{ name = "LS_WS_Cabin_Den", file = "media/maps/LS_WS_Cabin_Den/spawnpoints.lua" },
{ name = "LS_WS_Cabin_Dry", file = "media/maps/LS_WS_Cabin_Dry/spawnpoints.lua" },
{ name = "LS_WS_Cabin_Hunter", file = "media/maps/LS_WS_Cabin_Hunter/spawnpoints.lua" },
{ name = "LS_WS_Cabin_InWoods", file = "media/maps/LS_WS_Cabin_InWoods/spawnpoints.lua" },
{ name = "LS_WS_Cabin_LakeHouse", file = "media/maps/LS_WS_Cabin_LakeHouse/spawnpoints.lua" },
{ name = "LS_WS_Cabin_Retreat", file = "media/maps/LS_WS_Cabin_Retreat/spawnpoints.lua" },
{ name = "LS_WS_Cabin_River", file = "media/maps/LS_WS_Cabin_River/spawnpoints.lua" },
{ name = "LS_WS_Cabin_SurvivorCamp", file = "media/maps/LS_WS_Cabin_SurvivorCamp/spawnpoints.lua" },
{ name = "LS_WS_Cabin_TheKnowby", file = "media/maps/LS_WS_Cabin_TheKnowby/spawnpoints.lua" },
{ name = "LS_WS_Cabin_TheLife", file = "media/maps/LS_WS_Cabin_TheLife/spawnpoints.lua" },
{ name = "LS_WS_Cabin_TotalIsolation", file = "media/maps/LS_WS_Cabin_TotalIsolation/spawnpoints.lua" },
{ name = "LS_WS_Cabin_Trash", file = "media/maps/LS_WS_Cabin_Trash/spawnpoints.lua" },
{ name = "LS_WS_Cabin_Workshop", file = "media/maps/LS_WS_Cabin_Workshop/spawnpoints.lua" },
{ name = "LS_WS_DeepInWoods", file = "media/maps/LS_WS_DeepInWoods/spawnpoints.lua" },
{ name = "LS_WS_GreatRiver", file = "media/maps/LS_WS_GreatRiver/spawnpoints.lua" },
{ name = "LS_WS_LongOnes", file = "media/maps/LS_WS_LongOnes/spawnpoints.lua" },
{ name = "LS_WS_LongSnake", file = "media/maps/LS_WS_LongSnake/spawnpoints.lua" },
{ name = "LS_WS_OtterPond", file = "media/maps/LS_WS_OtterPond/spawnpoints.lua" },
{ name = "LS_WS_RiverElbow", file = "media/maps/LS_WS_RiverElbow/spawnpoints.lua" },
{ name = "LS_WS_TheLips", file = "media/maps/LS_WS_TheLips/spawnpoints.lua" },
{ name = "LS_WS_TheManyPonds", file = "media/maps/LS_WS_TheManyPonds/spawnpoints.lua" },
{ name = "LS_WS_TheMouth", file = "media/maps/LS_WS_TheMouth/spawnpoints.lua" },
{ name = "LS_WS_ThePond", file = "media/maps/LS_WS_ThePond/spawnpoints.lua" },
{ name = "LS_WS_TheTip", file = "media/maps/LS_WS_TheTip/spawnpoints.lua" },
{ name = "LS_WS_ThreePonds", file = "media/maps/LS_WS_ThreePonds/spawnpoints.lua" },
{ name = "LS_WS_TwoPonds", file = "media/maps/LS_WS_TwoPonds/spawnpoints.lua" },
{ name = "LS_WS_WaterAllAround", file = "media/maps/LS_WS_WaterAllAround/spawnpoints.lua" },
```

This module adds spawn definitions only. It does not add world map cells, so the existing server `Map=` setting does not require an entry for these names.
