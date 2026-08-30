# Translation PT-BR - Lascivious Traits

**Status: 100% complete, both languages, all three families (2026-08-30, LS-007).**
`UI.json` 227/227, `Sandbox.json` 540/540, `Moodles.json` 50/50 - EN and PT-BR both at exact parity,
every family has both a native `.txt` and a JSON reference.

**Root-cause correction (LS-005, 2026-08-30)**: earlier revisions of this document assumed PZ's
translation loader merges files by the Lua table name declared inside them (`UI_EN = {...}`,
`Moodles_EN = {...}`), regardless of filename, the same way it merges the SAME category across
DIFFERENT mods. That part is true. What turned out to be **false**: it does **not** apply within a
single mod - PZ reads exactly **one file per translation category per language per mod**
(`UI.json`/`UI_EN.txt`, `Moodles.json`/`Moodles_EN.txt`, `Sandbox.json`/`Sandbox_EN.txt`, ...), the
same one-file-per-mod rule already known and tooled for `Sandbox` via
`tools/generate_ptbr_sandbox_native.py`. Confirmed by inspecting the local vanilla 42.20.x install:
`Translate/EN/` and `Translate/PTBR/` there contain exactly one `UI.json`, one `Sandbox.json`, one
`Moodles.json` each - **zero native `.txt` files anywhere** - meaning `getText()` reads JSON
directly for these families in the currently installed build, and there is no per-file merging
happening for either format. A scoped filename like `UI_KillCount.json` or
`UI_RegretNothing_EN.txt` is therefore never read at all when it coexists with another file in the
same mod folder that also declares `UI_EN`/`UI.json` - not "purely for tree clarity" as previously
documented, but a silent functional bug. This was caught only once the project owner tested I
Regret Nothing's trait name/description in game (`UI_trait_regretnothing` shown raw instead of
translated) - the same bug had already existed for KillCount's `UI` family since LS-002, just never
noticed because nobody had looked at its "Kills" tab text in game yet.

**Second instance found on the English side (LS-007, 2026-08-30)**: while closing the PT-BR gap for
ETW, UCWF's own EN Sandbox options turned out to have the exact same bug - `Sandbox_UCWF_EN.txt`/
`Sandbox_UCWF.json` (non-canonical filenames) had been sitting unread since LS-003, meaning "Cap max
weight at 50" and "Gather Detailed Debug Information" had likely never rendered in English either.
Fixed by merging into the canonical `Sandbox_EN.txt`/`Sandbox.json` and deleting the orphaned files.

**Standing rule**: every dependency/trait bundled into this submod must have its `UI`, `Moodles`,
and `Sandbox` keys merged into the ONE canonical `{UI,Moodles,Sandbox}.json` (+ `_EN.txt`/`_PTBR.txt`)
per language folder - never a dependency-scoped filename. `UI_trait_<Name>`/`UI_trait_<Name>desc`
(and similarly for `Moodles_*`/`Sandbox_*`) needs a correct entry in the submod's canonical file per
language to display at all. Native `.txt` for `UI`/`Moodles` was withheld in PT-BR until coverage
was complete (a partial file could have shadowed keys still living only in JSON) - now that coverage
is 100%, native `.txt` was added for both, matching `Sandbox`'s already-proven-necessary pattern.
PT-BR native `.txt` uses ASCII decimal escapes for accents, generated the same way as
`tools/generate_ptbr_sandbox_native.py`'s own output (see `docs/STATUS.md` "Hard-won technical
lessons" for the general "PT-BR accents in raw Lua literals render as '?'" rule this follows).

## Vanilla trait name glossary used across ETW's translated strings

ETW's sandbox options reference vanilla trait names constantly (skill/kill requirements for the
traits it makes dynamic). Where vanilla's own PT-BR already had a translation, it was matched
exactly; where vanilla's own PT-BR was missing the key (true for roughly half of them), one was
picked and used consistently across every reference:　

| English | PT-BR used | Source |
|---|---|---|
| Artisan | Artesanato | vanilla PT-BR |
| Blacksmith | Conhecimento de Ferraria | vanilla PT-BR |
| Conspicuous | Chamativo | vanilla PT-BR |
| Cook | Cozinheiro Habilidoso | vanilla PT-BR (disambiguated from ETW's own `HomeCook`="Cozinheiro") |
| Crafty | Engenhoso | vanilla PT-BR |
| Pacifist | Pacifista | vanilla PT-BR |
| Adrenaline Junkie | Viciado em Adrenalina | vanilla PT-BR |
| Desensitized | Dessensibilização | vanilla PT-BR |
| Inconspicuous | Discreto | vanilla PT-BR |
| All Thumbs | Desajeitado | vanilla PT-BR |
| Axeman ("Ax-pert" in ETW) | Mestre do Machado | new (pun not portable) |
| Burglar | Arrombador | new |
| Cat Eyes | Olhos de Gato | new |
| Clumsy | Desastrado | new |
| Cowardly | Covarde | new |
| Hemophobic ("Fear of Blood") | Hemofóbico | new |
| Brave | Corajoso | new |
| Dextrous | Destro | new |
| Eagle Eyed | Olho de Águia | new |
| Graceful | Gracioso | new |
| Target Shooter | Atirador Certeiro | new |
| Brawler | Brigão | new |
| Nimble | Ágil | new |
| Sprinting (skill) | Corrida | new |
| Outdoorsman | Sobrevivente do Mato | new |
| Mason | Pedreiro | new |
| Tinkerer | Consertador | new |
| Whittler | Entalhador | new |
| Wilderness Knowledge ("Bushcrafter" in ETW) | Sobrevivencialista | new |
| Hearty Appetite / Light Eater | Apetite Voraz / Comilão Leve | new |
| High Thirst / Low Thirst | Sede Alta / Sede Baixa | new |
| Thin Skinned / Thick Skinned | Pele Fina / Pele Grossa | new |
| Slow Reader / Fast Reader | Leitor Lento / Leitor Rápido | new |
| Slow Healer / Fast Healer | Cura Lenta / Cura Rápida | new |
| Wakeful / Sleepyhead | Desperto / Sonolento | new |
| Prone to Illness / Resilient | Propenso a Doenças / Resiliente | new |
| Disorganized / Organized | Desorganizado / Organizado | new |

## Current state, per bundled dependency/trait

- **Moodle Framework**: EN native `UI_EN.txt` complete (upstream shipped it, merged into the
  submod's canonical file). PT-BR now has both the JSON reference and a native `UI_PTBR.txt`
  (LS-007) - translated using the terms above where its own strings referenced sandbox categories.
- **KillCount**: `Sandbox` family has full native PT-BR (`Sandbox_PTBR.txt`, generated via
  `tools/generate_ptbr_sandbox_native.py` - re-run that tool after editing
  `Translate/PTBR/Sandbox.json` for this or any other module, it regenerates all of them). `UI`
  family is now complete in both native `.txt` and JSON for both languages (LS-007).
- **UCWF (Unified Carry Weight Framework)**: only has a `Sandbox` family (2 options + a title key).
  Merged into the canonical `Sandbox.json`/`Sandbox_EN.txt`/`Sandbox_PTBR.txt` for both languages -
  its EN copy was previously an orphaned, unread file (`Sandbox_UCWF_EN.txt`), fixed in LS-007 (see
  the root-cause note above).
- **I Regret Nothing**: both `UI` (2 keys) and `Moodles` (32 keys) now have complete native `.txt`
  and JSON for both languages.
- **Evolving Traits World (ETW)**: the large one - 65 trait names/descriptions plus ~525 Sandbox
  option labels/tooltips covering every system it adds (Bravery, Fear of Locations, Fog, Rain,
  Healer, Injuries, Food/Thirst/Sleep/Eating-Speed/Hearing systems, per-trait skill/kill
  requirements for every vanilla trait it makes dynamic, and per-trait tuning for all 65 new
  traits). Upstream's own PT-BR only covered ~21% of Sandbox and ~28% of UI before this pass; the
  remaining 432 Sandbox keys and 149 UI keys were translated by hand in LS-007, using the glossary
  above for consistency with vanilla trait names referenced throughout. A handful of PT-BR-only
  keys left over from an older upstream ETW version (renamed/removed options - e.g.
  `Sandbox_ETW_Axpert` before it became `Sandbox_ETW_Axeman`) no longer matched anything in the
  current English source of truth and were removed rather than kept as dead entries.
