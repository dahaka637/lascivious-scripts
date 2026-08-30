# Local Changes — Improvised Silencers

## LS-004
Tipo: tradução PT-BR de sandbox
Arquivos: `42/media/lua/shared/Translate/PTBR/{Sandbox.json,Sandbox_PTBR.txt}`
Mudança: adicionadas as 23 chaves PT-BR completas; o TXT nativo usa escapes decimais ASCII-safe.
Validação: paridade 23/23 com EN, sintaxe Lua 5.1 e reconstrução UTF-8 exata.

## LS-001
Tipo: tradução / correção de bug
Arquivos novos: `42/media/lua/shared/Translate/EN/{Sandbox_EN.txt,ItemName_EN.txt,Recipes_EN.txt,Tooltip_EN.txt}`
Motivo: upstream só tinha `.json` (8 idiomas), que os sistemas nativos de tradução (Sandbox Options,
nome de item, menu de receita, tooltip) nunca leem — mesmo bug recorrente já corrigido em quase todo
o resto do pacote. Impacto mais visível que o usual aqui: o script de itens não declara nenhum
`DisplayName=` de fallback para os 5 silenciadores, então sem o `ItemName_EN.txt` nativo eles
apareceriam com o nome interno cru (`Silencer`, `MetalPipeSilencer`, ...) no jogo.
Mudança: criados os 4 arquivos nativos com o texto já correto do EN JSON, chave por chave (23 + 5 +
5 + 8 = 41 chaves no total).

## LS-002
Tipo: bundling / identidade do mod
Arquivo: `42/mod.info`
Motivo: rebrand para o namespace do pacote (mod não faz nenhum check do próprio Mod ID — Categoria A,
seção 20 da arquitetura).
Mudança: `id=ImprovisedSilencers` -> `id=LS_ImprovisedSilencers`; `name=`/`description=` reescritos.
`versionMin=42.20.0` preservado. `poster=` preservado.

## LS-003
Tipo: bundling / estrutura
Arquivos: todo `42/media/` (consolidado a partir do upstream `common/media/`, que já incluía o
próprio `mod.info`)
Motivo: o upstream usa `common/` (mod.info + conteúdo compartilhado) + `42.0/` (pasta de versão
quase vazia, só placeholders) para suportar o layout multi-build do B42. Como este pacote alveja só
42.20.x, não faz sentido manter esse split — mesmo raciocínio já aplicado em
`vendor/proximity-inventory/LOCAL_CHANGES.md`.
Mudança: conteúdo de `common/media/` (e o `common/mod.info`) copiado para dentro do `42/` deste
submod, sem nenhuma alteração de conteúdo além da consolidação de caminho.

## Itens sem alteração

Todo o código Lua (12 arquivos: 5 client, 1 server, 6 shared), scripts, sons, texturas e modelos são
cópia byte-a-byte do upstream — confirmado via `diff -rq` e `luac5.1 -p` em todo o Lua e traduções
nativas. **Nenhuma correção de código foi necessária.** Este é um dos módulos mais bem escritos já
integrados neste pacote — autoridade de MP corretamente restrita ao servidor para durabilidade,
sincronização de rede própria com contador de revisão e retry para lidar com pacotes fora de ordem
entre o packet nativo e o comando customizado, e integração cuidadosa com Guns of Marz/Vanilla
Firearms Expansion sem nunca sobrescrever os handlers globais dessas outras frameworks. Ver
`INTEGRATION.md` para a análise completa, incluindo a checagem cruzada contra os outros 19 módulos
já bundlados neste pacote (nenhuma colisão real encontrada).

## Itens ignorados deliberadamente

- `common/preview{1,2,3,4}.png` — screenshots da página do Workshop, não referenciados por nenhuma
  chave do `mod.info` (`poster=poster.png` é a única imagem usada). Não bundlados (preservados só no
  snapshot `vendor/` por fidelidade).
