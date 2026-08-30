#!/usr/bin/env python3
"""Index bundled-resource paths across all submods and flag exact collisions.

Detects: duplicate Mod IDs, and identical relative paths under common/media/ or 42/media/
appearing in more than one *different* submod -- the "same override path" class of
collision from docs/ARCHITECTURE.md section 11 (e.g. two submods both overriding the same
vanilla AnimSets/Lua file path, where only one survives by load order).

Does NOT flag the well-known per-mod files from architecture doc section 10/19.2
(sandbox-options.txt, Sandbox_<LANG>.txt, UI_<LANG>.txt, registries.lua, etc.) -- PZ loads and
merges every active mod's own copy of these, so every submod having one is normal, not a
collision.

Does NOT parse Lua/XML/scripts for item/recipe/trait/perk/vehicle/tiledef/pack IDs, network
module names, or Lua globals -- those need manual review per the checklist in section 11 and
should be logged by hand in docs/COLLISION_REGISTRY.md.
"""
import sys
from collections import defaultdict
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
MODS_DIR = REPO_ROOT / "Contents" / "mods"

IGNORED_FILENAMES = {".gitkeep"}

# Filenames PZ expects every mod that needs them to ship its own copy of -- the engine loads
# and merges these across all active mods rather than picking one by load order, so the same
# filename recurring in multiple submods is normal, not a path collision.
# Native .txt files embed the language in the filename (family_LANG.txt); JSON translation
# files instead put the language in the folder (Translate/<LANG>/family.json) and share one
# bare filename per family across every language.
_TRANSLATION_FAMILIES = (
    "Sandbox",
    "UI",
    "IG_UI",
    "IGUI",  # alternate no-underscore filename some mods use for the IG_UI family
    "ContextMenu",
    "Tooltip",
    "ItemName",
    "Recipes",
    "Moodles",
    "Entity",
)
_LANGS = ("EN", "PTBR")

EXPECTED_PER_MOD_FILENAMES = {"sandbox-options.txt", "registries.lua"}
EXPECTED_PER_MOD_FILENAMES |= {f"{family}.json" for family in _TRANSLATION_FAMILIES}
EXPECTED_PER_MOD_FILENAMES |= {
    f"{family}_{lang}.txt" for family in _TRANSLATION_FAMILIES for lang in _LANGS
}


def mod_info_id(submod: Path):
    mod_info = submod / "42" / "mod.info"
    if not mod_info.exists():
        return None
    for line in mod_info.read_text(encoding="utf-8", errors="replace").splitlines():
        if line.startswith("id="):
            return line[len("id="):].strip()
    return None


def media_roots(submod: Path):
    for variant in ("common/media", "42/media"):
        root = submod / variant
        if root.is_dir():
            yield root


def main():
    if not MODS_DIR.is_dir():
        print(f"ERROR: {MODS_DIR} not found")
        return 1

    submods = sorted(p for p in MODS_DIR.iterdir() if p.is_dir())

    ids_by_modid = defaultdict(list)
    owners_by_relpath = defaultdict(set)

    for submod in submods:
        mod_id = mod_info_id(submod)
        if mod_id:
            ids_by_modid[mod_id].append(submod.name)

        for root in media_roots(submod):
            for path in root.rglob("*"):
                if path.is_file() and path.name not in IGNORED_FILENAMES and path.name not in EXPECTED_PER_MOD_FILENAMES:
                    rel = path.relative_to(root)
                    owners_by_relpath[str(rel)].add(submod.name)

    problems = 0
    print(f"Indexed {len(submods)} submod(s).\n")

    dupe_ids = {k: v for k, v in ids_by_modid.items() if len(v) > 1}
    if dupe_ids:
        print("Duplicate Mod IDs:")
        for mod_id, owners in sorted(dupe_ids.items()):
            print(f"  x {mod_id}: {', '.join(owners)}")
            problems += 1

    dupe_paths = {k: v for k, v in owners_by_relpath.items() if len(v) > 1}
    if dupe_paths:
        print("\nSame relative media path in more than one submod:")
        for rel, owners in sorted(dupe_paths.items()):
            print(f"  x {rel}: {', '.join(sorted(owners))}")
            problems += 1

    if problems == 0:
        print("No path/Mod-ID collisions detected (see module docstring for what this does NOT check).")
        return 0

    print(f"\n{problems} potential collision(s) found. Cross-check docs/COLLISION_REGISTRY.md.")
    return 1


if __name__ == "__main__":
    sys.exit(main())
