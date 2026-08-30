# Translation PT-BR — Cye's Push Doors!

> **Atualização 2026-08-26 — Sandbox completo:** as 35 chaves agora têm JSON PT-BR e
> `Sandbox_PTBR.txt` nativo ASCII-safe. A situação do texto externo ao sandbox não mudou. Esta nota
> substitui somente as afirmações históricas abaixo sobre o sandbox permanecer em inglês.

**Parcial.**

- `42/mod.info`'s `description=` está em PT-BR (seguro — parseado em Java, não Kahlua).
- As 33 strings de Sandbox Options (título de página + 16 opções × rótulo/tooltip) agora têm um
  arquivo nativo EN (ver LOCAL_CHANGES LS-001), mas ficam em inglês — sem versão PT-BR nativa, mesma
  limitação já aceita no resto do pacote (texto acentuado quebra o loader nativo de `.txt`, vira "?";
  ver [[feedback-ptbr-accents-in-lua]]).
- O upstream não shippa um `Translate/PTBR/*.json` para esse mod (só EN/ES/ES_MX existem) — nada a
  preservar por fidelidade além do que já está no bundle.
- A única string de UI fora do Sandbox (o tickbox "Impact Feedback" do Mod Options) não usa
  `getText()` — é texto literal escolhido entre EN/ES por um heurístico próprio do upstream
  (`localText()`/`useSpanishText()`), então nunca aparece em PT-BR nem teria como ser traduzida sem
  editar o Lua diretamente (não feito, ver LOCAL_CHANGES "Itens ignorados deliberadamente").
