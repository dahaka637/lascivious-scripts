-- Overrides do dono do servidor por cima dos pools padrao do mod (secao 23
-- da especificacao -- os pools ja sao listas brancas, isso aqui e a camada
-- de customizacao em cima delas). Edite este arquivo a mao: nao da pra
-- expor "lista de itens" como opcao de sandbox (o sistema de sandbox do
-- jogo so tem boolean/integer/double/enum, sem tipo de texto/lista -- ver
-- HardcoreKits_SandboxBridge.lua).
--
-- ForceInclude: fullTypes SEMPRE adicionados aquele pool, alem do que o mod
-- ja traz -- principal uso: incluir itens de OUTROS mods instalados no
-- servidor que voce queira que apareçam no sorteio. E o unico jeito de
-- incluir BEBIDA ou RECURSO de outro mod -- essas duas categorias nunca
-- entram sozinhas pelo scan automatico de HardcoreKitsConfig.ModdedContentEnabled
-- (ver o comentario longo em HardcoreKits_Config.lua sobre por que).
-- Exclude: fullTypes banidos do sorteio mesmo que estejam num pool padrao
-- do mod -- vale pra QUALQUER pool, nao precisa repetir por categoria, e
-- TAMBEM e respeitado pelo scan automatico de conteudo moddado (ModdedContentEnabled).
--
-- Aplicado automaticamente em HardcoreKits_Pools.lua logo apos os pools
-- padrao serem definidos, ANTES da validacao contra o ScriptManager
-- (HardcoreKits_Validation.lua) -- um fullType invalido aqui e ignorado com
-- seguranca exatamente como qualquer outro item do pool, nunca quebra o mod.
HardcoreKitsAdminOverrides = {

    ForceInclude = {
        FoodCanned = {
            -- "Base.SeuItemDeOutroMod",
        },
        FoodPickled = {},
        FoodSecondary = {},
        DrinkWater = {},
        DrinkOther = {},
        MeleeByCategory = {
            smallblunt = {}, blunt = {}, blade = {}, axe = {}, spear = {},
        },
        -- cada entrada de arma de fogo precisa da estrutura completa (nao so
        -- o fullType): ammoBox e obrigatorio, magazine so se a arma tiver
        -- carregador destacavel, tier decide o peso na recompensa semanal.
        -- Exemplo:
        -- { fullType = "Base.MinhaArma", ammoBox = "Base.MinhaMunicaoBox",
        --   magazine = "Base.MeuCarregador", maxAmmo = 10, tier = "rare" },
        Firearms = {},
        BackpackByTier = {
            escolar = {}, comum = {}, grande = {}, militar = {},
        },
        Resources = {},
        -- caixas de municao avulsa da recompensa semanal (secao 18.1) -- pool
        -- independente do Firearms, precisa ser listado a parte aqui tambem
        AmmoBoxes = {},
    },

    -- lista simples de fullTypes -- removidos de QUALQUER pool onde aparecerem
    Exclude = {
        -- "Base.Dogfood",
    },
}

-- aplica ForceInclude/Exclude numa lista simples de fullTypes (in-place).
-- Sempre refaz a lista via filtro (mesmo com excludeSet vazio, o que so
-- copia a lista pra ela mesma sem custo real) -- Kahlua (a VM Lua do jogo)
-- NAO tem a funcao global next() usada antes aqui pra pular esse passo
-- quando vazio (confirmado decompilando BaseLib.class/TableLib.class do
-- projectzomboid.jar: so pairs/ipairs sao registrados, next nao existe),
-- entao chama-la travava o boot inteiro do cliente com "tried to call nil".
local function applyToList(list, forceIncludeList, excludeSet)
    if forceIncludeList then
        for _, fullType in ipairs(forceIncludeList) do
            table.insert(list, fullType)
        end
    end
    local filtered = {}
    for _, fullType in ipairs(list) do
        if not excludeSet[fullType] then table.insert(filtered, fullType) end
    end
    for i = #list, 1, -1 do list[i] = nil end
    for _, fullType in ipairs(filtered) do table.insert(list, fullType) end
end

-- exclui pelo fullType de dentro de uma lista de definicoes de arma
-- (Firearms guarda tabelas, nao strings -- precisa olhar def.fullType).
-- Mesmo motivo do applyToList acima: sem next(), sempre refaz via filtro.
local function applyExcludeToFirearms(list, excludeSet)
    local filtered = {}
    for _, def in ipairs(list) do
        if not excludeSet[def.fullType] then table.insert(filtered, def) end
    end
    for i = #list, 1, -1 do list[i] = nil end
    for _, def in ipairs(filtered) do table.insert(list, def) end
end

-- chamado uma vez por HardcoreKits_Pools.lua, logo apos definir os pools padrao
function HardcoreKitsAdminOverrides.apply(pools)
    local ov = HardcoreKitsAdminOverrides
    local fi = ov.ForceInclude or {}
    local excludeSet = {}
    for _, fullType in ipairs(ov.Exclude or {}) do excludeSet[fullType] = true end

    applyToList(pools.FoodCanned, fi.FoodCanned, excludeSet)
    applyToList(pools.FoodPickled, fi.FoodPickled, excludeSet)
    applyToList(pools.FoodSecondary, fi.FoodSecondary, excludeSet)
    applyToList(pools.DrinkWater, fi.DrinkWater, excludeSet)
    applyToList(pools.DrinkOther, fi.DrinkOther, excludeSet)
    applyToList(pools.Resources, fi.Resources, excludeSet)
    applyToList(pools.AmmoBoxes, fi.AmmoBoxes, excludeSet)

    for category, list in pairs(pools.MeleeByCategory) do
        applyToList(list, fi.MeleeByCategory and fi.MeleeByCategory[category], excludeSet)
    end
    for tier, list in pairs(pools.BackpackByTier) do
        applyToList(list, fi.BackpackByTier and fi.BackpackByTier[tier], excludeSet)
    end

    if fi.Firearms then
        for _, def in ipairs(fi.Firearms) do
            table.insert(pools.Firearms, def)
        end
    end
    applyExcludeToFirearms(pools.Firearms, excludeSet)
end
