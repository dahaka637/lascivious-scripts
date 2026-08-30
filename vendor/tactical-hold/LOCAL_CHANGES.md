# Local Changes — Tactical Hold

## LS-003
Tipo: tradução PT-BR de sandbox
Arquivos: `42/media/lua/shared/Translate/PTBR/{Sandbox.json,Sandbox_PTBR.txt}`
Mudança: adicionadas as 5 chaves PT-BR completas; o TXT nativo usa escapes decimais ASCII-safe.
Validação: paridade 5/5 com EN, sintaxe Lua 5.1 e reconstrução UTF-8 exata.

## LS-001
Tipo: tradução / correção de bug
Arquivo novo: `42/media/lua/shared/Translate/EN/Sandbox_EN.txt`
Motivo: upstream só tinha `Sandbox.json`, que a tela nativa de Sandbox Options nunca lê — mesmo bug
recorrente já corrigido em quase todo o resto do pacote.
Mudança: criado o arquivo nativo com as 5 chaves (título de página + 2 opções × rótulo/tooltip) já
com o texto correto do EN JSON.

## LS-002
Tipo: bundling / identidade do mod
Arquivo: `42/mod.info`
Motivo: rebrand para o namespace do pacote (mod não faz nenhum check do próprio Mod ID — Categoria A,
seção 20 da arquitetura; o Mod ID original também continha espaços literais, normalizado no mesmo
passo).
Mudança: `id=TacHold Complete Fixed` -> `id=LS_TacticalHold`; `name=`/`description=` reescritos.
Adicionado `versionMin=42.20` (a pasta `42/` não declarava nenhum `versionMin=`). Removida a linha
`incompatible=` (nomeia cinco outras variantes do mesmo mod não bundladas neste pacote — mesmo
raciocínio já aplicado em `drag-bodies-faster`/`clean-hotbar`). `poster=`/`icon=` preservados.

## Itens sem alteração

Todos os 4 arquivos Lua, todo o XML de AnimSets e todos os `.fbx` de animação são cópia byte-a-byte
do upstream `42/` — confirmado via `diff -rq` e `luac5.1 -p`. **Nenhuma correção de código foi
necessária.** Ver `INTEGRATION.md` para a análise completa de por que o mecanismo (cada cliente
calcula e transmite a própria pose via `transmitModData()`, servidor totalmente inerte) é seguro em
MP sem nenhum código de rede customizado.

## Itens ignorados deliberadamente

- Toda a camada legada de nível superior (`mod.info` + `media/` sem pasta de versão) — codebase mais
  antiga com dois bugs reais do próprio upstream: os dois arquivos Lua de opções têm extensão dupla
  quebrada (`TacHold_Options.lua.lua`/`TacPHold_Options.lua.lua`) e o `mod.info` declara
  `require=modoptions`, uma dependência rígida em um mod utilitário de terceiros não bundlado neste
  pacote. Não bundlada nem incluída no snapshot `vendor/` (este pacote alveja só 42.20.x, e a pasta
  `42/` já é totalmente autocontida, sem essa dependência).
- `common/` (totalmente vazio, nem placeholder tem). Não bundlado nem incluído no snapshot.
