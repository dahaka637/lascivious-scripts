# Integration Notes — Simple Belt Flashlight+

- `module_key`: `simple-belt-flashlight`
- `bundled_mod_id`: `FixedLightOnBeltAF` — **NOT** renamed to `LS_*`. See "Mod ID kept verbatim"
  below, this is a deliberate exception to this pack's usual naming convention.
- Workshop item `3778709615`, folder name `Simple Belt Flashlight Plus`, ships a `42.20`
  build-version folder (not `common/`+`42/`) plus an already-empty `common/` (two `.gitkeep`-only
  placeholder subfolders, `actiongroups/` and `AnimSets/`, carrying zero content — not copied into
  the bundle, they add nothing).

## What it does

Lets flashlights/torches be attached to the belt/holster instead of only held in-hand, freeing both
hands. Adds a new `attachment` block (not new items) to vanilla `FemaleBody`/`MaleBody` models for
several belt-mounted positions (`SBFPlus_VanillaSmall{Left,Right}`, `SBFPlus_Angled{Left,Right}`,
`SBFPlus_AZMilitary{Left,Right}`, plus several `SBFPlus_BF_*` variants for Better Flashlights items),
then at runtime patches the `AttachmentType` field of existing vanilla/AuthenticZ/Better-Flashlights
light items via `item:DoParam("AttachmentType = ...")` (live script-manager patch, not a full item
redeclaration — much lower update-risk than `durable-tools-weapons`' approach, since it only touches
one field and leaves everything else the vanilla/other-mod item definition controls untouched) and
wires up hotbar attach-slot definitions (`ISHotbarAttachDefinition`) for belt/webbing slots. Also
migrates already-attached items to the correct model/slot when their `AttachmentType` changes
(e.g. a save made before/after Better Flashlights was toggled on).

Better Flashlights and Plysken Attachments Reborn (PAR) support is **soft/optional**: detected at
runtime by checking for the existence of a Better-Flashlights-specific item (`Base.BF_EgenerexLite`)
via `ScriptManager`, and for a PAR-specific global (`PARSlotsName`) via `rawget(_G, ...)` — no
`require=` dependency declared, nothing breaks if either mod is absent. AuthenticZ items are
referenced directly by `fullType` string (`AuthenticZClothing.*`) with no existence check at all,
but that's harmless — `itempatcher.lua`'s `getItem()` safely no-ops (increments `result.skipped`)
when a referenced item doesn't exist in the currently loaded script set.

A gated diagnostics module (`sbfplus_mpdiagnostics.lua`, off by default via the
`SBFPlus.DebugLogging` sandbox option) polls every 5s and logs attachment/light-state changes for
supported items to `console.txt` — purely client-side, no network traffic, matches its own sandbox
tooltip's claims.

## Mod ID kept verbatim — read before touching this module again

Upstream's own `mod.info` description says: **"Drop-in replacement for FixedLightOnBeltAF. Works on
existing saves."** This mod is explicitly designed to replace an older/simpler mod that used the
Mod ID `FixedLightOnBeltAF`, preserving that exact ID so a save that already has flashlights attached
via the original mod keeps working when swapped for this one. This is Category C per
[`../../docs/ARCHITECTURE.md`](../../docs/ARCHITECTURE.md) section 20 — "outros mods externos
(neste caso, o próprio conceito de saves antigos) dependem de detectar o Mod ID original" — so the
bundled Mod ID stays `FixedLightOnBeltAF`, unlike every other module in this pack so far (`LS_*`
prefix). **Caution flagged per that section's own warning**: if a player also has a *standalone*
copy of the original `FixedLightOnBeltAF` (or this same mod, subscribed separately) active, that
will collide with this bundled copy — same Mod ID can't be loaded twice. Migrating a server from a
standalone `FixedLightOnBeltAF`/`Simple Belt Flashlight+` subscription to this bundle must follow
section 33 of the architecture doc (remove the standalone Workshop ID only after this bundled copy
is validated).

## Fase 1 inventory findings

- `require "sbfplus/itemcatalog"` (all-lowercase, 3 call sites) resolves to the actual file at
  `SBFPlus/ItemCatalog.lua` (mixed case) — **verified this works**: PZ's `require()` path resolution
  is case-insensitive by design (found `lowercaseUri`/`toLowerCase`/`CASE_INSENSITIVE_ORDER` string
  constants directly in `zombie/Lua/LuaManager.class` from the installed game jar, in the same class
  responsible for the `"recursive require(): %s"` error message). This is **specific to `require()`
  path resolution** — it does NOT mean raw asset paths (AnimSets, Translate, textures) are
  case-insensitive on Linux; those still need exact-case per architecture doc section 9.3. Left
  upstream's lowercase `require` strings untouched (no bug, no reason to "fix" a working pattern).
- Upstream shipped `Translate/EN/sandbox.json` (lowercase filename) but **no native
  `Sandbox_EN.txt`** — same gap already found and fixed once before in this pack's own
  `zombie-decay` module (see [[feedback-sandbox-options-native-txt-required]]). Nothing in this
  mod's Lua reads that JSON file at all (no custom Options UI, only the one native
  `sandbox-options.txt` entry), so it was pure dead weight for the native Sandbox Options screen,
  which would've shown the raw untranslated key. Fixed — see Adaptation below.
- `authors=ACE` and `modVersion=1.0.4` (note the upstream typo: mixed-case `modVersion`, PZ's
  `mod.info` key parsing is case-sensitive so this almost certainly wasn't recognized as a version
  string by the game at all) were both present upstream.
- No `require=` dependency declared; only soft/runtime-detected optional compat (see above).
- No new items/recipes/traits/perks — only `attachment` blocks (3D attach points) and a live
  `AttachmentType` field patch on existing items.
- No Java/JAR, no maps/tiledefs/packs.
- No network commands anywhere in this mod (unlike `equip-while-running`) — `syncItemFields` used in
  `sbfplus_hotbar.lua`'s `syncMigratedItem` is vanilla's own item-sync API, not a custom protocol.
- No check of the mod's own Mod ID anywhere in the code (the ID-preservation reasoning above is
  about external/save compatibility, not a self-check).
- Well-written monkey patches: `ISHotbar.refresh`/`ISHotbar.doMenuFromInventory` are wrapped with a
  proper call-through (`previousRefresh(self, ...)`) and idempotency guards
  (`ISHotbar.SBFPlus_RefreshWrapped`/`SBFPlus_MenuWrapped`) — unlike `equip-while-running`'s
  from-scratch `:new()` reimplementations, this is the safer wrap-and-call-through pattern the
  architecture doc's own `require`-idempotency guidance (section 8) is written around. Registered in
  [`../../docs/COLLISION_REGISTRY.md`](../../docs/COLLISION_REGISTRY.md) anyway as occupied surface
  — different classes than `equip-while-running` touches, no actual overlap today.

## Adaptation applied (Fase 5)

- `id=FixedLightOnBeltAF` preserved verbatim (see "Mod ID kept verbatim" above — this is the one
  exception to this pack's `LS_<Name>` convention so far).
- `name=`/`description=` rewritten to the pack's style, PT-BR.
- `modVersion=1.0.4` -> `modversion=1.0.4` (lowercase key, matches `mod.info`'s actual expected
  field name and this pack's own convention elsewhere).
- `authors=ACE` left untouched (pre-existing upstream data).
- **Added `42/media/lua/shared/Translate/EN/Sandbox_EN.txt`** with the 3 keys already present in
  upstream's `sandbox.json` (`Sandbox_SBFPlus`, `Sandbox_SBFPlus_DebugLogging`,
  `Sandbox_SBFPlus_DebugLogging_tooltip`) so the native Sandbox Options screen actually shows
  translated English text for this module's one option instead of the raw key. No PT-BR native file
  added — same accepted limitation as the rest of this pack (accented text breaks native `.txt`
  Lua-table translation files, see [[feedback-ptbr-accents-in-lua]]).
- Dropped the two empty `.gitkeep`-only placeholder folders (`actiongroups/`, `AnimSets/`) — no
  content, nothing lost.
- Everything else copied byte-identical from upstream — confirmed via direct `diff` against every
  copied file.
