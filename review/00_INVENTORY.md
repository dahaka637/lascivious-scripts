# 00 — Inventário técnico da revisão pré-release

**Status:** `STATIC_COMPLETE / RUNTIME_PENDING`  
**Responsável pela abertura:** Codex  
**Última atualização:** 2026-08-26T20:21:16-03:00  
**Alvo:** Project Zomboid Build 42.20.4 Stable (e compatibilidade 42.20.x)

Este arquivo foi aberto na primeira passada da revisão; a frase histórica “nenhum Lua modificado”
valia somente para o snapshot inicial. Os números iniciais abaixo são inventário lexical preservado
como evidência. Para o estado atual, usar o checkpoint estático final e a fronteira no fim do arquivo.

**Diretriz de produtividade (2026-08-26):** deixou de existir a exigência de uma segunda IA validar
cada achado. Evidência direta de um revisor basta; segunda opinião só em ambiguidade material. A
passagem atual prioriza exclusivamente CRITICAL e HIGH inequívoco com consequência grave.

## Etapa 0 — snapshot congelado

### Dimensão atual

```text
Mod IDs:                 29
Arquivos em Contents/: 1510
Arquivos Lua:           314
```

O total de arquivos é maior que o valor histórico do plano porque o snapshot já inclui a cobertura
PT-BR nativa das opções de sandbox, concluída imediatamente antes do início desta revisão.

### Validadores executados

```text
python3 tools/validate_structure.py  -> PASS, sem erro estrutural
python3 tools/audit_collisions.py    -> PASS, nenhuma colisão de path/Mod ID
todos os 314 Lua com luac5.1 -p      -> PASS
resíduos *.bak/*.tmp/*.old/*~        -> nenhum encontrado
```

Warnings concluídos explicitamente na Etapa 13:

```text
LS_AliceWeaponSling/.../WorldItems/Clothing
LS_PlyskenSolarRevolution/.../client/UI
LS_PlyskenSolarRevolution/.../client/PSR/UI
```

Estado atual dos três: `SAFE_STATIC`.

- Alice: `models_X/WorldItems/Clothing` coincide com o casing do vanilla e com
  `mesh = WorldItems/Clothing/Sling_Flat`; renomear quebraria a referência em Linux.
- PSR `client/PSR/UI`: todos os `require "PSR/UI/..."` usam exatamente o mesmo casing.
- PSR `client/UI`: diretório vazio herdado da estrutura upstream, sem arquivo carregável.

Nenhum deles constitui incompatibilidade case-sensitive.

### Ordem gerada

```text
WorkshopItems=3788475731
Mods=LS_AegisPanel;LS_AliceWeaponSling;LS_AliceWeaponSlingRadialMenu;LS_Antibodies;LS_BetterEngineRepair;LS_BetterPush;LS_BurrisQualityOfLife;LS_CleanHotBar;LS_ClimbLadders;LS_CyesPushDoors;LS_DragBodiesFaster;LS_DurableToolsWeapons;LS_EquipWhileRunning;LS_FasterHoodOpening;LS_ImmersiveSuicide;LS_ImprovisedSilencers;LS_MiniHealthPanel;LS_OSRSExperienceBar;LS_PlyskenSolarRevolution;LS_ProximityInventory;LS_PushVehicle;LS_ResponsivePivoting;FixedLightOnBeltAF;LS_SkullysFasterAttackSpeed;LS_SkullysFasterSwingSpeed;LS_TacticalHold;LasciviousScripts;LS_TotalWeightRebalance;LS_WanderingZombies
```

O resultado de `tools/generate_server_mods.py` coincide com a linha canônica registrada em
`docs/SERVER_MOD_ORDER.md`. As duas restrições de ordem já documentadas também estão satisfeitas.

### Hashes do ponto de partida

```text
dd2165d1441ac8506c0d979b42623d528c5ca2081b1bb0a41d4868596affd0f1  Contents tree
6421c79b0d6446050925779091f355e0147efba80e09953d94c93fde912239c1  docs/MODULE_REGISTRY.md
999807b551f6b00e945e6e8d50b99504d2d59f50dca2f3210f530eb35146a19f  docs/COLLISION_REGISTRY.md
1ea3260d922e77d19fbe52881d672c23aed854146f244638c1d02f4f2d4407ba  docs/SERVER_MOD_ORDER.md
47144aeb9d087cb5f32fd562ada55a432fe8170983e32ad3de9f63337a8eb21f  plano da revisão
```

O hash da árvore é a soma determinística da lista ordenada de `sha256sum` de todos os arquivos sob
`Contents/`.

### Checkpoint depois das correções imediatas

```text
1583fa4e8d04f4fe63e94d32c88e882e4ad02cc8ab024f93b2a78bc7943b0c6a  Contents tree
Arquivos Lua: 315
Sintaxe de toda a árvore: PASS
Estrutura: PASS (somente os mesmos 3 case warnings)
Colisões: PASS
Ordem canônica do servidor: PASS
```

O hash inicial acima continua preservado como prova do snapshot auditado; este segundo hash é o
checkpoint após os sete patches registrados em `07_PATCH_PLAN.md`.

### Checkpoint estático final depois dos gates de override

```text
6b2e35762a7c5ac77d6c2d96910a1d962e3dbcad151d0eecee1daa1f1aad37e6  Contents tree
Arquivos em Contents/: 1509
Arquivos Lua: 315; luac5.1: PASS 315/315
XML: PASS 64/64
Estrutura: PASS (3 warnings encerrados como SAFE_STATIC)
Colisões: PASS
Ordem canônica do servidor: PASS
Durable overrides: PASS 351/351
Resíduos: nenhum
```

A redução líquida em relação aos 1.510 arquivos iniciais vem de: +1 helper de geometria para
Climb Ladders e -2 pseudo-overrides redundantes `defaultlunge.xml` do ZombieDecay. O hash anterior
permanece como checkpoint intermediário; este é o estado distribuído após todas as correções
estáticas registradas.

### Checkpoint após hotfixes de produção PROD-001/PROD-002

```text
58e5761b8a3342d043912f6a08134c557818b9ecf7904936d33ba70cc61798e8  Contents tree
Arquivos em Contents/: 1578
Arquivos Lua: 313; luac5.1: PASS 313/313
XML: PASS 64/64
Estrutura: PASS (os mesmos 3 warnings SAFE_STATIC)
Colisões: PASS
Ordem canônica do servidor: PASS
Durable overrides: PASS 351/351
Resíduos: nenhum
```

Este checkpoint representa a árvore corrente recebida depois das alterações posteriores à revisão
estática, já com o TimeVote sem dependência do global `next` e os quatro AnimNodes `OnFloor` do
Skully materializados. Causa, evidência e reteste estão em `09_PRODUCTION_FINDINGS.md`.

## Compatibilidade urgente — hotfix 42.20.4 (`loadstring` / `loadstream`)

```text
Status: PASS_STATIC para as duas APIs removidas; NEEDS_RUNTIME para o hotfix completo
Origem: release note oficial 42.20.4 Stable / 42.19.2 Unstable / 41.78.21 Legacy
Mudança: loadstring e loadstream foram removidos como parte de correções de segurança
```

Varredura exata realizada em 2026-08-26:

```bash
rg -n --hidden -S '\b(loadstring|loadstream)\b' Contents tools vendor docs README.md \
  workshop.txt LASCIVIOUS_SCRIPTS_PRE_RELEASE_REVIEW_FINAL.md review
```

Resultado na árvore realmente distribuída (`Contents/`): **nenhuma chamada executável**. Existe
somente um comentário em `LS_CleanHotBar/.../chbconfig.lua:60` explicando a remoção. Esse arquivo já
usa um parser fechado para o schema de configuração, solução implantada anteriormente justamente
para substituir `loadstring`. A única chamada executável encontrada fica na cópia upstream de
referência em `vendor/clean-hotbar/upstream/.../chbconfig.lua:60`; `vendor/` não é empacotado em
`Contents/` e não roda no mod bundlado. `loadstream` não ocorre em código algum do repositório.

Conclusão limitada: o hotfix não quebra o bundle por uso direto dessas duas APIs. Ainda é obrigatório
adicionar à matriz de runtime um boot SP, host e dedicated em 42.20.4, porque a nota também menciona
correções de segurança não detalhadas que podem afetar comportamento de rede além dessas remoções.

## Etapa 1 — matriz lexical inicial

Legenda `Lua C/S/H/O`: quantidade de arquivos em `client/server/shared/outro`. `Tick`, `ZU`, `PU`,
`CC` e `SC` contam registros lexicais dos eventos; `sendC`/`sendS` contam call sites; `MD` reúne
ocorrências das APIs principais de ModData; `Q/C`, `TA` e `I/O` contam arquivos candidatos, não
estruturas já revisadas.

| Módulo | Pri | Lua C/S/H/O | Tick | ZU | PU | CC | SC | sendC | sendS | MD | Q/C files | TA files | I/O files |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| `FixedLightOnBeltAF` | P1 | 2/0/5/0 | 1 | 0 | 0 | 0 | 0 | 0 | 0 | 2 | 0 | 0 | 2 |
| `LS_AegisPanel` | P0 | 52/24/2/0 | 26 | 0 | 0 | 22 | 33 | 145 | 52 | 60 | 38 | 2 | 39 |
| `LS_AliceWeaponSling` | P0 | 5/1/6/1 | 2 | 0 | 0 | 0 | 0 | 0 | 0 | 6 | 1 | 4 | 0 |
| `LS_AliceWeaponSlingRadialMenu` | P2 | 1/0/0/0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| `LS_Antibodies` | P1 | 13/1/16/0 | 0 | 0 | 0 | 0 | 1 | 2 | 4 | 2 | 0 | 0 | 1 |
| `LS_BetterEngineRepair` | P2 | 0/0/2/0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| `LS_BetterPush` | P0 | 1/1/1/0 | 2 | 0 | 0 | 1 | 1 | 1 | 1 | 0 | 2 | 0 | 0 |
| `LS_BurrisQualityOfLife` | P0 | 17/1/20/0 | 3 | 0 | 0 | 1 | 1 | 3 | 2 | 3 | 15 | 15 | 0 |
| `LS_CleanHotBar` | P1 | 13/0/0/0 | 1 | 0 | 0 | 0 | 0 | 0 | 0 | 7 | 1 | 0 | 2 |
| `LS_ClimbLadders` | P0 | 5/1/0/0 | 1 | 0 | 0 | 1 | 1 | 1 | 1 | 0 | 0 | 2 | 0 |
| `LS_CyesPushDoors` | P1 | 2/2/5/0 | 3 | 0 | 0 | 1 | 1 | 2 | 6 | 0 | 4 | 0 | 3 |
| `LS_DragBodiesFaster` | P2 | 0/0/0/0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| `LS_DurableToolsWeapons` | P2 | 0/0/0/0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| `LS_EquipWhileRunning` | P1 | 1/1/0/0 | 0 | 0 | 1 | 1 | 1 | 1 | 1 | 5 | 0 | 0 | 0 |
| `LS_FasterHoodOpening` | P2 | 1/0/0/0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 1 | 1 | 0 |
| `LS_ImmersiveSuicide` | P2 | 5/1/0/0 | 0 | 0 | 0 | 1 | 1 | 2 | 2 | 0 | 0 | 2 | 0 |
| `LS_ImprovisedSilencers` | P1 | 5/1/6/0 | 2 | 0 | 1 | 0 | 1 | 0 | 1 | 7 | 1 | 1 | 2 |
| `LS_MiniHealthPanel` | P1 | 4/0/0/0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 1 | 1 |
| `LS_OSRSExperienceBar` | P2 | 3/0/0/0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 1 | 0 | 1 |
| `LS_PlyskenSolarRevolution` | P0 | 8/9/17/0 | 3 | 0 | 0 | 2 | 2 | 6 | 10 | 106 | 10 | 13 | 0 |
| `LS_ProximityInventory` | P1 | 4/0/0/0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| `LS_PushVehicle` | P2 | 1/1/0/0 | 1 | 0 | 0 | 1 | 1 | 1 | 1 | 0 | 0 | 0 | 0 |
| `LS_ResponsivePivoting` | P2 | 0/0/1/1 | 3 | 0 | 0 | 0 | 0 | 0 | 0 | 3 | 1 | 0 | 0 |
| `LS_SkullysFasterAttackSpeed` | P2 | 0/0/0/0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| `LS_SkullysFasterSwingSpeed` | P2 | 0/0/1/0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| `LS_TacticalHold` | P2 | 2/0/2/0 | 0 | 0 | 2 | 0 | 0 | 0 | 0 | 14 | 0 | 0 | 0 |
| `LS_TotalWeightRebalance` | P2 | 1/0/3/0 | 0 | 0 | 0 | 1 | 1 | 1 | 1 | 0 | 0 | 0 | 1 |
| `LS_WanderingZombies` | P0 | 14/0/14/0 | 4 | 3 | 0 | 1 | 1 | 1 | 2 | 5 | 0 | 0 | 0 |
| `LasciviousScripts` | P0 | 3/2/2/0 | 2 | 1 | 0 | 1 | 1 | 3 | 2 | 1 | 2 | 2 | 0 |

## Cobertura P0 iniciada

O localizador de registros de eventos frequentes e `OnClientCommand` foi executado para todos os
P0. Os call sites foram encontrados nos oito módulos P0; os maiores grupos iniciais são:

```text
LS_AegisPanel:              26 Tick/EvenPaused, 22 OnClientCommand
LS_WanderingZombies:         4 Tick, 3 OnZombieUpdate, 1 OnClientCommand
LS_BurrisQualityOfLife:      3 Tick, 1 OnClientCommand
LS_BetterPush:               2 Tick, 1 OnClientCommand
LS_AliceWeaponSling:         2 Tick
LasciviousScripts core:      2 Tick, 1 OnZombieUpdate, 1 OnClientCommand
LS_ClimbLadders:             1 Tick, 1 OnClientCommand
LS_PlyskenSolarRevolution:   3 Tick, 2 OnClientCommand
```

Comando reproduzível usado:

```bash
rg -n 'Events\.(OnTick|OnTickEvenPaused|OnZombieUpdate|OnPlayerUpdate)\.Add|Events\.OnClientCommand\.Add' \
  Contents/mods/{LS_AegisPanel,LS_BurrisQualityOfLife,LS_ClimbLadders,LS_AliceWeaponSling,LS_PlyskenSolarRevolution,LS_BetterPush,LS_WanderingZombies,LasciviousScripts} \
  -g '*.lua'
```

## Fronteira do handoff — estado atual

### Concluído

- snapshot e hashes registrados;
- validadores e sintaxe executados;
- matriz lexical inicial dos 29 módulos criada;
- registros frequentes e `OnClientCommand` de P0 localizados mecanicamente;
- PRE-001 a PRE-005 reconciliados e corrigidos;
- todos os handlers P0/P1 e a superfície privilegiada do Aegis fechados para CRITICAL/HIGH;
- memory jobs, full overrides prioritários, case warnings e hotfix 42.20.4 fechados estaticamente;
- oito achados confirmados estão em `PATCHED_STATIC`.

### Ainda não concluído

- execução dentro do engine da matriz focada em `review/06_RUNTIME_TEST_MATRIX.md`;
- stress real do backup Aegis e boot SP/host/dedicated na 42.20.4.

### Próximo passo exato

Executar a matriz focada de runtime. Não reabrir candidatos especulativos ou P2 sem mecanismo
CRITICAL/HIGH diretamente demonstrável.
