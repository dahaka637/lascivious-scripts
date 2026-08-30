-- Camada de persistencia.
--
-- Kit Inicial ("ja resgatou neste personagem?") -> LISTA GLOBAL por CONTA
-- (accountId, steamID normalmente), em ModData.getOrCreate(...) do servidor.
-- Design original pedido explicitamente pelo usuario:
--   PEGOU O KIT    -> cadastra o accountId na lista (markInitialKitClaimed)
--   JOGADOR MORREU -> apaga o accountId da lista
-- O modo opcional InitialKitSingleUseEnabled adiciona uma segunda marca dentro
-- de HardcoreKits_Accounts: claims feitos enquanto esse modo esta ativo ficam
-- permanentes por conta e nao sao apagados em morte/personagem novo.
-- Deteccao de morte NAO usa Events.OnPlayerDeath (nao disparou no servidor
-- em teste ao vivo) -- usa Events.OnCharacterDeath, confirmado via
-- decompilacao do jar que dispara no servidor de verdade. Ver
-- onCharacterDeath em HardcoreKits_Server.lua.
--
-- Resto do estado (transacao pendente, contagem de recompensa de
-- sobrevivencia) continua POR PERSONAGEM -> player:getModData(), porque
-- pertence mesmo aquela vida especifica, nao a conta.
if isClient() then return end

require "HardcoreKits_Config"
require "HardcoreKits_Utils"

HardcoreKitsPersistence = HardcoreKitsPersistence or {}

local ACCOUNTS_KEY = "HardcoreKits_Accounts"
local CLAIMED_ACCOUNTS_KEY = "HardcoreKits_ClaimedInitialKitAccounts"
local CHAR_KEY = "HardcoreKits"

local function freshCharacterData()
    return {
        survivalRewardsClaimed = 0,
        lastCompletedClaimId = nil,
        pendingTx = nil,
    }
end

-- ---------- Kit Inicial: lista global por conta ----------

local function claimedAccountsTable()
    local data = ModData.getOrCreate(CLAIMED_ACCOUNTS_KEY)
    if type(data) ~= "table" then
        data = {}
        ModData.add(CLAIMED_ACCOUNTS_KEY, data)
    end
    return data
end

function HardcoreKitsPersistence.isInitialKitClaimed(accountId)
    if not accountId then return false end
    return claimedAccountsTable()[accountId] == true
end

function HardcoreKitsPersistence.markInitialKitClaimed(accountId)
    if not accountId then return false end
    claimedAccountsTable()[accountId] = true
    return claimedAccountsTable()[accountId] == true
end

function HardcoreKitsPersistence.clearInitialKitClaimed(accountId)
    if not accountId then return end
    claimedAccountsTable()[accountId] = nil
end

-- ---------- por personagem (transacao pendente, recompensa de sobrevivencia) ----------

function HardcoreKitsPersistence.characterData(player)
    if not player then return freshCharacterData() end
    local ok, md = pcall(function() return player:getModData() end)
    if not ok or type(md) ~= "table" then return freshCharacterData() end
    local data = md[CHAR_KEY]
    if type(data) ~= "table" then
        data = freshCharacterData()
        md[CHAR_KEY] = data
    end
    if data.pendingTx ~= nil and type(data.pendingTx) ~= "table" then
        data.pendingTx = nil
    end
    return data
end

function HardcoreKitsPersistence.survivalRewardsClaimed(player)
    local value = tonumber(HardcoreKitsPersistence.characterData(player).survivalRewardsClaimed) or 0
    if value ~= value or value == math.huge or value == -math.huge then return 0 end
    return math.max(0, math.floor(value))
end

function HardcoreKitsPersistence.incrementSurvivalRewardsClaimed(player, byHowMany)
    local data = HardcoreKitsPersistence.characterData(player)
    local delta = tonumber(byHowMany) or 1
    if delta ~= delta or delta == math.huge or delta == -math.huge then delta = 1 end
    data.survivalRewardsClaimed = math.max(0,
        math.floor(HardcoreKitsPersistence.survivalRewardsClaimed(player) + delta))
end

function HardcoreKitsPersistence.getPendingTx(player)
    return HardcoreKitsPersistence.characterData(player).pendingTx
end

function HardcoreKitsPersistence.setPendingTx(player, tx)
    HardcoreKitsPersistence.characterData(player).pendingTx = tx
end

function HardcoreKitsPersistence.clearPendingTx(player)
    local data = HardcoreKitsPersistence.characterData(player)
    if data.pendingTx then
        data.lastCompletedClaimId = data.pendingTx.claimId
    end
    data.pendingTx = nil
end

-- ---------- cooldown / historico de conta ----------

local function accounts()
    local data = ModData.getOrCreate(ACCOUNTS_KEY)
    if type(data) ~= "table" then
        data = {}
        ModData.add(ACCOUNTS_KEY, data)
    end
    return data
end

function HardcoreKitsPersistence.accountData(accountId)
    if not accountId then return nil end
    local all = accounts()
    local data = all[accountId]
    if type(data) ~= "table" then
        data = { lastInitialKitClaimTimestamp = 0, initialKitClaimCount = 0 }
        all[accountId] = data
    end
    return data
end

function HardcoreKitsPersistence.isInitialKitSingleUseClaimed(accountId)
    local data = HardcoreKitsPersistence.accountData(accountId)
    return data ~= nil and data.initialKitSingleUseClaimed == true
end

function HardcoreKitsPersistence.markInitialKitSingleUseClaimed(accountId, claimId)
    local data = HardcoreKitsPersistence.accountData(accountId)
    if not data then return false end
    if type(claimId) == "string" and claimId ~= "" and data.initialKitSingleUseClaimId == claimId then
        data.initialKitSingleUseClaimed = true
        return true
    end
    local now = HardcoreKitsUtils.realTime()
    if now <= 0 then return false end
    data.initialKitSingleUseClaimed = true
    data.initialKitSingleUseClaimTimestamp = now
    if type(claimId) == "string" and claimId ~= "" then
        data.initialKitSingleUseClaimId = claimId
    end
    return data.initialKitSingleUseClaimed == true
end

function HardcoreKitsPersistence.clearInitialKitSingleUseClaimed(accountId, claimId)
    local data = HardcoreKitsPersistence.accountData(accountId)
    if not data then return end
    if type(claimId) == "string" and claimId ~= ""
        and type(data.initialKitSingleUseClaimId) == "string"
        and data.initialKitSingleUseClaimId ~= claimId then
        return
    end
    data.initialKitSingleUseClaimed = nil
    data.initialKitSingleUseClaimTimestamp = nil
    data.initialKitSingleUseClaimId = nil
end

-- segundos restantes de cooldown de conta para o Kit Inicial (0 = liberado)
function HardcoreKitsPersistence.initialKitCooldownRemaining(accountId)
    local data = HardcoreKitsPersistence.accountData(accountId)
    if not data then return 0 end
    local cooldownHours = tonumber(HardcoreKitsConfig.InitialKitCooldownRealHours) or 0
    if cooldownHours ~= cooldownHours or cooldownHours == math.huge
        or cooldownHours == -math.huge or cooldownHours < 0 then cooldownHours = 0 end
    local cooldownSeconds = cooldownHours * 3600
    if cooldownSeconds ~= cooldownSeconds or cooldownSeconds == math.huge
        or cooldownSeconds == -math.huge then return 0 end
    if cooldownSeconds <= 0 then return 0 end
    local last = tonumber(data.lastInitialKitClaimTimestamp)
    -- Um timestamp persistido corrompido nao pode liberar um novo kit. Trate
    -- NaN/infinito/texto como cooldown completo ate reparo administrativo.
    if not last or last ~= last or last == math.huge or last == -math.huge then
        return cooldownSeconds
    end
    if last <= 0 then return 0 end
    local now = HardcoreKitsUtils.realTime()
    -- Falha da API/ajuste regressivo do relogio nunca libera o cooldown por acidente.
    if now <= 0 or now < last then return cooldownSeconds end
    return math.max(0, math.min(cooldownSeconds, cooldownSeconds - (now - last)))
end

function HardcoreKitsPersistence.markAccountInitialKitClaimed(accountId, claimId)
    local data = HardcoreKitsPersistence.accountData(accountId)
    if not data then return false end
    -- O claimId torna a atualizacao idempotente ate se o servidor cair depois
    -- de gravar o cooldown, mas antes de a transacao registrar o subpasso.
    if type(claimId) == "string" and claimId ~= "" and data.lastInitialKitClaimId == claimId then
        return true
    end
    local now = HardcoreKitsUtils.realTime()
    if now <= 0 then return false end
    data.lastInitialKitClaimTimestamp = now
    local count = tonumber(data.initialKitClaimCount) or 0
    if count ~= count or count == math.huge or count == -math.huge or count < 0 then count = 0 end
    data.initialKitClaimCount = math.floor(count) + 1
    if type(claimId) == "string" and claimId ~= "" then data.lastInitialKitClaimId = claimId end
    return true
end

-- usado so pelo comando de debug/admin para poder re-testar sem esperar o
-- cooldown de verdade (o comando tambem zera o modData do proprio
-- personagem direto, ver HardcoreKits_Debug.lua)
function HardcoreKitsPersistence.resetAccount(accountId)
    if not accountId then return end
    accounts()[accountId] = nil
    HardcoreKitsPersistence.clearInitialKitClaimed(accountId)
end

-- Move os dados registrados em `oldKey` para `newKey`, quando `newKey` ainda
-- nao tem nada. Usado uma unica vez por jogador afetado pelo bug de precisao
-- do SteamID64 (ver LasciviousSystems_SteamId.lua) -- oldKey e a chave errada
-- exata que o bug antigo calculava para o MESMO jogador, nunca dado de outra
-- conta. Chamado por HardcoreKitsIdentity.accountId().
function HardcoreKitsPersistence.migrateAccount(oldKey, newKey)
    if not oldKey or not newKey or oldKey == newKey then return end

    local claimed = claimedAccountsTable()
    if claimed[oldKey] == true and claimed[newKey] == nil then
        claimed[newKey] = true
    end
    claimed[oldKey] = nil

    local all = accounts()
    local oldData = all[oldKey]
    if type(oldData) == "table" then
        if type(all[newKey]) ~= "table" then
            all[newKey] = oldData
        end
        all[oldKey] = nil
    end
end
