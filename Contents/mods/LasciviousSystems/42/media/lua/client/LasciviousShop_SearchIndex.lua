if isServer() then return end

require "LasciviousShop_Shared"
require "LasciviousShop_Catalog"

local LS = LasciviousShop

LasciviousShopSearchIndex = LasciviousShopSearchIndex or {}
local Search = LasciviousShopSearchIndex

-- Search data lives for the whole client session. Product names and words are
-- resolved once, category lists contain only stable product IDs, and the game
-- item registry is never consulted from the filtering hot path after warmup.
Search.records = Search.records or {}
Search.idsByCategory = Search.idsByCategory or {}
Search.allIds = Search.allIds or {}
Search.wordIds = Search.wordIds or {}
Search.wordsByLength = Search.wordsByLength or {}
Search.warmCursor = tonumber(Search.warmCursor) or 1

local SEARCH_FOLD = {
    {"á","a"}, {"à","a"}, {"â","a"}, {"ã","a"}, {"ä","a"},
    {"Á","a"}, {"À","a"}, {"Â","a"}, {"Ã","a"}, {"Ä","a"},
    {"é","e"}, {"è","e"}, {"ê","e"}, {"ë","e"},
    {"É","e"}, {"È","e"}, {"Ê","e"}, {"Ë","e"},
    {"í","i"}, {"ì","i"}, {"î","i"}, {"ï","i"},
    {"Í","i"}, {"Ì","i"}, {"Î","i"}, {"Ï","i"},
    {"ó","o"}, {"ò","o"}, {"ô","o"}, {"õ","o"}, {"ö","o"},
    {"Ó","o"}, {"Ò","o"}, {"Ô","o"}, {"Õ","o"}, {"Ö","o"},
    {"ú","u"}, {"ù","u"}, {"û","u"}, {"ü","u"},
    {"Ú","u"}, {"Ù","u"}, {"Û","u"}, {"Ü","u"},
    {"ç","c"}, {"Ç","c"}, {"ñ","n"}, {"Ñ","n"},
}

local SEARCH_STOP_WORDS = {
    a=true, as=true, o=true, os=true, e=true, de=true, da=true, das=true,
    ["do"]=true, dos=true, para=true, com=true, um=true, uma=true,
    the=true, of=true, ["for"]=true, with=true, ["and"]=true,
}

local SEARCH_ALIASES = {
    DescResource="recurso ferramenta material construcao manutencao oficina craft crafting",
    DescVehiclePart="mecanica mecanico automotivo automovel carro veiculo reparo reposicao mechanic automotive vehicle",
    DescContainer="recipiente bolsa caixa maleta armazenamento container bag storage",
    DescAppliance="eletrodomestico eletrico cozinha appliance",
    DescFurniture="movel mobilia armazenamento furniture storage",
    DescCraftingStation="estacao trabalho oficina maquina crafting workshop machine",
    DescWeaponPart="acessorio arma mira luneta weapon attachment scope",
    DescSpecial="equipamento especial sobrevivencia utilidade survival utility",
    DescTobacco="tabaco fumo cigarro charuto isqueiro seda fumar tobacco smoke cigarette cigar lighter rolling paper",
    DescEntertainment="leitura livro revista jornal jogo lazer entretenimento reading book magazine newspaper game entertainment",
    DescMap="mapa cidade regiao localizacao rota map city region location route",
}

local SEARCH_SYNONYMS = {
    agua={"water"}, water={"agua"}, bebida={"drink"}, drink={"bebida"},
    comida={"food","alimento"}, alimento={"comida","food"}, food={"comida","alimento"},
    arma={"weapon"}, weapon={"arma"},
    municao={"ammo","ammunition","bala"}, ammo={"municao","ammunition"},
    ammunition={"municao","ammo"}, bala={"municao"},
    remedio={"medicina","medical","medicine","medicamento"},
    medicamento={"remedio","medicina","medicine"}, medicine={"remedio","medicina"},
    mecanica={"mechanic","automotivo","veiculo"}, mechanic={"mecanica","automotivo"},
    carro={"veiculo","vehicle","automovel"}, veiculo={"carro","vehicle","automovel"},
    gasolina={"fuel","petrol","combustivel"}, combustivel={"gasolina","fuel","petrol"},
    geladeira={"fridge","refrigerator"}, freezer={"congelador"}, congelador={"freezer"},
    mochila={"backpack","bag"}, bolsa={"bag"}, recipiente={"container"},
    ferramenta={"tool"}, material={"resource","recurso"}, recurso={"resource","material"},
    roupa={"clothing","vestuario"}, vestuario={"roupa","clothing"},
    protecao={"protetor","guard","armor","armour"}, protetor={"protecao","guard"},
    joelheira={"kneepad","knee"}, cotoveleira={"elbowpad","elbow"},
    livro={"book"}, semente={"seed"}, gerador={"generator"}, caixa={"box"},
}

local function normalize(value, splitIdentifier)
    value = tostring(value or "")
    if splitIdentifier then
        value = string.gsub(value, "(%l)(%u)", "%1 %2")
        value = string.gsub(value, "(%a)(%d)", "%1 %2")
        value = string.gsub(value, "(%d)(%a)", "%1 %2")
    end
    value = string.lower(value)
    for index = 1, #SEARCH_FOLD do
        local replacement = SEARCH_FOLD[index]
        value = string.gsub(value, replacement[1], replacement[2])
    end
    value = string.gsub(value, "[^%w]+", " ")
    value = string.gsub(value, "%s+", " ")
    value = string.gsub(value, "^%s+", "")
    value = string.gsub(value, "%s+$", "")
    return value
end
Search.normalize = normalize

local function wordsOf(value, removeStopWords)
    local words = {}
    for word in string.gmatch(value or "", "[a-z0-9]+") do
        if not removeStopWords or not SEARCH_STOP_WORDS[word] then
            words[#words + 1] = word
        end
    end
    return words
end

local function addUnique(list, seen, value)
    if value and value ~= "" and not seen[value] then
        seen[value] = true
        list[#list + 1] = value
    end
end

local function wordVariants(word)
    local variants, seen = {}, {}
    addUnique(variants, seen, word)
    local length = #word
    if length > 3 and string.sub(word, -1) == "s" then
        addUnique(variants, seen, string.sub(word, 1, -2))
    end
    if length > 4 and string.sub(word, -2) == "es" then
        addUnique(variants, seen, string.sub(word, 1, -3))
    end
    if length > 5 and string.sub(word, -3) == "oes" then
        addUnique(variants, seen, string.sub(word, 1, -4) .. "ao")
    end
    if length > 4 and string.sub(word, -3) == "ais" then
        addUnique(variants, seen, string.sub(word, 1, -4) .. "al")
    end
    if length > 4 and string.sub(word, -2) == "is" then
        addUnique(variants, seen, string.sub(word, 1, -3) .. "il")
    end
    local synonyms = SEARCH_SYNONYMS[word] or {}
    for index = 1, #synonyms do addUnique(variants, seen, synonyms[index]) end
    return variants
end

local function prepareQuery(query)
    query = normalize(query)
    if query == "" then return nil, query end
    local words = wordsOf(query, true)
    if #words == 0 then words = wordsOf(query, false) end
    local concepts = {}
    for index = 1, #words do concepts[#concepts + 1] = wordVariants(words[index]) end
    return { text=query, concepts=concepts }, query
end

local function addCategoryId(categoryId, productId)
    if not categoryId then return end
    local ids = Search.idsByCategory[categoryId]
    if not ids then
        ids = {}
        Search.idsByCategory[categoryId] = ids
    end
    ids[#ids + 1] = productId
end

if not Search.categoriesBuilt then
    Search.allIds = {}
    Search.idsByCategory = {}
    for index = 1, #LS.PRODUCTS do
        local product = LS.PRODUCTS[index]
        Search.allIds[#Search.allIds + 1] = product.id
        addCategoryId(product.category, product.id)
        local extras = product.extraCategories or {}
        for extraIndex = 1, #extras do addCategoryId(extras[extraIndex], product.id) end
    end
    Search.categoriesBuilt = true
end

local function indexWord(word, productId)
    local ids = Search.wordIds[word]
    if not ids then
        ids = {}
        Search.wordIds[word] = ids
        local length = #word
        local bucket = Search.wordsByLength[length]
        if not bucket then
            bucket = {}
            Search.wordsByLength[length] = bucket
        end
        bucket[#bucket + 1] = word
    end
    ids[#ids + 1] = productId
end

function Search.record(product)
    if not product then return nil end
    local cached = Search.records[product.id]
    if cached then return cached end

    local displayName = LS.productName(product)
    local description = LS.productDescription(product)
    local name = normalize(displayName)
    local identifier = normalize(product.fullType or product.perk or product.id, true)
    local fallback = normalize(product.fallback or "", true)
    local aliases = normalize(SEARCH_ALIASES[product.descKey] or "")
    local text = table.concat({ name, normalize(description), identifier, fallback, aliases }, " ")
    local primaryWords = {}
    local nameWords = wordsOf(name, false)
    for index = 1, #nameWords do primaryWords[nameWords[index]] = true end
    local seen, words = {}, {}
    local allWords = wordsOf(text, false)
    for index = 1, #allWords do
        local word = allWords[index]
        if not seen[word] then
            seen[word] = true
            words[#words + 1] = word
            indexWord(word, product.id)
        end
    end
    cached = {
        id=product.id, name=name, text=text, words=words,
        primaryWords=primaryWords, displayName=displayName, description=description,
    }
    Search.records[product.id] = cached
    return cached
end

function Search.warmBatch(maxProducts, maxMilliseconds)
    local cursor = tonumber(Search.warmCursor) or 1
    if cursor > #LS.PRODUCTS then return true end
    local startedAt = getTimestampMs and getTimestampMs() or 0
    local last = math.min(#LS.PRODUCTS, cursor + math.max(1, tonumber(maxProducts) or 8) - 1)
    while cursor <= last do
        Search.record(LS.PRODUCTS[cursor])
        cursor = cursor + 1
        if startedAt > 0 and maxMilliseconds and getTimestampMs()
            - startedAt >= maxMilliseconds then break end
    end
    Search.warmCursor = cursor
    return cursor > #LS.PRODUCTS
end

function Search.idsForCategory(categoryId, currentState)
    if categoryId == "offers" then return currentState and currentState.offerIds or {} end
    if not categoryId or categoryId == "all" then return Search.allIds end
    return Search.idsByCategory[categoryId] or {}
end

local function directWordScore(queryWord, candidate)
    if queryWord == candidate then return 260 end
    local queryLength, candidateLength = #queryWord, #candidate
    if queryLength >= 2 and string.find(candidate, queryWord, 1, true) == 1 then
        return 220 - math.min(40, candidateLength - queryLength)
    end
    if queryLength >= 3 and string.find(candidate, queryWord, 1, true) then
        return 190 - math.min(40, candidateLength - queryLength)
    end
    if candidateLength >= 3 and queryLength >= candidateLength
        and queryLength - candidateLength <= 3
        and string.find(queryWord, candidate, 1, true) == 1 then
        return 170 - (queryLength - candidateLength) * 10
    end
    return 0
end

local function directMatch(record, prepared)
    local total = 0
    for conceptIndex = 1, #prepared.concepts do
        local variants = prepared.concepts[conceptIndex]
        local best = 0
        for variantIndex = 1, #variants do
            local variant = variants[variantIndex]
            for wordIndex = 1, #record.words do
                local candidate = record.words[wordIndex]
                local score = directWordScore(variant, candidate)
                if score > 0 and record.primaryWords[candidate] then score = score + 35 end
                if score > best then best = score end
            end
        end
        if best <= 0 then return 0 end
        total = total + best
    end
    return total
end

-- Bounded Damerau-Levenshtein is intentionally reserved for the no-direct-hit
-- fallback. Length buckets prevent unrelated catalog words from reaching it.
local function boundedEditDistance(a, b, limit)
    local aLength, bLength = #a, #b
    if math.abs(aLength - bLength) > limit then return nil end
    local previousPrevious = nil
    local previous = {}
    for column = 0, bLength do previous[column] = column end
    for row = 1, aLength do
        local current = { [0]=row }
        local rowMinimum = row
        local aByte = string.byte(a, row)
        for column = 1, bLength do
            local cost = aByte == string.byte(b, column) and 0 or 1
            local value = math.min(current[column - 1] + 1,
                previous[column] + 1, previous[column - 1] + cost)
            if previousPrevious and row > 1 and column > 1
                and aByte == string.byte(b, column - 1)
                and string.byte(a, row - 1) == string.byte(b, column) then
                value = math.min(value, previousPrevious[column - 2] + 1)
            end
            current[column] = value
            if value < rowMinimum then rowMinimum = value end
        end
        if rowMinimum > limit then return nil end
        previousPrevious, previous = previous, current
    end
    local distance = previous[bLength]
    return distance <= limit and distance or nil
end

local function editLimit(word)
    local length = #word
    if length <= 2 then return 0 end
    if length <= 4 then return 1 end
    if length <= 8 then return 2 end
    return 3
end

local function exactVariantResults(sourceIds, prepared, invalidProducts)
    local allowed = {}
    for index = 1, #sourceIds do
        local id = sourceIds[index]
        if not (invalidProducts and invalidProducts[id]) then allowed[id] = true end
    end
    local combinedScores = nil
    for conceptIndex = 1, #prepared.concepts do
        local conceptScores = {}
        local conceptHasResults = false
        local variants = prepared.concepts[conceptIndex]
        for variantIndex = 1, #variants do
            local ids = Search.wordIds[variants[variantIndex]] or {}
            for idIndex = 1, #ids do
                local id = ids[idIndex]
                if allowed[id] then
                    conceptScores[id] = 260
                    conceptHasResults = true
                end
            end
        end
        if not conceptHasResults then return {}, {} end
        if not combinedScores then
            combinedScores = conceptScores
        else
            local combinedHasResults = false
            for id, score in pairs(combinedScores) do
                if conceptScores[id] then
                    combinedScores[id] = score + conceptScores[id]
                    combinedHasResults = true
                else
                    combinedScores[id] = nil
                end
            end
            if not combinedHasResults then return {}, {} end
        end
    end
    local output, relevance = {}, combinedScores or {}
    for index = 1, #sourceIds do
        local id = sourceIds[index]
        if relevance[id] then output[#output + 1] = id end
    end
    return output, relevance
end

local function fuzzyResults(sourceIds, prepared, invalidProducts)
    local allowed = {}
    for index = 1, #sourceIds do
        local id = sourceIds[index]
        if not (invalidProducts and invalidProducts[id]) then allowed[id] = true end
    end

    local combinedScores = nil
    for conceptIndex = 1, #prepared.concepts do
        local conceptScores = {}
        local conceptHasResults = false
        local variants = prepared.concepts[conceptIndex]
        for variantIndex = 1, #variants do
            local variant = variants[variantIndex]
            local limit = editLimit(variant)
            if limit > 0 then
                local minLength = math.max(1, #variant - limit)
                local maxLength = #variant + limit
                for length = minLength, maxLength do
                    local words = Search.wordsByLength[length] or {}
                    for wordIndex = 1, #words do
                        local candidate = words[wordIndex]
                        local distance = boundedEditDistance(variant, candidate, limit)
                        if distance then
                            local score = 155 - distance * 24
                            local ids = Search.wordIds[candidate] or {}
                            for idIndex = 1, #ids do
                                local id = ids[idIndex]
                                if allowed[id] and score > (conceptScores[id] or 0) then
                                    conceptScores[id] = score
                                    conceptHasResults = true
                                end
                            end
                        end
                    end
                end
            end
        end
        if not conceptHasResults then return {}, {} end
        if not combinedScores then
            combinedScores = conceptScores
        else
            local combinedHasResults = false
            for id, score in pairs(combinedScores) do
                local nextScore = conceptScores[id]
                if nextScore then
                    combinedScores[id] = score + nextScore
                    combinedHasResults = true
                else
                    combinedScores[id] = nil
                end
            end
            if not combinedHasResults then return {}, {} end
        end
    end

    local output, relevance = {}, combinedScores or {}
    for index = 1, #sourceIds do
        local id = sourceIds[index]
        if relevance[id] then output[#output + 1] = id end
    end
    return output, relevance
end

function Search.filter(categoryId, rawQuery, currentState)
    currentState = currentState or {}
    local sourceIds = Search.idsForCategory(categoryId, currentState)
    local prepared, normalizedQuery = prepareQuery(rawQuery)
    local invalidProducts = currentState.invalidProducts
    local output, relevance = {}, {}

    if not prepared then
        for index = 1, #sourceIds do
            local id = sourceIds[index]
            if not (invalidProducts and invalidProducts[id]) then output[#output + 1] = id end
        end
        return output, relevance, normalizedQuery, false
    end

    -- Fast path: the overwhelming majority of searches are a literal name,
    -- identifier or alias substring. Avoid all token/fuzzy work when it hits.
    for index = 1, #sourceIds do
        local id = sourceIds[index]
        if not (invalidProducts and invalidProducts[id]) then
            local product = LS.PRODUCT_BY_ID[id]
            local record = Search.record(product)
            local score = record and string.find(record.name, prepared.text, 1, true) and 1500
                or (record and string.find(record.text, prepared.text, 1, true) and 1000 or 0)
            if score > 0 then
                output[#output + 1] = id
                relevance[id] = score
            end
        end
    end
    local exactIds, exactRelevance = exactVariantResults(sourceIds, prepared, invalidProducts)
    if #exactIds > 0 then
        local included = {}
        for index = 1, #output do included[output[index]] = true end
        for index = 1, #exactIds do
            local id = exactIds[index]
            if not included[id] then
                output[#output + 1] = id
                included[id] = true
            end
            relevance[id] = math.max(relevance[id] or 0, exactRelevance[id] or 0)
        end
    end
    if #output > 0 then return output, relevance, normalizedQuery, false end

    -- Token path handles stop words, singular/plural forms and PT/EN synonyms.
    for index = 1, #sourceIds do
        local id = sourceIds[index]
        if not (invalidProducts and invalidProducts[id]) then
            local record = Search.record(LS.PRODUCT_BY_ID[id])
            local score = record and directMatch(record, prepared) or 0
            if score > 0 then
                output[#output + 1] = id
                relevance[id] = score
            end
        end
    end
    if #output > 0 then return output, relevance, normalizedQuery, false end

    output, relevance = fuzzyResults(sourceIds, prepared, invalidProducts)
    return output, relevance, normalizedQuery, true
end

-- Warm a time-bounded batch before the player normally opens the shop. This
-- removes the old indexing work from the panel's per-frame prerender. The
-- 1ms wall-clock cap is the real safety valve (never spikes a frame even on
-- a loaded client); the 64 item ceiling just lets fast ticks (the common
-- case -- each record is a handful of string ops) do more per tick so the
-- whole catalog reaches "fully warm" sooner, shrinking the tiny window where
-- a very early search could still fall back to building records on demand.
local function onWarmupTick()
    if Search.warmBatch(64, 1) and Events and Events.OnTick and Events.OnTick.Remove then
        Events.OnTick.Remove(onWarmupTick)
        Search.warmupInstalled = false
    end
end

if not Search.warmupInstalled and Events and Events.OnTick then
    Search.warmupInstalled = true
    Events.OnTick.Add(onWarmupTick)
end
