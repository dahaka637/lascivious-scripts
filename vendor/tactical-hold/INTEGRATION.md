# Integration Notes — Tactical Hold

- `module_key`: `tactical-hold`
- `bundled_mod_id`: `LS_TacticalHold`
- Workshop item `3712348921`, upstream folder name `TacHold Complete Fixed`. Original `id=TacHold
  Complete Fixed` — the Mod ID itself contained literal spaces, non-standard but present upstream;
  renamed regardless as part of the normal Category A rebrand.
- Ships **two layers**: a no-version-folder root (legacy layout) and a self-contained `42/` folder,
  plus a completely empty `common/` (zero files, not even a placeholder). **Only `42/` was
  bundled** — the root layer has two real, upstream-side problems the `42/` layer doesn't:
  - Its two client Lua files are misnamed `TacHold_Options.lua.lua` /
    `TacPHold_Options.lua.lua` (double `.lua` extension — almost certainly an accidental
    double-save/re-export by the author; `42/`'s copies are correctly named `TacHold_Options.lua` /
    `TacPHold_Options.lua`).
  - Its `mod.info` declares `require=modoptions` — a hard dependency on a separate, non-bundled
    third-party "ModOptions" utility mod. `42/`'s `mod.info` has **no** `require=` line at all, and
    confirmed by reading both Options files: `42/`'s codebase uses the native B42
    `PZAPI.ModOptions:create(...)` API exclusively, with zero reference to the external `ModOptions`
    global anywhere — the root layer is the older, pre-native-API codebase this fork's `42/`
    directory correctly superseded, and the missing `require=` in `42/mod.info` is intentional, not
    an oversight.

## What it does

Adds several "ready" hand-hold poses (high-ready, low-ready, gun-resting, plus vanilla) for both
two-handed long guns and one-handed pistols, automatically applied whenever the player is carrying
a ranged weapon but not currently aiming or sneaking, cycled between via a keybind (default `U`,
shared between the long-gun and pistol variants). Purely a cosmetic animation-pose feature — no new
items, no gameplay mechanic beyond the visual stance.

## Why this is safe in multiplayer with no server Lua at all

Both `TacHold.lua` and `TacPHold.lua` call `if isServer() then return end` at the very top of their
init function — **the dedicated server never runs any of this mod's logic**, confirmed by reading
both files in full. The mechanism: each client computes its own local player's pose (from
already-locally-known data — the local player's own Aiming skill level and current weapon/aiming/
sneaking state, nothing trusted from elsewhere) and sets it as the vanilla `RightHandMask`/
`LeftHandMask` character variables — purely visual AnimSet-mask conditions, with zero effect on
weapon accuracy, hit detection, or any server-validated stat. The chosen pose is then written to
`player:getModData().TacHoldPose` and broadcast via vanilla's own standard `player:transmitModData()`
call — the same safe, already-vanilla-supported mechanism many mods use to share a player's own
cosmetic state with other clients. Every other client's own copy of that remote player reads the
transmitted `modData.TacHoldPose` value back out and applies it locally purely for display
(`tacHoldMP`, explicitly skipped for `mPlayer:isLocalPlayer()`). Worst case a malicious client could
do is broadcast a bogus pose value for *their own* character, which only ever changes what that one
character visually looks like holding — same risk class as any other purely-cosmetic vanity mod
already in this pack (e.g. `responsive-pivoting`).

## Fase 1 inventory findings

- New `media/AnimSets/player/masking{left,right}/*.xml` files add fresh, mod-specific mask nodes
  (`m_StringValue` conditions like `TacGunPoseHighReady`, `TacPistolRightHigh`, etc.) — none of
  these mask string values or file paths overlap with anything vanilla or any other bundled module
  (grepped `RightHandMask`/`LeftHandMask`/`maskingleft`/`maskingright` across the whole pack: zero
  hits elsewhere).
- Missing native `Sandbox_EN.txt` (5 keys: page title + 2 options × label/tooltip) — same recurring
  pattern as most of this pack, fixed (see Adaptation). The `PZAPI.ModOptions` tickbox/keybind
  labels ("Tactical hold", "HighReady", "Low Ready", "GunResting", "Vanilla", "Cycle animation Key")
  are hardcoded English literals with no `getText()` plumbing at all — left untranslated for the
  same reason as `osrs-experience-bar`/`mini-health-panel` (see those modules' `INTEGRATION.md`).
- `incompatible=\TacHold AR,\TacHold,\TacHold Pistol,\TacHold Pistol AR,\TacHold Complete` in
  `42/mod.info` names five sibling Mod IDs — evidently other standalone weapon-type-specific
  variants (AR-only, Pistol-only, Pistol+AR combo, and a non-"Fixed" "Complete" bundle) of the same
  upstream mod family. None of those Mod IDs exist in this bundle, so the declaration has no effect
  either way — dropped (same reasoning as `drag-bodies-faster`'s and `clean-hotbar`'s dropped
  `incompatible=` lines).
- No check of the mod's own Mod ID anywhere (Category A per architecture doc section 20).

## Adaptation applied (Fase 5)

- `id=TacHold Complete Fixed` -> `id=LS_TacticalHold` (Category A rename, also normalizes the
  space-containing original ID); `name=`/`description=` rewritten to the pack's style, PT-BR. Added
  `versionMin=42.20` (`42/mod.info` declared none at all). Dropped `incompatible=` (see above).
  `poster=`/`icon=` preserved.
- Added native `Sandbox_EN.txt` (5 keys, transcribed from the already-correct EN JSON).
- All 4 Lua files, all AnimSets XML, and all animation `.fbx` files copied byte-identical from the
  `42/` upstream codebase — confirmed via `diff -rq` and `luac5.1 -p`. **Zero code changes.**
