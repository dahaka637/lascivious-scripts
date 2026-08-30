-- Nomes de modulo/comando de rede. Fonte unica para client e server,
-- para que um typo de string nunca separe silenciosamente quem envia de quem escuta.
HardcoreKits = HardcoreKits or {}

HardcoreKits.MODULE = "HKits"

-- cliente -> servidor
HardcoreKits.CMD_REQUEST_STATE = "requestKitState"
HardcoreKits.CMD_REQUEST_INITIAL_CLAIM = "requestInitialKitClaim"
HardcoreKits.CMD_REQUEST_SURVIVAL_CLAIM = "requestSurvivalRewardClaim"
HardcoreKits.CMD_REQUEST_PENDING = "requestPendingClaim"
-- avisa que a roleta terminou de girar visualmente -- so ENTAO o servidor
-- entrega os itens de verdade (o resultado ja foi decidido e persistido bem
-- antes disso, no clique original -- isso so libera o momento da entrega,
-- nunca o que sera entregue). Ver HardcoreKits_Server.lua e
-- HardcoreKitsConfig.PendingDeliveryTimeoutRealSeconds (rede de seguranca
-- caso esse aviso nunca chegue -- desconexao/fechamento no meio da animacao).
HardcoreKits.CMD_REQUEST_REVEAL_COMPLETE = "requestRevealComplete"

-- admin (comandos permanentes, protegidos por isAdmin -- ver HardcoreKits_Debug.lua)
HardcoreKits.CMD_DEBUG_STATE = "debugState"
HardcoreKits.CMD_DEBUG_RESET_ACCOUNT = "debugResetAccount"

-- servidor -> cliente
HardcoreKits.CMD_STATE = "kitState"
HardcoreKits.CMD_CLAIM_STARTED = "claimStarted"
HardcoreKits.CMD_CLAIM_RESULT = "claimResult"
HardcoreKits.CMD_CLAIM_ERROR = "claimError"
HardcoreKits.CMD_DEBUG_REPLY = "debugReply"

-- tipos de claim usados na maquina de transacao (secao 20.3 da spec)
HardcoreKits.CLAIM_TYPE_INITIAL = "initial"
HardcoreKits.CLAIM_TYPE_SURVIVAL = "survival"

-- estados da transacao (secao 20.3 da spec)
HardcoreKits.STATUS_CREATED = "created"
HardcoreKits.STATUS_ROLLED = "rolled"
HardcoreKits.STATUS_PERSISTED = "persisted"
HardcoreKits.STATUS_DELIVERING = "delivering"
HardcoreKits.STATUS_COMPLETED = "completed"
HardcoreKits.STATUS_CANCELLED = "cancelled"
HardcoreKits.STATUS_RECOVERY_REQUIRED = "recovery_required"
-- Personagem morreu entre o sorteio e o instante exato da entrega (secao
-- pedida pelo usuario: nao deve contar como resgatado). Diferente de
-- recovery_required (fica pendente para retry automatico somente quando zero
-- itens foram criados; demais casos exigem inspecao manual): esta e terminal,
-- nao ha "de novo" pra um cadaver. Ver HardcoreKitsTransactions.abandonDead.
HardcoreKits.STATUS_ABANDONED_DEAD = "abandoned_dead"
