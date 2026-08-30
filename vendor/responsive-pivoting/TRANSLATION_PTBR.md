# Translation PT-BR — Responsive Pivoting

> **Atualização 2026-08-26 — Sandbox completo:** as 47 chaves agora têm JSON PT-BR e
> `Sandbox_PTBR.txt` nativo ASCII-safe. A situação dos textos dos traços não mudou. Esta nota
> substitui somente as afirmações históricas abaixo sobre o sandbox permanecer em inglês.

**Parcial.**

- `42/mod.info`'s `description=` está em PT-BR (seguro — parseado em Java, não Kahlua).
- As opções de sandbox e os textos dos dois traits novos ("On Your Toes"/"Under the Influence")
  agora têm `Sandbox_EN.txt`/`UI_EN.txt`/`IGUI_EN.txt` nativos (ver LOCAL_CHANGES LS-001), mas ficam
  em inglês — sem versão PT-BR nativa, mesma limitação já aceita no resto do pacote (texto acentuado
  quebra o loader nativo de `.txt`, vira "?"; ver [[feedback-ptbr-accents-in-lua]]). O upstream nem
  tinha JSON em PT-BR para começo de conversa (só EN em ambas as pastas).
- Nomes/descrições dos dois traits ("On Your Toes", "Under the Influence") ficam em inglês na tela
  de criação de personagem por conta dessa mesma limitação.
