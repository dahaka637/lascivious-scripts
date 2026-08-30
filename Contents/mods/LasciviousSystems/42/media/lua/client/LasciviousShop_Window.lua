if isServer() then return end

require "ISUI/ISPanel"
require "ISUI/ISTextEntryBox"
require "ISUI/ISComboBox"
require "ISUI/ISInventoryItem"
require "LasciviousShop_Shared"
require "LasciviousShop_Catalog"
require "LasciviousShop_Client"
require "LasciviousShop_Theme"
require "LasciviousShop_SearchIndex"
require "LasciviousShop_VehicleScene"
require "LasciviousShop_Danger"

local LS = LasciviousShop
local Client = LasciviousShopClient
local UI = LasciviousShopUI
local Search = LasciviousShopSearchIndex

-- A debug Lua reload replaces this class table. Retire the previous instance
-- and its closures first; otherwise its invisible UI object and Client listener
-- remain strongly referenced for the rest of the client session.
local previousWindowClass = LasciviousShopWindow
local previousDeathHandler = previousWindowClass and previousWindowClass._playerDeathHandler
local previousWindow = previousWindowClass and previousWindowClass.instance
if previousDeathHandler and Events.OnPlayerDeath.Remove then
    Events.OnPlayerDeath.Remove(previousDeathHandler)
end
if previousWindow then
    if previousWindow._networkListener then
        Client.offUpdate(previousWindow._networkListener)
        previousWindow._networkListener = nil
    end
    pcall(function()
        previousWindow:setVisible(false)
        if previousWindow.removeFromUIManager then previousWindow:removeFromUIManager() end
    end)
end

LasciviousShopWindow = ISPanel:derive("LasciviousShopWindow")
LasciviousShopWindow.instance = nil

-- ===================================================================
-- Danger dimming (zombie proximity): fades the whole interface's alpha so
-- the player can see -- and react to -- the game world behind it instead of
-- getting ambushed while shopping. This window mixes UI.* helper calls with
-- plenty of raw self:drawRect/drawTextureScaled calls (see drawHeader,
-- drawSidebar, drawCart...), so patching UI.* alone would only dim half the
-- interface. Overriding the primitive draw methods themselves catches
-- everything in one place, regardless of which helper (if any) a given call
-- goes through -- same principle as HardcoreKits_Theme.lua's dim(), just
-- applied at the element level instead of inside a shared UI module.
--
-- self._dimAlpha (1.0 = normal) is recomputed once per frame in
-- updateDangerAlpha(); self._dimExempt is a transient flag toggled around
-- the close button's own draw calls (see drawHeader) so it always stays
-- fully visible/legible no matter how faded the rest of the window gets.
local BaseDrawRect = ISPanel.drawRect
local BaseDrawText = ISPanel.drawText
local BaseDrawTextCentre = ISPanel.drawTextCentre
local BaseDrawTextRight = ISPanel.drawTextRight
local BaseDrawTextureScaled = ISPanel.drawTextureScaled

local function dimmedAlpha(self, alpha)
    alpha = alpha or 1
    if self._dimExempt then return alpha end
    return alpha * (self._dimAlpha or 1)
end

function LasciviousShopWindow:drawRect(x, y, w, h, a, r, g, b)
    BaseDrawRect(self, x, y, w, h, dimmedAlpha(self, a), r, g, b)
end

function LasciviousShopWindow:drawText(str, x, y, r, g, b, a, font)
    BaseDrawText(self, str, x, y, r, g, b, dimmedAlpha(self, a), font)
end

function LasciviousShopWindow:drawTextCentre(str, x, y, r, g, b, a, font)
    BaseDrawTextCentre(self, str, x, y, r, g, b, dimmedAlpha(self, a), font)
end

function LasciviousShopWindow:drawTextRight(str, x, y, r, g, b, a, font)
    BaseDrawTextRight(self, str, x, y, r, g, b, dimmedAlpha(self, a), font)
end

function LasciviousShopWindow:drawTextureScaled(texture, x, y, w, h, a, r, g, b)
    BaseDrawTextureScaled(self, texture, x, y, w, h, dimmedAlpha(self, a), r, g, b)
end

local EDGE = 12
local DESIGN_W, DESIGN_H = 1500, 900
local MIN_W, MIN_H = 850, 540
local RESIZE_GRIP = 18
local PANEL_STATE_KEY = "LasciviousShop_panelState"
local TRANSFER_POPUP_W, TRANSFER_POPUP_H = 460, 560
local TRANSFER_EDGE = 18
local TRANSFER_ROW_H = 44
local TRANSFER_ROW_GAP = 6
local TRANSFER_LIST_REFRESH_SECONDS = 4
local scriptItemCache = {}
-- Furniture/appliance/crafting-station "Mov_*" items almost never have a
-- real inventory Icon (script field literally says Icon=default), which the
-- game renders as a generic "?" -- but every one of them DOES carry a real
-- WorldObjectSprite (the tile art used when it's actually placed). Cached
-- per fullType: false once resolved (no usable world sprite / has a real
-- icon already), otherwise the resolved Texture to draw instead.
local worldSpriteIconCache = {}
local SORT_OPTIONS = {
    { id="default",       labelKey="SortDefault",      fallback="Ordenação padrão" },
    { id="name_asc",      labelKey="SortNameAsc",      fallback="Nome: A–Z" },
    { id="name_desc",     labelKey="SortNameDesc",     fallback="Nome: Z–A" },
    { id="price_asc",     labelKey="SortPriceAsc",     fallback="Preço: menor primeiro" },
    { id="price_desc",    labelKey="SortPriceDesc",    fallback="Preço: maior primeiro" },
    { id="discount_desc", labelKey="SortDiscountDesc", fallback="Maior desconto" },
}
local VALID_SORT_MODES = {}
for _, option in ipairs(SORT_OPTIONS) do VALID_SORT_MODES[option.id] = true end

local function clamp(value, minimum, maximum)
    return math.max(minimum, math.min(value, maximum))
end

local function round(value)
    return math.floor(value + 0.5)
end

-- Products that only ever make sense as a single unit per purchase: the
-- emergency cure (its effect doesn't stack) and vehicles (each unit is a
-- whole separate physical spawn+placement search).
local function isSingleUseKind(kind)
    return kind == "cure" or kind == "vehicle"
end

local function reuseRect(rects, index, x, y, w, h)
    local rect = rects[index]
    if not rect then
        rect = {}
        rects[index] = rect
    end
    rect.x, rect.y, rect.w, rect.h = x, y, w, h
    return rect
end

local function trimRects(rects, count)
    for index = #rects, count + 1, -1 do rects[index] = nil end
end

local EMPTY_STATE = {}
local function state()
    return Client.state or EMPTY_STATE
end

local function texture(name)
    return UI.tex(name)
end

local function worldSpriteTexture(product, scriptItem)
    local cached = worldSpriteIconCache[product.fullType]
    if cached ~= nil then return cached or nil end
    local resolved = false
    local ok, icon = pcall(function() return scriptItem:getIcon() end)
    if ok and (not icon or icon == "" or icon == "default") then
        local ok2, spriteName = pcall(function() return scriptItem:getWorldObjectSprite() end)
        if ok2 and spriteName and spriteName ~= "" then
            local ok3, tex = pcall(getTexture, spriteName)
            if ok3 and tex then resolved = tex end
        end
    end
    worldSpriteIconCache[product.fullType] = resolved
    return resolved or nil
end

local function renderProductIcon(element, product, x, y, size, alpha)
    if not product then return end
    if product.kind == "item" then
        local scriptItem = scriptItemCache[product.fullType]
        if scriptItem == nil then
            local ok, value = pcall(function() return getScriptManager():FindItem(product.fullType) end)
            scriptItem = ok and value or false
            scriptItemCache[product.fullType] = scriptItem
        end
        if scriptItem and scriptItem ~= false then
            local spriteTex = worldSpriteTexture(product, scriptItem)
            if spriteTex then
                element:drawTextureScaled(spriteTex, x, y, size, size, alpha or 1, 1, 1, 1)
            else
                -- This is called for every visible inventory-product card on
                -- every frame. Passing the function/arguments directly avoids
                -- allocating a fresh protective closure for each icon draw.
                pcall(ISInventoryItem.renderScriptItemIcon,
                    element, scriptItem, x, y, alpha or 1, size, size)
            end
        end
    else
        local icon = texture(product.skillIcon or "xp-logo")
        if icon then element:drawTextureScaled(icon, x, y, size, size, alpha or 1, 1, 1, 1) end
    end
end

-- Dedicated child grips win hit-testing over the search box and the cart. The
-- window owns all clamping and reflow, so both corners behave identically.
local ResizeGrip = ISPanel:derive("LasciviousShopResizeGrip")

function ResizeGrip:new(x, y, size, corner, window)
    local o = ISPanel:new(x, y, size, size)
    setmetatable(o, self)
    self.__index = self
    o.background = false
    o.corner = corner
    o.ownerWindow = window
    o.dragging = false
    return o
end

function ResizeGrip:onMouseDown(x, y)
    self.dragging = true
    self:setCapture(true)
    if self.ownerWindow then self.ownerWindow:bringToTop() end
    return true
end

function ResizeGrip:onMouseMove(dx, dy)
    if self.dragging and self.ownerWindow then self.ownerWindow:resizeByDelta(self.corner, dx, dy) end
end

function ResizeGrip:onMouseMoveOutside(dx, dy)
    self:onMouseMove(dx, dy)
end

function ResizeGrip:onMouseUp(x, y)
    if self.dragging then
        self.dragging = false
        self:setCapture(false)
        if self.ownerWindow then self.ownerWindow:endResize() end
    end
    return true
end

function ResizeGrip:onMouseUpOutside(x, y)
    return self:onMouseUp(x, y)
end

function ResizeGrip:prerender() end
function ResizeGrip:render() end

local function formatClock(seconds)
    seconds = math.max(0, math.floor(tonumber(seconds) or 0))
    local hours = math.floor(seconds / 3600)
    local minutes = math.floor((seconds % 3600) / 60)
    local secs = seconds % 60
    if hours > 0 then return string.format("%02d:%02d:%02d", hours, minutes, secs) end
    return string.format("%02d:%02d", minutes, secs)
end

local function commaCredits(value)
    return (string.gsub(LS.formatCredits(value), "%.", ","))
end

function LasciviousShopWindow:new(x, y, width, height)
    local o = ISPanel:new(x, y, width, height)
    setmetatable(o, self)
    self.__index = self
    o.background = false
    o.moveWithMouse = false
    o.dragging = false
    o._resizing = false
    o.activeCategory = "all"
    o.sortMode = "default"
    o.currentPage = 1
    o.cart = {}
    o.cartOrder = {}
    o.cartScroll = 0
    o.categoryRects = {}
    o.cardRects = {}
    o.vehicleScenePool = {}
    o.cartMinusRects = {}
    o.cartPlusRects = {}
    o.pageRects = {}
    o.lastStateRequest = 0
    o.toastText = nil
    o.toastUntil = 0
    o.handledResult = nil
    o.handledError = nil
    o._filterDirty = true
    o._filteredProductIds = {}
    o._searchResultCache = {}
    o._searchResultCacheOrder = {}
    o._priceCache = {}
    o._originalPriceCache = {}
    o._priceCacheCommerce = {}
    o._originalPriceCacheCommerce = {}
    o._networkStateSignature = nil
    o._lastRawQuery = ""
    o._autoSwitchedQuery = nil
    o.marqueeProductId = nil
    o.marqueeStartedAt = 0
    o.transferOpen = false
    o.transferSelectedTarget = nil
    o.transferPlayerRects = {}
    o.transferListScroll = 0
    o.transferLastListRequest = 0
    o.transferHandledResult = nil
    o.transferCanSend = false
    o._dimAlpha = 1.0
    o._dimExempt = false
    o._dangerNear = false
    o._dangerCheckedAtMs = nil
    o._lastAttacker = nil
    o._clientOptions = nil
    o._clientOptionsReadAt = 0
    o._transferFilterQuery = nil
    o._transferFilterReceivedAt = nil
    o._transferFilteredPlayers = nil
    o:setWantKeyEvents(true)
    return o
end

function LasciviousShopWindow:layout()
    if self._layoutCache and self._layoutCacheWidth == self.width
        and self._layoutCacheHeight == self.height then
        return self._layoutCache
    end
    local scale = clamp(math.min(self.width / DESIGN_W, self.height / DESIGN_H), 0.68, 1.15)
    local headerH = clamp(round(66 * scale), 48, 72)
    local sidebarW = clamp(round(self.width * 0.15), round(166 * scale), round(225 * scale))
    local cartW = clamp(round(self.width * 0.213), 220, math.max(220, round(320 * scale)))
    local mainX = sidebarW + 1
    local mainW = self.width - sidebarW - cartW - 2
    local mainPad = clamp(round(20 * scale), 12, 23)
    local sectionGap = clamp(round(14 * scale), 9, 16)
    local balanceY = headerH + sectionGap
    local balanceH = clamp(round(90 * scale), 68, 100)
    local toolbarH = clamp(round(40 * scale), 34, 44)
    local toolbarY = balanceY + balanceH + sectionGap
    local paginationH = clamp(round(44 * scale), 38, 48)
    local paginationY = self.height - paginationH
    local gridY = toolbarY + toolbarH + sectionGap
    local gridH = math.max(150, paginationY - gridY - clamp(round(9 * scale), 6, 11))
    local contentW = mainW - mainPad * 2
    local cardGap = clamp(round(10 * scale), 7, 12)
    local minCardW = clamp(round(145 * scale), 124, 160)
    local columns = clamp(math.floor((contentW + cardGap) / (minCardW + cardGap)), 2, 4)
    local rows = gridH >= 135 * 3 + cardGap * 2 and 3 or 2
    local sortW = clamp(round(210 * scale), 170, 235)
    local toolbarGap = clamp(round(10 * scale), 7, 12)
    local searchW = math.max(150, contentW - sortW - toolbarGap)
    local sortX = mainX + mainPad + contentW - sortW
    local categoryRowH = clamp(round(42 * scale), 32, 46)
    local categoryGap = clamp(round(7 * scale), 4, 8)
    local cartRowH = clamp(round(62 * scale), 52, 68)
    local result = {
        scale=scale, headerH=headerH,
        sidebarW=sidebarW, cartW=cartW, cartX=self.width-cartW,
        mainX=mainX, mainW=mainW, mainPad=mainPad,
        balanceY=balanceY, balanceH=balanceH,
        toolbarY=toolbarY, toolbarH=toolbarH,
        gridY=gridY, gridH=gridH, paginationY=paginationY,
        contentX=mainX+mainPad, contentW=contentW,
        columns=columns, rows=rows, perPage=columns*rows,
        cardGap=cardGap, searchW=searchW, sortX=sortX, sortW=sortW,
        categoryRowH=categoryRowH, categoryGap=categoryGap,
        cartRowH=cartRowH,
    }
    self._layoutCache = result
    self._layoutCacheWidth = self.width
    self._layoutCacheHeight = self.height
    return result
end

function LasciviousShopWindow:markFilterDirty()
    self._filterDirty = true
    self.currentPage = 1
end

function LasciviousShopWindow:createChildren()
    local l = self:layout()
    local searchInset = clamp(round(35 * l.scale), 31, 39)
    self.searchEntry = ISTextEntryBox:new("", l.contentX + searchInset, l.toolbarY + 3,
        l.searchW - searchInset, l.toolbarH - 4)
    self.searchEntry.font = UIFont.Small
    self.searchEntry.backgroundColor = { r=UI.col.panel2.r, g=UI.col.panel2.g, b=UI.col.panel2.b, a=0.95 }
    self.searchEntry.borderColor = { r=UI.col.line.r, g=UI.col.line.g, b=UI.col.line.b, a=0 }
    self.searchEntry:setPlaceholderText(LS.text("Search", "Buscar item..."))
    self.searchEntry:setTooltip(LS.text("SearchHint",
        "A busca ignora acentos e tolera pequenos erros de digitação."))
    self.searchEntry.target = self
    self.searchEntry.onTextChangeFunction = function(target)
        target:markFilterDirty()
    end
    self.searchEntry:initialise()
    self.searchEntry:instantiate()
    self.searchEntry:setClearButton(true)
    -- UITextBox2 supports vertical centering (setCentreVertically) but defaults
    -- to false, and vanilla's ISTextEntryBox.lua never exposes/calls it -- so a
    -- box taller than one line of text (ours is, toolbarH-4) renders the text
    -- pinned near the top with dead space below instead of centered. Confirmed
    -- via decompiling UITextBox2.render(): the centered branch computes
    -- (getHeight() - MeasureStringY(font, text)) / 2, the real fix, not a
    -- padding/offset workaround.
    if self.searchEntry.javaObject and self.searchEntry.javaObject.setCentreVertically then
        self.searchEntry.javaObject:setCentreVertically(true)
    end
    self:addChild(self.searchEntry)

    self.sortCombo = ISComboBox:new(l.sortX, l.toolbarY + 2, l.sortW, l.toolbarH - 4,
        self, LasciviousShopWindow.onSortChanged)
    self.sortCombo:initialise()
    self.sortCombo:instantiate()
    self.sortCombo.backgroundColor = { r=UI.col.panel2.r, g=UI.col.panel2.g, b=UI.col.panel2.b, a=0.98 }
    self.sortCombo.backgroundColorMouseOver = {
        r=UI.col.accentDim.r, g=UI.col.accentDim.g, b=UI.col.accentDim.b, a=0.92,
    }
    self.sortCombo.borderColor = { r=UI.col.line.r, g=UI.col.line.g, b=UI.col.line.b, a=1 }
    self.sortCombo.textColor = { r=UI.col.text.r, g=UI.col.text.g, b=UI.col.text.b, a=1 }
    for _, option in ipairs(SORT_OPTIONS) do
        self.sortCombo:addOptionWithData(LS.text(option.labelKey, option.fallback), option.id)
    end
    self.sortCombo:selectData(VALID_SORT_MODES[self.sortMode] and self.sortMode or "default")
    self:addChild(self.sortCombo)

    self.transferSearchEntry = ISTextEntryBox:new("", 0, 0, 10, 10)
    self.transferSearchEntry.font = UIFont.Small
    self.transferSearchEntry.backgroundColor = { r=UI.col.panel2.r, g=UI.col.panel2.g, b=UI.col.panel2.b, a=0.95 }
    self.transferSearchEntry.borderColor = { r=UI.col.line.r, g=UI.col.line.g, b=UI.col.line.b, a=1 }
    self.transferSearchEntry:setPlaceholderText(LS.text("SendCreditsSearchPlaceholder", "Pesquisar jogador..."))
    self.transferSearchEntry.target = self
    self.transferSearchEntry.onTextChangeFunction = function(target) target.transferListScroll = 0 end
    self.transferSearchEntry:initialise()
    self.transferSearchEntry:instantiate()
    self.transferSearchEntry:setClearButton(true)
    -- setTextRGBA/setPlaceholderTextRGBA reach straight into self.javaObject
    -- with no nil guard too, same as setOnlyNumbers/setClearButton -- must
    -- come after instantiate(). Left unset, the entry box falls back to the
    -- engine's own default text colour, which reads as near-black against
    -- this popup's dark background.
    self.transferSearchEntry:setTextRGBA(UI.col.text.r, UI.col.text.g, UI.col.text.b, 1)
    self.transferSearchEntry:setPlaceholderTextRGBA(UI.col.muted.r, UI.col.muted.g, UI.col.muted.b, 1)
    self.transferSearchEntry:setVisible(false)
    self:addChild(self.transferSearchEntry)

    self.transferAmountEntry = ISTextEntryBox:new("", 0, 0, 10, 10)
    self.transferAmountEntry.font = UIFont.Small
    self.transferAmountEntry.backgroundColor = { r=UI.col.panel2.r, g=UI.col.panel2.g, b=UI.col.panel2.b, a=0.95 }
    self.transferAmountEntry.borderColor = { r=UI.col.line.r, g=UI.col.line.g, b=UI.col.line.b, a=1 }
    self.transferAmountEntry:setPlaceholderText(LS.text("SendCreditsAmountPlaceholder", "Digite a quantidade"))
    self.transferAmountEntry.target = self
    -- Live-clamps whatever the player types into [1, current balance] so
    -- typing more than they have snaps straight to "send everything" and
    -- typing 0 snaps up to the 1-credit minimum, instead of only catching
    -- either case at send time.
    self.transferAmountEntry.onTextChangeFunction = function(target, entryBox)
        local text = entryBox:getText() or ""
        if text == "" then return end
        local amount = math.floor(tonumber(text) or 0)
        local balance = math.max(0, math.floor(tonumber(state().balance) or 0))
        local clamped = amount
        if amount > balance then clamped = balance
        elseif amount < 1 then clamped = 1 end
        if tostring(clamped) ~= text then
            entryBox:setText(tostring(clamped))
            entryBox:setCursorPos(#tostring(clamped))
        end
    end
    self.transferAmountEntry:initialise()
    self.transferAmountEntry:instantiate()
    -- setOnlyNumbers reaches straight into self.javaObject with no nil
    -- guard (unlike setPlaceholderText just above, which does) -- it has to
    -- come after instantiate(), not before, or this throws immediately
    -- while the window is still being built and the whole shop fails to
    -- open. Same reasoning for setClearButton on the search box above.
    self.transferAmountEntry:setOnlyNumbers(true)
    self.transferAmountEntry:setTextRGBA(UI.col.text.r, UI.col.text.g, UI.col.text.b, 1)
    self.transferAmountEntry:setPlaceholderTextRGBA(UI.col.muted.r, UI.col.muted.g, UI.col.muted.b, 1)
    -- Closure over the real `self` (the window) instead of trusting what
    -- the framework passes into onCommandEntered: it calls this the same
    -- way any Lua method call passes its receiver (entryBox:onCommandEntered()
    -- -> the entry box itself), not self.target the way onTextChangeFunction
    -- does -- a plain function(target) here would have `target` be the
    -- entry box, not the window, and target:sendTransfer() would fail.
    local window = self
    self.transferAmountEntry.onCommandEntered = function() window:sendTransfer() end
    self.transferAmountEntry:setVisible(false)
    self:addChild(self.transferAmountEntry)

    self.resizeGripBR = ResizeGrip:new(0, 0, RESIZE_GRIP, "br", self)
    self.resizeGripBR:initialise()
    self.resizeGripBR:instantiate()
    self:addChild(self.resizeGripBR)
    self.resizeGripBL = ResizeGrip:new(0, 0, RESIZE_GRIP, "bl", self)
    self.resizeGripBL:initialise()
    self.resizeGripBL:instantiate()
    self:addChild(self.resizeGripBL)
    self:layoutGrips()

    local window = self
    self._networkListener = Client.onUpdate(function()
        if LasciviousShopWindow.instance == window then window:onNetworkUpdate() end
    end)
end

function LasciviousShopWindow:syncChildLayout(l)
    if not self.searchEntry then return end
    if self._childLayout == l then return end
    self._childLayout = l
    local searchInset = clamp(round(35 * l.scale), 31, 39)
    self.searchEntry:setX(l.contentX + searchInset)
    self.searchEntry:setY(l.toolbarY + 3)
    self.searchEntry:setWidth(math.max(80, l.searchW - searchInset))
    self.searchEntry:setHeight(l.toolbarH - 4)
    if self.sortCombo then
        self.sortCombo:setX(l.sortX)
        self.sortCombo:setY(l.toolbarY + 2)
        self.sortCombo:setWidth(l.sortW)
        self.sortCombo:setHeight(l.toolbarH - 4)
        self.sortCombo.baseHeight = l.toolbarH - 4
    end
    -- Keeps the transfer popup's own entry boxes aligned if the window is
    -- resized while it's open; openTransferPopup already syncs them once
    -- immediately on open, this covers every frame after that a real
    -- layout change happens.
    if self.transferOpen then self:syncTransferChildLayout() end
    self:layoutGrips()
end

function LasciviousShopWindow:onSortChanged(combo)
    local mode = combo and combo:getOptionData(combo.selected) or "default"
    self.sortMode = VALID_SORT_MODES[mode] and mode or "default"
    self:markFilterDirty()
    self:savePanelState()
end

function LasciviousShopWindow:showToast(message, duration)
    self.toastText = tostring(message or "")
    self.toastUntil = (getTimestampMs and getTimestampMs() or 0) + (duration or 2600)
end

local function priceStateSignature(currentState)
    currentState = currentState or {}
    return table.concat({
        tostring(currentState.offerRevision or 0),
        LS.priceConfigurationHash(currentState),
        tostring(currentState.perkProgressHash or currentState.perkLevelsHash or ""),
        tostring(currentState.commerceDiscountPercent or 0),
    }, "\31")
end

local function filterStateSignature(currentState, categoryId, sortMode)
    currentState = currentState or {}
    local parts = { tostring(currentState.invalidProductsHash or "") }
    if categoryId == "offers" or sortMode == "discount_desc"
        or sortMode == "price_asc" or sortMode == "price_desc" then
        parts[#parts + 1] = tostring(currentState.offerRevision or 0)
    end
    if sortMode == "price_asc" or sortMode == "price_desc" then
        parts[#parts + 1] = LS.priceConfigurationHash(currentState)
        parts[#parts + 1] = tostring(currentState.perkProgressHash
            or currentState.perkLevelsHash or "")
        parts[#parts + 1] = tostring(currentState.commerceDiscountPercent or 0)
    end
    return table.concat(parts, "\31")
end

function LasciviousShopWindow:purgeUnavailableXP()
    local changed = false
    for index = #self.cartOrder, 1, -1 do
        local id = self.cartOrder[index]
        local product = LS.PRODUCT_BY_ID[id]
        if product and product.kind == "xp" then
            local maximum = math.max(0, 10 - self:perkLevel(product))
            if maximum <= 0 then
                self.cart[id] = nil
                table.remove(self.cartOrder, index)
                changed = true
            elseif (tonumber(self.cart[id]) or 0) > maximum then
                self.cart[id] = maximum
                changed = true
            end
        end
    end
    if changed then self.cartScroll = 0 end
end

function LasciviousShopWindow:onNetworkUpdate()
    local currentState = state()
    local nextSignature = priceStateSignature(currentState)
    if nextSignature ~= self._networkStateSignature then
        self._networkStateSignature = nextSignature
        self._priceCache = {}
        self._originalPriceCache = {}
        self._priceCacheCommerce = {}
        self._originalPriceCacheCommerce = {}
        self:purgeUnavailableXP()
    end
    local nextFilterSignature = filterStateSignature(currentState, self.activeCategory, self.sortMode)
    if nextFilterSignature ~= self._networkFilterSignature then
        self._networkFilterSignature = nextFilterSignature
        self._filterDirty = true
    end
    local result = Client.lastResult
    if result and result ~= self.handledResult then
        self.handledResult = result
        if result.status == "failed" or result.status == "processing" then
            UI.playSound(UI.SOUND.error)
            self:showToast(LS.text(result.status == "processing" and "PurchaseInProgress" or "ErrorDelivery",
                result.status == "processing" and "Esta compra ainda está sendo processada."
                    or "Não foi possível entregar os produtos."), 3400)
        else
            self.cart, self.cartOrder, self.cartScroll = {}, {}, 0
            UI.playSound(UI.SOUND.purchaseSuccess)
        end
        if result.status == "partial" then
            self:showToast(LS.text("PurchasePartial", "Compra parcialmente entregue. Foram cobrados %1 crédito(s).",
                LS.formatCredits(result.charged)))
        elseif result.status == "completed" then
            self:showToast(LS.text("PurchaseComplete", "Compra concluída! %1 crédito(s) utilizado(s).",
                LS.formatCredits(result.charged)))
        end
    end
    local err = Client.lastError
    if err and err ~= self.handledError then
        self.handledError = err
        UI.playSound(UI.SOUND.error)
        local messages = {
            dead = LS.text("ErrorDead", "Não é possível comprar com o personagem morto."),
            invalid_cart = LS.text("ErrorInvalidCart", "O carrinho enviado é inválido."),
            insufficient_credits = LS.text("InsufficientCredits", "Créditos insuficientes."),
            prices_changed = LS.text("PricesChanged", "As ofertas ou os preços mudaram. Confirme novamente."),
            skill_maxed = LS.text("SkillMaxed", "Esta habilidade já está no nível máximo."),
            xp_level_limit = LS.text("XPLevelLimit", "Este carrinho já cobre o nível 10 desta habilidade."),
            cure_single_only = LS.text("CureSingleOnly", "Este item é de uso único: apenas 1 por compra."),
            vehicle_single_only = LS.text("VehicleSingleOnly", "Cada veículo é limitado a 1 por compra."),
            vehicle_cart_limit = LS.text("VehicleCartLimit",
                "O carrinho aceita no máximo %1 veículos por compra.", tostring(LS.MAX_VEHICLES_PER_PURCHASE)),
            vehicle_no_space = LS.text("VehicleNoSpace",
                "Não há espaço livre suficiente perto de você para o veículo. Tente em um local mais aberto."),
            too_fast = LS.text("PurchaseTooFast", "Aguarde um instante antes de tentar comprar novamente."),
            purchase_in_progress = LS.text("PurchaseInProgress", "Esta compra ainda está sendo processada."),
            purchase_status_unknown = LS.text("PurchaseStatusUnknown",
                "O resultado da compra é incerto. Clique em comprar para consultar a mesma transação com segurança."),
            delivery_failed = LS.text("ErrorDelivery", "Não foi possível entregar os produtos."),
            timeout = LS.text("ErrorGeneric", "A compra não pôde ser concluída."),
            server_error = LS.text("ErrorGeneric", "A compra não pôde ser concluída."),
        }
        self:showToast(messages[err.reason] or LS.text("ErrorGeneric", "A compra não pôde ser concluída."), 3400)
    end

    local transferResult = Client.lastTransferResult
    if transferResult and transferResult ~= self.transferHandledResult then
        self.transferHandledResult = transferResult
        if transferResult.ok then
            UI.playSound(UI.SOUND.purchaseSuccess)
            self:showToast(LS.text("SendCreditsSuccess", "%1 crédito(s) enviado(s) para %2.",
                LS.formatCredits(transferResult.amount), tostring(transferResult.target)))
            self:closeTransferPopup()
        else
            UI.playSound(UI.SOUND.error)
            local reasons = {
                dead = LS.text("SendCreditsDead", "Não é possível enviar créditos com o personagem morto."),
                invalid_player = LS.text("ErrorGeneric", "A compra não pôde ser concluída."),
                invalid_request = LS.text("ErrorGeneric", "A compra não pôde ser concluída."),
                too_fast = LS.text("SendCreditsTooFast", "Aguarde um instante antes de enviar novamente."),
                invalid_target = LS.text("SendCreditsInvalidTarget", "Selecione um jogador válido."),
                self_target = LS.text("SendCreditsSelfTarget", "Você não pode enviar créditos para você mesmo."),
                invalid_amount = LS.text("SendCreditsNoAmount", "Digite uma quantidade válida."),
                target_offline = LS.text("SendCreditsTargetOffline", "Esse jogador não está mais online."),
                insufficient_credits = LS.text("InsufficientCredits", "Créditos insuficientes."),
                queue_full = LS.text("SendCreditsQueueFull",
                    "Não foi possível creditar o destinatário agora. Tente novamente mais tarde."),
                recipient_balance_limit = LS.text("SendCreditsRecipientLimit",
                    "O destinatário atingiu o limite de saldo."),
                transfer_in_progress = LS.text("SendCreditsInProgress",
                    "Esta transferência ainda está sendo processada."),
                transfer_status_unknown = LS.text("SendCreditsStatusUnknown",
                    "O resultado da transferência é incerto. Clique em enviar para consultar a mesma transação com segurança."),
                timeout = LS.text("ErrorGeneric", "A compra não pôde ser concluída."),
                server_error = LS.text("ErrorGeneric", "A compra não pôde ser concluída."),
            }
            self:showToast(reasons[transferResult.reason] or LS.text("ErrorGeneric",
                "A compra não pôde ser concluída."), 3400)
        end
    end
end

function LasciviousShopWindow:offerDiscount(productId)
    return tonumber(state().offers and state().offers[productId]) or 0
end

-- The player's own faction's Comércio upgrade discount (0..30, flat -- not
-- per-product), read straight from synced server state -- the SERVER is
-- authoritative for this (LasciviousShop_Server.lua's commerceDiscountFor),
-- the client never queries LasciviousFactionsSystem directly, same
-- "server computes, client just previews" split as tributeRatePercent.
function LasciviousShopWindow:commerceDiscountPercent()
    return tonumber(state().commerceDiscountPercent) or 0
end

-- The REAL discount that will actually be charged for `productId`: the
-- active per-product sale offer (if any) stacked with the faction's flat
-- Comércio discount. Every price actually used for a total/charge routes
-- through this instead of offerDiscount alone -- see unitPrice/linePrice/
-- xpCardPreview's own `includeCommerce` parameter.
function LasciviousShopWindow:effectiveDiscount(productId)
    return LS.combineDiscounts(self:offerDiscount(productId), self:commerceDiscountPercent())
end

function LasciviousShopWindow:perkLevel(product)
    if not product or product.kind ~= "xp" then return 0 end
    local serverLevel = state().perkLevels and state().perkLevels[product.perk]
    if serverLevel ~= nil then
        return clamp(math.floor(tonumber(serverLevel) or 0), 0, 10)
    end
    local ok, level = pcall(function()
        local player = getPlayer()
        local perk = Perks.FromString(product.perk)
        return player and perk and player:getPerkLevel(perk) or 0
    end)
    return ok and clamp(math.floor(tonumber(level) or 0), 0, 10) or 0
end

function LasciviousShopWindow:xpAmount(product, quantity)
    if not product or product.kind ~= "xp" then return nil end
    quantity = math.max(1, math.floor(tonumber(quantity) or 1))
    local skillBundles = state().perkXPBundles and state().perkXPBundles[product.perk]
    local serverAmount = skillBundles and (skillBundles[quantity] or skillBundles[tostring(quantity)])
    if serverAmount == nil and quantity == 1 then
        serverAmount = state().perkXPToNext and state().perkXPToNext[product.perk]
    end
    if serverAmount ~= nil then return math.max(0, math.floor(tonumber(serverAmount) or 0)) end
    local ok, amount = pcall(function()
        local player = getPlayer()
        local perk = Perks.FromString(product.perk)
        return LS.xpRequiredForLevels(player, perk, self:perkLevel(product), quantity)
    end)
    return ok and math.max(0, math.floor(tonumber(amount) or 0)) or 0
end

-- Credit price (before multiplier/discount) to advance `quantity` levels from
-- the current one, per LS.xpLevelUpBasePrice -- decoupled from the perk's raw
-- XP curve, see that function's comment in LasciviousShop_Shared.lua.
function LasciviousShopWindow:xpBasePrice(product, quantity)
    if not product or product.kind ~= "xp" then return nil end
    quantity = math.max(1, math.floor(tonumber(quantity) or 1))
    local ok, price = pcall(function()
        local player = getPlayer()
        local perk = Perks.FromString(product.perk)
        return LS.xpLevelUpBasePrice(player, perk, self:perkLevel(product), quantity)
    end)
    return ok and math.max(0, tonumber(price) or 0) or 0
end

-- What buying ONE MORE unit of this XP product would look like, given
-- `cartQty` copies of it are already queued in the cart. Each queued unit is
-- a full level-up, so the next one starts completely fresh (0% into its XP
-- band) rather than at the player's real, unqueued progress -- this is what
-- lets the shop card preview "XP para alcançar o nível 2" once "nível 1" is
-- already sitting in the cart, instead of always showing the same real,
-- current-level info regardless of what's queued. Falls back to the real,
-- unqueued state (today's behaviour) when nothing of this product is in the
-- cart yet.
-- `includeCommerce` (default false, preserving every existing call site's
-- behaviour untouched) selects effectiveDiscount (offer + faction Comércio
-- discount, stacked) over plain offerDiscount -- true is used ONLY where the
-- result must match what will actually be charged (cart total/lines, the
-- purchase request, and the card's own commerce-price preview), so those
-- never round independently from each other. See LS.combineDiscounts' own
-- comment for why this stays a single combined LS.priceFor call rather than
-- a second discount layered on top of an already-rounded price.
function LasciviousShopWindow:xpCardPreview(product, includeCommerce)
    if not product or product.kind ~= "xp" then
        local price, original = self:unitPrice(product, includeCommerce)
        return self:perkLevel(product), self:xpAmount(product), price, original
    end
    local cartQty = math.max(0, math.floor(tonumber(self.cart[product.id]) or 0))
    local baseLevel = self:perkLevel(product)
    if cartQty <= 0 then
        local price, original = self:unitPrice(product, includeCommerce)
        return baseLevel, self:xpAmount(product), price, original
    end
    local previewLevel = clamp(baseLevel + cartQty, 0, 10)
    if previewLevel >= 10 then return previewLevel, 0, 0, 0 end
    local ok, xpAmount, basePrice = pcall(function()
        local perk = Perks.FromString(product.perk)
        return LS.xpRequiredForLevelsFromXP(perk, previewLevel, 0, 1),
            LS.xpLevelUpBasePriceFromXP(perk, previewLevel, 0, 1)
    end)
    if not ok then return previewLevel, 0, 0, 0 end
    xpAmount = math.max(0, math.floor(tonumber(xpAmount) or 0))
    basePrice = math.max(0, tonumber(basePrice) or 0)
    local multiplier = LS.priceMultiplierForCategory(state(), product.category)
    local discount = includeCommerce and self:effectiveDiscount(product.id) or self:offerDiscount(product.id)
    local price, original = LS.priceFor(product, discount, multiplier, basePrice)
    return previewLevel, xpAmount, price, original
end

function LasciviousShopWindow:unitPrice(product, includeCommerce)
    local discount = includeCommerce and self:effectiveDiscount(product and product.id)
        or self:offerDiscount(product and product.id)
    -- Severity- and level-progress-priced products read live player state
    -- (health/infection for cure, banked XP for skills), which can change far
    -- more often than the ~15s network state refresh that clears this cache
    -- -- caching them would show a stale price right when it matters most
    -- (right after a bite, or right after a kill that pushes XP past a
    -- threshold). Recomputed every call instead; the underlying reads are cheap.
    if product and product.kind == "cure" then
        local multiplier = LS.priceMultiplierForCategory(state(), product.category)
        local severity = LS.cureSeverity(getPlayer())
        return LS.priceFor(product, discount, multiplier, nil, severity)
    end
    if product and product.kind == "xp" then
        local multiplier = LS.priceMultiplierForCategory(state(), product.category)
        return LS.priceFor(product, discount, multiplier, self:xpBasePrice(product))
    end
    -- Separate cache buckets per mode -- includeCommerce true/false would
    -- otherwise collide on the same product.id key and hand back whichever
    -- mode happened to populate the cache first.
    local cacheKey = includeCommerce and "_priceCacheCommerce" or "_priceCache"
    local origKey = includeCommerce and "_originalPriceCacheCommerce" or "_originalPriceCache"
    local cached = product and self[cacheKey] and self[cacheKey][product.id]
    if cached ~= nil then return cached, self[origKey][product.id] end
    local s = state()
    local multiplier = LS.priceMultiplierForCategory(s, product.category)
    local price, original = LS.priceFor(product, discount, multiplier)
    self[cacheKey] = self[cacheKey] or {}
    self[origKey] = self[origKey] or {}
    self[cacheKey][product.id] = price
    self[origKey][product.id] = original
    return price, original
end

function LasciviousShopWindow:linePrice(product, quantity, includeCommerce)
    quantity = math.max(1, math.floor(tonumber(quantity) or 1))
    if not product then return 0 end
    if product.kind ~= "xp" then return self:unitPrice(product, includeCommerce) * quantity end
    local multiplier = LS.priceMultiplierForCategory(state(), product.category)
    local discount = includeCommerce and self:effectiveDiscount(product.id) or self:offerDiscount(product.id)
    return LS.priceFor(product, discount, multiplier, self:xpBasePrice(product, quantity))
end

-- Search fluidity: if the player is inside a specific category and their
-- query has zero matches there but does match somewhere else in the shop,
-- jump to "Todos os itens" automatically instead of showing an empty grid.
-- Fires only once per new query text (tracked via _autoSwitchedQuery, reset
-- whenever the query itself changes) so a player who then deliberately clicks
-- through categories to compare matches -- even ones with zero results for
-- this query -- is never fought or reverted by this.
function LasciviousShopWindow:autoSwitchCategoryForQuery(rawQuery)
    local query = Search.normalize(rawQuery)
    if query == "" then
        self._autoSwitchedQuery = nil
        return
    end
    if self._autoSwitchedQuery == query then return end
    self._autoSwitchedQuery = query
    local category = self.activeCategory or "all"
    if category == "all" then return end
    local s = state()
    local ok, currentResults = pcall(Search.filter, category, query, s)
    if ok and currentResults and #currentResults > 0 then return end
    local okAll, allResults = pcall(Search.filter, "all", query, s)
    if okAll and allResults and #allResults > 0 then
        local previousLabel = category
        for _, cat in ipairs(LS.CATEGORIES) do
            if cat.id == category then
                previousLabel = LS.text(cat.labelKey, cat.fallback)
                break
            end
        end
        self.activeCategory = "all"
        self:showToast(LS.text("SearchAutoSwitchedAll",
            "Sem resultados em \"%1\"; mostrando todos os itens.", previousLabel), 2200)
    end
end

function LasciviousShopWindow:filteredProductIds()
    local rawQuery = self.searchEntry and self.searchEntry.getText
        and tostring(self.searchEntry:getText() or "") or ""
    if rawQuery ~= self._lastRawQuery then
        self._lastRawQuery = rawQuery
        self._filterDirty = true
        self.currentPage = 1
        self:autoSwitchCategoryForQuery(rawQuery)
    end
    if not self._filterDirty and self._filteredProductIds then return self._filteredProductIds end

    local query = Search.normalize(rawQuery)
    local s = state()
    local mode = VALID_SORT_MODES[self.sortMode] and self.sortMode or "default"
    local signature = table.concat({
        self.activeCategory or "all", query, mode,
        filterStateSignature(s, self.activeCategory, mode),
    }, "\31")
    local cached = self._searchResultCache[signature]
    if cached then
        self._filteredProductIds = cached
        self._filterDirty = false
        return cached
    end

    local ok, output, relevance = pcall(Search.filter, self.activeCategory, query, s)
    if not ok then
        if self._lastSearchError ~= tostring(output) then
            self._lastSearchError = tostring(output)
            LS.log("search failed safely: " .. tostring(output))
        end
        output, relevance = {}, {}
    else
        self._lastSearchError = nil
    end
    if mode ~= "default" or query ~= "" then
        local names, prices, discounts = {}, {}, {}
        local function productFor(id) return LS.PRODUCT_BY_ID[id] end
        local function name(id)
            local value = names[id]
            if not value then
                local record = Search.record(productFor(id))
                value = record and record.name or id
                names[id] = value
            end
            return value
        end
        local function price(id)
            local value = prices[id]
            if not value then
                value = self:unitPrice(productFor(id), true)
                prices[id] = value
            end
            return value
        end
        local function discount(id)
            local value = discounts[id]
            if value == nil then
                value = self:offerDiscount(id)
                discounts[id] = value
            end
            return value
        end
        table.sort(output, function(a, b)
            local av, bv
            if mode == "default" then
                av, bv = relevance[a] or 0, relevance[b] or 0
            elseif mode == "name_asc" or mode == "name_desc" then
                av, bv = name(a), name(b)
            elseif mode == "price_asc" or mode == "price_desc" then
                av, bv = price(a), price(b)
            else
                av, bv = discount(a), discount(b)
            end
            if av == bv then
                local an, bn = name(a), name(b)
                if an == bn then return a < b end
                return an < bn
            end
            if mode == "default" or mode == "name_desc"
                or mode == "price_desc" or mode == "discount_desc" then
                return av > bv
            end
            return av < bv
        end)
    end

    -- The emergency full-cure card is meant to stand out as "special" (see
    -- its dedicated frame in drawCard) -- under the default/relevance sort
    -- it should always lead the medical tab specifically, regardless of
    -- where relevance scoring would have otherwise placed it. Left alone in
    -- "all items"/other tabs, where it would be an out-of-place jump-scare
    -- ahead of unrelated categories.
    if mode == "default" and self.activeCategory == "medical" then
        for i = 1, #output do
            local product = LS.PRODUCT_BY_ID[output[i]]
            if product and product.kind == "cure" then
                if i > 1 then
                    table.remove(output, i)
                    table.insert(output, 1, product.id)
                end
                break
            end
        end
    end

    self._searchResultCache[signature] = output
    self._searchResultCacheOrder[#self._searchResultCacheOrder + 1] = signature
    while #self._searchResultCacheOrder > 24 do
        local oldest = table.remove(self._searchResultCacheOrder, 1)
        self._searchResultCache[oldest] = nil
    end
    self._filteredProductIds = output
    self._filterDirty = false
    return output
end

function LasciviousShopWindow:cartCount()
    local count = 0
    for _, qty in pairs(self.cart) do count = count + math.max(0, tonumber(qty) or 0) end
    return count
end

function LasciviousShopWindow:vehicleCartCount()
    local count = 0
    for _, id in ipairs(self.cartOrder) do
        local product = LS.PRODUCT_BY_ID[id]
        if product and product.kind == "vehicle" and (tonumber(self.cart[id]) or 0) > 0 then
            count = count + 1
        end
    end
    return count
end

function LasciviousShopWindow:cartTotal()
    local total = 0
    for _, id in ipairs(self.cartOrder) do
        local qty = tonumber(self.cart[id]) or 0
        local product = LS.PRODUCT_BY_ID[id]
        if qty > 0 and product then total = total + self:linePrice(product, qty, true) end
    end
    return total
end

function LasciviousShopWindow:addToCart(product)
    if not product then return end
    if product.kind == "xp" and self:perkLevel(product) >= 10 then
        return self:showToast(LS.text("SkillMaxed", "Esta habilidade já está no nível máximo."))
    end
    if product.kind == "xp" and (tonumber(self:xpAmount(product)) or 0) <= 0 then
        return self:showToast(LS.text("ErrorGeneric", "A compra não pôde ser concluída."))
    end
    local current = tonumber(self.cart[product.id]) or 0
    if product.kind == "xp" and current >= 10 - self:perkLevel(product) then
        return self:showToast(LS.text("XPLevelLimit", "Este carrinho já cobre o nível 10 desta habilidade."))
    end
    if isSingleUseKind(product.kind) and current >= 1 then
        return self:showToast(LS.text("CureSingleOnly", "Este item é de uso único: apenas 1 por compra."))
    end
    if product.kind == "vehicle" and current < 1
        and self:vehicleCartCount() >= LS.MAX_VEHICLES_PER_PURCHASE then
        return self:showToast(LS.text("VehicleCartLimit",
            "O carrinho aceita no máximo %1 veículos por compra.", tostring(LS.MAX_VEHICLES_PER_PURCHASE)))
    end
    if self:cartCount() >= 50 then
        return self:showToast(LS.text("CartLimit", "O carrinho aceita no máximo 50 unidades."))
    end
    if not self.cart[product.id] then table.insert(self.cartOrder, product.id) end
    self.cart[product.id] = product.kind == "xp" and math.min(10 - self:perkLevel(product), current + 1)
        or isSingleUseKind(product.kind) and 1
        or math.min(50, current + 1)
    UI.playSound(UI.SOUND.cartAdd)
    self:showToast(LS.text("AddedToCart", "%1 adicionado ao carrinho.", LS.productName(product)), 1500)
end

function LasciviousShopWindow:changeCart(productId, delta)
    local product = LS.PRODUCT_BY_ID[productId]
    if delta > 0 and product and product.kind == "xp"
        and (tonumber(self.cart[productId]) or 0) >= 10 - self:perkLevel(product) then
        return self:showToast(LS.text("XPLevelLimit", "Este carrinho já cobre o nível 10 desta habilidade."))
    end
    if delta > 0 and product and isSingleUseKind(product.kind) and (tonumber(self.cart[productId]) or 0) >= 1 then
        return self:showToast(LS.text("CureSingleOnly", "Este item é de uso único: apenas 1 por compra."))
    end
    if delta > 0 and product and product.kind == "vehicle"
        and (tonumber(self.cart[productId]) or 0) < 1
        and self:vehicleCartCount() >= LS.MAX_VEHICLES_PER_PURCHASE then
        return self:showToast(LS.text("VehicleCartLimit",
            "O carrinho aceita no máximo %1 veículos por compra.", tostring(LS.MAX_VEHICLES_PER_PURCHASE)))
    end
    if delta > 0 and self:cartCount() >= 50 then
        return self:showToast(LS.text("CartLimit", "O carrinho aceita no máximo 50 unidades."))
    end
    local qty = (tonumber(self.cart[productId]) or 0) + delta
    if qty <= 0 then
        self.cart[productId] = nil
        for i = #self.cartOrder, 1, -1 do
            if self.cartOrder[i] == productId then table.remove(self.cartOrder, i) end
        end
    else
        local maximum = product and product.kind == "xp" and (10 - self:perkLevel(product))
            or product and isSingleUseKind(product.kind) and 1
            or 50
        self.cart[productId] = math.min(maximum, qty)
    end
    UI.playSound(delta > 0 and UI.SOUND.cartAdd or UI.SOUND.cartRemove)
end

function LasciviousShopWindow:purchase()
    if Client.awaitingPurchase then return end
    local total = self:cartTotal()
    if total <= 0 then return end
    local balance = tonumber(state().balance) or 0
    if balance + 0.0001 < total then
        return self:showToast(LS.text("InsufficientCredits", "Créditos insuficientes."))
    end
    local items = {}
    for _, id in ipairs(self.cartOrder) do
        local qty = tonumber(self.cart[id]) or 0
        if qty > 0 then table.insert(items, { id=id, qty=qty }) end
    end
    if Client.requestPurchase(items, total, tonumber(state().offerRevision) or 0) then
        self:showToast(LS.text("Buying", "COMPRANDO..."), 1200)
    end
end

function LasciviousShopWindow:drawHeader(l)
    local c = UI.col
    UI.roundRect(self, 1, 1, self.width - 2, l.headerH, 12, 1, c.panel2)
    self:drawRect(1, l.headerH - 10, self.width - 2, 10, 1, c.panel2.r, c.panel2.g, c.panel2.b)
    local grad = texture("grad_v")
    if grad then self:drawTextureScaled(grad, 1, 1, self.width - 2, l.headerH, 0.18, c.accent.r, c.accent.g, c.accent.b) end
    self:drawRect(1, l.headerH - 1, self.width - 2, 1, 1, c.lineHi.r, c.lineHi.g, c.lineHi.b)

    local logoSize = clamp(round(38 * l.scale), 32, 42)
    local logoX = clamp(round(22 * l.scale), 14, 24)
    local logoY = math.floor((l.headerH - logoSize) / 2)
    UI.roundFrame(self, logoX, logoY, logoSize, logoSize, 9, c.accent, c.accentDim)
    local shopIcon = texture("shop-solid")
    local iconSize = math.max(20, logoSize - 14)
    if shopIcon then
        self:drawTextureScaled(shopIcon, logoX + math.floor((logoSize-iconSize)/2),
            logoY + math.floor((logoSize-iconSize)/2), iconSize, iconSize, 1, 0.92, 0.78, 1)
    end
    local titleX = logoX + logoSize + clamp(round(12 * l.scale), 9, 14)
    local titleY = math.floor((l.headerH - UI.fontHeight(UIFont.Medium)) / 2)
    UI.text(self, LS.text("Title", "LOJA DE CRÉDITOS"), titleX, titleY, UIFont.Medium, c.text)

    local closeSize = clamp(round(34 * l.scale), 30, 38)
    local closeMargin = clamp(round(14 * l.scale), 10, 16)
    self.closeRect = self.closeRect or {}
    self.closeRect.x, self.closeRect.y = self.width-closeMargin-closeSize, math.floor((l.headerH-closeSize)/2)
    self.closeRect.w, self.closeRect.h = closeSize, closeSize
    local hovered = UI.inside(self.closeRect, self:getMouseX(), self:getMouseY())
    -- Must stay fully legible (and, while a zombie is close, stand out even
    -- MORE than usual) no matter how faded the rest of the window gets --
    -- see updateDangerAlpha/the drawRect override above. _dimExempt only
    -- brackets the drawing itself; input handling for this rect is already
    -- unconditional regardless of dimming.
    local urgent = hovered or self._dangerNear
    self._dimExempt = true
    if self._dangerNear then
        UI.glow(self, self.closeRect.x, self.closeRect.y, self.closeRect.w, self.closeRect.h, 10, 0.35, c.danger)
    end
    UI.roundFrame(self, self.closeRect.x, self.closeRect.y, self.closeRect.w, self.closeRect.h, 7,
        urgent and c.danger or c.line, urgent and c.cardHi or c.panel2)
    UI.textCentre(self, "X", self.closeRect.x + math.floor(closeSize/2),
        self.closeRect.y + math.floor((closeSize - UI.fontHeight(UIFont.Small)) / 2), UIFont.Small,
        urgent and c.danger or c.muted)
    self._dimExempt = false
end

function LasciviousShopWindow:drawSidebar(l)
    local c = UI.col
    self:drawRect(1, l.headerH, l.sidebarW, self.height - l.headerH - 1, 1, c.bg.r, c.bg.g, c.bg.b)
    self:drawRect(l.sidebarW, l.headerH, 1, self.height - l.headerH, 1, c.line.r, c.line.g, c.line.b)
    local sidePad = clamp(round(14 * l.scale), 10, 16)
    UI.text(self, LS.text("Categories", "CATEGORIAS"), sidePad, l.headerH + clamp(round(17*l.scale), 12, 19), UIFont.Small, c.muted)

    -- Pinned to the sidebar's bottom edge rather than appended to the
    -- category list: this isn't a catalog filter, it's a standalone action,
    -- and keeping it at a fixed spot means it never drifts as categories are
    -- added or removed. Computed BEFORE the category loop below so that
    -- loop can shrink its own row height to always fit above it -- on a
    -- tall window this never kicks in (rows stay at their normal size), it
    -- only compresses things on a short window with many categories, which
    -- is exactly the one case that could otherwise overlap this button.
    local btnH = clamp(round(46 * l.scale), 38, 50)
    local btnY = self.height - btnH - sidePad

    local rectCount = 0
    local y = l.headerH + clamp(round(50 * l.scale), 40, 54)
    local rowH = l.categoryRowH
    local categoryCount = #LS.CATEGORIES
    if categoryCount > 0 then
        local available = (btnY - 10) - y
        local natural = categoryCount * rowH + (categoryCount - 1) * l.categoryGap
        if natural > available then
            rowH = math.max(24, math.floor((available - (categoryCount - 1) * l.categoryGap) / categoryCount))
        end
    end
    for _, category in ipairs(LS.CATEGORIES) do
        rectCount = rectCount + 1
        local rect = reuseRect(self.categoryRects, rectCount,
            sidePad-4, y, l.sidebarW-(sidePad-4)*2, rowH)
        rect.id = category.id
        local active = self.activeCategory == category.id
        local hovered = UI.inside(rect, self:getMouseX(), self:getMouseY())
        if active then
            UI.roundFrame(self, rect.x, rect.y, rect.w, rect.h, 7, c.lineHi, c.accentDim)
            self:drawRect(rect.x, rect.y + 7, 3, rect.h - 14, 1, c.accent.r, c.accent.g, c.accent.b)
        elseif hovered then
            UI.roundRect(self, rect.x, rect.y, rect.w, rect.h, 7, 1, c.panel2)
        end
        local icon = texture(category.icon)
        if icon then
            local tint = active and c.accentHi or c.muted
            local iconSize = clamp(round(18*l.scale), 16, 20)
            self:drawTextureScaled(icon, rect.x + clamp(round(11*l.scale), 8, 12),
                rect.y + math.floor((rect.h-iconSize)/2), iconSize, iconSize, 1, tint.r, tint.g, tint.b)
        end
        local textX = rect.x + clamp(round(39*l.scale), 32, 42)
        UI.textFit(self, LS.text(category.labelKey, category.fallback), textX,
            rect.y + math.floor((rect.h - UI.fontHeight(UIFont.Small)) / 2), rect.x + rect.w - textX - 8,
            UIFont.Small, active and c.text or c.muted)
        y = y + rowH + l.categoryGap
    end
    trimRects(self.categoryRects, rectCount)

    self.transferButtonRect = self.transferButtonRect or {}
    local rect = self.transferButtonRect
    rect.x, rect.y, rect.w, rect.h = sidePad - 4, btnY, l.sidebarW - (sidePad - 4) * 2, btnH
    self:drawRect(rect.x, rect.y - 8, rect.w, 1, 1, c.line.r, c.line.g, c.line.b)
    local hoveredTransfer = UI.inside(rect, self:getMouseX(), self:getMouseY())
    UI.roundFrame(self, rect.x, rect.y, rect.w, rect.h, 8,
        hoveredTransfer and c.lineHi or c.line, hoveredTransfer and c.cardHi or c.panel2)
    local transferIcon = texture("money-bill-transfer-solid")
    if transferIcon then
        local iconSize = clamp(round(18 * l.scale), 16, 20)
        self:drawTextureScaled(transferIcon, rect.x + clamp(round(11 * l.scale), 8, 12),
            rect.y + math.floor((rect.h - iconSize) / 2), iconSize, iconSize, 1,
            c.accentHi.r, c.accentHi.g, c.accentHi.b)
    end
    local transferTextX = rect.x + clamp(round(39 * l.scale), 32, 42)
    UI.textFit(self, LS.text("SendCreditsButton", "Enviar Créditos"), transferTextX,
        rect.y + math.floor((rect.h - UI.fontHeight(UIFont.Small)) / 2), rect.x + rect.w - transferTextX - 8,
        UIFont.Small, c.accentHi)
end

function LasciviousShopWindow:drawBalanceAndToolbar(l)
    local c = UI.col
    local x, w = l.contentX, l.contentW
    UI.roundFrame(self, x, l.balanceY, w, l.balanceH, 10, c.lineHi, c.panel2)
    local heroPad = clamp(round(16*l.scale), 11, 18)
    local creditSize = clamp(round(54*l.scale), 46, 58)
    local creditY = l.balanceY + math.floor((l.balanceH-creditSize)/2)
    UI.roundFrame(self, x + heroPad, creditY, creditSize, creditSize, 11, c.lineHi, c.cardHi)
    local coin = texture("coins-solid")
    local heroCoinSize = clamp(round(26*l.scale), 22, 28)
    if coin then self:drawTextureScaled(coin, x + heroPad + math.floor((creditSize-heroCoinSize)/2),
        creditY + math.floor((creditSize-heroCoinSize)/2), heroCoinSize, heroCoinSize, 1, 1, 1, 1) end
    local balanceX = x + heroPad + creditSize + clamp(round(14*l.scale), 10, 16)
    local balanceLabelY = l.balanceY + math.max(10, math.floor((l.balanceH-49)/2))
    UI.text(self, LS.text("YourCredits", "SEUS CRÉDITOS"), balanceX, balanceLabelY, UIFont.Small, c.muted)
    local balance = Client.state and LS.formatCreditsFixed(state().balance) or "--"
    UI.text(self, balance, balanceX, balanceLabelY + UI.fontHeight(UIFont.Small) + 1, UIFont.Large, c.gold)

    local rightX = x + w - heroPad
    -- PT-BR comma convention specifically for this hint (LS.formatCredits
    -- itself stays dot -- every OTHER caller is a whole-number price where
    -- the difference never shows), matching the exact "1,35"/"2,5" examples
    -- the user gave for how a boosted rate should read.
    local plainRateHour = tonumber(state().creditsPerHourSurvived) or 1
    local boostedRateHour = tonumber(state().creditsPerHourSurvivedBoosted)
    local hourBoosted = boostedRateHour ~= nil and boostedRateHour > plainRateHour + 0.001
    local rateHourText = commaCredits(hourBoosted and boostedRateHour or plainRateHour)

    local plainRateKill = tonumber(state().creditsPerZombieKill) or 1
    local boostedRateKill = tonumber(state().creditsPerZombieKillBoosted)
    -- True only when the faction's Multiplicador de Recompensa upgrade is
    -- actually raising this above the plain configured rate -- level 0 (or
    -- no faction/no active claim) sends the Boosted state field equal to the
    -- plain rate, so both of these naturally stay false with zero extra state.
    local killBoosted = boostedRateKill ~= nil and boostedRateKill > plainRateKill + 0.001
    local rateKillText = commaCredits(killBoosted and boostedRateKill or plainRateKill)

    local hintY = l.balanceY + clamp(round(17*l.scale), 12, 19)
    local hintMaxW = math.max(80, rightX - balanceX - 145)

    -- Five segments so ONLY each number itself can turn blue when boosted --
    -- explicit user correction: "é só número que tem cor diferente, não o
    -- trecho todo" (not the whole "X por zumbi abatido" phrase, just "X").
    -- Built right-to-left since the whole line is right-aligned to rightX.
    -- Falls back to the original single-color, single-string rendering
    -- (still with the correct, possibly-boosted numbers, just not colored)
    -- if the combined text is too wide to fit cleanly -- not worth inventing
    -- per-segment truncation for a narrow-window edge case.
    local lead = LS.text("EarnHintLead", "Ganhe ")
    local mid = LS.text("EarnHintMid", " crédito(s) por hora sobrevivida e ")
    local tail = LS.text("EarnHintTail", " por zumbi abatido.")
    local tailW = UI.textWidth(UIFont.Small, tail)
    local killW = UI.textWidth(UIFont.Small, rateKillText)
    local midW = UI.textWidth(UIFont.Small, mid)
    local hourW = UI.textWidth(UIFont.Small, rateHourText)
    local leadW = UI.textWidth(UIFont.Small, lead)
    local totalW = tailW + killW + midW + hourW + leadW
    if totalW <= hintMaxW then
        local cursorX = rightX
        cursorX = cursorX - tailW
        UI.text(self, tail, cursorX, hintY, UIFont.Small, c.accentHi)
        cursorX = cursorX - killW
        UI.text(self, rateKillText, cursorX, hintY, UIFont.Small,
            killBoosted and c.discount or c.accentHi)
        cursorX = cursorX - midW
        UI.text(self, mid, cursorX, hintY, UIFont.Small, c.accentHi)
        cursorX = cursorX - hourW
        UI.text(self, rateHourText, cursorX, hintY, UIFont.Small,
            hourBoosted and c.discount or c.accentHi)
        cursorX = cursorX - leadW
        UI.text(self, lead, cursorX, hintY, UIFont.Small, c.accentHi)
    else
        local hint = LS.text("EarnHint", "Ganhe %1 crédito(s) por hora sobrevivida e %2 por zumbi abatido.",
            rateHourText, rateKillText)
        UI.textRight(self, UI.fitText(hint, UIFont.Small, hintMaxW), rightX, hintY, UIFont.Small, c.accentHi)
    end

    -- Faction tribute hint: only when the player belongs to a taxed faction (see
    -- LasciviousShop_Server.lua's buildState). Centered across the whole card,
    -- distinct from the right-aligned earn hint/offer timer above/below it.
    local tributeRate = state().tributeRatePercent
    local offerY = l.balanceY + l.balanceH - UI.fontHeight(UIFont.Small) - 10
    if tributeRate and tributeRate > 0 then
        local tributeText = LS.text("FactionTributeHint",
            "Sua facção cobra %1% de tributo sobre seus créditos ganhos.", tostring(math.floor(tributeRate)))
        local tributeY = state().offersEnabled and (offerY - UI.fontHeight(UIFont.Small) - 4) or offerY
        UI.textCentre(self, UI.fitText(tributeText, UIFont.Small, w - heroPad * 2), x + math.floor(w / 2),
            tributeY, UIFont.Small, c.accentHi)
    end
    if state().offersEnabled then
        local timer = LS.text("OfferEnds", "Novas ofertas em %1", formatClock(Client.offerSecondsRemaining()))
        UI.textRight(self, UI.fitText(timer, UIFont.Small, hintMaxW), rightX,
            offerY, UIFont.Small, c.gold)
    end

    UI.roundFrame(self, l.contentX, l.toolbarY, l.searchW, l.toolbarH, 8, c.line, c.panel2)
    local searchIcon = texture("magnifying-glass-solid")
    local searchIconSize = clamp(round(16*l.scale), 14, 18)
    if searchIcon then self:drawTextureScaled(searchIcon, l.contentX + clamp(round(11*l.scale), 9, 12),
        l.toolbarY + math.floor((l.toolbarH-searchIconSize)/2), searchIconSize, searchIconSize,
        1, c.muted.r, c.muted.g, c.muted.b) end
end

function LasciviousShopWindow:drawCardText(product, text, rect, y, hovered, color)
    local left = rect.x + 8
    local available = rect.w - 16
    local width = UI.textWidth(UIFont.Small, text)
    if width <= available then
        UI.textCentre(self, text, rect.x + math.floor(rect.w / 2), y, UIFont.Small, color)
        return
    end
    if not hovered then
        UI.textCentreFit(self, text, rect.x + math.floor(rect.w / 2), y,
            available, UIFont.Small, color)
        return
    end

    local now = getTimestampMs and getTimestampMs() or 0
    if self.marqueeProductId ~= product.id then
        self.marqueeProductId = product.id
        self.marqueeStartedAt = now
    end
    self._marqueeHoveredThisFrame = true
    local overflow = math.max(0, width - available)
    local speed = 28 -- pixels per second
    local startPause, endPause = 800, 650
    local travel = math.max(1, math.floor(overflow / speed * 1000))
    local cycle = startPause + travel + endPause + travel
    local phase = (now - (self.marqueeStartedAt or now)) % cycle
    local offset
    if phase < startPause then
        offset = 0
    elseif phase < startPause + travel then
        offset = overflow * ((phase - startPause) / travel)
    elseif phase < startPause + travel + endPause then
        offset = overflow
    else
        offset = overflow * (1 - (phase - startPause - travel - endPause) / travel)
    end

    local fontH = UI.fontHeight(UIFont.Small)
    local sx, sy, sw, sh = self:clampStencilRectToParent(left, y, available, fontH)
    UI.text(self, text, left - offset, y, UIFont.Small, color)
    self:clearStencilRect()
    if self.doRepaintStencil then self:repaintStencilRect(sx, sy, sw, sh) end
end

-- Pooled ISUI3DScene widgets, one per grid slot (bounded by the highest
-- perPage=columns*rows this shop's layout() ever produces -- columns clamps
-- to [2,4], rows to [2,3], so 12 is the real ceiling). Reused across
-- frames/pages/categories instead of recreated: instantiating the
-- underlying Java 3D scene is real work, repositioning an existing one is
-- cheap. Hidden whenever its slot doesn't currently hold a vehicle card.
local MAX_GRID_SLOTS = 12

function LasciviousShopWindow:vehicleSceneForSlot(slot)
    local scene = self.vehicleScenePool[slot]
    if scene then return scene end
    scene = LasciviousShopVehicleScene:new(0, 0, 10, 10)
    scene:initialise()
    scene:instantiate()
    scene.shopWindow = self
    self:addChild(scene)
    self.vehicleScenePool[slot] = scene
    scene:setupOnce()
    return scene
end

-- Positions/sizes/shows this slot's pooled scene over the card's model area
-- and (re)assigns its vehicle if the card at this slot changed; returns the
-- Y for the name text that follows (vehicle cards skip the description
-- line entirely -- see drawCard -- so only one text line plus the price row
-- need to fit below the viewport; both anchor off the real font height
-- instead of a guessed pixel constant, so this stays correct even if the
-- UI font ever changes). `offered` reserves headroom for the top-left
-- discount badge only when this particular card actually has one -- the
-- "+"/MAX pill that used to justify a wide top margin for every card is
-- gone for vehicles now (see drawCard), so the common (not-on-offer) case
-- gets the extra space back instead of leaving it reserved unconditionally.
function LasciviousShopWindow:layoutVehicleScene(slot, product, rect, offered)
    local scene = self:vehicleSceneForSlot(slot)
    local fontH = UI.fontHeight(UIFont.Small)
    local top = rect.y + (offered and 40 or 26)
    local bottom = rect.y + rect.h - (fontH * 2 + 18)
    scene:setX(rect.x + 5)
    scene:setY(top)
    scene:setWidth(rect.w - 10)
    scene:setHeight(math.max(40, bottom - top))
    -- This is a real child widget, so like searchEntry/sortCombo it renders
    -- in a pass that always happens after the window's own prerender -- left
    -- visible, it would show straight through the transfer popup's dim
    -- backdrop regardless of draw order. Force it hidden for as long as the
    -- popup is open instead of just trusting the overlay to cover it.
    if self.transferOpen then
        scene:setVisible(false)
    else
        scene:setVisible(true)
        scene:showVehicle(product)
    end
    return bottom + 3
end

function LasciviousShopWindow:drawCard(product, rect, slot)
    local c = UI.col
    local perkLevel, xpAmount, price, original = self:xpCardPreview(product)
    local maxed = product.kind == "xp" and perkLevel >= 10
    local isCure = product.kind == "cure"
    local discount = self:offerDiscount(product.id)
    local offered = discount > 0 and not maxed
    local offerColor = state().offerColor or c.gold
    local highlightEnabled = state().offerHighlightEnabled ~= false
    local badgeEnabled = state().offerBadgeEnabled ~= false
    local hovered = UI.inside(rect, self:getMouseX(), self:getMouseY())
    if isCure then
        UI.glow(self, rect.x, rect.y, rect.w, rect.h, 8, hovered and 0.22 or 0.14, c.cureBorder)
    elseif offered and highlightEnabled then
        UI.glow(self, rect.x, rect.y, rect.w, rect.h, 7, hovered and 0.18 or 0.10, offerColor)
    end
    local cardBorder = maxed and c.ok
        or (isCure and (hovered and c.cureBorderHi or c.cureBorder))
        or (offered and highlightEnabled and offerColor or (hovered and c.lineHi or c.line))
    local cardFill = maxed and c.panel2 or (isCure and c.cureFill or (hovered and c.cardHi or c.card))
    UI.roundFrame(self, rect.x, rect.y, rect.w, rect.h, 9, cardBorder, cardFill, maxed and 0.72 or 1)
    if offered and highlightEnabled then
        self:drawRect(rect.x + 12, rect.y + 1, rect.w - 24, 2, 0.9, offerColor.r, offerColor.g, offerColor.b)
    end
    if offered and badgeEnabled then
        local badgeSize = clamp(round(30*(rect.scale or 1)), 27, 32)
        local badgeX = rect.x + 7
        local badgeIcon = texture("discount")
        if badgeIcon then self:drawTextureScaled(badgeIcon, badgeX, rect.y + 7, badgeSize, badgeSize, 1, 1, 1, 1) end
        local badgeFrameX = badgeX + badgeSize + 7
        UI.roundRect(self, badgeFrameX, rect.y + 10, 45, 20, 6, 0.96, offerColor)
        UI.textCentre(self, "-" .. tostring(discount) .. "%", badgeFrameX + 22,
            rect.y + 10 + math.floor((20 - UI.fontHeight(UIFont.Small)) / 2), UIFont.Small, c.bg)
    end

    local cardScale = rect.scale or 1
    local isVehicle = product.kind == "vehicle"
    if not isVehicle then
        -- The "+"/MAX pill is redundant on vehicle cards (the model itself
        -- fills that visual role) and was sitting awkwardly over the 3D
        -- viewport, so it's skipped there entirely per request.
        local plusSize = clamp(round(25*cardScale), 23, 28)
        local plusWidth = maxed and clamp(round(42*cardScale), 38, 46) or plusSize
        local plusX, plusY = rect.x + rect.w - plusWidth - 8, rect.y + 8
        UI.roundFrame(self, plusX, plusY, plusWidth, plusSize, 6,
            maxed and c.ok or (hovered and c.accent or c.line), c.panel2, maxed and 0.75 or 1)
        UI.textCentre(self, maxed and "MAX" or "+", plusX + math.floor(plusWidth/2),
            plusY + math.floor((plusSize - UI.fontHeight(UIFont.Small)) / 2), UIFont.Small,
            maxed and c.ok or c.accentHi)
    end

    local nameY
    if isVehicle then
        nameY = self:layoutVehicleScene(slot, product, rect, offered)
    else
        if slot and self.vehicleScenePool[slot] then self.vehicleScenePool[slot]:setVisible(false) end
        local iconSize = clamp(rect.h - 100, 42, clamp(round(64*cardScale), 44, 74))
        local iconY = rect.y + clamp(round(38*cardScale), 32, 42)
        renderProductIcon(self, product, rect.x + math.floor((rect.w - iconSize) / 2), iconY, iconSize,
            maxed and 0.35 or 1)
        nameY = iconY + iconSize + 4
    end
    self:drawCardText(product, LS.productName(product), rect, nameY, hovered, maxed and c.muted or c.text)
    -- Vehicle cards skip the description line entirely: the model already
    -- shows what it is, the text was fighting the price row for the same
    -- few pixels below a viewport this wide, and "Veículo completo,
    -- entregue..." said nothing a screenshot of the actual car doesn't.
    if not isVehicle then
        local description = maxed and LS.text("MaxLevelReached", "NÍVEL MÁXIMO ATINGIDO")
            or LS.productDescription(product, xpAmount, perkLevel)
        self:drawCardText(product, description, rect,
            nameY + UI.fontHeight(UIFont.Small) + 2, hovered, maxed and c.ok or c.muted)
    end

    local priceY = rect.y + rect.h - UI.fontHeight(UIFont.Small) - 11
    if maxed then
        UI.textCentre(self, LS.text("MaxLevelShort", "NÍVEL MÁXIMO"),
            rect.x + math.floor(rect.w / 2), priceY, UIFont.Small, c.ok)
        return
    end
    local coin = texture("coins-solid")
    local groupX = rect.x + 12
    if coin then self:drawTextureScaled(coin, groupX, priceY + 1, 14, 14, 1, 1, 1, 1) end
    groupX = groupX + 19
    local priceEndX
    if offered then
        local originalText = tostring(original)
        UI.text(self, originalText, groupX, priceY, UIFont.Small, c.muted)
        local originalW = UI.textWidth(UIFont.Small, originalText)
        self:drawRect(groupX, priceY + math.floor(UI.fontHeight(UIFont.Small) / 2), originalW, 1,
            1, c.danger.r, c.danger.g, c.danger.b)
        local priceText = tostring(price)
        UI.text(self, priceText, groupX + originalW + 8, priceY, UIFont.Small, c.gold)
        priceEndX = groupX + originalW + 8 + UI.textWidth(UIFont.Small, priceText)
    else
        local priceText = tostring(price)
        UI.text(self, priceText, groupX, priceY, UIFont.Small, c.gold)
        priceEndX = groupX + UI.textWidth(UIFont.Small, priceText)
    end
    -- Faction Comércio upgrade preview: the SAME price further reduced by
    -- the player's own faction's flat discount, shown in parentheses right
    -- after the normal price -- explicit user spec ("ao lado do preço...
    -- entre parênteses... o preço com o desconto do aprimoramento... azul
    -- claro... sem excesso de informação"). Only appears when there's an
    -- active discount to show; a second xpCardPreview call (includeCommerce
    -- = true) keeps this on the EXACT same LS.priceFor rounding path as
    -- what cartTotal/the purchase request will actually charge, instead of
    -- an independently-rounded second pass that could disagree by a credit.
    local commercePct = self:commerceDiscountPercent()
    if commercePct > 0 then
        local _, _, commercePrice = self:xpCardPreview(product, true)
        if commercePrice and commercePrice < price then
            UI.text(self, " (" .. tostring(commercePrice) .. ")", priceEndX, priceY, UIFont.Small, c.discount)
        end
    end
    local quantityLabel = product.kind == "xp" and ("+" .. tostring(xpAmount) .. " XP")
        or ("x" .. tostring(product.quantity or 1))
    UI.textRight(self, quantityLabel, rect.x + rect.w - 11, priceY, UIFont.Small, c.muted)
end

function LasciviousShopWindow:drawCatalog(l)
    local c = UI.col
    local cardRectCount, pageRectCount = 0, 0
    self._marqueeHoveredThisFrame = false
    local productIds = self:filteredProductIds()
    local pageCount = math.max(1, math.ceil(#productIds / l.perPage))
    self.currentPage = math.max(1, math.min(self.currentPage, pageCount))
    local cardW = math.floor((l.contentW - l.cardGap * (l.columns - 1)) / l.columns)
    local cardH = math.floor((l.gridH - l.cardGap * (l.rows - 1)) / l.rows)
    local startIndex = (self.currentPage - 1) * l.perPage + 1
    for slot = 1, l.perPage do
        local productId = productIds[startIndex + slot - 1]
        local product = productId and LS.PRODUCT_BY_ID[productId] or nil
        if not product then break end
        local column = (slot - 1) % l.columns
        local row = math.floor((slot - 1) / l.columns)
        cardRectCount = cardRectCount + 1
        local rect = reuseRect(self.cardRects, cardRectCount,
            l.contentX + column * (cardW + l.cardGap),
            l.gridY + row * (cardH + l.cardGap), cardW, cardH)
        rect.product, rect.scale = product, l.scale
        self:drawCard(product, rect, cardRectCount)
    end
    trimRects(self.cardRects, cardRectCount)
    for slot = cardRectCount + 1, MAX_GRID_SLOTS do
        local scene = self.vehicleScenePool[slot]
        if scene then scene:setVisible(false) end
    end
    if not self._marqueeHoveredThisFrame then self.marqueeProductId = nil end
    if #productIds == 0 then
        UI.textCentre(self, LS.text("NoProducts", "Nenhum produto encontrado."),
            l.contentX + math.floor(l.contentW / 2), l.gridY + math.floor(l.gridH / 2), UIFont.Medium, c.muted)
    end

    if pageCount > 1 then
        local buttonW = clamp(round(32*l.scale), 29, 36)
        local buttonH = clamp(round(30*l.scale), 28, 34)
        local gap = clamp(round(6*l.scale), 5, 7)
        local paginationKey = tostring(pageCount) .. ":" .. tostring(self.currentPage)
        local pages = self._paginationKey == paginationKey and self._paginationPages or nil
        if not pages then
            pages = {}
            if pageCount <= 7 then
                for page = 1, pageCount do pages[#pages + 1] = page end
            else
                pages[#pages + 1] = 1
                local first = math.max(2, self.currentPage - 1)
                local last = math.min(pageCount - 1, self.currentPage + 1)
                if self.currentPage <= 4 then last = 5 end
                if self.currentPage >= pageCount - 3 then first = pageCount - 4 end
                if first > 2 then pages[#pages + 1] = "ellipsis" end
                for page = first, last do pages[#pages + 1] = page end
                if last < pageCount - 1 then pages[#pages + 1] = "ellipsis" end
                pages[#pages + 1] = pageCount
            end
            self._paginationKey, self._paginationPages = paginationKey, pages
        end
        local totalW = (#pages + 2) * buttonW + (#pages + 1) * gap
        local x = l.contentX + math.floor((l.contentW - totalW) / 2)
        local function pageButton(label, target, enabled, active)
            pageRectCount = pageRectCount + 1
            local rect = reuseRect(self.pageRects, pageRectCount,
                x, l.paginationY+4, buttonW, buttonH)
            rect.page, rect.enabled = target, enabled
            UI.roundFrame(self, rect.x, rect.y, rect.w, rect.h, 6,
                active and c.accent or c.line, active and c.accentDim or c.panel2, enabled and 1 or 0.45)
            UI.textCentre(self, label, rect.x + math.floor(buttonW/2),
                rect.y + math.floor((buttonH-UI.fontHeight(UIFont.Small))/2), UIFont.Small,
                active and c.text or c.muted, enabled and 1 or 0.45)
            x = x + buttonW + gap
        end
        pageButton("<", self.currentPage - 1, self.currentPage > 1, false)
        for _, page in ipairs(pages) do
            if page == "ellipsis" then
                pageButton("...", self.currentPage, false, false)
            else
                pageButton(tostring(page), page, true, page == self.currentPage)
            end
        end
        pageButton(">", self.currentPage + 1, self.currentPage < pageCount, false)
    end
    trimRects(self.pageRects, pageRectCount)
end

function LasciviousShopWindow:drawCart(l)
    local c = UI.col
    local x, w = l.cartX, l.cartW
    local headPad = clamp(round(15*l.scale), 11, 16)
    self:drawRect(x, l.headerH, w - 1, self.height - l.headerH - 1, 1, c.bg.r, c.bg.g, c.bg.b)
    self:drawRect(x, l.headerH, 1, self.height - l.headerH, 1, c.line.r, c.line.g, c.line.b)
    local count = self:cartCount()
    UI.text(self, LS.text("Cart", "SEU CARRINHO"), x + headPad,
        l.headerH + clamp(round(17*l.scale), 13, 19), UIFont.Small, c.text)
    local countText = tostring(count) .. " " .. LS.text(count == 1 and "Item" or "Items", count == 1 and "item" or "itens")
    UI.textRight(self, countText, x + w - headPad,
        l.headerH + clamp(round(17*l.scale), 13, 19), UIFont.Small, c.muted)
    local cartDividerY = l.headerH + clamp(round(47*l.scale), 39, 50)
    self:drawRect(x + 12, cartDividerY, w - 24, 1, 1, c.line.r, c.line.g, c.line.b)

    local buyH = clamp(round(42*l.scale), 38, 46)
    local bottomPad = clamp(round(14*l.scale), 10, 16)
    local buySidePad = clamp(round(14*l.scale), 10, 16)
    local bottomY = self.height - bottomPad
    self.buyRect = self.buyRect or {}
    self.buyRect.x, self.buyRect.y = x+buySidePad, bottomY-buyH
    self.buyRect.w, self.buyRect.h = w-buySidePad*2, buyH
    local totalY = self.buyRect.y - clamp(round(47*l.scale), 43, 52)
    self:drawRect(x + 12, totalY - 9, w - 24, 1, 1, c.line.r, c.line.g, c.line.b)
    local totalLabel = LS.text("Total", "TOTAL")
    UI.text(self, totalLabel, x + headPad, totalY + 7, UIFont.Small, c.muted)
    local total = self:cartTotal()
    local coin = texture("coins-solid")
    local totalText = tostring(total)
    local totalCoinSize = clamp(round(22*l.scale), 20, 24)
    local totalGap = clamp(round(8*l.scale), 6, 9)
    local totalRight = x + w - headPad
    local totalCoinX = totalRight - totalCoinSize
    UI.textRight(self, totalText, totalCoinX - totalGap, totalY + 5, UIFont.Medium, c.gold)
    if coin then
        -- The coin stays anchored in the cart corner after the number. Its
        -- artwork has extra transparent space at the top, hence the +8 offset.
        self:drawTextureScaled(coin, totalCoinX, totalY + 8,
            totalCoinSize, totalCoinSize, 1, 1, 1, 1)
    end
    -- Faction Comércio upgrade hint: small, discreet, directly below the
    -- "TOTAL" label itself (not the gold number) -- explicit user spec
    -- ("abaixo do texto TOTAL... sem forçar o texto TOTAL ir para cima").
    -- totalY itself is never touched -- this only adds a line in the
    -- existing slack between the total row and the buy button below it.
    local commercePct = self:commerceDiscountPercent()
    if commercePct > 0 then
        local discountNoteY = totalY + 7 + UI.fontHeight(UIFont.Small) + clamp(round(2*l.scale), 1, 3)
        local discountNoteText = LS.text("CartCommerceDiscount",
            "(com %1% de desconto)", tostring(commercePct))
        UI.text(self, discountNoteText, x + headPad, discountNoteY, UIFont.Small, c.discount, 0.8)
    end

    local enough = (tonumber(state().balance) or 0) + 0.0001 >= total
    local buyEnabled = count > 0 and enough and Client.state ~= nil and not Client.awaitingPurchase
    local buyHovered = buyEnabled and UI.inside(self.buyRect, self:getMouseX(), self:getMouseY())
    if buyHovered then UI.glow(self, self.buyRect.x, self.buyRect.y, self.buyRect.w, self.buyRect.h, 8, 0.17, c.accent) end
    UI.roundFrame(self, self.buyRect.x, self.buyRect.y, self.buyRect.w, self.buyRect.h, 8,
        buyEnabled and c.accentHi or c.line, buyEnabled and c.accentDim or c.panel2, buyEnabled and 1 or 0.5)
    local bag = texture("bag-shopping-solid")
    local buyText = Client.awaitingPurchase and LS.text("Buying", "COMPRANDO...") or LS.text("Buy", "COMPRAR")
    local textW = UI.textWidth(UIFont.Small, buyText)
    local contentW = textW + (bag and 24 or 0)
    local contentX = self.buyRect.x + math.floor((self.buyRect.w - contentW) / 2)
    if bag then
        self:drawTextureScaled(bag, contentX, self.buyRect.y + 12, 18, 18, buyEnabled and 1 or 0.45,
            c.accentHi.r, c.accentHi.g, c.accentHi.b)
        contentX = contentX + 24
    end
    UI.text(self, buyText, contentX,
        self.buyRect.y + math.floor((buyH - UI.fontHeight(UIFont.Small)) / 2), UIFont.Small,
        buyEnabled and c.text or c.muted, buyEnabled and 1 or 0.55)
    self.buyEnabled = buyEnabled

    local listTop = cartDividerY + clamp(round(12*l.scale), 9, 13)
    local listBottom = totalY - 16
    self.cartListRect = self.cartListRect or {}
    self.cartListRect.x, self.cartListRect.y = x+9, listTop
    self.cartListRect.w, self.cartListRect.h = w-18, listBottom-listTop
    local minusRectCount, plusRectCount = 0, 0
    local liveIds = self.cartOrder
    local visibleRows = math.max(1, math.floor(self.cartListRect.h / l.cartRowH))
    local maxScroll = math.max(0, #liveIds - visibleRows)
    self.cartScroll = math.max(0, math.min(self.cartScroll, maxScroll))
    if #liveIds == 0 then
        trimRects(self.cartMinusRects, 0)
        trimRects(self.cartPlusRects, 0)
        local emptyIcon = texture("cart-shopping-solid")
        if emptyIcon then
            local emptySize = clamp(round(42*l.scale), 36, 46)
            self:drawTextureScaled(emptyIcon, x + math.floor((w-emptySize)/2),
                listTop + clamp(round(35*l.scale), 25, 38), emptySize, emptySize, 0.45,
                c.muted.r, c.muted.g, c.muted.b)
        end
        UI.textCentre(self, LS.text("EmptyCart", "Seu carrinho está vazio."), x + math.floor(w/2),
            listTop + clamp(round(88*l.scale), 70, 94), UIFont.Small, c.muted)
        UI.textCentre(self, LS.text("EmptyCartHint", "Selecione um item para adicionar."), x + math.floor(w/2),
            listTop + clamp(round(88*l.scale), 70, 94) + UI.fontHeight(UIFont.Small) + 3, UIFont.Small, c.muted, 0.75)
        return
    end

    for row = 1, visibleRows do
        local id = liveIds[self.cartScroll + row]
        if not id then break end
        local product = LS.PRODUCT_BY_ID[id]
        local qty = tonumber(self.cart[id]) or 0
        local y = listTop + (row - 1) * l.cartRowH
        local rowFrameH = l.cartRowH - 6
        UI.roundFrame(self, x + 9, y, w - 18, rowFrameH, 7, c.line, c.panel2)
        local rowIconSize = clamp(round(34*l.scale), 30, 38)
        renderProductIcon(self, product, x + 17, y + math.floor((rowFrameH-rowIconSize)/2), rowIconSize, 1)
        local productTextX = x + 17 + rowIconSize + 8
        UI.textFit(self, LS.productName(product), productTextX, y + 8,
            math.max(28, x+w-83-productTextX), UIFont.Small, c.text)
        local rowDetail = product and product.kind == "xp"
            and ("+" .. tostring(self:xpAmount(product, qty)) .. " XP • "
                .. tostring(self:linePrice(product, qty, true)) .. " cr")
            or (tostring(self:unitPrice(product, true)) .. " cr")
        UI.textFit(self, rowDetail, productTextX,
            y + 10 + UI.fontHeight(UIFont.Small), math.max(28, x+w-83-productTextX),
            UIFont.Small, c.muted)
        local controlY = y + math.floor((rowFrameH-22)/2)
        minusRectCount = minusRectCount + 1
        local minus = reuseRect(self.cartMinusRects, minusRectCount, x+w-77, controlY, 20, 22)
        minus.id = id
        local xpPackage = product and product.kind == "xp"
        local xpAtLimit = xpPackage and qty >= 10 - self:perkLevel(product)
        local plusX = x + w - 31
        if not xpAtLimit then
            plusRectCount = plusRectCount + 1
            local plus = reuseRect(self.cartPlusRects, plusRectCount, plusX, controlY, 20, 22)
            plus.id = id
        end
        UI.roundFrame(self, minus.x, minus.y, minus.w, minus.h, 5, c.line, c.card)
        UI.roundFrame(self, plusX, controlY, 20, 22, 5, c.line, c.card, xpAtLimit and 0.4 or 1)
        UI.textCentre(self, "-", minus.x+10, minus.y+math.floor((22-UI.fontHeight(UIFont.Small))/2), UIFont.Small, c.muted)
        UI.textCentre(self, xpAtLimit and "x" or "+", plusX+10,
            controlY+math.floor((22-UI.fontHeight(UIFont.Small))/2), UIFont.Small,
            xpAtLimit and c.muted or c.accentHi, xpAtLimit and 0.45 or 1)
        UI.textCentre(self, tostring(qty), x+w-44,
            y+math.floor((rowFrameH-UI.fontHeight(UIFont.Small))/2), UIFont.Small, c.text)
    end
    trimRects(self.cartMinusRects, minusRectCount)
    trimRects(self.cartPlusRects, plusRectCount)
end

function LasciviousShopWindow:drawResizeGrips()
    local c = UI.col
    local mx, my = self:getMouseX(), self:getMouseY()
    local gripY = self.height - RESIZE_GRIP
    local overLeft = mx >= 0 and mx <= RESIZE_GRIP and my >= gripY and my <= self.height
    local overRight = mx >= self.width-RESIZE_GRIP and mx <= self.width
        and my >= gripY and my <= self.height
    local active = self._resizing or overLeft or overRight
    local color = active and c.accentHi or c.muted
    local alpha = active and 0.95 or 0.48

    -- Small L-shaped corner marks stay legible at every UI scale without adding
    -- another bitmap dependency.
    self:drawRect(4, self.height-5, 9, 2, alpha, color.r, color.g, color.b)
    self:drawRect(3, self.height-13, 2, 9, alpha, color.r, color.g, color.b)
    self:drawRect(self.width-13, self.height-5, 9, 2, alpha, color.r, color.g, color.b)
    self:drawRect(self.width-5, self.height-13, 2, 9, alpha, color.r, color.g, color.b)
end

function LasciviousShopWindow:drawToast()
    local now = getTimestampMs and getTimestampMs() or 0
    if not self.toastText or now >= self.toastUntil then return end
    local c = UI.col
    local width = math.min(self.width - 80, UI.textWidth(UIFont.Small, self.toastText) + 34)
    local x = math.floor((self.width - width) / 2)
    local y = self.height - 62
    UI.shadow(self, x, y, width, 38, 8, 0.4, c.black)
    UI.roundFrame(self, x, y, width, 38, 8, c.lineHi, c.cardHi)
    UI.textCentreFit(self, self.toastText, x + math.floor(width/2),
        y + math.floor((38-UI.fontHeight(UIFont.Small))/2), width - 20, UIFont.Small, c.text)
end

-- How often the zombie-list scan itself actually re-runs while the window
-- is open (the scan is cheap but not free -- see LasciviousShop_Danger.lua).
-- self._dimAlpha still glides every single frame off whatever the last scan
-- found, so the fade reads as smooth even though the scan is throttled.
-- Same interval HardcoreKits uses for the identical check.
local DANGER_CHECK_INTERVAL_MS = 400
local CLIENT_OPTIONS_CACHE_MS = 1000

function LasciviousShopWindow:clientOptions()
    local now = getTimestampMs and getTimestampMs() or 0
    if not self._clientOptions or (now > 0 and now - (self._clientOptionsReadAt or 0) >= CLIENT_OPTIONS_CACHE_MS) then
        self._clientOptions = LS.getOptions()
        self._clientOptionsReadAt = now
    end
    return self._clientOptions
end

function LasciviousShopWindow:updateDangerAlpha()
    local opts = self:clientOptions()
    if not opts.windowDimOnDangerEnabled then
        self._dimAlpha = 1.0
        self._dangerNear = false
        return
    end
    local now = getTimestampMs and getTimestampMs() or 0
    if not self._dangerCheckedAtMs or now - self._dangerCheckedAtMs >= DANGER_CHECK_INTERVAL_MS then
        self._dangerCheckedAtMs = now
        local ok, player = pcall(getPlayer)
        self._dangerNear = ok and player
            and LasciviousShopDanger.zombiesNear(player, opts.windowDimOnDangerRadius)
            or false
    end
    local target = self._dangerNear and opts.windowDimOnDangerAlpha or 1.0
    self._dimAlpha = UI.glide(self._dimAlpha or 1.0, target, 0.25)
end

local function attackedBy(player)
    return player:getAttackedBy()
end

-- Force-closes the shop the moment the player takes a hit from an actual
-- attacker (zombie, animal, or another player) while it's open -- getting
-- ambushed mid-purchase is exactly what the dimming above tries to prevent
-- in the first place; this is the hard backstop for when it isn't enough.
-- getAttackedBy() only ever gets set by combat, never by hunger/thirst/cold/
-- disease/fall damage, so "normal" damage naturally never triggers this --
-- no extra filtering needed. Baseline is whatever getAttackedBy() already
-- returned when the shop was opened (see LasciviousShopWindow.open()), so a
-- fight that was already winding down before the player opened the shop
-- doesn't instantly slam it shut; only a genuinely NEW hit does.
function LasciviousShopWindow:checkAttackedClose()
    local opts = self:clientOptions()
    if not opts.closeOnAttackEnabled then return end
    local ok, player = pcall(getPlayer)
    if not (ok and player) then return end
    local gotAttacker, attacker = pcall(attackedBy, player)
    if not gotAttacker then return end
    if attacker ~= nil and attacker ~= self._lastAttacker then
        self._lastAttacker = attacker
        self:close()
        return
    end
    self._lastAttacker = attacker
end

function LasciviousShopWindow:prerender()
    self:updateDangerAlpha()
    self:checkAttackedClose()
    local l = self:layout()
    self:syncChildLayout(l)
    Client.clearPurchaseTimeout()
    Client.clearTransferTimeout()
    local now = getTimestamp and getTimestamp() or 0
    if now - (self.lastStateRequest or 0) >= 15 then
        self.lastStateRequest = now
        Client.requestState()
    end
    if self.transferOpen and now - (self.transferLastListRequest or 0) >= TRANSFER_LIST_REFRESH_SECONDS then
        self.transferLastListRequest = now
        Client.requestTransferList()
    end
    local c = UI.col
    UI.shadow(self, 0, 0, self.width, self.height, 26, 0.52, c.black)
    UI.glow(self, 0, 0, self.width, self.height, 30, 0.08, c.accent)
    UI.roundFrame(self, 0, 0, self.width, self.height, 13, c.lineHi, c.bg)
    self:drawHeader(l)
    self:drawSidebar(l)
    self:drawBalanceAndToolbar(l)
    self:drawCatalog(l)
    self:drawCart(l)
    self:drawResizeGrips()
    if not Client.state then
        UI.roundFrame(self, l.contentX + math.floor((l.contentW-260)/2), l.gridY + 25,
            260, 42, 8, c.line, c.panel2)
        UI.textCentre(self, LS.text("Syncing", "Sincronizando com o servidor..."),
            l.contentX + math.floor(l.contentW/2), l.gridY + 25 + math.floor((42-UI.fontHeight(UIFont.Small))/2),
            UIFont.Small, c.muted)
    end
    self:drawToast()
    -- Always last: must paint over literally everything above, including
    -- the toast, to actually be "on top" rather than just usually on top.
    if self.transferOpen then self:drawTransferPopup() end
end

function LasciviousShopWindow:render() end

function LasciviousShopWindow:layoutGrips()
    if self.resizeGripBR then
        self.resizeGripBR:setX(self:getWidth() - RESIZE_GRIP)
        self.resizeGripBR:setY(self:getHeight() - RESIZE_GRIP)
    end
    if self.resizeGripBL then
        self.resizeGripBL:setX(0)
        self.resizeGripBL:setY(self:getHeight() - RESIZE_GRIP)
    end
end

function LasciviousShopWindow:savePanelState()
    local player = getPlayer()
    local modData = player and player:getModData()
    if not modData then return end
    modData[PANEL_STATE_KEY] = {
        x=math.floor(self:getX()), y=math.floor(self:getY()),
        w=math.floor(self:getWidth()), h=math.floor(self:getHeight()),
        sort=VALID_SORT_MODES[self.sortMode] and self.sortMode or "default",
    }
end

function LasciviousShopWindow:onResized(width, height)
    self:setWidth(math.floor(width))
    self:setHeight(math.floor(height))
    self._layoutCache = nil
    self._childLayout = nil
    self:layoutGrips()
end

function LasciviousShopWindow:resizeByDelta(corner, dx, dy)
    self._resizing = true
    local screenW, screenH = getCore():getScreenWidth(), getCore():getScreenHeight()
    local x, y = self:getX(), self:getY()
    local width, height = self:getWidth(), self:getHeight()
    local minW, minH = math.min(MIN_W, screenW), math.min(MIN_H, screenH)

    local maxH = math.max(minH, screenH - y)
    local newH = clamp(height + dy, minH, maxH)
    local newW
    if corner == "br" then
        local maxW = math.max(minW, screenW - x)
        newW = clamp(width + dx, minW, maxW)
    else
        local right = x + width
        newW = math.max(minW, width - dx)
        local newX = right - newW
        if newX < 0 then
            newX = 0
            newW = right
        end
        self:setX(newX)
    end

    self:onResized(newW, newH)
end

function LasciviousShopWindow:endResize()
    self._resizing = false
    self:savePanelState()
end

function LasciviousShopWindow:constrainToScreen()
    local screenW, screenH = getCore():getScreenWidth(), getCore():getScreenHeight()
    local minW, minH = math.min(MIN_W, screenW), math.min(MIN_H, screenH)
    local width = clamp(self:getWidth(), minW, screenW)
    local height = clamp(self:getHeight(), minH, screenH)
    self:onResized(width, height)
    self:setX(clamp(self:getX(), 0, math.max(0, screenW-width)))
    self:setY(clamp(self:getY(), 0, math.max(0, screenH-height)))
end

function LasciviousShopWindow:onMouseDown(x, y)
    self:bringToTop()
    -- Modal gate: while the transfer popup is open, it is the only thing
    -- that gets to see clicks, including ones that land outside its own
    -- box but still inside the window (the full-window dim backdrop is
    -- drawn precisely so nothing behind it looks or acts clickable). This
    -- is what actually keeps it "on top" from an input standpoint, not
    -- just a z-order/visual guarantee.
    if self.transferOpen then
        if UI.inside(self.transferCloseRect, x, y) then self.transferPendingClose = true return true end
        if self.transferCanSend and UI.inside(self.transferSendRect, x, y) then
            self.transferPendingSend = true
            return true
        end
        for _, rect in ipairs(self.transferPlayerRects or {}) do
            if UI.inside(rect, x, y) then
                self.transferSelectedTarget = rect.name
                UI.playSound(UI.SOUND.click)
                return true
            end
        end
        return true
    end
    if UI.inside(self.closeRect, x, y) then self.pendingClose = true return true end
    if UI.inside(self.transferButtonRect, x, y) then
        UI.playSound(UI.SOUND.click)
        self:openTransferPopup()
        return true
    end
    for _, rect in ipairs(self.categoryRects or {}) do
        if UI.inside(rect, x, y) then
            UI.playSound(UI.SOUND.click)
            self.activeCategory = rect.id
            self:markFilterDirty()
            return true
        end
    end
    for _, rect in ipairs(self.cardRects or {}) do
        if UI.inside(rect, x, y) then self:addToCart(rect.product) return true end
    end
    for _, rect in ipairs(self.cartMinusRects or {}) do
        if UI.inside(rect, x, y) then self:changeCart(rect.id, -1) return true end
    end
    for _, rect in ipairs(self.cartPlusRects or {}) do
        if UI.inside(rect, x, y) then self:changeCart(rect.id, 1) return true end
    end
    for _, rect in ipairs(self.pageRects or {}) do
        if rect.enabled and UI.inside(rect, x, y) then
            UI.playSound(UI.SOUND.click)
            self.currentPage = rect.page
            return true
        end
    end
    if self.buyEnabled and UI.inside(self.buyRect, x, y) then self.pendingBuy = true return true end
    if y <= self:layout().headerH then
        self.dragging = true
        self:setCapture(true)
        return true
    end
    return false
end

function LasciviousShopWindow:onMouseUp(x, y)
    if self.transferOpen then
        if self.transferPendingClose then
            self.transferPendingClose = false
            if UI.inside(self.transferCloseRect, x, y) then self:closeTransferPopup() end
        end
        if self.transferPendingSend then
            self.transferPendingSend = false
            if UI.inside(self.transferSendRect, x, y) then self:sendTransfer() end
        end
        return true
    end
    local wasDragging = self.dragging
    self.dragging = false
    if wasDragging then
        self:setCapture(false)
        self:savePanelState()
    end
    if self.pendingClose then
        self.pendingClose = false
        if UI.inside(self.closeRect, x, y) then self:close() return true end
    end
    if self.pendingBuy then
        self.pendingBuy = false
        if self.buyEnabled and UI.inside(self.buyRect, x, y) then self:purchase() return true end
    end
    return false
end

function LasciviousShopWindow:onMouseUpOutside(x, y)
    if self.transferOpen then
        self.transferPendingClose = false
        self.transferPendingSend = false
        return
    end
    local wasDragging = self.dragging
    self.dragging = false
    if wasDragging then
        self:setCapture(false)
        self:savePanelState()
    end
    self.pendingClose = false
    self.pendingBuy = false
end

function LasciviousShopWindow:onMouseMove(dx, dy)
    if not self.dragging then return end
    local screenW, screenH = getCore():getScreenWidth(), getCore():getScreenHeight()
    self:setX(math.max(0, math.min(self:getX() + dx, screenW - self:getWidth())))
    self:setY(math.max(0, math.min(self:getY() + dy, screenH - self:getHeight())))
end

function LasciviousShopWindow:onMouseMoveOutside(dx, dy)
    self:onMouseMove(dx, dy)
end

function LasciviousShopWindow:onMouseWheel(delta)
    if self.transferOpen then
        if UI.inside(self.transferListRect, self:getMouseX(), self:getMouseY()) then
            self.transferListScroll = math.max(0, self.transferListScroll - delta)
        end
        return true
    end
    if UI.inside(self.cartListRect, self:getMouseX(), self:getMouseY()) then
        self.cartScroll = math.max(0, self.cartScroll - delta)
        return true
    end
    return false
end

function LasciviousShopWindow:isKeyConsumed(key)
    return key == Keyboard.KEY_ESCAPE
end

function LasciviousShopWindow:onKeyRelease(key)
    if key ~= Keyboard.KEY_ESCAPE then return end
    if self.transferOpen then
        self:closeTransferPopup()
        return
    end
    if self.searchEntry and self.searchEntry:isFocused() then
        self.searchEntry:unfocus()
        return
    end
    self:close()
end

function LasciviousShopWindow:close()
    -- Closing the main window must take the transfer popup down with it --
    -- silently, no sound/state-save of its own, it's not a separate window.
    if self.transferOpen then
        self.transferOpen = false
        if self.transferSearchEntry then self.transferSearchEntry:setVisible(false) end
        if self.transferAmountEntry then self.transferAmountEntry:setVisible(false) end
        if self.searchEntry then self.searchEntry:setVisible(true) end
        if self.sortCombo then self.sortCombo:setVisible(true) end
        if self.resizeGripBR then self.resizeGripBR:setVisible(true) end
        if self.resizeGripBL then self.resizeGripBL:setVisible(true) end
    end
    UI.playSound(UI.SOUND.close)
    self:savePanelState()
    if self.dragging then self:setCapture(false) end
    -- A resize grip owns mouse capture independently of the parent. If danger
    -- closes the shop mid-drag, release it explicitly or the invisible child
    -- can keep consuming mouse input until the next click.
    for _, grip in ipairs({ self.resizeGripBR, self.resizeGripBL }) do
        if grip and grip.dragging then
            grip.dragging = false
            grip:setCapture(false)
        end
    end
    self:setVisible(false)
    self.dragging = false
    self._resizing = false
    self.pendingClose = false
    self.pendingBuy = false
    self.transferPendingClose = false
    self.transferPendingSend = false
    if self.searchEntry then self.searchEntry:unfocus() end
    if self.transferSearchEntry then self.transferSearchEntry:unfocus() end
    if self.transferAmountEntry then self.transferAmountEntry:unfocus() end
end

-- ===================================================================
-- Send Credits: a modal popup, not a separate window -- see the comment on
-- the transferOpen gate in onMouseDown for why. Everything below reads
-- Client.onlinePlayers (server-pushed, never the client's own guess at who
-- is online) and only ever calls Client.requestTransfer, which the server
-- re-validates completely independently (see Commands[LS.CMD_TRANSFER] in
-- LasciviousShop_Server.lua) -- nothing here is trusted, it's all just
-- presentation.
-- ===================================================================

function LasciviousShopWindow:transferPopupRect()
    local cached = self._transferPopupRect
    if cached and self._transferPopupRectWidth == self.width
        and self._transferPopupRectHeight == self.height then return cached end
    local w = math.min(TRANSFER_POPUP_W, self.width - 32)
    local h = math.min(TRANSFER_POPUP_H, self.height - 32)
    cached = cached or {}
    cached.x, cached.y = math.floor((self.width - w) / 2), math.floor((self.height - h) / 2)
    cached.w, cached.h = w, h
    self._transferPopupRect = cached
    self._transferPopupRectWidth, self._transferPopupRectHeight = self.width, self.height
    return cached
end

-- Every Y coordinate the popup's content needs, computed once and shared
-- between drawing and the two real child widgets (search/amount entries)
-- so the drawn boxes and the actual input widgets can never drift apart.
function LasciviousShopWindow:transferPopupLayout()
    local p = self:transferPopupRect()
    -- Title renders in UIFont.Medium, not Small -- titleH has to match that
    -- font or the search box (and everything below it) creeps up into the
    -- title's own glyphs instead of sitting under them.
    local titleH = UI.fontHeight(UIFont.Medium)
    local searchY = p.y + TRANSFER_EDGE + titleH + 14
    local searchH = 40
    local listY = searchY + searchH + 10
    local amountH = 42
    local sendH = 44
    local bottomBlockH = amountH + 12 + sendH
    local listBottom = p.y + p.h - TRANSFER_EDGE - bottomBlockH
    local listH = math.max(90, listBottom - listY - 10)
    local amountY = listY + listH + 10
    local sendY = amountY + amountH + 12
    local result = self._transferPopupLayout or {}
    result.popup, result.titleH = p, titleH
    result.searchY, result.searchH = searchY, searchH
    result.listY, result.listH = listY, listH
    result.amountY, result.amountH = amountY, amountH
    result.sendY, result.sendH = sendY, sendH
    self._transferPopupLayout = result
    return result
end

function LasciviousShopWindow:syncTransferChildLayout()
    if not self.transferSearchEntry then return end
    local tl = self:transferPopupLayout()
    local p = tl.popup
    self.transferSearchEntry:setX(p.x + TRANSFER_EDGE)
    self.transferSearchEntry:setY(tl.searchY)
    self.transferSearchEntry:setWidth(p.w - TRANSFER_EDGE * 2)
    self.transferSearchEntry:setHeight(tl.searchH)
    self.transferAmountEntry:setX(p.x + TRANSFER_EDGE)
    self.transferAmountEntry:setY(tl.amountY)
    self.transferAmountEntry:setWidth(p.w - TRANSFER_EDGE * 2)
    self.transferAmountEntry:setHeight(tl.amountH)
end

function LasciviousShopWindow:openTransferPopup()
    self.transferOpen = true
    self.transferSelectedTarget = nil
    self.transferListScroll = 0
    -- Acknowledge whatever result is already sitting there from a previous
    -- send this session, so onNetworkUpdate only reacts to a genuinely new
    -- one -- same reasoning as handledResult/handledError for purchases.
    self.transferHandledResult = Client.lastTransferResult
    -- drawTransferPopup's dim backdrop only covers what the window paints
    -- directly in its own prerender -- real child widgets (search box, sort
    -- combo, resize grips) render in a pass the engine always does AFTER
    -- that, so they'd otherwise show through/on top of the modal no matter
    -- where drawTransferPopup is called from. Hiding them is what actually
    -- keeps the popup "on top" and stops them from eating input underneath it.
    if self.searchEntry then
        self.searchEntry:unfocus()
        self.searchEntry:setVisible(false)
    end
    if self.sortCombo then self.sortCombo:setVisible(false) end
    if self.resizeGripBR then self.resizeGripBR:setVisible(false) end
    if self.resizeGripBL then self.resizeGripBL:setVisible(false) end
    if self.transferSearchEntry then
        self.transferSearchEntry:setText("")
        self.transferSearchEntry:setVisible(true)
    end
    if self.transferAmountEntry then
        self.transferAmountEntry:setText("")
        self.transferAmountEntry:setVisible(true)
    end
    self:syncTransferChildLayout()
    self.transferLastListRequest = 0
    UI.playSound(UI.SOUND.open)
end

function LasciviousShopWindow:closeTransferPopup()
    if not self.transferOpen then return end
    self.transferOpen = false
    if self.transferSearchEntry then
        self.transferSearchEntry:setVisible(false)
        self.transferSearchEntry:unfocus()
    end
    if self.transferAmountEntry then
        self.transferAmountEntry:setVisible(false)
        self.transferAmountEntry:unfocus()
    end
    if self.searchEntry then self.searchEntry:setVisible(true) end
    if self.sortCombo then self.sortCombo:setVisible(true) end
    if self.resizeGripBR then self.resizeGripBR:setVisible(true) end
    if self.resizeGripBL then self.resizeGripBL:setVisible(true) end
    UI.playSound(UI.SOUND.close)
end

function LasciviousShopWindow:filteredOnlinePlayers()
    local query = self.transferSearchEntry and self.transferSearchEntry.getText
        and Search.normalize(self.transferSearchEntry:getText() or "") or ""
    local list = type(Client.onlinePlayers) == "table" and Client.onlinePlayers or {}
    if query == "" then return list end
    local receivedAt = Client.onlinePlayersReceivedAt or 0
    if self._transferFilterQuery == query and self._transferFilterReceivedAt == receivedAt
        and self._transferFilteredPlayers then return self._transferFilteredPlayers end
    local out = {}
    for _, name in ipairs(list) do
        if string.find(Search.normalize(name), query, 1, true) then table.insert(out, name) end
    end
    self._transferFilterQuery = query
    self._transferFilterReceivedAt = receivedAt
    self._transferFilteredPlayers = out
    return out
end

function LasciviousShopWindow:sendTransfer()
    if not self.transferOpen or Client.awaitingTransfer then return end
    local target = self.transferSelectedTarget
    if not target then
        return self:showToast(LS.text("SendCreditsNoTarget", "Selecione um jogador para enviar."))
    end
    local amountText = self.transferAmountEntry and self.transferAmountEntry:getText() or ""
    local amount = math.floor(LS.finiteNumber(amountText, 0))
    if amount <= 0 then
        return self:showToast(LS.text("SendCreditsNoAmount", "Digite uma quantidade válida."))
    end
    local balance = tonumber(state().balance) or 0
    if amount > balance then
        return self:showToast(LS.text("InsufficientCredits", "Créditos insuficientes."))
    end
    if Client.requestTransfer(target, amount) then
        self:showToast(LS.text("SendCreditsSending", "Enviando..."), 1200)
    end
end

function LasciviousShopWindow:drawTransferPopup()
    local c = UI.col
    -- Dims the ENTIRE window, not just a border around the popup: this is
    -- what visually communicates "the shop behind this is paused", matching
    -- the input gate in onMouseDown that backs it up functionally.
    self:drawRect(0, 0, self.width, self.height, 0.62, 0, 0, 0)

    local tl = self:transferPopupLayout()
    local p = tl.popup
    UI.shadow(self, p.x, p.y, p.w, p.h, 22, 0.5, c.black)
    UI.roundFrame(self, p.x, p.y, p.w, p.h, 12, c.lineHi, c.bg)
    UI.text(self, LS.text("SendCreditsTitle", "Enviar Créditos"), p.x + TRANSFER_EDGE, p.y + TRANSFER_EDGE,
        UIFont.Medium, c.text)

    local closeSize = 24
    self.transferCloseRect = self.transferCloseRect or {}
    local closeRect = self.transferCloseRect
    closeRect.x, closeRect.y = p.x + p.w - TRANSFER_EDGE - closeSize, p.y + TRANSFER_EDGE - 6
    closeRect.w, closeRect.h = closeSize, closeSize
    local hoveredClose = UI.inside(closeRect, self:getMouseX(), self:getMouseY())
    UI.roundFrame(self, closeRect.x, closeRect.y, closeSize, closeSize, 7,
        hoveredClose and c.lineHi or c.line, c.panel2)
    UI.textCentre(self, "X", closeRect.x + math.floor(closeSize / 2),
        closeRect.y + math.floor((closeSize - UI.fontHeight(UIFont.Small)) / 2), UIFont.Small, c.muted)

    local players = self:filteredOnlinePlayers()
    local rowH, rowGap = TRANSFER_ROW_H, TRANSFER_ROW_GAP
    local visibleRows = math.max(1, math.floor((tl.listH + rowGap) / (rowH + rowGap)))
    local maxScroll = math.max(0, #players - visibleRows)
    self.transferListScroll = math.max(0, math.min(self.transferListScroll, maxScroll))
    self.transferListRect = self.transferListRect or {}
    local listRect = self.transferListRect
    listRect.x, listRect.y = p.x + TRANSFER_EDGE, tl.listY
    listRect.w, listRect.h = p.w - TRANSFER_EDGE * 2, tl.listH

    local rectCount = 0
    if #players == 0 then
        UI.textCentre(self, LS.text("SendCreditsNoPlayers", "Nenhum jogador encontrado."),
            listRect.x + math.floor(listRect.w / 2),
            listRect.y + math.floor(listRect.h / 2) - math.floor(UI.fontHeight(UIFont.Small) / 2),
            UIFont.Small, c.muted)
    else
        for row = 1, visibleRows do
            local name = players[self.transferListScroll + row]
            if not name then break end
            rectCount = rectCount + 1
            local rect = reuseRect(self.transferPlayerRects, rectCount,
                listRect.x, listRect.y + (row - 1) * (rowH + rowGap), listRect.w, rowH)
            rect.name = name
            local selected = self.transferSelectedTarget == name
            local hovered = UI.inside(rect, self:getMouseX(), self:getMouseY())
            UI.roundFrame(self, rect.x, rect.y, rect.w, rect.h, 8,
                selected and c.accent or (hovered and c.lineHi or c.line),
                selected and c.accentDim or c.panel2)
            local onlineLabel = LS.text("SendCreditsOnline", "Online")
            local labelW = UI.textWidth(UIFont.Small, onlineLabel)
            local dotX = rect.x + rect.w - 12 - labelW - 12
            UI.textFit(self, name, rect.x + 12, rect.y + math.floor((rect.h - UI.fontHeight(UIFont.Small)) / 2),
                dotX - rect.x - 20, UIFont.Small, c.text)
            self:drawRect(dotX, rect.y + math.floor(rect.h / 2) - 3, 6, 6, 1, c.ok.r, c.ok.g, c.ok.b)
            UI.text(self, onlineLabel, dotX + 12, rect.y + math.floor((rect.h - UI.fontHeight(UIFont.Small)) / 2),
                UIFont.Small, c.muted)
        end
    end
    trimRects(self.transferPlayerRects, rectCount)

    self.transferSendRect = self.transferSendRect or {}
    local sendRect = self.transferSendRect
    sendRect.x, sendRect.y = p.x + TRANSFER_EDGE, tl.sendY
    sendRect.w, sendRect.h = p.w - TRANSFER_EDGE * 2, tl.sendH
    local amountText = self.transferAmountEntry and self.transferAmountEntry:getText() or ""
    local amountValue = math.floor(LS.finiteNumber(amountText, 0))
    local balance = math.max(0, math.floor(tonumber(state().balance) or 0))
    -- Same enabled/disabled treatment as the cart's own Buy button (see
    -- drawCart/buyEnabled): dim accent fill + bright text when clickable,
    -- flat panel + muted text when not, instead of the old bright-fill
    -- with near-black text that read as broken.
    local canSend = self.transferSelectedTarget ~= nil and amountValue >= 1
        and amountValue <= balance and not Client.awaitingTransfer
    local hoveredSend = canSend and UI.inside(sendRect, self:getMouseX(), self:getMouseY())
    if hoveredSend then UI.glow(self, sendRect.x, sendRect.y, sendRect.w, sendRect.h, 8, 0.17, c.accent) end
    UI.roundFrame(self, sendRect.x, sendRect.y, sendRect.w, sendRect.h, 9,
        canSend and c.accentHi or c.line, canSend and c.accentDim or c.panel2, canSend and 1 or 0.5)
    UI.textCentre(self,
        Client.awaitingTransfer and LS.text("SendCreditsSending", "Enviando...")
            or LS.text("SendCreditsSend", "ENVIAR CRÉDITOS"),
        sendRect.x + math.floor(sendRect.w / 2),
        sendRect.y + math.floor((sendRect.h - UI.fontHeight(UIFont.Small)) / 2), UIFont.Small,
        canSend and c.text or c.muted, canSend and 1 or 0.55)
    self.transferCanSend = canSend
end

local function initialGeometry(screenW, screenH)
    local availableW = math.max(1, screenW - EDGE * 2)
    local availableH = math.max(1, screenH - EDGE * 2)
    local scale = math.min(1, availableW / DESIGN_W, availableH / DESIGN_H)
    local width = math.max(1, math.floor(DESIGN_W * scale))
    local height = math.max(1, math.floor(DESIGN_H * scale))
    return width, height, math.floor((screenW-width)/2), math.floor((screenH-height)/2)
end

local function ensureWindow()
    local instance = LasciviousShopWindow.instance
    if instance and instance.javaObject and not instance.removed then return instance end
    if instance and instance._networkListener then
        Client.offUpdate(instance._networkListener)
        instance._networkListener = nil
    end
    LasciviousShopWindow.instance = nil
    local screenW, screenH = getCore():getScreenWidth(), getCore():getScreenHeight()
    local width, height, x, y = initialGeometry(screenW, screenH)
    local player = getPlayer()
    local modData = player and player:getModData()
    local saved = modData and modData[PANEL_STATE_KEY]
    if type(saved) == "table" then
        local minW, minH = math.min(MIN_W, screenW), math.min(MIN_H, screenH)
        width = clamp(tonumber(saved.w) or width, minW, screenW)
        height = clamp(tonumber(saved.h) or height, minH, screenH)
        x = clamp(tonumber(saved.x) or x, 0, math.max(0, screenW-width))
        y = clamp(tonumber(saved.y) or y, 0, math.max(0, screenH-height))
    end
    local window = LasciviousShopWindow:new(x, y, width, height)
    if type(saved) == "table" and VALID_SORT_MODES[saved.sort] then
        window.sortMode = saved.sort
    end
    window:initialise()
    window:instantiate()
    window:addToUIManager()
    LasciviousShopWindow.instance = window
    return window
end

function LasciviousShopWindow.open()
    local window = ensureWindow()
    window:constrainToScreen()
    window:setVisible(true)
    window:bringToTop()
    window.lastStateRequest = getTimestamp and getTimestamp() or 0
    -- Baseline for checkAttackedClose(): whatever getAttackedBy() already
    -- reads as RIGHT NOW, not nil -- otherwise reopening the shop moments
    -- after a fight (before the engine clears/replaces that field) would
    -- instantly slam it shut again. Only a hit that happens AFTER this
    -- point counts as new.
    window._lastAttacker = nil
    pcall(function()
        local player = getPlayer()
        if player then window._lastAttacker = player:getAttackedBy() end
    end)
    Client.requestState()
    UI.playSound(UI.SOUND.open)
    return window
end

function LasciviousShopWindow.toggle()
    local instance = LasciviousShopWindow.instance
    if instance and instance.javaObject and not instance.removed and instance:isVisible() then
        instance:close()
        return
    end
    LasciviousShopWindow.open()
end

-- OnPlayerDeath only ever fires for the local player (confirmed usage
-- elsewhere in this mod: Aegis's own death-report hook relies on the same
-- guarantee), so no username/ownership check is needed here -- unlike
-- checkAttackedClose, which polls every frame, death is a one-shot event
-- the engine already tells us about directly.
local function closeOnPlayerDeath()
    local instance = LasciviousShopWindow.instance
    if instance and instance.javaObject and not instance.removed and instance:isVisible() then
        instance:close()
    end
end

LasciviousShopWindow._playerDeathHandler = closeOnPlayerDeath
Events.OnPlayerDeath.Add(closeOnPlayerDeath)
