# PT-BR Translation — Sprint Through Windows

Status: **completa** (native Sandbox Options, 13/13 chaves em paridade com `EN/Sandbox.json`).

O upstream já shippa `Translate/EN/Sandbox.json` e `Translate/PTBR/Sandbox.json` nativos — as 6
opções do Sandbox (`FailChance`, `InjuryChance`, `MinSprintTime`, `ShortSprintBreaksGlass`,
`VanillaAnimation`, `Debug`) aparecem em português no painel nativo de Sandbox Options do próprio
jogo, sem precisar de painel customizado.

O texto PT-BR upstream estava sem nenhum acento ("Atraves", "chao", "e" em vez de "é"). Reescrito por
completo em LS-003 (`LOCAL_CHANGES.md`) com acentuação e fraseado naturais — esse arquivo é JSON lido
via `getText()`, não um literal Lua cru, então não sofre o bug de acentuação documentado em
`[[feedback-ptbr-accents-in-lua]]`.

Não há nenhum outro texto exposto ao jogador (sem itens, receitas, context menu, nomes de trait/perk,
mensagens de chat, ou UI customizada) — o único texto vindo deste mod é `mod.info` (`name=`/
`description=`, também reescritos em PT-BR, ver LOCAL_CHANGES LS-002) e essas 13 chaves do Sandbox.
