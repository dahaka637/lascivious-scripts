# Integration Notes — Drag Bodies Faster (80%)

- `module_key`: `drag-bodies-faster`
- `bundled_mod_id`: `LS_DragBodiesFaster`
- Workshop item `3393821407` bundles **5 separate, mutually-incompatible mods**
  (`DBFaster25`/`DBFaster50`/`DBFaster60`/`DBFaster70`/`DBFaster80`, each declaring the other four as
  `incompatible=` in its own `mod.info`, and each `[SELECT ONLY ONE]` per its own description) — same
  pattern as `durable-tools-weapons`' Soft/Normal/Hardened tiers. **User picked the 80% tier
  (`DragBodiesFaster 80%`, original `id=DBFaster80`).** The other four tiers are not bundled and are
  not present anywhere under `Contents/`; only the 80% tier's files were snapshotted into
  `vendor/drag-bodies-faster/upstream/`.

## What it does

Pure `AnimSets` file-path overrides — no Lua, no scripts, no sandbox options, nothing but 12 XML
files overriding vanilla animation nodes for the drag/pick-up/lay-down-body actions. Confirmed by
comparing `<m_SpeedScale>` across all 5 tiers (all override the exact same 12 vanilla paths):

| Animation | 25% | 50% | 60% | 70% | 80% (bundled) |
|---|---|---|---|---|---|
| `draggingBody-*` (4 files, the ongoing drag-walk) | 1.00 | 1.20 | 1.28 | 1.36 | **1.44** |
| `pickUpBody-HeadEnd-onBack` / `layDownBody-*` (5 files) | 1.20 | 1.20 | 1.20 | 1.20 | **1.20** |
| `pickUpBody-HeadEnd-onFront` / `pickUpBody-LegsEnd-*` (3 files) | 1.00 | 1.00 | 1.00 | 1.00 | **1.00** |

Only the 4 `draggingBody-*` (ongoing drag) animations actually vary by tier — the math is consistent
with a vanilla baseline of `0.80` (`0.80 × 1.25 = 1.00` for the 25% tier, `0.80 × 1.80 = 1.44` for
80%, etc.), confirming the "+X%" naming is literal. The pick-up/lay-down one-shot animations get a
flat, tier-independent bump (1.20 for most, 1.00 unchanged for three of them) — not part of what the
tier selection controls.

All 12 paths are under `AnimSets/player/{draggingBody,layDownBody,pickUpBody}-{HeadEnd,LegsEnd}-
{onBack,onFront}/...xml` — genuine vanilla file-path overrides (same class as `zombie-decay`'s
AnimSets), all logged in
[`../../docs/COLLISION_REGISTRY.md`](../../docs/COLLISION_REGISTRY.md). No overlap with
`zombie-decay`'s own AnimSets (`zombie/lunge/...` — different subtree entirely).

## Fase 1 inventory findings

- No Lua anywhere in this mod — zero code, zero network commands, zero multiplayer-authority
  concerns, zero sandbox options, zero translatable text beyond `mod.info`.
- Upstream ships the AnimSets under `common/media/` (not `42/media/`) — preserved as-is (this is
  the upstream author's own choice, not something we're reorganizing into `common/` ourselves; see
  architecture doc section 4.1's "don't move things into common/ just to organize" applies to us
  moving things, not to leaving an upstream choice untouched).
- No dependency on any other mod.
- No check of the mod's own Mod ID anywhere (no Lua at all — Category A per architecture doc
  section 20, trivially safe rename).
- `author=Neighz` present in every tier's `mod.info` (pre-existing upstream data).

## Adaptation applied (Fase 5)

- `id=DBFaster80` -> `id=LS_DragBodiesFaster` (Category A rename; no "80" suffix in the Mod ID
  itself, matching how `durable-tools-weapons` dropped "Hardened" from its own ID — the tier is
  recorded in `name=`/this doc/the registry instead).
- `name=`/`description=` rewritten to the pack's style, PT-BR (mod.info descriptions aren't affected
  by the Kahlua accent-rendering bug).
- `versionMin=42.20` and `modversion=1.0.0` added (upstream declared neither, though `[B42]` in the
  original name implies general Build 42 support).
- All 12 AnimSet XML files copied byte-identical from the 80% tier's upstream — confirmed via
  `diff -rq`.
- The `incompatible=\DBFaster25,\DBFaster50,\DBFaster60,\DBFaster70` line from upstream was
  **dropped**, not preserved: those four Mod IDs will never exist in this bundle (we didn't bundle
  them), and there's no meaningful standalone-collision risk to guard against the way there was for
  `simple-belt-flashlight`'s Mod-ID-preservation case (a player having a *different* percentage tier
  of this exact mod installed standalone is a real but low-probability edge case; if it comes up,
  vanilla's own duplicate-Mod-ID rejection or the multiple-AnimSets-override load-order behavior
  handles it, not a specific `incompatible=` declaration we'd need to hand-maintain across 4 IDs we
  don't otherwise track).
