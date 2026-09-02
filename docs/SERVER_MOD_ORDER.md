# Server Mod Order

Canonical `Mods=` order for the dedicated server, per section 22 of
[`ARCHITECTURE.md`](ARCHITECTURE.md). This file is the human-readable record; when the registry
grows, `tools/generate_server_mods.py` derives the same string mechanically from
[`MODULE_REGISTRY.md`](MODULE_REGISTRY.md) so the two never drift apart.

## Workshop item

```
WorkshopItems=3788475731
```

## Mod order

```
Mods=LS_AegisPanel;LS_AliceWeaponSling;LS_Antibodies;LS_BetterCorpseBurning;LS_BetterEngineRepair;LS_BetterPush;LS_BugFixes;LS_BurrisQualityOfLife;LS_CleanHotBar;LS_ClimbLadders;LS_CyesPushDoors;LS_DragBodiesFaster;LS_DurableToolsWeapons;LS_EquipWhileRunning;LS_EvilMortyDeathScreen;LS_FasterHoodOpening;LS_ImmersiveSuicide;LS_ImprovisedSilencers;LasciviousSystems;LS_Traits;LS_MiniHealthPanel;LS_OSRSExperienceBar;LS_PlyskenSolarRevolution;LS_ProximityInventory;LS_PushVehicle;LS_ResponsivePivoting;FixedLightOnBeltAF;LS_SkullysFasterAttackSpeed;LS_SkullysFasterSwingSpeed;LS_SpawnSelector;LS_SprintThroughWindows;LS_TacticalHold;LasciviousScripts;LS_TotalWeightRebalance;LS_WanderingZombies;LS_WildernessSpawnpoints
```

Thirty-six Mod IDs today — the originally scoped list, the later explicit Wilderness Spawnpoints
addition, the generic `LS_BugFixes` container, the first-party `LasciviousSystems` ecosystem and the
`LS_Traits` container are complete/active. Before Systems was
consolidated, `LS_AegisPanel` had no real collision against the other bundled modules. The
consolidated pack now has one intentional overlap: both Aegis and Systems wrap
`ISChat.onCommandEntered`; both preserve and call through to the previous handler, so no hard order
is required. The interaction is recorded in `docs/COLLISION_REGISTRY.md` and remains part of the
runtime staging matrix. Two other Aegis patches are logged in
`docs/COLLISION_REGISTRY.md` as occupied-surface watch items for future integrations
(`ItemContainer`'s class-metatable `getCapacity`/`getEffectiveCapacity`/`hasRoomFor`, and an unwrapped
`MapSpawnSelect:getSafehouseSpawnRegion` override with no call-through) — neither needs an ordering
rule today since nothing else in this pack touches either surface. See
`vendor/aegis-panel/INTEGRATION.md` for the full MP-authority audit (zero missing permission gates
across 26 server-side command files — the most rigorously engineered module in this pack).
No new hard ordering constraint from `LS_WanderingZombies`: its four
sandbox-screen wrappers do not overlap any bundled method, and the shared `OnZombieUpdate` surface
with `zombie-decay` consists only of additive event listeners. No new hard ordering constraint from
`LS_Antibodies`: its overlap with
`LS_BurrisQualityOfLife` is limited to different methods of `ISHealthPanel`, while
`LS_MiniHealthPanel` only instantiates the TimedActions that Antibodies safely wraps. No new hard
ordering constraint from `LS_PlyskenSolarRevolution`: it has
no `require=`/`loadModAfter=`/`loadModBefore=` and its two real cross-module surfaces
(`ISInventoryPane.drawItemDetails` shared with `LS_ImprovisedSilencers`, `ISReadABook` touched
alongside `LS_BurrisQualityOfLife` on a different method) both compose correctly regardless of
position — see `docs/COLLISION_REGISTRY.md` and `vendor/plysken-solar-revolution/INTEGRATION.md`.
No new hard ordering constraint from `LS_CleanHotBar` either: its one real
overlap with another bundled module (`ISHotbar.refresh`, shared with `FixedLightOnBeltAF` /
`simple-belt-flashlight`) composes correctly regardless of position, because Clean HotBar's own
wrap installs late (`Events.OnLoad`/`OnGameStart`, after every mod's file-scope Lua has already run)
and always calls through to whatever it finds already installed — see
`docs/COLLISION_REGISTRY.md` and `vendor/clean-hotbar/INTEGRATION.md` for the full trace. No new hard
ordering constraint from `LS_BetterCorpseBurning`: its world-menu hook is additive and its optional
`PhunZones` compatibility lookup only runs when a burn command is processed, after every submod has
loaded. The unique `BCB` network namespace and full interaction are recorded in
`vendor/better-corpse-burning/INTEGRATION.md` and `docs/COLLISION_REGISTRY.md`. One **hard,
code-discovered ordering constraint** applies on top of whatever
`tools/generate_server_mods.py` mechanically emits from the registry's row order — verify it still
holds after any future registry edit, don't just trust alphabetical coincidence:

`LasciviousSystems` also wraps `ISEquippedItem.render` for Hardcore Kits while Clean Hot Bar wraps
the same method for its equipped-item indicators. Both capture the previous function and call it,
so the canonical order above composes as Systems -> Clean Hot Bar -> vanilla at runtime. A clean
game/server start is order-independent; isolated debug reloads of only one of these files are not a
supported production operation and should be followed by a full Lua/game restart.

- **`LS_AliceWeaponSling` must load before `LS_EquipWhileRunning`.** Both fully reimplement
  `ISAttachItemHotbar:new/:perform/:stop` with no call-through, so whichever loads last wins each
  method outright. Only this order keeps both mods' effects composing correctly (traced in full in
  `vendor/alices-weapon-sling/INTEGRATION.md` and `docs/COLLISION_REGISTRY.md`). Currently satisfied
  because `alices-weapon-sling` sorts alphabetically before `equip-while-running` as a `module_key` —
  incidental today, required always.
- **`LS_BetterEngineRepair` must load before `LS_Traits`.** Better Engine Repair fully reimplements
  `ISRepairEngine:complete`; ETW inside `LS_Traits` wraps that method to track Bodywork
  Enthusiast/Mechanics progress. Loading Better Engine Repair first lets ETW wrap the already-fixed
  repair implementation; loading it after `LS_Traits` would overwrite ETW's tracker silently. The
  canonical order above satisfies this.

The core `LasciviousScripts` submod hosts own-code modules (`time-vote`, `vehicle-firearms` and
`zombie-decay`, internally). `LS_AliceWeaponSling` (craftable/lootable weapon sling clothing item, monkey-patches
`ISAttachItemHotbar`/`ISHotbar`/`ISEquipWeaponAction` — see the ordering constraint above) is bundled
alone; the upstream Workshop item also offers an optional radial-menu addon
(`alicesWeaponSlingRadialMenu`), which was bundled as `LS_AliceWeaponSlingRadialMenu` for a while and
then **removed entirely by the project owner's request** (not a bug, a product decision — see
`vendor/alices-weapon-sling/INTEGRATION.md`). `LS_Antibodies` (Antibodies 1.97 com correções B42.20 auditadas da versão
comunitária; simulação de infecção e cura exclusivamente server-authoritative em MP, prontuário e
namespace de sandbox preservados para saves existentes, wrappers de tratamento corrigidos para
propagar o resultado do `NetTimedAction` — ver `vendor/antibodies/INTEGRATION.md`).
`LS_BetterCorpseBurning` (queima em cadeia configurável de pilhas de cadáveres; comando, distância,
recursos e regras de zona validados no servidor, ver `vendor/better-corpse-burning/INTEGRATION.md`),
`LS_BetterEngineRepair` (full override of `ISRepairEngine:complete`,
verified faithful to vanilla by diff), `LS_BetterPush` (Strength-scaled zombie domino-knockdown,
fully rewritten MP protocol — see `vendor/better-push/LOCAL_CHANGES.md`), `LS_BugFixes`
(container para fixes pequenos; hoje inclui `MapAllKnownFix`, client-only, sem rede ou save data),
`LS_BurrisQualityOfLife`
(compilation of 14 sandbox-toggleable QoL features after removing two that duplicated
`simple-belt-flashlight`/`clean-hotbar` — prying is server-validated, tourniquet state reconciles
server-side, see `vendor/burris-quality-of-life/INTEGRATION.md`), `LS_ClimbLadders` (ladder
climb up/down, no monkey-patching, MP authority already correct upstream), `LS_CyesPushDoors`
(Strength/Fitness-scaled forceful door impacts against zombies and players, monkey-patches 5 vanilla
door-interaction classes, MP authority already correct upstream with its own candidate-arbitration
system — see `vendor/cyes-push-doors/INTEGRATION.md`), `LS_DragBodiesFaster` (AnimSets-only, no
Lua), `LS_DurableToolsWeapons` (pure vanilla-item script overrides, no Lua at all),
`LS_EquipWhileRunning` (client Lua monkey-patches + a small server-relayed network sync — see the
ordering constraint above), `LS_EvilMortyDeathScreen` (client-only cinematic death-screen pull-back
+ custom theme, monkey-patches 5 `ISPostDeathUI` methods with an idempotency guard; sound moved from
`Music`/3D to non-3D `UI` category and the recurring per-second `StopMusic()` removed, a local fix
for a buzzing/glitching-audio bug reported on the upstream Workshop page — see
`vendor/evil-morty-death-screen/INTEGRATION.md`), `LS_FasterHoodOpening` (single vanilla-file override),
`LS_ImmersiveSuicide` (server-authoritative self-only kill command), `LS_ImprovisedSilencers`
(5 craftable suppressors, server-authoritative durability with its own revisioned/retried network
sync, optional Guns of Marz/VFE compatibility that self-disables when neither is active — see
`vendor/improvised-silencers/INTEGRATION.md`; also wraps `ISRemoveWeaponUpgrade:complete`, verified
order-independent against `LS_AliceWeaponSling`'s own wrap of the same method, see
`docs/COLLISION_REGISTRY.md`), `LS_MiniHealthPanel` (minimalist wound panel, no monkey-patching,
treatment menu reuses vanilla's own global `HealthPanelAction` for actual execution — see
`vendor/mini-health-panel/INTEGRATION.md`; note the upstream's own B42 update notes admit it "was
not tested in multiplayer"), `LS_OSRSExperienceBar` (100% client-only RuneScape-style XP bar,
no monkey-patching, no network code — see `vendor/osrs-experience-bar/INTEGRATION.md`),
`LS_PlyskenSolarRevolution` (solar-power system — panels, linkable battery banks, inverter, backup-
generator failsafe, remote device-management terminal; consistently server-authoritative, every
TimedAction re-resolves its target server-side from primitive coordinates; the most extensively
self-audited upstream in this pack, bundled with zero code changes — see
`vendor/plysken-solar-revolution/INTEGRATION.md` and `docs/COLLISION_REGISTRY.md` for its two safe
cross-module surfaces), `LS_ProximityInventory`
(100% client-side loot-window container aggregator, no server Lua at all, no network code — see
`vendor/proximity-inventory/INTEGRATION.md`), `LS_PushVehicle`
(server-authoritative vehicle push/turn physics), `LS_ResponsivePivoting` (100% client-only
turn-speed tweak, no network code, adds two persisted traits — see
[`COLLISION_REGISTRY.md`](COLLISION_REGISTRY.md)), `FixedLightOnBeltAF` (Mod ID preserved from
upstream on purpose, see [`MODULE_REGISTRY.md`](MODULE_REGISTRY.md) and
`vendor/simple-belt-flashlight/INTEGRATION.md` — it's the one module in this pack not prefixed
`LS_`; also see `LS_CleanHotBar` below for the one real overlap between the two),
`LS_CleanHotBar` (full hotbar/equipped-item visual overhaul, no network code, no server Lua at all
— see `vendor/clean-hotbar/INTEGRATION.md`), `LS_TacticalHold` (cosmetic ready-pose animations for ranged weapons, server completely inert,
each client transmits its own pose via vanilla `transmitModData()` — see
`vendor/tactical-hold/INTEGRATION.md`), `LS_SkullysFasterAttackSpeed` (AnimSets-only override cutting the vanilla post-swing melee
delay) and `LS_SkullysFasterSwingSpeed` (client-local `CombatSpeed` multiplier on
`Events.OnWeaponSwing`, no network code) — two independent Mod IDs bundled from the same Workshop
item, complementary rather than mutually exclusive, see
`vendor/skullys-faster-attack-speed/INTEGRATION.md` — `LS_TotalWeightRebalance` (admin-gated
item-weight rebalance, no monkey-patching) — and `LS_WanderingZombies` (WIP 42.18 corrigida,
movimentação/hordas sob posse local do cliente e valores aleatórios sincronizados pelo servidor;
perfil padrão sem Pull, Migrate, Homing ou Flee direcionado ao jogador, ver
`vendor/wandering-zombies/INTEGRATION.md`).

No hard ordering constraint comes from `LS_SprintThroughWindows` either: it has no monkey-patches
at all, reacting to `Events.OnObjectCollide`/`OnPlayerUpdate` and calling the public API of vanilla's
own `ClimbOverFenceState`/`ClimbThroughWindowState` instead of overriding them, so nothing in this
pack can clobber or be clobbered by it — see `vendor/sprint-through-windows/INTEGRATION.md`.

No hard ordering constraint comes from `LS_WildernessSpawnpoints`: it contains only 29 namespaced,
static spawn-region definitions. Because the dedicated server uses an explicit spawn-region file,
merge the 29 entries from `vendor/wilderness-spawnpoints/SERVER_SPAWN_REGIONS.md` into
`/home/dahaka/Zomboid/Server/LASCIVIOUS_spawnregions.lua`; the module adds no world-map cells and
therefore requires no change to `Map=`.

## Ordering rules for future entries

When a third-party module is bundled as its own submod (`LS_<Nome>`), record here:

- any `require=` declared in its `mod.info`;
- any `loadModAfter=` / `loadModBefore=` declared in its `mod.info`;
- any load-order dependency discovered in code (e.g. one module reading a global another module
  creates) that isn't already expressed via `mod.info`.

Regenerate this section with `tools/generate_server_mods.py` after any change to
`MODULE_REGISTRY.md`'s module list rather than hand-editing the `Mods=` line, so the two stay in
sync.
