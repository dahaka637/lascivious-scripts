# Translation PT-BR — Improvised Silencers

> **Atualização 2026-08-26 — Sandbox completo:** as 23 chaves agora têm JSON PT-BR e
> `Sandbox_PTBR.txt` nativo ASCII-safe. A situação das demais famílias não mudou. Esta nota
> substitui somente as afirmações históricas abaixo sobre o sandbox permanecer em inglês.

**Parcial.**

- `42/mod.info`'s `description=` está em PT-BR (seguro — parseado em Java, não Kahlua).
- As 41 strings nativas (`Sandbox_EN.txt`: 23, `ItemName_EN.txt`: 5, `Recipes_EN.txt`: 5,
  `Tooltip_EN.txt`: 8) agora têm arquivo nativo, mas ficam em inglês — sem versão PT-BR nativa,
  mesma limitação já aceita no resto do pacote (texto acentuado quebra o loader nativo de `.txt`,
  vira "?"; ver [[feedback-ptbr-accents-in-lua]]).
- O upstream já tinha `Translate/PTBR/{ItemName,Recipes,Tooltip}.json` completo e correto
  (preservado no bundle, igual aos outros 7 idiomas) — não promovido a nativo pelo mesmo motivo
  acima. Não existe `Sandbox.json` em PT-BR no upstream (nem em nenhum outro idioma além de EN) —
  nada a preservar por fidelidade nesse arquivo específico.
