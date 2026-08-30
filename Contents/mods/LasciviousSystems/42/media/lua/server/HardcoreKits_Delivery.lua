-- Entrega autoritativa de itens. So este arquivo cria InventoryItem de
-- verdade -- Rolls decide O QUE, Delivery decide COMO virar item real.
--
-- Padrao de entrega verificado direto no jogo (nao suposto):
--   * pilha de N itens: container:AddItems(fullType, n) + sendAddItemsToContainer
--     (mesmo padrao usado por Aegis_Kits.lua no Aegis Panel)
--   * item unico: container:AddItem(fullType) + sendAddItemToContainer
--   * arma de fogo pronta pra atirar: setContainsClip(true) (so quando a
--     arma tem carregador destacavel) + setCurrentAmmoCount(maxAmmo) --
--     confirmado em media/lua/client/DebugUIs/Scenarios/FenrisScenario.lua,
--     script de conteudo oficial que monta armas prontas exatamente assim.
--   * agua "cheia": nao precisa de nenhuma chamada extra -- o script de
--     Base.WaterBottle ja define Fluids fluid=Water:1.0 (mais uma variante
--     Carbonated, tambem valida) como estado padrao de instanciacao,
--     confirmado em media/scripts/generated/items/normal.txt.
--   * mochila de um item ja instanciado: item:getInventory() devolve o
--     ItemContainer de dentro dela (mesmo metodo usado pelo Aegis Panel pra
--     mexer no conteudo de bags existentes) -- e o que deixa entregar o
--     resto do Kit Inicial JA DENTRO da mochila sorteada, em vez de solto.
--   * radio/walkie-talkie pronto pra ligar: item:getDeviceData():addBattery(item)
--     -- mesma chamada que a UI vanilla usa ao arrastar uma bateria pro
--     radio (client/RadioCom/RadioWindowModules/RWMPower.lua:addBattery +
--     shared/TimedActions/ISDeviceBatteryAction.lua:24), sem a timed action
--     de andar-ate/arrastar que so faz sentido pra interacao do jogador.
--
-- As funcoes de baixo nivel abaixo recebem um ItemContainer diretamente (nao
-- um player) -- assim a mesma logica serve tanto pro inventario principal
-- quanto pro interior de uma mochila, sem duplicar codigo.
--
-- Nenhuma funcao aqui lanca erro pra cima: falha de entrega de UM slot vira
-- "false"/0 no retorno, nunca derruba o resgate inteiro (secao 22).
if isClient() then return end

require "HardcoreKits_Pools"
require "HardcoreKits_Identity"

HardcoreKitsDelivery = HardcoreKitsDelivery or {}

local function normalizedQty(qty)
    local n = tonumber(qty)
    if not n or n ~= n or n == math.huge or n == -math.huge then return 0 end
    return math.max(0, math.floor(n))
end

local function finiteOrZero(value)
    local number = tonumber(value)
    if not number or number ~= number or number == math.huge or number == -math.huge then return 0 end
    return number
end

-- entrega N unidades de fullType (empilhavel ou nao) num container. Retorna
-- quantas unidades foram realmente criadas (0 em qualquer falha).
function HardcoreKitsDelivery.deliverStack(container, fullType, qty)
    qty = normalizedQty(qty)
    if not container or type(fullType) ~= "string" or fullType == "" or qty <= 0 then return 0 end
    local ok, items = pcall(function() return container:AddItems(fullType, qty) end)
    if not ok or not items then return 0 end
    pcall(function() sendAddItemsToContainer(container, items) end)
    local ok2, size = pcall(function() return items:size() end)
    if ok2 and type(size) == "number" then return normalizedQty(size) end
    return 0
end

-- fullTypes de "recurso" que precisam de um ajuste pos-criacao (garante carga
-- cheia em vez de confiar no estado padrao de instanciacao -- ver
-- HardcoreKitsPools.ResourceFullChargeOnDeliver).
local RESOURCE_FULL_CHARGE = {}
for _, fullType in ipairs(HardcoreKitsPools.ResourceFullChargeOnDeliver or {}) do
    RESOURCE_FULL_CHARGE[fullType] = true
end

-- fullTypes de "recurso" que sao radio/dispositivo e nao funcionam sem
-- bateria instalada -- ver HardcoreKitsPools.ResourceNeedsBatteryOnDeliver.
local RESOURCE_NEEDS_BATTERY = {}
for _, fullType in ipairs(HardcoreKitsPools.ResourceNeedsBatteryOnDeliver or {}) do
    RESOURCE_NEEDS_BATTERY[fullType] = true
end

-- mesma coisa que deliverStack, mas pra itens da categoria "recurso" -- se o
-- fullType precisar de ajuste pos-criacao (carga cheia e/ou bateria), entrega
-- um a um via deliverSingle (reaproveita o caminho ja testado de item unico,
-- evita depender de como iterar a colecao que AddItems devolve pra um lote).
-- Fora dessas listas curtas, se comporta identico a deliverStack (caminho em
-- lote, sem diferenca).
function HardcoreKitsDelivery.deliverResourceStack(container, fullType, qty)
    qty = normalizedQty(qty)
    if not container or type(fullType) ~= "string" or fullType == "" or qty <= 0 then return 0 end
    if RESOURCE_FULL_CHARGE[fullType] or RESOURCE_NEEDS_BATTERY[fullType] then
        local delivered, createdCount = 0, 0
        for _ = 1, qty do
            local item, configured = HardcoreKitsDelivery.deliverSingle(container, fullType, function(created)
                if RESOURCE_FULL_CHARGE[fullType] then
                    -- Drainable/torch convention in vanilla: 1.0 = full, 0 = empty.
                    created:setUsedDelta(1.0)
                end
                if RESOURCE_NEEDS_BATTERY[fullType] then
                    local deviceData = created:getDeviceData()
                    local battery = instanceItem("Base.Battery")
                    if not deviceData or not battery then error("bateria/dispositivo indisponivel") end
                    deviceData:addBattery(battery)
                end
            end)
            if item then createdCount = createdCount + 1 end
            if item and configured then delivered = delivered + 1 end
        end
        return delivered, createdCount
    end
    local delivered = HardcoreKitsDelivery.deliverStack(container, fullType, qty)
    return delivered, delivered
end

-- Entrega um item unico. Retorna item, configuredOk. A criacao e irreversivel:
-- se a configuracao falhar, o item continua no container e o chamador registra
-- entrega parcial (created>0), nunca repete o lote inteiro e nunca duplica.
function HardcoreKitsDelivery.deliverSingle(container, fullType, configureFn)
    if not container or type(fullType) ~= "string" or fullType == "" then return nil, false end
    local ok, item = pcall(function() return container:AddItem(fullType) end)
    if not ok or not item then return nil, false end
    -- Configure antes do pacote de sincronizacao: clientes MP nunca enxergam por
    -- um frame a arma vazia/condicao default ou um radio sem bateria.
    local configured = true
    if configureFn then
        local okConfigure, err = pcall(configureFn, item)
        if not okConfigure then
            configured = false
            print("[HardcoreKits] Falha ao configurar item entregue " .. tostring(fullType) .. ": " .. tostring(err))
        end
    end
    pcall(function() sendAddItemToContainer(container, item) end)
    return item, configured
end

-- arma corpo a corpo com uma condicao sorteada (fracao 0..1 da condicao
-- maxima do PROPRIO item, nao um valor fixo -- cada arma tem sua escala)
function HardcoreKitsDelivery.deliverMelee(container, fullType, conditionFraction)
    local item, configured = HardcoreKitsDelivery.deliverSingle(container, fullType, function(created)
        local maxCond = created:getConditionMax()
        if type(maxCond) ~= "number" or maxCond <= 0 then error("condicao maxima invalida") end
        local fraction = tonumber(conditionFraction) or 1.0
        if fraction ~= fraction or fraction == math.huge or fraction == -math.huge then fraction = 1.0 end
        fraction = math.max(0, math.min(1, fraction))
        local current = math.floor(maxCond * fraction + 0.5)
        created:setCondition(math.max(1, math.min(current, maxCond)))
    end)
    if not item then return false, false end
    return configured, true
end

-- "bolsa de trauma" OU "kit medico": mochila/maleta + itens de dentro, mesmo
-- padrao do backpack do Kit Inicial (mochila primeiro, depois getInventory()
-- pra popular o interior). bagFullType/contents ja vem RESOLVIDO por
-- HardcoreKits_Rolls (contra os pools validados -- bolsa de trauma tem lista
-- fixa, kit medico e parcialmente aleatorio, ver rollMedicalKitContents) --
-- aqui e so entrega, generico pros dois, sem tocar em pools.
--
-- 2026-08-05: existiu uma versao com verificacao pos-entrega (conferia
-- inner:getItemCount() e refazia com uma lista de fallback separada se
-- viesse curto) -- removida a pedido explicito do usuario depois que o bug
-- da maleta vazia persistiu MESMO com essa checagem. Voltou a ser entrega
-- direta e simples, so que agora com a lista generosa (fundida com o que
-- antes era so o fallback). Retorna ok (mochila entregue), quantos itens de
-- dentro foram entregues.
function HardcoreKitsDelivery.deliverMedicalKit(container, bagFullType, contents)
    if not container or type(bagFullType) ~= "string" or bagFullType == "" then return false, 0 end
    local bag = HardcoreKitsDelivery.deliverSingle(container, bagFullType)
    if not bag then return false, 0 end
    local ok, bagInv = pcall(function() return bag:getInventory() end)
    if not ok or not bagInv then return true, 0 end
    local delivered = 0
    for _, entry in ipairs(type(contents) == "table" and contents or {}) do
        if type(entry) == "table" then
            delivered = delivered + HardcoreKitsDelivery.deliverStack(bagInv, entry.fullType, entry.qty)
        end
    end
    return true, delivered
end

-- arma de fogo ja carregada (municao interna cheia) + caixas avulsas da
-- municao compativel entregues separadas (secao 10.2). ammoBoxQty pode ser 0
-- para so entregar a arma carregada, sem caixas extras.
--
-- magazineQty (opcional): quantos carregadores no TOTAL essa entrega deve
-- representar (so faz sentido pra armas com firearmDef.magazine setado --
-- ignorado com seguranca pras que nao tem carregador destacavel). Desses N
-- carregadores, 1 ja fica representado pela propria arma entregue carregada
-- (setContainsClip acima, sem consumir nenhum item de carregador de verdade)
-- -- so os outros N-1 saem como itens soltos no container. Com magazineQty=1
-- (recompensa semanal, sempre fixo em 1) isso significa 0 carregadores
-- soltos: o unico prometido e o que ja esta na arma.
function HardcoreKitsDelivery.deliverFirearm(container, firearmDef, ammoBoxQty, magazineQty)
    if type(firearmDef) ~= "table" or not firearmDef.fullType then return false, 0, 0, false end
    local weapon, configured = HardcoreKitsDelivery.deliverSingle(container, firearmDef.fullType, function(created)
        if firearmDef.magazine then created:setContainsClip(true) end
        local maxAmmo = normalizedQty(firearmDef.maxAmmo)
        if maxAmmo <= 0 then error("capacidade de municao invalida") end
        created:setCurrentAmmoCount(maxAmmo)
    end)
    if not weapon then return false, 0, 0, false end
    ammoBoxQty = normalizedQty(ammoBoxQty)
    magazineQty = normalizedQty(magazineQty)
    local ammoDelivered = 0
    if ammoBoxQty > 0 then
        ammoDelivered = HardcoreKitsDelivery.deliverStack(container, firearmDef.ammoBox, ammoBoxQty)
    end
    local magazinesDelivered = 0
    if firearmDef.magazine and magazineQty > 1 then
        magazinesDelivered = HardcoreKitsDelivery.deliverStack(container, firearmDef.magazine, magazineQty - 1)
    end
    return configured, ammoDelivered, magazinesDelivered, true
end

-- ================= Bonus de Habilidade (skill boost) =================
-- AddXP e ADITIVO por natureza (soma ao XP que o personagem ja tem, nunca
-- sobrescreve -- pedido explicito do usuario, e ja o comportamento normal
-- da API). useMultipliers=false de proposito: o teto do tier "alto" foi
-- calculado (HardcoreKits_Rolls.rollSkillXp) pra ser EXATAMENTE o total pra
-- platinar aquela skill do zero -- se o multiplicador de XP do sandbox do
-- servidor entrasse aqui, um "alto" com XpMultiplier>1 estouraria esse teto
-- "nem mais, nem menos". Assinatura AddXP(perk, amount, addGlobalXP,
-- useMultipliers, ?, ?) confirmada em ISPlayerStatsUI.lua vanilla -- os
-- ultimos 4 args espelham exatamente a chamada de la (false nos 4).

-- entrega os grupos do Kit Inicial. Retorna uma lista de
-- {groupKey=,tier=,totalXp=,totalMax=,totalLevels=,ok=} -- um registro POR
-- GRUPO (nao por skill individual), pro log de auditoria nao ficar poluido
-- com 35 linhas. totalMax = soma de perk:getTotalXpForLevel(10) de cada
-- skill do grupo, totalLevels = soma dos niveis sorteados -- diagnostico
-- pedido: da pra conferir o XP real entregue contra a janela de niveis
-- configurada, com numero de verdade em vez de suposicao.
function HardcoreKitsDelivery.deliverSkillBoosts(player, skillBoosts)
    local out = {}
    for _, boost in ipairs(type(skillBoosts) == "table" and skillBoosts or {}) do
        local totalXp, totalMax, totalLevels, applied, allOk = 0, 0, 0, 0, true
        for _, p in ipairs((type(boost) == "table" and boost.perks) or {}) do
            local xp = type(p) == "table" and tonumber(p.xp) or nil
            local ok = xp and xp == xp and xp > 0 and xp < math.huge and p.perkName and pcall(function()
                local perk = Perks.FromString(p.perkName)
                if not perk or (Perks.None and perk == Perks.None) then error("perk invalida") end
                local xpManager = player and player:getXp()
                if not xpManager then error("XP manager indisponivel") end
                xpManager:AddXP(perk, xp, false, false, false, false)
            end) == true
            if ok then
                applied = applied + 1
                totalXp = totalXp + xp
                totalMax = totalMax + math.max(0, finiteOrZero(p.totalToMax))
                totalLevels = totalLevels + math.max(0, finiteOrZero(p.levels))
            else
                allOk = false
            end
        end
        if type(boost) ~= "table" or applied == 0 then allOk = false end
        table.insert(out, { groupKey = type(boost) == "table" and boost.groupKey or nil,
            tier = type(boost) == "table" and boost.tier or nil, totalXp = totalXp,
            totalMax = totalMax, totalLevels = totalLevels, applied = applied, ok = allOk })
    end
    return out
end

-- bonus de uma unica skill (Recompensa de Sobrevivencia)
function HardcoreKitsDelivery.deliverSkillBonus(player, bonus)
    if not bonus or not bonus.perkName then return false end
    local xp = tonumber(bonus.xp)
    if not xp or xp ~= xp or xp <= 0 or xp == math.huge then return false end
    return pcall(function()
        local perk = Perks.FromString(bonus.perkName)
        if not perk or (Perks.None and perk == Perks.None) then error("perk invalida") end
        local xpManager = player and player:getXp()
        if not xpManager then error("XP manager indisponivel") end
        xpManager:AddXP(perk, xp, false, false, false, false)
    end)
end

-- ================= entrega do resultado completo =================
-- Ambas devolvem {granted,total,created,log}. Entitlement/cooldown ja foram
-- consumidos antes da mutacao fisica: entrega incompleta com created>0 fecha
-- como completed_partial (at-most-once); somente zero criacoes pode entrar no
-- caminho de recovery seguro.

-- Kit Inicial: a mochila vai pro inventario principal (precisa estar la pra
-- ser equipavel), e TUDO o resto (comida, bebida, arma, municao) vai pra
-- DENTRO dela -- o personagem recebe a mochila ja empacotada, nao um monte
-- de item solto. Se por algum motivo a mochila falhar (pool vazio/invalido),
-- cai de volta pro inventario principal em vez de perder os outros itens.
function HardcoreKitsDelivery.deliverInitialKit(player, rolled)
    local log, granted, total, created = {}, 0, 0, 0
    -- pcall: player pode ter ficado invalido entre o sorteio (clique) e essa
    -- entrega (a animacao da roleta pode levar 40-90s -- ver
    -- PendingDeliveryTimeoutRealSeconds). Sem isso, uma excecao aqui so seria
    -- pega pelo pcall generico do dispatcher (onClientCommand), que loga e
    -- segue sem avisar o cliente nem marcar a transacao pra recuperacao --
    -- reforco pedido explicito do usuario apos relatos raros de "kit nao
    -- recebido". Bail-out limpo (granted=0) deixa resumeInitialDelivery
    -- tratar isso exatamente como "zero_items_delivered" de sempre.
    local okInv, mainInv = pcall(function() return player:getInventory() end)
    if not okInv or not mainInv then
        return { granted = 0, total = 1, created = 0,
            log = { { slot = "mainInv", item = nil, qty = 0, ok = false } } }
    end

    if type(rolled) ~= "table" then
        return { granted = 0, total = 1, created = 0,
            log = { { slot = "rolled", item = nil, qty = 0, ok = false } } }
    end

    local function record(slot, item, qty, ok, createdQty)
        total = total + 1
        if ok then granted = granted + 1 end
        created = created + normalizedQty(createdQty)
        table.insert(log, { slot = slot, item = item, qty = qty, ok = ok })
    end

    local backpackItem = nil
    if rolled.backpack then
        backpackItem = HardcoreKitsDelivery.deliverSingle(mainInv, rolled.backpack)
        record("backpack", rolled.backpack, 1, backpackItem ~= nil, backpackItem and 1 or 0)
    end

    local packContainer = mainInv
    if backpackItem then
        local ok, inner = pcall(function() return backpackItem:getInventory() end)
        if ok and inner then packContainer = inner end
    elseif rolled.usingEquippedBackpack then
        -- personagem ja tinha mochila equipada -- HardcoreKitsRolls.rollInitialKit
        -- decidiu nao sortear uma nova (ver comentario la). Entrega o resto
        -- do kit DENTRO da mochila que ele ja tem vestida, em vez de solto no
        -- inventario principal -- mesmo espirito de sempre, so muda QUAL
        -- mochila e o alvo. AddItem(s) no jogo nao trava por "sem espaco"
        -- (so deixa o container mais pesado) -- entao nenhuma checagem extra
        -- de capacidade e necessaria alem do que deliverStack/deliverSingle
        -- ja fazem.
        local pack = HardcoreKitsIdentity.equippedBackpackInventory(player)
        if pack then packContainer = pack end
    end

    -- comida/bebida sao sempre LISTAS agora (1 entrada no modo padrao, N
    -- entradas independentes em FoodDrinkMultiRollMode -- ver HardcoreKits_Rolls.lua)
    for _, entry in ipairs(type(rolled.food) == "table" and rolled.food or {}) do
        if type(entry) == "table" then
            local expected = normalizedQty(entry.qty)
            local delivered = HardcoreKitsDelivery.deliverStack(packContainer, entry.fullType, expected)
            record("food", entry.fullType, expected, expected > 0 and delivered == expected, delivered)
        end
    end
    for _, entry in ipairs(type(rolled.drink) == "table" and rolled.drink or {}) do
        if type(entry) == "table" then
            local expected = normalizedQty(entry.qty)
            local delivered = HardcoreKitsDelivery.deliverStack(packContainer, entry.fullType, expected)
            record("drink", entry.fullType, expected, expected > 0 and delivered == expected, delivered)
        end
    end
    if rolled.medicalKitBag then
        -- resultado especial: maleta medica ja recheada, entregue DENTRO da
        -- mochila principal sorteada (packContainer) -- mesmo espirito de
        -- tudo mais no Kit Inicial, e mesma funcao ja usada pela Recompensa
        -- de Sobrevivencia (so muda o container alvo: la e mainInv, aqui e
        -- dentro da mochila). expected = soma das qty (nao o numero de
        -- entradas -- ver a licao da Recompensa de Sobrevivencia sobre isso).
        local bagOk, delivered = HardcoreKitsDelivery.deliverMedicalKit(packContainer, rolled.medicalKitBag, rolled.medicalKitContents)
        delivered = delivered or 0
        local expected = 0
        for _, entry in ipairs(type(rolled.medicalKitContents) == "table" and rolled.medicalKitContents or {}) do
            if type(entry) == "table" then expected = expected + normalizedQty(entry.qty) end
        end
        record("resource:medicalkit", string.format("%s/contents=%d-%d", tostring(rolled.medicalKitBag), delivered, expected),
            1, bagOk and delivered == expected, (bagOk and 1 or 0) + delivered)
    else
        for _, entry in ipairs(type(rolled.resource) == "table" and rolled.resource or {}) do
            if type(entry) == "table" then
                local expected = normalizedQty(entry.qty)
                local delivered, createdItems = HardcoreKitsDelivery.deliverResourceStack(
                    packContainer, entry.fullType, expected)
                record("resource", entry.fullType, expected, expected > 0 and delivered == expected,
                    createdItems or delivered)
            end
        end
    end

    if rolled.melee ~= nil then
        local meleeOk, meleeCreated = HardcoreKitsDelivery.deliverMelee(
            packContainer, rolled.melee, rolled.meleeConditionFraction)
        record("melee", rolled.melee, 1, meleeOk, meleeCreated and 1 or 0)
    end

    if rolled.hasFirearm and type(rolled.firearm) == "table" then
        local ok, ammoDelivered, magazinesDelivered, firearmCreated = HardcoreKitsDelivery.deliverFirearm(
            packContainer, rolled.firearm, rolled.ammoBoxQty, rolled.magazineQty)
        local ammoExpected = normalizedQty(rolled.ammoBoxQty)
        record("firearm", rolled.firearm.fullType, 1, ok, firearmCreated and 1 or 0)
        if ammoExpected > 0 then
            record("ammo", rolled.firearm.ammoBox, ammoExpected, ammoDelivered == ammoExpected, ammoDelivered)
        end
        local magazineExpected = normalizedQty(rolled.magazineQty)
        if rolled.firearm.magazine and magazineExpected > 0 then
            -- ok mesmo quando 0 saem soltos (magazineQty==1: o unico
            -- carregador prometido e o que ja esta dentro da arma)
            local looseExpected = math.max(0, magazineExpected - 1)
            local magazineOk = ok and magazinesDelivered == looseExpected
            record("magazine", rolled.firearm.magazine, magazineExpected, magazineOk, magazinesDelivered)
        end
    end

    for _, e in ipairs(HardcoreKitsDelivery.deliverSkillBoosts(player, rolled.skillBoosts)) do
        record("skill", string.format("%s(%s)/lvl=%.2f/max=%d", tostring(e.groupKey), tostring(e.tier),
            finiteOrZero(e.totalLevels), math.floor(math.max(0, finiteOrZero(e.totalMax)))), e.totalXp, e.ok, e.applied)
    end

    return { granted = granted, total = total, created = created, log = log }
end

-- Recompensa semanal: sempre no inventario principal (nao ha mochila sendo
-- sorteada aqui, secao 12-18 nao menciona uma).
function HardcoreKitsDelivery.deliverSurvivalReward(player, rolledList)
    local log, granted, total, created = {}, 0, 0, 0
    -- mesmo reforco de HardcoreKitsDelivery.deliverInitialKit acima -- ver
    -- comentario la.
    local okInv, mainInv = pcall(function() return player:getInventory() end)
    if not okInv or not mainInv then
        return { granted = 0, total = 1, created = 0,
            log = { { slot = "mainInv", item = nil, qty = 0, ok = false } } }
    end
    if type(rolledList) ~= "table" then
        return { granted = 0, total = 1, created = 0,
            log = { { slot = "rolled", item = nil, qty = 0, ok = false } } }
    end

    local function record(slot, item, qty, ok, createdQty)
        total = total + 1
        if ok then granted = granted + 1 end
        created = created + normalizedQty(createdQty)
        table.insert(log, { slot = slot, item = item, qty = qty, ok = ok })
    end

    for _, r in ipairs(rolledList) do
        if type(r) == "table" and r.category == "combat" and r.subCategory == "melee" then
            for _, entry in ipairs(type(r.items) == "table" and r.items or {}) do
                if type(entry) == "table" then
                    local expected = normalizedQty(entry.qty)
                    local delivered, createdItems = 0, 0
                    for _ = 1, expected do
                        local itemOk, itemCreated = HardcoreKitsDelivery.deliverMelee(
                            mainInv, entry.fullType, r.meleeConditionFraction)
                        if itemOk then delivered = delivered + 1 end
                        if itemCreated then createdItems = createdItems + 1 end
                    end
                    record("combat:melee", entry.fullType, expected,
                        expected > 0 and delivered == expected, createdItems)
                end
            end
        elseif r.category == "combat" and r.subCategory == "firearm" then
            -- entrega a arma ja carregada + 1 carregador (se a arma usar
            -- carregador destacavel, r.magazineQty) + 1 caixa de municao da
            -- propria arma, SEMPRE, garantido (r.ammoBoxQty, ver
            -- HardcoreKits_Rolls.rollSurvivalCombat -- pedido explicito do
            -- usuario, "quando cai arma sempre cai 1 caixa"). Municao
            -- ISOLADA (sem estar ligada a nenhuma arma) e a categoria "ammo"
            -- separada, tratada mais abaixo no branch generico.
            local ok, ammoDelivered, magazinesDelivered, firearmCreated = HardcoreKitsDelivery.deliverFirearm(
                mainInv, r.firearm, r.ammoBoxQty or 0, r.magazineQty)
            record("combat:firearm", r.firearm and r.firearm.fullType or nil, 1, ok,
                firearmCreated and 1 or 0)
            local ammoExpected = normalizedQty(r.ammoBoxQty)
            if ammoExpected > 0 then
                record("combat:ammo", r.firearm and r.firearm.ammoBox or nil, ammoExpected,
                    ammoDelivered == ammoExpected, ammoDelivered)
            end
            local magazineExpected = normalizedQty(r.magazineQty)
            if magazineExpected > 0 then
                local looseExpected = math.max(0, magazineExpected - 1)
                record("combat:magazine", r.firearm and r.firearm.magazine or nil, magazineExpected,
                    ok and magazinesDelivered == looseExpected, magazinesDelivered)
            end
        elseif r.category == "skill" and r.kind == "group" then
            -- bonus raro de GRUPO INTEIRO (duplo sorteio dentro de
            -- rollSurvivalSkillBonus, ver HardcoreKits_Rolls.lua) -- reusa
            -- deliverSkillBoosts (mesma funcao do Kit Inicial) com uma lista
            -- de 1 elemento so, mesmo formato de log da linha "skill" dele.
            local delivered = HardcoreKitsDelivery.deliverSkillBoosts(player, { r })
            local e = delivered[1]
            if e then
                record("skill", string.format("%s(%s)/lvl=%.2f/max=%d", tostring(e.groupKey), tostring(e.tier),
                    finiteOrZero(e.totalLevels), math.floor(math.max(0, finiteOrZero(e.totalMax)))), e.totalXp, e.ok, e.applied)
            end
        elseif r.category == "skill" then
            -- bonus de uma unica skill (raro, ver HardcoreKits_Rolls.rollSurvivalSkillBonus)
            local ok = HardcoreKitsDelivery.deliverSkillBonus(player, r)
            record("skill", string.format("%s(%s)/lvl=%.2f/max=%d", tostring(r.perkName), tostring(r.tier),
                finiteOrZero(r.levels), math.floor(math.max(0, finiteOrZero(r.totalToMax)))), r.xp, ok, ok and 1 or 0)
        elseif r.category == "resource" and r.subCategory == "medicalkit" then
            -- resultado especial: mochila medica recheada (r.medicalKitBag/
            -- Contents ja vem resolvido de HardcoreKits_Rolls) em vez de um
            -- item avulso -- ver HardcoreKitsDelivery.deliverMedicalKit. O
            -- conteudo de dentro e fixo/deterministico (nao sorteado por
            -- claim, so QUANTOS itens de dentro realmente foram entregues) --
            -- por isso o log embute "contents=entregue-esperado" no proprio
            -- campo do item (mesma ideia do campo Skills, que ja embute
            -- lvl=/max= em vez de abrir uma linha por skill). expected e a
            -- SOMA das qty de cada entrada (nao o numero de entradas -- ex:
            -- Bandage sozinho ja e qty=4), senao "ok" nunca bateria mesmo
            -- numa entrega perfeita.
            local bagOk, delivered = HardcoreKitsDelivery.deliverMedicalKit(mainInv, r.medicalKitBag, r.medicalKitContents)
            delivered = delivered or 0
            local expected = 0
            for _, entry in ipairs(type(r.medicalKitContents) == "table" and r.medicalKitContents or {}) do
                if type(entry) == "table" then expected = expected + normalizedQty(entry.qty) end
            end
            record("resource:medicalkit", string.format("%s/contents=%d-%d", tostring(r.medicalKitBag), delivered, expected),
                1, bagOk and delivered == expected, (bagOk and 1 or 0) + delivered)
        else
            -- comida/bebida/recurso/municao -- todos genericos, sempre uma
            -- lista (comida/bebida podem ter N entradas em modo multi-sorteio).
            -- "recurso" usa deliverResourceStack (carga cheia pra lanterna,
            -- ver HardcoreKits_Delivery no topo do arquivo); os demais usam
            -- deliverStack normal, sem diferenca de comportamento.
            local slot = (r.category == "combat") and ("combat:" .. tostring(r.subCategory)) or r.category
            for _, entry in ipairs(type(r.items) == "table" and r.items or {}) do
                if type(entry) == "table" then
                    local expected = normalizedQty(entry.qty)
                    local delivered, createdItems
                    if r.category == "resource" then
                        delivered, createdItems = HardcoreKitsDelivery.deliverResourceStack(
                            mainInv, entry.fullType, expected)
                    else
                        delivered = HardcoreKitsDelivery.deliverStack(mainInv, entry.fullType, expected)
                        createdItems = delivered
                    end
                    record(slot, entry.fullType, expected, expected > 0 and delivered == expected,
                        createdItems or delivered)
                end
            end
        end
    end

    return { granted = granted, total = total, created = created, log = log }
end
