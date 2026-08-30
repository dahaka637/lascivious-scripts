# Integration Notes — Alice's Weapon Sling

- `module_key`: `alices-weapon-sling`
- `bundled_mod_id`: `LS_AliceWeaponSling`
- Workshop item `3775549570` actually contains **two separate PZ mods**: this one
  (`alicesWeaponSling`) and an optional addon, `alicesWeaponSlingRadialMenu`, which declared
  `require=alicesWeaponSling` in its own `mod.info` — a genuine, upstream-declared dependency (not
  a coincidental sibling like the Skully's pair). Both were bundled at first (as
  `LS_AliceWeaponSlingRadialMenu`), but the addon was **removed entirely from this pack** at the
  project owner's explicit request (2026-08-27) — not a bug fix, a product decision (they didn't
  want an extra radial-menu keybind for something this small). See `LOCAL_CHANGES.md` for the
  removal entry. This module (the base sling item) is unaffected and stands alone now; nothing in
  its own code ever depended on the addon being present (the addon only ever called *into* this
  module's globals, never the reverse).

## What it does

Adds a craftable/lootable "Weapon Sling" clothing accessory (4 style variants — front `\`, front
`/`, front `--`, back — switchable via the vanilla clothing right-click submenu, plus a hidden
texture-swap variant of each so players can toggle the visible strap on/off) that lets rifles,
shotguns, and other large two-handed weapons be holstered onto new hotbar attachment slots instead
of only the vanilla belt/back slots. A weapon mounted through a sling gets an invisible weapon part
attached (`AliceWeaponSlingWeightReductionPart`, `WeightModifier = -0.3`) that reduces its carried
weight, automatically applied/removed as the sling is worn/removed.

## Real cross-module collision found and resolved: `ISAttachItemHotbar` vs. `equip-while-running`

This is the first case in this pack where two of **our own bundled modules** write to the exact same
vanilla class in an order-sensitive way (`docs/COLLISION_REGISTRY.md` already flagged
`ISAttachItemHotbar`/`ISDetachItemHotbar` as "occupied surface" by `equip-while-running` for exactly
this reason). Full method-by-method analysis (see `docs/COLLISION_REGISTRY.md` for the summary row):

- `42/media/lua/shared/TimedActions/ISAttachItemHotbar_AliceWeaponSling.lua` **fully reimplements**
  `ISAttachItemHotbar:new/:perform/:stop` (no call-through to whatever was there before) —
  necessary because the sling needs to redirect attachment to a different slot/model *before*
  vanilla's own attach logic runs, not layer on top of it. `equip-while-running` also fully
  reimplements the same three methods (to make the action not stop while running). Neither mod
  calls through to the other, so **whichever one's file loads last in `Mods=` wins that method's
  slot entirely** — the other mod's fields for `:new` (`stopOnRun`, `animSpeed`/`maxTime` handling)
  and the other mod's logic for `:perform`/`:stop` are silently dropped for this specific action.
  Traced the actual consequence of both orderings:
  - **`LS_AliceWeaponSling` before `LS_EquipWhileRunning` (the order this pack uses)**: EWR's
    `:new`/`:perform`/`:stop` win. EWR's `:perform`/`:stop` call through to whatever was captured at
    EWR's own load time — which, in this order, is Alice's version — so Alice's `commitAttach()`
    sling logic still runs (wrapped by EWR's own sync-variable bookkeeping around it). The only
    field genuinely lost is Alice's `:new`-side `stopOnRun = true`; EWR's `stopOnRun = false` wins
    instead, meaning running no longer cancels a hotbar-attach action while `equip-while-running` is
    active — a strict improvement for that combination, not a break, and it matches EWR's whole
    purpose. `:complete()` and `:isValid()` are untouched by EWR either way, so the sling's core
    attach commit **always fires reliably regardless of order** (see below).
  - **The reverse order** would instead make Alice's `:new`/`:perform`/`:stop` win, silently
    dropping EWR's `RunAttach_Enable` synced-variable reset on this specific action (a real, if
    minor, stuck-synced-state bug) and losing EWR's `stopOnRun = false` for hotbar-attach
    specifically.
  - **Resolution: `LS_AliceWeaponSling` must load before `LS_EquipWhileRunning`.** Enforced today by
    `module_key` alphabetical order (`alices-weapon-sling` < `equip-while-running`) in
    `docs/MODULE_REGISTRY.md`, but recorded explicitly in `docs/SERVER_MOD_ORDER.md` as a hard
    constraint rather than left to alphabetical coincidence — re-check this note if the registry's
    row order or `tools/generate_server_mods.py` output ordering ever changes.
- The sling's own **`:complete()`** (which is what actually commits the attachment —
  `commitAttach(self)`, idempotency-guarded via `action.aliceWeaponSlingCommitted`) is **not touched
  by `equip-while-running` at all**, so the core "attach a weapon to a sling slot" mechanic works
  correctly regardless of load order — only the running-specific interaction nuance above is
  order-sensitive.
- `42/media/lua/client/AliceWeaponSling_WeightReductionPartHotbarHooks.lua` also wraps
  `ISDetachItemHotbar:perform` and `ISHotbar:removeItem` — but via the pack's standard **safe**
  pattern (idempotency guard + capture-before + call-through), which composes correctly with EWR's
  own wraps of the same methods *regardless of load order* (verified by tracing both orderings; each
  side's captured "previous" function ends up pointing at the other mod's version either way, so
  both always run). No fix needed there.
- `42/media/lua/client/AliceWeaponSling_ISHotbar.lua` also fully reimplements `ISHotbar:attachItem`
  (no call-through) — but **no other bundled module touches that method**, so this is a documented,
  informational-only override with zero actual collision today.

## Fase 1 inventory findings

- No dependency in the base mod's own `mod.info` (the `require=` relationship is one-directional:
  the addon needs the base, not the reverse).
- No check of the mod's own Mod ID anywhere (Category A per architecture doc section 20).
- Missing native translations — same recurring pattern as most modules in this pack: JSON existed
  for `ContextMenu`/`ItemName`/`Recipes`/`UI` (EN + 9 other languages, including a complete, correct
  `PTBR` set) but no native `.txt` for any of them. Fixed (see Adaptation) for EN only, per this
  pack's accepted PT-BR-accent limitation.
- **Genuine pre-existing upstream bug**: the weapon-part item `AliceWeaponSlingWeightReductionPart`
  declares `Tooltip = Tooltip_Sling`, but no `Tooltip_Sling` key exists in *any* language's JSON —
  the tooltip would render as the literal string `"Tooltip_Sling"` in-game. Fixed by adding a native
  `Tooltip_EN.txt` with original text (nothing to transcribe from, since upstream never had one).
- **Genuine pre-existing upstream bug**: `mod.info` declares `poster=` three times
  (`poster.png`, `preview.png`, `sling_recipe.png`) — PZ's `mod.info` parser only honors one
  `poster=` line, so two of the three images were dead weight. Dropped to a single `poster=poster.png`
  and removed the two unreachable image files from the bundle (kept in `vendor/` only for fidelity).
- `media/registries.lua` (`ItemBodyLocation.register("alicesweaponsling:slingfront")` /
  `"...slingback"`) is the **second** module in this pack to use this special B42 top-level file
  (first was `responsive-pivoting`, for `CharacterTrait.register`) — different registry namespace,
  no collision. `tools/audit_collisions.py` didn't yet know `registries.lua` is a legitimate
  per-mod-repeating filename (like `sandbox-options.txt`); fixed the tool rather than let it flag a
  false positive.
- `media/scripts/clothing/AliceWeaponSling_att.txt` adds new named `attachment` points
  (`alice_sling_*`) under the vanilla `FemaleBody`/`MaleBody` models — purely additive (new
  attachment names, doesn't redeclare any existing vanilla attachment), same safe pattern already
  used by `simple-belt-flashlight`'s own `SBFPlus_Attachments.txt`; no name overlap between the two.
- Two lightweight defensive compatibility checks are baked into several files:
  `if getActivatedMods():contains("\nattachments") then return end` (self-disables if a
  third-party "nAttachments" mod is active — unrelated to anything in this pack) and a `SwapIt`
  activated-mods presence check in `AliceWeaponSling_ISHotbar.lua` (adjusts hotbar-swap behavior if
  a `SwapIt` mod is active). Neither matches any Mod ID in this pack; both are inert here.
- `tools/validate_structure.py` flags a non-fatal case warning on
  `models_X/WorldItems/Clothing` (expects lowercase `clothing`) — verified harmless: the model
  script's own `mesh = WorldItems/Clothing/Sling_Flat` reference (in
  `AliceWeaponSling_items.txt`) uses the exact same capitalized casing as the actual folder, so
  reference and file agree on a case-sensitive filesystem (Linux dedicated server included); the
  heuristic just doesn't know this particular "clothing" is a mod-chosen subfolder under
  `models_X/WorldItems/`, not the top-level `42/media/clothing/` convention it's really checking
  for.
- `media/fileGuidTable.xml` is clothing-editor GUID metadata (used by PZ's in-game clothing/asset
  editor tool), first time seen in this pack — harmless, preserved as-is, not functionally read by
  the game outside that editor.

## Adaptation applied (Fase 5)

- `id=alicesWeaponSling` -> `id=LS_AliceWeaponSling` (Category A rename); `name=`/`description=`
  rewritten to the pack's style, PT-BR. `versionMin=42.20`, `modversion=1.5` preserved verbatim.
  Collapsed the triple `poster=` bug to one line; dropped `icon=`'s reference is kept (file exists).
- Added native `ContextMenu_EN.txt` (10 keys: 6 from JSON + 4 `AliceSlingStyle1..4` submenu labels
  used by the clothing script's `ClothingExtraSubmenu`/`ClothingItemExtraOption` fields, not
  referenced by any `getText()` call directly but read natively by the engine's clothing-submenu
  renderer), `ItemName_EN.txt` (4 keys), `Recipes_EN.txt` (1 key), `UI_EN.txt` (4 keys), and a new
  `Tooltip_EN.txt` (1 key, `Tooltip_Sling` — did not exist upstream in any form, see bug above).
- Every Lua file, clothing XML, script, and model copied byte-identical from upstream — confirmed
  via `diff -rq` and `luac5.1 -p` on all Lua. **Zero Lua code changes** — the `ISAttachItemHotbar`
  interaction with `equip-while-running` is resolved entirely through bundle load order (see above),
  not by patching either mod's code.
