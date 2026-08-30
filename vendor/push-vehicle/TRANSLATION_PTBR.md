# Translation PT-BR — Push Vehicle

> **Atualização 2026-08-26 — Sandbox completo:** as 3 chaves agora têm JSON PT-BR e
> `Sandbox_PTBR.txt` nativo ASCII-safe. A situação das demais famílias não mudou. Esta nota
> substitui somente as afirmações históricas abaixo sobre o sandbox permanecer em inglês.

**Parcial.**

- `42/mod.info`'s `description=` está em PT-BR (seguro — parseado em Java, não Kahlua).
- A sandbox option e os dois textos de UI (rótulo da ação, rótulo do keybind) agora têm
  `Sandbox_EN.txt`/`UI_EN.txt` nativos (ver LOCAL_CHANGES LS-001/LS-002), mas ficam em inglês — sem
  `Sandbox_PTBR.txt`/`UI_PTBR.txt`, mesma limitação já aceita no resto do pacote (texto acentuado
  quebra o loader nativo de `.txt`, vira "?"; ver [[feedback-ptbr-accents-in-lua]] e
  [[feedback-sandbox-options-native-txt-required]]).
- Nenhum item novo, nenhuma UI custom desenhada em Lua — não há mais texto exposto ao jogador além
  do já coberto acima.
