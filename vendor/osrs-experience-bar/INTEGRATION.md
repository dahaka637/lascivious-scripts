# Integration Notes — OSRS Experience Bar

- `module_key`: `osrs-experience-bar`
- `bundled_mod_id`: `LS_OSRSExperienceBar`
- Workshop item `3776534799`, upstream folder name `Rune Exp` (contains a literal space),
  `id=RUNE-EXP`. Standard single-`42/`-folder layout, no `common/` at all.

## What it does

Adds a movable, RuneScape-styled XP bar showing the currently tracked skill's progress, with
floating "+N exp" pop-ups whenever the local player gains experience, and a right-click dropdown for
hiding the bar or opening a config panel to choose which skills to track. Purely a visual/UI
addition — no gameplay mechanic, no new items, no sandbox options.

## Why this is safe without any server-side code or network commands

100% client-side, single-file-pair architecture: `RUNE-EXP.lua` (37 lines) subscribes to
`Events.AddXP` to react to the local player's own XP gains. The mod's own code comments explain a
real, deliberately handled vanilla limitation: *"The AddXP event is not triggered on multiplayer
clients, so there we watch the player's exp values for changes instead of waiting to be told about
them"* — `ISExpBar:pollXpChanges()` polls `self.player:getXp():getXP(perk)` every tick when
`isClient()` is true and raises a synthetic "drop" whenever a skill's already-known XP value
increases since the last poll. Every value involved (the player's own XP per skill) is already
locally known to that player's own client via vanilla's normal stat sync — nothing here reads or
trusts data belonging to another player, and nothing is written back to shared state. No
`sendClientCommand`/`sendServerCommand`/`OnServerCommand`/`OnClientCommand` appears anywhere in the
mod.

## Fase 1 inventory findings

- No monkey-patching of any vanilla class anywhere — `ISExpBar`/`ISExpDropdown` are both brand-new
  classes (`ISPanel:derive(...)`), not overrides of existing ones. Zero collision risk with any
  other bundled module.
- No sandbox options, no dependency on any other mod, no `require=`/`loadModAfter=`/
  `loadModBefore=` in `mod.info`.
- No check of the mod's own Mod ID anywhere (Category A per architecture doc section 20).
- Persists the player's bar position and tracked-skill preferences to a local, per-install config
  file (`getFileWriter/getFileReader("RUNE_EXP_conf.ini", ...)`) — standard PZ mod-local file
  storage, not shared or server-relevant.
- **No translation system used at all** — unlike almost every other module in this pack, this mod
  ships no `Translate/` folder and never calls `getText()`/`getTextOrNull()` for its own UI text.
  The handful of player-facing labels ("Tracked Skills:", "Close", "Hide"/"Show", "Configurate") are
  hardcoded English string literals directly in the Lua source. Skill names shown elsewhere resolve
  through `PerkFactory.getPerk(...):getName()`, which is already properly localized by vanilla
  regardless of language — only those 4 short UI labels are unlocalized upstream.

## Adaptation applied (Fase 5)

- `id=RUNE-EXP` -> `id=LS_OSRSExperienceBar` (Category A rename); `name=`/`description=` rewritten
  to the pack's style, PT-BR. `versionMin=42.0`, `modversion=2.0.3` preserved verbatim.
- No translation fix applied — see Fase 1 finding above. Deliberately did **not** inline PT-BR text
  into the 4 hardcoded Lua string literals: per this pack's standing rule
  ([[feedback-ptbr-accents-in-lua]]), any accented character placed directly in a raw Kahlua string
  literal (as opposed to routed through `getText()`/a native `.txt`/JSON) renders as "?" — and since
  this mod has no `getText()` plumbing to route through at all, there is no safe way to localize
  these labels without either accepting that risk on every future edit or building out translation
  infrastructure the upstream author never used. Left as English, matching this pack's
  already-accepted policy for every other native-text gap.
- All 3 Lua files copied byte-identical from upstream — confirmed via `diff -rq` and `luac5.1 -p`.
  **Zero code changes.**
