# Local Changes — Push Vehicle

## LS-004
Tipo: tradução PT-BR de sandbox
Arquivos: `42/media/lua/shared/Translate/PTBR/{Sandbox.json,Sandbox_PTBR.txt}`
Mudança: adicionadas as 3 chaves PT-BR completas; o TXT nativo usa escapes decimais ASCII-safe.
Validação: paridade 3/3 com EN, sintaxe Lua 5.1 e reconstrução UTF-8 exata.

## LS-001
Tipo: tradução / correção de bug
Arquivo novo: `42/media/lua/shared/Translate/EN/Sandbox_EN.txt`
Motivo: mesmo gap já visto em `zombie-decay` e `simple-belt-flashlight` — upstream só tinha
`Translate/EN/sandbox.json`, que nada no mod lê. A tela nativa de Sandbox Options mostraria a chave
crua em vez do texto da única opção (`PushVehicle.AllowSidePushing`).
Mudança: criado `Sandbox_EN.txt` com as 3 chaves já presentes em `sandbox.json`, texto idêntico.

## LS-002
Tipo: tradução / correção de bug (mais sério que LS-001)
Arquivo novo: `42/media/lua/shared/Translate/EN/UI_EN.txt`
Motivo: `UI.json` do upstream também não é lido por nenhum código — `getText()` nativo só lê
`UI_<LANG>.txt`. Isso significa que `getText("UI_PushVehicle_Action")`, usado no rótulo do menu de
contexto, na tooltip e na fatia do menu radial (os três lugares onde o jogador realmente clica),
não tinha texto nenhum por trás — nem em inglês. Sem esse arquivo, o próprio nome da ação do mod
apareceria como a chave crua `UI_PushVehicle_Action` no jogo.
Mudança: criado `UI_EN.txt` com as 2 chaves já presentes em `UI.json`
(`UI_optionscreen_binding_PushVehicle_Hotkey`, `UI_PushVehicle_Action`), texto idêntico.

## LS-003
Tipo: bundling / identidade do mod
Arquivo: `42/mod.info`
Motivo: rebrand para o namespace do pacote (mod não faz nenhum check do próprio Mod ID — Categoria A,
seção 20 da arquitetura).
Mudança: `id=PushVehicle` -> `id=LS_PushVehicle`; `name=`/`description=` reescritos;
`versionMin=42.20` e `modversion=1.0.0` adicionados (upstream não declarava nenhum dos dois, embora
os dois arquivos Lua já dissessem "Build 42.20" nos próprios comentários de cabeçalho).

## Itens sem alteração

Os dois arquivos Lua (`PushVehicle_ContextMenu.lua`, `PushVehicle_Server.lua`) e
`sandbox-options.txt` são cópias byte-a-byte do upstream — confirmado via `diff`. **Nenhuma correção
de segurança/autoridade foi necessária** — o lado servidor já revalida tudo (distância, velocidade
do veículo, resistência do jogador, se side-push está habilitado) de forma independente do cliente;
ver `INTEGRATION.md` para o detalhamento.

## Perguntas para revisitar em updates futuros

- Reconferir se o upstream adiciona um `UI_EN.txt`/`Sandbox_EN.txt` próprios numa atualização futura
  — se sim, LS-001/LS-002 podem ficar redundantes (comparar antes de remover).
- Se algum mod novo bundlado também mexer em `ISVehicleMenu.showRadialMenuOutside`, checar
  `docs/COLLISION_REGISTRY.md` antes de integrar.
