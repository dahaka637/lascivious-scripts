-- Ponto de entrada do servidor: um unico Events.OnClientCommand, uma tabela
-- de comandos, e o fluxo completo de resgate (secoes 19.2, 28 e 29 da
-- especificacao). Toda decisao fica aqui; Rolls/Delivery/Persistence/Audit
-- so executam o que este arquivo manda.
if isClient() then return end

require "HardcoreKits_Protocol"
require "HardcoreKits_Config"
require "HardcoreKits_Utils"
require "HardcoreKits_Identity"
require "HardcoreKits_Persistence"
require "HardcoreKits_Validation"
require "HardcoreKits_Rolls"
require "HardcoreKits_Transactions"
require "HardcoreKits_Delivery"
require "HardcoreKits_State"
require "HardcoreKits_Audit"

local Commands = {}

local function finiteNumber(value)
    local number = tonumber(value)
    if not number or number ~= number or number == math.huge or number == -math.huge then return nil end
    return number
end

local function toClient(player, command, args)
    if isServer() then
        sendServerCommand(player, HardcoreKits.MODULE, command, args)
    else
        -- singleplayer: nao ha rede de verdade, o mesmo processo escuta os
        -- dois lados (mesmo padrao do Aegis Panel)
        triggerEvent("OnServerCommand", HardcoreKits.MODULE, command, args)
    end
end

-- protege contra spam de clique/comando repetido (secao 21). Janela curta
-- de proposito -- a protecao de verdade contra resgate duplicado e o flag
-- initialKitClaimed (travado no instante do sorteio) + a checagem redundante
-- em resumeInitialDelivery/resumeSurvivalDelivery, nao esse throttle. Uma
-- janela maior aqui so faz o servidor IGNORAR EM SILENCIO (sem erro, sem
-- resposta nenhuma) um segundo clique de um jogador impaciente, deixando o
-- botao parecendo travado sem explicacao -- ja foi testado e confirmado
-- pior, revertido de volta pra 1s pros dois lados.
local THROTTLE_SECONDS = 1
local lastCall = {}
local throttleWrites = 0
local lastThrottlePruneAtMs = 0

local function monotonicMs()
    local ok, now = pcall(getTimestampMs)
    now = ok and finiteNumber(now) or nil
    if now and now > 0 then return now end
    local fallback = HardcoreKitsUtils.realTime()
    return fallback > 0 and fallback * 1000 or 0
end

local function throttled(username, command)
    local now = monotonicMs()
    if now <= 0 then return false end -- protecoes autoritativas continuam valendo
    local key = username .. "|" .. command
    local previous = finiteNumber(lastCall[key])
    if previous and now >= previous and now - previous < THROTTLE_SECONDS * 1000 then return true end
    lastCall[key] = now
    throttleWrites = throttleWrites + 1
    if throttleWrites >= 256 or now - lastThrottlePruneAtMs >= 300000 then
        local cutoff = now - 300000
        for oldKey, calledAt in pairs(lastCall) do
            local validCalledAt = finiteNumber(calledAt)
            if not validCalledAt or validCalledAt < cutoff or validCalledAt > now then lastCall[oldKey] = nil end
        end
        throttleWrites = 0
        lastThrottlePruneAtMs = now
    end
    return false
end

local function hasArrayEntries(value)
    return type(value) == "table" and #value > 0
end

local function hasDeliverableItem(value)
    if type(value) ~= "table" then return false end
    for _, entry in ipairs(value) do
        local qty = type(entry) == "table" and finiteNumber(entry.qty) or nil
        if type(entry) == "table" and type(entry.fullType) == "string" and entry.fullType ~= ""
            and qty and qty >= 1 then return true end
    end
    return false
end

local function validInitialRoll(rolled)
    if type(rolled) ~= "table" then return false end
    return (type(rolled.backpack) == "string" and rolled.backpack ~= "")
        or (type(rolled.melee) == "string" and rolled.melee ~= "")
        or (type(rolled.medicalKitBag) == "string" and rolled.medicalKitBag ~= "")
        or (rolled.hasFirearm == true and type(rolled.firearm) == "table"
            and type(rolled.firearm.fullType) == "string" and rolled.firearm.fullType ~= "")
        or hasDeliverableItem(rolled.food) or hasDeliverableItem(rolled.drink)
        or hasDeliverableItem(rolled.resource) or hasArrayEntries(rolled.skillBoosts)
end

local function validSurvivalRoll(rolled)
    if not hasArrayEntries(rolled) then return false end
    for _, result in ipairs(rolled) do
        if type(result) == "table" then
            if hasDeliverableItem(result.items)
                or (result.subCategory == "firearm" and type(result.firearm) == "table"
                    and type(result.firearm.fullType) == "string" and result.firearm.fullType ~= "")
                or (result.subCategory == "medicalkit" and type(result.medicalKitBag) == "string"
                    and result.medicalKitBag ~= "")
                or (result.category == "skill" and ((result.kind == "group" and hasArrayEntries(result.perks))
                    or (type(result.perkName) == "string" and (finiteNumber(result.xp) or 0) > 0))) then
                return true
            end
        end
    end
    return false
end

-- forward declarations: definidas mais abaixo, referenciadas pelos handlers
-- de claim (retomam a entrega de uma transacao ja sorteada -- usado tanto no
-- caminho normal quanto na recuperacao de uma transacao pendente)
local resumeInitialDelivery
local resumeSurvivalDelivery

local function quarantineAmbiguousPending(player, tx)
    if not tx then return nil end
    if tx.status == HardcoreKits.STATUS_CREATED then
        -- Nenhum resultado/entitlement existe ainda; abandonar e seguro.
        HardcoreKitsTransactions.cancel(player, "interrupted_before_roll")
        return nil
    end
    if tx.status == HardcoreKits.STATUS_DELIVERING then
        -- Um save/crash nesse ponto pode ter acontecido depois de AddItem. Nao
        -- repita o lote inteiro: isso e recuperacao manual, sem risco de dupe.
        return HardcoreKitsTransactions.markRecoveryRequired(player, "interrupted_during_delivery", false)
    end
    return tx
end

-- rede de seguranca: se o cliente nunca mandar CMD_REQUEST_REVEAL_COMPLETE
-- (desconectou, fechou o jogo, crashou no meio da animacao), a entrega fica
-- "presa" em persisted/delivering. Chamado no inicio de qualquer pedido de
-- estado -- assim que o jogador voltar a interagir com o painel (ou so
-- reabrir), resolve sozinho quando ainda nao houve mutacao fisica. Um estado
-- delivering e ambiguo (o crash pode ter ocorrido apos AddItem) e fica
-- deliberadamente pendente para recuperacao manual, evitando duplicacao.
local function maybeResolveStaleDelivery(player, accountId)
    local tx = quarantineAmbiguousPending(player, HardcoreKitsTransactions.getPending(player))
    if not tx then return end
    if tx.status ~= HardcoreKits.STATUS_PERSISTED
        and not (tx.status == HardcoreKits.STATUS_RECOVERY_REQUIRED and tx.recoveryRetrySafe == true) then return end
    local timeout = finiteNumber(HardcoreKitsConfig.PendingDeliveryTimeoutRealSeconds) or 30
    timeout = math.max(1, timeout)
    local now = HardcoreKitsUtils.realTime()
    local since = finiteNumber(tx.lastDeliveryAttemptAt) or finiteNumber(tx.createdAt) or now
    if now <= 0 or now - since < timeout then return end
    if tx.claimType == HardcoreKits.CLAIM_TYPE_INITIAL then
        resumeInitialDelivery(player, accountId, tx)
    elseif tx.claimType == HardcoreKits.CLAIM_TYPE_SURVIVAL then
        resumeSurvivalDelivery(player, accountId, tx)
    end
end

local function commitInitialEntitlement(accountId, tx)
    if type(tx) ~= "table" or not accountId then return false end
    if tx.entitlementCommitted == true then return true end

    -- Dois subpassos persistidos separadamente: se um deles falhar/crashar, o
    -- retry completa somente o que falta. O cooldown usa claimId e tambem e
    -- idempotente na propria tabela de conta (nao duplica o contador).
    if tx.initialAccountCooldownCommitted ~= true then
        if HardcoreKitsPersistence.markAccountInitialKitClaimed(accountId, tx.claimId) ~= true then return false end
        tx.initialAccountCooldownCommitted = true
    end
    if HardcoreKitsConfig.InitialKitSingleUseEnabled == true and tx.initialSingleUseCommitted ~= true then
        if HardcoreKitsPersistence.markInitialKitSingleUseClaimed(accountId, tx.claimId) ~= true then return false end
        tx.initialSingleUseCommitted = true
    end
    if tx.initialClaimFlagCommitted ~= true then
        if not HardcoreKitsPersistence.isInitialKitClaimed(accountId)
            and HardcoreKitsPersistence.markInitialKitClaimed(accountId) ~= true then return false end
        if not HardcoreKitsPersistence.isInitialKitClaimed(accountId) then return false end
        tx.initialClaimFlagCommitted = true
    end
    tx.entitlementCommitted = true
    return true
end

local function commitSurvivalEntitlement(player, tx)
    if tx.entitlementCommitted == true then return true end
    local current = HardcoreKitsPersistence.survivalRewardsClaimed(player)
    local ordinal = finiteNumber(tx.survivalClaimOrdinal)
    if not ordinal or ordinal < 1 then
        -- Transacao de save anterior a este campo: preserva o contador atual e
        -- evita um segundo incremento potencialmente duplicado.
        ordinal = current
    end
    ordinal = math.max(0, math.floor(ordinal))
    if current < ordinal then
        HardcoreKitsPersistence.incrementSurvivalRewardsClaimed(player, ordinal - current)
        current = HardcoreKitsPersistence.survivalRewardsClaimed(player)
        if current < ordinal then return false end
    end
    tx.entitlementCommitted = true
    return true
end

local function normalizedDeliveryResult(result)
    if type(result) ~= "table" then result = {} end
    local function nonnegativeInt(value)
        local n = tonumber(value)
        if not n or n ~= n or n == math.huge or n == -math.huge then return 0 end
        return math.max(0, math.floor(n))
    end
    local granted = nonnegativeInt(result.granted)
    local total = nonnegativeInt(result.total)
    local created = nonnegativeInt(result.created)
    result.granted = math.min(granted, total)
    result.total = total
    result.created = created
    if type(result.log) ~= "table" then result.log = {} end
    return result
end

local function deliveryDisposition(okDeliver, result)
    result = normalizedDeliveryResult(result)
    if okDeliver and result.total > 0 and result.granted == result.total then
        return "completed", nil, result
    end
    -- Qualquer mutacao fisica torna um replay integral inseguro. Finaliza como
    -- parcial (at-most-once) e deixa o log dizer exatamente quais slots falharam.
    if result.created > 0 then
        return "completed_partial", "partial_delivery", result
    end
    local reason = okDeliver and (result.total > 0 and "zero_items_delivered" or "empty_delivery") or "exception"
    return "recovery_required", reason, result
end

local function identityAvailable(player, claimType)
    local accountId = HardcoreKitsIdentity.accountId(player)
    if accountId then return accountId end
    HardcoreKitsAudit.logAttemptDenied(player, nil, claimType, "identity_unavailable")
    toClient(player, HardcoreKits.CMD_CLAIM_ERROR, { claimType = claimType, reason = "delivery_failed" })
    return nil
end

-- ================= estado =================

Commands[HardcoreKits.CMD_REQUEST_STATE] = function(player, args)
    local accountId = HardcoreKitsIdentity.accountId(player)
    maybeResolveStaleDelivery(player, accountId)
    toClient(player, HardcoreKits.CMD_STATE, HardcoreKitsState.build(player, accountId))
end

Commands[HardcoreKits.CMD_REQUEST_PENDING] = function(player, args)
    -- o proprio state ja carrega hasPendingClaim/pendingClaimType/Status;
    -- o cliente usa isso pra decidir se reabre a roleta de uma transacao em andamento
    local accountId = HardcoreKitsIdentity.accountId(player)
    maybeResolveStaleDelivery(player, accountId)
    toClient(player, HardcoreKits.CMD_STATE, HardcoreKitsState.build(player, accountId))
end

-- ================= Kit Inicial (secoes 6, 19.3, 28) =================

Commands[HardcoreKits.CMD_REQUEST_INITIAL_CLAIM] = function(player, args)
    local claimType = HardcoreKits.CLAIM_TYPE_INITIAL
    local accountId = identityAvailable(player, claimType)
    if not accountId then return end

    if HardcoreKitsIdentity.isDead(player) then
        HardcoreKitsAudit.logAttemptDenied(player, accountId, claimType, "dead")
        toClient(player, HardcoreKits.CMD_CLAIM_ERROR, { claimType = claimType, reason = "dead" })
        return
    end

    local existingTx = quarantineAmbiguousPending(player, HardcoreKitsTransactions.getPending(player))
    if existingTx then
        if existingTx.claimType == claimType and HardcoreKitsTransactions.needsRecovery(player) then
            resumeInitialDelivery(player, accountId, existingTx)
        else
            toClient(player, HardcoreKits.CMD_CLAIM_ERROR, { claimType = claimType, reason = "pending_exists" })
        end
        return
    end

    if HardcoreKitsConfig.InitialKitEnabled ~= true then
        toClient(player, HardcoreKits.CMD_CLAIM_ERROR, { claimType = claimType, reason = "disabled" })
        return
    end
    local singleUseEnabled = HardcoreKitsConfig.InitialKitSingleUseEnabled == true
    if singleUseEnabled and HardcoreKitsPersistence.isInitialKitSingleUseClaimed(accountId) then
        HardcoreKitsAudit.logAttemptDenied(player, accountId, claimType, "already_claimed_account")
        toClient(player, HardcoreKits.CMD_CLAIM_ERROR, { claimType = claimType, reason = "already_claimed_account" })
        return
    end
    if HardcoreKitsPersistence.isInitialKitClaimed(accountId) then
        HardcoreKitsAudit.logAttemptDenied(player, accountId, claimType, "already_claimed_character")
        toClient(player, HardcoreKits.CMD_CLAIM_ERROR, { claimType = claimType, reason = "already_claimed_character" })
        return
    end
    if not singleUseEnabled and HardcoreKitsConfig.InitialKitCooldownEnabled == true then
        local cooldown = HardcoreKitsPersistence.initialKitCooldownRemaining(accountId)
        if cooldown > 0 then
            HardcoreKitsAudit.logAttemptDenied(player, accountId, claimType, "cooldown")
            toClient(player, HardcoreKits.CMD_CLAIM_ERROR, { claimType = claimType, reason = "cooldown", remainingSeconds = cooldown })
            return
        end
    end

    local tx = HardcoreKitsTransactions.begin(player, claimType, accountId)
    if not tx then
        toClient(player, HardcoreKits.CMD_CLAIM_ERROR, { claimType = claimType, reason = "pending_exists" })
        return
    end

    -- sorteio acontece UMA vez, aqui, e e persistido antes de qualquer
    -- animacao comecar no cliente (secao 19.2 e 19.7). A ENTREGA fisica dos
    -- itens fica pra depois (so quando o cliente avisar que terminou de girar
    -- a roleta, CMD_REQUEST_REVEAL_COMPLETE mais abaixo, ou a rede de
    -- seguranca por timeout resolver -- ver maybeResolveStaleDelivery) --
    -- MAS o "ja resgatado" trava JA, aqui, no instante do sorteio, nao la na
    -- entrega. Bug real corrigido: antes disso, marcar como resgatado so
    -- depois da entrega deixava uma janela (a animacao inteira, poucos
    -- segundos a mais de um minuto) em que o MESMO personagem, ainda vivo,
    -- conseguia fechar e reabrir o painel e resgatar de novo, porque nada
    -- ainda tinha travado o slot -- nada a ver com o cooldown de conta
    -- (esse e outra coisa, entre mortes de personagem, sempre foi). "Uma vez
    -- por personagem" precisa ser atomico com o sorteio, nao com a entrega.
    local okRoll, rolled = pcall(HardcoreKitsRolls.rollInitialKit, player)
    if not okRoll or not validInitialRoll(rolled) then
        print("[HardcoreKits] Falha no sorteio do Kit Inicial: " .. tostring(rolled))
        HardcoreKitsTransactions.cancel(player, okRoll and "empty_roll" or "roll_exception")
        HardcoreKitsAudit.logAttemptDenied(player, accountId, claimType, okRoll and "empty_roll" or "roll_exception")
        toClient(player, HardcoreKits.CMD_CLAIM_ERROR, { claimType = claimType, reason = "delivery_failed" })
        return
    end
    if not HardcoreKitsTransactions.setRolled(player, rolled) then
        HardcoreKitsTransactions.cancel(player, "invalid_transition")
        toClient(player, HardcoreKits.CMD_CLAIM_ERROR, { claimType = claimType, reason = "delivery_failed" })
        return
    end
    local okCommit, commitErr = pcall(commitInitialEntitlement, accountId, tx)
    if not okCommit or commitErr ~= true or not HardcoreKitsTransactions.markPersisted(player) then
        print("[HardcoreKits] Falha persistindo Kit Inicial: " .. tostring(commitErr))
        toClient(player, HardcoreKits.CMD_CLAIM_ERROR, { claimType = claimType, reason = "delivery_failed" })
        return
    end

    toClient(player, HardcoreKits.CMD_CLAIM_STARTED, { claimType = claimType, claimId = tx.claimId, rolled = rolled })
end

resumeInitialDelivery = function(player, accountId, tx)
    -- trava redundante, direto aqui dentro -- nao confia so em quem chama ja
    -- ter checado o status antes. Se por QUALQUER motivo (bug futuro, corrida
    -- entre comandos, retry duplicado) essa funcao for chamada duas vezes pro
    -- MESMO resgate ja concluido, a segunda chamada nao entrega nada de novo.
    if tx.status == HardcoreKits.STATUS_COMPLETED then return end
    if tx.status == HardcoreKits.STATUS_DELIVERING then
        HardcoreKitsTransactions.markRecoveryRequired(player, "interrupted_during_delivery", false)
        toClient(player, HardcoreKits.CMD_CLAIM_ERROR,
            { claimType = HardcoreKits.CLAIM_TYPE_INITIAL, reason = "delivery_failed" })
        return
    end

    -- Checagem pedida explicitamente pelo usuario: o personagem pode ter
    -- morrido depois do sorteio (que ja trava "resgatado" pra CONTA, la em
    -- CMD_REQUEST_INITIAL_CLAIM) mas ANTES deste instante exato de entrega --
    -- a animacao da roleta no cliente leva de 40 a 90s, tempo de sobra pra
    -- levar uma mordida. Sem isto, os itens iriam parar dentro de um cadaver
    -- que ninguem vai looter -- desperdicados, e o cliente (que pode nem
    -- estar mais olhando pra tela de resultado a essa altura) ainda receberia
    -- um CMD_CLAIM_RESULT de sucesso. onCharacterDeath (mais abaixo neste
    -- arquivo) ja limpa o "ja resgatado" comum da CONTA no instante da morte;
    -- no modo de Kit unico, tambem desfaz a marca permanente quando a morte
    -- aconteceu antes da entrega real. Um personagem novo pode tentar de novo
    -- nesse caso; isto so evita a entrega fisica desperdicada e fecha a
    -- transacao de forma limpa.
    if HardcoreKitsIdentity.isDead(player) then
        HardcoreKitsTransactions.abandonDead(player)
        HardcoreKitsAudit.logInitialClaim(player, accountId, tx, { granted = 0, total = 0, log = {} },
            "abandoned", "character_dead")
        toClient(player, HardcoreKits.CMD_CLAIM_ERROR, { claimType = HardcoreKits.CLAIM_TYPE_INITIAL, reason = "dead" })
        return
    end

    local okCommit, committed = pcall(commitInitialEntitlement, accountId, tx)
    if not okCommit or committed ~= true then
        print("[HardcoreKits] Falha ao confirmar entitlement do Kit Inicial: " .. tostring(committed))
        toClient(player, HardcoreKits.CMD_CLAIM_ERROR,
            { claimType = HardcoreKits.CLAIM_TYPE_INITIAL, reason = "delivery_failed" })
        return
    end
    if not HardcoreKitsTransactions.markDelivering(player) then
        toClient(player, HardcoreKits.CMD_CLAIM_ERROR,
            { claimType = HardcoreKits.CLAIM_TYPE_INITIAL, reason = "delivery_failed" })
        return
    end
    -- pcall LOCAL em volta da entrega inteira -- reforco pedido explicito do
    -- usuario apos relatos raros de "jogador nao recebe o kit". Sem isso,
    -- uma excecao nao prevista em qualquer ponto da entrega so seria pega
    -- pelo pcall generico do dispatcher (onClientCommand, HardcoreKits_Server.lua
    -- mais abaixo), que so loga no console e segue -- SEM avisar o cliente
    -- nem marcar a transacao pra recuperacao, deixando o jogador preso pra
    -- sempre (a flag de "ja resgatado" ja foi setada no sorteio, muito antes
    -- daqui). Com o pcall aqui, uma excecao vira exatamente o mesmo caminho
    -- de "zero_items_delivered" ja existente -- cliente avisado, transacao
    -- marcada STATUS_RECOVERY_REQUIRED. So falha limpa com zero itens criados
    -- pode ser repetida automaticamente; excecao/entrega parcial e ambigua e
    -- nunca e reexecutada inteira (evita duplicacao).
    local okDeliver, result = pcall(HardcoreKitsDelivery.deliverInitialKit, player, tx.rolledItems)
    if not okDeliver then
        print("[HardcoreKits] Excecao na entrega do Kit Inicial: " .. tostring(result))
        result = { granted = 0, total = 0, created = 0, log = {} }
    end

    local status, reason
    status, reason, result = deliveryDisposition(okDeliver, result)
    if status == "completed" or status == "completed_partial" then
        HardcoreKitsTransactions.complete(player)
        HardcoreKitsAudit.logInitialClaim(player, accountId, tx, result, status, reason)
        toClient(player, HardcoreKits.CMD_CLAIM_RESULT,
            { claimType = HardcoreKits.CLAIM_TYPE_INITIAL, claimId = tx.claimId, rolled = tx.rolledItems,
                result = result, status = status, partial = status == "completed_partial" })
    else
        -- resultado ja existe e fica registrado; nao sorteia de novo. Fica
        -- para retomada/investigacao manual (secao 20.3 e 30)
        local retrySafe = okDeliver and result.total > 0 and result.created == 0
        HardcoreKitsTransactions.markRecoveryRequired(player, reason, retrySafe)
        HardcoreKitsAudit.logInitialClaim(player, accountId, tx, result, "recovery_required", reason)
        toClient(player, HardcoreKits.CMD_CLAIM_ERROR, { claimType = HardcoreKits.CLAIM_TYPE_INITIAL, reason = "delivery_failed" })
    end
end

-- ================= Recompensa de Sobrevivencia (secoes 12-18, 19.4, 29) =================

Commands[HardcoreKits.CMD_REQUEST_SURVIVAL_CLAIM] = function(player, args)
    local claimType = HardcoreKits.CLAIM_TYPE_SURVIVAL
    local accountId = identityAvailable(player, claimType)
    if not accountId then return end

    if HardcoreKitsIdentity.isDead(player) then
        HardcoreKitsAudit.logAttemptDenied(player, accountId, claimType, "dead")
        toClient(player, HardcoreKits.CMD_CLAIM_ERROR, { claimType = claimType, reason = "dead" })
        return
    end

    local existingTx = quarantineAmbiguousPending(player, HardcoreKitsTransactions.getPending(player))
    if existingTx then
        if existingTx.claimType == claimType and HardcoreKitsTransactions.needsRecovery(player) then
            resumeSurvivalDelivery(player, accountId, existingTx)
        else
            toClient(player, HardcoreKits.CMD_CLAIM_ERROR, { claimType = claimType, reason = "pending_exists" })
        end
        return
    end

    if HardcoreKitsConfig.SurvivalRewardEnabled ~= true then
        toClient(player, HardcoreKits.CMD_CLAIM_ERROR, { claimType = claimType, reason = "disabled" })
        return
    end

    -- revalida a elegibilidade em cima da fonte da verdade agora, nao de um
    -- estado que o cliente possa ter guardado de segundos atras
    local state = HardcoreKitsState.build(player, accountId)
    if not state.survivalRewardAvailableNow then
        HardcoreKitsAudit.logAttemptDenied(player, accountId, claimType, "not_earned")
        toClient(player, HardcoreKits.CMD_CLAIM_ERROR, { claimType = claimType, reason = "not_earned" })
        return
    end

    local tx = HardcoreKitsTransactions.begin(player, claimType, accountId)
    if not tx then
        toClient(player, HardcoreKits.CMD_CLAIM_ERROR, { claimType = claimType, reason = "pending_exists" })
        return
    end
    tx.survivalClaimOrdinal = HardcoreKitsPersistence.survivalRewardsClaimed(player) + 1

    -- mesma logica de entrega diferida do Kit Inicial -- ver comentario la em
    -- cima -- e o MESMO fix: consome o slot de recompensa JA aqui no sorteio,
    -- nao la na entrega, senao reabrir o painel durante a animacao mostrava
    -- recompensa disponivel de novo e deixava resgatar mais vezes do que
    -- o personagem realmente tinha direito.
    local okRoll, rolled = pcall(HardcoreKitsRolls.rollSurvivalReward, player)
    if not okRoll or not validSurvivalRoll(rolled) then
        print("[HardcoreKits] Falha no sorteio da Recompensa de Sobrevivencia: " .. tostring(rolled))
        HardcoreKitsTransactions.cancel(player, okRoll and "empty_roll" or "roll_exception")
        HardcoreKitsAudit.logAttemptDenied(player, accountId, claimType, okRoll and "empty_roll" or "roll_exception")
        toClient(player, HardcoreKits.CMD_CLAIM_ERROR, { claimType = claimType, reason = "delivery_failed" })
        return
    end
    if not HardcoreKitsTransactions.setRolled(player, rolled) then
        HardcoreKitsTransactions.cancel(player, "invalid_transition")
        toClient(player, HardcoreKits.CMD_CLAIM_ERROR, { claimType = claimType, reason = "delivery_failed" })
        return
    end
    local okCommit, commitErr = pcall(commitSurvivalEntitlement, player, tx)
    if not okCommit or commitErr ~= true or not HardcoreKitsTransactions.markPersisted(player) then
        print("[HardcoreKits] Falha persistindo recompensa de sobrevivencia: " .. tostring(commitErr))
        toClient(player, HardcoreKits.CMD_CLAIM_ERROR, { claimType = claimType, reason = "delivery_failed" })
        return
    end

    toClient(player, HardcoreKits.CMD_CLAIM_STARTED, { claimType = claimType, claimId = tx.claimId, rolled = rolled })
end

resumeSurvivalDelivery = function(player, accountId, tx)
    -- mesma trava redundante do resumeInitialDelivery -- ver comentario la.
    if tx.status == HardcoreKits.STATUS_COMPLETED then return end
    if tx.status == HardcoreKits.STATUS_DELIVERING then
        HardcoreKitsTransactions.markRecoveryRequired(player, "interrupted_during_delivery", false)
        toClient(player, HardcoreKits.CMD_CLAIM_ERROR,
            { claimType = HardcoreKits.CLAIM_TYPE_SURVIVAL, reason = "delivery_failed" })
        return
    end

    -- mesma checagem de morte do resumeInitialDelivery -- ver comentario la.
    -- O contador de recompensas resgatadas (incrementado no sorteio) e por
    -- PERSONAGEM e morre junto com ele -- um personagem novo comeca do zero,
    -- entao nao ha nada pra reverter alem de fechar esta transacao.
    if HardcoreKitsIdentity.isDead(player) then
        HardcoreKitsTransactions.abandonDead(player)
        HardcoreKitsAudit.logSurvivalClaim(player, accountId, tx, { granted = 0, total = 0, log = {} },
            "abandoned", "character_dead")
        toClient(player, HardcoreKits.CMD_CLAIM_ERROR, { claimType = HardcoreKits.CLAIM_TYPE_SURVIVAL, reason = "dead" })
        return
    end

    local okCommit, committed = pcall(commitSurvivalEntitlement, player, tx)
    if not okCommit or committed ~= true then
        print("[HardcoreKits] Falha ao confirmar entitlement de sobrevivencia: " .. tostring(committed))
        toClient(player, HardcoreKits.CMD_CLAIM_ERROR,
            { claimType = HardcoreKits.CLAIM_TYPE_SURVIVAL, reason = "delivery_failed" })
        return
    end
    if not HardcoreKitsTransactions.markDelivering(player) then
        toClient(player, HardcoreKits.CMD_CLAIM_ERROR,
            { claimType = HardcoreKits.CLAIM_TYPE_SURVIVAL, reason = "delivery_failed" })
        return
    end
    -- mesmo reforco de resumeInitialDelivery acima -- ver comentario la.
    local okDeliver, result = pcall(HardcoreKitsDelivery.deliverSurvivalReward, player, tx.rolledItems)
    if not okDeliver then
        print("[HardcoreKits] Excecao na entrega da Recompensa de Sobrevivencia: " .. tostring(result))
        result = { granted = 0, total = 0, created = 0, log = {} }
    end

    local status, reason
    status, reason, result = deliveryDisposition(okDeliver, result)
    if status == "completed" or status == "completed_partial" then
        HardcoreKitsTransactions.complete(player)
        HardcoreKitsAudit.logSurvivalClaim(player, accountId, tx, result, status, reason)
        toClient(player, HardcoreKits.CMD_CLAIM_RESULT,
            { claimType = HardcoreKits.CLAIM_TYPE_SURVIVAL, claimId = tx.claimId, rolled = tx.rolledItems,
                result = result, status = status, partial = status == "completed_partial" })
    else
        local retrySafe = okDeliver and result.total > 0 and result.created == 0
        HardcoreKitsTransactions.markRecoveryRequired(player, reason, retrySafe)
        HardcoreKitsAudit.logSurvivalClaim(player, accountId, tx, result, "recovery_required", reason)
        toClient(player, HardcoreKits.CMD_CLAIM_ERROR, { claimType = HardcoreKits.CLAIM_TYPE_SURVIVAL, reason = "delivery_failed" })
    end
end

-- ================= revelacao concluida (entrega diferida) =================

-- disparado pelo cliente quando a roleta termina de girar visualmente (ver
-- HardcoreKitsRouletteWidget.onAllDone em HardcoreKits_Roulette.lua) -- so
-- AQUI os itens realmente entram no inventario do jogador. args.claimId e
-- opcional (o cliente sempre manda, mas se faltar so confiamos no que esta
-- pendente pro jogador mesmo assim -- ha no maximo uma transacao pendente
-- por jogador de qualquer forma).
Commands[HardcoreKits.CMD_REQUEST_REVEAL_COMPLETE] = function(player, args)
    local accountId = HardcoreKitsIdentity.accountId(player)
    if not accountId then return end
    local tx = HardcoreKitsTransactions.getPending(player)
    if not tx then return end -- nada pendente (ja entregue, ou este claimId nao existe mais) -- ignora
    if args and args.claimId and tx.claimId and args.claimId ~= tx.claimId then return end
    if tx.status ~= HardcoreKits.STATUS_PERSISTED
        and not (tx.status == HardcoreKits.STATUS_RECOVERY_REQUIRED and tx.recoveryRetrySafe == true) then return end

    if tx.claimType == HardcoreKits.CLAIM_TYPE_INITIAL then
        resumeInitialDelivery(player, accountId, tx)
    elseif tx.claimType == HardcoreKits.CLAIM_TYPE_SURVIVAL then
        resumeSurvivalDelivery(player, accountId, tx)
    end
end

-- ================= ciclo de vida do personagem =================
    -- Design original: PEGOU = cadastra (ja feito acima, no instante do sorteio).
    -- MORREU = apaga. O modo InitialKitSingleUseEnabled adiciona uma marca
    -- permanente por conta; essa nao e apagada em morte, exceto se a morte
    -- aconteceu antes de qualquer entrega real daquele claim especifico.
--
-- NAO usa Events.OnPlayerDeath: testado ao vivo e nao disparou no servidor
-- (bate com o proprio jogo base -- ISPerkLog.lua vanilla so trata esse
-- evento como confiavel isClient() + isLocalPlayer()).
--
-- Usa Events.OnCharacterDeath em vez disso -- confirmado via decompilacao
-- do projectzomboid.jar que dispara no servidor de verdade pra morte de
-- jogador em multiplayer: o cliente manda um DeadPlayerPacket pro servidor,
-- o servidor processa em DeadCharacterPacket.processClient(...) (nome de
-- metodo padrao da propria interface INetworkPacket do jogo pra "roda no
-- servidor, processando algo vindo de um cliente"), que chama
-- IsoGameCharacter.dieNetwork -> Kill -> onKilled -- e IsoPlayer.onKilled
-- (que sobrescreve a versao vazia da classe base) chama DoDeath(...) sem
-- nenhuma checagem de lado, que chama OnDeath(), cujo corpo inteiro e so
-- "trigger OnCharacterDeath, sem condicao nenhuma". Dispara pra QUALQUER
-- personagem (zumbi, animal, jogador) -- por isso o instanceof abaixo.
local function onCharacterDeath(character)
    if not character then return end
    if not instanceof(character, "IsoPlayer") then return end -- ignora zumbi/animal
    local okAnimal, animal = pcall(function()
        return character.isAnimal and character:isAnimal()
    end)
    if okAnimal and animal == true then return end -- IsoAnimal pode herdar IsoPlayer em B42

    local ok, err = pcall(function()
        local accountId = HardcoreKitsIdentity.accountId(character)
        local pending = HardcoreKitsPersistence.getPendingTx(character)
        if pending and pending.claimType == HardcoreKits.CLAIM_TYPE_INITIAL
            and pending.status ~= HardcoreKits.STATUS_COMPLETED then
            HardcoreKitsPersistence.clearInitialKitSingleUseClaimed(accountId, pending.claimId)
        end
        local singleUseActive = HardcoreKitsConfig.InitialKitSingleUseEnabled == true
        if not (singleUseActive and HardcoreKitsPersistence.isInitialKitSingleUseClaimed(accountId)) then
            HardcoreKitsPersistence.clearInitialKitClaimed(accountId)
        end
    end)
    if not ok then
        print("[HardcoreKits] Erro em onCharacterDeath: " .. tostring(err))
    end
end
if HardcoreKits._characterDeathHandler and Events.OnCharacterDeath.Remove then
    Events.OnCharacterDeath.Remove(HardcoreKits._characterDeathHandler)
end
HardcoreKits._characterDeathHandler = onCharacterDeath
Events.OnCharacterDeath.Add(onCharacterDeath)

-- ================= dispatch =================

local function onClientCommand(module, command, player, args)
    if module ~= HardcoreKits.MODULE then return end
    if not player then return end
    if type(command) ~= "string" or command == "" or #command > 64 then return end
    local ok, username = pcall(function() return player:getUsername() end)
    if not ok or type(username) ~= "string" or username == "" or #username > 64 then return end

    local handler = Commands[command]
    if not handler then return end
    if throttled(username, command) then return end

    -- um erro num handler nao deve derrubar o listener pra todo mundo
    local safeArgs = type(args) == "table" and args or {}
    local ok2, err = pcall(handler, player, safeArgs)
    if not ok2 then
        print("[HardcoreKits] Erro no comando '" .. tostring(command) .. "': " .. tostring(err))
    end
end

if HardcoreKits._serverCommandHandler and Events.OnClientCommand.Remove then
    Events.OnClientCommand.Remove(HardcoreKits._serverCommandHandler)
end
HardcoreKits._serverCommandHandler = onClientCommand
Events.OnClientCommand.Add(onClientCommand)

print("[HardcoreKits] Servidor pronto.")
