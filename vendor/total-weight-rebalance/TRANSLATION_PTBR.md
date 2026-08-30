# Translation PT-BR — Total Weight Rebalance

> **Atualização 2026-08-26 — Sandbox completo:** as 3 chaves agora têm JSON PT-BR e
> `Sandbox_PTBR.txt` nativo ASCII-safe. A situação do menu externo ao sandbox não mudou. Esta nota
> substitui somente as afirmações históricas abaixo sobre o sandbox permanecer em inglês.

**Parcial.**

- `42/mod.info`'s `description=` está em PT-BR (seguro — parseado em Java, não Kahlua).
- A única sandbox option (`TotalWeightRebalance.CustomWeights`) agora tem `Sandbox_EN.txt` nativo
  (ver LOCAL_CHANGES LS-001), mas fica em inglês — sem `Sandbox_PTBR.txt`, mesma limitação já aceita
  no resto do pacote (texto acentuado quebra o loader nativo de `.txt`, vira "?"; ver
  [[feedback-ptbr-accents-in-lua]]). O upstream nem tinha um `Sandbox.json` em PT-BR pra começo de
  conversa — só as famílias `Entity`/`IG_UI`/`Tooltip`, que este mod nem usa (ver `LOCAL_CHANGES.md`).
- O rótulo "Set Weight" do menu de contexto é uma string literal em inglês no próprio Lua, não uma
  chave de tradução — preservado como está.
- Nenhum item novo — os 1616 itens rebalanceados mantêm seus nomes/traduções vanilla originais,
  já cobertos pelo PT-BR nativo do próprio jogo.
