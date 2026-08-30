# Translation PT-BR — Equip Items While Running

**Parcial, por limitação técnica conhecida, não por falta de revisão.**

- Nenhum item/receita/trait novo — nada a traduzir aí.
- A única string PT-BR deste submod é a `description=` do `42/mod.info` (segura: `mod.info` é
  parseado em Java puro, fora da VM Kahlua, então não sofre o bug de acentuação — ver
  `feedback_ptbr_accents_in_lua` na memória do projeto).
- Os 5 rótulos/tooltips do menu nativo **Opções > Mods** (`PZAPI.ModOptions`, em
  `EqiupWhileRunning.lua`) **ficaram em inglês, deliberadamente**: são literais de string Lua cruas,
  a mesma classe de texto que já quebra (vira "?") quando tem acento — o mesmo motivo pelo qual este
  pacote nunca criou um `Sandbox_PTBR.txt` nativo (ver `feedback_sandbox_options_native_txt_required`
  na memória). Não existe hoje, neste módulo, um caminho seguro para localizar esse menu específico
  em PT-BR acentuado sem construir um hook próprio — não fizemos isso aqui, seguindo o mesmo limite
  já aceito em outros lugares do pacote.

Se algum dia quisermos consertar isso de verdade, a solução seria replicar o padrão `getText()` +
JSON já usado noutro pacote irmão (Lascivious Shop) para esse menu especificamente — não é um
trabalho de tradução simples, é construir um loader novo.
