-- Maquina de estados da transacao de resgate (secao 20.3 da especificacao):
-- created -> rolled -> persisted -> delivering -> completed
--                                              \-> cancelled / recovery_required / abandoned_dead
--
-- O ponto central: o resultado sorteado (rolledItems) e escrito no ModData do
-- personagem assim que existe (setRolled), MUITO antes da entrega comecar.
-- Se o servidor cair, o proximo /kit encontra a mesma transacao e nunca
-- sorteia de novo. A entrega so e retomada automaticamente antes de qualquer
-- criacao, ou apos falha confirmada com zero criacoes; estado delivering e
-- sempre isolado para recuperacao manual (ver needsRecovery).
if isClient() then return end

require "HardcoreKits_Protocol"
require "HardcoreKits_Persistence"
require "HardcoreKits_Identity"
require "HardcoreKits_Utils"

HardcoreKitsTransactions = HardcoreKitsTransactions or {}

-- cria e persiste uma transacao nova. Retorna nil, "pending_exists" se ja
-- houver uma pendente -- nunca sobrescreve uma transacao em andamento
-- (protege contra duplo clique e comando duplicado, secao 21).
function HardcoreKitsTransactions.begin(player, claimType, accountId)
    if HardcoreKitsPersistence.getPendingTx(player) then
        return nil, "pending_exists"
    end
    local tx = {
        claimId = HardcoreKitsUtils.newClaimId(),
        claimType = claimType,
        accountId = accountId,
        characterName = HardcoreKitsIdentity.characterName(player),
        username = HardcoreKitsIdentity.username(player),
        createdAt = HardcoreKitsUtils.realTime(),
        status = HardcoreKits.STATUS_CREATED,
        rolledItems = nil,
        completedAt = nil,
    }
    HardcoreKitsPersistence.setPendingTx(player, tx)
    return tx
end

function HardcoreKitsTransactions.setRolled(player, rolledItems)
    local tx = HardcoreKitsPersistence.getPendingTx(player)
    if not tx or tx.status ~= HardcoreKits.STATUS_CREATED or type(rolledItems) ~= "table" then return nil end
    tx.status = HardcoreKits.STATUS_ROLLED
    tx.rolledItems = rolledItems
    return tx
end

function HardcoreKitsTransactions.markPersisted(player)
    local tx = HardcoreKitsPersistence.getPendingTx(player)
    if not tx or tx.status ~= HardcoreKits.STATUS_ROLLED then return nil end
    tx.status = HardcoreKits.STATUS_PERSISTED
    return tx
end

function HardcoreKitsTransactions.markDelivering(player)
    local tx = HardcoreKitsPersistence.getPendingTx(player)
    if not tx then return nil end
    if tx.status ~= HardcoreKits.STATUS_ROLLED
        and tx.status ~= HardcoreKits.STATUS_PERSISTED
        and not (tx.status == HardcoreKits.STATUS_RECOVERY_REQUIRED and tx.recoveryRetrySafe == true) then
        return nil
    end
    tx.status = HardcoreKits.STATUS_DELIVERING
    local attempts = tonumber(tx.deliveryAttempts) or 0
    if attempts ~= attempts or attempts == math.huge or attempts == -math.huge then attempts = 0 end
    tx.deliveryAttempts = math.max(0, math.floor(attempts)) + 1
    tx.lastDeliveryAttemptAt = HardcoreKitsUtils.realTime()
    -- O proximo retry so volta a ser seguro se a tentativa terminar normalmente
    -- com zero itens criados e markRecoveryRequired confirmar isso.
    tx.recoveryRetrySafe = false
    return tx
end

-- Registra uma falha sem descartar o resultado sorteado. retrySafe so pode ser
-- true quando a entrega terminou normalmente e confirmou granted==0: depois de
-- uma excecao/queda ou entrega parcial, repetir o lote inteiro poderia duplicar
-- itens que ja chegaram ao inventario.
function HardcoreKitsTransactions.markRecoveryRequired(player, reason, retrySafe)
    local tx = HardcoreKitsPersistence.getPendingTx(player)
    if not tx then return nil end
    tx.status = HardcoreKits.STATUS_RECOVERY_REQUIRED
    tx.recoveryReason = reason
    tx.recoveryRetrySafe = retrySafe == true
    tx.recoveryMarkedAt = HardcoreKitsUtils.realTime()
    return tx
end

-- marca concluida e libera o slot de "pendente" do personagem (fica so o
-- lastCompletedClaimId). So chamar depois que a entrega ja rodou.
function HardcoreKitsTransactions.complete(player)
    local tx = HardcoreKitsPersistence.getPendingTx(player)
    if not tx then return nil end
    tx.status = HardcoreKits.STATUS_COMPLETED
    tx.completedAt = HardcoreKitsUtils.realTime()
    HardcoreKitsPersistence.clearPendingTx(player)
    return tx
end

-- cancela uma transacao que AINDA NAO sorteou nada (status created) -- por
-- exemplo, revalidacao de elegibilidade falhou depois do pedido. Nunca deve
-- ser chamada depois de setRolled: nesse ponto o resultado ja existe e
-- precisa ser entregue ou recuperado, nao descartado.
function HardcoreKitsTransactions.cancel(player, reason)
    local tx = HardcoreKitsPersistence.getPendingTx(player)
    if not tx or tx.status ~= HardcoreKits.STATUS_CREATED then return nil end
    tx.status = HardcoreKits.STATUS_CANCELLED
    tx.cancelReason = reason
    HardcoreKitsPersistence.setPendingTx(player, nil)
    return tx
end

-- Termina uma transacao JA SORTEADA porque o personagem morreu entre o
-- sorteio e o instante exato da entrega -- diferente de cancel() acima, que
-- so serve ANTES do sorteio (e explicitamente nunca deve ser chamada depois
-- dele). Nao ha "tentar de novo" aqui: o personagem esta morto, entregar
-- itens agora so os jogaria dentro de um cadaver que ninguem vai looter. O
-- flag de "ja resgatado" da CONTA ja foi limpo por onCharacterDeath no
-- instante da morte (ver HardcoreKits_Server.lua) -- isto so fecha a
-- transacao em si de forma limpa, sem entregar nada.
function HardcoreKitsTransactions.abandonDead(player)
    local tx = HardcoreKitsPersistence.getPendingTx(player)
    if not tx then return nil end
    tx.status = HardcoreKits.STATUS_ABANDONED_DEAD
    HardcoreKitsPersistence.clearPendingTx(player)
    return tx
end

function HardcoreKitsTransactions.getPending(player)
    return HardcoreKitsPersistence.getPendingTx(player)
end

-- true somente quando uma transacao sorteada pode ser retomada sem risco:
-- persisted/rolled antes da mutacao, ou recovery explicitamente marcado como
-- zero-criacao. Estados ambiguos permanecem pendentes para inspecao manual.
function HardcoreKitsTransactions.needsRecovery(player)
    local tx = HardcoreKitsPersistence.getPendingTx(player)
    if not tx then return false end
    return tx.status == HardcoreKits.STATUS_ROLLED
        or tx.status == HardcoreKits.STATUS_PERSISTED
        or (tx.status == HardcoreKits.STATUS_RECOVERY_REQUIRED and tx.recoveryRetrySafe == true)
end
