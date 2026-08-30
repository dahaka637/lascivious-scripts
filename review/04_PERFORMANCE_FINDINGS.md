# 04 — Findings de desempenho e memória

**Status:** `BLOCKER_STATIC_PATCHED / PROFILING_OPTIONAL`  
**Última atualização:** 2026-08-26  
**Regra ativa:** suspeitas não são promovidas a `PERF-HIGH` sem evidência estática forte ou profiling.

Este arquivo registra o modelo de escala antes de qualquer decisão. Nenhum código de runtime foi
alterado nesta passada.

## PERF-CDX-001 — Aegis Backup/Restore pré-materializa filas e snapshots grandes

```text
Status: PATCHED_STATIC — aguardando teste de runtime/stress
Severidade candidata: HIGH / PERF-HIGH
Módulo: LS_AegisPanel
Referência cruzada: CDX-005 em 02_CODEX_FINDINGS.md
```

```text
EVENTO: criação e processamento de backup/restore
FREQUÊNCIA: manual e automação diária; múltiplas zonas podem ser construídas no mesmo callback
N: até 90.000 colunas/job; até 64 jobs; até 16 níveis Z/coluna; restore até 400.000 linhas/job
CUSTO: construção síncrona O(J*C); snapshot O(C*Z + objetos + itens); concat/escrita O(bytes)
ALOCAÇÕES: tabela {x,y} por coluna, arrays de columns/lines e string contígua final
I/O: conteúdo inteiro entregue à camada de store; restore pré-lê todas as linhas do job
REDE: não é o fator dominante
COMPLEXIDADE: memória O(J*C + linhas/bytes); trabalho O(C*Z + conteúdo)
PIOR CENÁRIO REALISTA: várias áreas grandes no auto-backup ou restore, pressionando heap/GC e
  produzindo stalls/OOM antes mesmo de os jobs chegarem à cabeça da fila
```

Evidência: `Aegis_Backup.lua:19-21,275-325,677-700,748-781,819-885,911-924` e
`Aegis_Store.lua:33-42,283-305`. O teto configurado permite 5.760.000 tabelas de coluna retidas;
com estimativa conservadora de 80–160 bytes por pequena tabela Kahlua, são aproximadamente
460–920 MB somente nessas entradas. O valor real precisa ser medido, mas a pré-materialização e a
duplicação de pico por `table.concat` estão confirmadas.

Probe obrigatório: 1/8/64 jobs, heap antes/depois, GC, tamanho dos buffers e p50/p95/p99/max do
tick. Solução candidata: descritor + cursor em vez de `columns`, escrita/leitura incremental com
buffer limitado, budget por tempo/bytes/conteúdo e fila menor.

Correção aplicada em 2026-08-26: jobs de backup guardam somente retângulos e cursor; sobreposição
é eliminada durante a iteração sem tabela `seen`; a saída usa buffers de até 1.000 linhas; cada
execução escreve em caminho próprio e só entra no manifest ao terminar; jobs de restore guardam
somente o path e usam reader incremental quando chegam à cabeça da fila. Foram removidos os dois
piores multiplicadores: `64 * 90.000` tabelas de coluna e `64 * 400.000` strings de restore.

---

## PERF-CAND-001 — BetterPush faz scans globais por tentativa aceita

```text
Status: NEEDS_PROFILING — não é blocker confirmado
Módulo: LS_BetterPush
```

```text
EVENTO: comando BetterPush/request aceito pelo rate limit servidor
FREQUÊNCIA: máximo nominal de um pedido por jogador a cada 350 ms
N: Z zombies na lista da cell; K elos da cadeia (default/máximo configurado normalmente 4)
CUSTO: findZombie O(Z); em sucesso, getDominoChain O(K*Z)
ALOCAÇÕES: results, used e até K entradas da serverQueue por sucesso
I/O: nenhum
REDE: até K broadcasts de sync por sucesso
COMPLEXIDADE: O(Z) por tentativa; O((K+1)*Z) em tentativa bem-sucedida
PIOR CENÁRIO REALISTA: 100 jogadores modificados, 10.000 zombies na cell, pedidos no limite de
  350 ms e chance máxima de 30%: aproximadamente 2,86 milhões de iterações/s no lookup mais
  3,44 milhões/s nas cadeias com K=4, antes do custo Lua/Java e broadcasts
```

Evidência: `BetterPush_Shared.lua:62-120,131-154` e `BetterPush_Server.lua:12-19,46-93`.
O servidor é autoritativo, tem validação de distância e rate limit por jogador. A fila atrasada
mantém referências fortes e usa `table.remove`, mas com K pequeno não há evidência estática de
`PERF-HIGH`. Medir 1/10/32/50/100 jogadores e 1k/5k/10k zombies. Uma otimização futura deve buscar
target por ID/índice e cadeia apenas nos squares vizinhos, preservando a autoridade servidor.

---

## PERF-CAND-002 — ZombieDecay reaplica variáveis por OnZombieUpdate de sprinter

```text
Status: NEEDS_PROFILING — não é blocker confirmado
Módulo: LasciviousScripts / ZombieDecay
```

```text
EVENTO: Events.OnZombieUpdate
FREQUÊNCIA: definida pelo engine por zombie ativo/controlado
N: zombies atualizados, com custo maior para sprinters
CUSTO: cache lookup + getSpeedType protegido; para sprinter, dois setVariable em cada callback
ALOCAÇÕES: uma entrada pequena por zombie em weak-key cache; sem alocação grande por callback
I/O: nenhum
REDE: indireta pelo estado de zombie; nenhuma mensagem Lua por callback
COMPLEXIDADE: O(N updates); constantes maiores para sprinters
PIOR CENÁRIO REALISTA: milhares de sprinters ativos recebendo callbacks frequentes, com duas
  travessias Lua/Java de setVariable por callback
```

Evidência: `ZombieDecay/Client.lua:7-18,84-101,103-145,147-163`. O cache usa chaves fracas; stats
são refeitos por geração de lore e tier por revisão diária, portanto não há leak estrutural nem
reclassificação completa a cada callback. Medir callbacks/s, sprinters ativos, tempo total e custo
das duas `setVariable`; só então avaliar cachear/reaplicar em transições de animação controladas.

---

## PERF-CAND-003 — Wandering Zombies distribui updates e busca de hordas por budget

```text
Status: NEEDS_PROFILING — não é blocker confirmado
Módulo: LS_WanderingZombies
```

```text
EVENTO: OnZombieUpdate para registro; WZTick para simulação e busca incremental de horda
FREQUÊNCIA: OnZombieUpdate do engine + um WZTick/frame
N: zombies locais rastreados; processLimit configurável 1–20, default 4
CUSTO: registro O(1); por tick até processLimit updates e até processLimit candidatos de horda
ALOCAÇÕES: um wrapper/list link por zombie; tabela weak-key de guarda; pequenas cópias de vetor
I/O: nenhum no hot path observado
REDE: clientes ignoram remote zombies; nenhum broadcast por tick neste fluxo
COMPLEXIDADE: O(processLimit) por frame, com uma varredura de horda amortizada pela linked list
PIOR CENÁRIO REALISTA: população muito alta aumenta o tempo entre revisitas; processLimit=20
  executa até ~40 passos de wrapper/horda por frame, além dos callbacks leves de registro
```

Evidência: `RYUKU_WanderingZombies.lua:28-53,60-136,138-228` e
`RYUKU_WanderingZombies_ZombieBase.lua:107-165,172-178`. O registry usa weak keys, a linked list
remove wrappers inválidos, clientes rejeitam zombies remotos e cada wrapper recusa update completo
antes de 250 ms. Essas salvaguardas são reais; o custo precisa ser medido em `WZTick`,
`WZZombie:update`, join/merge, path requests e quantidade rastreada antes de qualquer reescrita.

## Próximo passo exato

Executar somente o stress de runtime do Aegis previsto em `06_RUNTIME_TEST_MATRIX.md`. Os demais
candidatos permanecem `NEEDS_PROFILING`, sem mecanismo suficiente para bloquear o release; não
devem ampliar a revisão estática sob a diretriz atual de foco crítico.
