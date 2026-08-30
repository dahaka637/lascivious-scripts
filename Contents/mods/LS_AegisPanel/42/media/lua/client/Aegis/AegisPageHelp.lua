-- Page help: a compact card under the header question mark with a few
-- hints for the page currently open. Texts live in AegisHelpContent
-- (pagehelp block per mode), the full manual stays one click away
require "ISUI/ISPanel"
require "Aegis/AegisTheme"
require "Aegis/AegisWidgets"
require "Aegis/AegisPlayerCore"
require "Aegis/AegisHelpContent"
require "Aegis/AegisHelp"

AegisPageHelp = ISPanel:derive("AegisPageHelp")

local CARD_W = 330
local CARD_Y = 52
local MARGIN_R = 14
local PAD_X = 16
local TOP = 12
local STRIPE_W = 3
local BTN_H = 28
local ENTRY_GAP = 6
-- ceiling so a runaway entry cannot grow the card past the window
local MAX_ROWS = 14

-- nav label of the page def, the fallback title when no entry exists
local function pageTitle(win, id)
    if id and win.pages then
        for _, def in ipairs(win.pages) do
            if def.id == id then return getText(def.label) end
        end
    end
    return getText("UI_Aegis_Help")
end

function AegisPageHelp.toggle(win, mode)
    if not win then return end
    if win.pageHelpCard then
        win.pageHelpCard:close()
        return
    end
    mode = mode == "player" and "player" or "admin"
    local o = ISPanel:new(0, CARD_Y, CARD_W, 120)
    setmetatable(o, AegisPageHelp)
    AegisPageHelp.__index = AegisPageHelp
    o.background = false
    o.win = win
    o.mode = mode
    o.accent = mode == "player" and AegisPlayerCol.accent or Aegis.col.gold
    o.title = ""
    o.rows = {}
    o:initialise()
    win:addChild(o)
    win.pageHelpCard = o
    o:fill()
    -- restack above the page panel outside the mouse dispatch
    o.raiseWanted = true
end

function AegisPageHelp:createChildren()
    local bw = math.floor((CARD_W - PAD_X * 2 - 8) / 2)
    self.manualBtn = AegisButton:new(PAD_X, 0, bw, BTN_H, getText("UI_Aegis_PageHelpManual"), nil, self, function(card)
        local mode = card.mode
        card:close()
        AegisHelp.toggle(mode)
    end)
    self:addChild(self.manualBtn)
    self.closeBtn = AegisButton:new(PAD_X + bw + 8, 0, bw, BTN_H, getText("UI_Aegis_Close"), nil, self, AegisPageHelp.close)
    self:addChild(self.closeBtn)
end

-- title, wrapped rows and height for the page currently open
function AegisPageHelp:fill()
    local win = self.win
    self.pageId = win.activePage
    local entry = nil
    local content = AegisHelpContent.get(self.mode)
    local block = content and content.pagehelp
    if block and self.pageId then entry = block[self.pageId] end

    local innerW = CARD_W - PAD_X * 2
    self.title = Aegis.fitText((entry and entry.title) or pageTitle(win, self.pageId), UIFont.Medium, innerW)
    self.rows = {}
    if entry and entry.lines then
        for i, line in ipairs(entry.lines) do
            local wrapped = Aegis.wrapText(line, UIFont.Small, innerW, 6)
            for k, s in ipairs(wrapped) do
                if #self.rows >= MAX_ROWS then break end
                table.insert(self.rows, { text = s, gap = (i > 1 and k == 1) })
            end
            if #self.rows >= MAX_ROWS then break end
        end
    end

    local lineH = Aegis.fontH(UIFont.Small)
    local y = TOP + Aegis.fontH(UIFont.Medium) + 8
    for _, row in ipairs(self.rows) do
        if row.gap then y = y + ENTRY_GAP end
        row.y = y
        y = y + lineH
    end
    y = y + 12
    if self.manualBtn then self.manualBtn:setY(y) end
    if self.closeBtn then self.closeBtn:setY(y) end
    self:setHeight(y + BTN_H + 12)
end

function AegisPageHelp:close()
    local win = self.win
    if win then
        win.pageHelpCard = nil
        win:removeChild(self)
    end
end

function AegisPageHelp:prerender()
    local win = self.win
    -- page switched while the card is open: refresh in place
    if win.activePage ~= self.pageId then
        self:fill()
        self.raiseWanted = true
    end
    self:setX(win.width - CARD_W - MARGIN_R)
    local w, h = self.width, self.height
    Aegis.shadow(self, 0, 0, w, h, 16, 0.6)
    Aegis.roundFrame(self, 0, 0, w, h, 10, 1, Aegis.col.line, Aegis.col.bg)
    local ac = self.accent
    self:drawRect(1, 8, STRIPE_W, h - 16, 1, ac.r, ac.g, ac.b)
    Aegis.text(self, self.title, PAD_X, TOP, UIFont.Medium, Aegis.col.text)
    for _, row in ipairs(self.rows) do
        Aegis.text(self, row.text, PAD_X, row.y, UIFont.Small, Aegis.col.muted)
    end
end

function AegisPageHelp:update()
    ISPanel.update(self)
    local win = self.win
    if not win then return end
    if win.rebuildWanted then
        -- a rebuild replaces the page children, restack once it settled
        self.raiseWanted = true
    elseif self.raiseWanted then
        self.raiseWanted = nil
        win:removeChild(self)
        win:addChild(self)
        -- the grip stays last so the corner keeps its mouse priority
        if win.grip then
            win:removeChild(win.grip)
            win:addChild(win.grip)
        end
    end
end
