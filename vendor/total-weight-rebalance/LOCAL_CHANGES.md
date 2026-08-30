# Local Changes — Total Weight Rebalance

## LS-003
Tipo: tradução PT-BR de sandbox
Arquivos: `42/media/lua/shared/Translate/PTBR/{Sandbox.json,Sandbox_PTBR.txt}`
Mudança: adicionadas as 3 chaves PT-BR completas; o TXT nativo usa escapes decimais ASCII-safe.
Validação: paridade 3/3 com EN, sintaxe Lua 5.1 e reconstrução UTF-8 exata.

## LS-001
Tipo: tradução / correção de bug
Arquivo novo: `42/media/lua/shared/Translate/EN/Sandbox_EN.txt`
Motivo: upstream só tinha `Translate/EN/Sandbox.json`, que nada no mod lê (painel nativo de Sandbox
Options só lê `.txt`). Sem esse arquivo, a única opção do mod (`TotalWeightRebalance.CustomWeights`)
apareceria com a chave crua em vez do texto real.
Mudança: criado `Sandbox_EN.txt` com as 3 chaves já presentes em `Sandbox.json`, texto idêntico.

## LS-002
Tipo: bundling / identidade do mod
Arquivo: `42/mod.info`
Motivo: rebrand para o namespace do pacote (mod não faz nenhum check do próprio Mod ID — Categoria A,
seção 20 da arquitetura).
Mudança: `id=TotalWeightRebalance` -> `id=LS_TotalWeightRebalance`; `name=`/`description=`
reescritos. `versionMin=42.0` e `modversion=1.2` preservados do upstream.

## Achado sem ação — traduções Entity/IG_UI/Tooltip não usadas pelo mod

`Translate/<LANG>/{Entity,IG_UI,Tooltip}.json` (9 idiomas) contêm chaves com cara de rótulo nativo
do vanilla (`EC_Weight`, `IGUI_invpanel_weight`, `Tooltip_item_Weight` etc.), mas nenhum código deste
mod chama `getText()` nelas — o rótulo "Set Weight" do menu de contexto é uma string literal, não
uma chave de tradução. Não promovidas para `.txt` nativo de propósito: fazer isso faria este bundle
passar a sobrescrever rótulos genéricos do próprio vanilla ("Weight", "Stack Weight" etc.) em todo o
jogo, o que está fora do escopo deste mod e não foi pedido. Mantidas como estão, inertes.

## Itens sem alteração

Os dois arquivos de tabela de peso (`weights_vanilla.lua`, 1616 itens; `weights_mods.lua`, 3 mods
opcionais), `apply_weights.lua`, `SetWeightContextMenu.lua`, `sandbox-options.txt`, `icon.png`, os 4
pôsteres e os JSONs de todos os idiomas são cópias byte-a-byte do upstream — confirmado via `diff`/
`diff -rq`. **Nenhuma correção de segurança/autoridade foi necessária** — cliente e servidor já
validam nível de admin independentemente antes de qualquer mudança de peso; ver `INTEGRATION.md`.

## Perguntas para revisitar em updates futuros

- Cada entrada de `weights_vanilla.lua` já vem comentada com o valor vanilla original
  (`-- pesoOriginal`), o que facilita comparar contra uma atualização do jogo — usar isso em vez de
  `tools/hash_module.py` para essa checagem específica.
