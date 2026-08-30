-- Escaneia os itens de OUTROS mods instalados (NUNCA Base., que os pools
-- curados em HardcoreKits_Pools.lua ja cobrem por completo) e complementa os
-- pools validados automaticamente com COMIDA e ARMA CORPO A CORPO -- as duas
-- unicas categorias com um sinal de script confiavel o bastante pra detectar
-- sem arriscar incluir algo errado (ver comentario longo em
-- HardcoreKits_Config.lua sobre por que BEBIDA e RECURSO ficam de fora
-- deste scan: o jogo nao tem como diferenciar com seguranca uma bebida
-- moddada de um combustivel/produto quimico moddado, e "recurso" nem e uma
-- categoria nativa do jogo).
--
-- So roda quando HardcoreKitsConfig.ModdedContentEnabled == true, chamado a
-- partir do FINAL de HardcoreKitsValidation.validateAll() (nunca antes --
-- precisa que os pools estaticos ja tenham sido reconstruidos nesta mesma
-- passada) -- assim herda de graca o mesmo ciclo de boot + revalidacao
-- periodica (RevalidatePoolsEveryRealHours), sem precisar de um timer proprio.
--
-- So mexe em HardcoreKitsValidatedPools (o resultado JA validado), nunca em
-- HardcoreKitsPools (a fonte estatica) -- assim cada chamada pode reconstruir
-- sua propria contribuicao do zero sem acumular duplicata a cada ciclo.
if isClient() then return end

require "HardcoreKits_Config"
require "HardcoreKits_AdminOverrides"

HardcoreKitsModdedContent = HardcoreKitsModdedContent or {}

local function buildExcludeSet()
    local set = {}
    for _, fullType in ipairs(HardcoreKitsConfig.ModdedContentExcludeList or {}) do
        set[fullType] = true
    end
    for _, fullType in ipairs((HardcoreKitsAdminOverrides and HardcoreKitsAdminOverrides.Exclude) or {}) do
        set[fullType] = true
    end
    return set
end

-- B42 expoe AmmoBox/MagazineType na instancia HandWeapon como strings de
-- fullType. getAmmoType() devolve AmmoType (municao solta, sem getFullName) e
-- nao serve para cumprir a promessa de entregar uma CAIXA compativel.
local function resolveFullType(value, fallbackModule)
    if value == nil then return nil end
    local name = tostring(value)
    if name == "" or name == "nil" then return nil end
    if not name:find(".", 1, true) and type(fallbackModule) == "string" and fallbackModule ~= "" then
        name = fallbackModule .. "." .. name
    end
    if name:find(".", 1, true) then return name end
    return nil
end

function HardcoreKitsModdedContent.scan()
    if HardcoreKitsConfig.ModdedContentEnabled ~= true then return end
    if not HardcoreKitsValidatedPools then return end -- validateAll() precisa ter rodado primeiro nesta passada

    local excludeSet = buildExcludeSet()
    local includeFirearms = HardcoreKitsConfig.ModdedContentIncludeFirearms == true
    local itemExists = HardcoreKitsValidation and HardcoreKitsValidation.itemExists

    local okAll, allItems = pcall(function() return getScriptManager():getAllItems() end)
    if not okAll or not allItems then
        print("[HardcoreKits] Conteudo moddado: getAllItems() indisponivel, scan pulado.")
        return
    end
    local okSize, count = pcall(function() return allItems:size() end)
    if not okSize or type(count) ~= "number" or count ~= count or count < 0
        or count == math.huge or count == -math.huge then return end
    count = math.floor(count)

    local moddedMelee, moddedFirearms = {}, {}
    local foodSeen, meleeSeen, firearmSeen = {}, {}, {}
    for _, poolName in ipairs({ "FoodCanned", "FoodPickled", "FoodSecondary" }) do
        for _, fullType in ipairs(HardcoreKitsValidatedPools[poolName] or {}) do foodSeen[fullType] = true end
    end
    for _, list in pairs(HardcoreKitsValidatedPools.MeleeByCategory or {}) do
        for _, fullType in ipairs(list) do meleeSeen[fullType] = true end
    end
    for _, def in ipairs(HardcoreKitsValidatedPools.Firearms or {}) do
        if type(def) == "table" then firearmSeen[def.fullType] = true end
    end
    local foodFound, meleeFound, firearmCandidates, firearmValid = 0, 0, 0, 0

    for i = 0, count - 1 do
        local okItem, item = pcall(function() return allItems:get(i) end)
        if okItem and item then
            local okBasics, fullType, moduleName, obsolete, hidden = pcall(function()
                return item:getFullType(), item:getModuleName(), item:getObsolete(), item:isHidden()
            end)
            if okBasics and type(fullType) == "string" and fullType ~= "" and moduleName ~= "Base"
                and not obsolete and not hidden and not excludeSet[fullType] then
                local okType, itemType = pcall(function() return item:getItemType():toString() end)
                if okType and itemType == "Food" then
                    if not foodSeen[fullType] then
                        table.insert(HardcoreKitsValidatedPools.FoodSecondary, fullType)
                        foodSeen[fullType] = true
                        foodFound = foodFound + 1
                    end
                elseif okType and itemType == "Weapon" then
                    -- precisa de uma instancia pra checar municao (o script
                    -- sozinho nao expoe isso) -- instanceItem cria um item
                    -- solto, nunca adicionado a nenhum container/jogador, so
                    -- pra inspecao, e vira lixo assim que a funcao termina.
                    local okInst, weapon = pcall(function() return instanceItem(fullType) end)
                    if okInst and weapon then
                        local okAmmo, ammoBox = pcall(function() return weapon:getAmmoBox() end)
                        local ammoFullType = okAmmo and resolveFullType(ammoBox, moduleName) or nil
                        if ammoFullType and includeFirearms then
                            if not firearmSeen[fullType] then firearmCandidates = firearmCandidates + 1 end
                            local okMag, magType = pcall(function() return weapon:getMagazineType() end)
                            local magazineFullType = okMag and resolveFullType(magType, moduleName) or nil
                            local okMax, maxAmmo = pcall(function() return weapon:getMaxAmmo() end)
                            -- mesma exigencia de HardcoreKits_Validation.lua pras
                            -- armas vanilla: municao valida e obrigatoria, ou a
                            -- arma fica de fora (nunca entrega arma sem municao
                            -- compativel de verdade)
                            local ammoOk = (not itemExists) or itemExists(ammoFullType)
                            local magOk = (not magazineFullType) or (not itemExists) or itemExists(magazineFullType)
                            if not firearmSeen[fullType] and ammoOk and magOk then
                                if not okMax or type(maxAmmo) ~= "number" or maxAmmo ~= maxAmmo
                                    or maxAmmo <= 0 or maxAmmo == math.huge then maxAmmo = 1 end
                                table.insert(moddedFirearms, {
                                    fullType = fullType, ammoBox = ammoFullType,
                                    magazine = magazineFullType,
                                    maxAmmo = (okMax and type(maxAmmo) == "number" and maxAmmo) or 1,
                                    tier = "uncommon", -- raridade real desconhecida pra um mod de terceiros
                                })
                                firearmSeen[fullType] = true
                                firearmValid = firearmValid + 1
                            end
                        elseif not ammoFullType and not meleeSeen[fullType] then
                            table.insert(moddedMelee, fullType)
                            meleeSeen[fullType] = true
                            meleeFound = meleeFound + 1
                        end
                    end
                end
            end
        end
    end

    HardcoreKitsValidatedPools.MeleeByCategory.modded = moddedMelee
    for _, def in ipairs(moddedFirearms) do
        table.insert(HardcoreKitsValidatedPools.Firearms, def)
    end

    print(string.format(
        "[HardcoreKits] Conteudo moddado: %d comida(s), %d arma(s) corpo a corpo, %d/%d arma(s) de fogo (validas/candidatas).",
        foodFound, meleeFound, firearmValid, firearmCandidates))
end
