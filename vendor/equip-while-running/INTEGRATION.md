# Integration Notes — Equip Items While Running

- `module_key`: `equip-while-running`
- `bundled_mod_id`: `LS_EquipWhileRunning`
- Workshop item `3492077449` is a single mod (`id=equipwhilerunning` in both variants) that ships two
  build-version folders instead of the `common/`+`42/` split this project uses: `42.19` (labelled
  `[B42.19 SP ONLY]` by the author, `versionMax=42.19`, single-player only, uses an older
  `EqiupWhileRunning_old.lua`) and `42.20.2` (`versionMin=42.20`, proper client/server split with a
  server-relayed network sync). **Only the `42.20.2` variant was integrated** — it matches this
  pack's `42.20.x` target exactly and is the only one with server-side code at all. The `42.19`
  variant is preserved pristine in `vendor/equip-while-running/upstream/42.19/` for reference but
  nothing from it was copied into `Contents/`.

## What it does

Lets the player equip/unequip weapons, wear/remove clothing, transfer items between containers, and
attach/detach hotbar items while running, instead of vanilla forcing a stop. Implemented as monkey
patches (see Risk below) of six vanilla `ISBaseTimedAction` subclasses plus
`luautils.haveToBeTransfered`, driving four new custom AnimSet nodes
(`Movement_Run{Attach,Detach,Equip,Unequip}Item`, condition-gated on new player anim variables this
mod owns: `Run{Attach,Detach,Equip,Unequip}_Enable`/`_AnimSpeed`) blended over a new running
animation clip (`media/anims_X/Bob/equipwhilerunningbob.x`, referenced as `Bob_DoingSthWhileRunning_s`).
Those 4 AnimSet node files are **new node names at paths that don't collide with any vanilla file**
(unlike `zombie-decay`'s AnimSets, which literally override vanilla paths) — the PZ animation engine
picks them up by condition-matching, not path override. Since remote players' Character objects don't
run this mod's client-side logic for you, the local client that owns a given player broadcasts its
own anim-variable changes over a small network relay (`RunningActionsMod` module,
`SyncAnimVar` command) so every other connected client can mirror that player's animation state.

Configuration is exposed via 5 toggles in the native **Options > Mods** menu (`PZAPI.ModOptions`,
category key `"RunningActionsMod"` — shared with the network module name, both preserved verbatim
from upstream), not `sandbox-options.txt` — this mod has no Sandbox Options page at all.

## Fase 1 inventory findings

- No `sandbox-options.txt`. Uses `PZAPI.ModOptions` instead (native "Mod Options" menu, a different
  PZ subsystem).
- No `Translate/` folder — the 5 `PZAPI.ModOptions` tickbox labels/tooltips are hardcoded English
  Lua string literals (see PT-BR note below).
- No dependency on any other mod — pure vanilla API (`PZAPI`, `ISBaseTimedAction` subclasses,
  `luautils`, `Events`). No `require`, no `getActivatedMods()`.
- No item/recipe/vehicle/trait/perk IDs introduced.
- No Java/JAR, no maps/tiledefs/packs.
- `player:getModData().bIsUnequippingClothing` — a transient per-character modData flag, set/cleared
  within a single unequip action's start/perform/stop, never persisted meaningfully across a save.
  Not save-sensitive.
- No check of the mod's own Mod ID anywhere (Category A per architecture doc section 20 — safe to
  rebrand the bundled Mod ID with no functional risk).
- **Monkey-patches six vanilla classes wholesale**: `ISEquipWeaponAction`, `ISUnequipAction`,
  `ISWearClothing`, `ISInventoryTransferAction`, `ISAttachItemHotbar`, `ISDetachItemHotbar` (their
  `:new`/`:start`/`:update`/`:perform`/`:stop` methods — several `:new()` overrides fully reimplement
  vanilla logic instead of calling through to it; upstream's own comments literally say
  `-- TOFIX: Find out why not reusing vanilla code causes not equipping bug`, i.e. the author
  couldn't get the safer wrap-and-call-through approach working either) plus `luautils.haveToBeTransfered`.
  Registered in [`../../docs/COLLISION_REGISTRY.md`](../../docs/COLLISION_REGISTRY.md) as an
  occupied-surface entry — **any future bundled mod that also patches these same classes will
  silently clobber one or the other, last-load-wins.** Check that registry before adding another mod
  that touches player equip/unequip/transfer actions.
- **Server relay had zero validation** (see LOCAL_CHANGES LS-001) — any client could spoof another
  player's `onlineID` and set arbitrary animation variables on their Character. Patched.

## Adaptation applied (Fase 5)

- `id=equipwhilerunning` -> `id=LS_EquipWhileRunning` (Category A rename).
- `name=`/`description=` rewritten to the pack's style, PT-BR (mod.info descriptions are parsed by
  PZ's own Java `mod.info` reader, not Kahlua, so this doesn't hit the accent-rendering bug — see
  [[feedback-ptbr-accents-in-lua]] in memory / the equivalent note already applied for
  `durable-tools-weapons`).
- `modversion` added locally (upstream didn't declare one); currently `1.0.1` after LS-004.
- Dropped the `42.19` SP-only legacy variant and the empty upstream `common/` — this project's own
  `common/media/` placeholder is used instead, matching every other submod.
- **LS-001 (server hardening):** `RunningActionsServer.lua` now rejects a relay unless
  `args.id == player:getOnlineID()` — see LOCAL_CHANGES.md.
- **LS-004 (run-control fix):** the client update loop now honors the three speed-penalty settings
  instead of disabling running during every managed action. It takes ownership of `AllowRun` only
  while applying an enabled penalty, preserves the previous value per player, and restores it when
  the penalty ends; this also removes the upstream's unconditional per-frame
  `player:setAllowRun(true)` interference with vanilla/other mods. See LOCAL_CHANGES.md.
- **PT-BR left incomplete on purpose:** the 5 `PZAPI.ModOptions` tickbox labels/tooltips
  (`options:addTickBox(...)` calls in `EqiupWhileRunning.lua`) are raw Lua string literals — the same
  failure class already documented in [[feedback-ptbr-accents-in-lua]] and
  [[feedback-sandbox-options-native-txt-required]] (accented PT-BR text hits the "?" rendering bug
  when it's a literal Kahlua string rather than JSON-decoded via `getText()`). Left in English,
  untouched from upstream, exactly like this pack's existing accepted limitation for the native
  Sandbox Options screen. Do not hardcode accented PT-BR text into those 5 strings.
- Beyond the localized LS-004 block, the client gameplay logic remains unchanged; the 4 AnimSet XML
  nodes and the `.x` animation clip are still byte-identical to upstream.

## Known risks to watch

1. **Monkey-patch fragility**: full `:new()` reimplementation instead of call-through means any
   future vanilla update to these 6 action classes' constructors can silently desync from this mod's
   copy. Re-diff against a fresh vanilla install if equip/unequip/wear/transfer/hotbar actions start
   behaving oddly after a PZ update.
2. **Occupied vanilla-class surface**: see Collision Registry — don't bundle another mod that patches
   the same 6 classes without resolving load order / merging logic consciously.
3. **Intentional sprint limit**: equip/unequip/clothing/transfer actions retain the upstream guards
   that cancel them while sprinting. LS-004 fixes normal running/jogging only; extending the custom
   animation set to sprinting is a separate feature, not part of this bug fix.
