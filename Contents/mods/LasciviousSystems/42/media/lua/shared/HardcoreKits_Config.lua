-- Configuracao central e ajustavel do mod. Nenhum outro modulo deve ter
-- um numero magico escondido no meio da logica -- se for um peso, uma
-- chance ou um limite, ele mora aqui.
require "HardcoreKits_Protocol"

HardcoreKitsConfig = {

    -- ---------- Kit Inicial ----------
    InitialKitEnabled = true,
    -- Quando ligado, o Kit Inicial vira um direito unico por conta: depois
    -- que um claim feito com esta opcao ativa e consumido, mortes/personagens
    -- futuros nao liberam outro. Desligado por padrao e nao retroativo para
    -- claims antigos que nao tenham sido marcados nesse modo.
    InitialKitSingleUseEnabled = false,
    -- antiabuso de conta (secao 6.2 da especificacao) -- de proposito e tempo
    -- REAL, nao tempo de jogo: o objetivo e impedir criar personagem/resgatar/
    -- matar/criar outro em sequencia rapida, e tempo de jogo daria pra furar
    -- so dormindo ou acelerando o relogio in-game. Desligado por padrao --
    -- ligue InitialKitCooldownEnabled se quiser essa trava.
    InitialKitCooldownEnabled = false,
    InitialKitCooldownRealHours = 2,

    InitialFoodQuantityMin = 1,
    InitialFoodQuantityMax = 8,
    -- % de chance do sorteio de comida vir do pool principal (enlatados/conservas)
    InitialFoodPrimaryPoolChance = 50,
    -- dentro do pool principal, % que e enlatado vs conserva -- 50 = totalmente
    -- aleatorio entre os dois, sem favorecer nenhum
    InitialFoodCannedShareOfPrimary = 50,

    InitialDrinkQuantityMin = 1,
    InitialDrinkQuantityMax = 6,
    InitialWaterChance = 50,

    -- pesos por categoria de arma corpo a corpo (soma nao precisa ser 100, e normalizado).
    -- "modded" so entra em jogo com ModdedContentEnabled=true E pelo menos uma
    -- arma corpo a corpo de outro mod encontrada no scan -- vazio, e ignorado
    -- automaticamente (mesma regra de qualquer categoria vazia). Nao exposto
    -- no sandbox de proposito, ja que so importa quando o scan esta ligado.
    -- Sistema de peso continua existindo (ajustavel aqui direto), mas o default
    -- e totalmente aleatorio: nenhuma categoria favorecida em relacao a outra.
    InitialMeleeCategoryWeights = {
        smallblunt = 1,
        blunt = 1,
        blade = 1,
        axe = 1,
        spear = 1,
        modded = 1,
    },
    -- faixa de condicao (fracao da condicao maxima do item) entregue no kit inicial
    InitialMeleeConditionMinFraction = 0.4,
    InitialMeleeConditionMaxFraction = 1.0,

    -- 2026-08-22: raised 50->100, explicit request ("deixe o default 100"),
    -- no longer sandbox-configurable at any other value.
    InitialFirearmChance = 100,
    InitialAmmoBoxesMin = 1,
    InitialAmmoBoxesMax = 4,
    InitialAmmoBoxesWeights = { [1] = 45, [2] = 30, [3] = 15, [4] = 10 },

    -- modo alternativo de sorteio pra comida/bebida (Kit Inicial E recompensa
    -- semanal): quando true, sorteia a QUANTIDADE primeiro e depois sorteia o
    -- TIPO uma vez por unidade (cada unidade pode vir de um item diferente).
    -- Quando false (padrao), sorteia o tipo uma unica vez e entrega N copias
    -- dele -- comportamento original.
    -- 2026-08-22: flipped true->false, explicit request ("para que default
    -- ele venha desativado"), no longer a sandbox option.
    FoodDrinkMultiRollMode = false,

    -- pesos por tier de mochila
    InitialBackpackTierWeights = {
        escolar = 40,
        comum = 35,
        grande = 20,
        militar = 5,
    },

    -- categoria "recurso" do Kit Inicial (ferramenta/item util avulso, ex:
    -- lanterna, bussola, itens de primeiros socorros -- ver HardcoreKitsPools.Resources).
    -- Sempre exatamente 1 item (como a arma corpo a corpo), so a quantidade
    -- empilhada varia.
    InitialResourceQuantityMin = 1,
    InitialResourceQuantityMax = 2,
    -- % de chance do sub-sorteio de "recurso" virar um dos dois resultados
    -- especiais em vez do sorteio normal de itens distintos -- checados em
    -- sequencia (bolsa de trauma primeiro, depois kit medico): a bolsa de
    -- trauma (HardcoreKitsPools.TraumaBagBag/Contents, mochila grande) e o
    -- kit medico (MedicalKitBag/Contents, maleta pequena) sao dois bundles
    -- INDEPENDENTES desde 2026-08-05 -- os dois podem cair, pedido explicito
    -- do usuario. Configs proprias do Kit Inicial, nao compartilhadas com as
    -- equivalentes da Recompensa de Sobrevivencia (SurvivalTraumaBagChance/
    -- SurvivalMedicalKitChance, logo abaixo).
    InitialTraumaBagChance = 15,
    InitialMedicalKitChance = 15,

    -- "equipamento superior": quando ligado, o sorteio de arma corpo a corpo
    -- do Kit Inicial (rollMeleeItem, so aqui -- NAO afeta o sub-sorteio melee
    -- da Recompensa de Sobrevivencia) so considera itens cujo dano real
    -- (Item:getMaxDamage(), o mesmo campo MaxDamage do script) seja >=
    -- InitialMeleeMinDamage. Pedido explicito do usuario, que sugeriu "metade
    -- do dano maximo da Katana, acho que e uns 5" como referencia -- checado
    -- contra media/scripts/generated/items/weapon.txt: a Katana tem
    -- MaxDamage=8.0 (nao ~10), e e disparada a arma de MAIOR dano do mod
    -- inteiro -- a segunda colocada fica em 3.0 (Sledgehammer, Machete,
    -- Sword, BlockMaul e mais um punhado de itens "pesados"). Ou seja, metade
    -- exata da Katana (4.0) deixaria o pool com APENAS a Katana, o que
    -- provavelmente nao e o espirito de um filtro de "dano moderado pra
    -- cima". 2026-08-08: recalibrado pra 2.0 (era 3.0) a pedido explicito do
    -- usuario ("fica equilibrado") -- pega ~36 itens (Katana + o patamar de
    -- 3.0, o de ~2.0-2.9, e o proprio 2.0) num pool de 137, um recorte bem
    -- mais generoso que o de 3.0 (~18 itens) sem deixar de filtrar a maioria
    -- fraca do pool (a maior parte fica abaixo de 2.0). Ajustavel livremente
    -- pelo sandbox se quiser mais restrito (ate 8.0 = so Katana) ou mais
    -- permissivo. Pool derivado calculado em HardcoreKits_Validation.lua
    -- (MeleeHighDamageByCategory), recalculado junto com o resto da
    -- validacao de pools (boot + RevalidatePoolsEveryRealHours).
    InitialMeleeHighDamageOnly = false,
    InitialMeleeMinDamage = 2.0,

    -- ---------- Recompensa de Sobrevivencia ----------
    -- DESATIVADA (2026-08-28): bug conhecido em producao -- apos o 1o
    -- resgate, resgates seguintes liberam de novo bem antes do proximo marco
    -- esperado (ver comentario detalhado em HardcoreKits_State.lua, secao
    -- "Recompensa de Sobrevivencia"). Fixo em false e FORA do mapeamento de
    -- sandbox (HardcoreKits_SandboxBridge.lua) de proposito, pra nenhum admin
    -- religar sem querer enquanto isso nao for investigado com calma. So
    -- reativar depois de identificar a causa raiz.
    SurvivalRewardEnabled = false,
    SurvivalRewardIntervalHours = 168, -- 7 dias
    SurvivalMaximumStoredRewards = 3, -- 0/nil = sem limite

    SurvivalRewardCountWeights = { [1] = 60, [2] = 30, [3] = 10 },

    -- pedido explicito do usuario: chance de deixar TODAS as categorias com
    -- peso igual (totalmente aleatorio) em vez dos pesos configurados abaixo
    -- -- so muda o VALOR usado pra cada categoria ja disponivel (continua
    -- respeitando pool vazio -- uma categoria sem nada pra dar nunca entra no
    -- sorteio, com ou sem este toggle). Nao afeta o sub-sorteio melee/firearm
    -- dentro de "combat" (SurvivalCombatWeights, logo abaixo) nem o kit
    -- medico/bolsa de trauma (esses tem a propria chance separada) -- so as
    -- categorias de "slot" (comida/bebida/recurso/combate/municao).
    -- 2026-08-22: flipped false->true, explicit request ("deixar... chances
    -- de categorias totalmente aleatórias como default"), no longer a
    -- sandbox option -- every category weight below is now dead weight by
    -- design, kept only as a code-level fallback.
    SurvivalCategoriesFullyRandom = true,
    SurvivalCategoryWeights = {
        food = 35,
        drink = 25,
        resource = 20,
        combat = 10,
        -- municao ISOLADA (nao ligada a nenhuma arma especifica) -- categoria
        -- propria desde 2026-08-06, pedido explicito do usuario ("adiciona
        -- uma nova categoria tambem de municao isolada"). Antes disso, a
        -- municao so existia como sub-sorteio dentro de "combat"
        -- (SurvivalCombatWeights.ammo, removido) -- agora arma de fogo
        -- SEMPRE vem com 1 caixa garantida (ver rollSurvivalCombat), e essa
        -- categoria aqui e a UNICA forma de ganhar municao avulsa, solta, de
        -- um tipo aleatorio, sem estar ligada a nenhuma arma que o
        -- personagem tenha recebido.
        ammo = 10,
    },
    -- sub-sorteio dentro da categoria "combat" (so melee vs firearm agora --
    -- municao saiu daqui, virou categoria propria acima)
    SurvivalCombatWeights = {
        melee = 45,
        firearm = 20,
    },

    SurvivalFoodQuantityMin = 1,
    SurvivalFoodQuantityMax = 3,
    SurvivalFoodPrimaryPoolChance = 50,

    SurvivalDrinkQuantityMin = 1,
    SurvivalDrinkQuantityMax = 3,
    SurvivalWaterChance = 50,

    SurvivalResourceQuantityMin = 1,
    SurvivalResourceQuantityMax = 3,
    -- mesmo mecanismo do Kit Inicial acima (bolsa de trauma checada primeiro,
    -- depois kit medico, os dois independentes) -- resultado raro e mais
    -- empolgante, mesmo espirito do bonus de arma de fogo do Kit Inicial.
    SurvivalTraumaBagChance = 15,
    SurvivalMedicalKitChance = 15,

    -- quantos TIPOS de item aleatorio (alem da bandagem garantida) entram no
    -- kit medico a cada entrega -- compartilhado entre Kit Inicial e
    -- Recompensa de Sobrevivencia (o kit medico e o mesmo item/mesmo pool
    -- nos dois, so a CHANCE de cair e que e configuravel por tipo de resgate
    -- em separado, ver Initial/SurvivalMedicalKitChance). Pedido explicito
    -- do usuario: tipos aleatorios a cada vez, nunca a mesma combinacao.
    MedicalKitRandomItemCountMin = 2,
    -- 2026-08-22: raised 3->5, explicit request, no longer sandbox-configurable.
    MedicalKitRandomItemCountMax = 5,

    -- quantas caixas quando a categoria "ammo" ISOLADA (acima) e sorteada --
    -- default 1-5, pedido explicito do usuario. NAO e usado pela caixa
    -- garantida de arma de fogo (essa e sempre exatamente 1, hardcoded, ver
    -- rollSurvivalCombat -- "quando cai arma sempre cai 1 caixa").
    SurvivalAmmoBoxQuantityMin = 1,
    SurvivalAmmoBoxQuantityMax = 5,

    -- municao avulsa: da preferencia pra tipos compativeis com arma(s) de
    -- fogo que o personagem JA tem no inventario principal ou na mochila
    -- equipada (recursivo, pega o que estiver dentro de bolsas aninhadas
    -- tambem) -- pedido explicito do usuario: "se o jogador tem um revolver
    -- calibre 38, da preferencia pra cair municao 38". Com mais de uma arma
    -- diferente, qualquer uma das municoes compativeis ganha a mesma
    -- preferencia (nao so a "primeira" arma) -- sem nenhuma compativel,
    -- continua 100% aleatorio entre todos os tipos, sem excecao nenhuma.
    -- SurvivalAmmoPreferOwnedWeight = quantas vezes mais provavel um tipo
    -- compativel fica em relacao a um tipo comum (peso 1) -- NAO uma
    -- garantia, so preferencia. Ver rollSurvivalSingleResult (categoria "ammo").
    SurvivalAmmoPreferOwnedEnabled = true,
    SurvivalAmmoPreferOwnedWeight = 5,

    -- pesos por tier de raridade de arma de fogo na recompensa semanal --
    -- o sistema de peso existe (ajustavel via sandbox), mas o default e
    -- totalmente aleatorio: nenhum tier favorecido em relacao a outro.
    SurvivalFirearmTierWeights = {
        common = 33,
        uncommon = 33,
        rare = 33,
    },

    -- ---------- Bonus de Habilidade (skill boost) ----------
    -- Feature pedida pelo usuario: apos o sorteio normal, bonus de XP em uma
    -- quantidade configuravel de grupos inteiros (Kit Inicial) ou chance de
    -- bonus numa skill/grupo (Recompensa de Sobrevivencia). UM toggle so
    -- controla os dois -- ver HardcoreKits_Rolls.lua.
    SkillBoostEnabled = true,

    -- quantidade de grupos/classes boostados no Kit Inicial. O sorteio nao
    -- repete grupo e limita ambos os valores ao numero de grupos realmente
    -- disponiveis (hoje 6). Com o default 6/6, todas as seis classes recebem
    -- bonus, mas o tier e a quantidade de XP continuam aleatorios por classe.
    InitialSkillGroupCountMin = 6,
    InitialSkillGroupCountMax = 6,

    -- peso do TIER (muito pouco/baixo/medio/alto) de cada grupo/skill
    -- sorteada. Default 30/30/20/20: muito pouco e baixo continuam sendo os
    -- mais comuns, mas alto agora tem o mesmo peso de medio.
    SkillBoostTierWeights = { verylow = 30, low = 30, medium = 20, high = 20 },

    -- janela de XP por tier, em NIVEIS (escala 0 a 10 -- os mesmos 10
    -- quadradinhos de nivel que o jogo mostra pra qualquer skill), NAO em
    -- porcentagem do total (tentativa anterior, descartada por ser
    -- desproporcional -- ver licao abaixo). Numeros podem ter casas decimais
    -- (ex: min=1.64) -- HardcoreKits_Rolls.lua converte a fracao numa fracao
    -- linear do custo do proximo nivel. alto.max = 10 de proposito: contando
    -- SEMPRE a partir do zero, 10 niveis e por definicao o total inteiro pra
    -- platinar aquela skill (perk:getTotalXpForLevel(10) e a soma de
    -- getXpForLevel(1) ate (10)) -- "equivalente a platinar", nem mais nem
    -- menos, exatamente como pedido.
    --
    -- LICAO desta calibracao (segunda tentativa, a primeira foi em % do
    -- total e ficou desproporcional em jogo real -- "baixo" dando o
    -- equivalente ao teto do "medio", etc): a curva real de XP por nivel do
    -- jogo e concentrada nos niveis finais (getXpForLevel(10) custa muito
    -- mais que getXpForLevel(1)), entao uma PORCENTAGEM do total podia
    -- cobrir varios niveis iniciais baratos de uma vez, virando um pulo bem
    -- maior do que a % sozinha sugeria. Calibrar em NIVEIS em vez de %
    -- resolve isso de raiz: um teto de "3 niveis" nunca custa mais do que o
    -- custo real dos niveis 1+2+3 daquela skill especifica, nao importa o
    -- quao cara ou barata a curva seja -- sem precisar adivinhar percentual
    -- nenhum. Ainda assim, ver o campo Skills do log de auditoria
    -- (HardcoreKits_Audit.lua) pra conferir os numeros reais de XP entregue
    -- contra o total pra platinar, caso precise de mais um ajuste fino.
    SkillBoostTierLevels = {
        verylow = { min = 0.5, max = 2 },
        low     = { min = 1,   max = 3 },
        medium  = { min = 2,   max = 5 },
        high    = { min = 5,   max = 10 },
    },

    -- Recompensa de Sobrevivencia: chance (%) de, ALEM dos resultados
    -- normais, tambem sortear uma unica skill especifica (dentre as 35, peso
    -- igual pra cada uma) pra ganhar bonus baixo/medio/alto. Raro de proposito.
    SurvivalSkillBonusChance = 8,

    -- DADO que o bonus acima disparou: chance (%) de, em vez de UMA skill
    -- especifica, o bonus valer pro GRUPO INTEIRO (mesmo tratamento do Kit
    -- Inicial -- todas as skills daquele grupo, cada uma com seu proprio
    -- sorteio de XP dentro do tier). Duplo sorteio independente: primeiro
    -- decide grupo-vs-skill-unica (esta chance), DEPOIS sorteia o tier
    -- (muito pouco/baixo/medio/alto, SkillBoostTierWeights) -- pedido
    -- explicito do usuario. Pequeno de proposito: o caso normal continua
    -- sendo uma unica skill.
    SurvivalSkillBonusGroupChance = 10,

    -- ---------- Roleta / UI ----------
    RouletteSpeedMultiplier = 1.0,
    RouletteStepDurationMs = 2200,
    RoulettePauseBetweenMs = 1000, -- pausa depois que o item alvo fixa, antes do proximo sorteio

    -- "Modo roleta rapida": pedido explicito do usuario. Em vez de UMA roleta
    -- grande revelando passo a passo em sequencia, revela em LOTES de
    -- FastRouletteBatchSize roletas menores girando em paralelo (a ultima
    -- leva o que sobrar, pode ter menos itens que o tamanho do lote). Dentro
    -- de um lote, cada roleta comeca a girar FastRouletteStaggerMs depois da
    -- anterior (efeito cascata); o mesmo intervalo tambem e usado como pausa
    -- entre um lote pousar e o proximo lote aparecer -- o usuario descreveu
    -- os dois como "0.5 segundos", entao um unico valor cobre as duas coisas
    -- em vez de duas configs quase identicas. Enquanto ativo, SOBREPOE
    -- RouletteSpeedMultiplier/RouletteStepDurationMs (giro sempre dura
    -- FastRouletteStepDurationMs, sem view do multiplicador de velocidade) --
    -- RoulettePauseBetweenMs tambem fica sem efeito nas roletas rapidas (cada
    -- uma gira uma vez so, a pausa entre lotes e quem manda). O resumo final
    -- (HardcoreKitsSummaryPanel) so aparece depois que TODOS os lotes
    -- terminam (nao mais progressivo a cada passo) -- ver
    -- HardcoreKitsRouletteFastRunner em HardcoreKits_Roulette.lua.
    -- 2026-08-22: flipped false->true, explicit request ("deixa default
    -- ativo"), no longer a sandbox option (nor is the rest of the roulette
    -- timing family below it).
    FastRouletteMode = true,
    FastRouletteBatchSize = 3,
    FastRouletteStepDurationMs = 1000,
    FastRouletteStaggerMs = 500,

    -- ---------- Conteudo moddado (secao nova) ----------
    -- QUANDO TRUE: alem dos pools curados a mao acima, o mod tambem escaneia
    -- (uma vez no boot + a cada RevalidatePoolsEveryRealHours, cacheado --
    -- nunca em tempo real durante um sorteio) todos os itens carregados que
    -- NAO sejam do namespace Base.* (ou seja, so itens de OUTROS mods
    -- instalados) e inclui automaticamente COMIDA e ARMA CORPO A CORPO (as
    -- duas categorias com um sinal de script confiavel: ItemType=Food, e
    -- ItemType=Weapon sem municao). Bebida e recurso ficam DE FORA do scan de
    -- proposito -- o jogo nao tem um jeito seguro de diferenciar uma bebida
    -- moddada de um combustivel/produto quimico moddado (os dois usam o mesmo
    -- mecanismo generico de "container de fluido"), e "recurso" nao e uma
    -- categoria nativa do jogo (e so a nossa propria curadoria por exclusao) --
    -- pra essas duas, continue usando HardcoreKitsAdminOverrides.ForceInclude.
    -- Pula qualquer fullType listado em ModdedContentExcludeList ou
    -- HardcoreKitsAdminOverrides.Exclude. O vanilla (Base.*) NUNCA passa por
    -- esse scan -- os pools curados acima ja cobrem ele por completo. Ver
    -- HardcoreKits_ModdedContent.lua.
    ModdedContentEnabled = false,
    -- separado do toggle geral de proposito: armas de mod precisam de
    -- ammoBox/magazine corretos (resolvidos via weapon:getAmmoBox()/
    -- getMagazineType() na propria instancia, nao adivinhado por nome -- ver
    -- HardcoreKits_ModdedContent.lua), mas isso so garante COMPATIBILIDADE
    -- MECANICA, nao BALANCEAMENTO -- uma arma moddada pode ser absurdamente
    -- forte/rara e ainda assim passar por todos os filtros tecnicos. Fica
    -- desligado por padrao mesmo com ModdedContentEnabled=true; o dono do
    -- servidor que decide se confia nas armas dos mods que instalou.
    ModdedContentIncludeFirearms = false,
    -- lista de fullTypes SEMPRE ignorados pelo scan de conteudo moddado, alem
    -- do que ja esta em HardcoreKitsAdminOverrides.Exclude (que tambem vale
    -- pros pools curados a mao). Texto livre nao da pra expor como opcao de
    -- sandbox (boolean/integer/double/enum apenas) -- edite esta lista aqui
    -- a mao. Formato: um fullType por entrada, EXACTAMENTE como aparece no
    -- item (ex: "OutroMod.ItemRuim").
    ModdedContentExcludeList = {
        -- "OutroMod.ItemRuim",
    },

    -- ---------- Recurso: peso por item ("give rate inverso") ----------
    -- alguns itens do pool de Recurso (HardcoreKits_Pools.Resources) sao
    -- uteis mas menos essenciais que os outros -- em vez de sumirem do pool,
    -- ficam com peso reduzido (ainda podem cair, so com menos frequencia).
    -- ResourceReducedWeightPercent = peso relativo (%) desses itens
    -- comparado a um item "normal" (100 = mesma chance, 0 = nunca cai).
    -- ResourceReducedItems = lista curada A MAO pelo usuario (nao vira
    -- sandbox option: seria uma lista de ~19 fullTypes, e o sistema de
    -- sandbox do jogo so tem boolean/integer/double/enum -- mesmo motivo de
    -- WelcomeMessageText/ModdedContentExcludeList acima).
    ResourceReducedWeightPercent = 35,
    ResourceReducedItems = {
        ["Base.Coldpack"] = true,
        ["Base.Zipties"] = true,
        ["Base.Funnel"] = true,
        ["Base.MagnifyingGlass"] = true,
        ["Base.DuctTape"] = true,
        ["Base.Glue"] = true,
        ["Base.WireStack"] = true,
        ["Base.Sheet"] = true,
        ["Base.Twine"] = true,
        ["Base.Whistle"] = true,
        ["Base.CompassDirectional"] = true,
        ["Base.RadioBlack"] = true,
        ["Base.Battery"] = true,
        ["Base.WalkieTalkie2"] = true,
        ["Base.Tarp"] = true,
        ["Base.InsectRepellent"] = true,
        ["Base.Soap2"] = true,
        ["Base.UmbrellaBlack"] = true,
        ["Base.Extinguisher"] = true,
    },

    -- ---------- Arma corpo a corpo: penalidade por peso real ----------
    -- classificacao DINAMICA, sem lista fixa: toda arma cujo Weight real do
    -- script (Item:getActualWeight()) seja >= MeleeHeavyWeightThreshold
    -- recebe MeleeHeavyReducedWeightPercent como peso relativo dentro da sua
    -- categoria. Uma arma leve continua com peso 100. Exemplo: 35 significa
    -- que cada arma pesada tem peso 35 contra 100 de cada arma leve (65%
    -- menos propensao relativa); 100 desliga a penalidade e 0 impede armas
    -- pesadas de cair. Aplica-se ao Kit Inicial e a Recompensa de
    -- Sobrevivencia, inclusive a armas corpo a corpo detectadas de outros
    -- mods. O limite e inclusivo: default 3.0 classifica Weight >= 3.0.
    MeleeHeavyWeightThreshold = 3.0,
    MeleeHeavyReducedWeightPercent = 35,

    -- ---------- Diversos ----------
    -- 2026-08-22: flipped true->false, explicit request ("default deixa
    -- desativado"), no longer a sandbox option.
    EnableAuditLog = false,
    -- habilita comandos administrativos de diagnostico/reset. Fixo em false
    -- aqui -- o valor real vem de HardcoreKits_SandboxBridge.lua, computado
    -- (singleplayer de verdade + LasciviousFactionsSystem.Debug no sandbox),
    -- nunca verdadeiro numa sessao MP de verdade, entao ferramentas de
    -- recuperacao nunca ficam expostas em live.
    DebugToolsEnabled = false,
    -- roda a validacao de pools de novo a cada N horas reais de servidor ligado
    -- (alem da validacao obrigatoria no boot), para pegar mods removidos/
    -- adicionados em live -- e tambem quando o scan de conteudo moddado roda de novo.
    RevalidatePoolsEveryRealHours = 12,

    -- quanto tempo (segundos reais) o servidor espera o cliente confirmar que
    -- a animacao da roleta terminou antes de entregar os itens de qualquer
    -- jeito -- rede de seguranca pra quem desconecta/fecha o jogo no meio da
    -- animacao nao perder a recompensa (ela ja foi decidida e persistida no
    -- instante do clique, so a ENTREGA fica pendente ate aqui). Precisa ficar
    -- folgado o bastante pra nunca disparar ANTES da animacao terminar de
    -- verdade -- com FoodDrinkMultiRollMode + quantidades altas (ex: 8 comidas
    -- + 6 bebidas), a roleta do Kit Inicial pode passar de 40-50s sozinha.
    PendingDeliveryTimeoutRealSeconds = 90,

    WelcomeMessageEnabled = true,
    -- nil (padrao) = mensagem gerada automaticamente por HardcoreKits_Welcome.lua
    -- usando getText(), no idioma que o jogador tem configurado no jogo
    -- (EN ou PTBR -- ver shared/Translate/*/UI.json). Nao da pra expor
    -- "string"/texto livre via sandbox-options.txt -- o sistema de sandbox do
    -- jogo so tem boolean/integer/double/enum -- entao pra um texto CUSTOM
    -- (fixo, sem localizacao automatica) o dono do servidor pode sobrescrever
    -- aqui com sua propria string, ex:
    -- WelcomeMessageText = "[Hardcore Kits] minha mensagem /kit",
    -- Texto simples, SEM tag de cor <RGB:...> -- varias tentativas com tag
    -- deram bug de espacamento/truncamento no chat que nunca foi resolvido
    -- de forma confiavel, entao a mensagem padrao (e a recomendacao pra
    -- overrides tambem) e sempre texto puro.
    WelcomeMessageText = nil,

    -- abre o painel do /kit sozinho pouco depois do personagem nascer, pra
    -- quem nao le o chat/nao sabe do comando. Ver HardcoreKits_AutoOpen.lua.
    AutoOpenOnSpawnEnabled = true,

    -- se tiver zumbi vivo a esta distancia (quadrados) do jogador no exato
    -- instante em que o auto-open iria abrir, pula essa abertura desta vez --
    -- checagem UNICA, sem repetir nem esperar ficar seguro (pedido explicito
    -- do usuario); o jogador continua podendo abrir manualmente (/kit ou
    -- botao da barra lateral) quando quiser. Ver HardcoreKits_AutoOpen.lua.
    AutoOpenZombieCheckEnabled = true,
    AutoOpenZombieCheckRadius = 8,

    -- botao de icone na barra lateral esquerda (junto de Inventario/Saude/
    -- Mapa/Admin etc) pra abrir o /kit sem depender do chat -- principalmente
    -- util no singleplayer, que nao tem chat de jogador de verdade. So
    -- aparece quando ha algo pra resgatar. Ver HardcoreKits_Sidebar.lua.
    SidebarButtonEnabled = true,

    -- mini roleta no canto superior direito, arrastavel, mostrando o ultimo
    -- item/skill que caiu enquanto um sorteio continua rolando em segundo
    -- plano com a janela do /kit FECHADA -- some por completo quando o
    -- servidor confirma a entrega, dando lugar a um aviso verde curto (3s).
    -- Ver HardcoreKits_RouletteOverlay.lua e o ticker global em
    -- HardcoreKits_Roulette.lua (o que de fato mantem o sorteio rodando).
    RouletteOverlayEnabled = true,

    -- enquanto a janela do /kit esta aberta, se tiver zumbi vivo MUITO perto
    -- do jogador (raio bem menor que o do auto-open acima -- e uma checagem
    -- continua, nao unica), a interface fica temporariamente translucida
    -- (exceto o botao de fechar, que continua visivel/clicavel) pra dar pra
    -- ver o que esta acontecendo por tras dela e reagir. Ver
    -- HardcoreKits_Window.lua e HardcoreKits_Theme.lua (dimAlpha).
    WindowDimOnDangerEnabled = true,
    WindowDimOnDangerRadius = 4,
    WindowDimOnDangerAlpha = 0.25,
}
