-- Mini overlay opcional (HardcoreKitsConfig.RouletteOverlayEnabled, ligado
-- por padrao) que aparece no canto superior direito enquanto um sorteio
-- continua rolando em segundo plano com a janela do /kit FECHADA -- pedido
-- explicito do usuario, pra deixar claro que fechar a janela nao interrompe
-- o resgate (ver o ticker global em HardcoreKits_Roulette.lua, que e o que
-- realmente garante isso -- este arquivo e so a pontinha visivel).
--
-- So mostra o ULTIMO item/skill que ja caiu (HardcoreKitsRoulette.
-- lastLandedEntry), sem animar o giro em si -- "so o que caiu, ja pula pra
-- proxima" (pedido explicito). Some por completo assim que o servidor
-- confirma a entrega de verdade (CMD_CLAIM_RESULT, via
-- HardcoreKitsClient.lastClaimResult -- nao o mero fim da animacao, que e um
-- instante antes), e da lugar a um aviso verde curto por 3 segundos.
--
-- Singleton igual a HardcoreKitsWindow -- criado uma vez, so alterna
-- visibilidade dali pra frente, entao a posicao arrastada pelo jogador
-- sobrevive pro resto da sessao sem precisar de nenhuma logica extra.
require "ISUI/ISPanel"
require "HardcoreKits_Theme"
require "HardcoreKits_Config"
require "HardcoreKits_Client"
require "HardcoreKits_Roulette"

local previousOverlayClass = HardcoreKitsRouletteOverlay
local previousOverlay = previousOverlayClass and previousOverlayClass.instance
if previousOverlayClass and previousOverlayClass._gameStartHandler and Events.OnGameStart.Remove then
    Events.OnGameStart.Remove(previousOverlayClass._gameStartHandler)
end
if previousOverlay then
    pcall(function()
        previousOverlay:setVisible(false)
        if previousOverlay.removeFromUIManager then previousOverlay:removeFromUIManager() end
    end)
end

HardcoreKitsRouletteOverlay = ISPanel:derive("HardcoreKitsRouletteOverlay")
HardcoreKitsRouletteOverlay.instance = nil

local W, H = 220, 78
local TOAST_MS = 3000
local FADE_MS = 500

function HardcoreKitsRouletteOverlay:new(x, y)
    local o = ISPanel:new(x, y, W, H)
    setmetatable(o, self)
    self.__index = self
    o.background = false
    o.dragging = false
    o.activeClaimId = nil
    o.lastSeenStartedClaimId = nil
    o.toastUntilMs = 0
    o.mode = "roulette"
    o.toastPartial = false
    return o
end

-- Estado (nao desenho) -- roda TODO frame mesmo com o painel invisivel
-- (diferente de :prerender(), ver o comentario grande em
-- HardcoreKits_Roulette.lua sobre essa distincao; mesmo padrao ja usado por
-- LFS_Ticker.lua neste mod), o que e essencial aqui: precisa continuar
-- detectando "um sorteio comecou"/"a entrega terminou" mesmo enquanto o
-- proprio overlay esta escondido (ex: com a janela do /kit aberta).
function HardcoreKitsRouletteOverlay:update()
    local now = getTimestampMs()

    local started = HardcoreKitsClient.lastClaimStarted
    if started and started.claimId ~= self.lastSeenStartedClaimId then
        self.lastSeenStartedClaimId = started.claimId
        self.activeClaimId = started.claimId
    end

    local result = HardcoreKitsClient.lastClaimResult
    if self.activeClaimId and result and result.claimId == self.activeClaimId then
        self.activeClaimId = nil
        self.toastPartial = result.partial == true or result.status == "completed_partial"
        -- Aviso verde so faz sentido se a janela principal NAO estava aberta
        -- (se estava, o resumo de verdade ja apareceu la na hora -- um aviso
        -- aqui em cima seria redundante). "Coisa sutil", pedido explicito.
        if not HardcoreKitsRoulette.isWindowVisible() then
            self.toastUntilMs = now + TOAST_MS
        end
    end

    local showRoulette = HardcoreKitsConfig.RouletteOverlayEnabled == true
        and self.activeClaimId ~= nil
        and not HardcoreKitsRoulette.isWindowVisible()
    local showToast = now < self.toastUntilMs
    self.mode = showToast and "toast" or "roulette"

    local visible = showRoulette or showToast
    if visible ~= self:isVisible() then self:setVisible(visible) end
end

function HardcoreKitsRouletteOverlay:onMouseDown(x, y)
    self.dragging = true
    self:bringToTop()
end
function HardcoreKitsRouletteOverlay:onMouseMove(dx, dy)
    if self.dragging then
        self:setX(self.x + dx)
        self:setY(self.y + dy)
    end
end
function HardcoreKitsRouletteOverlay:onMouseMoveOutside(dx, dy) self:onMouseMove(dx, dy) end
function HardcoreKitsRouletteOverlay:onMouseUp(x, y) self.dragging = false end
function HardcoreKitsRouletteOverlay:onMouseUpOutside(x, y) self.dragging = false end

function HardcoreKitsRouletteOverlay:render()
    local c = HardcoreKitsUI.col
    local w, h = self.width, self.height

    -- Pedido explicito do usuario: sem caixa/moldura nenhuma por tras -- so
    -- o texto e os cartoes de item/skill flutuando direto sobre o jogo, pra
    -- ficar bem discreto no canto da tela.
    if self.mode == "toast" then
        -- desvanece so no ultimo meio segundo -- "some" gradual, nao um corte seco
        local remaining = self.toastUntilMs - getTimestampMs()
        local a = (remaining < FADE_MS) and math.max(0, remaining / FADE_MS) or 1
        local key = self.toastPartial and "UI_HardcoreKits_PartialDelivery" or "UI_HardcoreKits_OverlayDelivered"
        local color = self.toastPartial and c.danger or c.ok
        HardcoreKitsUI.textCentreFit(self, getText(key), math.floor(w / 2),
            math.floor((h - HardcoreKitsUI.fontH(UIFont.Small)) / 2), w - 12, UIFont.Small, color, a)
        return
    end

    HardcoreKitsUI.textCentreFit(self, getText("UI_HardcoreKits_OverlayRolling"), math.floor(w / 2), 8,
        w - 16, UIFont.Small, c.muted)

    local entry = HardcoreKitsRoulette.lastLandedEntry
    local cardSize = h - 32
    local cardX = math.floor((w - cardSize) / 2)
    local cardY = 8 + HardcoreKitsUI.fontH(UIFont.Small) + 6
    if entry then
        if entry.kind == "skill" then
            HardcoreKitsUI.skillCard(self, math.floor((w - HardcoreKitsUI.skillCardWidth(entry.groupText, entry.tierText)) / 2),
                cardY, HardcoreKitsUI.skillCardWidth(entry.groupText, entry.tierText), cardSize,
                entry.groupText, entry.tierText, entry.tierColor)
        else
            HardcoreKitsUI.itemCard(self, cardX, cardY, cardSize, cardSize, entry.fullType, entry.qty)
        end
    end
end

local function ensureCreated()
    if HardcoreKitsRouletteOverlay.instance then return end
    local sw = getCore():getScreenWidth()
    -- Y inicial um pouco mais pra baixo que o topo -- pedido explicito do
    -- usuario, deixa de folga pro canto superior direito onde o jogo/outros
    -- mods costumam por icones/indicadores. So a posicao DE PARTIDA -- depois
    -- disso o jogador pode arrastar pra onde quiser (ver :onMouseMove acima),
    -- e a posicao arrastada persiste pro resto da sessao (singleton, nunca
    -- recriado).
    local o = HardcoreKitsRouletteOverlay:new(sw - W - 16, 90)
    o:initialise()
    o:addToUIManager()
    o:setVisible(false)
    HardcoreKitsRouletteOverlay.instance = o
end
HardcoreKitsRouletteOverlay._gameStartHandler = ensureCreated
Events.OnGameStart.Add(ensureCreated)
if previousOverlay then pcall(ensureCreated) end
