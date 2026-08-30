# Integration Notes — Immersive Suicide

- `module_key`: `immersive-suicide`
- `bundled_mod_id`: `LS_ImmersiveSuicide`
- Workshop item `3426448380`, folder name `ImmersiveSuicide` (`id=stanks_suicide` in every variant).
  Ships **two genuinely different code versions**, not a cosmetic split: the top-level/root files
  (`versionMin=41.66`) are the old Build 41 codebase, and `42.0/` (`versionMin=42.15`) is a separate,
  Build-42-specific rewrite — confirmed by diffing every same-named Lua file between the two; 4 of
  6 differ (only `ImmersiveSuicide.lua` and `ISYesNoDialog.lua` are identical). **Only `42.0/`'s
  code was bundled** — it's the one that matches this pack's target build, and its own code contains
  several `BUILD_NOTE: Build 41/42 Difference` comments documenting exactly which vanilla API calls
  changed between builds (worth reading if this module ever needs updating).

## What it does

Lets a player equip a loaded, chambered firearm and use a context-menu/firearm-radial-menu option to
end their character's life outright (`head:SetHealth(0)`), with a played suicide animation and a
confirmation dialog (togglable via sandbox option). A second sandbox option controls whether the
character forcibly becomes/avoids becoming a zombie afterward (`ForceZombification`) — since the
head is destroyed either way, vanilla's normal infection outcome doesn't naturally apply, so the mod
explicitly decides it based on the sandbox setting.

## Multiplayer authority — safe by construction

`ImmersiveSuicideServer.lua`'s `onKillPlayerCommand(module, command, player, args)` only ever acts on
`player` — the framework-authenticated sender of the command, never anything from the client-supplied
`args` table. A client can only ever request suicide/effect-sync for **itself**; there is no
player-ID field in the request payload to spoof (unlike `equip-while-running`'s original bug). Since
the only possible outcome of abusing this command is killing your own character, there's no griefing
vector against other players or server state to guard against — no LOCAL_CHANGES patch needed.

## Known real translation bug found and fixed

Same root cause as `push-vehicle`, but affecting **every language including English**: the `42.0/`
code calls native `getText()` (see `ContextMenu.lua`, `FirearmRadialMenuPatch.lua`,
`ISYesNoDialog.lua`), but `42.0/Translate/` only ships `.json` files (24 languages), which
`getText()` never reads. The root/B41 folder, however, already has the *correct* native `.txt`
Lua-table files for every one of those languages — the author's translation pipeline for the B42
rewrite evidently switched to JSON and the native files were never carried over. **Ported the B41
root's English native files (`ContextMenu_EN.txt`/`Sandbox_EN.txt`/`UI_EN.txt`) into the bundled
`42/` folder**, after confirming key-for-key that `42.0`'s code uses exactly the same 8 translation
keys as the B41 build (`sandbox-options.txt` is byte-identical between root and `42.0` too, just a
whitespace difference). This is the second bundled mod (after `push-vehicle`) where the actual
context-menu/tooltip text had no functional backing at all before this fix.

### A second, independent finding: upstream's own PT-BR native file is corrupted

The root/B41 folder's `Translate/PTBR/*.txt` files (which are otherwise the exact source we'd want to
port for PT-BR too) have **irrecoverable byte-level corruption**: every accented character was
replaced with U+FFFD (the Unicode replacement character) at some point in upstream's own export
pipeline — e.g. `"For�ar Zombifica��o?"` instead of `"Forçar Zombificação?"`. This is not a PZ
rendering issue, it's literally baked into the `.txt` file's bytes (confirmed via a raw hexdump:
`\xef\xbf\xbd` = UTF-8 for U+FFFD). Fortunately, `42.0/Translate/PTBR/*.json` — a completely separate
export — has **correctly encoded** PT-BR text with no corruption (verified: proper UTF-8 bytes for
ç/ã/á/ã/õ etc., matching a clean manual translation). So the correct PT-BR strings are recoverable
from the JSON, just not from the corrupted native `.txt`.

**This PT-BR text was still not ported into a native `Sandbox_PTBR.txt`/`UI_PTBR.txt`/
`ContextMenu_PTBR.txt`**, despite having a clean source this time — the *separate*, independently
confirmed [[feedback-ptbr-accents-in-lua]] bug (accented text in a native Lua-table-loaded string
breaks to "?" regardless of source encoding correctness) still applies, and is the reason this whole
pack has never shipped a native PTBR sandbox/UI file anywhere. See `TRANSLATION_PTBR.md`.

## Fase 1 inventory findings

- Soft-detects the "Efficiency Skill" mod via `Perks.Efficiency ~= nil` (no `require=`, gracefully
  no-ops if absent) to scale the suicide animation's duration.
- New `AnimSets/player/actions/Suicide_*.xml` nodes — novel names/paths, no vanilla-path collision.
  No accompanying `.x` animation clip file ships with the mod at all (the referenced
  `Bob_Suicide_Handgun`/etc. animation clips aren't in this mod's own assets) — worth confirming in
  actual Fase 9 client testing that the suicide animation plays correctly rather than falling back
  to nothing; static file review alone can't confirm this.
- Monkey-patches `ISFirearmRadialMenu:fillMenu` — wrapped with call-through and an idempotency guard
  (`ImmersiveSuicide.RuntimePatchStatus.FirearmRadialMenu`), same safe pattern as
  `simple-belt-flashlight`/`push-vehicle`. Registered in
  [`../../docs/COLLISION_REGISTRY.md`](../../docs/COLLISION_REGISTRY.md) as occupied surface.
- Defines a global `ISYesNoDialog` class (a fairly generic, commonly-reused PZ-modding utility class
  name) via a plain unguarded assignment — logged in the collision registry as an occupied global
  name in case a future bundled mod defines its own same-named class.
- No item/recipe/vehicle/trait/perk IDs introduced. No Java, no maps/tiledefs. No save/modData usage
  beyond vanilla `Kill()`/body-damage calls.
- No check of the mod's own Mod ID anywhere (Category A per architecture doc section 20).

## Adaptation applied (Fase 5)

- `id=stanks_suicide` -> `id=LS_ImmersiveSuicide` (Category A rename).
- `name=`/`description=` rewritten to the pack's style, PT-BR (mod.info description is Java-parsed,
  unaffected by the Kahlua accent bug).
- `versionMin=42.15` preserved verbatim from the `42.0/` upstream `mod.info` (not bumped to 42.20 —
  delta mínimo, no functional reason to raise an already-present, already-appropriate floor).
- `icon=poster_icon.png` preserved (upstream's own icon field/asset).
- **Added `Sandbox_EN.txt`/`UI_EN.txt`/`ContextMenu_EN.txt`** ported from the B41 root folder,
  verified key-for-key against `42.0`'s actual `getText()` calls — the real functional fix.
- No PT-BR native file added — see "A second, independent finding" above and
  `TRANSLATION_PTBR.md`. All 24 languages' original JSON files were kept as-is (harmless, unused by
  any native panel, preserved for fidelity/possible future use).
- Everything else — all Lua, all AnimSet XML, `sandbox-options.txt`, the radial-menu icon PNG, every
  language's JSON — copied byte-identical from the `42.0/` upstream folder, confirmed via `diff`.
