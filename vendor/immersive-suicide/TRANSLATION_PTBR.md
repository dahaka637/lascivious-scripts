# Translation PT-BR — Immersive Suicide

> **Atualização 2026-08-26 — Sandbox completo:** as 5 chaves agora estão em JSON PT-BR e
> `Sandbox_PTBR.txt` nativo ASCII-safe, incluindo a confirmação que faltava. A situação das demais
> famílias não mudou. Esta nota substitui somente as afirmações históricas abaixo sobre o sandbox.

**Parcial, com uma nota especial.**

- `42/mod.info`'s `description=` está em PT-BR (seguro — parseado em Java, não Kahlua).
- As 8 strings de UI/menu de contexto/sandbox agora têm `Sandbox_EN.txt`/`UI_EN.txt`/
  `ContextMenu_EN.txt` nativos (ver LOCAL_CHANGES LS-001), mas ficam em inglês.
- **Diferente de toda integração anterior neste pacote, desta vez o texto PT-BR correto existe e
  foi verificado** — está em `42/media/lua/shared/Translate/PTBR/*.json` (preservado do upstream,
  UTF-8 correto, conferido por hexdump). Ele só não foi promovido para um `Sandbox_PTBR.txt`/
  `UI_PTBR.txt`/`ContextMenu_PTBR.txt` nativo porque isso ainda esbarra na mesma limitação de
  sempre: acento em string Lua crua carregada pelo painel nativo vira "?" no jogo (ver
  [[feedback-ptbr-accents-in-lua]] e [[feedback-sandbox-options-native-txt-required]]). Se um dia
  este pacote construir um hook próprio de tradução (como o `LS.text()` do Lascivious Shop) para
  telas nativas, o texto PT-BR já pronto está bem aqui, só esperando.
- Curiosidade registrada só para conhecimento: o `Translate/PTBR/*.txt` **do próprio upstream**
  (pasta raiz, build 41) está com corrupção de encoding (virou `�` em todo acento) — não tem relação
  com o bug de renderização nativo do PZ, é um problema de pipeline de tradução do autor original.
  Não usamos esse arquivo de jeito nenhum (nem a pasta raiz inteira foi bundlada).
