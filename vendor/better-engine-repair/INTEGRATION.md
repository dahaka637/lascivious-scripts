# Integration Notes — Better Engine Repair

- `module_key`: `better-engine-repair`
- `bundled_mod_id`: `LS_BetterEngineRepair`
- Workshop item `3780298250`, folder name `BetterEngineRepairB42`, already uses this project's own
  `common/`+`42/` layout. No `icon.png`/`poster.png` at all (upstream shipped neither, and doesn't
  declare `icon=`/`poster=` in `mod.info` — falls back to PZ's default, nothing to copy).

## What it does

Makes engine-condition repair (`Spare Engine Part` usage) configurable per Mechanics skill level
(0-10), via a `BetterEngineRepair.Mechanics<N>` sandbox integer (1-100, default table `3/3/3/3/5/5
/5/10/10/10/20`) instead of vanilla's fixed formula. Implemented as a **full replacement** of
`ISRepairEngine:complete()` (`Vehicles/TimedActions/ISRepairEngine.lua`), not a wrap — upstream's own
comment explains why: *"B42.20.x keeps the repair amount local inside ISRepairEngine:complete(), so
there is no narrower helper to override."* Guarded: checks
`if not ISRepairEngine or type(ISRepairEngine.complete) ~= "function"` first and prints a warning +
no-ops instead of erroring if the base function is ever missing/renamed.

## Verified against the locally installed vanilla copy

Diffed `BetterEngineRepairPatch.lua`'s replacement directly against
`.../ProjectZomboid/projectzomboid/media/lua/shared/Vehicles/TimedActions/ISRepairEngine.lua` (same
technique used for `faster-hood-opening`). Confirmed exactly two behavioral differences from
vanilla, both deliberate:

1. **Formula**: vanilla computes `skill = mechanicsLevel - vehicle:getScript():getEngineRepairLevel()`
   then `condPerPart = clamp(1 + skill/2, ..., 5)` (per-vehicle-difficulty-adjusted, capped at 5%).
   This mod uses the character's raw Mechanics level (no vehicle-difficulty subtraction) as a direct
   index into `BetterEngineRepair.getConditionGain()`'s sandbox-configurable table (up to 100%,
   default caps at 20% for level 10). This is the actual point of the mod, not a bug — vanilla's
   formula is hard to meaningfully tune (implicit −5-cap, vehicle-dependent); this one is a flat,
   directly configurable per-level table.
2. Every other line — item removal (`getSomeTypeRecurse`/`DoRemoveItem`/`sendRemoveItemFromContainer`),
   XP awarding, `sendObjectChange`, `addMechanicsItem`, `transmitPartCondition` — is **byte-identical**
   to vanilla. No new network calls, no new multiplayer surface: this override reuses 100% of
   vanilla's own sync primitives, so it carries exactly vanilla's own MP trust model, not a
   weaker one.

No LOCAL_CHANGES patch was needed — reviewed and confirmed safe, faithful to its own stated intent.

## Fase 1 inventory findings

- Already ships a correct native `Translate/EN/Sandbox_EN.txt` (unlike every other third-party mod
  integrated into this pack so far) — no translation bug to fix here. Also ships
  `Translate/RU/Sandbox_RU.txt`, kept as-is (harmless to preserve, doesn't affect PT-BR).
- No dependency on any other mod, no items/recipes/traits/vehicles introduced, no Java, no
  maps/tiledefs, no new save/modData usage (`addMechanicsItem` calls are unchanged from vanilla).
- No check of the mod's own Mod ID anywhere (Category A per architecture doc section 20).
- Full override of `ISRepairEngine:complete` registered in
  [`../../docs/COLLISION_REGISTRY.md`](../../docs/COLLISION_REGISTRY.md) as occupied surface — no
  overlap with any other bundled module today.

## Adaptation applied (Fase 5)

- `id=BetterEngineRepairB42` -> `id=LS_BetterEngineRepair` (Category A rename).
- `name=`/`description=` rewritten to the pack's style, PT-BR.
- `versionMin=42.20` and `modversion=1.0.0` added (upstream declared neither, though the mod's own
  Lua comment explicitly targets "B42.20.x").
- No PT-BR native sandbox file added — same accepted limitation as the rest of this pack (accented
  text breaks native `.txt` Lua-table translation loading, see [[feedback-ptbr-accents-in-lua]]).
- Everything else copied byte-identical from upstream — confirmed via direct `diff` against every
  file, zero code changes.
