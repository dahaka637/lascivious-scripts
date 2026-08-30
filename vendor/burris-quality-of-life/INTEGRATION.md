# Integration Notes — Burris Quality of Life

- `module_key`: `burris-quality-of-life`
- `bundled_mod_id`: `LS_BurrisQualityOfLife`
- Workshop item `3776168400`, upstream folder `BurrisQualityOfLife`, `id=BurrisQoL`. Ships
  `common/` (mod.info, icons, and all `Translate/EN/*.json` — no other language) + `42.20/`
  (all Lua, `sandbox-options.txt`, `scripts/`). Consolidated into this pack's single `42/` folder,
  same reasoning as every other `common/`+version-folder module in this pack.
- **This is a compilation mod**: 16 independently sandbox-toggleable quality-of-life features
  bundled under one Workshop item, not a single mechanic. The user flagged this explicitly and
  asked for a check against this pack's other 24 already-bundled modules for redundant/overlapping
  features before integrating — see "Redundant features removed" below for what that check found.

## What it does (after the two removals below)

Pry doors/windows/garage doors/vehicles open with a crowbar (server-validated, see below); tie off
a bleeding limb with a belt (tourniquet); equip weapons/clothing/bags straight off the ground; pick
up loose twigs/rocks/logs/branches vanilla leaves uninteractable; wash only equipped or unequipped
items; reload every selected magazine in one click; replace a dirty bandage in one click; read and
get dressed while walking; no ground weight limit; jumbo tree canopies that stop blocking view
indoors/on the road/on foot; zombies that push each other apart instead of clipping through one
another; inventory selections that stop deselecting themselves; container buttons for bags inside
bags/crates; a fix for corpse storage in closed vehicle trunks; a chance to cut yourself opening
cans without an opener; and three additive crafting/repair recipes. Every feature (bar the three
recipes, which are additive and have no toggle) is individually gated by its own sandbox option.

## Redundant features removed — real overlap with two already-bundled modules

Found during Fase 1/2 review, confirmed with the user, **removed entirely** (not just disabled by
sandbox default) per explicit instruction:

1. **"Flashlights fit the tool loop" (`TweakFlashlightSlot`)** collided with `simple-belt-flashlight`
   (`FixedLightOnBeltAF`), already bundled in this pack. Both mods write the `AttachmentType` script
   field of the exact same two vanilla items (`Base.HandTorch`, `Base.Flashlight_Crafted`) to
   *different* values — BQoL sets `"Screwdriver"` (the vanilla tool-loop slot 14 other items already
   use), `simple-belt-flashlight` sets `"SBFPlus_VanillaSmall"` (its own custom belt attachment
   point). Since `ScriptManager` is process-global and both patches run via `DoParam`/live field
   writes, whichever mod's init code runs last silently wins for just these two items — a genuine
   last-write-wins data race, not a crash but an inconsistent, load-order-dependent outcome the
   player would have no way to predict. `simple-belt-flashlight` covers strictly more items
   (vanilla + AuthenticZ + Better Flashlights variants) and already has a working, tested belt-slot
   solution in this pack, so the user chose to remove BQoL's narrower, colliding version outright
   rather than accept the race.
2. **Ammo counter (`AmmoHudEnabled`)** collided with `clean-hotbar`, already bundled in this pack.
   Both draw an ammo-remaining indicator in the exact same on-screen location — the equipped
   primary-hand slot (`ISEquippedItem:render`, anchored to `self.mainHand`) — via safe, properly
   call-through-chained monkey-patches on both sides (traced both load orders; each ends up drawing
   its own overlay on top of the other's, not crashing, but visually duplicated/cluttered). Clean
   HotBar's own `showWeaponAmmo.equipitem` option already covers this. The user chose to remove
   BQoL's version rather than keep two overlapping ammo displays.

Removed: `42/media/lua/client/BQoL/{BQoL_FlashlightSlot.lua,BQoL_AmmoHud.lua}`,
`42/media/lua/shared/BQoL/BQoL_ItemParams.lua` (the shared half of the flashlight retrofit — nothing
else in the codebase referenced it; verified via grep that no `require` pointed at any of the three
removed files), the corresponding `TweakFlashlightSlot`/`AmmoHudEnabled` blocks from
`sandbox-options.txt`, the matching `DEFAULTS` entries from `BQoL_Settings.lua` (re-verified the two
files list the exact same 47 option names after the edit — the mod's own `tools/lint.sh` invariant,
not shipped with the runtime, but kept in sync by hand), the `Sandbox_BurrisQoL_TweakFlashlightSlot`/
`Sandbox_BurrisQoL_AmmoHudEnabled` (+ `_tooltip`) key pairs from the bundled `Sandbox.json` and the
native `Sandbox_EN.txt` built from it, and the corresponding phrases from `mod.info`'s description.

## Code quality — exceptionally high, extensively self-documented

Read in full: `BQoL_Core.lua`, `BQoL_Commands.lua` (server), `BQoL_ItemParams.lua` (pre-removal),
`BQoL_FlashlightSlot.lua`/`BQoL_AmmoHud.lua` (pre-removal, for the collision analysis above),
`BQoL_ZombieCollisionLogic.lua`, `BQoL_PryOutcome.lua`, `BQoL_ReplaceBandage.lua` (partial),
`BQoL_items.txt`, `BQoL_recipes.txt`, `BQoL_fixing.txt`. Every file carries long, precise comments
documenting real bugs found during development (several reference commit hashes), genuine Java/Lua
bridge gotchas (e.g. `IsOpen()` vs `isOpen()` case-sensitivity silently breaking a guard), and
multiplayer-specific traps (`ISTimedActionQueue` being nil on a dedicated server inside a shared
`complete()`, `SandboxVars` arriving after `OnGameBoot` but not before `OnGameStart`). This is one of
the most carefully engineered third-party mods reviewed in this pack, on par with `cyes-push-doors`,
`climb-ladders` and `improvised-silencers`.

- **Pry is genuinely server-authoritative**: the client sends only square coordinates and a `kind`
  string via `sendClientCommand`; `BQoL_Commands.lua`'s `resolveTarget` independently re-runs
  `BQoL.Pry.classify(object)` server-side and only proceeds if the re-classification agrees — the
  file's own comment: *"Deliberately re-classifies rather than trusting the client: a client that
  asks to open a door which is not actually priable gets nothing."* `Pry.applySuccess`/
  `applyFailure` (the functions that actually unlock/open a door or shatter a window) are only ever
  called from that server-side handler.
- **Tourniquet state sync doesn't trust client claims either**: `handlers.tourniquetUnequipped`'s own
  comment: *"The claim is not taken at face value: the server re-derives the orphan list from its own
  copy of what the player is wearing."*
- **`BQoL.isModActive(modId)`** (in `BQoL_Core.lua`) is existing infrastructure for standing down from
  a feature when another specific mod is already active — not used to resolve either collision above
  (it checks Mod IDs the upstream author would know about, not this pack's own bundled IDs), but
  worth knowing about if a future BQoL update or another integration needs the same kind of check.
- Every monkey-patch found (`ISHotbar.canBeAttached`, `ISEquippedItem.render`,
  `ISHealthPanel.doBodyPartContextMenu`/`getDamagedParts`/`setOtherPlayer`,
  `ISHealthBodyPartListBox.doDrawItem`, `ISReadABook.new`, `ISInventoryPane.restoreSelection`,
  `ISInventoryTransferAction.isValid`, `ISInventoryPaneDraggedItems.update`) uses the safe
  capture-before + always-call-through pattern.

## Cross-checked against every one of this pack's other 24 bundled modules

Grepped every vanilla class this mod touches across all other bundled submods. Besides the two
removed overlaps above, found zero real collisions:

- `ISHealthPanel` appears in `mini-health-panel` and `climb-ladders`, but only inside comments in
  both cases (no actual code touches the class in either).
- `ISInventoryPane` appears in `clean-hotbar`, `immersive-suicide` and `improvised-silencers`, but
  none of them touch `:restoreSelection` (the only method BQoL patches there).
- `ISInventoryTransferAction` appears in `alices-weapon-sling`, `equip-while-running`,
  `mini-health-panel` and `improvised-silencers`; only `equip-while-running` actually monkey-patches
  it (`:new`/`:start`/`:update`/`:perform`/`:stop`), and BQoL's own patch is `:isValid()` — no
  overlap on any method name.
- `ISHotbar.canBeAttached` (kept in this bundle, unlike the removed flashlight feature — see below)
  is also patched by `clean-hotbar`. Traced both load orders: `clean-hotbar`'s version blocks broken
  items outright (no call-through in that one branch) but otherwise always calls through; BQoL's
  version always tries the existing check first and only adds its own fallback afterward. Both
  orderings compose correctly — broken-item rejection and BQoL's retrofit both still apply — same
  "verified safe regardless of order" shape already logged for `ISHotbar.refresh` between
  `clean-hotbar` and `simple-belt-flashlight`.
- `ISReadABook`, `ISHealthBodyPartListBox`, `ISInventoryPaneDraggedItems`: touched by no other
  bundled module at all.
- Zombie-to-zombie collision physics (position-based personal-space push) is entirely orthogonal to
  this pack's own `zombie-decay` module (sandbox-driven speed/strength/toughness scaling over time,
  plus AnimSet root-motion overrides) — no shared state, no shared files, confirmed by reading
  `BQoL_ZombieCollisionLogic.lua` in full.
- New item IDs (`BQoL_TourniquetLeftLeg`/`RightLeg`) and recipe IDs
  (`CleanBandageWithAlcohol`/`BQoL_DisinfectRagWithCologne`/`CutSheetWithClothes`) don't collide with
  anything this pack's other item-adding modules (`durable-tools-weapons`, `alices-weapon-sling`,
  `improvised-silencers`) declare.

## Fase 1 inventory findings

- Missing native translations for all 6 families used (`Sandbox`/`ContextMenu`/`IG_UI`/`ItemName`/
  `Recipes`/`Tooltip`) — same recurring pattern as most of this pack, fixed (see Adaptation). Only
  EN exists upstream (no other language, including no PT-BR JSON at all for this mod).
- No dependency on any other mod, no `require=`/`loadModAfter=`/`loadModBefore=` in `mod.info`.
- No check of the mod's own Mod ID anywhere (Category A per architecture doc section 20).

## Adaptation applied (Fase 5)

- `id=BurrisQoL` -> `id=LS_BurrisQualityOfLife` (Category A rename); `name=`/`description=`
  rewritten to the pack's style, PT-BR, with the two removed features' phrases dropped from the
  description. `versionMin=42.20.0`, `modversion=0.9.3` preserved verbatim. `poster=`/`icon=`
  preserved.
- Consolidated upstream's `common/` + `42.20/` into this pack's single `42/` folder.
- Removed the two redundant features in full — see above.
- Added native `Sandbox_EN.txt` (built from the edited, 2-keys-shorter `Sandbox.json`),
  `ContextMenu_EN.txt`, `IG_UI_EN.txt`, `ItemName_EN.txt`, `Recipes_EN.txt`, `Tooltip_EN.txt` — all
  transcribed from the already-correct EN JSON.
- Every other Lua file, and every non-`Sandbox` JSON file, copied byte-identical from upstream —
  confirmed via `diff -rq` and `luac5.1 -p` on every Lua/native-translation file after the edits.
