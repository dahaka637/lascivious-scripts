# 01b — Claude findings: LS_WanderingZombies, TimeVote, ZombieDecay

**Status da passada:** `HISTORICAL_COMPLETE — NÃO EXECUTAR PENDÊNCIAS DO CORPO`
**Última atualização:** 2026-08-26
**Nota de handoff vigente:** pesquisa preservada como histórico. TimeVote foi refutado; ZombieDecay
foi corrigido; Wandering Zombies fechou sem blocker estático. Próximo trabalho fica em
`06_RUNTIME_TEST_MATRIX.md`, não nas pendências antigas deste arquivo. Este arquivo cobre os três
módulos P0 ainda não auditados individualmente por nenhum agente: `LS_WanderingZombies`,
`LasciviousScripts/TimeVote` e `LasciviousScripts/ZombieDecay`. Parte de `review/00_INVENTORY.md`,
`review/01_CLAUDE_FINDINGS.md`, `review/02_CODEX_FINDINGS.md` e `review/04_PERFORMANCE_FINDINGS.md`
(PERF-CAND-002/PERF-CAND-003 já abertos como NEEDS_PROFILING) já foram lidos antes de iniciar esta
sessão, para não duplicar PRE-001..005.

## Escopo desta sessão

1. `Contents/mods/LS_WanderingZombies/` — `OnClientCommand` (1 call site pelo inventário),
   `OnZombieUpdate` (3), `WZTick`/`OnTick` (4), lifecycle de `trackedZombies`.
2. `Contents/mods/LasciviousScripts/42/media/lua/{shared,client,server}/LasciviousScripts/TimeVote/`
   — comandos de rede de voto, roster online, TimedAction registry.
3. `Contents/mods/LasciviousScripts/42/media/lua/{shared,client,server}/LasciviousScripts/ZombieDecay/`
   — `OnZombieUpdate` (PERF-CAND-002), `ZombieLore` rewriting, six-phase migration.

---

## Notas de investigação em andamento (INVESTIGATING)

Nenhuma pendente — as três seções abaixo já refletem o estado final desta sessão.

---

# 1. LS_WanderingZombies

**Status:** `CONFIRMED_STATIC` (clean bill of health — network authority) / `NEEDS_PROFILING`
(performance, refinando PERF-CAND-003, sem promoção a HIGH).

## 1.1. Arquivos lidos integralmente

```text
client/RYUKU_WanderingZombies.lua                              (229 linhas)
shared/RYUKU_WanderingZombies_SandboxVars.lua                   (405 linhas)
shared/RYUKU_WanderingZombies_ZombieBase.lua                    (506 linhas)
shared/RYUKU_WanderingZombies_Zombie.lua                        (434 linhas)
shared/RYUKU_WanderingZombies_Horde.lua                         (353 linhas)
shared/RYUKU_WanderingZombies_LinkedList.lua                    (209 linhas)
shared/RYUKU_WanderingZombies_Director.lua                      (152 linhas)
shared/RYUKU_WanderingZombies_DirectorEvent.lua                 (103 linhas)
shared/RYUKU_WanderingZombies_Utility.lua                       (41 linhas)
shared/RYUKU_WanderingZombies_IndexedDictionary.lua              (97 linhas, dead code — nenhum caller)
shared/wz-director/RYUKU_WanderingZombies_PullEvent.lua          (124 linhas)
shared/wz-director/RYUKU_WanderingZombies_MigrateEvent.lua       (82 linhas)
```

## 1.2. `OnClientCommand` — checklist de cliente hostil

Único call site do módulo (confirma o número do inventário):
`RYUKU_WanderingZombies_SandboxVars.lua:395-404`.

```lua
local function OnClientCommand(mod, command, player, args)
    if mod ~= "WanderingZombies" then return end
    if command ~= "WZSVInit" then return end

    local sv = {}
    for i = WZ_LONE, WZ_DIRECTOR do sv[i] = { key = sandboxVars[i].key } end
    sendServerCommand(player, "WanderingZombies", "WZSVInit", sv)
end

if isServer() or isCoopHost() then Events.OnClientCommand.Add(OnClientCommand) end
```

- **Cliente comunica intenção ou resultado?** Nenhum dos dois — o payload `args` do comando
  `WZSVInit` recebido pelo servidor **não é lido em nenhum momento**. O handler ignora `args`
  completamente e responde sempre com o mesmo conteúdo: os valores atuais de sandbox do servidor
  (`sandboxVars[i].key`, `i = WZ_LONE..WZ_DIRECTOR`).
- **O servidor muta algum estado a partir do comando?** Não. É um endpoint puramente de leitura —
  o servidor nunca escreve em `sandboxVars`, `modData` ou em qualquer outra estrutura como reação a
  este comando. O único efeito colateral é o envio da resposta.
- **Validação de tipo/distância/Z/target/permissão?** Não aplicável — não há alvo, posição ou
  permissão envolvida; o comando não opera sobre nenhum objeto do mundo.
- **Rate limit / replay / pacote duplicado?** Nenhum. Um cliente modificado pode enviar `WZSVInit`
  repetidamente sem limite. Como o handler é O(1) por chamada (apenas 4 grupos de chaves de
  sandbox, um pacote de tamanho fixo) e não muta estado, isso é, na pior hipótese, um amplificador
  de tráfego de rede irrelevante (resposta um pouco maior que o pedido, tamanho fixo, não escala
  com nenhuma entrada do cliente) — não atinge o critério de `HIGH`/`PERF-HIGH` desta revisão
  (não há crescimento, não há custo por elemento controlado pelo atacante, não há O(N²)).
- **Uso legítimo:** o cliente dispara isso uma única vez por sessão, via `PlayerIDTick` em
  `RYUKU_WanderingZombies.lua` (deveria ler `SandboxVars.lua:374-380`, mas o call site real do
  `sendClientCommand` está lá), assim que `getOnlineID()` deixa de ser `-1` após o load — ou seja,
  o fluxo normal é "uma vez ao entrar no mundo". O handler servidor está correto em não confiar
  nisso como garantia, mas confirmo que mesmo abusado o comando não representa alteração de estado
  autoritativo.

**Conclusão:** `OnClientCommand` deste módulo é seguro mesmo assumindo cliente completamente
modificado — não expõe nenhuma primitiva de escrita, teleporte, execução administrativa ou bypass.
Não há achado CRITICAL/HIGH aqui. (`sendServerCommand`/`OnServerCommand` para `WZSVUpdate` só correm
em sentido servidor -> cliente e não aceitam nenhum comando de volta que mute o servidor.)

## 1.3. `OnZombieUpdate` (3 registros) — modelo de desempenho

```text
1. client/RYUKU_WanderingZombies.lua:31-53           — registro/tracking de wrapper (OnZombieUpdate principal)
2. shared/RYUKU_WanderingZombies_ZombieBase.lua:368-392 — monitorIndoorThump (sempre ativo)
3. shared/wz-director/RYUKU_WanderingZombies_PullEvent.lua:26,38,62-77 — WZPullEvent.onZombieUpdate
   (Add/Remove dinâmico, só ativo quando o sandbox `PullEnabled` está ligado)
```

Todos os três fazem trabalho O(1) por callback (leitura/gravação de `modData`/`getVariableBoolean`,
sem scans, sem alocação de tabela grande, sem I/O). `monitorIndoorThump` só faz trabalho extra
(`pathToLocation`) quando `modData.wzThumpIndoors` já está marcado, que é um caso raro e
autolimitado. Nenhum dos três eleva a superfície de `OnZombieUpdate` acima de "custo constante por
zumbi"; a única pergunta de escala real está em `WZTick`, abaixo.

## 1.4. `WZTick` / `WZZombie:update` / horde join-merge / path requests — refinando `PERF-CAND-003`

```text
EVENTO: Events.OnTick (WZTick, RYUKU_WanderingZombies.lua:93-226)
FREQUÊNCIA: 1x por frame do cliente (ou host)
N: zombies:size() == população total rastreada pelo cliente (todas as não-remotas, não-mortas)
CUSTO: round-robin com orçamento por frame, não O(N) por frame
```

Mecanismo confirmado por leitura completa (não apenas inspeção pontual):

- `processLimitDelta` acumula `min(zombies:size() * updateDelta, cap)`, onde `cap` é
  `perfProcessLimit:getValue()` (slider 1-20, default 4) quando o frame não está lento, ou uma
  fração `<1` de `frameCutoff/updateDelta` quando o frame já está abaixo de 50 FPS (autolimitação
  de degradação). Como `zombies:size() * updateDelta` cresce com a população mas o `min()` sempre
  escolhe o menor dos dois, **o número de updates por frame é, na prática, sempre limitado pelo
  slider configurável (4-20), independente de a população ser 500 ou 10.000+** — confirma
  estaticamente a suposição do Codex em `04_PERFORMANCE_FINDINGS.md` de que o custo por frame é
  `O(processLimit)`, não `O(N)`.
- Efeito colateral direto dessa arquitetura: com N=10.000 e processLimit=4 (default), o "round-robin"
  completo (cada zumbi revisitado uma vez) leva `10000/4 = 2500` ticks, ou seja, dezenas de segundos
  em vez de frames — isso é uma escolha de design deliberada (throughput vs. cardinalidade), não um
  bug, mas é o fator dominante para qualquer estimativa de "quanto tempo até um zumbi morto ser
  limpo da lista" (ver 1.5).
- `wzZombie:update()` em si (`WZZombieBase:update` -> `WZHorde:update` -> `WZZombie:update`, cadeia
  de override via `Director.lua:95-152`) é O(1) por zumbi: nenhum scan de zumbis vizinhos, nenhuma
  chamada `getZombieList()`/`getMovingObjects()`. `updatePlayers()` (`Zombie.lua:185-237`) é O(1)
  por chamada — processa exatamente 1 jogador por update (`_nextPlayerIdx` avança em round-robin
  próprio), não itera todos os jogadores online por zumbi; o comentário no código (linha 188)
  confirma que essa é uma otimização deliberada em relação a uma versão anterior mais precisa.
- **Horde join/merge**: `WZHorde:mergeHordeWith` (`Horde.lua:249-291`) tem uma nota do próprio autor
  já citando o risco de mutar uma lista circular durante iteração ("Mutating the circular list while
  its iterator uses the live size skips entries in larger hordes") e mitiga com snapshot para array
  antes de iterar (`Horde.lua:272-283`). Custo é `O(hordeSize)` por merge (tamanho da horda *que está
  sendo absorvida*, não da população total), limitado adicionalmente por `mergeCooldown` escalado
  pelo tamanho da horda alvo (linha 263). Não há scan global de zumbis nesse caminho.
- **Path requests**: `pathTo()` (`ZombieBase.lua:312-365`) varre apenas 3 squares (`z-1, z, z+1`) na
  posição de destino para escolher um nível Z válido — não escala com população nem com área,
  apenas custo fixo por chamada de path.
- **Busca de candidato de horda** (segundo `while` em `WZTick`, linhas 149-225): também orçado pelo
  mesmo `processLimit`/`processedCount` da passada principal (reaproveitado, não é um orçamento
  adicional) e usa o cursor persistente `hordeCurrentLink`, avançando incrementalmente pela mesma
  lista circular em vez de re-escanear tudo a cada tick — condizente com a nota do plano ("busca
  incremental de horda amortizada").

### Conclusão sobre `PERF-CAND-003`

Confirmo a avaliação do Codex: o mecanismo já é O(processLimit) por frame para todos os caminhos
centrais (update, path, merge), não O(N). **Não encontrei nenhum caminho dentro de `WZTick`,
`WZZombie:update`, join/merge de horda ou path requests que faça um scan proporcional à população
total por frame.** Mantenho `NEEDS_PROFILING` — não `HIGH` — porque a única variável real que falta
para fechar o modelo é o custo *absoluto* em microssegundos de cada `wzZombie:update()` (chamadas
Java/Kahlua como `getCurrentStateName()`, `isOutside()`, `getSpeedType()`, `getBuilding()` etc. têm
custo desconhecido sem profiling) multiplicado por até 20 (processLimit máximo) por frame — não há
evidência estática de que isso seja caro o bastante para spike severo, e a arquitetura já limita
deliberadamente o pior caso. Não reescrever sem medir, conforme a regra do plano.

## 1.5. Lifecycle de `trackedZombies` — disconnect / despawn / chunk unload

```text
Quem adiciona:  client/RYUKU_WanderingZombies.lua:46-50 (OnZombieUpdate), uma vez por IsoZombie novo
Quem remove:    client/RYUKU_WanderingZombies.lua:122-126, só dentro do while orçado de WZTick,
                quando wzZombie:update() retorna nil
Weak/strong:    trackedZombies é __mode="k" (chave fraca = a própria IsoZombie), mas o VALOR
                (wzZombie) também é referenciado fortemente pelo nó da WZLinkedList `zombies`
                (zombies:push(wzZombie) na mesma função que insere em trackedZombies)
```

Achado de arquitetura (não é um novo bug, é uma correção ao texto do plano): a propriedade "weak
table" de `trackedZombies` citada no plano como fator mitigante **não é a razão real pela qual o
zumbi pado referenciado é liberado**. `trackedZombies[zombie] = wzZombie` teria, sozinha, uma chave
fraca (o `zombie` IsoZombie) — mas a mesma `wzZombie` também é empurrada para dentro de
`zombies` (a `WZLinkedList` viva durante toda a sessão), cujo nó (`WZLinkedListLink._ref`) segura uma
referência **forte** ao wrapper, que por sua vez segura uma referência **forte** ao `IsoZombie` via
`self._ref` (`WZZombieBase:new`, linha 54). Ou seja: enquanto o nó não for removido da lista
(`zombies:remove(link)`), o `IsoZombie` subjacente é mantido vivo do lado Lua *independente* da
propriedade `__mode="k"` de `trackedZombies` — é a lista, não o cache, quem prova a posse real da
referência.

A remoção do nó só acontece quando **a própria rodada de round-robin chega até aquele nó
especificamente** e `wzZombie:update()` detecta `isValid() == false` (zumbi morto, removido do
mundo via `isExistInTheWorld()`, remoto, ou marcado `Bandit`) — ver `ZombieBase.lua:107-120,172-178`.
Isso tem duas implicações que valem registrar:

1. **Atraso limitado, não vazamento indefinido.** Como a lista é circular e `next()`/`remove()`
   preservam a topologia corretamente (self-healing confirmado por leitura de
   `LinkedList.lua:98-180`), todo nó É eventualmente revisitado — o pior caso é
   `zombies:size() / processLimit` ticks até a limpeza (ver 1.4: dezenas de segundos com população
   alta e processLimit default), não "nunca". Isso não atinge o critério HIGH de "fila/cache
   crescendo sem limite" porque o tamanho de `trackedZombies`/`zombies` está travado ao número de
   IsoZombie efetivamente vivos no mundo do lado do cliente (population cap do próprio jogo), não a
   uma entrada externa/atacante-controlada que poderia crescer sem bound.
2. **Dependência de engine não verificável estaticamente.** O caminho de limpeza depende de
   `IsoZombie:isExistInTheWorld()` retornar `false` de forma confiável quando um zumbi é
   despawnado/desidratado (virtualizado) pelo motor ao sair de alcance de simulação — não consigo
   confirmar essa premissa lendo só Lua. Se essa API do engine eventualmente deixasse de refletir a
   desidratação corretamente (não há evidência de que isso ocorra; é apenas o limite do que dá para
   provar sem rodar o jogo), o wrapper ficaria retido até a próxima falha de outra checagem de
   `isValid()` (ex.: `isDead()`), então ainda não seria indefinido, só adiado. Marco esta única
   dependência como `NEEDS_RUNTIME` e não escalo — é exatamente o tipo de suposição de engine que a
   seção 22 do plano pede para não assumir sem prova, mas também não há motivo concreto para
   desconfiar dela.
3. **Disconnect do jogador**: todo o pipeline de tracking (`trackedZombies`, `zombies`, `WZDirector`,
   `WZ_DIRECTOR_EVENTS`) é estado puramente client-local, nunca persistido (comentário explícito em
   `RYUKU_WanderingZombies.lua:44-45: "Keep tracking state client-local... these wrappers do not
   persist with the save"`) e nunca transmitido a outro cliente/servidor. Ao desconectar, todo o
   estado Lua do processo cliente é descartado junto com o processo — não há como esse estado
   "vazar" para uma sessão futura ou para o servidor. Confirmado por grep completo: nenhum
   `transmitModData`/`sendServerCommand` carrega qualquer parte dessas estruturas.

**Conclusão:** não encontrei um caminho onde `trackedZombies` acumula entradas indefinidamente. O
atraso de limpeza é orçado e proporcional à população, coerente com o próprio modelo de performance
do módulo (1.4), e a única suposição não verificável estaticamente é uma API do engine, marcada
`NEEDS_RUNTIME` sem promoção a achado.

## 1.6. Sumário — LS_WanderingZombies

Nenhum CRITICAL/HIGH/PERF-HIGH confirmado. `PERF-CAND-003` permanece `NEEDS_PROFILING`, agora com o
modelo de escala completo (round-robin orçado por `processLimit`, não scan por população, em todos
os quatro subsistemas pedidos: `WZTick`, `WZZombie:update`, horde join/merge, path requests). O
único `OnClientCommand` do módulo foi auditado assumindo cliente totalmente hostil e não expõe
nenhuma escrita de estado. Lifecycle de `trackedZombies` é self-healing e limitado pela população
real do mundo, não por uma entrada externa.

---

# 2. LasciviousScripts / TimeVote

**Status:** clean bill of health para autoridade de rede (voto/consenso); **1 achado HIGH** para o
registro de escala de `NetTimedAction` (`TV-001`, abaixo).

## 2.1. Arquivos lidos integralmente

```text
shared/LasciviousScripts/TimeVote/Core.lua      (74 linhas)
server/LasciviousScripts/TimeVote/Server.lua    (355 linhas)
client/LasciviousScripts/TimeVote/Client.lua    (286 linhas)
client/LasciviousScripts/TimeVote/SpeedPanel.lua (148 linhas)
```

`docs/modules/time-vote.md` foi lido antes desta auditoria; o código bate com a arquitetura
documentada ("server owns consensus", "multiplier is applied once", sem loop de reforço em
`OnTickEvenPaused`) — não encontrei nenhum ponto onde a documentação afirma algo mais forte do que
o código garante, ao contrário do aviso genérico da seção 4 do plano.

## 2.2. `OnClientCommand` — checklist de cliente hostil (voto/consenso)

Um único dispatcher server-side, `Server.lua:215-221`, cobrindo três comandos:
`hello` / `vote` / `cancel`.

### `vote` (`onVote`, `Server.lua:157-201`)

- **Cliente comunica intenção ou resultado?** Intenção pura: `args.speed` é só o nível desejado
  (1-4); o servidor é quem decide o `applied` real via `consensusSpeed()`. O cliente nunca envia
  "resultado".
- **Validação de tipo:** `Core.isValidSpeed(level)` (`Core.lua:62-64`) exige `type == "number"`,
  inteiro, `1 <= level <= 4`. Cobre inclusive `NaN`/`inf` (comparações com `NaN` são sempre falsas
  em Lua, então `level == math.floor(level)` já rejeita `NaN`; `inf` é rejeitado pelo teste
  `<= MAX_SPEED`). Testei manualmente a lógica dos operadores — não há caminho de crash por tipo
  inesperado.
- **Identidade do remetente:** `playerKey(player)` (`Server.lua:22-30`) deriva a chave do objeto
  `player` que o **engine** passa como parâmetro do evento `OnClientCommand` (a conexão de rede já
  autenticada), nunca de `args`. Um cliente modificado não consegue votar em nome de outro jogador —
  não há campo `playerId`/`target` em `args` para forjar.
- **Distância/Z/target/permissão/safehouse/ferramenta:** não aplicável — o comando não opera sobre
  nenhum objeto do mundo, só sobre o próprio voto do remetente.
- **Recalcula RNG:** não aplicável, não há RNG envolvido.
- **Rate limit / replay / pacote duplicado:** não há rate limit explícito. Efeito de spam avaliado
  explicitamente: `votes[key] = level` é uma escrita idempotente (sobrescreve o próprio slot do
  remetente, nunca acumula), e cada chamada é O(jogadores online) (`consensusSpeed()`/`broadcast()`
  iteram a roster, que é limitada ao cap de jogadores do servidor — nunca uma cardinalidade
  controlada pelo atacante). Um cliente automatizado disparando `vote` no limite da rede só produz
  broadcasts redundantes limitados por O(jogadores) cada; não atinge o critério de `HIGH`/`PERF-HIGH`
  desta revisão (sem O(N²), sem crescimento, sem alocação proporcional a uma entrada externa).
- **Pode votar duas vezes / duplicar contagem?** Não — respondendo diretamente à pergunta do
  escopo: `votes` é uma tabela chaveada por jogador, não uma lista; reenviar `vote` só atualiza o
  próprio slot. `consensusSpeed()` (`Server.lua:82-89`) exige que **todo** jogador da roster atual
  tenha o mesmo voto — um único cliente hostil não pode fabricar consenso sozinho a menos que seja
  o único jogador online (unanimidade trivial, que é o comportamento documentado e intencional para
  jogador solo).
- **1x a qualquer momento:** qualquer jogador pode forçar `forceNormal()` votando `1`
  (`Server.lua:168-171`) — isso é comportamento de design documentado ("Any one client's vanilla
  interruption cancels fast-forward for every player"), não um bypass; o pior efeito é griefing
  (um jogador insistente impede o grupo de acelerar o tempo), não corrupção de estado ou escrita
  fora do próprio voto.

### `cancel` (`onCancel`, `Server.lua:203-213`)

- Mesmo padrão de identidade via `player` do engine. `args.revision` é comparado com a `revision`
  monotônica do servidor só para **descartar** cancelamentos antigos/atrasados
  (`clientRevision < revision`), nunca para conceder poder extra — mesmo que um cliente hostil
  forje um `revision` alto para nunca ser descartado, o efeito continua sendo "forçar 1x", que
  qualquer jogador já pode fazer via `vote{speed=1}`. Não há escalada de privilégio possível
  fabricando esse campo.

### `hello` (`onHello`, `Server.lua:151-155`)

- Sincroniza a roster e reenvia o payload atual. Não muta `votes`/`applied` além do que
  `refreshElectorate` já faria de qualquer forma quando a roster muda. Sem risco.

**Conclusão:** os três comandos client -> server do TimeVote são seguros assumindo cliente
completamente modificado. Nenhum permite votar por outro jogador, forjar consenso sozinho (exceto
o caso de unanimidade trivial documentado), ou escalar para qualquer escrita fora do próprio voto.

## 2.3. Double-vote, disconnect/reconnect e corrupção de roster

Perguntas do escopo, respondidas por leitura direta:

- **Cliente pode votar múltiplas vezes?** Não resulta em contagem dupla — `votes[key] = level` é
  sobrescrita, não append (ver 2.2).
- **Voto de jogador desconectado pode persistir e corromper a roster?** Não. `refreshElectorate()`
  (`Server.lua:120-149`) roda em **todo tick** do servidor (`onTick` -> chamado incondicionalmente
  quando o módulo está habilitado, `Server.lua:341`) e compara a roster atual
  (`onlineRoster()`, uma leitura fresca de `getOnlinePlayers()` a cada chamada) contra `lastOnline`
  via `sameOnlineSet`. Qualquer mudança de roster (entrada OU saída, incluindo disconnect) que
  não bata com o snapshot anterior dispara `resetVotes()` (quando `applied < FAST_FORWARD_MIN`) ou
  `forceNormal()` (quando já acelerado, que também chama `resetVotes()` internamente) — ambos
  reconstroem `votes = {}` do zero, populado só com as chaves da roster **atual**. Ou seja, o voto
  de um jogador que desconectou é descartado no próximo tick após a desconexão (atraso máximo de 1
  tick de servidor, não "nunca").
- **Servidor confirma independentemente que o remetente está online/elegível antes de contar um
  voto?** Sim, por construção: `consensusSpeed()` sempre itera `onlineRoster()` (uma leitura
  fresca), nunca uma lista de "quem já votou alguma vez" — um jogador cujo voto ficou órfão em
  `votes` (por exemplo, se a chave dele mudasse de `"name:X"` para um ID numérico durante o handshake
  de conexão — ver próximo ponto) simplesmente não entra na iteração de `consensusSpeed()` porque
  não está mais na roster atual sob aquela chave.
- **Troca de chave durante handshake (fallback de username para ID online):** `playerKey()`
  (`Server.lua:22-30`) usa `getOnlineID()` quando disponível e válido (`>= 0`), com fallback para
  `"name:" .. username` só quando o ID ainda não foi atribuído. Se um jogador for brevemente
  identificado por `"name:X"` e depois obtiver um ID numérico, a chave efetivamente muda no meio da
  sessão — mas como a roster inteira é recomputada a cada chamada de `onlineRoster()` (nunca
  cacheada por mais de uma comparação), essa troca de chave é detectada como "mudança de roster"
  por `sameOnlineSet` e provoca o mesmo `resetVotes()` de qualquer entrada/saída normal — autocura
  em até 1 tick, sem voto órfão sobrevivendo de forma persistente.

**Conclusão:** não há corrupção de roster por disconnect/reconnect nem voto duplicado. A
reconciliação é orientada por polling a cada tick (não por evento `OnDisconnect` dedicado), o que
introduz uma janela de até 1 tick de servidor entre a desconexão real e a limpeza — irrelevante em
termos de impacto (não há nenhuma decisão de consenso tomada com base numa roster desatualizada,
porque `consensusSpeed()` sempre lê a roster fresca no mesmo instante em que decide).

## 2.4. `TV-001` — Registro de duração de `NetTimedAction` (`liveNetActions`) não tem TTL/limpeza por desconexão

```text
ID: TV-001
Severidade: HIGH
Confiança: NEEDS_RUNTIME (mecanismo de ausência de safety-net confirmado estaticamente;
           a taxa real de crescimento depende do comportamento do engine ao chamar
           net:getProgress() sobre um NetTimedAction abandonado/desconectado, não verificável
           sem rodar o jogo)
Módulo: LasciviousScripts / TimeVote
Lado: server
Arquivo: Contents/mods/LasciviousScripts/42/media/lua/server/LasciviousScripts/TimeVote/Server.lua
Linha: 241-297 (liveNetActions definido em 241, hook em 246-253, driveNetRegistry em 259-297)
Função: driveNetRegistry(liveNetActions, ...), hook de emulateAnimEvent
```

### Trigger

Qualquer `NetTimedAction` do jogo cujo `emulateAnimEvent` seja acionado ao menos uma vez (isto é,
qualquer ação animada acompanhada pelo sistema de `NetTimedAction` do B42 — o hook é um override do
**global** `emulateAnimEvent`, não restrito às TimedActions de comer/beber/lavar/artesanato que o
módulo lista explicitamente para `injectedActions`) e que depois nunca alcance `progress >= 1` nem
faça `net:getProgress()` lançar erro — por exemplo, uma ação interrompida por desconexão do jogador
no meio da execução, se o objeto `net` sobrevivente continuar respondendo a `getProgress()` com um
valor `< 1` válido indefinidamente em vez de errar.

### Cenário mínimo

Jogador inicia qualquer ação que dispare `emulateAnimEvent` (registrando `liveNetActions[net] =
{mult=1}`), e desconecta (ou tem a ação abortada de outra forma que não seja "completar" nem
"invalidar o objeto net do lado Java") antes de `progress` chegar a 1. Repetir esse padrão ao longo
de uma sessão longa (72h é um dos cenários pedidos na seção 10 do plano) com múltiplos jogadores.

### Estado esperado

Toda entrada de um registro de acompanhamento de `NetTimedAction` deveria ter uma via de saída
garantida independente de o `net` continuar "vivo e respondendo": conclusão normal, erro/objeto
inválido, **ou um TTL/contagem de ticks sem progresso**, igual ao que o próprio módulo já implementa
para o registro irmão.

### Estado atual

- `liveNetActions` (`Server.lua:241`) é uma tabela **forte** (não `__mode`), chaveada pelo próprio
  objeto `net`. Populada unicamente pelo override global de `emulateAnimEvent`
  (`Server.lua:246-253`), sem filtro por módulo/tipo de ação — qualquer `NetTimedAction` do
  servidor inteiro pode entrar aqui, não só as seis TimedActions explicitamente listadas para
  `injectedActions` (`ISEatFoodAction`, `ISDrinkFromBottle`, `ISWashClothing`, `ISWashYourself`,
  `ISCraftAction`, `ISAddItemInRecipe`).
- `driveNetRegistry()` (`Server.lua:259-297`), chamada todo tick via `onTick -> driveTimedActions()`
  (`Server.lua:324-347`), é o único código que remove entradas de `liveNetActions`. Para essa
  tabela especificamente, `getNet = function(net) return net end` (`Server.lua:325`) — ou seja, a
  "chave" e o "net" são o mesmo objeto, então `net = getNet(key)` **nunca é nil** por construção; o
  branch `if not net then state.noNet = ...; if state.noNet > 600 then registry[key] = nil end`
  (linhas 263-265) é **morto** para `liveNetActions` (só pode disparar de fato para
  `injectedActions`, onde `getNet` lê `action.netAction`, que pode legitimamente ser `nil`).
- A única via de remoção que resta para `liveNetActions` é
  `local okP, progress = pcall(net.getProgress, net); if not okP or type(progress) ~= "number" or
  progress >= 1 then registry[key] = nil` (linhas 268-271). Isso cobre conclusão normal (`progress
  >= 1`) e qualquer erro do lado do engine ao chamar `getProgress` num objeto inválido/destruído.
  **Não cobre** o caso em que o objeto `net` do lado Java continua existindo e respondendo com um
  número válido `< 1` para sempre porque a ação foi abandonada (ex.: jogador desconectou) sem que o
  objeto seja destruído/nulado — não há um contador de ticks estagnados equivalente ao `noNet > 600`
  que o próprio módulo usa para `injectedActions`.
- Não existe nenhum handler de `Events.OnDisconnect` (nem qualquer variante) neste arquivo — grep
  completo em `server/LasciviousScripts/TimeVote/Server.lua` confirma que os únicos três eventos
  registrados são `OnClientCommand`, `OnTick` e `OnCharacterDeath` (`Server.lua:349-355`), e nenhum
  dos três toca `liveNetActions`/`injectedActions`.

### Impacto

Se a suposição de engine acima se confirmar (isto é, se `net:getProgress()` de um `NetTimedAction`
abandonado por desconexão continuar retornando um número válido em vez de lançar), `liveNetActions`
cresce por uma entrada a cada ação net-driven abandonada durante toda a vida do processo do
servidor, sem nenhum limite de tamanho e sem nenhuma via de saída baseada em tempo — e, como
`driveNetRegistry` itera `pairs(registry)` a **cada tick do servidor**, cada entrada morta também
passa a custar um `pcall`/chamada Java por tick para sempre, transformando um vazamento de memória
em um custo de CPU por tick que cresce ao longo da sessão (pressão de GC + trabalho por tick
crescente, ambos citados explicitamente como critério HIGH na seção 2.2 do plano). Isso bate
diretamente com os cenários de sessão longa (30min/6h/24h/72h) da seção 10 do plano.

### Escala

```text
EVENTO: driveNetRegistry(liveNetActions, ...) dentro de onTick
FREQUÊNCIA: todo tick do servidor (module Enabled=true, que é o default)
N: número de NetTimedAction distintos observados por emulateAnimEvent desde o boot do servidor
   que nunca completam nem erram (potencialmente todo jogador, toda ação animada, ao longo de dias)
CUSTO: O(1) por entrada por tick (1 pcall + comparação); custo total O(N) por tick, N não limitado
PIOR CENÁRIO REALISTA: servidor 24/7 com dezenas de jogadores interrompendo ações (desconexão,
  queda de rede, alt-F4) regularmente ao longo de semanas — se a suposição acima for real, o
  registro nunca é podado e N cresce monotonicamente pela vida do servidor
```

### Memória

Quem adiciona: hook global de `emulateAnimEvent`, incondicional, sem filtro de módulo. Quem remove:
só conclusão (`progress>=1`) ou erro do engine. Sem TTL. Sem limite de tamanho. Sem limpeza por
disconnect/death. Cada entrada é pequena (`{mult=1, ...}` mais a chave forte para o objeto `net`
Java/Kahlua), mas o crescimento é ilimitado em teoria se a premissa de "getProgress nunca erra para
net abandonado" se confirmar.

### Possível crash

Não diretamente — o risco é degradação (memória + CPU por tick), não uma exception imediata. Em
sessões extremamente longas, contribui para pressão de GC que pode agravar outros achados de
performance do pacote.

### Solução recomendada

Aplicar ao `liveNetActions` a mesma defesa que `injectedActions` já tem: um contador de ticks sem
progresso observado (ou sem chamada nova do hook `emulateAnimEvent` para aquele `net`) que remove a
entrada após um teto (por exemplo, os mesmos 600 ticks/~9,6s já usados, ou um valor maior se
9,6s for cedo demais para ações longas legítimas — vale checar contra a duração máxima real de
ações net-driven do jogo). Alternativa complementar: registrar `Events.OnDisconnect` /
`Events.OnPlayerDeath` e, ao disparar, varrer e remover quaisquer entradas cujo jogador dono não
está mais presente (exigiria guardar o dono junto ao estado, o que o registro atual não faz).

### Risco da solução

Baixo — adicionar um contador de ticks estagnados é o mesmo padrão que o código já usa em
`injectedActions`, só replicado para `liveNetActions`; não muda nenhum comportamento de gameplay
observável, só poda entradas mortas mais cedo.

### Teste de regressão

```text
sessão longa (>=6h) com múltiplos jogadores completando ações normalmente: liveNetActions volta a 0
jogador desconecta no meio de uma ação animada net-driven: entrada correspondente é removida dentro
  do teto de ticks configurado, sem exception
fast-forward 5x/20x durante uma ação em andamento: duração ainda é escalada corretamente
  (comportamento de negócio inalterado)
medir memória/tamanho de #liveNetActions + #injectedActions antes/depois de um ciclo de
  50 conexões/desconexões no meio de ações
```

## 2.5. `TimeVote server onTick` — custo por tick (probe do plano)

```text
EVENTO: Events.OnTick (server), onTick -> refreshElectorate + enforceSoloGate + driveTimedActions
FREQUÊNCIA: todo tick do servidor
N: jogadores online (limitado ao cap do servidor, tipicamente dezenas, não milhares) para
   refreshElectorate/enforceSoloGate; ver 2.4 para o N não limitado de driveTimedActions
CUSTO: refreshElectorate é O(jogadores) (getOnlinePlayers + sort); enforceSoloGate reusa a mesma
   leitura; driveTimedActions é O(|liveNetActions|+|injectedActions|), potencialmente ilimitado
   (ver TV-001)
```

`refreshElectorate`/`enforceSoloGate` por si só, isolados do achado TV-001, não passam do critério
HIGH — o número de jogadores é sempre limitado pelo cap do servidor, não por uma entrada de
atacante, e o trabalho por jogador é uma leitura/comparação de string, não uma chamada cara. O
elemento que efetivamente pode crescer sem limite dentro deste mesmo `onTick` é exatamente o
registro coberto por `TV-001`.

## 2.6. Sumário — TimeVote

1 achado: **`TV-001` (HIGH, `NEEDS_RUNTIME`)** — registro `liveNetActions` sem TTL/limpeza por
disconnect, ao contrário do registro irmão `injectedActions`, que já tem essa defesa. Autoridade de
voto/consenso (o foco principal do escopo — vote casting, double-vote, roster de disconnect) está
**limpa**: identidade sempre vem do engine, nunca de `args`; consenso exige unanimidade recomputada
a cada chamada contra a roster real; nenhum comando permite escrever fora do próprio voto do
remetente; roster se autocura em até 1 tick de qualquer entrada/saída, incluindo desconexão.

---

# 3. LasciviousScripts / ZombieDecay

**Status:** `NEEDS_PROFILING` (performance, refinando `PERF-CAND-002`, sem promoção a HIGH); **1
achado HIGH** de corrupção de estado persistente (`ZD-001`, abaixo); limpo para NaN/valor
inválido e para "double-apply" de migração.

## 3.1. Arquivos lidos integralmente

```text
shared/LasciviousScripts/ZombieDecay/Core.lua    (365 linhas)
client/LasciviousScripts/ZombieDecay/Client.lua  (164 linhas)
server/LasciviousScripts/ZombieDecay/Server.lua   (39 linhas)
```

`docs/modules/zombie-decay.md` foi lido antes desta auditoria. O código bate com a descrição
("deterministic, world-age-driven", seis fases, `DoorOpeningPercentage`/`ZombiesDragDown`/
`ZombiesFenceLunge` nunca tocados) — confirmado por leitura direta de `Core.captureOriginalLore`
(comentário e implementação nas linhas 301-317) e `Core.buildState`.

## 3.2. `OnZombieUpdate` — refinando `PERF-CAND-002`

```text
EVENTO: Events.OnZombieUpdate (client/LasciviousScripts/ZombieDecay/Client.lua:163, updateZombie)
FREQUÊNCIA: nativa do engine, por zumbi ativo — não amortizada por nenhum orçamento próprio do
            módulo (ao contrário de LS_WanderingZombies, que tem seu próprio processLimit)
N: todos os zumbis que recebem OnZombieUpdate do engine
```

Leitura completa de `updateZombie()` (`Client.lua:103-145`) e das funções que ela chama:

- **Custo já amortizado corretamente** pelas duas camadas de cache por zumbi
  (`Runtime.zombieCache[zombie]`, chave fraca):
  - `cache.loreGeneration` só diverge de `Runtime.loreGeneration` nas (no máximo) 3 transições de
    `loreRevision` (1->2->3->4) que existem em toda a linha do tempo do jogo — `DoZombieStats()`
    (`refreshZombieStats`, a chamada mais cara do arquivo) roda **no máximo 3 vezes por zumbi em
    toda a vida da run**, não por callback.
  - `cache.tierRevision` é `math.floor(day)` — muda **no máximo uma vez por dia de jogo** — então
    `Core.getDesiredTier()` (o roll determinístico) também só recalcula uma vez por zumbi por dia,
    não por callback.
- **Custo que roda em TODO callback, sem cache/skip:** `zombie:getSpeedType()` (1 pcall + getter) e,
  quando `desiredTier == SPRINTER`, `applyRunnerVariables()` (`Client.lua:91-101`) chama
  incondicionalmente `zombie:setVariable(MOVE_VARIABLE, moveScale)` e
  `zombie:setVariable(LUNGE_VARIABLE, lungeScale)` — **2 chamadas Java por callback, sem alocação de
  tabela, sem scan**. O próprio comentário no código (linha 96: "Reapply on every zombie update. B42
  animation state can recycle variables.") confirma que a ausência de cache aqui é uma decisão
  deliberada para contornar uma peculiaridade de animação do B42, não um descuido — bate com a nota
  do plano em "Já observado" (seção 23/PERF-C) de que isso é reaplicado a cada update.
- **Cardinalidade real do custo não-cacheado:** como `runnerChance = 100%` até o dia
  `RunnerSpeedFloor` (180 dias * escala), **todo zumbi no mundo é SPRINTER** durante essa janela
  inicial — ou seja, no início de uma run, 100% da população paga o custo de `applyRunnerVariables`
  em todo `OnZombieUpdate`, não uma fração.

### Conclusão sobre `PERF-CAND-002`

O modelo confirma que o módulo já faz a coisa certa para as partes caras (roll de seed, leitura de
lore, `DoZombieStats`) — todas amortizadas para "no máximo uma vez por dia" ou "no máximo 3 vezes na
vida do zumbi". O único custo por-callback restante é genuinely pequeno (1 getter + até 2 setters
Java, sem alocação), mas roda para até 100% da população durante a janela de sprinter completo.
Sem número real de `OnZombieUpdate`/s do engine para popuações de 5.000-10.000+ zumbis, não dá para
provar que 2 `setVariable` a mais por callback vira spike real — mantenho `NEEDS_PROFILING`, não
`HIGH`, e concordo com a nota do plano de não cachear/pular a reaplicação sem entender primeiro por
que ela existe (o comentário do próprio autor já documenta o motivo).

## 3.3. `ZombieLore` — risco de valor inválido/NaN

Verificação explícita pedida no escopo: persegui todos os caminhos aritméticos entre
`Core.getWorldAgeDays()` e as chamadas finais `setVanillaValue(...)`.

- `progress(value, startValue, endValue)` (`Core.lua:55-58`) faz guarda explícita contra divisão por
  zero/intervalo invertido: `if endValue <= startValue then return value >= endValue and 1 or 0 end`
  — só divide quando `endValue > startValue`. Como os cinco marcos de `cfg` (`RunnerSlowdownStart <
  RunnerSpeedFloor < RunnersGone < FinalDecay < FinalCollapse`) são todos `BASE_DAYS.X * scale` com o
  **mesmo** `scale` positivo (`TimelineScalePercent` já clampado 25-400 antes de virar `scale`), a
  ordem relativa nunca inverte — a guarda é defesa adicional, não um caminho normalmente exercitado,
  mas garante que mesmo uma configuração futura que violasse a ordem não geraria `NaN`/erro.
- `round()`/`clamp()` (`Core.lua:38-47`) sempre passam a entrada por `tonumber(value) or <fallback>`
  antes de qualquer aritmética — uma entrada não numérica nunca chega a `math.floor`.
- `state.runnerSpeedPercent`/`runnerChance`/`shamblerChance` são sempre `round(clamp(...))`'d antes
  de sair de `buildState` (`Core.lua:214-216`) — impossível sair do intervalo válido.
- `Core.rollPercent(seed, salt)` (`Core.lua:244-249`) só usa módulo por constantes literais
  (`% 1000003`, `% 10000`), nunca por uma variável que possa ser zero.
- `applyVanillaLore()` só escreve nomes de opção fixos e hardcoded com valores já validados pelas
  funções acima, ou inteiros literais por fase (`state.strength = 1/2/3`, etc.) — nunca passa um
  valor calculado sem clamp para `setVanillaValue`.

**Conclusão:** não encontrei nenhum caminho onde o rewriting de `ZombieLore` produza `NaN`, infinito
ou fora de faixa. As proteções (`clamp`, `round`, guarda de `progress`) cobrem toda a cadeia
aritmética antes de qualquer escrita em sandbox. Checado explicitamente, não é achado.

## 3.4. Sistema de seis fases — risco de "double-apply" em migração

Verificação explícita pedida no escopo: "does the six-narrative-phase system have any destructive
one-shot migration that could double-apply or apply incorrectly across a save reload?"

- `Core.buildState(worldAgeDays, cfg)` é uma função **pura** (sem `Events.*`, sem efeito colateral,
  recebe `day`/`cfg` e retorna uma tabela nova) recalculada do zero em **toda** chamada de
  `refreshWorldState()`/`updateWorldLore()` (`OnGameStart`, `EveryTenMinutes`, `OnInitGlobalModData`)
  — não existe um flag de "já migrado"/`modData.ver` como o que `LS_WanderingZombies_SandboxVars`
  usa (`WZ_SANDBOX_VERSION`). A fase narrativa não é "aplicada uma vez e esquecida"; ela é
  recalculada a cada 10 minutos a partir de `Core.getWorldAgeDays()`, que por sua vez lê
  `IsoWorld.instance:getWorldAgeDays()` (estado do PRÓPRIO ENGINE, persistido pelo jogo, não por
  este mod) — então um save/reload não pode fazer a fase "aplicar duas vezes" ou "aplicar errado":
  o próximo cálculo simplesmente usa a idade de mundo correta e produz o mesmo resultado que
  produziria em qualquer outro momento com a mesma idade.
- `applyVanillaLore()` é idempotente por construção: `setVanillaValue` só chama `options:set(...)`
  quando `not sameValue(current, value)` (`Core.lua:295-298`) — reaplicar o mesmo estado depois de
  um reload não gera nenhuma escrita nem efeito colateral duplo.

**Conclusão:** não há mecanismo de migração one-shot no sentido do plano (nenhum `modData`
versionado, nenhuma bandeira "já migrado"); o design é "recompute contínuo e idempotente a partir de
estado do engine", o que estruturalmente impede double-apply. Checado explicitamente, não é achado
— mas essa mesma ausência de estado persistido PRÓPRIO é exatamente a causa do achado `ZD-001`
abaixo (a única coisa que o módulo captura e mantém como "estado próprio" entre sessões é
`Core._originalLore`, e ela não é persistida corretamente).

## 3.5. `ZD-001` — `Core._originalLore` é recapturado a cada boot do processo, não uma vez por save

```text
ID: ZD-001
Severidade: HIGH
Confiança: HIGH_CONFIDENCE
Módulo: LasciviousScripts / ZombieDecay
Lado: shared (efeito visível em client e server)
Arquivo: Contents/mods/LasciviousScripts/42/media/lua/shared/LasciviousScripts/ZombieDecay/Core.lua
Linha: 35, 305-317, 344-358
Função: Core.captureOriginalLore, Core.restoreOriginalLore
```

### Trigger

Servidor dedicado (ou cliente) reinicia o processo (restart de manutenção, crash+restart, ou
simplesmente sair e reabrir o save em single-player) **enquanto ZombieDecay já vinha decaindo
ativamente o `ZombieLore` havia dias/semanas** — ou seja, qualquer sessão que não seja a primeiríssima
vez que o mod roda contra aquele save.

### Cenário mínimo

1. Sessão 1: servidor sobe com `ZombieLore` no preset original do admin. ZombieDecay captura esse
   preset em `Core._originalLore` (correto, primeira vez). O mundo avança 60 dias; o módulo já
   reescreveu `ZombieLore.Speed`/`SprinterPercentage`/etc. várias vezes via `options:set(...)`.
2. Servidor reinicia (rotina normal de manutenção, ou crash).
3. Sessão 2 (novo processo Lua, `Core._originalLore = nil` de novo por ser variável de módulo, não
   `modData`): a PRIMEIRA chamada de `applyVanillaLore` desta sessão roda `captureOriginalLore()`,
   que lê `getVanillaValue(...)` no **estado atual das sandbox options** — e essas opções, no PZ,
   persistem com o save/config do servidor entre reinícios (é assim que edições ao vivo de sandbox
   via admin sobrevivem a um restart). O valor lido agora é o valor **já decaído do dia 60**, não o
   preset original do admin.
4. Admin desliga `LasciviousScriptsZombieDecay.Enabled` mais tarde, esperando que o servidor volte
   ao preset de `ZombieLore` que ele configurou originalmente.

### Estado esperado

Desligar o switch mestre (`Enabled=false`) deve restaurar exatamente o preset de `ZombieLore` que o
admin tinha configurado antes de o ZombieDecay tocar em qualquer coisa, independente de quantos
restarts de servidor aconteceram no meio do caminho.

### Estado atual

`Core._originalLore` (`Core.lua:35`) é uma variável de módulo comum, não persistida em
`ModData`/`GlobalModData`. `captureOriginalLore()` (`Core.lua:305-317`) só verifica
`if Core._originalLore then return end` — ou seja, "já capturei nesta execução do processo", não
"já capturei alguma vez na vida deste save". Toda vez que o processo Lua reinicia (qualquer restart
de servidor, ou fechar/reabrir single-player), a primeira chamada subsequente a `applyVanillaLore()`
recaptura a partir do estado *atual* das sandbox options — que, se o módulo já estava ativo há dias,
é um valor já modificado por este mesmo módulo, não o preset original do admin. Isso não requer
nenhuma ação maliciosa nem cliente hostil — acontece em qualquer operação normal de manutenção de
servidor de longa duração (os próprios cenários de sessão de 24h/72h da seção 10 do plano
tipicamente incluem pelo menos um restart).

### Impacto

`restoreOriginalLore()` (chamado quando o admin desliga o módulo) passa a restaurar para um valor
incorreto — um snapshot intermediário de decaimento, não o preset real do admin — de forma
silenciosa (sem erro, sem warning; o único log é o de opção-não-encontrada em
`setVanillaValue`, que não dispara aqui porque as opções existem, só têm o valor errado). O preset
original fica efetivamente perdido de forma permanente e silenciosa a partir do primeiro restart
pós-ativação — o admin não tem como saber que o "restore" não voltou ao que ele configurou, e não há
como recuperar o valor original sem reconfigurar manualmente o sandbox do zero. Isso bate com o
critério HIGH "perda/duplicação persistente de estado" da seção 2.2 do plano — é perda silenciosa e
permanente de uma configuração do admin, não um crash, mas uma corrupção de configuração persistente.

### Escala

Não é um finding de performance — é determinístico e acontece uma vez por restart de processo, sem
relação com população de zumbis ou número de jogadores. Afeta qualquer instalação que (a) use
ZombieDecay, (b) reinicie o servidor ao menos uma vez depois de o mundo já ter avançado além do dia
0, e (c) mais tarde desligue `Enabled` esperando reverter para o preset original — um subconjunto
plausível e comum de operação normal de servidor dedicado de longa duração.

### Memória

Não é um achado de memória — não há crescimento, é sobre a CORREÇÃO do valor de um único snapshot
capturado uma vez por processo.

### Possível crash

Não. Puramente incorreção silenciosa de dado persistente.

### Solução recomendada

Persistir `_originalLore` uma única vez por save (não por processo), por exemplo em
`GlobalModData`/`ModData.getOrCreate("LasciviousScriptsZombieDecay")`, com uma verificação
`if modData.originalLoreCaptured then <usar valores persistidos> else <capturar do estado atual E
gravar no modData> end` — análogo ao padrão `modData.ver = WZ_SANDBOX_VERSION` que
`LS_WanderingZombies_SandboxVars.lua` já usa para o mesmo tipo de problema (estado que precisa
sobreviver a um restart de processo, não só a um `OnGameStart`). Isso garante que a captura
"original" só aconteça de fato na primeiríssima vez que o módulo roda contra aquele save, e restart
subsequentes leiam o valor persistido em vez de recapturar do estado (já modificado) atual.

### Risco da solução

Baixo/médio — é um acréscimo de persistência isolado (grava um snapshot pequeno e fixo de 8 valores
de sandbox uma única vez), não altera a lógica de decaimento em si. Cuidado necessário: garantir que
a migração para o novo formato de captura não tente "recapturar" a partir de um estado já poluído em
saves que já passaram por essa situação antes do patch — nesses casos não há como recuperar o preset
original verdadeiro retroativamente; o patch só previne recorrência futura, não corrige o passado
(vale documentar isso para o usuário/changelog, sem tom de aviso de licença/autoria, só o fato
técnico).

### Teste de regressão

```text
save novo: capturar original, decair por X dias, desligar Enabled -> ZombieLore volta ao preset
  original real (comparar valores antes/depois byte a byte)
mesmo teste, mas com um restart do processo/servidor no meio do caminho (entre a ativação e o
  desligamento) -> o restore ainda deve bater com o preset original real, não com o valor decaído
  no momento do restart
múltiplos restarts consecutivos durante o decaimento -> _originalLore nunca muda de valor uma vez
  persistido
save pré-existente de antes do patch (já com _originalLore "poluído" por essa falha) -> comportamento
  documentado explicitamente (não é uma regressão nova, é uma limitação conhecida do save antigo)
```

## 3.6. Sumário — ZombieDecay

1 achado: **`ZD-001` (HIGH, `HIGH_CONFIDENCE`)** — `Core._originalLore` é recapturado a cada boot do
processo Lua em vez de uma única vez por save, corrompendo silenciosamente o ponto de restauração do
preset original do admin após qualquer restart de servidor ocorrido enquanto o módulo já estava
ativo. `PERF-CAND-002` permanece `NEEDS_PROFILING` com o modelo refinado (custo por-callback já é
mínimo e o resto está corretamente amortizado por geração/revisão; falta só o número real de
`OnZombieUpdate`/s em populações de 5k-10k+ para fechar o modelo). Sem achado de NaN/valor inválido
no rewriting de `ZombieLore` (checado explicitamente, cadeia aritmética inteira tem clamp/guarda).
Sem achado de double-apply de migração (o sistema de seis fases é recompute contínuo e idempotente a
partir de estado do próprio engine, não uma migração one-shot).

---

# 4. Sumário geral desta sessão

```text
LS_WanderingZombies:  0 CRITICAL/HIGH. PERF-CAND-003 refinado, mantido NEEDS_PROFILING.
TimeVote:              1 HIGH (TV-001, NEEDS_RUNTIME) — registro liveNetActions sem TTL/disconnect.
                        Autoridade de voto/consenso: limpa.
ZombieDecay:            1 HIGH (ZD-001, HIGH_CONFIDENCE) — _originalLore não sobrevive a restart.
                        PERF-CAND-002 refinado, mantido NEEDS_PROFILING. Sem NaN/corrupção de
                        sandbox. Sem double-apply de migração.
```

Nenhum CRITICAL encontrado nos três módulos. Dois HIGH novos (`TV-001`, `ZD-001`), nenhum deles
relacionado a autoridade de rede/cliente hostil — os `OnClientCommand` de `LS_WanderingZombies` e
`TimeVote` foram auditados assumindo cliente completamente modificado e nenhum expõe escrita de
estado, teleporte, execução administrativa ou bypass. Ambos os HIGH são bugs de lifecycle/persistência
(um registro de rede sem TTL, um snapshot de configuração sem persistência entre restarts) — a
categoria que o plano pede para revisar em "ETAPA 3 (memória)" e "ETAPA 10 (persistência)".

Próximo passo exato para reconciliação: `TV-001` e `ZD-001` devem passar pela tentativa de
refutação do Codex (seção 17 do plano) antes de ir para `03_RECONCILED_FINDINGS.md`. Nenhum patch
foi aplicado nesta sessão — primeira passada preservada.
