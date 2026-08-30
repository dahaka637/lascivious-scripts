#!/usr/bin/env python3
"""Validate Durable Tools against vanilla and its pristine vendor snapshot."""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path


REPO = Path(__file__).resolve().parents[1]
DEFAULT_VANILLA = Path(
    "/home/dahaka/.local/share/Steam/steamapps/common/ProjectZomboid/"
    "projectzomboid/media/scripts/generated/items"
)
BUNDLE = REPO / "Contents/mods/LS_DurableToolsWeapons/42/media/scripts"
VENDOR = REPO / "vendor/durable-tools-weapons/upstream/42/media/scripts"
EXPECTED_ITEMS = 351
ITEM_RE = re.compile(r"^\s*item\s+([A-Za-z0-9_.:-]+)\s*$")
DURABILITY_RE = re.compile(
    r"^\s*(ConditionMax|ConditionLowerChanceOneIn)\s*=\s*([^,]+),"
)


def parse_blocks(
    root: Path, wanted: set[str] | None = None
) -> dict[str, tuple[Path, list[str]]]:
    blocks: dict[str, tuple[Path, list[str]]] = {}
    for source in sorted(root.rglob("*.txt")):
        lines = source.read_text(encoding="utf-8-sig").splitlines()
        index = 0
        while index < len(lines):
            match = ITEM_RE.match(lines[index])
            if not match:
                index += 1
                continue
            name = match.group(1)
            opening = index + 1
            while opening < len(lines) and "{" not in lines[opening]:
                opening += 1
            if opening == len(lines):
                raise ValueError(f"item sem abertura: {name} em {source}")
            depth = 0
            closing = opening
            while closing < len(lines):
                code = lines[closing].split("//", 1)[0]
                depth += code.count("{") - code.count("}")
                if depth == 0:
                    break
                closing += 1
            if closing == len(lines):
                raise ValueError(f"item sem fechamento: {name} em {source}")
            if wanted is not None and name not in wanted:
                index = closing + 1
                continue
            if name in blocks:
                raise ValueError(f"item duplicado: {name} em {source} e {blocks[name][0]}")
            blocks[name] = (source, lines[index : closing + 1])
            index = closing + 1
    return blocks


def durability(block: list[str]) -> dict[str, str]:
    result: dict[str, str] = {}
    for line in block:
        match = DURABILITY_RE.match(line)
        if match:
            result[match.group(1)] = match.group(2).strip()
    return result


def without_durability(block: list[str]) -> list[str]:
    result: list[str] = []
    for line in block:
        stripped = line.strip().replace("\ufeff", "")
        if not stripped or stripped.startswith("//"):
            continue
        if DURABILITY_RE.match(stripped):
            continue
        result.append(re.sub(r"\s+", "", stripped))
    return result


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--vanilla-root",
        type=Path,
        default=DEFAULT_VANILLA,
        help="diretório generated/items da instalação vanilla alvo",
    )
    args = parser.parse_args()

    try:
        bundled = parse_blocks(BUNDLE)
        wanted = set(bundled)
        vanilla = parse_blocks(args.vanilla_root, wanted)
        vendor = parse_blocks(VENDOR, wanted)
    except (OSError, UnicodeError, ValueError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 2

    errors: list[str] = []
    if len(bundled) != EXPECTED_ITEMS:
        errors.append(f"quantidade bundled {len(bundled)} != {EXPECTED_ITEMS}")

    for name, (_, block) in sorted(bundled.items()):
        if name not in vanilla:
            errors.append(f"{name}: ausente no vanilla alvo")
            continue
        if name not in vendor:
            errors.append(f"{name}: ausente no snapshot vendor")
            continue
        if without_durability(block) != without_durability(vanilla[name][1]):
            errors.append(f"{name}: drift fora de durabilidade")
        if durability(block) != durability(vendor[name][1]):
            errors.append(f"{name}: valores Hardened divergentes do vendor")

    if errors:
        for error in errors:
            print(f"ERROR: {error}", file=sys.stderr)
        print(f"FAIL - {len(errors)} erro(s)", file=sys.stderr)
        return 1

    print(
        f"OK - {len(bundled)}/{EXPECTED_ITEMS} itens: vanilla atual fora de durabilidade; "
        "Hardened preservado nos campos permitidos"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
