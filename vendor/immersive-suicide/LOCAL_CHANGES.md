# Local Changes — Immersive Suicide

## LS-003
Tipo: tradução PT-BR de sandbox
Arquivos: `42/media/lua/shared/Translate/PTBR/{Sandbox.json,Sandbox_PTBR.txt}`
Mudança: completadas as 5 chaves PT-BR, incluindo a confirmação, e criada a tabela nativa com
escapes decimais ASCII-safe. Validação: paridade 5/5 com EN, sintaxe Lua 5.1 e UTF-8 exato.

## LS-001
Tipo: tradução / correção de bug (afeta todos os idiomas, não só PT-BR)
Arquivos novos: `42/media/lua/shared/Translate/EN/{Sandbox_EN.txt,UI_EN.txt,ContextMenu_EN.txt}`
Motivo: a pasta `42.0/` do upstream só tinha `.json` (24 idiomas), que `getText()` nativo nunca lê —
o código de `42.0/` (`ContextMenu.lua`, `FirearmRadialMenuPatch.lua`, `ISYesNoDialog.lua`) chama
`getText()` em 8 chaves diferentes, todas sem texto nativo por trás. Sem correção, o menu de
contexto, a tooltip e o diálogo de confirmação apareceriam com a chave crua, em qualquer idioma
incluindo inglês.
Mudança: portados os arquivos nativos `.txt` já corretos da pasta raiz do upstream (build 41),
confirmando chave por chave que batem com o que o código de `42.0/` realmente usa
(`sandbox-options.txt` é idêntico entre raiz e `42.0/`, só muda espaço em branco).

## LS-002
Tipo: bundling / identidade do mod
Arquivo: `42/mod.info`
Motivo: rebrand para o namespace do pacote (mod não faz nenhum check do próprio Mod ID — Categoria A,
seção 20 da arquitetura).
Mudança: `id=stanks_suicide` -> `id=LS_ImmersiveSuicide`; `name=`/`description=` reescritos;
`versionMin=42.15` preservado do upstream (`42.0/mod.info`), não alterado.

## Achado sem ação — PT-BR nativo do upstream está corrompido

`Translate/PTBR/*.txt` da pasta raiz (build 41) tem corrupção de encoding irrecuperável — todo
caractere acentuado virou `�` (U+FFFD) no próprio arquivo do upstream, antes mesmo de chegar no PZ.
`42.0/Translate/PTBR/*.json` tem o texto correto (UTF-8 limpo, confirmado por hexdump), mas como
`getText()` não lê JSON e o pacote já tem a política estabelecida de não criar `Sandbox_PTBR.txt`/
`UI_PTBR.txt` nativos (acento quebra e vira "?" no painel nativo — ver
[[feedback-ptbr-accents-in-lua]]), **não foi criado nenhum arquivo PTBR nativo aqui**, mesmo tendo
o texto correto disponível. Ver `TRANSLATION_PTBR.md`.

## Itens sem alteração

Todo o Lua, os 4 arquivos de AnimSet, `sandbox-options.txt`, o ícone do menu radial e os JSONs de
todos os 24 idiomas são cópias byte-a-byte do upstream `42.0/` — confirmado via `diff`/`diff -rq`.
**Nenhuma correção de segurança/autoridade foi necessária** — o servidor só age sobre o `player`
autenticado pelo framework, nunca sobre algo vindo de `args`; ver `INTEGRATION.md`.

## Perguntas para revisitar em updates futuros

- Testar em jogo se a animação de suicídio realmente toca — o mod não inclui nenhum arquivo `.x` de
  clipe de animação junto com os nós de AnimSet, então isso não dá pra confirmar só lendo os
  arquivos.
- Se o upstream algum dia corrigir a própria corrupção do `Sandbox_PTBR.txt`/`UI_PTBR.txt` nativo,
  reconferir se vale a pena revisitar a decisão de não portar (ainda dependeria de resolver o bug de
  renderização de acento, que é um problema nosso/do motor, não do arquivo).
