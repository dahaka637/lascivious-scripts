-- Conteudo da aba "Kit Inicial" (secao 5.1). v3: sem frames/bordas
-- encapsulando secoes internas (so espacamento separa as partes -- pedido
-- explicito do usuario, "nao quero aparencia de tudo em frames visiveis"),
-- UMA roleta grande que troca de titulo/sequencia a cada sorteio, resumo
-- final em grade de cartas com icone + quantidade (quebra linha sozinha se
-- nao couber, importante com o modo multi-sorteio que pode gerar varios
-- resultados de comida/bebida numa unica captura).
require "ISUI/ISPanel"
require "HardcoreKits_Protocol"
require "HardcoreKits_Config"
require "HardcoreKits_Theme"
require "HardcoreKits_Widgets"
require "HardcoreKits_Client"
require "HardcoreKits_Window"
require "HardcoreKits_Utils"
require "HardcoreKits_Roulette"

HardcoreKitsTabInitial = ISPanel:derive("HardcoreKitsTabInitial")

local PAD = 20
local BTN_W, BTN_H = 300, 44
local ROULETTE_H = 210
local REPLY_TIMEOUT_MS = 6000
-- modo roleta rapida: 1-2 reels no lote usam o tamanho NORMAL (ROULETTE_H,
-- cabe com folga -- pedido explicito do usuario), 3+ usam esse tamanho
-- compacto. A janela (HardcoreKits_Window.lua) cresce/encolhe sozinha por
-- baixo pra acompanhar cada lote (ver HardcoreKitsRouletteFastRunner e o
-- callback onHeightNeeded em startRoulette abaixo) -- nao precisa mais de um
-- calculo de "cabe no espaco atual" aqui, a janela e quem se adapta.
local FAST_REEL_H = 170
-- linhas do resumo quando ele tem a tela so pra ele (modo rapido, ja
-- terminado -- ver prerender()); o padrao de 2 linhas (competindo por
-- espaco com a roleta) continua vindo de HardcoreKitsSummaryPanel.DEFAULT_ROWS_VISIBLE.
local FAST_SUMMARY_ROWS = 3

local function create(window, x, y, w, h)
    local o = ISPanel:new(x, y, w, h)
    setmetatable(o, HardcoreKitsTabInitial)
    HardcoreKitsTabInitial.__index = HardcoreKitsTabInitial
    o.background = false
    o.window = window
    o.awaitingReply = false
    o.roulette = nil
    o.lastSeenClaimId = nil
    return o
end

HardcoreKitsWindow.registerTab({ id = "initial", labelKey = "UI_HardcoreKits_TabInitial", create = create })

function HardcoreKitsTabInitial:createChildren()
    self.claimBtn = HardcoreKitsButton:new(0, 0, BTN_W, BTN_H, getText("UI_HardcoreKits_BtnOpenKit"), self,
        HardcoreKitsTabInitial.onClaimClick, "primary")
    self:addChild(self.claimBtn)
    -- grade de resumo com altura fixa de 2 linhas -- vira scroll se tiver mais
    self.summary = HardcoreKitsSummaryPanel:new(0, 0, self.width)
    self.summary:initialise()
    self:addChild(self.summary)
    self.summary:setVisible(false)
    self:refreshButton()
end

function HardcoreKitsTabInitial:onShow()
    self:refreshButton()
end

-- painel reaberto (fechado -> aberto de novo): uma roleta ja concluida e
-- sobra de uma captura anterior -- descarta pra a aba voltar pro estado
-- normal (status + botao) em vez de exibir uma animacao velha de novo
function HardcoreKitsTabInitial:onReopen()
    if self.roulette and self.roulette.finished then
        self:removeChild(self.roulette)
        self.roulette = nil
    end
end

function HardcoreKitsTabInitial:onClaimClick()
    if self.awaitingReply then return end
    self.awaitingReply = true
    self.awaitingSince = getTimestampMs()
    HardcoreKitsClient.requestInitialClaim()
    self:refreshButton()
end

function HardcoreKitsTabInitial:startRoulette(rolled)
    if self.roulette then
        HardcoreKitsRoulette.unregister(self.roulette)
        self:removeChild(self.roulette)
        self.roulette = nil
    end
    local innerW = self.width - PAD * 2
    -- so avisa o servidor pra entregar os itens de verdade quando a roleta
    -- termina de girar visualmente -- ver HardcoreKits_Server.lua
    local claimId = self.lastSeenClaimId
    local onAllDone = function() HardcoreKitsClient.requestRevealComplete(claimId) end
    -- modo roleta rapida (pedido explicito do usuario): mesma
    -- interface externa (:new(x,y,w,h,steps,onAllDone), campos
    -- .finished/.isFastRunner), so troca QUAL classe gira -- ver
    -- HardcoreKitsRouletteFastRunner em HardcoreKits_Roulette.lua.
    local fastMode = HardcoreKitsConfig.FastRouletteMode == true
    local steps = HardcoreKitsRoulette.buildInitialSteps(rolled, fastMode)
    local runner
    if fastMode then
        -- onHeightNeeded: o runner chama isso a cada lote com a altura de
        -- container que precisa AGORA -- a janela cresce/encolhe sozinha
        -- pra caber (ver HardcoreKitsWindow:setContentHeight), sem precisar
        -- de um tamanho de janela fixo grande o tempo todo.
        local onHeightNeeded = function(rouletteH)
            self.window:setContentHeight(PAD + rouletteH + 18 + BTN_H)
        end
        runner = HardcoreKitsRouletteFastRunner:new(PAD, PAD, innerW, ROULETTE_H, steps, onAllDone,
            ROULETTE_H, FAST_REEL_H, onHeightNeeded)
    else
        -- garante o tamanho base -- a janela pode ter ficado maior de um
        -- claim anterior no modo rapido (lote de 3+ reels)
        self.window:setContentHeight(0)
        runner = HardcoreKitsRouletteWidget:new(PAD, PAD, innerW, ROULETTE_H, steps, onAllDone)
    end
    runner:initialise()
    self:addChild(runner)
    self.roulette = runner
    -- Registra no ticker global (HardcoreKits_Roulette.lua) -- e o que
    -- garante que o sorteio continua avancando de verdade mesmo se o
    -- jogador fechar a janela do /kit no meio da animacao (pedido explicito
    -- do usuario). Desregistrado sozinho quando o proprio runner termina
    -- (ver HardcoreKitsRouletteWidget:advance() / FastRunner:launchNextBatch()).
    HardcoreKitsRoulette.register(runner)
end

function HardcoreKitsTabInitial:onStateUpdated()
    local started = HardcoreKitsClient.lastClaimStarted
    if started and started.claimType == HardcoreKits.CLAIM_TYPE_INITIAL
        and started.claimId ~= self.lastSeenClaimId then
        self.lastSeenClaimId = started.claimId
        self.awaitingReply = false
        self:startRoulette(started.rolled)
    end
    if self.awaitingReply then
        local err = HardcoreKitsClient.lastClaimError
        if err and err.claimType == HardcoreKits.CLAIM_TYPE_INITIAL then
            self.awaitingReply = false
        end
    end
    self:refreshButton()
end

function HardcoreKitsTabInitial:refreshButton()
    local s = HardcoreKitsClient.state
    local label, enabled = getText("UI_HardcoreKits_BtnOpenKit"), false

    if self.awaitingReply or (self.roulette and not self.roulette.finished) then
        label, enabled = getText("UI_HardcoreKits_BtnOpening"), false
    elseif s then
        if s.initialKitAvailable then
            enabled = true
        elseif s.initialKitClaimedByAccount then
            label = getText("UI_HardcoreKits_BtnAlreadyClaimed")
        elseif s.initialKitClaimedByCharacter then
            label = getText("UI_HardcoreKits_BtnAlreadyClaimed")
        elseif not s.initialKitEnabled then
            label = getText("UI_HardcoreKits_BtnUnavailable")
        elseif (s.initialKitCooldownRemainingSeconds or 0) > 0 then
            label = getText("UI_HardcoreKits_BtnLocked")
        end
    else
        label = getText("UI_HardcoreKits_BtnSyncing")
    end

    self.claimBtn:setLabel(label)
    self.claimBtn:setEnabled(enabled)
end

local function statusLine(s)
    if not s then return getText("UI_HardcoreKits_StatusSyncing"), HardcoreKitsUI.col.muted end
    local c = HardcoreKitsUI.col
    if s.initialKitClaimedByAccount then
        return getText("UI_HardcoreKits_StatusInitialAlreadyClaimedAccount"), c.muted
    end
    if s.initialKitClaimedByCharacter then return getText("UI_HardcoreKits_StatusInitialAlreadyClaimed"), c.muted end
    if not s.initialKitEnabled then return getText("UI_HardcoreKits_StatusInitialDisabled"), c.muted end
    local cooldown = HardcoreKitsClient.liveRemaining("initialKitCooldownRemainingSeconds")
    if cooldown > 0 then
        return getText("UI_HardcoreKits_StatusInitialCooldown", HardcoreKitsUtils.formatDuration(cooldown)), c.danger
    end
    if s.initialKitAvailable then return getText("UI_HardcoreKits_StatusInitialAvailable"), c.ok end
    return getText("UI_HardcoreKits_StatusUnavailableNow"), c.muted
end

-- por alguns segundos apos um CMD_CLAIM_ERROR sem equivalente no state
-- (personagem morto, resgate ja em andamento, falha na entrega), mostra o
-- motivo no lugar da linha de status normal -- depois volta sozinho pro
-- statusLine(s) de sempre (checagem por tempo, sem timer/limpeza manual)
local ERROR_DISPLAY_MS = 5000
local function effectiveStatusLine(s)
    local notice = HardcoreKitsClient.lastClaimNotice
    if notice and notice.claimType == HardcoreKits.CLAIM_TYPE_INITIAL and HardcoreKitsClient.lastClaimNoticeAtMs
        and getTimestampMs() - HardcoreKitsClient.lastClaimNoticeAtMs < ERROR_DISPLAY_MS then
        local text = HardcoreKitsUI.claimNoticeText(notice.reason)
        if text then return text, HardcoreKitsUI.col.danger end
    end
    local err = HardcoreKitsClient.lastClaimError
    if err and err.claimType == HardcoreKits.CLAIM_TYPE_INITIAL and HardcoreKitsClient.lastClaimErrorAtMs
        and getTimestampMs() - HardcoreKitsClient.lastClaimErrorAtMs < ERROR_DISPLAY_MS then
        local text = HardcoreKitsUI.claimErrorText(err.reason)
        if text then return text, HardcoreKitsUI.col.danger end
    end
    return statusLine(s)
end

function HardcoreKitsTabInitial:prerender()
    if self.awaitingReply and getTimestampMs() - (self.awaitingSince or 0) > REPLY_TIMEOUT_MS then
        self.awaitingReply = false
    end
    self:refreshButton()

    local c = HardcoreKitsUI.col
    local s = HardcoreKitsClient.state
    local w = self.width
    local items = HardcoreKitsUI.completedResultSteps(self.roulette)

    -- modo roleta rapida, ja terminado: o runner nao tem mais reel nenhum
    -- visivel (ver HardcoreKitsRouletteFastRunner:launchNextBatch) -- so o
    -- resumo + botao aparecem, CENTRALIZADOS verticalmente na aba (pedido
    -- explicito do usuario: "todas as roletas somem e fica so o claim
    -- summary centralizado na tela"). Botao vem DEPOIS do resumo (pedido
    -- explicito: "deveria aparecer embaixo do resumo e nao acima, se nao
    -- fica estranho") -- mantido visivel (em vez de so o resumo sozinho) pra
    -- continuar acessivel sem precisar fechar/reabrir o painel. Resumo usa
    -- mais linhas que o padrao (FAST_SUMMARY_ROWS) -- pedido explicito:
    -- "a caixa do resumo poderia ser maior nesse caso, pois nao vai competir
    -- espaco com a roleta".
    local fastFinished = self.roulette and self.roulette.isFastRunner and self.roulette.finished
    if fastFinished and #items > 0 then
        self.summary:setRowsVisible(FAST_SUMMARY_ROWS)
        local dividerH = HardcoreKitsUI.fontH(UIFont.Small)
        local blockH = dividerH + 16 + self.summary:getHeight() + 30 + BTN_H
        local y = math.max(0, math.floor((self.height - blockH) / 2))

        HardcoreKitsUI.leftDivider(self, getText("UI_HardcoreKits_SummaryHeader"), 0, y, w, UIFont.Small, c.accentHi)
        y = y + dividerH + 16
        self.summary:setVisible(true)
        self.summary:setY(y)
        self.summary:setItems(items)
        y = y + self.summary:getHeight() + 30

        self.claimBtn:setX(math.floor((w - BTN_W) / 2))
        self.claimBtn:setY(y)
        return
    end

    local y = 0

    -- ---------- roleta (ou status quando ociosa) + botao -- sem frame ----------
    if self.roulette then
        local rh = self.roulette:getHeight()
        self.roulette:setX(0)
        self.roulette:setY(y)
        self.claimBtn:setX(math.floor((w - BTN_W) / 2))
        self.claimBtn:setY(y + rh + 18)
        y = y + rh + 18 + BTN_H
    else
        local statusH = HardcoreKitsUI.fontH(UIFont.Small)
        local status, statusC = effectiveStatusLine(s)
        HardcoreKitsUI.textCentreFit(self, status, math.floor(w / 2), y, w - 40, UIFont.Small, statusC)
        self.claimBtn:setX(math.floor((w - BTN_W) / 2))
        self.claimBtn:setY(y + statusH + 18)
        y = y + statusH + 18 + BTN_H
    end

    -- ---------- grade de resumo: um cartao por item/skill ja revelado -- sem frame ----------
    if #items > 0 then
        -- volta pro tamanho padrao (2 linhas) -- pode ter ficado maior de um
        -- estado anterior de roleta rapida finalizada (ver acima), e aqui a
        -- roleta/status ainda ocupa espaco em cima, competindo com o resumo.
        self.summary:setRowsVisible(HardcoreKitsSummaryPanel.DEFAULT_ROWS_VISIBLE)
        y = y + 30
        HardcoreKitsUI.leftDivider(self, getText("UI_HardcoreKits_SummaryHeader"), 0, y, w, UIFont.Small, c.accentHi)
        y = y + HardcoreKitsUI.fontH(UIFont.Small) + 16
        self.summary:setVisible(true)
        self.summary:setY(y)
        self.summary:setItems(items)
        y = y + self.summary:getHeight()
    else
        self.summary:setVisible(false)
    end
end
