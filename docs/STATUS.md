# Project Status & Handoff Briefing

**Read this before touching anything else.** `docs/ARCHITECTURE.md` is the canonical rulebook (the
*how*); this document is the *where we are right now* briefing plus the practical lessons learned
across 31 real third-party integrations that aren't written down anywhere else. If you're a new
agent/session picking this project up cold, read this file fully, then skim
`docs/MODULE_REGISTRY.md` and `docs/COLLISION_REGISTRY.md` for current state, then start work.

Last updated: 2026-08-31, after Spawn Selector was integrated as `LS_SpawnSelector` and the
Bloodlust/Regret/HardcoreKits/Shop reward fixes were reinforced — see
`vendor/lascivious-traits/INTEGRATION.md`.

## Pre-release review: closed, pack is in production (2026-08-27)

A full CRITICAL/HIGH static security/stability/performance review ran across 2026-08-26/27 (see
`LASCIVIOUS_SCRIPTS_PRE_RELEASE_REVIEW_FINAL.md` and `review/*.md`). Zero known CRITICAL/HIGH is left
unpatched — see `review/03_RECONCILED_FINDINGS.md` and `review/08_RELEASE_BLOCKERS.md` for the full
list and patches applied. **The project owner closed the review on 2026-08-27 and put the pack into
production without running the formal in-engine test matrix** (`review/06_RUNTIME_TEST_MATRIX.md`
stayed `NOT_RUN` by explicit choice — runtime verification now happens naturally in production
instead of as a pre-release gate).

**Going forward, work on this pack is reactive only**: no more proactive auditing, no new review
rounds, no unprompted re-reads of `review/`. Only act on this when the project owner reports a real
problem observed in actual gameplay — then treat `review/` as historical context (what was already
checked and patched) rather than restarting the methodology from scratch.

## Where things stand — the pack is complete

**35 active Mod IDs bundled in one Workshop item**, including the originally-planned mods, the later
Wilderness Spawnpoints addition, the generic `LS_BugFixes` container, the first-party
`LasciviousSystems` ecosystem, Evil Morty Death Screen and the active `LS_Traits` container (one,
`LS_AliceWeaponSlingRadialMenu`, was bundled and then removed entirely on 2026-08-27 at the project
owner's request — see `vendor/alices-weapon-sling/LOCAL_CHANGES.md` LS-005). Own-code lives in the
core `LasciviousScripts` submod and `LasciviousSystems`; third-party integrations live either in
isolated `LS_*` submods or in purpose-specific containers such as `LS_BugFixes`/`LS_Traits` (see
`docs/MODULE_REGISTRY.md` for the full table,
`docs/COLLISION_REGISTRY.md` for every cross-module interaction found and resolved,
`docs/SERVER_MOD_ORDER.md` for the canonical `Mods=` string and the hard load-order constraints that
currently exist). `tools/validate_structure.py` and `tools/audit_collisions.py` are the standing
structure/collision checks after each integration.

## `LS_Traits` — active trait container (2026-08-30)

`LS_Traits` (`docs/modules/lascivious-traits.md`, `vendor/lascivious-traits/`) is now the active
"container that grows over time" for trait frameworks and trait packs. It bundles Moodle Framework,
KillCount, Unified Carry Weight Framework, I Regret Nothing, Evolving Traits World and Bloodlust
Overwhelming. The canonical `Mods=` order includes `LS_Traits`, and the live
`/home/dahaka/Zomboid/Server/LASCIVIOUS.ini` also lists it. Before adding or renaming any trait,
read `vendor/lascivious-traits/INTEGRATION.md`; the trait resource-location string is save-sensitive
once a player selects or earns it.

**No separate pending queue is tracked here.** If the user names a new mod/trait in the future, the
same Fase 1-10 flow below still applies.

**What's very likely next, per the user's own earlier (2026-08-25) instruction, only on explicit
request**: a GitHub remote gets set up "at the very end, after the whole mod pack is finished." That
point has now been reached. The repo has local git history only (`git init` ran 2026-08-25, no
commits forced automatically). **Do not create a remote, add an `origin`, or push anywhere — and
don't assume "the pack is done" alone is the trigger — wait for the user to actually ask for that
step**, per the standing "never touch git remotes without an explicit per-instance request" rule
below.

## Absolute constraints — violating these has caused real problems before

- **Never mention license, authorship, redistribution permission, or crediting the original mod
  author, anywhere — not in `INTEGRATION.md`, not in commit messages, not in conversation.** This
  used to be part of the architecture doc (a license/permission gate) and was ripped out entirely
  after the project owner reacted very badly to it being raised. Every bundled `mod.info` has its
  `author=`/`Authors=`/`url=` lines stripped as a matter of course (see any `Contents/mods/LS_*/42/
  mod.info` for the pattern) — keep doing that, and don't reintroduce any authorship/licensing
  framing in new docs, however incidental it seems.
- **Never `git commit` or touch a GitHub remote without an explicit, direct request** for that
  specific action, every time — a prior blanket approval doesn't carry forward, and "the pack is
  finished" is not itself that request.
- **Don't ask the user to re-explain the integration process** — they've confirmed (2026-08-25) they
  understand the flow and will keep supplying just "name + Workshop ID" for any future addition. Only
  interrupt for a real judgment call (see below) or a missing Workshop ID / mod not downloaded.

## Judgment calls — the two shapes that actually come up, and how they were resolved

1. **Mutually-exclusive tiers/variants of the same mod** (`incompatible=` cross-references sibling
   Mod IDs, description says "select only one," e.g. Durable Tools and Weapons' Soft/Normal/Hardened
   split, Drag Bodies Faster's 5 speed tiers). Always stop and ask the user which one before doing
   anything else. Don't confuse this with a Workshop item that happens to bundle two genuinely
   independent, complementary mods (Skully's Faster Attack/Swing Speed) — decide which shape it is
   by reading what each variant's code actually touches, not by the mere fact that they share a
   Workshop page.
2. **Genuinely redundant features between a new mod and an already-bundled one** (two different
   mods each independently implementing overlapping functionality — distinct from tier variants of
   the *same* mod). Found twice in Burris Quality of Life (a flashlight-slot tweak duplicating
   `simple-belt-flashlight`, an ammo-HUD duplicating `clean-hotbar`). Present the conflict to the
   user with a recommendation (via a direct question), but expect them to sometimes want something
   *stronger* than the safe default — in both real cases the user asked for full code removal of the
   losing feature (files deleted, sandbox option removed, settings/translation kept in sync), not
   just a sandbox-default-off. Chase every place the mod's own internal consistency (sandbox
   options ↔ settings defaults ↔ translation keys) references the removed feature, not just the
   obvious Lua file.

Ordinary cross-module collisions where both sides use the safe monkey-patch pattern (see below) are
**not** judgment calls — resolve and document those yourself in `COLLISION_REGISTRY.md`, no need to
ask.

## Hard-won technical lessons (condensed — see each module's own `vendor/<key>/INTEGRATION.md` for full detail)

- **`getText()` never reads JSON, only native `Translate/<LANG>/<Family>_<LANG>.txt` (Lua-table
  format).** Many upstream mods ship only JSON translations (or ship JSON alongside a native EN file
  that's missing other families). Before considering translation work done, grep the mod's own Lua
  for every `getText(` call and confirm each key has a native `.txt` backing, not just a JSON file
  that looks complete. Fix by transcribing from JSON into a new native `.txt` (verify with a
  programmatic key-set diff and `luac5.1 -p`, since the game itself can't be run in this
  environment). Some mods ship **zero** native `.txt` in **any** family — budget for potentially
  recreating every translation family from scratch. Scale varies wildly: Plysken Solar Revolution
  needed 210 keys across 7 families; Aegis Panel needed 1092 keys across 2 families (the largest
  translation gap found in this pack) — for a job that size, write a one-off Python script to
  transcribe JSON → Lua-table mechanically rather than hand-typing it, then verify programmatically.
- **Native PT-BR `.txt` must be ASCII-safe, not raw UTF-8.** Raw accented Lua string literals in
  these tables render PT-BR accents (ã, ç, õ...) as `?` in-game. The safe path, validated across all
  17 modules with sandbox options on 2026-08-26, is to encode every non-ASCII UTF-8 byte as a
  three-digit Lua decimal escape (`\195\167`, etc.). Maintain the readable PT-BR source in JSON and
  generate `Sandbox_PTBR.txt` with `tools/generate_ptbr_sandbox_native.py`; then require an ASCII-only
  source check, `luac5.1 -p`, exact EN/PTBR key parity and a Lua 5.1 runtime reconstruction diff.
  Never hand-convert accented text into raw native literals.
- **Mod ID rename is (almost) always safe and expected** (`id=<Original>` → `id=LS_<Name>`,
  `ARCHITECTURE.md` section 20's "Category A"). Also strip empty `url=`, strip `author=`/`Authors=`,
  and drop any `incompatible=` line that names Workshop mods not bundled in this pack (those Mod IDs
  will never exist in this curated pack, so the line is dead weight — established precedent, don't
  debate it per-mod). The two known exceptions: a mod whose own code checks its own Mod ID (Category
  B — read the Lua for that before renaming), or a mod that exists specifically as a drop-in
  replacement for another mod's ID for save-compatibility reasons (Category C —
  `simple-belt-flashlight` is the one case so far, kept as `FixedLightOnBeltAF`).
- **Multiple upstream version folders are common** (`common/`+`42/`, root+`42.0/`, three-layer
  B41/common-stub/B42 splits, etc.). Don't assume the highest-numbered folder wins — PZ picks by
  `versionMin`/`versionMax` range actually covering 42.20.x, and this pack always consolidates
  whichever folder(s) actually apply into a single `42/` in the bundle. **Always check whether the
  folders' code actually differs** before assuming a legacy-vs-rewrite split (Better Push's 3
  identical-`versionMin` folders were just redundant packaging, not a real split).
- **Safe monkey-patch pattern**: capture-before (`local orig = X.method`) + always call through +
  (often) an idempotency guard. Two ways a cross-module collision on the same method turns out safe
  regardless of load order: (a) both sides use that pattern, or (b) one side captures late at
  `Events.OnLoad`/`OnGameStart`/similar (which only fires after every mod's file-scope Lua has
  already run pack-wide), so its capture always sees whatever the other side already installed. A
  collision is **order-sensitive** (needs a documented hard ordering rule in `SERVER_MOD_ORDER.md`)
  only when at least one side does a full reimplementation with no call-through at all — this has
  happened twice: `ISAttachItemHotbar` between `alices-weapon-sling`/`equip-while-running`, and (a
  currently-solo, no-collision-yet occupied surface, not an active rule) `aegis-panel`'s own
  unwrapped `MapSpawnSelect:getSafehouseSpawnRegion`.
- **MP-authority review checklist**: does the server independently recompute/validate anything a
  client claims (position, target ID, damage, currency/resource deltas), rather than trusting it?
  Does a `TimedAction` re-resolve its target server-side from primitive coordinates rather than a
  live object reference (B42's `NetTimedAction` can hand a dedicated server a `null` for an
  IsoObject-typed constructor arg)? Is a destructive cleanup path ever triggered by "I don't know"
  (unloaded chunk, unresolved reference) instead of a proven absence — several real food-loss/
  desync bugs across this pack's integrations trace back to exactly that mistake. Also watch for
  **event handlers that aren't actually local-player-scoped** — `Events.OnWeaponHitCharacter` fires
  on every connected client for every player's action, not just the attacker's; this caused a real
  multiplication bug in this pack's own `better-push` rewrite. For a mod with many privileged
  server commands (an admin panel, a moderation tool), verify **every single command handler**
  re-checks authority server-side, not just a representative sample — `aegis-panel`'s 26 files with
  a `Commands` table were checked exhaustively (two dedicated research passes) specifically because
  a single missed gate in an admin tool is a full server compromise, not a minor bug.
- **Scale technique** (first used on Plysken Solar Revolution, ~35 files; used twice more on Aegis
  Panel, ~78 files across two parallel agents): read the highest-priority files yourself first
  (server command handlers, anything network-facing or permission-deciding), then delegate the
  remaining exhaustive file-by-file inventory to one or more background research agents with a
  precise brief (exact files, exactly what to report per file: monkey-patches, MP-trust issues,
  globals defined, save-format keys, missing permission gates). For a very large or especially
  security-sensitive mod, splitting into multiple parallel agents by concern (e.g. "server authority"
  vs. "client UI + translations") worked well and kept each agent's brief focused. **Spot-check at
  least one of each agent's claims against a file you read directly** — on Plysken Solar Revolution
  an agent incorrectly called a helper function "dead code" only because it hadn't been told to
  re-read a file the orchestrating session had already read, which actually called it. An agent's
  summary describes what it did, not necessarily ground truth.
- **`luac5.1 -p <file>`** is the real Lua 5.1 syntax checker available in this environment — use it
  to verify any new/edited `.lua` or native-translation `.txt` file (the `.txt` files are just Lua
  table literals) parses correctly, since the game itself can't be launched here.
- A **local vanilla Project Zomboid install** exists at
  `/home/dahaka/.local/share/Steam/steamapps/common/ProjectZomboid/projectzomboid/` — whenever a mod
  fully overrides a vanilla file path (not a monkey-patch), diff directly against the matching file
  there for an exact, verified description of what actually changed, instead of trusting the mod's
  own description text.
- Third-party mod files live under
  `/home/dahaka/.local/share/Steam/steamapps/workshop/content/108600/<workshop_id>/` once
  subscribed/downloaded — this is the source for every `vendor/<key>/upstream/` snapshot.
- **Not every mod needs a code fix.** By the end of this pack, four modules needed zero LOCAL_CHANGES
  beyond the standard mod.info rebrand + translation work: `better-engine-repair`, `climb-ladders`,
  `plysken-solar-revolution`, and `aegis-panel` (the largest and most security-sensitive of the four,
  and still needed nothing beyond the missing-translation fix). Don't manufacture a fix where the
  upstream is already correct — a thorough MP-authority/collision review can legitimately conclude
  "no changes needed" and that's a completed integration, not an unfinished one.

## Standard integration deliverable shape (for reference — full detail in `ARCHITECTURE.md` §17)

Every completed integration produces: `vendor/<module_key>/{manifest.yml, upstream/, INTEGRATION.md,
LOCAL_CHANGES.md, TRANSLATION_PTBR.md}`, `Contents/mods/LS_<Name>/{common/media/.gitkeep,
42/{mod.info, media/...}}`, one alphabetical row in `docs/MODULE_REGISTRY.md`, zero or more rows in
`docs/COLLISION_REGISTRY.md`, a `docs/SERVER_MOD_ORDER.md` prose update plus a regenerated `Mods=`
string via `tools/generate_server_mods.py`, and both `tools/validate_structure.py` and
`tools/audit_collisions.py` passing clean before calling it done.
