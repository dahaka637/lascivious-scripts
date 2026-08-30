# Translation PT-BR — Antibodies

> **Atualização 2026-08-26 — Sandbox completo no jogo:** as 149 chaves agora também estão em
> `Sandbox_PTBR.txt` nativo ASCII-safe. A situação das demais famílias não mudou. Esta nota
> substitui somente as afirmações históricas abaixo sobre o sandbox permanecer em inglês.

**Parcial no jogo; completa como catálogo JSON.**

- `42/mod.info` possui descrição PT-BR.
- Criados `PTBR/UI.json` (85/85 chaves contra EN) e `PTBR/Sandbox.json` (149/149), ambos válidos e
  com todos os placeholders `%1`/`%2` preservados.
- A UI e o painel de sandbox usam `getText()`, que neste ambiente do PZ só carrega as tabelas
  nativas `.txt`. Por isso foram mantidos fallbacks nativos EN válidos e completos; não foi criado
  `.txt` PT-BR, seguindo a limitação já confirmada de acentuação do projeto.
- O catálogo PT-BR fica preservado para uso futuro quando houver um caminho seguro de exibição sem
  corromper acentos.
