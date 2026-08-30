# Translation PT-BR — Clean HotBar

**Parcial.**

- `42/mod.info`'s `description=` está em PT-BR (seguro — parseado em Java, não Kahlua).
- As 7 strings de `IG_UI_EN.txt` (recriado, ver `LOCAL_CHANGES.md` LS-001) ficam em inglês — sem
  versão PT-BR nativa, mesma limitação já aceita no resto do pacote (texto acentuado quebra o
  loader nativo de `.txt`, vira "?"; ver [[feedback-ptbr-accents-in-lua]]).
- O upstream já tinha um `Translate/PTBR/IG_UI.json` completo e correto (preservado no bundle, igual
  aos outros 14 idiomas) — não promovido a nativo pelo mesmo motivo acima, igual ao caso de vários
  outros módulos deste pacote.
