-- Monta o payload de elegibilidade que o cliente recebe ao abrir /kit
-- (secao 4 da especificacao). Le apenas: nenhuma escrita, nenhum sorteio,
-- nenhuma entrega -- so calcula "onde as coisas estao agora".
if isClient() then return end

require "HardcoreKits_Config"
require "HardcoreKits_Persistence"
require "HardcoreKits_Identity"
require "HardcoreKits_Transactions"

HardcoreKitsState = HardcoreKitsState or {}

function HardcoreKitsState.build(player, accountId)
    local cfg = HardcoreKitsConfig
    local state = {}

    -- ---------- Kit Inicial ----------
    -- O modo de Kit unico e uma trava permanente por conta para claims feitos
    -- enquanto a opcao estava ativa. Quando ligado, ele substitui o cooldown:
    -- se ainda nao pegou, pode pegar agora; se ja pegou nesse modo, nunca mais.
    --
    -- O antiabuso de conta (tempo REAL, secao 6.2 da especificacao -- de
    -- proposito NAO e tempo de jogo, senao dava pra furar so acelerando/
    -- dormindo no jogo) continua opcional para o modo normal: quando desligado,
    -- a conta nunca bloqueia um novo Kit Inicial, so o "ja resgatado por este
    -- personagem" continua valendo.
    local claimedByChar = HardcoreKitsPersistence.isInitialKitClaimed(accountId)
    local singleUseEnabled = cfg.InitialKitSingleUseEnabled == true
    local claimedByAccount = singleUseEnabled
        and HardcoreKitsPersistence.isInitialKitSingleUseClaimed(accountId) == true
    local cooldownEnabled = cfg.InitialKitCooldownEnabled == true and not singleUseEnabled
    local cooldownRemaining = cooldownEnabled and HardcoreKitsPersistence.initialKitCooldownRemaining(accountId) or 0
    state.initialKitEnabled = cfg.InitialKitEnabled == true
    state.initialKitSingleUseEnabled = singleUseEnabled
    state.initialKitClaimedByAccount = claimedByAccount
    state.initialKitClaimedByCharacter = claimedByChar
    state.initialKitCooldownRemainingSeconds = cooldownRemaining
    state.initialKitAvailable = state.initialKitEnabled
        and (not claimedByAccount) and (not claimedByChar) and cooldownRemaining <= 0

    -- ---------- Recompensa de Sobrevivencia ----------
    -- BUG CONHECIDO (2026-08-28, desativado ate investigar com calma): apos o
    -- 1o resgate (7 dias default), resgates seguintes liberam de novo muito
    -- antes do proximo marco esperado (14 dias), com um pequeno delay (nao
    -- instantaneo -- indica que algo muda entre uma checagem e outra, nao um
    -- estado travado). Ja confirmado que NAO e a formula abaixo: earned =
    -- floor(hours/intervalHours), available = earned - claimed, com claimed
    -- persistido por personagem em player:getModData() -- matematicamente
    -- equivalente a qualquer jeito de escrever essa checagem, entao o bug nao
    -- esta em "como comparar". Hipoteses ainda nao descartadas por falta de
    -- log real de producao: (1) o hoursSurvived da propria engine nao sobe do
    -- jeito que a gente assume pra um personagem real conectado -- so achei
    -- no bytecode do jogo um caminho de incremento por tick gated por
    -- isNpc()==true (nao deveria valer pra jogador de verdade) e um caminho
    -- de rede (ConnectedPacket) que so mexe nisso na reconexao (jogador
    -- confirmou que o bug acontece mesmo sem reconectar, entao esse
    -- especificamente fica descartado); (2) uma entrega que fica "presa" e o
    -- mecanismo de recuperacao (maybeResolveStaleDelivery em
    -- HardcoreKits_Server.lua) reprocessando ela sem re-somar hours de
    -- verdade. Pra reabrir a investigacao: reativar SurvivalRewardEnabled,
    -- reproduzir (dá pra acelerar baixando SurvivalRewardIntervalHours no
    -- sandbox) e logar hours/earned/claimed juntos no exato instante em que
    -- "available" volta a ficar > 0 depois do 1o resgate.
    local hours = HardcoreKitsIdentity.hoursSurvived(player)
    local intervalHours = tonumber(cfg.SurvivalRewardIntervalHours) or 168
    if intervalHours ~= intervalHours or intervalHours <= 0 or intervalHours == math.huge then
        intervalHours = 168
    end
    local earned = math.floor(hours / intervalHours)
    local claimed = HardcoreKitsPersistence.survivalRewardsClaimed(player)
    local available = math.max(0, earned - claimed)

    local cap = tonumber(cfg.SurvivalMaximumStoredRewards)
    if cap and (cap ~= cap or cap == math.huge or cap == -math.huge) then cap = nil end
    if cap and cap > 0 then
        cap = math.floor(cap)
        available = math.min(available, cap)
    end

    local hoursIntoCurrentCycle = hours % intervalHours
    local hoursUntilNextMilestone = intervalHours - hoursIntoCurrentCycle

    state.survivalRewardEnabled = cfg.SurvivalRewardEnabled == true
    state.hoursSurvived = hours
    state.survivalRewardsEarned = earned
    state.survivalRewardsClaimed = claimed
    state.survivalRewardsAvailable = available
    state.survivalMaxStoredRewards = cap
    state.survivalNextRewardInSeconds = math.max(0, math.floor(hoursUntilNextMilestone * 3600))
    state.survivalRewardAvailableNow = state.survivalRewardEnabled and available > 0

    -- ---------- transacao pendente ----------
    local pending = HardcoreKitsTransactions.getPending(player)
    state.hasPendingClaim = pending ~= nil
    state.pendingClaimType = pending and pending.claimType or nil
    state.pendingClaimStatus = pending and pending.status or nil
    state.pendingNeedsRecovery = HardcoreKitsTransactions.needsRecovery(player)

    state.isDead = HardcoreKitsIdentity.isDead(player)

    if state.survivalRewardEnabled then
        pcall(diagLogSurvival, player, state)
    end

    return state
end
