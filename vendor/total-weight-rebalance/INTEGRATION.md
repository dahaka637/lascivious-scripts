# Integration Notes — Total Weight Rebalance

- `module_key`: `total-weight-rebalance`
- `bundled_mod_id`: `LS_TotalWeightRebalance`
- Workshop item `3786993262`, folder name `TotalWeightRebalance`, already uses this project's own
  `42/` layout (no `common/` shipped upstream at all — our own empty `common/media/` placeholder is
  used instead, matching every other submod).

## What it does

Rewrites `getActualWeight()`/`setActualWeight()` on **1616 vanilla items** (organized into 22
categories in `weights_vanilla.lua` — camping, cooking, tools, literature, security, etc.) to
approximate real-world kilograms, via a live per-field patch (`item:setActualWeight(weight)` through
`ScriptManager.instance:getItem(fullType)`) — not a full item-block redeclaration, so it doesn't
clobber `DisplayName`/`Icon`/`Tags`/anything else the way `durable-tools-weapons` does. Every entry
in `weights_vanilla.lua` is commented with the original vanilla value for easy comparison
(`["Base.X"] = newWeight, -- oldWeight`), which will make future re-syncs against upstream updates
straightforward.

Also ships **soft-optional weight rebalancing for 3 named third-party mods** (`weights_mods.lua`:
Skill Recovery Journal, Neat Lockpicking, Gyde's Trait Magazines) — none of which are bundled in
this pack; each entry safely no-ops via the same `ScriptManager` existence check if the item doesn't
exist. Not a real dependency, no `require=` declared.

A single string sandbox option, `TotalWeightRebalance.CustomWeights`, lets an admin add further
per-item overrides beyond the built-in tables (`Base.ItemName:0.25; Base.Other:1.0` format,
persisted through the sandbox options file itself). A right-click "Set Weight" context-menu option
(togglable via a `PZAPI.ModOptions` tickbox) opens a small dialog showing vanilla/TWR/current weight
side by side and lets an admin set a new one live.

## Multiplayer authority — admin-gated at both ends, no patch needed

This is the most carefully access-controlled bundled mod so far:

- **Client-side**: the "Set Weight" context-menu option itself is hidden from non-admins
  (`canSetWeight()` checks `isAdmin()`/`getAccessLevel() == "admin"` before even adding the menu
  entry — see `SetWeightContextMenu.lua`).
- **Server-side**: `apply_weights.lua`'s `onClientCommand` independently re-checks
  `player:getAccessLevel() == "admin"` (using the framework-authenticated `player`, never anything
  client-supplied) before applying or persisting anything, and before broadcasting the change to
  every other client via `weightsChanged`. A non-admin client could not get a weight change applied
  even by hand-crafting the network command.

No LOCAL_CHANGES security patch was needed — reviewed and confirmed safe as designed. Third bundled
mod (after `push-vehicle`, `better-engine-repair`) needing zero MP hardening.

## Fase 1 inventory findings

- Missing native `Sandbox_EN.txt` for the one sandbox option — same recurring pattern as
  `zombie-decay`/`simple-belt-flashlight`/`push-vehicle`/`immersive-suicide`. Fixed (see Adaptation).
- Ships `Translate/<LANG>/{Entity,IG_UI,Tooltip}.json` for 9 languages (EN, PTBR, CH, ES, FR, IT,
  JP, PL, UA) with keys like `EC_Weight`, `IGUI_invpanel_weight`, `Tooltip_item_Weight` — **these
  look like vanilla's own generic UI label keys, not mod-specific ones, and nothing in this mod's
  own Lua ever calls `getText()` on any of them** (the "Set Weight" menu label is a hardcoded plain
  string, not a translation key). Left as inert, unused dead weight — **not** promoted to a native
  `.txt` file, since doing so would mean this bundle starts overriding vanilla's own "Weight"/"Stack
  Weight" labels pack-wide, which is out of this mod's actual scope and not something asked for.
  An empty `Translate/TR/` folder (no files at all, an apparently-abandoned partial Turkish
  translation) was preserved as-is too.
- No hard dependency on any other mod; 3 soft-optional weight tables for other mods (see above).
- No item/recipe/vehicle/trait/perk IDs introduced — only existing items' weight field is touched.
- No Java, no maps/tiledefs, no AnimSets, no monkey-patching of any vanilla class/function.
- No check of the mod's own Mod ID anywhere (Category A per architecture doc section 20).
- `mod.info` has 4 repeated `poster=` lines (`preview.png`, `poster_1.png`, `poster_2.png`,
  `poster_3.png`) — preserved verbatim, not something worth "fixing" to a single value.

## Adaptation applied (Fase 5)

- `id=TotalWeightRebalance` -> `id=LS_TotalWeightRebalance` (Category A rename).
- `name=`/`description=` rewritten to the pack's style, PT-BR.
- `versionMin=42.0` and `modversion=1.2` preserved verbatim from upstream.
- **Added `42/media/lua/shared/Translate/EN/Sandbox_EN.txt`** — same fix pattern as several prior
  modules, text copied from upstream's already-correct `Sandbox.json`.
- No PT-BR native file added — same accepted limitation as the rest of this pack (accented text
  breaks native `.txt` Lua-table translation loading, see [[feedback-ptbr-accents-in-lua]]). Note
  upstream didn't even ship a PT-BR `Sandbox.json` in the first place, only the unused
  Entity/IG_UI/Tooltip families.
- Everything else — both weight-table Lua files, the client UI Lua, `sandbox-options.txt`, `icon.png`,
  all 4 poster images, every language's JSON — copied byte-identical from upstream, confirmed via
  direct `diff`/`diff -rq`.
