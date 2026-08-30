# Local Changes — Plysken Solar Revolution

## LS-004
Tipo: tradução PT-BR de sandbox
Arquivo novo: `42/media/lua/shared/Translate/PTBR/Sandbox_PTBR.txt`
Mudança: promovidas as 47 chaves do JSON PT-BR para o formato nativo com escapes decimais
ASCII-safe. Validação: paridade 47/47 com EN, sintaxe Lua 5.1 e reconstrução UTF-8 exata.

## LS-001
Tipo: correção de bug real (regressão do upstream)
Arquivos novos: `42/media/lua/shared/Translate/EN/{ContextMenu_EN.txt, IG_UI_EN.txt, ItemName_EN.txt,
Moveables_EN.txt, Recipes_EN.txt, Sandbox_EN.txt, Tooltip_EN.txt}`
Motivo: o upstream não shippa **nenhum** arquivo `.txt` nativo de tradução, em nenhum dos 7 famílias
usadas (`ContextMenu`, `IG_UI`, `ItemName`, `Moveables`, `Recipes`, `Sandbox`, `Tooltip`) nem em
nenhum dos 28 idiomas — só JSON. `getText()` nativo nunca lê JSON (ver
[[feedback-sandbox-options-native-txt-required]]), então as 210 strings visíveis ao jogador (nomes
de item, menu de contexto, tooltips, nomes de receita, as 16 opções de sandbox) apareceriam como
chaves cruas não traduzidas em jogo.
Mudança: criados os 7 arquivos acima, transcritos literalmente do JSON EN (já correto e completo).
`ItemName_EN.txt` usa chaves em forma `["Modulo.Item"]` (o fullType do item contém um `.` literal,
inválido como identificador Lua puro). `Recipes_EN.txt` usa a mesma forma só para as 2 chaves que
contêm um `-` literal (`Make_Wall-Mounted_Solar_Panel`, `Make_Floor-Mounted_Solar_Panel`); as outras
15 usam identificador puro. Verificado programaticamente que o conjunto de chaves de cada `.txt`
bate exatamente com o do `.json` correspondente, e `luac5.1 -p` passa limpo nos 7 arquivos.

## LS-002
Tipo: bundling / identidade do mod
Arquivo: `42/mod.info`
Motivo: rebrand para o namespace do pacote (mod não faz nenhum check do próprio Mod ID — Categoria
A, seção 20 da arquitetura).
Mudança: `id=PSR` -> `id=LS_PlyskenSolarRevolution`; `name=`/`description=` reescritos, PT-BR (campo
Java, seguro para acentos). `versionMin=42.0`, `modversion=1.76`, `poster=poster.png`,
`pack=solarmod_tileset`, `tiledef=solarmodtiledefs 575` preservados verbatim — os dois últimos são
identificadores de asset (tileset/texturepack), não do mod, renomeá-los quebraria a referência
interna do `.tiles` binário ao pack. Removida a linha `url=` (vazia) e
`incompatible=ISA_41,ISA,ISA_42` (nomeia o mod original do qual este é fork e duas variantes dele,
nenhum dos três bundlado neste pacote — mesmo raciocínio já aplicado ao `incompatible=` removido de
`drag-bodies-faster` e `clean-hotbar`, esses Mod IDs nunca vão existir neste bundle).

## LS-003
Tipo: bundling / estrutura
Arquivos: todo `42/media/`
Motivo: o upstream usa três camadas — raiz (só `mod.info`+`poster.png`), `common/media/` (o tiledef
binário `solarmodtiledefs.tiles` + o atlas `texturepacks/solarmod_tileset.pack`, sem `mod.info`
próprio) e `42.1/` (`mod.info` + todo o resto: Lua, scripts, UI, texturas, modelo 3D). Como este
pacote alveja só 42.20.x, consolidamos `common/media/` + `42.1/` no `42/` único deste submod, mesmo
raciocínio já aplicado em `proximity-inventory`/`improvised-silencers`/`clean-hotbar`.
Mudança: conteúdo copiado sem alteração além da tradução (LS-001) e do mod.info (LS-002).

## Itens sem alteração

Todos os ~35 arquivos Lua, os 3 arquivos de scripts (`Items.txt`/`Models.txt`/`Recipes.txt`), as
texturas, a UI e o modelo 3D são cópia byte-a-byte do upstream — confirmado via `diff -rq` e
`luac5.1 -p`. **Nenhuma correção de código foi necessária** — o upstream já é o módulo mais
extensivamente auto-auditado deste pacote (histórico de correções documentado em comentário, datado
até 2026-08-23, com leitura de bytecode e reprodução medida antes de cada correção). Ver
`INTEGRATION.md` para a análise completa de qualidade de código, autoridade MP, e a checagem cruzada
contra todos os outros 25 módulos já bundlados (duas colisões reais encontradas — `ISInventoryPane.
drawItemDetails` com `improvised-silencers`, `ISReadABook` com `burris-quality-of-life` em métodos
diferentes — ambas seguras/independentes de ordem, sem necessidade de regra de ordenação).
