# Local Changes — Sprint Through Windows

## LS-001
Tipo: servidor / autoridade multiplayer
Arquivo: `42/media/lua/server/SprintDiveWindows_Server.lua`
Motivo: os comandos `diveOutcome` e `diveLanding` repassavam `args.id`/`args.outcome`/
`args.x`/`args.y`/`args.z` do cliente sem nenhuma validação contra o jogador autenticado pelo
servidor. Qualquer cliente podia enviar `{id = <onlineID de outro jogador>, outcome = "fall"}` ou
`{id = <onlineID de outro jogador>, x = <qualquer valor>, y = <qualquer valor>}`, e o servidor
repassava isso para todos os outros clientes conectados. O handler `diveLanding` do lado do cliente
(`SprintDiveWindows_Remote.lua`) aplica `player:setX/Y/Z` diretamente sobre o objeto do jogador-alvo
assim que recebe o pacote — ou seja, um cliente malicioso podia fazer o avatar de QUALQUER outro
jogador aparecer "teleportado" para coordenadas arbitrárias na tela de todo mundo (efeito visual,
local a cada cliente, sem mover a posição real/autoritativa do alvo — mas ainda assim um vetor de
grief claro e evitável, na mesma categoria do LS-001 já aplicado em `equip-while-running`).
Mudança: adicionada checagem `args.id ~= player:getOnlineID()` (onde `player` é o objeto autenticado
pelo servidor) antes de repassar os pacotes `diveOutcome` e `diveLanding`. O handler `glassCut` já
operava sobre `player` diretamente (nunca leu `args.id`) e não precisou de alteração. Nenhum efeito
no uso legítimo — todo call site do mod já envia sempre `id = character:getOnlineID()` do próprio
jogador local.

## LS-002
Tipo: bundling / identidade do mod
Arquivo: `42/mod.info`
Motivo: rebrand para o namespace do pacote (mod não faz nenhum check do próprio Mod ID — Categoria A).
Mudança: `id=SprintDiveWindows` -> `id=LS_SprintThroughWindows`; `name=`/`description=` reescritos em
PT-BR (mod.info é lido pelo parser Java do PZ, não pelo Kahlua, então não sofre o bug de acentuação —
ver `[[feedback-ptbr-accents-in-lua]]`); `poster=poster.png` corrigido para apontar para o arquivo que
de fato existe (upstream referenciava `poster.png` mas só distribui `preview.png` — renomeado na cópia
bundled). `modversion=2.0` preservado do upstream.

## LS-003
Tipo: tradução
Arquivo: `42/media/lua/shared/Translate/PTBR/Sandbox.json`
Motivo: o upstream já shippa PT-BR nativo (13/13 chaves), mas sem nenhum acento — "Atraves", "chao",
"e" em vez de "é" etc. Como esse arquivo é JSON consumido via `getText()`, acentuação correta não sofre
o bug de literais Lua crus (diferente das 5 labels do `PZAPI.ModOptions` do `equip-while-running`,
que ficaram em inglês por esse motivo).
Mudança: reescrita completa das 13 chaves com acentuação e fraseado naturais em PT-BR, mantendo a
paridade 13/13 com o `EN/Sandbox.json` (chaves idênticas, texto revisado).

## Itens sem alteração

- `SprintDiveWindows.lua` (client) e `SprintDiveWindows_Remote.lua` (client) permanecem byte-a-byte
  iguais ao upstream — a lógica de gameplay (detecção de janela, direção do pulo, reposicionamento
  sobre móveis, quebra de vidro, chance de falha/corte) não foi tocada.
- O AnimSet XML (`diveThruWindowCrash.xml`) e o clipe `.x` (`Bob_ValultOver_Sprint_Crash.x`) são
  cópias byte-a-byte do upstream — nó novo em caminho que não colide com nenhum arquivo vanilla (ver
  `INTEGRATION.md`).
- `sandbox-options.txt` e `EN/Sandbox.json` permanecem iguais ao upstream.

## Perguntas para revisitar em updates futuros

- Comparar `vendor/sprint-through-windows/upstream/42/` contra a nova versão via
  `tools/hash_module.py` (upstream não versiona `mod.info` além do `modversion` bruto).
- Reaplicar LS-001 manualmente se o upstream reescrever `SprintDiveWindows_Server.lua` — não é um
  merge automático.
- Reavaliar se algum mod novo bundlado também usa `Events.OnObjectCollide`, ou patcheia
  `ClimbOverFenceState`/`ClimbThroughWindowState`/`IsoWindow`/`IsoWindowFrame`, antes de integrá-lo —
  nenhuma colisão encontrada hoje (ver `INTEGRATION.md`), mas essa superfície ficaria ocupada por este
  módulo a partir de agora.
