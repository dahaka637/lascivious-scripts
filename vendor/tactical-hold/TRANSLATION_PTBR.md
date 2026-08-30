# Translation PT-BR — Tactical Hold

> **Atualização 2026-08-26 — Sandbox completo:** as 5 chaves agora têm JSON PT-BR e
> `Sandbox_PTBR.txt` nativo ASCII-safe. A situação do painel externo ao sandbox não mudou. Esta nota
> substitui somente as afirmações históricas abaixo sobre o sandbox permanecer em inglês.

**Parcial.**

- `42/mod.info`'s `description=` está em PT-BR (seguro — parseado em Java, não Kahlua).
- As 5 strings de `Sandbox_EN.txt` (ver `LOCAL_CHANGES.md` LS-001) ficam em inglês — sem versão
  PT-BR nativa, mesma limitação já aceita no resto do pacote (texto acentuado quebra o loader nativo
  de `.txt`, vira "?"; ver [[feedback-ptbr-accents-in-lua]]).
- O upstream não shippa nenhum idioma além de EN para este mod — nada a preservar por fidelidade.
- Os rótulos do painel `PZAPI.ModOptions` ("Tactical hold", "HighReady", "Low Ready", "GunResting",
  "Vanilla", "Cycle animation Key") são strings literais fixas em inglês no Lua, não roteadas por
  `getText()` — mesma limitação/decisão já aplicada em `osrs-experience-bar`/`mini-health-panel`
  (ver aqueles `INTEGRATION.md` para o motivo).
