# Integration Notes - Lascivious Traits

- `module_key`: `lascivious-traits`
- `bundled_mod_id`: `LS_Traits`
- Container submod for original character traits, inspired by mechanics/ideas seen across several
  third-party trait mods but implemented as our own code rather than a 1:1 port of any single
  upstream mod. Same "container that grows over time" shape as `bug-fixes`
  (`vendor/bug-fixes/INTEGRATION.md`), adapted for traits specifically.

## Status

Three framework dependencies (Moodle Framework, KillCount, UCWF) plus two trait bundles, **I
Regret Nothing** and **Evolving Traits World (ETW)** (see "Included Traits" below), are bundled and
validated. ETW's PT-BR translation is deliberately incomplete for now (project owner's explicit
call - implement first, translate once everything is functionally done). Not yet wired into
`docs/SERVER_MOD_ORDER.md`'s `Mods=` string or the live production ini - that happens once this
version is republished to Workshop and re-downloaded server-side, per the pack's standing
sequencing rule.

## Included dependencies

### Moodle Framework

- Workshop item `3396446795`, upstream `id=MoodleFramework`, `modversion=2.7`.
- Upstream ships **4 different code variants** for `MF_ISMoodle.lua` across version-numbered
  folders (`42.0`, `42.13`, `42.20`, plus `common/` for `MF_Config.lua` and translations) - these
  are NOT redundant packaging, they genuinely differ (see `git diff`-style comparison done during
  integration). We bundle only the `42.20` variant, the one actually applicable to our 42.20.x
  target, merged with `common/`'s `MF_Config.lua` and EN translation. Pristine snapshot of exactly
  that merged set: `vendor/lascivious-traits/upstream/moodle-framework/42/`.
- **Bundled directly inside `LS_Traits`, not as a separate Mod ID** - the project owner's explicit
  choice, same shape as PhunZones being embedded inside `LasciviousSystems` rather than kept as a
  separate `require=`d dependency (see `docs/modules/lascivious-systems.md`).
- Bundled files: `42/media/lua/client/{MF_Config.lua,MF_ISMoodle.lua}`,
  `42/media/lua/shared/Translate/EN/{UI_EN.txt,UI.json}`,
  `42/media/lua/shared/Translate/PTBR/UI.json` (readable PT-BR reference only, not a native `.txt` -
  same accepted limitation as the rest of the pack for non-Sandbox translation families; see
  `TRANSLATION_PTBR.md`).

#### What it does

A pure client-side UI framework: `MF.createMoodle(name)` registers a new moodle type (once, on
`Events.OnCreatePlayer` for local player slots only); `MF.getMoodle(name, playerNum):setValue(v)`
(0.0-1.0) drives its displayed intensity/level, which the consuming mod is expected to call whenever
the underlying stat/condition changes. Rendering, good/bad/neutral thresholds, chevron indicators,
tooltips and vanilla-consistent styling are all handled internally. No server file exists anywhere
in the upstream download - 100% client rendering, nothing authoritative.

#### Findings from reading the 42.20 code in full

- **No monkey-patching, no vanilla file override.** `MF.ISMoodle = ISUIElement:derive(...)` is a
  normal PZ subclass, not a patch of an existing class. Chevron/background/border textures
  (`media/ui/Moodle_chevron_*.png`, `media/ui/Moodles/<size>/_Moodles_BG*.png`) are real vanilla
  B42 assets referenced by path (confirmed present in the local vanilla install) - the framework
  ships none of its own, so there is nothing missing.
- **Splitscreen/local-only by design.** `MF.createMoodle` hooks `Events.OnCreatePlayer`, which only
  fires for the local machine's own player slots (0-3), never for other players joining a server -
  every internal comment says "splitscreen compatibility" for a reason. This means each client only
  ever tracks its own local character(s), never remote players.
- **Known, bounded, non-blocking memory note:** `MF.MoodleData` (line ~62 of `MF_ISMoodle.lua`) is a
  plain Lua table keyed by `tostring(self.char)`, populated on demand and **never explicitly
  cleared** - there is no removal path anywhere in the file, not even on `Events.OnPlayerDeath`
  (`MF.ISMoodle:suspend()` only sets `self.disable = true`, it does not drop the `MoodleData` entry
  for the dead character). Each local character death/respawn during one client session therefore
  leaves one small stale entry behind for the rest of that session. This is real but low severity:
  it is 100% client-local (never server-side, confirmed above), bounded by how many times *that one
  client's own local character* dies in *one session* (not by server population or uptime), and each
  entry is a few small fields. Not something to patch preemptively - noted here so it is not
  rediscovered from scratch if a very-long-session client ever reports elevated memory from this
  submod specifically.
- `PerformanceSettings.getLockFPS()` (used in the wiggle-oscillation animation) and
  `Registries.MOODLE_TYPE:values()` / `MoodleType.FOOD_EATEN` (used for vanilla-moodle position
  stacking) are genuine, current B42.20 APIs - confirmed directly against the local vanilla install
  and against the `PerformanceSettings` bytecode already decompiled during the unrelated Tempo
  mod investigation.
- Global namespace `MF` and every string this framework touches (`UI_options_MFColor_*`,
  `MoodleFramework` ModOptions key) checked against the other 33 submods - zero collision.

#### Local changes from upstream

None beyond file placement (dropped directly into `LS_Traits/42/media/lua/...` instead of a
standalone mod) and adding the PT-BR reference JSON. No line of the Lua itself was modified - see
`LOCAL_CHANGES.md`.

### KillCount

- Workshop item `2553809727`, upstream `id=KillCount`, `modversion=1.37`.
- Upstream ships the same multi-folder shape as Moodle Framework, but messier: a **root copy** (no
  version folder, legacy pre-restructure text), `42.0/`, `42.13/` (overrides only
  `WeaponTypeKillCount.lua`), `42.15/` (full set) and `common/` (base + translations +
  `sandbox-options.txt`, which no numbered folder provides its own copy of). Confirmed by diffing
  every file: `common/` and `42.15/` are byte-identical for 6 of 11 Lua files and genuinely differ
  on 5 (`ISCharacterInfoWindow_AddTab.lua`, `ISCharacterKills.lua`, `KillCountUpdate.lua`,
  `WeaponTypeKillCount.lua`, `server/KillCountServer.lua`). We bundle `common/` as the base
  (translations, `sandbox-options.txt`, the 6 identical files) with the 5 divergent files
  overlaid from `42.15/` - the highest numbered folder available and the one actually applicable to
  our 42.20.x target. Translations (`Sandbox`/`UI` JSON) were diffed key-for-key between `common/`
  and `42.15/` - identical, no drift to reconcile.
- Pristine snapshot of exactly that merged set: `vendor/lascivious-traits/upstream/killcount/42/`.
- **Bundled directly inside `LS_Traits`**, same as Moodle Framework.
- Bundled files: `42/media/lua/client/{ISCharacterInfoWindow_AddTab,ISCharacterKills,KillCountClient,
  KillCountClientModData,KillCountExports,KillCountUpdate,RISCharacterScreen,RISPostDeathUI,
  WeaponTypeKillCount}.lua`, `42/media/lua/server/KillCountServer.lua`,
  `42/media/lua/shared/KillCountShared.lua`, `42/media/sandbox-options.txt`,
  `42/media/lua/shared/Translate/EN/{Sandbox_EN.txt,Sandbox.json}` plus its `UI` keys merged into
  the submod's single canonical `UI.json`/`UI_EN.txt` (originally split into a separate
  `UI_KillCount_EN.txt`/`UI_KillCount.json` to dodge a filename clash with Moodle Framework's own
  `UI_EN.txt`/`UI.json` - **that turned out to be a real bug, not just tidiness**: PZ's translation
  loader reads exactly one file per category per mod, the same way it does for `Sandbox`; a
  differently-named `UI_KillCount.json` was silently never read at all. Fixed in LS-005, see
  `LOCAL_CHANGES.md` and `TRANSLATION_PTBR.md`),
  `42/media/lua/shared/Translate/PTBR/Sandbox.json`/`Sandbox_PTBR.txt` (native, generated via
  `tools/generate_ptbr_sandbox_native.py`) plus its `UI` keys merged into the submod's single
  canonical `PTBR/UI.json` (reference-only, same accepted non-Sandbox PT-BR limitation as the rest
  of the pack - no native `UI_PTBR.txt` exists for this family, see `TRANSLATION_PTBR.md`).

#### What it does

Tracks per-character kill counts by cause (weapon/genuine, fire, car, explosion) beyond vanilla's
own `getZombieKills()`, adds a detailed "Kills" tab (weapon-by-weapon breakdown) to the character
info window, augments the character-creation screen and the post-death screen with the
fire/car-inclusive total, and optionally exports the running total to a `killcount.txt` file for
streaming overlays. All tracking is event-driven heuristics client-side
(`OnZombieDead`/`OnCharacterDeath`/`OnWeaponHitXp`/`OnWeaponHitCharacter` correlation), stored on
`player:getModData().AKCModData` (`gk`/`fk`/`ck`/`ek` fields).

#### MP-authority finding - read before any trait reads this data

**The server does not validate the kill counts it receives - it trusts the client's self-report
verbatim.** `KillCountServer.lua`'s `OnClientCommand` handler ties the write to the *sender's own*
identity correctly (`command == player:getUsername()`, read from the engine's own connection
object, not from `args` - a client cannot forge another player's score), but then does
`gmd[command] = args -- override last values` with **zero validation of the values inside `args`**.
A modified client can report an arbitrarily inflated `gk`/`fk`/`ck`/`ek` for itself and the server
will store and (if `SandboxVars.KillCount.shareOnServer` is on, default true) broadcast it to every
connected client unquestioned.

Impact is bounded today because KillCount itself is purely cosmetic/informational (a display stat,
a leaderboard-style shared score) - faking it only wins bragging rights, nothing mechanical. **This
stops being true the moment a future trait reads this data to gate or scale a real effect** (e.g. "a
trait that grants a bonus past N kills"). If that is ever wanted, the trait's own server-side code
must independently corroborate the claim (e.g. cross-check against vanilla's own
`player:getZombieKills()`, which KillCount does not touch/replace, or maintain its own
server-side-only counter) rather than trusting `AKCModData` as a security boundary. Fine to use
`AKCModData`/`getZombieKills()` as pure *flavor* (a moodle showing "you feel bloodthirsty" text that
scales with a self-reported number) where a motivated player faking it costs nothing real.

#### Collision review

- `ISCharacterInfoWindow.createChildren` - **also wrapped by `LS_Antibodies`**
  (`Contents/mods/LS_Antibodies/42/media/lua/client/ui/is_character_info_window.lua`). Both sides
  use the pack's safe pattern (capture-before + always call-through, each adding its own distinct
  tab via `self.panel:addView(...)` without touching the other's), so this composes correctly
  regardless of load order - confirmed by reading both files in full, not just checking the pattern
  by name. No hard ordering constraint needed.
  - `ISCharacterInfoWindow_AddTab.lua` also wraps `:onTabTornOff` and `:SaveLayout` on the same
    class, both also capture-before + call-through. No other bundled module touches either method.
- `ISPostDeathUI` - **also touched by `LS_EvilMortyDeathScreen`**, but on entirely different
  methods (KillCount wraps `:addToUIManager` only, to replace one line of death-screen text with a
  fire-kill-inclusive total; Evil Morty wraps `:prerender`/`:onMouseWheel`/`:onExit`/`:onRespawn`/
  `:onConfirmQuitToDesktop` for the cinematic effect). No overlapping method, so no ordering
  question arises - genuinely additive, both effects apply together.
- `ISCharacterScreen.render` (the character-creation screen, via `RISCharacterScreen.lua`) - capture
  + call-through, plus a temporary hook-then-immediately-unhook of `ISUIElement.setHeightAndParentHeight`
  scoped to the duration of one render call (to grow the panel by one text line, then restored). No
  other bundled module touches `ISCharacterScreen` today.
- Sandbox namespace `KillCount.*` and every `KillCount`/`KC`/`AKC`-prefixed global/ModData key
  checked against the other 33 submods (now 34 with Moodle Framework already in) - zero collision.

#### Findings from reading the code in full

- No monkey-patch anywhere does a full silent replacement without calling through - every vanilla
  method touched follows the capture-before pattern.
- `ISCharacterKills` is KillCount's own new UI class (the detailed "Kills" tab content), not a
  patch of anything vanilla - all its `function ISCharacterKills:...` definitions are normal OOP on
  a class only this mod defines.
- `RISCharacterScreen.lua`'s `require ('XpSystem/ISUI/ISCharacterScreen')` looked like a possible
  third dependency at first read; confirmed against the local vanilla install
  (`media/lua/client/XpSystem/ISUI/ISCharacterScreen.lua`) that this is a genuine base-game B42
  file, not a separate mod - no hidden dependency.
- Optional soft-compatibility with "Bandits" (`getModInfoByID("Bandits")`, adjusts a height
  calculation) and "TchernoLib" (`getModInfoByID("TchernoLib")`, defers tab-adding to that library's
  own implementation if present) - neither is bundled in this pack, so both branches are simply
  inert no-ops for us.
- Server-side is a single small file (105 lines), read in full - no other authority concerns beyond
  the one documented above.

### Unified Carry Weight Framework (UCWF)

- Workshop item `3682045254`, upstream `id=UnifiedCarryWeightFramework`, `modversion=2.1.0`, single
  version folder (`42.19/`, no multi-version complexity like the other two dependencies).
- **Bundled directly inside `LS_Traits`**, same as the other two.
- Bundled files: `42/media/lua/client/UnitedCarryWeightFramework_Client.lua`,
  `42/media/lua/server/UnitedCarryWeightFramework_Server.lua`,
  `42/media/lua/shared/UnifiedCarryWeightFramework.lua`, two option blocks appended to
  `42/media/sandbox-options.txt` (merged into the same file KillCount's options already live in -
  PZ reads one `sandbox-options.txt` per mod, not per dependency),
  `42/media/lua/shared/Translate/EN/{Sandbox_UCWF_EN.txt,Sandbox_UCWF.json}` (upstream shipped no
  native EN file at all, only JSON - written by hand from the JSON, verified key-for-key identical),
  and the 2 UCWF keys merged into the *same* `Translate/PTBR/Sandbox.json` KillCount's keys live in
  (`tools/generate_ptbr_sandbox_native.py` reads exactly one `Sandbox.json` per mod and regenerates
  one `Sandbox_PTBR.txt` from it - a second JSON file would have been silently ignored by the tool).
- **Deliberately NOT bundled**: `UCWF_client_example.lua`, `UCWF_server_example.lua`,
  `UCWF_server_test_always_on.lua`. All three open with `if true then return end` - permanently
  dead author scratch/reference code, never meant to ship to players. Kept in the pristine
  `vendor/lascivious-traits/upstream/ucwf/` snapshot for reference (the example files are the best
  available documentation of the intended `registerBaseModifier`/`registerMaxModifier` usage
  pattern - read them before writing the first trait that touches carry weight), excluded from the
  bundled copy.

#### What it does

A pure registration-pipeline library: other code calls `UnifiedCarryWeightFramework.
registerBaseModifier(def)` / `registerMaxModifier(def)` with `{id=..., resolve=function(ctx) return
{add=N, mult=M} end}`. On `Events.EveryHours` (and `Events.OnCreatePlayer` in SP), it recomputes
every player's `maxWeightBase`/`maxWeightDelta` by folding every registered modifier's `resolve()`
result through a `(start + sum(add)) * product(mult)` pipeline. **Nothing runs at all until some
mod actually registers a modifier** (`systemShouldRun` starts `false` and nothing in this framework
itself ever calls the registration functions) - bundled with zero traits using it yet, this is
100% inert, exactly like Moodle Framework before `MF.createMoodle` is ever called.

#### Why this is inherently MP-authoritative (better than KillCount's situation)

The shared file (`UnifiedCarryWeightFramework.lua`) checks its own `gameMode()` and **returns
immediately, doing nothing, whenever `isClient()` is true** - the actual modifier pipeline only
ever executes in Singleplayer or on the dedicated server process, never on a network client. The
client-side file's only job is to detect a newly-spawned local player and, in MP, send
`sendClientCommand(player, "UCWF", "update_weight", {})` - an empty-payload trigger, not a claimed
result. The server handler (`Commands.update_weight`) ignores `args` entirely and just calls
`recomputeAll(player)`, which uses only server-registered modifier functions and the server's own
`player` object. A hostile client can request a recompute of its own weight on demand, but cannot
influence what value comes out - textbook "communicates intent, not result".

#### The `8` baseline - a concern raised and resolved during review

Reading `recomputeAll` in isolation, `local originalBaseWeight = 8` looks like it could silently
flatten vanilla's own Strength-based carry-capacity scaling every time a base modifier is
registered, since `player:setMaxWeightBase(newBaseWeight)` is computed from that hardcoded `8`, not
from whatever `maxWeightBase` currently holds. Checked directly against the vanilla 42.20 jar
(`javap` decompile of `IsoPlayer`/`IsoGameCharacter`): `maxWeightBase` is **not** dynamically
Strength-scaled in vanilla in the first place - it is Strength via a different vanilla path, and the
upstream author's own `UCWF_server_example.lua` explicitly comments `--- 8 is default game base
weight`, confirming `8` is the correct neutral vanilla baseline, not an arbitrary flattening value.
Separately, `maxWeightDelta` (the vanilla trait-based multiplier - Strong=1.5x/Weak=0.75x/
Feeble=0.9x/Stout=1.25x, confirmed in the same decompile) is handled more carefully by the MAX
pipeline: it reads the character's *current* `getMaxWeight()`, tries to detect and undo its own
previously-applied delta, and re-derives a new delta as a *ratio* on top - so the vanilla
trait-based multiplier survives being layered under UCWF's own max modifiers, rather than being
discarded. Net: registering a modifier with a `resolve()` that returns `{}` when it should not
apply is genuinely a no-op, matching the framework's own intended contract - no unresolved risk,
but this reasoning is worth keeping here rather than re-deriving it from scratch later.

#### Collision review

- No monkey-patching, no vanilla file override. Everything is done through the public
  `setMaxWeightBase`/`setMaxWeightDelta`/`getMaxWeight` API.
- Sandbox namespace `UnifiedCarryWeightFramework.*` and every UCWF-prefixed global checked against
  the other 33 submods - zero collision.
- **Real interaction to know about, not a bug**: `LS_AegisPanel` has an admin "pin carry weight"
  tool (`Aegis_Server.lua:carryApply`, continuously re-asserted client-side in
  `AegisHud.lua` whenever the observed `getMaxWeight()` drifts from the pinned value) that also
  calls `setMaxWeightBase`/`setMaxWeight` directly. Today, with zero UCWF modifiers registered,
  there is nothing to interact with. **Once a future trait registers a UCWF modifier**, an admin
  using the carry-weight pin on a player will see it briefly overwritten by UCWF's next
  `EveryHours` recompute, then immediately reasserted by Aegis's own drift-check - a visible flicker
  rather than a silent loss of the pin (Aegis's client-side check runs far more often than UCWF's
  hourly one), but worth knowing about before either system is used together with real traits. Not
  fixed now because it cannot manifest until a modifier actually exists; revisit when the first
  carry-weight-affecting trait is written (e.g. have that trait's `resolve()` be a no-op while the
  target player has an active Aegis pin, if that turns out to matter in practice).

## Included Traits

*(one `###` subsection per trait goes here as they are added, each noting: which upstream mod(s),
if any, inspired it; what was kept vs. reimplemented; whether it is fully original. Traits built on
top of this container can `require "MF_ISMoodle"` directly.)*

### I Regret Nothing

- Workshop item `3676431328`, upstream `id=IRegretNothingTrait`, `modversion=1.2.0`, author's own
  namespace `RegretNothing:RegretNothing`. Not "inspired by, reimplemented" like the container's
  general intent - this is a straight bundle of a specific existing trait mod (Postal 2 Dude
  homage), same shape as the three framework dependencies above rather than an original design.
- **Namespace kept as upstream's own `RegretNothing:RegretNothing`, not renamed to
  `lascivioustraits:regretnothing`.** The `lascivioustraits:` convention (see "Structural
  conventions" below) is reserved for traits authored from scratch for this container. This trait
  is a bundled port of a specific third-party mod, treated the same way Moodle
  Framework/KillCount/UCWF were: dropped in with its own identity intact, not re-branded. Renaming
  would have meant touching the `CharacterTrait.register` call, all three references in
  `traits.txt`, and the `ResourceLocation.of()` lookup in the mechanics file for zero functional
  gain - pure churn. Safe to revisit later if it ever ships to a save (see the save-persistence
  warning below), but not planned.
- Icon filename kept exactly as shipped, **including its mixed case**:
  `media/ui/Traits/trait_RegretNothing.png`. This looks like it violates the pack's own "lowercase
  everything on Linux" instinct, but checked against the local vanilla install
  (`media/ui/Traits/trait_<lowercase-name>.png` for every vanilla trait, e.g. `trait_artisan.png`
  for `base:artisan`): B42 derives a trait's icon path from the resource location's own local name,
  case preserved, not force-lowercased. Since the registered name here is `RegretNothing` (matching
  the icon's case), lowercasing the file would have broken icon resolution on our case-sensitive
  Linux server, not fixed anything. The pack's own future `lascivioustraits:<trait_name>` namespace
  is all-lowercase by convention specifically so this question never comes up for traits we design.
- Bundled files: `42/media/lua/client/RegretNothing_DudeMechanics.lua` (reinforced, see below),
  `42/media/lua/client/RegretNothing_Moodle.lua` (verbatim), `42/media/registries.lua` (first one
  for this submod - see "Structural conventions"), `42/media/scripts/RegretNothing/traits.txt`
  (verbatim), `42/media/ui/{MoodleRNFrenzy.png,MoodleRNMeleebuff.png,RNFrenzy.png,RNMeleebuff.png}`
  (verbatim), `42/media/ui/Traits/trait_RegretNothing.png` (verbatim, case preserved),
  its `UI` and `Moodles` keys merged into the submod's single canonical
  `42/media/lua/shared/Translate/{EN,PTBR}/{UI.json,Moodles.json}` (plus `EN/UI_EN.txt` and
  `EN/Moodles_EN.txt` natively, English coverage is complete so a native `.txt` is safe there -
  **originally shipped as scoped `UI_RegretNothing_EN.txt`/`.json` and
  `Moodles_RegretNothing_EN.txt`/`.json` files, which turned out to never be read by PZ at all -
  see LS-005 in `LOCAL_CHANGES.md` and `TRANSLATION_PTBR.md` for the root cause and fix**).
  Pristine upstream snapshot: `vendor/lascivious-traits/upstream/regret-nothing/42/`.

#### What it does

Adds a `+12` cost character trait that forces `base:smoker` and `base:desensitized`
(`GrantedTraits`), grants `+2` XP boost to Blunt/SmallBlunt, and is mutually exclusive with most
fear-related traits (agoraphobic, claustrophobic, cowardly, pacifist, hemophobic) and the two other
"pumped up" traits (brave, adrenaline junkie). Behaviorally: continuously zeroes Food Sickness,
Poison, Panic and Stress while worn (`RN_OnPlayerUpdate`, every frame); nudges Boredom/Unhappiness
down on a zombie kill and up if two hours pass without one; tracks a "frenzied" state (any bitten
body part) that zeroes Pain/Fatigue, maxes Endurance, and permanently boosts nine combat-relevant
perks to level 10 the first time it triggers per life; grants a 2-hour "combat high" buff (+10%
melee damage via `RN_OnWeaponHitCharacter`, slow Endurance regen) after eating/using a cigarette,
cigar or pills (`ISEatFoodAction:perform` hook); doubles condition-lower resistance the first time a
Shovel/Nightstick/Scissors is equipped. Two Moodle Framework moodles (`RNFrenzy`, `RNMeleebuff`)
surface the frenzy/combat-high states in the UI.

#### The reported bug, and what was actually found

The project owner flagged an unconfirmed Workshop comment describing an endless error stream
triggered by spawning with or admin-granting the trait. Read `RegretNothing_DudeMechanics.lua` (the
only file with meaningful logic - 310 lines, read in full) end to end rather than trusting either
the bug report or the file's own comments at face value:

- The **current downloaded version (1.2.0) already contains a real fix for exactly this bug
  class**, evidently added by the upstream author in response to the same reports: an `RN_safe(key,
  fn)` helper (top of file) that runs a risky call once and, on failure, permanently disables that
  one keyed operation for the session instead of retrying it every frame - with an explicit comment
  noting a bare `pcall` alone does **not** stop console spam, only prevents a crash, because PZ logs
  caught `pcall` errors too. This was already applied thoroughly to `RN_OnPlayerUpdate`, the
  highest-risk function since it runs every single frame, including a specific fix for a
  "poison the queue" pattern in the moodle-update branches: state flags (`RN_WasFrenzied`,
  `RN_WasBuffed`) are now written *before* the `MF.getMoodle`/`:setValue` call, not after - the old
  order meant a throw inside the Moodle Framework call skipped the flag write, so the same branch
  re-fired (and re-threw) on the very next frame forever.
- **The fix was inconsistently applied**, and this pack closed the gap (LS-004, see
  `LOCAL_CHANGES.md`): `RN_OnZombieDead` and `RN_EveryTenMinutes` still used a bare `pcall` around
  their stats writes (same spam risk, just lower-frequency triggers - a horde fight or a long AFK
  period could still produce a real stream), and `RN_OnWeaponHitCharacter` plus most of
  `RN_OnEquipPrimary` had **no error protection whatsoever** despite firing on frequent combat/equip
  events. All four now go through `RN_safe`, matching the pattern already proven in
  `RN_OnPlayerUpdate`. No behavior changed for the success path - only what happens the first time
  one of these calls throws.
- Nothing above required guessing at what triggers the throw in the first place (a Moodle Framework
  API change, a `CharacterStat` rename, etc.) - the fix class the upstream author already chose
  (disable-after-first-failure, one log line) does not need to know the cause, and this pack's
  extension follows the exact same shape rather than inventing a different mitigation.

#### Collision review

- `ISEatFoodAction:perform` - the trait's one monkey-patch (capture-before + always call-through,
  `orig(self, ...)` runs unconditionally before the trait-specific check). No other bundled module
  wraps this method today - new row added to `docs/COLLISION_REGISTRY.md`.
- `RegretNothing`/`RNFrenzy`/`RNMeleebuff` naming (globals, Moodle names, ModData keys) checked
  against the rest of the pack - zero collision.
- Item-type strings `Base.CigaretteSingle`/`Base.Cigar`/`Base.Pills` (read, not hooked, by
  `RN_InjectEatHook`) also appear in `LS_TotalWeightRebalance/weights_vanilla.lua` (weight-override
  table), `LasciviousSystems/HardcoreKits_Pools.lua` (kit loot pool) and
  `LasciviousSystems/LasciviousShop_Catalog.lua` (shop catalog entry) - all three are pure data
  references to the item type, not behavioral hooks on the same event, so there is no real overlap:
  this trait only reads the item's type after a normal eat action already completed elsewhere.
- `GrantedTraits = base:smoker;base:desensitized` checked against every other bundled trait/script
  for a conflicting grant of the same two vanilla traits - none found.

#### Local changes from upstream

`RN_safe` hardening extended to `RN_OnZombieDead`, `RN_EveryTenMinutes`, `RN_OnWeaponHitCharacter`,
`RN_OnEquipPrimary` (see above), plus writing EN and PT-BR translation content that did not exist
upstream in any form but JSON, merged into this submod's canonical translation files (see LS-004
and LS-005 in `LOCAL_CHANGES.md` - the filename-scoping approach LS-004 originally used turned out
not to work, fixed in LS-005).

### Evolving Traits World (ETW)

- Workshop item `2914075159`, upstream `id=EvolvingTraitsWorld`, `modversion=13.0.0`. By far the
  largest single piece ever bundled into this pack: 206 files, ~15,000 lines of Lua, 65 new
  traits plus a system that makes dozens of vanilla traits dynamically earnable during play
  instead of only pickable at character creation.
- `require=\MoodleFramework,\KillCount,UnifiedCarryWeightFramework` in upstream's own `mod.info` -
  **exactly the three framework dependencies already bundled into this submod**, confirming why
  they were added ahead of time. `incompatible=\DynamicTraits` (a different, unrelated dynamic-trait
  mod this pack does not use).
- **Bundled directly inside `LS_Traits`**, same as everything else in this container. Namespace
  kept as upstream's own `ETW:<TraitName>` (e.g. `ETW:Bloodlust`), same reasoning as I Regret
  Nothing - this is a bundled port of a specific mod's trait pack, not traits designed from
  scratch for this container.
- Single code version folder (`42.19/`, no multi-version-folder complexity like Moodle
  Framework/KillCount had) plus `common/` for translations, sounds and icons. Bundled files:
  the entire `42.19/media/lua/{client,server,shared}/**` tree (merged into this submod's existing
  `client/`/`server/`/`shared/` folders - zero filename collisions with the three dependencies or
  I Regret Nothing already there, checked before copying),
  `42.19/media/registries.lua` (`ETW_Registry.traits`, appended into this submod's shared
  `registries.lua` alongside I Regret Nothing's own registration),
  `42.19/media/sandbox-options.txt` (appended into this submod's shared sandbox-options.txt,
  same duplicate-`VERSION=`-line pitfall as the UCWF merge, caught and fixed the same way),
  `42.19/media/scripts/ETW_Traits.txt` (own file, 65 `character_trait_definition` blocks),
  `common/media/ui/{Traits/*.png (65 trait icons),Moodles/*.png (2),GradientBars/*.png (3)}`,
  `common/media/sound/*` (23 sound files - level-up/frenzy/scream stingers used by several
  traits), `common/media/scripts/ETW_{NotificationSounds,ParanoiaSounds,TraitSounds}.txt`.
  Translation content (`common/media/lua/shared/Translate/{EN,PTBR}/{Sandbox,UI,Moodles}.json`)
  merged into this submod's own canonical files per the LS-005 rule - see "Translation" below.
  Pristine upstream snapshot: `vendor/lascivious-traits/upstream/etw/` (both the `42.19/` and
  `common/` folders preserved as-is, no merge needed since there was no version-folder drift to
  resolve here).

#### What it does

Two mostly-independent halves under one Mod ID:

1. **65 new traits** (`ETW:*`), spanning combat (Bloodlust, Terminator, Prowess\*, weapon-specific
   fighter traits), health (Anemic, Thick Blooded, Hardy, Super Immune, Immunocompromised),
   mental (Ascetic, Blissful, Paranoia, Depressive, Self Destructive), and lifestyle/flavor
   (Gourmand, Home Cook, Hoarder, Pack Mule/Mouse, Quiet, Bad Teeth, Butterfingers). Most are
   dynamically earnable/losable during play via server-side condition checks
   (`server/DynamicLogic/`, `server/TraitsLogic/`), not just pickable at character creation.
2. **Vanilla trait dynamism**: `shared/ETW_MarkDynamicTraits.lua` registers ~65 vanilla traits
   (Cowardly, Brave, Outdoorsman, Hunter, Handy, Fast/Slow Learner, Smoker, and many more) as
   dynamically earnable too, driven by the same `DynamicLogic`/`TraitsLogic` condition checks
   (kills, skills, location, time played, weather exposure, health state).

Architecture: a small number of shared event handlers (`server/TraitsLogic/ETW_EventsOrchestrator.lua`)
do ONE player traversal per tick/minute/hour and dispatch to per-category logic modules
(Combat/Health/Mental/Weather traits), rather than each trait registering its own listener - a
notably more scalable design than a typical trait mod, consistent with the code quality found
throughout (every risky call is wrapped, every monkey patch captures-before and calls through,
every server file uses a `gameModeSafeguard` to stay out of the wrong process type).

#### MDTF (Mark Dynamic Traits Framework) - confirmed NOT needed

`ETW_MarkDynamicTraits.lua`'s entire body is gated behind
`if not getActivatedMods():contains("MarkDynamicTraitsFramework") then return end`, which at first
read looked like it might gate the actual dynamic-trait mechanism behind an undocumented, not-yet-
downloaded 4th dependency. Checked directly against the upstream Steam Workshop page description
(MDTF is explicitly listed as optional, not a required item) and against the code itself: MDTF's
only API surface referenced anywhere in ETW (`MarkDynamicTraitsFramework.registerTrait`,
`.getUndecoratedUIName`) is a **character-creation UI label decorator** (adds a "(D)" suffix to
dynamic trait names so players can spot them at a glance) - it has zero involvement in the actual
earn/lose logic, which lives entirely in `DynamicLogic`/`TraitsLogic` and runs identically with or
without MDTF active. Not bundled. Could be added later purely as a UI nicety; not a functional gap.

#### Deliberately NOT bundled: "Trait Sandbox" companion mod

Workshop item `2914075159` also ships a second mod, "Evolving Traits World (ETW) - Trait Sandbox"
(`require=\StarlitLibrary,\EvolvingTraitsWorld`), an admin UI for enabling/disabling individual ETW
traits and adjusting their point cost. Left out for now - project owner's explicit call - since it
needs a new dependency (`StarlitLibrary`) not currently in this pack. Reference-only snapshot at
`vendor/lascivious-traits/upstream/etw-trait-sandbox/`, not bundled. Revisit if the project owner
asks for it later.

#### Collision review

Every monkey-patch in the codebase found via a full grep for the pack's own capture-before pattern
(`local original_X = Class.method`), not just the files that looked risky at a glance - 25 total
methods across ~14 vanilla classes, each individually checked against every other bundled module:

- `ISInventoryTransferAction:perform` - shared with `aegis-panel`. **Composes correctly in both
  load orders** - ETW always calls through unconditionally; Aegis only skips its call-through for
  its own synthetic admin-move flag (`self.aegisServerMove`), which real player transfers never
  set. If Aegis loads second, ETW's tracking simply doesn't fire for admin-triggered moves - correct
  behavior, not a bug (admin item teleports shouldn't count as player progress anyway).
- `ISEatFoodAction:complete`/`:eat`/`:getDuration` - three different methods than the `:perform`
  I Regret Nothing already wraps, and than the `:serverStart` `lasciviousscripts` (TimeVote)
  wraps. Four different methods across three modules on the same vanilla class, zero overlap.
- `ISReadABook:complete` - shared with `plysken-solar-revolution` (learns PSRMag1 recipes on
  finish). Both sides capture-before and call through unconditionally - no conflict.
- `ISRepairEngine:complete` - **real bug found and fixed, but in a THIRD-PARTY module already in
  this pack, not in ETW's own code**: `LS_BetterEngineRepair`'s patch did a full reassignment with
  no call-through at all (documented as such since its own original integration - "reimplementação
  completa, não wrap" in `docs/COLLISION_REGISTRY.md`). ETW's own wrap is a proper capture-before +
  call-through. If `LS_BetterEngineRepair` loads AFTER `LS_Traits`, its flat reassignment silently
  discards ETW's wrap and the Bodywork Enthusiast/Mechanics trait-progress tracking stops firing -
  no crash, no error, just a quietly dead feature. Fixed by documenting (in
  `BetterEngineRepairPatch.lua` and `docs/COLLISION_REGISTRY.md`) that `LS_BetterEngineRepair` must
  load before `LS_Traits` in `Mods=` - not yet enforceable since `LS_Traits` isn't wired into
  `Mods=` at all yet, but will be applied when that happens. A real call-through fix isn't possible
  here: `BetterEngineRepair`'s formula replaces vanilla's inline `condPerPart` math, so calling
  through to a captured "original" would double-apply the repair.
- `ISWorldObjectContextMenu.getBedQuality` - narrow method, not touched by any of the ~10 other
  modules that patch other methods on the same class (see the rows above this one in
  `docs/COLLISION_REGISTRY.md`).
- `ISAddItemInRecipe:complete` vs `lasciviousscripts` (TimeVote)'s `:serverStart` wrap - different
  methods, no conflict.
- The remaining 14 methods/classes (`ISChopTreeAction`, `ISFitnessAction`, `ISFixAction`,
  `ISFixVehiclePartAction`, `ISLoadBulletsInMagazine`/`ISUnloadBulletsFromMagazine:animEvent`,
  `ISButcherAnimal`/`ISKillAnimal`/`ISKillAnimalInInventory:complete`, `forageSystem.addOrDropItems`,
  `ISPetAnimal:animEvent`, `radioInteractions.checkPlayer`, `RecipeCodeOnEat.consumeNicotine`,
  `RecipeCodeOnCreate.ripClothing`) - genuinely new surface, nothing else bundled today touches
  any of them. All confirmed capture-before + call-through.
- `ETW:*` trait namespace, `ETW_`-prefixed globals/ModData keys checked against the rest of the
  pack - zero collision.

#### MP-authority review

Every server file uses `gameModeSafeguard` to stay out of the wrong process (SP/MP_SERVER-only
code never runs on an MP client, and vice versa) - more consistent discipline than most bundled
mods. One soft spot found, same class of issue as KillCount's (bounded, cosmetic-only impact):
`Commands.checkEngineCondition` (`server/ETW_ClientCommands.lua`) computes a repair-progress delta
as `serverCondition - args.conditionBefore`, where `conditionBefore` is client-reported and not
independently corroborated - a modified client could claim a lower starting condition to inflate
its own Bodywork Enthusiast/Mechanics trait progress. Other MP command handlers checked
(`applyAntiGunAimingMood`, `applyTerminatorAimingMood`) correctly re-derive everything from
server-truth state (the player's actual trait, actual equipped weapon) before applying any effect -
the "communicate intent, not result" pattern this pack's MP-authority checklist asks for. Not fixed
now: same reasoning as KillCount - harmless while every trait affected is flavor/progress-only,
would need hardening (e.g. reading the vehicle's own stored condition server-side instead of
trusting the client's claim) if a future trait ever gated something higher-stakes on this data.

#### Translation

**Complete as of the dedicated translation pass (LS-007, 2026-08-30).** English and Portuguese
both sit at 100% coverage across all three families for the whole `LS_Traits` submod, not just
ETW: `UI.json` 227/227, `Sandbox.json` 540/540, `Moodles.json` 50/50, every one with both native
`.txt` and JSON reference. The 432 missing `Sandbox_ETW_*` keys and 149 missing `UI_ETW_*`/
`UI_trait_*` keys (trait names, descriptions, sandbox option labels/tooltips) were translated by
hand - see `TRANSLATION_PTBR.md` for translation conventions (vanilla trait name glossary, etc.).
While closing the gap, a **second instance of the LS-005 orphaned-filename bug** was found on the
English side: UCWF's own Sandbox options lived in a non-canonically-named `Sandbox_UCWF_EN.txt`/
`Sandbox_UCWF.json` pair since LS-003, meaning `Cap max weight at 50` and `Gather Detailed Debug
Information` had likely never rendered in English either - fixed by merging into the canonical
`Sandbox_EN.txt`/`Sandbox.json`. A handful of stale PT-BR-only keys left over from an earlier
upstream ETW version (renamed options like `Sandbox_ETW_Axpert` -> `Sandbox_ETW_Axeman`, and a few
removed ones) were also cleaned out since they no longer match anything in the current English
source of truth.

#### Local changes from upstream

No line of ETW's own Lua/scripts modified - bundled verbatim (file placement +
registries.lua/sandbox-options.txt merges only). One asset renamed: programmatically compared all
65 registered resource locations' local names against their `trait_<Name>.png` icon file and found
one case mismatch upstream - `ETW:BodyWorkEnthusiast` (capital W) only shipped
`trait_BodyworkEnthusiast.png` (lowercase w). Works on Windows/Mac (case-insensitive filesystems)
but would have broken icon resolution on our case-sensitive Linux server - renamed to
`trait_BodyWorkEnthusiast.png` to match exactly; the other 64 icons already matched. The one
non-asset local change this integration required was in a DIFFERENT, pre-existing module
(`LS_BetterEngineRepair`) - see the collision review above and `LOCAL_CHANGES.md` LS-006.

### Cross-trait harmony: I Regret Nothing <-> Evolving Traits World

A dedicated checkup (2026-08-30, LS-008) once both trait bundles were in and translated, looking
specifically for places where ETW's own systems could interact with I Regret Nothing's design
rather than just avoiding function-level collisions (already covered above). Two real interactions
were found; both were deliberately left alone after reconsidering what "harmonious" actually means
here - see the reversal below. One theoretical third case was investigated and found to already be
a non-issue.

- **ETW's Smoker addiction-decay system can remove `base:smoker` from a character who doesn't
  smoke, including one who got it from I Regret Nothing's `GrantedTraits`.** Confirmed real by
  decompiling `CharacterTraits.class` (`add`/`remove` both delegate to a bare `set()` that just
  mutates a `Map`/`List`, with zero cross-trait awareness - nothing in the engine protects a
  `GrantedTraits` grant from being independently removed later). First reaction was to treat this
  as a bug and patch `RegretNothing_DudeMechanics.lua` to re-grant the trait if ETW ever removed
  it. **Reverted after reconsidering the actual design intent** (project owner's own read, correct
  one): `GrantedTraits` is a one-time kickstart, not a promise of permanence - I Regret Nothing's
  own description says it *forces* Smoker, not that it *locks* Smoker forever. Once granted, the
  character should live by ETW's normal dynamic rules exactly like a character who picked Smoker
  any other way; artificially re-granting it every ten minutes would be I Regret Nothing fighting
  ETW's central "traits are earned and can be lost" philosophy, which is a worse kind of disharmony
  than the one it would "fix". No code change.
- **ETW's Bravery System and Fear of Locations system can grant traits I Regret Nothing declares
  itself incompatible with** (`MutuallyExclusiveTraits = base:agoraphobic;base:claustrophobic;
  base:cowardly;base:pacifist;base:hemophobic;base:brave;base:adrenalinejunkie`), since that field
  is only enforced by the character-creation screen at selection time, not by a later runtime
  grant - `ETW_ByKills.lua`'s kill-count thresholds can grant `base:adrenalinejunkie`/`base:brave`,
  and `ETW_ByLocation.lua` can grant `base:agoraphobic`/`base:claustrophobic`, with zero awareness
  of any other mod's exclusivity list (confirmed via the same decompile that
  `player:getCharacterTraits():add()` performs no exclusivity check at all). Also reverted after
  the same reconsideration, and for `brave`/`adrenalinejunkie` specifically the original static
  exclusivity itself reads more like a character-creation point-budget rule (don't let a player pay
  points for two traits that grant overlapping combat-confidence effects) than a hard mechanical
  contradiction - earning one of them later through actual zombie kills is a different, paid-for
  acquisition path that doesn't have the same "free stacking" concern the static rule exists to
  prevent. No code change.
- **Investigated, found to already be handled correctly by the engine regardless - no fix ever
  needed here:** whether I Regret Nothing (which grants Smoker) could still be picked alongside
  ETW's own `Blissful` trait, which ETW declares mutually exclusive with Smoker
  (`ETW_TraitsExclusivity.lua`: `setMutualExclusive(CharacterTrait.SMOKER,
  ETWTraitsRegistry.BLISSFUL)`). Decompiling `CharacterTraitDefinition.isMutuallyExclusive()` shows
  it already walks a trait's own `GrantedTraits` recursively when checking exclusivity - since I
  Regret Nothing grants Smoker, and Smoker is exclusive with Blissful, the engine already refuses
  to let a character take both at character creation, with no help needed from us. (An explicit
  `ETW:Blissful` entry was briefly added to I Regret Nothing's own `MutuallyExclusiveTraits` in
  `traits.txt` for self-documentation, confirmed harmless/redundant via the same decompile - also
  reverted, since it wasn't fixing anything real either and the file is better left matching
  upstream exactly where nothing is actually broken.)

## Structural conventions for this container

B42 requires two specific files working together for any script-defined trait, and both are
**special files the engine loads in a fixed way** - see `docs/ARCHITECTURE.md` section 9 and the
`responsive-pivoting` precedent (`vendor/alices-weapon-sling/...` is unrelated; the real precedent
is documented in `vendor/responsive-pivoting/INTEGRATION.md`'s now-amended trait section) for why
these two exist and why they cannot be reorganized freely:

- `42/media/registries.lua` - loaded before any `character_trait_definition` script parses.
  **One single file per mod**, so every trait this submod ever adds registers here, in the same
  file, growing over time:
  ```lua
  LasciviousTraits = LasciviousTraits or {}
  LasciviousTraits.CharacterTrait = LasciviousTraits.CharacterTrait or {}

  LasciviousTraits.CharacterTrait.SOME_TRAIT = CharacterTrait.register("lascivioustraits:some_trait")
  ```
- `42/media/scripts/characters/LS_Traits_<TraitName>.txt` - one file per trait (proposed default;
  revisit only if we end up with many small variants of the same trait family, in which case
  grouping into one file with multiple `character_trait_definition` blocks, like the old
  `PivotMod_traits.txt`, is also a valid B42 shape) - the `CharacterTrait = lascivioustraits:...`
  line inside must match the resource location registered above exactly.
- `42/media/ui/Traits/<lowercase_trait_name>.png` - trait icon. Filename **must** be all lowercase
  (B42 resolves trait icons by the lowercase resource-location path on Linux's case-sensitive
  filesystem - see `docs/ARCHITECTURE.md` section 9.3, "REGRA CRÍTICA PARA LINUX").

**Namespace: `lascivioustraits:<trait_name>`, all lowercase, no separators beyond `_`.** Pick the
final `<trait_name>` carefully before shipping - see the save-persistence warning below.

## Save-persistence warning - read before adding or renaming a trait

A trait's resource-location string (`lascivioustraits:whatever`) gets written into a player
character's save data the moment anyone selects it at character creation, or is granted it in game.
**Once a trait has shipped in a released version, its resource-location string must never be
renamed or removed** without following the module-removal procedure in `docs/ARCHITECTURE.md`
section 32 (classify `safe_to_remove` / `save_sensitive` / `requires_migration`, check for existing
saves before touching it). This is exactly the category of mistake the pack undid on
`responsive-pivoting` (its two traits were removed entirely, but only because the pack had not yet
shipped to Workshop and no save had ever existed with them - see
`vendor/responsive-pivoting/LOCAL_CHANGES.md` LS-004). Once `LS_Traits` is live in production, that
shortcut is gone - removing a trait at that point needs a real migration path, not just a deletion.

## Multiplayer / authority

Traits themselves are inert data (`CharacterTrait` + stat/perk modifiers via
`XPBoosts`/`Cost` in the script definition) unless a trait's *behavior* is also implemented in Lua
(e.g. a passive effect that runs every tick, or one granted/revoked by a server-side condition).
Any such behavior must follow the pack's standing MP-authority checklist
(`docs/STATUS.md` "Hard-won technical lessons" - MP-authority review checklist) - apply it per trait
as each one is added, not just once for the container.

## Remaining Risk

- KillCount's MP-authority gap (self-reported kill counts, see above) - fine today, must be
  independently corroborated server-side if a future trait ever gates a real effect on it.
- UCWF/`LS_AegisPanel` carry-weight-pin interaction (see above) - inert until the first
  weight-affecting trait registers a UCWF modifier.
- I Regret Nothing's `RN_safe` hardening reduces every currently-known-risky call site to "one log
  line, then silently inert for the session" on failure, but cannot prevent every possible future
  throw (a game update renaming a `CharacterStat`, for instance, would still disable that one
  operation the first time it is hit) - by design, matching the upstream author's own chosen
  mitigation strategy rather than trying to eliminate all possible failure sources.
- `LS_BetterEngineRepair` must load before `LS_Traits` in `Mods=` once that string is finally
  written (see the ETW collision review above) - not enforceable yet since `LS_Traits` isn't wired
  in at all, but must not be forgotten when it is.
- ETW's `checkEngineCondition` MP-authority soft spot (see above) - same bounded/cosmetic-only
  category as KillCount's, not fixed for the same reasons.
