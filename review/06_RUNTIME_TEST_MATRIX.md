# 06 — Matriz de runtime antes do release

**Status:** `NOT_RUN — REVISÃO ENCERRADA, GATE NÃO SERÁ MAIS COBRADO PRÉ-RELEASE`
**Alvo:** Project Zomboid 42.20.4 Stable
**Nota (2026-08-27):** o dono do projeto encerrou a revisão pré-release e foi para produção sem
rodar estes gates formalmente — a verificação passa a acontecer em jogo real. Esta tabela fica como
referência de cenários a testar **se e quando** um problema real for reportado num destes módulos;
não é mais um bloqueador de release.

## Instrução para quem assumir

Não repetir a revisão estática. Executar o primeiro gate viável, trocar `NOT_RUN` pelo resultado e
anexar evidência curta (modo, cenário, log/observação). Se um gate exigir interação que não está
disponível, marcar `BLOCKED_MANUAL` uma vez e seguir ao próximo. Falha nova só reabre código se for
CRITICAL/HIGH inequívoca; nesse caso, documentar e corrigir imediatamente, sem esperar outra IA.

| Gate | Contexto mínimo | Resultado exigido | Resultado |
|---|---|---|---|
| BQoL Pry | SP + dedicated, sucesso/falha, sem tool, longe, safehouse, reforçada, spam | somente tentativa local válida; RNG servidor em MP | `NOT_RUN` |
| Better Push | SP + dedicated com 2 clientes; push simples/em cadeia, alvo distante fabricado e spam | push legítimo sincroniza; alvo remoto é recusado; fila drena e não há desync/erro recorrente | `NOT_RUN` |
| Climb Ladders | SP + dedicated, subir/descer, 1/múltiplos níveis, quatro direções, landing lateral | servidor calcula mesmo destino; pacote fabricado sem escada não move | `NOT_RUN` |
| PSR Computer | dedicated + host, individual/grupo, duas bases | computador real vinculado e raio curto aceitos; bank remota/replay recusados | `NOT_RUN` |
| Cyes Push Doors | dedicated + host, porta simples/dupla/garagem, latência | begin no estado anterior + transição aceitos; report isolado recusado | `NOT_RUN` |
| Alice Sling | arma anexada/nas mãos, todas variantes, repetição e exceção artificial | fila chega a zero, callback sai, hotbar permanece coerente | `NOT_RUN` |
| ZombieDecay | mundo novo e existente; salvar, reiniciar, desativar | snapshot persiste e restaura os oito valores originais | `NOT_RUN` |
| Wandering Zombies WIP | SP + host/dedicated; população alta, hordas variadas, migração e área limpa pelo jogador | movimento continua emergente/aleatório; nenhum diretor força zumbis ao jogador ou repovoa área limpa por ela estar vazia; budget permanece estável | `NOT_RUN` |
| Aegis Backup | 1/8/64 jobs e zonas pequenas/grandes; backup + restore | sem stall/OOM; arquivo e manifest válidos; restore idêntico | `NOT_RUN` |
| Durable Tools | boot + spawn/uso/quebra de amostra blunt, blade, spear, axe e ferramenta | parser sem erro; campos atuais do item presentes; durabilidade Hardened aplicada | `NOT_RUN` |
| Hotfix 42.20.4 | boot SP, host e dedicated | nenhum erro por API removida ou carregamento de módulo | `NOT_RUN` |
| TimeVote — eleitorado vazio | dedicated vazio >120 ticks; entrar/sair; voto solo e com 2 clientes | nenhum erro em `refreshElectorate`; roster/votos resetam; consenso continua server-authoritative | `FAIL_PRODUCTION / PATCHED_STATIC / NEEDS_PROD_RETEST` |
| Skully Faster Attack — OnFloor | boot dedicated Linux; ataques no chão com faca, 1H, 2H e heavy | 4 nós carregam sem `AnimNode.Parse`; timing e colisão dos ataques permanecem corretos | `FAIL_PRODUCTION / PATCHED_STATIC / NEEDS_PROD_RETEST` |

Saves que já foram alterados por uma versão antiga do ZombieDecay não permitem reconstruir
automaticamente valores anteriores inexistentes. No primeiro snapshot persistente de save antigo,
o servidor emite warning explícito.
