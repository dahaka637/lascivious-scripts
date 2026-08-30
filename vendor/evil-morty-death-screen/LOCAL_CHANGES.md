# Local Changes - Evil Morty Death Screen

## LS-001

Tipo: bundling / identidade do mod
Arquivo: `42/mod.info`
Motivo: rebrand para o namespace do pacote.
Mudanca: `id=EvilMortyDeathScreen` -> `id=LS_EvilMortyDeathScreen`; `name=` e `description=`
reescritos em PT-BR; `modversion=1.0.1` registra a correcao local de audio.

## LS-002

Tipo: audio / estabilidade
Arquivo: `42/media/scripts/EvilMortyDeathScreenTheme_Sounds.txt`
Motivo: reduzir risco do glitch/buzzing reportado em morte por fogo.
Mudanca: `EvilMortyDeathTheme` deixou de ser som `Music` 3D e passou a ser som `UI` nao posicional.
O arquivo OGG foi preservado byte-a-byte.

## LS-003

Tipo: client Lua / estabilidade
Arquivo: `42/media/lua/client/EvilMortyDeathScreenTheme.lua`
Motivo: evitar que o tema customizado brigue com o gerenciador de musica enquanto toca e evitar
wrappers duplicados em reload de Lua.
Mudanca: removido o `StopMusic()` recorrente por segundo; mantido apenas um `StopMusic()` inicial
protegido por `pcall`; wrappers de `ISPostDeathUI` receberam guarda de idempotencia; `onMouseWheel`
agora chama a funcao capturada quando o efeito nao esta ativo.

## Itens sem alteracao

`icon.png`, `poster.png` e `EvilMortyTheme.ogg` foram preservados byte-a-byte do upstream.
