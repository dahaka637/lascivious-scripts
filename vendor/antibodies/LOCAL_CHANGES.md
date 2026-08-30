# Local Changes — Antibodies

## LS-006
Tipo: tradução PT-BR de sandbox
Arquivo novo: `42/media/lua/shared/Translate/PTBR/Sandbox_PTBR.txt`
Mudança: promovidas as 149 chaves do JSON PT-BR para o formato nativo com escapes decimais
ASCII-safe. Validação: paridade 149/149 com EN, sintaxe Lua 5.1 e reconstrução UTF-8 exata.

## LS-001
Tipo: compatibilidade B42.20
Arquivos: `42/media/lua/{client/antibodies_client.lua,server/antibodies_server.lua,client/ui/*.lua}`
Motivo: os módulos vanilla e os cinco módulos internos de TimedAction mudaram de caminho.
Mudança: aplicadas somente as sete correções de `require` comprovadas contra a instalação local da
Build 42.20.x. Mantida também a guarda do fix comunitário que impede criar prontuário remoto no
cliente antes do snapshot do servidor.

## LS-002
Tipo: compatibilidade de save/configuração e preservação de comportamento
Arquivos: `42/media/lua/shared/antibodies.lua`, `42/media/sandbox-options.txt`, traduções Sandbox e
`42/media/lua/shared/antibodies_medical_file.lua`
Motivo: o pacote comunitário renomeava o namespace das 67 opções e adicionava uma mecânica de
convalescença fora do escopo do fix, sem migração para prontuários existentes.
Mudança: preservados `player.modData.Antibodies`, o namespace interno/de rede `lgd_antibodies`, as
opções `lgd_antibodies_194_*`, a versão lógica 1.97 e o comportamento de recuperação original. A
mecânica adicional não foi levada ao bundle.

## LS-003
Tipo: correção de autoridade/NetTimedAction e isolamento Lua
Arquivos: os cinco arquivos em `42/media/lua/shared/timed_actions/`
Motivo: os wrappers upstream descartavam o retorno booleano do `:complete()` vanilla e aplicavam o
bônus de tratamento mesmo quando a ação era rejeitada. Quatro arquivos também vazavam captures
auxiliares como globals Lua.
Mudança: cada wrapper guarda o resultado vanilla, aplica o tratamento somente quando ele é
verdadeiro e retorna o mesmo valor ao engine. Todos os captures auxiliares agora são `local`.

## LS-004
Tipo: tradução e correção de carregamento de texto
Arquivos: `42/media/lua/shared/Translate/{EN,PTBR}/`
Motivo: o fix comunitário deixava apenas JSON ativo, mas `getText()` exige arquivo nativo; o arquivo
Sandbox EN original também tinha dez vírgulas ausentes e não compilava como Lua.
Mudança: restaurados `UI_EN.txt` e `Sandbox_EN.txt`, corrigidas as dez vírgulas e o nome da tabela
de `UI_Antibodies_EN` para a família reconhecida `UI_EN`, adicionada a chave de calorias e
corrigidos os dois placeholders de porcentagem (`%%`). Criados JSONs PT-BR completos
para UI (85/85) e Sandbox (149/149), com placeholders preservados. Os JSONs dos demais idiomas foram
preservados com o namespace de sandbox compatível.

## LS-005
Tipo: bundling / estrutura e identidade
Arquivo: `42/mod.info` e layout do submod
Motivo: isolamento conforme a arquitetura do pacote.
Mudança: criado `LS_Antibodies`, consolidando a base aplicável em `42/`; `common/media/` permanece
presente. Nome e descrição foram adaptados ao padrão do pacote; versão mínima fixada em 42.20.0.
