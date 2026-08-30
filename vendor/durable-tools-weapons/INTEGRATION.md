# Integration Notes — Durable Tools and Weapons (Hardened)

- `module_key`: `durable-tools-weapons`
- `bundled_mod_id`: `LS_DurableToolsWeapons`
- Workshop item `3387217267` bundles 4 separate mods (`DTWhard`, `DTW` normal, `DTWsoft`, `DTWfirearms`,
  mutually exclusive difficulty tiers plus a separate firearms-durability submod). **Only `DTW_hard`
  (original `id=DTWhard`) was integrated.** `DTW_normal`, `DTW_soft` and `DTW_firearms` were not
  bundled and are not present anywhere under `Contents/` or `vendor/durable-tools-weapons/upstream/`.

## What it does

Pure `module Base { item X { ... } }` redeclaration of vanilla tool/weapon items, raising
`ConditionMax`/`ConditionLowerChanceOneIn` (and equivalent durability fields) roughly +75% over
vanilla. 351 items redeclared across 8 script files under `42/media/scripts/`:

| File | Items |
|---|---|
| `vanilla_items_carpentry.txt` | 2 |
| `vanilla_items_tools.txt` | 9 |
| `vanilla_items_weapons_1handed_axe.txt` | 16 |
| `vanilla_items_weapons_1handed.txt` | 102 |
| `vanilla_items_weapons_2handed_axe.txt` | 17 |
| `vanilla_items_weapons_2handed.txt` | 61 |
| `vanilla_items_weapons_heavy.txt` | 31 |
| `vanilla_items_weapons_long_blade.txt` | 14 |
| `vanilla_items_weapons_spears.txt` | 29 |
| `vanilla_items_weapons_stab.txt` | 70 |

Every redeclared item keeps its exact vanilla `DisplayName`, `Icon`, `StaticModel`,
`WorldStaticModel`, `Tags` and every other field — only durability-related fields differ from
vanilla. No item ID was renamed, no new item/recipe/trait/perk was introduced. See
[`../../docs/COLLISION_REGISTRY.md`](../../docs/COLLISION_REGISTRY.md) for the collision-registry
entry.

## Fase 1 inventory findings

- No Lua files anywhere in the mod (client/server/shared) — pure script content.
- No `sandbox-options.txt`, no `Translate/` folder — no sandbox options, no translatable strings.
- No Java/JAR, no maps/tiledefs/packs, no save/modData manipulation.
- No dependency on any other mod (`require`/`getActivatedMods()` not used — there's no Lua to use
  them from).
- `incompatible=\DTWsoft,\DTW` in upstream `mod.info` — the two sibling difficulty variants we did
  *not* bundle. Kept as-is (see Adaptation below).
- No check of the mod's own Mod ID anywhere (Category A per architecture doc section 20 — safe to
  rebrand the bundled Mod ID with no functional risk).

## Adaptation applied (Fase 5)

- `id=DTWhard` -> `id=LS_DurableToolsWeapons` (Category A rename, see above).
- `name=` updated to `Lascivious Scripts - Durable Tools and Weapons (Hardened)`.
- `description=` rewritten short/PT-BR to match this pack's style (see
  [`../../docs/ARCHITECTURE.md`](../../docs/ARCHITECTURE.md) section 37) — the original description
  block was English marketing copy (`+75% from normal DTW` etc.), not meant for translation via the
  JSON/Sandbox_<LANG> pipeline since `mod.info` descriptions aren't part of that system.
- `incompatible=\DTWsoft,\DTW` preserved verbatim — still correctly guards against a player also
  running the *standalone* Workshop versions of the sibling variants alongside this bundle.
- `versionMin=42.0.0` preserved verbatim (upstream's own floor; no reason to raise it).
- Dropped the legacy top-level `mods/DTW_hard/{mod.info,media/,icon.png,poster.png}` duplicate and
  the meta-only `common/` (icon/poster/mod.info with no `media/`) that the upstream packaging
  shipped alongside `42/` — neither is needed under this project's `common/` convention (see
  [`../../docs/ARCHITECTURE.md`](../../docs/ARCHITECTURE.md) section 4). Our own `common/media/` is
  an empty placeholder, matching every other submod in this pack.
- Na integração original, os scripts eram byte-identical ao upstream. Na revisão 42.20.4, LS-003
  os ressincronizou com o vanilla atual e reaplicou somente os dois campos de durabilidade; o
  snapshot upstream continua prístino. Ver `LOCAL_CHANGES.md`.

## Known update risk

Because this mod fully redeclares each item block (not a partial merge), a future vanilla update to
any of these 351 items (new field, changed `Tags`, renamed `Icon`, etc.) will be silently reverted to
whatever this mod's snapshot has until we resync against a newer vanilla baseline. Worth a periodic
diff against vanilla's own item scripts, not just against upstream DTW releases.
