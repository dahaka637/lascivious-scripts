# Translation PT-BR — Burris Quality of Life

> **Atualização 2026-08-26 — Sandbox completo:** as 108 chaves agora têm JSON PT-BR e
> `Sandbox_PTBR.txt` nativo ASCII-safe. A situação das demais famílias não mudou. Esta nota
> substitui somente as afirmações históricas abaixo sobre o sandbox permanecer em inglês.

**Parcial.**

- `42/mod.info`'s `description=` está em PT-BR (seguro — parseado em Java, não Kahlua).
- As strings nativas (6 arquivos: `Sandbox_EN.txt`, `ContextMenu_EN.txt`, `IG_UI_EN.txt`,
  `ItemName_EN.txt`, `Recipes_EN.txt`, `Tooltip_EN.txt`, ver `LOCAL_CHANGES.md` LS-005) ficam em
  inglês — sem versão PT-BR nativa, mesma limitação já aceita no resto do pacote (texto acentuado
  quebra o loader nativo de `.txt`, vira "?"; ver [[feedback-ptbr-accents-in-lua]]).
- O upstream não shippa nenhum idioma além de EN para este mod (nem JSON) — nada a preservar por
  fidelidade em nenhum outro idioma.
