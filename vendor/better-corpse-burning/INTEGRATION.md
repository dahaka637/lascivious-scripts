# Integration Notes — Better Corpse Burning

- `module_key`: `better-corpse-burning`
- `bundled_mod_id`: `LS_BetterCorpseBurning`
- Workshop item `3790089095`, upstream `modversion=1.11`, uma única variante
  `id=BetterCorpseBurning` com `versionMin=42.0`.

## Função

Adiciona ao menu de mundo uma ação para queimar a pilha de cadáveres usando qualquer item com a tag
vanilla `START_FIRE`, sem exigir gasolina por padrão. Dez opções de Sandbox controlam duração,
substituição da opção vanilla, raio/velocidade da propagação, consumo de fonte de fogo/gasolina,
queima interna, autoextinção e remoção de cinzas.

O cliente implementa `BCB_ISBCBBurnAction` e adiciona um listener a
`Events.OnFillWorldObjectContextMenu`. O servidor inicia o fogo principal, controla a fila de
propagação, autoextinção e limpeza opcional de pisos queimados. Não substitui arquivo ou método
vanilla; os listeners de evento são aditivos.

## Inventário e gate

- Build 42 compatível (`versionMin=42.0`), integrado para 42.20.x.
- Sem dependências, incompatibilidades ou múltiplas variantes.
- Sem item, receita, trait, perk, veículo, Java/JAR, mapa, tiledef ou pack.
- Sem `modData`, `GlobalModData` ou formato persistente próprio; não é save-sensitive.
- O código não consulta o próprio Mod ID, portanto a renomeação externa é Categoria A.
- Identidades internas preservadas: sandbox `BetterCorpseBurning.*`, rede `BCB` e TimedAction
  `BCB_ISBCBBurnAction`.
- 29 catálogos JSON de idioma preservados. EN/PTBR receberam tabelas nativas adicionais.
- `icon.png` e `poster.png` foram preservados e continuam referenciados pelo `mod.info`.

## Autoridade multiplayer aplicada

O protocolo upstream confiava integralmente no cliente. LS-002 tornou o comando server-authoritative:
o payload contém apenas `x/y/z`; o servidor valida números inteiros finitos, chunk carregado,
distância máxima 1,8, nível Z, presença/estado do cadáver, restrição interna e recursos reais no
inventário autenticado do jogador. O servidor consome a fonte de fogo/gasolina e usa seu próprio
raio de Sandbox, com clamp 0–5. O cliente não inicia fogo nem altera recursos em multiplayer.

As regras nativas `NoFire` e `SafehouseAllowFire` são respeitadas. Quando Lascivious Systems está
ativo, a mesma validação consulta `PhunZones` em runtime e impede que a queima inicial ou a cadeia
entrem numa zona `nofire`; isso não cria requisito de ordem porque o comando só roda após todos os
submods terminarem de carregar.

## Colisões

Vários módulos usam `Events.OnFillWorldObjectContextMenu`, mas todos apenas adicionam listeners; não
há atribuição global do evento nem remoção de callback alheio. Nenhum outro submod usa `BCB`,
`BCB_ISBCBBurnAction` ou altera `ISBurnCorpseAction`/`burnCorpse`. A interação com `PhunZones`
compõe por consulta tardia opcional e está registrada em `docs/COLLISION_REGISTRY.md`.

## Riscos restantes

- Fogo é uma mutação destrutiva do mundo por natureza. Os padrões upstream permitem queima interna,
  raio 4 e não apagam o fogo automaticamente; o perfil ativo do servidor foi registrado com esses
  mesmos padrões, sem mudar o balanceamento solicitado pelo módulo.
- O cliente ainda cronometra a animação customizada porque o B42 rejeita a conclusão normal desse
  tipo no `NetTimedAction`. Isso não dá autoridade sobre o resultado: toda mutação e todo consumo
  são revalidados pelo servidor após a animação.
- A limpeza `NoAshRemains` remove sprites `floors_burnt_01_*` do quadrado após o fogo acabar, como no
  upstream. A opção permanece desativada por padrão.
