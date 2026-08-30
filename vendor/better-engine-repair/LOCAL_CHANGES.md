# Local Changes — Better Engine Repair

## LS-002
Tipo: tradução PT-BR de sandbox
Arquivos: `42/media/lua/shared/Translate/PTBR/{Sandbox.json,Sandbox_PTBR.txt}`
Mudança: adicionadas as 23 chaves PT-BR completas; o TXT nativo usa escapes decimais ASCII-safe.
Validação: paridade 23/23 com EN, sintaxe Lua 5.1 e reconstrução UTF-8 exata.

## LS-001
Tipo: bundling / identidade do mod
Arquivo: `42/mod.info`
Motivo: rebrand para o namespace do pacote (mod não faz nenhum check do próprio Mod ID — Categoria A,
seção 20 da arquitetura).
Mudança: `id=BetterEngineRepairB42` -> `id=LS_BetterEngineRepair`; `name=`/`description=`
reescritos; `versionMin=42.20` e `modversion=1.0.0` adicionados (upstream não declarava nenhum dos
dois, embora o comentário do próprio Lua já dissesse "B42.20.x").

## Itens sem alteração

Todo o código Lua, `sandbox-options.txt` e os dois arquivos de tradução nativos (`Sandbox_EN.txt`,
`Sandbox_RU.txt`) são cópias byte-a-byte do upstream — confirmado via `diff`. **Nenhuma mudança de
lógica foi necessária ou aplicada.** Ver `INTEGRATION.md` para a comparação linha a linha contra o
`ISRepairEngine.lua` vanilla instalado localmente, que confirma que a única diferença de
comportamento real é a fórmula de `condPerPart` — todo o resto (remoção de item, XP, sync de rede)
é idêntico ao vanilla.

## Perguntas para revisitar em updates futuros

- Se uma atualização do PZ mudar a assinatura ou estrutura interna de `ISRepairEngine:complete()`,
  reconferir contra a instalação vanilla local (mesma técnica usada nesta integração) antes de
  aceitar uma atualização do upstream.
