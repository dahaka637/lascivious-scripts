# Lascivious Scripts — Plano Final de Revisão Pré-Release

**Projeto:** Lascivious Scripts  
**Alvo:** Project Zomboid Build 42.20.x  
**Fase:** revisão técnica final antes da bateria de testes  
**Agentes:** Claude + Codex  
**Objetivo:** encontrar e corrigir somente problemas de **alta severidade** e problemas de **performance relevantes em escala real**.

---

# 1. Objetivo desta revisão

Esta revisão existe para responder a uma pergunta simples:

> Existe alguma falha capaz de comprometer seriamente a estabilidade, segurança, sincronização, persistência ou performance do pacote antes de começarmos a fase pesada de testes?

O foco é exclusivamente:

- **CRITICAL**;
- **HIGH**;
- problemas de performance que possam produzir:
  - travamentos;
  - grandes spikes;
  - degradação importante de FPS/TPS;
  - uso excessivo de CPU;
  - uso excessivo de RAM;
  - pressão extrema de GC;
  - crescimento de memória ao longo da sessão;
  - OutOfMemory;
  - filas/caches crescendo sem limite;
  - processamento que escala muito mal com muitos zumbis, jogadores, itens ou objetos.

Não gastar tempo com:

- estilo;
- organização;
- naming;
- comentários;
- formatação;
- refactors estéticos;
- pequenas duplicações;
- micro-otimizações;
- warnings sem consequência;
- pequenas melhorias de UI;
- performance baixa/média sem impacto real;
- mudanças de balanceamento;
- features novas.

A revisão deve ser conservadora:

> É melhor retornar 8 achados realmente importantes do que 100 “melhorias” irrelevantes.

---

# 2. Regra de severidade

## 2.1. CRITICAL

Usar somente se o problema puder plausivelmente causar um dos seguintes:

- crash do servidor;
- crash recorrente dos clientes;
- OutOfMemory;
- corrupção séria de save;
- perda massiva de estado;
- execução administrativa indevida;
- cliente não confiável podendo alterar estado autoritativo grave;
- teleporte arbitrário;
- bypass grave de proteção;
- operação remota capaz de afetar bases/jogadores sem autorização;
- loop infinito ou retry por tick capaz de tornar a aplicação inutilizável;
- fila/cache sem limite com crescimento capaz de esgotar memória;
- override incompatível capaz de impedir mundo/servidor de carregar.

## 2.2. HIGH

Usar quando houver impacto sério, mas não necessariamente destrutivo:

- grande desync multiplayer;
- perda/duplicação persistente de estado;
- lógica autoritativa incompleta;
- crash em fluxo legítimo específico;
- spike severo no main thread;
- operação `O(N²)` com cardinalidade realista alta;
- scan global repetido frequentemente;
- forte pressão de GC;
- retenção grande de memória;
- I/O pesado no main thread;
- monkey-patch/override capaz de quebrar feature central;
- incompatibilidade séria com Linux/case-sensitive;
- erro recorrente em callback frequente.

## 2.3. PERF-HIGH

Performance deve ser classificada como HIGH apenas quando houver evidência ou forte justificativa de escala.

Usar a fórmula:

```text
frequência × cardinalidade × custo por elemento
```

Exemplos:

```text
OnZombieUpdate × milhares de zumbis × chamadas caras
```

```text
100 jogadores × vários shoves/s × scan de todos os zumbis
```

```text
64 jobs × 90.000 tabelas pré-materializadas
```

```text
OnTick × container scan × milhares de itens
```

Não classificar algo como HIGH apenas porque está em `OnTick`.

---

# 3. Snapshot analisado

No snapshot atual do projeto:

```text
29 Mod IDs
1.469 arquivos publicados
314 arquivos Lua
```

Eventos/call sites relevantes encontrados:

```text
Events.OnTick.Add                      53
Events.OnTickEvenPaused.Add             1
Events.OnZombieUpdate.Add               4
Events.OnPlayerUpdate.Add               4
OnRefreshInventoryWindowContainers      2
Events.OnClientCommand.Add              34
sendClientCommand                     174
pcall(...)                             731
getModData(...)                        169
```

Validadores atuais:

```bash
python3 tools/validate_structure.py
python3 tools/audit_collisions.py
```

Resultado no snapshot:

```text
validate_structure.py -> PASS
audit_collisions.py   -> PASS
```

O validator retorna três warnings de case:

```text
LS_AliceWeaponSling/.../WorldItems/Clothing
LS_PlyskenSolarRevolution/.../client/UI
LS_PlyskenSolarRevolution/.../client/PSR/UI
```

Eles não devem ser automaticamente tratados como bugs.

A revisão deve determinar:

```text
CONFIRMED_SAFE_CASE
ou
REAL_CASE_BUG
```

---

# 4. Fontes de verdade

Claude/Codex devem começar lendo:

```text
README.md
docs/STATUS.md
docs/ARCHITECTURE.md
docs/MODULE_REGISTRY.md
docs/COLLISION_REGISTRY.md
docs/SERVER_MOD_ORDER.md
```

Depois:

```text
vendor/<mod>/INTEGRATION.md
vendor/<mod>/LOCAL_CHANGES.md
vendor/<mod>/upstream/
```

Entretanto:

> Documentação NÃO é prova de que o código atual está correto.

Se a documentação diz:

```text
"server authoritative"
"safe"
"validated"
"sem colisão"
"já corrigido"
```

isso deve ser confirmado novamente no código.

Já existem casos no snapshot onde a documentação afirma uma coisa mais forte do que aquilo que o código realmente garante.

---

# 5. Regra operacional fundamental — dinâmica vigente

## DOCUMENTAR E RESOLVER NO MESMO CICLO

Não existe mais primeira passada separada, auditoria independente obrigatória nem espera pela outra
IA. A dinâmica atual substitui qualquer instrução histórica em contrário neste arquivo:

```text
achar -> confirmar com evidência direta -> documentar -> corrigir -> validar -> atualizar status
```

Não reabrir módulos já fechados nem repetir PRE-items resolvidos. Antes de iniciar, ler o estado
atual em `review/00_INVENTORY.md`, `03_RECONCILED_FINDINGS.md`, `07_PATCH_PLAN.md` e
`08_RELEASE_BLOCKERS.md`; esses arquivos prevalecem sobre listas históricas deste plano.

## REGISTRO CONTÍNUO OBRIGATÓRIO — antes de qualquer aprofundamento

Todo achado ou candidato a achado deve ser documentado **imediatamente**, antes de o agente
continuar a investigação, tentar corrigi-lo ou depender apenas do contexto da conversa.

Os arquivos Markdown dentro de `review/` são a fonte de verdade compartilhada entre Claude e
Codex durante esta fase. Nenhum achado pode existir somente no chat, na memória do agente ou em
anotações temporárias.

Ao encontrar algo relevante, o agente deve primeiro registrar no arquivo correspondente:

```text
status atual (INVESTIGATING, CONFIRMED, REJECTED ou NEEDS_RUNTIME)
módulo
arquivo e linha
função/evento
evidência já observada
hipótese e impacto possível
o que já foi verificado
o que ainda falta verificar
próximo passo exato
```

Um candidato ainda incompleto deve ser registrado como `INVESTIGATING`; não é necessário esperar
uma conclusão para escrevê-lo. Antes de encerrar uma sessão, trocar de módulo, sofrer compactação
de contexto ou entregar o trabalho ao outro agente, atualizar o registro com o último estado
conhecido.

## Regra de responsividade e produtividade

- comunicar ao usuário em uma frase curta o que está sendo executado e depois avançar;
- atualizar documentação a cada achado ou marco material, sem acumular tudo para o fim;
- não gastar uma sessão recapitulando documentos já consolidados;
- não pedir confirmação para leitura, validação ou patch claramente dentro do escopo;
- se um teste depender do engine, registrar uma única vez o bloqueio exato e continuar os demais
  gates executáveis;
- não criar fila de “validação pela outra IA”; segunda opinião só resolve dúvida técnica concreta;
- ignorar LOW/MEDIUM, limpeza estética e profiling especulativo;
- terminar cada sessão com estado objetivo: feito, evidência, pendência real e próximo comando.

Claude e Codex podem continuar a investigação iniciada pelo outro usando esses arquivos. Não
apagar silenciosamente registros anteriores: complementar, refutar ou reconciliar deixando o
histórico e a justificativa explícitos. Não existe pipeline fixo “Claude findings -> Codex findings
-> refutação”: qualquer agente pode concluir, corrigir e validar um item sozinho quando a evidência
for suficiente. O agente seguinte começa da pendência registrada, não do início da investigação.

---

# 6. Divisão de trabalho

# 6.1. Claude

Claude deve priorizar:

- arquitetura;
- invariantes;
- multiplayer;
- autoridade;
- persistência;
- sequência de estados;
- TimedActions;
- relações entre módulos;
- ownership;
- lifecycle de objetos;
- reconnect;
- unload/reload;
- error paths;
- race conditions;
- save corruption;
- regressões conceituais.

Perguntas que Claude deve fazer:

```text
Quem é a autoridade desse estado?

O cliente está comunicando intenção ou resultado?

O servidor revalida?

O que acontece se o objeto sumir?

O que acontece se o chunk descarregar?

O que acontece se dois players fizerem isso simultaneamente?

Quem adiciona essa referência?

Quem remove?

Existe timeout?

O que acontece depois de disconnect?

O que acontece depois de death?

Esse estado sobrevive a restart?

O código trata "não carregado" como "não existe"?

A operação é idempotente?
```

---

# 6.2. Codex

Codex deve priorizar cobertura mecanizada.

Ele deve gerar inventários completos de:

```text
Events.OnTick
Events.OnZombieUpdate
Events.OnPlayerUpdate
OnRefreshInventoryWindowContainers
OnClientCommand
OnServerCommand
sendClientCommand
sendServerCommand
getModData
transmitModData
queues
caches
registries
weak tables
TimedActions
monkey-patches
full overrides
file I/O
loadstring
getZombieList
getObjects
getMovingObjects
```

Codex deve localizar exatamente:

```text
arquivo
linha
função
evento
callers
callees importantes
```

Um grep sem leitura da função completa NÃO conta como revisão.

---

# 7. Etapas obrigatórias

# ETAPA 0 — Congelar o snapshot

Antes de qualquer alteração:

```bash
python3 tools/validate_structure.py
python3 tools/audit_collisions.py
python3 tools/generate_server_mods.py
```

Registrar:

```text
data
Build alvo
Mod IDs
Mods= gerado
warnings
hash dos arquivos principais
```

Não fazer commit automático.

Não alterar git remote.

---

# ETAPA 1 — Inventário técnico

Gerar:

```text
review/00_INVENTORY.md
```

Para cada módulo:

```text
Mod ID
Lua files
server files
client files
shared files
OnTick
OnZombieUpdate
OnPlayerUpdate
OnClientCommand
OnServerCommand
sendClientCommand
sendServerCommand
queues
caches
ModData
TimedActions
monkey-patches
full overrides
file I/O
risk class
```

---

# ETAPA 2 — Auditoria de crashes e exceptions recorrentes

Buscar:

```bash
rg -n 'Events\.(OnTick|OnZombieUpdate|OnPlayerUpdate|OnContainerUpdate).*Add' Contents/mods -g '*.lua'
```

Para cada callback frequente:

1. ler a função inteira;
2. identificar todas as chamadas que podem falhar;
3. verificar tratamento da exceção;
4. verificar se o item da fila é removido antes/depois;
5. verificar se um erro pode ser repetido no próximo tick;
6. verificar se o erro gera log a cada tick;
7. verificar se o callback fica permanentemente instalado.

Padrão de alto risco:

```lua
if ready then
    dangerousOperation(job)
    table.remove(queue, i)
end
```

Se `dangerousOperation()` lança:

```text
table.remove nunca acontece
→ próximo tick
→ erro novamente
→ próximo tick
→ erro novamente
```

O padrão mais seguro é:

```text
retirar/invalidar job
→ executar protegido
→ log rate-limited
→ não repetir indefinidamente
```

---

# ETAPA 3 — Auditoria de memória

Buscar:

```bash
rg -n 'queue|cache|registry|pending|tracked|active|session|jobs|history|last[A-Z]' Contents/mods -g '*.lua'
```

Para cada estrutura responder:

```text
Quem adiciona?
Quem remove?
Existe limite?
Existe TTL?
Disconnect limpa?
Death limpa?
Unload limpa?
World reset limpa?
Erro limpa?
Callback ausente deixa referência viva?
Usa userdata como key?
Usa weak table?
```

## Procurar especialmente

### Strong references para:

```text
IsoPlayer
IsoZombie
IsoObject
InventoryItem
ItemContainer
IsoGridSquare
```

### Tabelas que guardam:

```text
todos os zombies vistos
todos os players vistos
todos os items vistos
todos os backups
todos os jobs
todos os objetos
```

### Strings gigantes

```text
table.concat
serialization
log buffering
snapshot completo em RAM
```

---

# ETAPA 4 — Auditoria de filas

Para cada queue:

```text
max size
input rate
processing rate
worst-case queue size
memory por job
object references por job
retry behavior
failure behavior
```

Não basta existir:

```lua
MAX_QUEUE = 64
```

Se cada job puder armazenar centenas de milhares de objetos, o limite continua perigoso.

Estimativa obrigatória:

```text
max_jobs × memória aproximada/job
```

---

# ETAPA 5 — Auditoria de performance de hot paths

Buscar:

```bash
rg -n 'Events\.(OnTick|OnTickEvenPaused|OnZombieUpdate|OnPlayerUpdate|OnContainerUpdate|OnRefreshInventoryWindowContainers)\.Add' Contents/mods -g '*.lua'
```

Dentro dos callbacks procurar:

```text
nested loops
table creation
string creation
sort
pcall
getZombieList
getObjects
getMovingObjects
getGridSquare
getModData
setVariable
sendClientCommand
sendServerCommand
transmitModData
pathfinding
disk I/O
large UI rebuild
```

---

# ETAPA 6 — Scans globais

Buscar:

```bash
rg -n 'getZombieList|getObjectListForLua|getOnlinePlayers|getObjects\(\)|getMovingObjects|getGridSquare' Contents/mods -g '*.lua'
```

Classificar:

```text
LOCAL
LOCAL_BOUNDED
CELL_WIDE
NETWORK_WIDE
WORLD_WIDE
```

Depois:

```text
USER_TRIGGERED
PER_TICK
PER_ZOMBIE
PER_PLAYER
PER_COMMAND
PER_10_MINUTES
```

Um scan `CELL_WIDE` acionado uma vez por dia provavelmente não é grave.

Um scan `CELL_WIDE` executado várias vezes por segundo pode ser HIGH.

---

# ETAPA 7 — Auditoria específica de zumbis

O servidor alvo trabalha com população alta.

Assumir cenários:

```text
500 zombies
2.000 zombies
5.000 zombies
10.000+ zombies
```

Revisar prioritariamente:

```text
LasciviousScripts/ZombieDecay
LS_WanderingZombies
LS_BetterPush
LS_CyesPushDoors
qualquer feature BQoL relacionada a zombies
```

## ZombieDecay

Arquivos:

```text
Contents/mods/LasciviousScripts/42/media/lua/client/LasciviousScripts/ZombieDecay/
```

Já observado:

```lua
Runtime.zombieCache = setmetatable({}, {__mode = "k"})
```

Isso é positivo.

Não declarar leak baseado apenas na existência do cache.

Entretanto `OnZombieUpdate` executa lógica por zumbi e, para sprinters, reaplica:

```lua
zombie:setVariable(...)
zombie:setVariable(...)
```

em todo update.

Medir:

```text
calls/s
avg µs
p95
p99
max
zombies processed/s
```

---

## Wandering Zombies

Já observado:

```lua
trackedZombies = setmetatable({}, { __mode = "k" })
```

e budget:

```lua
while processedCount < processLimit ...
```

Também remove wrappers inválidos.

Isso reduz bastante a suspeita de leak estrutural simples.

Não reescrever o sistema sem profiling.

Revisar:

```text
linked lists
horde merge
path requests
candidate selection
processLimit
frame degradation
stale wrappers
Director listener lifecycle
```

---

# ETAPA 8 — Auditoria de rede e autoridade

Buscar:

```bash
rg -n 'sendClientCommand|Events\.OnClientCommand\.Add' Contents/mods -g '*.lua'
```

Para cada comando client → server:

```text
1. Cliente envia intenção ou resultado?
2. Servidor valida tipo?
3. Servidor valida distância?
4. Servidor valida Z?
5. Servidor resolve o target?
6. Servidor valida permissão?
7. Servidor valida safehouse?
8. Servidor valida item/ferramenta?
9. Servidor recalcula RNG?
10. Existe rate limit?
11. Existe replay?
12. Existe packet duplicado?
13. O ID pode ter mudado?
14. Target pode estar unloaded?
15. Cliente consegue chamar o comando sem abrir UI?
```

Regra:

> Qualquer `sendClientCommand` deve ser analisado assumindo um cliente completamente modificado.

Nunca confiar em:

```text
botão escondido
menu
TimedAction client-side
check client-side
UI permission
```

---

# ETAPA 9 — TimedActions

Buscar:

```bash
rg -n 'ISTimedAction|NetTimedAction|serverStart|complete\s*=|:complete|:perform|:start|:stop' Contents/mods -g '*.lua'
```

Perguntas:

```text
O servidor recebe objeto ou coordenadas?
Objeto é re-resolvido?
A distância é revalidada?
Item ainda existe?
Item ainda pertence ao player?
Target continua válido?
Completion pode acontecer duas vezes?
Cancel limpa estado?
Disconnect limpa estado?
TimeVote interfere na duração?
```

---

# ETAPA 10 — Persistência e ModData

Buscar:

```bash
rg -n 'getModData|ModData\.|GlobalModData|savedObjectModData|transmitModData|OnSave|OnInitGlobalModData' Contents/mods -g '*.lua'
```

Investigar somente riscos HIGH/CRITICAL:

```text
state corruption
state overwrite
stale persistent reference
wrong identity key
unloaded == deleted
migration destructive
unbounded data growth
transmit every tick
```

---

# ETAPA 11 — Monkey-patches

Usar:

```text
docs/COLLISION_REGISTRY.md
```

mas confirmar no código.

Classificar patches:

## Menor risco

```text
capture original
call-through
idempotency guard
```

## Alto risco

```text
full replacement
sem call-through
ordem de carregamento obrigatória
```

Revalidar especialmente:

```text
LS_AliceWeaponSling
LS_EquipWhileRunning
LS_AegisPanel
LS_CleanHotBar
FixedLightOnBeltAF
LS_Antibodies
LS_PlyskenSolarRevolution
```

---

# ETAPA 12 — Overrides vanilla

Comparar com o vanilla EXATO da Build 42.20.x.

Prioridade:

```text
ZombieDecay AnimSets
Drag Bodies Faster
Faster Hood Opening
Better Engine Repair
Skully Faster Attack
Durable Tools Weapons
qualquer outro override completo
```

Para cada:

```bash
diff -u VANILLA BUNDLE
```

Pergunta:

> O bundle contém apenas o delta intencional sobre o vanilla atual?

Problema HIGH se:

- override remove correção recente;
- override copia versão antiga;
- override quebra novo state;
- override usa asset inexistente;
- override causa load failure.

---

# ETAPA 13 — Linux/case-sensitive

Rodar:

```bash
python3 tools/validate_structure.py
```

Depois verificar referências:

```text
require
models
textures
AnimSets
imports
directories
```

Os três warnings atuais devem receber conclusão explícita.

---

# ETAPA 14 — I/O e serialização

Buscar:

```bash
rg -n 'getFileReader|getFileWriter|readLines|write|zoneBackup|table\.concat|io\.' Contents/mods -g '*.lua'
```

Perguntas:

```text
arquivo inteiro é carregado em RAM?
conteúdo inteiro é mantido em tabela?
há concat duplicando memória?
I/O ocorre no main thread?
existe limite em bytes?
existe limite apenas em linhas?
job é incremental de verdade?
```

---

# ETAPA 15 — pcall

Existem centenas de `pcall`.

Não aceitar:

```text
"tem pcall, então está seguro"
```

Para pcall em caminho crítico:

```text
erro é logado?
log é rate-limited?
estado parcial fica vivo?
job é removido?
próximo tick tenta novamente?
queue fica envenenada?
```

---

# 8. Módulos prioritários

# P0 — revisar antes de todos

```text
LS_AegisPanel
LS_BurrisQualityOfLife
LS_ClimbLadders
LS_AliceWeaponSling
LS_PlyskenSolarRevolution
LS_BetterPush
LS_WanderingZombies
LasciviousScripts/ZombieDecay
LasciviousScripts/TimeVote
```

---

# P1

```text
LS_Antibodies
LS_CyesPushDoors
LS_EquipWhileRunning
LS_ProximityInventory
LS_ImprovisedSilencers
LS_MiniHealthPanel
LS_CleanHotBar
FixedLightOnBeltAF
```

---

# P2

Os demais módulos só devem ser revisados profundamente se:

- possuem full override;
- participam de colisão;
- possuem evento frequente;
- usam rede;
- mantêm estado persistente;
- forem puxados por finding de outro módulo.

---

# 9. Revisão de performance — metodologia obrigatória

Toda suspeita de performance deve ter um modelo.

Formato:

```text
EVENTO:
FREQUÊNCIA:
N:
CUSTO:
ALOCAÇÕES:
I/O:
REDE:
COMPLEXIDADE:
PIOR CENÁRIO REALISTA:
```

Exemplo:

```text
EVENTO: BetterPush shove
FREQUÊNCIA: variável por jogadores
N: zombies na cell
CUSTO: find O(Z) + chain O(K*Z)
COMPLEXIDADE: O((K+1)*Z)
```

---

# 10. Cenários de escala

Usar:

## Jogadores

```text
1
10
32
50
100
```

## Zombies

```text
500
2.000
5.000
10.000+
```

## Inventário

```text
1.000 items próximos
5.000
10.000
20.000+
```

## Sessão

```text
30 min
6 h
24 h
72 h
```

## Operações

```text
backup
restore
clearing
undo
network power scan
mass zombie shove
large inventory refresh
```

---

# 11. Instrumentação de performance

Criar temporariamente:

```text
review/perf/
```

Métricas mínimas:

```text
calls
calls/s
elapsed total
avg
p95
p99
max
elements processed
queue size
cache size
memory-related counters
network packets
```

Evitar log por chamada.

Acumular métricas e imprimir periodicamente.

---

# 12. Probes obrigatórios

Instrumentar temporariamente:

```text
Aegis_Backup.snapshotStep
Aegis_Backup.buildSnapshotJob
Aegis restore
Aegis Clearing
ZombieDecay.updateZombie
Wandering Zombies WZTick
WZZombie:update
BetterPush.findZombie
BetterPush.getDominoChain
PSR PowerBank:updateDrain
PSR PowerBank:getDrainBuilding
PSR network update
ProximityInventory refresh
Cyes Push Doors nearby scan
TimeVote server onTick
TimeVote timed-action registry
```

---

# 13. Memory probes

Monitorar:

```text
JVM heap used
JVM heap committed
GC count
GC pause
Lua/Kahlua structures quando possível
queue lengths
job lines
backup file size
deviceList sizes
tracked zombie count
```

Especialmente antes/depois de:

```text
large backup
restore
large clearing
long zombie session
reconnect loops
```

---

# 14. Auditoria de crescimento ao longo do tempo

O teste deve procurar:

```text
heap que nunca volta
queue que nunca volta
cache que só cresce
table keyed por IDs antigos
userdata retida depois de unload
player retido depois de disconnect
zombie retido depois de despawn
```

Executar ciclos:

```text
join
play
disconnect
join
play
disconnect
```

e:

```text
spawn zombies
kill/despawn
move para outra região
voltar
```

---

# 15. Cross-module review

## Zombie stack

```text
ZombieDecay
WanderingZombies
BetterPush
CyesPushDoors
```

Verificar:

```text
speed changes
horde state
pathing
knockdown
remote zombies
ownership
despawn
```

---

## Inventory stack

```text
ProximityInventory
CleanHotBar
BQoL nested containers
Aegis patches
```

---

## Equipment stack

```text
AliceWeaponSling
EquipWhileRunning
SimpleBeltFlashlight
CleanHotBar
```

---

## Health stack

```text
Antibodies
MiniHealthPanel
BQoL medical features
```

---

## TimedAction stack

```text
TimeVote
Antibodies
PSR
EquipWhileRunning
BQoL
```

Testar em:

```text
1x
5x
20x
cancel
movement
zombie interruption
disconnect
```

---

# 16. Formato obrigatório de finding

Todo finding:

```text
ID:
Severidade:
Confiança:
Módulo:
Lado:
Arquivo:
Linha:
Função:
Trigger:
Cenário mínimo:
Estado esperado:
Estado atual:
Impacto:
Escala:
Evidência:
Complexidade:
Memória:
Possível crash:
Solução recomendada:
Risco da solução:
Teste de regressão:
```

Confiança:

```text
CONFIRMED_STATIC
HIGH_CONFIDENCE
NEEDS_RUNTIME
NEEDS_PROFILING
```

---

# 17. Regra de decisão para blockers (atualizada pelo mantenedor em 2026-08-26)

Uma segunda IA **não é mais uma etapa obrigatória** para aceitar um achado. Um único revisor
pode confirmar CRITICAL/HIGH quando registrar evidência direta e suficiente: caminho, linhas,
fluxo de entrada, checks existentes e impacto demonstrável. A segunda opinião fica reservada para
ambiguidade real de engine, checks indiretos não resolvidos ou divergência que mudaria a decisão.

O objetivo desta revisão passa a ser produtividade orientada a risco:

```text
prioridade principal: CRITICAL com impacto direto e reproduzível
prioridade secundária: HIGH inequívoco com crash, corrupção/perda persistente ou degradação grave
não bloqueia release: candidato especulativo, NEEDS_PROFILING ou NEEDS_RUNTIME sem evidência
```

Fluxo:

```text
revisor encontra -> lê entrada, callers e checks -> documenta evidência ->
CONFIRMED_STATIC / REJECTED_FALSE_POSITIVE / NEEDS_RUNTIME / NEEDS_PROFILING -> patch plan
```

Se uma segunda opinião for usada, ela serve para resolver a dúvida específica; não cria uma fila
obrigatória nem impede que os demais blockers avancem.

---

# 18. Arquivos de saída

Criar:

```text
review/
├── 00_INVENTORY.md
├── 01_CLAUDE_FINDINGS.md
├── 02_CODEX_FINDINGS.md
├── 03_RECONCILED_FINDINGS.md
├── 04_PERFORMANCE_FINDINGS.md
├── 05_MEMORY_AND_CRASH_FINDINGS.md
├── 06_RUNTIME_TEST_MATRIX.md
├── 07_PATCH_PLAN.md
└── 08_RELEASE_BLOCKERS.md
```

---

# 19. `08_RELEASE_BLOCKERS.md`

Deve conter somente:

```text
CRITICAL
HIGH
PERF-HIGH confirmado
```

Não incluir:

```text
LOW
MEDIUM
cosmetic
refactor
nice-to-have
```

---

# 20. Correção contínua durante a revisão (atualizada pelo mantenedor em 2026-08-26)

Não é mais necessário esperar a primeira passada inteira terminar. Assim que um achado estiver
confirmado por evidência direta, ele deve ser documentado e pode ser corrigido imediatamente. Cada
correção precisa manter o finding de origem, registrar o diff conceitual e executar ao menos sintaxe
e validadores antes de ser marcada como resolvida.

```text
1. documentar o achado confirmado;
2. corrigir CRITICAL;
3. corrigir HIGH inequívoco;
4. corrigir PERF-HIGH com mecanismo demonstrado;
5. reexecutar validators;
6. reexecutar syntax checks;
7. revisar diff;
8. rodar testes focados;
9. retomar a varredura crítica.
```

---

# 21. Syntax/static checks

Se disponível:

```bash
find Contents/mods -type f -name '*.lua' -print0 | xargs -0 -n1 luac5.1 -p
```

Também buscar resíduos:

```bash
find Contents -type f \( -name '*.bak' -o -name '*.tmp' -o -name '*.old' -o -name '*~' \)
```

---

# 22. Critério para terminar a revisão

A revisão pré-release está pronta quando:

```text
CRITICAL conhecidos = 0 sem patch
HIGH conhecidos = 0 sem decisão
PERF-HIGH conhecidos = corrigidos ou medidos/aceitos
todos P0 críticos revisados por ao menos um revisor com evidência direta
todos OnClientCommand P0/P1 revisados
todos hot paths P0 revisados
full overrides importantes comparados ao vanilla
memory jobs revisados
runtime matrix criada
compatibilidade 42.20.4: ausência de chamadas loadstring/loadstream confirmada e boot SP/host/dedicated testado
```

## 21.1. Hotfix de segurança 42.20.4 — gate adicional obrigatório

O hotfix 42.20.4 removeu `loadstring` e `loadstream`. Antes do release:

```text
buscar chamadas executáveis das duas APIs em Contents/
distinguir código distribuído de cópias upstream em vendor/
substituir qualquer execução dinâmica por parser fechado ou command dispatch explícito
executar boot/runtime em 42.20.4 nos modos SP, host e dedicated
```

O resultado e a evidência devem ser registrados em `review/00_INVENTORY.md` e na matriz de runtime.

---

# 23. Achados já constatados nesta pré-revisão

**HISTÓRICO — NÃO REEXECUTAR.** PRE-001..005 foram confirmados, documentados e corrigidos. Os
vereditos atuais estão em `review/03_RECONCILED_FINDINGS.md` e os patches em
`review/07_PATCH_PLAN.md`. Esta seção preserva a evidência anterior ao patch, não uma fila aberta.

---

## PRE-001 — CRITICAL — BQoL Pry confia no resultado escolhido pelo cliente

### Arquivos

```text
Contents/mods/LS_BurrisQualityOfLife/42/media/lua/shared/TimedActions/BQoL_PryAction.lua
Contents/mods/LS_BurrisQualityOfLife/42/media/lua/server/BQoL/BQoL_Commands.lua
Contents/mods/LS_BurrisQualityOfLife/42/media/lua/shared/BQoL/BQoL_PryLogic.lua
```

### Evidência

Em `BQoL_PryAction.lua`, aproximadamente linha 92:

```lua
local succeeded = BQoL.Pry.roll(playerObj, self.penalty)

if succeeded then
    if isClient() then
        self:sendToServer("prySuccess")
```

O cliente decide:

```text
prySuccess
ou
pryFailure
```

Servidor, aproximadamente linha 43:

```lua
function handlers.prySuccess(playerObj, args)
    local target = resolveTarget(args)
    ...
    BQoL.Pry.applySuccess(target.object, playerObj, target.kind)
end
```

O servidor re-resolve o objeto, mas não recalcula a tentativa.

Também não foi observado no handler:

```text
safehouse validation
tool validation
distance
TimedAction proof
RNG server-side
rate limit
```

A proteção de SafeHouse existe no menu cliente:

```lua
not BQoL.Pry.isBlockedBySafehouse(...)
```

mas não no servidor antes de `applySuccess`.

### Impacto

Cliente alterado pode fabricar um `prySuccess`.

### Solução recomendada

Eliminar protocolo:

```text
prySuccess
pryFailure
```

Cliente deve enviar somente:

```text
pryAttempt
```

Servidor deve:

```text
resolver target
validar distância
validar safehouse
validar ferramenta
validar estado
recalcular RNG
aplicar resultado
sincronizar
rate-limit
```

---

## PRE-002 — CRITICAL — Climb Ladders expõe primitive de teleporte

### Arquivo

```text
Contents/mods/LS_ClimbLadders/42/media/lua/server/SubirEscaleras_Server.lua
```

### Evidência

Aproximadamente linha 39:

```lua
local function onClientCommand(...)
```

Validação usa somente deltas:

```lua
MAX_HORIZONTAL = 2
MAX_VERTICAL = 8
```

Depois:

```lua
player:teleportTo(args.x, args.y, args.z)
```

Não foi observada validação server-side de:

```text
existência de escada
origem da escada
destino calculado pelo servidor
cooldown
rate limit
```

O cliente também aplica movimento local imediatamente.

### Impacto

Um cliente modificado pode repetir pequenos teleportes aceitos pelo servidor.

### Solução recomendada

O cliente NÃO deve enviar destino.

Enviar:

```text
requestClimb(ladder reference/coordinates)
```

Servidor:

```text
resolve ladder
validate adjacency
validate geometry
calculate destination
validate destination
teleport
broadcast result
```

---

## PRE-003 — CRITICAL/HIGH — PSR possui comandos de rede sem autorização contextual suficiente

### Arquivo

```text
Contents/mods/LS_PlyskenSolarRevolution/42/media/lua/server/PSR/PowerBank/PowerBankSystem_Commands.lua
```

### Pontos

```text
Commands.controlDeviceGroup ~ linha 334
Commands.controlDevice      ~ linha 409
```

Existe revalidação de device membership, o que é positivo.

Porém o servidor ainda resolve a Power Bank escolhida pelo cliente:

```lua
local pb = getPowerBank(args.bank)
```

O dispatch recebe comandos diretamente de:

```lua
Events.OnClientCommand
```

Não foi observada uma camada geral provando:

```text
player realmente está usando aquele terminal
player está próximo
terminal pertence à bank
sessão ainda está válida
player tem direito de operar essa rede
```

### Solução recomendada

Criar sessão server-side para Solar Computer:

```text
sessionId
player
terminal
bank/network
createdAt
expiresAt
```

Todo comando de controle deve validar essa sessão.

Operações físicas devem validar proximidade e estado diretamente.

---

## PRE-004 — HIGH / risco de crash-OOM — Aegis Backup pré-materializa estruturas enormes

### Arquivo

```text
Contents/mods/LS_AegisPanel/42/media/lua/server/Aegis_Backup.lua
```

### Constantes

Aproximadamente linha 16:

```lua
SNAP_BUDGET = 250
REST_BUDGET = 32
MAX_COLUMNS = 90000
MAX_LINES = 400000
MAX_QUEUED = 64
```

### Problema A — columns

`buildSnapshotJob()`, aproximadamente linha 748:

```lua
local columns = {}
local seen = {}
...
table.insert(columns, { x = x, y = y })
```

Um job pode materializar:

```text
90.000 tabelas
```

Fila:

```text
64 jobs
```

Worst-case teórico:

```text
5.760.000 pequenas tabelas
```

antes de contar conteúdo dos snapshots.

### Problema B — snapshot inteiro em RAM

Cada job mantém:

```lua
lines = {}
```

e `saveSquare()` adiciona strings com:

```text
squares
objects
containers
items
modData
```

### Problema C — duplicação no final

`snapshotStep()`:

```lua
local content = table.concat(job.lines, "\n")
```

Nesse momento coexistem:

```text
job.lines + strings
content gigante
```

aumentando o pico de heap.

### Problema D — restore

Restore carrega até:

```text
400.000 linhas
```

em tabela.

A fila aceita vários jobs.

### Problema E — budget enganoso

`SNAP_BUDGET = 250` significa 250 colunas.

Cada coluna percorre:

```text
Z -8 até 7
```

portanto:

```text
até 4.000 squares/tick
```

mais todos os objetos/items daqueles squares.

### Solução recomendada

Reescrever para streaming incremental:

```text
job pequeno
cursor rectangle/x/y/z/object/item
buffer pequeno
append incremental em arquivo temporário
budget por tempo
```

Exemplo:

```text
MAX_MS_PER_TICK
MAX_SQUARES
MAX_OBJECTS
MAX_ITEMS
```

Fila deve guardar somente descritores pequenos.

Restore também deve ser streaming.

---

## PRE-005 — HIGH — Alice Weapon Sling possui callback OnTick potencialmente envenenável

### Arquivo

```text
Contents/mods/LS_AliceWeaponSling/42/media/lua/shared/TimedActions/ISClothingExtraAction_AliceWeaponSling.lua
```

### Erro concreto

`preserveHotbarSlot()`, aproximadamente linha 149:

```lua
item:setAttachedSlot(slotIndex)
item:setAttachedSlotType(slotType)
item:setAttachedToModel(model)
```

Porém nessa função os valores disponíveis são:

```text
data.item
data.newSlotType
```

`item` e `slotType` não são locais/parâmetros dessa função.

### Segundo problema

`onRepairTick()`, aproximadamente linha 286:

```lua
restoreAttachedWeapon(data.attached)
table.remove(repairQueue, index)
```

Se `restoreAttachedWeapon()` lança:

```text
table.remove não roda
entrada continua ticks <= 0
próximo OnTick tenta novamente
erro novamente
```

Isso pode criar:

```text
exception storm
log storm
queda extrema de FPS
client instability
```

### Solução recomendada

Corrigir:

```text
item      -> data.item
slotType  -> data.newSlotType
```

E tornar queue exception-safe:

```text
remover/inativar entrada antes de operação perigosa
pcall
log once/rate limit
sem retry infinito
```

Revisar a segunda repair queue em:

```text
ISAttachItemHotbar_AliceWeaponSling.lua
```

pelo mesmo padrão.

---

# 24. Candidatos de performance já identificados

**HISTÓRICO / NÃO BLOQUEANTE.** Estes não devem ser promovidos automaticamente a HIGH sem profiling
nem reabertos antes da matriz de runtime. O único mecanismo PERF-HIGH confirmado, Aegis Backup, já
foi corrigido; estado atual em `review/04_PERFORMANCE_FINDINGS.md`.

---

## PERF-A — BetterPush scan global de zombies

Arquivos:

```text
Contents/mods/LS_BetterPush/42/media/lua/shared/BetterPush_Shared.lua
Contents/mods/LS_BetterPush/42/media/lua/server/BetterPush_Server.lua
```

`findZombie()`, ~linha 131:

```lua
local zombies = cell:getZombieList()

for i = 0, zombies:size() - 1 do
```

`getDominoChain()`, ~linha 62:

```lua
local allZombies = cell:getZombieList()
```

e para cada elo procura novamente na lista.

Complexidade aproximada:

```text
find       O(Z)
chain      O(K × Z)
total      O((K+1) × Z)
```

Com `K≈4`:

```text
~5 passes na lista de zombies por shove
```

Em população Insane + muitos players isso pode gerar spikes.

### Solução provável

Lookup do target por ID/índice eficiente.

Para cadeia, usar:

```text
movingObjects de squares próximos
3x3 / 5x5
```

em vez de todos os zombies da cell.

Adicionar budget global server-side.

---

## PERF-B — PSR recalcula grandes footprints por Power Bank

Arquivo principal:

```text
PowerBankObject_Server.lua
```

`PowerBank:getDrainBuilding()` faz scans tridimensionais do footprint associado.

O sistema de network chama `member:updateDrain()` em múltiplos membros.

Consequentemente uma rede com várias banks pode repetir scans parcialmente sobrepostos.

O código já possui algumas otimizações e deduplicação posteriores.

Portanto:

> não classificar como HIGH sem medir.

### Probe

Medir:

```text
banks/network
area scanned
squares visited
devices found
updateDrain ms
network total ms
```

---

## PERF-C — ZombieDecay OnZombieUpdate

Arquivo:

```text
ZombieDecay/Client.lua
```

Já possui weak cache.

Para sprinters:

```lua
zombie:setVariable(MOVE_VARIABLE, moveScale)
zombie:setVariable(LUNGE_VARIABLE, lungeScale)
```

é reaplicado em todo `OnZombieUpdate`.

Medir com milhares de zombies.

---

## PERF-D — Wandering Zombies

Já possui:

```text
weak trackedZombies
processLimit
cleanup
```

Portanto não reescrever baseado em suspeita.

Medir:

```text
WZTick
WZZombie:update
horde join/merge
path request count
tracked zombies
```

---

## PERF-E — Cyes Push Doors

Investigar o scanner client-side de portas.

Procurar:

```text
scanNearbyDoors
OnTick
snapshot tables
pcall por object
```

Objetivo:

```text
quantos scans/s
quantos squares
quantos objects
quanto garbage
```

Se rodar dezenas de vezes/s sem necessidade, reduzir para:

```text
on tile change
interaction
5–10 Hz fallback
```

---

## PERF-F — Proximity Inventory

O módulo limpa o container virtual, então não há evidência atual de leak contínuo simples.

Porém reconstrói o inventário agregado:

```text
todos os containers próximos
todos os items
addAll
UI refresh
```

Testar:

```text
5k
10k
20k items
```

---

## PERF-G — TimeVote

Revisar:

```text
server OnTick
client OnTick
onlineRoster
vote recalculation
TimedAction registries
```

Somente promover se profiling mostrar impacto relevante.

---

# 25. Pontos de atenção de memória

Não confirmados como HIGH, mas devem ser checados.

## Aegis Clearing

```text
lastClearing[admin]
```

retém `blocks` completos para Undo.

Confirmar:

```text
TTL
limite
cleanup por disconnect
tamanho máximo
```

---

## Improvised Silencers

Revisar:

```text
observed suppressors
deferred weapon states
strong references
timeout
```

---

## BetterPush

Revisar:

```text
lastRequest
lastShoveReport
serverQueue
```

Confirmar cleanup.

---

# 26. Atenção especial: documentação conflitante

Exemplo importante:

`MODULE_REGISTRY.md` classifica Climb Ladders como:

```text
"autoridade MP já correta no upstream"
```

Porém o código atual do servidor aceita diretamente:

```text
args.x
args.y
args.z
```

e executa:

```lua
player:teleportTo(...)
```

sem provar a existência de escada.

Portanto a revisão deve assumir:

> comentários e docs podem estar desatualizados em relação ao último patch.

Sempre seguir código.

---

# 27. Ordem vigente para continuidade

As rodadas estáticas históricas foram concluídas. Quem assumir agora **não deve reiniciá-las**.

```text
1. ler review/08_RELEASE_BLOCKERS.md
2. ler review/06_RUNTIME_TEST_MATRIX.md
3. executar o próximo gate de runtime possível
4. registrar resultado imediatamente
5. corrigir no mesmo ciclo somente se aparecer novo CRITICAL/HIGH inequívoco
6. reexecutar os validadores afetados
```

Estado no fechamento estático de 2026-08-26: oito achados confirmados em `PATCHED_STATIC`, zero
CRITICAL/HIGH conhecido sem patch, autoridade Aegis fechada, full overrides prioritários comparados
à 42.20.4 e hotfix `loadstring`/`loadstream` limpo em `Contents/`. O gate restante é runtime, não uma
nova auditoria ampla.

---

# 28. Prompt final para Claude

```text
Leia este documento como rulebook, mas use `review/00`, `03`, `06`, `07` e `08` como estado atual.
Não reinicie a revisão estática: ela está concluída, com zero CRITICAL/HIGH conhecido sem patch.

Documente cada achado antes de agir. Achados confirmados podem ser corrigidos imediatamente,
conforme as seções 17 e 20 atualizadas pelo mantenedor.

Procure somente CRITICAL, HIGH e problemas de performance capazes de causar grande degradação, travamento, memory leak, GC excessivo, OOM ou crash.

Ignore estilo, naming, organização, pequenas otimizações e issues de baixa/média severidade.

Comece pelo próximo item ainda não executado de `review/06_RUNTIME_TEST_MATRIX.md`. PRE-001..005,
Aegis, P0/P1 e overrides já foram fechados; só os reabra se um teste produzir evidência nova direta.

Para rede, assuma cliente hostil.

Para performance, use frequência × cardinalidade × custo e não marque HIGH sem justificativa de escala.

Para memory leaks, prove quem mantém a referência e por que ela não é liberada.

Para cada finding inclua arquivo, linha, trigger, impacto, evidência, solução e teste.

Gere/atualize os relatórios em `review/`; não espere outra IA quando a evidência direta já for
suficiente. Seja responsivo: atualização curta por marco, ação imediata, sem longas recapitulações,
sem pedir autorização para passos seguros e sem transformar `NEEDS_PROFILING` especulativo em fila.

Se o engine/teste manual não estiver disponível, registre exatamente o que não pôde ser executado
uma vez e avance para o próximo gate possível. Ao encerrar, deixe o próximo comando concreto.
```

---

# 29. Prompt final para Codex

```text
Continue do estado consolidado em `review/00`, `03`, `06`, `07` e `08`; não repita a auditoria
estática já concluída.

Documente cada achado antes de agir. Achados confirmados podem ser corrigidos imediatamente,
conforme as seções 17 e 20 atualizadas pelo mantenedor.

Execute primeiro o próximo gate possível de `review/06_RUNTIME_TEST_MATRIX.md`. Só reabra código
quando o runtime apresentar evidência nova CRITICAL/HIGH.

Dê prioridade a:
- scans globais;
- nested loops;
- jobs pré-materializados;
- arrays/tabelas sem bound;
- userdata mantida em cache;
- callbacks que podem repetir erro;
- full-file serialization;
- table.concat de buffers grandes;
- client->server commands sem revalidação.

Não reporte questões LOW/MEDIUM.

Para performance, estime a complexidade e escreva o pior cenário realista.

Atualize o relatório correspondente em `review/`. Registre evidência e patch no mesmo ciclo;
segunda opinião é reservada a ambiguidade material. Comunique progresso por marcos curtos e não
pare para recontar trabalho já documentado.
```

---

# 30. Estado desejado antes dos testes

A fase de testes só deve começar com:

```text
PRE-001..005 corrigidos
RECONCILED-006..008 corrigidos
CRITICAL/HIGH conhecidos sem patch = 0
Aegis backup corrigido estaticamente
autoridade Aegis/P0/P1 fechada
full overrides prioritários comparados à 42.20.4
matriz de runtime pronta
```

Este estado já foi atingido estaticamente. Não usá-lo como checklist para repetir trabalho; seguir
diretamente para os testes.

---

# 31. Filosofia desta revisão

Não transformar esta fase em uma reescrita geral.

A pergunta para cada alteração é:

> Esta mudança remove um risco sério antes do release?

Se a resposta for não:

```text
não mexer agora
```

Objetivo final:

```text
código estável
sem release blockers conhecidos
sem bombas de memória
sem hot paths obviamente explosivos
sem autoridade MP gravemente quebrada
sem regressões críticas de vanilla
```

Depois disso:

```text
stress test
multiplayer test
long-session test
release candidate
```
