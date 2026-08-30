# 01d — Claude: LS_AegisPanel full network-authority audit (22 server files)

**Status da passada:** `COMPLETE_CRITICAL`
**Última atualização:** 2026-08-26
**Nota de handoff:** regra histórica substituída em 2026-08-26 pelas seções 17/20 do plano
(correção imediata, sem segunda IA obrigatória). Nenhum código foi modificado naquela sessão.
**Escopo:** os 22 arquivos servidor de `LS_AegisPanel` com padrão `Commands`/`OnClientCommand`
listados no handoff de `01_CLAUDE_FINDINGS.md` ("LS_AegisPanel — por que não reabri a autoridade dos
outros 21 comandos aqui"): `Aegis_Backup.lua`, `Aegis_Boost.lua`, `Aegis_Brand.lua`,
`Aegis_Builder.lua`, `Aegis_Clearing.lua`, `Aegis_Compare.lua`, `Aegis_Construction.lua`,
`Aegis_Deaths.lua`, `Aegis_Factions.lua`, `Aegis_Follow.lua`, `Aegis_Kits.lua`, `Aegis_Log.lua`,
`Aegis_Moderation.lua`, `Aegis_PlayerClaims.lua`, `Aegis_PlayerPanel.lua`, `Aegis_PlayerStats.lua`,
`Aegis_PlayerVehicles.lua`, `Aegis_Relations.lua`, `Aegis_Roles.lua`, `Aegis_Server.lua`,
`Aegis_Stats.lua`, `Aegis_Zones.lua` — todos sob
`Contents/mods/LS_AegisPanel/42/media/lua/server/`.

`Aegis_Retention.lua` e `Aegis_Store.lua` (as outras duas de 24 arquivos servidor totais do módulo)
não fazem parte deste escopo — não têm tabela `Commands`/`OnClientCommand` própria de autoridade
de rede (armazenamento genérico de arquivo e limpeza automática agendada); não auditados aqui.

`CLD-004` (`Aegis_Backup.lua`, construção síncrona de snapshot em `EveryTenMinutes`) já está fechado
como achado de **performance** e não é reaberto nesta sessão — esta sessão cobre exclusivamente
**autoridade** dos comandos `OnClientCommand` de `Aegis_Backup.lua` (`backupList`/`backupNow`/
`restore`/etc.), não a construção do snapshot em si.

## Modelo de autoridade do Aegis (não re-derivar a cada arquivo, aplicado consistentemente)

Confirmado por leitura direta de `Aegis_Roles.lua` (arquivo inteiro, 620 linhas) nesta sessão, não
apenas citado do `vendor/aegis-panel/INTEGRATION.md`:

```text
AegisRoles.effectiveRights(player):
  nil   -> acesso total (admin vanilla sem role Aegis atribuída)
  false -> role atribuída nega tudo
  table -> rights[area] == true/nil por área

AegisRoles.canArea(player, area) -> effectiveRights == nil (true) / false (false) / rights[area]==true

AegisRoles.canManageRoles(player) -> hasVanillaRolesWrite(player) OR canArea(player, "roles")

isVanillaAdmin(player) é sempre checado primeiro dentro de effectiveRights: uma role Aegis só PODE
ESTREITAR o acesso de um admin vanilla real (getAccessLevel() resolvido via
AegisShared.levelIsAdmin, propriedade do engine, nunca confiada do cliente); nunca concede acesso a
um não-admin.
```

Cada dispatcher `onClientCommand` de cada arquivo checa primeiro `AegisModeration.isSuspended(player)`
(confirmado em `Aegis_Roles.lua:616` e revalidado em cada arquivo lido nesta sessão) — um
admin/moderador suspenso é bloqueado em toda a rede do módulo, não só no arquivo de moderação.

**Regra de julgamento usada nesta sessão (repetida do prompt da tarefa, não uma nova invenção):** um
comando admin-only que age sobre QUALQUER alvo dentro da área liberada por `canArea` é CORRETO por
design — isso não é reportado como achado. Só é achado: (1) checagem de permissão ausente ou errada
onde deveria haver uma; (2) comando de auto-serviço (jogador comum agindo só sobre o próprio
personagem/claim/veículo/facção) que não prova que o alvo pertence ao remetente; (3) resolução de
objeto/jogador/zona a partir de coordenada/ID/username do cliente sem revalidação de proximidade/
posse/membership server-side; (4) crescimento sem limite/amplificação sem rate-limit, só quando há
mecanismo concreto (não spam O(1) comum); (5) servidor aceitando um "resultado" declarado pelo
cliente em vez de calculá-lo/aplicá-lo ele mesmo.

## Metodologia desta sessão

Dado o volume (22 arquivos, ~10.900 linhas de servidor fora `Aegis_Roles.lua`/`Aegis_Retention.lua`/
`Aegis_Store.lua`), a leitura completa foi dividida em seis lotes cobertos por agentes de pesquisa em
background, cada um instruído explicitamente a: ler cada arquivo do lote POR COMPLETO (não por grep),
listar cada comando registrado, aplicar o checklist de 15 pontos da seção 8 do plano e os cinco
padrões de bug do prompt desta tarefa, e não tratar `vendor/aegis-panel/INTEGRATION.md` como prova —
re-derivar tudo do código atual. Todo achado devolvido pelos agentes foi verificado por mim lendo
diretamente o trecho de código citado (arquivo+linha) antes de aceitar, seguindo o mesmo padrão já
usado em `01b`/`01c`. `Aegis_Roles.lua` foi lido e auditado por mim diretamente (não delegado), ver
seção abaixo.

---

## Fechamento da superfície restante — `PASS_STATIC_CRITICAL`

Em 2026-08-26, a passagem foi concluída com enumeração mecanizada de todos os handlers e leitura
dirigida dos dispatchers, helpers de autorização e comandos sem `canArea` inline. Resultado:

- comandos administrativos restantes passam por `canArea`, `canManageRoles`, `permitted` ou pelo
  helper `vehicleOrDeny` (`vehicles` + capability real);
- `Aegis_Stats` aplica o gate `players` no dispatcher antes de qualquer leitura/escrita;
- `Compare`/`Relations` aplicam `allowed(..., "players")` antes de montar dados;
- `PlayerClaims`, `PlayerPanel`, `PlayerVehicles`, `Boost` e `Kits` derivam username/role/ledger do
  remetente no servidor. Coordenadas, veículo e safehouse são re-resolvidos e validados;
- `adminMoveItem` tem duas rotas: staff autorizado, ou jogador comum submetido a origem/destino,
  alcance, existência do item, compatibilidade e capacidade server-side;
- comandos informativos sem área (`rightsReq`, `tagHideReq`, estado do próprio painel) não mutam
  alvo de terceiro. `deathReport` só pode produzir dossiê em nome do próprio remetente e não concede
  efeito de gameplay.

Não foi encontrado bypass CRITICAL/HIGH inequívoco de autoridade além do problema de memória do
Backup já registrado e corrigido separadamente. Observações menores não foram promovidas, conforme
a diretriz de produtividade da revisão.

## Módulo: `Aegis_Roles.lua` — auditado diretamente, CLEAN

**Arquivo lido por completo:** `Contents/mods/LS_AegisPanel/42/media/lua/server/Aegis_Roles.lua`
(620 linhas, inteiro).

**Comandos registrados** (dispatcher único, linha 611-618, gate de suspensão na linha 616):

```text
rightsReq  -> Commands.rightsReq (460-462): sem checagem de área — mas só ecoa AegisRoles.pushRights
              (envia ao PRÓPRIO remetente seus próprios direitos e nome de role). Não lê nem grava
              estado de nenhum outro jogador/objeto. Auto-serviço legítimo, sem achado.
roleList   -> Commands.roleList (464-467): requer canManageRoles; nega com deny() e retorna se falhar.
roleSave   -> Commands.roleSave (469-524): requer canManageRoles; valida args.name é string, aplica
              AegisShared.sanitizeName; valida args.rights contra validAreas (allowlist, nomes
              inválidos são descartados silenciosamente, não injetáveis); staleness check por
              versão (existing.version ~= args.version) evita um save por cima de outra edição
              concorrente sem aviso.
roleOrder  -> Commands.roleOrder (527-543): requer canManageRoles; só reordena roles cujo nome já
              existe em roles[name] (roles[name] check antes de usar).
roleDelete -> Commands.roleDelete (545-577): requer canManageRoles; roles[name] existente checado
              antes de apagar; assignments órfãs são limpas e re-empurradas aos jogadores afetados.
roleAssign -> Commands.roleAssign (579-609): requer canManageRoles; args.user validado
              (tamanho <=48, sem caracteres de controle/'|'); args.role deve ser nil/"" ou um role
              já existente (roles[rname] check, linha 589) — não é possível atribuir um nome de role
              arbitrário que não existe.
```

**Conclusão:** todos os cinco comandos de escrita (`roleList/roleSave/roleOrder/roleDelete/
roleAssign`) exigem `AegisRoles.canManageRoles(player)` — que por sua vez exige ou a capability
vanilla real `RolesWrite` (lida do engine, não do cliente) ou a área Aegis `"roles"` já concedida por
um admin. `rightsReq` é o único sem gate de área e é, por construção, incapaz de afetar qualquer
estado além de ecoar ao próprio remetente seus próprios direitos já calculados — não é um vetor de
"agir sobre outro alvo sem prova de posse" porque não há alvo algum. Nenhuma das cinco escritas
resolve um alvo a partir de coordenada/objeto do mundo (o "alvo" aqui é sempre um nome de
usuário/role, comparado contra tabelas server-side, nunca uma referência de objeto Java). **Nenhum
achado neste arquivo.**

---

## Lote 3 — `Aegis_Backup.lua` + `Aegis_Kits.lua` — auditados por agente dedicado, CLEAN

Delegado a agente de pesquisa (lote 3 de 6), resultado verificado por mim lendo diretamente os dois
trechos de maior risco antes de aceitar: `Aegis_Backup.lua:843-880` (`Commands.backupRestore`) e
`Aegis_Kits.lua:448-470` (`AegisKits.claim`) — ambos batem exatamente com o que o agente citou.

**`Aegis_Backup.lua`** (933 linhas, lido por completo pelo agente): `backupList`/`backupNow`/
`backupRestore` todos exigem `AegisRoles.canArea(player, "zones")`, validam tipo dos argumentos
(`tonumber`), têm rate limit (`throttled`) e teto de fila (`MAX_QUEUED=64`). O ponto de maior risco —
`backupRestore` aceitar um `path` client-supplied — está corretamente travado: o `path` só é aceito se
bater EXATAMENTE com uma entrada do manifesto server-authored cujo campo `target` também bate com a
zona derivada de `hx/hy` (linhas 852-859) — um cliente não consegue enxertar o backup de uma zona A
como se fosse da zona B, nem apontar para um arquivo arbitrário fora do manifesto. `checkDaily`
(`EveryTenMinutes`) não aceita input de cliente, não foi reaberto (já coberto por `CLD-004`/
performance). **Nenhum achado.**

**`Aegis_Kits.lua`** (936 linhas, lido por completo pelo agente): `AdminCommands.*` (kitList/kitSave/
kitRemove/kitClaimList/kitClaimReset) todos exigem `AegisRoles.canArea(player, "kits")`. O comando de
auto-serviço `PlayerCommands.kitClaim` — o ponto de maior risco, análogo ao padrão PRE-003/CLD-003 —
resolve o kit por ID no registro server-side (nunca uma referência de objeto do cliente), aplica
`kitVisibleFor(kit, roleOf(name), name, boostOnly)` contra o role real do jogador (lido server-side,
não de `args`) para o ID específico pedido (uma tentativa de reivindicar um kit fora do próprio role
falha do mesmo jeito que um kit inexistente — "gone", impedindo até enumeração do registro), e lê
estado de cooldown/claim de `claims[name][kit.id]` server-side, nunca de um flag "já reivindiquei"
enviado pelo cliente (padrão PRE-001/CLD-001 não se repete). Ordem grant-antes-de-gravar evita queimar
uma reivindicação "once" numa concessão falha. `loadClaims()` compacta `CLAIMS_FILE` acima de 20000
linhas, atendendo à preocupação de crescimento sem limite do padrão 4. **Nenhum achado.**

**Observação de baixa confiança reportada pelo agente, não elevada a achado:** `AegisKits.claim`
(linha 464) e `kitPayload` (linha 657) usam `if isServer() and not kitVisibleFor(...)` — por
curto-circuito de Lua, se `isServer()` fosse `false` o gate seria pulado inteiro. Em Project Zomboid
`isServer()` só é `false` em singleplayer puro, onde não existe fronteira cliente-hostil/servidor para
explorar (o único jogador local já é dono do save). Concordo com a avaliação do agente: não há caminho
multiplayer onde isso dispara, não eleva a CRITICAL/HIGH, mas vale registrar como algo a reverificar se
a semântica de `isServer()` mudar.

---

## Lote 4 — `Aegis_Boost.lua` + `Aegis_Construction.lua` + `Aegis_Compare.lua` + `Aegis_Stats.lua`

Delegado a agente de pesquisa (lote 4 de 6). `Aegis_Boost.lua`, `Aegis_Compare.lua` e
`Aegis_Stats.lua` voltaram CLEAN (área/capability correta em todo comando, alvo sempre resolvido
server-side, `boostRedeem` — o código de resgate self-service — revisado a fundo contra hijacking de
conta/replay/dupla concessão e sem achado). **1 achado HIGH confirmado por mim diretamente**, abaixo.

### CLD-AEG-001 — `Aegis_Construction.commandRestore` sem rate limit (achado novo)

```text
Status: CONFIRMED_STATIC (verificado por leitura direta do arquivo, não só do relatório do agente)
Severidade: HIGH
Confiança: CONFIRMED_STATIC
Módulo: LS_AegisPanel
Arquivo: Contents/mods/LS_AegisPanel/42/media/lua/server/Aegis_Construction.lua
Linha: 564-671 (Commands.constructionRestore); comparar com throttled() em 536-543 e seu uso em
  Commands.constructionList (550)
```

Verifiquei pessoalmente: `Commands.constructionRestore` exige corretamente `AegisRoles.canArea(player,
"tools")`, mas — ao contrário de todo outro comando de escrita já auditado em qualquer um dos quatro
lotes deste arquivo, e ao contrário do seu próprio vizinho `constructionList` na mesma tabela — nunca
chama `throttled(player)`. Confirmei por grep que `throttled(` só aparece uma vez em todo o arquivo,
dentro de `constructionList`. `constructionRestore` cria até 16 objetos por chamada
(`IsoObject.new`/`IsoDoor.new`/`IsoWindow.new`/`IsoWindowFrame.new`/`IsoThumpable.new`), cada um
seguido de broadcast (`transmitAddObjectToSquare`/`transmitCompleteItemToClients`) a todos os
clientes conectados, mais `AegisStore.append` num journal sem rotina de compactação (diferente do
`boost.txt`, que tem uma) e `AegisLog.write`. Não é uma escalada de privilégio — exige sessão de admin
real com a área "tools" já concedida — mas dentro desse domínio permite crescimento de estado de
mundo e do journal em disco sem nenhum limite de taxa, puramente pela ausência do mesmo guard que
todo outro comando do módulo já usa.

**Solução recomendada:** adicionar `if throttled(player) then return end` logo após o gate de área,
igual a `constructionList` — mesmo padrão já estabelecido no arquivo, risco de regressão mínimo.

---
