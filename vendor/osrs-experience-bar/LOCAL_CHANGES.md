# Local Changes — OSRS Experience Bar

## LS-001
Tipo: bundling / identidade do mod
Arquivo: `42/mod.info`
Motivo: rebrand para o namespace do pacote (mod não faz nenhum check do próprio Mod ID — Categoria A,
seção 20 da arquitetura).
Mudança: `id=RUNE-EXP` -> `id=LS_OSRSExperienceBar`; `name=`/`description=` reescritos.
`versionMin=42.0`, `modversion=2.0.3` preservados. `poster=` preservado.

## Itens sem alteração

Todos os 3 arquivos Lua são cópia byte-a-byte do upstream — confirmado via `diff -rq` e
`luac5.1 -p`. **Nenhuma correção de código foi necessária.** Módulo 100% client-side, sem código de
rede, sem monkey-patch de nenhuma classe vanilla — ver `INTEGRATION.md` para a análise completa,
incluindo como o mod já lida corretamente com o fato de `Events.AddXP` não disparar em clientes MP
(faz polling do próprio XP do jogador local a cada tick).

## Itens deliberadamente não traduzidos

O upstream não usa `getText()`/sistema de tradução nativo em lugar nenhum — os poucos rótulos de UI
("Tracked Skills:", "Close", "Hide"/"Show", "Configurate") são strings literais fixas em inglês
direto no Lua. Não foram traduzidos para PT-BR: sem nenhum `getText()` para rotear, qualquer texto
acentuado colocado direto no literal Lua quebraria (vira "?", ver
[[feedback-ptbr-accents-in-lua]]) — mesma limitação já aceita no resto do pacote, aqui sem nem
sequer a opção de contornar via arquivo nativo `.txt`.
