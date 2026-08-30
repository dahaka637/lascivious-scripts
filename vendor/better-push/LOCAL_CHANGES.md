# Local Changes — Better Push

## LS-005
Tipo: tradução PT-BR de sandbox
Arquivos: `42/media/lua/shared/Translate/PTBR/{Sandbox.json,Sandbox_PTBR.txt}`
Mudança: adicionadas as 17 chaves PT-BR completas; o TXT nativo usa escapes decimais ASCII-safe.
Validação: paridade 17/17 com EN, sintaxe Lua 5.1 e reconstrução UTF-8 exata.

## LS-004 (the big one — read this first, supersedes LS-001's approach)
Tipo: reescrita completa / multiplayer, desincronização
Arquivos: `42/media/lua/shared/BetterPush_Shared.lua`, `42/media/lua/client/BetterPush_Client.lua`,
`42/media/lua/server/BetterPush_Server.lua`
Motivo: usuário reportou (2026-08-25) relatos de que o Better Push original está desatualizado e
quebrado em multiplayer, e pediu um patch manual completo focado em MP/desincronização. Investigação
encontrou um mod de terceiro
(`/home/dahaka/.local/share/Steam/steamapps/workshop/content/108600/3779917103`, "[B42.20] 更好的推搡
Better Push", `id=BetterPushB4220`, autor original Semzuwu, adaptação B42.20 por "wand_39") que tenta
corrigir o mesmo mod — **estudado como referência, nunca bundlado nem copiado** (não é upstream deste
módulo, é um mod de terceiro não relacionado, não faz parte deste pacote). A descrição dele já
indicava o problema: "重构了推搡识别、方向筛选和多人同步" (reestruturou detecção de empurrão, filtro de
direção e sincronização multiplayer).

Comparando o código dele com o nosso, identifiquei a causa raiz real do "quebrado em MP": o handler
`Events.OnWeaponHitCharacter` dispara **em todo cliente conectado**, não só no cliente de quem deu o
empurrão. O `BetterPush_Client.lua` original (upstream, e nosso LS-001) não tinha nenhuma guarda pra
isso — então com N jogadores online, cada um dos N clientes calculava sua própria cadeia de dominó e
mandava seu próprio comando `Trigger` pro servidor **para o mesmo empurrão**, multiplicando o efeito
e criando exatamente o tipo de dessincronização relatada. Esse bug já existia na versão que
bundlamos originalmente (upstream 1.4) e no nosso próprio LS-001 (que só validava o que o servidor
recebia, mas não impedia múltiplos clientes de mandar a mesma requisição pro mesmo evento).

Mudança — reescrita completa dos três arquivos, com arquitetura própria (não é uma cópia do mod de
terceiro, mas foi informada por ele):

1. **Guarda "só o atacante local age"**: `if isClient() and player ~= getPlayer() then return end`
   no `BetterPush_Client.lua` — a correção central. Sem isso, nada mais adianta.
2. **Cliente não manda mais a cadeia inteira** — só reporta qual zumbi foi empurrado (ID + posição).
   O servidor agora calcula a cadeia inteira sozinho, usando `BetterPush.getDominoChain()` com dados
   100% server-authoritative. Isso substitui a abordagem do LS-001 (que validava uma lista vinda do
   cliente) por uma onde o cliente nunca escolhe zumbi nenhum — só reporta o alvo inicial.
3. **Busca de cadeia agora é direcional**: `getDominoChain` calcula produto escalar (quão "à frente"
   um zumbi candidato está, na direção do empurrão original) e produto vetorial (desvio lateral),
   em vez de simplesmente pegar o zumbi não-usado mais próximo em qualquer direção. Isso evita a
   cadeia zigueweguear pra trás ou pro lado. Também pula zumbis já derrubados
   (`zombie:isKnockedDown()`, checagem que não existia antes).
4. **Sincronização explícita via broadcast**: o servidor agora manda um comando `Knockdown` pra
   *todos* os clientes pra cada zumbi da cadeia (com ID/posição/atraso), e cada cliente aplica o
   knockdown na sua própria cópia local do zumbi via uma fila com o mesmo atraso escalonado. Antes,
   o servidor só mexia no próprio objeto zumbi dele e torcia pra sincronização genérica de estado
   propagar pros clientes — não confiável.
5. **`findZombie()` novo**: resolve zumbi por ID online, com fallback por posição (raio de 1.5
   tiles) caso o ID ainda não tenha propagado pra essa máquina — mais robusto contra a janela de
   atraso entre servidor e cliente.
6. **Rate limiting nos dois lados**: cliente (500ms por zumbi) e servidor (350ms por jogador,
   autoritativo — não pode ser burlado por um cliente modificado) — evita reenvio duplicado se o
   evento disparar mais de uma vez pro mesmo empurrão.
7. **`knockDownZombie()` simplificado**: só `setHitReaction("Shove")` + `setKnockedDown(true)`, em
   vez dos 5 métodos especulativos do upstream — evita empilhar setters de knockdown possivelmente
   conflitantes no mesmo zumbi.

`LS-001` (patch de validação server-side original) fica registrado abaixo só para rastreabilidade —
a lógica dele foi absorvida e substituída por esta reescrita, não é mais o estado atual do arquivo.

**Ainda não testado em jogo** (client + dedicated server + MP com 2+ jogadores) — ver seção
"Perguntas para revisitar" no fim deste arquivo.

## LS-001 (histórico — absorvido pelo LS-004 acima)
Tipo: servidor / autoridade multiplayer
Arquivo: `42/media/lua/server/BetterPush_Server.lua`
Motivo: `onClientCommand` aceitava `args.targetIDs` do cliente sem nenhuma validação — qualquer
quantidade de IDs de zumbi, em qualquer lugar do mapa, sem checar Força do jogador nem distância. Um
cliente modificado podia mandar uma lista com o ID de todo zumbi online do servidor e derrubar todos
de uma vez, sem precisar de Força nem estar perto — um bypass real de dificuldade, não só cosmético.
Viola a diretriz de autoridade server-side da seção 29 da arquitetura ("existe comando sem
validação?").
Mudança (na época): recálculo server-side do limite de zumbis via
`BetterPush.getMaxZombiesForStrength(player:getPerkLevel(Perks.Strength))` + checagem de distância.
Superado pelo LS-004, que também elimina a lista de alvos vinda do cliente por completo.

## LS-002
Tipo: bundling / identidade do mod
Arquivo: `42/mod.info`
Motivo: rebrand para o namespace do pacote (mod não faz nenhum check do próprio Mod ID — Categoria A,
seção 20 da arquitetura).
Mudança: `id=BetterPush` -> `id=LS_BetterPush`; `name=`/`description=` reescritos. `versionMin=42.0`
e `modversion=1.4` preservados do upstream.

## LS-003
Tipo: tradução / correção de bug
Arquivo novo: `42/media/lua/shared/Translate/EN/Sandbox_EN.txt`
Motivo: upstream só tinha `Sandbox_EN.json` (formato aninhado incomum `{"EN": {...}}`, mas de todo
jeito nada no mod lê JSON — painel nativo de Sandbox Options só lê `.txt`).
Mudança: criado `Sandbox_EN.txt` com as chaves já presentes no JSON, texto idêntico.

## Itens sem alteração

`sandbox-options.txt`, `icon.png`, `poster.png` são cópias byte-a-byte do upstream `42/` —
confirmado via `diff`. Os três arquivos Lua (`BetterPush_Shared.lua`, `BetterPush_Client.lua`,
`BetterPush_Server.lua`) foram reescritos por completo no LS-004 — não são mais cópias do upstream,
ver esse item para o que mudou e por quê.

## Perguntas para revisitar em updates futuros

- **Testar em jogo antes de considerar o LS-004 concluído**: client + dedicated server + MP real com
  2+ jogadores simultâneos empurrando zumbis ao mesmo tempo. Validar que (a) só um dominó acontece
  por empurrão mesmo com vários jogadores online, (b) o efeito aparece pra todo mundo no tempo
  esperado, (c) a cadeia segue a direção do empurrão de forma sensata.
- Os valores de cooldown (500ms cliente / 350ms servidor) foram herdados do mod de terceiro
  estudado como referência — ajustar se algum jogador reportar empurrões legítimos sendo ignorados
  em sequência rápida.
- Se o upstream (Semzuwu) lançar uma atualização própria que corrija isso, comparar a abordagem dele
  com o LS-004 antes de decidir manter, ajustar ou substituir nosso patch.
- Este pacote nunca deve depender do Workshop item `3779917103` nem bundlá-lo — ele só serviu de
  referência de leitura para este patch.
