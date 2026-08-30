-- Lascivious Factions System - on-screen HUD ticker (client side).
--
-- A small persistent strip at the top-centre of the screen that surfaces the two
-- things a player cares about mid-match without opening the panel: their leaderboard
-- standing this season, and any war they're in with its live score. Display-only
-- (not clickable -- the HUD emblem / J key already open the panel). Attaches directly
-- to the UIManager like ISHotbar/ISChat, and reads the replicated registry each frame
-- in prerender() (cheap, the same pattern the HUD emblem uses for its raid tint).
-- Gated by ShowHudTicker; renders nothing when the player is factionless or has
-- neither a season nor a war to show.

require "LFS_Shared"
require "LFS_UI"
require "LFS_Localization"

local FF = LasciviousFactionsSystem
local UI = FF.UI

local TICKER_WIDTH = 300

-- This faction's rank on the (season-adjusted) leaderboard: 1 + how many factions
-- currently out-score it. Cheap -- one pass over the registry.
local function leaderboardRank(name, opts)
    local data = FF.getData()
    local seasonMode = opts.seasonsEnabled
    local mine = 0
    local scores = {}
    for fn, f in pairs(data.factions or {}) do
        local sc = seasonMode and FF.seasonScore(f, opts, fn) or FF.factionScore(f, opts, fn)
        scores[fn] = sc
        if fn == name then mine = sc end
    end
    local rank = 1
    for fn, sc in pairs(scores) do
        if fn ~= name and sc > mine then rank = rank + 1 end
    end
    return rank
end

-- Build the ordered list of { text, color } chips to show this frame (or empty).
local function tickerLines(name, opts)
    local lines = {}
    local data = FF.getData()
    if opts.leaderboardEnabled and opts.seasonsEnabled then
        local season = data.season or {}
        lines[#lines + 1] = { text = FF.text("UI_LFS_TickerSeason", "Season %d   #%d",
            season.number or 1, leaderboardRank(name, opts)), color = UI.factionColor(name) }
    end
    if opts.warsEnabled then
        local wars = {}
        for _, war in pairs(data.wars or {}) do
            if war.a == name or war.b == name then wars[#wars + 1] = war end
        end
        table.sort(wars, function(a, b) return (a.a .. a.b) < (b.a .. b.b) end)
        for _, war in ipairs(wars) do
            local opp = (war.a == name) and war.b or war.a
            local mine = (war.score and war.score[name]) or 0
            local theirs = (war.score and war.score[opp]) or 0
            lines[#lines + 1] = { text = FF.text("UI_LFS_TickerWar",
                "WAR vs %s   %d - %d", opp, mine, theirs),
                color = UI.color.bad }
        end
    end
    return lines
end

local FFTicker = ISPanel:derive("FFTicker")

function FFTicker:new(x, y, width, height)
    local o = ISPanel:new(x, y, width, height)
    setmetatable(o, self); self.__index = self
    o.background = false
    o.moveWithMouse = false
    o.lines = {}
    return o
end

-- Click-through: a display-only overlay must never eat clicks meant for whatever is
-- under it. Returning false leaves the event unconsumed so it falls through.
function FFTicker:onMouseDown() return false end
function FFTicker:onMouseUp() return false end
function FFTicker:onRightMouseDown() return false end
function FFTicker:onRightMouseUp() return false end
function FFTicker:onMouseWheel() return false end

-- Decide visibility + size once per frame (runs even while hidden, unlike prerender),
-- so an empty ticker occupies no clickable area and the strip hugs its content.
-- How often the strip's CONTENT is recomputed. Visibility and centring below still
-- settle every frame; only the registry read is throttled.
--
-- This matters more than it looks: update() runs every frame for the whole session
-- (see the note above), and tickerLines -> leaderboardRank scores every faction on the
-- server. Recomputing that at framerate cost is wasted work on every client even with
-- no UI open. The strip shows a season rank and a war score -- 1 Hz is plenty.
local CONTENT_INTERVAL = 1

function FFTicker:update()
    local opts = FF.getOptions()
    local player = getPlayer()
    -- Server master switch AND this client's per-player toggle (Options > Mods). The
    -- resolver lives in the Panel file (loaded first); fall back to the server switch if
    -- it isn't available for any reason.
    local show = FF.showHudTickerClient and FF.showHudTickerClient() or opts.showHudTicker
    -- Resolved BEFORE any scoring work, so a player with the ticker off or no faction
    -- pays nothing at all.
    local name = (show and player) and FF.getFactionOfPlayer(player:getUsername()) or nil
    if not name then
        self.lines = {}
    else
        local now = getTimestamp and getTimestamp() or nil
        if (not now) or (not self.linesAt) or (now - self.linesAt) >= CONTENT_INTERVAL
            or self.linesFor ~= name then
            self.lines = tickerLines(name, opts)
            self.linesAt, self.linesFor = now, name
        end
    end
    if #self.lines == 0 then
        if self:isVisible() then self:setVisible(false) end
        return
    end
    local h = #self.lines * (UI.fh(UI.font.small) + 4) + 10
    self:setHeight(h)
    self:setX(math.floor((getCore():getScreenWidth() - self:getWidth()) / 2))  -- stay centred on resize
    if not self:isVisible() then self:setVisible(true) end
end

function FFTicker:prerender()
    if #self.lines == 0 then return end
    local font = UI.font.small
    local lineH = UI.fh(font) + 4
    local w, h = self:getWidth(), self:getHeight()
    UI.roundRect(self, 0, 0, w, h, 6, 0.55, UI.color.bg or UI.color.titlebar)
    UI.roundRect(self, 0, 0, w, h, 6, 0.18, UI.color.border)
    local cy = 5
    for _, ln in ipairs(self.lines) do
        local c = ln.color or UI.color.text
        local tw = UI.tw(font, ln.text)
        self:drawText(ln.text, math.floor((w - tw) / 2), cy, c.r, c.g, c.b, 1.0, font)
        cy = cy + lineH
    end
end

function FFTicker:render() end

-- Attach directly to the UIManager (like the HUD emblem). Created at game start;
-- prerender no-ops until the player and a faction exist, so this is MP-safe.
local function createFactionTicker()
    if FF._ticker then
        pcall(function()
            FF._ticker:setVisible(false)
            FF._ticker:removeFromUIManager()
        end)
        FF._ticker = nil
    end
    local x = math.floor((getCore():getScreenWidth() - TICKER_WIDTH) / 2)
    local ticker = FFTicker:new(x, 6, TICKER_WIDTH, 80)
    ticker:initialise()
    ticker:instantiate()
    ticker:setVisible(true)
    ticker:addToUIManager()
    FF._ticker = ticker
end
if FF._tickerGameStartHook then Events.OnGameStart.Remove(FF._tickerGameStartHook) end
FF._tickerGameStartHook = createFactionTicker
Events.OnGameStart.Add(createFactionTicker)
