# Lascivious Traits

## Identity

- **Module key:** `lascivious-traits`
- **Project Zomboid Mod ID:** `LS_Traits`
- **Distribution:** bundled inside Workshop item `3788475731`
- **Version:** `0.7.0` (three framework dependencies + I Regret Nothing + Evolving Traits World's
  65 traits bundled; PT-BR translation 100% complete)
- **Runtime root:** `Contents/mods/LS_Traits/42/`
- **Vendor tracking:** `vendor/lascivious-traits/` (see `INTEGRATION.md` there for the structural
  conventions every trait must follow, and the save-persistence warning)

## What this is

A container submod for character traits authored for this pack specifically - not a straight port
of any single third-party trait mod. The intent is to look at the mechanics/ideas across several
existing trait mods and implement our own version, so the result is closer to `time-vote.md`/
`zombie-decay.md` (own-code, occasionally informed by prior art) than to a normal Fase 1-10
third-party integration, even though individual traits may still trace back to specific inspirations
worth recording per trait in `vendor/lascivious-traits/INTEGRATION.md`.

## Status: three framework dependencies in, two trait bundles shipped

- **Moodle Framework** (Workshop 3396446795) is bundled directly inside this submod as of
  2026-08-30 - a client-only UI dependency future traits can build on to show their status in the
  moodle bar (`require "MF_ISMoodle"`, `MF.createMoodle`/`MF.getMoodle`). Full detail, including a
  noted-but-low-severity client-local memory-growth quirk in the upstream code, in
  `vendor/lascivious-traits/INTEGRATION.md`.
- **KillCount** (Workshop 2553809727) is bundled directly inside this submod as of 2026-08-30 -
  tracks per-character kill counts by cause (weapon/fire/car/explosion) beyond vanilla's own
  `getZombieKills()`, in `player:getModData().AKCModData`. **Read the MP-authority note in
  `vendor/lascivious-traits/INTEGRATION.md` before any trait uses this data for anything beyond
  flavor** - the server accepts the client's self-reported kill counts without validating the
  values (only the sender's own identity is checked), which is harmless for KillCount's own
  cosmetic display but must not be trusted as a security boundary for a trait that would grant a
  real effect based on kill count.
- **UCWF (Unified Carry Weight Framework)** (Workshop 3682045254) is bundled directly inside this
  submod as of 2026-08-30 - a modifier-pipeline library future traits can call
  (`UnifiedCarryWeightFramework.registerBaseModifier`/`registerMaxModifier`) to affect carry weight
  without fighting other mods that do the same. Inherently server/SP-authoritative by design (the
  logic never runs on an MP client at all). Zero collision with anything bundled today, but has a
  known future interaction with `LS_AegisPanel`'s carry-weight admin pin once the first
  weight-affecting trait actually registers a modifier - see
  `vendor/lascivious-traits/INTEGRATION.md` and `docs/COLLISION_REGISTRY.md`.
- **I Regret Nothing** (Workshop 3676431328) is bundled as of 2026-08-30 - the container's first
  real trait, a Postal 2 Dude homage (immune to panic, pushes combat stats hard while "frenzied",
  buffed by cigarettes/pills, forces the Smoker and Desensitized traits, `+12` cost). Kept its own
  upstream namespace (`RegretNothing:RegretNothing`) rather than being renamed into
  `lascivioustraits:*`, since it is a bundled port of a specific mod, not an original design - see
  `vendor/lascivious-traits/INTEGRATION.md` "Included Traits" for the full writeup, including the
  reported-error-stream investigation (the upstream author had already partially fixed it; this
  pack extended the same fix to the remaining unprotected call sites) and native EN+PT-BR
  translation written by hand (upstream shipped neither language as a working native `.txt`).
- **Evolving Traits World (ETW)** (Workshop 2914075159) is bundled as of 2026-08-30 - by far the
  largest piece in this pack (206 files, ~15,000 lines), 65 new traits (`ETW:*` namespace, kept
  as-is like I Regret Nothing) plus a system that makes dozens of vanilla traits dynamically
  earnable during play, not just pickable at character creation. Its own `require=` already named
  the three framework dependencies already bundled here, confirming they were prepared correctly.
  Its optional "MDTF" soft-dependency was investigated and confirmed to be a pure UI label
  ("(D)" suffix), not needed for the actual mechanic - not bundled. Its "Trait Sandbox" companion
  (admin point-cost UI) was deliberately left out per the project owner's explicit call - needs a
  new dependency, `StarlitLibrary`. **A real collision bug was found and fixed in a DIFFERENT,
  already-bundled module** (`LS_BetterEngineRepair`'s `ISRepairEngine:complete` patch did a full
  reassignment with no call-through, which would silently discard ETW's own safe wrap depending on
  load order) - see `vendor/lascivious-traits/INTEGRATION.md` and `docs/COLLISION_REGISTRY.md`.
  **PT-BR translation is now 100% complete** (2026-08-30, LS-007) - all 432 missing Sandbox keys
  and 149 missing UI keys hand-translated, closing the dedicated translation pass the project owner
  asked for. A second orphaned-filename bug (same class as LS-005) was found and fixed along the
  way: UCWF's own English Sandbox options had been sitting in an unread file since LS-003.
- **Cross-trait harmony checkup between I Regret Nothing and ETW** (2026-08-30, LS-008) -
  investigated whether ETW's own dynamic systems (Smoker addiction decay, Bravery/Fear-of-Locations)
  should be blocked from touching the traits I Regret Nothing forces/excludes; a first pass
  patched `RegretNothing_DudeMechanics.lua` to defend both, but that was reverted after
  reconsidering the actual design intent - `GrantedTraits` is a one-time kickstart, not a
  permanence lock, and letting the character follow ETW's normal earn/lose rules afterward is more
  harmonious with ETW's own philosophy than fighting it. No code changed in the end. See
  `vendor/lascivious-traits/INTEGRATION.md` "Cross-trait harmony" for the full reasoning.
- `media/registries.lua` now exists (created with I Regret Nothing, ETW's own trait registry table
  appended alongside it) - see the vendor `INTEGRATION.md` for the pattern future traits append to.
- **Not wired into `docs/SERVER_MOD_ORDER.md`'s canonical `Mods=` string or the production
  `/home/dahaka/Zomboid/Server/LASCIVIOUS.ini` yet.** Both happen once the first real trait lands
  and passes validation, same sequencing already used for `LS_EvilMortyDeathScreen` and
  `HWNetBridge`: local integration first, Workshop publish, only then the live server config.

## Namespace

`lascivioustraits:<trait_name>`, all lowercase. See the vendor `INTEGRATION.md` for the full
registries.lua / script-file / icon-filename pattern, and read the save-persistence warning there
before naming (or renaming) anything - a trait's resource-location string becomes permanent the
moment any character in any save picks it.

## Next step

Waiting on the project owner to name any further trait mods/ideas to fold in beyond I Regret
Nothing. Each one goes through the same shape already proven here: read the source for the
mechanic, decide what to keep/reimplement/bundle-as-is, write it under this submod's
`42/media/lua/{client,server,shared}/`, register it in `registries.lua`, add its
`character_trait_definition` block, translate it (EN native + PT-BR native), document it as a
subsection in `vendor/lascivious-traits/INTEGRATION.md`, and only then wire the registry rows /
`Mods=` string / live ini - still not done for this submod at all, even with a trait shipped
locally, per the pack's standing sequencing rule.
