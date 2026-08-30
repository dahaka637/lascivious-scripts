# Local Changes — Better Corpse Burning

## LS-001
Tipo: bundling / identidade
Arquivo: `42/mod.info` e estrutura do submod
Motivo: adequar o módulo ao pacote único e ao layout canônico `common/` + `42/`.
Mudança: Mod ID `BetterCorpseBurning` renomeado para `LS_BetterCorpseBurning`, nome e descrição
adaptados e `modversion` incrementado de `1.11` para `1.11.1`. O namespace de sandbox
`BetterCorpseBurning`, o namespace de rede `BCB` e o tipo `BCB_ISBCBBurnAction` foram preservados.

## LS-002
Tipo: segurança / autoridade multiplayer
Arquivos: `42/media/lua/client/BetterCorpseBurning/bcb_actions.lua` e
`42/media/lua/server/BetterCorpseBurning/bcb_server.lua`
Motivo: o upstream consumia a fonte de fogo e a gasolina no cliente, aceitava coordenadas e raio de
propagação sem validação e iniciava fogo no servidor sem comprovar distância, cadáver ou recursos.
Um cliente modificado podia iniciar incêndios arbitrários e enviar um raio sem limite.
Mudança: no multiplayer o cliente envia somente coordenadas inteiras. O servidor re-resolve o
quadrado e o cadáver, limita a distância ao mesmo máximo de 1,8 quadrado usado pelo pacote vanilla
`BurnCorpse`, exige o mesmo nível Z, rejeita cadáver ausente/em chamas e valida fonte de fogo,
gasolina e ambiente antes de consumir os recursos autoritativamente. O raio vem exclusivamente da
opção de sandbox do servidor e é limitado a 0–5. Single-player conserva execução local.

## LS-003
Tipo: estabilidade / compatibilidade
Arquivo: `42/media/lua/server/BetterCorpseBurning/bcb_server.lua`
Motivo: a propagação podia enfileirar o mesmo quadrado várias vezes; dois helpers também vazavam
como globals Lua genéricos. Além disso, a queima direta poderia atravessar as regras de fogo do
servidor e as zonas `nofire` do Lascivious Systems.
Mudança: quadrados de propagação agora têm chave de deduplicação; `onSpreadTick` e `findFireItem`
ficaram locais; logs de sucesso por quadrado foram removidos; solicitações e propagação respeitam
`NoFire`, `SafehouseAllowFire` e `PhunZones.getLocation(...).nofire`. A busca de gasolina passou a
incluir containers internos tanto no cliente quanto no servidor.

## LS-004
Tipo: tradução
Arquivos: `42/media/lua/shared/Translate/{EN,PTBR}/`
Motivo: o upstream trazia somente catálogos JSON; `getText()` e a tela nativa de Sandbox precisam
das tabelas `.txt`. O tooltip de `TimePerCorpse` também dizia incorretamente que o valor era em
minutos do jogo, embora seja duração da TimedAction.
Mudança: adicionadas tabelas nativas EN/PTBR para 1 texto de interface e 21 textos de sandbox;
catálogo PT-BR revisado e tooltip corrigido nos dois idiomas. A tabela PT-BR nativa usa escapes
decimais ASCII-safe.

## LS-005
Tipo: higiene do pacote
Arquivo: `42/media/lua/shared/Translate/UA/Sandbox.json.tmp`
Motivo: o upstream distribuía uma cópia temporária do catálogo ucraniano, idêntica ao arquivo
preservado no snapshot e sem função em runtime.
Mudança: o arquivo `.tmp` foi omitido somente do submod empacotado para não publicar artefatos
temporários. O snapshot upstream permanece byte-a-byte intacto.

## Upstream preservado

`vendor/better-corpse-burning/upstream/42/` é uma cópia byte-a-byte dos 125 arquivos importados.
As alterações acima existem somente em `Contents/mods/LS_BetterCorpseBurning/`.
