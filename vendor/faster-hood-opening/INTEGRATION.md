# Integration Notes — Faster Hood Opening

- `module_key`: `faster-hood-opening`
- `bundled_mod_id`: `LS_FasterHoodOpening`
- Simplest integration so far: a single Lua file that **fully replaces** the vanilla
  `media/lua/client/Vehicles/TimedActions/ISOpenMechanicsUIAction.lua` (the timed action that plays
  before a vehicle's mechanics/hood UI opens) — a genuine vanilla file-path override, not a
  monkey-patch-by-reassignment like `equip-while-running`.

## What it does

Confirmed by diffing directly against the vanilla copy of this exact file from the locally installed
game (`/home/dahaka/.local/share/Steam/steamapps/common/ProjectZomboid/projectzomboid/media/lua/client/Vehicles/TimedActions/ISOpenMechanicsUIAction.lua`,
current live install): the **entire file is byte-identical to vanilla except one line**:

```lua
-- vanilla
o.maxTime = 200 - (character:getPerkLevel(Perks.Mechanics) * (200/15));
-- this mod
o.maxTime = 22 - (character:getPerkLevel(Perks.Mechanics) * (22/15));
```

Base time to open the hood/mechanics UI drops from 200 to 22 (still scaled down further by the
Mechanics perk level, same formula shape, just a smaller base constant). No other line differs —
`isValid`/`waitToStart`/`update`/`start`/`stop`/`perform`/`new` signatures are all untouched vanilla
code.

## Fase 1 inventory findings

- No `mod.info` `versionMin`/`versionMax` declared upstream at all (no explicit build gate) — safe
  in practice since the file is confirmed in sync with the currently-installed live game version.
- No sandbox options, no `Translate/` folder, no text exposed to the player at all beyond the
  `mod.info` description.
- No dependency on any other mod, no `incompatible=` declared.
- No item/recipe/vehicle/trait/perk IDs, no Java, no maps/tiledefs, no save/modData use.
- No check of the mod's own Mod ID anywhere (Category A per architecture doc section 20).
- Purely client-side, purely local UI-open timing — no network command, no server-authoritative
  state touched, so no multiplayer-authority concern (see section 29 of the architecture doc).
- Registered in [`../../docs/COLLISION_REGISTRY.md`](../../docs/COLLISION_REGISTRY.md) as an
  occupied vanilla file path: any future mod that also ships a file at this exact relative path
  would silently clobber one or the other depending on `Mods=` load order.

## Adaptation applied (Fase 5)

- `id=FasterHoodOpening` -> `id=LS_FasterHoodOpening` (Category A rename).
- `name=`/`description=` rewritten to the pack's style, PT-BR (mod.info descriptions are parsed by
  Java, not Kahlua — not affected by the accent-rendering bug).
- `modversion=1.0.0` added (upstream didn't declare one); `versionMin=42.20` added explicitly since
  upstream had none.
- Dropped the legacy top-level duplicate (`mods/Faster Hood Opening/{mod.info,media/,poster.png}`)
  and the empty upstream `common/` — this project's own `common/media/` placeholder is used instead.
- The Lua file itself is byte-identical to upstream — zero changes beyond the vanilla override
  itself (which is upstream's whole point).

## Known update risk

Because this is a full-file override rather than a wrap/monkey-patch, **any** future vanilla change
to `ISOpenMechanicsUIAction.lua` (bug fix, new field, changed signature) is silently discarded until
this file is manually re-synced against the new vanilla version. Worth a direct diff against the
installed game's copy of that file on every PZ update, exactly like was done for this integration.
