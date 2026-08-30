# Integration Notes — Better Push

- `module_key`: `better-push`
- `bundled_mod_id`: `LS_BetterPush` — the exact name [`../../docs/ARCHITECTURE.md`](../../docs/ARCHITECTURE.md)
  itself uses as its running example throughout (section 1.1's example tree, section 3's canonical
  table, section 25's branch-naming example). First of those example names to actually ship with
  real content instead of being a placeholder.
- Workshop item `3715137752`, folder name `BetterPush`. Ships redundant top-level, `common/` (no
  `common/media/` at all, just a duplicate `mod.info`/`icon.png`/`poster.png`) and `42/` copies of
  the same `mod.info` — not a real build split like `immersive-suicide`/`responsive-pivoting`
  (all three declare the same `versionMin=42.0`). Only `42/`'s content (the only place with any Lua
  at all) was bundled; the top-level/common duplicates were dropped, matching the
  `durable-tools-weapons`/`faster-hood-opening` precedent for redundant legacy packaging.

## What it does

Shoving a zombie (spacebar, bare-handed only — explicitly excludes weapon swings by checking the hit
weapon's type) has a Strength-scaled chance to trigger a "domino" effect: a chain of nearby zombies
behind the shoved one, found by walking outward from its position within a configurable
distance/lateral-tolerance window, gets knocked down in a staggered sequence (~0.33s apart
client-side, ~0.66s apart server-side). Chance and chain length both linearly interpolate between a
`MinStrengthLevel`/`MaxStrengthLevel` band using 4 sandbox values.

## Multiplayer authority and desync — full rewrite (LS-004), read `LOCAL_CHANGES.md` for the details

This module went through two rounds of MP fixes:

**Round 1 (`LS-001`, 2026-08-25, initial integration)**: `onClientCommand` originally trusted the
client completely — it looped over `args.targetIDs` (an arbitrary-length list of zombie online IDs
chosen entirely client-side) and queued every one of them for knockdown, with no strength re-check,
no count cap, and no distance/range check at all. A modified client could mass-clear zombie threat on
demand regardless of Strength or position — a difficulty-bypass exploit, not just cosmetic. Patched
by recomputing the sender's allowed chain length and a reach radius server-side.

**Round 2 (`LS-004`, 2026-08-25, same day, follow-up)**: the user reported that community feedback
says upstream Better Push is outdated/broken in multiplayer, and asked for a full manual MP-focused
rewrite. Investigating a third-party community patch mod (Workshop `3779917103`, studied as reference
only — never bundled) revealed the actual root cause: `Events.OnWeaponHitCharacter` fires locally on
**every connected client** whenever **any** player shoves a zombie, not just the attacker's own
client. Neither upstream nor `LS-001` guarded against this, so with N players online, a single shove
caused **N clients** to each independently compute a domino chain and send their own `Trigger`
request for the *same* shove — multiplying the effect and producing exactly the desync symptoms
reported. `LS-004` is a complete rewrite of all three Lua files: an attacker-only guard on the client
(the actual fix), moving domino-chain computation entirely server-side (the client now only reports
which zombie it shoved, never a target list — a stronger security posture than `LS-001`'s
cap-and-validate approach), a direction-aware (not just nearest-neighbor) chain search, an explicit
server-to-all-clients sync broadcast instead of relying on implicit zombie-state sync, ID-with-
position-fallback zombie resolution, and two-sided rate limiting. Full technical detail, and exactly
what came from studying the reference mod versus what's this pack's own design, is in
`LOCAL_CHANGES.md`'s `LS-004` entry — that file is the authoritative record for this module's
multiplayer design going forward.

## Fase 1 inventory findings

- Missing native `Sandbox_EN.txt` — same recurring pattern as several prior modules. Unusually, the
  upstream JSON itself uses a nested `{"EN": {...}}` structure (every other bundled mod's JSON has
  been a flat `{key: value}` object) — harmless either way since nothing reads the JSON natively, but
  worth knowing this mod's export format differs if it's ever re-diffed against a future upstream
  version.
- No dependency on any other mod, no items/recipes/vehicles/traits, no Java, no maps/tiledefs/
  AnimSets, no monkey-patching (only plain `Events.X.Add(...)` listeners, which don't collide with
  other mods' listeners on the same event the way a monkey-patched method assignment would).
- Upstream's `BetterPush.knockDownZombie()` unconditionally `print()`d a line on every successful
  knockdown. `LS-004` dropped the debug prints along with the rest of the rewrite (they were mostly
  there to trace the original's own trigger logic, which no longer exists in the same form).
- Upstream tried 5 different zombie-knockdown methods speculatively
  (`setHitReaction`/`knockDown`/`setKnockedDown`/`setStaggerBack`/`setFallOnFront`, "for
  compatibility"). `LS-004` narrowed this to the 2 that actually represent a domino knockdown
  (`setHitReaction`/`setKnockedDown`) after the reference community patch's author apparently reached
  the same conclusion independently — see `LOCAL_CHANGES.md` LS-004 point 7.
- No check of the mod's own Mod ID anywhere (Category A per architecture doc section 20).

## Adaptation applied (Fase 5)

- `id=BetterPush` -> `id=LS_BetterPush` (Category A rename).
- `name=`/`description=` rewritten to the pack's style, PT-BR; `versionMin=42.0` and
  `modversion=1.4` preserved verbatim.
- **LS-004**: complete rewrite of `BetterPush_Shared.lua`/`BetterPush_Client.lua`/
  `BetterPush_Server.lua` (see above and `LOCAL_CHANGES.md`) — supersedes LS-001, no longer
  byte-identical to upstream in any of the three Lua files.
- **Added `42/media/lua/shared/Translate/EN/Sandbox_EN.txt`**, text transcribed from upstream's
  nested `Sandbox_EN.json` (unwrapping the `"EN"` key). Untouched by LS-004 — no sandbox option
  names or defaults changed.
- No PT-BR native file added — same accepted limitation as the rest of this pack (accented text
  breaks native `.txt` Lua-table translation loading, see [[feedback-ptbr-accents-in-lua]]).
- `sandbox-options.txt`, `icon.png`, `poster.png` copied byte-identical from upstream `42/` —
  confirmed via direct `diff`. `mod.info` and all three Lua files differ from upstream.
