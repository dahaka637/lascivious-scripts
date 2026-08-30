-- Funcoes de sorteio. Nenhuma funcao aqui toca inventario, ModData ou rede --
-- elas so leem HardcoreKitsValidatedPools/HardcoreKitsConfig e devolvem uma
-- tabela de resultado. Isso mantem a logica de "o que foi sorteado" separada
-- de "como isso vira item de verdade" (HardcoreKits_Delivery) e de
-- "quando isso pode acontecer" (HardcoreKits_Transactions).
--
-- Forma padrao de resultado empilhavel: SEMPRE uma lista de { fullType=, qty= }
-- (nunca um fullType+qty solto) -- assim comida/bebida se comportam igual em
-- modo normal (1 entrada) ou em FoodDrinkMultiRollMode (N entradas, cada uma
-- possivelmente de um item diferente), e quem consome (Delivery, Roulette) so
-- precisa iterar uma lista, sem checar qual modo estava ativo.
if isClient() then return end

require "HardcoreKits_Config"
require "HardcoreKits_Validation"
require "HardcoreKits_Utils"
require "HardcoreKits_Pools"
require "HardcoreKits_Identity"

HardcoreKitsRolls = HardcoreKitsRolls or {}

local function finiteNumber(value, fallback)
    local number = tonumber(value)
    if not number or number ~= number or number == math.huge or number == -math.huge then return fallback end
    return number
end

-- ================= blocos reutilizaveis =================

-- secao 7: comida, UM tipo. Retorna fullType, "canned"|"pickled"|"secondary"
-- (ou nil,nil se todos os pools estiverem vazios -- quem chama ignora com seguranca)
local function rollFoodType(primaryPoolChance, cannedShareOfPrimary)
    local pools = HardcoreKitsValidatedPools
    local hasPrimary = (#pools.FoodCanned > 0) or (#pools.FoodPickled > 0)
    if hasPrimary and HardcoreKitsUtils.rollChance(primaryPoolChance) then
        local wantCanned = HardcoreKitsUtils.rollChance(cannedShareOfPrimary)
        if wantCanned and #pools.FoodCanned > 0 then
            return HardcoreKitsUtils.pick(pools.FoodCanned), "canned"
        elseif #pools.FoodPickled > 0 then
            return HardcoreKitsUtils.pick(pools.FoodPickled), "pickled"
        elseif #pools.FoodCanned > 0 then
            return HardcoreKitsUtils.pick(pools.FoodCanned), "canned"
        end
    end
    if #pools.FoodSecondary > 0 then
        return HardcoreKitsUtils.pick(pools.FoodSecondary), "secondary"
    end
    if #pools.FoodCanned > 0 then return HardcoreKitsUtils.pick(pools.FoodCanned), "canned" end
    if #pools.FoodPickled > 0 then return HardcoreKitsUtils.pick(pools.FoodPickled), "pickled" end
    return nil, nil
end

-- secao 8: bebida, UM tipo. Retorna fullType, "water"|"other"
local function rollDrinkType(waterChance)
    local pools = HardcoreKitsValidatedPools
    if #pools.DrinkWater > 0 and HardcoreKitsUtils.rollChance(waterChance) then
        return HardcoreKitsUtils.pick(pools.DrinkWater), "water"
    end
    if #pools.DrinkOther > 0 then
        return HardcoreKitsUtils.pick(pools.DrinkOther), "other"
    end
    if #pools.DrinkWater > 0 then return HardcoreKitsUtils.pick(pools.DrinkWater), "water" end
    return nil, nil
end

-- secoes 7/8, modo composto: sorteia a QUANTIDADE, depois decide se sorteia o
-- TIPO uma vez (padrao: N copias do mesmo item) ou uma vez POR UNIDADE
-- (FoodDrinkMultiRollMode: cada unidade pode ser um item diferente). Sempre
-- devolve uma lista de { fullType=, qty=, bucket= }, nunca vazia por padrao
-- (pode vir vazia so se o pool inteiro estiver vazio).
local function rollStackedResults(rollTypeFn, qtyMin, qtyMax, multiMode)
    local qty = HardcoreKitsUtils.randInt(qtyMin, qtyMax)
    if multiMode then
        local out = {}
        for _ = 1, qty do
            local fullType, bucket = rollTypeFn()
            if fullType then
                table.insert(out, { fullType = fullType, qty = 1, bucket = bucket })
            end
        end
        return out
    end
    local fullType, bucket = rollTypeFn()
    if not fullType then return {} end
    return { { fullType = fullType, qty = qty, bucket = bucket } }
end

local function rollFoodResults(primaryPoolChance, cannedShareOfPrimary, qtyMin, qtyMax)
    return rollStackedResults(function() return rollFoodType(primaryPoolChance, cannedShareOfPrimary) end,
        qtyMin, qtyMax, HardcoreKitsConfig.FoodDrinkMultiRollMode == true)
end

local function rollDrinkResults(waterChance, qtyMin, qtyMax)
    return rollStackedResults(function() return rollDrinkType(waterChance) end,
        qtyMin, qtyMax, HardcoreKitsConfig.FoodDrinkMultiRollMode == true)
end

-- Peso relativo por ARMA dentro da categoria: classificacao dinamica pelo
-- Weight real do script, sem lista fixa. O limite e inclusivo (>=) e os dois
-- valores sao lidos a cada sorteio, entao live-reload do Sandbox vale sem
-- reconstruir pool. Peso desconhecido fica normal (100), por seguranca.
local function meleeItemWeight(fullType)
    local itemWeight = HardcoreKitsValidation.itemActualWeight
        and HardcoreKitsValidation.itemActualWeight(fullType) or nil
    local threshold = math.max(0, finiteNumber(HardcoreKitsConfig.MeleeHeavyWeightThreshold, 3.0))
    if itemWeight and itemWeight >= threshold then
        return math.max(0, finiteNumber(HardcoreKitsConfig.MeleeHeavyReducedWeightPercent, 35))
    end
    return 100
end

-- secao 9: sorteia primeiro a categoria (peso), depois um item ponderado
-- dentro dela -- assim uma categoria com muitos itens nao fica artificialmente
-- mais provavel. Dentro da categoria, armas pesadas recebem a penalidade
-- dinamica de meleeItemWeight acima.
-- Categorias sem nenhum item valido no momento sao excluidas do sorteio.
-- highDamageOnly: "equipamento superior", so usado pelo Kit Inicial (ver
-- rollInitialKit abaixo) -- troca pro pool derivado MeleeHighDamageByCategory
-- (filtrado por HardcoreKitsConfig.InitialMeleeMinDamage em
-- HardcoreKits_Validation.lua), NAO afeta o sub-sorteio melee da Recompensa
-- de Sobrevivencia (rollSurvivalCombat, que sempre chama sem esse argumento).
local function rollMeleeItem(categoryWeights, highDamageOnly)
    if type(categoryWeights) ~= "table" then return nil, nil end
    local byCategory = highDamageOnly and HardcoreKitsValidatedPools.MeleeHighDamageByCategory
        or HardcoreKitsValidatedPools.MeleeByCategory
    local effective, weightedByCategory = {}, {}
    for category, weight in pairs(categoryWeights) do
        if byCategory[category] and #byCategory[category] > 0 then
            local entries, totalItemWeight = {}, 0
            for _, fullType in ipairs(byCategory[category]) do
                local itemWeight = meleeItemWeight(fullType)
                table.insert(entries, { value = fullType, weight = itemWeight })
                if itemWeight > 0 then totalItemWeight = totalItemWeight + itemWeight end
            end
            -- Uma categoria composta apenas por armas penalizadas com peso 0
            -- fica fora do primeiro sorteio tambem; assim nunca escolhemos
            -- uma categoria incapaz de produzir item enquanto outra valida
            -- ainda existe.
            if totalItemWeight > 0 then
                effective[category] = weight
                weightedByCategory[category] = entries
            end
        end
    end
    local category = HardcoreKitsUtils.weightedKey(effective)
    if not category then return nil, nil end
    return HardcoreKitsUtils.weightedValue(weightedByCategory[category]), category
end

-- secao 11: mesma ideia (tier por peso, depois item dentro do tier)
local function rollBackpackItem(tierWeights)
    if type(tierWeights) ~= "table" then return nil, nil end
    local byTier = HardcoreKitsValidatedPools.BackpackByTier
    local effective = {}
    for tier, weight in pairs(tierWeights) do
        if byTier[tier] and #byTier[tier] > 0 then
            effective[tier] = weight
        end
    end
    local tier = HardcoreKitsUtils.weightedKey(effective)
    if not tier then return nil, nil end
    return HardcoreKitsUtils.pick(byTier[tier]), tier
end

-- fracao aleatoria de condicao (aplicada ao ConditionMax real do item em
-- HardcoreKits_Delivery, que e quem toca o item de verdade)
local function rollConditionFraction(minFraction, maxFraction)
    local minimum = finiteNumber(minFraction, 1.0)
    local maximum = finiteNumber(maxFraction, minimum)
    minimum = math.max(0, math.min(1, minimum))
    maximum = math.max(0, math.min(1, maximum))
    if minimum > maximum then minimum, maximum = maximum, minimum end
    if minimum == maximum then return minimum end
    return ZombRandFloat(minimum, maximum)
end

-- "give rate inverso" do pool de Recurso: itens em
-- HardcoreKitsConfig.ResourceReducedItems (curados a mao pelo usuario) tem
-- peso reduzido (ResourceReducedWeightPercent, % relativo a 100 de um item
-- normal) -- ainda podem cair, so com menos frequencia. Usado nos dois
-- lugares que sorteiam do pool de Recurso (Kit Inicial e Recompensa Semanal).
local function resourceWeight(fullType)
    if HardcoreKitsConfig.ResourceReducedItems and HardcoreKitsConfig.ResourceReducedItems[fullType] then
        return HardcoreKitsConfig.ResourceReducedWeightPercent or 100
    end
    return 100
end

-- copia uma lista de {fullType=,qty=} pra uma lista NOVA (nunca a referencia
-- direta do pool validado, reusada por TODA claim que sortear aquele bundle
-- -- ver a licao de 2026-08-05 sobre isso no historico do mod). Usado pelos
-- dois bundles especiais (bolsa de trauma / kit medico), nos dois caminhos
-- (Kit Inicial e Recompensa de Sobrevivencia).
local function copyEntries(list)
    local out = {}
    for _, entry in ipairs(type(list) == "table" and list or {}) do
        if type(entry) == "table" and type(entry.fullType) == "string" then
            table.insert(out, { fullType = entry.fullType, qty = entry.qty })
        end
    end
    return out
end

-- conteudo do kit medico: a parte GARANTIDA sempre entra (hoje, 2 bandagens
-- -- pedido explicito do usuario, "sempre 2 bandagens no minimo"), mais um
-- numero aleatorio de TIPOS extras (MedicalKitRandomItemCountMin/Max) sorteados
-- SEM repetir do pool de variedade, cada um com sua propria quantidade
-- aleatoria (1-2) -- nunca a mesma combinacao duas vezes.
local function rollMedicalKitContents()
    local pools = HardcoreKitsValidatedPools
    local cfg = HardcoreKitsConfig
    local out = copyEntries(pools.MedicalKitGuaranteed)
    local count = HardcoreKitsUtils.randInt(cfg.MedicalKitRandomItemCountMin, cfg.MedicalKitRandomItemCountMax)
    for _, fullType in ipairs(HardcoreKitsUtils.pickN(pools.MedicalKitRandomPool, count)) do
        table.insert(out, { fullType = fullType, qty = HardcoreKitsUtils.randInt(1, 2) })
    end
    return out
end

-- sub-sorteio de "recurso": bolsa de trauma primeiro, depois kit medico (dois
-- resultados especiais INDEPENDENTES -- pedido explicito do usuario, "as
-- duas" podem cair, cada uma com sua propria chance), senao nil,nil (quem
-- chama cai no sorteio normal de itens distintos). Devolve bagFullType,
-- contents -- ou nil,nil se nenhum dos dois bateu.
local function rollSpecialResourceContainer(traumaChance, medicalKitChance)
    local pools = HardcoreKitsValidatedPools
    if pools.TraumaBagBag and #pools.TraumaBagContents > 0
        and HardcoreKitsUtils.rollChance(traumaChance) then
        return pools.TraumaBagBag, copyEntries(pools.TraumaBagContents)
    end
    if pools.MedicalKitBag and (#pools.MedicalKitGuaranteed > 0 or #pools.MedicalKitRandomPool > 0)
        and HardcoreKitsUtils.rollChance(medicalKitChance) then
        return pools.MedicalKitBag, rollMedicalKitContents()
    end
    return nil, nil
end

HardcoreKitsRolls.rollMeleeItem = rollMeleeItem
HardcoreKitsRolls.rollBackpackItem = rollBackpackItem

-- uniforme entre todas as armas validas (usado pelo Kit Inicial -- a spec nao
-- pede raridade aqui, so a chance de 50% ja controla o quao especial e ganhar uma)
function HardcoreKitsRolls.rollFirearmUniform()
    return HardcoreKitsUtils.pick(HardcoreKitsValidatedPools.Firearms)
end

-- por tier (usado na recompensa semanal -- secao 18.2: "armas fortes ou raras
-- devem possuir pesos baixos")
function HardcoreKitsRolls.rollFirearmByTier(tierWeights)
    local pool = HardcoreKitsValidatedPools.Firearms
    if #pool == 0 then return nil end
    local byTier = {}
    for _, def in ipairs(pool) do
        byTier[def.tier] = byTier[def.tier] or {}
        table.insert(byTier[def.tier], def)
    end
    local effective = {}
    for tier, weight in pairs(tierWeights) do
        if byTier[tier] and #byTier[tier] > 0 then effective[tier] = weight end
    end
    local tier = HardcoreKitsUtils.weightedKey(effective)
    if not tier then return HardcoreKitsUtils.pick(pool) end
    return HardcoreKitsUtils.pick(byTier[tier])
end

-- ================= Bonus de Habilidade (skill boost) =================
-- XP e sempre SOMADO ao que o personagem ja tem (AddXP e aditivo por
-- natureza, nunca sobrescreve -- ver HardcoreKits_Delivery).
--
-- Escala em NIVEIS (0 a 10 -- os mesmos 10 quadradinhos de nivel que o jogo
-- mostra pra qualquer skill), NAO em porcentagem do total (tentativa
-- anterior, descartada): converter "quantos niveis" em XP somando o custo
-- REAL de cada nivel individual (perk:getXpForLevel(1), (2), (3)...), sempre
-- contando a partir do ZERO -- e o que garante "10 niveis = exatamente o
-- total pra platinar do zero" continuar valendo (perk:getTotalXpForLevel(10)
-- e por definicao a soma de getXpForLevel(1) ate (10)), SEM o problema da
-- versao em porcentagem: la, uma fatia pequena do TOTAL podia cobrir varios
-- niveis iniciais baratos de uma curva concentrada nos niveis finais,
-- fazendo um tier "baixo" entregar o equivalente a varios niveis de verdade.
-- Aqui isso nao acontece: um teto de "3 niveis" nunca custa mais do que o
-- custo real dos niveis 1+2+3 daquela skill especifica, nao importa o quao
-- concentrada a curva seja.

-- soma o custo real (getXpForLevel) do nivel 1 ate levelCount, sempre a
-- partir do zero. levelCount pode ser fracionario (ex: 1.64) -- soma os
-- niveis inteiros completos mais uma fracao linear do proximo nivel.
local function xpForLevelCount(perk, levelCount)
    levelCount = finiteNumber(levelCount, 0)
    levelCount = math.max(0, math.min(levelCount, 10))
    local wholeLevels = math.floor(levelCount)
    local frac = levelCount - wholeLevels
    local xp = 0
    for lvl = 1, wholeLevels do
        xp = xp + (perk:getXpForLevel(lvl) or 0)
    end
    if frac > 0 and wholeLevels < 10 then
        xp = xp + (perk:getXpForLevel(wholeLevels + 1) or 0) * frac
    end
    return xp
end

-- XP sorteado pra UMA skill dentro da janela do tier (em niveis) -- dupla
-- camada: o tier ja foi decidido antes (por grupo ou pra a skill unica da
-- recompensa), isso aqui e o segundo sorteio, independente por skill.
-- Devolve XP sorteado, o total real pra platinar do zero (diagnostico/log,
-- perk:getTotalXpForLevel(10)) e quantos niveis foram sorteados
-- (diagnostico/log) -- ver o campo Skills do log de auditoria.
local function rollSkillXp(perkName, tier)
    local range = HardcoreKitsConfig.SkillBoostTierLevels[tier]
    if type(range) ~= "table" then return 0, 0, 0 end
    local ok, xp, totalToMax, levels = pcall(function()
        local perk = Perks.FromString(perkName)
        if not perk then return nil end
        local minimum = math.max(0, math.min(10, finiteNumber(range.min, 0)))
        local maximum = math.max(0, math.min(10, finiteNumber(range.max, minimum)))
        if minimum > maximum then minimum, maximum = maximum, minimum end
        local rolledLevels = minimum == maximum and minimum or ZombRandFloat(minimum, maximum)
        return xpForLevelCount(perk, rolledLevels), perk:getTotalXpForLevel(10), rolledLevels
    end)
    xp, totalToMax, levels = finiteNumber(xp), finiteNumber(totalToMax), finiteNumber(levels)
    if not ok or not xp or not totalToMax or not levels then return 0, 0, 0 end
    return math.max(0, math.floor(xp + 0.5)), math.max(0, math.floor(totalToMax + 0.5)), levels
end

-- Kit Inicial: quantidade configuravel de grupos, sem repetir grupo. Minimo
-- e maximo sao normalizados aqui contra 1..#SkillGroups; se o admin deixar
-- minimo maior que maximo, os dois sao invertidos com seguranca. Cada grupo
-- sorteado ja sai com o tier decidido junto (nao e uma fase separada) e a lista de
-- {perkName=, xp=} de cada skill daquele grupo, cada uma com seu proprio
-- sorteio independente dentro da janela do tier.
function HardcoreKitsRolls.rollSkillBoosts()
    if HardcoreKitsConfig.SkillBoostEnabled ~= true then return {} end
    local groups = HardcoreKitsPools.SkillGroups
    if not groups or #groups == 0 then return {} end

    local minGroups = math.floor(finiteNumber(HardcoreKitsConfig.InitialSkillGroupCountMin, 1))
    local maxGroups = math.floor(finiteNumber(HardcoreKitsConfig.InitialSkillGroupCountMax, #groups))
    minGroups = math.max(1, math.min(minGroups, #groups))
    maxGroups = math.max(1, math.min(maxGroups, #groups))
    if minGroups > maxGroups then minGroups, maxGroups = maxGroups, minGroups end

    local n = HardcoreKitsUtils.randInt(minGroups, maxGroups)
    local chosen = HardcoreKitsUtils.pickN(groups, n)
    local out = {}
    for _, group in ipairs(chosen) do
        local tier = HardcoreKitsUtils.weightedKey(HardcoreKitsConfig.SkillBoostTierWeights)
        if tier then
            local perks = {}
            for _, perkName in ipairs(type(group.perks) == "table" and group.perks or {}) do
                local xp, totalToMax, levels = rollSkillXp(perkName, tier)
                table.insert(perks, { perkName = perkName, xp = xp, totalToMax = totalToMax, levels = levels })
            end
            table.insert(out, { groupKey = group.key, groupLabelKey = group.labelKey, tier = tier, perks = perks })
        end
    end
    return out
end

-- Recompensa de Sobrevivencia: raro (SurvivalSkillBonusChance). Na maioria
-- das vezes e so UMA skill especifica (pool achatado com as 35 skills de
-- todos os grupos, chance igual pra cada uma -- nao pesado por tamanho de
-- grupo, decisao tomada sem instrucao explicita do usuario sobre isso).
-- Duplo sorteio extra (pedido explicito do usuario): DADO que o bonus
-- disparou, uma pequena chance (SurvivalSkillBonusGroupChance) troca "uma
-- skill" por "o GRUPO inteiro" -- mesmo tratamento do bonus de grupo do Kit
-- Inicial (rollSkillBoosts), so que aqui e sempre exatamente 1 grupo (nunca
-- 0 nem mais de 1, ja que o bonus inteiro so existe se a chance acima
-- disparou). O tier (muito pouco/baixo/medio/alto) e sempre um sorteio
-- proprio, independente do grupo-vs-skill-unica.
function HardcoreKitsRolls.rollSurvivalSkillBonus()
    if HardcoreKitsConfig.SkillBoostEnabled ~= true then return nil end
    if not HardcoreKitsUtils.rollChance(HardcoreKitsConfig.SurvivalSkillBonusChance) then return nil end

    if HardcoreKitsUtils.rollChance(HardcoreKitsConfig.SurvivalSkillBonusGroupChance) then
        local group = HardcoreKitsUtils.pick(HardcoreKitsPools.SkillGroups or {})
        if not group then return nil end
        local tier = HardcoreKitsUtils.weightedKey(HardcoreKitsConfig.SkillBoostTierWeights)
        if not tier then return nil end
        local perks = {}
        for _, perkName in ipairs(type(group.perks) == "table" and group.perks or {}) do
            local xp, totalToMax, levels = rollSkillXp(perkName, tier)
            table.insert(perks, { perkName = perkName, xp = xp, totalToMax = totalToMax, levels = levels })
        end
        return {
            category = "skill", kind = "group", groupKey = group.key, groupLabelKey = group.labelKey,
            tier = tier, perks = perks,
        }
    end

    local allPerks, perkGroup = {}, {}
    for _, group in ipairs(HardcoreKitsPools.SkillGroups or {}) do
        for _, perkName in ipairs(type(group.perks) == "table" and group.perks or {}) do
            table.insert(allPerks, perkName)
            perkGroup[perkName] = group
        end
    end
    local perkName = HardcoreKitsUtils.pick(allPerks)
    if not perkName then return nil end
    local tier = HardcoreKitsUtils.weightedKey(HardcoreKitsConfig.SkillBoostTierWeights)
    if not tier then return nil end
    local group = perkGroup[perkName]
    local xp, totalToMax, levels = rollSkillXp(perkName, tier)
    return {
        category = "skill", kind = "single", perkName = perkName, groupKey = group.key, groupLabelKey = group.labelKey,
        tier = tier, xp = xp, totalToMax = totalToMax, levels = levels,
    }
end

-- ================= Kit Inicial (secao 6) =================

-- player e opcional (mantido assim pra nao quebrar nenhum outro chamador
-- futuro que so queira testar a distribuicao do sorteio sem um IsoPlayer de
-- verdade) -- so usado pra checar se ja tem mochila equipada, ver abaixo.
function HardcoreKitsRolls.rollInitialKit(player)
    local cfg = HardcoreKitsConfig
    local result = {}

    result.food = rollFoodResults(cfg.InitialFoodPrimaryPoolChance, cfg.InitialFoodCannedShareOfPrimary,
        cfg.InitialFoodQuantityMin, cfg.InitialFoodQuantityMax)
    result.drink = rollDrinkResults(cfg.InitialWaterChance, cfg.InitialDrinkQuantityMin, cfg.InitialDrinkQuantityMax)

    result.melee, result.meleeCategory = rollMeleeItem(cfg.InitialMeleeCategoryWeights, cfg.InitialMeleeHighDamageOnly == true)
    result.meleeConditionFraction = rollConditionFraction(cfg.InitialMeleeConditionMinFraction, cfg.InitialMeleeConditionMaxFraction)

    result.hasFirearm = (#HardcoreKitsValidatedPools.Firearms > 0) and HardcoreKitsUtils.rollChance(cfg.InitialFirearmChance)
    if result.hasFirearm then
        result.firearm = HardcoreKitsRolls.rollFirearmUniform()
        result.ammoBoxQty = HardcoreKitsUtils.weightedKey(cfg.InitialAmmoBoxesWeights)
            or HardcoreKitsUtils.randInt(cfg.InitialAmmoBoxesMin, cfg.InitialAmmoBoxesMax)
        -- armas com carregador destacavel ganham 1 carregador por caixa de
        -- municao sorteada (so a quantidade -- HardcoreKits_Delivery decide
        -- quantos vem soltos vs ja encaixados na arma). Armas sem carregador
        -- destacavel (ex: revolveres, bolt-action) ficam com magazineQty nil.
        if result.firearm and result.firearm.magazine then
            result.magazineQty = result.ammoBoxQty
        end
    end

    -- mochila: so sorteia/entrega uma NOVA se o personagem ainda nao tiver
    -- uma equipada nas costas -- pedido explicito do usuario ("detecte se o
    -- jogador ja possui mochila e ela esta equipada, e caso esteja, nao de
    -- mochila pra ele"). Decidido AQUI (na hora do sorteio, nao so na
    -- entrega) pra roleta do cliente ja refletir o resultado real -- nunca
    -- mostrar "ganhou uma mochila" se ela nunca vai ser de fato entregue (ver
    -- HardcoreKits_Roulette.buildInitialSteps). O resto do kit continua indo
    -- todo pra DENTRO de alguma mochila -- a nova sorteada, OU a ja
    -- equipada -- ver HardcoreKits_Delivery.deliverInitialKit.
    result.usingEquippedBackpack = HardcoreKitsIdentity.equippedBackpackInventory(player) ~= nil
    if not result.usingEquippedBackpack then
        result.backpack, result.backpackTier = rollBackpackItem(cfg.InitialBackpackTierWeights)
    end

    -- categoria "recurso": chance de virar um dos dois resultados especiais
    -- (bolsa de trauma OU kit medico, independentes -- ver
    -- rollSpecialResourceContainer acima) em vez do sorteio normal. Configs
    -- PROPRIAS do Kit Inicial, nao compartilhadas com as da Recompensa de
    -- Sobrevivencia (pedido explicito do usuario: os dois bundles tambem
    -- podem cair no Kit Inicial, nao so na recompensa semanal).
    local specialBag, specialContents = rollSpecialResourceContainer(cfg.InitialTraumaBagChance, cfg.InitialMedicalKitChance)
    if specialBag then
        result.medicalKitBag = specialBag
        result.medicalKitContents = specialContents
        result.resource = {}
    else
        -- quantidade sorteada, mas cada unidade e um item DIFERENTE (sem
        -- repeticao) -- corrigido a pedido do usuario: antes sorteava 1 tipo
        -- e empilhava N copias dele (ex: 2x Apito), o que sempre pareceu
        -- "sem graca" pra quantidades > 1. Usa pickNWeighted (mesma
        -- amostra-sem-reposicao do sorteio de grupos de skill, agora com
        -- peso reduzido pros itens marcados em ResourceReducedItems) e
        -- entrega qty=1 por entrada -- Delivery/Roulette ja tratam isso como
        -- uma lista de entradas independentes, igual ja fazem com comida/
        -- bebida em FoodDrinkMultiRollMode, sem precisar de mudanca no consumidor.
        local resourceCount = HardcoreKitsUtils.randInt(cfg.InitialResourceQuantityMin, cfg.InitialResourceQuantityMax)
        result.resource = {}
        for _, fullType in ipairs(HardcoreKitsUtils.pickNWeighted(HardcoreKitsValidatedPools.Resources, resourceCount, resourceWeight)) do
            table.insert(result.resource, { fullType = fullType, qty = 1 })
        end
    end

    -- skillBoostEnabled viaja separado de skillBoosts pra o cliente omitir
    -- completamente os passos de habilidade quando a feature esta desligada.
    result.skillBoostEnabled = cfg.SkillBoostEnabled == true
    result.skillBoosts = HardcoreKitsRolls.rollSkillBoosts()

    return result
end

-- ================= Recompensa de Sobrevivencia (secoes 13-18) =================

-- municao avulsa: conjunto de ammoBox fullTypes compativeis com arma(s) de
-- fogo que o personagem JA TEM -- inventario principal + mochila equipada
-- (as duas checadas recursivamente, containsTypeRecurse -- confirmado via
-- decompilacao de zombie.inventory.ItemContainer.class -- pega tambem o que
-- estiver dentro de bolsas aninhadas). nil quando nao ha player ou nenhuma
-- arma de fogo validada encontrada -- rollSurvivalSingleResult trata isso
-- como "sem preferencia nenhuma", cai pro sorteio totalmente aleatorio de
-- sempre. So olha HardcoreKitsValidatedPools.Firearms (mesma fonte de
-- verdade que o resto do mod usa pra "quais armas de fogo sao validas").
local function ownedFirearmAmmoBoxes(player)
    if not player then return nil end
    local containers = {}
    local ok, mainInv = pcall(function() return player:getInventory() end)
    if ok and mainInv then table.insert(containers, mainInv) end
    local pack = HardcoreKitsIdentity.equippedBackpackInventory(player)
    if pack then table.insert(containers, pack) end
    if #containers == 0 then return nil end

    local owned = nil
    for _, def in ipairs(HardcoreKitsValidatedPools.Firearms or {}) do
        for _, container in ipairs(containers) do
            local ok2, has = pcall(function() return container:containsTypeRecurse(def.fullType) end)
            if ok2 and has then
                owned = owned or {}
                owned[def.ammoBox] = true
                break
            end
        end
    end
    return owned
end

-- secao 18: sub-sorteio de "arma ou municao". items fica uniforme com os
-- outros resultados (lista, mesmo quando so tem 1 entrada); firearm e
-- tratado a parte porque a entrega precisa de campos proprios (ammoBox etc).
-- 2026-08-06: municao SAIU daqui, virou categoria propria ("ammo", ver
-- rollSurvivalSingleResult) -- pedido explicito do usuario. Agora "combat" so
-- sorteia melee vs firearm; e firearm SEMPRE vem com 1 caixa de municao
-- garantida (result.ammoBoxQty = 1, NAO chance nenhuma -- outro pedido
-- explicito: "quando cai arma sempre cai 1 caixa para aquela arma").
local function rollSurvivalCombat()
    local cfg = HardcoreKitsConfig
    local pools = HardcoreKitsValidatedPools
    local effective = {}
    local meleeAny = false
    for _, list in pairs(pools.MeleeByCategory) do
        if #list > 0 then meleeAny = true break end
    end
    if meleeAny then effective.melee = cfg.SurvivalCombatWeights.melee end
    if #pools.Firearms > 0 then effective.firearm = cfg.SurvivalCombatWeights.firearm end

    local sub = HardcoreKitsUtils.weightedKey(effective)
    if sub == "melee" then
        local item = rollMeleeItem(cfg.InitialMeleeCategoryWeights)
        return {
            category = "combat", subCategory = "melee",
            items = item and { { fullType = item, qty = 1 } } or {},
            meleeConditionFraction = rollConditionFraction(cfg.InitialMeleeConditionMinFraction, cfg.InitialMeleeConditionMaxFraction),
        }
    elseif sub == "firearm" then
        local firearm = HardcoreKitsRolls.rollFirearmByTier(cfg.SurvivalFirearmTierWeights)
        -- recompensa semanal sempre da exatamente 1 carregador quando a arma
        -- usa carregador destacavel, E exatamente 1 caixa de municao da
        -- propria arma -- os dois garantidos, sem sorteio nenhum. Municao
        -- ISOLADA (sem estar ligada a nenhuma arma) e a categoria "ammo"
        -- separada, com sua propria quantidade configuravel (X a Y).
        return {
            category = "combat", subCategory = "firearm", items = {},
            firearm = firearm,
            magazineQty = (firearm and firearm.magazine) and 1 or nil,
            ammoBoxQty = firearm and 1 or nil,
        }
    end
    -- nada disponivel em nenhuma das duas sub-categorias
    return { category = "combat", subCategory = nil, items = {} }
end

-- secao 14: um unico resultado (categoria + lista de itens). player e
-- opcional (so usado pela preferencia de municao avulsa por arma ja
-- possuida, ver ownedFirearmAmmoBoxes acima) -- sem ele, cai pro sorteio
-- totalmente aleatorio de sempre.
function HardcoreKitsRolls.rollSurvivalSingleResult(player)
    local cfg = HardcoreKitsConfig
    local pools = HardcoreKitsValidatedPools
    local effective = {}

    if (#pools.FoodCanned + #pools.FoodPickled + #pools.FoodSecondary) > 0 then
        effective.food = cfg.SurvivalCategoryWeights.food
    end
    if (#pools.DrinkWater + #pools.DrinkOther) > 0 then
        effective.drink = cfg.SurvivalCategoryWeights.drink
    end
    if #pools.Resources > 0 then
        effective.resource = cfg.SurvivalCategoryWeights.resource
    end
    local meleeAny = false
    for _, list in pairs(pools.MeleeByCategory) do if #list > 0 then meleeAny = true break end end
    -- "combat" agora so precisa de melee OU arma de fogo pra existir --
    -- municao sozinha NAO conta mais (virou categoria propria "ammo" logo
    -- abaixo, 2026-08-06).
    if meleeAny or #pools.Firearms > 0 then
        effective.combat = cfg.SurvivalCategoryWeights.combat
    end
    -- municao ISOLADA: categoria propria, nao ligada a nenhuma arma
    -- especifica -- pedido explicito do usuario.
    if #pools.AmmoBoxes > 0 then
        effective.ammo = cfg.SurvivalCategoryWeights.ammo
    end

    -- pedido explicito do usuario: toggle pra deixar a chance ENTRE as
    -- categorias ja disponiveis totalmente igual, em vez de usar os pesos
    -- configurados -- so troca o VALOR (pra 1, todas empatadas), nunca MUDA
    -- quais categorias entram no sorteio (isso continua vindo so do que foi
    -- montado acima, respeitando pool vazio do jeito de sempre).
    if cfg.SurvivalCategoriesFullyRandom == true then
        for key in pairs(effective) do effective[key] = 1 end
    end

    local category = HardcoreKitsUtils.weightedKey(effective)
    if category == "food" then
        return { category = "food", items = rollFoodResults(cfg.SurvivalFoodPrimaryPoolChance,
            cfg.InitialFoodCannedShareOfPrimary, cfg.SurvivalFoodQuantityMin, cfg.SurvivalFoodQuantityMax) }
    elseif category == "drink" then
        return { category = "drink", items = rollDrinkResults(cfg.SurvivalWaterChance,
            cfg.SurvivalDrinkQuantityMin, cfg.SurvivalDrinkQuantityMax) }
    elseif category == "resource" then
        -- resultado especial e raro: bolsa de trauma OU kit medico ja
        -- recheados, em vez de um item avulso (independentes -- ver
        -- rollSpecialResourceContainer acima). O fullType da mochila/maleta e
        -- dos itens de dentro ja vem RESOLVIDO aqui (contra o pool validado)
        -- -- Delivery.lua so recebe e entrega, sem precisar conhecer
        -- HardcoreKitsValidatedPools (mesma separacao "Rolls decide O QUE,
        -- Delivery decide COMO" do resto do arquivo).
        local specialBag, specialContents = rollSpecialResourceContainer(cfg.SurvivalTraumaBagChance, cfg.SurvivalMedicalKitChance)
        if specialBag then
            return {
                category = "resource", subCategory = "medicalkit", items = {},
                medicalKitBag = specialBag,
                medicalKitContents = specialContents,
            }
        end
        -- mesma correcao do Kit Inicial: qty > 1 sorteia itens DISTINTOS, nao
        -- N copias do mesmo (ver comentario em rollInitialKit acima)
        local resItems = {}
        local resCount = HardcoreKitsUtils.randInt(cfg.SurvivalResourceQuantityMin, cfg.SurvivalResourceQuantityMax)
        for _, fullType in ipairs(HardcoreKitsUtils.pickNWeighted(pools.Resources, resCount, resourceWeight)) do
            table.insert(resItems, { fullType = fullType, qty = 1 })
        end
        return { category = "resource", items = resItems }
    elseif category == "combat" then
        return rollSurvivalCombat()
    elseif category == "ammo" then
        -- municao ISOLADA: um tipo aleatorio, nao ligado a nenhuma arma
        -- especifica -- pedido explicito do usuario. Diferente da caixa
        -- garantida que ja vem junto de um resultado de arma de fogo
        -- (rollSurvivalCombat, sempre 1) -- aqui a quantidade e sorteada
        -- (SurvivalAmmoBoxQuantityMin/Max, default 1-5). Preferencia por
        -- municao compativel com arma(s) de fogo ja possuida(s) -- pedido
        -- explicito do usuario -- so muda o PESO relativo dentro do mesmo
        -- pool (pickNWeighted com n=1), nunca restringe as opcoes: sem
        -- arma compativel nenhuma (ownedAmmoBoxes nil/vazio), todo tipo
        -- volta a ter peso igual, exatamente como antes.
        local ownedAmmoBoxes = (cfg.SurvivalAmmoPreferOwnedEnabled == true) and ownedFirearmAmmoBoxes(player) or nil
        local preferWeight = finiteNumber(cfg.SurvivalAmmoPreferOwnedWeight, 5)
        local box = HardcoreKitsUtils.pickNWeighted(pools.AmmoBoxes, 1, function(fullType)
            return (ownedAmmoBoxes and ownedAmmoBoxes[fullType]) and preferWeight or 1
        end)[1]
        return {
            category = "ammo",
            items = box and { { fullType = box, qty = HardcoreKitsUtils.randInt(cfg.SurvivalAmmoBoxQuantityMin, cfg.SurvivalAmmoBoxQuantityMax) } } or {},
        }
    end
    -- todos os pools estao vazios (config quebrada) -- devolve um resultado
    -- vazio que HardcoreKits_Delivery sabe ignorar, em vez de travar o resgate
    return { category = "empty", items = {} }
end

-- secao 13: quantos resultados (1/2/3), depois um HardcoreKitsRolls.rollSurvivalSingleResult() por resultado.
-- player e opcional, so repassado adiante pra preferencia de municao avulsa
-- por arma ja possuida (ver ownedFirearmAmmoBoxes acima).
function HardcoreKitsRolls.rollSurvivalReward(player)
    local count = HardcoreKitsUtils.weightedKey(HardcoreKitsConfig.SurvivalRewardCountWeights) or 1
    count = math.max(1, math.min(10, math.floor(finiteNumber(count, 1))))
    local results = {}
    for _ = 1, count do
        table.insert(results, HardcoreKitsRolls.rollSurvivalSingleResult(player))
    end
    -- bonus de skill: ADICIONAL aos N resultados normais acima, nao um deles
    -- (nao consome nenhum peso de SurvivalCategoryWeights) -- so mais uma
    -- entrada na mesma lista achatada, category="skill", que Delivery/
    -- Roulette/Audit ja sabem reconhecer.
    local skillBonus = HardcoreKitsRolls.rollSurvivalSkillBonus()
    if skillBonus then table.insert(results, skillBonus) end
    return results
end
