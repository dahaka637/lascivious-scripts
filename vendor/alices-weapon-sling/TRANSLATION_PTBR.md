# Translation PT-BR — Alice's Weapon Sling

**Parcial.**

- `42/mod.info`'s `description=` está em PT-BR (seguro — parseado em Java, não Kahlua).
- As 19 strings nativas (`ContextMenu_EN.txt`: 10, `ItemName_EN.txt`: 4, `Recipes_EN.txt`: 1,
  `UI_EN.txt`: 4) mais a nova `Tooltip_EN.txt` (1) agora têm arquivo nativo, mas ficam em inglês —
  sem versão PT-BR nativa, mesma limitação já aceita no resto do pacote (texto acentuado quebra o
  loader nativo de `.txt`, vira "?"; ver [[feedback-ptbr-accents-in-lua]]).
- O upstream já tinha um `Translate/PTBR/{ContextMenu,ItemName,Recipes}.json` completo e correto
  (preservado no bundle, igual aos outros 9 idiomas) — não promovido a nativo pelo mesmo motivo
  acima, igual ao caso do `immersive-suicide`/`climb-ladders`.
- `Tooltip_Sling` não existia em PT-BR (nem em nenhum outro idioma) no upstream — texto novo criado
  só em EN (ver `LOCAL_CHANGES.md` LS-002), sem fonte PT-BR upstream para preservar.
