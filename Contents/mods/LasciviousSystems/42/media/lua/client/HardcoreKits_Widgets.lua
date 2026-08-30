-- Botao reutilizavel, mesmo mecanismo do AegisButton (hover suave, estilos
-- por cor, texto centralizado) portado para a nossa paleta/namespace.
require "ISUI/ISPanel"
require "HardcoreKits_Theme"

HardcoreKitsButton = ISPanel:derive("HardcoreKitsButton")

-- style: "primary" (CTA violeta), "danger", "close", ou nil/"ghost"
-- (padrao, contorno).
function HardcoreKitsButton:new(x, y, w, h, label, target, onClick, style)
    local o = ISPanel:new(x, y, w, h)
    setmetatable(o, self)
    self.__index = self
    o.background = false
    o.label = label
    o.target = target
    o.onClick = onClick
    o.style = style or "ghost"
    o.radius = 10
    o.font = UIFont.Small
    o.enabled = true
    o.hoverT = 0
    o.pressed = false
    o.hovered = false
    return o
end

function HardcoreKitsButton:setEnabled(b)
    self.enabled = b and true or false
    if not self.enabled then self.pressed = false end
end

function HardcoreKitsButton:setLabel(label)
    self.label = label
end

function HardcoreKitsButton:prerender()
    HardcoreKitsUI.updateTooltip(self)
end

function HardcoreKitsButton:render()
    local c = HardcoreKitsUI.col
    local w, h = self.width, self.height
    local r = math.min(self.radius, math.floor(h / 2))
    self.hoverT = HardcoreKitsUI.glide(self.hoverT, (self.enabled and self.hovered) and 1 or 0, 0.35)
    local a = self.enabled and 1 or 0.35
    local textA = self.enabled and 1 or 0.62
    local textC = c.text

    if not self.enabled then
        HardcoreKitsUI.roundFrame(self, 0, 0, w, h, r, 0.65, c.line, c.panel)
        textC = c.muted
    elseif self.style == "primary" then
        if self.hoverT > 0.01 then
            HardcoreKitsUI.glow(self, 0, 0, w, h, 10, 0.16 * self.hoverT, c.accent)
        end
        HardcoreKitsUI.roundFrame(self, 0, 0, w, h, r, a, c.accentHi, c.accent)
        if self.hoverT > 0.01 then
            HardcoreKitsUI.roundRect(self, 1, 1, w - 2, h - 2, math.max(1, r - 1),
                0.10 * self.hoverT, c.white)
        end
        if self.pressed then
            HardcoreKitsUI.roundRect(self, 1, 1, w - 2, h - 2, math.max(1, r - 1), 0.28, c.dark)
        end
        textC = c.text
    elseif self.style == "danger" then
        HardcoreKitsUI.roundRect(self, 0, 0, w, h, r, a, c.danger)
        HardcoreKitsUI.roundRect(self, 1, 1, w - 2, h - 2, math.max(1, r - 1), a * (0.82 - 0.35 * self.hoverT), c.bg)
        textC = c.danger
    elseif self.style == "close" then
        local borderC = self.hoverT > 0.01 and c.danger or c.line
        local fillC = self.hoverT > 0.01 and c.cardHi or c.panel
        HardcoreKitsUI.roundFrame(self, 0, 0, w, h, r, a, borderC, fillC)
        if self.pressed then
            HardcoreKitsUI.roundRect(self, 1, 1, w - 2, h - 2, math.max(1, r - 1), 0.35, c.dark)
        end
        textC = self.hoverT > 0.01 and c.danger or c.muted
    else
        HardcoreKitsUI.roundRect(self, 0, 0, w, h, r, a, self.hoverT > 0.01 and c.accentDim or c.line)
        HardcoreKitsUI.roundRect(self, 1, 1, w - 2, h - 2, math.max(1, r - 1), a, c.card)
        if self.hoverT > 0.01 then
            HardcoreKitsUI.roundRect(self, 1, 1, w - 2, h - 2, math.max(1, r - 1), 0.6 * self.hoverT * a, c.cardHi)
        end
        if self.pressed then
            HardcoreKitsUI.roundRect(self, 1, 1, w - 2, h - 2, math.max(1, r - 1), 0.35, c.dark)
        end
    end

    if self.label then
        local availW = w - 12
        if self._fitSrc ~= self.label or self._fitW ~= availW then
            self._fitSrc = self.label
            self._fitW = availW
            self._fitLabel = HardcoreKitsUI.fitText(self.label, self.font, availW)
        end
        local label = self._fitLabel
        local tw = HardcoreKitsUI.strW(self.font, label)
        local pressedOffset = self.pressed and 1 or 0
        HardcoreKitsUI.text(self, label, math.floor((w - tw) / 2),
            math.floor((h - HardcoreKitsUI.fontH(self.font)) / 2) + pressedOffset, self.font, textC, textA)
    end
end

function HardcoreKitsButton:onMouseMove(dx, dy) self.hovered = true end
function HardcoreKitsButton:onMouseMoveOutside(dx, dy) self.hovered = false end
function HardcoreKitsButton:onMouseDown(x, y)
    if self.enabled then self.pressed = true end
end
function HardcoreKitsButton:onMouseUpOutside(x, y) self.pressed = false end

function HardcoreKitsButton:onMouseUp(x, y)
    if self.pressed and self.enabled then
        self.pressed = false
        HardcoreKitsUI.sound()
        if self.onClick then self.onClick(self.target, self) end
        return
    end
    self.pressed = false
end

-- ==================================================================
-- HardcoreKitsSummaryPanel: grade de resumo do resgate com altura FIXA de
-- 2 linhas de cartoes -- pedido explicito do usuario: antes disso, a grade
-- crescia sem limite e podia vazar da janela quando o resultado tinha
-- muitos itens (FoodDrinkMultiRollMode + recurso sem repeticao + bonus de
-- skill, todos ligados por padrao, facilmente passam de 2 linhas numa unica
-- captura). Quando o conteudo nao cabe, vira scroll de verdade -- reusa o
-- ISScrollBar nativo do jogo (self:addScrollBars()) em vez de reinventar
-- arraste/roda do mouse: o proprio scrollbar ja cuida disso sozinho
-- (ISScrollBar.lua), so escondendo automaticamente quando o conteudo cabe
-- (ver ISScrollBar:render(), "if sh > self:getHeight()").
--
-- O scroll nativo (setScrollChildren) desloca FILHOS de verdade (objetos
-- adicionados via addChild) -- os cartoes aqui sao desenho imediato (ver
-- HardcoreKitsUI.itemCard/skillCard), entao o deslocamento e feito a mao:
-- le self:getYScroll() (sempre <= 0 por convencao do engine) e desenha a
-- grade inteira deslocada por esse valor, com setStencilRect/clearStencilRect
-- (mesma tecnica que HardcoreKitsRouletteWidget ja usa pro giro horizontal
-- da roleta) cortando o que sair da area visivel.
HardcoreKitsSummaryPanel = ISPanel:derive("HardcoreKitsSummaryPanel")

HardcoreKitsSummaryPanel.DEFAULT_ROWS_VISIBLE = 2

-- altura pra mostrar `rows` linhas de cartao sem scroll -- static, nao
-- depende de instancia nenhuma (usado tanto pro tamanho inicial em :new()
-- quanto por :setRowsVisible abaixo).
function HardcoreKitsSummaryPanel.heightForRows(rows)
    local h = HardcoreKitsUI.RESULT_CARD_H
    local gap = HardcoreKitsUI.RESULT_CARD_GAP
    return rows * h + (rows - 1) * gap
end

function HardcoreKitsSummaryPanel:new(x, y, w)
    local rows = HardcoreKitsSummaryPanel.DEFAULT_ROWS_VISIBLE
    local o = ISPanel:new(x, y, w, HardcoreKitsSummaryPanel.heightForRows(rows))
    setmetatable(o, self)
    self.__index = self
    o.background = false
    o.items = {}
    o.lastItemCount = 0
    o.followNewest = false
    o.rowsVisible = rows
    return o
end

-- pedido explicito do usuario: no modo roleta rapida, uma vez terminada, o
-- resumo nao compete mais por espaco com nenhuma roleta (a interface fica
-- so pra ele) -- pode ficar maior que as 2 linhas padrao. Instancia por
-- instancia (cada aba tem seu proprio HardcoreKitsSummaryPanel) -- no-op se
-- o numero de linhas nao mudou, pra nao reajustar altura/scroll a toa a
-- cada frame.
function HardcoreKitsSummaryPanel:setRowsVisible(rows)
    if rows == self.rowsVisible then return end
    self.rowsVisible = rows
    self:setHeight(HardcoreKitsSummaryPanel.heightForRows(rows))
end

function HardcoreKitsSummaryPanel:initialise()
    ISPanel.initialise(self)
    self:addScrollBars()
end

-- chamado pela aba (Tab_Initial/Tab_Survival) toda vez que a lista de
-- passos ja revelados pode ter mudado. Se a lista CRESCEU (a roleta acabou
-- de revelar mais um item/skill), a rolagem persegue o fim sozinha -- sem
-- isso, um resultado com mais de 2 linhas ficava com os itens mais recentes
-- escondidos abaixo da dobra, exigindo rolagem manual pra ver o que acabou
-- de cair (pedido explicito do usuario)
function HardcoreKitsSummaryPanel:setItems(items)
    items = items or {}
    if #items > self.lastItemCount then
        self.followNewest = true
    end
    if self.items ~= items then self._resultLayout = nil end
    self.items = items
    self.lastItemCount = #items
end

function HardcoreKitsSummaryPanel:render()
    local availW = self:getScrollAreaWidth() -- ja desconta a largura do scrollbar quando ele esta visivel
    local layout = self._resultLayout
    if not layout or layout.items ~= self.items or layout.width ~= availW then
        local rows, widths, height = HardcoreKitsUI.computeResultRows(self.items, availW)
        layout = { items = self.items, width = availW, rows = rows, widths = widths, height = height }
        self._resultLayout = layout
    end
    local contentH = layout.height
    self:setScrollHeight(math.max(contentH, self:getScrollAreaHeight()))

    if self.followNewest then
        -- getYScroll() e sempre <= 0 (0 = topo, mais negativo = mais rolado
        -- pra baixo) -- o "fundo" fica em -(altura do conteudo - altura
        -- visivel), a mesma clamp que setYScroll ja aplica sozinho
        local bottomY = -math.max(contentH - self:getScrollAreaHeight(), 0)
        local next = HardcoreKitsUI.glide(self:getYScroll(), bottomY, 0.35)
        self:setYScroll(next)
        if next == bottomY then self.followNewest = false end
    end

    self:setStencilRect(0, 0, availW, self.height)
    HardcoreKitsUI.renderResultGrid(self, self.items, 0, self:getYScroll(), availW,
        layout.rows, layout.widths, layout.height)
    self:clearStencilRect()
end
