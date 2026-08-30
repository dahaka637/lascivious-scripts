# 07 — Registro de patches aplicados

**Status:** `IMPLEMENTED_STATIC`; runtime pendente  
**Atualização:** 2026-08-26

## Autoridade multiplayer

1. `BQoL Pry`: protocolo reduzido a `pryAttempt`; servidor re-resolve alvo, valida raio/Z,
   safehouse, ferramenta e Força, aplica cooldown e decide RNG/efeito.
2. `Climb Ladders`: cliente envia `ladderX/Y/Z + down`; nova geometria shared servidor resolve a
   escada e o único landing. O cliente só se move após `climbed` do servidor.
3. `PSR Computer`: leitura e toggles carregam coordenadas do terminal. O servidor exige o objeto
   real, back-reference para a bank, registro `PSR_computer`, mesmo Z, raio de 2,5 tiles e throttle.
4. `Cyes Push Doors`: duas fases `doorInteractionBegin -> doorOpened`; o servidor observa o estado
   anterior, conserva intent por até 3 s e consome uma vez. Scanner sem prova não causa efeitos
   autoritativos em MP.

## Crash, persistência e memória

5. `Alice Weapon Sling`: campos de escopo corrigidos; dequeue-before-work + `pcall` nos dois loops.
6. `ZombieDecay`: snapshot completo dos oito valores em Global ModData versionado por save.
7. `Aegis Backup`: descritor/cursor, buffer de 1.000 linhas, path por execução, commit de manifest
   ao final e restore por reader/bloco incremental.

## Overrides vanilla

8. `Durable Tools and Weapons`: os 351 blocos foram ressincronizados sobre os scripts vanilla da
   42.20.4; somente `ConditionMax`/`ConditionLowerChanceOneIn` continuam diferentes, com os valores
   exatos da variante Hardened preservados. O snapshot prístino permanece em `vendor/`; o gate
   reproduzível é `python3 tools/audit_durable_overrides.py`.
9. `ZombieDecay AnimSets`: removidos os dois `defaultlunge.xml` redundantes com casing diferente do
   vanilla `defaultLunge.xml`; eram byte-equivalentes e os 10 sprint nodes já materializam os campos
   herdados necessários. Permanecem 13 overrides funcionais, todos comparados à 42.20.4.

## Verificação executada

```text
315 arquivos Lua (incluindo o novo helper): luac5.1 -p  -> PASS
tools/validate_structure.py                     -> PASS, 3 case warnings conhecidos
tools/audit_collisions.py                       -> PASS
tools/audit_durable_overrides.py                -> PASS, 351/351
tools/generate_server_mods.py                   -> ordem canônica preservada
resíduos .bak/.tmp/.old/~                       -> nenhum
loadstring/loadstream executável em Contents   -> nenhum
Durable: diferenças fora de durabilidade       -> 0/351
Durable: valores Hardened preservados          -> 351/351
```

Nenhum teste dentro do engine foi alegado como concluído. A aceitação final depende de `06`.
