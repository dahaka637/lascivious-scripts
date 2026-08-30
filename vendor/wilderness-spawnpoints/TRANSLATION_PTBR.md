# Wilderness Spawnpoints — PTBR Coverage

Status: complete.

- 29/29 `title.txt` files translated and reviewed.
- 29/29 `description.txt` files translated and reviewed.
- 29/29 `map.info` files point to the matching namespaced EN fallback; each PTBR file mirrors the
  same relative path under `Translate/PTBR`, as required by the map-selection localizer.
- Wording, difficulty labels, spacing and display markup were normalized.

The engine reads these files as direct map-selection metadata, so they intentionally contain plain UTF-8 text rather than Lua `getText()` tables.
