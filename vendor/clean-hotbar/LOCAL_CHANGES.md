# Local Changes — Clean HotBar

## LS-001
Tipo: correção de bug real (regressão do upstream)
Arquivo novo: `42/media/lua/shared/Translate/EN/IG_UI_EN.txt`
Motivo: a pasta de versão que realmente cobre nosso alvo (42.15+, ou seja, inclusive 42.20.x) só
tinha `IG_UI.json` por idioma — o `.txt` nativo que a pasta `42/` mais antiga (excluída deste
bundle, pois seu `versionMax=42.14.99` não cobre nosso alvo) ainda tinha foi perdido na versão mais
nova. Como `getText()` nativo nunca lê JSON, isso é uma regressão real que afeta exatamente a faixa
de build que este pacote usa.
Mudança: criado `IG_UI_EN.txt` com as mesmas 7 chaves, texto idêntico ao já correto do EN JSON
(conferido chave por chave contra o `.txt` nativo da pasta `42/` mais antiga, que tinha o mesmo
conteúdo).

## LS-002
Tipo: bundling / identidade do mod
Arquivo: `42/mod.info`
Motivo: rebrand para o namespace do pacote (mod não faz nenhum check do próprio Mod ID — Categoria A,
seção 20 da arquitetura).
Mudança: `id=CleanHotBar` -> `id=LS_CleanHotBar`; `name=`/`description=` reescritos.
`versionMin=42.15`, `modversion=1.12.3` preservados. `poster=`/`icon=` preservados. Removida a linha
`incompatible=qdx_item_condition,TheStar` (nomeia dois outros mods do Workshop não bundlados neste
pacote — mesmo raciocínio já aplicado ao `incompatible=` removido de `drag-bodies-faster`, esses Mod
IDs nunca vão existir neste bundle).

## LS-003
Tipo: bundling / estrutura
Arquivos: todo `42/media/`
Motivo: o upstream usa `common/` (Lua e assets de UI compartilhados, sem `mod.info` nem
`Translate/` próprios) + duas pastas de versão (`42/`, cujo `versionMax=42.14.99` exclui nosso alvo;
`42.15/`, sem limite superior, que é a que realmente se aplica). Como este pacote alveja só
42.20.x, consolidamos `common/` + `42.15/` no `42/` único deste submod, mesmo raciocínio já aplicado
em `proximity-inventory`/`improvised-silencers`/`mini-health-panel`.
Mudança: conteúdo copiado sem alteração além do fix de tradução em LS-001.

## LS-004
Tipo: correção de crash recorrente na inicialização
Arquivo: `42/media/lua/client/hotbar/chbconfig.lua`
Motivo: `readConfigFile()` chamava `loadstring(content)`, mas Build 42.20 não expõe `loadstring`;
ao carregar `CleanHotbarConfig.txt`, a chamada falhava na linha 60 durante `OnGameBoot`.
Mudança: substituído o carregamento executável por um parser restrito ao schema conhecido do Clean
Hot Bar. O parser mantém compatibilidade com o `.txt` atual e com o `.lua` legado, aceita somente
as chaves e tipos esperados e não executa o conteúdo do arquivo.

## Itens sem alteração

Doze dos 13 arquivos Lua continuam cópia byte-a-byte do upstream `common/`; `chbconfig.lua` possui
somente a correção LS-004. Ver `INTEGRATION.md` para a análise completa da colisão real com
`simple-belt-flashlight` em `ISHotbar.refresh` (verificada segura independente da ordem de
carregamento, sem precisar de patch nem regra de ordem) e da checagem cruzada contra os demais
módulos bundlados neste pacote.
