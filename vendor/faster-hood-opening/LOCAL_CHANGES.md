# Local Changes — Faster Hood Opening

## LS-001
Tipo: bundling / identidade do mod
Arquivo: `42/mod.info`
Motivo: rebrand para o namespace do pacote (mod não faz nenhum check do próprio Mod ID — Categoria A,
seção 20 da arquitetura).
Mudança: `id=FasterHoodOpening` -> `id=LS_FasterHoodOpening`; `name=`/`description=` reescritos;
`modversion=1.0.0` e `versionMin=42.20` adicionados (upstream não declarava nenhum dos dois).

## LS-002
Tipo: estrutura
Arquivo: layout do submod inteiro
Motivo: adequar à estrutura canônica `common/` + `42/` deste projeto.
Mudança: descartada a cópia legada no nível raiz (`mods/Faster Hood Opening/{mod.info,media/,
poster.png}`) e o `common/` original (vazio). Ficou só `42/` com o conteúdo funcional, mais um
`common/media/` vazio próprio deste pacote.

## Itens sem alteração

`ISOpenMechanicsUIAction.lua` é cópia byte-a-byte do upstream — a única diferença de comportamento
(base de `maxTime` 200 -> 22) já é o próprio conteúdo do mod, não uma alteração nossa. Ver
`INTEGRATION.md` para o diff completo contra o vanilla confirmado.

## Perguntas para revisitar em updates futuros

- Sem `versionMin`/`versionMax` no upstream — reconferir manualmente contra uma instalação vanilla
  atual a cada atualização do jogo (foi assim que esta integração foi validada, ver
  `INTEGRATION.md`), já que não há sinal automático de incompatibilidade de build.
