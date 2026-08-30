# Local Changes — Burris Quality of Life

## LS-008
Tipo: tradução PT-BR de sandbox
Arquivos: `42/media/lua/shared/Translate/PTBR/{Sandbox.json,Sandbox_PTBR.txt}`
Mudança: adicionadas as 108 chaves PT-BR completas; o TXT nativo usa escapes decimais ASCII-safe.
Validação: paridade 108/108 com EN, sintaxe Lua 5.1 e reconstrução UTF-8 exata.

## LS-001
Tipo: remoção de funcionalidade redundante (decisão do usuário)
Arquivos removidos: `42/media/lua/client/BQoL/{BQoL_FlashlightSlot.lua,BQoL_AmmoHud.lua}`,
`42/media/lua/shared/BQoL/BQoL_ItemParams.lua`
Motivo: colisão real de dado com `simple-belt-flashlight` (`Base.HandTorch`/`Base.Flashlight_Crafted`
recebendo `AttachmentType` diferente de cada mod, quem carrega por último vence silenciosamente) e
sobreposição visual real com `clean-hotbar` (os dois desenham um contador de munição no mesmo lugar
exato do slot de mão principal). Ver `INTEGRATION.md` para a análise completa. Usuário optou por
remover as duas funcionalidades do BQoL por completo, não só desativar via sandbox — já temos
soluções melhores/mais completas para as duas coisas neste pacote.
Verificado antes de remover: nenhum outro arquivo faz `require` desses três, e `BQoL.ItemParams`/
`BQoL.has()` não são usados por nenhuma outra feature além das removidas.

## LS-002
Tipo: remoção de funcionalidade redundante (consequência de LS-001)
Arquivo: `42/media/sandbox-options.txt`
Motivo: as duas opções (`TweakFlashlightSlot`, `AmmoHudEnabled`) não tinham mais código nenhum para
ler seu valor depois de LS-001; deixá-las como toggles mortos no menu de Sandbox Options seria
confuso.
Mudança: removidos os dois blocos `option BurrisQoL.TweakFlashlightSlot {...}` e
`option BurrisQoL.AmmoHudEnabled {...}`, incluindo seus comentários de cabeçalho de seção.

## LS-003
Tipo: remoção de funcionalidade redundante (consequência de LS-001)
Arquivo: `42/media/lua/shared/BQoL/BQoL_Settings.lua`
Motivo: o próprio código do mod documenta a invariante "toda opção em sandbox-options.txt DEVE
também aparecer em BQoL_Settings.lua com o mesmo default" (reforçada por um `tools/lint.sh` do
upstream, não incluído no runtime). Removendo as 2 opções de um lado sem o outro quebraria essa
invariante.
Mudança: removidas as entradas `AmmoHudEnabled = true,` e `TweakFlashlightSlot = true,` da tabela
`DEFAULTS`. Reconferido programaticamente: as 47 chaves de `sandbox-options.txt` e as 47 chaves de
`DEFAULTS` batem exatamente após a remoção.

## LS-004
Tipo: remoção de funcionalidade redundante (consequência de LS-001) / tradução
Arquivo: `42/media/lua/shared/Translate/EN/Sandbox.json`
Motivo: mesma limpeza, agora nas chaves de tradução das 2 opções removidas.
Mudança: removidos os pares `Sandbox_BurrisQoL_TweakFlashlightSlot`/`_tooltip` e
`Sandbox_BurrisQoL_AmmoHudEnabled`/`_tooltip`. JSON revalidado com `python3 -m json` após a edição.

## LS-005
Tipo: tradução / correção de bug
Arquivos novos: `42/media/lua/shared/Translate/EN/{Sandbox_EN.txt,ContextMenu_EN.txt,IG_UI_EN.txt,ItemName_EN.txt,Recipes_EN.txt,Tooltip_EN.txt}`
Motivo: upstream só tinha `.json` (só EN, nenhum outro idioma), que os sistemas nativos de tradução
nunca leem — mesmo bug recorrente já corrigido em quase todo o resto do pacote.
Mudança: criados os 6 arquivos nativos com o texto já correto do EN JSON, chave por chave. O
`Sandbox_EN.txt` já reflete a remoção das 2 chaves de LS-004 (transcrito do JSON já editado).

## LS-006
Tipo: bundling / identidade do mod
Arquivo: `42/mod.info`
Motivo: rebrand para o namespace do pacote (mod não faz nenhum check do próprio Mod ID — Categoria A,
seção 20 da arquitetura); descrição precisa refletir a remoção das 2 funcionalidades de LS-001.
Mudança: `id=BurrisQoL` -> `id=LS_BurrisQualityOfLife`; `name=`/`description=` reescritos em PT-BR,
removendo as menções a "an ammo counter on your weapon" e "a flashlight that fits the tool loop".
`versionMin=42.20.0`, `modversion=0.9.3` preservados. `poster=`/`icon=` preservados.

## LS-007
Tipo: bundling / estrutura
Arquivos: todo `42/media/`
Motivo: o upstream usa `common/` (mod.info + ícones + Translate) + `42.20/` (todo o Lua + scripts +
sandbox-options.txt). Como este pacote alveja só 42.20.x, consolidamos os dois no `42/` único deste
submod, mesmo raciocínio já aplicado em outros módulos com essa estrutura.
Mudança: conteúdo copiado sem alteração além das mudanças LS-001 a LS-006.

## Itens sem alteração

Todos os outros 31 arquivos Lua (de 34 originais) e os 5 arquivos JSON não relacionados a Sandbox
são cópia byte-a-byte do upstream — confirmado via `diff -rq` e `luac5.1 -p`. Ver `INTEGRATION.md`
para a análise completa de segurança em MP (a funcionalidade de arrombamento é totalmente validada
no servidor, o torniquete não confia em alegações do cliente) e a checagem cruzada contra os outros
24 módulos já bundlados neste pacote (só uma colisão real remanescente, `ISHotbar.canBeAttached`
com `clean-hotbar`, verificada segura independente da ordem de carregamento — mesmo padrão já
documentado para `ISHotbar.refresh`).
