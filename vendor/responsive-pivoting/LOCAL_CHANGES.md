# Local Changes — Responsive Pivoting

## LS-004
Tipo: remoção de feature (traits)
Motivo: pedido direto do usuário antes do upload pra Workshop — não quer o mod tocando em traits do
personagem por algo tão pequeno quanto velocidade de giro.
Arquivos removidos: `42/media/scripts/characters/PivotMod_traits.txt` (definição dos dois traits),
`42/media/registries.lua` (registro dos `CharacterTrait`), `42/media/ui/Traits/{trait_onyourtoes.png,
trait_podshofe.png}` (ícones), `42/media/lua/shared/Translate/EN/{UI_EN.txt,UI.json,IGUI_EN.txt,
IG_UI.json}` (só tinham texto desses traits, ficaram vazios de propósito).
Arquivos editados: `42/media/lua/shared/DoublePivotMod.lua` (removida toda resolução de trait —
`getTrait`/`playerHasTrait`/`nimbleAffected`, o switch `traitVersion`, a curva "On Your
Toes"/"PodShofe" do modo Nimble — que agora usa só a curva "default" pra todo mundo —, e o bloco que
adicionava/removia o trait automaticamente ao atingir Agilidade 6); `42/media/sandbox-options.txt`
(removidas as opções `TraitVersion`, `OnYourToesMultiplier`, `PodShofeMultiplier`,
`OnYourToesInGameMultiplier`, `PodShofeInGameMultiplier`); `42/mod.info` (descrição não menciona mais
traits); as 4 traduções `Sandbox_PivotMod_*` correspondentes removidas de
`Translate/{EN/Sandbox_EN.txt,EN/Sandbox.json,PTBR/Sandbox.json}`, com `Sandbox_PTBR.txt`
regenerado via `tools/generate_ptbr_sandbox_native.py` (37/37 chaves, paridade EN/PT-BR confirmada).
Mudança de comportamento: o mod passa a aplicar sua velocidade de giro globalmente para todo mundo
(já era o padrão de fábrica antes — `TraitVersion` default era `false` — então isso só remove a
OPÇÃO de restringir por trait, não muda o comportamento padrão de quem já jogava sem mexer nesse
switch). O modo Nimble usa só a curva "default" (`DefaultMultiplier`/`NimbleLvlMultiplier`) para
todos os jogadores, sem variação por trait.
**Risco de compatibilidade de save**: qualquer personagem salvo que já tivesse escolhido
`pivotmod:onyourtoes` ou `pivotmod:podshofe` na criação (ou ganhado via Agilidade 6) fica com uma
referência de trait que não existe mais no script. Isso é um risco real só se este mod já tiver sido
usado num save existente antes deste patch — como o mod ainda não tinha ido para a Workshop, não há
save de produção afetado; ok publicar direto. Se o pacote for atualizado no ar num save que já usava
a versão anterior, seguir o procedimento de remoção de trait da seção 32 da arquitetura antes de só
sobrescrever os arquivos.
Validação: `luac5.1 -p` em todos os arquivos tocados, `tools/validate_structure.py` e
`tools/audit_collisions.py` (PASS), grep de `pivotmod:`/`OnYourToes`/`PodShofe`/`TraitVersion` no
módulo inteiro confirma zero resquício.

## LS-003
Tipo: tradução PT-BR de sandbox
Arquivos: `42/media/lua/shared/Translate/PTBR/{Sandbox.json,Sandbox_PTBR.txt}`
Mudança: adicionadas as 47 chaves PT-BR completas; o TXT nativo usa escapes decimais ASCII-safe.
Validação: paridade 47/47 com EN, sintaxe Lua 5.1 e reconstrução UTF-8 exata.

## LS-001
Tipo: tradução / correção de bug
Arquivos novos: `42/media/lua/shared/Translate/EN/{Sandbox_EN.txt,UI_EN.txt,IGUI_EN.txt}`
Motivo: `42/` só tinha `.json` (nada no mod lê JSON — `getText()` nativo só lê `.txt`). A pasta raiz
(build 41) já tinha os `.txt` nativos corretos, mas **incompletos** em relação ao JSON de `42/`:
faltavam as 10 chaves `Sandbox_PivotMod_{PivotSpeed,MovementTurnSpeed}_option1..5` (rótulos dos
níveis do enum) e uma frase extra na tooltip de `PivotSpeed`.
Mudança: `UI_EN.txt`/`IGUI_EN.txt` portados verbatim da raiz (texto idêntico ao JSON de `42/`, então
sem risco). `Sandbox_EN.txt` foi **construído a partir do JSON de `42/`** (mais completo/atualizado),
não copiado da raiz — dessa vez a raiz é que estava desatualizada. Corrigido `%%` -> `%` em dois
textos (`DynPanic`/`DynSneak`) ao transcrever do JSON, pra bater com o formato nativo já usado (e
presumivelmente testado) pela própria raiz.

## LS-002
Tipo: bundling / identidade do mod
Arquivo: `42/mod.info`
Motivo: rebrand para o namespace do pacote (mod não faz nenhum check do próprio Mod ID — Categoria A,
seção 20 da arquitetura). **Não afeta** os IDs de trait `pivotmod:onyourtoes`/`pivotmod:podshofe`,
que são strings fixas no script, independentes do Mod ID.
Mudança: `id=PivotMod` -> `id=LS_ResponsivePivoting`; `name=`/`description=` reescritos.
`versionMin=42.0.0` e `modversion=3.0` preservados do upstream.

## Itens sem alteração

`sandbox-options.txt` (fora as 5 opções de trait removidas em LS-004) e o restante de
`DoublePivotMod.lua` (presets fixos, sistema Nimble, modificadores dinâmicos) continuam batendo com
a lógica do upstream `42/` — só a camada de trait foi removida, nada mais foi tocado. **Nenhuma
correção de segurança/autoridade foi necessária** — o mod não tem absolutamente nenhum código de
rede, é 100% local por design. `registries.lua`, `PivotMod_traits.txt` e os dois PNGs de trait não
existem mais neste módulo desde LS-004 (ver acima) — a nota anterior sobre o case sensível do PNG
(`trait_onyourtoes.png` minúsculo, ver histórico deste arquivo) ficou sem objeto.

## Perguntas para revisitar em updates futuros

- Reconferir contra o JSON de `42/` (não contra a raiz B41) se o upstream atualizar as traduções —
  desta vez foi a raiz que ficou pra trás.
- Se o upstream lançar uma atualização, ela vai trazer `PivotMod_traits.txt`/`registries.lua`/os PNGs
  de trait de volta — **não reintroduzir esses arquivos automaticamente** ao portar uma atualização
  futura; a remoção em LS-004 foi uma decisão de produto do usuário, não um bug do upstream a
  "corrigir de volta".
