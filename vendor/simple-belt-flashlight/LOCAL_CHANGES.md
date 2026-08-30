# Local Changes — Simple Belt Flashlight+

## LS-004
Tipo: tradução PT-BR de sandbox
Arquivos: `42/media/lua/shared/Translate/PTBR/{Sandbox.json,Sandbox_PTBR.txt}`
Mudança: adicionadas as 3 chaves PT-BR completas; o TXT nativo usa escapes decimais ASCII-safe.
Validação: paridade 3/3 com EN, sintaxe Lua 5.1 e reconstrução UTF-8 exata.

## LS-001
Tipo: tradução / correção de bug
Arquivo novo: `42/media/lua/shared/Translate/EN/Sandbox_EN.txt`
Motivo: o upstream só tinha `Translate/EN/sandbox.json` (não lido por nenhum código deste mod — sem
UI própria de Options) e nenhum `Sandbox_EN.txt` nativo. A tela nativa de Sandbox Options só lê
`Sandbox_<LANG>.txt` em formato de tabela Lua — sem esse arquivo, a única opção do mod
(`SBFPlus.DebugLogging`) apareceria com a chave crua em vez de texto traduzido. Mesmo bug já
encontrado e corrigido antes no `zombie-decay` deste pacote.
Mudança: criado `Sandbox_EN.txt` com as 3 chaves que já existiam em `sandbox.json`
(`Sandbox_SBFPlus`, `Sandbox_SBFPlus_DebugLogging`, `Sandbox_SBFPlus_DebugLogging_tooltip`), texto
idêntico ao já presente no JSON.

## LS-002
Tipo: bundling / identidade do mod — **exceção à convenção do pacote**
Arquivo: `42/mod.info`
Motivo: ao contrário de todo módulo anterior, este **não** foi renomeado para `LS_<Nome>`. O próprio
upstream é um "drop-in replacement" deliberado para o Mod ID `FixedLightOnBeltAF`, preservando
compatibilidade com saves que já tinham esse mod ativo — Categoria C (seção 20 da arquitetura).
Renomear quebraria exatamente a compatibilidade que é a razão de existir do mod.
Mudança: `id=FixedLightOnBeltAF` mantido verbatim. `name=`/`description=` reescritos para o padrão
do pacote; `modVersion=1.0.4` (chave com V maiúsculo, provavelmente nunca reconhecida pelo parser de
`mod.info`) corrigido para `modversion=1.0.4`; `authors=ACE` mantido intocado (dado do upstream).

## LS-003
Tipo: estrutura
Arquivo: layout do submod inteiro
Motivo: adequar à estrutura canônica `common/` + `42/` deste projeto; o upstream usa uma pasta
`42.20/` em vez de `42/`.
Mudança: conteúdo de `42.20/` copiado para `Contents/mods/FixedLightOnBeltAF/42/`. As duas pastas
vazias `common/media/{actiongroups,AnimSets}/` (só continham `.gitkeep`) não foram copiadas — sem
conteúdo, nada perdido. `common/media/.gitkeep` próprio deste pacote usado no lugar.

## Itens sem alteração

Todos os 9 arquivos de código/script/asset (Lua, `sandbox-options.txt`, `SBFPlus_Attachments.txt`,
`icon.png`, `poster.png`) são cópias byte-a-byte do upstream — confirmado via `diff` direto contra
`vendor/simple-belt-flashlight/upstream/42.20/`. Nenhuma lógica foi tocada.

## Perguntas para revisitar em updates futuros

- Reconferir se o upstream corrige o `modVersion`/typo de capitalização e adicionar um
  `Sandbox_EN.txt` próprio em alguma atualização futura — se sim, nossos LS-001/LS-002 podem ficar
  redundantes (não removê-los sem comparar primeiro).
- Se algum mod novo bundlado também mexer em `ISHotbar.refresh`/`doMenuFromInventory`, checar
  `docs/COLLISION_REGISTRY.md` antes de integrar.
