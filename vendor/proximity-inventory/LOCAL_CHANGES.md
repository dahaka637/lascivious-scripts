# Local Changes — Proximity Inventory

## LS-003
Tipo: tradução PT-BR de sandbox
Arquivos: `42/media/lua/shared/Translate/PTBR/{Sandbox.json,Sandbox_PTBR.txt}`
Mudança: adicionadas as 3 chaves PT-BR completas; o TXT nativo usa escapes decimais ASCII-safe.
Validação: paridade 3/3 com EN, sintaxe Lua 5.1 e reconstrução UTF-8 exata.

## LS-001
Tipo: bundling / identidade do mod
Arquivo: `42/mod.info`
Motivo: rebrand para o namespace do pacote (mod não faz nenhum check do próprio Mod ID — Categoria A,
seção 20 da arquitetura).
Mudança: `id=ProximityInventory` -> `id=LS_ProximityInventory`; `name=`/`description=` reescritos.
Adicionado `versionMin=42.20` (upstream não declarava nenhum `versionMin=`/`modversion=`).
`poster=`/`icon=` preservados.

## LS-002
Tipo: bundling / estrutura
Arquivos: todo `42/media/` (consolidado a partir do upstream `common/media/`)
Motivo: o upstream usa a estrutura `common/` (conteúdo compartilhado entre builds) + `42/mod.info`
(metadados específicos do B42, sem `media/` próprio) para suportar múltiplos builds do jogo. Como
este pacote alveja só 42.20.x, não faz sentido manter esse split.
Mudança: conteúdo de `common/media/` copiado para dentro do `42/media/` deste submod, sem nenhuma
alteração de conteúdo — só consolidação de caminho.

## Itens sem alteração

Todo o código Lua (4 arquivos) e as traduções nativas (`Sandbox_EN.txt`, `UI_EN.txt`, `IG_UI_EN.txt`)
são cópia byte-a-byte do codebase B42 do upstream — confirmado via `diff -rq` e `luac5.1 -p`.
**Nenhuma correção de código foi necessária.** Diferente de quase todo o resto do pacote, a
tradução nativa EN já vinha completa e correta no upstream — nenhum fix de tradução foi preciso.

## Itens ignorados deliberadamente

- Todo o layout legado do upstream (`mod.info` de nível superior, `media/lua/client/
  {1ProximityInventory.core.lua,2ProximityInventory.client.lua}`, `media/sandbox-options.txt`,
  `media/ui/`, `icon.png`/`poster.png` de nível superior) — implementação mais antiga e menos
  completa do mesmo mod (namespace `ProxInv` global, depende opcionalmente de uma API externa
  `ModOptions:AddKeyBinding`, sem suporte a veículo, correção de dupe menos completa). Não bundlado
  nem incluído no snapshot `vendor/` (este pacote alveja só 42.20.x, então a camada legada não tem
  utilidade nenhuma aqui). Ver `INTEGRATION.md` para a comparação completa.
