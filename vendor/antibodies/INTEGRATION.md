# Integration Notes — Antibodies

- `module_key`: `antibodies`
- `bundled_mod_id`: `LS_Antibodies`
- Base funcional: Antibodies 1.97, Workshop `2392676812`.
- Fonte atualizada auditada: Antibodies B42.20 Community - Compatibility Fix 0.2.3, Workshop
  `3786732297`, alvo declarado 42.20.3.

## Resultado do gate original x Community Fix

O pacote comunitário é **completo em arquivos**: a pasta `42.20/` contém a implementação inteira
1.97 (cliente, servidor, compartilhado, cinco patches de TimedAction, UI, 67 opções de sandbox e
textura), não apenas um carregador ou patch parcial. As mudanças de compatibilidade de caminhos
foram comparadas contra a instalação vanilla local da Build 42.20.x e estão corretas:

- `timedActions.*` -> `timed_actions/*` para os cinco arquivos internos do mod;
- `ISPanel` -> `ISUI/ISPanel`;
- `ISCharacterProtection`, `ISCharacterInfoWindow` e `ISHealthPanel` ->
  `XpSystem/ISUI/...`.

Ele não é seguro para uso literal, porém. A auditoria encontrou três desvios não necessários para
compatibilidade: troca do namespace persistente das 67 opções de sandbox, desativação de todos os
arquivos nativos que alimentam `getText()`, e uma mecânica nova de convalescença que altera fadiga,
resistência e doença depois da cura. Essa mecânica não aparece nas notas do fix, não migra os dados
de personagens já existentes e foge do comportamento 1.97. O bundle, portanto, usa a implementação
1.97 completa com apenas as correções B42.20 comprovadas e os patches locais descritos abaixo. O
snapshot comunitário permanece prístino em `upstream/` para futuras comparações.

## Inventário e comportamento

O runtime final tem 30 arquivos Lua (~3.200 linhas), `sandbox-options.txt`, uma textura de UI, duas
imagens de apresentação e 14 JSONs de tradução, além dos dois fallbacks nativos EN. Não contém
Java/JAR, mapas, tiledefs, packs, itens, receitas, traits ou perks próprios. Não há dependência,
`require=` de outro mod, `loadModAfter=` ou `loadModBefore=`.

O sistema mantém um prontuário em `player:getModData().Antibodies.medicalFile`. A cada minuto ele
mede condição física, nutrição, temperatura, estado dos 17 membros, ferimentos, infecções,
tratamentos, sangue e sujeira; soma esses efeitos à curva de anticorpos e retrocede o relógio da
infecção quando a resposta imune supera a progressão viral. O prontuário, o namespace de sandbox
`lgd_antibodies_194_*` e o módulo de rede `lgd_antibodies` foram preservados para compatibilidade de
save e de configuração com o Antibodies 1.97 standalone.

## Multiplayer e servidor dedicado

- Em SP, somente o cliente local atualiza o prontuário. Em MP, `AntibodiesClient.ensureInitialization`
  impede a simulação client-side e somente `AntibodiesServer` calcula progressão e cura.
- O servidor não aceita nenhum comando de estado vindo do cliente. A única mensagem ativa é
  `shareMedicalFile`, enviada pelo servidor ao próprio jogador e a jogadores em um raio de 8 tiles
  para alimentar a UI de diagnóstico.
- Os cinco tratamentos (`ISApplyBandage`, `ISDisinfect` e três cataplasmas) chamam primeiro o
  `:complete()` vanilla no servidor. O upstream descartava o booleano retornado e aplicava o bônus
  do Antibodies até quando o vanilla retornava `false`; o bundle agora só registra o tratamento
  após sucesso e devolve o mesmo resultado ao `NetTimedAction`.
- A UI de outro paciente não cria mais um prontuário autoritativo no cliente quando os dados ainda
  não chegaram; o botão aparece apenas após existir o snapshot enviado pelo servidor.

Conclusão estática: a divisão de autoridade é adequada e não há payload client-trusted capaz de
curar, alterar a curva ou fabricar tratamentos. A execução real dentro do jogo/servidor dedicado
continua necessária para validar UI, persistência e sincronização sob carga.

## Colisões cruzadas

- `ISHealthPanel` também é tocado por `burris-quality-of-life`, mas em métodos diferentes:
  Antibodies envolve `createChildren`, `update`, `onGainJoypadFocus` e `onJoypadDown`; BQoL envolve
  `doBodyPartContextMenu`, `getDamagedParts` e `setOtherPlayer`. Sem conflito e sem ordem necessária.
- `mini-health-panel` instancia as mesmas cinco classes de tratamento, mas não sobrescreve seus
  métodos; suas ações passam normalmente pelos wrappers do Antibodies.
- `ISCharacterInfoWindow.createChildren` e os cinco pares `perform`/`complete` das TimedActions são
  superfícies novas ocupadas no pacote. Todos os wrappers capturam antes e chamam adiante.
- O módulo de rede `lgd_antibodies`, o modData `Antibodies` e o namespace de sandbox
  `lgd_antibodies_194_*` são exclusivos entre os módulos bundled atuais.

## Tradução

Os JSONs PT-BR novos cobrem exatamente as mesmas 85 chaves de UI e 149 chaves de sandbox do EN.
Os fallbacks nativos EN foram restaurados e corrigidos (incluindo a tabela incorreta
`UI_Antibodies_EN`, agora `UI_EN`) porque `getText()` não lê JSON. Ver
`TRANSLATION_PTBR.md` para a limitação de exibição nativa já conhecida no pacote.

## Verificação possível neste ambiente

Todos os Lua e os dois arquivos nativos de tradução passam em `luac5.1 -p`; todos os 16 JSONs são
válidos; os conjuntos EN/PTBR batem por família; os caminhos `require` alterados existem na
instalação vanilla local; e as duas ferramentas globais do pacote passam limpas. O jogo não é
executável por este fluxo, portanto teste funcional client + dedicated permanece pendente.
