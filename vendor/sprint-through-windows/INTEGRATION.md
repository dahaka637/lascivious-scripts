# Integration Notes — Sprint Through Windows

- `module_key`: `sprint-through-windows`
- `bundled_mod_id`: `LS_SprintThroughWindows`
- Workshop item `3791228868` ("Sprint Through Windows" on the Workshop page) ships internally as
  `SprintDiveWindows` (`id=SprintDiveWindows` in `mod.info`, folder name `SprintDiveWindows`) — a
  single build-42 variant, no `42.19`/`42.20.2` split like `equip-while-running`.

## What it does

Lets a sprinting player smash/dive through a window instead of the vanilla "vault over fence" outcome
always applying to a plain window collision. Hooks `Events.OnObjectCollide`: when a sprinting player
collides with an `IsoWindow`/`IsoWindowFrame`/window-flagged `IsoThumpable`, it works out which
direction the player is diving, whether the window can actually be passed through (not barricaded/
invincible), and whether the player had enough of a run-up (`MinSprintTime` sandbox option). A short
run-up bounces the player off the window (`bounceOffWindow`, reusing the vanilla bump/stagger state);
a long enough run-up smashes the glass (`window:smashWindow()`), rolls a fail chance and a glass-cut
injury chance, and hands off to vanilla's own `ClimbOverFenceState` to actually perform the vault/dive
animation and movement. A custom AnimSet node (`diveThruWindowCrash`, condition-gated on a new
`DiveThruWindow` player anim variable this mod owns) swaps in a window-smashing animation instead of
the plain vanilla vault, unless `VanillaAnimation` is turned on. If the window has a multi-tile piece
of furniture blocking the landing square, it also repositions the player to the nearest free square
past the obstacle (`ClimbThroughWindowState.getFreeSquareAfterObstacles`) and relays that
reposition, plus the outcome (success/fall), to other clients so they see the dive animation and
landing position too — mirrors are needed because a remote client's local Character object doesn't run
this mod's own `OnObjectCollide` logic for you.

## Fase 1 inventory findings

- `sandbox-options.txt` with 6 native options under page `SprintDiveWindows`: `FailChance`,
  `InjuryChance`, `MinSprintTime`, `ShortSprintBreaksGlass`, `VanillaAnimation`, `Debug`. Already has
  a complete native `EN`/`PTBR` `Translate/*/Sandbox.json` pair upstream (13/13 keys) — PT-BR text was
  present but unaccented, corrected (see LOCAL_CHANGES LS-003).
- No dependency on any other mod — pure vanilla API (`Events.OnObjectCollide`/`OnPlayerUpdate`,
  `ClimbOverFenceState`, `ClimbThroughWindowState`, `IsoWindow`/`IsoWindowFrame`/`IsoThumpable`,
  `ZombRand`, `sendClientCommand`/`sendServerCommand`). No `require=`, no `getActivatedMods()`.
- No item/recipe/vehicle/trait/perk IDs introduced. No Java/JAR, no maps/tiledefs/packs.
- No check of the mod's own Mod ID anywhere (Category A — safe to rebrand).
- Does **not** monkey-patch any vanilla class — reacts to `Events.OnObjectCollide`/`OnPlayerUpdate`
  and calls into `ClimbOverFenceState`/`ClimbThroughWindowState`'s existing public API instead of
  overriding their methods. Checked against `docs/COLLISION_REGISTRY.md` and every other bundled
  module for `ClimbOverFenceState`, `ClimbThroughWindowState`, `IsoWindow`, `IsoWindowFrame`,
  `Events.OnObjectCollide` — **no hits, no collision** with anything currently bundled.
- Network module name `"SprintDiveWindows"` and sandbox namespace `SandboxVars.SprintDiveWindows` —
  checked against every other bundled module, no collision.
- AnimSet node `diveThruWindowCrash.xml` at `media/AnimSets/player/climbfence/` and clip
  `Bob_ValultOver_Sprint_Crash.x` — checked against vanilla's own `climbfence` folder (which has many
  files) and every bundled module's assets: **new file, no path collision**, picked up by
  condition-matching like `equip-while-running`'s own AnimSet nodes, not a vanilla override.
- Transient player anim variables only (`DiveThruWindow`, plus vanilla's own
  `ClimbFenceOutcome`/`ClimbingFence`) — not save-sensitive.
- **Server relay had zero validation** (see LOCAL_CHANGES LS-001) — same vulnerability class already
  found and fixed in `equip-while-running` (LS-001 there too). Patched here identically.
- `poster=poster.png` in the upstream `mod.info` pointed at a file that doesn't exist in the mod
  (only `preview.png` is shipped) — cosmetic upstream bug, fixed on rebrand (LS-002).

## Adaptation applied (Fase 5)

- `id=SprintDiveWindows` -> `id=LS_SprintThroughWindows` (Category A rename).
- `name=`/`description=` rewritten to the pack's style, in PT-BR (mod.info is parsed by PZ's own Java
  reader, not Kahlua — safe for accents, see [[feedback-ptbr-accents-in-lua]]).
- `poster.png` supplied from upstream's `preview.png` so the `poster=` reference actually resolves.
- **LS-001 (server hardening):** `SprintDiveWindows_Server.lua` now rejects `diveOutcome`/
  `diveLanding` relays unless `args.id == player:getOnlineID()`. `glassCut` was already safe
  (operates on `player` directly).
- **LS-003 (PT-BR polish):** rewrote the 13 native Sandbox translation strings with proper accents and
  more natural phrasing; kept exact key parity with `EN/Sandbox.json`.
- Everything else (client gameplay logic, AnimSet XML, `.x` clip, `sandbox-options.txt`,
  `EN/Sandbox.json`) is untouched, byte-identical to upstream.

## Known risks to watch

1. **No monkey-patch, but does read several vanilla class internals directly**
   (`ClimbOverFenceState.isObstacleSquare`/`isFreeSquare`/`getFreeSquareAfterObstacles`,
   `IsoWindowFrame.isWindowFrame`/`canClimbThrough`) — a future vanilla rename/removal of these
   specific methods would break the mod outright (not silently degrade). Re-check after a PZ update
   if window dives stop working.
2. **Client-only visual reposition on `diveLanding`**: the remote-client position write
   (`player:setX/Y/Z` in `SprintDiveWindows_Remote.lua`) is cosmetic and local to each observing
   client, not server-authoritative — it will self-correct on the next real position sync. Not
   treated as save-sensitive or a desync risk beyond a brief visual glitch, even after LS-001.
3. **Occupies `Events.OnObjectCollide` for window-diving purposes**: no other bundled module uses this
   event today. Check `docs/COLLISION_REGISTRY.md` before bundling another mod that also reacts to
   object collisions or the vault-over-fence states.
