#!/usr/bin/env python3
"""Generate native PT-BR sandbox translation tables from the maintained JSON catalogs."""

from __future__ import annotations

import json
import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
MODS = ROOT / "Contents" / "mods"
KEY_RE = re.compile(r"Sandbox_[A-Za-z0-9_]+\Z")


def lua_string(value: str) -> str:
    """Return an ASCII-only Lua literal whose decimal escapes reconstruct UTF-8."""
    result: list[str] = []
    for byte in value.encode("utf-8"):
        if byte == 34:
            result.append(r'\"')
        elif byte == 92:
            result.append(r"\\")
        elif byte == 10:
            result.append(r"\n")
        elif byte == 13:
            result.append(r"\r")
        elif byte == 9:
            result.append(r"\t")
        elif 32 <= byte <= 126:
            result.append(chr(byte))
        else:
            result.append(f"\\{byte:03d}")
    return '"' + "".join(result) + '"'


def main() -> None:
    generated = 0
    for options in sorted(MODS.glob("*/42/media/sandbox-options.txt")):
        translate = options.parent / "lua" / "shared" / "Translate"
        source = translate / "PTBR" / "Sandbox.json"
        if not source.is_file():
            raise SystemExit(f"Catálogo PT-BR ausente: {source.relative_to(ROOT)}")

        catalog = json.loads(source.read_text(encoding="utf-8"))
        if len(catalog) == 1 and isinstance(next(iter(catalog.values())), dict):
            catalog = next(iter(catalog.values()))
        if not isinstance(catalog, dict) or not catalog:
            raise SystemExit(f"Catálogo PT-BR inválido: {source.relative_to(ROOT)}")

        lines = ["Sandbox_PTBR = {"]
        for key, value in catalog.items():
            if not isinstance(key, str) or not KEY_RE.fullmatch(key):
                raise SystemExit(f"Chave inválida em {source.relative_to(ROOT)}: {key!r}")
            if not isinstance(value, str):
                raise SystemExit(f"Valor não textual em {source.relative_to(ROOT)}: {key}")
            lines.append(f"    {key} = {lua_string(value)},")
        lines.append("}")
        lines.append("")

        target = translate / "PTBR" / "Sandbox_PTBR.txt"
        target.write_text("\n".join(lines), encoding="ascii")
        generated += 1

    print(f"Gerados {generated} arquivos Sandbox_PTBR.txt.")


if __name__ == "__main__":
    main()
