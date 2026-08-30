# Translation PT-BR — Mini Health Panel

Não aplicável. O upstream não shippa nenhum idioma além de EN, e não usa JSON em lugar nenhum — só
`UI_EN.txt`/`IG_UI_EN.txt` nativos (2 chaves no total, uma delas corrigida em
`LOCAL_CHANGES.md` LS-001). A `description=` do próprio `42/mod.info` está em PT-BR (seguro —
parseado em Java, não Kahlua). Os poucos rótulos de UI do painel de configurações ("Always
visible", "Health bar", "Muscle strains", "Lock window", "Settings") são strings literais fixas em
inglês no Lua, não roteadas por `getText()` — mesma limitação/decisão já aplicada em
`osrs-experience-bar` (ver aquele `INTEGRATION.md` para o motivo).
