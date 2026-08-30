# Translation PT-BR — OSRS Experience Bar

Não aplicável. O upstream não tem nenhum sistema de tradução (`Translate/`, `getText()`) — os
poucos rótulos de UI são strings literais fixas em inglês no próprio código Lua, e não foram
traduzidos (ver `LOCAL_CHANGES.md` para o motivo: sem `getText()` para rotear, o texto acentuado
quebraria o parser Kahlua, mesma limitação de [[feedback-ptbr-accents-in-lua]]). A
`description=` do próprio `42/mod.info` está em PT-BR (seguro — parseado em Java, não Kahlua).
