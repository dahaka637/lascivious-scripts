# Local Changes — Drag Bodies Faster (80%)

## LS-001
Tipo: bundling / identidade do mod
Arquivo: `42/mod.info`
Motivo: rebrand para o namespace do pacote (mod não tem nenhum código Lua, logo nenhum check do
próprio Mod ID — Categoria A, seção 20 da arquitetura).
Mudança: `id=DBFaster80` -> `id=LS_DragBodiesFaster`; `name=`/`description=` reescritos;
`versionMin=42.20` e `modversion=1.0.0` adicionados (upstream não declarava nenhum dos dois).
`incompatible=\DBFaster25,\DBFaster50,\DBFaster60,\DBFaster70` removido — ver justificativa em
`INTEGRATION.md`.

## Itens sem alteração

Os 12 arquivos XML de AnimSets são cópias byte-a-byte da variante 80% do upstream — confirmado via
`diff -rq`. `icon.png`/`poster.png` também idênticos.

## Perguntas para revisitar em updates futuros

- Se o upstream atualizar os valores de `m_SpeedScale` de qualquer uma das 5 variantes, reconferir
  a tabela em `INTEGRATION.md` (ela documenta os 5 tiers, não só o 80% bundlado).
- Se algum jogador reportar ter a versão standalone (qualquer tier) deste mod ativa junto do
  servidor, revisar a decisão de não preservar `incompatible=`.
