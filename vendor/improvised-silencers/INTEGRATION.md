# Integration Notes — Improvised Silencers

- `module_key`: `improvised-silencers`
- `bundled_mod_id`: `LS_ImprovisedSilencers`
- Workshop item `3779164273`, upstream folder name `Improvised Silencers` (contains a literal
  space). Ships `mod.info` directly inside `common/` (not inside the version folder, unlike most
  modules in this pack) and a `42.0/` version folder (dotted, not just `42`) containing only empty
  `AnimSets`/`actiongroups` placeholders — all real content lives under `common/media/`. Same
  overall shape as `proximity-inventory`: consolidated `common/` into this pack's single `42/`
  folder, since this pack only ever targets one build. Also ships 4 unreferenced `preview*.png`
  Workshop-page screenshots (`mod.info` declares no `preview=`) — not bundled, kept in `vendor/`
  only for fidelity.

## What it does

Adds 5 craftable suppressors — professional (welded), metal pipe, hand torch, water bottle, and a
one-shot potato — each reducing a firearm's sound radius/volume by a fixed amount (or a
sandbox-configurable amount in an opt-in "Extended Realism Mode", which also adds durability that
wears with each shot, at a rate configurable per caliber). Ships its own suppressed-fire sound per
weapon family (pistol/shotgun/rifle) for each suppressor type. Includes substantial, fully optional
compatibility layers for two popular external Workshop mods (Guns of Marz and Vanilla Firearms
Expansion) that add suppressor support to those mods' own weapons without modifying either mod's
files — neither is bundled in this pack, so both compat files self-gate on `getActivatedMods()` and
are completely inert unless a server/client separately runs one of those mods alongside this pack.

## Code quality — exceptionally high, no patch needed

This is one of the most carefully engineered third-party mods reviewed in this pack, on par with
`cyes-push-doors` and `climb-ladders`. All 12 Lua files were read in full. Highlights:

- **Correct MP authority for durability**: `onWeaponFired` (the function that reduces suppressor
  durability per shot) explicitly guards `if isClient() and not isServer() then return end` — only
  the server (or a listen-server host) ever mutates durability. Clients only ever receive the
  result via `syncHandWeaponFields` and this mod's own broadcast.
- **Aware of a real vanilla sync gap and fixes it correctly**: `syncHandWeaponFields`/the native
  hand-weapon packet does not serialize `SoundRadius`/`SoundVolume`/`SwingSound`/muzzle-flash model
  key, and does not reliably remove nested weapon parts from observer clients' copies. This mod adds
  its own explicit `sendServerCommand`/`Events.OnServerCommand` broadcast
  (`broadcastNetworkWeaponState`/`applyNetworkWeaponState`), gated server-only for sending, with a
  revision counter (`ISILSuppressorNetworkRevision`) so a delayed/out-of-order packet can never
  overwrite a newer state, plus a short retry schedule (`ISILPendingNetworkWeaponStates`, ticks
  2/10/30) to handle the native packet and this mod's custom packet arriving in either order under
  latency. This is the same class of problem this pack's own `better-push` rewrite (`LS-004`) had to
  solve independently, solved here with an equally (arguably more) rigorous approach.
- **Interop-aware without monkey-patching other frameworks' core handlers**: explicitly avoids
  replacing the global `ISUpgradeWeapon`/`ISRemoveWeaponUpgrade` completion handlers that Guns of
  Marz' "Gunworks" system and VFE rely on for their own generic-to-directional part conversion —
  wraps them with capture-before + always-call-through instead, and even defers final weapon-state
  restoration by one `OnPlayerUpdate` tick (`ISILDeferredWeaponStates`) specifically to let those
  other frameworks' own post-completion hooks run first before this mod's own bookkeeping applies.
  Context-menu decoration (`ISIL_WeaponStateCompatibility.lua`) resolves the *active* handler at
  click time rather than capturing a possibly-stale reference, so it stays compatible with whichever
  framework last modified that handler.
- **Defensive against its own hot-reload/multi-instance edge cases**: the inventory-pane durability
  overlay (`ISIL_DurabilityInventoryPane.lua`) keeps a versioned global hook-state
  (`ISILInventoryPaneHookState`, `HOOK_VERSION`) specifically so this file loading twice, or a UI mod
  swapping the concrete pane class at runtime (it even explicitly probes for CleanUI's alternate pane
  classes via `rawget`, though CleanUI isn't part of this pack), can never create a duplicate-wrapped
  or recursive method chain.
- All monkey-patches use the safe capture-before + call-through pattern; several add an explicit
  idempotency guard flag on top (`ISRemoveWeaponUpgrade.AliceWeaponSling_BlockHiddenPart`-style
  flags aren't used here — instead a simple `originalX = ClassX.method` local capture per file, which
  is safe because each file only loads once per session).

## Cross-checked against every one of this pack's other 19 bundled modules — no real collision

This mod touches several shared vanilla UI/TimedAction classes (`ISUpgradeWeapon`,
`ISRemoveWeaponUpgrade`, `ISToolTipInv`, `ISInventoryPane`, plus read-only references to
`ISInventoryPaneContextMenu`). Grepped every one of those symbols across all other bundled modules:

- `ISRemoveWeaponUpgrade:complete` is also wrapped by `alices-weapon-sling`
  (`AliceWeaponSling_HideWeaponPartContextMenu.lua`, to block manually removing its own hidden
  weight-reduction part). Both sides use capture-before + always-call-through, so this composes
  correctly regardless of load order (same verified-safe shape as the `ISDetachItemHotbar` overlap
  documented for that module in `docs/COLLISION_REGISTRY.md`) — no ordering constraint needed.
  `alices-weapon-sling` touches `:isValid`, this module touches `:new`; no overlap there.
- `ISToolTipInv`, `ISInventoryPane`'s patched methods (`.prerender`/`.onMouseMove`/
  `.drawItemDetails`), `ISUpgradeWeapon`, and `ISCraftingUI` are not touched by any other bundled
  module.
- `ISInventoryPaneContextMenu` appears in three other modules
  (`alices-weapon-sling`/`proximity-inventory`), but every one of those touches a *different* method
  (`.onRemoveUpgradeWeapon`, `.transferIfNeeded`, `.getContainers`) — this mod only ever *reads*
  `ISInventoryPaneContextMenu.onUpgradeWeapon` to call the currently-installed handler, never
  reassigns it.
- `ModelWeaponPart`/`DoParam` runtime script mutation (used to associate suppressor visuals with
  vanilla/VFE/GoM weapons) doesn't overlap with `simple-belt-flashlight`'s own `DoParam` usage — that
  module sets a different script key (`AttachmentType =`) entirely.

## Fase 1 inventory findings

- Missing native translations for all 4 families used (`Sandbox`/`ItemName`/`Recipes`/`Tooltip`,
  41 keys total) — same recurring pattern as most modules in this pack, fixed (see Adaptation). This
  time the impact was more visible than usual: the item script declares no `DisplayName=` fallback
  at all for any of the 5 suppressor items, so without a native `ItemName_EN.txt` they would have
  displayed as their raw internal names (`Silencer`, `MetalPipeSilencer`, ...) rather than falling
  back to readable text.
- No dependency on any other mod, no `require=`/`loadModAfter=`/`loadModBefore=` in `mod.info`.
- No check of the mod's own Mod ID anywhere (Category A per architecture doc section 20).
- PT-BR JSON already exists and is complete/correct for `ItemName`/`Recipes`/`Tooltip` (no PT-BR
  `Sandbox.json` upstream) — preserved, not promoted to native per this pack's accepted accent
  limitation (see Adaptation).

## Adaptation applied (Fase 5)

- `id=ImprovisedSilencers` -> `id=LS_ImprovisedSilencers` (Category A rename); `name=`/
  `description=` rewritten to the pack's style, PT-BR. `versionMin=42.20.0` preserved verbatim.
  `poster=` preserved.
- Consolidated upstream's `common/mod.info` + `common/media/` into this pack's single `42/` folder
  (no functional change, just this pack's standard single-build layout, same as
  `proximity-inventory`).
- Added native `Sandbox_EN.txt` (23 keys), `ItemName_EN.txt` (5 keys), `Recipes_EN.txt` (5 keys),
  and `Tooltip_EN.txt` (8 keys), transcribed from the already-correct EN JSON.
- All 12 Lua files, all scripts, sounds, textures, and models copied byte-identical from upstream —
  confirmed via `diff -rq` and `luac5.1 -p` on every Lua/native-translation file. **Zero code
  changes.**
