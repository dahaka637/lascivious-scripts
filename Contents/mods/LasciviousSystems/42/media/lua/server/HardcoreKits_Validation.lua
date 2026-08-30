-- Valida cada fullType configurado contra o ScriptManager antes de deixar a
-- roleta escolhe-lo. Itens de mods removidos ou renomeados sao logados e
-- descartados silenciosamente do pool em memoria -- nunca travam o mod
-- inteiro (secao 24 da especificacao).
if isClient() then return end

require "HardcoreKits_Config"
require "HardcoreKits_Pools"
require "HardcoreKits_Utils"
require "HardcoreKits_ModdedContent"
require "GoMCompat"

HardcoreKitsValidation = HardcoreKitsValidation or {}

-- pools "limpos": mesma forma dos pools originais, mas so com entradas que
-- existem de verdade no servidor atual. Rolls.lua le APENAS daqui, nunca de
-- HardcoreKitsPools diretamente.
HardcoreKitsValidatedPools = HardcoreKitsValidatedPools or {
    FoodCanned = {}, FoodPickled = {}, FoodSecondary = {},
    DrinkWater = {}, DrinkOther = {},
    MeleeByCategory = {},
    MeleeHighDamageByCategory = {},
    Firearms = {},
    AmmoBoxes = {},
    BackpackByTier = {},
    Resources = {},
    TraumaBagBag = nil,
    TraumaBagContents = {},
    MedicalKitBag = nil,
    MedicalKitGuaranteed = {},
    MedicalKitRandomPool = {},
}

local existsCache = {}
local actualWeightCache = {}
local lastFullValidation = 0

-- true/false com cache -- getScriptManager():FindItem e barato, mas uma
-- roleta chega a checar dezenas de itens em sequencia rapida
local function itemExists(fullType)
    if type(fullType) ~= "string" or fullType == "" then return false end
    local cached = existsCache[fullType]
    if cached ~= nil then return cached end
    local ok, script = pcall(function()
        return getScriptManager():FindItem(fullType)
    end)
    local found = ok and script ~= nil
    existsCache[fullType] = found
    return found
end
HardcoreKitsValidation.itemExists = itemExists

-- Weight real do script (campo Weight, exposto por Item:getActualWeight()).
-- Cacheia somente o valor bruto; limite e porcentagem continuam sendo lidos
-- do Config a cada sorteio, entao mudancas no sandbox nao exigem revalidar os
-- pools. nil significa API/item indisponivel e faz a arma permanecer com o
-- peso normal no sorteio, em vez de ser penalizada por um dado desconhecido.
local function itemActualWeight(fullType)
    local cached = actualWeightCache[fullType]
    if cached ~= nil then return cached ~= false and cached or nil end
    local ok, script = pcall(function() return getScriptManager():FindItem(fullType) end)
    if not ok or not script then
        actualWeightCache[fullType] = false
        return nil
    end
    local okWeight, weight = pcall(function() return script:getActualWeight() end)
    if not okWeight or type(weight) ~= "number" or weight ~= weight
        or weight == math.huge or weight == -math.huge then
        actualWeightCache[fullType] = false
        return nil
    end
    actualWeightCache[fullType] = weight
    return weight
end
HardcoreKitsValidation.itemActualWeight = itemActualWeight

local function logInvalid(context, fullType)
    print(string.format("[HardcoreKits] Item invalido ignorado (%s): %s", context, tostring(fullType)))
end

-- dano real (MaxDamage do script, zombie.scripting.objects.Item:getMaxDamage(),
-- confirmado via decompilacao -- o mesmo objeto que FindItem() ja devolve pra
-- itemExists() acima, sem precisar instanciar o item) -- usado so pelo filtro
-- "equipamento superior" do Kit Inicial (InitialMeleeHighDamageOnly, ver
-- HardcoreKits_Config.lua). nil quando o item nao existe ou nao e uma arma
-- (sem campo MaxDamage de verdade).
local function itemMaxDamage(fullType)
    local ok, script = pcall(function() return getScriptManager():FindItem(fullType) end)
    if not ok or not script then return nil end
    local okDmg, dmg = pcall(function() return script:getMaxDamage() end)
    if okDmg and type(dmg) == "number" and dmg == dmg
        and dmg ~= math.huge and dmg ~= -math.huge then return dmg end
    return nil
end

local function filterList(list, context)
    local out = {}
    for _, fullType in ipairs(list or {}) do
        if itemExists(fullType) then
            table.insert(out, fullType)
        else
            logInvalid(context, fullType)
        end
    end
    return out
end

-- reconstroi HardcoreKitsValidatedPools inteiro a partir de HardcoreKitsPools.
-- Roda no boot do servidor e pode ser re-chamada periodicamente (config
-- RevalidatePoolsEveryRealHours) para pegar mods removidos em live.
function HardcoreKitsValidation.validateAll()
    existsCache = {}
    actualWeightCache = {}
    lastFullValidation = HardcoreKitsUtils.realTime()

    HardcoreKitsValidatedPools.FoodCanned = filterList(HardcoreKitsPools.FoodCanned, "comida enlatada")
    HardcoreKitsValidatedPools.FoodPickled = filterList(HardcoreKitsPools.FoodPickled, "comida em conserva")
    HardcoreKitsValidatedPools.FoodSecondary = filterList(HardcoreKitsPools.FoodSecondary, "comida secundaria")
    HardcoreKitsValidatedPools.DrinkWater = filterList(HardcoreKitsPools.DrinkWater, "bebida (agua)")
    HardcoreKitsValidatedPools.DrinkOther = filterList(HardcoreKitsPools.DrinkOther, "bebida (outras)")
    HardcoreKitsValidatedPools.AmmoBoxes = filterList(HardcoreKitsPools.AmmoBoxes, "caixa de municao avulsa")
    HardcoreKitsValidatedPools.Resources = filterList(HardcoreKitsPools.Resources, "recurso/ferramenta")

    -- bolsa de trauma e kit medico: se a propria mochila/maleta nao existir
    -- mais, o bundle inteiro fica indisponivel (Rolls.lua cai de volta pro
    -- sorteio normal de recurso avulso) -- os itens de dentro sao filtrados
    -- um a um, igual a qualquer outro pool. Dois bundles independentes desde
    -- 2026-08-05 -- ver comentario em HardcoreKits_Pools.lua. A propria
    -- mochila/maleta avisa no console se nao validar (unico jeito de pegar
    -- esse caso especifico -- os itens de DENTRO ja tem logInvalid()).
    HardcoreKitsValidatedPools.TraumaBagBag = itemExists(HardcoreKitsPools.TraumaBagBag)
        and HardcoreKitsPools.TraumaBagBag or nil
    if not HardcoreKitsValidatedPools.TraumaBagBag then
        print("[HardcoreKits] AVISO: bolsa de trauma invalida -- item nao encontrado: "
            .. tostring(HardcoreKitsPools.TraumaBagBag))
    end
    HardcoreKitsValidatedPools.TraumaBagContents = {}
    for _, entry in ipairs(HardcoreKitsPools.TraumaBagContents or {}) do
        if type(entry) == "table" and itemExists(entry.fullType) then
            table.insert(HardcoreKitsValidatedPools.TraumaBagContents, entry)
        else
            logInvalid("item da bolsa de trauma", type(entry) == "table" and entry.fullType or entry)
        end
    end
    HardcoreKitsValidatedPools.MedicalKitBag = itemExists(HardcoreKitsPools.MedicalKitBag)
        and HardcoreKitsPools.MedicalKitBag or nil
    if not HardcoreKitsValidatedPools.MedicalKitBag then
        print("[HardcoreKits] AVISO: kit medico invalido -- item nao encontrado: "
            .. tostring(HardcoreKitsPools.MedicalKitBag))
    end
    -- conteudo do kit medico: parte GARANTIDA (sempre entregue) + pool de
    -- itens que sorteiam aleatoriamente (tipos e quantidade) na hora da
    -- entrega -- ver HardcoreKitsRolls.rollMedicalKitContents. O pool
    -- aleatorio e uma lista de fullTypes (nao {fullType=,qty=}), entao usa
    -- filterList como o resto dos pools "simples".
    HardcoreKitsValidatedPools.MedicalKitGuaranteed = {}
    for _, entry in ipairs(HardcoreKitsPools.MedicalKitGuaranteed or {}) do
        if type(entry) == "table" and itemExists(entry.fullType) then
            table.insert(HardcoreKitsValidatedPools.MedicalKitGuaranteed, entry)
        else
            logInvalid("item garantido do kit medico", type(entry) == "table" and entry.fullType or entry)
        end
    end
    HardcoreKitsValidatedPools.MedicalKitRandomPool = filterList(HardcoreKitsPools.MedicalKitRandomPool, "item aleatorio do kit medico")
    HardcoreKitsValidatedPools.MeleeByCategory = {}
    for category, list in pairs(HardcoreKitsPools.MeleeByCategory or {}) do
        HardcoreKitsValidatedPools.MeleeByCategory[category] = filterList(list,
            "arma corpo a corpo (" .. tostring(category) .. ")")
    end

    HardcoreKitsValidatedPools.BackpackByTier = {}
    for tier, list in pairs(HardcoreKitsPools.BackpackByTier or {}) do
        HardcoreKitsValidatedPools.BackpackByTier[tier] = filterList(list, "mochila (" .. tostring(tier) .. ")")
    end

    -- extraido do loop original (era so o corpo do for abaixo) pra poder ser
    -- reaproveitado tambem pro pool do GoM, ver bloco de compatibilidade logo
    -- depois. Mesma logica exata de antes -- so virou funcao.
    local function validateFirearms(list, context)
        local out = {}
        for _, def in ipairs(list or {}) do
            if type(def) == "table" and itemExists(def.fullType) then
                local ammoOk = itemExists(def.ammoBox)
                local magOk = (def.magazine == nil) or itemExists(def.magazine)
                if not ammoOk then
                    logInvalid("caixa de municao da arma " .. def.fullType, def.ammoBox)
                end
                if not magOk then
                    logInvalid("carregador da arma " .. def.fullType, def.magazine)
                end
                -- uma arma sem municao valida configurada e inutil e perigosa de
                -- sortear (secao 10.2: "nao entregar municao incompativel") --
                -- melhor remove-la do pool do que entregar so a arma vazia
                if ammoOk and magOk then
                    table.insert(out, def)
                end
            else
                logInvalid(context, type(def) == "table" and def.fullType or def)
            end
        end
        return out
    end

    -- Guns of Marz (GoM) ativo no servidor: troca o pool inteiro de armas de
    -- fogo e caixas de municao pro equivalente do GoM (HardcoreKitsPools.
    -- GoMFirearms/GoMAmmoBoxes, ver HardcoreKits_Pools.lua) em vez do vanilla
    -- -- decisao explicita do servidor (GoM nao remove as armas vanilla
    -- sozinho, ver comentario em GoMCompat.lua). HardcoreKitsValidatedPools.
    -- AmmoBoxes ja foi montado com o vanilla la em cima; aqui e sobrescrito de
    -- proposito quando o GoM esta presente.
    if GoMCompat.isActive() then
        HardcoreKitsValidatedPools.Firearms = validateFirearms(HardcoreKitsPools.GoMFirearms, "arma de fogo (GoM)")
        HardcoreKitsValidatedPools.AmmoBoxes = filterList(HardcoreKitsPools.GoMAmmoBoxes, "caixa de municao avulsa (GoM)")
        print("[HardcoreKits] Guns of Marz detectado: armas de fogo e municao vanilla desativadas, usando o pool do GoM.")
    else
        HardcoreKitsValidatedPools.Firearms = validateFirearms(HardcoreKitsPools.Firearms, "arma de fogo")
    end

    local function categoryCounts(mapOfLists)
        local parts = {}
        for category, list in pairs(mapOfLists) do
            table.insert(parts, tostring(category) .. ":" .. #list)
        end
        table.sort(parts)
        return "{" .. table.concat(parts, " ") .. "}"
    end

    print(string.format(
        "[HardcoreKits] Validacao de pools concluida: FoodCanned=%d FoodPickled=%d FoodSecondary=%d "
        .. "DrinkWater=%d DrinkOther=%d AmmoBoxes=%d Resources=%d Firearms=%d Melee=%s Backpacks=%s",
        #HardcoreKitsValidatedPools.FoodCanned, #HardcoreKitsValidatedPools.FoodPickled,
        #HardcoreKitsValidatedPools.FoodSecondary, #HardcoreKitsValidatedPools.DrinkWater,
        #HardcoreKitsValidatedPools.DrinkOther, #HardcoreKitsValidatedPools.AmmoBoxes,
        #HardcoreKitsValidatedPools.Resources, #HardcoreKitsValidatedPools.Firearms,
        categoryCounts(HardcoreKitsValidatedPools.MeleeByCategory),
        categoryCounts(HardcoreKitsValidatedPools.BackpackByTier)
    ))

    -- por ultimo de proposito: precisa dos pools estaticos ja reconstruidos
    -- acima nesta mesma passada (so mexe em HardcoreKitsValidatedPools, nunca
    -- na fonte estatica -- ver comentario em HardcoreKits_ModdedContent.lua)
    HardcoreKitsModdedContent.scan()

    -- por ultimo de novo, de proposito: MeleeByCategory.modded so existe
    -- depois do scan acima -- assim armas corpo a corpo de outros mods
    -- tambem entram no filtro de dano do Kit Inicial, nao so as curadas a
    -- mao. So mexe em HardcoreKitsValidatedPools.MeleeHighDamageByCategory
    -- (pool DERIVADO, nunca uma fonte propria) -- reconstruido do zero a
    -- cada passada, sem risco de acumular duplicata.
    HardcoreKitsValidatedPools.MeleeHighDamageByCategory = {}
    local minDamage = tonumber(HardcoreKitsConfig.InitialMeleeMinDamage) or 0
    if minDamage ~= minDamage or minDamage == math.huge or minDamage == -math.huge then minDamage = 0 end
    for category, list in pairs(HardcoreKitsValidatedPools.MeleeByCategory) do
        local filtered = {}
        for _, fullType in ipairs(list) do
            local dmg = itemMaxDamage(fullType)
            if dmg and dmg >= minDamage then
                table.insert(filtered, fullType)
            end
        end
        HardcoreKitsValidatedPools.MeleeHighDamageByCategory[category] = filtered
    end
end

function HardcoreKitsValidation.maybeRevalidate()
    local everyHours = tonumber(HardcoreKitsConfig.RevalidatePoolsEveryRealHours)
    if not everyHours or everyHours ~= everyHours or everyHours <= 0
        or everyHours == math.huge or everyHours == -math.huge then return end
    if HardcoreKitsUtils.realTime() - lastFullValidation >= everyHours * 3600 then
        HardcoreKitsValidation.validateAll()
    end
end

if HardcoreKitsValidation._serverStartedHandler and Events.OnServerStarted.Remove then
    Events.OnServerStarted.Remove(HardcoreKitsValidation._serverStartedHandler)
end
if HardcoreKitsValidation._gameStartHandler and Events.OnGameStart.Remove then
    Events.OnGameStart.Remove(HardcoreKitsValidation._gameStartHandler)
end
HardcoreKitsValidation._serverStartedHandler = HardcoreKitsValidation.validateAll
HardcoreKitsValidation._gameStartHandler = HardcoreKitsValidation.validateAll
Events.OnServerStarted.Add(HardcoreKitsValidation._serverStartedHandler)
Events.OnGameStart.Add(HardcoreKitsValidation._gameStartHandler) -- cobre singleplayer

-- 2026-08-06: maybeRevalidate() existia desde sempre mas nunca era chamada
-- de lugar nenhum -- RevalidatePoolsEveryRealHours ficava sem efeito nenhum
-- na pratica (a validacao so rodava mesmo no boot). Achado ao mexer nesta
-- mesma area pro live-reload das opcoes de sandbox (pedido do usuario, ver
-- HardcoreKits_SandboxBridge.lua) -- corrigido junto, mesmo espirito. Ela ja
-- se autolimita pelo intervalo configurado (RevalidatePoolsEveryRealHours,
-- escala de HORAS), mas mesmo assim checa isso via Events.OnTick direto seria
-- centenas de vezes por segundo -- throttle local aqui so pra nao chamar
-- realTime()/pcall a cada tick a toa, checagem de verdade continua so na
-- escala de horas configurada.
local REVALIDATE_CHECK_INTERVAL_MS = 30000
local lastRevalidateCheckAtMs = 0
local function maybeRevalidateThrottled()
    local ok, now = pcall(getTimestampMs)
    if not ok or type(now) ~= "number" or now ~= now or now <= 0
        or now == math.huge or now == -math.huge then return end
    if now < lastRevalidateCheckAtMs then lastRevalidateCheckAtMs = 0 end
    if now - lastRevalidateCheckAtMs < REVALIDATE_CHECK_INTERVAL_MS then return end
    lastRevalidateCheckAtMs = now
    HardcoreKitsValidation.maybeRevalidate()
end
if HardcoreKitsValidation._revalidateTickHandler and Events.OnTick.Remove then
    Events.OnTick.Remove(HardcoreKitsValidation._revalidateTickHandler)
end
HardcoreKitsValidation._revalidateTickHandler = maybeRevalidateThrottled
Events.OnTick.Add(maybeRevalidateThrottled)
