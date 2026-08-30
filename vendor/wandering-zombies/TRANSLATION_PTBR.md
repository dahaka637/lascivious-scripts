# Translation PT-BR — Wandering Zombies

> **Atualização 2026-08-26 — Sandbox completo no jogo:** as 160 chaves já traduzidas agora também
> estão em `Sandbox_PTBR.txt` nativo ASCII-safe. Esta nota substitui a afirmação histórica abaixo de
> que o catálogo existia apenas em JSON.

**Parcial no jogo; completa como catálogo JSON.**

- `42/mod.info` possui descrição PT-BR.
- Criado `Translate/PTBR/Sandbox.json` com as mesmas 160 chaves do JSON EN, incluindo nomes de
  páginas, opções, valores de enum e tooltips da UI personalizada.
- A camada upstream 42.18 não possuía tabela nativa. Foi criado `Sandbox_EN.txt` completo e válido,
  pois `getText()` e o painel de sandbox precisam desse formato para fallback funcional.
- Não foi criado `.txt` PT-BR, seguindo a limitação de acentuação já confirmada no projeto. O
  catálogo JSON PT-BR fica preservado para um caminho futuro de exibição sem corrupção de acentos.
- Os conjuntos EN/PTBR são idênticos (160/160), os JSONs passam em `jq` e o fallback EN passa em
  `luac5.1 -p`.
