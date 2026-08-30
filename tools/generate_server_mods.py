#!/usr/bin/env python3
"""Generate WorkshopItems=/Mods= lines from docs/MODULE_REGISTRY.md and workshop.txt.

Only rows whose Status column is 'ativo' are included. Mod IDs are deduplicated, keeping
first-seen order in the registry table (top to bottom). This does NOT yet resolve
loadModAfter/loadModBefore ordering constraints -- once a submod declares one, record it
in docs/SERVER_MOD_ORDER.md and adjust the output order there by hand.

Usage: tools/generate_server_mods.py
"""
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
REGISTRY = REPO_ROOT / "docs" / "MODULE_REGISTRY.md"
WORKSHOP_TXT = REPO_ROOT / "workshop.txt"


def parse_workshop_id():
    if not WORKSHOP_TXT.exists():
        return None
    for line in WORKSHOP_TXT.read_text(encoding="utf-8").splitlines():
        if line.startswith("id="):
            return line[len("id="):].strip()
    return None


def parse_registry_rows():
    if not REGISTRY.exists():
        print(f"ERROR: {REGISTRY} not found", file=sys.stderr)
        return []

    lines = REGISTRY.read_text(encoding="utf-8").splitlines()
    header_idx = next((i for i, line in enumerate(lines) if line.strip().startswith("| Key")), None)
    if header_idx is None:
        return []

    rows = []
    for line in lines[header_idx + 2:]:
        stripped = line.strip()
        if not stripped.startswith("|"):
            break
        cells = [c.strip() for c in stripped.strip("|").split("|")]
        if len(cells) >= 7:
            rows.append(cells)
    return rows


def main():
    workshop_id = parse_workshop_id()
    rows = parse_registry_rows()

    mod_ids = []
    for cells in rows:
        mod_id_raw, status = cells[2], cells[6]
        mod_id = mod_id_raw.split("(")[0].strip().strip("`").strip()
        if status.lower() != "ativo":
            continue
        if mod_id and mod_id not in mod_ids:
            mod_ids.append(mod_id)

    if not mod_ids:
        print("ERROR: no active Mod IDs found in docs/MODULE_REGISTRY.md", file=sys.stderr)
        return 1

    if workshop_id:
        print(f"WorkshopItems={workshop_id}")
    print(f"Mods={';'.join(mod_ids)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
