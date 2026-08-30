# API interna do Lascivious Factions System

Versão do esquema: `2`

Esta API existe apenas no lado do servidor. Ela entrega cópias independentes dos
dados: alterar uma resposta não altera facções, território nem pontuação. SteamIDs
são sempre textos para preservar todos os dígitos de um SteamID64.

## Como importar

```lua
if isClient() then return end

local API = require "LFS_API"
-- Alternativas depois que o mod carregar:
-- local API = LasciviousFactionsSystem.API
-- local API = LasciviousFactionsSystemAPI
```

O mod que fizer a bridge deve declarar `LasciviousSystems` como dependência e
carregar o código de integração em `media/lua/server`.

O ID do pacote e a versão retornados no snapshot seguem o `mod.info`
(`LasciviousSystems`, atualmente `1.0.0`). O namespace Lua e o nome do ModData
continuam `LasciviousFactionsSystem` por compatibilidade.

## Operações públicas

```lua
API.getVersion()                    -- { schemaVersion, modVersion }
API.getRevision()                   -- contador de mudanças nesta sessão
API.getFactionNames()               -- nomes em ordem alfabética
API.getFactions()                   -- snapshots de todas as facções
API.getPlayers()                    -- todos os jogadores conhecidos
API.getTerritories()                -- visão compacta para mapas/territórios
API.getSnapshot()                   -- snapshot completo em tabela Lua
API.getSnapshotJSON(true)           -- snapshot completo em JSON formatado
API.toJSON(value, true)             -- qualquer resposta da API em JSON
API.getFaction("Nome")              -- uma facção ou nil
API.getPlayer("username")           -- um jogador conhecido ou nil
API.findFactionByPlayer("username") -- nome, snapshot da facção
API.getFactionAt(10620, 9810)       -- nome, facção, retângulo exato
API.refreshIdentities()             -- atualiza jogadores on-line e SteamIDs
```

`getSnapshot()` contém:

- `summary`, regras de pontuação, regras de território e opções de sandbox;
- `factions`, `players`, `wars`, `ceasefires`, `pacts` e temporada;
- zonas administrativas em que reivindicações são proibidas;
- `recruitment` permanece como lista vazia por compatibilidade (o quadro público foi removido);
- para cada facção: identidade, cor RGB/hexadecimal, configurações, relações,
  convites, cargos, membros, SteamIDs, pontuação e estatísticas de ataques;
- para o território: todos os retângulos exatos (`x1`, `y1`, `x2`, `y2`), áreas
  conectadas, limites, quantidade de quadrados, nível de acesso e permissões de
  visitantes, limite dinâmico de áreas e pontos restantes para liberar outra área;
- para convites: `membershipRules`, pendências resumidas e detalhadas
  (`pendingInvites`/`pendingInvitationDetails`) e bloqueios por recusa
  (`inviteDeclineCooldowns`).

As listas vazias são codificadas como `[]` no JSON.
`territory.areaCount` conta somente componentes geométricos desconectados, exatamente
como a cota do jogo. `territory.policyAreaCount` conta as seções gerenciáveis da lista
`territory.areas`; ele pode ser maior quando uma área contínua contém trechos com
acessos diferentes (`private`, `allies` ou `public`).
Os nomes dos campos e valores enumerados (`private`, `allies`, `public`, cargos
internos etc.) permanecem em inglês de propósito, para formarem um contrato técnico
estável independentemente do texto exibido na interface.

## Pontuação nativa do personagem

Para jogadores conectados, kills e horas são lidas diretamente dos contadores nativos
`IsoPlayer:getZombieKills()` e `IsoPlayer:getHoursSurvived()`. No modo padrão, a API
e o placar usam esses snapshots absolutos como a pontuação do personagem atual. Com
`PreserveMemberPowerOnDeath=true`, os mesmos snapshots viram a base da vida atual
para somar novos ganhos sobre o total preservado. Com isso:

- personagens que já existiam antes da instalação do LFS importam todo o total atual;
- alterações aparecem dinamicamente enquanto o personagem está on-line;
- ao desconectar, a última leitura fica persistida para a facção não perder o membro;
- por padrão, ao morrer e criar outro personagem, os contadores nativos zerados
  substituem o cache;
- com `PreserveMemberPowerOnDeath=true`, a morte preserva o total já contribuído,
  reseta apenas a base dos contadores nativos e a nova vida continua somando sobre
  esse total.

O objeto `score` de um jogador/membro contém `zombieKills`, `hoursSurvived`,
`zombieKillPoints`, `survivalPoints`, `total`, `observedAt` e `source`. Os campos
`lastReportedZombieKills` e `lastReportedHoursSurvived` foram preservados por
compatibilidade com o esquema 1. No modo padrão eles espelham o último snapshot
absoluto; com preservação ativa, espelham a base nativa da vida atual enquanto
`zombieKills`/`hoursSurvived` expõem o total preservado.

## Exemplo para uma bridge

```lua
local API = require "LFS_API"

local function exportar()
    local json, erro = API.getSnapshotJSON(false)
    if not json then
        print("[MinhaBridge] erro ao serializar LFS: " .. tostring(erro))
        return
    end
    -- Envie `json` ao processo/bot pelo mecanismo já usado pela sua bridge.
end

-- A notificação é leve e não constrói o snapshot automaticamente.
local inscricao = API.subscribe(function(evento)
    -- registry_changed, registry_delta, identity_changed ou presence_changed
    exportar()
end)

-- Se a bridge for descarregada:
-- API.unsubscribe(inscricao)
```

Mutações completas são coalescidas por janela de transmissão; atualizações frequentes
de pontuação/tributo chegam como `registry_delta`. Para uma bridge HTTP/arquivo,
recomenda-se ainda aplicar debounce de 1 a 5 segundos ou consultar
`API.getRevision()` em um temporizador. Cada facção possui `id`, que atualmente é o
próprio nome e portanto muda quando a facção é renomeada. A identidade persistida de
um jogador passa a ter SteamID depois que ele conectar ao servidor ao menos uma vez; em jogo solo ou
sem Steam, `steamId` fica ausente e `accountId` usa `username:<nome>`.

## Estabilidade

O esquema 2 substituiu `claimRules.maximumAreas` por `baseAreas` e
`pointsPerAdditionalArea`, pois o limite deixou de ser fixo. O limite atual de cada
facção está em `faction.territory.maximumAreas`. O fluxo de recrutamento público foi
retirado; `recruitment` continua presente como `[]`, enquanto convites pendentes
continuam em `pendingInvites`.

Integrações devem verificar `schemaVersion`. Campos podem ser acrescentados sem
alterar essa versão; remoções, renomes ou mudanças de significado exigem uma nova
versão de esquema. Não leia nem modifique diretamente
`ModData.getOrCreate("LasciviousFactionsSystem")`.
