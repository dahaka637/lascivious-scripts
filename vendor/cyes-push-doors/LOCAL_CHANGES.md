# Local Changes — Cye's Push Doors!

## LS-003
Tipo: tradução PT-BR de sandbox
Arquivos: `42/media/lua/shared/Translate/PTBR/{Sandbox.json,Sandbox_PTBR.txt}`
Mudança: adicionadas as 35 chaves PT-BR completas; o TXT nativo usa escapes decimais ASCII-safe.
Validação: paridade 35/35 com EN, sintaxe Lua 5.1 e reconstrução UTF-8 exata.

## LS-001
Tipo: tradução / correção de bug
Arquivo novo: `42/media/lua/shared/Translate/EN/Sandbox_EN.txt`
Motivo: upstream só tinha `Sandbox.json` (EN/ES/ES_MX), que a tela nativa de Sandbox Options nunca
lê — mesmo bug recorrente já corrigido em quase todos os outros módulos deste pacote.
Mudança: criado o arquivo nativo com as 33 chaves (título da página + 16 opções × rótulo/tooltip) já
com o texto correto do EN JSON, quebras de linha reais convertidas para `<LINE>` e `%` duplicado para
`%%` (mesma convenção já usada e validada no módulo próprio `zombie-decay`).

## LS-002
Tipo: bundling / identidade do mod
Arquivo: `42/mod.info`
Motivo: rebrand para o namespace do pacote (mod não faz nenhum check do próprio Mod ID — Categoria A,
seção 20 da arquitetura).
Mudança: `id=CyesPushDoors` -> `id=LS_CyesPushDoors`; `name=`/`description=` reescritos.
`versionMin=42.20`, `modversion=1.0.2` e `poster=`/`icon=` preservados do upstream.

## Itens sem alteração

Todo o código Lua (9 arquivos: 2 client, 2 server, 5 shared) é cópia byte-a-byte do upstream —
confirmado via `diff -rq`. **Nenhuma correção de código foi necessária.** A arquitetura de rede já é
totalmente server-authoritative (validação de distância/transição/Z-level/estado da porta no
servidor, Força/Aptidão Física lidas do personagem-servidor, broadcast explícito e aplicação local em
todo cliente) e já resolve, de forma mais sofisticada que a reescrita deste pacote em `better-push`,
o problema de múltiplos clientes observando o mesmo evento de porta (arbitragem de candidatos em
`Server.lua`, preferindo quem de fato interagiu sobre quem só está "observando" por perto). Ver
`INTEGRATION.md` para os detalhes completos da revisão de MP.

## Itens ignorados deliberadamente

- `42/media/lua/shared/Translate/*/IG_UI.json` (EN/ES/ES_MX) — as 2 chaves nunca são lidas por
  `getText()` em lugar nenhum do código (o próprio menu de Mod Options usa texto literal via um
  helper `localText()` interno). Preservados no bundle por fidelidade, sem gerar nenhum arquivo
  nativo correspondente (não haveria efeito).
