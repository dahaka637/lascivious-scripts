-- Paleta de cores e helpers de desenho da GUI. Namespace separado do
-- HardcoreKits compartilhado (protocolo/config) de proposito -- isso aqui e
-- puramente client/renderizacao, servidor nunca deveria tocar nisso.
--
-- A tecnica de desenho (retangulo arredondado feito de 4 texturas de canto +
-- sombra via textura de glow) e portada do Aegis Panel (autorizado
-- explicitamente pelo usuario). As texturas cnr_tl/tr/bl/br e glow sao
-- mascaras brancas neutras (conferido abrindo os PNGs: forma branca em fundo
-- transparente) -- a cor de verdade vem do tint passado em drawTextureScaled,
-- entao usar os mesmos arquivos com a NOSSA paleta abaixo produz um visual
-- com a mesma linguagem, mas nas nossas cores, nao nas do Aegis.
require "ISUI/ISPanel"
require "ISUI/ISInventoryItem"

HardcoreKitsUI = HardcoreKitsUI or {}

-- Identidade visual do servidor: violeta eletrico sobre fundos ameixa quase
-- pretos. Os tons de superficie sobem em luminosidade em passos pequenos pra
-- separar janela/painel/cartao sem virar uma interface cinza. Verde e coral
-- ficam reservados a estados semanticos (sucesso/erro), nunca a decoracao.
HardcoreKitsUI.col = {
    bg      = { r = 0.059, g = 0.039, b = 0.086 }, -- #0f0a16
    panel   = { r = 0.090, g = 0.059, b = 0.129 }, -- #170f21
    card    = { r = 0.129, g = 0.082, b = 0.184 }, -- #21152f
    cardHi  = { r = 0.188, g = 0.118, b = 0.275 }, -- #301e46
    line    = { r = 0.286, g = 0.204, b = 0.373 }, -- #49345f
    accent  = { r = 0.486, g = 0.227, b = 0.929 }, -- #7c3aed
    accentHi= { r = 0.769, g = 0.710, b = 0.992 }, -- #c4b5fd
    accentDim = { r = 0.298, g = 0.180, b = 0.459 }, -- #4c2e75
    text    = { r = 0.953, g = 0.929, b = 1.000 }, -- #f3edff
    muted   = { r = 0.608, g = 0.541, b = 0.686 }, -- #9b8aaf
    danger  = { r = 1.000, g = 0.400, b = 0.541 }, -- #ff668a
    ok      = { r = 0.388, g = 0.839, b = 0.639 }, -- #63d6a3
    dark    = { r = 0.027, g = 0.016, b = 0.043 }, -- #07040b
    white   = { r = 1, g = 1, b = 1 },
    -- cores do tier do bonus de habilidade (secao "skill boost") -- pedido
    -- explicito do usuario: muito pouco azul, baixo laranja, medio amarelo,
    -- alto verde vivo.
    tierVeryLow = { r = 0.455, g = 0.600, b = 1.000 },
    tierLow    = { r = 1.000, g = 0.565, b = 0.345 },
    tierMedium = { r = 0.973, g = 0.800, b = 0.310 },
    tierHigh   = { r = 0.400, g = 0.920, b = 0.635 },
}

-- Multiplicador de alpha "modo perigo" (zumbi muito perto, ver Window.lua) --
-- 1.0 = normal. So a JANELA muda este valor, uma vez por frame no proprio
-- prerender(); todo o resto do arquivo (chamado pela janela e pelos paineis
-- de aba dela) so LE. O botao de fechar fica de fora marcando
-- el.hkNoDim = true na propria instancia (ver HardcoreKitsWindow:createChildren)
-- -- assim ele continua visivel/clicavel mesmo com o resto da interface
-- translucida, pro jogador sempre conseguir fechar rapido.
--
-- Injetado so nas primitivas de desenho FOLHA (as que chamam el:drawRect/
-- drawText/drawTextureScaled de verdade) -- roundFrame, itemCard, skillCard,
-- textFit e companhia so chamam essas por baixo, entao o efeito ja cobre
-- tudo sem precisar tocar em cada uma delas.
HardcoreKitsUI.dimAlpha = 1.0
local function dim(el, a)
    a = a or 1
    if el and el.hkNoDim then return a end
    return a * HardcoreKitsUI.dimAlpha
end

local texCache = {}
function HardcoreKitsUI.tex(name)
    local t = texCache[name]
    if t == nil then
        t = getTexture("media/ui/HardcoreKits/" .. name .. ".png") or false
        texCache[name] = t
    end
    if t == false then return nil end
    return t
end

local scriptItemCache = {}
function HardcoreKitsUI.scriptItem(fullType)
    if type(fullType) ~= "string" or fullType == "" then return nil end
    local cached = scriptItemCache[fullType]
    if cached ~= nil then return cached ~= false and cached or nil end
    local ok, scriptItem = pcall(function() return getScriptManager():FindItem(fullType) end)
    scriptItemCache[fullType] = (ok and scriptItem) or false
    return ok and scriptItem or nil
end

-- delta de frame normalizado a 30 FPS, travado contra engasgo
function HardcoreKitsUI.delta()
    local d = UIManager.getMillisSinceLastRender() / 33.3
    if d > 3 then d = 3 end
    return d
end

function HardcoreKitsUI.glide(cur, target, rate)
    local t = rate * HardcoreKitsUI.delta()
    if t > 1 then t = 1 end
    local v = cur + (target - cur) * t
    if math.abs(target - v) < 0.002 then return target end
    return v
end

-- retangulo preenchido com cantos arredondados, feito de 4 texturas de quarto de circulo
function HardcoreKitsUI.roundRect(el, x, y, w, h, r, a, c)
    a = dim(el, a)
    local half = math.floor(math.min(w, h) / 2)
    if r > half then r = half end
    if r < 1 then
        el:drawRect(x, y, w, h, a, c.r, c.g, c.b)
        return
    end
    el:drawTextureScaled(HardcoreKitsUI.tex("cnr_tl"), x, y, r, r, a, c.r, c.g, c.b)
    el:drawTextureScaled(HardcoreKitsUI.tex("cnr_tr"), x + w - r, y, r, r, a, c.r, c.g, c.b)
    el:drawTextureScaled(HardcoreKitsUI.tex("cnr_bl"), x, y + h - r, r, r, a, c.r, c.g, c.b)
    el:drawTextureScaled(HardcoreKitsUI.tex("cnr_br"), x + w - r, y + h - r, r, r, a, c.r, c.g, c.b)
    if w > 2 * r then
        el:drawRect(x + r, y, w - 2 * r, r, a, c.r, c.g, c.b)
        el:drawRect(x + r, y + h - r, w - 2 * r, r, a, c.r, c.g, c.b)
    end
    if h > 2 * r then
        el:drawRect(x, y + r, w, h - 2 * r, a, c.r, c.g, c.b)
    end
end

-- moldura arredondada: cor de borda embaixo, preenchimento por cima recuado 1px
function HardcoreKitsUI.roundFrame(el, x, y, w, h, r, a, cBorder, cFill)
    HardcoreKitsUI.roundRect(el, x, y, w, h, r, a, cBorder)
    HardcoreKitsUI.roundRect(el, x + 1, y + 1, w - 2, h - 2, math.max(1, r - 1), a, cFill)
end

function HardcoreKitsUI.shadow(el, x, y, w, h, spread, a)
    local t = HardcoreKitsUI.tex("glow")
    if t then
        el:drawTextureScaled(t, x - spread, y - spread + 6, w + spread * 2, h + spread * 2, dim(el, a), 0, 0, 0)
    end
end

-- Halo colorido discreto. Usa a mesma mascara neutra da sombra, mas separado
-- dela pra o roxo aparecer apenas nos elementos importantes (janela, CTA em
-- hover e vencedor da roleta), sem tingir todas as superficies por igual.
function HardcoreKitsUI.glow(el, x, y, w, h, spread, a, c)
    local t = HardcoreKitsUI.tex("glow")
    if not t then return end
    c = c or HardcoreKitsUI.col.accent
    el:drawTextureScaled(t, x - spread, y - spread, w + spread * 2, h + spread * 2,
        dim(el, a or 0.12), c.r, c.g, c.b)
end

function HardcoreKitsUI.hairline(el, x, y, w, a, c)
    c = c or HardcoreKitsUI.col.line
    if w <= 0 then return end
    el:drawRect(x, y, w, 1, dim(el, a or 1), c.r, c.g, c.b)
end

-- cabecalho "titulo com linha divisoria dos dois lados", centralizado numa
-- faixa de largura w (ex: "COMIDA" no topo da roleta). Trunca o texto com
-- ".." se nem com as duas linhas no minimo ele couber em w -- ver fitText.
function HardcoreKitsUI.centeredDivider(el, text, x, y, w, font, color, lineColor)
    local pad = 16
    local minLine = 16
    text = HardcoreKitsUI.fitText(text, font, math.max(10, w - pad * 2 - minLine * 2))
    local tw = HardcoreKitsUI.strW(font, text)
    local lineY = y + math.floor(HardcoreKitsUI.fontH(font) / 2)
    local textX = x + math.floor((w - tw) / 2)
    HardcoreKitsUI.hairline(el, x, lineY, math.max(0, textX - pad - x), 1, lineColor)
    HardcoreKitsUI.text(el, text, textX, y, font, color)
    local afterX = textX + tw + pad
    HardcoreKitsUI.hairline(el, afterX, lineY, math.max(0, x + w - afterX), 1, lineColor)
end

-- cabecalho "titulo alinhado a esquerda + linha preenchendo o resto", usado
-- fora da roleta (ex: "RESUMO DOS RESGATES"). Mesmo truncamento do de cima.
function HardcoreKitsUI.leftDivider(el, text, x, y, w, font, color, lineColor)
    local pad = 16
    local minLine = 16
    text = HardcoreKitsUI.fitText(text, font, math.max(10, w - pad - minLine))
    HardcoreKitsUI.text(el, text, x, y, font, color)
    local tw = HardcoreKitsUI.strW(font, text)
    local lineY = y + math.floor(HardcoreKitsUI.fontH(font) / 2)
    local afterX = x + tw + pad
    HardcoreKitsUI.hairline(el, afterX, lineY, math.max(0, x + w - afterX), 1, lineColor)
end

-- cartao "icone do item centralizado + xN embaixo" usado no resumo de
-- resgates (substitui a lista de texto da versao anterior). w/h e o cartao
-- inteiro; o icone ocupa a metade de cima, qty e label ficam embaixo dele.
function HardcoreKitsUI.itemCard(el, x, y, w, h, fullType, qty, label, highlight)
    local c = HardcoreKitsUI.col
    if highlight then HardcoreKitsUI.glow(el, x, y, w, h, 8, 0.10, c.accent) end
    HardcoreKitsUI.roundFrame(el, x, y, w, h, 7, 1, highlight and c.accent or c.line,
        highlight and c.cardHi or c.card)
    if highlight then
        HardcoreKitsUI.hairline(el, x + 10, y + 2, w - 20, 0.70, c.accentHi)
    else
        HardcoreKitsUI.hairline(el, x + 10, y + 2, w - 20, 0.24, c.accentHi)
    end

    local iconSize = math.min(w - 12, 40)
    local iconX = x + math.floor((w - iconSize) / 2)
    local iconY = y + 8
    if fullType then
        local scriptItem = HardcoreKitsUI.scriptItem(fullType)
        if scriptItem then
            pcall(function()
                ISInventoryItem.renderScriptItemIcon(el, scriptItem, iconX, iconY, 1.0, iconSize, iconSize)
            end)
        end
    end

    local qtyY = iconY + iconSize + 4
    if qty and qty > 0 then
        HardcoreKitsUI.textCentre(el, "x" .. tostring(qty), x + math.floor(w / 2), qtyY, UIFont.Small, c.accentHi)
    end
    if label then
        HardcoreKitsUI.textCentreFit(el, label, x + math.floor(w / 2), qtyY + HardcoreKitsUI.fontH(UIFont.Small) + 2,
            w - 8, UIFont.Small, c.muted)
    end
end

-- ---------- bonus de habilidade (skill boost) ----------

local TIER_TEXT_KEYS = {
    verylow = "UI_HardcoreKits_TierVeryLow", low = "UI_HardcoreKits_TierLow",
    medium = "UI_HardcoreKits_TierMedium", high = "UI_HardcoreKits_TierHigh",
}
local TIER_COLOR_KEYS = { verylow = "tierVeryLow", low = "tierLow", medium = "tierMedium", high = "tierHigh" }

function HardcoreKitsUI.tierText(tier)
    local key = TIER_TEXT_KEYS[tier]
    return key and getText(key) or "-"
end

function HardcoreKitsUI.tierColor(tier)
    local key = TIER_COLOR_KEYS[tier]
    return (key and HardcoreKitsUI.col[key]) or HardcoreKitsUI.col.text
end

-- cartao de largura DINAMICA (bonus de habilidade: nome do grupo/skill em
-- cima + tier entre parenteses embaixo, colorido pelo tier) -- diferente do
-- itemCard, w NAO e fixo: quem desenha calcula com skillCardWidth antes.
local SKILL_CARD_PAD = 14
local SKILL_CARD_MINW = 92
-- pedido explicito do usuario: o nome da habilidade/grupo precisa ter fonte
-- MAIOR que o indicador de nivel, nao o contrario (estava invertido: nome em
-- Small, nivel em Medium -- trocado aqui, nos dois lugares que precisam
-- concordar: o calculo de largura do cartao E o desenho de verdade).
function HardcoreKitsUI.skillCardWidth(groupText, tierText)
    local gw = HardcoreKitsUI.strW(UIFont.Medium, groupText or "")
    local tw = HardcoreKitsUI.strW(UIFont.Small, "(" .. (tierText or "") .. ")")
    return math.max(SKILL_CARD_MINW, math.max(gw, tw) + SKILL_CARD_PAD * 2)
end

function HardcoreKitsUI.skillCard(el, x, y, w, h, groupText, tierText, tierColor, highlight)
    local c = HardcoreKitsUI.col
    if highlight then HardcoreKitsUI.glow(el, x, y, w, h, 8, 0.10, c.accent) end
    HardcoreKitsUI.roundFrame(el, x, y, w, h, 7, 1, highlight and c.accent or c.line,
        highlight and c.cardHi or c.card)
    if highlight then
        HardcoreKitsUI.hairline(el, x + 10, y + 2, w - 20, 0.70, c.accentHi)
    else
        HardcoreKitsUI.hairline(el, x + 10, y + 2, w - 20, 0.24, c.accentHi)
    end
    local cx = x + math.floor(w / 2)
    local groupY = y + math.floor(h / 2) - HardcoreKitsUI.fontH(UIFont.Medium) - 2
    HardcoreKitsUI.textCentreFit(el, groupText or "", cx, groupY, w - 8, UIFont.Medium, c.text)
    local tierY = groupY + HardcoreKitsUI.fontH(UIFont.Medium) + 4
    HardcoreKitsUI.textCentreFit(el, "(" .. (tierText or "") .. ")", cx, tierY, w - 8, UIFont.Small, tierColor or c.text)
end

-- passos ja concluidos da roleta atual que representam algo REALMENTE
-- entregue (item OU bonus de skill) -- ignora passos-meta ("quantos
-- resultados?") e cartoes de falha (como o "X" de arma de fogo ausente).
-- Substitui a antiga completedItemSteps (identica, copiada nas duas abas).
function HardcoreKitsUI.completedResultSteps(roulette)
    if not roulette then return {} end
    local upTo = roulette.finished and #roulette.steps or (roulette.stepIndex - 1)
    local cached = roulette._hkCompletedResultCache
    if cached and cached.steps == roulette.steps and cached.upTo == upTo and cached.length == #roulette.steps then
        return cached.items
    end
    local out = {}
    for i = 1, math.min(upTo, #roulette.steps) do
        local step = roulette.steps[i]
        local kind = step.winner and step.winner.kind
        if (kind == "item" and step.winner.fullType) or kind == "skill" then
            table.insert(out, step)
        end
    end
    roulette._hkCompletedResultCache = { steps = roulette.steps, upTo = upTo, length = #roulette.steps, items = out }
    return out
end

-- grade que mistura cartoes de largura FIXA (item) e DINAMICA (skill),
-- quebrando linha sozinha quando a largura acumulada estoura w. Separado em
-- duas funcoes: computeResultRows so CALCULA o layout (linhas + altura
-- total), sem desenhar nada -- usado tanto por renderResultGrid quanto por
-- HardcoreKitsSummaryPanel (HardcoreKits_Widgets.lua), que precisa saber a
-- altura do conteudo ANTES de desenhar pra configurar o scroll vertical.
HardcoreKitsUI.RESULT_CARD_H = 108
HardcoreKitsUI.RESULT_CARD_GAP = 10
local RESULT_CARD_H, RESULT_CARD_GAP = HardcoreKitsUI.RESULT_CARD_H, HardcoreKitsUI.RESULT_CARD_GAP

function HardcoreKitsUI.computeResultRows(steps, w)
    if #steps == 0 then return {}, {}, 0 end
    local widths = {}
    for i, step in ipairs(steps) do
        if step.winner.kind == "skill" then
            widths[i] = HardcoreKitsUI.skillCardWidth(step.winner.groupText, step.winner.tierText)
        else
            widths[i] = RESULT_CARD_H -- mesma largura fixa de sempre pro item card
        end
    end

    local rows, row, rowW = {}, {}, 0
    for i in ipairs(steps) do
        local cw = widths[i]
        local addW = (#row > 0) and (RESULT_CARD_GAP + cw) or cw
        if #row > 0 and rowW + addW > w then
            table.insert(rows, row)
            row, rowW = {}, 0
            addW = cw
        end
        table.insert(row, i)
        rowW = rowW + addW
    end
    if #row > 0 then table.insert(rows, row) end

    local totalH = #rows * RESULT_CARD_H + math.max(0, #rows - 1) * RESULT_CARD_GAP
    return rows, widths, totalH
end

-- desenha a grade a partir do layout ja calculado -- y pode ser negativo
-- (usado pelo scroll do HardcoreKitsSummaryPanel: linhas acima da area
-- visivel saem de tela por causa do stencil, nao por magica)
function HardcoreKitsUI.renderResultGrid(el, steps, x, y, w, rows, widths, totalH)
    if not rows or not widths or totalH == nil then
        rows, widths, totalH = HardcoreKitsUI.computeResultRows(steps, w)
    end
    if #rows == 0 then return 0 end

    local rowY = y
    for _, rowIdxs in ipairs(rows) do
        local rw = 0
        for j, i in ipairs(rowIdxs) do rw = rw + widths[i] + (j > 1 and RESULT_CARD_GAP or 0) end
        local rowX = x + math.floor((w - rw) / 2)
        for _, i in ipairs(rowIdxs) do
            local step = steps[i]
            local cw = widths[i]
            if step.winner.kind == "skill" then
                HardcoreKitsUI.skillCard(el, rowX, rowY, cw, RESULT_CARD_H,
                    step.winner.groupText, step.winner.tierText, step.winner.tierColor, step.highlight)
            else
                HardcoreKitsUI.itemCard(el, rowX, rowY, cw, RESULT_CARD_H,
                    step.winner.fullType, step.winner.qty, step.label, step.highlight)
            end
            rowX = rowX + cw + RESULT_CARD_GAP
        end
        rowY = rowY + RESULT_CARD_H + RESULT_CARD_GAP
    end
    return totalH
end

function HardcoreKitsUI.text(el, str, x, y, font, c, a)
    el:drawText(str, x, y, c.r, c.g, c.b, dim(el, a), font)
end

function HardcoreKitsUI.textCentre(el, str, x, y, font, c, a)
    el:drawTextCentre(str, x, y, c.r, c.g, c.b, dim(el, a), font)
end

function HardcoreKitsUI.textRight(el, str, x, y, font, c, a)
    el:drawTextRight(str, x, y, c.r, c.g, c.b, dim(el, a), font)
end

function HardcoreKitsUI.fontH(font)
    return getTextManager():getFontHeight(font)
end

function HardcoreKitsUI.strW(font, str)
    return getTextManager():MeasureStringX(font, str)
end

-- corta o texto pra caber em maxW, terminando com ".."
function HardcoreKitsUI.fitText(str, font, maxW)
    if not str or str == "" then return "" end
    if HardcoreKitsUI.strW(font, str) <= maxW then return str end
    local s = str
    while string.len(s) > 1 and HardcoreKitsUI.strW(font, s .. "..") > maxW do
        s = string.sub(s, 1, string.len(s) - 1)
    end
    return s .. ".."
end

-- variantes de text()/textCentre() que NUNCA vazam de maxW -- truncam com
-- ".." antes de desenhar (ver fitText). Usar em qualquer rotulo de largura
-- fixa (abas, status, badges, cartoes) em vez de text()/textCentre() puro,
-- ja que o texto agora vem de getText() e o mesmo rotulo tem tamanhos bem
-- diferentes em EN/PTBR (ex: "MUNICAO" vs "AMMO").
function HardcoreKitsUI.textFit(el, str, x, y, maxW, font, c, a)
    HardcoreKitsUI.text(el, HardcoreKitsUI.fitText(str, font, maxW), x, y, font, c, a)
end

function HardcoreKitsUI.textCentreFit(el, str, x, y, maxW, font, c, a)
    HardcoreKitsUI.textCentre(el, HardcoreKitsUI.fitText(str, font, maxW), x, y, font, c, a)
end

-- tooltip compartilhado (mesmo padrao do ISButton), chamar a partir de prerender()
function HardcoreKitsUI.updateTooltip(el)
    if (el:isMouseOver() or el.joypadFocused) and el.tooltip and el.tooltip ~= "" then
        if not el.tooltipUI then
            el.tooltipUI = ISToolTip:new()
            el.tooltipUI:setOwner(el)
            el.tooltipUI:setVisible(false)
            el.tooltipUI:setAlwaysOnTop(true)
        end
        if not el.tooltipUI:getIsVisible() then
            el.tooltipUI.maxLineWidth = 280
            el.tooltipUI:addToUIManager()
            el.tooltipUI:setVisible(true)
        end
        el.tooltipUI.description = el.tooltip
        el.tooltipUI:setDesiredPosition(getMouseX(), el:getAbsoluteY() + el:getHeight() + 8)
    elseif el.tooltipUI and el.tooltipUI:getIsVisible() then
        el.tooltipUI:setVisible(false)
        el.tooltipUI:removeFromUIManager()
    end
end

-- motivos de CMD_CLAIM_ERROR que NAO tem nenhum campo equivalente no state
-- persistente (cooldown/ja-resgatado/desativado/nao-conquistada ja aparecem
-- sozinhos assim que o state ressincroniza -- ver HardcoreKits_Client.lua) --
-- alguns ainda ganham mensagem temporaria para a tela nao piscar em vazio
-- enquanto o state novo chega do servidor.
local CLAIM_ERROR_KEYS = {
    already_claimed_account = "UI_HardcoreKits_StatusInitialAlreadyClaimedAccount",
    already_claimed_character = "UI_HardcoreKits_StatusInitialAlreadyClaimed",
    dead = "UI_HardcoreKits_ErrorDead",
    pending_exists = "UI_HardcoreKits_ErrorPending",
    delivery_failed = "UI_HardcoreKits_ErrorDeliveryFailed",
}
function HardcoreKitsUI.claimErrorText(reason)
    local key = CLAIM_ERROR_KEYS[reason]
    if not key then return nil end
    return getText(key)
end

function HardcoreKitsUI.claimNoticeText(reason)
    if reason == "partial_delivery" then
        return getText("UI_HardcoreKits_PartialDelivery")
    end
    return nil
end

function HardcoreKitsUI.sound()
    pcall(function() getSoundManager():playUISound("UIActivateButton") end)
end

-- triangulo feito de linhas finas empilhadas -- nao existe uma primitiva de
-- triangulo generica no engine (checado: "self:drawTriangle" so existe como
-- metodo proprio de classes especificas como ISFluidBar, nao do ISUIElement
-- base), entao desenhamos a mao com drawRect, mesma tecnica que o vanilla usa.
-- Vertical: aponta pra baixo (base em cima) ou pra cima (base embaixo).
function HardcoreKitsUI.triangleV(el, centerX, topY, size, pointingDown, a, c)
    a = dim(el, a)
    for i = 0, size - 1 do
        local half = size - i
        local y = pointingDown and (topY + i) or (topY + (size - 1 - i))
        el:drawRect(centerX - half, y, half * 2, 1, a, c.r, c.g, c.b)
    end
end

-- horizontal: aponta pra direita ou esquerda (usado nos chevrons da roleta)
function HardcoreKitsUI.triangleH(el, leftX, centerY, size, pointingRight, a, c)
    a = dim(el, a)
    for i = 0, size - 1 do
        local half = size - i
        local x = pointingRight and (leftX + i) or (leftX + (size - 1 - i))
        el:drawRect(x, centerY - half, 1, half * 2, a, c.r, c.g, c.b)
    end
end

-- tick curto por item passando na roleta -- som real vanilla verificado em
-- media/lua/client (usado normalmente pra selecionar item de lista, cadencia
-- leve o bastante pra repetir a cada card sem cansar)
function HardcoreKitsUI.tickSound()
    pcall(function() getSoundManager():playUISound("UISelectListItem") end)
end
