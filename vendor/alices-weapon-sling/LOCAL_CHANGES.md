# Local Changes — Alice's Weapon Sling

## LS-005
Tipo: remoção de submod addon
Motivo: pedido direto do usuário — não queria o atalho/menu radial extra do addon
`alicesWeaponSlingRadialMenu` no pacote.
Mudança: `Contents/mods/LS_AliceWeaponSlingRadialMenu/` (o submod bundled inteiro, Workshop item
`3775549570`) e `vendor/alices-weapon-sling-radial-menu/` (snapshot upstream + docs) foram apagados
por completo. Este módulo (`LS_AliceWeaponSling`, o item de roupa em si) não muda em nada — o addon
só chamava PARA os globais deste módulo (`AliceWeaponSling.repairHotbarItem`), nunca o contrário, e
não registrava nenhum trait/item/recipe/modData próprio que precisasse de migração de save. `Mods=`
em `docs/SERVER_MOD_ORDER.md`, a linha de `LS_AliceWeaponSlingRadialMenu` em
`docs/MODULE_REGISTRY.md` e a menção ao addon aqui em `INTEGRATION.md` foram atualizadas junto.
Validação: `tools/generate_server_mods.py`, `tools/validate_structure.py` e
`tools/audit_collisions.py` re-executados após a remoção (28 submods, sem colisão).

## LS-001
Tipo: tradução / correção de bug
Arquivos novos: `42/media/lua/shared/Translate/EN/{ContextMenu_EN.txt,ItemName_EN.txt,Recipes_EN.txt,UI_EN.txt}`
Motivo: upstream só tinha `.json` (10 idiomas, incluindo PTBR completo e correto), que os sistemas
nativos de tradução (nome de item, menu de contexto, receita, rótulo de slot do hotbar) nunca leem —
mesmo bug recorrente já corrigido em quase todos os outros módulos deste pacote.
Mudança: criados os 4 arquivos nativos com o texto já correto do EN JSON, chave por chave. O
`ContextMenu_EN.txt` inclui 4 chaves extras (`AliceSlingStyle1..4`) usadas pelo script de roupa
(`ClothingExtraSubmenu`/`ClothingItemExtraOption`) mas nunca chamadas via `getText()` explícito no
Lua — lidas diretamente pelo motor do submenu de roupa.

## LS-002
Tipo: correção de bug real (upstream)
Arquivo novo: `42/media/lua/shared/Translate/EN/Tooltip_EN.txt`
Motivo: o item `AliceWeaponSlingWeightReductionPart` declara `Tooltip = Tooltip_Sling`, mas essa
chave não existe em nenhum idioma do upstream (nem no JSON) — o tooltip apareceria como a string
literal "Tooltip_Sling" no jogo.
Mudança: criado `Tooltip_EN.txt` com texto próprio (não havia nenhuma fonte para transcrever).

## LS-003
Tipo: correção de bug real (upstream) / bundling
Arquivo: `42/mod.info`
Motivo: o `mod.info` original declarava `poster=` três vezes (`poster.png`, `preview.png`,
`sling_recipe.png`) — o parser do PZ só honra uma linha `poster=`, então dois dos três arquivos
nunca apareciam em lugar nenhum.
Mudança: `id=alicesWeaponSling` -> `id=LS_AliceWeaponSling`; `name=`/`description=` reescritos;
colapsado para uma única linha `poster=poster.png`. `preview.png`/`sling_recipe.png` removidos do
bundle (preservados só no snapshot `vendor/` por fidelidade). `versionMin=42.20`/`modversion=1.5`
preservados.

## LS-004
Tipo: estrutura / scaffold
Arquivos: `42/media/{AnimSets,actiongroups}/_alices_weapon_sling_no_animsets.txt` /
`_no_actiongroups.txt` removidos, substituídos por `.gitkeep`.
Motivo: os dois arquivos placeholder do upstream (vazios, só para marcar pastas sem conteúdo
funcional) tinham o mesmo nome e caminho relativo tanto no módulo base quanto no addon
`alices-weapon-sling-radial-menu`, disparando falso positivo em `tools/audit_collisions.py` (mesmo
caminho relativo em dois submods diferentes). Trocados pelo `.gitkeep` padrão já usado em todo o
resto do pacote para pastas vazias — mesmo efeito (pasta existe, sem conteúdo), sem colisão de nome.

## Itens sem alteração

Todo o código Lua (12 arquivos), XML de roupa, scripts e modelos são cópia byte-a-byte do upstream —
confirmado via `diff -rq` e `luac5.1 -p` em todo o Lua. **Nenhuma correção de código foi
necessária.**

## Colisão real com `equip-while-running` — resolvida via ordem de carregamento, não patch

`ISAttachItemHotbar:new/:perform/:stop` são reimplementados por completo (sem call-through) tanto
por este módulo quanto por `equip-while-running`. Análise completa e a resolução (ordem obrigatória
`LS_AliceWeaponSling` antes de `LS_EquipWhileRunning`) estão documentadas em `INTEGRATION.md` e em
`docs/COLLISION_REGISTRY.md`. Nenhuma linha de Lua foi alterada para resolver isso — a ordem de
bundling já resolve completamente, sem perda funcional real.
