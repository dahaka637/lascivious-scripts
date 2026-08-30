# Local Changes - Bug Fixes

## LS-001

Tipo: bundling / container generico
Arquivos:
`42/mod.info`,
`42/media/lua/client/LS_BugFixes/MapAllKnownFix.lua`
Motivo: agrupar pequenos fixes de bugs do jogo em um unico submod do pacote, em vez de criar uma
pasta/mod separado para cada patch pequeno.
Mudanca: `id=MapAllKnownFix` foi substituido pelo novo `id=LS_BugFixes`; o Lua do fix foi movido
para o namespace de pasta `LS_BugFixes/`, sem alterar sua logica.
Validacao: sintaxe Lua 5.1 e equivalencia de hash do arquivo Lua contra o upstream, exceto pelo
caminho.

## Itens sem alteracao

O arquivo `MapAllKnownFix.lua` bundled e uma copia byte-a-byte do upstream. Nenhuma logica foi
reescrita.
