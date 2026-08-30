# Integration Notes — Responsive Pivoting

- `module_key`: `responsive-pivoting`
- `bundled_mod_id`: `LS_ResponsivePivoting`
- Workshop item `2946812728`, folder name `PivotMod` (`id=PivotMod` in both variants). Same shape as
  `immersive-suicide`: root/top-level is a genuinely separate Build-41 codebase (`modversion=3.1`,
  no explicit `versionMin` but the code comments say "B41 build"), `42/` is a separate Build-42
  rewrite (`modversion=3.0`, `versionMin=42.0.0`). **Only `42/`'s code was bundled.** Confirmed by
  diff that the two `DoublePivotMod.lua` files differ throughout (trait API, stat API, and a
  `MOVEMENT_TURN_PRESETS` array that B41 needs to counteract a moveDelta-attenuation quirk that B42
  doesn't have).

## What it does

Speeds up how fast a character visually turns to face the aim direction (while aiming) and while
walking (not jogging/sprinting — see "Known engine limitation" below), via
`player:setTurnDelta(...)`. One switch picks fixed-speed-by-preset vs. Nimble-skill-scaled ("Nimble
mode"), applied globally to everyone. An optional "dynamic modifiers" layer further scales turn speed
live by encumbrance, leg/foot injury, fatigue, drunkenness, panic and sneaking — every engine read is
`pcall`-guarded with a neutral fallback so a missing API can never error or spam logs.

*(Upstream originally shipped this as a 2x2 — fixed/Nimble × global/restricted-to-two-new-traits.
The trait axis was removed entirely in this bundle, see the amendment below.)*

## Multiplayer — no network code at all, inherently safe

This module has **zero `sendClientCommand`/`sendServerCommand`/network-event code anywhere**.
Turning is purely a local, client-visual effect (`setTurnDelta`), and every touch point is gated by
`isLocalPlayerObj(p)` (`p:isLocalPlayer()`), iterating only local split-screen player slots
(`getSpecificPlayer(0..3)`) — never remote players. On a dedicated server, no player is ever local,
so the whole runtime is a no-op there by construction (confirmed by the code's own comment: *"this is
what keeps it multiplayer-safe"*). Nothing to patch — there's no server-authority surface to review
because nothing here ever needs one.

## Amendment — traits removed entirely (see `LOCAL_CHANGES.md` LS-004)

Everything in the section below ("Persisted trait IDs") describes the **original upstream state**
only. Both traits, `media/registries.lua` and `PivotMod_traits.txt` were deleted from the bundled
copy at the user's request before the pack's Workshop upload — the mod no longer defines, grants, or
checks any trait. Kept here as historical record of why those files existed upstream and how they
worked; do not follow the "never rename" guidance below as if the traits still exist in this bundle.

## Persisted trait IDs (historical — upstream only, see amendment above)

Adds two **script-defined B42 traits** (`media/scripts/characters/PivotMod_traits.txt`), resolved via
resource locations `pivotmod:onyourtoes` / `pivotmod:podshofe`, registered up-front in
`media/registries.lua` (a B42-specific top-level file, loaded before trait-definition scripts parse —
**not** something to move elsewhere, its exact location matters the same way `mod.info` or
`sandbox-options.txt`'s do; see architecture doc section 10, this is a newly-seen "special file"
class worth remembering for future integrations). These trait IDs are **save-persisted** the moment
any character has one (chosen at character creation) — same category of concern as item/recipe IDs
in architecture doc section 6. **Never rename `pivotmod:onyourtoes`/`pivotmod:podshofe`.** They are
hardcoded in the script and in `media/registries.lua`, entirely independent of the Mod ID string, so
renaming the bundled Mod ID (`PivotMod` -> `LS_ResponsivePivoting`) has zero effect on them — this is
purely a Category A rename as far as the Mod ID goes.

## A genuinely interesting engine-limitation the upstream author already solved

Both variants' code has an extensive comment explaining why jog/sprint turning is never touched:
`getTurnDelta()` reads the protected `turnDeltaRunning`/`turnDeltaSprinting` fields while
running/sprinting, and PZ's Kahlua exposer only adds a `__newindex` metamethod to **static class
tables**, never to Java **instances** — so `instance.field = value` throws before any field-setting
code runs. An earlier version of this mod tried exactly that and it silently failed while spamming
Kahlua RuntimeException logs. The current code doesn't attempt it at all; jog/sprint turning always
stays vanilla. Worth remembering as a real, previously-verified Kahlua constraint if any future
bundled mod ever needs to set a protected/instance field from Lua — it can't be done.

## Case-sensitive icon filenames (historical — the file this describes was deleted in LS-004)

`42/media/ui/Traits/trait_onyourtoes.png` is all-lowercase, while the B41 root variant's equivalent
file is `trait_OnYourToes.png` (mixed case). This isn't an upstream inconsistency to "clean up" — B42
trait icons resolve by the lowercase resource-location path (`pivotmod:onyourtoes`), while B41 traits
resolved by the exact trait name string. Each variant's icon filename already matches its own build's
actual lookup convention. **Left exactly as shipped in `42/`** (lowercase) — renaming it to match B41's
casing would break the B42 icon lookup on this Linux dedicated server (architecture doc section 9.3).

## Fase 1 inventory findings

- No dependency on any other mod, no Java, no maps/tiledefs/AnimSets, no monkey-patching of any
  vanilla class/function.
- No check of the mod's own Mod ID anywhere (Category A per architecture doc section 20 for the Mod
  ID itself — see above for why the trait IDs are a separate, unrelated concern).
- `42/Translate/EN/{Sandbox,UI,IG_UI}.json` exist but nothing reads them (`getText()` needs native
  `.txt`) — same recurring bug as several prior modules, **except this time the B41 root's native
  `.txt` files were slightly less complete than the B42 JSON** (missing the 10
  `Sandbox_PivotMod_{PivotSpeed,MovementTurnSpeed}_option1..5` enum-label keys, and an updated
  `PivotSpeed` tooltip sentence) — see Adaptation below for how this was handled.

## Adaptation applied (Fase 5)

- `id=PivotMod` -> `id=LS_ResponsivePivoting` (Category A rename; does not affect the `pivotmod:*`
  trait resource locations, see above).
- `name=`/`description=` rewritten to the pack's style, PT-BR; `versionMin=42.0.0` and
  `modversion=3.0` preserved verbatim from the `42/` upstream `mod.info`.
- **Added `42/media/lua/shared/Translate/EN/{Sandbox_EN.txt,UI_EN.txt,IGUI_EN.txt}`.** `UI_EN.txt`
  and `IGUI_EN.txt` are ported verbatim from the B41 root (confirmed identical text to `42/`'s JSON).
  `Sandbox_EN.txt` was **built from the `42/` JSON** rather than ported from root, since the JSON had
  10 additional enum-option-label keys root's native file lacked, plus a slightly expanded tooltip
  sentence — root was the incomplete one this time, not the source of truth. Filename convention
  (`IGUI_EN.txt`, not `IG_UI_EN.txt`) matches exactly what the author's own proven-working B41 build
  already used.
- One text fix while transcribing: the `42/` JSON's `DynPanic`/`DynSneak` tooltips use `%%` (escaped
  percent, likely a JSON-export artifact); root's native `.txt` for the same two strings used a
  single `%`. Used single `%` (matching root's already-shipped, presumably-tested native format) —
  Lua string literals don't need percent-escaping the way a `string.format` template would.
- No PT-BR native file added — same accepted limitation as the rest of this pack (accented text
  breaks native `.txt` Lua-table translation loading, see [[feedback-ptbr-accents-in-lua]]).
- Everything else — the Lua, `registries.lua`, the trait script, `sandbox-options.txt`, both trait
  icon PNGs — copied byte-identical from the `42/` upstream folder, confirmed via direct `diff`.
