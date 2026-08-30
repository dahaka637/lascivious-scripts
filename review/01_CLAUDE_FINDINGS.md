# 01 — Findings do Claude

**Status da passada:** `HISTORICAL_COMPLETE — NÃO USAR AS PENDÊNCIAS ANTIGAS COMO PRÓXIMO PASSO`
**Última atualização:** 2026-08-26
**Nota de handoff vigente:** este arquivo preserva a pesquisa histórica. As pendências e frases
“aguardando Codex/segunda passada” no corpo estão encerradas e não devem ser executadas. Estado
atual: `00_INVENTORY`, `03_RECONCILED_FINDINGS`, `07_PATCH_PLAN` e `08_RELEASE_BLOCKERS`; próximo
trabalho: `06_RUNTIME_TEST_MATRIX`. Não reiniciar rodadas estáticas.

## Sumário desta sessão

Rodada 1 completa: tentei refutar CDX-001 a CDX-005 (PRE-001 a PRE-005) lendo os mesmos arquivos que
o Codex citou, mais qualquer caller/validação indireta que pudesse invalidar o achado. **Não consegui
refutar nenhum dos cinco.** Todos os cinco passam de `CONFIRMED — aguardando refutação` para
`CONFIRMED_INDEPENDENTLY` e devem ir para `03_RECONCILED_FINDINGS.md`. Em cada um encontrei um
detalhe adicional que o relatório do Codex não havia enfatizado (listado em cada seção). Nenhum
patch foi aplicado.

Rodada 2 (delegada a dois agentes de pesquisa em background, ambos concluídos e com resultado
verificado por mim contra o código-fonte antes de aceitar):

- **P1 (autoridade de rede, 8 módulos)** — `01c_CLAUDE_P1_AUTHORITY.md`: 1 achado novo
  (`CLD-P1-001`, HIGH, Cyes Push Doors), `LS_EquipWhileRunning` limpo (fix LS-001 reconfirmado), os
  outros 6 módulos sem superfície `OnClientCommand` nenhuma.
- **WanderingZombies + TimeVote + ZombieDecay** — `01b_CLAUDE_WANDERING_TIMEVOTE_ZOMBIEDECAY.md`:
  `LS_WanderingZombies` limpo (autoridade e performance, `PERF-CAND-003` refinado); 2 achados novos,
  ambos de lifecycle/persistência e não de autoridade de rede (`TV-001` HIGH no registro
  `liveNetActions` do TimeVote, `ZD-001` HIGH no snapshot `_originalLore` do ZombieDecay que não
  sobrevive a restart de servidor).

Nenhum CRITICAL novo nesta rodada 2. `CLD-P1-001`, `TV-001` e `ZD-001` ainda precisam da tentativa de
refutação do Codex (seção 17 do plano) antes de irem para `03_RECONCILED_FINDINGS.md`.

---

## CLD-001 / PRE-001 / CDX-001 — BQoL Pry aceita resultado escolhido pelo cliente

```text
Status: CONFIRMED_INDEPENDENTLY — refutação tentada e falhou
Severidade: CRITICAL
Confiança: CONFIRMED_STATIC
Módulo: LS_BurrisQualityOfLife
Lado: client -> server
```

### Verificação feita

Li integralmente `BQoL_PryAction.lua`, `BQoL_Commands.lua`, `BQoL_PryLogic.lua`,
`BQoL_PryOutcome.lua` e `BQoL_Pry_Menu.lua` (os cinco arquivos que o Codex citou, mais
`BQoL_PryOutcome.lua`, que ele não havia transcrito). Procurei especificamente por qualquer
validação que `handlers.prySuccess` pudesse herdar indiretamente de `Pry.classify`/`Pry.applySuccess`
que tornasse a fabricação do comando inofensiva.

### O que confirma o achado

- `Pry.classify()` (chamado por `resolveTarget` no servidor) só verifica se o objeto ainda é uma
  porta/janela travada e se a categoria está habilitada no sandbox — não verifica base protegida
  nem exigência de Força para porta reforçada.
- `Pry.isBlockedBySafehouse()` e `Pry.canForceReinforced()` **existem no código compartilhado**, mas
  seus únicos callers em todo o módulo estão em `BQoL_Pry_Menu.lua` (cliente, decide o que aparece no
  menu). Busquei os dois nomes em todo `LS_BurrisQualityOfLife/` — nenhuma outra ocorrência.
- `Pry.applySuccess()` (`BQoL_PryOutcome.lua:87-119`) não recebe nem consulta o jogador remetente
  além de dar XP; destrava e abre o objeto incondicionalmente a partir do `object`/`kind` que
  recebeu.
- `handlers.prySuccess` (`BQoL_Commands.lua:43-52`) chama `Pry.applySuccess` diretamente após
  `resolveTarget`, sem checar distância, ferramenta, força ou cooldown.

### Achado adicional (além do relatório do Codex)

`resolveTarget()` usa só `getCell():getGridSquare(args.x, args.y, args.z)` — **não há nenhuma
verificação de distância entre o square alvo e a posição do jogador remetente em nenhum ponto da
cadeia**. Qualquer square carregado no servidor serve, não apenas squares próximos ao jogador. Em um
servidor populado, chunks ficam carregados ao redor de todos os jogadores conectados simultaneamente,
então o alcance prático deste bypass é "qualquer porta/janela travada perto de qualquer jogador
online", não "perto do atacante" — mais amplo do que o relatório original sugere.

### Impacto

Confirmado: cliente modificado pode abrir remotamente qualquer porta/janela travada carregada no
servidor (incluindo dentro de safehouse alheia quando `PrySafeDoors=false`, e portas reforçadas sem
ter a Força exigida), sem ferramenta, sem distância, sem rolar RNG, repetidamente, ganhando XP de
Força a cada chamada.

### Solução recomendada

A mesma do Codex: eliminar o protocolo `prySuccess`/`pryFailure`; cliente envia só `pryAttempt`
(coordenadas + kind); servidor resolve o alvo, valida distância/Z, ferramenta ainda na posse do
jogador, `isBlockedBySafehouse`, `canForceReinforced` quando aplicável, recalcula o RNG com
`Pry.roll` no próprio servidor, aplica o resultado e sincroniza. Adicionar rate limit por
jogador+coordenada.

### Teste de regressão

Igual ao já listado em `02_CODEX_FINDINGS.md` (singleplayer, dedicado, sem ferramenta, longe, porta
de safehouse com a opção desligada, porta reforçada sem Força, replay/spam, alvo destrancado durante
a ação).

---

## CLD-002 / PRE-002 / CDX-002 — Climb Ladders aceita teleporte incremental sem provar escada

```text
Status: CONFIRMED_INDEPENDENTLY — refutação tentada e falhou
Severidade: CRITICAL
Confiança: CONFIRMED_STATIC
Módulo: LS_ClimbLadders
Lado: client -> server
```

### Verificação feita

Li `SubirEscaleras_Server.lua` por completo (69 linhas, o arquivo inteiro). Procurei qualquer
cooldown/rate-limit em qualquer outro arquivo do módulo:

```bash
grep -rn "cooldown|rateLimit|lastClimb|throttle|lastRequest" Contents/mods/LS_ClimbLadders/
# zero resultados
```

### O que confirma o achado

- `isReasonable()` só compara `args.x/y/z` recebidos contra a posição atual do jogador no servidor,
  com margem de `MAX_HORIZONTAL=2` e `MAX_VERTICAL=8`. Não resolve nenhum objeto "escada" — a
  detecção de escada inteira vive em `client/SubirEscaleras/`, nunca carregado no servidor dedicado.
- `player:teleportTo(args.x, args.y, args.z)` roda incondicionalmente se `isReasonable` passar.
- O próprio comentário de cabeçalho do arquivo (linhas 9-11) já reconhece o risco genérico ("sem
  limites seria um teletransporte livre"), mas a mitigação implementada (delta desde a posição atual)
  não impede encadeamento: a posição do servidor é atualizada a cada chamada aceita, então o próximo
  pacote parte da nova posição. Nada limita quantas vezes por segundo isso pode repetir.

### Achado adicional

`MAX_VERTICAL = 8` é o salto vertical isolado mais generoso entre os cinco PRE-items — um único
pacote aceito pode cruzar até 8 níveis de Z de uma vez (cerca de um prédio inteiro), sem nenhuma
verificação de que existe piso, escada ou qualquer superfície válida no destino. Combinado com a
ausência total de rate limit, um cliente automatizado pode encadear isso em velocidade de rede, não
limitada por nenhum cooldown do próprio mod.

### Impacto

Confirmado: teleporte arbitrário por composição de pequenos saltos aceitos, atravessando pisos e
paredes, sem exigir escada real, sem cooldown. Servidor retransmite `climbed` para todos os clientes
como se fosse legítimo.

### Solução recomendada

Igual ao Codex: protocolo `requestClimb` com referência da escada de origem, servidor resolve o
objeto e calcula o único destino válido, valida origem/destino transitáveis, aplica cooldown por
jogador.

---

## CLD-003 / PRE-003 / CDX-004 — PSR PowerBank não valida qual terminal/bank o jogador tem direito de operar

```text
Status: CONFIRMED_INDEPENDENTLY — refutação tentada e falhou
Severidade: CRITICAL
Confiança: CONFIRMED_STATIC
Módulo: LS_PlyskenSolarRevolution
Lado: client -> server
```

### Verificação feita

Reli `PowerBankSystem_Commands.lua` (funções `controlDevice`/`controlDeviceGroup` completas, mais
`psrDeviceIsListed`/`collectDeviceCoords`) e `PSRComputerPanel.lua` em torno da abertura do painel
(`OnOpen`, como `self.bx/self.by/self.bz` são preenchidos) especificamente atrás de qualquer sessão
servidor que o Codex sugeriu poder existir via `LinkComputer`.

### O que confirma o achado

- `PSRComputerPanel.OnOpen(player, computer)` (linha 1144) lê
  `computer:getModData().PSR_linkedBank` — **modData comum, replicado a todo cliente em alcance**,
  não um canal autenticado — e guarda em `self.bx/by/bz` no objeto do painel, puramente client-side.
- `controlDevice`/`controlDeviceGroup` resolvem a bank só a partir de `args.bank` enviado pelo
  cliente (`getPowerBank(args.bank)`), sem checar se o `playerObj` remetente está de fato perto,
  logado naquele terminal específico ou tem qualquer vínculo com aquela bank.
- `controlDevice` valida `psrDeviceIsListed` (o dispositivo precisa estar na lista *daquela* bank) —
  uma trava real contra apontar para coordenadas fora da rede escolhida — mas não valida se o
  jogador tinha o direito de escolher *aquela* bank em primeiro lugar.
- `controlDeviceGroup` nem isso: deriva `coords` fresh a partir de `pb`+`dtype` sem checar contra
  nenhuma lista pré-existente associada ao jogador.

### Achado adicional

Busquei por qualquer construção de "sessão" (abrir/fechar terminal, handshake) em todo o módulo —
**não existe nenhuma**. O Codex propôs que `LinkComputer` poderia estabelecer algo assim; não
estabelece — `LinkComputer`/`UnlinkComputer` só gravam/apagam o `PSR_linkedBank` no modData do
computador, que é exatamente o dado público que qualquer cliente já pode ler e forjar. Ou seja, a
lacuna é ainda mais direta do que "falta revalidar uma sessão": **nunca existiu sessão nenhuma para
revalidar**.

### Impacto

Confirmado: cliente modificado pode escolher qualquer Battery Bank carregada no mapa (não apenas a
vinculada ao terminal que está usando) e ligar/desligar remotamente seus dispositivos — incluindo
geladeiras/freezers, que persistem estado via `container:setType`.

### Solução recomendada

Igual ao Codex: sessão servidor curta (jogador + terminal real + bank), criada quando o servidor
efetivamente confirma proximidade/abertura do terminal e revalidada a cada comando; manter
`psrDeviceIsListed` como segunda camada.

---

## CLD-004 / PRE-004 / CDX-005 — Aegis Backup materializa estrutura grande de forma síncrona

```text
Status: CONFIRMED_INDEPENDENTLY (mecanismo) — dimensão exata continua NEEDS_PROFILING
Severidade: HIGH / PERF-HIGH candidato
Confiança: HIGH_CONFIDENCE estática para o mecanismo; NEEDS_PROFILING para o pior caso real
Módulo: LS_AegisPanel
```

### Verificação feita

Li `buildSnapshotJob()` (`Aegis_Backup.lua:748-782`) e `checkDaily()` (`:911-922`) por completo, e
confirmei as constantes citadas (`SNAP_BUDGET=250`, `MAX_COLUMNS=90000`, `MAX_QUEUED=64`) diretamente
no arquivo.

### O que confirma o achado

- `buildSnapshotJob()` constrói `columns = {}` inteiro, de uma vez, dentro da própria chamada —
  **antes** de qualquer budget por tick entrar em ação. O budget (`SNAP_BUDGET`) só governa
  `snapshotStep()`, chamado depois, tick a tick; não limita a construção inicial do array.
- `checkDaily()` (`Events.EveryTenMinutes.Add`) itera **todos** os grupos de zona do servidor
  (`AegisZones.allGroups()`) em um único disparo do callback e chama `buildSnapshotJob()`
  sincronamente para cada um não já enfileirado, até `#queue < MAX_QUEUED` (64). Ou seja: em um
  único tick de `EveryTenMinutes`, o servidor pode construir até 64 arrays `columns` completos, um
  atrás do outro, sem ceder o main thread entre eles.

### Avaliação de confiança (mais conservadora que o número do Codex)

O teto teórico de 5.760.000 tabelas (90.000 × 64) exige 64 zonas DIFERENTES cada uma perto do teto
individual de 90.000 colunas — isso corresponderia a uma área de ~300×300 tiles por zona, o que é
extremo para uma safehouse real mesmo com anexos agrupados. Não tenho como medir a distribuição real
de tamanho de zona em um servidor de produção a partir do código sozinho. O que está **confirmado
sem depender de medição** é o mecanismo em si: a construção é incondicionalmente síncrona por job e
o loop de automação diária não distribui a construção entre ticks — só a resenha/gravação depois.
Mesmo um cenário bem mais modesto (10-20 zonas médias no mesmo tick diário) já é uma alocação
significativa de tabelas pequenas e potencial stall do main thread sem medição prévia, o que já
satisfaz o critério HIGH desta revisão ("I/O pesado no main thread" / "spike severo no main thread")
independente do teto teórico.

### Solução recomendada

Igual ao Codex/CDX-005: job guarda descritor + cursor, não `columns` pré-computado; streaming
incremental com buffer limitado; budget também na fase de enfileiramento de `checkDaily` (não só no
processamento), por tempo ou por número de zonas por tick.

### Próximo passo exato

Instrumentar conforme a seção 12 do plano (`Aegis_Backup.snapshotStep`, `buildSnapshotJob`) com
1/8/64 jobs e zonas de tamanho variado antes de decidir a severidade final; o mecanismo já é
suficiente para reconciliar como HIGH mínimo desde já.

---

## CLD-005 / PRE-005 / CDX-003 — Alice Weapon Sling: bug de escopo Lua confirmado, fila pode travar em `OnTick`

```text
Status: CONFIRMED_INDEPENDENTLY — bug de escopo é determinístico, não depende de runtime
Severidade: HIGH
Confiança: CONFIRMED_STATIC
Módulo: LS_AliceWeaponSling
Lado: client/shared
```

### Verificação feita

Li `ISClothingExtraAction_AliceWeaponSling.lua` linhas 130-310 por completo, com foco em
`preserveHotbarSlot`, `restoreAttachedWeapon` e `onRepairTick`.

### O que confirma o achado — este é o mais simples de verificar dos cinco

`preserveHotbarSlot(data, model)` (linha 149) tem exatamente estes dois parâmetros: `data` e
`model`. No corpo (linhas 155-157):

```lua
item:setAttachedSlot(slotIndex)
item:setAttachedSlotType(slotType)
item:setAttachedToModel(model)
```

`item` e `slotType` **não são parâmetros, não são locais declarados antes deste ponto na função, e
não existem em nenhum escopo superior do arquivo** (confirmei com leitura completa do arquivo até
este ponto — os únicos nomes com significado equivalente são `data.item` e `data.newSlotType`,
usados corretamente em todo o resto do arquivo). Em Lua, uma referência a um nome sem `local`
correspondente resolve para uma variável GLOBAL; se nenhum global com esse nome existir no momento da
chamada — o que é o caso esperado — a linha `item:setAttachedSlot(...)` lança
`attempt to index a nil value (global 'item')`. Isto não é uma hipótese: é um erro de sintaxe válido
mas semanticamente quebrado, 100% determinístico sempre que `preserveHotbarSlot` é efetivamente
chamada.

`preserveHotbarSlot` é chamada de `restoreAttachedWeapon` (linha 258-260) exatamente quando
`itemInHands(data.character, data.item)` é verdadeiro — ou seja, sempre que o jogador está com a arma
anexada nas mãos no momento em que o sling é trocado. Esse é um estado alcançável em jogo normal, não
um edge case exótico.

`onRepairTick()` (linha 286-304) chama `restoreAttachedWeapon(data.attached)` (linha 295) **sem
pcall**, e só remove a entrada da fila (`table.remove(repairQueue, index)`) na linha seguinte. Se a
chamada lança, `table.remove` nunca executa para essa entrada; `data.ticks` já está `<= 0` e
permanece assim, então a mesma entrada é reprocessada — e lança de novo — em todo `OnTick`
subsequente (potencialmente até a taxa de frames do cliente), e por estar em um `for` sem proteção
própria, a exceção também interrompe o processamento das entradas restantes daquela mesma passada
(elas são retentadas na passada seguinte, então não ficam presas — só a entrada problemática fica
presa permanentemente).

### Impacto

Confirmado: exception storm por tick no cliente afetado (potencialmente dezenas por segundo),
degradação severa de FPS, callback `onRepairTick` permanentemente instalado (`#repairQueue` nunca
chega a 0 enquanto a entrada quebrada existir), sem qualquer interação de rede necessária —
puramente local ao cliente que troca o sling com a arma nas mãos.

### Segunda fila (`ISAttachItemHotbar_AliceWeaponSling.lua`) — verificada nesta sessão

Li `onRepairTick`/`repairAttachedItem`/`scheduleRepairWindow` por completo
(linhas 101-186). Confirmo o que o Codex apontou: os nomes de campo aqui estão corretos
(`data.item`/`data.slotIndex`/`data.slotType`/`data.model`, todos batendo com o que
`scheduleRepairWindow` grava), **não** há o bug de escopo do primeiro arquivo. Porém o padrão
estrutural perigoso é idêntico: `repairAttachedItem(data)` (linha 148) roda sem `pcall`, e
`table.remove(repairQueue, i)` (linha 149) só executa depois — qualquer exceção dentro de
`repairAttachedItem` ou de `AliceWeaponSling.repairHotbarItem` (não auditada nesta sessão) deixaria a
mesma entrada presa, re-lançando em todo `OnTick` seguinte, exatamente como no primeiro arquivo.

Agravante encontrado: `scheduleRepairWindow` (linha 167) insere **seis entradas** por chamada, uma
para cada atraso em `{1, 2, 5, 10, 15, 30}` — isso é verdade nos dois arquivos (o Codex já havia
citado isso para o primeiro). Se a causa da falha for persistente (não um estado transitório), as
seis entradas de uma mesma troca de sling ficam presas independentemente ao longo do tempo, cada
uma gerando sua própria tempestade de exceções por tick — não é uma falha isolada, é até 6x o
volume por evento de troca.

### Status atualizado

Segunda fila: `CONFIRMED_STATIC` para o padrão estrutural (perigo-antes-de-remover, sem pcall,
sem proteção de lifecycle), mas **não** encontrei um bug de nome/escopo que garanta 100% de
reprodução como no primeiro arquivo — aqui depende de `repairAttachedItem`/`repairHotbarItem`
realmente lançar em algum caminho, o que não confirmei linha a linha na função `repairHotbarItem`
em si (fica fora do escopo desta TimedAction, provavelmente em `AliceWeaponSling_Core.lua` ou
similar — não lido nesta sessão). Severidade recomendada: HIGH pelo padrão estrutural sozinho
(mesmo raciocínio do primeiro arquivo — um "poison the queue forever" é HIGH por si só, mesmo sem
uma causa de disparo 100%-garantida identificada), Confiança `HIGH_CONFIDENCE` (não
`CONFIRMED_STATIC` como o primeiro, por essa lacuna).

### Solução recomendada

Trocar `item`/`slotType` por `data.item`/`data.newSlotType` nas linhas 155-156. Nas duas filas,
mover `table.remove`/invalidação da entrada para ANTES de executar a operação perigosa (ou envolver
a operação em `pcall` e sempre remover depois, com log rate-limited).

### Próximo passo exato

Ler `ISAttachItemHotbar_AliceWeaponSling.lua` por completo (pendente, não bloqueia a reconciliação
deste item — o bug de escopo já confirma HIGH sozinho) e confirmar se o mesmo padrão
perigoso-antes-de-remover se repete lá mesmo sem o erro de nome.

---

---

## CLD-P1-001 — Cyes Push Doors aceita causalidade não-comprovada (achado novo, fora dos 5 PRE-items)

```text
Status: CONFIRMED_STATIC (mecanismo) / NEEDS_RUNTIME (magnitude prática)
Severidade: HIGH
Confiança: CONFIRMED_STATIC
Módulo: LS_CyesPushDoors
Lado: client -> server
Origem: achado por agente de pesquisa dedicado a este módulo (P1), verificado por mim contra o
  código-fonte antes de aceitar (li Core.lua:2374-2411 e CyesPushDoors_Server.lua:100-133
  diretamente e confirmei que os trechos citados batem exatamente).
```

Detalhe completo em `review/01c_CLAUDE_P1_AUTHORITY.md`. Resumo: `validateServerRequest`
(`Core.lua:2374-2411`) e `serverDoorStateMatches` (`CyesPushDoors_Server.lua:122-133`) só verificam
se a porta **está atualmente** no estado alvo (garagem fechada / porta aberta) — nunca se uma
transição **acabou de acontecer**, nem se **este jogador específico** a causou. Como o estado padrão
mais comum (garagem fechada, por exemplo) já bate com o alvo sem nenhuma ação real, um cliente
modificado perto de uma porta/garagem já nesse estado, com um zumbi do lado oposto, pode "colher"
repetidamente (respeitando só os cooldowns de debounce, não uma prova de causalidade) o dano a
zumbis, XP de força e desgaste/quebra de porta de garagem — inclusive em bases de outros jogadores —
sem nunca ter empurrado nada de verdade. Distância, Z, resolução de alvo, RNG e geometria de impacto
são todos corretos e server-side (verificado); a lacuna é especificamente a ausência de prova de
transição recente correlata ao remetente. Solução recomendada: guardar o último estado observado
por porta (chave `getDoorWorldKey`) e só aplicar efeito quando o servidor também tiver testemunhado
uma mudança de estado recente, não apenas o estado estático atual.

`LS_EquipWhileRunning` foi auditado no mesmo agente (mesmo padrão de 15 pontos) e voltou limpo: a
vulnerabilidade de spoofing de `args.id` já documentada como corrigida (`LOCAL_CHANGES.md` LS-001)
foi reconfirmada como realmente corrigida no código atual (`args.id ~= player:getOnlineID()`
presente). Os outros seis módulos P1 (`Antibodies`, `ProximityInventory`, `ImprovisedSilencers`,
`MiniHealthPanel`, `CleanHotBar`, `FixedLightOnBeltAF`) não têm nenhuma superfície
`Events.OnClientCommand` — confirmado por busca textual completa em cada árvore de arquivos, não só
pela tabela agregada de `00_INVENTORY.md`. Ver `01c` para o detalhe módulo a módulo.

---

## TV-001 — TimeVote: registro `liveNetActions` sem TTL/limpeza por desconexão (achado novo)

```text
Status: aguardando refutação do Codex (seção 17 do plano)
Severidade: HIGH
Confiança: NEEDS_RUNTIME (mecanismo de ausência de safety-net confirmado estaticamente; taxa real de
  crescimento depende de net:getProgress() continuar retornando valor válido para um NetTimedAction
  abandonado/desconectado, não verificável sem rodar o jogo)
Módulo: LasciviousScripts / TimeVote
Lado: server
Origem: achado por agente de pesquisa dedicado (WanderingZombies/TimeVote/ZombieDecay), verificado
  por mim contra o código-fonte antes de aceitar.
```

Detalhe completo em `review/01b_CLAUDE_WANDERING_TIMEVOTE_ZOMBIEDECAY.md` seção 2.4. Resumo:
`liveNetActions` (`Server.lua:241`) é populado por um override global de `emulateAnimEvent`, sem
filtro por módulo — qualquer `NetTimedAction` do servidor inteiro pode entrar. A única via de saída é
`progress >= 1` ou erro do engine ao chamar `net:getProgress()`; não existe um contador de ticks
estagnados equivalente ao que o registro irmão `injectedActions` já usa (`noNet > 600`), nem qualquer
handler de `OnDisconnect`. `driveNetRegistry` itera essa tabela **todo tick do servidor**, então cada
entrada morta (se a suposição de engine acima se confirmar) também vira custo de CPU por tick que
cresce ao longo da sessão — memória + CPU, não um crash imediato. Autoridade de voto/consenso do
TimeVote foi auditada separadamente e está limpa (identidade sempre do engine, sem double-vote,
roster se autocura em até 1 tick de qualquer desconexão) — este achado é puramente sobre o registro
de duração de `NetTimedAction`, não sobre o mecanismo de votação em si.

### Solução recomendada

Aplicar a `liveNetActions` a mesma defesa que `injectedActions` já tem: contador de ticks sem
progresso observado, removendo a entrada após um teto. Alternativa complementar: handler de
`OnDisconnect`/`OnPlayerDeath` que varre e remove entradas cujo dono não está mais presente.

---

## ZD-001 — ZombieDecay: `Core._originalLore` recapturado a cada boot do processo, não por save (achado novo)

```text
Status: aguardando refutação do Codex (seção 17 do plano)
Severidade: HIGH
Confiança: HIGH_CONFIDENCE
Módulo: LasciviousScripts / ZombieDecay
Lado: shared (efeito visível em client e server)
Origem: achado por agente de pesquisa dedicado (WanderingZombies/TimeVote/ZombieDecay), verificado
  por mim contra o código-fonte antes de aceitar.
```

Detalhe completo em `review/01b_CLAUDE_WANDERING_TIMEVOTE_ZOMBIEDECAY.md` seção 3.5. Resumo:
`Core._originalLore` (`Core.lua:35`) é uma variável de módulo comum, não persistida em
`ModData`/`GlobalModData`. `captureOriginalLore()` só verifica "já capturei nesta execução do
processo", não "já capturei alguma vez neste save". Como as sandbox options do `ZombieLore`
persistem entre restarts do servidor (é assim que edições ao vivo de admin sobrevivem), qualquer
restart de servidor ocorrido enquanto o ZombieDecay já estava decaindo ativamente faz a primeira
chamada seguinte de `applyVanillaLore()` recapturar o valor **já decaído** como se fosse o preset
original do admin — corrompendo silenciosamente o ponto de restauração para sempre a partir daquele
restart. Não requer nenhuma ação maliciosa; acontece em qualquer manutenção normal de servidor de
longa duração (os próprios cenários de 24h/72h do plano tipicamente incluem ao menos um restart). Sem
NaN/valor inválido no rewriting de `ZombieLore` (cadeia aritmética inteira tem clamp/guarda,
verificado) e sem double-apply de migração (recompute contínuo e idempotente a partir da idade do
mundo do próprio engine, não uma migração one-shot) — ambos checados explicitamente e limpos.

### Solução recomendada

Persistir `_originalLore` uma única vez por save em `GlobalModData`, análogo ao padrão
`modData.ver = WZ_SANDBOX_VERSION` que `LS_WanderingZombies_SandboxVars.lua` já usa para o mesmo tipo
de problema. Saves já afetados por esta falha não têm como recuperar o preset original retroativamente
— o patch só previne recorrência futura.

---

## Verificações limpas (sem achado CRITICAL/HIGH) — registradas para não serem re-auditadas à toa

### LS_BetterPush — autoridade de rede

Li `BetterPush_Server.lua` (arquivo inteiro, 96 linhas) e `BetterPush_Shared.lua` (arquivo inteiro,
178 linhas). `onClientCommand`: rate limit autoritativo por `player:getOnlineID()` com timestamp de
servidor (350ms, não contornável pelo cliente); `findZombie` resolve o zumbi a partir da lista do
próprio servidor com raio de fallback limitado (1.5 tiles), nunca confia em referência de objeto do
cliente; distância entre o zumbi resolvido e a posição real do jogador é validada server-side
DEPOIS da resolução (não usa as coordenadas cruas do cliente para essa checagem); `chance` vem de
`player:getPerkLevel(Perks.Strength)` (autoritativo) e o RNG (`ZombRand`) roda no servidor, não é um
resultado recebido do cliente; a cadeia inteira (`getDominoChain`) é computada a partir da lista de
zumbis do próprio servidor, nunca recebida do cliente. Nenhum dos 5 padrões de bypass encontrados em
PRE-001/002/003 se repete aqui. Combina com a avaliação do Codex em `PERF-CAND-001` (autoridade OK,
só performance em aberto). **Não precisa de nova auditoria de autoridade**, apenas o profiling de
escala que o Codex já propôs.

### P2 com `OnClientCommand` (rodada 3 do plano) — LS_ImmersiveSuicide, LS_PushVehicle, LS_TotalWeightRebalance

Os demais módulos P2 do inventário (`LS_DragBodiesFaster`, `LS_OSRSExperienceBar`,
`LS_ResponsivePivoting`, `LS_TacticalHold`, `LS_SkullysFasterAttackSpeed`,
`LS_SkullysFasterSwingSpeed`, `LS_FasterHoodOpening`, `LS_BetterEngineRepair`,
`LS_DurableToolsWeapons`) não têm nenhum registro `OnClientCommand` (confirmado pela coluna CC=0 do
inventário, sem necessidade de leitura linha a linha). Só três P2 tinham CC=1 e foram lidos por
completo:

- **`LS_ImmersiveSuicide`** (`ImmersiveSuicideServer.lua`, 44 linhas): os dois comandos
  (`requestSynchronizedCharacterFX`, `requestPerformSuicide`) operam exclusivamente sobre o `player`
  que o próprio engine passa como parâmetro do evento — `args` nunca contém um ID de alvo, o comando
  não consegue apontar para outro personagem. Pior caso de abuso é o jogador suicidar a si mesmo
  repetidamente, o que ele já pode fazer sem o mod. Limpo.
- **`LS_PushVehicle`** (`PushVehicle_Server.lua`, 309 linhas): `requestPush` resolve o veículo por
  `getVehicleById(args.vehicle)` mas revalida tudo server-side antes de aplicar qualquer efeito —
  `validateRequest` usa a posição real do `playerObj` (não coordenadas do cliente) para exigir
  proximidade (`MAX_REQUEST_DISTANCE_SQ=25`, ~5 tiles), velocidade quase nula do veículo
  (`MAX_START_SPEED_KMH=1.0`), e endurance mínima; a direção/magnitude do empurrão é toda calculada
  server-side a partir da geometria real do veículo (`getPushData`), nunca recebida do cliente; o
  modo "turn" é explicitamente re-bloqueado server-side mesmo que o cliente minta sobre o sandbox.
  Nenhum padrão CLD-001/002/003 se repete. Observação sem escalada: cada push bem-sucedido também
  transfere a autoridade de física do veículo (`authorizationServerOnSeat`) para quem empurrou, sem
  cooldown — em teoria permite "roubar" a autoridade de física de um veículo estacionado repetidas
  vezes, mas isso não atinge o critério HIGH desta revisão (sem corrupção de estado persistente, sem
  crescimento ilimitado, sem crash), é no máximo um incômodo cosmético de física. Limpo.
- **`LS_TotalWeightRebalance`** (`apply_weights.lua`, `onClientCommand` linhas 170-181): `setWeight`
  exige `player:getAccessLevel()` (lido do objeto do engine, não de `args`) ser exatamente `"admin"`
  antes de aceitar qualquer alteração; peso é validado por `isValidWeight`/`applyScriptWeight`
  (rejeita não-numérico, negativo, infinito) antes de persistir. Comando corretamente restrito a
  admin real. Limpo.

### LS_AegisPanel — por que não reabri a autoridade dos outros 21 comandos aqui

O módulo já recebeu uma auditoria dedicada de autoridade durante sua própria integração (ver
`vendor/aegis-panel/INTEGRATION.md`), cobrindo os 26 arquivos de servidor com tabela `Commands` e
respondendo explicitamente à pergunta "o servidor confia em coordenadas/IDs/strings de tipo do
cliente sem validar contra o estado real do mundo?" para cada um. O modelo de autoridade do Aegis é
por design diferente do PSR (PRE-003): um admin com a área liberada (`AegisRoles.canArea`) tem
permissão de agir sobre QUALQUER alvo daquele domínio — isso é a definição de um painel de
administração, não um bug de escopo. A exceção seria um comando de auto-serviço (não-admin) que
devesse ser limitado ao próprio jogador/objeto e não o é; a auditoria original já examinou
especificamente os arquivos de auto-serviço (`Aegis_PlayerClaims`, `Aegis_PlayerPanel`,
`Aegis_PlayerVehicles`, as metades `PlayerCommands` de `Aegis_Kits`/`Aegis_Boost`) e não encontrou
esse padrão. Não re-auditei linha a linha nesta sessão — meu next step abaixo mantém isso como
`NEEDS_RUNTIME`/pendência de segunda opinião, não como confirmado por mim agora, já que a auditoria
original não seguiu o formato desta revisão pré-release.

---

## Alterações de código

```text
Nenhuma. Primeira passada preservada, conforme a regra operacional do plano.
```

## Próximo passo vigente para o handoff

Não executar a lista histórica acima. PRE-items, Cyes, ZombieDecay, Aegis e overrides foram
reconciliados; oito achados estão corrigidos e a revisão estática crítica terminou. Abrir
`review/06_RUNTIME_TEST_MATRIX.md`, executar o próximo gate possível e registrar o resultado no
mesmo ciclo. Candidatos `NEEDS_PROFILING` sem evidência grave não bloqueiam o release.
