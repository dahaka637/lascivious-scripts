#!/usr/bin/env python3
"""Print a relative_path|size|sha256 inventory for a directory tree.

Usage:
    tools/hash_module.py <path>

<path> may be relative to the repo root or absolute. Typical uses:
    tools/hash_module.py Contents/mods/LasciviousScripts
    tools/hash_module.py vendor/better-push/upstream

Diff two runs of this script (e.g. old upstream vs. new upstream, or upstream vs. our
bundled copy) to see exactly which files changed -- see docs/ARCHITECTURE.md section 18,
step 4 (UPSTREAM_ONLY / LOCAL_ONLY / BOTH_CHANGED / UNCHANGED classification).
"""
import hashlib
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent


def sha256_of(path: Path, block_size=65536):
    digest = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(block_size), b""):
            digest.update(chunk)
    return digest.hexdigest()


def main(argv):
    if len(argv) != 2:
        print(f"usage: {argv[0]} <path>", file=sys.stderr)
        return 1

    target = Path(argv[1])
    if not target.is_absolute():
        target = REPO_ROOT / target
    if not target.is_dir():
        print(f"ERROR: {target} is not a directory", file=sys.stderr)
        return 1

    count = 0
    for path in sorted(target.rglob("*")):
        if path.is_dir():
            continue
        rel = path.relative_to(target)
        print(f"{rel}|{path.stat().st_size}|{sha256_of(path)}")
        count += 1

    print(f"{count} file(s) under {target}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
