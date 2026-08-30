# Integration Notes — Climb Ladders

- `module_key`: `climb-ladders`
- `bundled_mod_id`: `LS_ClimbLadders` — the exact name [`../../docs/ARCHITECTURE.md`](../../docs/ARCHITECTURE.md)
  section 1.1's example tree uses.
- Workshop item `3774776279`, upstream folder name `SubirEscaleras` (Spanish, "climb stairs" —
  author writes in Spanish; the mod ships EN/ES/ES_CL/ES_MX/DE/FR/PL/RU/CN/PTBR translations). Ships
  a top-level duplicate `mod.info` alongside `42/mod.info` (identical content, both `versionMin=42.15`
  — not a real build split, just redundant packaging) and no `common/` folder at all. Also ships a
  genuinely excellent `README.md` at the repo root (Spanish) documenting the engine internals, a real
  vanilla tiledef bug this mod works around, and the multiplayer design in detail — worth reading
  directly (`vendor/climb-ladders/upstream/README.md`) if this module ever needs deeper changes.

## What it does

Right-click "Climb up/down the ladder" on any climbable object in the game — including ones from
other mods, detected without a hardcoded list (see "Ladder detection" below) — plus a hold-E keybind
alternative. No sandbox options exist for this mod; its few tunables
(`SubirEscaleras.debug`/`climbTime`/`enduranceCost`/`blockIfInjured`/`minEndurance`/
`overloadPenalty`/`searchRadius`/`downSearchRadius`/`holdTicks`) are plain Lua variables at the top
of `SE_Utils.lua`, editable by hand per the upstream README's own "Ajustes" section — this is an
upstream design choice, not something to "fix" by adding sandbox options it never had.

## Code quality — exceptionally high, nothing needed patching

This is the most carefully engineered third-party mod integrated into this pack so far. Notable
points, all verified by reading the actual code (not just trusting the README):

- **Multiplayer done right, matching this pack's own hard-won lessons almost line for line**: client
  moves itself locally *and* sends `sendClientCommand("SubirEscaleras", "climb", {x,y,z})`; the
  server (`SubirEscaleras_Server.lua`) validates the destination is reasonable
  (`MAX_HORIZONTAL = 2` tiles, `MAX_VERTICAL = 8` levels, `z` in `[0,31]`) before calling
  `player:teleportTo()` — the upstream code's own comment explains *why* this validation exists:
  *"esto es una orden que puede mandar cualquier cliente... sin limites seria un teletransporte
  libre"* (this is a command any client can send; without limits it'd be a free teleport). Then the
  server explicitly broadcasts `sendServerCommand("SubirEscaleras", "climbed", {...})` so every other
  client repositions its own copy of that remote player (`SE_Sync.lua`) — the exact
  broadcast-and-apply-locally pattern this pack settled on independently while rewriting
  `better-push`. No LOCAL_CHANGES patch needed anywhere.
- **Explicitly avoids `media/AnimSets` after hitting a real, previously-shipped bug**: an earlier
  version shipped a custom AnimSet XML, which broke client/server file-verification handshake
  (reported as "can't connect" / servers stuck on "Loading the World" — see `SE_ClimbAction.lua`'s
  header comment and the README's animation section). Current version uses only the vanilla `Loot`
  action-layer animation instead. A `ClimbRope` variable cleanup runs on `OnCreatePlayer` as a
  migration safety net for characters who got stuck with it from that old version.
- **`isStandable()` uses `TreatAsSolidFloor()`**, replacing an earlier `getFloor() ~= nil` check that
  the README says caused a real player death from a fall due to false positives.
- **`moveSafely()` watchdog**: after moving the character, watches for up to 30 ticks and reverts to
  the origin square with a player-facing message if the destination turns out unstandable — a second
  safety net on top of the pre-move validation.
- Ladder detection tries, in order: engine `climbSheet{N,S,E,W}` flags -> tiledef `ladder{N,S,E,W}`
  properties (this is what makes it work with *any* mod's ladders, not just vanilla's) -> a hardcoded
  list of the 18 vanilla B42.20 ladder sprites (explicit fallback safety net) -> `CustomName`/sprite-
  name heuristic. The hardcoded list exists specifically because upstream found several vanilla
  ladder tiledefs that have `ladder*` but are *missing* `climbSheet*` (a genuine vanilla data bug,
  documented with exact sprite names in the README) — the engine itself won't let you climb those
  without this mod's workaround.

## Fase 1 inventory findings

- No sandbox-options.txt at all (see above) — nothing to add a native `Sandbox_EN.txt` for, unlike
  almost every other module in this pack.
- Missing native `ContextMenu_EN.txt`/`IG_UI_EN.txt`/`UI_EN.txt` — same recurring pattern as several
  prior modules (JSON shipped, nothing reads it natively). Fixed (see Adaptation).
- No dependency on any other mod (ladder detection is explicitly mod-agnostic by design).
- No monkey-patching at all — `ISSubirEscaleraAction` is a brand-new class
  (`ISBaseTimedAction:derive(...)`), not an override of an existing one. No vanilla file overrides,
  no AnimSets shipped (see above). Lowest collision risk of any bundled mod with real gameplay logic.
- No check of the mod's own Mod ID anywhere (Category A per architecture doc section 20).
- No icon/poster shipped at all (mod.info declares neither `icon=` nor `poster=`) — nothing to copy.

## Adaptation applied (Fase 5)

- `id=SubirEscaleras` -> `id=LS_ClimbLadders` (Category A rename).
- `name=`/`description=` rewritten to the pack's style, PT-BR; `versionMin=42.15`, `modversion=2.4`
  and `tags=Building,Misc` preserved verbatim.
- **Added `42/media/lua/shared/Translate/EN/{ContextMenu_EN.txt,IG_UI_EN.txt,UI_EN.txt}`**, text
  transcribed from upstream's already-correct EN JSON files.
- No PT-BR native file added — same accepted limitation as the rest of this pack (accented text
  breaks native `.txt` Lua-table translation loading, see [[feedback-ptbr-accents-in-lua]]) — even
  though, like `immersive-suicide`, a clean correct PT-BR JSON already exists upstream and was
  preserved (along with all 9 other languages' JSON) for fidelity/possible future use.
- Every Lua file copied byte-identical from upstream — confirmed via `diff -rq`. Zero code changes.
