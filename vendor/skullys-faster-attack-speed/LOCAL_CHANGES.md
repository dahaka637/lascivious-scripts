# Local Changes — Skully's Faster Attack Speed

## LS-001
Tipo: bundling / identidade do mod
Arquivo: `42/mod.info`
Motivo: rebrand para o namespace do pacote (mod não tem nenhum código Lua, logo nenhum check do
próprio Mod ID — Categoria A, seção 20 da arquitetura).
Mudança: `id=SkullysFasterAttackSpeed` -> `id=LS_SkullysFasterAttackSpeed`; `name=`/`description=`
reescritos. Removida a linha `icon=logo.png` — o arquivo `logo.png` não existe em lugar nenhum do
download do upstream (referência quebrada pré-existente); `poster=poster.png` mantido.

## LS-002
Tipo: estrutura / scaffold
Arquivo novo: `common/media/.gitkeep`
Motivo: upstream shippa `common/` totalmente vazio (nem placeholder tem); Build 42 espera que o
diretório exista.

## LS-003
Tipo: compatibilidade / servidor Linux
Arquivos: `42/media/AnimSets/player/melee/{1handed/1HOnFloor.xml,1handed/KnifeOnFloor.xml,2handed/2HOnFloor.xml,heavy/HeavyOnFloor.xml}`
Motivo: em produção, `PZXmlUtil` normalizou os caminhos relativos de `x_extends` para minúsculas e
tentou abrir fisicamente `1hdefault.xml`, `knifedefault.xml`, `2hdefault.xml` e `heavydefault.xml`.
Esses nomes não existem num filesystem Linux case-sensitive, então os quatro nós eram descartados
por `AnimNode.Parse` durante o boot.
Mudança: materializado em cada `*OnFloor.xml` o resultado estrutural exato de
`PZXmlUtil.resolve(child, parent)` e removido `x_extends`. Não foram criados aliases minúsculos, para
não registrar nós duplicados com o mesmo `m_Name`. Os quatro resultados deram `semantic_match=true`
contra a herança upstream e passam em `xmllint`.

## Itens sem alteração

Os cinco arquivos sem herança problemática (`1HDefault.xml`, `KnifeDefault.xml`, `2HDefault.xml`,
`SpearDefault.xml`, `HeavyDefault.xml`) continuam cópia byte-a-byte do upstream. Os quatro
`*OnFloor.xml` só diferem pela materialização descrita em LS-003; o comportamento XML efetivo é o
mesmo. Ver `INTEGRATION.md` para o que muda em relação ao vanilla.

## Itens ignorados deliberadamente

- `42/preview.png` — duplicata byte-idêntica de `poster.png`, não referenciada por nenhuma chave do
  `mod.info`. Não bundlado (preservado só no snapshot `vendor/` por fidelidade).
