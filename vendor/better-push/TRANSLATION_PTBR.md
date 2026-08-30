# Translation PT-BR — Better Push

> **Atualização 2026-08-26 — Sandbox completo:** as 17 chaves agora têm JSON PT-BR e
> `Sandbox_PTBR.txt` nativo ASCII-safe. Esta nota substitui as afirmações históricas abaixo sobre o
> sandbox permanecer em inglês.

**Parcial.**

- `42/mod.info`'s `description=` está em PT-BR (seguro — parseado em Java, não Kahlua).
- As 8 sandbox options agora têm `Sandbox_EN.txt` nativo (ver LOCAL_CHANGES LS-003), mas ficam em
  inglês — sem `Sandbox_PTBR.txt`, mesma limitação já aceita no resto do pacote (texto acentuado
  quebra o loader nativo de `.txt`, vira "?"; ver [[feedback-ptbr-accents-in-lua]]). O upstream nem
  tinha JSON em PT-BR para começo de conversa.
- Nenhum item novo, nenhuma UI própria além do console log de debug (`print`, não visível ao
  jogador comum) — não há mais texto exposto ao jogador além do já coberto acima.
