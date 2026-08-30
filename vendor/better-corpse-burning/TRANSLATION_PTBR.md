# Translation PT-BR — Better Corpse Burning

Tradução completa para todo texto exposto pelo módulo:

- 1 opção de menu (`IGUI_BCB_QuickBurnCorpse`);
- 10 títulos e 10 tooltips de Sandbox, mais o título da página (21 chaves);
- nome e descrição localizados no `Mod.json` e descrição PT-BR no `mod.info` bundled.

O snapshot preserva todos os catálogos JSON upstream. O bundle mantém os 29 idiomas e revisa EN/PTBR:
o PT-BR recebeu termos naturais e capitalização consistente, e o tooltip de duração deixou de chamar
ticks da TimedAction de "minutos do jogo". Como o carregador nativo não usa esses JSON em `getText()`,
também foram adicionados `IG_UI_EN.txt`, `IG_UI_PTBR.txt`, `Sandbox_EN.txt` e `Sandbox_PTBR.txt`.

`Sandbox_PTBR.txt` e `IG_UI_PTBR.txt` são ASCII-only e codificam caracteres não ASCII com escapes
decimais Lua de três dígitos. EN/PTBR possuem paridade exata de chaves.
