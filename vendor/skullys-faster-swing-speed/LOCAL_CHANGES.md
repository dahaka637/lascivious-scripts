# Local Changes — Skully's Faster Swing Speed

## LS-001
Tipo: bundling / identidade do mod
Arquivo: `42/mod.info`
Motivo: rebrand para o namespace do pacote (mod não faz nenhum check do próprio Mod ID — Categoria A,
seção 20 da arquitetura).
Mudança: `id=SkullysFasterSwingSpeed` -> `id=LS_SkullysFasterSwingSpeed`; `name=`/`description=`
reescritos. Removida a linha `icon=logo.png` — o arquivo `logo.png` não existe em lugar nenhum do
download do upstream (mesma referência quebrada pré-existente do módulo irmão
`skullys-faster-attack-speed`); `poster=poster.png` mantido.

## LS-002
Tipo: estrutura / scaffold
Arquivo novo: `common/media/.gitkeep`
Motivo: upstream shippa `common/` totalmente vazio (nem placeholder tem); Build 42 espera que o
diretório exista.

## Itens sem alteração

`swing_time_skully.lua` (único arquivo de código do módulo) é cópia byte-a-byte do upstream —
confirmado via `diff -rq` e validado com `luac5.1 -p`. **Nenhuma correção de código foi necessária.**
Ver `INTEGRATION.md` para a análise de por que o mecanismo (multiplicar a variável de animação
`CombatSpeed` em reação a `Events.OnWeaponSwing`) é seguro em MP sem nenhum código de rede.

## Itens ignorados deliberadamente

- `42/preview.png` — duplicata byte-idêntica de `poster.png`, não referenciada por nenhuma chave do
  `mod.info`. Não bundlado (preservado só no snapshot `vendor/` por fidelidade).
