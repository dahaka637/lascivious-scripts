-- Camada de rede do cliente: manda os requests e guarda a ultima resposta do
-- servidor num cache simples que a GUI le. Nenhuma decisao de elegibilidade
-- acontece aqui -- o cliente so repassa o que o servidor mandou e pede
-- acoes; quem decide e sempre o servidor (secao 21 da especificacao).
require "HardcoreKits_Protocol"

HardcoreKitsClient = HardcoreKitsClient or {}

-- ultimo state recebido + timestamp local de quando chegou, pra dar pra
-- calcular contagens regressivas no cliente sem reconsultar o servidor a
-- cada segundo (ver HardcoreKitsClient.liveRemaining)
HardcoreKitsClient.state = nil
HardcoreKitsClient.stateReceivedAtMs = 0

-- ultima mensagem de cada tipo -- Etapa 5 troca a exibicao disso por uma
-- roleta animada, o dado que chega do servidor ja serve pras duas
HardcoreKitsClient.lastClaimStarted = nil
HardcoreKitsClient.lastClaimResult = nil
HardcoreKitsClient.lastClaimError = nil
HardcoreKitsClient.lastClaimNotice = nil

-- Mantida no namespace para sobreviver a reload sem deixar closures antigas
-- presas ao dispatcher anterior. A janela remove explicitamente seu token.
HardcoreKitsClient.listeners = HardcoreKitsClient.listeners or {}
local listeners = HardcoreKitsClient.listeners
function HardcoreKitsClient.onUpdate(fn)
    if type(fn) ~= "function" then return nil end
    table.insert(listeners, fn)
    return fn
end

function HardcoreKitsClient.offUpdate(fn)
    if type(fn) ~= "function" then return end
    for i = #listeners, 1, -1 do
        if listeners[i] == fn then table.remove(listeners, i) end
    end
end

local function notify()
    for _, fn in ipairs(listeners) do
        local ok, err = pcall(fn)
        if not ok then print("[HardcoreKits] listener de UI falhou: " .. tostring(err)) end
    end
end

local function send(command, args)
    local player = getPlayer()
    if not player then return end
    sendClientCommand(player, HardcoreKits.MODULE, command, args or {})
end

function HardcoreKitsClient.requestState()
    send(HardcoreKits.CMD_REQUEST_STATE, {})
end

function HardcoreKitsClient.requestInitialClaim()
    HardcoreKitsClient.lastClaimError = nil
    HardcoreKitsClient.lastClaimNotice = nil
    send(HardcoreKits.CMD_REQUEST_INITIAL_CLAIM, {})
end

function HardcoreKitsClient.requestSurvivalClaim()
    HardcoreKitsClient.lastClaimError = nil
    HardcoreKitsClient.lastClaimNotice = nil
    send(HardcoreKits.CMD_REQUEST_SURVIVAL_CLAIM, {})
end

-- avisa o servidor que a roleta terminou de girar visualmente -- so ENTAO os
-- itens realmente entram no inventario (ver HardcoreKits_Server.lua). Chamado
-- pelo onAllDone da roleta (HardcoreKits_Roulette.lua).
function HardcoreKitsClient.requestRevealComplete(claimId)
    send(HardcoreKits.CMD_REQUEST_REVEAL_COMPLETE, { claimId = claimId })
end

-- segundos restantes calculados no cliente a partir do ultimo valor
-- conhecido do servidor -- so um cronometro visual, nunca a fonte da verdade
function HardcoreKitsClient.liveRemaining(fieldName)
    local s = HardcoreKitsClient.state
    if not s or type(s[fieldName]) ~= "number" then return 0 end
    local elapsedMs = getTimestampMs() - HardcoreKitsClient.stateReceivedAtMs
    local remaining = s[fieldName] - math.floor(elapsedMs / 1000)
    return math.max(0, remaining)
end

local function onServerCommand(module, command, args)
    if module ~= HardcoreKits.MODULE then return end
    if type(command) ~= "string" then return end
    args = type(args) == "table" and args or {}
    if command == HardcoreKits.CMD_STATE then
        HardcoreKitsClient.state = args
        HardcoreKitsClient.stateReceivedAtMs = getTimestampMs()
    elseif command == HardcoreKits.CMD_CLAIM_STARTED then
        HardcoreKitsClient.lastClaimStarted = args
        HardcoreKitsClient.lastClaimResult = nil
        HardcoreKitsClient.lastClaimError = nil
        HardcoreKitsClient.lastClaimNotice = nil
    elseif command == HardcoreKits.CMD_CLAIM_RESULT then
        HardcoreKitsClient.lastClaimResult = args
        HardcoreKitsClient.lastClaimError = nil
        HardcoreKitsClient.lastClaimNotice = nil
        if args and (args.partial == true or args.status == "completed_partial") then
            HardcoreKitsClient.lastClaimNotice = {
                claimType = args.claimType,
                claimId = args.claimId,
                reason = "partial_delivery",
            }
            HardcoreKitsClient.lastClaimNoticeAtMs = getTimestampMs()
        end
        HardcoreKitsClient.requestState() -- reflete o cooldown/flag novo na hora
    elseif command == HardcoreKits.CMD_CLAIM_ERROR then
        HardcoreKitsClient.lastClaimError = args
        HardcoreKitsClient.lastClaimErrorAtMs = getTimestampMs()
        -- o cliente pode ter clicado achando que estava liberado (state em
        -- cache, corrida com o servidor) -- resincroniza pra a tela parar de
        -- oferecer uma acao que o servidor acabou de rejeitar
        HardcoreKitsClient.requestState()
    else
        return
    end
    notify()
end

-- Reload de Lua nao pode empilhar dispatchers/listeners antigos.
if HardcoreKitsClient._serverCommandHandler and Events.OnServerCommand.Remove then
    Events.OnServerCommand.Remove(HardcoreKitsClient._serverCommandHandler)
end
HardcoreKitsClient._serverCommandHandler = onServerCommand
Events.OnServerCommand.Add(onServerCommand)
