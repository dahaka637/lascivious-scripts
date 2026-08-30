# Integration Notes — Wandering Zombies

- `module_key`: `wandering-zombies`
- `bundled_mod_id`: `LS_WanderingZombies`
- Fonte: Workshop `2983905789`.
- Variante selecionada: WIP experimental, camada `42.18`, consolidada para o alvo 42.20.x.

## Escolha da variante

O item contém duas variantes incompatíveis entre si. A estável mantém a implementação antiga e
mais simples; a WIP é uma reescrita com hordas persistentes em memória, exploração de construções,
perfis separados para solitários/hordas, UI própria e dois eventos de Director. Após comparação, o
usuário escolheu a WIP para obter movimentação mais rica e imprevisível, com autorização para
recuar à estável caso a base experimental não fosse recuperável.

A WIP publicada não carregava literalmente: `RYUKU_WanderingZombies_SandboxVars.lua` construía uma
tabela com o índice global inexistente `WZ_PERFORMANCE`, produzindo `table index is nil`. A revisão
também encontrou defeitos localizados em reload, fusão de hordas, UI e reflexão. Todos possuem
correções pequenas e testáveis, sem exigir reescrever o núcleo; por isso a WIP foi mantida.

## Comportamento final e perfil orgânico

O runtime contém 28 arquivos Lua (~5.200 linhas) e 144 opções de sandbox. Cada cliente só registra
zumbis sob seu controle local e os processa gradualmente, tentando revisar cada um aproximadamente
uma vez por segundo, com teto configurável por frame.

- Zumbis livres recebem destino, distância e intervalo aleatórios; podem atravessar a borda da
  célula ativa e explorar de 1 a 10 cômodos ao entrar em uma construção.
- Zumbis externos próximos formam hordas com líder/seguidores. Seguidores acompanham o líder,
  afastados demais deixam o grupo e hordas vizinhas podem se fundir.
- Tamanho e quantidade de hordas ficam sem limite (`0`), fusão fica ligada, todos os tipos de
  velocidade — inclusive rastejadores — são aceitos, e o destino máximo padrão é 100 tiles.
- A chance diária de vagar é sorteada entre 20% e 100%, com intervalo individual de 3 a 33 segundos
  e direção livre em 360 graus. O comportamento destrutivo é sorteado entre sempre, somente em
  interiores e nunca.
- `Homing` e `Flee` têm chance mínima/máxima 0. `Director Pull` e `Director Migrate` ficam
  desligados. Portanto nenhuma rotina do mod escolhe o jogador, o tempo sem ser visto ou a baixa
  densidade local como motivo para repovoar/aproximar zumbis; encontros surgem do vagar, das rotas,
  dos sons vanilla e da dinâmica das hordas.

O mod força `ZombieConfig.RallyGroupSize` para `0`, pois seu próprio sistema substitui o agrupamento
vanilla. As demais opções de população/respawn não são alteradas.

## Multiplayer e servidor dedicado

- O servidor mantém as janelas de atividade e valores aleatórios compartilhados em
  `ModData["WanderingZombies"]`, preservando o namespace upstream, e os distribui pelo módulo de
  rede `WanderingZombies`.
- O único comando aceito do cliente é `WZSVInit`, sem payload utilizado: ele apenas solicita ao
  servidor uma cópia dos valores já calculados. Não existe comando para o cliente declarar alvo,
  posição, população ou tamanho de horda.
- A movimentação roda no cliente que possui o zumbi; zumbis remotos são ignorados por
  `isRemoteZombie()`. Isso acompanha o modelo de posse da IA do jogo, mas não equivale a uma
  simulação integral no dedicated server. Transferências de posse podem gerar nova decisão
  aleatória, sem fabricar/remover zumbis.
- O marcador de wrappers deixou de usar `IsoZombie.modData.wz`, que podia sobreviver ao reload
  enquanto a lista Lua desaparecia. O bundle usa uma tabela fraca, estritamente local à sessão;
  o formato persistente compartilhado não foi renomeado.

Conclusão estática: após as correções, o bootstrap compartilhado do dedicated server passa, o
bootstrap do núcleo client passa com stubs, e não há canal client-trusted de mutação do mundo. Um
teste real client + dedicated ainda é necessário para medir comportamento sob troca de posse e
carga elevada.

## Correções funcionais relevantes

- Removido o índice fatal `WZ_PERFORMANCE` e o arquivo legado de UI inteiramente comentado.
- O rastreamento de zumbis agora é local e seguro para reload.
- A fusão fotografa a lista de seguidores antes de movê-los; o iterator upstream perdia membros ao
  alterar a lista circular durante o percurso. Um teste isolado confirma fusão 5+2 = 7.
- O raio da horda agora aplica `/ math.pi` tanto com tamanho explícito quanto implícito; vetores de
  magnitude zero não produzem divisão por zero.
- Chamadas antigas/inexistentes de reflexão no bloco de sons foram migradas para a API utilitária
  realmente presente. O Pull não registra mais um callback `OnZombieDead` inexistente.
- Grupos da UI têm ordem determinística e a instalação dos painéis é idempotente ao reabrir telas.
- Logs periódicos de população e janelas de atividade foram removidos; mensagens de erro reais
  permanecem.

## Colisões cruzadas

- `SandboxOptionsScreen.createPanel`/`onPanelChange`,
  `ISServerSandboxOptionsUI.createChildren` e `ServerSettingsScreen.aboutToShow` são envolvidos com
  captura anterior e call-through. Nenhum módulo bundled atual toca esses quatro métodos.
- `Events.OnZombieUpdate` também é usado pelo módulo próprio `zombie-decay`, mas eventos PZ são
  listeners aditivos; Wandering Zombies não remove nem substitui o listener do outro módulo.
- `ZombieConfig.RallyGroupSize` é deliberadamente mantido em zero; nenhum outro módulo bundled o
  altera.
- Globals `WZ*`/`RYRNG`, rede/ModData `WanderingZombies` e sandbox
  `WZLoneZombie`/`WZHordeZombie`/`WZShared`/`WZDirector` são exclusivos no pacote atual.

## Tradução e verificação

O JSON EN possui 160 chaves. Foi criado catálogo PT-BR 160/160 e fallback nativo
`Sandbox_EN.txt`, necessário para `getText()` e para a UI de sandbox. Ver
`TRANSLATION_PTBR.md`.

Todos os Lua e a tabela nativa EN passam em `luac5.1 -p`; os JSONs passam em `jq`; requires foram
conferidos contra o runtime ou a instalação vanilla 42.20.x; snapshot vendor permanece idêntico à
fonte local. As validações globais do pacote estão registradas na conclusão da integração.
