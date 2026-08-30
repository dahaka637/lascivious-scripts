# Translation PT-BR — Better Engine Repair

> **Atualização 2026-08-26 — Sandbox completo:** as 23 chaves agora têm JSON PT-BR e
> `Sandbox_PTBR.txt` nativo ASCII-safe. Esta nota substitui as afirmações históricas abaixo sobre o
> sandbox permanecer em inglês.

**Parcial.**

- `42/mod.info`'s `description=` está em PT-BR (seguro — parseado em Java, não Kahlua).
- As 11 sandbox options (`BetterEngineRepair.Mechanics0`..`Mechanics10`) já tinham `Sandbox_EN.txt`
  nativo correto vindo do upstream (raro entre os mods integrados até agora — a maioria precisou de
  correção). Ficam em inglês — sem `Sandbox_PTBR.txt`, mesma limitação já aceita no resto do pacote
  (texto acentuado quebra o loader nativo de `.txt`, vira "?"; ver
  [[feedback-ptbr-accents-in-lua]] e [[feedback-sandbox-options-native-txt-required]]).
- `Sandbox_RU.txt` (russo) também veio do upstream e foi mantido — não afeta PT-BR de forma alguma.
- Nenhum item novo, nenhuma UI própria — não há mais texto exposto ao jogador além do já coberto
  acima.
