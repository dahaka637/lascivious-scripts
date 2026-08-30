# 02 — Findings do Codex

**Status da passada:** `HISTORICAL_COMPLETE — PENDÊNCIAS SUPERADAS PELO 03/08`  
**Última atualização:** 2026-08-26  
**Regra ativa (atualizada em 2026-08-26):** este é o relatório histórico de descoberta. Menções no
corpo a espera/refutação não são tarefas abertas. Veredito atual em `03_RECONCILED_FINDINGS.md`,
patches em `07_PATCH_PLAN.md`, blockers em `08_RELEASE_BLOCKERS.md`; próximo gate em
`06_RUNTIME_TEST_MATRIX.md`.

## CDX-001 / PRE-001 — servidor aceita resultado de arrombamento escolhido pelo cliente

```text
Status: CONFIRMED — aguardando tentativa de refutação pelo segundo agente
Severidade: CRITICAL
Confiança: CONFIRMED_STATIC
Módulo: LS_BurrisQualityOfLife
Lado: client -> server
Trigger: comando BQoL/prySuccess fabricado ou repetido por cliente modificado
```

### Arquivos e linhas

```text
Contents/mods/LS_BurrisQualityOfLife/42/media/lua/shared/TimedActions/BQoL_PryAction.lua:92-138
Contents/mods/LS_BurrisQualityOfLife/42/media/lua/server/BQoL/BQoL_Commands.lua:22-59,107-128
Contents/mods/LS_BurrisQualityOfLife/42/media/lua/shared/BQoL/BQoL_PryLogic.lua:279-347,352-405
Contents/mods/LS_BurrisQualityOfLife/42/media/lua/client/BQoL/BQoL_Pry_Menu.lua:12-84
Contents/mods/LS_BurrisQualityOfLife/42/media/lua/shared/BQoL/BQoL_PryOutcome.lua:87-119
```

### Funções

```text
BQoL_PryAction:complete
BQoL_PryAction:sendToServer
handlers.prySuccess
resolveTarget
Pry.classify
Pry.isBlockedBySafehouse
Pry.canForceReinforced
Pry.roll
Pry.applySuccess
```

### Cenário mínimo

Um cliente modificado envia diretamente:

```text
module = BQoL
command = prySuccess
args = { x, y, z, kind = "door" }
```

para uma porta trancada carregada pelo servidor. Não é necessário ter concluído a TimedAction nem
possuir uma ferramenta. Se a opção de invadir bases seguras estiver desativada, o cliente também
pode escolher uma porta dentro de uma base protegida porque esse bloqueio só é consultado no menu
cliente.

### Estado esperado

O cliente comunica apenas a intenção. O servidor deve re-resolver o alvo e validar, no mínimo:

```text
distância e mesmo Z
base protegida
ferramenta válida e ainda pertencente ao jogador
força exigida para porta reforçada
estado atual do alvo
cooldown/rate limit
RNG da tentativa
```

### Estado atual e evidência

- `BQoL_PryAction:complete()` calcula `Pry.roll()` no cliente e escolhe entre `prySuccess` e
  `pryFailure` (`BQoL_PryAction.lua:92-115`).
- O pacote enviado contém somente coordenadas e `kind`; não contém uma prova servidor da ação
  (`BQoL_PryAction.lua:128-137`).
- O servidor re-resolve o square e chama `Pry.classify()`. Isso confirma que o objeto ainda é uma
  porta/janela trancada e que o tipo está habilitado, mas não valida o jogador
  (`BQoL_Commands.lua:22-38`).
- `handlers.prySuccess()` chama diretamente `Pry.applySuccess()` depois dessa classificação
  (`BQoL_Commands.lua:43-52`).
- Não há no handler verificação de distância, Z relativo, ferramenta, inventário, força para porta
  reforçada, base protegida, cooldown ou RNG.
- `Pry.isBlockedBySafehouse()` existe (`BQoL_PryLogic.lua:334-347`), mas seu único caller no fluxo
  de portas de edifício é o menu cliente (`BQoL_Pry_Menu.lua:33-43`).
- `Pry.canForceReinforced()` também é aplicado somente na disponibilidade do menu cliente
  (`BQoL_Pry_Menu.lua:71-79`).
- `Pry.applySuccess()` destranca/abre o objeto, transmite a mudança e concede XP ao remetente
  (`BQoL_PryOutcome.lua:87-118`).

### Impacto

Operação remota sobre portas/janelas carregadas, bypass do RNG e dos requisitos de ferramenta e
Força, ganho arbitrário repetível de XP e bypass da proteção de bases. A capacidade de afetar bases
sem a autorização contextual exigida enquadra o problema como `CRITICAL` pela regra desta revisão.

### Escala e complexidade

Não é finding de performance. O custo de cada comando é limitado ao scan dos objetos de um square,
mas o efeito pode ser repetido sem rate limit observado.

### Memória

Nenhum crescimento persistente demonstrado neste finding.

### Possível crash

Não é necessário para o impacto. O dispatcher envolve o handler em `pcall`; o problema principal é
a operação indevida aceita, não uma exception.

### Solução recomendada

Substituir `prySuccess`/`pryFailure` por uma única intenção `pryAttempt`. O servidor deve executar as
validações contextuais, calcular o RNG e aplicar o resultado. Adicionar rate limit curto por jogador
e coordenada. O cliente deve apenas apresentar animação/feedback a partir do resultado servidor.

### Risco da solução

Médio: muda o protocolo de uma TimedAction e o momento do feedback cliente. Deve preservar o fluxo
singleplayer e evitar resultado duplo em host cooperativo.

### Teste de regressão necessário

```text
singleplayer: sucesso e falha continuam funcionando
dedicated MP: sucesso/falha sincronizam para todos
sem ferramenta: comando recusado
longe ou Z diferente: comando recusado
porta de base protegida: recusada quando PrySafeDoors=false
porta reforçada sem Força: recusada
spam/replay de pryAttempt: sem resultados múltiplos
alvo destrancado/destruído durante a ação: recusado com segurança
```

### Verificado nesta sessão

Foram lidas integralmente a TimedAction, o dispatcher servidor, a lógica de classificação/RNG, o
menu cliente e a aplicação do resultado. Foi feita busca global pelos comandos e pelos checks
relevantes dentro do módulo.

### Ainda falta verificar

- tentativa de refutação independente do Claude, obrigatória para CRITICAL/HIGH;
- semântica exata do raio de squares carregados no servidor, que limita alcance mas não elimina o
  bypass;
- desenho do patch somente depois da reconciliação.

### Próximo passo exato

Claude deve ler os mesmos cinco arquivos e procurar qualquer validação indireta instalada pelo
engine/TimedAction ou por caller servidor que torne impossível fabricar `prySuccess`. Se não houver,
mover para `03_RECONCILED_FINDINGS.md` como confirmado. Não aplicar patch antes disso.

---

## CDX-002 / PRE-002 — comando de escada oferece teleporte incremental arbitrário

```text
Status: CONFIRMED — aguardando tentativa de refutação pelo segundo agente
Severidade: CRITICAL
Confiança: CONFIRMED_STATIC
Módulo: LS_ClimbLadders
Lado: client -> server
Trigger: comando SubirEscaleras/climb fabricado ou repetido por cliente modificado
```

### Arquivos e linhas

```text
Contents/mods/LS_ClimbLadders/42/media/lua/server/SubirEscaleras_Server.lua:14-69
Contents/mods/LS_ClimbLadders/42/media/lua/client/SubirEscaleras/SE_Utils.lua:103-145,211-403,405-477
Contents/mods/LS_ClimbLadders/42/media/lua/client/SubirEscaleras/SE_ClimbAction.lua:25-124
Contents/mods/LS_ClimbLadders/42/media/lua/client/SubirEscaleras/SE_ContextMenu.lua:12-31,97-139
Contents/mods/LS_ClimbLadders/42/media/lua/client/SubirEscaleras/SE_Keybind.lua:40-96
```

### Funções

```text
onClientCommand
isReasonable
SubirEscaleras.movePlayerTo
SubirEscaleras.moveSafely
SubirEscaleras.findLadder/getClimbDir/findLadderEnd/getTargetSquare
ISSubirEscaleraAction:perform
```

### Cenário mínimo

Um cliente modificado envia `SubirEscaleras/climb` com destino até 2 unidades em X, 2 em Y e 8
níveis em Z da posição servidor atual. Depois que o servidor aplica o movimento, repete o comando a
partir da nova posição. Nenhuma escada, TimedAction ou superfície válida é necessária.

### Estado esperado

O cliente deve indicar a intenção e, no máximo, coordenadas da escada adjacente. O servidor deve
resolver o objeto, provar que ele é trepável, calcular a coluna/final/landing com sua própria visão
do mundo, confirmar origem e destino transitáveis e aplicar cooldown.

### Estado atual e evidência

- O pacote legítimo contém somente `{x,y,z}` escolhidos pelo cliente (`SE_Utils.lua:405-421`).
- O servidor valida apenas a diferença numérica para a posição atual e o intervalo absoluto de Z
  (`SubirEscaleras_Server.lua:20-37`).
- O handler passa as coordenadas recebidas diretamente para `player:teleportTo()` e depois as
  retransmite para todos (`SubirEscaleras_Server.lua:39-66`).
- Não existe no lado servidor qualquer carregamento das rotinas de detecção de escada. Toda a
  detecção, landing, segurança do destino, condição física e TimedAction vive em `client/`.
- Não há cooldown, rate limit, nonce, sessão ou estado servidor de uma subida em andamento.
- Como a posição servidor muda após cada chamada aceita, os limites são apenas por passo e não
  limitam o alcance acumulado. Em particular, até 8 níveis verticais podem ser atravessados por
  pacote.
- Os argumentos também não passam por validação explícita de tipo antes das operações aritméticas;
  isso é uma robustez adicional pendente, mas não é necessário para confirmar o teleporte.

### Impacto

Teleporte arbitrário por repetição de pequenos passos, incluindo atravessar pisos, paredes e
barreiras e alcançar qualquer região carregável em sequência. O servidor ainda anuncia o resultado
aos demais clientes como se fosse legítimo. Enquadra-se diretamente no critério `CRITICAL` de
teleporte arbitrário/bypass grave.

### Escala e complexidade

Não é finding de performance. Cada pacote é O(1), mas não há limite de frequência.

### Memória

Nenhum crescimento persistente demonstrado.

### Possível crash

Argumentos de tipo inesperado podem lançar no callback não protegido, mas não foi promovido como
finding separado nesta sessão. O impacto crítico já existe com números válidos.

### Solução recomendada

Trocar o protocolo para `requestClimb` contendo apenas referência primitiva da escada/origem e
sentido. Mover ou compartilhar com o servidor as rotinas mínimas de detecção e cálculo; o servidor
deve resolver a escada adjacente, calcular o único destino permitido, validar origem/destino e
cooldown, então teleportar. Nunca aceitar destino final calculado pelo cliente.

### Risco da solução

Alto: hoje toda a geometria está em `client/`, inclui vários tipos de escada e landings laterais e
há comportamento especial ao descer. A migração deve preservar escadas de múltiplos níveis e não
deixar jogadores presos em telhados.

### Teste de regressão necessário

```text
subir/descer escadas de 1 e vários níveis
quatro direções e landing lateral
escada inexistente: recusar
origem distante: recusar
destino bloqueado/sem piso: recusar
destino Z fabricado: recusar
replay/spam: um único movimento legítimo
dois jogadores simultâneos e observador remoto: sincronização correta
cancelamento, movimento e disconnect durante a TimedAction
```

### Verificado nesta sessão

Foram lidos integralmente o handler servidor e a TimedAction. Também foram rastreadas as rotinas
cliente que detectam a escada, calculam o destino e enviam o comando, além dos dois callers que
constroem a TimedAction.

### Ainda falta verificar

- tentativa de refutação independente do Claude;
- comportamento exato de correção de posição do engine diante do teleporte local antecipado;
- desenho do compartilhamento da geometria somente depois da reconciliação.

### Próximo passo exato

Claude deve procurar qualquer validação implícita do engine anterior ao `OnClientCommand` que prove
a existência de uma escada para este módulo/comando. Se não existir, reconciliar como CRITICAL.

## Candidatos herdados ainda não auditados pelo Codex

O PRE-004 abaixo permanece sem leitura do código pelo Codex.

## CDX-004 / PRE-003 — controle remoto PSR não valida contexto do jogador

```text
Status: CONFIRMED — aguardando refutação pelo segundo agente
Severidade: CRITICAL
Confiança: CONFIRMED_STATIC
Módulo: LS_PlyskenSolarRevolution
```

`PSRComputerPanel.lua:711-727` envia a bank e o alvo/tipo escolhidos pelo cliente. O dispatcher
servidor apenas chama `Commands[command]` (`PowerBankSystem_Server.lua:292-295`).
`controlDeviceGroup` resolve `args.bank`, deriva os devices e aplica/persiste o grupo
(`PowerBankSystem_Commands.lua:332-359`); `controlDevice` revalida corretamente que o alvo pertence à
rede escolhida (`:389-420`) e então aplica/persiste (`:421-433`). Porém nenhum dos dois usa
`playerObj` para validar distância, Z, terminal real, vínculo terminal-bank, sessão, área protegida,
direito do jogador ou rate limit. Membership impede alvo fora da rede indicada, mas o cliente pode
indicar outra bank carregada e operar remotamente a rede dela, inclusive estados persistentes de
refrigeração. Isso satisfaz o critério CRITICAL de operação remota sobre outra base.

Solução recomendada: sessão servidor curta vinculando jogador + terminal real + bank/network,
revalidada por comando e expirada por tempo/distância/disconnect; preservar membership como segunda
camada e adicionar rate limit. Claude deve tentar refutar rastreando a abertura do painel e
`LinkComputer`; se não existir gate servidor anterior ao callback público, reconciliar como
CRITICAL. Testar dedicado/host, individual/grupo, rede ligada, bank arbitrária, distância, replay e
duas bases independentes.

## CDX-005 / PRE-004 — backup/restore pré-materializa jobs grandes em RAM

```text
Status: CONFIRMED — aguardando refutação e profiling
Severidade: HIGH / PERF-HIGH
Confiança: HIGH_CONFIDENCE estática; dimensão exata NEEDS_PROFILING
Módulo: LS_AegisPanel
```

`buildSnapshotJob()` materializa até 90.000 tabelas `{x,y}` por job antes de enfileirar
(`Aegis_Backup.lua:748-781`). A fila admite 64 jobs (`:19-21,819-840`) e a automação diária pode
construí-los sincronicamente no mesmo callback (`:911-924`): até 5.760.000 pequenas tabelas retidas,
além dos arrays. Com estimativa conservadora de 80–160 bytes por entrada Kahlua, somente as colunas
ficam na ordem de 460–920 MB, sem contar overhead dos arrays/GC.

O job ativo acumula o snapshot inteiro em `job.lines` (`:275-325`) e ao terminar cria outra string
contígua com `table.concat` (`:677-700`), mantendo linhas + conteúdo durante o pico; a escrita recebe
a string inteira (`Aegis_Store.lua:33-42,283-305`). Restore lê até 400.000 linhas de uma vez
(`Aegis_Backup.lua:843-885`). Com 64 zonas distintas, o teto teórico é 25,6 milhões de strings
retidas antes do processamento. O budget de backup é por coluna: 250 colunas × até 16 Z = até 4.000
squares/tick, mais objetos/containers/items (`:677-694`), portanto também pode causar spikes.

Impacto: pressão extrema de heap/GC, stall do main thread e OOM em áreas/grupos grandes ou fila de
restores. A fila processa um job por vez, mas isso não reduz a memória já pré-carregada dos demais.

Solução: jobs guardarem somente descritor + cursor; percorrer retângulos sem `columns`; streaming
incremental para arquivo temporário com buffer pequeno e rename ao concluir; restore com reader
aberto/cursor incremental; limites por bytes e por tempo/squares/objects/items, além de fila bem
menor. Profiling obrigatório com 1/8/64 jobs e snapshots grandes, medindo heap, GC, p95/p99/max por
tick e tamanho de buffers. Claude deve refutar a estimativa com o tamanho real das estruturas ou
reconciliar o risco; a pré-materialização em si está confirmada estaticamente.

## CDX-003 / PRE-005 — repair queue pode permanecer envenenada em `OnTick`

```text
Status: CONFIRMED — aguardando tentativa de refutação pelo segundo agente
Severidade: HIGH
Confiança: CONFIRMED_STATIC
Módulo: LS_AliceWeaponSling
Lado: cliente/shared
Trigger: janela de reparo tenta preservar arma anexada que está nas mãos
```

### Arquivos e linhas

```text
Contents/mods/LS_AliceWeaponSling/42/media/lua/shared/TimedActions/ISClothingExtraAction_AliceWeaponSling.lua:149-165,232-304,306-335
Contents/mods/LS_AliceWeaponSling/42/media/lua/shared/TimedActions/ISAttachItemHotbar_AliceWeaponSling.lua:101-186
```

### Estado esperado

Cada entrada da janela de reparo deve ser consumida mesmo quando a operação falha; uma falha deve
ser protegida, registrada no máximo uma vez e não permanecer em `OnTick` indefinidamente.

### Estado atual e evidência

- `preserveHotbarSlot(data, model)` valida `data.item`, mas usa os identificadores inexistentes
  `item` e `slotType` nas linhas 155-157, em vez de `data.item` e `data.newSlotType`.
- `restoreAttachedWeapon()` chama essa função quando a arma está nas mãos (linhas 258-260).
- `onRepairTick()` executa `restoreAttachedWeapon(data.attached)` antes de
  `table.remove(repairQueue,index)` (linhas 286-297), sem `pcall`.
- Depois da primeira falha, `ticks` continua `<= 0`; a mesma entrada é tentada em todo tick e o
  callback não alcança nem a remoção nem seu próprio desregistro.
- Cada mudança de sling pode inserir seis entradas com referências fortes a hotbar, personagem e
  item (linhas 306-323). Se a fila fica envenenada, operações posteriores podem continuar
  acrescentando entradas.
- A segunda repair queue (`ISAttachItemHotbar...:101-186`) usa os campos corretos e não contém o
  mesmo erro nominal confirmado. Entretanto, também executa a rotina perigosa antes da remoção e
  sem proteção; deve receber a mesma correção de lifecycle preventivo.

### Impacto

Exception/log storm por tick no cliente, queda severa de FPS e callback permanentemente instalado.
Há ainda retenção/crescimento de referências caso novas janelas sejam agendadas depois que a fila
fica envenenada. Classificação `HIGH`; não há evidência necessária para promover a CRITICAL.

### Solução recomendada

Corrigir os dois identificadores para os campos de `data`. Nas duas queues, remover/inativar a
entrada antes de executar a rotina, envolver somente a operação em proteção, emitir log
rate-limited e garantir o desregistro do `OnTick` quando a fila esvaziar.

### Risco e teste de regressão

Risco baixo/médio, localizado no reparo visual do hotbar. Testar mudança entre todas as variantes
de sling com arma anexada, arma nas mãos, slot ocupado, ação repetida e exception artificial;
confirmar fila vazia e callback removido após 30 ticks.

### Verificado nesta sessão

Os dois arquivos e os dois lifecycles de fila foram lidos integralmente. O erro de escopo é direto
em Lua e o caminho `itemInHands -> preserveHotbarSlot` está confirmado.

### Ainda falta verificar / próximo passo exato

Claude deve tentar refutar o trigger no estado real do hotbar e verificar se o dispatcher de eventos
captura exceptions sem remover callbacks. Mesmo que o engine capture, isso não remove a entrada
envenenada; reconciliar como HIGH se o caminho de arma nas mãos for alcançável.

## Alterações de código

```text
Nenhuma. Primeira passada preservada.
```

---

# Segunda opinião sobre findings posteriores do Claude

## CDX-REF-001 / CLD-P1-001 — Cyes Push Doors

```text
Veredito: CONFIRMED — tentativa de refutação falhou
Severidade: HIGH
Confiança: CONFIRMED_STATIC
```

Li o fluxo legítimo em `Hook.lua:374-430`, o dispatcher e lifecycle completos em
`CyesPushDoors_Server.lua:45-319`, e a aplicação/validação servidor em
`Core.lua:2087-2411`. O cliente legítimo só marca `interaction=true` depois de observar a transição,
mas esse boolean é fabricável. O servidor re-resolve porta, distância, Z, lado de impacto, estado,
targets, atributos e RNG corretamente; porém `validateServerRequest()` e
`serverDoorStateMatches()` provam somente o estado estático atual. Nenhum nonce, histórico servidor
de transição ou correlação player+porta prova que o remetente acabou de causar a abertura/fechamento.

Logo, perto de uma porta comum já aberta ou garagem já fechada, um cliente modificado pode produzir
efeitos de combate e desgaste repetidos nos limites de cooldown sem transição nova. Correção factual
ao texto original: não encontrei concessão de XP; `applyArmStrain()` aplica strain, não XP. Isso não
refuta o HIGH, pois dano/knockdown em personagens/zombies e desgaste/quebra de porta continuam sendo
efeitos autoritativos indevidos.

## CDX-REF-002 / TV-001 — TimeVote `liveNetActions`

```text
Veredito: REJECTED_FALSE_POSITIVE
Severidade final: nenhuma
Confiança: CONFIRMED_ENGINE_BYTECODE (Build 42.20.4 instalado)
```

A premissa necessária ao finding não se sustenta na implementação do engine. Inspecionei
`zombie.core.Action` e `zombie.core.NetTimedAction` no `projectzomboid.jar` 42.20.4 instalado.
`Action.getProgress()` não depende do player, da conexão nem de a TimedAction continuar registrada:
calcula diretamente `(GameTime.getServerTimeMills() - startTime) / (endTime - startTime)`. Assim, uma
desconexão não consegue congelar `progress < 1`; o relógio servidor continua avançando e
`driveNetRegistry()` remove a entrada quando chega a 1.

Até ações com duração negativa/infinita têm saída: `Action.setTimeData()` converte duração negativa
em `endTime = startTime + AnimEventEmulator.getDurationMax()`. `setDuration()` também mantém um
`endTime` temporal explícito. Portanto a ausência de `noNet`/TTL no registry não cria o crescimento
monotônico proposto. A tabela ainda deve ser perfilada como parte do custo normal do TimeVote, mas
`TV-001` não é HIGH nem release blocker.

Comandos de reprodução da prova:

```bash
javap -classpath <PZ>/projectzomboid.jar -c -p zombie.core.Action
javap -classpath <PZ>/projectzomboid.jar -c -p zombie.core.NetTimedAction
```

## CDX-REF-003 / ZD-001 — ZombieDecay `_originalLore`

```text
Veredito: CONFIRMED — tentativa de refutação falhou
Severidade: HIGH
Confiança: CONFIRMED_ENGINE_BYTECODE (Build 42.20.4 instalado)
```

Li `ZombieDecay/Core.lua:274-358` e `Server.lua:12-38`. A possível refutação era que
`options:set()` + `toLua()` talvez fossem apenas runtime e que um restart recarregasse sempre o
arquivo administrativo original. A implementação do engine elimina essa defesa: `SandboxOptions.toLua()`
realmente só atualiza `SandboxVars`, mas `GameWindow.save(boolean)` grava os valores atuais de
`SandboxOptions.instance` em `map_sand.bin` chamando `SandboxOptions.save(ByteBuffer)`. No load de
mundo, `IsoWorld` chama `SandboxOptions.load()`, que lê esse snapshot salvo.

Assim, depois que ZombieDecay muda as oito opções e ocorre um save/restart, o novo processo perde a
tabela Lua `_originalLore` mas recarrega do save os valores já decaídos. A primeira chamada de
`captureOriginalLore()` recaptura esses valores intermediários como “originais”. O mecanismo de
perda silenciosa do ponto de restauração está confirmado. A solução continua sendo persistir, por
save, o snapshot original uma única vez antes da primeira aplicação.

## Próximo passo vigente

Reconciliação já concluída: Cyes e ZombieDecay foram promovidos e corrigidos; TimeVote foi refutado.
Não repetir essa etapa. Seguir `06_RUNTIME_TEST_MATRIX.md` e documentar cada resultado imediatamente.
