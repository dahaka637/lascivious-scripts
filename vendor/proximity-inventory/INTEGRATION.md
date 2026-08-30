# Integration Notes — Proximity Inventory

- `module_key`: `proximity-inventory`
- `bundled_mod_id`: `LS_ProximityInventory`
- Workshop item `2847184718` ships **two separate implementations of the same mod** side by side:
  a top-level `mod.info` + `media/` (pre-B42 layout, global `ProxInv` namespace, uses
  `ISInventoryPage.GetLocalContainer` and an external `ModOptions:AddKeyBinding` API guarded by a
  presence check — an older/simpler codebase, likely kept only for players still on Build 41) and a
  `common/media/` + `42/mod.info` layout (`name=Proximity Inventory B42`, modern `ProximityInventory`
  namespace, native `PZAPI.ModOptions` API, split across 4 focused files instead of one monolith).
  **Only the `common/`+`42/` (B42) codebase was bundled** — this pack targets 42.20.x exclusively,
  and the B42 codebase is unambiguously the newer, more complete, self-contained one (no external
  `ModOptions` dependency, adds vehicle-container support, a "force select" mode, and a real dupe-bug
  fix the old codebase lacks — see below). The legacy top-level `media/`/`mod.info` was excluded
  entirely from both the vendor snapshot and the bundle. `common/` and `42/` were consolidated into
  this pack's single-`42/`-folder convention (this pack only ever targets one build, so the
  common/version split upstream uses for multi-build support serves no purpose here).

## What it does

Adds a synthetic "Proximity Inventory" entry to the loot window's container list that aggregates
every eligible nearby container's items (backpacks, corpses, furniture, vehicle trunks) into one
virtual view — so items on/around you can be seen and grabbed without opening each container
individually. A "Force Selected" mode (toggle keybind, default Numpad0) keeps that aggregated view
pinned as the active selection even as you move between containers; a highlight option outlines the
real-world objects currently contributing items to it. A `ZombieOnly` sandbox option restricts
aggregation to zombie corpse inventories only. 100% client-side UI feature — no server-side Lua at
all in this mod (confirmed: no `media/lua/server/` anywhere in the B42 codebase).

## Why this is safe without any server-side code

The virtual "proxInv" container (`ItemContainer.new("proxInv", nil, nil)`) only *aggregates
references* to items that already live in their real, normally-synced containers — it never creates,
moves, or duplicates an item server-side. Clicking/transferring an item from the aggregated view
still resolves through vanilla's normal pickup/transfer action path against the item's real
container, which is already validated the same way vanilla always validates those actions. The one
genuine risk this pattern creates — a container being "available" from the aggregator *and* the
crafting UI seeing it twice, enabling a duplication exploit — is explicitly caught and fixed by the
mod's own `CraftingFix.lua` (see below), which the upstream author's own comment flags as
"Very important file, it avoids duping in SP and MP".

## Fase 1 inventory findings

- `CraftingFix.lua` removes the synthetic proxInv container from both `ISCraftingUI:getContainers`
  and `ISInventoryPaneContextMenu.getContainers` (safe wrap, capture-before + call-through) — this
  is the author's own real dupe-bug fix, not something we needed to add ourselves; the *old*
  top-level codebase has an equivalent but less complete version of the same fix (only patches
  `ISCraftingUI`, not `ISInventoryPaneContextMenu`) — another point favoring the B42 codebase.
- `ISInventoryPage.lua` monkey-patches `:onBackpackRightMouseDown`, `:onBackpackMouseDown`, and
  `:update` — all safe wraps (capture-before + call-through in every branch). No idempotency guard
  on any of these four files' patches, but none collide with any other bundled module (checked via
  grep across the whole pack) and each file only runs once per session, so the missing guard has no
  practical effect here.
- `ProximityInventoryLootControls.lua` monkey-patches `ISLootWindowContainerControls:arrange` and
  `:handleJoypadContextMenu` so the vanilla "Take All / Take Same Type" loot control bar (normally
  floor-only) also renders for the virtual container — self-disables if the `CleanUI` mod is active
  (upstream compatibility check; irrelevant here, `CleanUI` isn't bundled in this pack).
- No dependency on any other mod, no `require=`/`loadModAfter=`/`loadModBefore=` in `42/mod.info`.
- No check of the mod's own Mod ID anywhere (Category A per architecture doc section 20).
- **Translation was already fully correct and native upstream** — first module in this pack where
  no `LOCAL_CHANGES` translation fix was needed at all. The B42 codebase ships native
  `Sandbox_EN.txt`/`UI_EN.txt`/`IG_UI_EN.txt` (not just JSON) already matching every `getText()` call
  in the code, cross-checked key by key. No PT-BR exists in any form upstream (only CN/EN/ES/FR/IT/
  TR/UA) — nothing to preserve for PT-BR fidelity.
- `42/mod.info` declared neither `versionMin=` nor `modversion=` at all — added `versionMin=42.20`
  to match this pack's target build (see Adaptation).

## Adaptation applied (Fase 5)

- `id=ProximityInventory` -> `id=LS_ProximityInventory` (Category A rename); `name=`/`description=`
  rewritten to the pack's style, PT-BR. Added `versionMin=42.20` (absent upstream). `poster=`/`icon=`
  preserved (both files identical between the legacy top-level and `common/` copies).
- Consolidated upstream's `common/media/` + `42/mod.info` into this pack's single `42/` folder
  (no functional change, just this pack's standard single-build layout).
- All 4 Lua files and all native translation files copied byte-identical from the B42 codebase —
  confirmed via `diff -rq` and `luac5.1 -p`. **Zero code changes.**
