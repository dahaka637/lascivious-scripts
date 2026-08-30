# Lascivious Shop

Servidor/autônomo para Project Zomboid Build 42.

## Fluxo

- `/shop` ou o ícone amarelo da loja abre a interface.
- O servidor lê `getZombieKills()` e horas completas de `getHoursSurvived()`.
- O primeiro registro importa retroativamente os contadores da vida atual.
- Compras, preços, descontos, saldo, entrega de itens e XP são validados no servidor.
- `Events.OnCharacterDeath` zera o saldo; regressão dos contadores nativos funciona como proteção adicional.
- Ofertas são globais, persistentes e rotacionadas por relógio real.

## Estrutura do catálogo

O catálogo fica em `42/media/lua/shared/LasciviousShop_Catalog.lua`. Ele possui 2.440 produtos: 2.249 itens, 155 veículos, uma cura emergencial e 35 perícias treináveis. A distribuição atual é: 255 alimentos, 54 bebidas, 20 armas de fogo, 185 armas corpo a corpo, 33 munições, 310 recursos, 48 produtos médicos, 557 peças de vestuário/equipamento, 195 móveis, 593 outros, 155 veículos e 35 pacotes de XP. Os IDs são estáveis e únicos; itens, veículos e perks são novamente validados pelo servidor quando o catálogo inicializa, e entradas indisponíveis são ocultadas do cliente.

Cada produto tem ID estável, categoria, preço-base e entrega do tipo `item`, `vehicle`, `cure` ou `xp`. A quantidade do carrinho representa quantas unidades o jogador escolheu; veículos são limitados a quatro linhas distintas por compra e têm posicionamento livre pré-validado antes do débito. Produtos de XP possuem um ícone próprio para a classe da habilidade. O primeiro pacote cobre exatamente o restante até o próximo nível; ao adicionar mais pacotes da mesma habilidade, o XP e o preço são recalculados para cobrir progressivamente os níveis seguintes. A quantidade é limitada pelos níveis restantes até o 10, quando o produto fica visualmente bloqueado e sem preço. O cliente envia somente IDs, quantidades e a revisão de preços; o servidor recalcula e valida tudo.

Pedidos de compra e transferência usam IDs persistidos para deduplicação. O saldo é reservado antes de qualquer efeito no mundo; uma falha total devolve o valor, uma entrega parcial cobra apenas a parte criada, e uma interrupção ambígua fica marcada no log para reconciliação sem reexecutar efeitos potencialmente já aplicados. Valores não finitos, payloads grandes, spam de comandos e dados persistidos corrompidos são rejeitados ou normalizados nos limites de autoridade.

O painel abre inicialmente ajustado à resolução, pode ser redimensionado pelos dois cantos inferiores e memoriza tamanho, posição e ordenação por personagem. O catálogo pode ser ordenado pela ordem padrão, nome crescente/decrescente, preço crescente/decrescente ou maior desconto. A pesquisa é imediata, ignora acentos e pontuação, trata singular/plural, reconhece sinônimos PT/EN e tolera erros e letras invertidas. O índice persistente é pré-aquecido fora da renderização, filtra somente IDs da categoria ativa, resolve correspondências diretas primeiro e executa a busca aproximada apenas quando necessário. Resultados, preços, layout, texturas e estruturas visuais reutilizáveis possuem caches independentes; somente os produtos da página atual são desenhados. Nomes e descrições maiores que o cartão deslizam suavemente enquanto o jogador mantém o mouse sobre o produto.

## Configuração

As opções Sandbox controlam créditos por abate/hora, roubo de créditos em mortes PvP, preservação opcional de saldo ao morrer, multiplicador geral, ativação e intervalo real das ofertas, quantidade de produtos e desconto mínimo/máximo. Por padrão a morte continua zerando créditos; com `PreserveCreditsOnDeath` ativo, o saldo é mantido, exceto pela porcentagem realmente roubada em morte causada por outro jogador. A opção de debug concede 10.000 créditos uma vez por vida para facilitar testes da loja.
