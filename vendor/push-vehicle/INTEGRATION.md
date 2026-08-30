# Integration Notes — Push Vehicle

- `module_key`: `push-vehicle`
- `bundled_mod_id`: `LS_PushVehicle`
- Workshop item `3780639614`, folder name `PushVehicle`, already uses this project's own
  `common/`+`42/` layout (no legacy top-level duplicate, no per-point-version folders). Both Lua
  files' own header comments say "Project Zomboid Build 42.20" explicitly, matching this pack's
  target exactly even though `mod.info` itself declared no `versionMin`.

## What it does

Lets a player push a stationary vehicle forward/backward, or turn it by shoving near the front/rear
of either side, using the game's real shove-combat animation (`playerObj:setDoShove(true)` +
`AttemptAttack(0.0)` — the same fields RMB+Space combat shove uses) instead of a generic timed
action. Push force scales with Strength and inversely with vehicle mass; costs stamina. Adds a
context-menu option, an unbound-by-default configurable hotkey (inserted next to the vanilla
vehicle-radial-menu keybind in Options, with a documented fallback if that binding is ever renamed),
and a controller-radial-menu slice appended to `ISVehicleMenu.showRadialMenuOutside` (wrapped with
call-through + an idempotency guard, `ISVehicleMenu._PushVehicleRadialHookInstalled` — the same safe
wrap pattern `simple-belt-flashlight` uses, unlike `equip-while-running`'s from-scratch
reimplementations).

## Multiplayer authority — genuinely well done, no patch needed

Unlike `equip-while-running`'s original zero-validation relay (see that module's LS-001), this mod's
server side (`PushVehicle_Server.lua`) is a model example of section 29 of
[`../../docs/ARCHITECTURE.md`](../../docs/ARCHITECTURE.md):

- The client only ever sends a vehicle ID (`requestPush`); every other value (push zone/mode,
  direction, magnitude, endurance cost) is **independently recomputed server-side** from the actual
  server-side player/vehicle state, never trusted from the client.
- Server re-validates distance (`MAX_REQUEST_DISTANCE_SQ`), vehicle speed, player endurance, and
  whether the vehicle is even in a valid push zone, before doing anything.
- Side-turn pushing is force-disabled server-side when the sandbox option is off, "to also block
  stale/modified clients" (upstream's own comment) — the client-side check exists only for UI
  responsiveness, not as the actual gate.
- Vehicle physics authority is explicitly handed to the requesting player
  (`authorizationServerOnSeat`) and released from whoever held it before, one push at a time, with a
  documented remote-vs-authoritative-client force-scale mismatch (`x30`) deliberately corrected for
  in the remote path (`addImpulse` vs `applyImpulseGeneric`).

No LOCAL_CHANGES security patch was needed for this module — reviewed and confirmed safe as-is.

## Fase 1 inventory findings

- No `sandbox-options.txt` collision, no item/recipe/vehicle/trait/perk IDs introduced.
- No dependency on any other mod.
- **Two missing-translation-file bugs found, both fixed** (see Adaptation below) — same missing
  `Sandbox_EN.txt` pattern already seen in `zombie-decay` and `simple-belt-flashlight`, plus a
  second, more serious instance: `UI.json` was **also never read by any code** (`getText()` only
  reads native `UI_<LANG>.txt`), meaning `getText("UI_PushVehicle_Action")` — the actual context-menu
  /tooltip/radial-menu **label players click on** — had no backing text at all upstream, in any
  language including English.
- Monkey-patches `ISVehicleMenu.showRadialMenuOutside` (wrapped, not replaced) — registered in
  [`../../docs/COLLISION_REGISTRY.md`](../../docs/COLLISION_REGISTRY.md) as occupied surface. No
  overlap with any other bundled module's patched classes today.
- Network module name `"PushVehicle"` (matches the original Mod ID) used for
  `sendClientCommand`/`sendServerCommand`. Preserved verbatim, no collision with any other bundled
  module's network namespace today — logged as occupied namespace anyway.
- Keybinding ID `PushVehicle_Hotkey` stored in the global `keyBinding` table — this is a per-client
  input-config value (not save data). Preserved verbatim; renaming it on a future update would reset
  players' custom bindings for no benefit.
- No check of the mod's own Mod ID anywhere (Category A per architecture doc section 20 — safe
  rename).

## Adaptation applied (Fase 5)

- `id=PushVehicle` -> `id=LS_PushVehicle` (Category A rename).
- `name=`/`description=` rewritten to the pack's style, PT-BR; `versionMin=42.20` and
  `modversion=1.0.0` added (upstream declared neither).
- **Added `42/media/lua/shared/Translate/EN/Sandbox_EN.txt`** — same fix pattern as
  `zombie-decay`/`simple-belt-flashlight`, the one sandbox option's page/label/tooltip keys copied
  from upstream's already-correct `sandbox.json` text.
- **Added `42/media/lua/shared/Translate/EN/UI_EN.txt`** with `UI_optionscreen_binding_
  PushVehicle_Hotkey` and `UI_PushVehicle_Action` (again, text copied from upstream's own
  `UI.json`, which had the right strings but in a format nothing in-game reads). This is the more
  important of the two fixes here — without it, the mod's main context-menu entry has no label.
- No PT-BR native file added for either family — same accepted limitation as the rest of this pack
  (accented text breaks native `.txt` Lua-table translation loading, see
  [[feedback-ptbr-accents-in-lua]]).
- Everything else (both Lua files, `sandbox-options.txt`, `poster.png`) copied byte-identical from
  upstream — confirmed via direct `diff`.
- Dropped the two empty `_push_vehicle_no_{actiongroups,animsets}.txt` placeholder files (Steam
  Workshop packaging keeps empty directories with a placeholder file; not needed once the directory
  itself isn't shipped at all in our bundle).
