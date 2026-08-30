# Integration Notes — Plysken Solar Revolution

- `module_key`: `plysken-solar-revolution`
- `bundled_mod_id`: `LS_PlyskenSolarRevolution`
- Workshop item `3725311427`, upstream folder name `Plysken Solar Revolution` (contains a literal
  space). Upstream ships a genuinely new shape for this pack: the mod root has only `mod.info` +
  `poster.png` (no media at all); `common/media/` carries a compiled binary tiledef
  (`solarmodtiledefs.tiles`, magic bytes `tdef`) and its texture-pack atlas
  (`texturepacks/solarmod_tileset.pack`, ~780 KB) — the placeable solar-panel/battery-bank/inverter
  sprites; `42.1/` carries everything else (`mod.info`, all Lua, scripts, UI textures, a single
  world-item 3D model). `mod.info`'s own `pack=solarmod_tileset` / `tiledef=solarmodtiledefs 575`
  keys are what wire the tiledef into the game — both preserved verbatim, since renaming a tileset
  identifier would break the binary `.tiles` file's own internal reference to it (unlike the mod
  `id=`, which is just a folder/`Mods=`-string label). Consolidated `common/` + `42.1/` into this
  pack's single `42/` folder, same reasoning as `proximity-inventory`/`improvised-silencers`/
  `clean-hotbar` (this pack only ever targets one build).

## What it does

Adds a solar-power system: craftable solar panels (roof-tile, wall-mounted, floor-mounted),
a placeable "Battery Bank" that stores charge from linked panels and an inverter, an optional
backup-generator failsafe, and a "Solar Computer" terminal for remote device management (toggling
lights/appliances/fridges/freezers wired to the bank's covered building). Panels connect to a bank
within a sandbox-configurable range/floor radius; multiple banks can be linked into one network that
pools charge and drain. Batteries (wired car battery, DIY, improvised, or purpose-built deep-cycle)
slot into the bank and degrade with use. A player-built structure (not just a vanilla building) can
also be manually wired to a bank's coverage.

## Code quality — the most extensively self-audited mod reviewed in this pack

All Lua was read in full (initial batch by this session directly: `Patches.lua`,
`PowerBankSystem_Shared.lua`, most of `PowerBankSystem_Server.lua`, `PowerBankSystem_Commands.lua`,
`PowerBankSystem_Client.lua`; the remaining ~27 files — `PowerBankObject_Server/Client.lua`, all 4
UI files, all 8 `TimedActions/*.lua`, `Distributions.lua`, `PSR_RecipeCommands.lua`, the 4
`World/*.lua` files, `Utilities.lua`, `WorldUtilities.lua`, `MoveableProps.lua`,
`PSR_recipecode.lua`, `PSRMagazine.lua`, `PSR_BootBanner.lua` — by a delegated research pass whose
findings this document incorporates). This upstream carries an unusually deep in-code history of its
own bug hunts, dated 2026-06 through 2026-08-23, several explicitly citing player bug reports,
bytecode reads of vanilla classes, and measured (not assumed) reproduction steps before landing a
fix. Highlights:

- **Consistently server-authoritative.** All 8 `TimedActions/*.lua` files take primitive coordinates
  as constructor arguments (never live object references, because B42's `NetTimedAction`
  reconstructs actions server-side and can resolve an IsoObject-typed constructor arg to `null` on a
  dedicated server) and every `:complete()` re-resolves its target server-side from those
  coordinates rather than trusting anything the client claims — the same pattern this pack's
  `cyes-push-doors` and `improvised-silencers` were already praised for, applied here with the most
  explicit in-code justification of any module in the pack (bytecode-verified field-name/replication
  rules for `NetTimedAction.set()`). `ConnectStructure:complete()` additionally re-checks its own
  anti-grief sandbox gate server-side rather than trusting the client's menu-visibility check.
- **"Positive proof required to erase" discipline**, applied repeatedly to destructive cleanup paths
  (`OnChunkLoaded`, `WorldUtilities.lua`'s link-healing functions): an unresolved/unloaded chunk is
  always treated as "unknown," never as "gone," so a transient loading gap can never permanently wipe
  a bank's saved links. The in-code comments explicitly attribute this discipline to a lesson learned
  from a sibling mod's food-loss incident.
- **Real MP-authority split in the device-management UI**: `PSRComputerPanel.lua` branches cleanly —
  SP/coop-host reads/writes the server object directly; a dedicated client only ever sends a
  request/toggle command and applies whatever the server pushes back. No client-supplied device state
  is trusted.
- **Anti-grief-aware loot/coverage code**: `PowerBankObject_Server.lua`'s building-drain scan
  explicitly refuses to bill or expose a neighbour's building/vanilla generator; `Distributions.lua`
  wraps every loot-table insertion in a guard that skips (rather than crashes worldgen) if a
  third-party loot-overhaul mod has already restructured the vanilla table it expects.
- A handful of **currently-open, upstream-acknowledged edge cases** remain (not fixed here — see
  "Not changed" below): same-floor-only drain coverage for player-built structures, a low-probability
  electrified-chunk residue if a bank is dismantled while some of its covered chunks are unloaded, and
  a same-floor-only toxic-fumes re-warning. All three are explicitly reasoned about in the upstream's
  own comments (cost/likelihood weighed, not overlooked) rather than being silent gaps.

## Cross-checked against every one of this pack's other 25 bundled modules — no real collision

- **`ISInventoryPane.drawItemDetails`** is patched by both this module (`PSRUI.lua`'s
  `ISInventoryPane_drawItemDetails_patch`, installed in `~_PSR_Compatibility_client.lua`) and
  `improvised-silencers` (`ISIL_DurabilityInventoryPane.lua`). Both sides use capture-before +
  conditional-delegate: PSR only replaces the draw for items carrying its own `PSR_maxCapacity`
  modData (its batteries), always calling through to whatever was installed before it otherwise;
  ISIL always calls through first and only appends a suppressor-durability bar afterward. Since the
  two mods' item sets never overlap (batteries vs. weapon suppressors), each patch only ever takes
  its "special" branch for its own items and delegates for everything else — composes correctly
  regardless of load order, no ordering constraint needed.
- **`zombie.inventory.types.DrainableComboItem`'s `DoTooltip`** is patched by this module (via the
  generic `PSR.patchClassMetaMethod` helper in `Utilities.lua`, install site in
  `~_PSR_Compatibility_client.lua`) for items with `PSR_maxCapacity` modData. `improvised-silencers`
  separately patches `ISToolTipInv:render()` (the tooltip *window*, not the item's own `DoTooltip`),
  which calls through to `item:DoTooltip()` for non-suppressor items — different classes, no
  functional overlap (a PSR battery is never a suppressor `WeaponPart`).
- **`ISReadABook`** is touched by both this module (`PSRMagazine.lua` wraps `.complete`, teaching
  crafting recipes when the PSR magazine is finished) and `burris-quality-of-life`
  (`BQoL_WalkTweaks.lua` wraps `.new`, to allow reading while walking) — different methods on the
  same vanilla class, no call-chain interaction, both capture-before + always-call-through.
- **`ISMoveableSpriteProps`** — the vanilla class governing moveable-item placement — is patched
  5 ways by this module (`MoveableProps.lua`: `.new`, `canPlaceMoveable`, `canPlaceMoveableInternal`,
  `placeMoveable`, `walkToAndEquip`), the single largest patch surface in the module. Grepped across
  all other bundled modules: no other module touches this class. Sole owner, no collision.
- No recipe-name, item-fullType, `AcceptItemFunction`, or `mod.info id=` collisions found via a
  literal-string grep of all 17 recipe names / `AcceptItemFunction.PSR_Batteries` /
  `id=PSR` against every other bundled module's scripts and mod.info files.
- **Soft cross-mod dependencies, both currently inert in this pack**: this module reads/writes a
  third-party "PFR" mod's `PFR_isColdUnit`/`PFR_on` modData tags (to remote-toggle a PFR cold unit
  from the Solar Computer) and checks for mod id `"PUR"` via `getActivatedMods()` (a dug-basement
  drain bridge) — neither PFR nor PUR is bundled in this pack, and both checks are tag/ID-based with
  no hard `require=`, so they simply never fire. Worth re-checking if either is added to this pack
  later, since this module's behavior would then change automatically.

## Fase 1 inventory findings

- **Biggest finding: zero native `.txt` translations shipped upstream, in any of the 28 languages.**
  Every one of the 7 translatable families (`ContextMenu`, `IG_UI`, `ItemName`, `Moveables`,
  `Recipes`, `Sandbox`, `Tooltip`) exists only as JSON. Vanilla's `getText()` — used by every one of
  these families in normal play, including the native Sandbox Options screen — never reads JSON (see
  [[feedback-sandbox-options-native-txt-required]]), so without native `.txt` files every one of
  this module's 210 player-facing strings (item names, context-menu labels, tooltips, recipe names,
  all 16 sandbox options) would have rendered as raw untranslated keys in-game. This is the same
  pattern `burris-quality-of-life` hit, but broader: that module was missing only its 6 non-`IG_UI`
  families, this one was missing all 7. Fixed (see Adaptation).
- Sandbox cross-check: all 16 declared options in `sandbox-options.txt` are read somewhere in the
  Lua. One dead JSON/Lua key found (`Sandbox_PSR_solarPanelWorldSpawns` / `SandboxVars.PSR.
  solarPanelWorldSpawns`) — the option was deliberately removed from `sandbox-options.txt` upstream
  on 2026-08-04 (its own comment: "an option that does nothing is a UI lie"), and its only caller
  (`RandomWorldSpawns.lua`'s `doRolls()`) is itself unreachable dead code. Left as-is — matches
  upstream's own JSON, which still carries the same unused key, and it's inert either way.
- No `require=`, `loadModAfter=`, or `loadModBefore=` in `mod.info` — no hard ordering dependency on
  any other module in this pack.
- PT-BR JSON is well-formed and 100% key-complete against EN across all 7 families (210/210 keys),
  but contains accented characters in 83 of those 210 strings — see `TRANSLATION_PTBR.md`.

## Adaptation applied (Fase 5)

- `id=PSR` -> `id=LS_PlyskenSolarRevolution` (Category A rename, no self-Mod-ID check found
  anywhere in the Lua); `name=`/`description=` rewritten to the pack's style, PT-BR (`description=`
  is Java-parsed, not Kahlua, so accents render correctly there — see
  [[feedback-ptbr-accents-in-lua]]). `versionMin=42.0`, `modversion=1.76`, `poster=poster.png`,
  `pack=solarmod_tileset`, `tiledef=solarmodtiledefs 575` all preserved verbatim. Removed `url=`
  (empty) and `incompatible=ISA_41,ISA,ISA_42` — those three Mod IDs (the original
  ImmersiveSolarArrays this module forked from, and its own older build-specific variants) will
  never exist in this pack's curated `Mods=` list, same reasoning already applied to
  `drag-bodies-faster`'s and `clean-hotbar`'s own removed `incompatible=` lines.
- Consolidated upstream's `common/media/` (the tiledef + texture-pack atlas) and `42.1/` (mod.info +
  all other media) into this pack's single `42/` folder — no functional change, this pack's standard
  single-build layout.
- Added native `ContextMenu_EN.txt` (25 keys), `IG_UI_EN.txt` (104 keys), `ItemName_EN.txt` (8 keys,
  bracket-string keyed since item fullTypes contain a literal `.`), `Moveables_EN.txt` (6 keys),
  `Recipes_EN.txt` (17 keys, 2 bracket-string keyed since their recipe names contain a literal `-`),
  `Sandbox_EN.txt` (47 keys), and `Tooltip_EN.txt` (3 keys) — 210 keys total, transcribed verbatim
  from the already-correct, already-complete EN JSON. Verified programmatically (key-set diff) that
  every native `.txt` file's key set exactly matches its JSON source, and `luac5.1 -p` confirms valid
  Lua syntax for all 7 files.
- All Lua, scripts, textures, UI assets, the 3D model, and the tiledef/texture-pack binaries are
  byte-identical to upstream — confirmed via `diff -rq`. **Zero code changes.** This is the first
  module in this pack bundled with no bug fixes at all, a direct consequence of the upstream's own
  code quality (see above).

## Not changed — upstream-acknowledged open limitations (left as-is)

Each of these is explicitly reasoned about in the upstream's own comments (cost/likelihood weighed,
not an oversight), so none were treated as bugs to fix in this integration:

1. A dismantled bank does not retry clearing its electrified-chunk coverage if some covered chunks
   were unloaded at the moment of removal — low-probability (players are usually standing at the
   bank when dismantling it).
2. The toxic-fumes re-suppression warning (not the suppression itself, which is unconditional) only
   checks the bank's own z-level for a competing generator.
3. Player-built (non-vanilla-building) structure drain coverage is same-floor-only.

## Cross-project note

The sibling `LasciviousSystems` shop catalog already carries `nameOverride` entries for this
module's items (added 2026-08-23, ahead of this integration) — no action needed here, noted only for
awareness that the shop-side integration predates this one.
