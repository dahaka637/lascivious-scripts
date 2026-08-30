-- Conteudo da aba "Recompensa por Sobrevivencia" (secao 5.2). Mesmo
-- tratamento visual da aba Kit Inicial: margem e centralizacao, sem
-- frames/bordas encapsulando secoes internas, UMA roleta grande (primeiro
-- revela quantos resultados, depois um passo por resultado -- secao 19.4),
-- resumo final em grade de icones que quebra linha sozinha se precisar.
require "ISUI/ISPanel"
require "HardcoreKits_Protocol"
require "HardcoreKits_Config"
require "HardcoreKits_Theme"
require "HardcoreKits_Widgets"
require "HardcoreKits_Client"
require "HardcoreKits_Window"
require "HardcoreKits_Utils"
require "HardcoreKits_Roulette"

HardcoreKitsTabSurvival = ISPanel:derive("HardcoreKitsTabSurvival")

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
    setmetatable(o, HardcoreKitsTabSurvival)
    HardcoreKitsTabSurvival.__index = HardcoreKitsTabSurvival
    o.background = false
    o.window = window
    o.awaitingReply = false
    o.roulette = nil
    o.lastSeenClaimId = nil
    return o
end

-- SurvivalRewardEnabled fixo em false (bug conhecido, ver HardcoreKits_Config.lua
-- e HardcoreKits_State.lua) -- nem registra a aba, pra ela sumir do menu
-- inteiramente em vez de so aparecer desabilitada.
if HardcoreKitsConfig.SurvivalRewardEnabled == true then
    HardcoreKitsWindow.registerTab({ id = "survival", labelKey = "UI_HardcoreKits_TabSurvival", create = create })
end

function HardcoreKitsTabSurvival:createChildren()
    self.claimBtn = HardcoreKitsButton:new(0, 0, BTN_W, BTN_H, getText("UI_HardcoreKits_BtnClaimReward"), self,
        HardcoreKitsTabSurvival.onClaimClick, "primary")
    self:addChild(self.claimBtn)
    -- grade de resumo com altura fixa de 2 linhas -- vira scroll se tiver mais
    self.summary = HardcoreKitsSummaryPanel:new(0, 0, self.width)
    self.summary:initialise()
    self:addChild(self.summary)
    self.summary:setVisible(false)
    self:refreshButton()
end

function HardcoreKitsTabSurvival:onShow()
    self:refreshButton()
end

-- painel reaberto (fechado -> aberto de novo): uma roleta ja concluida e
-- sobra de uma captura anterior -- descarta pra a aba voltar pro estado
-- normal (status + botao) em vez de exibir uma animacao velha de novo
function HardcoreKitsTabSurvival:onReopen()
    if self.roulette and self.roulette.finished then
        self:removeChild(self.roulette)
        self.roulette = nil
    end
end

function HardcoreKitsTabSurvival:onClaimClick()
    if self.awaitingReply then return end
    self.awaitingReply = true
    self.awaitingSince = getTimestampMs()
    HardcoreKitsClient.requestSurvivalClaim()
    self:refreshButton()
end

function HardcoreKitsTabSurvival:startRoulette(rolledList)
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
    -- modo roleta rapida (pedido explicito do usuario, vale pra Recompensa
    -- de Sobrevivencia tambem): mesma interface externa
    -- (:new(x,y,w,h,steps,onAllDone), campos .finished/.isFastRunner), so
    -- troca QUAL classe gira -- ver HardcoreKitsRouletteFastRunner em
    -- HardcoreKits_Roulette.lua.
    local fastMode = HardcoreKitsConfig.FastRouletteMode == true
    local steps = HardcoreKitsRoulette.buildSurvivalSteps(rolledList, fastMode)
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
    -- Registra no ticker global (HardcoreKits_Roulette.lua) -- garante que o
    -- sorteio continua avancando de verdade mesmo com a janela do /kit
    -- fechada (pedido explicito do usuario). Desregistrado sozinho quando o
    -- proprio runner termina.
    HardcoreKitsRoulette.register(runner)
end

function HardcoreKitsTabSurvival:onStateUpdated()
    local started = HardcoreKitsClient.lastClaimStarted
    if started and started.claimType == HardcoreKits.CLAIM_TYPE_SURVIVAL
        and started.claimId ~= self.lastSeenClaimId then
        self.lastSeenClaimId = started.claimId
        self.awaitingReply = false
        self:startRoulette(started.rolled)
    end
    if self.awaitingReply then
        local err = HardcoreKitsClient.lastClaimError
        if err and err.claimType == HardcoreKits.CLAIM_TYPE_SURVIVAL then
            self.awaitingReply = false
        end
    end
    self:refreshButton()
end

function HardcoreKitsTabSurvival:refreshButton()
    local s = HardcoreKitsClient.state
    local label, enabled = getText("UI_HardcoreKits_BtnClaimReward"), false

    if self.awaitingReply or (self.roulette and not self.roulette.finished) then
        label, enabled = getText("UI_HardcoreKits_BtnClaiming"), false
    elseif s then
        if s.survivalRewardAvailableNow then
            enabled = true
            if (s.survivalRewardsAvailable or 0) > 1 then
                label = getText("UI_HardcoreKits_BtnClaimRewardCount", s.survivalRewardsAvailable)
            end
        elseif not s.survivalRewardEnabled then
            label = getText("UI_HardcoreKits_BtnUnavailable")
        else
            label = getText("UI_HardcoreKits_BtnNotEarnedYet")
        end
    else
        label = getText("UI_HardcoreKits_BtnSyncing")
    end

    self.claimBtn:setLabel(label)
    self.claimBtn:setEnabled(enabled)
end

-- 2 linhas compactas: progresso atual + proximo marco (a segunda some quando
-- ha recompensa disponivel agora, sem sentido mostrar "proxima em" junto)
local function statusLines(s)
    local c = HardcoreKitsUI.col
    if not s then return { { getText("UI_HardcoreKits_StatusSyncing"), c.muted } } end

    local days = math.floor((s.hoursSurvived or 0) / 24)
    local lines = {}
    local available = s.survivalRewardsAvailable or 0
    if available > 0 then
        local capNote = ""
        if s.survivalMaxStoredRewards and s.survivalMaxStoredRewards > 0 and available >= s.survivalMaxStoredRewards then
            capNote = getText("UI_HardcoreKits_StatusSurvivalCapNote")
        end
        table.insert(lines, { getText("UI_HardcoreKits_StatusSurvivalAvailable", available, capNote, days), c.ok })
    else
        table.insert(lines, { getText("UI_HardcoreKits_StatusSurvivalDay", days), c.text })
        local nextIn = HardcoreKitsClient.liveRemaining("survivalNextRewardInSeconds")
        table.insert(lines, { getText("UI_HardcoreKits_StatusSurvivalNextIn", HardcoreKitsUtils.formatDuration(nextIn)), c.muted })
    end
    return lines
end

-- mesma ideia da aba Kit Inicial: por alguns segundos, motivos de erro sem
-- equivalente no state (morto, resgate ja em andamento, falha na entrega)
-- substituem as linhas normais -- depois volta sozinho pro statusLines(s)
local ERROR_DISPLAY_MS = 5000
local function effectiveStatusLines(s)
    local notice = HardcoreKitsClient.lastClaimNotice
    if notice and notice.claimType == HardcoreKits.CLAIM_TYPE_SURVIVAL and HardcoreKitsClient.lastClaimNoticeAtMs
        and getTimestampMs() - HardcoreKitsClient.lastClaimNoticeAtMs < ERROR_DISPLAY_MS then
        local text = HardcoreKitsUI.claimNoticeText(notice.reason)
        if text then return { { text, HardcoreKitsUI.col.danger } } end
    end
    local err = HardcoreKitsClient.lastClaimError
    if err and err.claimType == HardcoreKits.CLAIM_TYPE_SURVIVAL and HardcoreKitsClient.lastClaimErrorAtMs
        and getTimestampMs() - HardcoreKitsClient.lastClaimErrorAtMs < ERROR_DISPLAY_MS then
        local text = HardcoreKitsUI.claimErrorText(err.reason)
        if text then return { { text, HardcoreKitsUI.col.danger } } end
    end
    return statusLines(s)
end

function HardcoreKitsTabSurvival:prerender()
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
        local lines = effectiveStatusLines(s)
        local ly = y
        for _, l in ipairs(lines) do
            HardcoreKitsUI.textCentreFit(self, l[1], math.floor(w / 2), ly, w - 40, UIFont.Small, l[2])
            ly = ly + HardcoreKitsUI.fontH(UIFont.Small) + 4
        end
        self.claimBtn:setX(math.floor((w - BTN_W) / 2))
        self.claimBtn:setY(ly + 14)
        y = ly + 14 + BTN_H
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
