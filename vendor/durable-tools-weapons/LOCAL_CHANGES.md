# Local Changes — Durable Tools and Weapons (Hardened)

## LS-001
Tipo: bundling / identidade do mod
Arquivo: `42/mod.info`
Motivo: rebrand para o namespace do pacote (mod não faz nenhum check do próprio Mod ID — Categoria A,
ver seção 20 da arquitetura).
Mudança: `id=DTWhard` -> `id=LS_DurableToolsWeapons`; `name=` e `description=` reescritos para o
padrão do pacote; `modversion=1.0.0` adicionado (upstream não declarava versão).

## LS-002
Tipo: estrutura
Arquivo: layout do submod inteiro
Motivo: adequar à estrutura canônica `common/` + `42/` deste projeto (seção 3/4 da arquitetura).
Mudança: descartada a cópia legada no nível raiz (`mods/DTW_hard/{mod.info,media/,icon.png,
poster.png}`) e o `common/` original (que só tinha `mod.info`/`icon.png`/`poster.png` duplicados,
sem `media/`). Ficou apenas `42/` com o conteúdo funcional, mais um `common/media/` vazio próprio
deste pacote.

## LS-003

Tipo: compatibilidade / ressincronização de full redeclaration  
Arquivos: os 10 `42/media/scripts/vanilla_items_*.txt`  
Motivo: na revisão pré-release da 42.20.4, todos os 351 blocos upstream estavam defasados fora de
durabilidade e revertiam campos atuais do vanilla.  
Mudança: cada bloco foi reconstruído do vanilla exato da 42.20.4, reaplicando exclusivamente os
valores upstream de `ConditionMax`/`ConditionLowerChanceOneIn`. Validação mecanizada: 351/351
iguais ao vanilla ignorando esses campos e 351/351 iguais ao upstream nesses campos.

O snapshot em `upstream/` permanece prístino; a árvore bundled deixa deliberadamente de ser
byte-a-byte igual a ele a partir de LS-003.

## Perguntas para revisitar em updates futuros

- **O upstream ainda não versiona (`modversion=` ausente no `mod.info` original).** Ao buscar uma
  atualização, comparar `vendor/durable-tools-weapons/upstream/` inteiro via
  `tools/hash_module.py` em vez de confiar em número de versão.
- Reexecutar a comparação dos 351 itens a cada atualização do jogo; qualquer drift fora dos dois
  campos de durabilidade exige nova ressincronização (ver "Known update risk" em `INTEGRATION.md`).
