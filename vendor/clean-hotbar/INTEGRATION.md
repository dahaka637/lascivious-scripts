# Integration Notes — Clean HotBar

- `module_key`: `clean-hotbar`
- `bundled_mod_id`: `LS_CleanHotBar`
- Workshop item `3461263912`, upstream folder name `CleanHotBar`. Ships **two different
  version-specific folders** alongside `common/`: `42/` (`versionMin=42.0`,
  `versionMax=42.14.99`) and `42.15/` (`versionMin=42.15`, no upper bound). PZ picks whichever
  version folder's range covers the running build; since this pack targets 42.20.x, the engine
  would select **`42.15/`**, not `42/` — despite `42/` sorting first alphabetically/numerically,
  it explicitly excludes anything past 42.14.99. Bundled `common/` (all the actual Lua and UI
  assets) + `42.15/` (the version folder that actually matches this pack's target), consolidated
  into this pack's standard single `42/` folder. `common/` itself carries no `mod.info` and no
  `Translate/` folder at all in this mod — both version folders are fully self-contained for
  metadata and translations.

## What it does

A comprehensive visual overhaul of the vanilla hotbar and hand-equipped-item slots: per-slot item
condition/durability bars, weapon head-condition and sharpness indicators, ammo count and liquid-
fill display, a low-durability weapon alert icon, built-in drag-to-reorder (with lock/swap-vs-insert
modes), configurable hotbar scale/opacity, and green/yellow/red compatible-slot highlighting while
dragging an item. 100% client-side — confirmed no `sendClientCommand`/`sendServerCommand`/
`OnServerCommand`/`OnClientCommand` anywhere across all 13 Lua files, and no server-side Lua at all
(only `client/hotbar/*.lua`). Settings persist to a local per-install config file
(`CleanHotbarConfig.txt`, migrated automatically from an older `CleanHotbarConfig.lua` — the mod's
own comment notes *"Build 42.20+ no longer allows writing .lua config files through getFileWriter"*,
showing the author already tracks this pack's exact target build's engine behavior).

## Real cross-module collision found and verified safe: `ISHotbar.refresh` vs. `simple-belt-flashlight`

`cleanhotbarreorder.lua` (the built-in reorder feature) wraps `ISHotbar.refresh` — the same method
`simple-belt-flashlight` already wraps (see `docs/COLLISION_REGISTRY.md`, added when that module was
integrated). Traced the actual composition:

- `simple-belt-flashlight` patches `ISHotbar.refresh` at **file load time** (safe pattern: capture-
  before + idempotency guard `ISHotbar.SBFPlus_RefreshWrapped` + always call-through).
- Clean HotBar's reorder feature installs its own wrap **later**, inside `installInternalReorder()`,
  triggered from `Events.OnLoad`/`Events.OnGameStart` — both fire only after every mod's file-scope
  Lua (including SBF's) has already finished loading. It captures whatever `ISHotbar.refresh`
  currently is at that point (`original.refresh = ISHotbar.refresh`) and its own wrapper always
  calls `original.refresh(self)` first before adding reorder-specific logic.
- Because Clean HotBar's capture happens at a guaranteed-late point (a gameplay-start event, not
  file-load order), it reliably picks up SBF's already-installed wrapper regardless of which mod's
  `Mods=` position comes first — **no ordering constraint needed**, verified safe in both directions
  the same way the `ISRemoveWeaponUpgrade:complete` overlap between `improvised-silencers` and
  `alices-weapon-sling` was (see that entry in `COLLISION_REGISTRY.md` for the same reasoning
  pattern).
- No other bundled module touches any of the other `ISHotbar` methods Clean HotBar patches
  (`render`, `setSizeAndPosition`, `onMouseDown`, `onMouseMove`, `onMouseUp`, `onMouseUpOutside`,
  `getSlotIndexAt`, `canBeAttached`, `updateTooltip`) or the vanilla `ISEquippedItem` class it also
  patches (`render`, `checkToolTip`, for the hand-equip slot overlay) — grepped every one of these
  method names across all 22 other bundled submods to confirm.
- Also self-disables its own built-in reorder feature entirely if a separate, non-bundled "Reorder
  The Hotbar" mod (`ReorderTheHotbar_Mod` global) is active, and disables a "CommonSense" mod's
  redundant ammo-count overlay via `SandboxVars.CommonSense.GunStats = false` if that unbundled mod
  happens to be present — both checks are inert in this pack since neither mod is bundled here.

## Fase 1 inventory findings

- **Real translation regression in the upstream's own newer version folder**: the older `42/`
  folder (which this pack does *not* use, since it excludes our target build) shipped a working
  native `IG_UI_EN.txt` (and 14 other languages' native `.txt` files). The newer `42.15/` folder —
  the one that actually applies to 42.20.x — only ships `IG_UI.json` per language, having silently
  dropped the native `.txt` fallback that the older folder had. Since native `getText()` never reads
  JSON, this is a real regression affecting exactly the build range this pack targets. Fixed by
  re-adding a native `IG_UI_EN.txt` with the same 7 keys, transcribed from the (matching) EN JSON —
  see LOCAL_CHANGES.
- `incompatible=qdx_item_condition,TheStar` in `mod.info` names two other, unrelated Workshop mods
  not bundled in this pack — dropped (same reasoning as `drag-bodies-faster`'s dropped
  `incompatible=` line: those Mod IDs will never exist in this bundle, so the declaration has no
  effect either way).
- No dependency on any other mod, no `require=`/`loadModAfter=`/`loadModBefore=`.
- No check of the mod's own Mod ID anywhere (Category A per architecture doc section 20).
- No sandbox options — all tuning lives in the mod's own local config file/settings panel instead.

## Adaptation applied (Fase 5)

- `id=CleanHotBar` -> `id=LS_CleanHotBar` (Category A rename); `name=`/`description=` rewritten to
  the pack's style, PT-BR. `versionMin=42.15`, `modversion=1.12.3` preserved verbatim. Dropped
  `incompatible=` (see above). `poster=`/`icon=` preserved.
- Consolidated upstream's `common/` + `42.15/` into this pack's single `42/` folder (no functional
  change beyond the translation fix below — same reasoning as `proximity-inventory`/
  `improvised-silencers`/`mini-health-panel`'s common+version consolidation).
- Added native `Translate/EN/IG_UI_EN.txt` (7 keys) — see the regression fix above.
- All 13 Lua files copied byte-identical from the `common/` upstream codebase — confirmed via
  `diff -rq` and `luac5.1 -p`. **Zero code changes.**
