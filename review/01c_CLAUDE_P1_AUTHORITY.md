# 01c — Claude P1 network-authority audit

**Status da passada:** `HISTORICAL_COMPLETE — ACHADOS JÁ RECONCILIADOS/CORRIGIDOS`
**Última atualização:** 2026-08-26
**Escopo:** módulos P1 designados — `LS_Antibodies`, `LS_CyesPushDoors`, `LS_EquipWhileRunning`,
`LS_ProximityInventory`, `LS_ImprovisedSilencers`, `LS_MiniHealthPanel`, `LS_CleanHotBar`,
`FixedLightOnBeltAF` — com foco em autoridade de rede (client→server) conforme seção 6.1/8 do plano.
**Nota de handoff vigente:** Cyes já foi reconciliado e corrigido; os demais P1 fecharam sem
blocker. Não reiniciar esta passada. Próximo gate: `06_RUNTIME_TEST_MATRIX.md`. As observações do
corpo permanecem como histórico da auditoria original.

## Metodologia

Antes de ler qualquer handler, confirmei diretamente no código (não confiando apenas em
`00_INVENTORY.md`) onde `Events.OnClientCommand.Add` (handler servidor recebendo comando do
cliente) e `Events.OnServerCommand.Add` (handler cliente recebendo broadcast do servidor) realmente
existem nos oito módulos, via:

```bash
rg -n 'Events\.OnClientCommand\.Add|Events\.OnServerCommand\.Add|sendClientCommand|sendServerCommand' \
  Contents/mods/<modulo> -g '*.lua'
```

Confirmação da direção da API (verificada no próprio código, não por memória): `sendClientCommand`
é chamado do lado **cliente** e é recebido no **servidor** via `Events.OnClientCommand.Add`
(callback `(module, command, player, args)`); `sendServerCommand` é chamado do lado **servidor** e é
recebido no **cliente** via `Events.OnServerCommand.Add`. Portanto o handler crítico para o checklist
de 15 pontos (cliente hostil → servidor) é sempre `OnClientCommand`, nunca `OnServerCommand`.

Resultado da varredura direta (diverge um pouco da tabela lexical de `00_INVENTORY.md` porque a
tabela conta `CC`/`SC` agregando arquivos, não a direção real confirmada por leitura):

| Módulo | `OnClientCommand.Add` (servidor) | Handler(s) | Ação |
|---|---|---|---|
| `LS_Antibodies` | 0 (nenhum) | — | wrapper `sendClientCommand` morto, nunca chamado; sem risco de rede |
| `LS_CyesPushDoors` | 1 | `CyesPushDoors_Server.lua:321` | auditoria completa de 15 pontos |
| `LS_EquipWhileRunning` | 1 | `RunningActionsServer.lua:12` | auditoria completa de 15 pontos |
| `LS_ProximityInventory` | 0 | — | nenhum código de rede no módulo inteiro |
| `LS_ImprovisedSilencers` | 0 | — | só `OnServerCommand` (servidor→cliente); sem handler client→server |
| `LS_MiniHealthPanel` | 0 | — | nenhum código de rede no módulo inteiro |
| `LS_CleanHotBar` | 0 | — | nenhum código de rede no módulo inteiro |
| `FixedLightOnBeltAF` | 0 | — | nenhum código de rede no módulo inteiro |

Os dois módulos com handler real (`LS_CyesPushDoors`, `LS_EquipWhileRunning`) recebem o checklist de
15 pontos completo. Os outros seis recebem confirmação de "sem superfície de rede client→server" mais
a passada leve de TimedAction/monkey-patch/lifecycle listada na seção 9/11 do plano.

---

## Módulo: `LS_CyesPushDoors`

**Rede:** `Events.OnClientCommand.Add(onClientCommand)` em
`Contents/mods/LS_CyesPushDoors/42/media/lua/server/CyesPushDoors_Server.lua:321`, comandos
`doorOpened` (linhas 251-319) e `zombieImpactAck` (linhas 242-249, só logging — servidor não age
sobre o conteúdo, sem risco).

### Leitura feita

Arquivo completo lido: `CyesPushDoors_Server.lua` (328 linhas, inteiro). Em `Core.lua` (2413 linhas)
li integralmente: `validateRequestEnvelope`/`queueDoorReport`/`resolvePendingDoor`/
`processPendingDoors` (server file), `CPD.resolveDoorImpact` (2087-2340), `CPD.findDoor` (2363-2372),
`CPD.validateServerRequest` (2374-2411), `CPD.getImpactBandFromPreferred`/`getInteractionImpactContext`
(942-1037), `CPD.collectTargetsFromSquares`/`collectTargets` (1062-1250), `CPD.isDuplicateImpact`
(637-657), `CPD.getDoorWorldKey`/`getPlayerDoorDistanceSq` (610-630), `CPD.prepareZombieHealth`/
`queueZombieDamageVerification`/`updatePendingZombieDamage` (1435-1535). Também apliquei o checklist
de 15 pontos ponto a ponto contra esse fluxo.

### Aplicação do checklist de 15 pontos (`doorOpened`)

```text
1. Intenção ou resultado? -> HÍBRIDO: cliente afirma "eu empurrei esta porta agora" (intenção +
   resultado implícito). O servidor não pede só a intenção; aceita a alegação de causalidade.
2. Tipo validado? -> sim, CPD.isSupportedDoor(object) contra o objeto real resolvido no square.
3. Distância validada? -> sim, <= 2.25 tiles (validateRequestEnvelope + validateServerRequest).
4. Z validado? -> sim, sq:getZ() == player:getZ() nos dois validadores.
5. Target resolvido pelo servidor? -> sim, CPD.findDoor(args) usa x/y/z/index para buscar o objeto
   real via getCell():getGridSquare()->getObjects():get(index); não confia em referência do cliente.
6. Permissão validada? -> não aplicável (porta pública), mas ver achado abaixo sobre causalidade.
7. Safehouse validada? -> não aplicável a este mecanismo (não é sobre trancas, é sobre impacto físico
   na porta/zumbis do outro lado); nenhuma verificação de posse/segurança do dono do imóvel existe
   nem parece ser o modelo do mod.
8. Item/ferramenta validado? -> não aplicável (mecânica é corporal, não usa ferramenta).
9. RNG recalculado no servidor? -> SIM — knockdown set, cap de zumbis afetados e shuffledCopy rodam
   inteiramente em Core.lua no servidor; strength/fitness são lidos do character server-side
   (CPD.getStrength/getFitness). Não há RNG do cliente sendo aceito.
10. Rate limit? -> sim, em três camadas: cooldown por porta (900ms, CyesPushDoors_Server.lua:26-29),
    dedupe por porta (CPD.isDuplicateImpact, IMPACT_DEDUPE_MS), e recovery pessoal por jogador
    (CPD.isImpactRecoveryActive, ~750ms+ escalando com strain, Core.lua:214-228).
11. Replay? -> mitigado pelos cooldowns acima, mas nenhum nonce; ver achado abaixo.
12. Packet duplicado? -> pendingDoors dedup por playerKey mantém só o melhor candidato por jogador
    por porta (queueDoorReport:105-109); não é o problema aqui.
13. ID pode ter mudado? -> resolvido: CPD.findDoor releitura sempre a partir de coordenadas+index
    reais, mais isSupportedDoor(); um index obsoleto simplesmente falha a resolver, não é explorável.
14. Target pode estar unloaded? -> getCell():getGridSquare() retorna nil se não carregado -> findDoor
    retorna nil -> envelopeValid=false -> rejeitado. Coberto.
15. Cliente chama sem abrir UI? -> SIM, é exatamente esse o vetor: sendClientCommand é chamado direto
    de Hook.lua:409 a partir de um hook de evento, não de um menu; um cliente modificado pode chamar
    isso a qualquer momento sem nunca ter realizado a interação real de empurrar a porta.
```

### CLD-P1-001

```text
ID: CLD-P1-001
Severidade: HIGH
Confiança: CONFIRMED_STATIC (mecanismo) / NEEDS_RUNTIME (magnitude prática do abuso)
Módulo: LS_CyesPushDoors
Lado: client -> server
Arquivo: Contents/mods/LS_CyesPushDoors/42/media/lua/server/CyesPushDoors_Server.lua
Linha: 239-319 (onClientCommand), com CPD.validateServerRequest em
       Contents/mods/LS_CyesPushDoors/42/media/lua/shared/CyesPushDoors/Core.lua:2374-2411 e
       CPD.resolveDoorImpact em Core.lua:2087-2340
Função: onClientCommand / CPD.validateServerRequest / CPD.resolveDoorImpact
Trigger: cliente modificado envia "CyesPushDoors"/"doorOpened" com interaction=true, coordenadas e
  index de uma porta real, sem nunca ter executado a ação de empurrar de fato.
```

**Cenário mínimo:** Um jogador (ou zumbi, ou qualquer evento do mundo) já deixou uma porta comum
aberta, ou uma porta de garagem já está no estado padrão fechado (o estado inicial mais comum do
jogo). Um cliente hostil se aproxima até <= 2.25 tiles dessa porta, no mesmo Z, com pelo menos um
zumbi (ou jogador) posicionado na faixa de impacto do lado oposto da porta. Ele envia repetidamente
`doorOpened` com `interaction=true` e a `transition` que já corresponde ao estado atual real da porta
(sem nunca ter aberto/fechado nada) — respeitando apenas os cooldowns de 900ms/porta e ~750ms+/jogador
para não ser descartado por `isDuplicateImpact`/`isImpactRecoveryActive`.

**Estado esperado:** O servidor só deveria aplicar dano/knockback a zumbis, desgaste de porta e chance
de quebra de garagem quando o jogador remetente **de fato** acabou de realizar a interação de
push/empurrão que causou aquela transição de estado — ou seja, existir prova de causalidade, não só
de coincidência de estado.

**Estado atual:** `CPD.validateServerRequest` (Core.lua:2374-2411) e `serverDoorStateMatches`
(CyesPushDoors_Server.lua:122-133) verificam apenas se a porta **está atualmente** no estado alvo
(`getLogicalDoorOpenState(door)` igual a `false` para fechar garagem / `true` para abrir porta comum)
— não se uma transição **acabou de acontecer** nem se **este jogador específico** foi quem a causou.
Nenhuma variável server-side (ex.: "última transição desta porta veio de qual player, em qual tick")
é comparada contra o remetente. `CPD.isDuplicateImpact` (Core.lua:637-657) e o cooldown de porta
(CyesPushDoors_Server.lua:26-29) são *debounces por porta*, não provas de causalidade — qualquer
jogador diferente pode disparar assim que a janela de cooldown expirar, mesmo sem nenhuma nova
transição real ter ocorrido, desde que o estado "congelado" da porta continue batendo com o
`transition` pedido (o que é quase sempre verdade para portas já abertas ou garagens já fechadas — o
estado padrão mais comum do jogo).

**Impacto:** Um cliente modificado pode "sequestrar" o resultado de push (dano a zumbis, knockdown,
XP indireto via `applyArmStrain`, e desgaste/possível destruição da porta de garagem via
`applyDoorWear`/`rollGarageBreakChance`) em qualquer porta que já esteja no estado alvo, incluindo
portas/garagens de bases de outros jogadores, sem nunca ter de fato empurrado nada — bastando estar
fisicamente perto e haver um zumbi (ou jogador) do lado oposto no momento. Isso é uma lógica
autoritativa incompleta que permite abuso de uma mecânica de combate/dano fora do controle real do
jogo, incluindo dano a bens de terceiros (portas de garagem) sem autorização real do dono.

**Escala:** Não é um finding de performance; o custo por chamada aceita é limitado (um scan de squares
adjacentes à porta), mas nada limita quantas portas *diferentes* um único cliente pode "colher" por
segundo (o cooldown de recovery é por-jogador-global, então o atacante fica limitado a ~1
impacto/750ms+ no total, não por porta — ainda assim, dado um mapa com muitas portas fechadas e
zumbis por perto, é suficiente para abuso sustentado ao longo de uma sessão).

**Evidência:**
```lua
-- Core.lua:2403-2408 (validateServerRequest) — só checa estado atual, não transição/causalidade
local open = CPD.getLogicalDoorOpenState(door)
if garage then
    if open ~= nil and open ~= false then return false end
else
    if open ~= nil and open ~= true then return false end
end
return true
```
```lua
-- CyesPushDoors_Server.lua:122-133 (serverDoorStateMatches) — mesmo padrão, sem histórico
local ok, open = pcall(function() return door:IsOpen() end)
if not ok then return false end
if garage then return open == false end
return open == true
```

**Complexidade:** O(1) por porta por chamada; não escala mal, o problema é de autoridade, não de
performance.

**Memória:** Nenhuma. As tabelas de suporte (`pendingDoors`, `doorCooldowns`, `_recentImpacts`,
`_impactRecoveryUntil`, `_pendingZombieDamage`, `_pendingZombieNetworkVerify`) já foram lidas e têm
limpeza própria (idade, ticks, ou `isAlive()`); nenhuma cresce sem limite nesta análise. Único detalhe
menor sem gravidade: `_impactRecoveryUntil[character]` fica com uma entrada residual por jogador que
já empurrou pelo menos uma vez e nunca mais tenta (não é limpo no disconnect), mas isso é O(jogadores
distintos que já usaram a mecânica), não cresce sem limite ao longo da sessão — não elevo isso a
achado separado.

**Possível crash:** Não. O handler tem `pcall` ao redor de `CPD.resolveDoorImpact` (linha 202-208 do
server file) e todas as chamadas para a API do jogo em `Core.lua` passam por `safeCall`.

**Solução recomendada:** Guardar, por porta (chave `getDoorWorldKey`), o estado observado no tick
anterior do `OnTick` do próprio mod (ou usar `Events.OnObjectStateChanged`/equivalente, se existir na
build alvo) e só aceitar `doorOpened` como "resolvível com efeito" quando o servidor também tiver
testemunhado uma mudança de estado recente correlata (janela curta, ex.: últimos 1-2 ticks) — não
apenas o estado atual estático. Alternativamente, anexar ao pedido um "proof token" gerado
client-side apenas no momento real da interação (ex.: id de TimedAction/interação vanilla em
andamento) e validar que esse token corresponde a uma ação real e recente daquele jogador específico
sobre aquela porta específica.

**Risco da solução:** Médio — exige acompanhar o estado de todas as portas suportadas em vez de só
reagir a relatos, ou instrumentar a interação vanilla real. Deve preservar o caso legítimo em que o
"scanner" (não-interação) reporta portas abertas remotamente por zumbis/outros jogadores para fins de
sincronização — não quebrar esse fluxo ao adicionar a exigência de causalidade.

**Teste de regressão:**
```text
push legítimo (transição real, jogador que empurrou): efeito aplicado normalmente
push legítimo repetido rapidamente: respeitando cooldowns, sem duplicar
scanner report (porta aberta por zumbi/outro jogador): ainda sincroniza corretamente sem aplicar
  impacto ao "reportador" que não empurrou
cliente hostil parado perto de porta já no estado alvo, sem interação real, com zumbi do lado
  oposto: comando deve ser rejeitado (não aplicar dano/desgaste)
garagem já fechada de base alheia com zumbi perto: não deve poder ser "quebrada" por push forjado
disconnect durante pendingDoors/recovery: sem exceptions, sem referência presa
```

### Outras observações desta módulo (não promovidas a finding)

- O geometria de `preferredImpactSquare` é corretamente limitada pelo servidor a uma das duas faixas
  físicas válidas ao lado da porta (`CPD.getImpactBandFromPreferred`, Core.lua:996-1006) — o cliente
  escolhe apenas *qual lado* é atingido, nunca coordenadas arbitrárias distantes. Isso é o padrão
  correto (mesma família do "golden standard" já visto em outros módulos do pacote).
- `CPD.collectTargetsFromSquares`/`collectTargets` re-escaneiam os squares reais no servidor para
  achar zumbis/jogadores — não confiam em uma lista de alvos enviada pelo cliente. Correto.
- `CPD.updatePendingZombieDamage` (Core.lua:1480-1535) reafirma a saúde do zumbi calculada pelo
  servidor por alguns ticks após o impacto, o que corrige ativamente qualquer tentativa de desync do
  cliente sobre a vida do zumbi — postura defensiva correta, não um problema.
- `zombieImpactAck` (linha 242-249) é só log; o servidor nunca usa esse ack para decidir nada, então
  não há vetor de confiar num "resultado" do cliente ali.
- Passada leve de monkey-patch/TimedAction: este módulo não usa `ISTimedAction`/`ISBaseTimedAction`
  para a mecânica de push (é resolvido diretamente no comando de rede, sem TimedAction própria) e não
  registrei overrides completos de classes vanilla em `Hook.lua`/`Core.lua` além de hooks de evento
  (`Events.*`) — não head full-override sem call-through neste módulo.

---

## Módulo: `LS_EquipWhileRunning`

**Rede:** `Events.OnClientCommand.Add(OnClientCommand)` em
`Contents/mods/LS_EquipWhileRunning/42/media/lua/server/RunningActionsServer.lua:12`, único comando
`SyncAnimVar`.

### Leitura feita

Arquivo servidor completo (11 linhas, inteiro). Arquivo cliente completo até a seção de rede e overrides
relevantes (`Contents/mods/LS_EquipWhileRunning/42/media/lua/client/EqiupWhileRunning.lua`, funções
`setSyncedVariable`/`OnServerCommand` linhas 76-114, mais leitura de todos os 20 call sites de
`setSyncedVariable` para confirmar frequência/uso). Também li
`vendor/equip-while-running/LOCAL_CHANGES.md` (entradas LS-001/LS-002) e confirmei no código atual que
a correção documentada realmente está presente — não aceitei a documentação sem checar.

### Aplicação do checklist de 15 pontos (`SyncAnimVar`)

```text
1. Intenção ou resultado? -> resultado (cliente relata o valor final de uma variável de animação do
   PRÓPRIO personagem local).
2/3/4/6/7/8/9. Não aplicável na maioria — este comando não move nada autoritativo (posição, save,
   inventário, RNG de jogo); é só uma variável de estado de animação (AnimSet param), replicada aos
   outros clientes para exibição visual.
5. Target resolvido pelo servidor? -> o servidor não resolve um "alvo" separado: usa o próprio
   `player` que o engine já autenticou como remetente do pacote (parâmetro do callback
   `OnClientCommand(module, command, player, args)`), e valida explicitamente
   `args.id == player:getOnlineID()` antes de repassar (linha 7) — não confia no id que veio dentro
   de `args` para decidir QUEM sofre o efeito, só usa para o relay downstream re-identificar o mesmo
   jogador nos clientes remotos.
10. Rate limit? -> nenhum explícito, mas todos os 20 call sites legítimos de `setSyncedVariable` são
    disparados só em transições discretas de start/stop de ação (equipar/desequipar/anexar/transferir),
    não em OnTick; um cliente hostil poderia floodar mais rápido que isso, mas o efeito de cada pacote
    é cosmético (ver Impacto).
11/12. Replay/duplicado? -> sem nonce, mas reaplica só uma variável de display; replay não muda nada
    autoritativo.
13/14. ID mudou / target unloaded? -> o "target" é sempre o próprio remetente (ver ponto 5), então não
    há problema de resolução de outro objeto.
15. Cliente chama sem abrir UI? -> sim, mas o efeito está limitado ao próprio personagem do remetente.
```

### Achado: já mitigado, confirmado no código atual (não é finding novo)

`vendor/equip-while-running/LOCAL_CHANGES.md` (entrada LS-001) documenta que a versão upstream original
deste arquivo repassava `args` sem validar `args.id`, permitindo que um cliente hostil escolhesse o
`onlineID` de **outro** jogador e fizesse o servidor aplicar `setVariable(args.var, args.val)` no
personagem de terceiros, em todos os clientes conectados — isso teria sido classificável como HIGH sob
esta revisão ("cliente não confiável alterando estado replicado de outro jogador"). Confirmei
diretamente no código atual (`RunningActionsServer.lua:7`) que a correção documentada está de fato
presente:

```lua
if not args or args.id ~= player:getOnlineID() then return end
```

Isso reduz o alcance do comando estritamente ao próprio personagem do remetente. O `var`/`val` em si
continuam sem allowlist (um cliente hostil pode escolher qualquer nome de variável de animação e
qualquer valor, exibido para outros jogadores), mas o efeito prático fica confinado a como o PRÓPRIO
personagem do atacante é renderizado/animado nas telas alheias — não há como afetar outro jogador, não
há dado de save ou stat de gameplay envolvido (`character:setVariable` é uma variável de FSM de
animação, não estado autoritativo). Isso fica abaixo do critério HIGH desta revisão (é, na pior
hipótese, um grief cosmético contra a própria aparência do atacante). Não abro finding novo aqui;
reporto como verificado e confirmado limpo.

### Outras observações desta módulo (não promovidas a finding)

- `ISEquipWeaponAction:new` (client file, linha 126 em diante) é um **full override sem
  call-through** do construtor vanilla (o próprio código tem um comentário `-- TOFIX: Find out why not
  reusing vanilla code causes not equipping bug`, reconhecendo a decisão). Isso é o padrão "alto risco"
  da seção 11 do plano (full replacement, sem call-through). Não elevo a finding HIGH nesta passada
  porque: (a) é uma limitação já conhecida e documentada pelo próprio autor do código (não uma
  regressão silenciosa), (b) não há evidência de que impeça o mundo/servidor de carregar (os
  validators/syntax check do snapshot passaram), e (c) o efeito relatado no próprio TOFIX é um bug de
  UX ("not equipping" em algum caso), não um crash ou corrupção. Registro aqui para que uma leitura
  futura, se houver tempo, compare campo a campo contra `ISBaseTimedAction.new`/`ISEquipWeaponAction.new`
  vanilla da build 42.20.x e confirme se algum campo novo do vanilla ficou de fora.

---


## Módulo: `LS_Antibodies` — CLEAN (sem superfície client→server)

**Verificado:** `Contents/mods/LS_Antibodies/42/media/lua/server/antibodies_server.lua` (131 linhas,
inteiro), `.../client/antibodies_client.lua` (91 linhas, inteiro),
`.../shared/antibodies_network.lua` (21 linhas, inteiro).

Este módulo **não possui nenhum `Events.OnClientCommand.Add`** em lugar nenhum da árvore — busquei o
literal `OnClientCommand` no módulo inteiro e não há ocorrência. `AntibodiesNetwork.sendClientCommand`
(antibodies_network.lua:7-9) é um wrapper definido mas **nunca chamado** por nenhum arquivo do módulo
(busquei `AntibodiesNetwork.sendClientCommand` em todo `LS_Antibodies/` — zero call sites). Todo o
fluxo de rede real é servidor -> cliente: `AntibodiesServer.broadcastMedicalFile`
(antibodies_server.lua:82-93) roda a cada `Events.EveryOneMinute`, computa a lista de jogadores
próximos inteiramente no servidor (`computeNearbyPlayerMapping`, distância 3D ao quadrado, sem entrada
do cliente) e empurra o "medical file" via `sendServerCommand`; o cliente só recebe e grava em
`getModData()` local (`AntibodiesClient.recieveMedicalFile`, client file:37-51) — nunca envia esse
dado de volta para o servidor agir sobre ele.

**Conclusão:** nenhum ponto de entrada client→server existe neste módulo; o checklist de 15 pontos não
se aplica por falta de superfície. `onlinePlayersByName`/`nearbyPlayerMapping` são recriados do zero
(`= {}`) a cada minuto — sem crescimento entre ciclos. Nenhum finding.

---

## Módulo: `LS_ProximityInventory` — CLEAN (sem superfície client→server)

**Verificado:** os 4 arquivos Lua do módulo inteiro (572 linhas no total —
`ProximityInventory.lua`, `ISInventoryPage.lua`, `ProximityInventoryLootControls.lua`,
`CraftingFix.lua`). Não existe pasta `server/` no módulo. Busca por
`OnClientCommand|OnServerCommand|sendClientCommand|sendServerCommand` no diretório inteiro retornou
zero ocorrências — confirmado, não é só ausência no arquivo principal.

**Conclusão:** módulo inteiramente client-side; reconstrói um container virtual agregando itens de
containers próximos, sem nenhuma comunicação de rede própria. Sem superfície para o checklist de 15
pontos. Nenhum finding de autoridade. (Nota: `01_CLAUDE_FINDINGS.md`/`04_PERFORMANCE_FINDINGS.md` já
sinalizaram este módulo como candidato de performance sob PERF-F — fora do escopo de rede desta
sessão.)

---

## Módulo: `LS_ImprovisedSilencers` — CLEAN (sem handler client→server; passada leve feita)

**Verificado:** `Contents/mods/LS_ImprovisedSilencers/42/media/lua/shared/ISIL_SilencerStats.lua`
(907 linhas), com leitura completa de `findNetworkWeapon`/`findNetworkPlayer`/
`applyNetworkWeaponState`/`broadcastNetworkWeaponState`/`onSuppressorServerCommand`/
`processPendingNetworkWeaponStates` (linhas 383-540), `onWeaponFired`/`captureWeaponState`/
`takePendingWeaponState`/`queueWeaponStateRestore` (605-730), os monkey-patches de
`ISUpgradeWeapon`/`ISRemoveWeaponUpgrade` (711-791) e `onPlayerUpdate` (821-886).

Este módulo só registra `Events.OnServerCommand.Add(onSuppressorServerCommand)` (linha 905) — ou
seja, só recebe broadcasts do próprio servidor (`broadcastNetworkWeaponState`, sempre atrás de
`isServer()` na linha 483). **Não existe `Events.OnClientCommand.Add` neste módulo** — confirmado por
busca no arquivo inteiro. O checklist de 15 pontos não se aplica por falta de handler client→server.

**Passada leve — queues/caches (seção 25 do plano pede checar especificamente "observed suppressors,
deferred weapon states, strong references, timeout" deste módulo):**

```text
ISILPendingNetworkWeaponStates[onlineId:itemId] -> retry local (client) de reaplicação de estado de
  arma após pacote de rede; retryTicks={2,10,30}, auto-removida quando os retries acabam
  (processPendingNetworkWeaponStates, linhas 528-540). Limitada e autolimpa. Sem achado.

ISILDeferredWeaponStates[weapon:getID()] -> criada só ao concluir upgrade/remoção do próprio
  supressor (ticks=1), consumida no onPlayerUpdate imediatamente seguinte do mesmo character
  (linhas 821-863) e removida (`ISILDeferredWeaponStates[itemId] = nil`, linha 860). Vida útil de
  no máximo 1 frame. Sem achado.

ISILObservedSuppressors[item:getID()] -> atualizada a cada onPlayerUpdate para a arma primária
  equipada (linha 884); nunca é explicitamente removida quando uma arma é destruída/dropada/sai de
  cena. Cresce no máximo O(armas distintas já equipadas na sessão) -- cada entrada é um único
  booleano/string por ID de item. Não atinge o patamar de HIGH desta revisão (não é O(N) por tick
  sobre uma população que escala com zumbis/jogadores, e o tamanho por entrada é desprezível); não
  promovido a finding, mas registrado aqui como observado conforme pedido pelo plano.
```

**Passada leve — monkey-patches:** `ISUpgradeWeapon:new/:complete` e `ISRemoveWeaponUpgrade:new/:complete`
capturam a função original (`originalUpgradeNew`/`originalUpgradeComplete`/etc.) e sempre chamam
`original...(self, ...)` antes/durante sua própria lógica (linhas 712-791) — padrão de **menor risco**
da seção 11 (capture + call-through), não full-replacement. Nenhum achado.

---

## Módulo: `LS_MiniHealthPanel` — CLEAN (sem superfície client→server)

**Verificado:** busca por rede nos 4 arquivos do módulo (1914 linhas no total) retornou zero
ocorrências de `OnClientCommand|OnServerCommand|sendClientCommand|sendServerCommand`; não existe pasta
`server/`.

**Conclusão:** painel de saúde é renderização/leitura local do próprio `BodyDamage` do jogador local,
sem envio de rede. Sem superfície para o checklist de 15 pontos. Nenhum finding de autoridade.

---

## Módulo: `LS_CleanHotBar` — CLEAN (sem superfície client→server)

**Verificado:** busca por rede nos 13 arquivos do módulo (3644 linhas no total) retornou zero
ocorrências de `OnClientCommand|OnServerCommand|sendClientCommand|sendServerCommand`; não existe pasta
`server/`.

**Conclusão:** módulo de UI/hotbar inteiramente client-side (reordenação de hotbar, ícones de estado de
arma/durabilidade, cores de líquido). Sem superfície para o checklist de 15 pontos. Nenhum finding de
autoridade. `vanillaSavePositionSyncsCache` (`cleanhotbarreorder.lua:88`) foi checado rapidamente: faz
parte do próprio fluxo local de salvar posições da hotbar, não é estrutura de rede.

---

## Módulo: `FixedLightOnBeltAF` — CLEAN (sem superfície client→server)

**Verificado:** busca por rede nos 7 arquivos do módulo (879 linhas no total) retornou zero ocorrências
de `OnClientCommand|OnServerCommand|sendClientCommand|sendServerCommand`; não existe pasta `server/`.

**Conclusão:** módulo puramente client-side (correção visual de lanterna/item no cinto e compatibilidade
de hotbar). Sem superfície para o checklist de 15 pontos. Nenhum finding de autoridade.
`trackedStates` em `sbfplus_mpdiagnostics.lua` foi checado: tem limpeza total explícita (linha 77,
`for key in pairs(trackedStates) do trackedStates[key] = nil end`) e remoção por chave (linha 227) —
sem crescimento sem limite.

---

## Sumário final da passada

```text
Módulos com handler OnClientCommand real (checklist de 15 pontos aplicado):
  LS_CyesPushDoors      -> 1 finding: CLD-P1-001 (HIGH)
  LS_EquipWhileRunning  -> 0 findings novos; vulnerabilidade LS-001 já documentada e já corrigida,
                            reconfirmada diretamente no código atual (args.id ~= player:getOnlineID())

Módulos sem superfície client->server (checklist não aplicável, confirmado por leitura/busca
completa de cada árvore de arquivos, não só pela tabela de 00_INVENTORY.md):
  LS_Antibodies          -> CLEAN
  LS_ProximityInventory  -> CLEAN
  LS_ImprovisedSilencers -> CLEAN (só server->client; passada leve de queues/monkey-patches feita)
  LS_MiniHealthPanel     -> CLEAN
  LS_CleanHotBar         -> CLEAN
  FixedLightOnBeltAF     -> CLEAN

Nenhum patch de código foi aplicado nesta sessão. Primeira passada preservada.
```
