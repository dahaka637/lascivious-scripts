# 09 — Achados de produção

**Atualização:** 2026-08-27  
**Escopo:** erros observados no servidor dedicado após o início dos testes reais

Todo achado crítico/alto deve ser registrado aqui antes do patch, com causa, impacto, correção e
estado do reteste. A evidência original desta rodada está nos dois recortes de log entregues pelo
dono do projeto em 2026-08-27.

## PROD-001 — TimeVote chama o global Lua `next`, ausente no servidor

- **Severidade:** HIGH (erro recorrente em `OnTick`).
- **Evidência:** `refreshElectorate(Server.lua:126)` lança `Object tried to call nil`; a chamada da
  linha é `next(lastOnline)`. O erro reaparece a partir de `onTick(Server.lua:341)` enquanto o
  servidor está vazio.
- **Causa:** o ambiente Kahlua da Build 42.20 em produção não expõe o global `next` nesse contexto.
  Não é dado nulo: `lastOnline` é inicializado como tabela e só recebe tabelas no arquivo.
- **Impacto:** a ressincronização periódica da votação falha e polui o log; a atualização do
  eleitorado não completa no ciclo afetado.
- **Correção planejada:** reutilizar `sameOnlineSet(lastOnline, current)`, que já percorre as tabelas
  com `pairs`, eliminando a chamada ao global indisponível sem mudar a regra de estado.
- **Estado:** `PATCHED_STATIC / NEEDS_PROD_RETEST`. `next(lastOnline)` foi substituído por
  `not sameOnlineSet(lastOnline, current)`; todos os Lua passam em `luac5.1` e um harness carregou o
  `Server.lua` completo e executou 240 ticks de roster vazio com `next=nil`, sem erro.
- **Reteste:** servidor vazio por mais de 120 ticks; entrada/saída de jogador; voto solo e voto com
  dois clientes; ausência de novo stack trace.

## PROD-002 — `x_extends` do Skully resolve para caminho todo minúsculo no Linux

- **Severidade:** HIGH (quatro nós de ataque no chão não carregam no boot dedicado).
- **Evidência:** `AnimNode.Parse` falha ao abrir `2hdefault.xml`, `knifedefault.xml`,
  `1hdefault.xml` e `heavydefault.xml`, embora os arquivos existentes sejam respectivamente
  `2HDefault.xml`, `KnifeDefault.xml`, `1HDefault.xml` e `HeavyDefault.xml`.
- **Arquivos afetados:** `2HOnFloor.xml`, `KnifeOnFloor.xml`, `1HOnFloor.xml` e
  `HeavyOnFloor.xml` de `LS_SkullysFasterAttackSpeed`.
- **Causa:** `PZXmlUtil.parse()` resolve `x_extends` através do mapa de arquivos normalizado em
  minúsculas. Quando a resolução relativa não encontra entrada nesse mapa durante esse boot, o
  caminho normalizado vira acesso físico; em filesystem Linux case-sensitive o arquivo não existe.
- **Impacto:** os quatro nós `OnFloor` são descartados pelo parser; ataques contra zumbis no chão
  podem perder as alterações do mod ou usar fallback do engine.
- **Correção planejada:** materializar em cada filho o XML efetivo que o próprio
  `PZXmlUtil.resolve(child, parent)` produz e remover `x_extends`. Não serão criadas cópias com nome
  minúsculo, pois aliases introduziriam nós duplicados com o mesmo `m_Name`.
- **Estado:** `PATCHED_STATIC / NEEDS_PROD_RETEST`. Os quatro XMLs foram materializados, não há mais
  `x_extends` no bundle, todos passam em `xmllint` e os quatro deram `semantic_match=true` contra o
  DOM efetivo produzido pelo `PZXmlUtil` do JAR local atual. Os quatro também passam diretamente em
  `PZXmlUtil.parseXml`.
- **Reteste:** boot de servidor Linux sem `AnimNode.Parse`; ataques no chão com faca, uma mão, duas
  mãos e arma pesada.

## Mensagens classificadas, mas fora destes patches

- `Missing tile definition: blends_natural_01_TEST_27/43`: não há referência a esses tiles em
  `Contents/`; mensagem de mapa/tile externo ao código analisado.
- `Missing texture: media/textures/weather/fogwhite.png`: caminho de clima do engine, sem referência
  em `Contents/`.
- `No packet handler for type: ...` em `PacketsCache.<init>`: diagnóstico de inicialização do
  protocolo do engine, sem stack de mod.
- `IsoThumpable not found on square ...`: evento isolado sem stack ou módulo atribuído; nenhum texto
  correspondente existe em `Contents/`. Manter sob observação somente se vier acompanhado de stack
  reproduzível.
