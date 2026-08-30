# Wilderness Spawnpoints — Integration Report

## Identity

- Module key: `wilderness-spawnpoints`
- Bundled Mod ID: `LS_WildernessSpawnpoints`
- Source Workshop ID: `3513206060`
- Source Mod ID: `LMWildSpawnMaps`
- Content shipped: 29 individually selectable spawn regions named `LS_WS_*`

## Selected scope

The source offers separate “all maps” and random-selection variants. This bundle deliberately uses only the 29 individual locations from the all-maps variant, matching the requested behavior:

- every source location remains independently selectable;
- no automatic or random selection;
- no profession, trait, clothing, inventory, character or sandbox filtering;
- no runtime Lua hook beyond the engine's standard `SpawnPoints()` files.

The locations comprise isolated cabins, houses, camps, woods, rivers and ponds. The coordinates themselves are unchanged.

## Gate and inventory

The selected source variant contains 29 map directories, each with `map.info`, `spawnpoints.lua`, preview media and EN/PTBR display text. It has no required dependency, networking, ModData, save migration, Java/JAR, sandbox option or vanilla-file override.

The source declared its random sibling as incompatible. That declaration was omitted because the sibling is not bundled. The selected variant is otherwise self-contained.

## Snapshot and adaptation

The complete selected source tree is preserved at `vendor/wilderness-spawnpoints/upstream/42` (324 files). The runtime bundle is intentionally lean:

- the Mod ID is namespaced as `LS_WildernessSpawnpoints`;
- all 29 region directories and translation directories are namespaced from `WS_*` to `LS_WS_*`;
- each exact coordinate and the `unemployed` fallback are preserved;
- `map.info` translation fallback paths, zoom and `lots=Muldraugh, KY` are preserved;
- `only_for_game_mode=Sandbox` was added explicitly;
- preview screenshots and videos were omitted from runtime because they do not affect spawning;
- only EN and reviewed PTBR display text are shipped.

Two source metadata typos were repaired: the dry-cabin title referenced the nonexistent directory
`WS_Cabin_Dryd`, and the two-ponds description referenced `WWS_TwoPond`. They now resolve to the
existing namespaced directories `LS_WS_Cabin_Dry` and `LS_WS_TwoPonds`.

The 29 coordinates were mechanically compared with the non-debug coordinate set of the source's random variant: the sets match exactly. They were also visually checked against the current Build 42 map and all resolve to land or intended structures.

The earlier candidate from Workshop ID `3677392791` is retained only as an audit reference under `reference-3677392791`; its single point is not shipped.

## Translation

All 29 titles and 29 descriptions are available in EN and PTBR. PTBR cleanup corrected wording, label formatting, alignment markup and a few literal mistranslations while preserving location meaning and difficulty information. See `TRANSLATION_PTBR.md`.

These translation files are direct engine map metadata (`title.txt` and `description.txt`), not Lua tables; UTF-8 accents are therefore intentional.

## Server integration

The server uses an explicit `/home/dahaka/Zomboid/Server/LASCIVIOUS_spawnregions.lua`, which takes precedence over automatic region discovery. Its table received all 29 entries during local test-server configuration on 2026-08-28, with PTBR display names and namespaced file paths. `SERVER_SPAWN_REGIONS.md` keeps the portable reference list.

The server's existing `Map=Muldraugh, KY` remains valid: these are spawn-region definitions only and add no map cells. Every region continues to use `lots=Muldraugh, KY`.

## Risk and test focus

Static integration risk is low: the module contains only namespaced map metadata and standard spawnpoint functions, with no runtime event hooks or network protocol. Runtime validation should confirm that all 29 entries appear in the new-character region selector and that a character created with a chosen entry arrives at its documented coordinate.
