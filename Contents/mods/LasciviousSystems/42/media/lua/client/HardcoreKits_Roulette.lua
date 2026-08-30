-- Roleta visual (secao 19 da especificacao). O resultado JA chegou fixado
-- do servidor em CMD_CLAIM_STARTED -- tudo neste arquivo e puramente
-- cosmetico, nenhum decoy jamais e entregue de verdade.
--
-- v2: uma UNICA roleta grande por aba (nao mais 5-6 lado a lado). Ela troca
-- de titulo e de sequencia a cada sorteio, ficando bem maior e mais legivel.
-- A faixa tem cartas ANTES e DEPOIS do item vencedor (nao so antes) pra dar
-- sensacao de fita continua/infinita, em vez de parecer que "a sorte" foi so
-- o ultimo card da lista acabar sendo o premio.
require "ISUI/ISPanel"
require "ISUI/ISInventoryItem"
require "HardcoreKits_Theme"
require "HardcoreKits_Config"
require "HardcoreKits_Pools"
require "HardcoreKits_Utils"

HardcoreKitsRoulette = HardcoreKitsRoulette or {}
if HardcoreKitsRoulette._globalTick and Events.OnTick.Remove then
    Events.OnTick.Remove(HardcoreKitsRoulette._globalTick)
end

-- ==================================================================
-- Ticker global, INDEPENDENTE da janela estar visivel -- pedido explicito do
-- usuario: fechar a janela do /kit no meio de um sorteio nao pode parar a
-- roleta. ISUIElement:prerender() so roda pra elementos VISIVEIS (por isso a
-- roleta "pausava" ao fechar a janela antes desta mudanca -- ela era filha da
-- aba, filha da janela, e parava de ser desenhada com o resto). :update(),
-- ao contrario, roda todo frame independente de visibilidade (mesmo padrao ja
-- usado por LFS_Ticker.lua neste mod) -- mas o widget/runner da roleta nao e
-- um elemento top-level adicionado direto ao UIManager, entao mesmo
-- :update() nao seria chamado nele enquanto filho de uma janela escondida.
-- Solucao: um Events.OnTick proprio, registrado uma unica vez aqui (nao preso
-- a elemento nenhum), que chama :tick() em cada instancia ativa diretamente
-- via referencia Lua -- nunca depende da arvore do UIManager pra continuar
-- avancando.
--
-- Tabela de chave FRACA (nunca impede coleta de lixo de uma instancia
-- descartada sem querer sem passar por unregister).
local activeInstances = HardcoreKitsRoulette._activeInstances
if type(activeInstances) ~= "table" then
    activeInstances = setmetatable({}, { __mode = "k" })
    HardcoreKitsRoulette._activeInstances = activeInstances
end
local activeCount = 0
for _ in pairs(activeInstances) do activeCount = activeCount + 1 end

function HardcoreKitsRoulette.register(instance)
    if not instance or activeInstances[instance] then return end
    activeInstances[instance] = true
    activeCount = activeCount + 1
end

function HardcoreKitsRoulette.unregister(instance)
    if not instance or not activeInstances[instance] then return end
    activeInstances[instance] = nil
    activeCount = math.max(0, activeCount - 1)
end

-- true so quando a JANELA principal do /kit esta aberta e visivel -- usado
-- tanto pra decidir se toca som (nao faz sentido tocar tique de roleta com a
-- janela fechada) quanto pelo overlay (HardcoreKits_RouletteOverlay.lua) pra
-- saber quando se mostrar. HardcoreKitsWindow e um global (carregado por
-- HardcoreKits_Window.lua, que roda antes deste arquivo em qualquer fluxo
-- real -- ambos sao exigidos pelas abas) -- sem require direto aqui pra nao
-- criar uma dependencia circular de carregamento, so precisa existir na hora
-- de CHAMAR isto, nao na hora deste arquivo carregar.
function HardcoreKitsRoulette.isWindowVisible()
    return HardcoreKitsWindow ~= nil and HardcoreKitsWindow.instance ~= nil
        and HardcoreKitsWindow.instance:isVisible()
end

-- Ultimo passo "pousado" (com item/skill de verdade -- nunca um passo-meta
-- como "quantos resultados?" ou um "X" de sem-sorte) de QUALQUER roleta ativa
-- -- lido pelo overlay pra mostrar o que acabou de cair. Atualizado por
-- HardcoreKitsRouletteWidget:tick() (usado tanto pela roleta normal quanto,
-- individualmente, por cada reel do modo rapido -- ver
-- HardcoreKitsRouletteFastRunner:tick() mais abaixo, que chama :tick() em
-- cada reel-filho diretamente).
if HardcoreKitsRoulette.lastLandedAtMs == nil then HardcoreKitsRoulette.lastLandedAtMs = 0 end

local function noteLanded(step)
    if not step or not step.winner then return end
    local kind = step.winner.kind
    if (kind == "item" and step.winner.fullType) or kind == "skill" then
        HardcoreKitsRoulette.lastLandedEntry = step.winner
        HardcoreKitsRoulette.lastLandedAtMs = getTimestampMs()
    end
end

local function globalTick()
    if activeCount <= 0 then return end
    -- copia as chaves antes de iterar: :tick() pode registrar/desregistrar
    -- instancias (FastRunner troca de lote, widget termina e chama
    -- onAllDone) -- mutar activeInstances durante o proprio pairs() dela e
    -- undefined behaviour em Lua.
    local batch = {}
    for instance in pairs(activeInstances) do table.insert(batch, instance) end
    if #batch == 0 then
        activeCount = 0 -- chaves fracas podem ter sido coletadas sem unregister
        return
    end
    for _, instance in ipairs(batch) do
        if activeInstances[instance] then
            local ok, err = pcall(instance.tick, instance)
            if not ok then
                print("[HardcoreKits] roleta: erro no tick em segundo plano: " .. tostring(err))
                HardcoreKitsRoulette.unregister(instance)
            end
        end
    end
end
HardcoreKitsRoulette._globalTick = globalTick
Events.OnTick.Add(globalTick)

-- ==================================================================
-- HardcoreKitsRouletteWidget: a roleta em si. Uma instancia so, reconfigurada
-- a cada passo (titulo + sequencia trocam, o widget continua o mesmo).
-- entry = { kind="item", fullType=, qty= } ou { kind="label", text= }
-- ==================================================================
HardcoreKitsRouletteWidget = ISPanel:derive("HardcoreKitsRouletteWidget")

local CARD_W = 92
local CARD_GAP = 12
local STEP_PX = CARD_W + CARD_GAP
local DECOY_BEFORE = 12
local DECOY_AFTER = 8 -- cartas depois do vencedor -- e o que da a sensacao de fita infinita
local WINNER_INDEX = DECOY_BEFORE + 1

local function easeOutCubic(t)
    local f = t - 1
    return f * f * f + 1
end

local function buildSequence(entries, winnerEntry)
    local seq = {}
    if entries and #entries > 0 then
        for _ = 1, DECOY_BEFORE do table.insert(seq, HardcoreKitsUtils.pick(entries)) end
        table.insert(seq, winnerEntry)
        for _ = 1, DECOY_AFTER do table.insert(seq, HardcoreKitsUtils.pick(entries)) end
    else
        -- pool vazio (config quebrada) -- so o vencedor, sem decoys
        table.insert(seq, winnerEntry)
    end
    return seq
end

-- steps: lista de { label, pool (lista de entries), winner (entry), highlight=, fail=, durationMs= }
function HardcoreKitsRouletteWidget:new(x, y, w, h, steps, onAllDone)
    local o = ISPanel:new(x, y, w, h)
    setmetatable(o, self)
    self.__index = self
    o.background = false
    o.steps = steps
    o.onAllDone = onAllDone
    o.stepIndex = 0
    o.state = "idle" -- idle | spinning | landed | done
    o.progress = 0
    o.sequence = {}
    o.title = ""
    o.finished = false
    o.lastTickIndex = nil
    return o
end

function HardcoreKitsRouletteWidget:createChildren()
    self:advance()
end

-- avanca pro proximo passo da fila (chamado no inicio e apos a pausa pos-pouso)
function HardcoreKitsRouletteWidget:advance()
    self.stepIndex = self.stepIndex + 1
    local step = self.steps[self.stepIndex]
    if not step then
        self.finished = true
        self.state = "done"
        -- so desregistra a instancia TOP-LEVEL (a que HardcoreKitsTabInitial/
        -- Survival registraram explicitamente em startRoulette) -- reels
        -- individuais do modo rapido nunca foram registrados aqui (ver
        -- HardcoreKitsRouletteFastRunner:tick(), que os chama direto), entao
        -- isto e um no-op inofensivo pra eles.
        HardcoreKitsRoulette.unregister(self)
        if self.onAllDone then self.onAllDone() end
        return
    end
    self.currentStep = step
    self.title = step.label or ""
    self.sequence = buildSequence(step.pool, step.winner)
    -- self.ignoreSpeedMultiplier: usado pelas roletas pequenas do modo rapido
    -- (HardcoreKitsRouletteFastRunner) -- o giro rapido tem que durar
    -- EXATAMENTE FastRouletteStepDurationMs, sem o multiplicador de
    -- velocidade normal (RouletteSpeedMultiplier) interferindo, pedido
    -- explicito do usuario ("sobrepoe a configuracao da velocidade da roleta").
    local speed = self.ignoreSpeedMultiplier and 1.0 or math.max(0.1, HardcoreKitsConfig.RouletteSpeedMultiplier or 1.0)
    self.durationMs = (step.durationMs or HardcoreKitsConfig.RouletteStepDurationMs or 2200) / speed
    self.progress = 0
    self.startedAtMs = getTimestampMs()
    self.state = "spinning"
    self.lastTickIndex = nil
end

-- Estado da roleta -- SEM nenhum desenho aqui. Chamado pelo ticker global
-- (globalTick, acima), independente da janela estar visivel -- e o que
-- permite a roleta continuar sorteando de verdade com a interface fechada
-- (pedido explicito do usuario). O timing e todo baseado em getTimestampMs()
-- (relogio real, nao um contador incremental por chamada), entao um "gap"
-- de chamadas nao acumula atraso nenhum -- so nao ha NADA fazendo esse
-- calculo enquanto a janela esta escondida, o que este ticker corrige.
function HardcoreKitsRouletteWidget:tick()
    if self.state == "spinning" then
        local elapsed = getTimestampMs() - self.startedAtMs
        local t = math.min(1, elapsed / math.max(1, self.durationMs))
        self.progress = easeOutCubic(t)

        -- indice da carta mais proxima do ponteiro agora -- toca um tick
        -- quando ela muda. A cadencia desacelera sozinha porque o progress
        -- desacelera (mesma curva de easing), sem precisar de um timer a parte
        -- (o efeito "CS:GO": rapido no comeco, espacando conforme se aproxima)
        -- Som so toca com a janela principal REALMENTE visivel -- nao faz
        -- sentido ficar tocando tique de roleta com a interface fechada.
        local approxIndex = 1 + math.floor(self.progress * (WINNER_INDEX - 1) + 0.5)
        if approxIndex ~= self.lastTickIndex then
            self.lastTickIndex = approxIndex
            if HardcoreKitsRoulette.isWindowVisible() then HardcoreKitsUI.tickSound() end
        end

        if t >= 1 then
            self.state = "landed"
            self.landedAtMs = getTimestampMs()
            if HardcoreKitsRoulette.isWindowVisible() then HardcoreKitsUI.sound() end
            noteLanded(self.currentStep)
        end
    elseif self.state == "landed" then
        local pause = HardcoreKitsConfig.RoulettePauseBetweenMs or 1000
        if getTimestampMs() - self.landedAtMs >= pause then
            self:advance()
        end
    end
end

function HardcoreKitsRouletteWidget:renderCard(entry, x, y, w, h, isWinner)
    local c = HardcoreKitsUI.col
    if isWinner then HardcoreKitsUI.glow(self, x, y, w, h, 7, 0.14, c.accent) end
    HardcoreKitsUI.roundFrame(self, x, y, w, h, 7, 1, isWinner and c.accent or c.line,
        isWinner and c.cardHi or c.card)
    HardcoreKitsUI.hairline(self, x + 10, y + 2, w - 20, isWinner and 0.75 or 0.20,
        isWinner and c.accentHi or c.muted)
    if not entry then return end
    if entry.kind == "skill" then
        -- so o icone do grupo (media/ui/HardcoreKits/skill_<groupKey>.png,
        -- ver HardcoreKitsPools.SkillGroups) enquanto gira -- SEM tier
        -- nenhum aqui: o tier so aparece depois que a roleta para, igual ao
        -- "xN" da quantidade de item (ver a anotacao pos-pouso em :render()).
        local iconSize = math.min(w - 14, h - 14)
        local tex = HardcoreKitsUI.tex("skill_" .. tostring(entry.groupKey))
        if tex then
            self:drawTextureScaled(tex, x + math.floor((w - iconSize) / 2), y + math.floor((h - iconSize) / 2),
                iconSize, iconSize, HardcoreKitsUI.dimAlpha, 1, 1, 1)
        end
        return
    end
    if entry.kind == "label" or not entry.fullType then
        -- entrada tipo texto (o "X" de sem-sorte, ou os digitos 1/2/3 da
        -- pre-revelacao da recompensa semanal) -- fonte grande, cabe numa
        -- carta sem vazar (secao 19.5: destaque diferente pra sem-sorte)
        local isFail = self.currentStep and self.currentStep.fail
        local textC = isWinner and (isFail and c.danger or c.accentHi) or c.muted
        -- UIFont.Large e o maior tamanho realmente disponivel (conferido:
        -- nao existe um "Massive"/"Huge" no engine) -- ainda assim, uma unica
        -- letra "X" ou digito nesse tamanho ocupa bem o cartao sem vazar.
        local font = UIFont.Large
        HardcoreKitsUI.textCentre(self, entry.text or "-", x + math.floor(w / 2),
            y + math.floor((h - HardcoreKitsUI.fontH(font)) / 2), font, textC)
        return
    end
    local scriptItem = HardcoreKitsUI.scriptItem(entry.fullType)
    if scriptItem then
        local iconSize = math.min(w - 10, h - 10)
        pcall(function()
            ISInventoryItem.renderScriptItemIcon(self, scriptItem,
                x + math.floor((w - iconSize) / 2), y + math.floor((h - iconSize) / 2), 1.0, iconSize, iconSize)
        end)
    end
end

function HardcoreKitsRouletteWidget:render()
    local c = HardcoreKitsUI.col
    local w, h = self.width, self.height
    local landed = self.state == "landed" or self.state == "done"

    -- titulo da categoria, centralizado com divisorias dos dois lados
    HardcoreKitsUI.centeredDivider(self, self.title, 0, 0, w, UIFont.Medium, c.accentHi, c.accentDim)

    local titleH = HardcoreKitsUI.fontH(UIFont.Medium) + 22
    local ptrSize = 9
    local viewX = 34
    local viewW = w - viewX * 2
    local viewY = titleH + ptrSize + 4
    local viewH = h - viewY - ptrSize - 4 - 26 -- 26 = espaco reservado pro "xN" embaixo

    local highlight = landed and self.currentStep and self.currentStep.highlight
    local fail = landed and self.currentStep and self.currentStep.fail
    local frameC = fail and c.danger or (highlight and c.accentHi or c.line)
    if landed then
        HardcoreKitsUI.glow(self, viewX, viewY, viewW, viewH, 10, fail and 0.08 or 0.10,
            fail and c.danger or c.accent)
    end
    HardcoreKitsUI.roundFrame(self, viewX, viewY, viewW, viewH, 10, 1, frameC, c.dark)

    local centerX = viewX + math.floor(viewW / 2)

    if self.state ~= "idle" then
        self:setStencilRect(viewX + 2, viewY + 2, viewW - 4, viewH - 4)
        -- faixa central fixa: deixa claro onde a carta vencedora vai parar e
        -- amarra visualmente os dois ponteiros ao mesmo eixo.
        HardcoreKitsUI.roundRect(self, centerX - math.floor(CARD_W / 2) - 5, viewY + 2,
            CARD_W + 10, viewH - 4, 8, 0.16, c.accentDim)
        local progress = landed and 1 or self.progress
        local total = (WINNER_INDEX - 1) * STEP_PX
        local offset = -progress * total
        for i, entry in ipairs(self.sequence) do
            local cx = centerX + (i - 1) * STEP_PX + offset - math.floor(CARD_W / 2)
            if cx + CARD_W >= viewX and cx <= viewX + viewW then
                self:renderCard(entry, cx, viewY + 3, CARD_W, viewH - 6, landed and i == WINNER_INDEX)
            end
        end
        self:clearStencilRect()
    end

    -- ponteiros triangulares acima/abaixo do centro
    local ptrC = fail and c.danger or (highlight and c.accentHi or c.accent)
    HardcoreKitsUI.triangleV(self, centerX, viewY - ptrSize - 2, ptrSize, true, 1, ptrC)
    HardcoreKitsUI.triangleV(self, centerX, viewY + viewH + 2, ptrSize, false, 1, ptrC)

    -- chevrons decorativos nas bordas (sugerem a fita continuando pros lados)
    HardcoreKitsUI.triangleH(self, viewX - 22, viewY + math.floor(viewH / 2), 7, false, 0.55, c.muted)
    HardcoreKitsUI.triangleH(self, viewX + viewW + 8, viewY + math.floor(viewH / 2), 7, true, 0.55, c.muted)

    -- quantidade do item (ou tier do bonus de skill) que fixou, embaixo da
    -- roleta -- SO aparece depois que ela para (landed), nunca durante o giro
    -- (pedido explicito do usuario: igual a quantidade de comida/bebida/
    -- municao, que tambem nunca aparece nas cartas girando, so no vencedor)
    if landed and self.currentStep then
        local winner = self.currentStep.winner
        if winner and winner.kind == "item" and (winner.qty or 1) > 1 then
            HardcoreKitsUI.textCentre(self, "x" .. tostring(winner.qty), centerX,
                viewY + viewH + ptrSize + 8, UIFont.Medium, c.accentHi)
        elseif winner and winner.kind == "skill" and winner.tierText then
            HardcoreKitsUI.textCentre(self, "(" .. winner.tierText .. ")", centerX,
                viewY + viewH + ptrSize + 8, UIFont.Medium, winner.tierColor or c.accentHi)
        end
    end
end

-- ==================================================================
-- HardcoreKitsRouletteFastRunner: "Modo roleta rapida" (pedido explicito do
-- usuario, 2026-08-08). Em vez de UM HardcoreKitsRouletteWidget avancando
-- step a step em sequencia, revela os steps em LOTES de ate
-- FastRouletteBatchSize roletas menores girando em PARALELO, EMPILHADAS NA
-- VERTICAL (uma abaixo da outra, largura total cada -- NAO lado a lado:
-- pedido explicito do usuario, lado a lado desperdicava espaco vertical e
-- deixava os reels apertados) -- cada reel e um HardcoreKitsRouletteWidget de
-- sempre, sem nenhuma mudanca de logica de giro, so recebe uma lista de UM
-- step so + geometria/duracao diferentes (ignoreSpeedMultiplier=true,
-- step.durationMs= FastRouletteStepDurationMs -- ver :advance() acima).
-- Dentro de um lote, cada reel comeca FastRouletteStaggerMs depois do
-- anterior (cascata); o mesmo valor tambem e a pausa entre um lote pousar e
-- o proximo aparecer -- o usuario descreveu os dois como "0.5 segundos", um
-- valor so cobre as duas coisas.
--
-- Mesmo contrato externo do HardcoreKitsRouletteWidget
-- (:new(x,y,w,h,steps,onAllDone), campos .steps/.stepIndex/.finished) -- as
-- abas (HardcoreKits_Tab_Initial.lua/HardcoreKits_Tab_Survival.lua) so
-- decidem QUAL classe instanciar (ver startRoulette em cada uma), o resto
-- do layout/refreshButton/onReopen ja funciona igual pros dois. .stepIndex
-- fica sempre 0 (nunca avanca de verdade aqui) -- isso faz
-- HardcoreKitsUI.completedResultSteps() (HardcoreKits_Theme.lua) devolver
-- lista vazia o tempo todo ate .finished virar true, quando entao devolve
-- TODOS os steps de uma vez -- exatamente o "resumo so aparece quando todas
-- as roletas ja sortearam" pedido, sem precisar mexer em
-- completedResultSteps nem nas abas. .isFastRunner marca o tipo pra
-- HardcoreKits_Tab_Initial/Survival.lua saberem quando aplicar o layout
-- especial de "tudo sumiu, so o resumo centralizado ficou" no estado final.
-- ==================================================================
HardcoreKitsRouletteFastRunner = ISPanel:derive("HardcoreKitsRouletteFastRunner")

-- normalReelH: altura de reel "cheia" (igual a roleta normal de um passo so)
-- -- usada quando o lote atual tem 1 ou 2 reels, que cabem com folga sem
-- precisar encolher nada (pedido explicito do usuario). compactReelH: altura
-- menor usada so quando o lote tem 3+ reels. onHeightNeeded(containerH):
-- callback pra quem criou o runner (a aba) saber que o container precisa de
-- containerH de altura AGORA -- normalmente empurra isso pra
-- HardcoreKitsWindow:setContentHeight, que cresce/encolhe a janela sob
-- demanda em vez de um tamanho fixo grande o tempo todo.
function HardcoreKitsRouletteFastRunner:new(x, y, w, h, steps, onAllDone, normalReelH, compactReelH, onHeightNeeded)
    local o = ISPanel:new(x, y, w, h)
    setmetatable(o, self)
    self.__index = self
    o.background = false
    o.steps = steps
    o.onAllDone = onAllDone
    o.normalReelH = normalReelH
    o.compactReelH = compactReelH
    o.onHeightNeeded = onHeightNeeded
    o.stepIndex = 0
    o.finished = false
    o.isFastRunner = true
    o.consumedSteps = 0
    o.reelSlots = {} -- { step=, ry=, rh=, startAtMs=, widget=nil/instancia }
    o.batchLandedAtMs = nil
    return o
end

function HardcoreKitsRouletteFastRunner:createChildren()
    self:launchNextBatch()
end

-- remove os reels do lote atual (se houver) e monta o proximo lote -- ou
-- termina se nao sobrar step nenhum. Chamada pelo createChildren() (primeiro
-- lote) e pelo :prerender() (lotes seguintes, apos a pausa pos-pouso).
--
-- Tamanho do reel e do container e recalculado A CADA lote em cima de n (o
-- tamanho REAL deste lote, nao do FastRouletteBatchSize configurado) --
-- pedido explicito do usuario: 1-2 reels usam o tamanho normal (cabe com
-- folga), 3+ usam o tamanho compacto -- e a janela cresce/encolhe pra
-- acompanhar via onHeightNeeded, entao nunca ha necessidade de "esticar" um
-- lote pequeno pra preencher um container grande demais (o container em si
-- muda de tamanho, ver self:setHeight abaixo).
function HardcoreKitsRouletteFastRunner:launchNextBatch()
    for _, slot in ipairs(self.reelSlots) do
        if slot.widget then self:removeChild(slot.widget) end
    end
    self.reelSlots = {}
    self.batchLandedAtMs = nil

    if self.consumedSteps >= #self.steps then
        self.finished = true
        -- desregistra a instancia TOP-LEVEL do ticker global -- ver
        -- comentario equivalente em HardcoreKitsRouletteWidget:advance().
        HardcoreKitsRoulette.unregister(self)
        -- sorteio inteiro terminado -- devolve a janela pro tamanho base
        -- (0 forca o piso de HardcoreKitsWindow:setContentHeight)
        if self.onHeightNeeded then self.onHeightNeeded(0) end
        if self.onAllDone then self.onAllDone() end
        return
    end

    local batchSize = math.max(1, math.floor(tonumber(HardcoreKitsConfig.FastRouletteBatchSize) or 3))
    local remaining = #self.steps - self.consumedSteps
    local n = math.min(batchSize, remaining)
    local staggerMs = math.max(0, tonumber(HardcoreKitsConfig.FastRouletteStaggerMs) or 500)
    local startedAtMs = getTimestampMs()

    -- empilhados na VERTICAL, cada um ocupando a largura TOTAL -- pedido
    -- explicito do usuario (nao lado a lado: "sobra muito espaco vertical
    -- disponivel a toa e as roletas ficam apertadas").
    local gap = 14
    local reelH = (n <= 2) and self.normalReelH or self.compactReelH
    local containerH = reelH * n + gap * (n - 1)

    self:setHeight(containerH)
    if self.onHeightNeeded then self.onHeightNeeded(containerH) end

    for i = 1, n do
        table.insert(self.reelSlots, {
            step = self.steps[self.consumedSteps + i],
            ry = (i - 1) * (reelH + gap),
            rh = reelH,
            startAtMs = startedAtMs + (i - 1) * staggerMs,
            widget = nil,
        })
    end
    self.consumedSteps = self.consumedSteps + n
end

-- Mesmo espirito de HardcoreKitsRouletteWidget:tick() -- estado puro, sem
-- desenho, chamado pelo ticker global independente de visibilidade. Os reels
-- individuais NUNCA se registram sozinhos no ticker global (evitaria dupla
-- chamada) -- este runner e o unico ponto que os avanca, chamando
-- slot.widget:tick() direto em cada um, tenha a janela sido desenhada este
-- frame ou nao. self:addChild(reel) continua acontecendo normalmente pra
-- quando a janela ESTA visivel, o proprio motor desenha o reel como filho.
function HardcoreKitsRouletteFastRunner:tick()
    local now = getTimestampMs()
    local spinMs = math.max(100, tonumber(HardcoreKitsConfig.FastRouletteStepDurationMs) or 1000)
    local allLanded = true

    for _, slot in ipairs(self.reelSlots) do
        if not slot.widget and now >= slot.startAtMs then
            -- copia rasa do step: evita sujar step.durationMs no step
            -- ORIGINAL (self.steps guarda os mesmos objetos que
            -- completedResultSteps le depois pro resumo)
            local reelStep = {}
            for k, v in pairs(slot.step) do reelStep[k] = v end
            reelStep.durationMs = spinMs
            local reel = HardcoreKitsRouletteWidget:new(0, slot.ry, self.width, slot.rh, { reelStep }, nil)
            reel.ignoreSpeedMultiplier = true
            self:addChild(reel)
            reel:initialise()
            slot.widget = reel
        end
        if slot.widget then
            slot.widget:tick()
        end
        if not slot.widget or (slot.widget.state ~= "landed" and slot.widget.state ~= "done") then
            allLanded = false
        end
    end

    if allLanded and #self.reelSlots > 0 then
        if not self.batchLandedAtMs then
            self.batchLandedAtMs = now
        end
        local staggerMs = math.max(0, tonumber(HardcoreKitsConfig.FastRouletteStaggerMs) or 500)
        if now - self.batchLandedAtMs >= staggerMs then
            self:launchNextBatch()
        end
    end
end

-- ==================================================================
-- construcao dos passos a partir do resultado sorteado (ja fixado pelo
-- servidor) -- so decide COMO exibir, nunca O QUE foi sorteado
-- ==================================================================

local function itemEntries(fullTypeList)
    local out = {}
    for _, t in ipairs(fullTypeList or {}) do
        table.insert(out, { kind = "item", fullType = t, qty = 1 })
    end
    return out
end

local function foodPool()
    local out = {}
    for _, t in ipairs(HardcoreKitsPools.FoodCanned) do table.insert(out, t) end
    for _, t in ipairs(HardcoreKitsPools.FoodPickled) do table.insert(out, t) end
    for _, t in ipairs(HardcoreKitsPools.FoodSecondary) do table.insert(out, t) end
    return itemEntries(out)
end

local function drinkPool()
    local out = {}
    for _, t in ipairs(HardcoreKitsPools.DrinkWater) do table.insert(out, t) end
    for _, t in ipairs(HardcoreKitsPools.DrinkOther) do table.insert(out, t) end
    return itemEntries(out)
end

local function meleePool()
    local out = {}
    for _, list in pairs(HardcoreKitsPools.MeleeByCategory) do
        for _, t in ipairs(list) do table.insert(out, t) end
    end
    return itemEntries(out)
end

local function firearmPool()
    local out = {}
    for _, def in ipairs(HardcoreKitsPools.Firearms) do table.insert(out, def.fullType) end
    return itemEntries(out)
end

local function ammoPool()
    local out = {}
    for _, def in ipairs(HardcoreKitsPools.Firearms) do table.insert(out, def.ammoBox) end
    return itemEntries(out)
end

local function backpackPool()
    local out = {}
    for _, list in pairs(HardcoreKitsPools.BackpackByTier) do
        for _, t in ipairs(list) do table.insert(out, t) end
    end
    return itemEntries(out)
end

local function resourcePool()
    return itemEntries(HardcoreKitsPools.Resources)
end

-- decoys do bonus de habilidade: cada grupo x cada tier -- so cosmetico,
-- nenhum decoy e entregue de verdade (mesma regra do resto do arquivo)
local SKILL_TIERS = { "verylow", "low", "medium", "high" }
local function skillGroupPool()
    local out = {}
    for _, group in ipairs(HardcoreKitsPools.SkillGroups or {}) do
        local groupText = getText(group.labelKey)
        for _, tier in ipairs(SKILL_TIERS) do
            table.insert(out, { kind = "skill", groupKey = group.key, groupText = groupText,
                tierText = HardcoreKitsUI.tierText(tier), tierColor = HardcoreKitsUI.tierColor(tier) })
        end
    end
    return out
end

-- constroi o entry "vencedor" de um bonus de skill ja sorteado (grupo
-- inteiro do Kit Inicial OU skill unica da recompensa -- os dois tem
-- groupKey/groupLabelKey/tier, so difere o rotulo em si). groupKey e o que
-- escolhe o icone (skill_<groupKey>.png); groupText/tierText/tierColor
-- continuam guardados aqui pro card de resumo (largura dinamica, com
-- texto) e pra anotacao pos-pouso do tier (ver HardcoreKitsRouletteWidget:render)
local function skillWinnerEntry(groupKey, groupLabelKey, tier)
    return { kind = "skill", groupKey = groupKey, groupText = getText(groupLabelKey),
        tierText = HardcoreKitsUI.tierText(tier), tierColor = HardcoreKitsUI.tierColor(tier) }
end

-- adiciona um passo por entrada da lista { fullType=, qty= } -- em modo
-- normal a lista tem 1 entrada so (comportamento de sempre); em
-- FoodDrinkMultiRollMode pode ter varias, cada uma virando seu proprio giro
-- da roleta ("COMIDA #1", "COMIDA #2", ...), dando mais variedade e suspense.
local function addStackedSteps(steps, baseLabel, pool, entries, extraOpts)
    local n = entries and #entries or 0
    for i = 1, n do
        local label = (n > 1) and (baseLabel .. " #" .. tostring(i)) or baseLabel
        local step = { label = label, pool = pool,
            winner = { kind = "item", fullType = entries[i].fullType, qty = entries[i].qty } }
        if extraOpts then for k, v in pairs(extraOpts) do step[k] = v end end
        table.insert(steps, step)
    end
end

-- secao 19.3: sequencia fixa do Kit Inicial. fastMode (modo roleta rapida,
-- pedido explicito do usuario): pula os passos de "quantos" (so a contagem
-- em si, sem revelar nada) pra agilizar -- revela os grupos de habilidade
-- JA sorteados direto, sem o giro extra so pra mostrar o numero antes.
function HardcoreKitsRoulette.buildInitialSteps(rolled, fastMode)
    local steps = {}
    addStackedSteps(steps, getText("UI_HardcoreKits_StepFood"), foodPool(), rolled.food)
    addStackedSteps(steps, getText("UI_HardcoreKits_StepDrink"), drinkPool(), rolled.drink)
    if rolled.medicalKitBag then
        -- resultado especial: maleta medica -- mostra ela como vencedora
        -- (mesmo espirito da mochila principal: o conteudo de dentro fica de
        -- surpresa, so o item "mochila" aparece na roleta -- identico ao
        -- tratamento que a Recompensa de Sobrevivencia ja da pro mesmo caso)
        table.insert(steps, { label = getText("UI_HardcoreKits_StepResource"), pool = resourcePool(),
            winner = { kind = "item", fullType = rolled.medicalKitBag, qty = 1 }, highlight = true })
    else
        addStackedSteps(steps, getText("UI_HardcoreKits_StepResource"), resourcePool(), rolled.resource)
    end
    table.insert(steps, { label = getText("UI_HardcoreKits_StepMelee"), pool = meleePool(),
        winner = { kind = "item", fullType = rolled.melee, qty = 1 } })
    if rolled.hasFirearm and rolled.firearm then
        table.insert(steps, { label = getText("UI_HardcoreKits_StepFirearm"), pool = firearmPool(),
            winner = { kind = "item", fullType = rolled.firearm.fullType, qty = 1 }, highlight = true })
        table.insert(steps, { label = getText("UI_HardcoreKits_StepAmmo"), pool = ammoPool(),
            winner = { kind = "item", fullType = rolled.firearm.ammoBox, qty = rolled.ammoBoxQty } })
    else
        -- so um "X" grande (nao uma frase) -- nao vaza do cartao (secao 19.5:
        -- destaque diferente pra quando nao ha arma de fogo). O glifo "X" e
        -- universal, nao precisa de traducao.
        table.insert(steps, { label = getText("UI_HardcoreKits_StepFirearm"), pool = firearmPool(),
            winner = { kind = "label", text = "X" }, fail = true })
    end
    -- pedido explicito do usuario: se o personagem ja tinha mochila
    -- equipada, HardcoreKitsRolls.rollInitialKit nem sorteia uma nova (ver
    -- comentario la) -- rolled.backpack fica nil, e esse passo e OMITIDO
    -- inteiro (nao um card "X" -- nao e "azarado", e so um passo que nao se
    -- aplica, mesmo espirito do bonus de habilidade so aparecer quando a
    -- feature esta ligada).
    if rolled.backpack then
        table.insert(steps, { label = getText("UI_HardcoreKits_StepBackpack"), pool = backpackPool(),
            winner = { kind = "item", fullType = rolled.backpack, qty = 1 } })
    end

    -- bonus de habilidade: so aparece se a feature estiver ligada (nao so se
    -- skillBoosts vier vazia -- vazia tambem acontece com a feature
    -- desligada, e nesse caso nao deve mostrar nada -- ver
    -- HardcoreKits_Rolls.rollInitialKit). Primeiro revela QUANTOS grupos,
    -- dentro do minimo/maximo configurado no sandbox, igual o passo "quantos
    -- resultados" da recompensa semanal.
    if rolled.skillBoostEnabled then
        local boosts = rolled.skillBoosts or {}
        if not fastMode then
            local maxGroups = #(HardcoreKitsPools.SkillGroups or {})
            local minConfigured = math.floor(tonumber(HardcoreKitsConfig.InitialSkillGroupCountMin) or 1)
            local maxConfigured = math.floor(tonumber(HardcoreKitsConfig.InitialSkillGroupCountMax) or maxGroups)
            minConfigured = math.max(1, math.min(minConfigured, maxGroups))
            maxConfigured = math.max(1, math.min(maxConfigured, maxGroups))
            if minConfigured > maxConfigured then minConfigured, maxConfigured = maxConfigured, minConfigured end
            local countEntries = {}
            for n = minConfigured, maxConfigured do
                table.insert(countEntries, { kind = "label", text = tostring(n) })
            end
            table.insert(steps, {
                label = getText("UI_HardcoreKits_StepSkillHowMany"),
                pool = countEntries,
                winner = { kind = "label", text = tostring(#boosts) },
                highlight = maxGroups > 0 and #boosts >= maxGroups,
            })
        end
        for _, boost in ipairs(boosts) do
            table.insert(steps, {
                label = getText("UI_HardcoreKits_StepSkill"),
                pool = skillGroupPool(),
                winner = skillWinnerEntry(boost.groupKey, boost.groupLabelKey, boost.tier),
                highlight = boost.tier == "high",
            })
        end
    end

    return steps
end

-- secao 19.4: primeiro quantos resultados (reaproveita a mesma roleta pra
-- girar entre "1"/"2"/"3"), depois um passo por resultado. fastMode: pula
-- esse passo de "quantos" -- mesma ideia do Kit Inicial acima, ver comentario la.
function HardcoreKitsRoulette.buildSurvivalSteps(rolledList, fastMode)
    local steps = {}

    if not fastMode then
        local countEntries = {}
        for n = 1, 3 do table.insert(countEntries, { kind = "label", text = tostring(n) }) end
        table.insert(steps, {
            label = getText("UI_HardcoreKits_StepHowMany"),
            pool = countEntries,
            winner = { kind = "label", text = tostring(#rolledList) },
            highlight = #rolledList >= 3,
        })
    end

    for idx, r in ipairs(rolledList) do
        local prefix = "#" .. tostring(idx) .. " "
        if r.category == "combat" and r.subCategory == "melee" then
            addStackedSteps(steps, prefix .. getText("UI_HardcoreKits_StepCombat"), meleePool(), r.items)
        elseif r.category == "combat" and r.subCategory == "firearm" then
            table.insert(steps, { label = prefix .. getText("UI_HardcoreKits_StepCombat"), pool = firearmPool(),
                winner = { kind = "item", fullType = r.firearm and r.firearm.fullType, qty = 1 }, highlight = true })
            -- caixa de municao GARANTIDA da propria arma (r.ammoBoxQty,
            -- sempre 1 -- ver HardcoreKits_Rolls.rollSurvivalCombat), passo
            -- proprio na sequencia -- mesmo padrao que o Kit Inicial ja usa
            -- pro par arma+municao.
            if r.ammoBoxQty and r.ammoBoxQty > 0 then
                table.insert(steps, { label = prefix .. getText("UI_HardcoreKits_StepAmmo"), pool = ammoPool(),
                    winner = { kind = "item", fullType = r.firearm and r.firearm.ammoBox, qty = r.ammoBoxQty } })
            end
        elseif r.category == "ammo" then
            -- municao ISOLADA (categoria propria, nao ligada a arma nenhuma
            -- -- pedido explicito do usuario, ver HardcoreKits_Rolls)
            addStackedSteps(steps, prefix .. getText("UI_HardcoreKits_StepAmmo"), ammoPool(), r.items)
        elseif r.category == "skill" then
            -- bonus raro (uma unica skill OU um grupo inteiro, r.kind ==
            -- "single"/"group" -- ver HardcoreKits_Rolls.rollSurvivalSkillBonus)
            -- -- ADICIONAL aos N resultados normais (nao entra na contagem do
            -- passo "quantos resultados?" acima), por isso sem o prefixo
            -- "#N". Card identico pros dois casos: so mostra o icone do grupo
            -- + tier, nunca skills individuais (r.groupKey/groupLabelKey/tier
            -- existem nas duas formas, entao nenhum branch extra e preciso aqui).
            table.insert(steps, {
                label = getText("UI_HardcoreKits_StepSkill"),
                pool = skillGroupPool(),
                winner = skillWinnerEntry(r.groupKey, r.groupLabelKey, r.tier),
                highlight = r.tier == "high",
            })
        elseif r.category == "resource" and r.subCategory == "medicalkit" then
            -- resultado especial: mochila medica -- mostra ela como vencedora
            -- (mesmo espirito da mochila do Kit Inicial: o conteudo de dentro
            -- fica de surpresa, so o item "mochila" aparece na roleta)
            table.insert(steps, { label = prefix .. getText("UI_HardcoreKits_StepResource"), pool = resourcePool(),
                winner = { kind = "item", fullType = r.medicalKitBag, qty = 1 }, highlight = true })
        elseif r.category == "resource" then
            addStackedSteps(steps, prefix .. getText("UI_HardcoreKits_StepResource"), resourcePool(), r.items)
        elseif r.category == "drink" then
            addStackedSteps(steps, prefix .. getText("UI_HardcoreKits_StepDrink"), drinkPool(), r.items)
        else
            addStackedSteps(steps, prefix .. getText("UI_HardcoreKits_StepFood"), foodPool(), r.items)
        end
    end

    return steps
end
