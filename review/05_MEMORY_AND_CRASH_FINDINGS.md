# 05 — Memória e crash

**Status:** `PATCHED_STATIC`; runtime pendente  
**Atualização:** 2026-08-26

## Blockers corrigidos

- `Alice Weapon Sling`: `item`/`slotType` globais foram trocados por campos de `data`. Nas duas
  repair queues, a entrada sai da fila antes da operação protegida por `pcall`; erro recebe log
  limitado a um por cinco segundos. A fila não pode mais ficar envenenada em `OnTick`.
- `Aegis Backup/Restore`: a fila não retém arrays de colunas nem arquivos inteiros de restore.
  Snapshot usa cursor e buffer de 1.000 linhas; restore mantém um bloco de square por vez. O limite
  de 400.000 linhas continua sendo aplicado durante o stream.
- `ZombieDecay`: o risco era perda persistente de estado, não heap. O snapshot original agora é
  versionado em `ModData.getOrCreate("LasciviousScripts.ZombieDecay")` antes da primeira mutação.

## Resultado estático

Não resta mecanismo conhecido de crescimento multiplicado pela fila nos itens confirmados. A
dimensão real de heap/GC do Aegis e o comportamento de exceção artificial da Alice ainda exigem os
testes de `06_RUNTIME_TEST_MATRIX.md`.
