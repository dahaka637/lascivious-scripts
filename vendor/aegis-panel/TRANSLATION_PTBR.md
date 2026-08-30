# Translation PT-BR — Aegis Panel

> **Atualização 2026-08-26 — Sandbox completo:** as 67 chaves de sandbox agora também estão em
> `Sandbox_PTBR.txt` nativo ASCII-safe. A situação das demais famílias não mudou. Esta nota
> substitui somente as afirmações históricas abaixo sobre o sandbox permanecer em inglês.

**Parcial.**

- `42/mod.info`'s `description=` está em PT-BR (seguro — parseado em Java, não Kahlua).
- O upstream shippa PT-BR completo em JSON para as 2 famílias (`Sandbox`, `UI`) — 1092/1092 chaves,
  key-complete contra o EN (comparação byte-exata do conjunto de chaves, 0 faltando/sobrando/vazias),
  JSON bem-formado. Tradução natural genuína (não é cópia do EN nem stub): 507 das 1092 strings
  (~46%) contêm acentuação PT-BR real (ex.: `"UI_Aegis_NavDashboard": "Visão geral"`,
  `"UI_Aegis_GroupCrafting": "Fabricação e construção"`). Preservado no vendor snapshot e no bundle
  para referência futura.
- As strings nativas (2 arquivos: `Sandbox_EN.txt`, `UI_EN.txt`, ver `LOCAL_CHANGES.md` LS-001) ficam
  em inglês — sem versão PT-BR nativa. Com 507 de 1092 valores acentuados, uma transcrição nativa
  quebraria exatamente no bug "?" já documentado em [[feedback-ptbr-accents-in-lua]], mesma limitação
  já aceita no resto do pacote.
- Sistema separado, não afetado por nada acima: `AegisHelpContent.lua` (o manual interno do painel,
  não as ~1092 strings de UI/sandbox) só mantém blocos `.DE`/`.EN` com fallback para inglês nos outros
  11 idiomas, incluindo PT-BR — já era assim no upstream, fora do escopo desta integração.
