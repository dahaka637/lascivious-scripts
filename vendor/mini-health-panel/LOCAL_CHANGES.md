# Local Changes — Mini Health Panel

## LS-001
Tipo: correção de bug real (upstream)
Arquivo: `42/media/lua/shared/Translate/EN/IG_UI_EN.txt`
Motivo: a string `IGUI_MiniHealth_UpdateNotes` no arquivo nativo original do upstream não fechava
as aspas nem tinha vírgula final antes do `}` — `luac5.1 -p` falhava com `unfinished string`. Isso
quebra o parse do chunk Lua inteiro do arquivo quando o jogo tenta carregá-lo, então
`getText("IGUI_MiniHealth_UpdateNotes")` (usado no popup de novidades exibido após atualizar o mod,
ver `ISMiniHealth.lua:743`) cairia no fallback e mostraria a chave crua em vez do texto real.
Mudança: adicionada a aspa de fechamento e a vírgula final. Nenhum outro caractere do texto foi
alterado.

## LS-002
Tipo: bundling / identidade do mod
Arquivo: `42/mod.info`
Motivo: rebrand para o namespace do pacote (mod não faz nenhum check do próprio Mod ID — Categoria A,
seção 20 da arquitetura).
Mudança: `id=MiniHealthPanel` -> `id=LS_MiniHealthPanel`; `name=`/`description=` reescritos.
`versionMin=42.13`, `modversion=1.6.1.42`, `tags=Interface` preservados. `poster=`/`icon=`
preservados.

## Itens sem alteração

Os 4 arquivos Lua (exceto a correção de string em LS-001, que é em um arquivo de tradução, não Lua
de código) são cópia byte-a-byte do upstream `42/` — confirmado via `diff -rq` e `luac5.1 -p`.
**Nenhuma correção de código Lua foi necessária.** Ver `INTEGRATION.md` para a análise completa de
por que o menu de tratamento (uma cópia local-scoped fiel das classes internas do
`ISHealthPanel.lua` vanilla) é seguro sem reimplementar nenhuma lógica server-side — toda ação real
passa pela `HealthPanelAction` global do próprio vanilla, inalterada.

## Itens ignorados deliberadamente

- Toda a camada legada de nível superior (`mod.info` + `media/` sem pasta de versão,
  `versionMin=41.60`/`versionMax=41.99`) — codebase mais antiga do Build 41, com Lua diferente e sem
  os 34 sprites de "stiff limb" que só existem na versão `42/`. Não bundlada nem incluída no
  snapshot `vendor/` (este pacote alveja só 42.20.x).
- `common/` (só `mod.info` + 2 ícones, sem Lua/UI nenhum — um stub incompleto que não funciona
  sozinho). Não bundlado nem incluído no snapshot.
- `42/media/.git/` — pasta de desenvolvimento (~1.7 MB) incluída acidentalmente pelo upstream no
  download do Workshop, sem nenhuma relação funcional com o mod. Excluída completamente, inclusive
  do snapshot `vendor/`.
