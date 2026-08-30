# 03 — Findings consolidados

**Status:** `CLOSED — EM PRODUÇÃO` (fechado pelo dono do projeto em 2026-08-27)
**Última atualização:** 2026-08-27
**Nota de encerramento:** a revisão pré-release está encerrada por decisão do dono do projeto. O
pacote foi para produção com zero CRITICAL/HIGH conhecido sem patch (ver seção 5) e sem teste de
runtime formal em `06_RUNTIME_TEST_MATRIX.md` — a verificação de runtime passa a acontecer
naturalmente em produção em vez de como gate pré-release. Não reabrir esta revisão nem iniciar nova
auditoria proativa; trabalho futuro é reativo, disparado só quando o dono do projeto reportar um
problema real observado em jogo.
**Regra ativa (seção 17 do plano, atualizada pelo mantenedor em 2026-08-26):** evidência direta e
suficiente de um único revisor basta para confirmar um blocker. Segunda opinião é opcional e usada
somente quando existe ambiguidade material. O foco é CRITICAL e, secundariamente, HIGH inequívoco
com crash, perda/corrupção persistente ou degradação grave. Candidatos especulativos não entram na
fila de blockers. Pela regra atualizada da seção 20, achados confirmados são documentados e
corrigidos imediatamente, sem aguardar o fim da primeira passada.

---

# 1. Totalmente reconciliados — prontos para `08_RELEASE_BLOCKERS.md`

Os cinco itens abaixo foram pré-identificados no próprio plano (seção 23), escritos formalmente por
Codex em `02_CODEX_FINDINGS.md` (Agente A, cobertura mecanizada) e depois cada um teve uma tentativa
de refutação independente por Claude em `01_CLAUDE_FINDINGS.md` (Agente B, foco em autoridade/
invariantes/multiplayer) — lendo os mesmos arquivos-fonte mais qualquer caller/validação indireta que
pudesse invalidar o achado. **Nenhum dos cinco foi refutado.** Verificação bidirecional completa.

## RECONCILED-001 — BQoL Pry aceita resultado escolhido pelo cliente

```text
IDs de origem: PRE-001 / CDX-001 / CLD-001
Severidade: CRITICAL
Confiança final: CONFIRMED_STATIC
Módulo: LS_BurrisQualityOfLife
Lado: client -> server
Veredito da reconciliação: CONFIRMED — nenhum agente encontrou motivo de refutação
```

Servidor aceita `prySuccess`/`pryFailure` como um resultado já decidido pelo cliente, sem revalidar
distância, ferramenta, safehouse ou Força exigida para porta reforçada. `Pry.isBlockedBySafehouse()` e
`Pry.canForceReinforced()` existem mas só são chamadas no menu client-side, nunca no handler servidor.
Claude confirmou adicionalmente que também não há checagem de distância em nenhum ponto da cadeia —
qualquer square carregado no servidor serve, não só squares próximos ao remetente. Detalhe completo em
`02_CODEX_FINDINGS.md` (CDX-001) e `01_CLAUDE_FINDINGS.md` (CLD-001).

**Solução recomendada (convergente entre os dois agentes):** eliminar o protocolo `prySuccess`/
`pryFailure`; cliente envia só `pryAttempt` (coordenadas + kind); servidor resolve o alvo, valida
distância/Z/ferramenta/safehouse/Força, recalcula o RNG no próprio servidor, aplica e sincroniza.
Adicionar rate limit por jogador+coordenada.

---

## RECONCILED-002 — Climb Ladders aceita teleporte incremental sem provar escada

```text
IDs de origem: PRE-002 / CDX-002 / CLD-002
Severidade: CRITICAL
Confiança final: CONFIRMED_STATIC
Módulo: LS_ClimbLadders
Lado: client -> server
Veredito da reconciliação: CONFIRMED — nenhum agente encontrou motivo de refutação
```

`isReasonable()` só compara as coordenadas recebidas contra a posição atual do jogador no servidor
(margem `MAX_HORIZONTAL=2`, `MAX_VERTICAL=8`) — nunca resolve um objeto "escada" real, e a detecção de
escada inteira vive só no cliente. Sem rate limit em todo o módulo (confirmado por grep). Claude
confirmou adicionalmente que `MAX_VERTICAL=8` é o salto isolado mais generoso dos cinco PRE-items —
um único pacote aceito pode cruzar ~um prédio inteiro de uma vez. Detalhe completo em
`02_CODEX_FINDINGS.md` (CDX-002) e `01_CLAUDE_FINDINGS.md` (CLD-002).

**Solução recomendada:** protocolo `requestClimb` com referência da escada de origem; servidor resolve
o objeto e calcula o único destino válido; valida origem/destino transitáveis; aplica cooldown por
jogador.

---

## RECONCILED-003 — PSR PowerBank não valida direito do jogador sobre o terminal/bank

```text
IDs de origem: PRE-003 / CDX-004 / CLD-003
Severidade: CRITICAL
Confiança final: CONFIRMED_STATIC
Módulo: LS_PlyskenSolarRevolution
Lado: client -> server
Veredito da reconciliação: CONFIRMED — nenhum agente encontrou motivo de refutação
```

`controlDevice`/`controlDeviceGroup` resolvem a Battery Bank só a partir de `args.bank` enviado pelo
cliente, sem checar proximidade/login/vínculo real do remetente com aquela bank. `psrDeviceIsListed`
trava contra apontar para fora da rede escolhida, mas não trava a escolha da rede em si. Claude
verificou especificamente a hipótese de sessão via `LinkComputer` levantada por Codex e confirmou que
**não existe nenhuma sessão** — `PSR_linkedBank` é modData comum, replicado e forjável por qualquer
cliente. Detalhe completo em `02_CODEX_FINDINGS.md` (CDX-004) e `01_CLAUDE_FINDINGS.md` (CLD-003).

**Solução recomendada:** sessão servidor curta (jogador + terminal real + bank), criada quando o
servidor confirma proximidade/abertura real do terminal, revalidada a cada comando; manter
`psrDeviceIsListed` como segunda camada.

---

## RECONCILED-004 — Aegis Backup materializa estrutura grande de forma síncrona

```text
IDs de origem: PRE-004 / CDX-005 / CLD-004
Severidade: HIGH / PERF-HIGH candidato
Confiança final: HIGH_CONFIDENCE para o mecanismo; NEEDS_PROFILING para a dimensão exata do pior caso
Módulo: LS_AegisPanel
Lado: server (custo local, não é bypass de autoridade)
Veredito da reconciliação: CONFIRMED — mecanismo confirmado por ambos; magnitude real requer profiling
```

`buildSnapshotJob()` constrói o array `columns` inteiro de uma vez, antes de qualquer budget por tick
entrar em ação; `checkDaily()` pode disparar essa construção síncrona para até 64 zonas (`MAX_QUEUED`)
no mesmo tick de `EveryTenMinutes`, sem ceder o main thread entre elas. Claude aplicou uma leitura mais
conservadora do teto teórico de Codex (5.760.000 tabelas exigiria 64 zonas todas próximas do teto
individual, extremo mas não impossível) mas confirma que o mecanismo síncrono em si já basta para o
critério HIGH desta revisão, independente da medição exata. Detalhe completo em
`02_CODEX_FINDINGS.md` (CDX-005) e `01_CLAUDE_FINDINGS.md` (CLD-004).

**Solução recomendada:** job guarda descritor + cursor, não `columns` pré-computado; streaming
incremental com buffer limitado; budget também na fase de enfileiramento de `checkDaily`.

**Pendência antes de fechar definitivamente:** profiling real (1/8/64 jobs, zonas de tamanho
variado) conforme seção 12 do plano — não muda o veredito CONFIRMED, só refina a severidade exata
entre HIGH e PERF-HIGH.

---

## RECONCILED-005 — Alice Weapon Sling: bug de escopo Lua trava fila de `OnTick`

```text
IDs de origem: PRE-005 / CDX-003 / CLD-005
Severidade: HIGH
Confiança final: CONFIRMED_STATIC (arquivo 1, bug de escopo determinístico) /
                 HIGH_CONFIDENCE (arquivo 2, mesmo padrão estrutural sem o bug de nome)
Módulo: LS_AliceWeaponSling
Lado: client/shared
Veredito da reconciliação: CONFIRMED — nenhum agente encontrou motivo de refutação
```

`preserveHotbarSlot()` em `ISClothingExtraAction_AliceWeaponSling.lua` referencia `item`/`slotType`
sem `local` — variáveis globais nunca definidas, lançando `attempt to index a nil value` de forma
100% determinística sempre que a função é chamada com a arma nas mãos (estado alcançável em jogo
normal). `onRepairTick()` chama a operação perigosa antes de `table.remove`, sem `pcall` — a entrada
quebrada nunca sai da fila e relança em todo `OnTick` subsequente. Claude confirmou adicionalmente
(não coberto pelo relatório original de Codex) que o segundo arquivo da mesma feature
(`ISAttachItemHotbar_AliceWeaponSling.lua`) tem os nomes corretos (sem o bug de escopo) mas repete o
mesmo padrão estrutural perigoso-antes-de-remover, e que `scheduleRepairWindow` insere 6 entradas por
evento de troca de sling nos dois arquivos — um agravante de amplificação não mencionado por Codex.
Detalhe completo em `02_CODEX_FINDINGS.md` (CDX-003) e `01_CLAUDE_FINDINGS.md` (CLD-005).

**Solução recomendada:** trocar `item`/`slotType` por `data.item`/`data.newSlotType`. Nos dois
arquivos, mover a remoção da fila para antes da operação perigosa (ou envolver em `pcall` e sempre
remover depois, com log rate-limited).

---

# 2. Findings posteriores já reconciliados

## RECONCILED-006 — Cyes Push Doors aceita causalidade fabricada

```text
IDs de origem: CLD-P1-001 / CDX-REF-001
Severidade: HIGH
Confiança final: CONFIRMED_STATIC
Módulo: LS_CyesPushDoors
Veredito: CONFIRMED — tentativa de refutação do Codex falhou
```

O servidor valida target, distância, Z, geometria, estado atual, atributos e RNG, mas aceita
`args.interaction=true` sem provar que o remetente causou uma transição recente. Porta comum já
aberta ou garagem já fechada satisfaz o gate estático indefinidamente; respeitados os cooldowns, um
cliente modificado próximo pode reaplicar dano/knockdown e desgaste/quebra de porta sem nova
interação. Não há concessão de XP no fluxo — correção feita na segunda opinião — mas os efeitos de
combate e dano persistente bastam para HIGH. Detalhes em `01c_CLAUDE_P1_AUTHORITY.md` e
`02_CODEX_FINDINGS.md` (`CDX-REF-001`).

**Solução recomendada:** servidor deve correlacionar porta + jogador + transição realmente observada
numa janela curta; estado estático e boolean do cliente não podem servir como prova de causalidade.

---

## RECONCILED-007 — ZombieDecay perde o snapshot original após save/restart

```text
IDs de origem: ZD-001 / CDX-REF-003
Severidade: HIGH
Confiança final: CONFIRMED_ENGINE_BYTECODE
Módulo: LasciviousScripts / ZombieDecay
Veredito: CONFIRMED — tentativa de refutação do Codex falhou
```

`Core._originalLore` vive somente no processo Lua. O engine 42.20.4 grava os valores atuais de
`SandboxOptions.instance` em `map_sand.bin` durante `GameWindow.save(boolean)` e os recarrega por
`SandboxOptions.load()` no próximo boot. Logo, após ZombieDecay alterar as opções, salvar e
reiniciar, a tabela Lua some e `captureOriginalLore()` recaptura do save os valores já decaídos.
Desligar o módulo depois restaura um snapshot intermediário, não a configuração original.

**Solução recomendada:** snapshot original pequeno e versionado em estado persistente por save,
capturado antes da primeira aplicação; migração deve deixar explícito que saves já poluídos não têm
como reconstruir automaticamente valores anteriores.

---

# 3. Finding refutado

## REJECTED-001 — TV-001 / TimeVote `liveNetActions`

```text
Veredito: REJECTED_FALSE_POSITIVE
Evidência: bytecode do engine Build 42.20.4
```

A hipótese exigia que um `NetTimedAction` abandonado continuasse retornando `progress < 1` para
sempre. `zombie.core.Action.getProgress()` calcula o progresso apenas pelo relógio servidor e pelos
campos `startTime/endTime`; desconexão não o congela. Duração negativa também ganha `endTime`
limitado por `AnimEventEmulator.getDurationMax()`. A entrada chega a `progress >= 1` e é removida.
Detalhe e comandos `javap` em `02_CODEX_FINDINGS.md` (`CDX-REF-002`).

---

# 4. Superfície crítica de autoridade

```text
LS_AegisPanel   PASS_STATIC_CRITICAL (com 1 achado HIGH corrigido nesta sessão, ver abaixo)
```

Escritas privilegiadas exigem área/capability derivada no servidor; rotas de autoatendimento derivam
a identidade do próprio remetente e validam seus objetos/ledgers. Nenhum bypass de autorização
CRITICAL/HIGH foi encontrado nos comandos auditados. **Correção sobre a nota anterior desta seção:**
"os 22 arquivos foram fechados" estava incorreto no momento em que foi escrito — só 7 dos 22 arquivos
(`Aegis_Roles`, `Aegis_Backup`, `Aegis_Kits`, `Aegis_Boost`, `Aegis_Construction`, `Aegis_Compare`,
`Aegis_Stats`) têm auditoria linha-a-linha registrada em `review/01d_CLAUDE_AEGIS_AUTHORITY.md`; os
outros 15 (`Aegis_Brand`, `Aegis_Builder`, `Aegis_Clearing`, `Aegis_Deaths`, `Aegis_Factions`,
`Aegis_Follow`, `Aegis_Log`, `Aegis_Moderation`, `Aegis_PlayerClaims`, `Aegis_PlayerPanel`,
`Aegis_PlayerStats`, `Aegis_PlayerVehicles`, `Aegis_Relations`, `Aegis_Server`, `Aegis_Zones`) não
foram verificados linha-a-linha nesta rodada e o "PASS" para eles reflete a auditoria anterior feita
durante a integração original do mod (`vendor/aegis-panel/INTEGRATION.md`), não o checklist estrito
desta revisão. Ver `RECONCILED-009` abaixo para o achado real que essa auditoria produziu.

## RECONCILED-009 — Aegis Construction: `constructionRestore` sem rate limit

```text
ID de origem: CLD-AEG-001
Severidade: HIGH
Confiança final: CONFIRMED_STATIC
Módulo: LS_AegisPanel
Lado: server (admin já autenticado na área "tools")
Veredito: CONFIRMED por leitura direta; PATCHED nesta sessão
```

`Commands.constructionRestore` (`Aegis_Construction.lua:564-671`) tem o gate de área correto
(`AegisRoles.canArea(player, "tools")`) mas, ao contrário de todo outro comando de escrita do módulo
e do seu vizinho `constructionList` na mesma tabela, nunca chamava `throttled(player)`. Por chamada
pode criar até 16 objetos de mundo, cada um com broadcast a todos os clientes, mais um append sem
compactação no journal em disco. Não é escalada de privilégio (exige sessão admin real já concedida),
mas dentro desse domínio permitia crescimento de estado de mundo e do journal sem limite de taxa.

**Correção aplicada:** adicionada a mesma chamada `if throttled(player) then return end` já usada em
`constructionList`, logo após o gate de área. `luac5.1 -p` confirma sintaxe válida pós-patch.

**Estado:** `PATCHED_STATIC` — `NEEDS_RUNTIME` (confirmar em jogo que o limite de 1/s não quebra o
fluxo legítimo de restauração em lote pela UI do painel).

## Próximo passo exato

1. Fechar os gates objetivos restantes de overrides e empacotamento.
2. Executar os testes de engine em `06_RUNTIME_TEST_MATRIX.md`.

---

# 5. Estado das correções imediatas (2026-08-26)

```text
RECONCILED-001 BQoL Pry             PATCHED_STATIC — NEEDS_RUNTIME MP
RECONCILED-002 Climb Ladders        PATCHED_STATIC — NEEDS_RUNTIME MP/geometria
RECONCILED-003 PSR Computer         PATCHED_STATIC — NEEDS_RUNTIME dedicated/host
RECONCILED-004 Aegis Backup         PATCHED_STATIC — NEEDS_RUNTIME + stress
RECONCILED-005 Alice Weapon Sling   PATCHED_STATIC — NEEDS_RUNTIME hotbar
RECONCILED-006 Cyes Push Doors      PATCHED_STATIC — NEEDS_RUNTIME transição/latência
RECONCILED-007 ZombieDecay          PATCHED_STATIC — NEEDS_RUNTIME save/restart
RECONCILED-008 Durable Tools        PATCHED_STATIC — NEEDS_RUNTIME load/items
```

Nenhum dos oito permanece sem patch. `PATCHED_STATIC` significa que o mecanismo vulnerável foi
removido e toda a árvore passou no parser Lua e validadores; não equivale a teste dentro do engine.
Detalhes e arquivos alterados estão em `07_PATCH_PLAN.md`; gates de jogo estão em
`06_RUNTIME_TEST_MATRIX.md`.

---

## RECONCILED-008 — Durable Tools sobrescreve 351 itens com snapshot anterior à 42.20.4

```text
ID de origem: CDX-OVR-001
Severidade: HIGH
Confiança final: CONFIRMED_STATIC
Módulo: LS_DurableToolsWeapons
Lado: parser de scripts / gameplay compartilhada
Veredito: CONFIRMED — comparação mecanizada de todos os 351 blocos
```

Os 351 Item IDs existem no vanilla 42.20.4 instalado, mas os 351 blocos bundled diferem fora de
`ConditionMax`/`ConditionLowerChanceOneIn`. O snapshot antigo ainda usa, entre outras diferenças,
`Type` em lugar de `ItemType`, tags sem namespace e não contém campos atuais como
`ResearchableRecipes`; também reverte valores atuais de itens individuais. Como o propósito
documentado deste módulo é alterar **somente durabilidade**, essa deriva é incompatível com a
intenção e pode apagar correções e comportamento atual do vanilla em uma superfície grande.

**Correção definida:** reconstruir cada um dos 351 blocos a partir do vanilla exato da 42.20.4 e
reaplicar somente os valores bundled de `ConditionMax` e `ConditionLowerChanceOneIn`. A validação
pós-patch deve provar: 351 IDs presentes, zero diferença não relacionada a durabilidade e nenhum
campo de durabilidade escolhido perdido.

**Estado:** `PATCHED_STATIC`. Resultado pós-sync: 351/351 IDs encontrados; 351/351 blocos idênticos
ao vanilla 42.20.4 quando os dois campos permitidos são ignorados; 351/351 valores de durabilidade
idênticos à variante Hardened prístina em `vendor/`; 10 arquivos e 351 blocos balanceados.
