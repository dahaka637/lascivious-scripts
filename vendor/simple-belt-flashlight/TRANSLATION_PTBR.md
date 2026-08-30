# Translation PT-BR — Simple Belt Flashlight+

> **Atualização 2026-08-26 — Sandbox completo:** as 3 chaves agora têm JSON PT-BR e
> `Sandbox_PTBR.txt` nativo ASCII-safe. Esta nota substitui as afirmações históricas abaixo sobre o
> sandbox permanecer em inglês.

**Parcial.**

- `42/mod.info`'s `description=` está em PT-BR (seguro — parseado em Java, não Kahlua).
- A única sandbox option (`SBFPlus.DebugLogging`) agora tem `Sandbox_EN.txt` nativo (ver
  LOCAL_CHANGES LS-001) mas **não** tem um `Sandbox_PTBR.txt` — mesma limitação já aceita no resto
  do pacote (texto acentuado quebra o loader nativo de `.txt`, vira "?"; ver
  [[feedback-ptbr-accents-in-lua]] e [[feedback-sandbox-options-native-txt-required]]). A opção
  aparece em inglês na tela nativa de Sandbox Options até esse limite técnico ser resolvido de
  verdade (exigiria um hook próprio, não construído em nenhum lugar deste pacote ainda).
- Nenhum item novo, nenhuma UI própria — não há mais nenhum texto exposto ao jogador além do
  já coberto acima.
