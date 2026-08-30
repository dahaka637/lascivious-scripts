# Integration Notes — Mini Health Panel

- `module_key`: `mini-health-panel`
- `bundled_mod_id`: `LS_MiniHealthPanel`
- Workshop item `2866258937`, upstream folder name `MiniHealthPanel`. Ships **three parallel
  layers**: a root `mod.info`+`media/` with no version folder (`versionMin=41.60`/
  `versionMax=41.99` — a legacy Build 41 codebase, older Lua, missing an entire visual feature, see
  below), a `common/` containing only `mod.info` + 2 icon PNGs (no Lua/UI content at all — an
  incomplete stub, not independently usable), and a `42/` folder that is fully self-contained
  (`versionMin=42.13`, `modversion=1.6.1.42`, its own copies of both icon PNGs, and the actual B42
  Lua). **Only `42/` was bundled** — it's the newest, most complete, self-contained codebase, and
  the only one actually meant for Build 42.20.x. Confirmed via `diff` that `42/`'s Lua genuinely
  differs from the root/B41 version (not just a copy) and that `42/` ships 34 additional "stiff
  limb" sprite frames (`mhp-stiff_0..16.png` × male/female) that don't exist in the B41 layer at
  all — a real visual feature (limb-immobilization display, e.g. for splints) added later and only
  present in the B42 codebase.
- The upstream download also contained a stray `.git/` folder (~1.7 MB) nested inside
  `42/media/` — clearly an accidental inclusion of the author's own local development repository,
  not part of the mod. Excluded entirely from both the vendor snapshot and the bundle.

## What it does

A small, movable panel showing wound status per body part without opening the full vanilla health
panel, auto-hiding when nothing needs treatment. Right-clicking a body part on the mini panel opens
the same treatment context menu (bandage, disinfect, stitch, splint, remove bullet/glass, etc.) the
full health panel offers, without needing to open it. Has its own small settings panel (always-show,
HP bar toggle, muscle-strain display toggle, window-lock toggle) plus an optional integration with a
third-party "ModOptions" utility mod, if that specific external mod happens to be active (it isn't
bundled in this pack) — presence-checked (`if ModOptions and ModOptions.getInstance then ... end`),
fully inert otherwise, and not needed for the mod's own native settings panel to work.

## Why the treatment menu is safe without reimplementing any server logic

`MiniHealthTreatments.lua`'s own header comment says *"Literal copy-paste of items functions from
ISHealthPanel.lua"* — and it is: all 13 treatment-handler classes (`BaseHandler`, `HApplyBandage`,
`HRemoveBandage`, `HApplyPoultice` + 3 plant variants, `HDisinfect`, `HStitch`, `HRemoveStitch`,
`HRemoveGlass`, `HSplint`, `HRemoveSplint`, `HRemoveBullet`, `HCleanBurn`) mirror vanilla's own
private classes from `ISHealthPanel.lua` line-for-line in purpose. Verified against the actual
vanilla source
(`media/lua/client/XpSystem/ISUI/ISHealthPanel.lua`): vanilla declares every one of these as
`local` to its own file, meaning they're not reachable from outside it — this mod's copies are
**also** declared `local` to its own file, so despite having identical names, Lua's per-file scoping
means the two sets never interact or collide; this is a completely safe, independent re-declaration,
not a global-namespace collision. Critically, none of these copied classes re-implements the actual
*action*: every one of them still calls `ISTimedActionQueue.add(HealthPanelAction:new(...))`,
reusing vanilla's own **global** `HealthPanelAction` TimedAction class verbatim (confirmed this mod
never redefines `HealthPanelAction` itself). The copied logic here only decides which context-menu
entries to show and what arguments to pass — the actual treatment execution (item consumption, wound
state change, and its already-existing MP validation) is 100% unmodified vanilla code running
through vanilla's normal TimedAction network path.

## A note on multiplayer testing status

The mod's own in-game changelog text (see LS-001 below), which was actually broken and never visible
until this fix, states verbatim: *"This was not tested in multiplayer. This update has not been
tested in multiplayer. Please report any errors you encounter in the Steam Workshop comments."* —
this refers specifically to the B42.13 update that fixed several errors from Build 42's multiplayer
release. Nothing in the code itself suggests an MP-authority problem (see above — all actual actions
route through vanilla's own validated path), but this is worth remembering as a lower confidence
module than most in this pack until it's actually exercised on this server in a real multiplayer
session.

## Fase 1 inventory findings

- **Genuine upstream bug, fixed**: `42/media/lua/shared/Translate/EN/IG_UI_EN.txt` (the mod's own
  in-game update-notes popup text) was missing its closing double-quote and trailing comma —
  `luac5.1 -p` failed outright on the unmodified file (`unfinished string near '...'`). Since this
  breaks the entire native `.txt` chunk when the game tries to load it, `getText("IGUI_MiniHealth_
  UpdateNotes")` would have silently fallen back to displaying the raw translation key instead of
  the actual changelog text in the update popup shown to players. Fixed (see LOCAL_CHANGES LS-001).
- Translation was otherwise already fully native and correct upstream (2 keys total:
  `UI_MiniHealth_Enable`, `IGUI_MiniHealth_UpdateNotes`) — no JSON exists at all for this mod, and
  no other language beyond EN. Second module in this pack (after `proximity-inventory`) where the
  author already used native `.txt` translation files directly.
- No monkey-patching of any vanilla class anywhere — `ISMiniHealth`/`ISMhpSettings` are both
  brand-new `ISPanel:derive(...)` classes. Zero collision risk with any other bundled module.
- No sandbox options, no dependency on any other mod, no `require=`/`loadModAfter=`/
  `loadModBefore=` in `mod.info`.
- No check of the mod's own Mod ID anywhere (Category A per architecture doc section 20).
- Same handful-of-hardcoded-English-labels pattern as `osrs-experience-bar`
  ("Always visible", "Health bar", "Muscle strains", "Lock window", "Settings") — left untranslated
  for the same reason (no `getText()` plumbing to safely route PT-BR through; see that module's
  `INTEGRATION.md` for the full reasoning).

## Adaptation applied (Fase 5)

- `id=MiniHealthPanel` -> `id=LS_MiniHealthPanel` (Category A rename); `name=`/`description=`
  rewritten to the pack's style, PT-BR. `versionMin=42.13`, `modversion=1.6.1.42`, `tags=Interface`
  preserved verbatim. `poster=`/`icon=` preserved.
- Fixed the broken `IG_UI_EN.txt` (see above).
- All 4 Lua files otherwise copied byte-identical from the `42/` upstream codebase — confirmed via
  `diff -rq` and `luac5.1 -p`.
