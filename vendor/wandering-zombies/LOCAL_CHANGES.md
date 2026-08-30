# Local Changes — Wandering Zombies

## LS-008
Tipo: tradução PT-BR de sandbox
Arquivo novo: `42/media/lua/shared/Translate/PTBR/Sandbox_PTBR.txt`
Mudança: promovidas as 160 chaves do JSON PT-BR para o formato nativo com escapes decimais
ASCII-safe. Validação: paridade 160/160 com EN, sintaxe Lua 5.1 e reconstrução UTF-8 exata.

## LS-001
Tipo: bundling / identidade e seleção de variante
Arquivos: layout do submod e `42/mod.info`
Motivo: o Workshop inclui Stable e WIP mutuamente exclusivas, além de múltiplas camadas B42.
Mudança: selecionada a WIP `42.18`, consolidada em `LS_WanderingZombies/42`; Mod ID externo
adaptado, identidade persistente/rede interna preservada e versão mínima fixada em 42.20.0.

## LS-002
Tipo: correção fatal de inicialização e reload
Arquivos: `RYUKU_WanderingZombies_SandboxVars.lua`, `RYUKU_WanderingZombies.lua` e
`RYUKU_WanderingZombies_ZombieBase.lua`
Motivo: `[WZ_PERFORMANCE]` usava uma global inexistente como índice de tabela e abortava o load. O
guard `IsoZombie.modData.wz` também podia persistir sem o wrapper Lua após reload.
Mudança: removido o grupo inexistente; wrappers agora são deduplicados por tabela fraca local e
liberados quando o zumbi deixa de ser válido. O namespace persistente `WanderingZombies` permanece.

## LS-003
Tipo: correção de hordas e matemática defensiva
Arquivos: `RYUKU_WanderingZombies_Horde.lua`, `RYUKU_WanderingZombies_Vector.lua`
Motivo: a fusão removia seguidores da lista circular durante o próprio iterator e pulava membros;
o raio calculava `size / pi` apenas quando o tamanho era implícito; normalização de vetor zero
produzia valores inválidos.
Mudança: snapshot dos seguidores antes da transferência, precedência corrigida e guards para
magnitude zero. Teste isolado cobre fusão completa e fórmula do raio.

## LS-004
Tipo: robustez de Director/reflexão e limpeza de diagnóstico
Arquivos: `RYUKU_WanderingZombies_{Zombie,Director,SandboxVars}.lua`,
`wz-director/RYUKU_WanderingZombies_PullEvent.lua`, `RYUKU_WanderingZombies.lua`
Motivo: o bloco de sons chamava uma função inexistente e usava a assinatura antiga da função
restante; Pull registrava callback `OnZombieDead` inexistente; reset não propagava retorno; logs de
debug eram emitidos continuamente.
Mudança: reflexão migrada para `WZUtility:getClassFieldVal`, registro inválido removido, reset
corrigido e logs periódicos eliminados.

## LS-005
Tipo: perfil de gameplay solicitado
Arquivo: `42/media/sandbox-options.txt`
Motivo: priorizar acaso e movimentação orgânica, sem compensar regiões limpas nem selecionar o
jogador como destino artificial.
Mudança: Pull/Migrate desligados; Homing/Flee fixados em 0; vagar aleatório 20–100%, distância 100,
intervalo aleatório até 30 s e destruição aleatória; rotas fora da célula liberadas; exploração
ampliada; hordas/fusão/tipos de velocidade habilitados com tamanho e quantidade ilimitados.

## LS-006
Tipo: estabilidade da UI
Arquivos: `42/media/lua/client/WZUI/*.lua` e remoção de
`42/media/lua/client/RYUKU_WanderingZombies_UI.lua`
Motivo: `pairs()` tornava a ordem dos grupos instável, a tela podia ser instalada novamente sobre
seus próprios controles ao reabrir, e o arquivo legado possuía 483 linhas totalmente comentadas.
Mudança: grupos estruturados e percorridos por `ipairs`, guarda idempotente adicionada e arquivo
inerte removido. Hooks vanilla continuam usando captura anterior e call-through.

## LS-007
Tipo: tradução e carregamento de texto
Arquivos: `42/media/lua/shared/Translate/{EN,PTBR}/`
Motivo: a camada 42.18 fornecia somente JSON, insuficiente para os `getText()` da UI.
Mudança: criado `Sandbox_EN.txt` nativo com as 160 chaves e catálogo PT-BR JSON completo 160/160;
três cabeçalhos de horda no `sandbox-options.txt` foram apontados para as chaves existentes
`WZGroupTitle_Horde_{Core,Merging,Speed}`.
