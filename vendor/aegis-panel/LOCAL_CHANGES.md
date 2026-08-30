# Local Changes — Aegis Panel

## LS-004
Tipo: tradução PT-BR de sandbox
Arquivo novo: `42/media/lua/shared/Translate/PTBR/Sandbox_PTBR.txt`
Mudança: promovidas as 67 chaves do JSON PT-BR para o formato nativo com escapes decimais
ASCII-safe. Validação: paridade 67/67 com EN, sintaxe Lua 5.1 e reconstrução UTF-8 exata.

## LS-001
Tipo: correção de bug real (regressão do upstream)
Arquivos novos: `42/media/lua/shared/Translate/EN/{Sandbox_EN.txt, UI_EN.txt}`
Motivo: o upstream não shippa **nenhum** arquivo `.txt` nativo de tradução, em nenhuma das 2 famílias
usadas (`Sandbox`, `UI`) nem em nenhum dos 13 idiomas — só JSON. `getText()` nativo nunca lê JSON (ver
[[feedback-sandbox-options-native-txt-required]]), então as ~1092 strings visíveis ao jogador (todas
as 33 opções de sandbox, todo rótulo de UI nos 52 arquivos client — confirmado via 953 sites de
`getText(` na árvore client) apareceriam como chaves cruas não traduzidas em jogo. Maior gap de
tradução já encontrado neste pacote (até então o recorde era `plysken-solar-revolution`, 210 chaves).
Mudança: criados os 2 arquivos acima via script Python de uma execução só, transcrevendo literalmente
o JSON EN (já correto e completo) chave por chave, valor por valor — todas as 1092 chaves são
identificadores Lua puros (sem `.`/`-`), então nenhuma precisou de forma `["chave"]`. Placeholders
posicionais `%1`/`%2`/`%3` e os 4 valores já escapados como `%%` na fonte foram transcritos
literalmente (sem manipulação — já estavam na convenção correta). Verificado programaticamente que o
conjunto de chaves de cada `.txt` bate exatamente com o do `.json` correspondente, verificados 20
valores amostrados byte-a-byte, e `luac5.1 -p` passa limpo nos 2 arquivos.

## LS-002
Tipo: bundling / identidade do mod
Arquivo: `42/mod.info`
Motivo: rebrand para o namespace do pacote (mod não faz nenhum check do próprio Mod ID — Categoria A,
seção 20 da arquitetura; verificado via grep por `"AP"` literal e por `getActivatedMods` em toda a
árvore Lua).
Mudança: `id=AP` -> `id=LS_AegisPanel`; `name=`/`description=` reescritos, PT-BR (campo Java, seguro
para acentos). Adicionado `versionMin=42.20` (upstream não declarava nenhum piso de versão — mesmo
ajuste já aplicado em `proximity-inventory`). Removida a linha `Authors=` (não havia `url=` para
remover).

## LS-003
Tipo: identidade visual do pacote (cosmético, pedido explícito do usuário — não é correção de bug)
Arquivos: `42/media/lua/client/Aegis/{AegisTheme.lua, AegisWindow.lua}`
Motivo: dar a cara do pacote Lascivious Scripts também na UI do painel em jogo (até então só os
posters/ícones do menu de mods tinham identidade visual aplicada, ver artes em
`Contents/mods/LS_AegisPanel/42/poster.png`).
Mudança:
- `AegisTheme.lua`: `Aegis.col` — os neutros de fundo (`bg`/`panel`/`card`/`cardHi`/`line`) receberam
  um leve puxão de matiz pro roxo da marca (R e B um pouco mais altos, G um pouco mais baixo,
  luminância geral preservada; o ouro do painel — `gold`/`goldHi`/`goldDim`, o acento principal da
  identidade visual original do Aegis — não foi tocado). Adicionadas duas cores novas,
  `purple`/`purpleHi`, para uso em selos/acentos da marca.
- `AegisWindow.lua`: na janela principal (dourada, admin), adicionado o texto "LASCIVIOUS EDITION"
  logo à direita do título "AEGIS"/`AegisBrand.title()`, mesma linha, fonte `UIFont.Small`, cor
  `c.purpleHi`. Posição calculada a partir da largura real do título (`Aegis.strW`), então acompanha
  tanto o nome padrão quanto um nome de operador customizado (o painel já suporta rebrand via
  `AegisBrand`); truncado com `Aegis.fitText` se a janela estiver estreita, e escondido inteiramente
  (`editionMaxW > 24`) se não sobrar espaço nenhum entre o título e o relógio à direita — nunca
  sobrepõe outro elemento do cabeçalho. `clockX` (usado pelo relógio) foi só reordenado pra cima no
  mesmo bloco, sem mudar seu cálculo.
Verificado: `luac5.1 -p` passa limpo nos dois arquivos. **Não verificado visualmente em jogo** — este
ambiente não roda o PZ; a posição/legibilidade do selo e o tom da paleta devem ser conferidos in-game
antes de considerar definitivo.

## Itens sem alteração

Os outros 76 dos 78 arquivos Lua, texturas de UI, e o JSON de todos os 13 idiomas seguem cópia
byte-a-byte do upstream — confirmado via `diff -rq`. Ver `INTEGRATION.md` para a análise completa de
qualidade de código (o módulo mais rigorosamente projetado revisado neste pacote — zero gates de
permissão faltando em 26 arquivos de servidor com comandos, verificado por dois agentes de pesquisa
dedicados), autoridade MP, e a checagem cruzada contra todos os outros 27 módulos já bundlados (24
monkey-patches ao todo, zero colisões reais encontradas — duas pendências de vigilância documentadas
em `docs/COLLISION_REGISTRY.md` como superfície ocupada, caso um módulo futuro toque os mesmos
pontos). LS-003 acima é a única mudança de código deste módulo, cosmética e local ao pacote.
