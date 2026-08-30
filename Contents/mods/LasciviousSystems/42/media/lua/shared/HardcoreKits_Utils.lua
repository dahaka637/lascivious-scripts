-- Helpers puros e pequenos, sem estado e sem efeito colateral.
-- Compartilhado entre client e server (formatacao de tempo e usada nos dois lados).
HardcoreKitsUtils = HardcoreKitsUtils or {}

local function finiteNumber(value)
    local n = tonumber(value)
    if not n or n ~= n or n == math.huge or n == -math.huge then return nil end
    return n
end

-- inteiro aleatorio uniforme em [a,b]
function HardcoreKitsUtils.randInt(a, b)
    a = math.floor(finiteNumber(a) or 0)
    b = math.floor(finiteNumber(b) or a)
    if a > b then a, b = b, a end
    a = math.max(-2147483647, math.min(2147483646, a))
    b = math.max(-2147483647, math.min(2147483646, b))
    if b == a then return a end
    return ZombRand(a, b + 1)
end

-- escolhe um indice em `list` (array 1-based) uniformemente
function HardcoreKitsUtils.pick(list)
    if type(list) ~= "table" or #list == 0 then return nil end
    return list[ZombRand(1, #list + 1)]
end

-- sorteio ponderado. `weights` = { chave = peso, ... }. Retorna a chave sorteada.
-- Pesos nao precisam somar 100, sao normalizados. Ignora pesos <= 0.
function HardcoreKitsUtils.weightedKey(weights)
    if type(weights) ~= "table" then return nil end
    local total, maxWeight = 0, 0
    for _, w in pairs(weights) do
        w = finiteNumber(w)
        if w and w > maxWeight then maxWeight = w end
    end
    if maxWeight <= 0 then return nil end
    for _, w in pairs(weights) do
        w = finiteNumber(w)
        if w and w > 0 then total = total + (w / maxWeight) end
    end
    local roll = ZombRandFloat(0, total)
    local acc = 0
    -- ordena as chaves para que o resultado seja deterministico dado o
    -- mesmo roll (pairs() nao garante ordem, e isso tornaria testes e
    -- logs inconsistentes entre execucoes)
    local keys = {}
    for k, w in pairs(weights) do
        w = finiteNumber(w)
        if w and w > 0 then table.insert(keys, k) end
    end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    for _, k in ipairs(keys) do
        acc = acc + ((finiteNumber(weights[k]) or 0) / maxWeight)
        if roll < acc then return k end
    end
    return keys[#keys]
end

-- mesma ideia, mas para uma lista de {value=..., weight=...} em vez de um mapa
function HardcoreKitsUtils.weightedValue(entries)
    if type(entries) ~= "table" then return nil end
    local total, maxWeight = 0, 0
    local lastValid = nil
    for _, e in ipairs(entries) do
        local w = type(e) == "table" and finiteNumber(e.weight) or nil
        if w and w > 0 then
            if w > maxWeight then maxWeight = w end
            lastValid = e.value
        end
    end
    if maxWeight <= 0 then return nil end
    for _, e in ipairs(entries) do
        local w = type(e) == "table" and finiteNumber(e.weight) or nil
        if w and w > 0 then total = total + (w / maxWeight) end
    end
    local roll = ZombRandFloat(0, total)
    local acc = 0
    for _, e in ipairs(entries) do
        local w = type(e) == "table" and finiteNumber(e.weight) or nil
        if w and w > 0 then
            acc = acc + (w / maxWeight)
            if roll < acc then return e.value end
        end
    end
    return lastValid
end

-- sorteia N elementos DISTINTOS de `list`, sem reposicao (nunca repete
-- indice). n > #list e silenciosamente limitado a #list. Algoritmo
-- swap-com-o-ultimo-e-encolhe -- sem vies, O(n).
function HardcoreKitsUtils.pickN(list, n)
    n = finiteNumber(n)
    if type(list) ~= "table" or not n or n <= 0 then return {} end
    n = math.floor(n)
    local pool = {}
    for i, v in ipairs(list) do pool[i] = v end
    local remaining = #pool
    n = math.min(n, remaining)
    local out = {}
    for _ = 1, n do
        local idx = ZombRand(1, remaining + 1)
        table.insert(out, pool[idx])
        pool[idx] = pool[remaining]
        remaining = remaining - 1
    end
    return out
end

-- mesma ideia de pickN (N elementos DISTINTOS, sem reposicao), mas com peso
-- por item -- weightFn(item) devolve o peso (numero > 0; nil/nao numerico vira
-- peso 1 e <=0 exclui o item, permitindo que o sandbox realmente use peso 0).
-- A cada rodada, sorteia dentre o que
-- SOBROU no pool (nao o pool original) via um weightedKey normal sobre os
-- indices restantes -- e o jeito correto de fazer amostra ponderada sem
-- reposicao (cada rodada reflete os pesos relativos do que ainda nao saiu).
function HardcoreKitsUtils.pickNWeighted(list, n, weightFn)
    n = finiteNumber(n)
    if type(list) ~= "table" or not n or n <= 0 then return {} end
    n = math.floor(n)
    local pool = {}
    for i, v in ipairs(list) do pool[i] = v end
    n = math.min(n, #pool)
    local out = {}
    for _ = 1, n do
        if #pool == 0 then break end
        local total, maxWeight = 0, 0
        local weights = {}
        for i, v in ipairs(pool) do
            local raw = weightFn and weightFn(v) or 1
            local w = finiteNumber(raw)
            if not w then w = 1 end
            if w < 0 then w = 0 end
            weights[i] = w
            if w > maxWeight then maxWeight = w end
        end
        if maxWeight <= 0 then break end
        for _, w in ipairs(weights) do total = total + (w / maxWeight) end
        local roll = ZombRandFloat(0, total)
        local acc = 0
        local chosenIdx = #pool
        for i, w in ipairs(weights) do
            acc = acc + (w / maxWeight)
            if roll < acc then
                chosenIdx = i
                break
            end
        end
        table.insert(out, pool[chosenIdx])
        pool[chosenIdx] = pool[#pool]
        table.remove(pool)
    end
    return out
end

-- roll booleano com `chancePercent` de chance de true (0..100)
function HardcoreKitsUtils.rollChance(chancePercent)
    local chance = finiteNumber(chancePercent) or 0
    chance = math.max(0, math.min(100, chance))
    return ZombRandFloat(0, 100) < chance
end

-- epoch real (independente do tempo de jogo), 0 se indisponivel
function HardcoreKitsUtils.realTime()
    local ok, t = pcall(getTimestamp)
    if ok and type(t) == "number" and t == t and t > 0
        and t ~= math.huge and t ~= -math.huge then return t end
    return 0
end

-- segundos -> "Xd Yh Zm" (omite unidades zeradas a esquerda)
function HardcoreKitsUtils.formatDuration(totalSeconds)
    totalSeconds = finiteNumber(totalSeconds) or 0
    totalSeconds = math.max(0, math.floor(totalSeconds))
    local days = math.floor(totalSeconds / 86400)
    local hours = math.floor((totalSeconds % 86400) / 3600)
    local minutes = math.floor((totalSeconds % 3600) / 60)
    if days > 0 then
        return string.format("%dd %dh %dm", days, hours, minutes)
    elseif hours > 0 then
        return string.format("%dh %dm", hours, minutes)
    else
        return string.format("%dm", math.max(minutes, totalSeconds > 0 and 1 or 0))
    end
end

-- id curto e legivel para transacoes/logs: HK-<epoch36>-<random5>
function HardcoreKitsUtils.newClaimId()
    local t = HardcoreKitsUtils.realTime()
    local rnd = ZombRand(0, 60466176) -- 36^5; reduz colisoes sob carga
    return string.format("HK-%s-%s", HardcoreKitsUtils.toBase36(t), HardcoreKitsUtils.toBase36(rnd))
end

local BASE36_DIGITS = "0123456789abcdefghijklmnopqrstuvwxyz"
function HardcoreKitsUtils.toBase36(n)
    n = finiteNumber(n) or 0
    n = math.floor(n)
    if n <= 0 then return "0" end
    local out = ""
    while n > 0 do
        local d = (n % 36) + 1
        out = string.sub(BASE36_DIGITS, d, d) .. out
        n = math.floor(n / 36)
    end
    return out
end

-- deep-ish copy de tabelas simples (config/resultado de sorteio), suficiente
-- para nao vazar referencia mutavel entre um resultado e o pool de origem
function HardcoreKitsUtils.shallowCopy(t)
    if type(t) ~= "table" then return t end
    local out = {}
    for k, v in pairs(t) do out[k] = v end
    return out
end
