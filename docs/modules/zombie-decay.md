# Module: Zombie Decay

| Field | Value |
|---|---|
| `module_key` | `zombie-decay` |
| Bundled location | `Contents/mods/LasciviousScripts/42/media/lua/{shared,client,server}/LasciviousScripts/ZombieDecay/` |
| Origin | own code (not derived from any upstream mod) |
| Namespace | `LasciviousScripts.ZombieDecay` |
| Sandbox option table | `LasciviousScriptsZombieDecay` |
| Current version | 1.0.0 (`Core.VERSION`) |
| Risk | high — overrides vanilla `AnimSets` paths, see [`COLLISION_REGISTRY.md`](../COLLISION_REGISTRY.md) |

This is a module of LasciviousScripts (`LasciviousScripts.ZombieDecay`), not a standalone mod.

## What it does

Deterministic, world-age-driven zombie decay: as in-game world age (`IsoWorld:getWorldAgeDays()`,
falling back to `getGameTime():getWorldAgeHours() / 24`) advances, the module progressively rewrites
vanilla `ZombieLore` sandbox values (`Speed`, `SprinterPercentage`, `Strength`, `Toughness`,
`Cognition`, `Memory`, `Sight`, `Hearing`) and nudges individual zombies toward a target speed tier
(Sprinter / Fast Shambler / Shambler), using a deterministic per-zombie seed
(`Core.getStableSeed`, preferring `zombie:getOnlineID()`) so tier rolls are stable and reproducible
across clients rather than re-randomized every check.

Six narrative phases (`SURTO_RECENTE` -> `DEGRADACAO_NEUROLOGICA`/`DEGRADACAO_MUSCULAR` ->
`COLAPSO_DA_CORRIDA` -> `DECOMPOSICAO_AVANCADA` -> `COLAPSO_FINAL_SHAMBLER` -> `ESTADO_FINAL`) are
keyed off five day milestones (`Core.BASE_DAYS`), scaled by `TimelineScalePercent`:

| Milestone (100% scale) | Day | Effect |
|---|---|---|
| `BrutalEnd` | 7 | End of the initial 100% Sprinter phase. |
| `RunnerSlowdownStart` | 30 | Runner speed begins lerping toward the floor. |
| `RunnerSpeedFloor` | 180 | Runner speed reaches `MinimumRunnerSpeedPercent`. |
| `RunnersGone` | 365 | Sprinter chance reaches 0%; population is 100% Fast Shambler. |
| `FinalDecay` | 730 | Fast Shamblers start converting to plain Shamblers (if enabled). |
| `FinalCollapse` | 1460 | Population reaches 100% Shambler (if `FinalShamblerCollapseEnabled`). |

`ZombieLore.DoorOpeningPercentage`, `ZombiesDragDown` and `ZombiesFenceLunge` are deliberately never
read or written by this module — those stay exactly whatever the server has configured natively
(explicit design decision, see the comment in `Core.captureOriginalLore`).

## Client vs. server split

- **`Core.lua`** (shared): pure math — config resolution, day-to-phase/tier calculations, the
  deterministic per-zombie roll, and vanilla-lore capture/apply/restore helpers. No event
  registration.
- **`Client.lua`**: owns per-zombie simulation. Hooks `OnGameStart`, `EveryTenMinutes` (world-lore
  refresh), `OnZombieCreate` and `OnZombieUpdate` (per-zombie tier enforcement + B42 root-motion
  `MoveScale`/`LungeScale` animation variables for partial-speed runners).
- **`Server.lua`**: keeps dedicated-server `ZombieLore` sandbox values aligned with world age via
  `OnInitGlobalModData`, `OnGameStart` and `EveryTenMinutes`. Does not touch per-zombie state
  directly — that's the client simulation's job on each machine (including a listen-server host).

## AnimSets overrides

Ships B42 vanilla `AnimSets` overrides under `media/AnimSets/zombie/{lunge,lunge-network,pathfind,
walktoward,walktoward-network}/` to support intermediate runner speeds via the
`LasciviousZombieDecayMoveScale` / `LasciviousZombieDecayLungeScale` animation variables applied in
`Client.lua`. These files must stay at their exact vanilla paths (case-sensitive on the Linux
dedicated server) — see [`COLLISION_REGISTRY.md`](../COLLISION_REGISTRY.md) for the full file list
and section 9.3 of [`ARCHITECTURE.md`](../ARCHITECTURE.md) for why they can't be namespaced/moved.

## Sandbox options

| Option | Type | Default | Purpose |
|---|---|---|---|
| `LasciviousScriptsZombieDecay.Enabled` | boolean | `true` | Master on/off switch for the whole system. |
| `LasciviousScriptsZombieDecay.TimelineScalePercent` | integer 25-400 | `100` | Scales all day milestones. 50 = twice as fast, 200 = twice as slow. |
| `LasciviousScriptsZombieDecay.MinimumRunnerSpeedPercent` | integer 25-100 | `50` | Runner speed floor reached around the 6-month milestone. |
| `LasciviousScriptsZombieDecay.FinalShamblerCollapseEnabled` | boolean | `true` | Whether Fast Shamblers keep decaying into plain Shamblers after day 730. |
| `LasciviousScriptsZombieDecay.DebugLogging` | boolean | `false` | Console logging of phase/percentage/speed calculations. |

## Important invariants

1. `Core.lua` stays pure/shared — no `Events.*.Add` in that file.
2. `ZombieLore.DoorOpeningPercentage`, `ZombiesDragDown`, `ZombiesFenceLunge` stay untouched — admin's
   call, not this module's.
3. Per-zombie tier rolls must stay deterministic per `getStableSeed` so simulation is consistent
   across clients; never switch to `math.random()` for the tier roll.
4. `AnimSets` override files stay at their exact vanilla relative path — never moved into the
   module's own namespaced folder.
