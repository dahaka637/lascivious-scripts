# 08 — Release blockers

**Status:** `CLOSED — EM PRODUÇÃO` (revisão encerrada pelo dono do projeto em 2026-08-27)
**Atualização:** 2026-08-27

## CRITICAL

```text
BQoL Pry remote authority       PATCHED_STATIC / NEEDS_RUNTIME
Climb Ladders arbitrary move    PATCHED_STATIC / NEEDS_RUNTIME
PSR remote bank control         PATCHED_STATIC / NEEDS_RUNTIME
```

## HIGH / PERF-HIGH confirmado

```text
Alice Sling poisoned OnTick     PATCHED_STATIC / NEEDS_RUNTIME
Cyes forged door causality      PATCHED_STATIC / NEEDS_RUNTIME
ZombieDecay restart snapshot    PATCHED_STATIC / NEEDS_RUNTIME
Aegis queued backup memory      PATCHED_STATIC / NEEDS_RUNTIME_STRESS
Durable Tools stale 351 items   PATCHED_STATIC / NEEDS_RUNTIME_LOAD
Aegis Construction no rate limit PATCHED_STATIC / NEEDS_RUNTIME
```

Conhecidos sem patch: **0**. O release ainda não recebe `GO`, porque os patches alteram fluxos
dependentes do engine ou dados carregados pelo parser e precisam passar pela matriz focada. `TV-001` permanece
`REJECTED_FALSE_POSITIVE` e não entra nesta lista. `Aegis Construction no rate limit` (`RECONCILED-009`)
foi achado e corrigido depois do fechamento estático original de 2026-08-26 — a auditoria linha-a-linha
do Aegis Panel cobre 7 dos 22 arquivos de comando; os outros 15 ainda dependem só da auditoria de
integração original, não do checklist desta revisão.

Revisão estática crítica: **concluída**. Próximo gate único: `06_RUNTIME_TEST_MATRIX.md`.

## Hotfixes de produção — 2026-08-27

```text
TimeVote refreshElectorate / global next ausente       PATCHED_STATIC / NEEDS_PROD_RETEST
Skully OnFloor x_extends / casing no Linux             PATCHED_STATIC / NEEDS_PROD_RETEST
```

Ambos vieram de log real, foram documentados antes do patch em `09_PRODUCTION_FINDINGS.md` e
corrigidos imediatamente. Não reabrem a revisão estática geral; exigem somente os dois retestes
focados adicionados à matriz.
