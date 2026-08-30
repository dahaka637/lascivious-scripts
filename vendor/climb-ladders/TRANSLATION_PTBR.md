# Translation PT-BR — Climb Ladders

**Parcial.**

- `42/mod.info`'s `description=` está em PT-BR (seguro — parseado em Java, não Kahlua).
- As 10 strings de menu de contexto/mensagens/keybind agora têm arquivos nativos EN (ver
  LOCAL_CHANGES LS-001), mas ficam em inglês — sem versão PT-BR nativa, mesma limitação já aceita no
  resto do pacote (texto acentuado quebra o loader nativo de `.txt`, vira "?"; ver
  [[feedback-ptbr-accents-in-lua]]).
- O upstream já tinha um `Translate/PTBR/*.json` completo e correto (preservado no bundle, igual aos
  outros 9 idiomas) — não promovido a nativo pelo mesmo motivo acima, igual ao caso do
  `immersive-suicide`.
