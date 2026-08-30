# Local Changes — Equip Items While Running

## LS-001
Tipo: servidor / autoridade multiplayer
Arquivo: `42/media/lua/server/RunningActionsServer.lua`
Motivo: o relay original repassava `args` do cliente sem nenhuma validação — qualquer cliente podia
enviar `{id = <onlineID de outro jogador>, var = <qualquer nome>, val = <qualquer valor>}` e o
servidor aplicava isso no personagem de outro jogador via `setVariable`, em todos os outros clientes
conectados. Efeito prático limitado a variáveis de animação (não é dado de save nem stat de
gameplay), mas ainda assim é um vetor de grief claro e evitável — viola a diretriz de autoridade
server-side da seção 29 da arquitetura ("existe comando sem validação?").
Mudança: adicionada checagem `args.id ~= player:getOnlineID()` (onde `player` é o objeto autenticado
pelo servidor, não algo vindo do payload do cliente) antes de repassar o pacote — um cliente só
consegue mais reportar variáveis de animação sobre o próprio personagem. Nenhum efeito no uso
legítimo (todo call site do mod já envia sempre `id = character:getOnlineID()` do próprio jogador
local).

## LS-002
Tipo: bundling / identidade do mod
Arquivo: `42/mod.info`
Motivo: rebrand para o namespace do pacote (mod não faz nenhum check do próprio Mod ID — Categoria A,
seção 20 da arquitetura).
Mudança: `id=equipwhilerunning` -> `id=LS_EquipWhileRunning`; `name=`/`description=` reescritos;
`modversion=1.0.0` adicionado (upstream não declarava versão).

## LS-003
Tipo: estrutura
Arquivo: layout do submod inteiro
Motivo: adequar à estrutura canônica `common/` + `42/` deste projeto; o upstream distribui duas
pastas por versão de build (`42.19` e `42.20.2`) em vez de `common/`+`42/`.
Mudança: só o conteúdo de `42.20.2/` (a variante que bate com nosso alvo `42.20.x` e a única com
código server-side) foi copiado para `Contents/mods/LS_EquipWhileRunning/42/`. A variante `42.19`
(rotulada pelo próprio autor como `[B42.19 SP ONLY]`) não foi bundlada — permanece só no snapshot
`vendor/equip-while-running/upstream/42.19/` para referência futura.

## LS-004
Tipo: cliente / controle de movimento
Arquivo: `42/media/lua/client/EqiupWhileRunning.lua`
Motivo: o loop `OnPlayerUpdate` marcava toda ação de equipar, desequipar, anexar/remover da hotbar
ou vestir roupa como `blockRun = true`, mesmo quando a opção de penalidade correspondente estava
desabilitada. Na sequência, `player:setAllowRun(false)` anulava o `stopOnRun = false` configurado
pelas próprias TimedActions do mod. Além disso, quando nenhuma dessas ações estava ativa, o loop
executava `player:setAllowRun(true)` em todos os frames e podia liberar uma restrição que pertencia
ao jogo ou a outro mod.
Mudança: o bloqueio agora só é aplicado quando a penalidade específica da categoria está habilitada
(armas/hotbar, roupas ou transferências). O valor anterior de `isAllowRun()` é guardado por jogador
apenas quando este mod assume o controle e restaurado ao fim da penalidade; fora desse intervalo o
mod não escreve mais em `AllowRun`. O estado também é restaurado antes de ignorar jogadores
montados. O sprint continua deliberadamente fora do escopo e conserva o comportamento upstream de
cancelar as ações que já possuíam essa proteção. `modversion` incrementado de `1.0.0` para `1.0.1`.

## Itens sem alteração

- Os 4 arquivos AnimSet XML e o clipe `.x` são cópias byte-a-byte do upstream.
- Fora da correção localizada LS-004, a lógica de gameplay em `EqiupWhileRunning.lua` (incluindo o
  typo no nome do arquivo, que já vem assim do upstream) permanece igual ao upstream.
- Os 5 rótulos/tooltips do `PZAPI.ModOptions` continuam em inglês, sem tradução — ver nota em
  `TRANSLATION_PTBR.md`.

## Perguntas para revisitar em updates futuros

- Comparar `vendor/equip-while-running/upstream/42.20.2/` contra a nova versão via
  `tools/hash_module.py` (upstream não versiona `mod.info`).
- Reaplicar LS-001 e LS-004 manualmente se o upstream reescrever, respectivamente,
  `RunningActionsServer.lua` e `EqiupWhileRunning.lua` — não é um merge automático.
- Reavaliar se algum mod novo bundlado também patcheia `ISEquipWeaponAction`/`ISUnequipAction`/
  `ISWearClothing`/`ISInventoryTransferAction`/`ISAttachItemHotbar`/`ISDetachItemHotbar`/
  `luautils.haveToBeTransfered` antes de integrá-lo (ver Collision Registry).
