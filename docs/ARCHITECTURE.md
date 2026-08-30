# Lascivious Scripts — Arquitetura, Metodologia de Integração e Manutenção

**Documento canônico para Codex / Claude / qualquer agente que altere o pacote**  
**Projeto:** Lascivious Scripts  
**Alvo atual:** Project Zomboid Build 42.20.x  
**Workshop atual:** `3788475731`  
**Mod principal atual:** `LasciviousScripts`  
**Data-base deste documento:** 2026-08-25

---

## 0. Regra de uso deste documento

Antes de integrar, atualizar, remover ou corrigir qualquer mod dentro do **Lascivious Scripts**, o agente deve ler este documento inteiro e tratá-lo como a regra arquitetural do projeto.

Este documento existe para impedir que o pacote vire um único diretório enorme de arquivos misturados, com código de origens diferentes, conflitos difíceis de localizar, traduções espalhadas e atualizações que exijam redescobrir manualmente o que foi alterado meses antes.

A prioridade do projeto é, nesta ordem:

1. **manutenção previsível**;
2. **isolamento entre mods importados**;
3. **facilidade para atualizar um único mod sem afetar os demais**;
4. **compatibilidade com Linux e servidor dedicado**;
5. **preservação do comportamento original do mod, salvo mudanças deliberadas**;
6. **tradução PT-BR e breve revisão de todo conteúdo incorporado**;
7. **rastreabilidade completa da origem e das alterações locais**;
8. **uma única distribuição pelo Steam Workshop sempre que possível**.

---

# 1. Decisão arquitetural principal

## 1.1. O Lascivious Scripts deve ser um único item do Workshop, mas NÃO precisa ser um único Mod ID do Project Zomboid

O Project Zomboid Build 42 permite oficialmente que um único item do Workshop contenha vários mods em:

```text
Contents/mods/
```

Portanto, a arquitetura recomendada é:

> **um único Workshop Item contendo vários submods isolados, um para cada mod externo incorporado, mais o núcleo autoral `LasciviousScripts`.**

Isso é melhor do que despejar o conteúdo de vinte mods diferentes dentro do mesmo `media/`.

A vantagem fundamental é que a organização física do próprio Project Zomboid passa a ser usada como fronteira arquitetural.

Exemplo:

```text
LasciviousScripts/
├── Contents/
│   └── mods/
│       ├── LasciviousScripts/
│       ├── LS_DurableToolsWeapons/
│       ├── LS_BurrisQOL/
│       ├── LS_SkullyFasterAttack/
│       ├── LS_ResponsivePivoting/
│       ├── LS_BetterPush/
│       ├── LS_Antibodies/
│       └── ...
├── workshop.txt
└── preview.png
```

Do ponto de vista do Steam, continua sendo **um download**. Do ponto de vista do PZ, cada componente continua isolado em seu próprio Mod ID.

### Por que esta é a arquitetura preferida

Se todos os mods forem fundidos em um único `Contents/mods/LasciviousScripts/42/media/`, surgem rapidamente problemas como:

- arquivos `Client.lua`, `Server.lua`, `Core.lua`, `UI.lua` de origens diferentes no mesmo domínio;
- vários `sandbox-options.txt` que precisam ser fundidos manualmente;
- arquivos de tradução com mesmo nome;
- texturas com nomes genéricos;
- scripts de itens e receitas difíceis de atribuir à origem;
- overrides de arquivos vanilla misturados;
- atualização de um mod exigindo descobrir manualmente quais arquivos pertenciam a ele;
- dificuldade para comparar a versão integrada com a versão nova do upstream;
- maior risco de apagar uma alteração de outro módulo durante uma atualização.

Com um submod por upstream, a pergunta **“quais arquivos pertencem ao mod X?”** normalmente é respondida pelo próprio caminho da pasta.

---

# 2. Arquitetura em camadas

O projeto deve ser entendido em três camadas diferentes.

## Camada A — pacote Workshop

É o repositório completo do Lascivious Scripts.

```text
LasciviousScripts/
```

Esta camada contém documentação, ferramentas, fontes originais para comparação e o `Contents/` que será publicado.

## Camada B — submods do Project Zomboid

Cada mod incorporado fica isolado em:

```text
Contents/mods/<BundledModID>/
```

Exemplo:

```text
Contents/mods/LS_BetterPush/
```

O núcleo autoral pequeno e coeso permanece em:

```text
Contents/mods/LasciviousScripts/
```

Um ecossistema autoral grande, com identidade persistente e APIs próprias já usadas em produção,
pode manter uma fronteira de submod própria. A exceção atual e deliberada é:

```text
Contents/mods/LasciviousSystems/
```

Essa fronteira preserva o Mod ID, os namespaces de rede/ModData/Sandbox e a capacidade de desligar
o ecossistema sem misturar Loja, Facções, Kits e zonas ao core TimeVote/ZombieDecay. Ambos continuam
dentro do mesmo item do Workshop.

## Camada C — módulos internos do código autoral

Somente funcionalidades que são realmente parte do código autoral do Lascivious Scripts devem compartilhar o namespace interno:

```text
media/lua/shared/LasciviousScripts/<ModuleKey>/
media/lua/client/LasciviousScripts/<ModuleKey>/
media/lua/server/LasciviousScripts/<ModuleKey>/
```

A estrutura atual de `TimeVote` e `ZombieDecay` já segue uma boa base para essa camada.

---

# 3. Estrutura canônica do repositório

A estrutura de trabalho recomendada daqui em diante é:

```text
LasciviousScripts/
├── Contents/
│   └── mods/
│       ├── LasciviousScripts/
│       │   ├── common/
│       │   │   └── media/
│       │   └── 42/
│       │       ├── mod.info
│       │       ├── icon.png
│       │       ├── poster.png
│       │       └── media/
│       │
│       ├── LasciviousSystems/
│       │   ├── common/
│       │   │   └── media/
│       │   └── 42/
│       │       ├── mod.info
│       │       ├── icon.png
│       │       ├── poster.png
│       │       └── media/
│       │
│       ├── LS_<ModuleA>/
│       │   ├── common/
│       │   │   └── media/
│       │   └── 42/
│       │       ├── mod.info
│       │       ├── poster.png
│       │       └── media/
│       │
│       ├── LS_<ModuleB>/
│       │   └── ...
│       └── ...
│
├── vendor/
│   ├── <module-a>/
│   │   ├── manifest.yml
│   │   ├── upstream/
│   │   ├── INTEGRATION.md
│   │   ├── LOCAL_CHANGES.md
│   │   └── TRANSLATION_PTBR.md
│   └── <module-b>/
│       └── ...
│
├── docs/
│   ├── ARCHITECTURE.md
│   ├── MODULE_REGISTRY.md
│   ├── COLLISION_REGISTRY.md
│   ├── SERVER_MOD_ORDER.md
│   └── modules/
│       ├── <module-a>.md
│       └── <module-b>.md
│
├── tools/
│   ├── validate_structure.py
│   ├── audit_collisions.py
│   ├── hash_module.py
│   └── generate_server_mods.py
│
├── .gitignore
├── README.md
├── workshop.txt
└── preview.png
```

## 3.1. Por que `vendor/`, `docs/` e `tools/` ficam fora de `Contents/`

No fluxo oficial de Workshop do Project Zomboid, o conteúdo jogável fica sob `Contents/mods/`. Arquivos auxiliares no nível superior do projeto podem ser usados para documentação, fontes, scripts e recursos de desenvolvimento sem fazer parte do conteúdo carregado pelo jogo.

Essa separação é intencional:

- `Contents/` = produto executado pelo PZ;
- `vendor/` = memória da origem;
- `docs/` = conhecimento do projeto;
- `tools/` = automação de manutenção.

Nunca usar `Contents/` como depósito de documentação, ZIPs originais, capturas, PSDs, dumps ou ferramentas.

---

# 4. Estrutura obrigatória de cada submod no Build 42

Cada submod deve ter ao menos:

```text
Contents/mods/<ModID>/
├── common/
└── 42/
    ├── mod.info
    └── media/
```

O diretório `common/` deve existir mesmo quando vazio.

Regra local do projeto:

> **Todo submod inserido no Lascivious Scripts deve possuir `common/`.**

O conteúdo deve ficar por padrão no diretório `42/` até existir uma razão concreta para movê-lo para `common/`.

## 4.1. Uso do `common/`

O Build 42 carrega primeiro o conteúdo de `common/` e depois a pasta de versão compatível, que pode sobrescrever o conteúdo comum.

Usar `common/` principalmente para assets grandes e comprovadamente independentes da versão, por exemplo:

- modelos;
- algumas texturas;
- animações realmente idênticas entre versões.

### Regra de segurança

Não mover automaticamente arquivos de um mod importado para `common/` apenas para “organizar”.

A primeira integração deve priorizar fidelidade ao upstream. Otimizações estruturais podem ser realizadas depois, com teste específico.

---

# 5. Padrão de identificação

Cada mod integrado recebe três identificadores diferentes.

## 5.1. `module_key`

Identificador interno do repositório.

Exemplo:

```text
better-push
```

Regras:

- minúsculo;
- ASCII;
- `kebab-case`;
- nunca reutilizado por outro mod.

## 5.2. `bundled_mod_id`

Mod ID do Project Zomboid usado dentro do pacote.

Exemplo:

```text
LS_BetterPush
```

Regra preferida:

```text
LS_<NomeCurtoUnico>
```

## 5.3. Nome humano

Nome exibido no Mod Manager.

Exemplo:

```text
Lascivious Scripts — Better Push
```

---

# 6. Não renomear identificadores persistentes do upstream sem necessidade

Uma distinção importantíssima deve ser mantida:

- **Mod ID do PZ** pode ser adaptado para a distribuição bundled;
- **IDs internos usados por itens, receitas, veículos, traits, perks, modelos ou dados persistidos** normalmente NÃO devem ser renomeados.

Exemplos de coisas que podem quebrar saves ao serem renomeadas:

```text
OriginalModule.ItemName
OriginalModule.VehiclePart
OriginalModule.RecipeName
OriginalTraitId
OriginalPerkId
```

Se o mod já foi utilizado no save do servidor, preservar seus IDs internos é a opção padrão.

Só realizar migração de IDs quando existir um plano explícito para converter dados antigos.

---

# 7. Namespace do código autoral

Para módulos realmente escritos para o Lascivious Scripts, usar sempre:

```lua
LasciviousScripts = LasciviousScripts or {}
LasciviousScripts.ModuleName = LasciviousScripts.ModuleName or {}
```

E arquivos em:

```text
media/lua/shared/LasciviousScripts/ModuleName/
media/lua/client/LasciviousScripts/ModuleName/
media/lua/server/LasciviousScripts/ModuleName/
```

Padrão recomendado para módulos mais complexos:

```text
ModuleName/
├── Core.lua
├── Config.lua
├── Network.lua
├── Compat.lua
├── Overrides.lua
├── UI.lua
├── Client.lua
└── Server.lua
```

Nem todo módulo precisa de todos os arquivos.

## Responsabilidades

### `Core.lua`

- constantes;
- funções puras;
- cálculos compartilhados;
- versão do protocolo;
- estruturas comuns.

Evitar registrar eventos em `Core.lua`.

### `Client.lua`

- entrypoint client-side;
- `Events.*.Add` do cliente;
- comandos recebidos do servidor;
- integração com UI e renderização.

### `Server.lua`

- autoridade de servidor;
- validação de comandos;
- persistência;
- regras de multiplayer;
- eventos server-side.

### `Network.lua`

- nomes dos módulos de rede;
- comandos;
- payloads;
- validação comum.

### `Compat.lua`

- compatibilidade com outros mods;
- detecção de APIs opcionais;
- adapters.

### `Overrides.lua`

Somente patches deliberados de funções vanilla ou de terceiros.

Todo override deve explicar:

1. o que está sendo sobrescrito;
2. por quê;
3. qual Build foi estudada;
4. como detectar se o upstream mudou;
5. risco de conflito.

---

# 8. Regra absoluta: não depender de ordem acidental de carregamento de arquivos Lua

Quando um arquivo depende de outro, utilizar `require` explicitamente.

Exemplo:

```lua
require "LasciviousScripts/TimeVote/Core"
```

Não assumir que `A.lua` será executado antes de `B.lua` apenas por nome ou posição de pasta.

Arquivos de biblioteca devem preferencialmente ser idempotentes e seguros caso sejam requeridos mais de uma vez.

---

# 9. Arquivos e caminhos controlados pelo engine não podem ser “organizados” livremente

A organização interna deve respeitar como o Project Zomboid procura cada tipo de recurso.

## 9.1. Lua

Pode e deve ser organizado por subpastas.

Exemplo:

```text
media/lua/client/LasciviousScripts/TimeVote/
```

## 9.2. Texturas e UI próprias

Para conteúdo autoral novo, usar nomes ou caminhos claramente namespaced.

Exemplo:

```text
media/textures/LasciviousScripts/TimeVote/ls_timevote_speed_fast.png
```

ou, quando o código/API exigir busca por nome simples, usar prefixo:

```text
ls_timevote_speed_fast.png
```

Não deixar novos assets com nomes genéricos como:

```text
icon.png
button.png
background.png
user.png
```

quando esses nomes forem usados no `media` global de um submod monolítico.

## 9.3. AnimSets e overrides vanilla

Arquivos que sobrescrevem caminhos vanilla são exceção.

Exemplo real do projeto atual:

```text
media/AnimSets/zombie/lunge/defaultlunge.xml
```

Eles precisam permanecer exatamente no caminho esperado pelo jogo.

Não mover para:

```text
media/AnimSets/LasciviousScripts/ZombieDecay/...
```

se a finalidade for substituir o AnimSet vanilla.

### REGRA CRÍTICA PARA LINUX

Linux e macOS tratam diferenças entre maiúsculas e minúsculas como caminhos diferentes.

Portanto:

```text
AnimSets
animsets
ANIMSETS
```

não são equivalentes.

A grafia deve corresponder exatamente à estrutura esperada pelo PZ e pelo recurso referenciado.

Nunca “normalizar” a capitalização de um caminho sem verificar o caminho efetivamente solicitado pelo jogo.

## 9.4. Scripts de itens, receitas, veículos etc.

Preservar IDs internos do upstream.

É permitido reorganizar nomes de arquivos somente quando comprovadamente seguro, mas a regra padrão durante importação é:

> manter a estrutura do upstream o mais próxima possível.

Isso reduz o delta local e facilita atualizações futuras.

## 9.5. Models, clothing, maps, sound, texturepacks e outros formatos

Não aplicar uma regra genérica de movimentação.

Cada mecanismo de assets possui convenções próprias do PZ. Antes de mover qualquer arquivo, verificar se o caminho é referenciado por:

- script;
- XML;
- Lua;
- `mod.info`;
- pack/tiledef;
- modelo;
- animação;
- código Java/engine.

---

# 10. Arquivos globais e colisões

Dentro de um submod, alguns arquivos ocupam posições especiais e não podem simplesmente existir várias vezes com o mesmo caminho.

Exemplos:

```text
mod.info
media/sandbox-options.txt
media/lua/shared/Translate/PTBR/UI_PTBR.txt
media/lua/shared/Translate/PTBR/Sandbox_PTBR.txt
```

Por isso, a estratégia de **um submod por upstream** é importante: ela reduz drasticamente a necessidade de fundir arquivos sem relação.

Mesmo assim, colisões entre submods ou com vanilla podem existir e devem ser registradas.

---

# 11. Registro obrigatório de colisões

Manter:

```text
docs/COLLISION_REGISTRY.md
```

Toda integração deve verificar e registrar no mínimo:

- mesmo Mod ID;
- mesmo caminho relativo de override;
- mesmo global Lua;
- mesmo nome de módulo de rede;
- mesmo Sandbox namespace;
- mesmo Item ID;
- mesmo Recipe ID;
- mesmo Vehicle ID;
- mesmo Trait/Perk ID;
- mesmo texture/model identifier;
- mesmo `tiledef`;
- mesmo `pack`;
- override da mesma função vanilla;
- override do mesmo arquivo vanilla.

Formato sugerido:

```text
| Recurso | Módulo A | Módulo B | Tipo | Resolução | Testado |
```

Nenhuma colisão deve ser resolvida silenciosamente.

---

# 12. `vendor/`: memória do upstream

Para cada mod de terceiros deve existir:

```text
vendor/<module_key>/
```

Exemplo:

```text
vendor/better-push/
```

Conteúdo:

```text
vendor/better-push/
├── manifest.yml
├── upstream/
├── INTEGRATION.md
├── LOCAL_CHANGES.md
└── TRANSLATION_PTBR.md
```

## 12.1. `upstream/`

Deve conter uma cópia **prístina** da versão original utilizada como base.

Nunca editar arquivos dentro de `vendor/<module>/upstream/` para adequá-los ao Lascivious Scripts.

O objetivo é permitir esta comparação futura:

```text
upstream antigo
        ↓
upstream novo
        ↓
quais mudanças vieram do upstream?
```

Separadamente:

```text
upstream antigo
        ↓
versão bundled
        ↓
quais mudanças são nossas?
```

Com Git, o snapshot anterior fica preservado no histórico.

Para mods muito grandes, considerar Git LFS para binários pesados.

---

# 13. Manifesto obrigatório de cada módulo

Cada módulo deve possuir:

```text
vendor/<module_key>/manifest.yml
```

Modelo:

```yaml
schema: 1
module_key: better-push
name: Better Push
bundled_mod_id: LS_BetterPush
status: enabled

upstream:
  workshop_id: "0000000000"
  original_mod_id: "OriginalModID"
  version: "unknown"
  imported_at: "2026-08-25"
  source_path: "vendor/better-push/upstream"

compatibility:
  target_build: "42.20.x"
  multiplayer: true
  dedicated_server: true
  save_sensitive: false

dependencies:
  required: []
  optional: []
  incompatible: []

integration:
  ptbr: complete
  reviewed: true
  local_changes: true
  local_revision: 1
  notes: "vendor/better-push/LOCAL_CHANGES.md"

risk:
  overrides_vanilla_files: false
  monkey_patches: false
  java: false
  maps: false
  tiledefs: false
  network_protocol: false
```

O agente deve atualizar esse arquivo em toda atualização relevante.

---

# 15. `LOCAL_CHANGES.md`: nunca perder o delta local

Cada mod incorporado que for alterado deve possuir uma lista objetiva de alterações locais.

Exemplo:

```markdown
# Local Changes — Better Push

## LS-001
Tipo: compatibilidade
Arquivo: 42/media/lua/client/...
Motivo: compatibilidade com B42.20 multiplayer.
Mudança: ...

## LS-002
Tipo: tradução
Arquivos: Translate/PTBR/...
Motivo: tradução completa e revisão de terminologia.

## LS-003
Tipo: servidor
Arquivo: ...
Motivo: remover comportamento inadequado para servidor dedicado.
```

Toda alteração nossa deve conseguir responder:

- **o que mudou?**
- **por que mudou?**
- **em qual arquivo?**
- **o upstream também mudou isso depois?**
- **a mudança ainda é necessária?**

---

# 16. Regra de delta mínimo

Ao importar um mod externo:

> **alterar o mínimo possível fora dos requisitos do Lascivious Scripts.**

Evitar “refatorar por estética” código upstream durante a primeira integração.

Razão: quanto maior o delta local, mais difícil será aplicar futuras atualizações do upstream.

Mudanças aceitáveis na integração inicial:

- adaptação indispensável para Build 42.20.x;
- correção de bug comprovado;
- compatibilidade multiplayer/dedicated;
- mudança explicitamente desejada para o servidor;
- remoção de dependência que será substituída de forma equivalente;
- namespace necessário para impedir conflito;
- tradução PT-BR;
- revisão textual;
- instrumentação de debug que fique desativada em produção.

Mudanças cosméticas sem benefício real devem ser evitadas.

---

# 17. Fluxo obrigatório para integrar um mod novo

O agente deve executar as etapas nesta ordem.

## Fase 1 — inventário

1. identificar Workshop ID;
2. identificar Mod ID original;
3. identificar versão/build alvo;
4. listar todos os arquivos;
5. identificar dependências;
6. identificar incompatibilidades;
7. identificar arquivos que sobrescrevem vanilla;
8. procurar checks de Mod ID;
9. procurar globals Lua;
10. procurar comandos client/server;
11. procurar sandbox options;
12. procurar traduções;
13. procurar item/recipe/vehicle/trait/perk IDs;
14. procurar Java/JAR;
15. procurar maps/tiledefs/packs;
16. procurar manipulação de save/modData/globalModData.

## Fase 2 — gate

Antes de copiar para `Contents/`, responder:

- Build compatível?
- funciona em multiplayer?
- depende de outro mod?
- colide com algum módulo já bundled?
- possui IDs persistentes que precisam ser preservados?
- depende de seu Mod ID original?
- outros mods externos detectam seu Mod ID?

Se houver dúvida estrutural, parar e documentar antes de integrar.

## Fase 3 — snapshot upstream

Copiar a versão original sem alterações para:

```text
vendor/<module_key>/upstream/
```

Criar o manifesto.

## Fase 4 — criação do submod bundled

Criar:

```text
Contents/mods/LS_<Module>/common/
Contents/mods/LS_<Module>/42/
```

Copiar a estrutura funcional do upstream para o submod.

## Fase 5 — adaptação

Aplicar apenas alterações necessárias.

Registrar cada alteração relevante em:

```text
vendor/<module_key>/LOCAL_CHANGES.md
```

## Fase 6 — tradução PT-BR

Todo texto exposto ao jogador deve ser auditado.

No mínimo:

- UI;
- context menu;
- tooltips;
- nomes de itens;
- receitas;
- sandbox options;
- mensagens do chat;
- erros exibidos ao jogador;
- textos de confirmação;
- labels;
- nomes de categorias;
- descrições.

## Fase 7 — revisão curta

A tradução não deve ser apenas literal.

Revisar:

- português natural;
- termos já usados no PZ PT-BR;
- consistência entre singular/plural;
- acentos;
- placeholders `%1`, `%2` etc.;
- tags `<LINE>`, `<BR>` e equivalentes;
- quebras de linha;
- textos técnicos que não devem ser traduzidos.

## Fase 8 — validação estática

Executar o checklist da seção de validação.

## Fase 9 — teste no PZ

Testar ao menos:

- inicialização client;
- inicialização servidor dedicado;
- jogador entrando;
- jogador saindo;
- funcionalidade principal;
- reload/restart quando aplicável;
- ausência de erros novos em console/server logs;
- tradução PT-BR;
- interação com os módulos já existentes.

## Fase 10 — commit isolado

Uma integração de mod deve preferencialmente ocorrer em um commit próprio.

Exemplo:

```text
feat(bundle): integrate Better Push upstream 1.4.2
```

Nunca misturar uma integração nova com correções aleatórias em cinco outros módulos.

---

# 18. Fluxo obrigatório para atualizar um mod já incorporado

Esta é a parte mais importante da metodologia.

## Nunca fazer

Não substituir cegamente a pasta bundled pela nova versão do Workshop.

Isso apagaria:

- traduções;
- compat patches;
- correções locais;
- alterações para B42.20;
- adaptações para servidor;
- namespaces;
- documentação.

## Processo correto

### Etapa 1 — obter o upstream novo em área temporária

Exemplo:

```text
/tmp/better-push-new/
```

Nunca copiar diretamente por cima de `Contents/`.

### Etapa 2 — comparar upstream antigo com upstream novo

Comparar:

```text
vendor/better-push/upstream/  <->  /tmp/better-push-new/
```

Classificar mudanças:

- arquivo novo;
- arquivo removido;
- arquivo renomeado;
- código alterado;
- assets alterados;
- tradução alterada;
- nova dependência;
- novo override;
- mudança de Mod ID;
- mudança de item/recipe IDs;
- mudança de protocolo multiplayer.

### Etapa 3 — ler `LOCAL_CHANGES.md`

Antes de aplicar o update, o agente deve reler todas as alterações locais já existentes.

### Etapa 4 — aplicar update na cópia bundled de forma consciente

Para cada arquivo alterado pelo upstream, verificar se ele também possui mudança local.

Classificação:

```text
UPSTREAM_ONLY
LOCAL_ONLY
BOTH_CHANGED
UNCHANGED
```

`BOTH_CHANGED` exige merge manual/revisado.

### Etapa 5 — verificar se patches locais ficaram obsoletos

Às vezes o upstream já corrigiu o problema que nós corrigíamos.

Nesse caso, remover nosso patch em vez de mantê-lo em duplicidade.

### Etapa 6 — atualizar PT-BR

Comparar novas strings EN/upstream com PT-BR.

Nenhuma string nova deve ficar silenciosamente sem tradução quando puder ser traduzida.

### Etapa 7 — atualizar snapshot pristine

Somente depois do merge concluído, substituir:

```text
vendor/<module>/upstream/
```

pela nova base pristine.

### Etapa 8 — atualizar manifesto

Atualizar ao menos:

- versão upstream;
- data de importação;
- Build alvo;
- dependências;
- riscos;
- status de tradução;
- revisão local.

### Etapa 9 — teste completo do módulo

Executar testes funcionais e de integração.

### Etapa 10 — commit isolado

Exemplo:

```text
chore(bundle): update Better Push 1.4.2 -> 1.5.0
```

---

# 19. Tradução PT-BR — política oficial do Lascivious Scripts

Todo mod incorporado será:

1. traduzido para PT-BR quando houver texto traduzível;
2. brevemente revisado;
3. mantido em sincronização nas atualizações seguintes.

## 19.1. Não apagar inglês

Quando possível, manter EN como fallback e adicionar PTBR.

## 19.2. Preservar famílias de tradução do PZ

O Project Zomboid utiliza famílias reconhecíveis de traduções, como:

```text
UI_PTBR.txt
IG_UI_PTBR.txt
ContextMenu_PTBR.txt
Tooltip_PTBR.txt
ItemName_PTBR.txt
Recipes_PTBR.txt
Sandbox_PTBR.txt
Moodles_PTBR.txt
```

Não inventar nomes incompatíveis apenas para organizar.

A organização por mod já é fornecida pela fronteira do submod.

## 19.3. Chaves

Não alterar chaves só para “ficarem bonitas”.

Se for código novo do Lascivious Scripts, usar prefixo próprio dentro da família correta.

Exemplo:

```text
UI_LS_TimeVote_Title
Tooltip_LS_TimeVote_...
Sandbox_LasciviousScriptsTimeVote_...
```

## 19.4. JSON e TXT

O projeto atual possui exemplos de Sandbox em JSON e TXT.

Não converter automaticamente o formato de um mod importado. Preservar o formato compatível com a Build e com a implementação atual, salvo motivo documentado.

Para PT-BR nativo, nunca colocar caracteres acentuados diretamente no literal Lua do `.txt`: neste
ambiente eles podem ser carregados como `?`. Manter o catálogo legível em `PTBR/Sandbox.json` e gerar
`PTBR/Sandbox_PTBR.txt` com `tools/generate_ptbr_sandbox_native.py`. O gerador representa cada byte
UTF-8 não ASCII com escape decimal Lua de três dígitos, produzindo uma fonte ASCII que reconstrói a
string UTF-8 correta em execução.

Toda geração deve ser seguida por:

1. paridade exata entre as chaves EN, JSON PTBR e TXT PTBR;
2. confirmação de que o TXT contém apenas bytes ASCII;
3. `luac5.1 -p` em cada arquivo gerado;
4. carregamento real pelo Lua 5.1 e comparação byte a byte dos valores reconstruídos com o JSON.

## 19.5. Revisão obrigatória após update

Se o upstream alterar arquivos EN, procurar diferenças correspondentes em PTBR.

---

# 20. Mod ID original versus Mod ID bundled

Mudar o Mod ID pode quebrar código que faça verificações como:

```lua
getActivatedMods():contains("OriginalModID")
```

ou integrações de terceiros que procurem especificamente o Mod ID original.

Por isso, todo módulo precisa ser classificado.

## Categoria A — independente de Mod ID

Pode receber `LS_<Nome>` com baixo risco.

## Categoria B — o próprio código verifica o Mod ID original

Adaptar conscientemente o check para aceitar o bundled ID.

Registrar em `LOCAL_CHANGES.md`.

## Categoria C — outros mods externos dependem de detectar o Mod ID original

Exige decisão arquitetural específica.

Possíveis soluções:

- preservar o Mod ID original dentro do bundle;
- criar compatibilidade explícita;
- manter o mod original externo;
- não incorporar esse mod.

### Atenção

Preservar o mesmo Mod ID do upstream pode causar colisão se um jogador possuir simultaneamente uma cópia standalone reconhecida pelo jogo.

Portanto, essa escolha nunca deve ser automática.

---

# 21. Dependências

Cada módulo deve declarar no manifesto:

```text
required
optional
incompatible
```

O agente deve procurar dependências tanto no `mod.info` quanto no código.

Exemplos de dependência escondida:

- `require "SomeFramework/..."`;
- `getActivatedMods()`;
- uso de global criado por outro mod;
- chamada de API de framework;
- texture/model de outro mod;
- script ID externo;
- item usado em receita;
- eventos customizados.

## Política

Uma dependência pode ser:

1. mantida externa;
2. incorporada também ao mesmo Workshop item, se permitido;
3. substituída por adapter próprio, se tecnicamente seguro;
4. eliminada com refatoração documentada.

Nunca “sumir” com uma dependência sem provar que o comportamento equivalente foi preservado.

---

# 22. Ordem de carregamento

Submods que dependem de ordem devem registrar:

- `require`;
- `loadModAfter`;
- `loadModBefore`;
- ordem do servidor.

Manter uma lista canônica em:

```text
docs/SERVER_MOD_ORDER.md
```

E uma fonte estruturada no registro dos módulos.

Um script `tools/generate_server_mods.py` pode gerar a string esperada para o servidor.

Exemplo conceitual:

```text
Mods=LasciviousScripts;LS_Antibodies;LS_BetterPush;LS_ClimbLadders;...
```

A ordem não deve ficar apenas “na cabeça” de quem configurou o servidor.

---

# 23. Um Workshop Item, vários Mod IDs

No servidor, separar mentalmente:

## Workshop ID

Responsável pelo download do pacote.

```text
WorkshopItems=3788475731
```

## Mod IDs

Responsáveis pelos componentes ativados pelo PZ.

Exemplo conceitual:

```text
Mods=LasciviousScripts;LS_BetterPush;LS_Antibodies;LS_ClimbLadders
```

Isso entrega o benefício desejado:

> **um pacote baixado pelo jogador, conteúdo internamente modular.**

Se um submod precisar ser desativado emergencialmente, ele pode ser removido da lista `Mods=` sem desmontar o restante do Workshop item.

---

# 24. Versionamento

Existem três versões diferentes e elas não devem ser confundidas.

## 24.1. Versão do pacote

Exemplo:

```text
Lascivious Scripts 1.4.0
```

Representa o bundle inteiro.

## 24.2. Versão do módulo upstream

Exemplo:

```text
Better Push 1.5.0
```

Registrada no manifesto.

## 24.3. Revisão local

Exemplo:

```text
local_revision: 3
```

É incrementada quando nós alteramos o módulo sem mudança upstream.

---

# 25. Git é parte da arquitetura

O projeto deve ser mantido em Git.

## Regras

- um mod novo por commit, salvo razão forte;
- um update de mod por commit;
- não misturar update upstream com refatoração global;
- releases do bundle devem receber tag;
- alterações delicadas devem usar branch dedicada.

Exemplos:

```text
feature/integrate-better-push
update/better-push-1.5.0
fix/timevote-vanilla-reset
release/1.4.0
```

Tags:

```text
ls-v1.4.0
```

O objetivo é tornar possível responder em segundos:

```text
quando este arquivo entrou?
quem o alterou?
por que mudou?
qual era a versão anterior?
```

---

# 26. Validação estática obrigatória

Antes de liberar qualquer alteração, executar auditoria automática ou manual equivalente.

## 26.1. Estrutura

Verificar:

- `common/` presente em cada submod B42;
- `42/mod.info` presente;
- `42/media/` quando necessário;
- IDs únicos;
- caminhos com capitalização correta;
- ausência de arquivos temporários;
- ausência de ZIPs dentro de `Contents/`;
- ausência de `.bak`, `.old`, `.tmp` no runtime.

## 26.2. Lua

Procurar:

- globals novos não intencionais;
- `require` quebrado;
- caminhos com case incorreto;
- comandos de rede duplicados;
- `Events.*.Add` duplicados;
- patches vanilla;
- loops por tick custosos;
- chamadas client-only no server;
- chamadas server-only no client.

## 26.3. Recursos

Procurar colisão de:

- path relativo;
- texture name;
- model name;
- script module;
- item;
- recipe;
- trait;
- perk;
- vehicle;
- sound;
- tiledef;
- pack.

## 26.4. Traduções

Verificar:

- PTBR existe quando há EN traduzível;
- placeholders preservados;
- sintaxe válida;
- aspas/escapes válidos;
- chaves duplicadas;
- strings novas sem tradução.

---

# 27. Ferramentas recomendadas

O projeto deve evoluir para possuir scripts simples de manutenção.

## `validate_structure.py`

Responsável por:

- enumerar submods;
- validar `common/`;
- ler `mod.info`;
- detectar Mod IDs duplicados;
- detectar paths com case suspeito;
- encontrar arquivos temporários.

## `audit_collisions.py`

Responsável por indexar recursos e sinalizar colisões.

## `hash_module.py`

Gerar um inventário por arquivo:

```text
relative_path | size | sha256
```

Útil para descobrir exatamente o que mudou entre versões.

## `generate_server_mods.py`

Ler o registro e gerar:

```text
Mods=...
```

na ordem canônica.

Essas ferramentas não devem modificar conteúdo automaticamente sem modo explícito.

---

# 28. Performance

Ao integrar mods pequenos, o custo individual pode parecer irrelevante. Em um bundle grande, vários pequenos custos se acumulam.

Toda integração deve procurar especialmente:

- `Events.OnTick`;
- `Events.OnPlayerUpdate`;
- scans de todos os jogadores;
- scans de todos os zumbis;
- scans de inventário inteiro por frame;
- polling de objetos do mundo;
- broadcast frequente de rede;
- serialização de tabelas grandes;
- geração recorrente de UI;
- criação de tabelas temporárias em hot path.

### Regra

Não “otimizar” automaticamente o upstream durante a primeira importação, mas registrar hot paths suspeitos para teste.

Se uma otimização local for aplicada, documentar benchmark ou motivo concreto.

---

# 29. Multiplayer e autoridade

Para mods que alteram estado relevante do jogo, identificar quem é autoridade.

Perguntas obrigatórias:

- a ação pode ser falsificada pelo cliente?
- o servidor valida distância?
- o servidor valida item/estado?
- o cliente decide recompensa?
- dados persistentes são alterados client-side?
- existe comando sem validação?

O bundle não deve transformar um mod originalmente inocente em vetor óbvio de abuso multiplayer.

Sempre preferir autoridade server-side para estado compartilhado/recompensas/regras.

---

# 30. Mods Java/JAR

Mods com código Java devem receber classificação de alto risco.

Antes de incorporar:

- verificar compatibilidade exata com B42.20.x;
- verificar instalação esperada;
- verificar se o servidor e cliente exigem o JAR;
- verificar conflitos de classes;
- verificar se o Workshop uploader distribui o formato adequadamente;
- documentar atualização separadamente.

Não tratar um mod Java como se fosse apenas outro conjunto de Lua.

---

# 31. Maps, tiledefs e packs

Mods de mapas, tiles ou texture packs exigem atenção especial porque podem possuir IDs globais e requisitos de ordem.

Antes de incorporar:

- registrar `tiledef`;
- registrar `pack`;
- verificar IDs já ocupados;
- registrar dependências de mapa;
- documentar ordem;
- testar em save novo e no cenário real antes de produção.

Não alterar IDs de tiledef em save ativo sem avaliar impacto.

---

# 32. Remoção de um módulo

Remover um módulo não é simplesmente apagar a pasta.

Antes de remover, classificar:

```text
safe_to_remove
save_sensitive
requires_migration
unknown
```

Procurar dados persistidos:

- itens existentes;
- traits;
- perks;
- veículos;
- modData;
- globalModData;
- objetos no mapa;
- receitas aprendidas;
- scripts referenciados pelo save.

Se houver risco, criar procedimento de migração.

---

# 33. Migração do servidor de mods standalone para o bundle

Para cada mod que hoje vem de um Workshop Item separado:

1. integrar e testar sua versão bundled;
2. preservar IDs persistentes quando necessário;
3. remover o Workshop ID original da configuração do servidor apenas quando o bundled estiver validado;
4. substituir o Mod ID na lista `Mods=` se ele tiver mudado;
5. garantir que cliente e servidor usem a mesma versão;
6. não manter simultaneamente duas cópias com o mesmo Mod ID;
7. validar o save em cópia de teste;
8. só depois promover para produção.

Fazer a migração em lotes pequenos, não vinte mods de uma vez.

Idealmente:

```text
2 a 4 módulos por release de migração
```

até a arquitetura estar comprovada.

---

# 34. Auditoria do Lascivious Scripts recebido neste estudo

O ZIP analisado contém atualmente **37 arquivos** e dois módulos autorais principais:

```text
LasciviousScripts.TimeVote
LasciviousScripts.ZombieDecay
```

## Pontos positivos atuais

### 1. Separação client/server/shared

A organização existente está correta conceitualmente:

```text
media/lua/client/LasciviousScripts/...
media/lua/server/LasciviousScripts/...
media/lua/shared/LasciviousScripts/...
```

### 2. Namespace Lua

Os módulos utilizam:

```lua
LasciviousScripts.TimeVote
LasciviousScripts.ZombieDecay
```

Isso deve ser preservado para código autoral.

### 3. `require` explícito

O TimeVote já usa imports claros como:

```lua
require "LasciviousScripts/TimeVote/Core"
```

Esse padrão deve continuar.

### 4. Sandbox options namespaced

Exemplos existentes:

```text
LasciviousScriptsTimeVote.*
LasciviousScriptsZombieDecay.*
```

Bom padrão para evitar colisão.

## Problemas/ajustes arquiteturais encontrados

### 34.1. Falta `common/`

No ZIP estudado existe:

```text
Contents/mods/LasciviousScripts/42/
```

mas não existe:

```text
Contents/mods/LasciviousScripts/common/
```

A documentação atual do Build 42 considera `common/` parte obrigatória da estrutura.

Criar ao menos:

```text
Contents/mods/LasciviousScripts/common/media/
```

ou manter `common/` vazio conforme o comportamento aceito pela versão alvo.

### 34.2. README dentro do runtime

Existe:

```text
Contents/mods/LasciviousScripts/TimeVote_README.md
```

Documentação de desenvolvimento deve preferencialmente ser movida para:

```text
docs/modules/time-vote.md
```

para não misturar produto executável e documentação de manutenção.

### 34.3. Assets do TimeVote possuem nomes curtos genéricos

Exemplos:

```text
tv_speed_fast.png
tv_speed_normal.png
tv_user.png
```

Não é um problema imediato, mas para um projeto que crescerá muito é preferível que assets autorais novos usem prefixo claro ou subpasta namespaced.

Não renomear os atuais sem atualizar/testar todos os consumidores.

### 34.4. AnimSets são uma área de alto risco

O `ZombieDecay` contém overrides em:

```text
media/AnimSets/zombie/...
```

Esses arquivos não podem ser movidos para a pasta do módulo apenas para organização, pois sua função depende do caminho de override.

Devem ser registrados em `COLLISION_REGISTRY.md` como overrides vanilla.

### 34.5. A capitalização de paths deve ser auditada

O projeto roda em Linux dedicado. Portanto, caminhos de assets e referências devem ser comparados byte a byte quanto a maiúsculas/minúsculas.

Especialmente em:

```text
AnimSets
Translate
lua
textures
```

### 34.6. Falta um registro central de módulos

Hoje as versões estão embutidas nos `Core.lua`, por exemplo:

```text
TimeVote 2.2.0
ZombieDecay 1.0.0
```

Isso é útil, mas não substitui um catálogo central contendo origem, status, risco e versão de todos os módulos bundled.

---

# 35. Migração recomendada da estrutura atual

Antes de começar a incorporar dezenas de mods, executar esta pequena reorganização.

## Etapa 1

Adicionar:

```text
Contents/mods/LasciviousScripts/common/
```

## Etapa 2

Criar:

```text
docs/
vendor/
tools/
```

## Etapa 3

Mover a documentação de TimeVote para:

```text
docs/modules/time-vote.md
```

## Etapa 4

Criar:

```text
docs/MODULE_REGISTRY.md
docs/COLLISION_REGISTRY.md
docs/SERVER_MOD_ORDER.md
```

## Etapa 5

Registrar os dois módulos atuais como conteúdo autoral.

## Etapa 6

Marcar todos os overrides atuais de `AnimSets` no Collision Registry.

## Etapa 7

Somente então começar a importar os mods de terceiros.

---

# 36. Modelo de registro de módulos

`docs/MODULE_REGISTRY.md` deve conter uma tabela simples para leitura humana.

Exemplo:

```text
| Key | Nome | Mod ID bundled | Upstream | Versão | PTBR | Status | Risco |
|---|---|---|---|---|---|---|---|
| time-vote | Time Vote | LasciviousScripts/Core | próprio | 2.2.0 | sim | ativo | médio |
| zombie-decay | Zombie Decay | LasciviousScripts/Core | próprio | 1.0.0 | sim | ativo | alto/AnimSets |
| better-push | Better Push | LS_BetterPush | Workshop XXXXX | 1.4 | sim | ativo | baixo |
```

O manifesto YAML é a fonte detalhada; esta tabela é o índice humano.

---

# 37. Modelo de `mod.info` para submods bundled

Exemplo conceitual:

```text
name=Lascivious Scripts - Better Push
id=LS_BetterPush
modversion=1.0.0
versionMin=42.20
poster=poster.png
```

Campos como `require`, `incompatible`, `loadModAfter`, `loadModBefore`, `pack` e `tiledef` devem ser preservados/adaptados conscientemente quando o upstream os utilizar.

---

# 38. Definition of Done para qualquer agente

Um mod só é considerado integrado quando TODOS os itens aplicáveis abaixo forem atendidos.

- [ ] upstream pristine armazenado;
- [ ] manifesto criado/atualizado;
- [ ] submod isolado criado;
- [ ] `common/` presente;
- [ ] `mod.info` correto;
- [ ] dependências auditadas;
- [ ] Mod ID checks auditados;
- [ ] IDs persistentes preservados ou migrados conscientemente;
- [ ] overrides vanilla registrados;
- [ ] conflitos analisados;
- [ ] alterações locais documentadas;
- [ ] PT-BR implementado;
- [ ] PT-BR revisado;
- [ ] placeholders de tradução preservados;
- [ ] paths/case auditados para Linux;
- [ ] client testado;
- [ ] dedicated server testado;
- [ ] multiplayer testado quando aplicável;
- [ ] logs verificados;
- [ ] módulo adicionado ao registro;
- [ ] ordem do servidor atualizada;
- [ ] commit isolado criado.

Se qualquer item crítico estiver pendente, o agente deve dizer explicitamente que a integração não está concluída.

---

# 39. Prompt operacional para Codex / Claude

Sempre que um agente receber um novo mod para incorporar, ele deve trabalhar com esta sequência mental:

```text
1. Não copie ainda.
2. Leia a arquitetura.
3. Identifique o upstream.
4. Inventarie todos os arquivos e dependências.
5. Procure colisões e IDs persistentes.
6. Guarde o upstream pristine em vendor/.
7. Crie um submod isolado em Contents/mods/.
8. Preserve a estrutura upstream sempre que possível.
9. Aplique somente os patches necessários.
10. Documente cada patch local.
11. Traduza e revise PT-BR.
12. Valide paths/case para Linux.
13. Teste client + dedicated + MP quando aplicável.
14. Atualize registro, ordem e manifesto.
15. Faça commit isolado.
```

Em uma atualização:

```text
1. Nunca sobrescreva a versão bundled diretamente.
2. Compare upstream antigo x upstream novo.
3. Compare upstream antigo x nossas alterações.
4. Faça merge consciente.
5. Revise se patches locais ainda são necessários.
6. Atualize PT-BR.
7. Teste.
8. Só então substitua o snapshot pristine e finalize o commit.
```

---

# 40. O princípio que deve ser preservado acima de todos os outros

O Lascivious Scripts não deve ser tratado como uma pasta onde mods são “copiados para dentro”.

Ele deve ser tratado como uma **distribuição versionada de componentes**, com:

- origem conhecida;
- fronteira clara;
- versão conhecida;
- delta local conhecido;
- traduções conhecidas;
- dependências conhecidas;
- conflitos conhecidos;
- processo de atualização repetível.

Se daqui a um ano for necessário atualizar apenas **Better Push**, o mantenedor deve conseguir abrir:

```text
vendor/better-push/
Contents/mods/LS_BetterPush/
```

ler o manifesto e o `LOCAL_CHANGES.md`, comparar a nova versão e atualizar aquele componente sem precisar vasculhar todo o restante do Lascivious Scripts.

Se esta propriedade for mantida, o pacote continuará administrável mesmo com dezenas de mods incorporados.

---

# 41. Referências técnicas consultadas

- PZwiki — Mod structure: `https://pzwiki.net/wiki/Mod_structure`
- PZwiki — Modding / recursos relacionados: `https://pzwiki.net/wiki/Modding`
- Project Zomboid Community Modding template: `https://github.com/Project-Zomboid-Community-Modding/pzmc-template`
- The Indie Stone — traduções oficiais: `https://github.com/TheIndieStone/ProjectZomboidTranslations`

A documentação externa deve ser revalidada quando o servidor mudar de branch principal ou quando uma nova Build alterar a estrutura de mods.

---

# 42. Decisão final desta arquitetura

**Adotar daqui em diante:**

```text
1 Workshop Item
    └── vários submods isolados em Contents/mods/
            ├── núcleo autoral LasciviousScripts
            ├── ecossistema autoral persistente LasciviousSystems
            └── 1 submod por mod externo incorporado
```

Com:

```text
vendor/<mod>/upstream        = cópia original/pristine
docs/modules/<mod>.md        = documentação
LOCAL_CHANGES.md             = nossos patches
manifest.yml                 = origem/versão/status
git                          = histórico
PTBR                         = obrigatório para conteúdo traduzível
```

Esta é a arquitetura canônica recomendada para o crescimento do Lascivious Scripts.
