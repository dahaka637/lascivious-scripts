# Integration Notes — Skully's Faster Swing Speed

- `module_key`: `skullys-faster-swing-speed`
- `bundled_mod_id`: `LS_SkullysFasterSwingSpeed`
- Workshop item `3702483515` bundles **two separate, independent PZ mods** (each its own `mod.info`
  and Mod ID): this one (`SkullysFasterSwing`, `id=SkullysFasterSwingSpeed`) and
  `SkullysFasterAttackSpeed` (see the sibling module
  [`../skullys-faster-attack-speed/INTEGRATION.md`](../skullys-faster-attack-speed/INTEGRATION.md)).
  They're complementary rather than mutually exclusive — see that file for how the two interact —
  so both were bundled as separate submods.
- Same broken upstream reference as the sibling module: `mod.info` declares `icon=logo.png`, but no
  such file exists anywhere in the download. Dropped (see Adaptation). `poster.png` exists and was
  kept; the unreferenced duplicate `preview.png` was not bundled.

## What it does

A single Lua file (`swing_time_skully.lua`, 21 lines, no other code in the mod) listens to
`Events.OnWeaponSwing` and scales up the character's `CombatSpeed` variable — the same variable
vanilla's own `AnimSets` reference via `<m_SpeedScale>CombatSpeed</m_SpeedScale>` to control how
fast the swing animation itself plays back:

```lua
if swingAnim == "Heavy" then combatSpeed = min(combatSpeed * 1.5, 1.51)
elseif swingAnim == "Stab" then combatSpeed = min(combatSpeed * 1.22, 1.23)
else combatSpeed = min(combatSpeed * 1.1, 1.11) end
```

Ranged weapons are excluded (`handWeapon:isRanged()` early return). The multiplier is capped
per-branch (`math.min`) regardless of how large the pre-existing `CombatSpeed` already was.

## Why this is safe in multiplayer despite having no explicit network code

`CombatSpeed` is a vanilla, engine-managed per-character **animation blend variable** (confirmed via
`grep` against the local vanilla install — referenced by `item:getCombatSpeedModifier()` and used
natively by the AnimSet system), not a networked gameplay stat and not something this mod invents.
Every client independently renders every character's animations from that character's own already-
synced state (equipped weapon, skill, injuries, etc.) — this mod just adds a deterministic
post-multiply on top of whatever `CombatSpeed` vanilla already computed, using only inputs every
client already has locally (the swinging character's own weapon swing-anim type). There's nothing
here for a malicious client to spoof: it doesn't read or trust any value that originates from
another player, and it doesn't send or receive any network message. This is the same category of
"100% client-local, no network code" module as `responsive-pivoting`.

## Fase 1 inventory findings

- No monkey-patching — `Events.OnWeaponSwing.Add(...)` is a plain event subscription, not an
  override of an existing function.
- No sandbox options, no translatable text beyond `mod.info`.
- No dependency on any other mod (including no hard dependency on the sibling
  `skullys-faster-attack-speed` module — the two work independently of each other; one doesn't
  `require` or check for the other).
- No check of the mod's own Mod ID anywhere (Category A per architecture doc section 20).

## Adaptation applied (Fase 5)

- `id=SkullysFasterSwingSpeed` -> `id=LS_SkullysFasterSwingSpeed` (Category A rename); `name=`/
  `description=` rewritten to the pack's style, PT-BR.
- Dropped the broken `icon=logo.png` reference (file doesn't exist upstream); kept `poster=`.
- Added `common/media/.gitkeep` (upstream shipped an empty `common/` with no files at all).
- Did not bundle `42/preview.png` (byte-identical duplicate of `poster.png`, unreferenced by
  `mod.info`).
- `swing_time_skully.lua` copied byte-identical from upstream — confirmed via `diff -rq` and
  verified with `luac5.1 -p`. **Zero code changes.**
