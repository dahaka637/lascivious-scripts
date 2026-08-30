# Lascivious Systems

Mod all-in-one para Project Zomboid Build 42 que reúne o ecossistema de mods
próprios do servidor numa única instalação. Antes eram 4 mods separados
(`LasciviousShop`, `LasciviousFactionsSystem`, `HardcoreKits`, `loading_logo`);
agora é um só, para simplificar a lista de mods do servidor e do Workshop.

Internamente os subsistemas mantêm namespaces, chaves de `ModData` e opções de
Sandbox próprios. A autoridade econômica, os resgates de kits, as facções e as
zonas continuam com limites claros, mas agora existem integrações explícitas e
defensivas entre Loja e Facções (tributos, melhorias e regras de PvP). O pacote
também inclui correções de robustez, idempotência, validação de payloads,
recuperação de transações e redução de trabalho por tick.

## Subsistemas

- **Lascivious Shop** — loja de créditos multiplayer. Ver
  [LasciviousShop_README.md](LasciviousShop_README.md).
  Preços, saldo, transferências e entregas são autoritativos no servidor; pedidos
  possuem proteção contra repetição e entrega parcial é reconciliada sem duplicar
  itens.
  Namespace: `LasciviousShop*` / `LasciviousShop_ServerData` / `SandboxVars.LasciviousShop.*`.
- **Lascivious Factions System** — facções com território, autoridade no
  servidor. Construído sobre o motor de zonas do **PhunZones 2**, que era uma
  dependência externa (`require=phunzones2`) e agora está embutido neste mesmo
  mod (pasta `media/lua/{client,server,shared}/PhunZones/`) — não é mais
  necessário instalar/assinar o PhunZones 2 separadamente. Ver
  [LasciviousFactionsSystem_README.md](LasciviousFactionsSystem_README.md)
  e, principalmente, [LasciviousFactionsSystem_API.md](LasciviousFactionsSystem_API.md) —
  API interna já pronta para bridges/bots e para futuras integrações entre os
  subsistemas deste mod.
  Namespace: `LasciviousFactionsSystem` / `ModData "LasciviousFactionsSystem"` / `SandboxVars.LasciviousFactionsSystem.*`.
  O PhunZones 2 embutido usa seu próprio namespace `PhunZones` / `ModData "PhunZones"` /
  `SandboxVars.PhunZones.*`, também sem qualquer conflito com os demais.
- **Hardcore Kits** — sistema de kits via `/kit`. Kit inicial aleatório,
  recompensa de sobrevivência periódica, bônus de XP configurável.
  Sorteio, entitlement e entrega usam uma máquina de estados persistida; uma
  queda durante a mutação física falha de modo conservador para evitar dupes.
  Namespace: `HardcoreKits*` / `HardcoreKits_Accounts` / `SandboxVars.HardcoreKits.*`.
- **Tela de carregamento** — substitui os sprites de progresso do loading
  screen por uma logo personalizada (`media/ui/Progress/`). Sem Lua, apenas
  assets sobrepondo o caminho vanilla.
- **HWNetBridge** — bridge server-only entre o servidor e o bot Discord (Node.js),
  via arquivos `hwbridge_*.json` em `~/Zomboid/Lua/` (sem rede própria, sem exigir
  nada do cliente). Publica heartbeat, snapshot de jogadores online, eventos de
  morte e snapshot de facções (via `LFS_API`) a cada `Events.EveryOneMinute`;
  processa comandos simples do bot pelo inbox (`ping`, `grant_discord_reward` —
  este último credita bônus de verificação Discord via `LasciviousShop.queueCredits`).
  Só roda `server/`, então nunca entra na comparação do `DoLuaChecksum` do
  cliente. Migrado de arquivo solto fora do sistema de mods (histórico em
  `/home/dahaka/Zomboid/Workshop/HWNetBridge/README.md`) para dentro do mod em
  2026-08-27, especificamente para poder ligar `DoLuaChecksum=true` no servidor.

## Estrutura

```
42/
├── mod.info
├── icon.png / poster.png
└── media/
    ├── sandbox-options.txt        (opções dos subsistemas, sem conflito de prefixo)
    ├── lua/
    │   ├── client/  server/  shared/   (codebases lado a lado, com namespaces próprios)
    │   │   ├── PhunZones/               (motor de zonas embutido, client+server+shared)
    │   │   └── server/HWNetBridge/      (bridge Discord, server-only)
    │   │       └── HWNetBridge.lua
    │   └── shared/Translate/EN|PTBR/{UI,Sandbox}.json + EN/{IG_UI,Tooltip}.json  (união das chaves; nenhuma colidiu)
    ├── ui/
    │   ├── LasciviousShop/
    │   ├── HardcoreKits/
    │   └── Progress/               (sprites do loading screen)
    └── textures/
        └── LasciviousFactionsSystem/
```

## Operação

- Ative somente `LasciviousSystems` na lista `Mods` do servidor. Como o motor de
  zonas já está embutido, não carregue também o item/mod independente do
  PhunZones 2; duas cópias registrariam os mesmos eventos e dados globais.
- Faça backup do save antes de atualizar um servidor existente. As migrações são
  conservadoras, mas saldos, facções e transações são dados persistentes.
- Ferramentas administrativas de diagnóstico ficam desligadas por padrão nas
  opções de Sandbox. Ative-as apenas durante uma investigação.
- O LFS grava avisos e checkpoints no log próprio; a Loja e o Hardcore Kits
  também registram falhas e resultados ambíguos para reconciliação manual.

## Créditos

Autoria original: Dahaka (Lascivious Shop, Lascivious Factions System,
Hardcore Kits). Os sprites da tela de carregamento (`loading_logo`) foram
originalmente publicados por **1Feliped**. O motor de zonas **PhunZones 2**
embutido no subsistema de facções foi originalmente publicado por
**UburGeek** — a cópia embutida foi adaptada para compatibilidade, segurança e
desempenho dentro deste pacote. Não foi encontrado um arquivo de licença local
no item original do Workshop; confirme os termos aplicáveis e preserve a
atribuição antes de redistribuir publicamente.
