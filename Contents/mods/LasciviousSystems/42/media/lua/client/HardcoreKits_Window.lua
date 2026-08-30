-- Janela principal: um unico painel com duas abas alternadas por botoes no
-- topo (secao 5 da especificacao). Mais simples que o sidebar multi-pagina
-- do Aegis -- apropriado pra so 2 abas -- mas usa a mesma tecnica de
-- desenho (HardcoreKits_Theme) e o mesmo padrao de singleton com toggle().
require "ISUI/ISPanel"
require "HardcoreKits_Theme"
require "HardcoreKits_Widgets"
require "HardcoreKits_Client"
require "HardcoreKits_Danger"

-- Um reload substitui a classe; aposenta a instancia e a closure anteriores
-- para que uma janela invisivel nao permaneça referenciada pela sessao toda.
local previousWindowClass = HardcoreKitsWindow
local previousWindow = previousWindowClass and previousWindowClass.instance
if previousWindow then
    if previousWindow._networkListener then
        HardcoreKitsClient.offUpdate(previousWindow._networkListener)
        previousWindow._networkListener = nil
    end
    pcall(function()
        previousWindow:setVisible(false)
        if previousWindow.removeFromUIManager then previousWindow:removeFromUIManager() end
    end)
end

HardcoreKitsWindow = ISPanel:derive("HardcoreKitsWindow")
HardcoreKitsWindow.instance = nil

local HEADER_H = 66
local TAB_H = 48
local WIN_W = 820
-- altura BASE/minima -- usada como tamanho de criacao e como piso pro resize
-- dinamico abaixo (nunca encolhe menos que isto). 2026-08-08: chegou a subir
-- pra 920 fixo pra caber o modo roleta rapida sem encolher icone nenhum, e
-- depois pra 800 com reels um pouco menores -- o usuario rejeitou os dois
-- (interface maior o tempo todo, mesmo quando nao precisa) e pediu resize
-- DINAMICO em vez de um tamanho fixo maior: ver HardcoreKitsWindow:setContentHeight
-- abaixo, chamado por HardcoreKitsRouletteFastRunner (HardcoreKits_Roulette.lua)
-- toda vez que um lote de reels e montado -- a janela cresce so quando o
-- lote atual (2+ reels em tamanho normal, ou 3+ em tamanho compacto)
-- realmente nao cabe neste tamanho base, e volta pra ca assim que nao
-- precisa mais (lote menor, ou sorteio terminado).
local WIN_H = 700
local EDGE = 12
-- margem interna consistente pra tudo (titulo, abas, botao de fechar) nunca
-- ficar colado na borda da janela
HardcoreKitsWindow.MARGIN = 22

-- abas registradas por outros arquivos: { id, labelKey, create(window,x,y,w,h) }.
-- labelKey e uma chave de getText(), resolvida so na hora de desenhar (nunca
-- guardada ja traduzida) -- assim, se o jogador trocar o idioma do jogo em
-- Opcoes sem reiniciar, a aba acompanha na hora, igual ao resto do vanilla.
-- create() deve devolver um ISPanel ja pronto pra initialise().
HardcoreKitsWindow.tabs = {}
function HardcoreKitsWindow.registerTab(def)
    table.insert(HardcoreKitsWindow.tabs, def)
end

-- cria a instancia (singleton) se ainda nao existir. Extraido pra fora de
-- toggle() pra tambem ser reaproveitado por open() abaixo -- ISPanel ja
-- nasce visivel por padrao ao ser adicionado ao UI manager, entao criar
-- sozinho ja conta como "abrir" nos dois casos.
local function ensureCreated()
    if HardcoreKitsWindow.instance then return HardcoreKitsWindow.instance end
    local sw, sh = getCore():getScreenWidth(), getCore():getScreenHeight()
    local w = math.min(WIN_W, sw - EDGE * 2)
    local h = math.min(WIN_H, sh - EDGE * 2)
    local o = HardcoreKitsWindow:new(math.floor((sw - w) / 2), math.floor((sh - h) / 2), w, h)
    o:initialise()
    o:addToUIManager()
    HardcoreKitsWindow.instance = o
    HardcoreKitsClient.requestState()
    o:onReopen()   -- also sets the checkAttackedClose() baseline on first creation
    return o
end

-- usado pelo comando manual /kit: abre se fechada, fecha se aberta.
function HardcoreKitsWindow.toggle()
    if HardcoreKitsWindow.instance then
        local o = HardcoreKitsWindow.instance
        local show = not o:isVisible()
        o:setVisible(show)
        if show then
            o:bringToTop()
            HardcoreKitsClient.requestState()
            o:onReopen()
        else
            o.dragging = false
        end
        return
    end
    ensureCreated()
end

-- IDEMPOTENTE: so garante que a janela fique ABERTA, nunca fecha -- ao
-- contrario de toggle(), chamar isto varias vezes seguidas nunca tem efeito
-- colateral. Usado pelo auto-open (HardcoreKits_AutoOpen.lua), que na
-- pratica pode disparar mais de uma vez pro mesmo spawn (Events.OnCreatePlayer
-- e sabidamente pouco confiavel quanto a disparar uma unica vez -- ver
-- comentario em HardcoreKits_AutoOpen.lua) -- chamar toggle() duas vezes ali
-- abria e fechava a janela quase instantaneamente na primeira vida de uma
-- conta nova (bug reportado pelo usuario: so funcionava a partir da segunda
-- tentativa manual).
function HardcoreKitsWindow.open()
    if HardcoreKitsWindow.instance then
        local o = HardcoreKitsWindow.instance
        if not o:isVisible() then
            o:setVisible(true)
            o:bringToTop()
            HardcoreKitsClient.requestState()
            o:onReopen()
        end
        return
    end
    ensureCreated()
end

function HardcoreKitsWindow:new(x, y, w, h)
    local o = ISPanel:new(x, y, w, h)
    setmetatable(o, self)
    self.__index = self
    o.background = false
    o.activeTab = nil
    o.tabPanels = {}
    o.tabRects = {}
    o.dragging = false
    o:setWantKeyEvents(true)   -- required for onKeyRelease/isKeyConsumed to fire
    return o
end

-- Escape closes the window fast -- same reasoning as the Factions panel: it's
-- good to be able to bail out of a menu quickly in an emergency, not just via
-- the corner X.
function HardcoreKitsWindow:isKeyConsumed(key)
    return key == Keyboard.KEY_ESCAPE
end

function HardcoreKitsWindow:onKeyRelease(key)
    if key == Keyboard.KEY_ESCAPE then self:close() end
end

function HardcoreKitsWindow:createChildren()
    local m = HardcoreKitsWindow.MARGIN
    self.closeBtn = HardcoreKitsButton:new(self.width - m - 28, math.floor((HEADER_H - 28) / 2), 28, 28,
        "X", self, HardcoreKitsWindow.close, "close")
    self.closeBtn.radius = 8
    -- Fica de FORA do escurecimento "zumbi muito perto" (ver :prerender()
    -- abaixo e o mecanismo em HardcoreKits_Theme.lua) -- o jogador sempre
    -- precisa conseguir ver e clicar o botao de fechar, mesmo com o resto da
    -- interface translucida.
    self.closeBtn.hkNoDim = true
    self:addChild(self.closeBtn)

    if #HardcoreKitsWindow.tabs > 0 then
        self:switchTab(HardcoreKitsWindow.tabs[1].id)
    end

    local win = self
    self._networkListener = HardcoreKitsClient.onUpdate(function()
        if HardcoreKitsWindow.instance == win then win:onStateUpdated() end
    end)
end

function HardcoreKitsWindow:close()
    self:setVisible(false)
    self.dragging = false
    -- Nao deixa um valor escurecido "vazar" pra proxima vez que a janela
    -- abrir (o proprio prerender ja recalcula isto a cada frame enquanto
    -- visivel, mas nada roda enquanto fechada, entao o ultimo valor ficaria
    -- parado do jeito que estava).
    HardcoreKitsUI.dimAlpha = 1.0
end

function HardcoreKitsWindow:contentArea()
    local m = HardcoreKitsWindow.MARGIN
    return m, HEADER_H + TAB_H + 10, self.width - m * 2, self.height - HEADER_H - TAB_H - 10 - m
end

-- redimensiona a janela pra caber desiredContentH de conteudo util na aba
-- ativa (a altura "util" que contentArea() devolveria, ja descontando
-- header/abas/margens) -- cresce ALEM de WIN_H quando precisa (modo roleta
-- rapida com mais reels do que cabe no tamanho base, ver
-- HardcoreKitsRouletteFastRunner), mas nunca encolhe abaixo dele. x/y (canto
-- superior esquerdo, onde o jogador pode ter arrastado a janela) ficam
-- parados -- so cresce/encolhe pra BAIXO. Propaga a nova altura pra TODOS os
-- paineis de aba ja criados (mesmo o que nao esta visivel agora), senao o
-- self.height deles ficaria desatualizado e quebraria qualquer layout que
-- dependa dele na proxima vez que aquela aba for mostrada.
function HardcoreKitsWindow:setContentHeight(desiredContentH)
    local m = HardcoreKitsWindow.MARGIN
    local sh = getCore():getScreenHeight()
    local wanted = math.max(WIN_H, (desiredContentH or 0) + HEADER_H + TAB_H + 10 + m)
    local newH = math.min(wanted, sh - EDGE * 2)
    if newH == self.height then return end
    self:setHeight(newH)
    local _, _, _, ch = self:contentArea()
    for _, panel in pairs(self.tabPanels) do
        panel:setHeight(ch)
    end
end

function HardcoreKitsWindow:switchTab(id)
    if self.activeTab == id then return end
    for tid, panel in pairs(self.tabPanels) do
        panel:setVisible(tid == id)
    end
    if not self.tabPanels[id] then
        for _, def in ipairs(HardcoreKitsWindow.tabs) do
            if def.id == id then
                local cx, cy, cw, ch = self:contentArea()
                local panel = def.create(self, cx, cy, cw, ch)
                panel:initialise()
                self:addChild(panel)
                self.tabPanels[id] = panel
                break
            end
        end
    end
    local panel = self.tabPanels[id]
    if panel then
        panel:setVisible(true)
        if panel.onShow then panel:onShow() end
    end
    self.activeTab = id
end

-- repassado pra aba visivel sempre que Client.lua recebe algo novo do
-- servidor (state, resultado de claim, erro)
function HardcoreKitsWindow:onStateUpdated()
    for _, panel in pairs(self.tabPanels) do
        if panel.onStateUpdated then panel:onStateUpdated() end
    end
end

-- chamado quando a JANELA volta a ficar visivel (fechada -> aberta de novo),
-- diferente de onShow() de cada aba (que tambem dispara so trocando de aba
-- com a janela ja aberta). Da pra cada aba descartar a roleta/resumo de uma
-- captura ja concluida antes desta reabertura, pra nao mostrar uma repeticao
-- velha -- ver HardcoreKitsTabInitial/Survival:onReopen.
function HardcoreKitsWindow:onReopen()
    -- Baseline for checkAttackedClose() below: whatever getAttackedBy()
    -- already reads as RIGHT NOW, not nil -- otherwise reopening the window
    -- moments after a fight (before the engine clears/replaces that field)
    -- would instantly close it again. Only a hit that happens AFTER this
    -- point counts as new. Set here rather than only in ensureCreated() so
    -- BOTH a fresh creation and every later reopen (toggle()/open()) get a
    -- fresh baseline -- onReopen() already fires from all three.
    self._lastAttacker = nil
    pcall(function()
        local player = getPlayer()
        if player then self._lastAttacker = player:getAttackedBy() end
    end)
    for _, panel in pairs(self.tabPanels) do
        if panel.onReopen then panel:onReopen() end
    end
end

-- Force-closes the window the moment the player takes a hit from an actual
-- attacker (zombie, animal, or another player) while it's open -- the hard
-- backstop for when the danger-dimming above isn't enough. getAttackedBy()
-- only ever gets set by combat, never by hunger/thirst/cold/disease/fall
-- damage, so "normal" damage naturally never triggers this. Same mechanism
-- as LasciviousShop_Window.lua/LFS_Panel.lua's own checkAttackedClose.
function HardcoreKitsWindow:checkAttackedClose()
    local ok, player = pcall(getPlayer)
    if not (ok and player) then return end
    local gotAttacker, attacker = pcall(function() return player:getAttackedBy() end)
    if not gotAttacker then return end
    if attacker ~= nil and attacker ~= self._lastAttacker then
        self._lastAttacker = attacker
        self:close()
        return
    end
    self._lastAttacker = attacker
end

-- Intervalo real entre checagens de "zumbi muito perto" -- nao precisa ser
-- por frame (a varredura de cell:getZombieList() e barata, mas nao gratis, e
-- o alpha so precisa reagir rapido o bastante pra parecer instantaneo, nao
-- literalmente a cada frame).
local DANGER_CHECK_INTERVAL_MS = 400

function HardcoreKitsWindow:updateDangerAlpha()
    if HardcoreKitsConfig.WindowDimOnDangerEnabled ~= true then
        HardcoreKitsUI.dimAlpha = 1.0
        return
    end
    local now = getTimestampMs()
    if not self.dangerCheckedAtMs or now - self.dangerCheckedAtMs >= DANGER_CHECK_INTERVAL_MS then
        self.dangerCheckedAtMs = now
        local ok, player = pcall(getPlayer)
        self.dangerNear = ok and player
            and HardcoreKitsDanger.zombiesNear(player, HardcoreKitsConfig.WindowDimOnDangerRadius)
            or false
    end
    local target = self.dangerNear and (tonumber(HardcoreKitsConfig.WindowDimOnDangerAlpha) or 0.25) or 1.0
    HardcoreKitsUI.dimAlpha = HardcoreKitsUI.glide(HardcoreKitsUI.dimAlpha, target, 0.25)
end

function HardcoreKitsWindow:prerender()
    self:updateDangerAlpha()
    self:checkAttackedClose()
    local c = HardcoreKitsUI.col
    local w, h = self.width, self.height
    local m = HardcoreKitsWindow.MARGIN
    HardcoreKitsUI.shadow(self, 0, 0, w, h, 28, 0.5)
    HardcoreKitsUI.glow(self, 0, 0, w, h, 34, 0.10, c.accent)
    HardcoreKitsUI.roundFrame(self, 0, 0, w, h, 14, 1, c.accentDim, c.bg)

    local grad = HardcoreKitsUI.tex("grad_v")
    if grad then
        self:drawTextureScaled(grad, 1, 1, w - 2, 58, 0.22, c.accent.r, c.accent.g, c.accent.b)
    end
    HardcoreKitsUI.textCentreFit(self, getText("UI_HardcoreKits_WindowTitle"), math.floor(w / 2),
        math.floor((HEADER_H - HardcoreKitsUI.fontH(UIFont.Large)) / 2), w - m * 2 - 70, UIFont.Large, c.text)
    HardcoreKitsUI.hairline(self, math.floor(w / 2) - 48, HEADER_H - 8, 96, 1, c.accent)
    HardcoreKitsUI.hairline(self, m, HEADER_H, w - m * 2, 1, c.line)

    -- abas: pilulas com borda propria, a ativa ganha preenchimento + risco embaixo
    self.tabRects = {}
    local count = math.max(1, #HardcoreKitsWindow.tabs)
    local gap = 10
    local totalW = w - m * 2
    local tabW = math.floor((totalW - gap * (count - 1)) / count)
    local tx = m
    local ty = HEADER_H + (TAB_H - 36) / 2
    local bh = 36
    local mouseX, mouseY = self:getMouseX(), self:getMouseY()
    for _, def in ipairs(HardcoreKitsWindow.tabs) do
        local active = self.activeTab == def.id
        local hovered = mouseX >= tx and mouseX <= tx + tabW and mouseY >= ty and mouseY <= ty + bh
        if active then
            HardcoreKitsUI.roundFrame(self, tx, ty, tabW, bh, 9, 1, c.accent, c.cardHi)
            HardcoreKitsUI.roundRect(self, tx + 10, ty + bh - 3, tabW - 20, 2, 1, 1, c.accentHi)
        elseif hovered then
            HardcoreKitsUI.roundFrame(self, tx, ty, tabW, bh, 9, 1, c.accentDim, c.card)
        else
            HardcoreKitsUI.roundFrame(self, tx, ty, tabW, bh, 9, 1, c.line, c.panel)
        end
        local textC = active and c.text or (hovered and c.accentHi or c.muted)
        HardcoreKitsUI.textCentreFit(self, getText(def.labelKey), tx + math.floor(tabW / 2),
            ty + math.floor((bh - HardcoreKitsUI.fontH(UIFont.Small)) / 2), tabW - 16, UIFont.Small, textC)
        table.insert(self.tabRects, { x = tx, y = ty, w = tabW, h = bh, id = def.id })
        tx = tx + tabW + gap
    end
end

function HardcoreKitsWindow:onMouseDown(x, y)
    self:bringToTop()
    if y <= HEADER_H then
        self.dragging = true
        return
    end
    for _, rect in ipairs(self.tabRects) do
        if x >= rect.x and x <= rect.x + rect.w and y >= rect.y and y <= rect.y + rect.h then
            HardcoreKitsUI.sound()
            self:switchTab(rect.id)
            return
        end
    end
end

function HardcoreKitsWindow:onMouseMove(dx, dy)
    if self.dragging then
        self:setX(self.x + dx)
        self:setY(self.y + dy)
    end
end

function HardcoreKitsWindow:onMouseMoveOutside(dx, dy)
    self:onMouseMove(dx, dy)
end

function HardcoreKitsWindow:onMouseUp(x, y)
    self.dragging = false
end

function HardcoreKitsWindow:onMouseUpOutside(x, y)
    self.dragging = false
end
