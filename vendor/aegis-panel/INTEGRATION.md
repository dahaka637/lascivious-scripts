# Integration Notes — Aegis Panel

- `module_key`: `aegis-panel`
- `bundled_mod_id`: `LS_AegisPanel`
- Workshop item `3766508989`, upstream mod id `AP`, upstream folder ships **only** a `42/` version
  folder (no `common/`, no legacy build split) — the simplest top-level layout structurally, offset
  by being by far the **largest** module in this pack: 78 Lua files (52 client, 24 server, 2 shared),
  33 declared sandbox options, 13 shipped languages, ~10,600 lines of server Lua alone. This is the
  last of the three third-party mods the project owner flagged in advance as the most complex of the
  whole list.

## What it does

A full server-administration control panel: dashboard, per-player cards (teleport/heal/god/invis/
stats/inventory/notes), moderation (kick/tempban/ban/mute/warn with an evidence package per action),
a role system that narrows what a given admin/moderator can reach, an item spawner, vehicle and
animal spawners with 3D preview, world/horde control (weather, time, siege/storm/heli/airdrop/
firestorm/ambush event director), a safehouse/zone editor (freeform paint, borders, backups/
restore), kit definitions with claim tracking, a Discord-booster code-redemption system, server
restart scheduling, an INI options editor, and a separate player-facing "blue panel" (self-service
safehouse claims, remembered vehicles, stats, SOS alerts) gated by role-granted budgets rather than
admin rights.

## Review method — this integration used two background research agents

Given the file count, this session read the six foundational files directly first (`Aegis_Shared.lua`,
`Aegis_Server.lua` — 2047 lines, the main command dispatcher — `Aegis_Roles.lua`, `Aegis_Moderation.lua`,
`Aegis_Log.lua`, `Aegis_Store.lua`) to establish the permission architecture, then delegated two
parallel research passes: one auditing the remaining 19 server files + `Aegis_Capacity.lua` for
MP-authority discipline specifically, one inventorying all 52 client files plus every translation/
asset file. Both full reports are preserved for reference at the paths noted in their respective
sections below (not copied into this repo — they were scratch-space research artifacts).

## The permission architecture (verified across all 26 server-side files with a `Commands` table)

- `AegisRoles.effectiveRights(player)` returns `nil` (full access — a vanilla admin with no Aegis
  role assigned), `false` (an assigned role explicitly denies everything), or a rights table keyed by
  area name. **An Aegis role can only narrow a vanilla admin's access, never grant access to a
  non-admin** — `isVanillaAdmin(player)` must be true first, checked via the player's own
  `getAccessLevel()` (a server-authoritative engine property, never trusted from the client).
- `AegisRoles.canArea(player, area)` is the area-level gate every admin command calls (directly, or
  via a same-file `allowed()`/`permitted()` wrapper) before doing anything privileged.
- `AegisModeration.isSuspended(player)` — every single file's own `OnClientCommand` dispatcher
  re-checks this at the top, because B42 has no engine-level way to filter packets from a suspended
  admin; a banned/suspended staff member is blocked network-wide, not just in the moderation file.
- `AegisStore.pathOk(relPath)` rejects `..`, `|`, `\`, and enforces every stored file stays under the
  `Aegis/` root; free-text (usernames, zone/role/note names) that becomes a file path goes through
  `AegisShared.sanitizeName()` first.
- Player-facing self-service files (`Aegis_PlayerClaims.lua`, `Aegis_PlayerPanel.lua`,
  `Aegis_PlayerVehicles.lua`, the `PlayerCommands` halves of `Aegis_Kits.lua`/`Aegis_Boost.lua`)
  correctly use a server-derived **entitlement** check instead of `canArea` — this is the structurally
  correct pattern for self-service (a role-granted budget, not an admin capability), not a gap.

**Result of the full audit: zero missing permission gates found across all 26 server-side command
files.** Two commands are deliberately open by design with strong compensating controls
(`Aegis_Deaths.lua`'s `deathReport` — the server independently corroborates the death before writing
anything, a live client cannot forge one; `Aegis_PlayerStats.lua`'s `banditKill` — a rate-limited
cosmetic leaderboard counter with no economy/world-state impact). No handler was found authorizing
off a client-supplied trust flag instead of re-deriving state server-side. Client-side rights checks
(`Aegis.allowed`/`Aegis.canSee`) are consistently display-only and fail closed until the server
confirms — every privileged/shared-state action routes through `sendClientCommand`/
`Events.OnServerCommand` or an equivalent vanilla server-validated channel.

This is, without qualification, the most rigorously engineered mod reviewed in this entire pack —
exceeding even `plysken-solar-revolution` and `cyes-push-doors`, the previous high-water marks.
Comments throughout are detailed postmortems of specific past production incidents (exact numbers
cited: "user: 4167", "server said 730, panel showed over 2300"), a codebase-wide "never rewrite a
file from an incomplete read" discipline independently reimplemented in at least six unrelated files,
and NaN/Infinity-safe numeric parsing repeated verbatim across independent files.

## Minor nits found — documented, not fixed (none are security issues)

- `Aegis_Retention.lua`'s automated zone-backup/log rotation deletions are not logged, unlike
  `Aegis_Backup.lua`'s automated backups (which log with `adminName="Server"`). Cosmetic audit-trail
  asymmetry, not a bug — left as upstream shipped it.
- `Aegis_Zones.lua`'s `shNew`/`shNewShape` accept an unvalidated `owner` free-text string (no roster
  check, no length cap, no control-char strip) — traced in full: it never becomes a file path (only
  vanilla engine fields and `AegisLog.write` target arguments), the command is already admin-gated on
  `"zones"`, and the field is explicitly "admin picks the target player" by design (comment 1666).
  Minor data-hygiene gap, not a vulnerability.
- `AegisVehicleDetail.lua` briefly reassigns the bare global `getText` function for the duration of a
  single `ISVehicleMechanics:render` call (to substitute a custom vehicle nickname into the vanilla
  mechanics-window title), then restores it unconditionally. Synchronous, narrow, and functions
  correctly — flagged here only as a fact worth knowing if a future collision investigation ever needs
  to explain unexpected `getText` behavior during that one render call.

## Cross-checked against every one of this pack's other 27 bundled modules — no real collision

**24 total monkey-patches** found across the whole mod (8 server-side, 16 client-side). Every vanilla
class/global name touched was grepped across all other bundled modules; **zero hits** except two
confirmed false positives (a PSR comment mentioning `ItemContainer.save()` in prose, and
`faster-hood-opening` reading the shared vanilla static field `ISVehicleMechanics.cheat` — a field
read, not a patch of `ISVehicleMechanics:render`, which is what Aegis wraps). Soft cross-mod
integrations (`KnoxClaim.*` client/server globals for vehicle-claim handoff, Faction Framework's
out-of-band faction data, a "DailyKillCount"-style kill-counter mod detected by symptom in
`Aegis_PlayerStats.lua`'s own postmortem comments) are all `pcall`-guarded and degrade to Aegis's own
built-in behavior when absent — none of those mods are bundled in this pack today, so all three
integrations are currently inert. Re-check if any of them are ever added later.

**Server-side (8 patches, all in `Aegis_Construction.lua`)** — the single highest-priority file for
future collision checks, since `ISMoveablesAction.complete`/`ISDestroyStuffAction.complete`/
`buildUtil.setInfo` are exactly the hook points a future building/anti-cheat/activity-log mod would
also use: `buildUtil.setInfo`, `buildUtil.addCorner`, `buildUtil.consumeMaterial` (also fixes a real
vanilla dedicated-server bug — the build-cheat's material bypass could structurally never fire there,
see the file's own comment), `ISBuildIsoEntity.setInfo`, `ISMoveablesAction.complete`,
`ISDestroyStuffAction.complete`, `ISSmashWindow.complete`, `ISHotwireVehicle.complete`. All eight are
idempotency-guarded wrap-style patches (namespaced flag + call-through).

**Client-side (16 patches across 7 files)** — full list in `docs/COLLISION_REGISTRY.md`. Two stand
out as the highest collision risk if a future mod is added: `AegisCapacityClient.lua` patches
`ItemContainer`'s **class-metatable** directly (`getCapacity`/`getEffectiveCapacity`/`hasRoomFor` —
the deepest patch mechanism PZ Lua allows, visible to every mod in the game, wrap-style); and
`AegisPlayerPages.lua` **fully overrides** `MapSpawnSelect:getSafehouseSpawnRegion` with **no
call-through** (fixes a real vanilla width/height-swap bug in safehouse-respawn placement) — the one
patch in the whole mod that doesn't chain, so it would silently lose to (or silently defeat) any
future mod patching the same method. No current collision (grepped, zero other bundled modules touch
either surface) — logged as occupied surface in `COLLISION_REGISTRY.md` for future integrations to
check, same pattern already established for `ISHotbar.refresh` before `clean-hotbar` arrived.

## Fase 1 inventory findings

- **Biggest finding, matching a pattern already seen in `plysken-solar-revolution`**: upstream ships
  translations only as JSON (`Sandbox.json` + `UI.json`, 13 languages, 1092 keys/language) and **zero**
  native `.txt` files anywhere. `getText()` never reads JSON, so every one of this mod's ~1092
  player-facing strings (all 33 sandbox option labels/tooltips, every UI label across all 52 client
  files — confirmed via 953 `getText(` call sites in the client tree) would have rendered as raw
  untranslated keys in-game. Fixed (see Adaptation).
- Sandbox cross-check: all 33 declared options (single page `AegisEvents`) are read somewhere in the
  Lua; zero declared-but-unread options, zero undeclared-option reads. (`AegisPower.lua` reads two
  *vanilla* base-game sandbox options for display math — not part of this mod's own declared set,
  correctly out of scope for this check.)
- No `require=`, `versionMin`, or `modversion` in the original `mod.info` at all — just
  `name`/`poster`/`id`/`description`/`Authors`. No self-Mod-ID check anywhere in the Lua (grepped for
  literal `"AP"` and `getActivatedMods` self-references) — Category A rename, straightforward.
- Section 6 security sweep (hardcoded Steam IDs/IPs/usernames/URLs, dynamic-code/shell-execution
  primitives `loadstring`/`dofile`/`os.execute`/`io.popen`) across the full 52-file client tree:
  **zero findings on both.** Worth stating explicitly for a mod this security-sensitive (full admin
  control, Discord-integration secret key) — nothing resembling a backdoor or telemetry beacon.
- PT-BR JSON is complete and correct for both families (1092/1092 keys, byte-exact key-set match
  against EN, 0 missing/extra/empty) — see `TRANSLATION_PTBR.md`.

## Adaptation applied (Fase 5)

- `id=AP` -> `id=LS_AegisPanel` (Category A rename); `name=`/`description=` rewritten to the pack's
  style, PT-BR. Added `versionMin=42.20` (upstream declared no version floor at all — same fix already
  applied to `proximity-inventory`). Removed `Authors=` (no `url=` was present to remove).
- Added native `Sandbox_EN.txt` (67 keys) and `UI_EN.txt` (1025 keys) — 1092 total — generated by a
  one-off Python script that transcribed the already-correct, already-complete EN JSON key-for-key
  and value-for-value into the native Lua-table format (all 1092 keys are safe bare Lua identifiers,
  no bracket-string keys needed this time, unlike `plysken-solar-revolution`'s dotted/hyphenated
  keys). Verified programmatically that both native files' key sets exactly match their JSON sources,
  spot-checked 20 values landed byte-identical, and `luac5.1 -p` passes on both files. `%1`/`%2`/`%3`
  positional placeholders and the 4 already-`%%`-escaped literal-percent values in the source JSON
  were transcribed verbatim (no manipulation needed — these are PZ's own `getText()` substitution
  syntax and Lua `string.format` percent-escaping respectively, both already correct in the source).
- All 78 Lua files, all UI textures, and every language's JSON were copied byte-identical from
  upstream — confirmed via `diff -rq`. **Zero code changes.** Second module in this pack (after
  `better-engine-repair`/`climb-ladders`/`plysken-solar-revolution`) needing no bug fix at all, and
  by a wide margin the largest.
