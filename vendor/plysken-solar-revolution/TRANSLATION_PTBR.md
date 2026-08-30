# Translation PT-BR — Plysken Solar Revolution

> **Atualização 2026-08-26 — Sandbox completo no jogo:** as 47 chaves agora também estão em
> `Sandbox_PTBR.txt` nativo ASCII-safe. A situação das demais famílias não mudou. Esta nota
> substitui somente as afirmações históricas abaixo sobre o sandbox permanecer em inglês.

**Parcial.**

- `42/mod.info`'s `description=` está em PT-BR (seguro — parseado em Java, não Kahlua).
- O upstream shippa PT-BR completo em JSON para as 7 famílias (`ContextMenu`, `IG_UI`, `ItemName`,
  `Moveables`, `Recipes`, `Sandbox`, `Tooltip`) — 210/210 chaves, key-complete contra o EN, JSON
  bem-formado. Preservado no vendor snapshot para referência futura.
- As strings nativas (7 arquivos: `ContextMenu_EN.txt`, `IG_UI_EN.txt`, `ItemName_EN.txt`,
  `Moveables_EN.txt`, `Recipes_EN.txt`, `Sandbox_EN.txt`, `Tooltip_EN.txt`, ver `LOCAL_CHANGES.md`
  LS-001) ficam em inglês — sem versão PT-BR nativa. O PT-BR JSON contém acentuação em 83 das 210
  chaves (ã, é, ç, etc.) — uma transcrição nativa quebraria exatamente no bug "?" já documentado em
  [[feedback-ptbr-accents-in-lua]], mesma limitação já aceita no resto do pacote.
- Sem hook de UI customizada neste módulo (é 100% telas nativas do PZ — Sandbox Options, tooltip,
  menu de contexto, nomes de item/receita), então não há caminho alternativo via `getText()` próprio
  para expor o PT-BR sem esbarrar no bug de acentuação.
