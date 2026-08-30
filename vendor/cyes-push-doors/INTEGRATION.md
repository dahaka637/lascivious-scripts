# Integration Notes — Cye's Push Doors!

- `module_key`: `cyes-push-doors`
- `bundled_mod_id`: `LS_CyesPushDoors`
- Workshop item `3780683663`, upstream folder name `CyesPushDoors`. Ships a top-level duplicate
  `mod.info`/`icon.png`/`poster.png` alongside identical copies inside `42/` (not a real build split,
  just redundant packaging — only `42/` was bundled), an empty scaffold `common/` (just `.keep`
  placeholders, no content), and a stray empty `Nueva carpeta` folder at the top level (not part of
  the mod, excluded from the vendor snapshot and from the bundle).

## What it does

Right-click / hold-E interactions on doors (including thumpables, double doors, and garage doors)
can now be done "with force": impacts damage, stagger, or knock down zombies (and, if enabled,
other players) in the door's swing path. Damage/knockdown scale with the acting player's Strength
and Fitness, the door's material/type, its remaining durability, and a per-arm "strain" resource
that accumulates with use and recovers over time (discouraging spamming). Extensive Sandbox tuning
(16 options — damage/knockdown/wear/arm-strain multipliers, `DamagePlayers`, `KnockDownPlayers`,
`PlayerKnockdownChance`, `AffectCrawlers`, etc.).

## Code quality — exceptionally high, no patch needed

This is one of the best-engineered third-party mods integrated into this pack so far, on par with
`climb-ladders` and `total-weight-rebalance`. Notable points, all verified by reading the actual
code (not just trusting the description):

- **Solves the "every client observes the event" problem that this pack independently ran into
  while rewriting `better-push`** — via a candidate-arbitration system in `Server.lua`
  (`pendingDoors` / `candidateIsBetter`): the server prefers a candidate explicitly flagged
  `interaction=true` (the actual acting player, via a local input-intent captured on keypress in
  `Hook.lua`'s `armLocalInteractionIntent`/`consumeLocalInteractionIntent`) over passive "nearby
  scanner" observations reported by every other client who merely sees the door state change. This
  is a more sophisticated solution to the same MP race than this pack's own `better-push` rewrite.
- **Server-authoritative from the ground up**: `Core.getStrength`/`Core.getFitness` read directly
  from `character:getPerkLevel(Perks.Strength/Fitness)` on the server's own character object — never
  trusts a client-supplied stat value. `Core.validateServerRequest` (called from
  `Server.lua:onClientCommand`) validates the requesting player is alive, the transition type, the
  door's Z-level, and distance (`Config.MAX_SERVER_VALIDATION_DISTANCE = 2.25`, including both parts
  of a double door) before anything is queued. `Core.resolveDoorImpact` then independently
  re-validates transition/door-state/arm-strain/recovery/duplicate-impact and computes all
  damage/target-caps/knockdown outcomes itself, collecting targets (zombies *and* players) from the
  server's own square scan — never from client-reported target lists.
- **Explicit broadcast-and-apply-locally pattern**: `Server.lua` calls
  `sendServerCommand("CyesPushDoors", ...)` for `impactSound`/`doorHealth`/`armStrainSync`/
  `combatTextHit`/`playerImpact`/`zombieImpact`; `Client.lua` only ever applies effects to a *remote*
  player from a server broadcast (e.g. `player:setKnockedDown(true)` inside the `playerImpact`
  handler), never peer-to-peer — the same safe pattern this pack settled on independently while
  rewriting `better-push`.
- **Safe monkey-patching**: all 5 vanilla hooks (`Hook.lua:installHooks`) go through a
  `wrapTableFunction(tbl, key, slot, wrapperFactory)` helper that checks
  `if current == wrapped then return true end` (idempotency guard) and always calls the vanilla
  function through — never a blind reimplementation. `installHooks()` is also re-run every 300 ticks
  as a safety net against another mod re-patching the same slot afterward.
- Debug logging (`ServerFileDebug.lua`, a file sink) is fully gated behind `Config.DEBUG` (hardcoded
  `false` upstream) — inert unless explicitly turned on, not a concern.

## Fase 1 inventory findings

- Missing native `Sandbox_EN.txt` — same recurring pattern as most modules in this pack (JSON
  shipped, nothing reads it natively for the Sandbox Options screen). Fixed (see Adaptation).
- `IG_UI.json`'s 2 keys (`IGUI_CyesPushDoors_ImpactFeedback` + tooltip) are **unused** —
  `ModOptions.lua` passes literal already-selected EN/ES text directly to
  `PZAPI.ModOptions:addTickBox(...)` (its own `localText()`/`useSpanishText()` heuristic) instead of
  calling `getText()` on those keys. No native `IG_UI_EN.txt` was needed — nothing reads that JSON
  either. Confirmed via `grep -rn getText` across all 9 Lua files: zero matches anywhere in this
  mod's own code.
- No dependency on any other mod, no `require=`/`loadModAfter=`/`loadModBefore=` in `mod.info`.
- No check of the mod's own Mod ID anywhere (Category A per architecture doc section 20) — rename
  was safe.
- 5 monkey-patched vanilla classes, all via the safe wrap pattern described above (see
  `docs/COLLISION_REGISTRY.md`).

## Adaptation applied (Fase 5)

- `id=CyesPushDoors` -> `id=LS_CyesPushDoors` (Category A rename); `name=`/`description=` rewritten
  to the pack's style, PT-BR. `versionMin=42.20`, `modversion=1.0.2` preserved verbatim.
  `poster=`/`icon=` kept (both PNGs bundled, unlike most other modules in this pack).
- **Added `42/media/lua/shared/Translate/EN/Sandbox_EN.txt`**, text transcribed key-by-key from
  upstream's already-correct EN JSON (33 keys: page title + 16 options × label/tooltip). Real `\n`
  line breaks in the JSON tooltips were converted to PZ's own `<LINE>` tooltip markup (same
  convention already used natively by this pack's own `zombie-decay` module), and literal `%` signs
  were doubled (`%%`) to match the same already-verified-working convention.
- Every Lua file copied byte-identical from upstream — confirmed via `diff -rq`. **Zero code
  changes.** No MP patch was necessary — this module's own multiplayer design already matches (and
  in the candidate-arbitration case, exceeds) the pattern this pack settled on while rewriting
  `better-push`.
