-- Resolucao de identidade: quem esta pedindo, e por qual "conta" ele deve
-- ser controlado para fins de antiabuso. NUNCA confie em nada vindo do
-- payload do cliente aqui -- tudo neste arquivo le do objeto `player` que o
-- proprio engine entrega ao handler de Events.OnClientCommand.
if isClient() then return end

require "HardcoreKits_Config"
require "HardcoreKits_Persistence"
require "LasciviousSystems_SteamId"
require "LasciviousSystems_Identity"

HardcoreKitsIdentity = HardcoreKitsIdentity or {}

-- true em singleplayer/save local (nem cliente nem servidor dedicado).
-- Nesse modo nao existe risco real de abuso multi-conta, entao o antiabuso
-- de 72h pode cair para uma chave por username sem problema.
function HardcoreKitsIdentity.isSoloSP()
    return not isClient() and not isServer()
end

-- identificador de conta estavel entre personagens/mortes. Preferencialmente
-- o SteamID (persiste mesmo se o personagem morrer e o username mudar);
-- cai para o username apenas quando SteamID nao esta disponivel (solo, ou
-- Steam fora do ar) -- ver secao 6.1 da especificacao.
--
-- IMPORTANTE: NUNCA usar tostring(player:getSteamID()) aqui -- e um `long`
-- Java virando double Lua, perde precisao (ver CLAUDE_SHOP_STEAMID_PRECISION_BUG.md
-- e LasciviousSystems_SteamId.lua). LasciviousSystemsSteamId.accountKey() usa
-- o global getSteamIDFromUsername() da engine, que devolve a String exata sem
-- passar por double nenhum.
--
-- Efeito colateral proposital: na primeira vez que a chave certa aparece pra
-- um jogador, migra qualquer conta que a versao antiga (com bug) tenha
-- criado com a chave arredondada -- senao o saldo/cooldown/kit-ja-resgatado
-- daquele jogador ficaria orfao pra sempre debaixo da chave errada.
function HardcoreKitsIdentity.accountId(player)
    if not player then return nil end
    local key = nil
    if LasciviousSystemsIdentity and LasciviousSystemsIdentity.resolvePlayer then
        key = LasciviousSystemsIdentity.resolvePlayer(player)
    end
    if not key then key = LasciviousSystemsSteamId.accountKey(player) end
    if key then
        local legacyKey = (type(key) == "string" and string.match(key, "^steam:%d+$"))
            and LasciviousSystemsSteamId.legacyAccountKey(player, key) or nil
        if legacyKey then
            HardcoreKitsPersistence.migrateAccount(legacyKey, key)
            print("[HardcoreKits] Conta migrada (bug de precisao do SteamID): '" .. tostring(legacyKey) .. "' -> '" .. tostring(key) .. "'")
        end
        return key
    end
    local ok2, name = pcall(function() return player:getUsername() end)
    if ok2 and type(name) == "string" and name ~= "" then
        return "name:" .. name
    end
    return nil
end

function HardcoreKitsIdentity.username(player)
    local ok, name = pcall(function() return player:getUsername() end)
    if ok and type(name) == "string" and name ~= "" then return name end
    return "?"
end

function HardcoreKitsIdentity.characterName(player)
    local ok, name = pcall(function() return player:getFullName() end)
    if ok and type(name) == "string" and name ~= "" then return name end
    return HardcoreKitsIdentity.username(player)
end

-- horas sobrevividas do PERSONAGEM atual (reseta sozinho ao morrer/recriar,
-- pois e um novo IsoPlayer com seu proprio estado) -- secao 12.2.
function HardcoreKitsIdentity.hoursSurvived(player)
    local ok, hours = pcall(function() return player:getHoursSurvived() end)
    if ok and type(hours) == "number" and hours == hours
        and hours ~= math.huge and hours ~= -math.huge then -- descarta NaN/infinito
        return math.max(0, hours)
    end
    return 0
end

function HardcoreKitsIdentity.isDead(player)
    local ok, dead = pcall(function() return player:isDead() end)
    return ok and dead == true
end

-- inventario da mochila (ou equivalente) JA equipada no slot das costas, se
-- houver -- usado pelo Kit Inicial pra nao dar uma mochila nova quando o
-- personagem ja tem uma vestida, e entregar o resto do kit dentro dela
-- (pedido explicito do usuario). getClothingItem_Back() e o mesmo acessor
-- que o jogo usa pra saber o que esta no slot "Back" (confirmado via
-- decompilacao de zombie/characters/IsoGameCharacter.class). Devolve nil se
-- nao houver nada equipado ali, ou se o item nao for um container de
-- verdade (ex: uma capa sem espaco de guardar coisas).
function HardcoreKitsIdentity.equippedBackpackInventory(player)
    if not player then return nil end
    local ok, item = pcall(function() return player:getClothingItem_Back() end)
    if not ok or not item then return nil end
    local ok2, inv = pcall(function() return item:getInventory() end)
    if ok2 and inv then return inv end
    return nil
end

-- mesma tecnica que o vanilla ISRolesList/ISUsersList usa: o veredito vem do
-- REGISTRO de roles (getRoles()/hasAdminTool), nao de comparar a string de
-- getAccessLevel() contra uma lista fixa -- B42 permite niveis de acesso
-- customizados, e uma blacklist ingenua classifica qualquer role custom
-- desconhecida como staff. So usado pelas ferramentas de diagnostico.
function HardcoreKitsIdentity.isAdmin(player)
    if not player then return false end
    if HardcoreKitsIdentity.isSoloSP() then return true end
    -- isCoopHost() descreve o processo. A excecao sem accessLevel pertence
    -- somente ao jogador local que hospeda, nunca aos convidados remotos.
    local okCoop, coop = pcall(function() return isCoopHost() end)
    if okCoop and coop == true then
        local okLocal, localFlag = pcall(function()
            return player.isLocalPlayer and player:isLocalPlayer()
        end)
        if okLocal and localFlag == true then return true end
        local okPlayer, localPlayer = pcall(function() return getPlayer and getPlayer() end)
        if okPlayer and localPlayer and localPlayer == player then return true end
    end
    local ok, level = pcall(function() return player:getAccessLevel() end)
    if not ok then return false end
    level = tostring(level or ""):lower()
    if level == "" or level == "none" or level == "user"
        or level == "banned" or level == "priorityuser" then
        return false
    end
    local ok2, role = pcall(function()
        local list = getRoles()
        if not list then return nil end
        for i = 0, list:size() - 1 do
            local r = list:get(i)
            if r and tostring(r:getName()):lower() == level then return r end
        end
        return nil
    end)
    if not ok2 or not role then return false end
    local ok3, res = pcall(function() return role:hasAdminTool() == true end)
    return ok3 and res == true
end
