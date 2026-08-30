# Lascivious Systems

## Identity

- **Module key:** `lascivious-systems`
- **Project Zomboid Mod ID:** `LasciviousSystems`
- **Distribution:** bundled inside Workshop item `3788475731`
- **Version:** `1.0.0`
- **Runtime root:** `Contents/mods/LasciviousSystems/42/`

The Mod ID and every persistent/network identifier remain unchanged from the former standalone
Workshop distribution. This consolidation changes only where the submod is downloaded from; it
does not migrate or rename save data.

## Internal systems

- Lascivious Shop: server-authoritative credits, catalog, purchases, delivery recovery and
  optional credit preservation on death.
- Lascivious Factions System: factions, territory, diplomacy, raids, friendly fire, respawn and
  the `legacy` upgrade for death inheritance, with optional member-power preservation on death.
- Hardcore Kits: character/account entitlements, random kits, rewards and delivery recovery.
- PhunZones: embedded zone engine consumed by the faction and territory layers.
- HWNetBridge: server-only file bridge used by the external server bot.
- Loading assets: custom `media/ui/Progress/` sprites.

## Stable identities

Do not rename these during maintenance:

- Mod ID/API identity: `LasciviousSystems`;
- network modules: `LasciviousShop`, `LasciviousFactionsSystem`, `HKits`, `PhunZones`;
- GlobalModData: `LasciviousShop_ServerData`, `LasciviousFactionsSystem`,
  `LasciviousFactionsSystem_LegacyV1`, `PhunZones`, `HardcoreKits_Accounts`,
  `HardcoreKits_ClaimedInitialKitAccounts`;
- Sandbox roots: `LasciviousShop`, `LasciviousFactionsSystem`, `HardcoreKits`, `PhunZones`.

## Integration decision (2026-08-29)

The complete former standalone submod was copied byte-for-byte into this package as a separate
`Contents/mods/LasciviousSystems` boundary. It was deliberately not flattened into the
`LasciviousScripts/42/media` core: the separate Mod ID preserves persistence, APIs, emergency
disablement and subsystem ownership while still giving the server and clients one Workshop item.

The standalone source directory remains outside this package as a rollback source until the
Workshop/server cutover is explicitly completed. It must not be enabled alongside the bundled
copy, because both provide the same Mod ID and event handlers.

## Cross-module surfaces

- `ISChat.onCommandEntered` composes with Aegis moderation through call-through wrappers.
- `ISEquippedItem.render` composes with Clean Hot Bar through call-through wrappers.
- Systems also wraps several vanilla UI, building, vehicle and zone methods. The grouped inventory
  and the two cross-module interactions are recorded in `docs/COLLISION_REGISTRY.md`.
- The faction `legacy` upgrade wraps `CharacterCreationProfession:PointToSpend()` client-side only
  to add the server-approved temporary creation-point bonus without mutating
  `SandboxVars.CharacterFreePoints`.
- There are no duplicate Sandbox option names, EN/PTBR translation keys, Lua basenames or
  non-mergeable media paths against the other bundled submods as of the consolidation snapshot.

## Runtime verification required before production cutover

1. Start a dedicated staging server with `DoLuaChecksum=true` and only Workshop item `3788475731`.
2. Exercise `/shop`, `/kit` and Aegis mute together.
3. Verify Shop/Factions/Kits sidebar buttons with Clean Hot Bar enabled.
4. Test faction creation, claims, diplomacy, friendly fire, respawn, map overlays and vehicle guards.
5. Test `legacy`: death while in an active claimed faction prepares one inheritance; the next
   character receives the frozen creation-point bonus and target-based XP restore; relogging a
   living character does not consume anything.
6. Test the two death-preservation toggles both off and on: Shop credits should reset by default
   but preserve with `PreserveCreditsOnDeath`, while PvP credit steal still deducts the stolen
   percentage; faction member power should reset by default but preserve with
   `PreserveMemberPowerOnDeath`.
7. Restart the server and verify balances, kits, faction/zone state, pending transactions and
   pending legacy records.
8. Verify HWNetBridge heartbeat/inbox/outbox and the custom loading sprites.
9. Confirm no standalone PhunZones or standalone Workshop copy of `LasciviousSystems` is present.
