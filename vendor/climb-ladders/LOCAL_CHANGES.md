# Local Changes — Climb Ladders

## LS-001
Tipo: tradução / correção de bug
Arquivos novos: `42/media/lua/shared/Translate/EN/{ContextMenu_EN.txt,IG_UI_EN.txt,UI_EN.txt}`
Motivo: upstream só tinha `.json` (10 idiomas), que `getText()` nativo nunca lê. O código chama
`getText()` em 10 chaves diferentes (3 de menu de contexto, 5 de mensagens in-game, 2 de rótulo de
keybind) sem nenhum backing nativo.
Mudança: criados os 3 arquivos nativos com o texto já correto do EN JSON, chave por chave.

## LS-002
Tipo: bundling / identidade do mod
Arquivo: `42/mod.info`
Motivo: rebrand para o namespace do pacote (mod não faz nenhum check do próprio Mod ID — Categoria A,
seção 20 da arquitetura).
Mudança: `id=SubirEscaleras` -> `id=LS_ClimbLadders`; `name=`/`description=` reescritos.
`versionMin=42.15`, `modversion=2.4` e `tags=Building,Misc` preservados do upstream.

## Itens sem alteração

Todo o código Lua (5 arquivos client, 1 server) é cópia byte-a-byte do upstream — confirmado via
`diff -rq`. **Nenhuma correção de código foi necessária.** Este é o módulo mais bem escrito
integrado até agora neste pacote — autoria multiplayer já correta (validação de distância no
servidor, broadcast explícito, sem confiar em sync implícito), sem monkey patch nenhum, e com
histórico documentado de bugs reais já encontrados e corrigidos pelo próprio autor (ver
`INTEGRATION.md` e o `README.md` do upstream, preservado em `vendor/climb-ladders/upstream/README.md`).

## Perguntas para revisitar em updates futuros

- Reler o `README.md` do upstream antes de qualquer atualização futura — o autor documenta ali,
  entre outras coisas, um bug real de tiledef do próprio vanilla (escadas com `ladder*` mas sem
  `climbSheet*`) que este mod contorna deliberadamente; se o vanilla corrigir isso numa build futura,
  reavaliar se o contorno ainda é necessário.
