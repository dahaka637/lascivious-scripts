# Wilderness Spawnpoints — Local Changes

## LS-001 — Bundle identity and Build 42 layout

- Renamed the Mod ID to `LS_WildernessSpawnpoints`.
- Kept the module in the canonical `common/` plus `42/` bundle layout.
- Declared `versionMin=42.20`.

## LS-002 — Namespace all spawn regions

- Renamed every source `WS_*` map folder and translation folder to `LS_WS_*`.
- Updated all corresponding `map.info` translation paths.
- Preserved every exact source coordinate and the `unemployed` fallback.

## LS-003 — Ship only individual locations

- Excluded the source's random-selection variant, runtime hooks, filters, sandbox options and debug coordinates.
- Omitted preview screenshots and videos from the runtime bundle.
- Removed obsolete `demoVideo` metadata references.

## LS-004 — Explicit game-mode scope

- Added `only_for_game_mode=Sandbox` to all 29 `map.info` files.

## LS-005 — PTBR review

- Reviewed all 29 titles and descriptions.
- Corrected terminology, grammar, label spacing and broken display markup without changing gameplay meaning.

## LS-006 — Broken translation paths

- Corrected the source typo `WS_Cabin_Dryd` to the existing namespaced directory
  `LS_WS_Cabin_Dry`, restoring the title in the spawn selector.
- Corrected the source typo `WWS_TwoPond` to `LS_WS_TwoPonds`, restoring that region's
  description.

## Preserved unchanged

- The 29 source locations and coordinates.
- Per-location descriptions, difficulty intent, zoom and `lots` metadata.
- Source icon and poster.
- A pristine full snapshot of the selected source variant under `upstream/42`.
