# Local Changes - Lascivious Traits

## LS-001

Tipo: bundling / dependencia interna
Arquivos: `42/media/lua/client/{MF_Config.lua,MF_ISMoodle.lua}`,
`42/media/lua/shared/Translate/EN/{UI_EN.txt,UI.json}`,
`42/media/lua/shared/Translate/PTBR/UI.json`
Motivo: Moodle Framework (Workshop 3396446795) adicionado como dependencia interna do container,
antecipando que os traits futuros vao querer mostrar status na barra de moodles.
Mudanca: nenhuma linha de Lua foi alterada - copia byte-a-byte da variante `42.20/` (mais `common/`
para `MF_Config.lua` e traducao EN), que e a que realmente se aplica ao nosso alvo 42.20.x entre as
4 variantes que o upstream distribui. Bundled direto dentro de `LS_Traits` (nao como Mod ID
separado), decisao explicita do dono do projeto. PT-BR nativo (`.txt`) nao foi criado para a familia
UI - mesma limitacao aceita no resto do pacote para familias fora de Sandbox (ver
`TRANSLATION_PTBR.md`); so o JSON de referencia em PT-BR foi adicionado.
Validacao: `luac5.1 -p` em `MF_Config.lua`, `MF_ISMoodle.lua` e `UI_EN.txt`; JSON EN/PTBR validados
com `json.load`; `tools/validate_structure.py` e `tools/audit_collisions.py` re-executados.

## LS-002

Tipo: bundling / dependencia interna
Arquivos: `42/media/lua/client/{ISCharacterInfoWindow_AddTab,ISCharacterKills,KillCountClient,
KillCountClientModData,KillCountExports,KillCountUpdate,RISCharacterScreen,RISPostDeathUI,
WeaponTypeKillCount}.lua`, `42/media/lua/server/KillCountServer.lua`,
`42/media/lua/shared/KillCountShared.lua`, `42/media/sandbox-options.txt`,
`42/media/lua/shared/Translate/EN/{Sandbox_EN.txt,Sandbox.json,UI_KillCount_EN.txt,UI_KillCount.json}`,
`42/media/lua/shared/Translate/PTBR/{Sandbox.json,Sandbox_PTBR.txt,UI_KillCount.json}`
Motivo: KillCount (Workshop 2553809727) adicionado como segunda dependencia interna do container,
antecipando que os traits futuros vao querer ler contagem de kills (fogo/carro/explosao/arma) alem
do `getZombieKills()` vanilla.
Mudanca: nenhuma linha de Lua foi alterada - copia mesclada de `common/` (base: traducoes,
sandbox-options.txt, 6 dos 11 arquivos Lua, identicos entre `common/` e `42.15/`) com os 5 arquivos
que genuinamente divergem sobrepostos de `42.15/` (a pasta numerada mais alta do upstream, a que
realmente se aplica ao nosso alvo 42.20.x). Os dois arquivos de traducao `UI_EN.txt`/`UI.json` do
upstream foram renomeados para `UI_KillCount_EN.txt`/`UI_KillCount.json` só para não colidir no
nome de arquivo com os que o Moodle Framework já usa neste mesmo submod (`LS_Traits`) - o nome da
tabela Lua dentro do arquivo, não o nome do arquivo, é o que o carregador de traducao do PZ usa,
entao isso é só organização, não uma correção de bug. PT-BR nativo (`.txt`) gerado para a familia
Sandbox via `tools/generate_ptbr_sandbox_native.py`; familia UI ficou só com JSON de referencia,
mesma limitação aceita no resto do pacote.
**Achado de autoridade MP documentado, sem alteração de código**: o servidor aceita os valores de
kill que o cliente reporta sem validar (`gmd[command] = args`), só amarrado à identidade real do
remetente (não dá pra falsificar o placar de outro jogador, só o próprio). Hoje isso é inofensivo
porque o KillCount é puramente cosmético/informativo. Ver `INTEGRATION.md` para o aviso completo
sobre por que isso importa se um trait futuro usar esses dados pra ganhar algo mecânico, não só
visual.
Validação: `luac5.1 -p` em todo o Lua/`.txt` nativo; JSON validado com `json.load`;
`tools/validate_structure.py` e `tools/audit_collisions.py` re-executados; duas linhas do
`docs/COLLISION_REGISTRY.md` atualizadas (`ISCharacterInfoWindow.createChildren` já tinha
`antibodies`, `ISPostDeathUI` já tinha `evil-morty-death-screen` - ambas confirmadas sem conflito
real, métodos diferentes ou padrão seguro dos dois lados) mais uma linha nova
(`ISCharacterScreen.render`).

## LS-003

Tipo: bundling / dependencia interna
Arquivos: `42/media/lua/client/UnitedCarryWeightFramework_Client.lua`,
`42/media/lua/server/UnitedCarryWeightFramework_Server.lua`,
`42/media/lua/shared/UnifiedCarryWeightFramework.lua`, 2 blocos de opcao anexados a
`42/media/sandbox-options.txt` (mesmo arquivo do KillCount),
`42/media/lua/shared/Translate/EN/{Sandbox_UCWF_EN.txt,Sandbox_UCWF.json}` (native EN escrito a
mao - upstream so tinha JSON), 2 chaves mescladas no `Translate/PTBR/Sandbox.json` ja existente
(mesmo arquivo do KillCount - a ferramenta so le um `Sandbox.json` por mod).
Motivo: Unified Carry Weight Framework (Workshop 3682045254) adicionado como terceira dependencia
interna do container, antecipando que traits futuros vao querer afetar o peso maximo que o
personagem carrega sem brigar com outros mods que fazem o mesmo.
Mudanca: nenhuma linha de Lua foi alterada nos arquivos bundled. **3 arquivos do upstream foram
deliberadamente excluidos do bundle**: `UCWF_client_example.lua`, `UCWF_server_example.lua`,
`UCWF_server_test_always_on.lua` - todos comecam com `if true then return end`, sao codigo de
rascunho do autor que nunca roda de verdade, mantidos so no snapshot `vendor/` como referencia (os
arquivos de exemplo sao a melhor documentacao de como chamar `registerBaseModifier`/
`registerMaxModifier` corretamente).
**Achado revisado e resolvido, sem alteracao de codigo necessaria**: o valor `8` hardcoded como
base de peso parecia poder descartar o escalonamento de Forca do vanilla, mas decompilei o jar do
jogo (42.20) e confirmei que `maxWeightBase` nao e dinamicamente escalado por Forca no vanilla - `8`
e mesmo o baseline neutro correto (confirmado tambem pelo proprio comentario do autor no arquivo de
exemplo). O multiplicador de trait vanilla (`maxWeightDelta`: Strong/Weak/Feeble/Stout) e preservado
corretamente pelo pipeline de modificadores MAX via razao, nao descartado. Ver `INTEGRATION.md` para
o raciocinio completo.
**Interacao real documentada, sem alteracao de codigo ainda necessaria**: o `LS_AegisPanel` tem uma
ferramenta administrativa de "fixar peso maximo" que tambem escreve em `setMaxWeightBase`/
`setMaxWeight`. Hoje, sem nenhum modificador UCWF registrado, nao ha nada com que interagir. Quando
um trait futuro registrar um modificador, o pin do Aegis vai piscar (ser sobrescrito pelo recompute
horario do UCWF e reafirmado logo em seguida pelo proprio Aegis) em vez de ser perdido
silenciosamente - documentado em `INTEGRATION.md` e `docs/COLLISION_REGISTRY.md` para ser resolvido
quando o primeiro trait que mexe em peso for escrito, nao antes.
Validacao: `luac5.1 -p` em todo o Lua/`.txt` nativo; JSON validado com `json.load`;
`tools/validate_structure.py` e `tools/audit_collisions.py` re-executados; nova linha em
`docs/COLLISION_REGISTRY.md` para a interacao com o pin de peso do Aegis Panel.

## LS-004

Tipo: primeiro trait real / reforco de tratamento de erro / traducao nativa escrita a mao
Arquivos: `42/media/lua/client/RegretNothing_DudeMechanics.lua` (modificado),
`42/media/lua/client/RegretNothing_Moodle.lua` (verbatim), `42/media/registries.lua` (novo, primeiro
deste submod), `42/media/scripts/RegretNothing/traits.txt` (verbatim),
`42/media/ui/{MoodleRNFrenzy.png,MoodleRNMeleebuff.png,RNFrenzy.png,RNMeleebuff.png}` (verbatim),
`42/media/ui/Traits/trait_RegretNothing.png` (verbatim, case preservado),
`42/media/lua/shared/Translate/EN/{UI_RegretNothing_EN.txt,UI_RegretNothing.json,
Moodles_RegretNothing_EN.txt,Moodles_RegretNothing.json}` (novos, escritos a mao),
`42/media/lua/shared/Translate/PTBR/{UI_RegretNothing_PTBR.txt,UI_RegretNothing.json,
Moodles_RegretNothing_PTBR.txt,Moodles_RegretNothing.json}` (novos, traducao manual)
Motivo: "I Regret Nothing Trait" (Workshop 3676431328) e o primeiro trait de verdade adicionado ao
container, a pedido explicito do dono do projeto, que tambem pediu revisao/reforco especifico contra
um relato (nao confirmado) de spam infinito de erro na pagina oficial do Workshop, e traducao manual
para PT-BR (upstream nao vem em portugues).
Mudanca de codigo: o upstream ja tinha um helper `RN_safe(key, fn)` (desabilita a operacao apos o
primeiro erro, loga uma linica) aplicado em `RN_OnPlayerUpdate` (roda todo frame, o de maior risco),
incluindo correcao especifica pra um padrao de "fila envenenada" nas branches de atualizacao de
moodle (flags de estado agora escritas antes da chamada ao Moodle Framework, nao depois). Mas a
aplicacao era inconsistente: `RN_OnZombieDead` e `RN_EveryTenMinutes` ainda usavam `pcall` puro
(mesmo risco de spam em eventos repetidos - uma horda ou uma sessao longa sem matar zumbi ainda
podia gerar um stream real), e `RN_OnWeaponHitCharacter` mais a maior parte de `RN_OnEquipPrimary`
nao tinham nenhuma protecao. Estendemos `RN_safe` pros quatro pontos, mesmo padrao ja usado no
resto do arquivo - nenhum comportamento do caminho de sucesso mudou, só o que acontece na primeira
vez que uma dessas chamadas lanca erro.
Namespace: mantido como o proprio `RegretNothing:RegretNothing` do upstream, nao renomeado pra
`lascivioustraits:regretnothing` - essa convencao e reservada pra traits desenhados do zero pra
este container; isso aqui e um bundle direto de um mod de trait especifico, mesmo tratamento dado
as tres dependencias de framework. Icone do trait mantido com o nome de arquivo original,
**incluindo maiuscula/minuscula** (`trait_RegretNothing.png`) - confirmado contra o jar vanilla que
o B42 resolve o icone pelo nome local da resource location com case preservado, nao forcado pra
minusculo; deixar tudo minusculo teria quebrado a resolucao do icone no Linux, nao corrigido nada.
Traducao: upstream nao tinha nenhum `.txt` nativo em nenhum idioma, so `Moodles.json`/`UI.json` em
ingles - escrevemos `UI_EN`/`Moodles_EN` nativos a mao (2 chaves + 16 chaves) e a traducao completa
pra PT-BR nativo (mesmo escape ASCII decimal usado no resto do pacote), nao so o JSON de referencia
que e o padrao aceito pro resto do pacote fora da familia Sandbox - pedido explicito do dono do
projeto.
Validacao: `luac5.1 -p` em todo Lua/`.txt` novo/modificado; JSON validado com `json.load`;
`tools/validate_structure.py` e `tools/audit_collisions.py` re-executados; nova linha em
`docs/COLLISION_REGISTRY.md` pra `ISEatFoodAction:perform`.

## LS-005

Tipo: correcao de bug / achado arquitetural que afeta toda tradução `UI`/`Moodles` do submod
Arquivos: `42/media/lua/shared/Translate/EN/{UI.json,UI_EN.txt,Moodles.json,Moodles_EN.txt}`
(mesclados), `42/media/lua/shared/Translate/PTBR/{UI.json,Moodles.json}` (mesclados),
removidos: `UI_KillCount_EN.txt`, `UI_KillCount.json`, `UI_RegretNothing_EN.txt`,
`UI_RegretNothing.json`, `Moodles_RegretNothing_EN.txt`, `Moodles_RegretNothing.json` (EN),
`UI_KillCount.json`, `UI_RegretNothing.json`, `UI_RegretNothing_PTBR.txt`,
`Moodles_RegretNothing.json`, `Moodles_RegretNothing_PTBR.txt` (PTBR)
Motivo: o dono do projeto reportou que, no jogo, o trait I Regret Nothing aparecia com o nome
cru `UI_trait_regretnothing` em vez do texto traduzido - nem o EN nem o PT-BR funcionavam.
**Achado raiz**: a suposição usada desde o LS-002 (KillCount) - "PZ mescla arquivos de tradução
pelo nome da tabela Lua declarada dentro do arquivo, não pelo nome do arquivo" - só é verdadeira
ENTRE mods diferentes (cada um com seu próprio Mod ID). **Dentro de um único mod, o carregador de
tradução do PZ lê exatamente UM arquivo por categoria por idioma** (`UI.json`/`UI_EN.txt`,
`Moodles.json`/`Moodles_EN.txt`, etc.), do mesmo jeito que `tools/generate_ptbr_sandbox_native.py`
já documentava pra família `Sandbox` especificamente. Comparado a instalação vanilla local
(42.20.x): o próprio jogo só usa `UI.json`/`Sandbox.json`/`Moodles.json` (nenhum `.txt` nativo
existe em lugar nenhum da pasta `Translate/` vanilla, nem em EN nem em PTBR) - confirma que
`getText()` lê JSON diretamente pra essas famílias (diferente da TELA de opções de sandbox
especificamente, que é o único caso realmente comprovado a exigir `.txt` nativo). Isso significa
que os arquivos com nome escopado (`UI_KillCount_EN.txt`/`UI_KillCount.json`,
`UI_RegretNothing_EN.txt`/`UI_RegretNothing.json` etc.) **nunca foram lidos pelo jogo, nem pro
KillCount nem pro I Regret Nothing** - o bug já existia desde o LS-002, só não tinha sido notado
porque ninguém tinha testado o texto da aba "Kills" do KillCount em jogo ainda.
Mudança: todas as chaves `UI`/`Moodles` de Moodle Framework + KillCount + I Regret Nothing agora
vivem nos arquivos canônicos únicos (`UI.json`, `Moodles.json`, e as versões `_EN.txt` pro
inglês). **Decisão pra PT-BR**: não foi criado `UI_PTBR.txt`/`Moodles_PTBR.txt` nativo agora -
teria cobertura parcial (só as chaves do I Regret Nothing, já que Moodle Framework/KillCount
ainda não têm tradução nativa pra essas duas famílias) e, se o carregador do jogo priorizar
`.txt` sobre `.json` quando os dois existem, um `.txt` parcial correria o risco de OCULTAR as
chaves que já funcionavam via `UI.json`/`Moodles.json` (regressão). Como o `.json` sozinho já é
comprovadamente o mecanismo que o próprio vanilla usa, ficou só ele por enquanto - tradução
nativa completa em PT-BR (exigiria traduzir também as 9+7 chaves de Moodle Framework/KillCount
que ainda não têm) fica pra quando fizermos a passada de tradução dedicada, a pedido do dono do
projeto.
Validação: `luac5.1 -p` nos `.txt` restantes; JSON validado com `json.load`;
`tools/validate_structure.py` e `tools/audit_collisions.py` re-executados; confirmado em jogo
pelo dono do projeto que o problema motivou esta correção (ainda não re-testado após a correção -
próximo passo do lado dele).

## LS-006

Tipo: segundo pacote de traits (bundling) / correcao de colisao em modulo ja existente
Arquivos: toda a arvore `42.19/media/lua/{client,server,shared}/**` do ETW mesclada dentro de
`42/media/lua/{client,server,shared}/` do LS_Traits (sem colisao de nome de arquivo com nada que
ja existia), `42/media/registries.lua` (bloco `ETW_Registry.traits` anexado), `42/media/sandbox-
options.txt` (conteudo do ETW anexado, removendo o `VERSION = 1,` duplicado - mesma armadilha ja
vista no merge do UCWF), `42/media/scripts/ETW_Traits.txt` (novo, 65 `character_trait_definition`),
`42/media/ui/{Traits (65 icones),Moodles (2),GradientBars (3)}`, `42/media/sound/` (23 arquivos),
`42/media/scripts/ETW_{NotificationSounds,ParanoiaSounds,TraitSounds}.txt`, e as chaves EN/PTBR de
`Sandbox`/`UI`/`Moodles` do ETW mescladas nos arquivos canonicos unicos do submod (mesma regra do
LS-005). Alem disso, **um arquivo de OUTRO modulo ja bundled foi corrigido**:
`Contents/mods/LS_BetterEngineRepair/42/media/lua/shared/BetterEngineRepairPatch.lua` (comentario
adicionado documentando a exigencia de ordem de carregamento, sem mudanca de logica).
Motivo: "Evolving Traits World" (Workshop 2914075159) e o segundo pacote de traits do container, a
pedido explicito do dono do projeto - 65 traits novos mais um sistema que torna dezenas de traits
vanilla ganhaveis jogando, nao so escolhiveis na criacao de personagem. O `require=` do proprio
upstream ja pedia exatamente as tres dependencias de framework que ja tinhamos bundled
(MoodleFramework, KillCount, UCWF), confirmando que a sequencia de preparo anterior fez sentido.
Achado sobre dependencia opcional: `MarkDynamicTraitsFramework` (MDTF) parecia à primeira vista
bloquear o mecanismo inteiro de traits dinamicos (todo o `ETW_MarkDynamicTraits.lua` fica atras de
um `getActivatedMods():contains("MarkDynamicTraitsFramework")`), mas confirmado contra a propria
pagina do Workshop que MDTF so decora o nome do trait com um sufixo "(D)" na tela de criacao de
personagem - a logica real de ganhar/perder trait roda igual sem ele. Nao bundled, nao e uma
lacuna funcional.
**Achado de colisao real, mas em codigo NOSSO, nao do ETW**: `ISRepairEngine:complete` ja tinha
uma linha no `COLLISION_REGISTRY.md` desde a integracao do `better-engine-repair` documentando que
ele faz reimplementacao completa sem chamar adiante ("superficie ocupada"). O ETW faz um wrap
seguro do mesmo metodo (mede condicao antes/depois pra rastrear progresso de Bodywork
Enthusiast/Mechanics). Se `LS_BetterEngineRepair` carregar DEPOIS de `LS_Traits` no `Mods=`, a
reatribuicao completa dele descarta silenciosamente o wrap do ETW e esse rastreamento para de
funcionar - sem erro, sem crash, só um recurso morto silenciosamente. Nao da pra corrigir com
"chamar adiante" dentro do `BetterEngineRepairPatch.lua` porque a formula dele substitui o calculo
inline do vanilla - chamar adiante duplicaria o reparo. Corrigido documentando a exigencia de ordem
(`LS_BetterEngineRepair` antes de `LS_Traits`) no proprio arquivo e no `COLLISION_REGISTRY.md` -
ainda nao aplicavel de verdade porque `LS_Traits` nao esta wireado em `Mods=` nenhum ainda, mas tem
que ser lembrado quando isso acontecer.
Colisao revisada em profundidade: todo monkey patch do ETW (25 metodos, ~14 classes vanilla,
localizados via grep pelo proprio padrao de captura-antes do pacote) checado individualmente
contra os outros 34 submods - so o `ISRepairEngine:complete` (acima) e um problema real; os demais
ou tocam metodos diferentes dos ja usados por outros mods bundled (`ISEatFoodAction`,
`ISInventoryTransferAction`, `ISReadABook`, `ISWorldObjectContextMenu`, `ISAddItemInRecipe`) ou sao
superficie nova sem toque nenhum de outro modulo.
**Segundo bug encontrado e corrigido, upstream desta vez**: comparado programaticamente o nome
local de cada uma das 65 resource locations registradas (`ETW:<Nome>`) contra o arquivo de icone
correspondente (`trait_<Nome>.png`) - `ETW:BodyWorkEnthusiast` (W maiusculo) so tinha um arquivo
`trait_BodyworkEnthusiast.png` (w minusculo) no upstream. Funciona no Windows/Mac (case-insensitive)
mas quebraria a resolucao do icone no nosso servidor Linux (case-sensitive), mesma categoria de
cuidado ja documentada pro icone do RegretNothing. Renomeado o arquivo pra
`trait_BodyWorkEnthusiast.png` pra bater exatamente com a resource location - os outros 64 icones
ja batiam certinho.
Traducao: **deliberadamente incompleta, a pedido explicito do dono do projeto** - implementar tudo
primeiro, traduzir depois numa passada dedicada (tarefa grande: ~525 chaves de Sandbox, ~213 de
UI). O PT-BR que o upstream ja trazia pronto (~21%/~28% de cobertura) foi bundled como esta -
mover o que ja existe nao e a mesma coisa que traduzir do zero, entao isso nao foi adiado.
Validacao: `luac5.1 -p` em todo Lua/`.txt` (novo e existente); JSON validado com `json.load`;
balanco de chaves conferido em `sandbox-options.txt` e `ETW_Traits.txt` (321/321 e 66/66); 65
`character_trait_definition` confirmados; `tools/validate_structure.py` e
`tools/audit_collisions.py` re-executados, ambos limpos; 8 novas linhas em
`docs/COLLISION_REGISTRY.md` (incluindo a correcao da linha de `ISRepairEngine:complete` pra
documentar a interacao com o ETW).

## LS-007

Tipo: traducao completa PT-BR (passada dedicada) / correcao de um segundo bug de arquivo orfao
Arquivos: `42/media/lua/shared/Translate/PTBR/{UI.json,Sandbox.json,Moodles.json}` (432 chaves de
Sandbox + 149 de UI traduzidas, 0 faltando), `42/media/lua/shared/Translate/PTBR/{UI_PTBR.txt,
Moodles_PTBR.txt}` (novos, nativos, cobertura completa agora segura), `Sandbox_PTBR.txt`
(regenerado via `tools/generate_ptbr_sandbox_native.py`), `42/media/lua/shared/Translate/EN/
{Sandbox.json,Sandbox_EN.txt}` (chaves do UCWF mescladas), removidos:
`EN/Sandbox_UCWF_EN.txt`, `EN/Sandbox_UCWF.json` (orfaos), mais uma limpeza de ~21 chaves
PT-BR-only orfas em `Sandbox.json`/`UI.json` que nao batiam com nada no EN atual.
Motivo: dono do projeto pediu a passada de traducao dedicada que tinha sido adiada no LS-006 -
"quero todos traduzidos, nada de fora" (nomes, descricoes e todas as opcoes de sandbox do ETW).
Traducao: 65 nomes/descricoes de trait, ~525 rotulos/dicas de opcao de sandbox cobrindo todos os
sistemas do ETW (Coragem, Medo de Lugares, Neblina, Chuva, Cura, Ferimentos, Alimentacao/Sede/
Sono/Velocidade de Comer/Audicao, requisitos de habilidade/mortes por trait pra cada trait vanilla
que o ETW torna dinamico, e ajuste fino de cada um dos 65 traits novos). Glossario de nomes de
trait vanilla estabelecido e documentado em `TRANSLATION_PTBR.md` pra manter consistencia em toda
referencia cruzada (ex: "Corajoso", "Desajeitado", "Pele Grossa" reaparecem em varias dicas).
**Segundo achado de bug, dessa vez no lado EN**: enquanto fechava a lacuna do ETW, percebi que o
UCWF tinha o mesmo problema do LS-005, só que em ingles - `Sandbox_UCWF_EN.txt`/`Sandbox_UCWF.json`
(nomes de arquivo nao-canonicos) estavam la desde o LS-003 e provavelmente nunca foram lidos pelo
jogo, o que significa que as duas opcoes de sandbox do UCWF ("Cap max weight at 50" / "Gather
Detailed Debug Information") nunca apareceram nem em ingles. Corrigido mesclando no
`Sandbox_EN.txt`/`Sandbox.json` canonico e apagando os arquivos orfaos.
Limpeza: ~21 chaves PT-BR-only descobertas nao batendo com nenhuma chave do EN atual (ex:
`Sandbox_ETW_Axpert` de uma versao antiga do upstream, antes de renomear pra `Sandbox_ETW_Axeman`;
`Sandbox_ETW_Desensitized*`, `Sandbox_ETW_WeightSystem*` de sistemas que nao existem mais na
versao atual) - removidas por serem entradas mortas, nao por afetarem funcionalidade.
Validacao: `luac5.1 -p` em todo `.txt` novo/modificado; JSON validado com `json.load`; paridade
exata EN/PTBR conferida chave a chave nas tres familias (UI 227/227, Sandbox 540/540, Moodles
50/50, zero faltando e zero sobrando dos dois lados); `tools/validate_structure.py` e
`tools/audit_collisions.py` re-executados, ambos limpos.

## LS-008

Tipo: checkup de harmonia entre dois traits ja bundled - investigacao concluida com REVERSAO,
nenhuma alteracao de codigo permanece
Arquivos: nenhum (as duas mudancas feitas durante a investigacao foram revertidas antes de fechar
este item - ver historico abaixo).
Motivo: dono do projeto pediu um checkup dedicado entre o I Regret Nothing e o ETW pra garantir
que os dois sistemas ficassem harmonicos, nao so sem colisao de funcao (ja coberto na revisao
anterior).
Achado #1: o sistema de decaimento de vicio de fumante do ETW (`ETW_ByTime.lua`) PODE remover
`base:smoker` de um personagem que nao fuma o suficiente, mesmo um que ganhou o trait via
`GrantedTraits` do I Regret Nothing (`GrantedTraits` so concede uma vez, nao trava o trait no
lugar depois - confirmado decompilando `CharacterTraits.class`: `add()`/`remove()` so mexem
direto num Map/List, zero verificacao cruzada entre traits). **Reacao inicial (revertida)**: tratei
isso como bug e escrevi uma funcao pra reconceder o trait toda vez que sumisse. **O dono do
projeto questionou essa decisao e estava certo**: `GrantedTraits` e so o pontapé inicial, nao uma
promessa de permanencia - a propria descricao do trait diz que ele "força" o Fumante, nao que
"trava" o Fumante pra sempre. Deixar o personagem seguir as regras normais do ETW depois de
ganhar o trait (podendo perde-lo por nao fumar, igual qualquer outro personagem) é mais harmonico
com a filosofia central do ETW ("traits sao ganhos e podem ser perdidos") do que fazer o I Regret
Nothing brigar contra o sistema. Revertido, sem alteracao de codigo.
Achado #2: o Sistema de Coragem (`ETW_ByKills.lua`) e o Sistema de Medo de Lugares
(`ETW_ByLocation.lua`) do ETW podem conceder `base:adrenalinejunkie`/`base:brave`/
`base:agoraphobic`/`base:claustrophobic` num personagem com I Regret Nothing baseado só em
contagem de mortes/tempo em locais, sem saber que o I Regret Nothing já declara esses traits como
`MutuallyExclusiveTraits` (essa lista só é aplicada pela tela de criação de personagem, confirmado
via o mesmo decompile que `player:getCharacterTraits():add()` não faz nenhuma checagem de
exclusividade). **Tambem revertido pelo mesmo motivo**, e especificamente pra `brave`/
`adrenalinejunkie`: a exclusividade estatica original parece mais uma regra de orçamento de pontos
na criação de personagem (não deixar pagar pontos duas vezes por efeitos parecidos de confiança
em combate) do que uma contradição mecânica de verdade - ganhar um desses depois, matando zumbi de
verdade, é um caminho de aquisição diferente, pago com esforço de jogo de verdade, sem a mesma
preocupação de "empilhamento de graça" que a regra estática existe pra evitar. Revertido, sem
alteracao de codigo.
Achado #3, investigado e descartado desde o inicio (nunca precisou de correcao): será que dava pra
escolher I Regret Nothing junto com o trait `Blissful` do ETW, que o ETW declara mutuamente
exclusivo com Smoker? Decompilando `CharacterTraitDefinition.isMutuallyExclusive()`, vi que ela já
percorre o `GrantedTraits` do proprio trait recursivamente - como I Regret Nothing concede Smoker,
e Smoker é exclusivo com Blissful, o motor do jogo já impede essa combinação na criação de
personagem sozinho, sem precisar de nada da nossa parte. Um `ETW:Blissful` explícito chegou a ser
adicionado na `MutuallyExclusiveTraits` do proprio I Regret Nothing por um tempo, só pra
documentação - confirmado pelo mesmo decompile que era inofensivo/redundante, mas revertido também
junto com o resto, já que não corrigia nada de verdade e o arquivo fica melhor batendo com o
upstream onde nada está realmente quebrado.
Validacao: `luac5.1 -p` e balanceamento de chaves conferidos apos a reversao (arquivos batem
exatamente com o estado anterior ao LS-008); `tools/validate_structure.py` e
`tools/audit_collisions.py` re-executados, ambos limpos. As tres claims tecnicas centrais
(comportamento de `add`/`remove`/`set` em `CharacterTraits`, `isMutuallyExclusive` e
`updateMutualExclusiveTraits` em `CharacterTraitDefinition`) continuam verificadas por
decompilação direta do jar vanilla 42.20.x via `javap` e permanecem validas/documentadas mesmo
sem nenhuma alteracao de codigo - a investigacao valeu a pena, so a conclusao mudou.

## LS-009

Tipo: correcao de bug de engine vanilla / rebalanceamento de trait / correcao de moodle em dois
submodulos
Arquivos: `42/media/lua/client/CharacterCreation_GrantedTraitGuard.lua` (novo),
`42/media/scripts/RegretNothing/traits.txt` (modificado), `42/media/lua/shared/Translate/{EN,PTBR}/
{UI.json,UI_EN.txt,UI_PTBR.txt}` (descricao do I Regret Nothing), `42/media/lua/client/
RegretNothing_DudeMechanics.lua` (moodles RNFrenzy/RNMeleebuff), `42/media/lua/client/
ETW_Moodles.lua` (moodle BloodlustMoodle do ETW).
Motivo: dono do projeto reportou em teste que escolher I Regret Nothing tambem "escolhia" Fumante
visivelmente na tela de criacao, e que remover os dois (RegretNothing + o Fumante concedido)
deixava os pontos disponiveis negativos apos repetir o ciclo 3 vezes. Investigacao separada, a
pedido dele, sobre os moodles RNFrenzy (aparecia sempre, mesmo fora de frenesi) e BloodlustMoodle
do ETW (suspeita de aparecer pra jogador sem o trait).
**Achado #1 (bug de engine vanilla, nao nosso)**: comparado contra o `CharacterCreationProfession.lua`
vanilla - quando um trait usa `GrantedTraits`, o sub-trait concedido vira uma linha comum em
`listboxTraitSelected` (mesma lista das escolhas manuais), mas seu custo nunca e cobrado
(`addTrait` so faz `addUniqueItem`, nunca `pointToSpend - cost`, pro item concedido). `removeTrait`
nao distingue isso de uma compra manual - clicar direto no item concedido devolve o custo dele
mesmo assim (`pointToSpend + cost`), sugando pontos que nunca foram cobrados. Reproduz de verdade
com Fumante (custo negativo, "devolve" pontos que nunca foram tirados = perda liquida). Corrigido
com `CharacterCreation_GrantedTraitGuard.lua`, generico (le `getGrantedTraits()` ao vivo, nao
hardcoded pro RegretNothing - protege qualquer trait futuro que use `GrantedTraits`): (1)
`isTraitExcluded` passa a excluir do pool selecionavel qualquer trait que seja alvo do
`GrantedTraits` de outro, entao ele nunca aparece como escolha manual separada pra comecar; (2)
`removeTrait` recusa remover diretamente um item que ainda esta em `self.freeTraits` (concedido),
mesma protecao que o vanilla ja da a `trait:isFree()`. `CoopCharacterCreationProfession` herda os
dois metodos de `CharacterCreationProfession` via `:derive()` sem sobrescrever nenhum dos dois, entao
um unico ponto de patch cobre solo e coop.
**Mudanca #2 (pedido explicito do dono do projeto)**: `GrantedTraits` do I Regret Nothing reduzido
de `base:smoker;base:desensitized` pra so `base:desensitized` - a dependencia de Fumante deixa de
ser forcada, Insensibilizado continua concedido (nao e uma dependencia, e so insensibilidade a
dor/medo, nucleo tematico do trait). Fumante volta a ser selecionavel normalmente (o guard acima
para de exclui-lo do pool assim que ele deixa de ser alvo de `GrantedTraits` de qualquer trait - lê
o catalogo ao vivo, nenhuma mudanca de codigo adicional precisou ser feita nele). O bonus de 2h ao
fumar cigarro/charuto/comprimido (`RegretNothing_DudeMechanics.lua`, secao 7 - regeneracao continua
de Resistencia + 10% de dano extra em acerto de arma) ja era condicionado só a ter o trait
RegretNothing (`hasTrait`), nunca ao Fumante em si, entao continua funcionando identico sem
qualquer trait adicional selecionado. Descricao do trait atualizada (EN + PT-BR, JSON e `.txt`
nativo) pra nao dizer mais "forces the Smoker trait"/"Concede a trait Fumante". Torna a
Achado #1 do LS-008 (decaimento de Fumante do ETW podendo remover o Smoker concedido) irrelevante
pro I Regret Nothing especificamente, ja que ele nao concede mais Fumante - vira comportamento
normal do ETW pra qualquer personagem que pegue Fumante manualmente.
**Achado #3, confirmado pro dono do projeto**: `ETW_Moodles.lua`'s `bloodlustMoodleUpdate` E
proposital do upstream mostrar pra qualquer jogador, nao so quem ja tem o trait Bloodlust - e o
medidor de progresso do sistema de trait dinamico (`SBvars.BloodlustMoodle`), some/entra pra todo
mundo que mata zumbi, nao um vazamento de dados de outro jogador nem bug de visibilidade por
trait. O bug real (corrigido): `MF.ISMoodle` (Moodle Framework) so esconde um moodle quando o valor
cai na faixa neutra central (padrao 0.4-0.6); RNFrenzy/RNMeleebuff mandavam `0.0` pro estado
"desligado", que cai no extremo BAD nivel 4 (o oposto de escondido) em vez da faixa neutra - por
isso o moodle de frenesi aparecia sempre avisando que NAO estava em frenesi. Mesmo padrao no
BloodlustMoodle do ETW: `percentage` perto de zero (mas positivo, dentro da janela de visibilidade
pos-morte) tambem cai no extremo BAD nivel 4 em vez de esconder, entao ate ~0% de progresso
aparecia gritando alarme pra qualquer jogador que matasse um zumbi. Corrigido nos tres: RNFrenzy/
RNMeleebuff usam `0.5` (o proprio sentinela "nada a reportar" que MF_ISMoodle/ETW_Moodles ja usam
como valor padrao/oculto em outros lugares) em vez de `0.0` pro estado desligado; BloodlustMoodle
ganhou uma condicao extra (`BloodLustModData.BloodlustMeter > 0`) pra so mostrar quando ha medidor
de verdade pra reportar, mantendo intacto o resto do design (visivel por N horas apos morte
proxima, escalado por nivel de progresso) pra quem realmente tem alguma coisa acumulada.
Validacao: `luac5.1 -p` em todo Lua novo/modificado; JSON validado com `json.load`; `.txt` nativo
verificado com `lua5.1 -e` de verdade (nao so sintaxe); `tools/validate_structure.py` e
`tools/audit_collisions.py` re-executados, ambos limpos.

## LS-010

Tipo: nova integracao de trait bundle com traducao completa e camada de compatibilidade de gameplay
Arquivos: `42/media/lua/client/bloodlusto/*.lua` (novo, a partir do upstream Bloodlust
Overwhelming 0.9.7), `42/media/lua/shared/bloodlusto/{Registries.lua,Compat.lua}` (novo),
`42/media/lua/shared/BloodlustOverwhelming_TraitsExclusivity.lua` (novo),
`42/media/scripts/BloodlustOverwhelming_Traits.txt` (novo), `42/media/registries.lua`
(registro `bloodlusto:bloodlusto`), `42/media/sandbox-options.txt` (266 novas chaves de sandbox),
`42/media/lua/shared/Translate/{EN,PTBR}/{UI,Moodles,Sandbox}.json` e `.txt` nativos
(Bloodlust Overwhelming + ModOptions + debug), `42/media/ui/BloodlustO_*.png`,
`42/media/ui/Traits/trait_BloodlustO.png`, `42/media/textures/gui/bloodlust-overwhelming-overlay.png`,
snapshot em `vendor/lascivious-traits/upstream/bloodlust-overwhelming/42/`.
Motivo: dono do projeto pediu para adicionar Bloodlust Overwhelming (Workshop `3786352314`) ao
container `LS_Traits`, com traducao 100% e cuidado especial para harmonia com ETW.

Decisao de namespace/save: mantido o resource location upstream `bloodlusto:bloodlusto`, em vez de
renomear para `lascivioustraits:*`, porque este e um port bundled de um mod especifico e o ID do
trait vira dado persistente no personagem assim que alguem seleciona/conquista o trait. Para evitar
chaves problematicas em traducao nativa, somente as chaves de texto foram adaptadas: o trait usa
`UI_trait_BloodlustOverwhelming`/`UI_trait_BloodlustOverwhelmingDesc`, e as frases dinamicas que
o upstream nomeava como `UI_BloodlustO:foo:1` agora sao resolvidas por `Utils.getVariants()` como
`UI_BloodlustO_foo_1` (substitui caracteres nao alfanumericos por `_`). O ID persistente do trait
nao mudou.

Compatibilidade/harmonia: Bloodlust Overwhelming nao e tecnicamente o mesmo trait que
`ETW:Bloodlust`, mas as duas mecanicas recompensam/alteram combate por sede de sangue e se
empilhariam de forma agressiva. Foi adicionada exclusividade de criacao e runtime contra
`ETW:Bloodlust` e `RegretNothing:RegretNothing`; tambem contra `base:pacifist` e `base:hemophobic`
por coerencia tematica. `bloodlusto/Earning.lua` nao concede o trait dinamicamente se o personagem
tem qualquer um desses bloqueadores. Do lado do ETW, `ETW_ByKills.lua`,
`ETW_AnimalActionsSharedLogic.lua` e `ETW_CombatTraits.lua` pulam especificamente jogadores com
Bloodlust Overwhelming, sem desligar o sistema Bloodlust do ETW para outros jogadores do servidor.
Assim o Overwhelming vence como variante mais extrema, mas nao interfere em personagens que usam o
Bloodlust dinamico normal do ETW.

Guard MP/local-player: `bloodlusto/Bloodlust.lua` e `bloodlusto/Earning.lua` agora ignoram players
nao locais antes de aplicar eventos de hit/kill/minuto/update/move/earn. O upstream roda client-side
e, em MP, eventos como `OnWeaponHitCharacter` podem aparecer em clientes que nao sao o atacante;
esse filtro evita multiplicacao/efeito fantasma em player remoto.

Fix local de asset/case: `RedVision.lua` agora carrega
`media/textures/gui/bloodlust-overwhelming-overlay.png` com o mesmo casing da pasta real do bundle,
evitando falha de overlay em filesystem case-sensitive.

Traducao: incorporadas as traducoes EN upstream de `UI`/`Moodles`/`Sandbox` aos arquivos canonicos
do submod e escrita traducao PT-BR completa para todas as novas chaves: +324 `UI` (incluindo
frases, Mod Options client-side e debug), +49 `Moodles`, +266 `Sandbox`. Totais atuais:
`UI.json` 551/551, `Moodles.json` 99/99, `Sandbox.json` 806/806, EN e PT-BR com paridade exata.
Native `.txt` de EN/PTBR regenerado a partir dos JSON canonicos para as tres familias.

Validacao: `luac5.1 -p` em todos os Lua de `LS_Traits`, `lua5.1 -e` nos `.txt` nativos de traducao,
JSON/paridade de chaves, chaves dinamicas do BloodlustO, `tools/validate_structure.py`,
`tools/audit_collisions.py` e `git diff --check` passaram.

## LS-011

Tipo: tres bugs pos-integracao do Bloodlusto (LS-010) encontrados em teste real -- um crash em
runtime, um erro de boot, e a tela de sandbox do Bloodlusto inteira ausente
Arquivos: `42/media/lua/client/bloodlusto/{Sandbox.lua,ControlSandbox.lua}` (fallback de defaults),
`/home/dahaka/Zomboid/Server/LASCIVIOUS_SandboxVars.lua` (fora do repo -- sandbox real do servidor),
`42/media/lua/server/ETW_ModDataServer.lua` (require corrigido),
`42/media/sandbox-options.txt` (uma linha removida)
Motivo: dono do projeto reportou, jogando com o Bloodlusto recem-integrado, um stream de erro Lua
em jogo (`attempted index: FreshBloodinessDecayMode of non-table: nil`) mais 1 erro ao iniciar o
jogo; corrigido em duas rodadas (Codex, depois retomado por mim quando os tokens do Codex
acabaram).

Achado #1 (Codex): `SandboxVars.BloodlustO`/`BloodlustO_Control` vinham `nil` (ou incompletos) em
runtime mesmo com `sandbox-options.txt` correto -- ordem/sessao de carregamento pode deixar a
tabela ainda nao populada quando `Bloodlust.lua`/`Earning.lua` a leem pela primeira vez.
`Sandbox.lua`/`ControlSandbox.lua` agora geram uma tabela `DEFAULTS` (extraida dos proprios
comentarios `@field ... = valor` no topo de cada arquivo -- 102 e 29 campos, conferido batendo
1:1 com os `option BloodlustO*.*` do sandbox-options.txt) e a aplicam via metatable
(`setmetatable(SB, { __index = DEFAULTS })`) sobre `SandboxVars.BloodlustO`/`_Control` -- valor
real do servidor sempre vence, ausente cai no default do proprio mod, nunca mais indexa nil. As
duas categorias tambem foram adicionadas ao sandbox real do servidor
(`/home/dahaka/Zomboid/Server/LASCIVIOUS_SandboxVars.lua`, fora deste repo) para existirem de
verdade e ficarem editaveis, com os mesmos defaults.

Achado #2 (retomado por mim): o "1 erro ao iniciar o jogo" restante era outro bug, sem relacao com
o #1 -- `ETW_ModDataServer.lua` fazia `require("ETW_BySkills")` sem caminho, mas o arquivo real
fica em `server/DynamicLogic/ETW_BySkills.lua` (uma pasta aninhada). O proprio arquivo ja usava o
padrao certo uma linha acima (`require("TraitSpecific/ETW_EagleEyedTracking")`, que resolve
corretamente `shared/TraitSpecific/ETW_EagleEyedTracking.lua`) -- so esqueceram de aplicar o mesmo
pro ETW_BySkills. Sem o caminho, o `require` falhava (`WARN ... require("ETW_BySkills") failed` no
console, o arquivo real so carregava depois, tarde demais pro `local` ja ter capturado nil), e
`ETW_BySkills.traitsGainsBySkill(...)` explodia na criacao de personagem. Corrigido pra
`require("DynamicLogic/ETW_BySkills")`.

Achado #3 (retomado por mim, o mais serio dos tres): o dono do projeto tambem reportou que as
opcoes de sandbox do Bloodlusto simplesmente nao apareciam na tela do jogo -- nem uma. Causa raiz:
o console mostrava uma SEGUNDA excecao de boot, separada da #2 --
`java.lang.RuntimeException: unknown block type "//" at CustomSandboxOptions.parse`. Decompilando
`CustomSandboxOptions.parse()`: ele chama `ScriptParser.stripComments()` antes de tokenizar, mas
essa rotina nao reconhece `//` como comentario neste formato -- o parser ve `//` como se fosse um
token de bloco de primeiro nivel (tipo `option`/`module`) e lanca excecao, o que aborta a leitura
do arquivo inteiro a partir dali. A causa: uma unica linha `// Bloodlust Overwhelming (Workshop
3786352314)` foi inserida como cabecalho de secao logo antes do primeiro `option BloodlustO_Control.*`
-- e e o UNICO comentario nas 3600 linhas do arquivo inteiro; nenhuma outra secao (KillCount, Moodle
Framework, UCWF, ETW) jamais usou comentario nenhum, so blocos `option` separados por linha em
branco. Como o arquivo inteiro falhava a partir dali, isso explica ao mesmo tempo o erro de boot
extra E a tela de sandbox do Bloodlusto inteira ausente (as 131 opcoes -- 102 + 29 -- nunca
chegavam a ser registradas). Corrigido removendo a linha, sem tentar outra sintaxe de comentario
nao comprovada neste formato -- mesmo padrao (zero comentarios) que todas as outras secoes ja
usam com sucesso.

Validacao: `luac5.1 -p` em `ETW_ModDataServer.lua` e no sandbox real do servidor; balanco de chaves
`{`/`}` do `sandbox-options.txt` (452/452) e contagem de `option BloodlustO*.*` (102 + 29,
batendo com os `DEFAULTS` de Sandbox.lua/ControlSandbox.lua) conferidos apos a remocao da linha;
`tools/validate_structure.py` e `tools/audit_collisions.py` re-executados, ambos limpos.

## Itens sem alteracao

Nenhum item pendente sem alteracao no momento.

## LS-012

Tipo: hotfix pos-teste em servidor dedicado para crashes ETW/Hardy e efeitos de humor dos traits
Bloodlust Overwhelming / I Regret Nothing
Arquivos: `42/media/lua/server/TraitsLogic/ETW_EventsOrchestrator.lua`,
`42/media/lua/server/TraitsLogic/ETW_HealthTraits.lua`,
`42/media/lua/client/RegretNothing_DudeMechanics.lua`,
`42/media/lua/server/RegretNothing_ServerEffects.lua`,
`42/media/lua/server/BloodlustOverwhelming_ServerEffects.lua`
Motivo: dono do projeto reportou stack trace repetindo `attempted index: HardyReserve of non-table:
null` em `hardyTrait()` e comportamento ruim dos traits Bloodlust Overwhelming / I Regret Nothing,
especialmente personagem continuar infeliz mesmo matando zumbis.

Hardy/ETW: `ETW_EventsOrchestrator.oneMinuteUpdate()` agora garante `modData` antes de chamar
`ETW_HealthTraits.hardyTrait()`. A propria `hardyTrait()` tambem ficou defensiva: se receber
`modData == nil`, busca via `ETW_CommonFunctions.getETWModData(player)`; se ainda nao existir,
loga uma linha e retorna sem explodir. `HardyReserve` tambem passa a nascer com o maximo da reserva
quando ausente, evitando `PZMath.clamp(nil, ...)`.

I Regret Nothing: eventos client-side agora filtram somente o player local, nao assumem mais
`getPlayer()` como atacante quando o evento nao informa o killer, e em MP dedicado deixam os efeitos
de humor/dano para o servidor. Novo `RegretNothing_ServerEffects.lua` aplica no servidor dedicado:
reduz tédio/infelicidade em kills, aumenta ambos se ficar mais de 2h sem matar, mantem pânico/stress
zerados, e aplica o bonus de dano temporario do consumivel.

Bloodlust Overwhelming: novo `BloodlustOverwhelming_ServerEffects.lua` aplica no servidor dedicado
o alivio mental essencial ao matar zumbis: remove tédio, reduz infelicidade, stress, abstinência de
nicotina e pânico usando os multiplicadores de sandbox do proprio Bloodlusto. Isso complementa o
client-side original, que em dedicado podia nao persistir ou ser sobrescrito pela autoridade do
servidor.

Validacao: `luac5.1 -p` em todos os Lua de `LS_Traits`, carregamento do sandbox real do servidor
via `lua5.1`, `tools/validate_structure.py`, `tools/audit_collisions.py` e `git diff --check`
passaram apos o hotfix.
