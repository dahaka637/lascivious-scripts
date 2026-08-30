# Integration Notes — Skully's Faster Attack Speed

- `module_key`: `skullys-faster-attack-speed`
- `bundled_mod_id`: `LS_SkullysFasterAttackSpeed`
- Workshop item `3702483515` bundles **two separate, independent PZ mods** (each its own `mod.info`
  and Mod ID) inside a single Steam Workshop page: this one (`SkullysFasterAttackSpeed`) and
  `SkullysFasterSwing` (`id=SkullysFasterSwingSpeed`, see the sibling module
  [`../skullys-faster-swing-speed/INTEGRATION.md`](../skullys-faster-swing-speed/INTEGRATION.md)).
  Unlike `drag-bodies-faster`/`durable-tools-weapons`, these two are **not** mutually-exclusive tiers
  of the same effect — they touch different parts of the melee-attack pipeline (see below) and stack
  cleanly, so both were bundled as separate submods rather than picking one.
- Upstream `mod.info` declares `icon=logo.png`, but no `logo.png` (or any icon file under any
  casing) exists anywhere in the Workshop download — a pre-existing broken reference in the upstream
  itself. Dropped the `icon=` line rather than pointing it at a file that doesn't exist (see
  Adaptation). `poster.png` does exist and was kept. A `preview.png` (byte-identical to
  `poster.png`) also ships but isn't referenced by any `mod.info` key — not bundled (kept in the
  vendor snapshot for fidelity only).

## What it does

Pure `AnimSets` file-path overrides — no Lua, no scripts, no sandbox options. 9 vanilla animation
node XML files under `AnimSets/player/melee/{1handed,2handed,heavy}/` are overridden. Diffed
directly against the local vanilla install (`ProjectZomboid/projectzomboid/media/AnimSets/...`) to
confirm exactly what changes:

- **`SetMeleeDelay` event's `m_ParameterValue`** (the post-swing delay before the next attack can
  start) is cut roughly in half or more on the two files that have one: `KnifeDefault.xml` (8 -> 1),
  `HeavyDefault.xml` (12 -> 4). This is the actual "shortens time between attacks" mechanic the
  mod's own description promises.
- **`m_BlendOutTime`/`m_BlendTime`** (animation-state blend/transition smoothing, not a gameplay
  delay by itself) is tweaked on most of the 9 files, in both directions depending on the file —
  purely a smoothing/feel adjustment layered on top of the `SetMeleeDelay` change, not itself a
  speed mechanic.
- All 9 files declare `<m_SpeedScale>CombatSpeed</m_SpeedScale>` (unchanged from vanilla) — this is
  the same `CombatSpeed` character variable that the sibling `skullys-faster-swing-speed` module
  scales via Lua on `Events.OnWeaponSwing`. The two modules are complementary by design: this one
  shortens the fixed post-swing recovery delay baked into the AnimSet event, the other speeds up the
  swing animation's own playback rate at runtime.

All 9 paths are under `AnimSets/player/melee/...`, genuine vanilla file-path overrides (same class
as `zombie-decay`/`drag-bodies-faster`), logged in
[`../../docs/COLLISION_REGISTRY.md`](../../docs/COLLISION_REGISTRY.md). No overlap with either of
those modules' AnimSets subtrees (`zombie/lunge/...`, `draggingBody-.../...`).

## Fase 1 inventory findings

- No Lua anywhere in this mod — zero code, zero network commands, zero multiplayer-authority
  concerns, zero sandbox options, zero translatable text beyond `mod.info`.
- No dependency on any other mod, no `require=`/`loadModAfter=`/`loadModBefore=`.
- No check of the mod's own Mod ID anywhere (no Lua at all — Category A per architecture doc
  section 20, trivially safe rename).
- `common/` ships completely empty (no files at all, not even the AnimSets are there — everything
  lives under `42/media/AnimSets/`).

## Adaptation applied (Fase 5)

- `id=SkullysFasterAttackSpeed` -> `id=LS_SkullysFasterAttackSpeed` (Category A rename); `name=`/
  `description=` rewritten to the pack's style, PT-BR.
- Dropped the broken `icon=logo.png` reference (file doesn't exist upstream); kept `poster=`.
- Added `common/media/.gitkeep` (upstream shipped an empty `common/` with no files at all, not even
  a placeholder — Build 42 expects the directory to exist).
- Did not bundle `42/preview.png` (byte-identical duplicate of `poster.png`, unreferenced by
  `mod.info`).
- Five standalone AnimSet XML files remain byte-identical to upstream. The four `*OnFloor.xml`
  files were flattened from their `x_extends` inheritance after a real Linux dedicated-server boot
  showed that the engine tried to open lower-cased physical filenames. The flattened DOMs are
  semantically identical to `PZXmlUtil.resolve(child, parent)` and avoid duplicate lowercase alias
  nodes; see LS-003 in `LOCAL_CHANGES.md`.
