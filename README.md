# Lascivious Scripts

All-in-one Project Zomboid Build 42 server pack for Lascivious Hardcore: a compiled,
reviewed and PT-BR-translated bundle of gameplay mods plus the server's own Shop, Factions,
Hardcore Kits and integration systems, distributed as a single Steam Workshop item.

- **Workshop ID:** `3788475731` (see [`workshop.txt`](workshop.txt))
- **Target build:** 42.20.x
- **Architecture:** one Workshop item, many isolated Project Zomboid submods under
  `Contents/mods/` — see [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) for the full canonical
  methodology. Read that document before integrating, updating or removing any mod here.

## Layout

```
Contents/mods/          # what actually ships and loads in-game
  LasciviousScripts/    # core authorial submod (own-code modules live here)
  LasciviousSystems/    # Shop, Factions, Kits, zones, Discord bridge and loading assets
  LS_BugFixes/          # small game bug fixes grouped together
vendor/                 # pristine upstream snapshots + manifests for third-party mods
docs/                   # architecture, module docs, registries
tools/                  # maintenance scripts (validation, collision audit, hashing, server Mods=)
```

## Docs

- [`docs/STATUS.md`](docs/STATUS.md) — **read this first if you're picking up this project cold.**
  Current progress and the non-obvious lessons learned across 30 integrations that aren't in
  `ARCHITECTURE.md` itself.
- [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) — canonical methodology (read this second — it's
  the rulebook, `STATUS.md` is the "where things stand" briefing).
- [`docs/MODULE_REGISTRY.md`](docs/MODULE_REGISTRY.md) — index of every bundled module.
- [`docs/COLLISION_REGISTRY.md`](docs/COLLISION_REGISTRY.md) — every vanilla override / cross-module collision.
- [`docs/SERVER_MOD_ORDER.md`](docs/SERVER_MOD_ORDER.md) — canonical `Mods=` order for the dedicated server.
- [`docs/modules/`](docs/modules/) — one file per own-code module (`time-vote.md`, `zombie-decay.md`).

## Tools

Run from the repo root with `python3` (stdlib only, no dependencies):

```
python3 tools/validate_structure.py      # structure/common/mod.info/case/temp-file checks
python3 tools/audit_collisions.py        # Mod ID + relative-path collision scan
python3 tools/audit_durable_overrides.py # 351 itens vs vanilla atual + valores Hardened
python3 tools/hash_module.py <path>      # relative_path|size|sha256 inventory of a directory
python3 tools/generate_server_mods.py    # WorkshopItems=/Mods= lines from MODULE_REGISTRY.md
```

None of these tools modify content automatically — see `docs/ARCHITECTURE.md` section 27.

## Current modules

**32 Mod IDs bundled in one Workshop item.** The package contains 2 own-code modules (Time Vote
and Zombie Decay) inside the core `LasciviousScripts` submod, the first-party
`LasciviousSystems` ecosystem, and 30 third-party integrations including the generic
`LS_BugFixes` container. Full table in
[`docs/MODULE_REGISTRY.md`](docs/MODULE_REGISTRY.md).

No mod is currently pending. If a new one is requested, follow the fluxo in
`docs/ARCHITECTURE.md` section 17 (or 18 for updates) end to end — it starts with a `vendor/`
snapshot, never a direct copy into `Contents/`. Read `docs/STATUS.md` first for the practical
lessons learned doing this 30 times already.
