# Integration Notes - Bug Fixes

- `module_key`: `bug-fixes`
- `bundled_mod_id`: `LS_BugFixes`
- Container submod for small game bug fixes that should live together instead of creating one PZ
  Mod ID per tiny patch.

## Included Fixes

### Map All Known Fix

- Workshop item `3785198639`
- Upstream folder `MapAllKnownFix`
- Original Mod ID `MapAllKnownFix`
- Bundled file: `42/media/lua/client/LS_BugFixes/MapAllKnownFix.lua`

The fix restores the expected multiplayer behavior of the vanilla sandbox option
`Map.MapAllKnown`. On MP clients, after game start/player creation, it retries a small number of
times and calls `WorldMapVisited.getInstance():setKnownInCells()` over the world meta-grid only when
the server sandbox option is enabled.

## Inventory and Gate

- Build 42 compatible (`versionMin=42.0.0` upstream), integrated for 42.20.x.
- Client-only Lua. No server commands, no client commands, no custom network namespace.
- No items, recipes, traits, perks, vehicles, Java/JAR, maps, tiledefs, packs, sandbox options or
  translation files.
- No `modData`, `GlobalModData` or persistent identifiers. Safe to add/remove from a save.
- No check of the original Mod ID in code, so bundling into `LS_BugFixes` is safe.
- No vanilla file override and no monkey-patch. It only adds listeners to `Events.OnGameStart`,
  `Events.OnCreatePlayer` and temporary `Events.OnTick`.

## Local Shape

The upstream fix is intentionally placed under a generic `LS_BugFixes` submod. Future tiny fixes can
be added beside it under `42/media/lua/client/LS_BugFixes/`, `server/LS_BugFixes/` or
`shared/LS_BugFixes/` as appropriate, with their own upstream snapshots under
`vendor/bug-fixes/upstream/<fix-key>/`.

## Collision Review

No bundled module touches `WorldMapVisited`, `Map.MapAllKnown`, `PlayerVisited` handling or the same
temporary retry function. Shared event surfaces are additive only.

## Remaining Risk

This depends on the B42.20.x client still exposing `WorldMapVisited.getInstance()` and
`setKnownInCells(minX, minY, maxX, maxY)`. If a future Project Zomboid build changes that API, this
container should be rechecked before release.
