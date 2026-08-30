#!/usr/bin/env python3
"""Validate Contents/mods/ submod structure. See docs/ARCHITECTURE.md section 26.1.

Checks, per submod under Contents/mods/*:
  - common/ directory present (section 4);
  - 42/ directory and 42/mod.info present;
  - Mod IDs (mod.info `id=`) are unique across submods;
  - no temp/backup files (.bak/.old/.tmp/.swp/~/.DS_Store/Thumbs.db) shipped in the tree;
  - heuristic case-sensitivity check on well-known PZ directory names (AnimSets, Translate,
    lua, textures, media, ...) -- catches accidental "animsets" / "translate" renames that
    would silently break on the Linux dedicated server (section 9.3, section 34.5). This is
    a heuristic on directory *names* only; it does not verify that a path matches what the
    game engine actually requests -- that still needs manual verification per section 9.3.

Exit code is non-zero if any error-level problem was found.
"""
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
MODS_DIR = REPO_ROOT / "Contents" / "mods"
REGISTRY = REPO_ROOT / "docs" / "MODULE_REGISTRY.md"

TEMP_SUFFIXES = (".bak", ".old", ".tmp", ".swp", "~")
TEMP_NAMES = {".DS_Store", "Thumbs.db"}

CANONICAL_DIR_NAMES = {
    "animsets": "AnimSets",
    "translate": "Translate",
    "lua": "lua",
    "textures": "textures",
    "media": "media",
    "scripts": "scripts",
    "sound": "sound",
    "models": "models",
    "clothing": "clothing",
    "maps": "maps",
    "texturepacks": "texturepacks",
    "fonts": "fonts",
    "ui": "ui",
}


def mod_info_id(mod_info_path: Path):
    if not mod_info_path.exists():
        return None
    for line in mod_info_path.read_text(encoding="utf-8", errors="replace").splitlines():
        if line.startswith("id="):
            return line[len("id="):].strip()
    return None


def active_registry_ids():
    """Return active Mod IDs declared by MODULE_REGISTRY, deduplicated in row order."""
    if not REGISTRY.exists():
        return None
    lines = REGISTRY.read_text(encoding="utf-8", errors="replace").splitlines()
    header_idx = next((i for i, line in enumerate(lines) if line.strip().startswith("| Key")), None)
    if header_idx is None:
        return None
    result = []
    for line in lines[header_idx + 2:]:
        stripped = line.strip()
        if not stripped.startswith("|"):
            break
        cells = [cell.strip() for cell in stripped.strip("|").split("|")]
        if len(cells) < 7 or cells[6].lower() != "ativo":
            continue
        mod_id = cells[2].split("(")[0].strip().strip("`").strip()
        if mod_id and mod_id not in result:
            result.append(mod_id)
    return result


def check_case(root: Path):
    problems = []
    for path in root.rglob("*"):
        if not path.is_dir():
            continue
        canonical = CANONICAL_DIR_NAMES.get(path.name.lower())
        if canonical and canonical != path.name:
            problems.append(f"{path.relative_to(REPO_ROOT)}: expected '{canonical}', found '{path.name}'")
    return problems


def check_temp_files(root: Path):
    problems = []
    for path in root.rglob("*"):
        if path.is_dir():
            continue
        if path.name in TEMP_NAMES or path.name.endswith(TEMP_SUFFIXES):
            problems.append(f"{path.relative_to(REPO_ROOT)}: temp/backup file must not ship in Contents/")
    return problems


def main():
    if not MODS_DIR.is_dir():
        print(f"ERROR: {MODS_DIR} not found")
        return 1

    submods = sorted(p for p in MODS_DIR.iterdir() if p.is_dir())
    if not submods:
        print(f"ERROR: no submods found under {MODS_DIR}")
        return 1

    errors = []
    warnings = []
    seen_ids = {}

    for submod in submods:
        label = submod.name
        common_dir = submod / "common"
        build42_dir = submod / "42"
        mod_info = build42_dir / "mod.info"

        if not common_dir.is_dir():
            errors.append(f"{label}: missing common/ directory")

        if not build42_dir.is_dir():
            errors.append(f"{label}: missing 42/ directory")
        elif not mod_info.exists():
            errors.append(f"{label}: missing 42/mod.info")
        else:
            mod_id = mod_info_id(mod_info)
            if not mod_id:
                errors.append(f"{label}: 42/mod.info has no id= line")
            elif mod_id in seen_ids:
                errors.append(f"{label}: duplicate Mod ID '{mod_id}' also used by {seen_ids[mod_id]}")
            else:
                seen_ids[mod_id] = label

        warnings.extend(check_case(submod))
        errors.extend(check_temp_files(submod))

    registry_ids = active_registry_ids()
    if registry_ids is None:
        errors.append("docs/MODULE_REGISTRY.md is missing or has no module table")
    else:
        runtime_ids = set(seen_ids)
        declared_ids = set(registry_ids)
        for mod_id in sorted(runtime_ids - declared_ids):
            errors.append(f"runtime Mod ID '{mod_id}' is missing from active MODULE_REGISTRY rows")
        for mod_id in sorted(declared_ids - runtime_ids):
            errors.append(f"active MODULE_REGISTRY Mod ID '{mod_id}' has no runtime submod")

    print(f"Checked {len(submods)} submod(s) under {MODS_DIR.relative_to(REPO_ROOT)}")
    for mod_id, label in sorted(seen_ids.items()):
        print(f"  - {label}: id={mod_id}")
    if registry_ids is not None:
        print(f"Active registry Mod IDs: {len(registry_ids)}")

    if warnings:
        print("\nCase warnings:")
        for w in warnings:
            print(f"  ! {w}")

    if errors:
        print("\nErrors:")
        for e in errors:
            print(f"  x {e}")
        return 1

    print("\nOK - no structural errors found.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
