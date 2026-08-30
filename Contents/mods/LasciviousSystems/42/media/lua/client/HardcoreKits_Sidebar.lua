-- Botao de icone na barra lateral esquerda (a mesma do Inventario/Saude/
-- Construcao/Mapa/Admin etc -- vanilla ISUI/ISEquippedItem.lua), pra abrir o
-- /kit sem depender do chat -- pedido explicito do usuario, principalmente
-- pro singleplayer, que nao tem chat de jogador de verdade (ver
-- HardcoreKits_Welcome.lua). So aparece quando ha algo pra resgatar.
--
-- Vanilla nao expoe nenhum hook de mod dentro de ISEquippedItem:initialise()/
-- :render() -- a unica forma de acrescentar um botao nessa barra e "abrir"
-- as duas funcoes por cima (guarda a original, chama ela primeiro, so
-- depois acrescenta o nosso por cima) -- encadeamento padrao de mod Lua,
-- compoe certo mesmo se outro mod fizer a mesma coisa.
require "ISUI/ISEquippedItem"
require "HardcoreKits_Config"
require "HardcoreKits_Client"
require "HardcoreKits_Window"

HardcoreKitsSidebarHooks = HardcoreKitsSidebarHooks or {}
local hookRegistry = HardcoreKitsSidebarHooks
if hookRegistry.refreshTick then
    if Events.OnTick.Remove then Events.OnTick.Remove(hookRegistry.refreshTick) end
    hookRegistry.refreshTick = nil
end
local initialiseCanWrap = true
if hookRegistry.initialiseWrapper then
    if ISEquippedItem.initialise == hookRegistry.initialiseWrapper then
        ISEquippedItem.initialise = hookRegistry.initialiseBase
        hookRegistry.initialiseWrapper, hookRegistry.initialiseBase = nil, nil
    else
        initialiseCanWrap = false
    end
end
local renderCanWrap = true
if hookRegistry.renderWrapper then
    if ISEquippedItem.render == hookRegistry.renderWrapper then
        ISEquippedItem.render = hookRegistry.renderBase
        hookRegistry.renderWrapper, hookRegistry.renderBase = nil, nil
    else
        renderCanWrap = false
    end
end

-- NAO checar HardcoreKitsConfig.SidebarButtonEnabled aqui no topo do arquivo:
-- esse valor so reflete o sandbox de verdade depois de
-- HardcoreKitsSandboxBridge.apply() rodar (Events.OnGameStart/OnServerStarted),
-- que acontece DEPOIS de todo arquivo terminar de carregar -- checar aqui
-- pegaria sempre o default hardcoded de HardcoreKits_Config.lua, nunca o
-- valor que o dono do servidor configurou. A checagem de verdade fica dentro
-- de render() abaixo, que so roda muito depois (todo frame, pra sempre) --
-- ali o sandbox ja com certeza foi aplicado.
local UI_BORDER_SPACING = 10 -- mesmo valor local (nao exportado) de ISEquippedItem.lua

-- mesma logica de ISEquippedItem.lua:setTextureWidth() (tambem local, nao
-- exportada) -- replicada aqui pra bater exatamente com o tamanho de icone
-- que o jogador escolheu nas opcoes (Sidebar Size). Note que a altura NAO e
-- igual a largura (0.75x) -- os botoes vanilla sao retangulares, nao quadrados.
local function currentIconSize()
    local size = getCore():getOptionSidebarSize()
    if size == 6 then
        size = getCore():getOptionFontSizeReal() - 1
    end
    local w = 48
    if size == 2 then w = 64
    elseif size == 3 then w = 80
    elseif size == 4 then w = 96
    elseif size == 5 then w = 128
    end
    return w, w * 0.75
end

-- pega o maior :getBottom() dentre todos os icones de botao ja criados --
-- usado so pra recalcular a altura final do painel (self:setHeight()) depois
-- de inserir e deslocar botoes abaixo. Percorre self.childrenInOrder (lista
-- real de filhos que ISUIElement:addChild ja preenche, na ordem em que foram
-- adicionados -- ver ISUIElement.lua), filtrando por `.internal` (toda vez
-- que a barra cria um ISButton de icone, ela seta esse campo com uma string,
-- ex: self.healthBtn.internal = "HEALTH" -- ver ISEquippedItem.lua) pra
-- ignorar elementos que NAO sao icones de botao (self.mainHand/offHand sao
-- ISImage, self.movableTooltip/movablePopup/mapPopup/radialIcon sao helpers
-- com geometria propria que nao bate com a dos botoes -- incluir eles
-- inflaria o calculo e criaria exatamente o espacamento errado que
-- queremos evitar).
local function lastButtonBottom(self)
    local maxBottom = 0
    for _, child in ipairs(self.childrenInOrder or {}) do
        if child.internal and child.getBottom then
            local bottom = child:getBottom()
            if bottom > maxBottom then maxBottom = bottom end
        end
    end
    return maxBottom
end

-- igual a lastButtonBottom acima, mas devolve o proprio botao (nao so a
-- posicao) -- usado pra deslocar so ESSE UM botao pra baixo, ao inves de
-- inserir logo apos crafting e deslocar a lista inteira (posicao anterior,
-- "muito para cima" no relato do usuario -- pediu penultimo/ultimo)
local function findLastButton(self)
    local last, maxBottom = nil, -1
    for _, child in ipairs(self.childrenInOrder or {}) do
        if child.internal and child.getBottom then
            local bottom = child:getBottom()
            if bottom > maxBottom then
                maxBottom = bottom
                last = child
            end
        end
    end
    return last
end

local function onKitButtonClick()
    HardcoreKitsWindow.toggle()
end

local origInitialise = ISEquippedItem.initialise
local function wrappedInitialise(self)
    origInitialise(self)

    -- a barra de botoes inteira (inv/saude/etc) so existe pro jogador 0 (o
    -- cliente local) -- ver ISEquippedItem.lua, tudo dentro de
    -- "if self.chr:getPlayerNum() == 0 then"
    if not self.chr or self.chr:getPlayerNum() ~= 0 then return end

    local w, h = currentIconSize()
    -- mesmo espacamento que a vanilla usa entre TODOS os seus proprios
    -- botoes (ver ISEquippedItem.lua: "y = X:getBottom() + UI_BORDER_SPACING
    -- + 5", repetido identico a cada botao) -- usar o mesmo valor aqui faz
    -- o nosso icone encaixar sem nenhuma folga/aperto diferente do resto
    local shiftAmount = h + UI_BORDER_SPACING + 5

    -- posiciona o kit como PENULTIMO icone: pega o botao que hoje e o
    -- ultimo da lista e empurra so ELE (nao a lista inteira) pra baixo, daí
    -- insere o nosso no lugar que ele deixou -- fica perto do fim (como
    -- pedido, "ultimo ou penultimo") mas sem afundar tudo depois de crafting
    -- (posicao anterior, "muito pra cima" no relato do usuario)
    local lastBtn = findLastButton(self)
    local y = 0
    if lastBtn then
        y = lastBtn:getY()
        lastBtn:setY(lastBtn:getY() + shiftAmount)

        -- mesmo problema de sempre: tooltip/popup/radialIcon guardam a
        -- posicao do botao DONO so no instante da criacao, nao acompanham
        -- sozinhos se ele se mover depois -- so importa aqui se o botao que
        -- acabamos de empurrar for justamente movable/map/safety
        if lastBtn == self.movableBtn then
            if self.movableTooltip then self.movableTooltip:setY(self.movableTooltip:getY() + shiftAmount) end
            if self.movablePopup then self.movablePopup:setY(self.movablePopup:getY() + shiftAmount) end
        elseif lastBtn == self.mapBtn and self.mapPopup then
            self.mapPopup:setY(self.mapPopup:getY() + shiftAmount)
        elseif lastBtn == self.safetyBtn and self.radialIcon then
            self.radialIcon:setY(self.radialIcon:getY() + shiftAmount)
        end
    end

    self.hkKitBtn = ISButton:new(0, y, w, h, "", self, onKitButtonClick)
    self.hkKitBtn:setImage(getTexture("media/ui/HardcoreKits/kit_icon.png"))
    self.hkKitBtn.internal = "HARDCOREKITS"
    self.hkKitBtn:initialise()
    self.hkKitBtn:instantiate()
    self.hkKitBtn:setDisplayBackground(false)
    self.hkKitBtn:ignoreWidthChange()
    self.hkKitBtn:ignoreHeightChange()
    self.hkKitBtn:setVisible(false) -- comeca escondido ate o primeiro state chegar
    self._hkKitVisible = false
    self:addChild(self.hkKitBtn)
    self:addMouseOverToolTipItem(self.hkKitBtn, getText("UI_HardcoreKits_WindowTitle"))

    self:setHeight(lastButtonBottom(self))
    self:shrinkWrap()

    HardcoreKitsClient.requestState()
end
if initialiseCanWrap then
    hookRegistry.initialiseBase = origInitialise
    hookRegistry.initialiseWrapper = wrappedInitialise
    ISEquippedItem.initialise = wrappedInitialise
end

-- Rastreia um resgate em andamento (sorteado mas ainda nao entregue de
-- verdade no inventario) -- pedido explicito do usuario: o botao NAO pode
-- sumir so porque o sorteio comecou (state.initialKitAvailable ja vira false
-- no instante do sorteio, MUITO antes da entrega real -- ver
-- HardcoreKits_Server.lua, "trava JA, aqui, no instante do sorteio"). Sem
-- isto, o refresh periodico abaixo (a cada 30s, e a animacao da roleta pode
-- levar 40-90s) buscava um state ja "indisponivel" no meio do giro e o botao
-- sumia antes dos itens chegarem no inventario de verdade.
--
-- Modulo-level (nao por instancia de ISEquippedItem) de proposito -- mesmo
-- padrao que HardcoreKitsClient.lastClaimStarted/lastClaimResult ja usam
-- (tambem modulo-level), e so ha uma transacao pendente por personagem de
-- qualquer forma.
local activeClaimId = nil
local lastSeenStartedClaimId = nil

local function claimInProgress()
    local started = HardcoreKitsClient.lastClaimStarted
    if started and started.claimId ~= lastSeenStartedClaimId then
        lastSeenStartedClaimId = started.claimId
        activeClaimId = started.claimId
    end
    if activeClaimId then
        local result = HardcoreKitsClient.lastClaimResult
        if result and result.claimId == activeClaimId then
            activeClaimId = nil
        end
        -- "dead" e definitivo (HardcoreKitsTransactions.abandonDead, servidor
        -- nunca tenta de novo -- personagem morreu antes da entrega) --
        -- diferente de "delivery_failed" (recovery_required), que pode exigir
        -- retry seguro ou intervencao admin -- o botao continua visivel para o
-- jogador consultar o estado sem perder a referencia do resgate.
        local err = HardcoreKitsClient.lastClaimError
        if err and err.reason == "dead" then
            activeClaimId = nil
        end
    end
    return activeClaimId ~= nil
end

-- visibilidade dinamica, recalculada todo frame -- mesma tecnica que o
-- proprio botao de admin vanilla usa (:setVisible em render(), ver
-- ISEquippedItem.lua). Aparece quando HA algo pra resgatar (Kit Inicial
-- disponivel OU Recompensa de Sobrevivencia disponivel agora) OU um resgate
-- ja sorteado ainda esta esperando a entrega de verdade -- pedido explicito
-- do usuario. Personagem que ja resgatou o Kit Inicial (ou conta que ja
-- consumiu o Kit unico, ver HardcoreKits_Persistence.lua) e sem recompensa por
-- dias sobrevividos pendente e sem nada em andamento = botao some.
local origRender = ISEquippedItem.render
local function wrappedRender(self)
    origRender(self)
    if not self.hkKitBtn then return end
    if HardcoreKitsConfig.SidebarButtonEnabled ~= true then
        if self._hkKitVisible ~= false then
            self.hkKitBtn:setVisible(false)
            self._hkKitVisible = false
        end
        return
    end
    local s = HardcoreKitsClient.state
    local available = s ~= nil and (s.initialKitAvailable == true or s.survivalRewardAvailableNow == true)
    local visible = available or claimInProgress()
    if self._hkKitVisible ~= visible then
        self.hkKitBtn:setVisible(visible)
        self._hkKitVisible = visible
    end
end
if renderCanWrap then
    hookRegistry.renderBase = origRender
    hookRegistry.renderWrapper = wrappedRender
    ISEquippedItem.render = wrappedRender
end

-- HardcoreKitsClient.state so e preenchido sob demanda (quando o painel
-- /kit e aberto, ou pelo auto-open) -- sem isso, o botao nunca saberia se
-- deve aparecer antes do jogador interagir com o mod pela primeira vez.
-- Pede um refresh periodico (nao a cada frame, pra nao floodar o servidor
-- de comando) -- mantem a visibilidade certa ao longo do tempo tambem (ex:
-- recompensa de sobrevivencia fica disponivel depois de X dias, sem o
-- jogador ter feito nada nesse meio tempo).
local REFRESH_INTERVAL_MS = 30000
local lastRefreshAtMs = 0
local function refreshStatePeriodically()
    if not ISEquippedItem.instance or not ISEquippedItem.instance.hkKitBtn then return end
    local now = getTimestampMs()
    if now - lastRefreshAtMs < REFRESH_INTERVAL_MS then return end
    lastRefreshAtMs = now
    HardcoreKitsClient.requestState()
end
hookRegistry.refreshTick = refreshStatePeriodically
Events.OnTick.Add(refreshStatePeriodically)
