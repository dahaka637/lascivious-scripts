# Translation PT-BR — Proximity Inventory

> **Atualização 2026-08-26 — Sandbox completo:** as 3 chaves agora têm JSON PT-BR e
> `Sandbox_PTBR.txt` nativo ASCII-safe. A situação das demais famílias não mudou. Esta nota
> substitui somente as afirmações históricas abaixo sobre o sandbox permanecer em inglês.

Não aplicável. O upstream não shippa nenhum idioma PT-BR (só CN/EN/ES/FR/IT/TR/UA) — não há nada
para preservar por fidelidade. A `description=` do próprio `42/mod.info` está em PT-BR (seguro —
parseado em Java, não Kahlua). O restante do texto (Sandbox/UI/IG_UI) fica em inglês nativo, mesma
limitação já aceita no resto do pacote (texto acentuado quebra o loader nativo de `.txt`, vira "?";
ver [[feedback-ptbr-accents-in-lua]]) — com a diferença de que aqui não havia sequer um JSON PT-BR
upstream para cross-referenciar, então mesmo se a limitação não existisse não haveria texto
PT-BR pronto para promover.
